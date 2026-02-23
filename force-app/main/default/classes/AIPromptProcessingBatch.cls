/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-13-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptProcessingBatch implements Database.Batchable<sObject>, Database.Stateful, Database.AllowsCallouts {
    
    public AI_Prompt_Scheduler__c sch;
    public AI_Prompt__c aiPrompt;
    public AI_Scheduled_Run__c schRun;
    
    /**
     * Constructs a new instance of the AIPromptProcessingBatch class.
     *
     * This constructor is used to initialize an object of the AIPromptProcessingBatch class.
     * It takes two parameters, an AI_Prompt_Scheduler__c object (sch) and an AI_Scheduled_Run__c object (schRun),
     * which represent the AI prompt scheduler and the scheduled run associated with the batch processing.
     * 
     * @param sch The AI_Prompt_Scheduler__c object representing the AI prompt scheduler.
     * @param schRun The AI_Scheduled_Run__c object representing the scheduled run associated with the batch processing.
     */
    public AIPromptProcessingBatch(AI_Prompt_Scheduler__c sch, AI_Scheduled_Run__c schRun){
        this.sch = sch;
        this.schRun = schRun; 
    }
	
    /**
     * This method is required by the Database.Batchable interface and is called
     * to initiate the execution of a batch job. It returns a Database.QueryLocator
     * instance, which specifies the set of records that the batch job will process.
     *
     * @param BC The context variable for the batch job execution.
     * @return Database.QueryLocator representing the set of records to process.
     */
    public Database.QueryLocator start(Database.BatchableContext BC){
        aiPrompt = AIPromptSelector.getAIPromptById(sch.Prompt__c);
        
        return Database.getQueryLocator([
            SELECT Id, AI_Prompt__c, Record_Id__c, Data_PII_Removed__c, Data_Decrypt_PII_Key__c, Data_Original__c
            FROM AI_Response__c 
            WHERE Prompt_Scheduler__c =:sch.Id
            AND Status__c =:AIConstants.RESP_STATUS_DATA_EXT
            AND Scheduled_Run__c =:schRun.Id
        ]); 
    }
    
    /**
     * Executes the batch job for processing a batch of AI_Response__c records.
     *
     * This method is called by the Salesforce Batch Apex framework when the batch job is executed.
     *
     * @param BC The batchable context provided by the Salesforce platform, allowing access to
     *           contextual information and control over the batch job.
     * @param scope The list of AI_Response__c records that are part of the current batch being processed.
     *              The size of the batch is determined by the Salesforce platform.
     */
    public void execute(Database.BatchableContext BC, List<AI_Response__c> scope){
        AI_Response__c resp = scope.get(0);
        resp = ChatGPTUtills.getDataUsingFiles(resp);
        try{
            if(!AILicenseManagerController.isLicenseAvailable() && !Test.isRunningTest()){
            	throw new CustomException(Label.License_Consumption_Error);
            }else if(aiPrompt.Include_Files__c == true && AIConstants.RESPONSES_API_MODEL.contains(aiPrompt.AI_Model_File_Processing__r?.Model__c)){
                ChatGPTUtills.processResponsesFileRequest(aiPrompt.Id,resp.Record_Id__c,'',resp); 
            } else{
                ChatGPTUtills.processRequest(resp.Record_Id__c, aiPrompt, null, resp.Id, resp); 
            }
        }catch(Exception e){
            resp.Status__c = AIConstants.RESP_STATUS_ERROR;
            resp.Message__c = e.getMessage();
            resp = ChatGPTUtills.insertAIResponse(resp, false);
        }
        ChatGPTUtills.rollupAIResponseScheduledRun(schRun.Id);
    }
    
    /**
     * Finish method called after the execution of the batch job.
     *
     * @param BC Database.BatchableContext parameter providing context information for the batch job.
     *           Use this context to perform any cleanup or finalization tasks.
     */
    public void finish(Database.BatchableContext BC){
        List<AI_Response__c> lst = [SELECT Id FROM AI_Response__c 
                                    WHERE Prompt_Scheduler__c =:sch.Id
                                    AND Status__c !=:AIConstants.RESP_STATUS_ERROR
                                    AND Status__c !=:AIConstants.RESP_STATUS_PROCESSED
                                    AND Status__c !=:AIConstants.RESP_STATUS_DISQ
                                    AND Scheduled_Run__c =:schRun.Id];
        if(lst != null && !lst.isEmpty()){
            for(AI_Response__c resp : lst){
                resp.Status__c = AIConstants.RESP_STATUS_ERROR;
            } 
            FLSCheck.getInstance().updateDML(lst);
        }
        
        //checking for retries
        Integer totalRetryCount = 0;
        if(sch.AI_Scheduler__c != null && sch.AI_Scheduler__r.Retry_Count__c != null && sch.AI_Scheduler__r.Retry_Count__c > 0){
            totalRetryCount = (Integer)sch.AI_Scheduler__r.Retry_Count__c;
        }
        
        if(totalRetryCount > 0){
            Integer currentRetryCount = 0;
            AI_Scheduled_Run__c scheduleRunUpdate = [SELECT Id, Current_Retry_Count__c, Status__c FROM AI_Scheduled_Run__c WHERE Id=:schRun.Id];
            if(scheduleRunUpdate.Current_Retry_Count__c != null && scheduleRunUpdate.Current_Retry_Count__c > 0){
                currentRetryCount = (Integer)scheduleRunUpdate.Current_Retry_Count__c;
            }
            if(totalRetryCount > currentRetryCount && scheduleRunUpdate.Status__c != AIConstants.SCH_STATUS_CANCELLED){
                Integer open = [SELECT Count() FROM AI_Response__c 
                                WHERE Scheduled_Run__c =:schRun.Id
                                AND Status__c !=:AIConstants.RESP_STATUS_ERROR
                                AND Status__c !=:AIConstants.RESP_STATUS_PROCESSED
                               	AND Status__c !=:AIConstants.RESP_STATUS_DISQ];
                if(open != null && open > 0){
                    //do-nothing - this will be picked by the next parallel running job
                }else{
                    Integer errored = [SELECT Count() FROM AI_Response__c 
                                       WHERE Scheduled_Run__c =:schRun.Id
                                       AND Status__c =:AIConstants.RESP_STATUS_ERROR];
                    if(errored != null && errored > 0){
                        schRun.Current_Retry_Count__c += 1;                        
                        scheduleRunUpdate.Current_Retry_Count__c += 1;
                        scheduleRunUpdate = (AI_Scheduled_Run__c)FLSCheck.getInstance().updateDML(new List<AI_Scheduled_Run__c>{scheduleRunUpdate}).get(0);
                        
                        Database.executeBatch(new AIPromptRetryBatch(schRun, sch), 1);
                    }else{
                         updateScheduleRunStatus();
                    }
                }
            }else if(scheduleRunUpdate.Status__c != AIConstants.SCH_STATUS_CANCELLED){
                updateScheduleRunStatus();
            }
        }else{
            updateScheduleRunStatus();
        }
        ChatGPTUtills.rollupAIResponseScheduledRun(schRun.Id);
    }

    public void updateScheduleRunStatus(){
        Integer errorRecordCount = [SELECT Count() FROM AI_Response__c 
                                    WHERE Scheduled_Run__c =:schRun.Id
                                     AND Status__c =:AIConstants.RESP_STATUS_ERROR];
        AI_Scheduled_Run__c scheduledRun = [SELECT Id, Status__c FROM AI_Scheduled_Run__c WHERE Id=:schRun.Id];
        if(errorRecordCount > 0){
            scheduledRun.Status__c = 'Errored';
        }else{
            scheduledRun.Status__c = 'Completed';
        }
        FLSCheck.getInstance().updateDML(new List<AI_Scheduled_Run__c>{scheduledRun});
    }
    
    public class CustomException extends Exception {} 
    
}