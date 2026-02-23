/**
 * Service class for creating AI Workspace Staging records
 * Handles staging of emails, calendar events, and tasks from external providers
 * 
 * This replaces direct creation of EmailMessage/Event/Task records,
 * allowing users to manually link staged items to Salesforce records later.
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIWorkspaceStagingCreator {

    // Record Type Developer Names
    private static final String RT_EMAIL = 'Email';
    private static final String RT_CALENDAR = 'Calendar';
    private static final String RT_TASK = 'Task';

    // Cache for record type IDs
    private static Map<String, Id> recordTypeIdCache;
    
    /**
     * Clear the record type cache (for testing)
     */
    @TestVisible
    private static void clearRecordTypeCache() {
        recordTypeIdCache = null;
    }

    /**
     * Result wrapper for staging operations
     * 
     * Count definitions:
     * - successCount: Staging records created successfully
     * - failedCount: Staging records that failed to create
     * - duplicateCount: Skipped because already synced
     * - matchedCount: Staging records that matched to Lead/Contact (EmailMessage/Event/Task created)
     * - unmatchedCount: Staging records that didn't match any Lead/Contact
     * - importedCount: Actual Salesforce records created (EmailMessage, Event, or Task)
     * - rematchedCount: Previously unmatched records that were re-matched
     */
    public class StagingResult {
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failedCount { get; set; }
        @AuraEnabled public Integer duplicateCount { get; set; }
        @AuraEnabled public Integer matchedCount { get; set; }
        @AuraEnabled public Integer unmatchedCount { get; set; }
        @AuraEnabled public Integer importedCount { get; set; }
        @AuraEnabled public Integer rematchedCount { get; set; }
        @AuraEnabled public List<String> errors { get; set; }
        @AuraEnabled public List<Id> stagingRecordIds { get; set; }

        public StagingResult() {
            this.successCount = 0;
            this.failedCount = 0;
            this.duplicateCount = 0;
            this.matchedCount = 0;
            this.unmatchedCount = 0;
            this.importedCount = 0;
            this.rematchedCount = 0;
            this.errors = new List<String>();
            this.stagingRecordIds = new List<Id>();
        }
    }

    /**
     * Get record type ID by developer name
     */
    private static Id getRecordTypeId(String developerName) {
        if (recordTypeIdCache == null) {
            recordTypeIdCache = new Map<String, Id>();
            // Use Schema describe to get record type IDs - more reliable than SOQL
            Map<String, Schema.RecordTypeInfo> rtInfos = 
                Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName();
            for (String rtName : rtInfos.keySet()) {
                Schema.RecordTypeInfo rtInfo = rtInfos.get(rtName);
                if (rtInfo.isActive()) {
                    recordTypeIdCache.put(rtName, rtInfo.getRecordTypeId());
                }
            }
        }
        return recordTypeIdCache.get(developerName);
    }

    /**
     * Creates staging records for emails
     * @param emails List of email data maps from Graph API
     * @param providerType Provider type (MICROSOFT_EMAIL or GMAIL_EMAIL)
     * @param userEmail User's email address for sent/received detection
     * @param syncLogId Optional sync log ID to link records
     * @return StagingResult with success/failure counts
     */
    public static StagingResult createEmailStagingRecords(
        List<Map<String, Object>> emails,
        String providerType,
        String userEmail,
        Id syncLogId
    ) {
        // Default to current user if no target user specified, and send notifications (for manual imports)
        return createEmailStagingRecords(emails, providerType, userEmail, syncLogId, null, true);
    }
    
    /**
     * Create email staging records with target user ID (for scheduled syncs)
     * @param emails List of email data maps
     * @param providerType Provider type (MICROSOFT_EMAIL or GMAIL_EMAIL)
     * @param userEmail User's email address for sent/received detection
     * @param syncLogId Optional sync log ID to link records
     * @param targetUserId The user ID who should own the records (null = current user)
     * @param sendNotifications Whether to send bell notifications (true for manual, false for auto-sync)
     * @return StagingResult with success/failure counts
     */
    public static StagingResult createEmailStagingRecords(
        List<Map<String, Object>> emails,
        String providerType,
        String userEmail,
        Id syncLogId,
        Id targetUserId,
        Boolean sendNotifications
    ) {
        // Use target user if provided, otherwise default to current user
        Id effectiveUserId = targetUserId != null ? targetUserId : UserInfo.getUserId();
        StagingResult result = new StagingResult();

        if (emails == null || emails.isEmpty()) {
            return result;
        }

        // Check CRUD permissions
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            result.errors.add('Insufficient permissions to create AI Workspace Staging records');
            result.failedCount = emails.size();
            return result;
        }

        Id emailRecordTypeId = getRecordTypeId(RT_EMAIL);
        if (emailRecordTypeId == null) {
            result.errors.add('Email record type not found on AI_Workspace_Staging__c');
            result.failedCount = emails.size();
            return result;
        }

        // Collect provider IDs and message identifiers for deduplication
        Set<String> providerIds = new Set<String>();
        Set<String> messageIdentifiers = new Set<String>();
        for (Map<String, Object> emailData : emails) {
            String providerId = (String) emailData.get('id');
            String messageId = (String) emailData.get('internetMessageId');
            if (String.isNotBlank(providerId)) {
                providerIds.add(providerId);
            }
            if (String.isNotBlank(messageId)) {
                messageIdentifiers.add(messageId);
            }
        }

        // Query existing staging records - get full records to check status
        // Check by Provider_Id__c (for staging deduplication) and Message_Identifier__c
        Map<String, AI_Workspace_Staging__c> existingStagingByProviderId = new Map<String, AI_Workspace_Staging__c>();
        Map<String, AI_Workspace_Staging__c> existingStagingByMessageId = new Map<String, AI_Workspace_Staging__c>();
        List<Id> existingUnmatchedIds = new List<Id>();
        
        if (!providerIds.isEmpty() || !messageIdentifiers.isEmpty()) {
            for (AI_Workspace_Staging__c existing : [
                SELECT Id, Provider_Id__c, Message_Identifier__c, Status__c 
                FROM AI_Workspace_Staging__c 
                WHERE (Provider_Id__c IN :providerIds OR Message_Identifier__c IN :messageIdentifiers)
                AND RecordTypeId = :emailRecordTypeId
                WITH USER_MODE
            ]) {
                if (String.isNotBlank(existing.Provider_Id__c)) {
                    existingStagingByProviderId.put(existing.Provider_Id__c, existing);
                }
                if (String.isNotBlank(existing.Message_Identifier__c)) {
                    existingStagingByMessageId.put(existing.Message_Identifier__c, existing);
                }
                
                // Collect unmatched records for re-matching
                if (existing.Status__c == 'Unmatched') {
                    existingUnmatchedIds.add(existing.Id);
                }
            }
        }
        
        // ALSO check for existing EmailMessage records with the same MessageIdentifier
        // This ensures deduplication works even after Staging records are deleted
        // Uses the standard MessageIdentifier field (RFC 2822 Message-ID)
        Set<String> existingEmailMessageIdentifiers = new Set<String>();
        if (!messageIdentifiers.isEmpty()) {
            existingEmailMessageIdentifiers = getExistingEmailMessageIdentifiers(messageIdentifiers);
        }

        List<AI_Workspace_Staging__c> recordsToInsert = new List<AI_Workspace_Staging__c>();

        for (Map<String, Object> emailData : emails) {
            try {
                String providerId = (String) emailData.get('id');
                String messageId = (String) emailData.get('internetMessageId');

                // Check if staging record already exists (by provider ID or message ID)
                AI_Workspace_Staging__c existingStaging = null;
                if (String.isNotBlank(providerId) && existingStagingByProviderId.containsKey(providerId)) {
                    existingStaging = existingStagingByProviderId.get(providerId);
                } else if (String.isNotBlank(messageId) && existingStagingByMessageId.containsKey(messageId)) {
                    existingStaging = existingStagingByMessageId.get(messageId);
                }
                
                // If staging exists, check its status
                if (existingStaging != null) {
                    // FIXED: Existing staging records (regardless of status) are considered duplicates
                    // for COUNT purposes because they were already fetched in a prior sync.
                    // The existingUnmatchedIds list handles re-matching attempts separately,
                    // but those re-match results don't inflate the current sync's counts.
                    // This ensures: Fetched = Matched + Unmatched + Duplicate (for THIS sync only)
                    result.duplicateCount++;
                    continue;
                }
                
                // ALSO check if EmailMessage already exists with this MessageIdentifier
                // This handles the case where Staging was deleted but EmailMessage remains
                // Uses the standard MessageIdentifier field (RFC 2822 Message-ID)
                if (String.isNotBlank(messageId) && existingEmailMessageIdentifiers.contains(messageId)) {
                    result.duplicateCount++;
                    continue;
                }

                AI_Workspace_Staging__c staging = mapEmailToStaging(
                    emailData, 
                    emailRecordTypeId, 
                    providerType, 
                    userEmail, 
                    syncLogId,
                    effectiveUserId
                );
                recordsToInsert.add(staging);
            } catch (Exception e) {
                result.errors.add('Error processing email: ' + e.getMessage());
                result.failedCount++;
            }
        }

        // Bulk insert new records
        if (!recordsToInsert.isEmpty()) {
            insertStagingRecords(recordsToInsert, result);
            
            // Immediately run matching for the newly created staging records
            // Pass the connected account email (userEmail) to exclude from matching
            if (!result.stagingRecordIds.isEmpty()) {
                MatchingCounts counts = matchEmailStagingRecordsInline(result.stagingRecordIds, sendNotifications, userEmail);
                result.matchedCount += counts.matchedCount;
                result.unmatchedCount += counts.unmatchedCount;
                result.importedCount += counts.importedCount;
                // Note: Notifications are sent from within matchEmailStagingRecordsInline (if sendNotifications=true)
            }
        }
        
        // Re-run matching on existing unmatched records
        // This handles two scenarios:
        // 1. User manually re-selects a previously unmatched email
        // 2. Scheduler re-fetches an email that was unmatched in previous sync (auto-retry)
        // If a Contact/Lead/Account was added since last sync, the email will now match and import.
        // NOTE: We don't add rematching counts to the main totals because those emails
        // were NOT fetched in this sync - they were already in staging from previous syncs.
        // The unmatchedCount was already incremented above when we detected existing unmatched staging.
        if (!existingUnmatchedIds.isEmpty()) {
            MatchingCounts rematchCounts = matchEmailStagingRecordsInline(existingUnmatchedIds, sendNotifications, userEmail);
            // Track how many were rematched for informational purposes
            result.rematchedCount = existingUnmatchedIds.size();
            // IMPORTANT: Do NOT add rematchCounts to result totals
            // The unmatchedCount was already counted when we detected the existing staging record.
            // If rematching succeeds, the staging Status changes from Unmatched to Matched,
            // and the EmailMessage is created - but we don't inflate sync log totals.
        }

        return result;
    }

    /**
     * Creates staging records for calendar events
     * @param events List of calendar events
     * @param providerType Provider type (MICROSOFT_CALENDAR or GOOGLE_CALENDAR)
     * @param syncLogId Optional sync log ID to link records
     * @return StagingResult with success/failure counts
     */
    public static StagingResult createCalendarStagingRecords(
        List<AIMicrosoftCalendarService.CalendarEvent> events,
        String providerType,
        Id syncLogId
    ) {
        // Default to current user if no target user specified, and send notifications (for manual imports)
        return createCalendarStagingRecords(events, providerType, syncLogId, null, true, null);
    }
    
    /**
     * Create calendar staging records with target user ID (for scheduled syncs)
     * @param events List of calendar events
     * @param providerType Provider type (MICROSOFT_CALENDAR or GOOGLE_CALENDAR)
     * @param syncLogId Optional sync log ID to link records
     * @param targetUserId The user ID who should own the records (null = current user)
     * @param sendNotifications Whether to send bell notifications (true for manual, false for auto-sync)
     * @return StagingResult with success/failure counts
     */
    public static StagingResult createCalendarStagingRecords(
        List<AIMicrosoftCalendarService.CalendarEvent> events,
        String providerType,
        Id syncLogId,
        Id targetUserId,
        Boolean sendNotifications
    ) {
        return createCalendarStagingRecords(events, providerType, syncLogId, targetUserId, sendNotifications, null);
    }
    
    /**
     * Create calendar staging records with connected account email exclusion (V2-8XXX)
     * @param events List of calendar events
     * @param providerType Provider type (MICROSOFT_CALENDAR or GOOGLE_CALENDAR)
     * @param syncLogId Optional sync log ID to link records
     * @param targetUserId The user ID who should own the records (null = current user)
     * @param sendNotifications Whether to send bell notifications (true for manual, false for auto-sync)
     * @param connectedAccountEmail The connected account email to exclude from matching (e.g., piyush2@gptfy.dev)
     * @return StagingResult with success/failure counts
     */
    public static StagingResult createCalendarStagingRecords(
        List<AIMicrosoftCalendarService.CalendarEvent> events,
        String providerType,
        Id syncLogId,
        Id targetUserId,
        Boolean sendNotifications,
        String connectedAccountEmail
    ) {
        // Use target user if provided, otherwise default to current user
        Id effectiveUserId = targetUserId != null ? targetUserId : UserInfo.getUserId();
        StagingResult result = new StagingResult();

        if (events == null || events.isEmpty()) {
            return result;
        }

        // Check CRUD permissions
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            result.errors.add('Insufficient permissions to create AI Workspace Staging records');
            result.failedCount = events.size();
            return result;
        }

        Id calendarRecordTypeId = getRecordTypeId(RT_CALENDAR);
        if (calendarRecordTypeId == null) {
            result.errors.add('Calendar record type not found on AI_Workspace_Staging__c');
            result.failedCount = events.size();
            return result;
        }

        // Collect deduplication IDs for checking existing records
        // For Google recurring events: uses eventId (unique per instance)
        // For others: uses iCalUID
        Set<String> dedupIds = new Set<String>();
        for (AIMicrosoftCalendarService.CalendarEvent evt : events) {
            String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
            if (String.isNotBlank(dedupId)) {
                dedupIds.add(dedupId);
            }
        }

        // Query existing staging records by ICalUID__c
        // Note: Staging stores the dedup ID in ICalUID__c field for consistency
        Map<String, AI_Workspace_Staging__c> existingStagingByICalUID = new Map<String, AI_Workspace_Staging__c>();
        List<Id> existingUnmatchedCalendarIds = new List<Id>();
        if (!dedupIds.isEmpty()) {
            for (AI_Workspace_Staging__c existing : [
                SELECT Id, ICalUID__c, Status__c 
                FROM AI_Workspace_Staging__c 
                WHERE ICalUID__c IN :dedupIds
                AND RecordTypeId = :calendarRecordTypeId
                WITH USER_MODE
            ]) {
                if (String.isNotBlank(existing.ICalUID__c)) {
                    existingStagingByICalUID.put(existing.ICalUID__c, existing);
                }
                // Collect unmatched records for re-processing
                if (existing.Status__c == 'Unmatched') {
                    existingUnmatchedCalendarIds.add(existing.Id);
                }
            }
        }
        
        // ALSO check for existing Event records with the same Workspace_Sync_Id__c
        // This ensures deduplication works even after Staging records are deleted
        // IMPORTANT: Only check events owned by the effective user to prevent false duplicates
        Set<String> existingEventCalendarIds = new Set<String>();
        if (!dedupIds.isEmpty()) {
            existingEventCalendarIds = getExistingEventCalendarIds(dedupIds, effectiveUserId);
        }

        List<AI_Workspace_Staging__c> recordsToInsert = new List<AI_Workspace_Staging__c>();

        for (AIMicrosoftCalendarService.CalendarEvent evt : events) {
            try {
                // Get the deduplication ID for this event
                String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
                
                // Check if staging record already exists
                AI_Workspace_Staging__c existingStaging = null;
                if (String.isNotBlank(dedupId) && existingStagingByICalUID.containsKey(dedupId)) {
                    existingStaging = existingStagingByICalUID.get(dedupId);
                }
                
                // If staging exists, it's a duplicate for COUNT purposes
                // (already fetched in a prior sync, regardless of current status)
                if (existingStaging != null) {
                    result.duplicateCount++;
                    continue;
                }
                
                // ALSO check if Event already exists with this dedup ID
                // This handles the case where Staging was deleted but Event remains
                if (String.isNotBlank(dedupId) && existingEventCalendarIds.contains(dedupId)) {
                    result.duplicateCount++;
                    continue;
                }

                AI_Workspace_Staging__c staging = mapCalendarEventToStaging(
                    evt, 
                    calendarRecordTypeId, 
                    providerType, 
                    syncLogId,
                    effectiveUserId
                );
                recordsToInsert.add(staging);
            } catch (Exception e) {
                result.errors.add('Error processing calendar event: ' + e.getMessage());
                result.failedCount++;
            }
        }

        // Bulk insert
        if (!recordsToInsert.isEmpty()) {
            insertStagingRecords(recordsToInsert, result);
            
            // Immediately run matching for the newly created calendar staging records
            // Pass the connected account email to exclude from matching
            if (!result.stagingRecordIds.isEmpty()) {
                MatchingCounts counts = matchCalendarStagingRecordsInline(result.stagingRecordIds, connectedAccountEmail);
                result.matchedCount += counts.matchedCount;
                result.unmatchedCount += counts.unmatchedCount;
                result.importedCount += counts.importedCount;
                
                // Send notifications only for manual imports (not for auto-sync/scheduler)
                if (sendNotifications) {
                    sendCalendarStagingNotifications(result.stagingRecordIds, counts);
                }
            }
        }
        
        // Re-process existing unmatched calendar events
        // This handles the case where scheduler re-fetches an event that was unmatched in previous sync
        // If the event can now be processed (e.g., calendar settings changed), it will be imported
        // NOTE: We don't add reprocessing counts to the main totals because those events
        // were NOT fetched in this sync - they were already in staging from previous syncs.
        // The unmatchedCount was already incremented above when we detected existing unmatched staging.
        if (!existingUnmatchedCalendarIds.isEmpty()) {
            MatchingCounts reprocessCounts = matchCalendarStagingRecordsInline(existingUnmatchedCalendarIds, connectedAccountEmail);
            // Track how many were reprocessed for informational purposes
            result.rematchedCount = existingUnmatchedCalendarIds.size();
            // IMPORTANT: Do NOT add reprocessCounts to result totals
            // The unmatchedCount was already counted when we detected the existing staging record.
            // If reprocessing succeeds, the staging Status changes from Unmatched to Matched,
            // and the Event is created - but we don't inflate sync log totals.
        }

        return result;
    }

    /**
     * Creates staging records for tasks
     * @param tasks List of to-do tasks
     * @param providerType Provider type (MICROSOFT_TASKS or GOOGLE_TASKS)
     * @param syncLogId Optional sync log ID to link records
     * @return StagingResult with success/failure counts
     */
    public static StagingResult createTaskStagingRecords(
        List<AIMicrosoftTaskService.ToDoTask> tasks,
        String providerType,
        Id syncLogId
    ) {
        // Default to current user if no target user specified, and send notifications (for manual imports)
        return createTaskStagingRecords(tasks, providerType, syncLogId, null, true);
    }
    
    /**
     * Create task staging records with target user ID (for scheduled syncs)
     * @param tasks List of tasks
     * @param providerType Provider type (MICROSOFT_TASKS or GOOGLE_TASKS)
     * @param syncLogId Optional sync log ID to link records
     * @param targetUserId The user ID who should own the records (null = current user)
     * @param sendNotifications Whether to send bell notifications (true for manual, false for auto-sync)
     * @return StagingResult with success/failure counts
     */
    public static StagingResult createTaskStagingRecords(
        List<AIMicrosoftTaskService.ToDoTask> tasks,
        String providerType,
        Id syncLogId,
        Id targetUserId,
        Boolean sendNotifications
    ) {
        // Use target user if provided, otherwise default to current user
        Id effectiveUserId = targetUserId != null ? targetUserId : UserInfo.getUserId();
        StagingResult result = new StagingResult();

        if (tasks == null || tasks.isEmpty()) {
            return result;
        }

        // Check CRUD permissions
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            result.errors.add('Insufficient permissions to create AI Workspace Staging records');
            result.failedCount = tasks.size();
            return result;
        }

        Id taskRecordTypeId = getRecordTypeId(RT_TASK);
        if (taskRecordTypeId == null) {
            result.errors.add('Task record type not found on AI_Workspace_Staging__c');
            result.failedCount = tasks.size();
            return result;
        }

        // Collect task IDs for deduplication
        Set<String> taskIds = new Set<String>();
        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            if (String.isNotBlank(task.taskId)) {
                taskIds.add(task.taskId);
            }
        }

        // Query ALL existing staging records (both Matched and Unmatched)
        // FIXED (2026-02-13): Check all staging records to update Unmatched ones
        Map<String, AI_Workspace_Staging__c> existingStagingByProviderId = new Map<String, AI_Workspace_Staging__c>();
        if (!taskIds.isEmpty()) {
            for (AI_Workspace_Staging__c existing : [
                SELECT Id, Provider_Id__c, Status__c
                FROM AI_Workspace_Staging__c 
                WHERE Provider_Id__c IN :taskIds
                AND RecordTypeId = :taskRecordTypeId
                WITH USER_MODE
            ]) {
                existingStagingByProviderId.put(existing.Provider_Id__c, existing);
            }
        }
        
        // ALSO check for existing Task records with the same Workspace_Sync_Id__c
        // This ensures deduplication works even after Staging records are deleted
        // IMPORTANT: Only check tasks owned by the effective user to prevent false duplicates
        Set<String> existingTaskProviderIds = new Set<String>();
        if (!taskIds.isEmpty()) {
            existingTaskProviderIds = getExistingTaskProviderIds(taskIds, effectiveUserId);
        }

        List<AI_Workspace_Staging__c> recordsToInsert = new List<AI_Workspace_Staging__c>();
        Set<Id> existingUnmatchedStagingIdsSet = new Set<Id>(); // Use Set to avoid duplicates

        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            try {
                AI_Workspace_Staging__c existingStaging = existingStagingByProviderId.get(task.taskId);
                
                // If staging exists (any status), it's a duplicate for COUNT purposes
                // because it was already fetched in a prior sync.
                // For Unmatched staging, we still collect IDs to retry Task creation,
                // but we don't inflate the current sync's counts.
                if (existingStaging != null) {
                    result.duplicateCount++;
                    // If Unmatched, collect ID for retry (but don't count again)
                    if (existingStaging.Status__c == 'Unmatched') {
                        existingUnmatchedStagingIdsSet.add(existingStaging.Id);
                    }
                    continue;
                }
                
                // Skip if Task record exists (no staging but Task was created)
                if (String.isNotBlank(task.taskId) && existingTaskProviderIds.contains(task.taskId)) {
                    result.duplicateCount++;
                    continue;
                }

                // No existing staging - create new one
                AI_Workspace_Staging__c staging = mapTaskToStaging(
                    task, 
                    taskRecordTypeId, 
                    providerType, 
                    syncLogId,
                    effectiveUserId
                );
                recordsToInsert.add(staging);
            } catch (Exception e) {
                result.errors.add('Error processing task: ' + e.getMessage());
                result.failedCount++;
            }
        }

        // CRITICAL: Get connected email BEFORE DML to avoid "callout after DML" error
        // This callout must happen before insertStagingRecords() which performs DML
        String connectedEmail = null;
        if (!recordsToInsert.isEmpty() || !existingUnmatchedStagingIdsSet.isEmpty()) {
            connectedEmail = getConnectedUserEmail(providerType);
        }

        // Bulk insert NEW staging records (DML operation)
        if (!recordsToInsert.isEmpty()) {
            insertStagingRecords(recordsToInsert, result);
        }
        
        // Combine new staging IDs with existing Unmatched staging IDs for Task creation
        // Use Set to ensure no duplicates
        Set<Id> allStagingIdsSet = new Set<Id>();
        allStagingIdsSet.addAll(result.stagingRecordIds);
        allStagingIdsSet.addAll(existingUnmatchedStagingIdsSet);
        List<Id> allStagingIdsToProcess = new List<Id>(allStagingIdsSet);
        
        // IMPORTANT: Add existing Unmatched staging IDs to result so controller can query them
        // This ensures manual imports from modal can link the created Tasks to selected Contacts
        // Convert result.stagingRecordIds to Set first to avoid duplicates
        Set<Id> resultStagingIdsSet = new Set<Id>(result.stagingRecordIds);
        resultStagingIdsSet.addAll(existingUnmatchedStagingIdsSet);
        result.stagingRecordIds = new List<Id>(resultStagingIdsSet);
        
        // Create/retry Salesforce Task records for both new and existing Unmatched staging
        if (!allStagingIdsToProcess.isEmpty()) {
            MatchingCounts counts = createTasksFromStagingInlineWithEmail(allStagingIdsToProcess, connectedEmail, sendNotifications);
            result.matchedCount += counts.matchedCount;
            result.unmatchedCount += counts.unmatchedCount;
            result.importedCount += counts.importedCount;
        }

        return result;
    }

    /**
     * Creates staging records for Google Tasks
     * @param tasks List of Google to-do tasks
     * @param userId User ID for the staging records
     * @param providerType Provider type (GOOGLE_TASKS)
     * @param sendNotifications Whether to send bell notifications (true for manual, false for auto-sync)
     * @return StagingResult with success/failure counts
     */
    public static StagingResult createGoogleTaskStagingRecords(
        List<AIGoogleTaskService.ToDoTask> tasks,
        Id userId,
        String providerType,
        Boolean sendNotifications
    ) {
        StagingResult result = new StagingResult();

        if (tasks == null || tasks.isEmpty()) {
            return result;
        }

        // Check CRUD permissions
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            result.errors.add('Insufficient permissions to create AI Workspace Staging records');
            result.failedCount = tasks.size();
            return result;
        }

        Id taskRecordTypeId = getRecordTypeId(RT_TASK);
        if (taskRecordTypeId == null) {
            result.errors.add('Task record type not found on AI_Workspace_Staging__c');
            result.failedCount = tasks.size();
            return result;
        }

        // Collect task IDs for deduplication
        Set<String> taskIds = new Set<String>();
        for (AIGoogleTaskService.ToDoTask task : tasks) {
            if (String.isNotBlank(task.taskId)) {
                taskIds.add(task.taskId);
            }
        }

        // Query ALL existing staging records (both Matched and Unmatched)
        // FIXED (2026-02-13): Check all staging records to update Unmatched ones
        Map<String, AI_Workspace_Staging__c> existingStagingByProviderId = new Map<String, AI_Workspace_Staging__c>();
        if (!taskIds.isEmpty()) {
            for (AI_Workspace_Staging__c existing : [
                SELECT Id, Provider_Id__c, Status__c
                FROM AI_Workspace_Staging__c 
                WHERE Provider_Id__c IN :taskIds
                AND RecordTypeId = :taskRecordTypeId
                WITH USER_MODE
            ]) {
                existingStagingByProviderId.put(existing.Provider_Id__c, existing);
            }
        }
        
        // ALSO check for existing Task records with the same Workspace_Sync_Id__c
        // This ensures deduplication works even after Staging records are deleted
        // IMPORTANT: Only check tasks owned by the specified user to prevent false duplicates
        Set<String> existingTaskProviderIds = new Set<String>();
        if (!taskIds.isEmpty()) {
            existingTaskProviderIds = getExistingTaskProviderIds(taskIds, userId);
        }

        List<AI_Workspace_Staging__c> recordsToInsert = new List<AI_Workspace_Staging__c>();
        Set<Id> existingUnmatchedStagingIdsSet = new Set<Id>(); // Use Set to avoid duplicates

        for (AIGoogleTaskService.ToDoTask task : tasks) {
            try {
                AI_Workspace_Staging__c existingStaging = existingStagingByProviderId.get(task.taskId);
                
                // If staging exists (any status), it's a duplicate for COUNT purposes
                // because it was already fetched in a prior sync.
                // For Unmatched staging, we still collect IDs to retry Task creation,
                // but we don't inflate the current sync's counts.
                if (existingStaging != null) {
                    result.duplicateCount++;
                    // If Unmatched, collect ID for retry (but don't count again)
                    if (existingStaging.Status__c == 'Unmatched') {
                        existingUnmatchedStagingIdsSet.add(existingStaging.Id);
                    }
                    continue;
                }
                
                // Skip if Task record exists (no staging but Task was created)
                if (String.isNotBlank(task.taskId) && existingTaskProviderIds.contains(task.taskId)) {
                    result.duplicateCount++;
                    continue;
                }

                // No existing staging - create new one
                AI_Workspace_Staging__c staging = mapGoogleTaskToStaging(
                    task, 
                    taskRecordTypeId, 
                    providerType,
                    userId
                );
                recordsToInsert.add(staging);
            } catch (Exception e) {
                result.errors.add('Error processing Google task: ' + e.getMessage());
                result.failedCount++;
            }
        }

        // CRITICAL: Get connected email BEFORE DML to avoid "callout after DML" error
        // This callout must happen before insertStagingRecords() which performs DML
        String connectedEmail = null;
        if (!recordsToInsert.isEmpty() || !existingUnmatchedStagingIdsSet.isEmpty()) {
            connectedEmail = getConnectedUserEmail(providerType);
        }

        // Bulk insert NEW staging records (DML operation)
        if (!recordsToInsert.isEmpty()) {
            insertStagingRecords(recordsToInsert, result);
        }
        
        // Combine new staging IDs with existing Unmatched staging IDs for Task creation
        // Use Set to ensure no duplicates
        Set<Id> allStagingIdsSet = new Set<Id>();
        allStagingIdsSet.addAll(result.stagingRecordIds);
        allStagingIdsSet.addAll(existingUnmatchedStagingIdsSet);
        List<Id> allStagingIdsToProcess = new List<Id>(allStagingIdsSet);
        
        // IMPORTANT: Add existing Unmatched staging IDs to result so controller can query them
        // This ensures manual imports from modal can link the created Tasks to selected Contacts
        // Convert result.stagingRecordIds to Set first to avoid duplicates
        Set<Id> resultStagingIdsSet = new Set<Id>(result.stagingRecordIds);
        resultStagingIdsSet.addAll(existingUnmatchedStagingIdsSet);
        result.stagingRecordIds = new List<Id>(resultStagingIdsSet);
        
        // Create/retry Salesforce Task records for both new and existing Unmatched staging
        if (!allStagingIdsToProcess.isEmpty()) {
            MatchingCounts counts = createTasksFromStagingInlineWithEmail(allStagingIdsToProcess, connectedEmail, sendNotifications);
            result.matchedCount += counts.matchedCount;
            result.unmatchedCount += counts.unmatchedCount;
            result.importedCount += counts.importedCount;
        }

        return result;
    }

    /**
     * Maps Google Task to AI_Workspace_Staging__c record
     */
    private static AI_Workspace_Staging__c mapGoogleTaskToStaging(
        AIGoogleTaskService.ToDoTask task,
        Id recordTypeId,
        String providerType,
        Id userId
    ) {
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c();
        staging.RecordTypeId = recordTypeId;
        staging.Provider__c = providerType;
        staging.Provider_Id__c = task.taskId;
        staging.User__c = userId;
        staging.Import_Date__c = DateTime.now();
        staging.Status__c = 'Unmatched';

        // Subject/Title
        staging.Subject__c = truncateField(task.title, 4000);

        // Description/Body (Google uses "notes")
        String description = '';
        if (String.isNotBlank(task.listName)) {
            description += 'From List: ' + task.listName + '\n---\n';
        }
        if (String.isNotBlank(task.body)) {
            description += task.body;
        }
        staging.Text_Body__c = truncateField(description, 32000);

        // List name
        staging.List_Name__c = truncateField(task.listName, 255);

        // Due date
        if (task.dueDateTime != null) {
            staging.Due_Date__c = task.dueDateTime.date();
        }

        // Status mapping
        staging.Task_Status__c = mapGoogleTaskStatus(task.status);

        // Priority/Importance mapping (Google doesn't have importance, defaults to normal)
        staging.Task_Priority__c = 'Normal';

        // Completed date
        staging.Completed_Date__c = task.completedDateTime;

        return staging;
    }

    /**
     * Maps Google Task status to Salesforce Task status
     * Google: needsAction, completed
     * Salesforce: Not Started, In Progress, Completed
     */
    private static String mapGoogleTaskStatus(String googleStatus) {
        if (googleStatus == 'completed') {
            return 'Completed';
        }
        // Default to Not Started for needsAction
        return 'Not Started';
    }

    /**
     * Maps Graph API email data to AI_Workspace_Staging__c record
     */
    private static AI_Workspace_Staging__c mapEmailToStaging(
        Map<String, Object> emailData,
        Id recordTypeId,
        String providerType,
        String userEmail,
        Id syncLogId,
        Id targetUserId
    ) {
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c();
        staging.RecordTypeId = recordTypeId;
        staging.Provider__c = providerType;
        staging.Provider_Id__c = (String) emailData.get('id');
        staging.Provider_Conversation_Id__c = (String) emailData.get('conversationId');
        staging.Message_Identifier__c = (String) emailData.get('internetMessageId');
        staging.User__c = targetUserId != null ? targetUserId : UserInfo.getUserId();
        staging.Sync_Log__c = syncLogId;
        staging.Import_Date__c = DateTime.now();
        staging.Status__c = 'Unmatched';

        // Subject
        staging.Subject__c = truncateField((String) emailData.get('subject'), 4000);

        // Body content
        Map<String, Object> body = (Map<String, Object>) emailData.get('body');
        if (body != null) {
            String contentType = (String) body.get('contentType');
            String content = (String) body.get('content');

            if (contentType == 'html') {
                staging.Html_Body__c = truncateField(content, 32000);
                staging.Text_Body__c = truncateField(stripHtml(content), 32000);
            } else {
                staging.Text_Body__c = truncateField(content, 32000);
                staging.Html_Body__c = truncateField('<pre>' + content + '</pre>', 32000);
            }
        }

        // From address
        Map<String, Object> fromObj = (Map<String, Object>) emailData.get('from');
        if (fromObj != null) {
            Map<String, Object> fromAddress = (Map<String, Object>) fromObj.get('emailAddress');
            if (fromAddress != null) {
                staging.From_Address__c = (String) fromAddress.get('address');
                staging.From_Name__c = truncateField((String) fromAddress.get('name'), 255);
            }
        }

        // Recipients
        staging.To_Address__c = buildRecipientString((List<Object>) emailData.get('toRecipients'), 4000);
        staging.Cc_Address__c = buildRecipientString((List<Object>) emailData.get('ccRecipients'), 4000);
        staging.Bcc_Address__c = buildRecipientString((List<Object>) emailData.get('bccRecipients'), 4000);

        // Dates
        staging.Message_Date__c = parseDateTime((String) emailData.get('receivedDateTime'));

        // Direction (incoming/outgoing)
        Boolean isSentEmail = isSentByUser(staging.From_Address__c, userEmail);
        staging.Is_Incoming__c = !isSentEmail;

        // Importance
        String importance = (String) emailData.get('importance');
        if (importance != null) {
            staging.Importance__c = importance.capitalize();
        }

        // Has attachments
        staging.Has_Attachments__c = emailData.get('hasAttachments') == true;

        return staging;
    }

    /**
     * Maps calendar event to AI_Workspace_Staging__c record
     */
    private static AI_Workspace_Staging__c mapCalendarEventToStaging(
        AIMicrosoftCalendarService.CalendarEvent evt,
        Id recordTypeId,
        String providerType,
        Id syncLogId,
        Id targetUserId
    ) {
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c();
        staging.RecordTypeId = recordTypeId;
        staging.Provider__c = providerType;
        staging.Provider_Id__c = evt.eventId;
        // Use deduplication ID for ICalUID__c field
        // For Google recurring events: uses eventId (unique per instance)
        // For others: uses iCalUID
        staging.ICalUID__c = AICalendarEventCreator.getDeduplicationId(evt);
        staging.User__c = targetUserId != null ? targetUserId : UserInfo.getUserId();
        staging.Sync_Log__c = syncLogId;
        staging.Import_Date__c = DateTime.now();
        staging.Status__c = 'Unmatched';

        // Subject/Title
        staging.Subject__c = truncateField(evt.subject, 4000);

        // Description
        staging.Text_Body__c = truncateField(evt.description, 32000);

        // DateTime fields
        staging.Start_DateTime__c = evt.startDateTime;
        staging.End_DateTime__c = evt.endDateTime;
        staging.Is_All_Day__c = evt.isAllDay == true;

        // Location
        staging.Location__c = truncateField(evt.location, 255);

        // Meeting link
        staging.Meeting_Link__c = evt.meetingLink;

        // Organizer
        if (String.isNotBlank(evt.organizerEmail)) {
            staging.Organizer__c = truncateField(evt.organizerName + ' <' + evt.organizerEmail + '>', 255);
        } else if (String.isNotBlank(evt.organizerName)) {
            staging.Organizer__c = truncateField(evt.organizerName, 255);
        }

        // Attendees
        if (evt.attendees != null && !evt.attendees.isEmpty()) {
            List<String> attendeeList = new List<String>();
            for (AIMicrosoftCalendarService.Attendee att : evt.attendees) {
                String attendeeStr = String.isNotBlank(att.name) 
                    ? att.name + ' <' + att.email + '>'
                    : att.email;
                attendeeList.add(attendeeStr);
            }
            staging.Attendees__c = truncateField(String.join(attendeeList, '\n'), 10000);
        }

        return staging;
    }

    /**
     * Maps task to AI_Workspace_Staging__c record
     */
    private static AI_Workspace_Staging__c mapTaskToStaging(
        AIMicrosoftTaskService.ToDoTask task,
        Id recordTypeId,
        String providerType,
        Id syncLogId,
        Id targetUserId
    ) {
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c();
        staging.RecordTypeId = recordTypeId;
        staging.Provider__c = providerType;
        staging.Provider_Id__c = task.taskId;
        staging.User__c = targetUserId != null ? targetUserId : UserInfo.getUserId();
        staging.Sync_Log__c = syncLogId;
        staging.Import_Date__c = DateTime.now();
        staging.Status__c = 'Unmatched';

        // Subject/Title
        staging.Subject__c = truncateField(task.title, 4000);

        // Description/Body
        String description = '';
        if (String.isNotBlank(task.listName)) {
            description += 'From List: ' + task.listName + '\n---\n';
        }
        if (String.isNotBlank(task.body)) {
            description += task.body;
        }
        staging.Text_Body__c = truncateField(description, 32000);

        // List name
        staging.List_Name__c = truncateField(task.listName, 255);

        // Due date
        if (task.dueDateTime != null) {
            staging.Due_Date__c = task.dueDateTime.date();
        }

        // Reminder
        if (task.isReminderOn == true && task.reminderDateTime != null) {
            staging.Reminder_DateTime__c = task.reminderDateTime;
        }

        // Status mapping
        staging.Task_Status__c = mapTaskStatus(task.status);

        // Priority/Importance mapping
        staging.Task_Priority__c = mapTaskPriority(task.importance);

        // Completed date
        staging.Completed_Date__c = task.completedDateTime;

        return staging;
    }

    /**
     * Bulk insert staging records with error handling and FLS enforcement
     */
    private static void insertStagingRecords(List<AI_Workspace_Staging__c> records, StagingResult result) {
        
        // Use FLSCheck for FLS/OLS enforcement
        List<AI_Workspace_Staging__c> accessibleRecords = FLSCheck.getInstance().insertCheck(records);
        
        if (accessibleRecords == null || accessibleRecords.isEmpty()) {
            result.failedCount = records.size();
            result.errors.add('Insufficient permissions to create AI Workspace Staging records');
            return;
        }
        
        
        // Perform DML with partial success handling
        Database.SaveResult[] saveResults = Database.insert(accessibleRecords, false);

        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                result.successCount++;
                result.stagingRecordIds.add(saveResults[i].getId());
            } else {
                result.failedCount++;
                for (Database.Error err : saveResults[i].getErrors()) {
                    String subject = accessibleRecords[i].Subject__c;
                    String errorMsg = String.isNotBlank(subject) 
                        ? subject + ': ' + err.getMessage()
                        : err.getMessage();
                    result.errors.add(errorMsg);
                }
            }
        }
        
    }
    
    /**
     * Helper method to update staging records with FLS enforcement
     */
    private static void updateStagingRecordsWithFLS(List<AI_Workspace_Staging__c> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        
        // Use FLSCheck for FLS/OLS enforcement
        List<AI_Workspace_Staging__c> accessibleRecords = FLSCheck.getInstance().updateCheck(records);
        
        if (accessibleRecords == null || accessibleRecords.isEmpty()) {
            return;
        }
        
        // Perform DML with partial success handling
        Database.update(accessibleRecords, false);
    }

    /**
     * Map Microsoft task status to picklist value
     */
    private static String mapTaskStatus(String msStatus) {
        if (String.isBlank(msStatus)) {
            return 'Not Started';
        }
        
        switch on msStatus.toLowerCase() {
            when 'completed' {
                return 'Completed';
            }
            when 'inprogress' {
                return 'In Progress';
            }
            when else {
                return 'Not Started';
            }
        }
    }

    /**
     * Map Microsoft task importance to picklist value
     */
    private static String mapTaskPriority(String msImportance) {
        if (String.isBlank(msImportance)) {
            return 'Normal';
        }
        
        switch on msImportance.toLowerCase() {
            when 'high' {
                return 'High';
            }
            when 'low' {
                return 'Low';
            }
            when else {
                return 'Normal';
            }
        }
    }

    /**
     * Check if email was sent by the user
     */
    private static Boolean isSentByUser(String fromAddress, String userEmail) {
        if (String.isBlank(fromAddress)) {
            return false;
        }
        
        // Check against provided user email (from provider)
        if (String.isNotBlank(userEmail) && fromAddress.equalsIgnoreCase(userEmail)) {
            return true;
        }
        
        // Fallback: check against SF user email
        String sfUserEmail = UserInfo.getUserEmail();
        if (String.isNotBlank(sfUserEmail) && fromAddress.equalsIgnoreCase(sfUserEmail)) {
            return true;
        }
        
        return false;
    }

    /**
     * Build recipient string from Graph API recipients array
     */
    private static String buildRecipientString(List<Object> recipients, Integer maxLength) {
        if (recipients == null || recipients.isEmpty()) {
            return null;
        }

        List<String> addresses = new List<String>();
        for (Object recipientObj : recipients) {
            Map<String, Object> recipient = (Map<String, Object>) recipientObj;
            Map<String, Object> emailAddress = (Map<String, Object>) recipient.get('emailAddress');
            if (emailAddress != null) {
                String address = (String) emailAddress.get('address');
                if (String.isNotBlank(address)) {
                    addresses.add(address);
                }
            }
        }

        return truncateField(String.join(addresses, '; '), maxLength);
    }

    /**
     * Parse ISO 8601 datetime string
     */
    private static DateTime parseDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }
        
        try {
            // Handle ISO 8601 format
            dateTimeStr = dateTimeStr.replace('T', ' ').replace('Z', '');
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
            }
            return DateTime.valueOfGmt(dateTimeStr);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Truncate field to maximum length
     */
    private static String truncateField(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    /**
     * Simple HTML stripping
     */
    private static String stripHtml(String htmlContent) {
        if (String.isBlank(htmlContent)) {
            return htmlContent;
        }
        return htmlContent.stripHtmlTags();
    }

    /**
     * Get existing staging record IDs by provider IDs (for deduplication checks)
     */
    public static Map<String, Id> getExistingEmailsByProviderId(Set<String> providerIds) {
        Map<String, Id> existingMap = new Map<String, Id>();
        if (providerIds == null || providerIds.isEmpty()) {
            return existingMap;
        }

        Id emailRecordTypeId = getRecordTypeId(RT_EMAIL);
        for (AI_Workspace_Staging__c staging : [
            SELECT Id, Provider_Id__c 
            FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c IN :providerIds
            AND RecordTypeId = :emailRecordTypeId
            WITH USER_MODE
        ]) {
            existingMap.put(staging.Provider_Id__c, staging.Id);
        }

        return existingMap;
    }

    /**
     * Get existing calendar staging records by iCalUID
     */
    public static Map<String, Id> getExistingCalendarsByICalUID(Set<String> iCalUIDs) {
        Map<String, Id> existingMap = new Map<String, Id>();
        if (iCalUIDs == null || iCalUIDs.isEmpty()) {
            return existingMap;
        }

        Id calendarRecordTypeId = getRecordTypeId(RT_CALENDAR);
        for (AI_Workspace_Staging__c staging : [
            SELECT Id, ICalUID__c 
            FROM AI_Workspace_Staging__c 
            WHERE ICalUID__c IN :iCalUIDs
            AND RecordTypeId = :calendarRecordTypeId
            WITH USER_MODE
        ]) {
            existingMap.put(staging.ICalUID__c, staging.Id);
        }

        return existingMap;
    }

    /**
     * Get existing task staging records by provider ID
     */
    public static Map<String, Id> getExistingTasksByProviderId(Set<String> providerIds) {
        Map<String, Id> existingMap = new Map<String, Id>();
        if (providerIds == null || providerIds.isEmpty()) {
            return existingMap;
        }

        Id taskRecordTypeId = getRecordTypeId(RT_TASK);
        for (AI_Workspace_Staging__c staging : [
            SELECT Id, Provider_Id__c 
            FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c IN :providerIds
            AND RecordTypeId = :taskRecordTypeId
            WITH USER_MODE
        ]) {
            existingMap.put(staging.Provider_Id__c, staging.Id);
        }

        return existingMap;
    }
    
    /**
     * Get existing EmailMessage MessageIdentifier values for deduplication
     * This queries the EmailMessage object directly to catch cases where
     * Staging records were deleted but EmailMessages still exist.
     * Uses the standard MessageIdentifier field (RFC 2822 Message-ID / internetMessageId)
     * @param messageIdentifiers Set of message identifiers to check
     * @return Set of message identifiers that already have EmailMessages
     */
    private static Set<String> getExistingEmailMessageIdentifiers(Set<String> messageIdentifiers) {
        Set<String> existingIdentifiers = new Set<String>();
        if (messageIdentifiers == null || messageIdentifiers.isEmpty()) {
            return existingIdentifiers;
        }
        
        // Query EmailMessage using the standard MessageIdentifier field
        for (EmailMessage em : [
            SELECT MessageIdentifier 
            FROM EmailMessage 
            WHERE MessageIdentifier IN :messageIdentifiers
            WITH USER_MODE
        ]) {
            if (String.isNotBlank(em.MessageIdentifier)) {
                existingIdentifiers.add(em.MessageIdentifier);
            }
        }
        
        return existingIdentifiers;
    }
    
    /**
     * Get existing Event Workspace_Sync_Id__c values for deduplication
     * This queries the Event object directly to catch cases where
     * Staging records were deleted but Events still exist.
     * @param iCalUIDs Set of iCalUIDs to check
     * @param userId The user ID to filter events by (only check events owned by this user)
     * @return Set of iCalUIDs that already have Events
     */
    private static Set<String> getExistingEventCalendarIds(Set<String> iCalUIDs, Id userId) {
        Set<String> existingCalendarIds = new Set<String>();
        if (iCalUIDs == null || iCalUIDs.isEmpty()) {
            return existingCalendarIds;
        }
        
        // Check if the field exists before querying (namespace-aware)
        String workspaceSyncIdField = AIConstants.NAMESPACE + 'Workspace_Sync_Id__c';
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Event.fields.getMap();
        if (!fieldMap.containsKey(workspaceSyncIdField)) {
            return existingCalendarIds;
        }
        
        // Query Event for existing Workspace_Sync_Id__c values
        // Only check events owned by the specified user
        String queryStr = 'SELECT ' + workspaceSyncIdField + ' FROM Event ' +
                         'WHERE ' + workspaceSyncIdField + ' IN :iCalUIDs ' +
                         'AND OwnerId = :userId';
        for (Event evt : Database.query(queryStr)) {
            String calendarId = (String) evt.get(workspaceSyncIdField);
            if (String.isNotBlank(calendarId)) {
                existingCalendarIds.add(calendarId);
            }
        }
        
        return existingCalendarIds;
    }
    
    /**
     * Get existing Task Workspace_Sync_Id__c values for deduplication
     * This queries the Task object directly to catch cases where
     * Staging records were deleted but Tasks still exist.
     * @param providerIds Set of provider task IDs to check
     * @param userId The user ID to filter tasks by (only check tasks owned by this user)
     * @return Set of provider IDs that already have Tasks
     */
    private static Set<String> getExistingTaskProviderIds(Set<String> providerIds, Id userId) {
        Set<String> existingProviderIds = new Set<String>();
        if (providerIds == null || providerIds.isEmpty()) {
            return existingProviderIds;
        }
        
        // Check if the field exists before querying (namespace-aware)
        String workspaceSyncIdField = AIConstants.NAMESPACE + 'Workspace_Sync_Id__c';
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Task.fields.getMap();
        if (!fieldMap.containsKey(workspaceSyncIdField)) {
            return existingProviderIds;
        }
        
        // Query Task for existing Workspace_Sync_Id__c values
        // FIXED (2026-02-15): Added OwnerId filter to prevent false duplicates across users
        // Only check tasks owned by the specified user
        String queryStr = 'SELECT ' + workspaceSyncIdField + ' FROM Task ' +
                         'WHERE ' + workspaceSyncIdField + ' IN :providerIds ' +
                         'AND OwnerId = :userId';
        for (Task t : Database.query(queryStr)) {
            String providerId = (String) t.get(workspaceSyncIdField);
            if (String.isNotBlank(providerId)) {
                existingProviderIds.add(providerId);
            }
        }
        
        return existingProviderIds;
    }
    
    /**
     * Inner class to hold matching results with counts
     */
    public class MatchingCounts {
        public Integer matchedCount = 0;
        public Integer unmatchedCount = 0;
        public Integer importedCount = 0;  // Actual EmailMessage/Event/Task records created
    }
    
    /**
     * Immediately match email staging records after creation
     * Uses AIStagingMatcherService to match From, To, CC emails to Lead/Contact
     * Creates EmailMessageRelation for ALL matching records
     * Excludes connected account email from matching (V2-8XXX)
     * @param stagingRecordIds List of newly created staging record IDs
     * @param sendNotifications Whether to send bell notifications (true for manual, false for auto-sync)
     * @param connectedAccountEmail The connected account email to exclude from matching (e.g., piyush2@gptfy.dev)
     * @return MatchingCounts with matched, unmatched, and imported counts
     */
    private static MatchingCounts matchEmailStagingRecordsInline(List<Id> stagingRecordIds, Boolean sendNotifications, String connectedAccountEmail) {
        MatchingCounts counts = new MatchingCounts();
        
        if (stagingRecordIds == null || stagingRecordIds.isEmpty()) {
            return counts;
        }
        
        // Check if matching is enabled
        if (!AIStagingMatcherService.isMatchingEnabled()) {
            // Mark all as Unmatched since matching is disabled
            List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
            for (Id stagingId : stagingRecordIds) {
                stagingToUpdate.add(new AI_Workspace_Staging__c(Id = stagingId, Status__c = 'Unmatched'));
            }
            updateStagingRecordsWithFLS(stagingToUpdate);
            counts.unmatchedCount = stagingRecordIds.size();
            
            // Send notifications even when matching is disabled
            if (sendNotifications) {
                try {
                    List<AI_Workspace_Staging__c> stagingRecords = [
                        SELECT Id, Subject__c
                        FROM AI_Workspace_Staging__c
                        WHERE Id IN :stagingRecordIds
                    ];
                    sendEmailStagingNotificationsInternal(stagingRecords, new Map<Integer, Id>(), new Map<Integer, Id>());
                } catch (Exception e) {
                    // Error sending email notifications
                }
            }
            
            return counts;
        }
        
        // Declare variables outside try block for notification access
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        Map<Integer, Id> emailIndexToStagingId = new Map<Integer, Id>();
        Map<Integer, Id> emailIndexToEmailMessageId = new Map<Integer, Id>();
        
        try {
            // Query the staging records we just created
            stagingRecords = [
                SELECT Id, From_Address__c, From_Name__c, To_Address__c, Cc_Address__c, Bcc_Address__c,
                       Subject__c, Text_Body__c, Html_Body__c, Message_Date__c, Message_Identifier__c,
                       Provider__c, Provider_Id__c, Provider_Conversation_Id__c, Importance__c,
                       Is_Incoming__c, Has_Attachments__c, User__c, Sync_Log__c
                FROM AI_Workspace_Staging__c
                WHERE Id IN :stagingRecordIds
            ];
            
            if (stagingRecords.isEmpty()) {
                return counts;
            }
            
            // Use the multi-match service to match From, To, CC emails
            // Pass connected account email to exclude from matching
            Map<Id, AIStagingMatcherService.MultiMatchResult> matchResults = 
                AIStagingMatcherService.matchEmailStagingRecordsMulti(stagingRecords, connectedAccountEmail);
            
            List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
            List<EmailMessage> emailsToCreate = new List<EmailMessage>();
            Map<Integer, List<AIStagingMatcherService.MatchResult>> emailIndexToAllMatches = 
                new Map<Integer, List<AIStagingMatcherService.MatchResult>>();
            
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                AIStagingMatcherService.MultiMatchResult multiMatch = matchResults.get(staging.Id);
                
                AI_Workspace_Staging__c updateRecord = new AI_Workspace_Staging__c(Id = staging.Id);
                
                if (multiMatch != null && multiMatch.hasAnyMatch) {
                    // Mark as matched - the actual Lead/Contact associations are stored in EmailMessageRelation
                    updateRecord.Status__c = 'Matched';
                    counts.matchedCount++;
                    
                    // Create EmailMessage for matched records
                    EmailMessage em = createEmailMessageFromStaging(staging);
                    
                    // Store the index for later relation creation
                    Integer emailIndex = emailsToCreate.size();
                    emailIndexToStagingId.put(emailIndex, staging.Id);
                    emailIndexToAllMatches.put(emailIndex, multiMatch.allMatches);
                    
                    emailsToCreate.add(em);
                } else {
                    // No match found
                    updateRecord.Status__c = 'Unmatched';
                    counts.unmatchedCount++;
                }
                
                stagingToUpdate.add(updateRecord);
            }
            
            // Insert EmailMessages and create relations for ALL matched records
            if (!emailsToCreate.isEmpty()) {
                // Pass staging records to get User__c for each email
                emailIndexToEmailMessageId = insertEmailMessagesInline(emailsToCreate, stagingRecords, emailIndexToStagingId);
                
                // Count successfully created EmailMessage records
                counts.importedCount = emailIndexToEmailMessageId.size();
                
                // Create EmailMessageRelations for ALL matched Contacts/Leads
                createMultipleEmailMessageRelations(emailIndexToEmailMessageId, emailIndexToAllMatches);
                
                // Update staging records with EmailMessage reference
                for (Integer idx : emailIndexToEmailMessageId.keySet()) {
                    Id stagingId = emailIndexToStagingId.get(idx);
                    Id emailMessageId = emailIndexToEmailMessageId.get(idx);
                    
                    if (stagingId != null && emailMessageId != null) {
                        for (AI_Workspace_Staging__c staging : stagingToUpdate) {
                            if (staging.Id == stagingId) {
                                staging.Email_Message__c = String.valueOf(emailMessageId);
                                break;
                            }
                        }
                    }
                }
            }
            
            // Update staging records
            if (!stagingToUpdate.isEmpty()) {
                updateStagingRecordsWithFLS(stagingToUpdate);
            }
            
        } catch (Exception e) {
            // Don't throw - matching failure shouldn't fail the staging creation
        }
        
        // Send notifications for ALL staging records after database update (only if sendNotifications=true)
        // This is outside the try-catch to ensure notifications are sent even if matching fails
        if (sendNotifications) {
            try {
                sendEmailStagingNotificationsInternal(stagingRecords, emailIndexToStagingId, emailIndexToEmailMessageId);
            } catch (Exception e) {
                // Error sending email notifications
            }
        }
        
        return counts;
    }
    
    /**
     * Create EmailMessageRelation records for ALL matched Contacts/Leads
     * 
     * NEW LOGIC: Each MatchResult now contains lists of ALL matched IDs at the successful
     * precedence level (matchedLeadIds, matchedContactIds). We create relations for ALL of them.
     * 
     * @param emailIndexToEmailMessageId Map of email index to created EmailMessage ID
     * @param emailIndexToAllMatches Map of email index to all match results
     */
    private static void createMultipleEmailMessageRelations(
        Map<Integer, Id> emailIndexToEmailMessageId,
        Map<Integer, List<AIStagingMatcherService.MatchResult>> emailIndexToAllMatches
    ) {
        List<EmailMessageRelation> relations = new List<EmailMessageRelation>();
        Set<String> createdRelations = new Set<String>(); // Prevent duplicates
        
        for (Integer idx : emailIndexToEmailMessageId.keySet()) {
            Id emailMessageId = emailIndexToEmailMessageId.get(idx);
            List<AIStagingMatcherService.MatchResult> allMatches = emailIndexToAllMatches.get(idx);
            
            if (allMatches == null || allMatches.isEmpty()) {
                continue;
            }
            
            for (AIStagingMatcherService.MatchResult match : allMatches) {
                // NEW: Create relations for ALL matched Contacts (from matchedContactIds list)
                if (match.matchedContactIds != null && !match.matchedContactIds.isEmpty()) {
                    for (Id contactId : match.matchedContactIds) {
                        String key = emailMessageId + '-' + contactId;
                        if (!createdRelations.contains(key)) {
                            EmailMessageRelation emr = new EmailMessageRelation();
                            emr.EmailMessageId = emailMessageId;
                            emr.RelationId = contactId;
                            emr.RelationType = 'OtherAddress';
                            relations.add(emr);
                            createdRelations.add(key);
                        }
                    }
                } else if (match.contactId != null) {
                    // Backward compatibility: use single contactId if list is empty
                    String key = emailMessageId + '-' + match.contactId;
                    if (!createdRelations.contains(key)) {
                        EmailMessageRelation emr = new EmailMessageRelation();
                        emr.EmailMessageId = emailMessageId;
                        emr.RelationId = match.contactId;
                        emr.RelationType = 'OtherAddress';
                        relations.add(emr);
                        createdRelations.add(key);
                    }
                }
                
                // NEW: Create relations for ALL matched Leads (from matchedLeadIds list)
                if (match.matchedLeadIds != null && !match.matchedLeadIds.isEmpty()) {
                    for (Id leadId : match.matchedLeadIds) {
                        String key = emailMessageId + '-' + leadId;
                        if (!createdRelations.contains(key)) {
                            EmailMessageRelation emr = new EmailMessageRelation();
                            emr.EmailMessageId = emailMessageId;
                            emr.RelationId = leadId;
                            emr.RelationType = 'OtherAddress';
                            relations.add(emr);
                            createdRelations.add(key);
                        }
                    }
                } else if (match.leadId != null) {
                    // Backward compatibility: use single leadId if list is empty
                    String key = emailMessageId + '-' + match.leadId;
                    if (!createdRelations.contains(key)) {
                        EmailMessageRelation emr = new EmailMessageRelation();
                        emr.EmailMessageId = emailMessageId;
                        emr.RelationId = match.leadId;
                        emr.RelationType = 'OtherAddress';
                        relations.add(emr);
                        createdRelations.add(key);
                    }
                }
                
                // Note: Only Lead and Contact are supported for EmailMessageRelation
            }
        }
        
        // Batch insert relations in chunks to avoid DML limits
        if (!relations.isEmpty()) {
            insertRelationsInBatches(relations, 50);
        }
    }
    
    /**
     * Insert relations in batches to avoid hitting DML limits
     * @param relations List of EmailMessageRelation records to insert
     * @param batchSize Size of each batch (default 50)
     */
    private static void insertRelationsInBatches(List<EmailMessageRelation> relations, Integer batchSize) {
        Integer totalSuccess = 0;
        Integer totalFailed = 0;
        
        // Check object-level create permission for EmailMessageRelation
        if (!Schema.sObjectType.EmailMessageRelation.isCreateable()) {
            return;
        }
        
        for (Integer i = 0; i < relations.size(); i += batchSize) {
            Integer endIdx = Math.min(i + batchSize, relations.size());
            List<EmailMessageRelation> batch = new List<EmailMessageRelation>();
            for (Integer j = i; j < endIdx; j++) {
                batch.add(relations[j]);
            }
            
            // Use FLSCheck for FLS/OLS enforcement
            List<EmailMessageRelation> accessibleBatch = FLSCheck.getInstance().insertCheck(batch);
            
            if (accessibleBatch == null || accessibleBatch.isEmpty()) {
                continue;
            }
            
            Database.SaveResult[] results = Database.insert(accessibleBatch, false);
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    totalSuccess++;
                } else {
                    totalFailed++;
                }
            }
        }
    }
    
    /**
     * Send bell notifications for matched emails
     * @param stagingRecords Original staging records with email data
     * @param emailIndexToStagingId Map of email index to staging record ID
     * @param emailIndexToEmailMessageId Map of email index to created EmailMessage ID
     * @param emailIndexToAllMatches Map of email index to all match results
     */
    private static void sendEmailMatchNotifications(
        List<AI_Workspace_Staging__c> stagingRecords,
        Map<Integer, Id> emailIndexToStagingId,
        Map<Integer, Id> emailIndexToEmailMessageId,
        Map<Integer, List<AIStagingMatcherService.MatchResult>> emailIndexToAllMatches
    ) {
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                return;
            }
            
            CustomNotificationType notifType = notifTypes[0];
            
            // Build a map of staging ID to staging record for easy lookup
            Map<Id, AI_Workspace_Staging__c> stagingMap = new Map<Id, AI_Workspace_Staging__c>(stagingRecords);
            
            // Send notifications for each successfully imported email
            for (Integer idx : emailIndexToEmailMessageId.keySet()) {
                Id emailMessageId = emailIndexToEmailMessageId.get(idx);
                Id stagingId = emailIndexToStagingId.get(idx);
                
                // Only send notification if EmailMessage was successfully created
                if (emailMessageId == null) continue;
                
                AI_Workspace_Staging__c staging = stagingMap.get(stagingId);
                if (staging == null) continue;
                
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    
                    // Truncate subject for title
                    String subject = staging.Subject__c != null ? staging.Subject__c : '(No Subject)';
                    String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
                    
                    notification.setTitle('✉️ Email imported: ' + truncatedSubject);
                    notification.setBody('Email imported successfully.\nClick to view the email.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(emailMessageId); // Always navigate to EmailMessage record
                    
                    notification.send(new Set<String>{UserInfo.getUserId()});
                } catch (Exception e) {
                    // Failed to send email notification
                }
            }
        } catch (Exception e) {
            // Error sending email match notifications
        }
    }
    
    /**
     * Send notifications for email staging records using in-memory data
     * Called from within matchEmailStagingRecordsInline after database update
     * @param stagingRecords List of staging records
     * @param emailIndexToStagingId Map of email index to staging ID
     * @param emailIndexToEmailMessageId Map of email index to EmailMessage ID
     */
    private static void sendEmailStagingNotificationsInternal(
        List<AI_Workspace_Staging__c> stagingRecords,
        Map<Integer, Id> emailIndexToStagingId,
        Map<Integer, Id> emailIndexToEmailMessageId
    ) {
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                return;
            }
            
            CustomNotificationType notifType = notifTypes[0];
            
            // Build a map of staging ID to staging record
            Map<Id, AI_Workspace_Staging__c> stagingMap = new Map<Id, AI_Workspace_Staging__c>(stagingRecords);
            
            // Build reverse map: stagingId -> emailMessageId
            Map<Id, Id> stagingIdToEmailMessageId = new Map<Id, Id>();
            for (Integer idx : emailIndexToEmailMessageId.keySet()) {
                Id stagingId = emailIndexToStagingId.get(idx);
                Id emailMessageId = emailIndexToEmailMessageId.get(idx);
                if (stagingId != null && emailMessageId != null) {
                    stagingIdToEmailMessageId.put(stagingId, emailMessageId);
                }
            }
            
            // Send notifications for ALL staging records
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                try {
                    // Determine target ID - use EmailMessage if matched, otherwise staging record
                    Id targetId = staging.Id; // Default to staging record
                    
                    if (stagingIdToEmailMessageId.containsKey(staging.Id)) {
                        targetId = stagingIdToEmailMessageId.get(staging.Id);
                    }
                    
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    
                    // Truncate subject for title
                    String subject = staging.Subject__c != null ? staging.Subject__c : '(No Subject)';
                    String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
                    
                    notification.setTitle('✉️ Email imported: ' + truncatedSubject);
                    notification.setBody('Email imported successfully.\nClick to view the email.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(targetId);
                    
                    notification.send(new Set<String>{UserInfo.getUserId()});
                } catch (Exception e) {
                    // Failed to send email notification
                }
            }
        } catch (Exception e) {
            // Error sending email staging notifications
        }
    }
    
    /**
     * Send notifications for ALL email staging records (matched and unmatched)
     * This is called for manual imports to notify users of all imported emails
     * @param stagingRecordIds List of staging record IDs
     * @param counts Matching counts with importedCount (EmailMessages created)
     */
    private static void sendEmailStagingNotifications(List<Id> stagingRecordIds, MatchingCounts counts) {
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                return;
            }
            
            CustomNotificationType notifType = notifTypes[0];
            
            // Query staging records with EmailMessage references
            List<AI_Workspace_Staging__c> stagingRecords = [
                SELECT Id, Subject__c, Email_Message__c, Status__c
                FROM AI_Workspace_Staging__c
                WHERE Id IN :stagingRecordIds
            ];
            
            // Send notifications for each staging record
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                try {
                    // Determine target ID - use EmailMessage if matched, otherwise staging record
                    Id targetId = staging.Id; // Default to staging record
                    
                    if (String.isNotBlank(staging.Email_Message__c)) {
                        try {
                            targetId = Id.valueOf(staging.Email_Message__c);
                        } catch (Exception e) {
                            // If Email_Message__c is not a valid ID, use staging ID
                        }
                    }
                    
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    
                    // Truncate subject for title
                    String subject = staging.Subject__c != null ? staging.Subject__c : '(No Subject)';
                    String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
                    
                    notification.setTitle('✉️ Email imported: ' + truncatedSubject);
                    notification.setBody('Email imported successfully.\nClick to view the email.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(targetId);
                    
                    notification.send(new Set<String>{UserInfo.getUserId()});
                } catch (Exception e) {
                    // Failed to send email notification
                }
            }
        } catch (Exception e) {
            // Error sending email staging notifications
        }
    }
    
    /**
     * Create EmailMessage from staging record
     * 
     * Note: We populate standard EmailMessage fields:
     * - MessageIdentifier (standard): For deduplication (RFC 2822 Message-ID / internetMessageId)
     */
    private static EmailMessage createEmailMessageFromStaging(AI_Workspace_Staging__c staging) {
        EmailMessage em = new EmailMessage();
        
        // Standard EmailMessage fields
        em.Subject = staging.Subject__c;
        em.FromAddress = staging.From_Address__c;
        em.FromName = staging.From_Name__c;
        em.ToAddress = staging.To_Address__c;
        em.CcAddress = staging.Cc_Address__c;
        em.BccAddress = staging.Bcc_Address__c;
        em.TextBody = staging.Text_Body__c;
        em.HtmlBody = staging.Html_Body__c;
        em.MessageDate = staging.Message_Date__c;
        em.MessageIdentifier = staging.Message_Identifier__c;
        em.Incoming = staging.Is_Incoming__c != null ? staging.Is_Incoming__c : true;
        em.Status = '3'; // Sent/Received status
        
        return em;
    }
    
    /**
     * Check if a field exists on EmailMessage and is createable
     */
    private static Boolean isEmailFieldCreateable(Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        if (!fieldMap.containsKey(fieldName)) {
            return false;
        }
        return fieldMap.get(fieldName).getDescribe().isCreateable();
    }
    
    /**
     * Insert EmailMessages and return map of index to created record ID (with FLS enforcement)
     * 
     * NOTE: EmailMessage records do NOT have an OwnerId field and are automatically owned by CreatedById.
     * System.runAs() does NOT change CreatedById - it only changes security context.
     * The ONLY way to have records owned by different users is to use Platform Events or accept
     * that records are owned by the scheduler user.
     * 
     * For now, we insert all emails as the scheduler user (which is the Salesforce standard behavior).
     * Users can still see emails through EmailMessageRelation (which links emails to their Contacts/Leads).
     */
    private static Map<Integer, Id> insertEmailMessagesInline(
        List<EmailMessage> emails, 
        List<AI_Workspace_Staging__c> stagingRecords,
        Map<Integer, Id> emailIndexToStagingId
    ) {
        Map<Integer, Id> indexToId = new Map<Integer, Id>();
        
        // Check object-level create permission
        if (!Schema.sObjectType.EmailMessage.isCreateable()) {
            return indexToId;
        }
        
        // Use FLSCheck for FLS/OLS enforcement
        List<EmailMessage> accessibleEmails = FLSCheck.getInstance().insertCheck(emails);
        
        if (accessibleEmails == null || accessibleEmails.isEmpty()) {
            return new Map<Integer, Id>();
        }
        
        // Insert all emails (they will be owned by the current running user - scheduler user)
        Database.SaveResult[] results = Database.insert(accessibleEmails, false);
        
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                indexToId.put(i, results[i].getId());
            }
        }
        
        return indexToId;
    }
    
    /**
     * Create EmailMessageRelation records to link EmailMessage to Contact/Lead
     */
    private static void createEmailMessageRelationsInline(
        Map<Integer, Id> emailIndexToEmailMessageId,
        Map<Integer, Id> emailIndexToContactId,
        Map<Integer, Id> emailIndexToLeadId
    ) {
        List<EmailMessageRelation> relations = new List<EmailMessageRelation>();
        
        for (Integer idx : emailIndexToEmailMessageId.keySet()) {
            Id emailMessageId = emailIndexToEmailMessageId.get(idx);
            
            // Create relation for Contact
            if (emailIndexToContactId.containsKey(idx)) {
                EmailMessageRelation emr = new EmailMessageRelation();
                emr.EmailMessageId = emailMessageId;
                emr.RelationId = emailIndexToContactId.get(idx);
                emr.RelationType = 'OtherAddress';
                relations.add(emr);
            }
            
            // Create relation for Lead
            if (emailIndexToLeadId.containsKey(idx)) {
                EmailMessageRelation emr = new EmailMessageRelation();
                emr.EmailMessageId = emailMessageId;
                emr.RelationId = emailIndexToLeadId.get(idx);
                emr.RelationType = 'OtherAddress';
                relations.add(emr);
            }
        }
        
        if (!relations.isEmpty()) {
            // Use FLSCheck for FLS/OLS enforcement
            List<EmailMessageRelation> accessibleRelations = FLSCheck.getInstance().insertCheck(relations);
            
            if (accessibleRelations == null || accessibleRelations.isEmpty()) {
                return;
            }
            
            Database.insert(accessibleRelations, false);
        }
    }
    
    /**
     * Immediately match calendar staging records after creation
     * Uses AIStagingMatcherService to match attendee emails to Lead/Contact
     * Excludes connected account email from matching (V2-8XXX)
     * @param stagingRecordIds List of newly created calendar staging record IDs
     * @param connectedAccountEmail The connected account email to exclude from matching (e.g., piyush2@gptfy.dev)
     * @return MatchingCounts with matched, unmatched, and imported counts
     */
    private static MatchingCounts matchCalendarStagingRecordsInline(List<Id> stagingRecordIds, String connectedAccountEmail) {
        MatchingCounts counts = new MatchingCounts();
        
        if (stagingRecordIds == null || stagingRecordIds.isEmpty()) {
            return counts;
        }
        
        // Check if matching is enabled
        if (!AIStagingMatcherService.isMatchingEnabled()) {
            // Mark all as Unmatched since matching is disabled
            List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
            for (Id stagingId : stagingRecordIds) {
                stagingToUpdate.add(new AI_Workspace_Staging__c(Id = stagingId, Status__c = 'Unmatched'));
            }
            updateStagingRecordsWithFLS(stagingToUpdate);
            counts.unmatchedCount = stagingRecordIds.size();
            return counts;
        }
        
        try {
            // Query the calendar staging records we just created
            List<AI_Workspace_Staging__c> stagingRecords = [
                SELECT Id, Subject__c, Text_Body__c, Start_DateTime__c, End_DateTime__c,
                       Is_All_Day__c, Location__c, Meeting_Link__c, Organizer__c, Attendees__c,
                       Provider__c, Provider_Id__c, ICalUID__c, User__c, Sync_Log__c
                FROM AI_Workspace_Staging__c
                WHERE Id IN :stagingRecordIds
            ];
            
            if (stagingRecords.isEmpty()) {
                return counts;
            }
            
            // Use the multi-match service to match ALL attendees
            // Pass connected account email to exclude from matching
            Map<Id, AIStagingMatcherService.MultiMatchResult> matchResults = 
                AIStagingMatcherService.matchCalendarStagingRecordsMulti(stagingRecords, connectedAccountEmail);
            
            List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
            List<Event> eventsToCreate = new List<Event>();
            Map<Integer, Id> eventIndexToStagingId = new Map<Integer, Id>();
            Map<Integer, List<AIStagingMatcherService.MatchResult>> eventIndexToAllMatches = 
                new Map<Integer, List<AIStagingMatcherService.MatchResult>>();
            
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                AIStagingMatcherService.MultiMatchResult multiMatch = matchResults.get(staging.Id);
                
                AI_Workspace_Staging__c updateRecord = new AI_Workspace_Staging__c(Id = staging.Id);
                
                if (multiMatch != null && multiMatch.hasAnyMatch) {
                    // Mark as matched - the actual Lead/Contact associations are stored in EventRelation
                    updateRecord.Status__c = 'Matched';
                    counts.matchedCount++;
                    
                    // Create Event with primary match
                    Event evt = createEventFromStaging(staging, multiMatch.hasPrimaryMatch ? multiMatch.primaryMatch : multiMatch.allMatches[0]);
                    
                    // Store the index for later relation creation
                    Integer eventIndex = eventsToCreate.size();
                    eventIndexToStagingId.put(eventIndex, staging.Id);
                    eventIndexToAllMatches.put(eventIndex, multiMatch.allMatches);
                    
                    eventsToCreate.add(evt);
                } else {
                    // No match found
                    updateRecord.Status__c = 'Unmatched';
                    counts.unmatchedCount++;
                }
                
                stagingToUpdate.add(updateRecord);
            }
            
            // Insert Events and create EventRelations for ALL matched attendees
            if (!eventsToCreate.isEmpty()) {
                Map<Integer, Id> eventIndexToEventId = insertEventsInline(eventsToCreate);
                
                // Count successfully created Event records
                counts.importedCount = eventIndexToEventId.size();
                
                // Create EventRelations for ALL matched Contacts/Leads
                createMultipleEventRelations(eventIndexToEventId, eventIndexToAllMatches);
                
                // Update staging records with Event reference
                for (Integer idx : eventIndexToEventId.keySet()) {
                    Id stagingId = eventIndexToStagingId.get(idx);
                    Id eventId = eventIndexToEventId.get(idx);
                    
                    if (stagingId != null && eventId != null) {
                        for (AI_Workspace_Staging__c staging : stagingToUpdate) {
                            if (staging.Id == stagingId) {
                                // Store Event ID in Email_Message__c (reusing the field for linked record)
                                staging.Email_Message__c = String.valueOf(eventId);
                                break;
                            }
                        }
                    }
                }
            }
            
            // Update staging records
            if (!stagingToUpdate.isEmpty()) {
                updateStagingRecordsWithFLS(stagingToUpdate);
            }
            
        } catch (Exception e) {
            // Don't throw - matching failure shouldn't fail the staging creation
        }
        
        return counts;
    }
    
    /**
     * Send bell notifications for matched calendar events
     * @param stagingRecords Original staging records with calendar data
     * @param eventIndexToStagingId Map of event index to staging record ID
     * @param eventIndexToEventId Map of event index to created Event ID
     * @param eventIndexToAllMatches Map of event index to all match results
     */
    private static void sendCalendarMatchNotifications(
        List<AI_Workspace_Staging__c> stagingRecords,
        Map<Integer, Id> eventIndexToStagingId,
        Map<Integer, Id> eventIndexToEventId,
        Map<Integer, List<AIStagingMatcherService.MatchResult>> eventIndexToAllMatches
    ) {
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                return;
            }
            
            CustomNotificationType notifType = notifTypes[0];
            
            // Build a map of staging ID to staging record for easy lookup
            Map<Id, AI_Workspace_Staging__c> stagingMap = new Map<Id, AI_Workspace_Staging__c>(stagingRecords);
            
            // Send notifications for each successfully imported event
            for (Integer idx : eventIndexToEventId.keySet()) {
                Id eventId = eventIndexToEventId.get(idx);
                Id stagingId = eventIndexToStagingId.get(idx);
                
                // Only send notification if Event was successfully created
                if (eventId == null) continue;
                
                AI_Workspace_Staging__c staging = stagingMap.get(stagingId);
                if (staging == null) continue;
                
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    
                    // Truncate subject for title
                    String subject = staging.Subject__c != null ? staging.Subject__c : '(No Subject)';
                    String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
                    
                    notification.setTitle('📅 Event imported: ' + truncatedSubject);
                    notification.setBody('Calendar event imported successfully.\nClick to view the event.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(eventId); // Always navigate to Event record
                    
                    notification.send(new Set<String>{UserInfo.getUserId()});
                } catch (Exception e) {
                    // Failed to send calendar notification
                }
            }
        } catch (Exception e) {
            // Error sending calendar match notifications
        }
    }
    
    /**
     * Send notifications for ALL calendar staging records (matched and unmatched)
     * This is called for manual imports to notify users of all imported events
     * @param stagingRecordIds List of staging record IDs
     * @param counts Matching counts with importedCount (Events created)
     */
    private static void sendCalendarStagingNotifications(List<Id> stagingRecordIds, MatchingCounts counts) {
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                return;
            }
            
            CustomNotificationType notifType = notifTypes[0];
            
            // Query staging records with Event references and User__c for notification target
            List<AI_Workspace_Staging__c> stagingRecords = [
                SELECT Id, Subject__c, Email_Message__c, Status__c, User__c
                FROM AI_Workspace_Staging__c
                WHERE Id IN :stagingRecordIds
            ];
            
            // Send notifications for each staging record
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                try {
                    // Determine target ID - use Event if matched, otherwise staging record
                    Id targetId = staging.Id; // Default to staging record
                    
                    if (String.isNotBlank(staging.Email_Message__c)) {
                        try {
                            targetId = Id.valueOf(staging.Email_Message__c);
                        } catch (Exception e) {
                            // If Email_Message__c is not a valid ID, use staging ID
                        }
                    }
                    
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    
                    // Truncate subject for title
                    String subject = staging.Subject__c != null ? staging.Subject__c : '(No Subject)';
                    String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
                    
                    notification.setTitle('📅 Event imported: ' + truncatedSubject);
                    notification.setBody('Calendar event imported successfully.\nClick to view the event.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(targetId);
                    
                    // Send to the staging record's owner (User__c), not the current running user
                    // This ensures notifications go to the correct user during scheduled syncs
                    Id recipientUserId = staging.User__c != null ? staging.User__c : UserInfo.getUserId();
                    notification.send(new Set<String>{recipientUserId});
                } catch (Exception e) {
                    // Failed to send calendar notification
                }
            }
        } catch (Exception e) {
            // Error sending calendar staging notifications
        }
    }
    
    /**
     * Create EventRelation records for ALL matched Contacts/Leads
     * 
     * NEW LOGIC: Each MatchResult now contains lists of ALL matched IDs at the successful
     * precedence level (matchedLeadIds, matchedContactIds). We create EventRelations for ALL of them.
     * 
     * @param eventIndexToEventId Map of event index to created Event ID
     * @param eventIndexToAllMatches Map of event index to all match results
     */
    private static void createMultipleEventRelations(
        Map<Integer, Id> eventIndexToEventId,
        Map<Integer, List<AIStagingMatcherService.MatchResult>> eventIndexToAllMatches
    ) {
        List<EventRelation> relations = new List<EventRelation>();
        Set<String> createdRelations = new Set<String>(); // Prevent duplicates
        
        for (Integer idx : eventIndexToEventId.keySet()) {
            Id eventId = eventIndexToEventId.get(idx);
            List<AIStagingMatcherService.MatchResult> allMatches = eventIndexToAllMatches.get(idx);
            
            if (allMatches == null || allMatches.isEmpty()) {
                continue;
            }
            
            for (AIStagingMatcherService.MatchResult match : allMatches) {
                // NEW: Create relations for ALL matched Contacts (from matchedContactIds list)
                if (match.matchedContactIds != null && !match.matchedContactIds.isEmpty()) {
                    for (Id contactId : match.matchedContactIds) {
                        String key = eventId + '-' + contactId;
                        if (!createdRelations.contains(key)) {
                            EventRelation er = new EventRelation();
                            er.EventId = eventId;
                            er.RelationId = contactId;
                            relations.add(er);
                            createdRelations.add(key);
                        }
                    }
                } else if (match.contactId != null) {
                    // Backward compatibility: use single contactId if list is empty
                    String key = eventId + '-' + match.contactId;
                    if (!createdRelations.contains(key)) {
                        EventRelation er = new EventRelation();
                        er.EventId = eventId;
                        er.RelationId = match.contactId;
                        relations.add(er);
                        createdRelations.add(key);
                    }
                }
                
                // NEW: Create relations for ALL matched Leads (from matchedLeadIds list)
                if (match.matchedLeadIds != null && !match.matchedLeadIds.isEmpty()) {
                    for (Id leadId : match.matchedLeadIds) {
                        String key = eventId + '-' + leadId;
                        if (!createdRelations.contains(key)) {
                            EventRelation er = new EventRelation();
                            er.EventId = eventId;
                            er.RelationId = leadId;
                            relations.add(er);
                            createdRelations.add(key);
                        }
                    }
                } else if (match.leadId != null) {
                    // Backward compatibility: use single leadId if list is empty
                    String key = eventId + '-' + match.leadId;
                    if (!createdRelations.contains(key)) {
                        EventRelation er = new EventRelation();
                        er.EventId = eventId;
                        er.RelationId = match.leadId;
                        relations.add(er);
                        createdRelations.add(key);
                    }
                }
                
                // Note: Only Lead and Contact are supported for EventRelation
            }
        }
        
        // Batch insert relations in chunks to avoid DML limits
        if (!relations.isEmpty()) {
            insertEventRelationsInBatches(relations, 50);
        }
    }
    
    /**
     * Insert EventRelation records in batches to avoid hitting DML limits
     * @param relations List of EventRelation records to insert
     * @param batchSize Size of each batch (default 50)
     */
    private static void insertEventRelationsInBatches(List<EventRelation> relations, Integer batchSize) {
        Integer totalSuccess = 0;
        Integer totalFailed = 0;
        
        // Check object-level create permission for EventRelation
        if (!Schema.sObjectType.EventRelation.isCreateable()) {
                return;
        }
        
        for (Integer i = 0; i < relations.size(); i += batchSize) {
            Integer endIdx = Math.min(i + batchSize, relations.size());
            List<EventRelation> batch = new List<EventRelation>();
            for (Integer j = i; j < endIdx; j++) {
                batch.add(relations[j]);
            }
            
            // Use FLSCheck for FLS/OLS enforcement
            List<EventRelation> accessibleBatch = FLSCheck.getInstance().insertCheck(batch);
            
            if (accessibleBatch == null || accessibleBatch.isEmpty()) {
                continue;
            }
            
            Database.SaveResult[] results = Database.insert(accessibleBatch, false);
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    totalSuccess++;
                } else {
                    totalFailed++;
                }
            }
        }
    }
    
    /**
     * Create Event from staging record
     * 
     * Note: We populate standard Event fields plus essential custom fields:
     * - Workspace_Sync_Id__c: For deduplication (unique provider event ID / iCalUID)
     * 
     * This field is critical for deduplication even after Staging records are deleted.
     * All other metadata is on Staging.
     */
    private static Event createEventFromStaging(AI_Workspace_Staging__c staging, AIStagingMatcherService.MatchResult match) {
        Event evt = new Event();
        
        // Standard Event fields
        evt.Subject = staging.Subject__c;
        evt.Description = staging.Text_Body__c;
        evt.StartDateTime = staging.Start_DateTime__c;
        evt.EndDateTime = staging.End_DateTime__c;
        evt.IsAllDayEvent = staging.Is_All_Day__c == true;
        evt.Location = staging.Location__c;
        evt.OwnerId = staging.User__c != null ? staging.User__c : UserInfo.getUserId();
        
        // Set WhoId based on matched record (Contact or Lead)
        if (match.contactId != null) {
            evt.WhoId = match.contactId;
        } else if (match.leadId != null) {
            evt.WhoId = match.leadId;
        }
        
        // Essential custom fields for deduplication
        // These persist even after Staging records are deleted
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Event.fields.getMap();
        
        // Use iCalUID for deduplication (more reliable than provider event ID)
        if (isEventFieldCreateable(fieldMap, 'Workspace_Sync_Id__c')) {
            evt.put('Workspace_Sync_Id__c', staging.ICalUID__c);
        }
        
        return evt;
    }
    
    /**
     * Check if a field exists on Event and is createable
     */
    private static Boolean isEventFieldCreateable(Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        if (!fieldMap.containsKey(fieldName)) {
            return false;
        }
        return fieldMap.get(fieldName).getDescribe().isCreateable();
    }
    
    /**
     * Insert Events and return map of index to created record ID (with FLS enforcement)
     */
    private static Map<Integer, Id> insertEventsInline(List<Event> events) {
        Map<Integer, Id> indexToId = new Map<Integer, Id>();
        
        // Use FLSCheck for FLS/OLS enforcement
        List<Event> accessibleEvents = FLSCheck.getInstance().insertCheck(events);
        
        if (accessibleEvents == null || accessibleEvents.isEmpty()) {
            return indexToId;
        }
        
        Database.SaveResult[] results = Database.insert(accessibleEvents, false);
        
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                indexToId.put(i, results[i].getId());
            }
        }
        
        return indexToId;
    }
    
    /**
     * Create Salesforce Task records from staging records
     * Tasks are created for the current user (OwnerId)
     * @param stagingRecordIds List of task staging record IDs
     * @return MatchingCounts with matched, unmatched, and imported counts
     */
    private static MatchingCounts createTasksFromStagingInline(List<Id> stagingRecordIds) {
        // Default to true for sendNotifications (backwards compatibility)
        return createTasksFromStagingInlineWithEmail(stagingRecordIds, null, true);
    }
    
    /**
     * Create Salesforce Task records from staging records with precedence-based matching
     * Uses the connected user's email to match against Lead/Contact
     * @param stagingRecordIds List of task staging record IDs
     * @param connectedEmail The email address of the connected Outlook/Gmail account (optional)
     * @param sendNotifications Whether to send bell notifications (true for manual, false for auto-sync)
     * @return MatchingCounts with matched, unmatched, and imported counts
     */
    private static MatchingCounts createTasksFromStagingInlineWithEmail(List<Id> stagingRecordIds, String connectedEmail, Boolean sendNotifications) {
        MatchingCounts counts = new MatchingCounts();
        
        if (stagingRecordIds == null || stagingRecordIds.isEmpty()) {
            return counts;
        }
        
        try {
            // Query the task staging records
            List<AI_Workspace_Staging__c> stagingRecords = [
                SELECT Id, Subject__c, Text_Body__c, Due_Date__c, Task_Status__c, Task_Priority__c,
                       Provider__c, Provider_Id__c, User__c, Sync_Log__c
                FROM AI_Workspace_Staging__c
                WHERE Id IN :stagingRecordIds
            ];
            
            if (stagingRecords.isEmpty()) {
                return counts;
            }
            
            // Get the connected email if not provided
            if (String.isBlank(connectedEmail)) {
                connectedEmail = getConnectedUserEmail(stagingRecords[0].Provider__c);
            }
            
            // Perform precedence-based matching using the connected email
            AIStagingMatcherService.MatchResult matchResult = null;
            if (String.isNotBlank(connectedEmail)) {
                // Build cache for the single email
                Set<String> emails = new Set<String>{ connectedEmail.toLowerCase() };
                AIStagingMatcherService.EmailMatchCache cache = AIStagingMatcherService.buildEmailMatchCache(emails);
                matchResult = AIStagingMatcherService.matchEmail(connectedEmail, cache);
            }
            
            List<Task> tasksToCreate = new List<Task>();
            Map<Integer, Id> taskIndexToStagingId = new Map<Integer, Id>();
            Map<Id, Boolean> stagingIdHasMatch = new Map<Id, Boolean>();
            
            // Only create Tasks if there's a matching Contact or Lead
            Boolean hasMatch = (matchResult != null && matchResult.isMatched && 
                               ((matchResult.matchedContactIds != null && !matchResult.matchedContactIds.isEmpty()) ||
                                (matchResult.matchedLeadIds != null && !matchResult.matchedLeadIds.isEmpty()) ||
                                matchResult.contactId != null || matchResult.leadId != null));
            
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                
                // LOGIC:
                // - Manual import (sendNotifications=true): Always create Task WITHOUT automatic WhoId
                //   The linkTasksToRecords method will handle linking to manually selected Contact/Lead
                // - Auto-sync (sendNotifications=false): Only create Task if there's an automatic match, WITH WhoId set
                if (hasMatch || sendNotifications) {
                    Task t;
                    if (hasMatch && !sendNotifications) {
                        // Auto-sync: Create Task with automatic match (WhoId set)
                        t = createTaskFromStagingWithMatch(staging, matchResult);
                        stagingIdHasMatch.put(staging.Id, true);
                    } else {
                        // Manual import: Create Task WITHOUT automatic match (WhoId null) - for manual linking
                        // This ensures the user's manual selections in the modal take full control
                        t = createTaskFromStagingWithMatch(staging, null);
                        stagingIdHasMatch.put(staging.Id, sendNotifications ? true : false);
                    }
                    taskIndexToStagingId.put(tasksToCreate.size(), staging.Id);
                    tasksToCreate.add(t);
                } else {
                    // Auto-sync with no match - mark staging as Unmatched, don't create Task
                    stagingIdHasMatch.put(staging.Id, false);
                    counts.unmatchedCount++;
                }
            }
            
            // Insert Tasks
            if (!tasksToCreate.isEmpty()) {
                Map<Integer, Id> taskIndexToTaskId = insertTasksInline(tasksToCreate);
                
                // Count successfully created Task records
                counts.importedCount = taskIndexToTaskId.size();
                
                // Update staging records with Task reference and mark as Matched/Unmatched
                List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
                
                for (Integer idx : taskIndexToTaskId.keySet()) {
                    Id stagingId = taskIndexToStagingId.get(idx);
                    Id taskId = taskIndexToTaskId.get(idx);
                    
                    if (stagingId != null && taskId != null) {
                        AI_Workspace_Staging__c updateRecord = new AI_Workspace_Staging__c(Id = stagingId);
                        updateRecord.Email_Message__c = String.valueOf(taskId); // Reuse field for linked record
                        // If task was successfully imported, mark as Matched (linked to user)
                        // For tasks, "Matched" means successfully imported and linked, not necessarily to Contact/Lead
                        updateRecord.Status__c = 'Matched';
                        counts.matchedCount++;
                        stagingToUpdate.add(updateRecord);
                    }
                }
                
                // Mark any unprocessed staging records as unmatched
                // (This handles cases where Task insert failed for matched records)
                Set<Id> processedIds = new Set<Id>();
                for (AI_Workspace_Staging__c s : stagingToUpdate) {
                    processedIds.add(s.Id);
                }
                
                for (Id stagingId : stagingRecordIds) {
                    if (!processedIds.contains(stagingId) && stagingIdHasMatch.get(stagingId) == true) {
                        // Task creation failed for a matched record
                        AI_Workspace_Staging__c updateRecord = new AI_Workspace_Staging__c(Id = stagingId);
                        updateRecord.Status__c = 'Unmatched';
                        stagingToUpdate.add(updateRecord);
                        counts.unmatchedCount++;
                    }
                }
                
                // Mark staging records that had no match from the beginning
                for (Id stagingId : stagingRecordIds) {
                    if (stagingIdHasMatch.get(stagingId) == false) {
                        AI_Workspace_Staging__c updateRecord = new AI_Workspace_Staging__c(Id = stagingId);
                        updateRecord.Status__c = 'Unmatched';
                        stagingToUpdate.add(updateRecord);
                        // counts.unmatchedCount already incremented earlier
                    }
                }
                
                if (!stagingToUpdate.isEmpty()) {
                    updateStagingRecordsWithFLS(stagingToUpdate);
                }
                
                // Send notifications only for manual imports (not for auto-sync/scheduler)
                if (sendNotifications) {
                    sendTaskNotifications(stagingRecords, taskIndexToStagingId, taskIndexToTaskId, matchResult);
                }
            }
            
        } catch (Exception e) {
            // Error creating tasks from staging
        }
        
        return counts;
    }
    
    /**
     * Send bell notifications for created tasks
     * @param stagingRecords Original staging records with task data
     * @param taskIndexToStagingId Map of task index to staging record ID
     * @param taskIndexToTaskId Map of task index to created Task ID
     * @param matchResult Match result for the connected user
     */
    private static void sendTaskNotifications(
        List<AI_Workspace_Staging__c> stagingRecords,
        Map<Integer, Id> taskIndexToStagingId,
        Map<Integer, Id> taskIndexToTaskId,
        AIStagingMatcherService.MatchResult matchResult
    ) {
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                return;
            }
            
            CustomNotificationType notifType = notifTypes[0];
            
            // Build a map of staging ID to staging record for easy lookup
            Map<Id, AI_Workspace_Staging__c> stagingMap = new Map<Id, AI_Workspace_Staging__c>(stagingRecords);
            
            // Send notifications for each successfully created task
            for (Integer idx : taskIndexToTaskId.keySet()) {
                Id taskId = taskIndexToTaskId.get(idx);
                Id stagingId = taskIndexToStagingId.get(idx);
                
                // Only send notification if Task was successfully created
                if (taskId == null) continue;
                
                AI_Workspace_Staging__c staging = stagingMap.get(stagingId);
                if (staging == null) continue;
                
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    
                    // Truncate subject for title
                    String subject = staging.Subject__c != null ? staging.Subject__c : '(No Subject)';
                    String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
                    
                    notification.setTitle('✅ Task imported: ' + truncatedSubject);
                    notification.setBody('Task imported successfully.\nClick to view the task.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(taskId); // Always navigate to Task record
                    
                    // Send to the staging record's owner (User__c), not the current running user
                    // This ensures notifications go to the correct user during scheduled syncs
                    Id recipientUserId = staging.User__c != null ? staging.User__c : UserInfo.getUserId();
                    notification.send(new Set<String>{recipientUserId});
                } catch (Exception e) {
                    // Failed to send task notification
                }
            }
        } catch (Exception e) {
            // Error sending task notifications
        }
    }
    
    /**
     * Get the connected user's email based on provider type
     * This is the email of the Outlook/Gmail account used for sync
     */
    private static String getConnectedUserEmail(String providerType) {
        try {
            if (providerType != null && providerType.containsIgnoreCase('GOOGLE')) {
                // Google - use Gmail API
                return getGoogleUserEmail();
            } else {
                // Microsoft - use Graph API
                return getMicrosoftUserEmail();
            }
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Get Microsoft user email from Graph API
     */
    private static String getMicrosoftUserEmail() {
        String accessToken = AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_OUTLOOK);
        if (String.isBlank(accessToken)) {
            return null;
        }
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(AIWorkspaceTokenService.getMicrosoftGraphEndpoint() + '/v1.0/me');
        req.setMethod('GET');
        req.setTimeout(30000);
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> userData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String email = (String) userData.get('mail');
            if (String.isBlank(email)) {
                email = (String) userData.get('userPrincipalName');
            }
            return email;
        }
        return null;
    }
    
    /**
     * Get Google user email from Gmail API
     */
    private static String getGoogleUserEmail() {
        String accessToken = AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_GMAIL);
        if (String.isBlank(accessToken)) {
            return null;
        }
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://www.googleapis.com/oauth2/v2/userinfo');
        req.setMethod('GET');
        req.setTimeout(30000);
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> userData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) userData.get('email');
        }
        return null;
    }
    
    /**
     * Create Salesforce Task from staging record
     * 
     * Note: We populate standard Task fields plus essential custom fields:
     * - Workspace_Sync_Id__c: For deduplication (unique provider task ID)
     * 
     * This field is critical for deduplication even after Staging records are deleted.
     * All other metadata is on Staging.
     */
    private static Task createTaskFromStaging(AI_Workspace_Staging__c staging) {
        return createTaskFromStagingWithMatch(staging, null);
    }
    
    /**
     * Create Salesforce Task from staging record with precedence-based matching
     * Sets WhoId based on matched Lead or Contact from the precedence config.
     * 
     * Salesforce Task WhoId only supports a SINGLE Lead or Contact (no TaskRelation exists).
     * The MatchResult contains IDs based on the precedence config:
     * - If config is {"1": ["Lead"]}, only Lead ID will be present
     * - If config is {"1": ["Contact"]}, only Contact ID will be present
     * - If config is {"1": ["Lead", "Contact"]}, both IDs present - we pick Lead first
     * 
     * @param staging The staging record
     * @param matchResult The match result from precedence-based matching (can be null)
     * @return Task record ready for insertion
     */
    private static Task createTaskFromStagingWithMatch(AI_Workspace_Staging__c staging, AIStagingMatcherService.MatchResult matchResult) {
        Task t = new Task();
        
        // Standard Task fields
        t.Subject = staging.Subject__c;
        t.Description = staging.Text_Body__c;
        t.ActivityDate = staging.Due_Date__c;
        t.OwnerId = staging.User__c != null ? staging.User__c : UserInfo.getUserId();
        
        // Apply precedence-based matching result
        // Link Task to matched Lead or Contact based on precedence config
        // Since Task only supports single WhoId, we take the first available match
        if (matchResult != null && matchResult.isMatched) {
            // Use Lead if available (from precedence match)
            if (matchResult.matchedLeadIds != null && !matchResult.matchedLeadIds.isEmpty()) {
                t.WhoId = matchResult.matchedLeadIds[0];
            } 
            // Otherwise use Contact if available (from precedence match)
            else if (matchResult.matchedContactIds != null && !matchResult.matchedContactIds.isEmpty()) {
                t.WhoId = matchResult.matchedContactIds[0];
            }
            // Fallback to single ID fields for backward compatibility
            else if (matchResult.leadId != null) {
                t.WhoId = matchResult.leadId;
            } else if (matchResult.contactId != null) {
                t.WhoId = matchResult.contactId;
            }
        }
        
        // Map status
        String status = staging.Task_Status__c;
        if (status == 'Completed') {
            t.Status = 'Completed';
        } else if (status == 'In Progress') {
            t.Status = 'In Progress';
        } else {
            t.Status = 'Not Started';
        }
        
        // Map priority
        String priority = staging.Task_Priority__c;
        if (priority == 'High') {
            t.Priority = 'High';
        } else if (priority == 'Low') {
            t.Priority = 'Low';
        } else {
            t.Priority = 'Normal';
        }
        
        // Essential custom fields for deduplication and provider tracking
        // These persist even after Staging records are deleted
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Task.fields.getMap();
        
        if (isTaskFieldCreateable(fieldMap, 'Workspace_Sync_Id__c')) {
            t.put('Workspace_Sync_Id__c', staging.Provider_Id__c);
        }
        
        return t;
    }
    
    /**
     * Check if a field exists on Task and is createable
     */
    private static Boolean isTaskFieldCreateable(Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        if (!fieldMap.containsKey(fieldName)) {
            return false;
        }
        return fieldMap.get(fieldName).getDescribe().isCreateable();
    }
    
    /**
     * Insert Tasks and return map of index to created record ID (with FLS enforcement)
     */
    private static Map<Integer, Id> insertTasksInline(List<Task> tasks) {
        Map<Integer, Id> indexToId = new Map<Integer, Id>();
        
        // Use FLSCheck for FLS/OLS enforcement
        List<Task> accessibleTasks = FLSCheck.getInstance().insertCheck(tasks);
        
        if (accessibleTasks == null || accessibleTasks.isEmpty()) {
            return indexToId;
        }
        
        Database.SaveResult[] results = Database.insert(accessibleTasks, false);
        
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                indexToId.put(i, results[i].getId());
            }
        }
        
        return indexToId;
    }
}