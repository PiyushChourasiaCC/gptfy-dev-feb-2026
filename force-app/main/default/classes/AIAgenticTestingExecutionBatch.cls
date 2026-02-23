/**
* @description       : This class used to execute Test Cycle Results
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 06-10-2025
* @last modified by  : Adarsh Sharma
* @JIRA V2-7163 : Agentic Testing Framework
**/
public with sharing class AIAgenticTestingExecutionBatch implements Database.Batchable<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>, Database.Stateful, Database.AllowsCallouts {

    public List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> agenticFrameworkInputs;
    public Map<String, String> mapUserContextId;
    public Set<String> setProcessedExternalId;
    public Set<String> testCycleIds;
    
    public AIAgenticTestingExecutionBatch(List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> agenticFrameworkInputs, Set<String> testCycleIds){
        this.agenticFrameworkInputs = agenticFrameworkInputs;
        this.mapUserContextId = new Map<String, String>();
        this.testCycleIds = testCycleIds;
        this.setProcessedExternalId = new Set<String>();
    }
    
    public Iterable<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> start(Database.BatchableContext batchContext){
        return agenticFrameworkInputs;
    }
    
    public void execute(Database.BatchableContext batchContext, List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> records){
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = records.get(0);
        if(wrap.isAgent){
            wrap = executeAgentTestCycle(wrap);
        }else{
            wrap = executePromptTestCycle(wrap);
        }
        if(!setProcessedExternalId.contains(wrap.externalId)){
            createTestCycleResult(wrap);
            setProcessedExternalId.add(wrap.externalId);
        }
    }
    
    public void finish(Database.BatchableContext batchContext){
        if(testCycleIds.size()>0){
            database.executeBatch(new AIAgenticTestingVerificationPromptBatch(testCycleIds),1);
        }        
    }
    
    public AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper executeAgentTestCycle(AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap){
        AIAgenticWebService.RequestWrapper Reqwrap = new AIAgenticWebService.RequestWrapper();
        Reqwrap.recordId = wrap.externalId;
        Reqwrap.agentName = wrap.agentDeveloperName;
        Reqwrap.userMessage = wrap.input;
        if(mapUserContextId.containsKey(wrap.externalId)){
            Reqwrap.userContextId = mapUserContextId.get(wrap.externalId);
        } 
        system.debug('--Reqwrap--'+Reqwrap);
        Reqwrap.developerInstructions = (wrap.externalId!=null?'User is viewing ' + Id.valueOf(wrap.externalId).getSObjectType() + ' record:\n- ID:  ' + wrap.externalId + '\n' : '');
        // Set identification info from current user context
        Reqwrap.userIdentificationField = 'Id';
        Reqwrap.userIdentificationValue = UserInfo.getUserId();
        AIAgenticWebService.ResponseWrapper respWrap = AIAgenticUtility.invokeAgent(Reqwrap);
        
        if((!String.isBlank(respWrap.status) && respWrap.status.toLowerCase()=='success') 
           || (respWrap.statusCode != null && respWrap.statusCode==200)){
               system.debug('--respWrap--'+respWrap.userContextId);
               wrap.userContextId = respWrap.userContextId;
               system.debug('--userContextId--'+wrap.userContextId);
               if(!mapUserContextId.containsKey(wrap.externalId)){
                    mapUserContextId.put(wrap.externalId, wrap.userContextId);
               }
           }else{
               if(!String.isBlank(respWrap.status) || respWrap.statusCode != null){
                   wrap.message = respWrap.responseBody;
                   wrap.status = 'Errored';
               }
               if(!String.isBlank(respWrap.userContextId) && !mapUserContextId.containsKey(wrap.externalId)){
                   wrap.userContextId = respWrap.userContextId;
                   mapUserContextId.put(wrap.externalId, respWrap.userContextId);
               }
           }
        return wrap;
    }
    
    public AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper executePromptTestCycle(AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap){
        try{
            AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(wrap.promptId);
            AI_Response__c resp;
            if(aiPrompt.Include_Files__c == true && aiPrompt.AI_Model_File_Processing__r.Model__c == 'gpt-4.1'){
                resp = ChatGPTUtills.processResponsesFileRequest(aiPrompt.Id, wrap.input, '', new AI_Response__c());
            }else{
                resp = ChatGPTUtills.initiateGPT(wrap.input, aiPrompt.Id, '', null, false);
            }
            if(resp != null){
                 wrap.aISecurityAudit = resp.Id;
            }
        }catch(Exception ex){
            wrap.message = ex.getMessage();
            wrap.status = 'Errored';
        }
        return wrap;
    }
    
    public void createTestCycleResult(AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap){
        AI_Test_Cycle_Result__c cycleResult = new AI_Test_Cycle_Result__c();
        cycleResult.AI_Test_Cycle__c = wrap.testCycleId;
        cycleResult.External_Id__c = wrap.externalId;
        cycleResult.Input__c = JSON.serializePretty(wrap.inputData);
        cycleResult.Message__c = wrap.message;
        cycleResult.AI_Security_Audit__c = wrap.aISecurityAudit;
        if(!String.isBlank(wrap.userContextId)){
            for(AI_Response__c response : [SELECT Id FROM AI_Response__c WHERE Name=:wrap.userContextId LIMIT 1]){
                cycleResult.AI_Security_Audit__c = response.Id;
            }
        }
        FLSCheck.getInstance().insertDML(new List<AI_Test_Cycle_Result__c>{cycleResult});
        
    }
}