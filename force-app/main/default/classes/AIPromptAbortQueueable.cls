/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 11-05-2024
* @last modified by  : Adarsh Sharma
**/
public with sharing class AIPromptAbortQueueable implements Queueable {
    
    public String schRunId; 
    
    /**
     * Constructs a new AIPromptRequestBatch.
     * 
     * @param schRunId The AI Scheduled Run object representing the scheduled run for the prompt.
     * 
     * This constructor is used to initialize a batch processing job for Security Audit. It takes
     * a scheduled run object as parameters to set up the batch with
     * the necessary information for processing Security Audit.
     */
    public AIPromptAbortQueueable(String schRunId){
        this.schRunId = schRunId;
    }
    
    public void execute(QueueableContext context) {
        for(AsyncApexJob asyncJob : [SELECT Id, CronTriggerId FROM AsyncApexJob WHERE ApexClass.Name IN:AIConstants.SCH_BATCH_CLASSES AND Status!=:AIConstants.SCH_STATUS_ABORTED AND Status!=:AIConstants.SCH_STATUS_COMPLETED]){
            system.abortJob((asyncJob.CronTriggerId!=null?asyncJob.CronTriggerId:asyncJob.Id));
        }
        
        AI_Scheduled_Run__c schRun = [SELECT Id, Scheduler__c FROM AI_Scheduled_Run__c WHERE Id =:schRunId LIMIT 1];
        schRun.Status__c = AIConstants.SCH_STATUS_CANCELLED;
        FLSCheck.getInstance().updateDML(new List<AI_Scheduled_Run__c>{schRun});
        
        Database.executeBatch(new AIPromptAbortBatch(schRunId), 200);
    }
}