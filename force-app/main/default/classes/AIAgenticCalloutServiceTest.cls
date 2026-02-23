@isTest
private class AIAgenticCalloutServiceTest {

    // Utility: builds a dummy config wrapper with full model details
    private static AIAgenticWebService.RequestWrapper buildRequest(String model, String namedCred, Boolean includeFunctions) {
        return buildRequest(model, namedCred, includeFunctions, null, null, null, null);
    }
    
    // Utility: builds a request with additional model parameters
    private static AIAgenticWebService.RequestWrapper buildRequest(
        String model, 
        String namedCred, 
        Boolean includeFunctions,
        Decimal maxTokens,
        Decimal temperature,
        Decimal topP,
        String additionalParams
    ) {
        // Create test AI Connection record with all parameters
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection ' + model,
            Model__c = model,
            Named_Credential__c = namedCred != null ? namedCred : 'Test_Credential',
            Type__c = 'Agentic',
            Max_Tokens__c = maxTokens,
            Temperature__c = temperature,
            Top_P__c = topP,
            Additional_Parameters__c = additionalParams
        );
        insert aiConnection;
        
        // Query to get all fields
        aiConnection = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, 
                               Max_Tokens__c, Temperature__c, Top_P__c, Additional_Parameters__c 
                        FROM AI_Connection__c WHERE Id = :aiConnection.Id];
        
        AI_Agent__c cfg = new AI_Agent__c(
            Name = 'My Test Config ' + model,
            AI_Model__c = aiConnection.Id,
            System_Prompt__c = 'You are a helpful assistant'
        );
        insert cfg;
        
        // Query to get relationship fields
        cfg = [SELECT Id, Name, AI_Model__c, System_Prompt__c,
                      AI_Model__r.Model__c, AI_Model__r.Named_Credential__c,
                      AI_Model__r.Max_Tokens__c, AI_Model__r.Temperature__c,
                      AI_Model__r.Top_P__c, AI_Model__r.Additional_Parameters__c
               FROM AI_Agent__c WHERE Id = :cfg.Id];

        AIAgenticWebService.RequestWrapper req = new AIAgenticWebService.RequestWrapper();
        req.config = cfg;
        req.conversation = new List<Object>{ 'Hello world' };
        req.previousResponseId = 'prev123';
        if(includeFunctions){
            req.promptFunctions = new List<Object>{ 'tool1' };
        }
        return req;
    }

    // ------------------------------------------------------------------------
    // Success Mock (200 / 201)
    // ------------------------------------------------------------------------
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String respBody = '{"id":"resp_68aede0881d08196b159131b1d7dcd3006a396067c4451c6","output":[{"id":"msg_68aede09276c8196b509f117634b6b4706a396067c4451c6","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"It appears that you haven\'t uploaded any files yet. Please upload the files you would like me to review, and I will list all the questions from them for you!"}],"role":"assistant"}],"usage":{"input_tokens":19,"input_tokens_details":{"cached_tokens":0},"output_tokens":34,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":53}}';
            res.setBody(respBody);
            return res;
        }
    }

    // Error Mock
    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Something broke');
            return res;
        }
    }

    // ------------------------------------------------------------------------
    // fetchQualifiedPrompt tests
    // ------------------------------------------------------------------------

    @isTest static void testFetchQualifiedPromptSuccessWithFunctions() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', true);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.isNotNull(resp.responseBody, 'Response body should not be null');
        Assert.isTrue(String.isNotBlank(resp.responseBody), 'Response body should contain AI reply text');
    }
    
    @isTest static void testFetchQualifiedPromptSuccessWithoutFunctions() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', false);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.isNotNull(resp.responseBody, 'Response body should not be null');
    }
    
    @isTest static void testFetchQualifiedPromptWithMaxTokens() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', false, 4000, null, null, null);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.isNotNull(resp.responseBody, 'Response body should not be null');
    }
    
    @isTest static void testFetchQualifiedPromptWithTemperatureAndTopP() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', false, 4000, 0.7, 0.9, null);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.isNotNull(resp.responseBody, 'Response body should not be null');
    }
    
    @isTest static void testFetchQualifiedPromptWithGPT5Model() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-5');
        String additionalParams = '{"reasoning": "high", "verbosity": "medium"}';
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-5', 'Test_NC', false, 4000, null, null, additionalParams);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.isNotNull(resp.responseBody, 'Response body should not be null');
    }
    
    @isTest static void testFetchQualifiedPromptWithGPT5NoAdditionalParams() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-5');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-5', 'Test_NC', false, 4000, null, null, null);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.isNotNull(resp.responseBody, 'Response body should not be null');
    }
    
    @isTest static void testFetchQualifiedPromptWithGPT5PartialParams() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-5.1');
        // Only reasoning, no verbosity
        String additionalParams = '{"reasoning": "medium"}';
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-5.1', 'Test_NC', true, 4000, null, null, additionalParams);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.isNotNull(resp.responseBody, 'Response body should not be null');
    }
    
    @isTest static void testFetchQualifiedPromptWithGPT6Model() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-6');
        String additionalParams = '{"verbosity": "high"}';
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-6', 'Test_NC', false, null, null, null, additionalParams);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.isNotNull(resp.responseBody, 'Response body should not be null');
    }

    @isTest static void testFetchQualifiedPromptErrorResponse() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', false);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(req);
        Test.stopTest();

        Assert.areEqual('Something broke', resp.message, 'Should hold error message from body');
    }

    @isTest static void testFetchQualifiedPromptExceptionHandling() {
        // Forcing null config to trigger exception
        AIAgenticWebService.RequestWrapper badReq = new AIAgenticWebService.RequestWrapper();
        badReq.config = null;
        Test.startTest();
        AIAgenticWebService.ResponseWrapper resp = AIAgenticCalloutService.fetchQualifiedPrompt(badReq);
        Test.stopTest();

        Assert.isNotNull(resp.message, 'Exception message should be populated');
    }

    // ------------------------------------------------------------------------
    // getAssistantReply tests
    // ------------------------------------------------------------------------

    @isTest static void testGetAssistantReplySuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', false);

        Test.startTest();
        Map<String,String> result = AIAgenticCalloutService.getAssistantReply(req, new List<Object>{'Hi'});
        Test.stopTest();

        Assert.isTrue(result.containsKey('response'), 'Should contain response key');
        Assert.isTrue(result.containsKey('threadId'), 'Should contain threadId key');
        Assert.isTrue(String.isNotBlank(result.get('threadId')), 'ThreadId should match mock id');
    }
    
    @isTest static void testGetAssistantReplyWithMaxTokens() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', false, 4000, null, null, null);

        Test.startTest();
        Map<String,String> result = AIAgenticCalloutService.getAssistantReply(req, new List<Object>{'Hi'});
        Test.stopTest();

        Assert.isTrue(result.containsKey('response'), 'Should contain response key');
    }
    
    @isTest static void testGetAssistantReplyWithTemperatureAndTopP() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', false, null, 0.7, 0.9, null);

        Test.startTest();
        Map<String,String> result = AIAgenticCalloutService.getAssistantReply(req, new List<Object>{'Hi'});
        Test.stopTest();

        Assert.isTrue(result.containsKey('response'), 'Should contain response key');
    }
    
    @isTest static void testGetAssistantReplyWithGPT5Model() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-5');
        String additionalParams = '{"reasoning": "high", "verbosity": "medium"}';
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-5', 'Test_NC', false, 4000, null, null, additionalParams);

        Test.startTest();
        Map<String,String> result = AIAgenticCalloutService.getAssistantReply(req, new List<Object>{'Hi'});
        Test.stopTest();

        Assert.isTrue(result.containsKey('response'), 'Should contain response key');
    }
    
    @isTest static void testGetAssistantReplyWithGPT5NoAdditionalParams() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-5');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-5', 'Test_NC', false, null, null, null, null);

        Test.startTest();
        Map<String,String> result = AIAgenticCalloutService.getAssistantReply(req, new List<Object>{'Hi'});
        Test.stopTest();

        Assert.isTrue(result.containsKey('response'), 'Should contain response key');
    }
    
    @isTest static void testGetAssistantReplyWithGPT5PartialParams() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-5.1');
        // Only verbosity, no reasoning
        String additionalParams = '{"verbosity": "low"}';
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-5.1', 'Test_NC', false, null, null, null, additionalParams);

        Test.startTest();
        Map<String,String> result = AIAgenticCalloutService.getAssistantReply(req, new List<Object>{'Hi'});
        Test.stopTest();

        Assert.isTrue(result.containsKey('response'), 'Should contain response key');
    }

    @isTest static void testGetAssistantReplyFailure() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        AIConstants.RESPONSES_API_MODEL.add('gpt-4.1');
        AIAgenticWebService.RequestWrapper req = buildRequest('gpt-4.1', 'Test_NC', false);

        Test.startTest();
        Map<String,String> result = AIAgenticCalloutService.getAssistantReply(req, new List<Object>{'Hi'});
        Test.stopTest();

        Assert.isTrue(result.containsKey('error'), 'Should contain error key when callout fails');
    }

    // ------------------------------------------------------------------------
    // responseGenerator direct test
    // ------------------------------------------------------------------------

    @isTest static void testResponseGenerator() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Test_NC/v1/test');
        String body = '{"test":"data"}';

        Test.startTest();
        HttpResponse res = AIAgenticCalloutService.responseGenerator(req, body);
        Test.stopTest();

        Assert.areEqual(200, res.getStatusCode(), 'Response should be mocked 200');
        Assert.isTrue(String.isNotBlank(res.getBody()), 'Response should contain thread id');
    }
}