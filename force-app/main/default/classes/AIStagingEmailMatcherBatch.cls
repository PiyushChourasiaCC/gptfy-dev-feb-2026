/**
 * AIStagingEmailMatcherBatch - Phase 2 batch processor for matching ALL staging records to Lead/Contact
 * V2-7889: Unified batch that processes Email, Calendar, and Task staging records
 * 
 * Processes ALL staged records (Status = 'Staged'), matches to Lead/Contact using configurable
 * precedence rules, populates WhoId__c with comma-separated matched IDs, and marks as 'Ready'.
 * If no match is found (WhoId__c is empty), the staging record is DELETED.
 * 
 * Phase 2 Logic (V2-7889):
 * - Query ALL staging records with Status = 'Staged' (Email, Calendar, Task)
 * - Match based on record type:
 *   - Email: Uses From_Address__c, To_Address__c, Cc_Address__c
 *   - Calendar: Uses Organizer__c, Attendees__c
 *   - Task: Uses connected account email
 * - Populate WhoId__c with comma-separated Contact/Lead IDs based on precedence
 * - If matched (WhoId__c populated): Status = 'Ready'
 * - If not matched (WhoId__c empty): DELETE the staging record
 * 
 * Precedence Logic:
 * - Follows Sync_Precedence__c from AI_Workspace_Sync_Settings__c
 * - Default: Try both Lead & Contact, then Lead only, then Contact only
 * - Example: {"1": ["Lead", "Contact"], "2": ["Lead"], "3": ["Contact"]}
 * 
 * Design for Governor Limits:
 * - Batch size: 50 records (safe for SOQL/DML limits)
 * - Bulkified SOQL: All emails queried in bulk against Lead/Contact
 * - Uses Database.Batchable for large data volumes
 * - Stateful to track totals across batches
 * 
 * @author GPTfy
 * @date 2026-01
 * @Jira V2-7889
 */
global with sharing class AIStagingEmailMatcherBatch implements Database.Batchable<sObject>, Database.Stateful {
    
    // Running totals across batches
    private Integer totalProcessed = 0;
    private Integer totalMatched = 0;
    private Integer totalDeleted = 0;
    private Integer totalErrors = 0;
    private List<String> errorMessages = new List<String>();
    
    // Maximum errors to track in memory
    private static final Integer MAX_ERRORS_TO_TRACK = 100;
    
    // Record Type IDs cache
    private static Id emailRecordTypeId;
    private static Id calendarRecordTypeId;
    private static Id taskRecordTypeId;
    
    // V2-7889: Initialize record type IDs
    static {
        Map<String, Schema.RecordTypeInfo> rtInfos = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName();
        emailRecordTypeId = rtInfos.get('Email')?.getRecordTypeId();
        calendarRecordTypeId = rtInfos.get('Calendar')?.getRecordTypeId();
        taskRecordTypeId = rtInfos.get('Task')?.getRecordTypeId();
    }
    
    /**
     * Query pending staging records (all record types)
     * V2-7889: Processes all Staged records - Email, Calendar, Task
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, From_Address__c, From_Name__c, To_Address__c, Cc_Address__c, Bcc_Address__c, ' +
                       'Subject__c, Text_Body__c, Html_Body__c, Message_Date__c, Message_Identifier__c, ' +
                       'Provider__c, Provider_Id__c, Provider_Conversation_Id__c, Importance__c, ' +
                       'Is_Incoming__c, Has_Attachments__c, User__c, Sync_Log__c, ' +
                       'Organizer__c, Attendees__c, RecordTypeId, ' +
                       'AI_Workspace_User__c, AI_Workspace_User__r.Service_User_Email__c, AI_Workspace_User__r.User__c ' +
                       'FROM AI_Workspace_Staging__c ' +
                       'WHERE Status__c = \'Staged\' ' +
                       'ORDER BY CreatedDate ASC';
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * Process each batch of staging records
     * V2-7889: Handles Email, Calendar, and Task record types with appropriate matching logic
     * 
     * Phase 2 Logic:
     * - Match staging records to Lead/Contact using record-type specific logic
     * - Populate WhoId__c with comma-separated matched IDs
     * - If matched (WhoId__c populated): Status = 'Ready'
     * - If not matched (WhoId__c empty): DELETE the staging record
     */
    global void execute(Database.BatchableContext bc, List<AI_Workspace_Staging__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        totalProcessed += scope.size();
        
        // V2-7889: Get sync settings to check which sync types are enabled
        AI_Workspace_Sync_Settings__c settings = AISyncSettingsService.getSettings();
        
        // V2-7889: Build map of staging ID to connected account email for each workspace user
        // Use Service_User_Email__c from AI_Workspace_User__c for each user's context
        Map<Id, String> connectedAccountEmailMap = new Map<Id, String>();
        for (AI_Workspace_Staging__c staging : scope) {
            if (staging.AI_Workspace_User__c != null && 
                staging.AI_Workspace_User__r != null && 
                String.isNotBlank(staging.AI_Workspace_User__r.Service_User_Email__c)) {
                connectedAccountEmailMap.put(staging.Id, staging.AI_Workspace_User__r.Service_User_Email__c.toLowerCase().trim());
            }
        }
        
        // V2-7889: Separate records by record type for appropriate matching
        // Only process record types that have sync enabled in settings
        List<AI_Workspace_Staging__c> emailRecords = new List<AI_Workspace_Staging__c>();
        List<AI_Workspace_Staging__c> calendarRecords = new List<AI_Workspace_Staging__c>();
        List<AI_Workspace_Staging__c> taskRecords = new List<AI_Workspace_Staging__c>();
        List<AI_Workspace_Staging__c> recordsToSkip = new List<AI_Workspace_Staging__c>();
        
        Boolean emailSyncEnabled = settings != null && settings.Sync_Enabled__c == true;
        Boolean calendarSyncEnabled = settings != null && settings.Calendar_Sync_Enabled__c == true;
        Boolean taskSyncEnabled = settings != null && settings.Task_Sync_Enabled__c == true;
        
        for (AI_Workspace_Staging__c staging : scope) {
            if (staging.RecordTypeId == emailRecordTypeId) {
                emailRecords.add(staging);
            } else if (staging.RecordTypeId == calendarRecordTypeId) {
                calendarRecords.add(staging);
            } else if (staging.RecordTypeId == taskRecordTypeId) {
                taskRecords.add(staging);
            } else {
               	emailRecords.add(staging);
            }
        }
        
        // Match each record type using appropriate service
        Map<Id, AIStagingMatcherService.MultiMatchResult> allMatchResults = new Map<Id, AIStagingMatcherService.MultiMatchResult>();
        
        // Match Email records - exclude connected account email per staging record
        if (!emailRecords.isEmpty()) {
            Map<Id, AIStagingMatcherService.MultiMatchResult> emailMatches = 
                AIStagingMatcherService.matchEmailStagingRecordsMultiWithMap(emailRecords, connectedAccountEmailMap);
            allMatchResults.putAll(emailMatches);
        }
        
        // Match Calendar records - exclude connected account email per staging record
        if (!calendarRecords.isEmpty()) {
            Map<Id, AIStagingMatcherService.MultiMatchResult> calendarMatches = 
                AIStagingMatcherService.matchCalendarStagingRecordsMultiWithMap(calendarRecords, connectedAccountEmailMap);
            allMatchResults.putAll(calendarMatches);
        }
        
        // Match Task records - uses connected account email FOR matching (not exclusion)
        if (!taskRecords.isEmpty()) {
            Map<Id, AIStagingMatcherService.MultiMatchResult> taskMatches = 
                matchTaskStagingRecords(taskRecords, connectedAccountEmailMap);
            allMatchResults.putAll(taskMatches);
        }
        
        List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
        List<AI_Workspace_Staging__c> stagingToDelete = new List<AI_Workspace_Staging__c>();
        
        for (AI_Workspace_Staging__c staging : scope) {
            AIStagingMatcherService.MultiMatchResult match = allMatchResults.get(staging.Id);
            
            if (match != null && match.hasAnyMatch) {
                // MATCHED: Populate WhoId__c with comma-separated Contact/Lead IDs
                List<String> whoIds = new List<String>();
                if (match.allMatches != null) {
                    for (AIStagingMatcherService.MatchResult matchResult : match.allMatches) {
                        if (matchResult.leadId != null) {
                            whoIds.add(String.valueOf(matchResult.leadId));
                        }
                        if (matchResult.contactId != null) {
                            whoIds.add(String.valueOf(matchResult.contactId));
                        }
                    }
                }
                
                String whoIdValue = String.join(whoIds, ',');
                
                AI_Workspace_Staging__c updateRecord = new AI_Workspace_Staging__c(Id = staging.Id);
                updateRecord.WhoId__c = whoIdValue;
                updateRecord.Status__c = 'Ready';
                stagingToUpdate.add(updateRecord);
                totalMatched++;
            } else {
                stagingToDelete.add(new AI_Workspace_Staging__c(Id = staging.Id));
                totalDeleted++;
            }
        }
        
        // Update staging records marked as Ready
        if (!stagingToUpdate.isEmpty()) {
            stagingToUpdate = (List<AI_Workspace_Staging__c>)FLSCheck.getInstance().updateCheck(stagingToUpdate);
            if(stagingToUpdate != null && !stagingToUpdate.isEmpty()){
                try {
                    // V2-7889: Use allOrNone=false to ensure partial success
                    Database.SaveResult[] updateResults = Database.update(stagingToUpdate, false);
                    for (Integer i = 0; i < updateResults.size(); i++) {
                        if (!updateResults[i].isSuccess()) {
                            for (Database.Error err : updateResults[i].getErrors()) {
                                String errorMsg = 'Update staging ' + stagingToUpdate.get(i).Id + ': ' + err.getMessage();
                                trackError(errorMsg);
                            }
                        }
                    }
                } catch (Exception e) {
                    trackError('Batch update exception: ' + e.getMessage());
                }
            }
        }
        
        // Delete staging records with no match (WhoId__c is empty)
        if (!stagingToDelete.isEmpty()) {
            FLSCheck.getInstance().deleteDML(stagingToDelete);
        }
    }
    
    /**
     * V2-7889: Match Task staging records using connected account email per workspace user
     * Tasks are matched to Lead/Contact based on each workspace user's connected email
     * @param taskRecords List of task staging records to match
     * @param connectedAccountEmailMap Map of staging ID to connected account email
     * @return Map of staging record ID to MultiMatchResult
     */
    private Map<Id, AIStagingMatcherService.MultiMatchResult> matchTaskStagingRecords(
        List<AI_Workspace_Staging__c> taskRecords, 
        Map<Id, String> connectedAccountEmailMap
    ) {
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = new Map<Id, AIStagingMatcherService.MultiMatchResult>();
        
        if (taskRecords == null || taskRecords.isEmpty()) {
            return results;
        }
        
        // Collect all unique connected account emails
        Set<String> allConnectedEmails = new Set<String>();
        for (AI_Workspace_Staging__c staging : taskRecords) {
            String email = connectedAccountEmailMap.get(staging.Id);
            if (String.isNotBlank(email)) {
                allConnectedEmails.add(email.toLowerCase().trim());
            }
        }
        
        // If no connected emails found, return empty results for all records
        if (allConnectedEmails.isEmpty()) {
            for (AI_Workspace_Staging__c staging : taskRecords) {
                results.put(staging.Id, new AIStagingMatcherService.MultiMatchResult());
            }
            return results;
        }
        
        // Build cache: email -> matched Lead/Contact IDs
        Map<String, Set<Id>> emailToMatchedIds = new Map<String, Set<Id>>();
        
        // Query Contacts with the connected account emails
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :allConnectedEmails LIMIT 20000]) {
            if (String.isNotBlank(c.Email)) {
                String normalizedEmail = c.Email.toLowerCase().trim();
                if (!emailToMatchedIds.containsKey(normalizedEmail)) {
                    emailToMatchedIds.put(normalizedEmail, new Set<Id>());
                }
                emailToMatchedIds.get(normalizedEmail).add(c.Id);
            }
        }
        
        // Query Leads with the connected account emails
        for (Lead l : [SELECT Id, Email FROM Lead WHERE Email IN :allConnectedEmails AND IsConverted = false LIMIT 20000]) {
            if (String.isNotBlank(l.Email)) {
                String normalizedEmail = l.Email.toLowerCase().trim();
                if (!emailToMatchedIds.containsKey(normalizedEmail)) {
                    emailToMatchedIds.put(normalizedEmail, new Set<Id>());
                }
                emailToMatchedIds.get(normalizedEmail).add(l.Id);
            }
        }
        
        // Create match results for each task record using its specific connected email
        for (AI_Workspace_Staging__c staging : taskRecords) {
            AIStagingMatcherService.MultiMatchResult multiResult = new AIStagingMatcherService.MultiMatchResult();
            
            String connectedEmail = connectedAccountEmailMap.get(staging.Id);
            if (String.isBlank(connectedEmail)) {
                // No connected email for this staging record
                results.put(staging.Id, multiResult);
                continue;
            }
            
            String normalizedEmail = connectedEmail.toLowerCase().trim();
            Set<Id> matchedIds = emailToMatchedIds.get(normalizedEmail);
            
            if (matchedIds != null && !matchedIds.isEmpty()) {
                multiResult.hasAnyMatch = true;
                multiResult.hasPrimaryMatch = true;
                
                for (Id matchedId : matchedIds) {
                    AIStagingMatcherService.MatchResult match = new AIStagingMatcherService.MatchResult();
                    match.isMatched = true;
                    
                    // Determine if Lead or Contact
                    String sObjectType = matchedId.getSObjectType().getDescribe().getName();
                    if (sObjectType == 'Lead') {
                        match.leadId = matchedId;
                    } else if (sObjectType == 'Contact') {
                        match.contactId = matchedId;
                    }
                    
                    multiResult.allMatches.add(match);
                }
                
                if (!multiResult.allMatches.isEmpty()) {
                    multiResult.primaryMatch = multiResult.allMatches[0];
                }
            }
            
            results.put(staging.Id, multiResult);
        }
        
        return results;
    }
    
    /**
     * Track error message
     */
    private void trackError(String message) {
        totalErrors++;
        if (errorMessages.size() < MAX_ERRORS_TO_TRACK) {
            errorMessages.add(message);
        }
    }
    
    /**
     * Finish method - log summary and trigger Phase 3
     * V2-7889: Trigger Phase 3 batch after Phase 2 completes
     */
    global void finish(Database.BatchableContext bc) {
        // V2-7889: Trigger Phase 3 batch to process Ready records
        try {
            Id phase3BatchId = AIStagingPolicyMatcherBatch.runBatch();
        } catch (Exception e) {
            
        }
    }
    
    /**
     * Static method to run the batch with default batch size
     */
    public static Id runBatch() {
        return runBatch(50); // Default batch size
    }
    
    /**
     * Static method to run the batch with custom batch size
     */
    public static Id runBatch(Integer batchSize) {
        return Database.executeBatch(new AIStagingEmailMatcherBatch(), batchSize);
    }
}