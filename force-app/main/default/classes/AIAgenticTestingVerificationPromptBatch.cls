/**
* @description       : This class used to verification Prompt for Test Cycle Results
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 22-10-2025
* @last modified by  : Adarsh Sharma
* @JIRA V2-7163 : Agentic Testing Framework
**/
public with sharing class AIAgenticTestingVerificationPromptBatch implements Database.Batchable<sObject>, Database.Stateful, Database.AllowsCallouts {
	
    public Set<String> testCycleIds;
    public Map<String, String> mapTestCycleIdWithStatus;
    
    public AIAgenticTestingVerificationPromptBatch(Set<String> testCycleIds){
        this.testCycleIds = testCycleIds;
        this.mapTestCycleIdWithStatus = new Map<String, String>();
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
        String sSOQL = 'SELECT Id, Name, AI_Security_Audit__c, AI_Test_Cycle__c, AI_Verification_Security_Audit__c,'
            			+' Message__c, AI_Test_Cycle__r.AI_Verification_Prompt__c'
            			+' FROM AI_Test_Cycle_Result__c'
            			+' WHERE AI_Test_Cycle__c IN: testCycleIds AND AI_Security_Audit__c != null '
            			+' AND AI_Test_Cycle__r.AI_Verification_Prompt__c != null ';
        return Database.getQueryLocator(sSOQL);
    }
    
    /**
     * Executes the batch job for processing a batch of AI_Test_Cycle_Result__c records.
     *
     * This method is called by the Salesforce Batch Apex framework when the batch job is executed.
     *
     * @param BC The batchable context provided by the Salesforce platform, allowing access to
     *           contextual information and control over the batch job.
     * @param scope The list of AI_Test_Cycle_Result__c records that are part of the current batch being processed.
     *              The size of the batch is determined by the Salesforce platform.
     */
    public void execute(Database.BatchableContext BC, List<AI_Test_Cycle_Result__c> scope){
        for(AI_Test_Cycle_Result__c testCycleResult : scope){
            AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(testCycleResult.AI_Test_Cycle__r.AI_Verification_Prompt__c);
            try{
                AI_Response__c resp;
                if(aiPrompt.Include_Files__c == true && aiPrompt.AI_Model_File_Processing__r.Model__c == 'gpt-4.1'){
                    resp = ChatGPTUtills.processResponsesFileRequest(aiPrompt.Id, testCycleResult.AI_Security_Audit__c, '', new AI_Response__c());
                }else{
                    resp = ChatGPTUtills.initiateGPT(testCycleResult.AI_Security_Audit__c, aiPrompt.Id, '', null, false);
                }
                if(resp != null){
                    testCycleResult.AI_Verification_Security_Audit__c = resp.Id;
                    testCycleResult.Message__c = '';
                    if(!mapTestCycleIdWithStatus.containsKey(testCycleResult.AI_Test_Cycle__c)){
                        mapTestCycleIdWithStatus.put(testCycleResult.AI_Test_Cycle__c, 'Processed');
                    }
                }
            }catch(Exception ex){
                testCycleResult.Message__c = ex.getMessage();
                mapTestCycleIdWithStatus.put(testCycleResult.AI_Test_Cycle__c, 'Errored');
            }
        }
        FLSCheck.getInstance().updateDML(scope);
    }
    
    /**
     * Finish method called after the execution of the batch job.
     *
     * @param BC Database.BatchableContext parameter providing context information for the batch job.
     *           Use this context to perform any cleanup or finalization tasks.
     */
    public void finish(Database.BatchableContext BC){
        List<AI_Test_Cycle__c> aiTestCycleToUpdate = new List<AI_Test_Cycle__c>();
        if(testCycleIds.size()>0){
            for(AI_Test_Cycle__c testCycle : [SELECT Id, Status__c, End_Date_Time__c, Message__c FROM AI_Test_Cycle__c WHERE Id IN: testCycleIds]){
                String status = testCycle.Status__c;
                String message = '';
                if(mapTestCycleIdWithStatus.containsKey(testCycle.Id) && status != 'Errored'){
                    status = mapTestCycleIdWithStatus.get(testCycle.Id);
                    message = (status=='Errored'?'Security Audit verification failed!':'');
                }
                testCycle.Status__c = (status!='Errored'?'Processed':status);
                testCycle.End_Date_Time__c = DateTime.now();
                if(!String.isBlank(message)){
                    testCycle.Message__c = message;
                }
                aiTestCycleToUpdate.add(testCycle);
            }
        }
        if(aiTestCycleToUpdate.size()>0){ 
            FLSCheck.getInstance().updateDML(aiTestCycleToUpdate);
        }
    }
}