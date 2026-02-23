/**
 * @description Handler class for AIScheduledRunTrigger that processes completed scheduled runs
 *              and initiates consolidation of AI_Response__c records.
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 12-02-2024
 * @last modified by Piyush Chourasia
 */
public with sharing class AIScheduledRunTriggerHandler {
    
    /**
     * This method is triggered after updating records of the custom object AI_Scheduled_Run__c.
     * It processes completed scheduled runs by initiating a batch job to consolidate AI responses.
     *
     * @param newList A List of AI_Scheduled_Run__c records that have been updated.
     * @param oldMap  A Map containing the old versions of the AI_Scheduled_Run__c records, with their Ids as keys.
     */
    public static void onAfterUpdate(List<AI_Scheduled_Run__c> newList, Map<Id, AI_Scheduled_Run__c> oldMap){
        processCompletedScheduledRuns(newList, oldMap);
    }
    
    /**
     * Processes completed scheduled runs by launching a batch job for each completed run.
     * This method identifies scheduled runs that have transitioned to 'Completed' status
     * and initiates consolidation of AI_Response__c records.
     *
     * @param newList The list of updated AI_Scheduled_Run__c records.
     * @param oldMap  A map containing the old versions of AI_Scheduled_Run__c records, with their Ids as keys.
     */
    public static void processCompletedScheduledRuns(List<AI_Scheduled_Run__c> newList, Map<Id, AI_Scheduled_Run__c> oldMap){
        List<Id> completedScheduledRunIds = new List<Id>();
        
        for(AI_Scheduled_Run__c scheduledRun : newList){
            AI_Scheduled_Run__c oldScheduledRun = oldMap.get(scheduledRun.Id);
            
            // Check if status changed to 'Completed'
            if(oldScheduledRun != null && 
               scheduledRun.Status__c == AIConstants.SCH_STATUS_COMPLETED && 
               oldScheduledRun.Status__c != AIConstants.SCH_STATUS_COMPLETED){
                completedScheduledRunIds.add(scheduledRun.Id);
            }
        }
        
        // Execute batch for each completed scheduled run
        if(!completedScheduledRunIds.isEmpty()){
            for(Id scheduledRunId : completedScheduledRunIds){
                Database.executeBatch(new AIResponseConsolidationBatch(scheduledRunId), 50);
            }
        }
    }
}