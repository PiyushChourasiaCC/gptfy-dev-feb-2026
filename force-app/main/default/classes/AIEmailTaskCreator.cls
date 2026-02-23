/**
 * EmailTaskCreator - Creates Task records from email data using Shared Activities pattern
 *
 * This class creates Tasks with TaskSubtype='Email' and TaskRelation records to link
 * emails to multiple Contacts/Leads. This approach provides better visibility compared
 * to EmailMessage when emails are CC'd to multiple Salesforce users.
 *
 * Key Features:
 * - Uses standard Task.Description (32KB) for plain text email body
 * - Includes To/CC headers in Description for context
 * - Only 1 custom field: Workspace_Sync_Id__c (dedup)
 * - Creates TaskRelation for each matched Contact/Lead
 * - Supports bulk operations with proper error handling
 */
public with sharing class AIEmailTaskCreator {

    /**
     * Result wrapper for email import operations
     */
    public class EmailImportResult {
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failedCount { get; set; }
        @AuraEnabled public Integer duplicateCount { get; set; }
        @AuraEnabled public List<String> errors { get; set; }
        @AuraEnabled public List<Id> taskIds { get; set; }

        public EmailImportResult() {
            this.successCount = 0;
            this.failedCount = 0;
            this.duplicateCount = 0;
            this.errors = new List<String>();
            this.taskIds = new List<Id>();
        }
    }

    /**
     * Creates Task records from email data with match results
     * Tasks will be owned by the current running user
     *
     * @param emailDataList List of email data maps from provider API
     * @param matchResults List of AIQuickMatchService.MatchResult aligned with emailDataList
     * @param providerType The email provider type (MICROSOFT_GRAPH or GMAIL)
     * @param userEmail The syncing user's email address for sent/received detection
     * @return EmailImportResult with success/failure counts and created Task IDs
     */
    public static EmailImportResult createEmailTasks(
        List<Map<String, Object>> emailDataList,
        List<AIQuickMatchService.MatchResult> matchResults,
        String providerType,
        String userEmail
    ) {
        // Default to current user as owner (for manual imports)
        return createEmailTasks(emailDataList, matchResults, providerType, userEmail, null);
    }
    
    /**
     * Creates Task records from email data with match results and explicit owner
     * Use this overload for scheduled syncs where records should belong to workspace user
     *
     * @param emailDataList List of email data maps from provider API
     * @param matchResults List of AIQuickMatchService.MatchResult aligned with emailDataList
     * @param providerType The email provider type (MICROSOFT_GRAPH or GMAIL)
     * @param userEmail The syncing user's email address for sent/received detection
     * @param ownerId The Salesforce User ID who should own the Task records (null = current user)
     * @return EmailImportResult with success/failure counts and created Task IDs
     */
    public static EmailImportResult createEmailTasks(
        List<Map<String, Object>> emailDataList,
        List<AIQuickMatchService.MatchResult> matchResults,
        String providerType,
        String userEmail,
        Id ownerId
    ) {
        EmailImportResult result = new EmailImportResult();

        // Validate inputs
        if (emailDataList == null || matchResults == null || emailDataList.size() != matchResults.size()) {
            result.errors.add('Invalid input data or size mismatch');
            result.failedCount = emailDataList != null ? emailDataList.size() : 0;
            return result;
        }

        // Check CRUD permissions
        if (!Schema.sObjectType.Task.isCreateable()) {
            result.errors.add('Insufficient permissions to create Task records');
            result.failedCount = emailDataList.size();
            return result;
        }

        // Bulk deduplication: collect message IDs
        Set<String> messageIds = new Set<String>();
        for (Map<String, Object> emailData : emailDataList) {
            String msgId = (String) emailData.get('internetMessageId');
            if (String.isNotBlank(msgId)) {
                messageIds.add(msgId);
            }
        }

        // Query existing Tasks with these message IDs for deduplication
        // Note: Class uses 'with sharing' for record-level security
        Set<String> existingMessageIds = new Set<String>();
        if (!messageIds.isEmpty()) {
            for (Task t : [
                SELECT Workspace_Sync_Id__c
                FROM Task
                WHERE Workspace_Sync_Id__c IN :messageIds
            ]) {
                if (String.isNotBlank(t.Workspace_Sync_Id__c)) {
                    existingMessageIds.add(t.Workspace_Sync_Id__c);
                }
            }
        }

        // Prepare Tasks and track relation data
        List<Task> tasksToInsert = new List<Task>();
        Map<Integer, List<Id>> taskIndexToRelationIds = new Map<Integer, List<Id>>();
        Map<Integer, Id> taskIndexToAccountId = new Map<Integer, Id>();

        for (Integer i = 0; i < emailDataList.size(); i++) {
            Map<String, Object> emailData = emailDataList[i];
            AIQuickMatchService.MatchResult match = matchResults[i];

            try {
                String msgId = (String) emailData.get('internetMessageId');

                // Skip duplicates
                if (String.isNotBlank(msgId) && existingMessageIds.contains(msgId)) {
                    result.duplicateCount++;
                    continue;
                }

                // Create Task record
                Task t = mapEmailToTask(emailData, providerType, userEmail);
                
                // Set owner if specified (for scheduled syncs)
                // This ensures the Task belongs to the workspace user, not the scheduler runner
                if (ownerId != null) {
                    t.OwnerId = ownerId;
                }

                // Determine if this is a Lead-only match or Contact match
                // Lead matched by email should NOT link to Account (website match)
                // Contact matched by email CAN link to Account (Contact belongs to Account)
                Boolean hasContact = (match.contactIds != null && !match.contactIds.isEmpty()) || match.contactId != null;
                Boolean hasLead = match.leadId != null;

                // Collect Contact/Lead IDs for TaskRelation
                List<Id> relationIds = new List<Id>();

                if (hasContact) {
                    // Contact match: Link to Contact(s) + Account/Opportunity
                    // Contact belongs to Account, so this relationship is valid
                    if (match.contactIds != null && !match.contactIds.isEmpty()) {
                        relationIds.addAll(match.contactIds);
                    } else if (match.contactId != null) {
                        relationIds.add(match.contactId);
                    }
                    // Note: If both Contact AND Lead have same email, prioritize Contact
                    // (Lead should be converted if Contact exists with same email)

                    // Set WhatId for Contact match - Account/Opportunity/Case
                    if (match.opportunityId != null) {
                        t.WhatId = match.opportunityId;
                    } else if (match.caseId != null) {
                        t.WhatId = match.caseId;
                    } else if (match.accountId != null) {
                        t.WhatId = match.accountId;
                    }
                } else if (hasLead) {
                    // Lead-only match: Link to Lead ONLY
                    // Do NOT set WhatId to Account (website match) because:
                    // 1. Lead is standalone, not linked to Account
                    // 2. TaskRelation to Lead fails when WhatId = Account
                    relationIds.add(match.leadId);
                    // WhatId remains null - Task will show on Lead only
                } else {
                    // No Contact or Lead match - only Account/Opportunity/Case match
                    // Set WhatId for non-person matches
                    if (match.opportunityId != null) {
                        t.WhatId = match.opportunityId;
                    } else if (match.caseId != null) {
                        t.WhatId = match.caseId;
                    } else if (match.accountId != null) {
                        t.WhatId = match.accountId;
                    }
                }

                tasksToInsert.add(t);

                if (!relationIds.isEmpty()) {
                    taskIndexToRelationIds.put(tasksToInsert.size() - 1, relationIds);
                }

            } catch (Exception e) {
                result.errors.add('Error processing email: ' + e.getMessage());
                result.failedCount++;
            }
        }

        // Insert Tasks and create TaskRelations
        if (!tasksToInsert.isEmpty()) {
            insertTasksWithRelations(tasksToInsert, taskIndexToRelationIds, result);
        }

        return result;
    }

    /**
     * Maps email data to a Task sObject
     */
    private static Task mapEmailToTask(
        Map<String, Object> emailData,
        String providerType,
        String userEmail
    ) {
        Task t = new Task();

        // Email-specific TaskSubtype
        t.TaskSubtype = 'Email';

        // Subject
        String subject = (String) emailData.get('subject');
        t.Subject = String.isNotBlank(subject) ? AIExchangeEmailHelper.truncateField(subject, 255) : '(No Subject)';

        // Build Description with headers + body
        t.Description = buildDescription(emailData);

        // Email identifier for deduplication
        t.Workspace_Sync_Id__c = (String) emailData.get('internetMessageId');
        
        // Note: Email_From__c field removed - from address stored in Description header

        // Activity date
        String receivedDateStr = (String) emailData.get('receivedDateTime');
        if (String.isNotBlank(receivedDateStr)) {
            DateTime receivedDt = parseDateTime(receivedDateStr);
            if (receivedDt != null) {
                t.ActivityDate = receivedDt.date();
            }
        }
        if (t.ActivityDate == null) {
            t.ActivityDate = Date.today();
        }

        // Status - mark as completed since email already happened
        t.Status = 'Completed';

        // Priority
        String importance = (String) emailData.get('importance');
        if (importance == 'high') {
            t.Priority = 'High';
        } else {
            t.Priority = 'Normal';
        }

        return t;
    }

    /**
     * Builds the Task Description with To/CC headers and plain text body
     * Format:
     * To: email1@example.com, email2@example.com
     * CC: email3@example.com
     * ---
     * Plain text email body...
     */
    private static String buildDescription(Map<String, Object> emailData) {
        List<String> parts = new List<String>();

        // To recipients
        String toAddresses = buildRecipientString((List<Object>) emailData.get('toRecipients'));
        if (String.isNotBlank(toAddresses)) {
            parts.add('To: ' + toAddresses);
        }

        // CC recipients
        String ccAddresses = buildRecipientString((List<Object>) emailData.get('ccRecipients'));
        if (String.isNotBlank(ccAddresses)) {
            parts.add('CC: ' + ccAddresses);
        }

        // Separator
        if (!parts.isEmpty()) {
            parts.add('---');
        }

        // Email body (plain text)
        Map<String, Object> body = (Map<String, Object>) emailData.get('body');
        if (body != null) {
            String contentType = (String) body.get('contentType');
            String content = (String) body.get('content');

            if (String.isNotBlank(content)) {
                String plainText;
                if (contentType == 'html') {
                    plainText = stripHtml(content);
                } else {
                    plainText = content;
                }
                parts.add(plainText);
            }
        }

        String description = String.join(parts, '\n');

        // Task Description limit is 32,000 characters
        return AIExchangeEmailHelper.truncateField(description, 32000);
    }

    /**
     * Builds comma-separated recipient string from email address objects
     */
    private static String buildRecipientString(List<Object> recipients) {
        if (recipients == null || recipients.isEmpty()) {
            return null;
        }

        List<String> addresses = new List<String>();
        for (Object recipientObj : recipients) {
            Map<String, Object> recipient = (Map<String, Object>) recipientObj;
            Map<String, Object> emailAddress = (Map<String, Object>) recipient.get('emailAddress');
            if (emailAddress != null) {
                String addr = (String) emailAddress.get('address');
                if (String.isNotBlank(addr)) {
                    addresses.add(addr);
                }
            }
        }

        return addresses.isEmpty() ? null : String.join(addresses, ', ');
    }

    /**
     * Inserts Tasks and creates corresponding TaskRelation records (if Shared Activities enabled)
     * Falls back to WhoId for single Contact/Lead if TaskRelation is not available
     */
    private static void insertTasksWithRelations(
        List<Task> tasks,
        Map<Integer, List<Id>> taskIndexToRelationIds,
        EmailImportResult result
    ) {
        // Check if Shared Activities (TaskRelation) is available
        Boolean sharedActivitiesEnabled = isSharedActivitiesEnabled();

        // If Shared Activities NOT enabled, set WhoId directly on Tasks before insert
        if (!sharedActivitiesEnabled) {
            for (Integer i = 0; i < tasks.size(); i++) {
                if (taskIndexToRelationIds.containsKey(i)) {
                    List<Id> relationIds = taskIndexToRelationIds.get(i);
                    if (!relationIds.isEmpty()) {
                        // Use first Contact/Lead as WhoId (standard limitation)
                        tasks[i].WhoId = relationIds[0];
                    }
                }
            }
        }

        // Insert Tasks
        Database.SaveResult[] taskResults = Database.insert(tasks, false);

        // Track successful task IDs for TaskRelation creation
        Map<Id, List<Id>> taskIdToRelationIds = new Map<Id, List<Id>>();

        for (Integer i = 0; i < taskResults.size(); i++) {
            if (taskResults[i].isSuccess()) {
                result.successCount++;
                Id taskId = taskResults[i].getId();
                result.taskIds.add(taskId);

                // Collect relations for Shared Activities
                if (sharedActivitiesEnabled && taskIndexToRelationIds.containsKey(i)) {
                    taskIdToRelationIds.put(taskId, taskIndexToRelationIds.get(i));
                }
            } else {
                result.failedCount++;
                for (Database.Error err : taskResults[i].getErrors()) {
                    result.errors.add(tasks[i].Subject + ': ' + err.getMessage());
                }
            }
        }

        // Create TaskRelations if Shared Activities is enabled
        if (sharedActivitiesEnabled && !taskIdToRelationIds.isEmpty()) {
            createTaskRelations(taskIdToRelationIds);
        }
    }

    /**
     * Check if Shared Activities (TaskRelation) is enabled in the org
     */
    private static Boolean isSharedActivitiesEnabled() {
        return Schema.getGlobalDescribe().containsKey('TaskRelation');
    }

    /**
     * Creates TaskRelation records for multi-contact relationships
     * Only called when Shared Activities is enabled
     */
    private static void createTaskRelations(Map<Id, List<Id>> taskIdToRelationIds) {
        List<SObject> relationsToInsert = new List<SObject>();
        Schema.SObjectType taskRelationType = Schema.getGlobalDescribe().get('TaskRelation');

        if (taskRelationType == null) {
            return; // Safety check
        }

        for (Id taskId : taskIdToRelationIds.keySet()) {
            for (Id relationId : taskIdToRelationIds.get(taskId)) {
                SObject tr = taskRelationType.newSObject();
                tr.put('TaskId', taskId);
                tr.put('RelationId', relationId);
                tr.put('IsWhat', false); // Contact/Lead goes in Who, not What
                relationsToInsert.add(tr);
            }
        }

        if (!relationsToInsert.isEmpty()) {
            Database.SaveResult[] relationResults = Database.insert(relationsToInsert, false);
            for (Integer i = 0; i < relationResults.size(); i++) {
                if (!relationResults[i].isSuccess()) {
                    for (Database.Error err : relationResults[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Error creating TaskRelation: ' + err.getMessage());
                    }
                }
            }
        }
    }

    /**
     * Strips HTML tags and converts to plain text
     * NO REGEX - uses Salesforce built-in stripHtmlTags() method
     */
    private static String stripHtml(String html) {
        if (String.isBlank(html)) {
            return '';
        }

        // Use Salesforce built-in method - no regex
        String text = html.stripHtmlTags();

        // Decode common HTML entities using simple replace() - no regex
        text = text.replace('&nbsp;', ' ');
        text = text.replace('&amp;', '&');
        text = text.replace('&lt;', '<');
        text = text.replace('&gt;', '>');
        text = text.replace('&quot;', '"');
        text = text.replace('&#39;', '\'');

        return text.trim();
    }

    /**
     * Parses ISO 8601 datetime string to DateTime
     */
    private static DateTime parseDateTime(String isoString) {
        if (String.isBlank(isoString)) {
            return null;
        }
        try {
            // Handle ISO 8601 format: 2024-01-15T10:30:00Z
            String cleaned = isoString.replace('T', ' ').replace('Z', '');
            if (cleaned.length() > 19) {
                cleaned = cleaned.substring(0, 19);
            }
            return DateTime.valueOfGmt(cleaned);
        } catch (Exception e) {
            System.debug('Failed to parse datetime: ' + isoString + ' - ' + e.getMessage());
            return null;
        }
    }
}