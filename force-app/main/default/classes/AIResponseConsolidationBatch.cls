/**
 * @description Batch class to consolidate AI_Response__c records for a completed scheduled run.
 *              Groups responses by Record_Id__c and creates parent AI_Response__c records
 *              for each unique record ID, then links all child responses to their parent.
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 12-02-2024
 * @last modified by Piyush Chourasia
 */
public with sharing class AIResponseConsolidationBatch implements Database.Batchable<AggregateResult>, Database.Stateful {
    
    private Id scheduledRunId;
    
    /**
     * Constructor for AIResponseConsolidationBatch
     *
     * @param scheduledRunId The ID of the AI_Scheduled_Run__c record to process
     */
    public AIResponseConsolidationBatch(Id scheduledRunId) {
        this.scheduledRunId = scheduledRunId;
    }
    
    /**
     * Start method that queries distinct Record_Id__c values for the given scheduled run.
     * Uses aggregate query to get unique Record_Id__c values to ensure each group is processed once.
     *
     * @param bc The Database.BatchableContext provided by the platform
     * @return Iterable containing AggregateResult with distinct Record_Id__c values
     */
    public Iterable<AggregateResult> start(Database.BatchableContext bc) {
        // Query distinct Record_Id__c values using aggregate query
        // This ensures each Record_Id__c group is processed exactly once
        return [
            SELECT Record_Id__c 
            FROM AI_Response__c 
            WHERE Scheduled_Run__c = :scheduledRunId 
            AND Record_Id__c != NULL 
            GROUP BY Record_Id__c
        ];
    }
    
    /**
     * Execute method that processes batches of unique Record_Id__c values.
     * For each Record_Id__c, fetches all related AI_Response__c records,
     * creates a parent record, and links all children to it.
     *
     * NOTE: Batch size should be adjusted based on expected number of responses per Record_Id__c
     * to avoid governor limits. Default of 50 Record_Id__c per batch is recommended.
     *
     * @param bc The Database.BatchableContext provided by the platform
     * @param scope The list of AggregateResult containing unique Record_Id__c values
     */
    public void execute(Database.BatchableContext bc, List<AggregateResult> scope) {
        try {
            // Extract Record_Id__c values from aggregate results
            Set<String> recordIds = new Set<String>();
            for(AggregateResult ar : scope) {
                String recordId = (String)ar.get('Record_Id__c');
                if(String.isNotBlank(recordId)) {
                    recordIds.add(recordId);
                }
            }
            
            if(recordIds.isEmpty()) {
                return;
            }
            
            // Fetch all AI_Response__c records for these Record_Id__c values
            // NOTE: This query could return many records if each Record_Id__c has multiple responses
            // Adjust batch size accordingly to stay within governor limits
            List<AI_Response__c> allResponses = [
                SELECT Id, Name, Record_Id__c, AI_Prompt__c, Status__c, 
                       Completion_Tokens__c, Prompt_Tokens__c, AI_Parent_Response__c 
                FROM AI_Response__c 
                WHERE Scheduled_Run__c = :scheduledRunId 
                AND Record_Id__c IN :recordIds
            ];
            
            // Group responses by Record_Id__c
            Map<String, List<AI_Response__c>> responsesByRecordId = new Map<String, List<AI_Response__c>>();
            for(AI_Response__c response : allResponses) {
                if(!responsesByRecordId.containsKey(response.Record_Id__c)) {
                    responsesByRecordId.put(response.Record_Id__c, new List<AI_Response__c>());
                }
                responsesByRecordId.get(response.Record_Id__c).add(response);
            }
            
            // Process each record ID group
            processRecordIdGroups(responsesByRecordId);
            
        } catch(Exception e) {
            System.debug('Error in AIResponseConsolidationBatch execute: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw e;
        }
    }
    
    /**
     * Processes each group of AI_Response__c records by Record_Id__c.
     * Creates parent AI_Response__c records and links child records.
     *
     * @param responsesByRecordId Map of Record_Id__c to List of AI_Response__c records
     */
    private void processRecordIdGroups(Map<String, List<AI_Response__c>> responsesByRecordId) {
        List<AI_Response__c> parentsToInsert = new List<AI_Response__c>();
        List<AI_Response__c> childrenToUpdate = new List<AI_Response__c>();
        Map<String, AI_Response__c> parentByRecordId = new Map<String, AI_Response__c>();
        
        // Step 1: Collect all unique child prompt IDs and map them to Record_Id__c
        Set<Id> childPromptIds = new Set<Id>();
        Map<Id, String> childPromptToRecordIdMap = new Map<Id, String>();
        
        for(String recordId : responsesByRecordId.keySet()) {
            List<AI_Response__c> responses = responsesByRecordId.get(recordId);
            for(AI_Response__c response : responses) {
                if(response.AI_Prompt__c != null) {
                    childPromptIds.add(response.AI_Prompt__c);
                    // Map child prompt to Record_Id for later lookup
                    childPromptToRecordIdMap.put(response.AI_Prompt__c, recordId);
                }
            }
        }
        
        // Step 2: Query AI_Prompt_Element__c ONCE for all child prompts (BULKIFIED)
        Map<Id, Id> childPromptToParentPromptMap = new Map<Id, Id>();
        if(!childPromptIds.isEmpty()) {
            List<AI_Prompt_Element__c> promptElements = [
                SELECT Id, AI_Prompt__c, AI_Parent_Prompt__c 
                FROM AI_Prompt_Element__c 
                WHERE AI_Prompt__c IN :childPromptIds
            ];
            
            for(AI_Prompt_Element__c element : promptElements) {
                // Store the mapping - if multiple elements exist for same child prompt,
                // the last one will be used (consistent behavior)
                childPromptToParentPromptMap.put(element.AI_Prompt__c, element.AI_Parent_Prompt__c);
            }
        }
        
        // Step 3: Create parent AI_Response__c for each unique Record_Id__c
        for(String recordId : responsesByRecordId.keySet()) {
            List<AI_Response__c> responses = responsesByRecordId.get(recordId);
            
            if(!responses.isEmpty()) {
                Id childPromptId = responses[0].AI_Prompt__c;
                
                // Get the parent prompt ID from the bulk query results
                Id parentPromptId = childPromptToParentPromptMap.get(childPromptId);
                
                // If no parent prompt found, fall back to the child prompt ID
                Id promptIdToUse = (parentPromptId != null) ? parentPromptId : childPromptId;
                
                // Create parent AI_Response__c record similar to getNewAIResponse()
                AI_Response__c parentResponse = new AI_Response__c();
                parentResponse.Record_Id__c = recordId;
                parentResponse.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
                parentResponse.Is_Canvas_Response__c = true;
                parentResponse.AI_Prompt__c = promptIdToUse;
                parentResponse.Scheduled_Run__c = scheduledRunId;
                
                parentsToInsert.add(parentResponse);
                parentByRecordId.put(recordId, parentResponse);
            }
        }
        
        // Insert parent records
        if(!parentsToInsert.isEmpty()) {
            List<SObject> insertedParents = FLSCheck.getInstance().insertDML(parentsToInsert);
            
            // Update map with inserted IDs - match by index using same iteration order
            for(Integer i = 0; i < parentsToInsert.size() && i < insertedParents.size(); i++) {
                String recordId = parentsToInsert[i].Record_Id__c;
                parentsToInsert[i].Id = insertedParents[i].Id;
                // Update the reference in the map as well
                if(parentByRecordId.containsKey(recordId)) {
                    parentByRecordId.get(recordId).Id = insertedParents[i].Id;
                }
            }
            
            // Link child records to parents and prepare for update
            linkChildrenToParents(responsesByRecordId, parentByRecordId, childrenToUpdate);
            
            // Update parent records with aggregated token counts
            updateParentRecords(responsesByRecordId, parentByRecordId);
        }
    }
    
    /**
     * Links child AI_Response__c records to their parent records.
     *
     * @param responsesByRecordId Map of Record_Id__c to List of AI_Response__c records
     * @param parentByRecordId Map of Record_Id__c to parent AI_Response__c records
     * @param childrenToUpdate List to collect child records that need updating
     */
    private void linkChildrenToParents(Map<String, List<AI_Response__c>> responsesByRecordId, 
                                      Map<String, AI_Response__c> parentByRecordId, 
                                      List<AI_Response__c> childrenToUpdate) {
        for(String recordId : responsesByRecordId.keySet()) {
            List<AI_Response__c> responses = responsesByRecordId.get(recordId);
            AI_Response__c parent = parentByRecordId.get(recordId);
            
            if(parent != null && parent.Id != null) {
                for(AI_Response__c childResponse : responses) {
                    childResponse.AI_Parent_Response__c = parent.Id;
                    childrenToUpdate.add(childResponse);
                }
            }
        }
        
        if(!childrenToUpdate.isEmpty()) {
            FLSCheck.getInstance().updateDML(childrenToUpdate);
        }
    }
    
    /**
     * Updates parent AI_Response__c records with aggregated token counts and status.
     * Similar to updateParentAIResponse() method in AICanvasController.
     *
     * @param responsesByRecordId Map of Record_Id__c to List of AI_Response__c records
     * @param parentByRecordId Map of Record_Id__c to parent AI_Response__c records
     */
    private void updateParentRecords(Map<String, List<AI_Response__c>> responsesByRecordId, 
                                    Map<String, AI_Response__c> parentByRecordId) {
        List<AI_Response__c> parentsToUpdate = new List<AI_Response__c>();
        
        for(String recordId : responsesByRecordId.keySet()) {
            List<AI_Response__c> responses = responsesByRecordId.get(recordId);
            AI_Response__c parent = parentByRecordId.get(recordId);
            
            if(parent != null && parent.Id != null) {
                Integer promptToken = 0;
                Integer completionToken = 0;
                
                for(AI_Response__c resp : responses) {
                    completionToken += (resp.Completion_Tokens__c != null ? Integer.valueOf(resp.Completion_Tokens__c) : 0);
                    promptToken += (resp.Prompt_Tokens__c != null ? Integer.valueOf(resp.Prompt_Tokens__c) : 0);
                }
                
                AI_Response__c parentToUpdate = new AI_Response__c(
                    Id = parent.Id,
                    Completion_Tokens__c = completionToken,
                    Prompt_Tokens__c = promptToken,
                    Status__c = AIConstants.RESP_STATUS_PROCESSED,
                    Is_Canvas_Response__c = true
                );
                
                parentsToUpdate.add(parentToUpdate);
            }
        }
        
        if(!parentsToUpdate.isEmpty()) {
            FLSCheck.getInstance().updateDML(parentsToUpdate);
        }
    }
    
    /**
     * Finish method called after all batches are processed.
     *
     * @param bc The Database.BatchableContext provided by the platform
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('AIResponseConsolidationBatch completed for Scheduled Run: ' + scheduledRunId);
    }
}