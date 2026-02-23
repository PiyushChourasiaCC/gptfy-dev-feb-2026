/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 09-09-2024
* @last modified by  : Adarsh Sharma
**/
public with sharing class AIPromptAbortBatch implements Database.Batchable<sObject>, Database.Stateful{

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
    public AIPromptAbortBatch(String schRunId){
        this.schRunId = schRunId;
    }
	
    /**
     * This method is part of the Database.Batchable interface and is called at the beginning of the batch job.
     * It returns a Database.QueryLocator, which defines the scope of records to be processed by the batch job.
     *
     * @param BC The Database.BatchableContext parameter provides information about the context in which the batch job is executed.
     * @return Database.QueryLocator The query locator specifying the records to be processed in the batch job.
     */
    public Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator([
            SELECT Id, Status__c, Message__c
            FROM AI_Response__c 
            WHERE Scheduled_Run__c =:schRunId
            AND Status__c != :AIConstants.RESP_STATUS_PROCESSED
        ]);
    }
    
    /**
     * Executes the batch job for processing a batch of Salesforce records.
     *
     * This method is called by the Salesforce Batch Apex framework to process a batch
     * of records specified by the `scope` parameter.
     *
     * @param BC The execution context for the batch job, providing information about the
     *           current execution, such as job ID and job scope.
     * @param scope The list of Salesforce sObjects representing the batch of records to be processed.
     *              This list is determined by the queryLocator specified in the start method.
     */
    public void execute(Database.BatchableContext BC, List<AI_Response__c> scope){
        for(AI_Response__c response : scope){
            response.Status__c = AIConstants.RESP_STATUS_ERROR;
            response.Message__c = AIConstants.SCH_STATUS_CANCELLED;
        }
        FLSCheck.getInstance().updateDML(scope);
    }
    
    /**
     * Finish method called after all batches are processed.
     *
     * @param BC The Database.BatchableContext provided by the platform.
     *           It can be used to get information about the current batch job execution.
     */
    public void finish(Database.BatchableContext BC){
        ChatGPTUtills.rollupAIResponseScheduledRun(schRunId);
    }
    
}