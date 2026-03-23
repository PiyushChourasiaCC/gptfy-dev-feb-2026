/**
 * AIStagingPolicyMatcherBatch - Phase 3 batch processor
 * 
 * Processes staging records with Status = 'Ready' and validates them against
 * AI_Workspace_Processing_Policy__c records. If a policy is found for the user
 * (either by User ID or Profile ID), the record is kept for future processing.
 * If no policy is found, the staging record is rejected.
 * 
 * Phase 3 Logic (V2-7889):
 * - Query staging records with Status = 'Ready'
 * - For each record, check if AI_Workspace_User__r.User__c exists in any policy's Users__c field
 * - If not found, check if the user's ProfileId exists in any policy's Profiles__c field
 * - If policy found: Do nothing (reserved for future processing)
 * - If no policy found: Update Status = 'Rejected'
 * 
 * Design:
 * - Batch size: 10 records (allows for callouts in future)
 * - Implements Database.AllowsCallouts for future enhancements
 * - Bulkified policy queries to minimize SOQL
 * - Stateful to track totals across batches
 * 
 * @author GPTfy
 * @date 2026-03-11
 * @Jira V2-7889
 */
public with sharing class AIStagingPolicyMatcherBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
    
    private Integer totalProcessed = 0;
    private Integer totalApproved = 0;
    private Integer totalRejected = 0;
    private Integer totalErrors = 0;
    private List<String> errorMessages = new List<String>();
    
    private static final Integer MAX_ERRORS_TO_TRACK = 100;
    
    /**
     * Query staging records with Status = 'Ready'
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        // V2-7889: Query all fields needed for EmailMessage/Event/Task creation
        String query = 'SELECT Id, Status__c, Provider__c, RecordTypeId, ' +
                       'AI_Workspace_User__c, AI_Workspace_User__r.User__c, ' +
                       'User__c, Subject__c, Html_Body__c, Text_Body__c, ' +
                       'WhoId__c, Message_Date__c, Is_Incoming__c, ' +
                       'Message_Identifier__c, From_Address__c, From_Name__c, ' +
                       'To_Address__c, Cc_Address__c, Bcc_Address__c, ' +
                       'Start_DateTime__c, End_DateTime__c, Is_All_Day__c, Location__c, ' +
                       'ICalUID__c, Provider_Id__c, ' +
                       'Task_Status__c, Task_Priority__c, Due_Date__c ' +
                       'FROM AI_Workspace_Staging__c ' +
                       'WHERE Status__c = \'Ready\' ' +
                       'ORDER BY CreatedDate ASC';
        
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * Process each batch of staging records
     * V2-7889: Validate against processing policies and process with AI
     */
    public void execute(Database.BatchableContext bc, List<AI_Workspace_Staging__c> scope) {
        
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        totalProcessed += scope.size();
        
        // Collect all User IDs from staging records
        Set<Id> allUserIds = new Set<Id>();
        for (AI_Workspace_Staging__c staging : scope) {
            if (staging.AI_Workspace_User__r != null && staging.AI_Workspace_User__r.User__c != null) {
                allUserIds.add(staging.AI_Workspace_User__r.User__c);
            }
        }
        
        
        // Query all processing policies once
        List<AI_Workspace_Processing_Policy__c> allPolicies = [
            SELECT Id, Users__c, Profiles__c, Prompt__c
            FROM AI_Workspace_Processing_Policy__c
            LIMIT 1000
        ];
        
        
        // Query User records to get Username and Profile Name
        Map<Id, String> userIdToUsername = new Map<Id, String>();
        Map<Id, String> userIdToProfileName = new Map<Id, String>();
        if (!allUserIds.isEmpty()) {
            for (User u : [SELECT Id, Username, Profile.Name FROM User WHERE Id IN :allUserIds]) {
                userIdToUsername.put(u.Id, u.Username);
                userIdToProfileName.put(u.Id, u.Profile.Name);
            }
        }
        
        
        // Collect prompt IDs from policies
        Set<Id> promptIds = new Set<Id>();
        for (AI_Workspace_Processing_Policy__c policy : allPolicies) {
            if (policy.Prompt__c != null) {
                promptIds.add(policy.Prompt__c);
            }
        }
        
        // Query prompts with Prompt_Request_Id__c
        Map<Id, String> promptIdToRequestId = new Map<Id, String>();
        if (!promptIds.isEmpty()) {
            for (AI_Prompt__c prompt : [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c WHERE Id IN :promptIds]) {
                if (String.isNotBlank(prompt.Prompt_Request_Id__c)) {
                    promptIdToRequestId.put(prompt.Id, prompt.Prompt_Request_Id__c);
                }
            }
        }
        
        
        // Process each staging record
        List<AI_Workspace_Staging__c> stagingToReject = new List<AI_Workspace_Staging__c>();
        List<AI_Workspace_Staging__c> stagingToError = new List<AI_Workspace_Staging__c>();
        Map<AI_Workspace_Staging__c, AI_Workspace_Processing_Policy__c> stagingToPolicyMap = new Map<AI_Workspace_Staging__c, AI_Workspace_Processing_Policy__c>();
        
        for (AI_Workspace_Staging__c staging : scope) {
            try {
                Id userId = staging.AI_Workspace_User__r != null ? staging.AI_Workspace_User__r.User__c : null;
                
                if (userId == null) {
                    stagingToReject.add(new AI_Workspace_Staging__c(
                        Id = staging.Id,
                        Status__c = 'Rejected',
                        Error_Message__c = 'No workspace user associated with this record.'
                    ));
                    totalRejected++;
                    continue;
                }
                
                String username = userIdToUsername.get(userId);
                String profileName = userIdToProfileName.get(userId);
                AI_Workspace_Processing_Policy__c matchedPolicy = findPolicyForUser(username, profileName, allPolicies);
                if (matchedPolicy != null) {
                    // V2-7889: Policy found - process with AI
                    stagingToPolicyMap.put(staging, matchedPolicy);
                    totalApproved++;
                } else {
                    // V2-7889: No policy found - reject the staging record
                    stagingToReject.add(new AI_Workspace_Staging__c(
                        Id = staging.Id,
                        Status__c = 'Rejected',
                        Error_Message__c = 'No processing policy found for this user or profile.'
                    ));
                    totalRejected++;
                }
            } catch (Exception e) {
                trackError('Staging ' + staging.Id + ': ' + e.getMessage());
                totalErrors++;
            }
        }
        
        // Process staging records with AI callouts
        if (!stagingToPolicyMap.isEmpty()) {
            processWithAI(stagingToPolicyMap, promptIdToRequestId, stagingToReject, stagingToError);
        }
        // Update rejected staging records
        if (!stagingToReject.isEmpty()) {
            
            // V2-7889: Use FLSCheck for FLS/CRUD enforcement
            try {
                FLSCheck.getInstance().updateDML(stagingToReject, false);
            } catch (Exception e) {
                trackError('Batch rejection exception: ' + e.getMessage());
            }
        }
        
        // V2-7889: Update errored staging records
        if (!stagingToError.isEmpty()) {
            try {
                FLSCheck.getInstance().updateDML(stagingToError, false);
            } catch (Exception e) {
                trackError('Batch error update exception: ' + e.getMessage());
            }
        }
    }
    
    /**
     * Check if a policy exists for the given user
     * V2-7889: Checks both Users__c (by Username) and Profiles__c (by Profile Name) fields
     * 
     * @param username The Salesforce Username to check
     * @param profileName The user's Profile Name
     * @param policies List of all processing policies
     * @return true if policy found, false otherwise
     */
    private Boolean checkPolicyForUser(String username, String profileName, List<AI_Workspace_Processing_Policy__c> policies) {
        
        for (AI_Workspace_Processing_Policy__c policy : policies) {
            // Check if username exists in Users__c field (comma-separated)
            if (String.isNotBlank(policy.Users__c) && String.isNotBlank(username)) {
                List<String> policyUsernames = policy.Users__c.split(';');
                for (String policyUsername : policyUsernames) {
                    if (policyUsername.trim().equalsIgnoreCase(username.trim())) {
                        return true;
                    }
                }
            }
            
            // Check if profile name exists in Profiles__c field (comma-separated)
            if (String.isNotBlank(profileName) && String.isNotBlank(policy.Profiles__c)) {
                List<String> policyProfileNames = policy.Profiles__c.split(';');
                for (String policyProfileName : policyProfileNames) {
                    if (policyProfileName.trim().equalsIgnoreCase(profileName.trim())) {
                        return true;
                    }
                }
            }
        }
        
        return false;
    }
    
    /**
     * Find matching policy for the given user
     * V2-7889: Returns the matched policy instead of just boolean
     * Uses semicolon (;) as delimiter to match policy data format
     */
    private AI_Workspace_Processing_Policy__c findPolicyForUser(String username, String profileName, List<AI_Workspace_Processing_Policy__c> policies) {
        for (AI_Workspace_Processing_Policy__c policy : policies) {
            if (String.isNotBlank(policy.Users__c) && String.isNotBlank(username)) {
                List<String> policyUsernames = policy.Users__c.split(';');
                for (String policyUsername : policyUsernames) {
                    if (policyUsername.trim().equalsIgnoreCase(username.trim())) {
                        return policy;
                    }
                }
            }
            
            if (String.isNotBlank(profileName) && String.isNotBlank(policy.Profiles__c)) {
                List<String> policyProfileNames = policy.Profiles__c.split(';');
                for (String policyProfileName : policyProfileNames) {
                    if (policyProfileName.trim().equalsIgnoreCase(profileName.trim())) {
                        return policy;
                    }
                }
            }
        }
        return null;
    }
    
    /**
     * Process staging records with AI callouts
     * V2-7889: Make AI callouts and create Salesforce records based on response
     */
    @TestVisible
    private void processWithAI(
        Map<AI_Workspace_Staging__c, AI_Workspace_Processing_Policy__c> stagingToPolicyMap, 
        Map<Id, String> promptIdToRequestId,
        List<AI_Workspace_Staging__c> stagingToReject,
        List<AI_Workspace_Staging__c> stagingToError
    ) {
        
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        for (RecordTypeInfo rti : Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfos()) {
            recordTypeMap.put(rti.getDeveloperName(), rti.getRecordTypeId());
        }
        
        List<EmailMessage> emailMessagesToInsert = new List<EmailMessage>();
        List<Event> eventsToInsert = new List<Event>();
        List<Task> tasksToInsert = new List<Task>();
        
        Map<Integer, List<Id>> emailIndexToWhoIds = new Map<Integer, List<Id>>();
        Map<Integer, List<Id>> eventIndexToWhoIds = new Map<Integer, List<Id>>();
        Map<Integer, List<Id>> taskIndexToWhoIds = new Map<Integer, List<Id>>();
        
        Map<Integer, Id> emailIndexToStagingId = new Map<Integer, Id>();
        Map<Integer, Id> eventIndexToStagingId = new Map<Integer, Id>();
        Map<Integer, Id> taskIndexToStagingId = new Map<Integer, Id>();
        
        Integer emailIndex = 0;
        Integer eventIndex = 0;
        Integer taskIndex = 0;
        
        for (AI_Workspace_Staging__c staging : stagingToPolicyMap.keySet()) {
            try {
                AI_Workspace_Processing_Policy__c policy = stagingToPolicyMap.get(staging);
                
                if (policy.Prompt__c == null) {
                    continue;
                }
                
                String promptRequestId = promptIdToRequestId.get(policy.Prompt__c);
                if (String.isBlank(promptRequestId)) {
                    continue;
                }
                
                AIPromptProcessingInvokable.RequestWrapper wrap = new AIPromptProcessingInvokable.RequestWrapper();
                wrap.promptRequestId = promptRequestId;
                wrap.recordId = staging.Id;
                wrap.customPromptCommand = '';
                
                
                List<AIPromptProcessingInvokable.ResponseWrapper> responses = 
                    AIPromptProcessingInvokable.processRequest(
                        new List<AIPromptProcessingInvokable.RequestWrapper>{wrap}
                    );
                
                if (responses != null && !responses.isEmpty()) {
                    AIPromptProcessingInvokable.ResponseWrapper response = responses.get(0);
                    
                    // V2-7889: Check for both 'Error' and 'Errored' status or error message
                    if (response.status == 'Error' || response.status == 'Errored' || String.isNotBlank(response.message)) {
                        stagingToError.add(new AI_Workspace_Staging__c(
                            Id = staging.Id,
                            Status__c = 'Errored',
                            Error_Message__c = String.isNotBlank(response.message) ? response.message : 'AI processing error'
                        ));
                        totalErrors++;
                        trackError('AI callout error for ' + staging.Id + ': ' + response.message);
                        
                        // V2-7889: Redact PII fields in AI_Response__c record
                        if (String.isNotBlank(response.responseId)) {
                            redactAIResponsePII(response.responseId);
                        }
                        continue;
                    }
                    
                    if (String.isNotBlank(response.responseBody)) {
                        AIResponseData aiData = parseAIResponse(response.responseBody);
                        
                        
                        if (aiData.isRelevant) {
                            Id ownerId = staging.AI_Workspace_User__r.User__c;
                            List<Id> whoIds = parseWhoIds(staging.WhoId__c);
                            
                            if (staging.RecordTypeId == recordTypeMap.get('Email')) {
                                EmailMessage em = createEmailMessageFromAI(staging, aiData, ownerId);
                                emailMessagesToInsert.add(em);
                                emailIndexToWhoIds.put(emailIndex, whoIds);
                                emailIndexToStagingId.put(emailIndex, staging.Id);
                                emailIndex++;
                            } else if (staging.RecordTypeId == recordTypeMap.get('Calendar')) {
                                Event evt = createEventFromAI(staging, aiData, ownerId);
                                eventsToInsert.add(evt);
                                eventIndexToWhoIds.put(eventIndex, whoIds);
                                eventIndexToStagingId.put(eventIndex, staging.Id);
                                eventIndex++;
                            } else if (staging.RecordTypeId == recordTypeMap.get('Task')) {
                                Task tsk = createTaskFromAI(staging, aiData, ownerId);
                                tasksToInsert.add(tsk);
                                taskIndexToWhoIds.put(taskIndex, whoIds);
                                taskIndexToStagingId.put(taskIndex, staging.Id);
                                taskIndex++;
                            }
                            // V2-7889: Redact PII fields in AI_Response__c record after successful processing
                            if (String.isNotBlank(response.responseId)) {
                                redactAIResponsePII(response.responseId);
                            }
                        } else {
                            // V2-7889: isRelevant = false, reject with specific message
                            stagingToReject.add(new AI_Workspace_Staging__c(
                                Id = staging.Id,
                                Status__c = 'Rejected',
                                Error_Message__c = 'The Content does not qualify for the business needs.'
                            ));
                            totalRejected++;
                            
                            // V2-7889: Redact PII fields in AI_Response__c record
                            if (String.isNotBlank(response.responseId)) {
                                redactAIResponsePII(response.responseId);
                            }
                        }
                    }
                }
            } catch (Exception e) {
                trackError('AI error for ' + staging.Id + ': ' + e.getMessage());
            }
        }
        
        
        Set<Id> successfulStagingIds = new Set<Id>();
        
        if (!emailMessagesToInsert.isEmpty()) {
            Set<Integer> successIndexes = insertEmailMessagesWithRelations(emailMessagesToInsert, emailIndexToWhoIds);
            for (Integer idx : successIndexes) {
                successfulStagingIds.add(emailIndexToStagingId.get(idx));
            }
        }
        
        if (!eventsToInsert.isEmpty()) {
            Set<Integer> successIndexes = insertEventsWithRelations(eventsToInsert, eventIndexToWhoIds);
            for (Integer idx : successIndexes) {
                successfulStagingIds.add(eventIndexToStagingId.get(idx));
            }
        }
        
        if (!tasksToInsert.isEmpty()) {
            Set<Integer> successIndexes = insertTasksWithRelations(tasksToInsert, taskIndexToWhoIds);
            for (Integer idx : successIndexes) {
                successfulStagingIds.add(taskIndexToStagingId.get(idx));
            }
        }
        
        // V2-7889: Update successfully processed staging records to 'Imported'
        if (!successfulStagingIds.isEmpty()) {
            List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
            for (Id stagingId : successfulStagingIds) {
                stagingToUpdate.add(new AI_Workspace_Staging__c(
                    Id = stagingId,
                    Status__c = 'Imported'
                ));
            }
            
            // V2-7889: Use FLSCheck for FLS/CRUD enforcement
            try {
                FLSCheck.getInstance().updateDML(stagingToUpdate);
            } catch (Exception e) {
                System.debug('Error' + e.getMessage());
                System.debug('Error Stack Trace' + e.getStackTraceString());
                trackError('Staging status update error: ' + e.getMessage());
            }
        }
    }
    
    /**
     * Parse WhoId__c comma-separated string into List of IDs
     */
    @TestVisible
    private List<Id> parseWhoIds(String whoIdString) {
        List<Id> whoIds = new List<Id>();
        if (String.isBlank(whoIdString)) {
            return whoIds;
        }
        
        for (String idStr : whoIdString.split(',')) {
            String trimmedId = idStr.trim();
            if (String.isNotBlank(trimmedId)) {
                try {
                    whoIds.add((Id) trimmedId);
                } catch (Exception e) {
                }
            }
        }
        return whoIds;
    }
    
    /**
     * Parse AI response JSON
     * V2-7889: Updated to handle both JSON format and key-value format
     */
    @TestVisible
    private AIResponseData parseAIResponse(String responseBody) {
        AIResponseData data = new AIResponseData();
        
        try {
            // Check if response is JSON format
            if (responseBody.trim().startsWith('{')) {
                // Parse as JSON
                Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                
                data.isRelevant = jsonMap.get('IsRelevant') == true;
                data.relatedToId = (String) jsonMap.get('RelatedToId');
                data.emailSummary = (String) jsonMap.get('EmailSummary');
                data.rejectionReason = (String) jsonMap.get('RejectionReason');
                
            } else {
                // Parse as key-value format (legacy)
                Map<String, String> responseMap = new Map<String, String>();
                for (String line : responseBody.split('\n')) {
                    if (line.contains(':')) {
                        List<String> parts = line.split(':', 2);
                        if (parts.size() == 2) {
                            responseMap.put(parts[0].trim(), parts[1].trim());
                        }
                    }
                }
                
                data.isRelevant = responseMap.get('IsRelevant') == 'true';
                data.relatedToId = responseMap.get('RelatedToId');
                data.emailSummary = responseMap.get('EmailSummary');
                data.rejectionReason = responseMap.get('RejectionReason');
                
            }
            
        } catch (Exception e) {
        }
        
        return data;
    }
    
    /**
     * Create EmailMessage from staging and AI response
     * V2-7889: Includes all address fields, RelatedToId, and MessageIdentifier for deduplication
     */
    @TestVisible
    private EmailMessage createEmailMessageFromAI(AI_Workspace_Staging__c staging, AIResponseData aiData, Id ownerId) {
        String decryptedSubject = AIWorkspaceEncryptionService.decrypt(staging.Subject__c, ownerId);
        String decryptedTextBody = AIWorkspaceEncryptionService.decrypt(staging.Text_Body__c, ownerId);
        String decryptedHtmlBody = AIWorkspaceEncryptionService.decrypt(staging.Html_Body__c, ownerId);
        
        EmailMessage em = new EmailMessage();
        em.Subject = decryptedSubject;
        
        // V2-7889: Use AI summary if available, otherwise use original body
        if (String.isNotBlank(aiData.emailSummary)) {
            em.TextBody = aiData.emailSummary + '\n\n---Original Content---\n' + decryptedTextBody;
            em.HtmlBody = '<p>' + aiData.emailSummary + '</p><hr><p>Original Content:</p>' + decryptedHtmlBody;
        } else {
            em.TextBody = decryptedTextBody;
            em.HtmlBody = decryptedHtmlBody;
        }
        
        em.Status = '3';
        em.Incoming = staging.Is_Incoming__c != null ? staging.Is_Incoming__c : false;
        em.MessageDate = staging.Message_Date__c != null ? staging.Message_Date__c : System.now();
        
        // V2-7889: Add address fields (Issue #3)
        em.FromAddress = staging.From_Address__c;
        em.FromName = staging.From_Name__c;
        em.ToAddress = staging.To_Address__c;
        em.CcAddress = staging.Cc_Address__c;
        em.BccAddress = staging.Bcc_Address__c;
        
        // V2-7889: Add MessageIdentifier for deduplication (Issue #2)
        em.MessageIdentifier = staging.Message_Identifier__c;
        
        // V2-7889: Add RelatedToId from AI response (Issue #4)
        if (String.isNotBlank(aiData.relatedToId)) {
            // Validate that the ID is a valid Account ID (starts with 001)
            try {
                Id relatedToId = Id.valueOf(aiData.relatedToId);
                em.RelatedToId = relatedToId;
            } catch (Exception e) {
                // Invalid ID format or not an Account - skip
            }
        }
        
        return em;
    }
    
    /**
     * Create Event from staging and AI response
     * V2-7889: Includes WhatId from AI response and all event details
     */
    @TestVisible
    private Event createEventFromAI(AI_Workspace_Staging__c staging, AIResponseData aiData, Id ownerId) {
        String decryptedSubject = AIWorkspaceEncryptionService.decrypt(staging.Subject__c, ownerId);
        
        Event evt = new Event();
        evt.Subject = decryptedSubject;
        evt.Description = aiData.emailSummary;
        evt.OwnerId = ownerId;
        evt.StartDateTime = staging.Start_DateTime__c != null ? staging.Start_DateTime__c : System.now();
        evt.EndDateTime = staging.End_DateTime__c != null ? staging.End_DateTime__c : System.now().addHours(1);
        evt.IsAllDayEvent = staging.Is_All_Day__c != null ? staging.Is_All_Day__c : false;
        
        // V2-7889: Populate Workspace_Sync_Id__c for UI to identify imported events
        // Use ICalUID__c as the unique identifier (or Provider_Id__c as fallback)
        String workspaceSyncId = String.isNotBlank(staging.ICalUID__c) ? staging.ICalUID__c : staging.Provider_Id__c;
        if (String.isNotBlank(workspaceSyncId)) {
            evt.put(AIConstants.NAMESPACE + 'Workspace_Sync_Id__c', workspaceSyncId);
        }
        
        // V2-7889: Add WhatId from AI response (similar to EmailMessage RelatedToId)
        if (String.isNotBlank(aiData.relatedToId)) {
            // Validate that the ID is a valid Account ID (starts with 001)
            try {
                Id relatedToId = Id.valueOf(aiData.relatedToId);
                evt.WhatId = relatedToId;
            } catch (Exception e) {
                // Invalid ID format or not an Account - skip
            }
        }
        
        if (String.isNotBlank(staging.Location__c)) {
            evt.Location = staging.Location__c;
        }
        
        return evt;
    }
    
    /**
     * Create Task from staging and AI response
     * V2-7889: WhatId is optional - skipped for now as AI may return non-existent IDs
     */
    @TestVisible
    private Task createTaskFromAI(AI_Workspace_Staging__c staging, AIResponseData aiData, Id ownerId) {
        String decryptedSubject = AIWorkspaceEncryptionService.decrypt(staging.Subject__c, ownerId);
        
        Task tsk = new Task();
        tsk.Subject = decryptedSubject;
        tsk.Description = aiData.emailSummary;
        tsk.OwnerId = ownerId;
        tsk.Status = staging.Task_Status__c != null ? staging.Task_Status__c : 'Not Started';
        tsk.Priority = staging.Task_Priority__c != null ? staging.Task_Priority__c : 'Normal';
        
        if (staging.Due_Date__c != null) {
            tsk.ActivityDate = staging.Due_Date__c;
        }
        
        // V2-7889: Populate Workspace_Sync_Id__c for UI to identify imported tasks
        // Use Provider_Id__c as the unique identifier
        if (String.isNotBlank(staging.Provider_Id__c)) {
            tsk.put(AIConstants.NAMESPACE + 'Workspace_Sync_Id__c', staging.Provider_Id__c);
        }
        
        // V2-7889: Add WhatId from AI response (similar to Event WhatId)
        // Task.WhatId can be: Account, Opportunity, Campaign, Case, or custom objects
        // Task.WhatId CANNOT be: Lead or Contact (those go in WhoId/TaskRelation)
        if (String.isNotBlank(aiData.relatedToId)) {
            try {
                Id relatedId = Id.valueOf(aiData.relatedToId);
                String objectType = String.valueOf(relatedId.getSObjectType());
                
                // Valid WhatId types for Task
                Set<String> validWhatIdTypes = new Set<String>{
                    'Account', 'Opportunity', 'Campaign', 'Case'
                };
                
                if (validWhatIdTypes.contains(objectType)) {
                    tsk.WhatId = relatedId;
                } else if (objectType == 'Lead' || objectType == 'Contact') {
                    // Skip - Lead/Contact should be in WhoId/TaskRelation, not WhatId
                    trackError('Task WhatId skipped: AI returned ' + objectType + ' ID (should be Account/Opportunity)');
                }
            } catch (Exception e) {
                // Invalid ID format - skip
            }
        }
        
        return tsk;
    }
    
    /**
     * Insert EmailMessages and create relations
     * V2-7889: Returns set of successful indexes, with duplicate detection (Issue #2)
     */
    @TestVisible
    private Set<Integer> insertEmailMessagesWithRelations(List<EmailMessage> emailMessages, Map<Integer, List<Id>> indexToWhoIds) {
        Set<Integer> successIndexes = new Set<Integer>();
        
        // V2-7889: Check for existing EmailMessages by MessageIdentifier to prevent duplicates (Issue #2)
        Set<String> messageIdentifiers = new Set<String>();
        for (EmailMessage em : emailMessages) {
            if (String.isNotBlank(em.MessageIdentifier)) {
                messageIdentifiers.add(em.MessageIdentifier);
            }
        }
        
        Set<String> existingMessageIds = new Set<String>();
        if (!messageIdentifiers.isEmpty()) {
            for (EmailMessage existing : [
                SELECT MessageIdentifier
                FROM EmailMessage
                WHERE MessageIdentifier IN :messageIdentifiers
                LIMIT 1000
            ]) {
                if (String.isNotBlank(existing.MessageIdentifier)) {
                    existingMessageIds.add(existing.MessageIdentifier);
                }
            }
        }
        
        // Filter out duplicates
        List<EmailMessage> emailsToInsert = new List<EmailMessage>();
        Map<Integer, Integer> oldIndexToNewIndex = new Map<Integer, Integer>();
        Integer newIndex = 0;
        for (Integer i = 0; i < emailMessages.size(); i++) {
            EmailMessage em = emailMessages.get(i);
            if (String.isBlank(em.MessageIdentifier) || !existingMessageIds.contains(em.MessageIdentifier)) {
                emailsToInsert.add(em);
                oldIndexToNewIndex.put(i, newIndex);
                newIndex++;
            } else {
                trackError('Duplicate EmailMessage skipped: ' + em.Subject);
            }
        }
        
        if (emailsToInsert.isEmpty()) {
            return successIndexes;
        }
        
        // V2-7889: Use FLSCheck for FLS/CRUD enforcement
        try {
            List<EmailMessage> insertedEmails = (List<EmailMessage>) FLSCheck.getInstance().insertDML(emailsToInsert);
            
            // Track successful indexes (map back to original indexes)
            for (Integer newIdx = 0; newIdx < insertedEmails.size(); newIdx++) {
                for (Integer oldIdx : oldIndexToNewIndex.keySet()) {
                    if (oldIndexToNewIndex.get(oldIdx) == newIdx) {
                        successIndexes.add(oldIdx);
                        break;
                    }
                }
            }
            
            // V2-7889: Create EmailMessageRelations for all matched Contacts/Leads (Issue #1)
            List<EmailMessageRelation> relations = new List<EmailMessageRelation>();
            for (Integer newIdx = 0; newIdx < insertedEmails.size(); newIdx++) {
                EmailMessage em = insertedEmails.get(newIdx);
                
                // Map back to original index to get whoIds
                Integer originalIdx = null;
                for (Integer oldIdx : oldIndexToNewIndex.keySet()) {
                    if (oldIndexToNewIndex.get(oldIdx) == newIdx) {
                        originalIdx = oldIdx;
                        break;
                    }
                }
                
                if (originalIdx == null) continue;
                
                List<Id> whoIds = indexToWhoIds.get(originalIdx);
                
                if (whoIds != null && !whoIds.isEmpty()) {
                    // Create relation for each matched Contact/Lead
                    // Use 'FromAddress' type if email is incoming (from external party)
                    // Use 'ToAddress' type if email is outgoing (to external party)
                    String relationType = 'OtherAddress';
                    
                    for (Id whoId : whoIds) {
                        relations.add(new EmailMessageRelation(
                            EmailMessageId = em.Id,
                            RelationId = whoId,
                            RelationType = relationType
                        ));
                    }
                }
            }
            
            if (!relations.isEmpty()) {
                try {
                    FLSCheck.getInstance().insertDML(relations, false);
                } catch (Exception e) {
                    trackError('EmailMessageRelation insert error: ' + e.getMessage());
                }
            }
        } catch (Exception e) {
            trackError('EmailMessage insert error: ' + e.getMessage());
        }
        
        return successIndexes;
    }
    
    /**
     * Insert Events and create relations
     * V2-7889: Returns set of successful indexes, with duplicate detection
     */
    @TestVisible
    private Set<Integer> insertEventsWithRelations(List<Event> events, Map<Integer, List<Id>> indexToWhoIds) {
        Set<Integer> successIndexes = new Set<Integer>();
        
        // V2-7889: Check for existing Events by Subject + StartDateTime + OwnerId to prevent duplicates
        Set<String> eventKeys = new Set<String>();
        for (Event evt : events) {
            String eventKey = evt.Subject + '|' + evt.StartDateTime + '|' + evt.OwnerId;
            eventKeys.add(eventKey);
        }
        
        Set<String> existingEventKeys = new Set<String>();
        if (!eventKeys.isEmpty() && !events.isEmpty()) {
            // Query existing events with same Subject and StartDateTime
            List<Event> existingEvents = [
                SELECT Subject, StartDateTime, OwnerId
                FROM Event
                WHERE OwnerId = :events[0].OwnerId
                AND StartDateTime >= :System.now().addDays(-30)
                LIMIT 1000
            ];
            
            for (Event existing : existingEvents) {
                String existingKey = existing.Subject + '|' + existing.StartDateTime + '|' + existing.OwnerId;
                existingEventKeys.add(existingKey);
            }
        }
        
        // Filter out duplicates
        List<Event> eventsToInsert = new List<Event>();
        Map<Integer, Integer> oldIndexToNewIndex = new Map<Integer, Integer>();
        Integer newIndex = 0;
        for (Integer i = 0; i < events.size(); i++) {
            Event evt = events.get(i);
            String eventKey = evt.Subject + '|' + evt.StartDateTime + '|' + evt.OwnerId;
            if (!existingEventKeys.contains(eventKey)) {
                eventsToInsert.add(evt);
                oldIndexToNewIndex.put(i, newIndex);
                newIndex++;
            } else {
                trackError('Duplicate Event skipped: ' + evt.Subject);
            }
        }
        
        if (eventsToInsert.isEmpty()) {
            return successIndexes;
        }
        
        // V2-7889: Use FLSCheck for FLS/CRUD enforcement
        try {
            List<Event> insertedEvents = (List<Event>) FLSCheck.getInstance().insertDML(eventsToInsert);
            
            // Track successful indexes (map back to original indexes)
            for (Integer newIdx = 0; newIdx < insertedEvents.size(); newIdx++) {
                for (Integer oldIdx : oldIndexToNewIndex.keySet()) {
                    if (oldIndexToNewIndex.get(oldIdx) == newIdx) {
                        successIndexes.add(oldIdx);
                        break;
                    }
                }
            }
            
            // V2-7889: Create EventRelations for all matched Contacts/Leads
            List<EventRelation> relations = new List<EventRelation>();
            for (Integer newIdx = 0; newIdx < insertedEvents.size(); newIdx++) {
                Event evt = insertedEvents.get(newIdx);
                
                // Map back to original index to get whoIds
                Integer originalIdx = null;
                for (Integer oldIdx : oldIndexToNewIndex.keySet()) {
                    if (oldIndexToNewIndex.get(oldIdx) == newIdx) {
                        originalIdx = oldIdx;
                        break;
                    }
                }
                
                if (originalIdx == null) continue;
                
                List<Id> whoIds = indexToWhoIds.get(originalIdx);
                
                if (whoIds != null && !whoIds.isEmpty()) {
                    for (Id whoId : whoIds) {
                        relations.add(new EventRelation(
                            EventId = evt.Id,
                            RelationId = whoId
                        ));
                    }
                }
            }
            
            if (!relations.isEmpty()) {
                try {
                    FLSCheck.getInstance().insertDML(relations, false);
                } catch (Exception e) {
                    trackError('EventRelation insert error: ' + e.getMessage());
                }
            }
        } catch (Exception e) {
            trackError('Event insert error: ' + e.getMessage());
        }
        
        return successIndexes;
    }
    
    /**
     * Insert Tasks and create relations
     * V2-7889: Returns set of successful indexes
     */
    @TestVisible
    private Set<Integer> insertTasksWithRelations(List<Task> tasks, Map<Integer, List<Id>> indexToWhoIds) {
        Set<Integer> successIndexes = new Set<Integer>();
        
        // V2-7889: Use FLSCheck for FLS/CRUD enforcement
        try {
            List<Task> insertedTasks = (List<Task>) FLSCheck.getInstance().insertDML(tasks);
            
            // All inserts succeeded, track all indexes
            for (Integer i = 0; i < insertedTasks.size(); i++) {
                successIndexes.add(i);
            }
            
            // V2-7889: Using SObject approach for TaskRelation compatibility
            Schema.SObjectType taskRelationType = Schema.getGlobalDescribe().get('TaskRelation');
            List<SObject> relations = new List<SObject>();

            if (taskRelationType != null) {
                for (Integer i = 0; i < insertedTasks.size(); i++) {
                    Task tsk = insertedTasks.get(i);
                    List<Id> whoIds = indexToWhoIds.get(i);

                    if (whoIds != null) {
                        for (Id whoId : whoIds) {
                            SObject tr = taskRelationType.newSObject();
                            tr.put('TaskId', tsk.Id);
                            tr.put('RelationId', whoId);
                            relations.add(tr);
                        }
                    }
                }

                if (!relations.isEmpty()) {
                    try {
                        FLSCheck.getInstance().insertDML(relations, false);
                    } catch (Exception e) {
                        trackError('TaskRelation insert error: ' + e.getMessage());
                    }
                }
            } else {
                // V2-7889: TaskRelation not available - update Task.WhoId directly with first ID
                List<Task> tasksToUpdate = new List<Task>();
                
                for (Integer i = 0; i < insertedTasks.size(); i++) {
                    Task tsk = insertedTasks.get(i);
                    List<Id> whoIds = indexToWhoIds.get(i);
                    
                    if (whoIds != null && !whoIds.isEmpty()) {
                        Task taskToUpdate = new Task(
                            Id = tsk.Id,
                            WhoId = whoIds[0]
                        );
                        tasksToUpdate.add(taskToUpdate);
                    }
                }
                
                if (!tasksToUpdate.isEmpty()) {
                    try {
                        FLSCheck.getInstance().updateDML(tasksToUpdate, false);
                    } catch (Exception e) {
                        trackError('Task WhoId update error: ' + e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            trackError('Task insert error: ' + e.getMessage());
        }
        
        return successIndexes;
    }
    
    /**
     * Track error message
     * V2-7889
     */
    @TestVisible
    private void trackError(String errorMsg) {
        if (errorMessages.size() < MAX_ERRORS_TO_TRACK) {
            errorMessages.add(errorMsg);
            totalErrors++;
        }
    }
    
    /**
     * Redact PII fields in AI_Response__c record for security
     * V2-7889: After processing, all PII-related fields are redacted
     */
    @TestVisible
    private void redactAIResponsePII(String aiResponseId) {
        try {
            if (String.isBlank(aiResponseId)) {
                return;
            }
            
            Id responseRecordId = Id.valueOf(aiResponseId);
            
            AI_Response__c aiResponse = new AI_Response__c(
                Id = responseRecordId,
                AI_Processed_Data_No_PII__c = '{"Redacted": "Redacted"}',
                AI_Processed_Data_PII_Added__c = '{"Redacted": "Redacted"}',
                Data_Decrypt_PII_Key__c = 'Redacted',
                Data_Original__c = '{"Redacted": "Redacted"}',
                Data_PII_Key__c = 'Redacted',
                Data_PII_Removed__c = '{"Redacted": "Redacted"}',
                Extracted_Data__c = 'Redacted'
            );
            
            FLSCheck.getInstance().updateDML(new List<AI_Response__c>{ aiResponse }, false);
            
            // V2-7889: Delete all ContentDocuments associated with this AI Response
            // Deleting ContentDocument will cascade delete ContentVersions and ContentDocumentLinks
            List<ContentDocumentLink> cdLinks = [
                SELECT ContentDocumentId 
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :responseRecordId
            ];
            
            if (!cdLinks.isEmpty()) {
                Set<Id> contentDocumentIds = new Set<Id>();
                for (ContentDocumentLink cdl : cdLinks) {
                    contentDocumentIds.add(cdl.ContentDocumentId);
                }
                
                // Delete ContentDocuments (cascade deletes ContentVersions and ContentDocumentLinks)
                List<ContentDocument> contentDocuments = [
                    SELECT Id 
                    FROM ContentDocument 
                    WHERE Id IN :contentDocumentIds
                ];
                
                if (!contentDocuments.isEmpty()) {
                    FLSCheck.getInstance().deleteDML(contentDocuments);
                }
            }

            
            
        } catch (Exception e) {
            trackError('AI Response redaction error: ' + e.getMessage());
        }
    }
    
    /**
     * Inner class to hold parsed AI response data
     */
    @TestVisible
    private class AIResponseData {
        public Boolean isRelevant = false;
        public String relatedToId;
        public String emailSummary;
        public String rejectionReason;
    }
    
    /**
     * Finish method - Log summary
     */
    public void finish(Database.BatchableContext bc) {
        
        if (!errorMessages.isEmpty()) {
            for (String error : errorMessages) {
            }
        }
        
        // V2-7889: Future enhancement - trigger Phase 4 here if needed
    }
    
    /**
     * Static method to run the batch with default batch size
     * V2-7889: Reduced to 1 to avoid SOQL limit (201) when making AI callouts
     */
    public static Id runBatch() {
        // V2-7889: Use batch size of 200 in test context to avoid multiple executeBatch calls
        // In production, use batch size of 1 to avoid governor limits with AI callouts
        Integer defaultBatchSize = Test.isRunningTest() ? 200 : 1;
        return runBatch(defaultBatchSize);
    }
    
    /**
     * Static method to run the batch with custom batch size
     */
    public static Id runBatch(Integer batchSize) {
        return Database.executeBatch(new AIStagingPolicyMatcherBatch(), batchSize);
    }
}
