/**
 * AIStagingEmailMatcherBatch - Batch processor for matching staging records to Lead/Contact/User
 * 
 * Processes pending email staging records, matches sender emails using configurable
 * precedence rules, creates EmailMessage records for matches, and updates staging status.
 * 
 * Design for Governor Limits:
 * - Batch size: 50 records (safe for SOQL/DML limits)
 * - Bulkified SOQL: All sender emails queried in bulk against Lead/Contact/User
 * - Uses Database.Batchable for large data volumes
 * - Stateful to track totals across batches
 * 
 * @author GPTfy
 * @date 2026-01
 */
public with sharing class AIStagingEmailMatcherBatch implements Database.Batchable<sObject>, Database.Stateful {
    
    // Running totals across batches
    private Integer totalProcessed = 0;
    private Integer totalMatched = 0;
    private Integer totalUnmatched = 0;
    private Integer totalEmailsCreated = 0;
    private Integer totalErrors = 0;
    private List<String> errorMessages = new List<String>();
    
    // Maximum errors to track in memory
    private static final Integer MAX_ERRORS_TO_TRACK = 100;
    
    /**
     * Query pending email staging records
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Get the Email record type ID
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
        
        String query = 'SELECT Id, From_Address__c, From_Name__c, To_Address__c, Cc_Address__c, Bcc_Address__c, ' +
                       'Subject__c, Text_Body__c, Html_Body__c, Message_Date__c, Message_Identifier__c, ' +
                       'Provider__c, Provider_Id__c, Provider_Conversation_Id__c, Importance__c, ' +
                       'Is_Incoming__c, Has_Attachments__c, User__c, Sync_Log__c ' +
                       'FROM AI_Workspace_Staging__c ' +
                       'WHERE Status__c = \'Unmatched\' ';
        
        if (emailRecordTypeId != null) {
            query += 'AND RecordTypeId = \'' + emailRecordTypeId + '\' ';
        }
        
        query += 'ORDER BY CreatedDate ASC';
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * Process each batch of staging records
     * 
     * NEW LOGIC: Uses the updated precedence matching that returns ALL matched IDs
     * at the successful precedence level (e.g., if Precedence 1 = [Lead, Contact, User] and all match,
     * creates EmailMessageRelation for all 3).
     */
    public void execute(Database.BatchableContext bc, List<AI_Workspace_Staging__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        totalProcessed += scope.size();
        
        // Match staging records using the matcher service
        Map<Id, AIStagingMatcherService.MatchResult> matchResults = 
            AIStagingMatcherService.matchStagingRecords(scope);
        
        List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
        List<EmailMessage> emailsToCreate = new List<EmailMessage>();
        Map<Integer, Id> emailIndexToStagingId = new Map<Integer, Id>();
        // NEW: Store all matched IDs (lists) instead of single IDs
        Map<Integer, List<Id>> emailIndexToContactIds = new Map<Integer, List<Id>>();
        Map<Integer, List<Id>> emailIndexToLeadIds = new Map<Integer, List<Id>>();
        
        for (AI_Workspace_Staging__c staging : scope) {
            AIStagingMatcherService.MatchResult match = matchResults.get(staging.Id);
            
            AI_Workspace_Staging__c updateRecord = new AI_Workspace_Staging__c(Id = staging.Id);
            
            if (match != null && match.isMatched) {
                // Mark as matched - associations stored in EmailMessageRelation
                updateRecord.Status__c = 'Matched';
                
                // Create EmailMessage for matched records
                EmailMessage em = createEmailMessageFromStaging(staging);
                
                // Store the index for later relation creation
                emailIndexToStagingId.put(emailsToCreate.size(), staging.Id);
                
                // NEW: Track ALL matched Contacts for EmailMessageRelation
                if (match.matchedContactIds != null && !match.matchedContactIds.isEmpty()) {
                    emailIndexToContactIds.put(emailsToCreate.size(), match.matchedContactIds);
                } else if (match.contactId != null) {
                    // Backward compatibility
                    emailIndexToContactIds.put(emailsToCreate.size(), new List<Id>{ match.contactId });
                }
                
                // NEW: Track ALL matched Leads for EmailMessageRelation
                if (match.matchedLeadIds != null && !match.matchedLeadIds.isEmpty()) {
                    emailIndexToLeadIds.put(emailsToCreate.size(), match.matchedLeadIds);
                } else if (match.leadId != null) {
                    // Backward compatibility
                    emailIndexToLeadIds.put(emailsToCreate.size(), new List<Id>{ match.leadId });
                }
                
                emailsToCreate.add(em);
                totalMatched++;
            } else {
                // No match found
                updateRecord.Status__c = 'Unmatched';
                totalUnmatched++;
            }
            
            stagingToUpdate.add(updateRecord);
        }
        
        // Insert EmailMessages and create relations
        if (!emailsToCreate.isEmpty()) {
            Map<Integer, Id> emailIndexToEmailMessageId = insertEmailMessages(emailsToCreate);
            
            // Create EmailMessageRelations for ALL matched Contacts/Leads
            createEmailMessageRelationsMultiple(emailIndexToEmailMessageId, emailIndexToContactIds, emailIndexToLeadIds);
            
            // Update staging records with EmailMessage reference (stored as Text ID)
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
            Database.SaveResult[] updateResults = Database.update(stagingToUpdate, false);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (!updateResults[i].isSuccess()) {
                    for (Database.Error err : updateResults[i].getErrors()) {
                        trackError('Update staging ' + stagingToUpdate[i].Id + ': ' + err.getMessage());
                    }
                }
            }
        }
    }
    
    /**
     * Create EmailMessage from staging record data
     * 
     * Note: We populate standard EmailMessage fields:
     * - MessageIdentifier (standard): For deduplication (RFC 2822 Message-ID / internetMessageId)
     * - Email_Provider_Type__c (custom): For provider tracking (MICROSOFT_GRAPH or GMAIL)
     * 
     * These two fields are critical for deduplication even after Staging records are deleted,
     * and for counting imported emails by provider.
     */
    private EmailMessage createEmailMessageFromStaging(AI_Workspace_Staging__c staging) {
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
        
        // Custom field for provider tracking (still needed to know which provider the email came from)
        // Deduplication now uses the standard MessageIdentifier field
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.EmailMessage.fields.getMap();
        
        if (isEmailFieldCreateable(fieldMap, 'Email_Provider_Type__c')) {
            em.put('Email_Provider_Type__c', staging.Provider__c);
        }
        
        return em;
    }
    
    /**
     * Check if a field exists on EmailMessage and is createable
     */
    private Boolean isEmailFieldCreateable(Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        if (!fieldMap.containsKey(fieldName)) {
            return false;
        }
        return fieldMap.get(fieldName).getDescribe().isCreateable();
    }
    
    /**
     * Insert EmailMessages and return map of index to created record ID
     */
    private Map<Integer, Id> insertEmailMessages(List<EmailMessage> emails) {
        Map<Integer, Id> indexToId = new Map<Integer, Id>();
        
        Database.SaveResult[] results = Database.insert(emails, false);
        
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                indexToId.put(i, results[i].getId());
                totalEmailsCreated++;
            } else {
                for (Database.Error err : results[i].getErrors()) {
                    trackError('Create EmailMessage: ' + err.getMessage());
                }
            }
        }
        
        return indexToId;
    }
    
    /**
     * Create EmailMessageRelation records for ALL matched Contacts/Leads
     * NEW: Handles multiple IDs per email (from new precedence logic)
     */
    private void createEmailMessageRelationsMultiple(
        Map<Integer, Id> emailIndexToEmailMessageId,
        Map<Integer, List<Id>> emailIndexToContactIds,
        Map<Integer, List<Id>> emailIndexToLeadIds
    ) {
        List<EmailMessageRelation> relations = new List<EmailMessageRelation>();
        Set<String> createdRelations = new Set<String>(); // Prevent duplicates
        
        for (Integer idx : emailIndexToEmailMessageId.keySet()) {
            Id emailMessageId = emailIndexToEmailMessageId.get(idx);
            
            // Create relations for ALL matched Contacts
            if (emailIndexToContactIds.containsKey(idx)) {
                for (Id contactId : emailIndexToContactIds.get(idx)) {
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
            }
            
            // Create relations for ALL matched Leads
            if (emailIndexToLeadIds.containsKey(idx)) {
                for (Id leadId : emailIndexToLeadIds.get(idx)) {
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
            }
        }
        
        // Insert in batches to avoid DML limits
        if (!relations.isEmpty()) {
            Integer batchSize = 50;
            for (Integer i = 0; i < relations.size(); i += batchSize) {
                Integer endIdx = Math.min(i + batchSize, relations.size());
                List<EmailMessageRelation> batch = new List<EmailMessageRelation>();
                for (Integer j = i; j < endIdx; j++) {
                    batch.add(relations[j]);
                }
                
                Database.SaveResult[] results = Database.insert(batch, false);
                for (Integer k = 0; k < results.size(); k++) {
                    if (!results[k].isSuccess()) {
                        for (Database.Error err : results[k].getErrors()) {
                            // Log but don't fail the batch for relation errors
                            System.debug(LoggingLevel.ERROR, 'EmailMessageRelation error: ' + err.getMessage());
                        }
                    }
                }
            }
        }
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
     * Finish method - log summary
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '=== AIStagingEmailMatcherBatch Complete ===');
        System.debug(LoggingLevel.INFO, 'Total Processed: ' + totalProcessed);
        System.debug(LoggingLevel.INFO, 'Total Matched: ' + totalMatched);
        System.debug(LoggingLevel.INFO, 'Total Unmatched: ' + totalUnmatched);
        System.debug(LoggingLevel.INFO, 'Total EmailMessages Created: ' + totalEmailsCreated);
        System.debug(LoggingLevel.INFO, 'Total Errors: ' + totalErrors);
        
        if (!errorMessages.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Errors: ' + String.join(errorMessages, '\n'));
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