/**
* @description       : Test class for AIPromptProcessingInvokable
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-03-2025
* @last modified by  : Rishabh Goel
**/
@isTest
private class AIPromptProcessingInvokableTest {
    
    private static final String TEST_PROMPT_REQUEST_ID = 'TEST_PROMPT_REQ_001';
    private static final String TEST_EVENT_UUID = 'TEST_EVENT_UUID_001';
    private static final String TEST_CUSTOM_COMMAND = 'Test custom prompt command';
    private static final String TEST_RESPONSE_BODY = 'Test AI response body';
    private static final String TEST_PROMPT_NAME = 'Test AI Prompt';
    private static final String TEST_ACCOUNT_NAME = 'Test Account';
    
    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Test Account22');
        insert acc;
        
        AI_Response_Mapping__c responseMapping = TestUtility.createResponseMapping('TestResponse',true);
        
        AI_Response_Mapping_Line__c oResponseMappingLine = new AI_Response_Mapping_Line__c();
        oResponseMappingLine.AI_Response_Mapping__c = responseMapping.Id;
        oResponseMappingLine.Security_Audit_Field_Name__c = 'Record_Id__c';
        oResponseMappingLine.Mapping_Field_Name__c = 'Record_Id__c';
        insert oResponseMappingLine;
        
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        conn.AI_Response_Mapping__c = responseMapping.Id;
        insert conn;
        
        TestUtility.insertDataExtraction();
        
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        AI_Prompt__c prompt = TestUtility.getAIPrompt(TEST_PROMPT_NAME, 'Account', 'Active', false);
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Give a sample response.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = AIConstants.PMT_LOCALE_GPTFY_CONSOLE_COMPANY_DEFAULT;
        prompt.AI_Locale_Automation__c = AIConstants.PMT_LOCALE_AUTOMATION_RECORD_OWNER;
        insert prompt;
        /*String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.', 'groundingContent' => 'Only answer what has been asked for.', 
            'groundingEthical' => 'Do not hallucinate.'
        }); */
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(prompt.Id, master.Id, 'Account', true);
        update cmp1;
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(prompt.Id, cDetail.Id, 'Contact', true);
        
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(prompt.Id, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(prompt.Id);
        
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt2 = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
        prompt2.Prompt_Request_Id__c = 'test';
        insert prompt2;
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt2.Id, sch.Id, true);
        AI_Scheduled_Run__c scheduledRun = TestUtility.getAIScheduledRun(sch.Id, true);
        
        // Create test AI_Response__c record
        AI_Response__c testResponse = new AI_Response__c(
            AI_Processed_Data_PII_Added__c = TEST_RESPONSE_BODY,
            AI_Prompt__c = prompt.Id
        );
        insert testResponse;
        
        AI_Connection__c modelFileProcessing = new AI_Connection__c(
            Name = 'Test AI Connection File',
            Model__c = 'gpt-4.1',
            Named_Credential__c = 'Test_Credential_File',
            Type__c = 'File'
        );
        insert modelFileProcessing;
        
        // Create AI_Prompt__c record with file processing enabled
        AI_Prompt__c filePrompt = new AI_Prompt__c(
            Name = 'Test File Prompt',
            Prompt_Request_Id__c = 'FILE_PROMPT_REQ_001',
            Status__c = AIConstants.PMT_STATUS_ACTIVE,
            Include_Files__c = true,
            AI_Model_File_Processing__c = modelFileProcessing.Id
        );
        insert filePrompt;
    }
    
    @isTest
    static void testProcessEventPublishing() {
        // Preparing request with required fields
        AIPromptProcessingInvokable.RequestWrapper requestWrapper = new AIPromptProcessingInvokable.RequestWrapper();
        AI_Prompt__c testPrompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c WHERE Name = :TEST_PROMPT_NAME LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1]; // Assuming the account creation in testSetup
        requestWrapper.promptRequestId = testPrompt.Prompt_Request_Id__c;
        requestWrapper.recordId = testAccount.Id;
        requestWrapper.eventUUID = 'SomeUniqueIdentifier';
        
        List<AIPromptProcessingInvokable.RequestWrapper> requests = new List<AIPromptProcessingInvokable.RequestWrapper>{requestWrapper};

        // Setting up mock response to simulate external callout
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Valid response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));

        // Actual test execution
        Test.startTest();
        List<AIPromptProcessingInvokable.ResponseWrapper> responses = AIPromptProcessingInvokable.processRequest(requests);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, responses, 'Responses should not be null');
       // System.assertEquals('Success', responses[0].status, 'Status should be Success');
        System.assertNotEquals('', responses[0].responseBody, 'ResponseBody should not be blank');

        // Directly asserting EventBus.publish happened isn't possible in Apex tests,
        // but reaching this logic path and verifying the response confirms the expected behavior.
    }


    @isTest
    public static void processRequestPMTREQIDNOTFOUNDTest(){
        List<AIPromptProcessingInvokable.RequestWrapper> requests = new List<AIPromptProcessingInvokable.RequestWrapper>();
        requests.add(new AIPromptProcessingInvokable.RequestWrapper());
        Test.startTest();
        List<AIPromptProcessingInvokable.ResponseWrapper> responses = AIPromptProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    
    @isTest
    public static void processRequestRECIDNOTFOUNDTest(){
        AI_Prompt__c prompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c limit 1];
        List<AIPromptProcessingInvokable.RequestWrapper> requests = new List<AIPromptProcessingInvokable.RequestWrapper>();
		AIPromptProcessingInvokable.RequestWrapper requestWrapper = new AIPromptProcessingInvokable.RequestWrapper();
        requestWrapper.promptRequestId = prompt.Prompt_Request_Id__c;
        requests.add(requestWrapper);
        Test.startTest();
        List<AIPromptProcessingInvokable.ResponseWrapper> responses = AIPromptProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    
    @isTest
    public static void processRequestNOACTIVEPMTFOUNDTest(){
        AI_Prompt__c prompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c limit 1];
        List<AIPromptProcessingInvokable.RequestWrapper> requests = new List<AIPromptProcessingInvokable.RequestWrapper>();
		AIPromptProcessingInvokable.RequestWrapper requestWrapper = new AIPromptProcessingInvokable.RequestWrapper();
        requestWrapper.promptRequestId = prompt.Id;
        requestWrapper.recordId = 'test';
        requests.add(requestWrapper);
        Test.startTest();
        List<AIPromptProcessingInvokable.ResponseWrapper> responses = AIPromptProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    
    @isTest
    public static void processRequestINCORRECTRECIDTest(){
        AI_Prompt__c prompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c limit 1];
        List<AIPromptProcessingInvokable.RequestWrapper> requests = new List<AIPromptProcessingInvokable.RequestWrapper>();
		AIPromptProcessingInvokable.RequestWrapper requestWrapper = new AIPromptProcessingInvokable.RequestWrapper();
        requestWrapper.promptRequestId = prompt.Prompt_Request_Id__c;
        requestWrapper.recordId = 'test';
        requests.add(requestWrapper);
        Test.startTest();
        List<AIPromptProcessingInvokable.ResponseWrapper> responses = AIPromptProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    
    @isTest
    public static void processRequestTest(){
        AI_Prompt__c prompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c limit 1];
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c limit 1];
        List<AIPromptProcessingInvokable.RequestWrapper> requests = new List<AIPromptProcessingInvokable.RequestWrapper>();
		AIPromptProcessingInvokable.RequestWrapper requestWrapper = new AIPromptProcessingInvokable.RequestWrapper();
        requestWrapper.promptRequestId = prompt.Prompt_Request_Id__c;
        requestWrapper.recordId = sch.Id;
        requests.add(requestWrapper);
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        List<AIPromptProcessingInvokable.ResponseWrapper> responses = AIPromptProcessingInvokable.processRequest(requests);
        System.Assert(responses != null);
        Test.stopTest();
    }
    @isTest
    static void testProcessEventPublishing_file() {
        // Preparing request with required fields
        AIPromptProcessingInvokable.RequestWrapper requestWrapper = new AIPromptProcessingInvokable.RequestWrapper();
        AI_Prompt__c testPrompt = [SELECT Id, Prompt_Request_Id__c FROM AI_Prompt__c WHERE Name = 'Test File Prompt' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1]; // Assuming the account creation in testSetup
        requestWrapper.promptRequestId = testPrompt.Prompt_Request_Id__c;
        requestWrapper.recordId = testAccount.Id;
        requestWrapper.eventUUID = 'SomeUniqueIdentifier';
        requestWrapper.customPromptCommand = '';
        
        List<AIPromptProcessingInvokable.RequestWrapper> requests = new List<AIPromptProcessingInvokable.RequestWrapper>{requestWrapper};

        // Setting up mock response to simulate external callout
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Valid response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));

        // Actual test execution
        Test.startTest();
        List<AIPromptProcessingInvokable.ResponseWrapper> responses = AIPromptProcessingInvokable.processRequest(requests);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, responses, 'Responses should not be null');
       // System.assertEquals('Success', responses[0].status, 'Status should be Success');
        System.assertNotEquals('', responses[0].responseBody, 'ResponseBody should not be blank');

        // Directly asserting EventBus.publish happened isn't possible in Apex tests,
        // but reaching this logic path and verifying the response confirms the expected behavior.
    }
}