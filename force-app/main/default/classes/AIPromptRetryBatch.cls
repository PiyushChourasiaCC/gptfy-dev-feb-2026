/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-13-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptRetryBatch implements Database.Batchable<sObject>, Database.Stateful, Database.AllowsCallouts {
	
    public AI_Scheduled_Run__c schRun;
    public AI_Prompt_Scheduler__c sch;
    public AI_Prompt__c aiPrompt;
    
    /**
     * Constructs a new instance of the AIPromptRetryBatch class.
     *
     * This constructor is used to create a batch job for retrying AI prompts,
     * based on the information provided in the AI_Scheduled_Run__c object.
     *
     * @param schRun The AI_Scheduled_Run__c object containing the information
     *               needed to configure the batch job for retrying AI prompts.
     */
    public AIPromptRetryBatch(AI_Scheduled_Run__c schRun, AI_Prompt_Scheduler__c sch){
        this.schRun = schRun;
        this.sch = sch;
    }
    
    /**
     * The start method is part of the Database.Batchable interface in Salesforce Apex.
     * It is called at the beginning of the batch job and is responsible for providing
     * the query locator that defines the scope of records to be processed in the batch.
     *
     * @param BC The Database.BatchableContext parameter provides access to the context
     *           information for the batch job.
     * @return Database.QueryLocator The query locator object that defines the set of
     *         records to be processed in the batch. This could be a SOQL query or a
     *         dynamic query locator.
     */
    public Database.QueryLocator start(Database.BatchableContext BC){
        sch = [SELECT Id, Cross_Object_Filter_Condition__c, Prompt__c FROM AI_Prompt_Scheduler__c WHERE Id=:sch.Id];
        aiPrompt = AIPromptSelector.getAIPromptById(sch.Prompt__c);
        
        return Database.getQueryLocator([
            SELECT Id, AI_Prompt__c, Record_Id__c
            FROM AI_Response__c 
            WHERE Scheduled_Run__c =:schRun.Id
            AND Status__c =:AIConstants.RESP_STATUS_ERROR
        ]);
    }
    
    /**
     * This method is part of a Salesforce Batch Apex class and is invoked to process a batch of AI_Response__c records.
     * It performs the actual processing logic on the provided batch of records.
     *
     * @param BC The context for the batch job, providing information about the execution environment.
     * @param scope A list of AI_Response__c records representing the batch of data to be processed.
     */
    public void execute(Database.BatchableContext BC, List<AI_Response__c> scope){
        /*for(AI_Response__c resp : scope){
            resp.Status__c = AIConstants.RESP_STATUS_DATA_EXT;
        }
        FLSCheck.getInstance().updateDML(scope);*/
        AI_Response__c resp = scope.get(0);
        resp = ChatGPTUtills.getDataUsingFiles(resp);
        resp.Id = scope.get(0).Id;
        try{ 
            
            Boolean isValid = true;
            String message;
            
            //checking visibility condition and record types for qualification of record.
            List<String> recordTypes = String.isNotBlank(aiPrompt.Record_Type__c) ? aiPrompt.Record_Type__c.split(';') : null;
            if(String.isNotBlank(aiPrompt.Visibility_Condition__c) || (recordTypes != null && !recordTypes.isEmpty())){
                isValid = GPTfyConsoleController.isValidVisibilityCondition(aiPrompt.Object__c, resp.Record_Id__c, aiPrompt.Visibility_Condition__c, recordTypes);
                message = !isValid ? 'Disqualified from Visibility Condition.' : '';
            }
            
            //checking cross object filter condition and record types for qualification of record.
            if(String.isNotBlank(sch.Cross_Object_Filter_Condition__c)){
                List<AI_Cross_Object_Filter__c> filters = AICrossObjectFilterService.getCrossObjectFilters(sch.Id);
                if(filters != null && !filters.isEmpty()){
                    Set<String> qualifiedIds = AICrossObjectFilterService.init(
                        sch.Cross_Object_Filter_Condition__c, 
                        filters, 
                        new Set<String>{resp.Record_Id__c}
                    );
                    if(qualifiedIds == null || qualifiedIds.isEmpty() || !qualifiedIds.contains(resp.Record_Id__c)){
                        isValid = false;
                        message = !isValid ? 'Disqualified from Cross Object Filters.' : '';
                    }
                }  
            }
            
            if(!isValid){
                resp.Status__c = AIConstants.RESP_STATUS_DISQ;
                resp.Message__c = message;
            }else{
                resp = ChatGPTUtills.getExtractedData(resp.Record_Id__c, aiPrompt, null, resp); 
            	resp.Status__c = AIConstants.RESP_STATUS_DATA_EXT;
            }
            FLSCheck.getInstance().updateDML(new List<AI_Response__c>{resp});
            ChatGPTUtills.rollupAIResponseScheduledRun(schRun.Id);
        }catch(Exception e){
            resp.Status__c = AIConstants.RESP_STATUS_ERROR;
            resp.Message__c = e.getMessage();
            FLSCheck.getInstance().updateDML(new List<AI_Response__c>{resp});
            ChatGPTUtills.rollupAIResponseScheduledRun(schRun.Id);
        }
    }
    
    /**
     * This method is called when the batch job finishes its execution.
     * It provides an opportunity to perform any cleanup or finalization tasks.
     *
     * @param BC The BatchableContext object, providing information about the batch job context.
     */
    public void finish(Database.BatchableContext BC){
        ChatGPTUtills.rollupAIResponseScheduledRun(schRun.Id);
        AI_Scheduled_Run__c scheduleRun = [SELECT Id, Status__c FROM AI_Scheduled_Run__c WHERE Id=:schRun.Id];
        if(scheduleRun.Status__c != AIConstants.SCH_STATUS_CANCELLED){
            for(AI_Prompt_Scheduler__c sc : [SELECT Id, Prompt__c, Where_Clause__c, Record_Limit__c,
                                             AI_Scheduler__c, AI_Scheduler__r.Retry_Count__c
                                             FROM AI_Prompt_Scheduler__c 
                                             WHERE AI_Scheduler__c =:schRun.Scheduler__c
                                             AND Prompt__r.Status__c = 'Active']){
                Database.executeBatch(new AIPromptProcessingBatch(sc, schRun), 1);
            }
        }
    }
}