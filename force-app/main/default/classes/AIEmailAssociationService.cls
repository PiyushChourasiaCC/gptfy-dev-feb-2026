/**
 * Provider-agnostic service for finding and enriching email associations
 * Works with any email source (Microsoft Graph, Gmail, etc.)
 */
public with sharing class AIEmailAssociationService {

    /**
     * Enriches email data with existing Salesforce associations
     * @param emails List of email objects (provider-agnostic format)
     * @return Same email list enriched with 'associations' and 'isImported' fields
     */
    public static List<Map<String, Object>> enrichEmailsWithAssociations(
        List<Map<String, Object>> emails
    ) {
        if (emails == null || emails.isEmpty()) {
            return emails;
        }

        // Collect Message IDs and Subjects for querying
        Set<String> messageIds = new Set<String>();
        Set<String> emailSubjects = new Set<String>();

        for (Map<String, Object> email : emails) {
            String messageId = (String) email.get('internetMessageId');
            if (String.isNotBlank(messageId)) {
                messageIds.add(messageId);
            }

            String subject = (String) email.get('subject');
            if (String.isNotBlank(subject)) {
                emailSubjects.add('Email: ' + subject);
            }
        }

        // Build association map
        Map<String, List<Map<String, String>>> associationMap =
            buildAssociationMap(messageIds, emailSubjects, emails);

        // Enrich email objects with associations
        for (Map<String, Object> email : emails) {
            String messageId = (String) email.get('internetMessageId');
            if (associationMap.containsKey(messageId)) {
                email.put('associations', associationMap.get(messageId));
                email.put('isImported', true);
            } else {
                email.put('isImported', false);
            }
        }

        return emails;
    }

    /**
     * Builds association map by querying EmailMessages, Tasks, and Staging records
     */
    private static Map<String, List<Map<String, String>>> buildAssociationMap(
        Set<String> messageIds,
        Set<String> emailSubjects,
        List<Map<String, Object>> emails
    ) {
        Map<String, List<Map<String, String>>> associationMap =
            new Map<String, List<Map<String, String>>>();

        if (messageIds.isEmpty()) {
            return associationMap;
        }

        // Query EmailMessage associations
        queryEmailMessageAssociations(messageIds, associationMap);

        // Query Task associations (for Contact imports)
        queryTaskAssociations(emailSubjects, emails, associationMap);

        // Query AI_Workspace_Staging__c associations (new staging approach)
        queryStagingAssociations(messageIds, associationMap);

        return associationMap;
    }

    /**
     * Queries AI_Workspace_Staging__c records to mark emails as imported
     * Uses Message_Identifier__c which stores the internetMessageId
     * Shows status (Matched/Unmatched/Pending) - associations come from EmailMessage/EmailMessageRelation
     * 
     * IMPORTANT: Verifies that linked EmailMessage records still exist.
     * If an EmailMessage was deleted, the staging record is reset to allow re-matching.
     */
    private static void queryStagingAssociations(
        Set<String> messageIds,
        Map<String, List<Map<String, String>>> associationMap
    ) {
        // Query staging records by Message_Identifier__c (internetMessageId)
        List<AI_Workspace_Staging__c> stagingRecords = [
            SELECT Id, Message_Identifier__c, Subject__c, Status__c, Email_Message__c
            FROM AI_Workspace_Staging__c
            WHERE Message_Identifier__c IN :messageIds
            AND RecordType.DeveloperName = 'Email'
            WITH USER_MODE
        ];
        
        if (stagingRecords.isEmpty()) {
            return;
        }
        
        // Collect EmailMessage IDs to verify they still exist
        Set<Id> emailMessageIds = new Set<Id>();
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            if (staging.Status__c == 'Imported' && String.isNotBlank(staging.Email_Message__c)) {
                try {
                    Id emId = Id.valueOf(staging.Email_Message__c);
                    emailMessageIds.add(emId);
                } catch (Exception e) {
                    // Invalid ID format, ignore
                }
            }
        }
        
        // Query to find which EmailMessage records still exist
        Set<Id> existingEmailMessageIds = new Set<Id>();
        if (!emailMessageIds.isEmpty()) {
            for (EmailMessage em : [
                SELECT Id FROM EmailMessage WHERE Id IN :emailMessageIds WITH USER_MODE
            ]) {
                existingEmailMessageIds.add(em.Id);
            }
        }
        
        // Track staging records that need to be reset (EmailMessage was deleted)
        List<AI_Workspace_Staging__c> stagingToReset = new List<AI_Workspace_Staging__c>();
        
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            if (String.isNotBlank(staging.Message_Identifier__c)) {
                // Check if this was a "Matched" record but EmailMessage was deleted
                Boolean emailMessageDeleted = false;
                if (staging.Status__c == 'Imported' && String.isNotBlank(staging.Email_Message__c)) {
                    try {
                        Id emId = Id.valueOf(staging.Email_Message__c);
                        emailMessageDeleted = !existingEmailMessageIds.contains(emId);
                    } catch (Exception e) {
                        emailMessageDeleted = true; // Invalid ID, treat as deleted
                    }
                }
                
                // If EmailMessage was deleted, reset the staging record
                if (emailMessageDeleted) {
                    AI_Workspace_Staging__c resetRecord = new AI_Workspace_Staging__c(
                        Id = staging.Id,
                        Status__c = 'Staged',
                        Email_Message__c = null
                    );
                    stagingToReset.add(resetRecord);
                    
                    // Email was previously matched but EmailMessage was deleted
                    // Don't show as imported anymore - skip adding to associationMap
                    continue; // Skip normal processing
                }
                
                // Only mark as imported if status is 'Matched'
                // Unmatched emails should not show as imported - they should be available for re-selection
                if (staging.Status__c == 'Imported') {
                    // If not already in the map, add an empty association list
                    // This marks the email as imported - associations come from EmailMessage/EmailMessageRelation queries
                    if (!associationMap.containsKey(staging.Message_Identifier__c)) {
                        associationMap.put(staging.Message_Identifier__c, new List<Map<String, String>>());
                    }
                    // No need to add staging record as association - actual Lead/Contact/User
                    // associations will be populated from queryEmailMessageAssociations
                }
                // For 'Unmatched' status, don't add to associationMap - email will not show as imported
                // and user can re-select it for matching
            }
        }
        
        // Reset staging records where EmailMessage was deleted
        if (!stagingToReset.isEmpty()) {
            resetStagingRecordsAsync(stagingToReset);
        }
    }
    
    /**
     * Resets staging records when their linked EmailMessage was deleted.
     * V2-7889: Uses FLSCheck for field-level security validation
     */
    private static void resetStagingRecordsAsync(List<AI_Workspace_Staging__c> stagingToReset) {
        try {
            FLSCheck.getInstance().updateDML(stagingToReset, false);
        } catch (Exception e) {
            
        }
    }

    /**
     * Queries EmailMessage records and their associations
     */
    private static void queryEmailMessageAssociations(
        Set<String> messageIds,
        Map<String, List<Map<String, String>>> associationMap
    ) {
        // Track Opportunity IDs for bulk Account query
        Map<String, Id> messageToOppId = new Map<String, Id>();
        // Track EmailMessage IDs for EmailMessageRelation query
        Map<Id, String> emailMessageIdToMessageId = new Map<Id, String>();

        for (EmailMessage em : [
            SELECT Id, MessageIdentifier,
                   RelatedTo.Name,
                   RelatedTo.Type,
                   RelatedToId,
                   ParentId,
                   Parent.CaseNumber
            FROM EmailMessage
            WHERE MessageIdentifier IN :messageIds
            WITH USER_MODE
        ]) {
            if (!associationMap.containsKey(em.MessageIdentifier)) {
                associationMap.put(em.MessageIdentifier, new List<Map<String, String>>());
            }

            // Track EmailMessage ID for EmailMessageRelation query
            emailMessageIdToMessageId.put(em.Id, em.MessageIdentifier);

            // Add Related Record (WhatId)
            if (em.RelatedTo != null) {
                addAssociationIfNotExists(
                    associationMap.get(em.MessageIdentifier),
                    em.RelatedTo.Name,
                    em.RelatedTo.Type,
                    em.RelatedToId
                );

                // Track Opportunity IDs for bulk query
                if (em.RelatedTo.Type == 'Opportunity') {
                    messageToOppId.put(em.MessageIdentifier, em.RelatedToId);
                }
            }

            // Add Parent Record (Case) if different
            if (em.Parent != null) {
                Boolean alreadyAdded = false;
                if (em.RelatedTo != null &&
                    em.RelatedTo.Type == 'Case' &&
                    em.RelatedTo.Name == em.Parent.CaseNumber) {
                    alreadyAdded = true;
                }

                if (!alreadyAdded) {
                    addAssociationIfNotExists(
                        associationMap.get(em.MessageIdentifier),
                        'Case #' + em.Parent.CaseNumber,
                        'Case',
                        em.ParentId
                    );
                }
            }
        }

        // Query Opportunity Accounts
        if (!messageToOppId.isEmpty()) {
            addOpportunityAccountAssociations(messageToOppId, associationMap);
        }

        // Query EmailMessageRelation to get Contact/Lead associations
        if (!emailMessageIdToMessageId.isEmpty()) {
            addEmailMessageRelationAssociations(emailMessageIdToMessageId, associationMap);
        }
    }

    /**
     * Queries EmailMessageRelation to get Contact/Lead associations for EmailMessages
     */
    private static void addEmailMessageRelationAssociations(
        Map<Id, String> emailMessageIdToMessageId,
        Map<String, List<Map<String, String>>> associationMap
    ) {
        for (EmailMessageRelation emr : [
            SELECT EmailMessageId, RelationId, Relation.Name, Relation.Type
            FROM EmailMessageRelation
            WHERE EmailMessageId IN :emailMessageIdToMessageId.keySet()
            AND Relation.Type IN ('Contact', 'Lead')
            WITH USER_MODE
        ]) {
            String messageIdentifier = emailMessageIdToMessageId.get(emr.EmailMessageId);
            if (messageIdentifier != null && emr.Relation != null) {
                addAssociationIfNotExists(
                    associationMap.get(messageIdentifier),
                    emr.Relation.Name,
                    emr.Relation.Type,
                    emr.RelationId
                );
            }
        }
    }

    /**
     * Adds Account associations for Opportunities
     */
    private static void addOpportunityAccountAssociations(
        Map<String, Id> messageToOppId,
        Map<String, List<Map<String, String>>> associationMap
    ) {
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, AccountId, Account.Name
            FROM Opportunity
            WHERE Id IN :messageToOppId.values()
            AND AccountId != null
            WITH USER_MODE
        ]);

        for (String messageId : messageToOppId.keySet()) {
            Id oppId = messageToOppId.get(messageId);
            if (oppMap.containsKey(oppId) && oppMap.get(oppId).Account != null) {
                addAssociationIfNotExists(
                    associationMap.get(messageId),
                    oppMap.get(oppId).Account.Name,
                    'Account',
                    oppMap.get(oppId).AccountId
                );
            }
        }
    }

    /**
     * Queries Task records for Contact associations
     * Tasks are used for Contact email imports since EmailMessage doesn't support WhoId
     */
    private static void queryTaskAssociations(
        Set<String> emailSubjects,
        List<Map<String, Object>> emails,
        Map<String, List<Map<String, String>>> associationMap
    ) {
        // Collect internetMessageIds from emails for direct matching
        Set<String> messageIds = new Set<String>();
        for (Map<String, Object> email : emails) {
            String messageId = (String) email.get('internetMessageId');
            if (String.isNotBlank(messageId)) {
                messageIds.add(messageId);
            }
        }

        if (messageIds.isEmpty()) {
            return;
        }

        // Query Tasks by Workspace_Sync_Id__c instead of subject
        // This provides accurate 1:1 matching even for emails with same subject
        queryTaskBatch(messageIds, emails, associationMap);
    }

    /**
     * Queries a batch of Task records by Workspace_Sync_Id__c
     * Provides accurate 1:1 matching without subject ambiguity
     */
    private static void queryTaskBatch(
        Set<String> messageIds,
        List<Map<String, Object>> emails,
        Map<String, List<Map<String, String>>> associationMap
    ) {
        // Track Opportunity IDs for bulk Account query
        Map<String, Id> messageToOppId = new Map<String, Id>();

        for (Task t : [
            SELECT Workspace_Sync_Id__c, Who.Name, Who.Type, WhoId, What.Name, What.Type, WhatId
            FROM Task
            WHERE Workspace_Sync_Id__c IN :messageIds
            AND TaskSubtype = 'Email'
        ]) {
            String taskMessageId = (String) t.get('Workspace_Sync_Id__c');

            if (String.isBlank(taskMessageId)) {
                continue;
            }

            // Direct matching by internetMessageId - no ambiguity
            if (!associationMap.containsKey(taskMessageId)) {
                associationMap.put(taskMessageId, new List<Map<String, String>>());
            }

            // Add Who association (Contact/Lead) if present
            if (t.Who != null && String.isNotBlank(t.Who.Name)) {
                addAssociationIfNotExists(
                    associationMap.get(taskMessageId),
                    t.Who.Name,
                    t.Who.Type,
                    t.WhoId
                );
            }

            // Add What association (Account/Opportunity/Case) if present
            if (t.What != null && String.isNotBlank(t.What.Name)) {
                addAssociationIfNotExists(
                    associationMap.get(taskMessageId),
                    t.What.Name,
                    t.What.Type,
                    t.WhatId
                );

                // Track Opportunity IDs for bulk Account query
                if (t.What.Type == 'Opportunity' && t.WhatId != null) {
                    messageToOppId.put(taskMessageId, t.WhatId);
                }
            }
        }

        // Add Account associations for Opportunities linked to Tasks
        if (!messageToOppId.isEmpty()) {
            addTaskOpportunityAccountAssociations(messageToOppId, associationMap);
        }
    }

    /**
     * Adds Account associations for Tasks linked to Opportunities
     */
    private static void addTaskOpportunityAccountAssociations(
        Map<String, Id> messageToOppId,
        Map<String, List<Map<String, String>>> associationMap
    ) {
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, AccountId, Account.Name
            FROM Opportunity
            WHERE Id IN :messageToOppId.values()
            AND AccountId != null
            WITH USER_MODE
        ]);

        for (String messageId : messageToOppId.keySet()) {
            Id oppId = messageToOppId.get(messageId);
            if (oppMap.containsKey(oppId) && oppMap.get(oppId).Account != null) {
                addAssociationIfNotExists(
                    associationMap.get(messageId),
                    oppMap.get(oppId).Account.Name,
                    'Account',
                    oppMap.get(oppId).AccountId
                );
            }
        }
    }

    /**
     * Helper method to add an association if it doesn't already exist
     */
    private static void addAssociationIfNotExists(
        List<Map<String, String>> associations,
        String name,
        String objectType,
        Id recordId
    ) {
        // Check if this association already exists (deduplicate)
        for (Map<String, String> existing : associations) {
            if (existing.get('name') == name && existing.get('type') == objectType) {
                return; // Already exists, skip
            }
        }

        // Add new association with recordId for navigation
        associations.add(new Map<String, String>{
            'name' => name,
            'type' => objectType,
            'recordId' => recordId != null ? String.valueOf(recordId) : null
        });
    }
}