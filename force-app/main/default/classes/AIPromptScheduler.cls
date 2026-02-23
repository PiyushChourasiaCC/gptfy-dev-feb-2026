/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-13-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptScheduler implements Schedulable {
    
    public String schedulerId;
    
    /**
     * Constructs an instance of the AIPromptScheduler class with the specified scheduler identifier.
     *
     * @param schedulerId The unique identifier for the scheduler.
     */
    public AIPromptScheduler(String schedulerId){
        this.schedulerId = schedulerId;
    }
    
    /**
     * Executes a task using the provided SchedulableContext.
     *
     * @param SC The SchedulableContext that provides context information for scheduling tasks.
     */
    public void execute(SchedulableContext SC) {
        AI_Scheduled_Run__c obj = new AI_Scheduled_Run__c();
        obj.Run_Date_Time__c = System.Now();
        obj.Scheduler__c = schedulerId;
        obj.Current_Retry_Count__c = 0;
        obj.Total_Records__c = 0;
        obj.InProgress_Records__c = 0; 
        obj.Errored_Records__c = 0;
        obj.Status__c = 'Not Started';
        if(SC != null && SC.getTriggerId() != null){
            obj.Job_Ids__c = SC.getTriggerId();
        }
        
        obj = (AI_Scheduled_Run__c)FLSCheck.getInstance().insertDML(new List<AI_Scheduled_Run__c>{obj}).get(0);
        
        for(AI_Prompt_Scheduler__c sch : [SELECT Id, Prompt__c, Where_Clause__c, Record_Limit__c,
                                          Prompt__r.Object__c, Prompt__r.AI_Connection__c, 
                                          Prompt__r.AI_Connection__r.Name, Prompt__r.Prompt_Command__c,
                                          AI_Scheduler__c, AI_Scheduler__r.Retry_Count__c, Object_Name__c,
                                          Cross_Object_Filter_Condition__c
                                          FROM AI_Prompt_Scheduler__c 
                                          WHERE AI_Scheduler__c =:schedulerId
                                          AND Prompt__r.Status__c =:AIConstants.PMT_STATUS_ACTIVE]){
            DateTime start = System.Now();
        	while(System.Now().getTime()< start.getTime()+2000){}
            Database.executeBatch(new AIPromptCountRequestBatch(sch, obj), 2000);
        }
    }

    /**
     * Executes a task immediately for the specified record.
     * 
     * @param recordId The identifier of the record for which the task should be run.
     *                 This parameter uniquely identifies the record in the system.
     */
    @AuraEnabled
    public static void runNow(String recordId){
        try{
            AIPromptScheduler job = new AIPromptScheduler(recordId);
			job.execute(null);
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptScheduler', 'runNow', '');
            throw new AuraHandledException(e.getMessage());
        } 
    }

}