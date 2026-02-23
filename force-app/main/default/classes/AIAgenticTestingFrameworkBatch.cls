/**
* @description       : This class used to Test Cycle for Agentic or Prompt
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 06-10-2025
* @last modified by  : Adarsh Sharma
* @JIRA V2-7163 : Agentic Testing Framework
**/
public with sharing class AIAgenticTestingFrameworkBatch implements Database.Batchable<sObject>, Database.Stateful, Database.AllowsCallouts {

    public String aiTestCycleId;
    public Set<String> testCycleIds;
    public List<agenticFrameworkInputWrapper> agenticFrameworkInputs;

    public AIAgenticTestingFrameworkBatch(){}
    
    public AIAgenticTestingFrameworkBatch(String aiTestCycleId){
        this.aiTestCycleId = aiTestCycleId;
        this.testCycleIds = new Set<String>();
        this.agenticFrameworkInputs = new List<agenticFrameworkInputWrapper>();
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
        String sSOQL = 'SELECT Id, Name, Status__c, Start_Date_Time__c, End_Date_Time__c,'
            			+' Description__c, AI_Agent__c, AI_Prompt__c, AI_Verification_Prompt__c,'
            			+' AI_Agent__r.Developer_Name__c, '
            			+' Message__c FROM AI_Test_Cycle__c'
            			+' WHERE (Status__c = \'Draft\' OR Status__c =\'In Progress\' OR Status__c =\'Errored\') '
            			+' AND Id=:aiTestCycleId ';
        return Database.getQueryLocator(sSOQL);
    }
    
    /**
     * Executes the batch job for processing a batch of AI_Test_Cycle__c records.
     *
     * This method is called by the Salesforce Batch Apex framework when the batch job is executed.
     *
     * @param BC The batchable context provided by the Salesforce platform, allowing access to
     *           contextual information and control over the batch job.
     * @param scope The list of AI_Test_Cycle__c records that are part of the current batch being processed.
     *              The size of the batch is determined by the Salesforce platform.
     */
    public void execute(Database.BatchableContext BC, List<AI_Test_Cycle__c> scope){
        try{
            Map<String, String> mapTestCycleContentDocumentId = getTestCycleContentDocumentId(scope);
            Map<String, String> mapTestCycleFile = getTestCycleFile(mapTestCycleContentDocumentId);
            scope = executeTestCycles(scope, mapTestCycleContentDocumentId, mapTestCycleFile);
            FLSCheck.getInstance().updateDML(scope);
        }catch(Exception e){
            AI_Test_Cycle__c ts = updateTestCycleFields(scope.get(0), 'Errored', e.getMessage(), DateTime.now());
            FLSCheck.getInstance().updateDML(new List<AI_Test_Cycle__c>{ts});
        }
    }
    
    /**
     * Finish method called after the execution of the batch job.
     *
     * @param BC Database.BatchableContext parameter providing context information for the batch job.
     *           Use this context to perform any cleanup or finalization tasks.
     */
    public void finish(Database.BatchableContext BC){
        if(agenticFrameworkInputs.size()>0){
            Database.executeBatch(new AIAgenticTestingExecutionBatch(agenticFrameworkInputs, testCycleIds), 1);
        }
    }
    
    public Map<String, String> getTestCycleContentDocumentId(List<AI_Test_Cycle__c> scope){
        Set<String> setParentId = getParentTestCycleIds(scope);
        Map<String, String> mapTestCycleContentDocumentId = new Map<String, String>();
		for(ContentDocumentLink cdl : [SELECT Id, LinkedEntityId, ContentDocumentId FROM ContentDocumentLink 
                                       WHERE LinkedEntityId IN:setParentId
                                      ORDER BY ContentDocument.LastModifiedDate DESC]){
            if(!mapTestCycleContentDocumentId.containsKey(cdl.LinkedEntityId)){
                mapTestCycleContentDocumentId.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
            }
        }        
        return mapTestCycleContentDocumentId;
    }
    
    public Set<String> getParentTestCycleIds(List<AI_Test_Cycle__c> testCycles){
        Set<String> setParentId = new Set<String>();
        for(AI_Test_Cycle__c testCycle : testCycles){
            setParentId.add(testCycle.Id);
        }
        return setParentId;
    }
    
    public Map<String, String> getTestCycleFile(Map<String, String> mapTestCycleContentDocumentId){
        Map<String, String> mapTestCycleFile = new Map<String, String>();
        if(!mapTestCycleContentDocumentId.IsEmpty()){
            for(ContentVersion cv : [SELECT ContentDocumentId, VersionData FROM ContentVersion 
                                     WHERE ContentDocumentId IN:mapTestCycleContentDocumentId.values()]){
                if(!mapTestCycleFile.containsKey(cv.ContentDocumentId)){
                    mapTestCycleFile.put(cv.ContentDocumentId, cv.VersionData.toString());
                }
            }
        }
        return mapTestCycleFile;
    }
    
    public AI_Test_Cycle__c updateTestCycleFields(AI_Test_Cycle__c testCycle, String status, String message, DateTime endTime){
        testCycle.Status__c = status;
        testCycle.Message__c = message;
        testCycle.End_Date_Time__c = endTime;
        return testCycle;
    }
    
    public List<AI_Test_Cycle__c> executeTestCycles(List<AI_Test_Cycle__c> scope, Map<String, String> mapTestCycleContentDocumentId, Map<String, String> mapTestCycleFile){
        //Validate attach files - AIPromptProcessingBatch
        for(AI_Test_Cycle__c testCycle : scope){
            if(mapTestCycleContentDocumentId.containsKey(testCycle.Id)){
                String fileData = mapTestCycleFile.get(mapTestCycleContentDocumentId.get(testCycle.Id));
                if(!String.isBlank(fileData)){
                    if(testCycle.AI_Agent__c != null){
                        boolean isValid = isValidFileData(fileData, true);
                        if(isValid){
                            try{
                                testCycle = executeAgentTestCycle(testCycle, fileData);
                                testCycleIds.add(testCycle.Id);
                            }catch(Exception ex){
                                testCycle = updateTestCycleFields(testCycle, 'Errored', ex.getMessage(), DateTime.now());
                            }
                        }else{
                            testCycle = updateTestCycleFields(testCycle, 'Errored', 'Invalid Test Cycle! Attach File have invalid data to process the Test Cycle.', DateTime.now());
                        }
                    }else if(testCycle.AI_Prompt__c != null){
                        boolean isValid = isValidFileData(fileData, false);
                        if(isValid){
                            try{
                                executePromptTestCycle(testCycle, fileData);
                                testCycleIds.add(testCycle.Id);
                            }catch(Exception ex){
                                testCycle = updateTestCycleFields(testCycle, 'Errored', ex.getMessage(), DateTime.now());
                            }
                        }else{
                            testCycle = updateTestCycleFields(testCycle, 'Errored', 'Invalid Test Cycle! Attach File have invalid data to process the Test Cycle.', DateTime.now());
                        }
                    }else{
                        testCycle = updateTestCycleFields(testCycle, 'Errored', 'Invalid Test Cycle! Agent or Prompt is not configured on Test Cycle.', DateTime.now());
                    }
                }else{
                    testCycle = updateTestCycleFields(testCycle, 'Errored', 'Invalid Test Cycle! Attach File have invalid data to process the Test Cycle.', DateTime.now());
                }
            }else{
                testCycle = updateTestCycleFields(testCycle, 'Errored', 'Invalid Test Cycle! There is no File attach to process the Test Cycle.', DateTime.now());
            }
            //testCycle.End_Date_Time__c = DateTime.now(); 
        }
        return scope;
    }
    
    public boolean isValidFileData(String fileData, Boolean isAgent){
        boolean isValid = false;
        try{
            // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
            if(isAgent){
                List<inputAgentWrapper> inputWrapper = (List<inputAgentWrapper>)JSON.deserialize(fileData, List<inputAgentWrapper>.class);
                if(inputWrapper != null && inputWrapper.size() > 0){
                    for(inputAgentWrapper wrapper : inputWrapper){
                        if(wrapper.input == null || wrapper.input.isEmpty()){
                            return false;
                        }
                    }
                    isValid = true;
                }
            }else{
                List<inputPromptWrapper> inputWrapper = (List<inputPromptWrapper>)JSON.deserialize(fileData, List<inputPromptWrapper>.class);
                if(inputWrapper != null && inputWrapper.size() > 0){
                    for(inputPromptWrapper wrapper : inputWrapper){
                        if(String.isBlank(wrapper.input)){
                            return false;
                        }
                    }
                    isValid = true;
                }
            }
        }catch(Exception ex){
            isValid = false;
        }
        return isValid;
    }
    
    public AI_Test_Cycle__c executeAgentTestCycle(AI_Test_Cycle__c testCycle, String fileData){
        List<inputAgentWrapper> inputWrapper = (List<inputAgentWrapper>)JSON.deserialize(fileData, List<inputAgentWrapper>.class);
        if(inputWrapper != null && inputWrapper.size()>0){
            //testCycle.Status__c = 'Processed';
            testCycle.Message__c = null;
            for(inputAgentWrapper iaw : inputWrapper){
                AI_Test_Cycle_Result__c cycleResult = new AI_Test_Cycle_Result__c();
                cycleResult.AI_Test_Cycle__c = testCycle.Id;
                cycleResult.External_Id__c = iaw.externalId;
                cycleResult.Input__c = JSON.serializePretty(iaw.input);
                cycleResult.Message__c = '';
                String userContextId = '';
                for(String question : iaw.input){
                    agenticFrameworkInputWrapper wrap = new agenticFrameworkInputWrapper();
                    wrap.isAgent = true;
                    wrap.agentId = testCycle.AI_Agent__c;
                    wrap.verificationPromptId = testCycle.AI_Verification_Prompt__c;
                    wrap.testCycleId = testCycle.Id;
                    wrap.externalId = iaw.externalId;
                    wrap.input = question;
                    wrap.inputData = JSON.serializePretty(iaw.input);
                    wrap.agentDeveloperName = testCycle.AI_Agent__r.Developer_Name__c;
                    wrap.userContextId = '';
                    agenticFrameworkInputs.add(wrap);
                }
            }
        }
        return testCycle;
    }
    
    public AI_Test_Cycle__c executePromptTestCycle(AI_Test_Cycle__c testCycle, String fileData){
        List<AI_Test_Cycle_Result__c> aiTestCycleResultToInsert = new List<AI_Test_Cycle_Result__c>();
        List<inputPromptWrapper> inputWrapper = (List<inputPromptWrapper>)JSON.deserialize(fileData, List<inputPromptWrapper>.class);
        if(inputWrapper != null && inputWrapper.size()>0){
            //testCycle.Status__c = 'Processed';
            testCycle.Message__c = null;
            AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(testCycle.AI_Prompt__c);
            for(inputPromptWrapper iaw : inputWrapper){
                agenticFrameworkInputWrapper wrap = new agenticFrameworkInputWrapper();
                wrap.isAgent = false;
                wrap.promptId = testCycle.AI_Prompt__c;
                wrap.verificationPromptId = testCycle.AI_Verification_Prompt__c;
                wrap.testCycleId = testCycle.Id;
                wrap.externalId = iaw.externalId;
                wrap.input = iaw.input;
                wrap.inputData = JSON.serializePretty(iaw.input);
                wrap.agentDeveloperName = testCycle.AI_Agent__r.Developer_Name__c;
                wrap.userContextId = '';
                agenticFrameworkInputs.add(wrap);
            }
        }
        return testCycle;
    }
    
    public class inputAgentWrapper{
        public String externalId;
        public List<String> input;
    }
    
    public class inputPromptWrapper{
        public String externalId;
        public String input;
    }
    
    public class agenticFrameworkInputWrapper{
        public boolean isAgent;
        public String agentId;
        public String promptId;
        public String verificationPromptId;
        public String testCycleId;
        public String externalId;
        public String input;
        public String inputData;
        public String agentDeveloperName;
        public String userContextId;
        public String status;
        public String message;
        public String aISecurityAudit;
    }
    
}