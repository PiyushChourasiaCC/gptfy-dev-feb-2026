/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 08-07-2023
* @last modified by  : Adarsh Sharma
**/
@isTest
public with sharing class AIPromptProcessingWebServiceTest {

    @testSetup
    public static void makeData(){
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
        prompt.Prompt_Request_Id__c = 'test';
        insert prompt;
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
    }
    
    @isTest
    public static void runRequestINCORRECTJSONTest(){
        RestRequest req = createRestRequest('/services/apexrest/v1/executePrompt/', 'POST', null);
        RestContext.request = req;
        RestContext.response= new RestResponse();
        
        Test.startTest();
        AIPromptProcessingWebService.ResponseWrapper response = AIPromptProcessingWebService.runRequest();
        System.Assert(response != null);
        Test.stopTest();
    }
    
    @isTest
    public static void runRequestPMTREQIDNOTFOUNDTest(){
        RestRequest req = createRestRequest('/services/apexrest/v1/executePrompt/', 'POST', '{"promptRequestId":"","recordId":"","customPromptCommand":""}');
        RestContext.request = req;
        RestContext.response= new RestResponse();
        
        Test.startTest();
        AIPromptProcessingWebService.ResponseWrapper response = AIPromptProcessingWebService.runRequest();
        System.Assert(response != null);
        Test.stopTest();
    }
    
    @isTest
    public static void runRequestRECIDNOTFOUNDTest(){
        AI_Prompt__c prompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c limit 1];
        RestRequest req = createRestRequest('/services/apexrest/v1/executePrompt/', 'POST', '{"promptRequestId":"'+prompt.Prompt_Request_Id__c+'","recordId":"","customPromptCommand":""}');
        RestContext.request = req;
        RestContext.response= new RestResponse();
        
        Test.startTest();
        AIPromptProcessingWebService.ResponseWrapper response = AIPromptProcessingWebService.runRequest();
        System.Assert(response != null);
        Test.stopTest();
    }
    
    @isTest
    public static void runRequestNOACTIVEPMTFOUNDTest(){
        AI_Prompt__c prompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c limit 1];
        RestRequest req = createRestRequest('/services/apexrest/v1/executePrompt/', 'POST', '{"promptRequestId":"'+prompt.Id+'","recordId":"test","customPromptCommand":""}');
        RestContext.request = req;
        RestContext.response= new RestResponse();
        
        Test.startTest();
        AIPromptProcessingWebService.ResponseWrapper response = AIPromptProcessingWebService.runRequest();
        System.Assert(response != null);
        Test.stopTest();
    }
    
    @isTest
    public static void runRequestINCORRECTRECIDTest(){
        AI_Prompt__c prompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c limit 1];
        RestRequest req = createRestRequest('/services/apexrest/v1/executePrompt/', 'POST', '{"promptRequestId":"'+prompt.Prompt_Request_Id__c+'","recordId":"test","customPromptCommand":""}');
        RestContext.request = req;
        RestContext.response= new RestResponse();
        
        Test.startTest();
        AIPromptProcessingWebService.ResponseWrapper response = AIPromptProcessingWebService.runRequest();
        System.Assert(response != null);
        Test.stopTest();
    }
    
     @isTest
    public static void runRequestTest(){
        AI_Prompt__c prompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c limit 1];
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c limit 1];
        RestRequest req = createRestRequest('/services/apexrest/v1/executePrompt/', 'POST', '{"promptRequestId":"'+prompt.Prompt_Request_Id__c+'","recordId":"'+sch.Id+'","customPromptCommand":""}');
        RestContext.request = req;
        RestContext.response= new RestResponse();
        
        Test.startTest();
        AIPromptProcessingWebService.ResponseWrapper response = AIPromptProcessingWebService.runRequest();
        System.Assert(response != null);
        Test.stopTest();
    }
    
    public static RestRequest createRestRequest(String requestURI, String httpMethod, String requestBody){
        RestRequest req = new RestRequest();
        req.requestURI = requestURI;
        req.httpMethod = httpMethod;
        if(String.isNotBlank(requestBody)){
            req.requestBody = Blob.valueOf(requestBody);
        }
        return req;
    }
    
}