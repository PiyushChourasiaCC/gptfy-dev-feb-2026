/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-13-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptDataExtractionBatch implements Database.Batchable<sObject>, Database.Stateful, Database.AllowsCallouts{
    
    public AI_Prompt_Scheduler__c sch;
    public AI_Prompt__c aiPrompt;
    public AI_Scheduled_Run__c schRun;
    
    /**
     * Constructs an instance of AIPromptDataExtractionBatch.
     *
     * This constructor is used to create a batch job for extracting data related to AI prompts.
     * It takes a scheduler object (sch) and a scheduled run object (schRun) as parameters.
     *
     * @param sch The AI prompt scheduler configuration that determines the prompts to be processed.
     * @param schRun The specific scheduled run details, including the start time and other run-related information.
     */
    public AIPromptDataExtractionBatch(AI_Prompt_Scheduler__c sch, AI_Scheduled_Run__c schRun){
        this.sch = sch;
        this.schRun = schRun;
    }
	
    /**
     * The start method is called at the beginning of the batch job execution.
     * It is responsible for providing a query locator, which defines the scope
     * of records that will be processed by the batch job.
     *
     * @param BC The Database.BatchableContext parameter provides access to the
     *           execution context of the batch job.
     * @return Database.QueryLocator The query locator specifying the records to
     *         be processed by the batch job.
     */
    public Database.QueryLocator start(Database.BatchableContext BC){
        aiPrompt = AIPromptSelector.getAIPromptById(sch.Prompt__c);
        
        return Database.getQueryLocator([
            SELECT Id, AI_Prompt__c, Record_Id__c
            FROM AI_Response__c 
            WHERE Prompt_Scheduler__c =:sch.Id
            AND Status__c =:AIConstants.RESP_STATUS_INPROGRESS
            AND Scheduled_Run__c =:schRun.Id
        ]);
    }
    
    /**
     * This method is part of a Salesforce Batch Apex class and is responsible for processing a batch of AI_Response__c records.
     * It is called by the Salesforce platform to execute the logic defined in the batch job.
     *
     * @param BC The Database.BatchableContext parameter provides contextual information for the batch job.
     * @param scope The List<AI_Response__c> parameter represents the batch of AI_Response__c records to be processed.
     */
    public void execute(Database.BatchableContext BC, List<AI_Response__c> scope){
        AI_Response__c resp = scope.get(0);
        resp = ChatGPTUtills.getDataUsingFiles(resp);
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
            ChatGPTUtills.insertAIResponse(resp, true);
            ChatGPTUtills.rollupAIResponseScheduledRun(schRun.Id);
        }catch(Exception e){
            resp.Status__c = AIConstants.RESP_STATUS_ERROR;
            resp.Message__c = e.getMessage();
            resp = ChatGPTUtills.insertAIResponse(resp, false);
            ChatGPTUtills.rollupAIResponseScheduledRun(schRun.Id);
        }
    }
    
    /**
     * This method is called when a batch execution finishes.
     * It provides an implementation of the finish method in the Database.Batchable interface.
     *
     * @param BC The Database.BatchableContext parameter provides context information
     *           for the batch job, such as the jobId and jobInstanceId.
     */
    public void finish(Database.BatchableContext BC){
        Database.executeBatch(new AIPromptProcessingBatch(sch, schRun), 1);
    }
    
}