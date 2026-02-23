/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 08-07-2023
* @last modified by  : Adarsh Sharma
**/
@isTest
public with sharing class AIPromptResponseProcessingInvokableTest {

    @testSetup
    public static void makeData(){
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
        prompt.Prompt_Request_Id__c = 'test';
        insert prompt;
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        AI_Scheduled_Run__c scheduledRun = TestUtility.getAIScheduledRun(sch.Id, true);
        AI_Response__c response = TestUtility.getAIResponse(scheduledRun.Id, promptScheduler.Id, null, true);
    }
    
    @isTest 
    public static void processRequestResponseIDNOTFOUNDTest(){
        List<AIPromptResponseProcessingInvokable.RequestWrapper> requests = new List<AIPromptResponseProcessingInvokable.RequestWrapper>();
        requests.add(new AIPromptResponseProcessingInvokable.RequestWrapper());
        Test.startTest();
        List<AIPromptResponseProcessingInvokable.ResponseWrapper> responses = AIPromptResponseProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    
    @isTest
    public static void processRequestNoDataToProcessTest(){
        AI_Response__c response = [SELECT Id FROM AI_Response__c limit 1];
        List<AIPromptResponseProcessingInvokable.RequestWrapper> requests = new List<AIPromptResponseProcessingInvokable.RequestWrapper>();
        AIPromptResponseProcessingInvokable.RequestWrapper wrapper = new AIPromptResponseProcessingInvokable.RequestWrapper();
        wrapper.responseId = response.Id;
        requests.add(wrapper);
        Test.startTest();
        List<AIPromptResponseProcessingInvokable.ResponseWrapper> responses = AIPromptResponseProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    
    @isTest
    public static void processRequestMalformedJSONTest(){
        AI_Response__c response = [SELECT Id, AI_Processed_Data_PII_Added__c FROM AI_Response__c limit 1];
        response.AI_Processed_Data_PII_Added__c = 'test';
        update response;
        List<AIPromptResponseProcessingInvokable.RequestWrapper> requests = new List<AIPromptResponseProcessingInvokable.RequestWrapper>();
        AIPromptResponseProcessingInvokable.RequestWrapper wrapper = new AIPromptResponseProcessingInvokable.RequestWrapper();
        wrapper.responseId = response.Id;
        requests.add(wrapper);
        Test.startTest();
        List<AIPromptResponseProcessingInvokable.ResponseWrapper> responses = AIPromptResponseProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    
    @isTest
    public static void processRequestTest(){
        AI_Response__c response = [SELECT Id, AI_Processed_Data_PII_Added__c FROM AI_Response__c limit 1];
        response.AI_Processed_Data_PII_Added__c = '{}';
        update response;
        List<AIPromptResponseProcessingInvokable.RequestWrapper> requests = new List<AIPromptResponseProcessingInvokable.RequestWrapper>();
        AIPromptResponseProcessingInvokable.RequestWrapper wrapper = new AIPromptResponseProcessingInvokable.RequestWrapper();
        wrapper.responseId = response.Id;
        wrapper.key = 'test1';
        requests.add(wrapper);
        Test.startTest();
        List<AIPromptResponseProcessingInvokable.ResponseWrapper> responses = AIPromptResponseProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    
}