/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-13-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptRequestBatch implements Database.Batchable<sObject>, Database.Stateful{
    
    public AI_Prompt_Scheduler__c sch; 
    public AI_Scheduled_Run__c schRun; 
    
    /**
     * Constructs a new AIPromptRequestBatch.
     * 
     * @param sch The AI Prompt Scheduler object representing the scheduled prompt.
     * @param schRun The AI Scheduled Run object representing the scheduled run for the prompt.
     * 
     * This constructor is used to initialize a batch processing job for AI prompts. It takes
     * a scheduler object and a scheduled run object as parameters to set up the batch with
     * the necessary information for processing AI prompts.
     */
    public AIPromptRequestBatch(AI_Prompt_Scheduler__c sch, AI_Scheduled_Run__c schRun){
        this.sch = sch;
        this.schRun = schRun;
    }
	
    /**
     * This method is part of the Database.Batchable interface and is called at the beginning of the batch job.
     * It returns a Database.QueryLocator, which defines the scope of records to be processed by the batch job.
     *
     * @param BC The Database.BatchableContext parameter provides information about the context in which the batch job is executed.
     * @return Database.QueryLocator The query locator specifying the records to be processed in the batch job.
     */
    public Database.QueryLocator start(Database.BatchableContext BC){
        if(!Test.isRunningTest()){
            if(!ChatGPTUtills.checkLicensePlanActive(System.Label.LICENSES_PRO_PLAN)){
                throw new ChatGPTUtills.ApplicationException(String.format(System.Label.LICENESES_PLAN_ERROR_MESSAGE,new List<String> { System.Label.LICENSES_ENTERPRISE_PLAN }));
        	}
        }
        // @jira : 4662 Handle ORDER BY in Where Clause of Data Extraction
        String whereClause = AIUtility.getFormattedWhereClause(sch.Where_Clause__c,NULL,50000000,false);
        
        String query = 'SELECT Id FROM '+String.escapeSingleQuotes(sch.Prompt__r.Object__c)+whereClause;
        
        return Database.getQueryLocator(query);
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
    public void execute(Database.BatchableContext BC, List<sObject> scope){
        List<AI_Response__c> lstOfResponses = new List<AI_Response__c>();
        for(sObject so : scope){
            AI_Response__c resp = new AI_Response__c();
            resp.Start_Date_Time__c = System.Now();
            resp.Record_Id__c = String.valueOf(so.get('Id'));
            resp.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
            resp.Prompt_Scheduler__c = sch.Id;
            resp.Scheduled_Run__c = schRun.Id;
            lstOfResponses.add(resp);
        }
        if(!lstOfResponses.isEmpty()){
            FLSCheck.getInstance().insertDML(lstOfResponses);
        }
        
        AI_Scheduled_Run__c scheduledRun = [SELECT Id, Status__c, InProgress_Records__c FROM AI_Scheduled_Run__c WHERE Id=:schRun.Id];
        if(scheduledRun.Status__c == 'Not Started'){
            scheduledRun.Status__c = 'In Progress';
        }
        if(scheduledRun.InProgress_Records__c == null){
            scheduledRun.InProgress_Records__c = 0;
        }
        scheduledRun.InProgress_Records__c += lstOfResponses.size();
        FLSCheck.getInstance().updateDML(new List<AI_Scheduled_Run__c>{scheduledRun});
    }
    
    /**
     * Finish method called after all batches are processed.
     *
     * @param BC The Database.BatchableContext provided by the platform.
     *           It can be used to get information about the current batch job execution.
     */
    public void finish(Database.BatchableContext BC){
        ChatGPTUtills.rollupAIResponseScheduledRun(schRun.Id);
        Database.executeBatch(new AIPromptDataExtractionBatch(sch, schRun), 1);
    }
    
}