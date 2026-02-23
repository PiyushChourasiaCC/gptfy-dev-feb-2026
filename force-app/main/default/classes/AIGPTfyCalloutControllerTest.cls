/**
 * @description Test class for AIGPTfyCalloutController
 * @author Plumcloud Labs
 */
@isTest
private class AIGPTfyCalloutControllerTest {
    
    /**
     * Mock class for successful API response
     */
    private class MockCalloutSuccess implements HttpCalloutMock {
        private String responseBody;
        
        public MockCalloutSuccess(String body) {
            this.responseBody = body;
        }
        
        public MockCalloutSuccess() {
            this.responseBody = '{"id": "chatcmpl-123", "choices": [{"message": {"content": "Test response"}}]}';
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody(responseBody);
            return resp;
        }
    }
    
    /**
     * Mock class for error response
     */
    private class MockCalloutError implements HttpCalloutMock {
        private Integer statusCode;
        private String errorBody;
        
        public MockCalloutError(Integer code, String body) {
            this.statusCode = code;
            this.errorBody = body;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(statusCode);
            resp.setStatus('Error');
            resp.setBody(errorBody);
            return resp;
        }
    }
    
    /**
     * Mock class for analyze result with headers
     */
    private class MockAnalyzeResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            if (req.getEndpoint().contains('AnalyzeDocument')) {
                resp.setBody('{"headers": [{"key": "Operation-Location", "value": ["https://test.com/analyzeResults/abc123"]}]}');
            } else if (req.getEndpoint().contains('GetAnalysisResults')) {
                resp.setBody('{"Result": "Analyzed data content"}');
            } else {
                resp.setBody('{"data": "Success"}');
            }
            return resp;
        }
    }
    
    /**
     * Mock class for file processing with Operation-Location header
     */
    private class MockFileProcessingResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setHeader('Operation-Location', 'https://test.com/analyzeResults/xyz789');
            resp.setBody('{"status": "running"}');
            return resp;
        }
    }

    @testSetup
    static void makeData() {
        Account testAccount = TestUtility.getAccount(true);
        
        // Create GPTfy connection - using TestUtility pattern
        AI_Connection__c gptfyConn = TestUtility.getConnection('GPTfy', false);
        gptfyConn.EndPoint_URL__c = '/v1/chat/completions';
        gptfyConn.Model__c = 'gpt-4';
        gptfyConn.Top_P__c = 0.9;
        insert gptfyConn;
        
        // Create second GPTfy connection for Davinci model tests
        AI_Connection__c davinciConn = TestUtility.getConnection('GPTfy', false);
        davinciConn.Name = 'Davinci Connection';
        davinciConn.EndPoint_URL__c = '/v1/completions';
        davinciConn.Model__c = AIConstants.DAVINCI_MODEL;
        insert davinciConn;
        
        // Create responses endpoint connection
        AI_Connection__c responsesConn = TestUtility.getConnection('GPTfy', false);
        responsesConn.Name = 'Responses Connection';
        responsesConn.EndPoint_URL__c = '/v1/responses';
        responsesConn.Model__c = 'gpt-4';
        insert responsesConn;
        
        // Create Text Bison model connection
        AI_Connection__c textBisonConn = TestUtility.getConnection('GPTfy', false);
        textBisonConn.Name = 'Text Bison Connection';
        textBisonConn.Model__c = AIConstants.TEXT_BISON_001_MODEL;
        insert textBisonConn;
        
        // Create AWS Bedrock model connection
        AI_Connection__c bedrockConn = TestUtility.getConnection('GPTfy', false);
        bedrockConn.Name = 'Bedrock Connection';
        bedrockConn.Model__c = AIConstants.AWS_BEDROCK_MODEL;
        insert bedrockConn;
        
        // Create X Large model connection (Cohere) - use GPTfy as AI_Technology
        AI_Connection__c xlargeConn = TestUtility.getConnection('GPTfy', false);
        xlargeConn.Name = 'XLarge Connection';
        xlargeConn.Model__c = AIConstants.X_LARGE_MODEL;
        insert xlargeConn;
        
        // Create GCP Chat Bison model connection - use GPTfy as AI_Technology
        AI_Connection__c chatBisonConn = TestUtility.getConnection('GPTfy', false);
        chatBisonConn.Name = 'Chat Bison Connection';
        chatBisonConn.Model__c = AIConstants.GCP_CHAT_BISON_MODEL;
        insert chatBisonConn;
        
        // Create GCP Dialogflow model connection - use GPTfy as AI_Technology
        AI_Connection__c dialogflowConn = TestUtility.getConnection('GPTfy', false);
        dialogflowConn.Name = 'Dialogflow Connection';
        dialogflowConn.Model__c = AIConstants.GCP_DIALOGFLOW_MODEL;
        insert dialogflowConn;
        
        // Create Azure RAG model connection - use GPTfy as AI_Technology
        AI_Connection__c azureRagConn = TestUtility.getConnection('GPTfy', false);
        azureRagConn.Name = 'Azure RAG Connection';
        azureRagConn.Model__c = AIConstants.AZURE_RAG_GPT_35_TURBO_MODEL;
        azureRagConn.Additional_Parameters__c = '{"endpoint": "https://test.com", "key": "testkey", "indexName": "testindex"}';
        insert azureRagConn;
        
        // Create Llama model connection - use GPTfy as AI_Technology
        AI_Connection__c llamaConn = TestUtility.getConnection('GPTfy', false);
        llamaConn.Name = 'Llama Connection';
        llamaConn.Model__c = 'llama-3';
        insert llamaConn;
        
        // Create AWS Bedrock with retrieveAndGenerate endpoint - use GPTfy as AI_Technology
        AI_Connection__c bedrockRagConn = TestUtility.getConnection('GPTfy', false);
        bedrockRagConn.Name = 'Bedrock RAG Connection';
        bedrockRagConn.Model__c = AIConstants.AWS_BEDROCK_MODEL;
        bedrockRagConn.EndPoint_URL__c = '/retrieveAndGenerate';
        bedrockRagConn.Additional_Parameters__c = '{"knowledgeBaseId": "kb123", "modelArn": "arn:aws:bedrock:model"}';
        insert bedrockRagConn;
        
        // Create GPT-5 chat completions connection - use GPTfy as AI_Technology
        AI_Connection__c gpt5ChatConn = TestUtility.getConnection('GPTfy', false);
        gpt5ChatConn.Name = 'GPT5 Chat Connection';
        gpt5ChatConn.Model__c = 'gpt-5';
        gpt5ChatConn.EndPoint_URL__c = '/chat/completions';
        gpt5ChatConn.Additional_Parameters__c = '{"gpt-5": true, "reasoning": "medium", "verbosity": "high"}';
        insert gpt5ChatConn;
        
        // Create GPT-5 responses connection - use GPTfy as AI_Technology
        AI_Connection__c gpt5RespConn = TestUtility.getConnection('GPTfy', false);
        gpt5RespConn.Name = 'GPT5 Responses Connection';
        gpt5RespConn.Model__c = 'gpt-5';
        gpt5RespConn.EndPoint_URL__c = '/v1/responses';
        gpt5RespConn.Additional_Parameters__c = '{"gpt-5": true, "reasoning": "high", "verbosity": "medium"}';
        insert gpt5RespConn;
        
        // Create AI Prompt with GPTfy connection
        AI_Prompt__c gptfyPrompt = new AI_Prompt__c(
            Name = 'GPTfy Test Prompt',
            AI_Connection__c = gptfyConn.Id,
            Max_Output_Tokens__c = 4000,
            Temperature__c = 0.5,
            Top_P__c = 0.8,
            Status__c = 'Active',
            Object__c = 'Account'
        );
        insert gptfyPrompt;
        
        // Create ContentVersion for file processing tests
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.pdf',
            VersionData = Blob.valueOf('Test file content')
        );
        insert cv;
    }
    
    private static AI_Connection__c getConnection(String name) {
        return [SELECT Id, Name, Named_Credential__c, AI_Technology__c, EndPoint_URL__c, 
                       Max_Tokens__c, Temperature__c, Top_P__c, Model__c, Version__c,
                       Max_Total_Tokens__c, Processing_Class__c, Connector_Class__c,
                       Additional_Parameters__c
                FROM AI_Connection__c WHERE Name = :name LIMIT 1];
    }
    
    private static AI_Prompt__c getPrompt(String name) {
        return [SELECT Id, Name, AI_Connection__c, AI_Connection__r.Name, AI_Connection__r.Named_Credential__c,
                       AI_Connection__r.AI_Technology__c, AI_Connection__r.EndPoint_URL__c,
                       AI_Connection__r.Max_Tokens__c, AI_Connection__r.Temperature__c,
                       AI_Connection__r.Top_P__c, AI_Connection__r.Model__c, AI_Connection__r.Version__c,
                       AI_Connection__r.Max_Total_Tokens__c, AI_Connection__r.Processing_Class__c,
                       AI_Connection__r.Connector_Class__c, AI_Connection__r.Additional_Parameters__c,
                       Max_Output_Tokens__c, Temperature__c, Top_P__c, Status__c
                FROM AI_Prompt__c WHERE Name = :name LIMIT 1];
    }
    
    @isTest
    static void testProcessRequestSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Prompt__c prompt = getPrompt('GPTfy Test Prompt');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.processRequest('Test command', 'Test body', prompt);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testProcessRequestWithError() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError(500, ''));
        
        AI_Prompt__c prompt = getPrompt('GPTfy Test Prompt');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.processRequest('Test command', 'Test body', prompt);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testValidateRequestSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('GPTfy');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.validateRequest('Test command', 'Test body', conn);
        Test.stopTest();
        
        System.assertEquals(null, result, 'Result should be null for successful validation');
    }
    
    @isTest
    static void testValidateRequestWithErrorMessage() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError(400, '{"message": "Invalid request"}'));
        
        AI_Connection__c conn = getConnection('GPTfy');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.validateRequest('Test command', 'Test body', conn);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should contain error message');
    }
    
    @isTest
    static void testValidateRequestWithNestedError() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError(400, '{"error": {"message": "API Error"}}'));
        
        AI_Connection__c conn = getConnection('GPTfy');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.validateRequest('Test command', 'Test body', conn);
        Test.stopTest();
        
        System.assertEquals('API Error', result, 'Result should contain nested error message');
    }
    
    @isTest
    static void testDoCalloutWithGPTfy() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('GPTfy');
        AI_Prompt__c prompt = getPrompt('GPTfy Test Prompt');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.doCallout('Test command', 'Test body', conn, prompt, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testProcessGptfyRequestWithDavinci() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Davinci Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.processGptfyRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testProcessGptfyRequestWithTextBison() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Text Bison Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.processGptfyRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testProcessGptfyRequestWithBedrock() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Bedrock Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.processGptfyRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithDavinci() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Davinci Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithXLarge() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('XLarge Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithChatBison() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Chat Bison Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithDialogflow() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Dialogflow Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithBedrock() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Bedrock Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithBedrockRAG() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Bedrock RAG Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithLlama() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Llama Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithAzureRAG() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Azure RAG Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithGPT5Chat() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('GPT5 Chat Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithGPT5Responses() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('GPT5 Responses Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testSubmitGPTRequestWithResponses() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Responses Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testProcessGptfyRequestWithGPT5Chat() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('GPT5 Chat Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.processGptfyRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testProcessGptfyRequestWithGPT5Responses() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('GPT5 Responses Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.processGptfyRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetGPTfyEncryptedToken() {
        Test.startTest();
        String token = AIGPTfyCalloutController.getGPTfyEncryptedToken();
        Test.stopTest();
        
        System.assertNotEquals(null, token, 'Token should not be null');
        System.assert(token.length() > 0, 'Token should not be empty');
    }
    
    @isTest
    static void testGetGPTfyAnalyzeResult() {
        Test.setMock(HttpCalloutMock.class, new MockAnalyzeResponse());
        
        Map<String, String> mapOfEndpointUrls = new Map<String, String>();
        mapOfEndpointUrls.put('cdId', 'abc123');
        
        Test.startTest();
        Map<String, String> result = AIGPTfyCalloutController.getGPTfyAnalyzeResult(mapOfEndpointUrls);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testGetAnalyzeResult() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess('{"data": "Analyzed content"}'));
        
        AI_Connection__c conn = getConnection('GPTfy');
        Map<String, String> mapOfEndpointUrls = new Map<String, String>();
        mapOfEndpointUrls.put('cdId', 'https://test.com/analyzeResults/abc123');
        
        Test.startTest();
        Map<String, String> result = AIGPTfyCalloutController.getAnalyzeResult(conn, mapOfEndpointUrls);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('{"data": "Analyzed content"}', result.get('cdId'), 'Result should contain analyzed content');
    }
    
    @isTest
    static void testProcessGPTfyFileRequest() {
        Test.setMock(HttpCalloutMock.class, new MockAnalyzeResponse());
        
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
        List<String> cdIds = new List<String>{cv.ContentDocumentId};
        
        Test.startTest();
        Map<String, String> result = AIGPTfyCalloutController.processGPTfyFileRequest(cdIds);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testProcessFileRequest() {
        Test.setMock(HttpCalloutMock.class, new MockFileProcessingResponse());
        
        AI_Connection__c conn = getConnection('GPTfy');
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
        List<String> cdIds = new List<String>{cv.ContentDocumentId};
        
        Test.startTest();
        Map<String, String> result = AIGPTfyCalloutController.processFileRequest(conn, cdIds);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testValidateVoiceRequest() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('GPTfy');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.validateVoiceRequest(conn);
        Test.stopTest();
        
        System.assertEquals(null, result, 'Result should be null for successful validation');
    }
    
    @isTest
    static void testValidateVoiceRequestWithError() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError(400, '{"error": "Invalid request"}'));
        
        AI_Connection__c conn = getConnection('GPTfy');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.validateVoiceRequest(conn);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should contain error');
    }
    
    @isTest
    static void testGetVoiceRequestBody() {
        Test.startTest();
        String body = AIGPTfyCalloutController.getVoiceRequestBody('gpt-4');
        Test.stopTest();
        
        System.assertNotEquals(null, body, 'Body should not be null');
        System.assert(body.contains('gpt-4'), 'Body should contain model name');
    }
    
    @isTest
    static void testProcessRequestWithMaxTokenExceeded() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        // Create connection with low max total tokens
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        conn.Name = 'Low Token Connection';
        conn.Max_Tokens__c = 100;
        conn.Max_Total_Tokens__c = 10;
        conn.Model__c = 'gpt-4';
        insert conn;
        
        AI_Prompt__c prompt = new AI_Prompt__c(
            Name = 'Low Token Prompt',
            AI_Connection__c = conn.Id,
            Status__c = 'Active',
            Object__c = 'Account'
        );
        insert prompt;
        
        // Re-query to get relationship fields
        prompt = [SELECT Id, Name, AI_Connection__c, AI_Connection__r.Name, AI_Connection__r.Named_Credential__c,
                         AI_Connection__r.AI_Technology__c, AI_Connection__r.EndPoint_URL__c,
                         AI_Connection__r.Max_Tokens__c, AI_Connection__r.Temperature__c,
                         AI_Connection__r.Top_P__c, AI_Connection__r.Model__c, AI_Connection__r.Version__c,
                         AI_Connection__r.Max_Total_Tokens__c, AI_Connection__r.Processing_Class__c,
                         AI_Connection__r.Connector_Class__c, AI_Connection__r.Additional_Parameters__c,
                         Max_Output_Tokens__c, Temperature__c, Top_P__c, Status__c
                  FROM AI_Prompt__c WHERE Id = :prompt.Id];
        
        // Create a very long message to exceed token limit
        String longMessage = 'This is a very long message that should exceed the max total tokens limit. ';
        for (Integer i = 0; i < 100; i++) {
            longMessage += 'Additional text to make message longer. ';
        }
        
        Test.startTest();
        String result = AIGPTfyCalloutController.processRequest('Command', longMessage, prompt);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('error'), 'Result should contain error');
    }
    
    @isTest
    static void testProcessGptfyRequestWithResponsesEndpoint() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('Responses Connection');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.processGptfyRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testValidateRequestWithStatusOnly() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError(401, ''));
        
        AI_Connection__c conn = getConnection('GPTfy');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.validateRequest('Test command', 'Test body', conn);
        Test.stopTest();
        
        System.assertEquals('Error', result, 'Result should be status text');
    }
    
    @isTest
    static void testSubmitGPTRequestDefault() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Connection__c conn = getConnection('GPTfy');
        
        Test.startTest();
        HttpResponse response = AIGPTfyCalloutController.submitGPTRequest('Test command', 'Test body', conn, 2000, 0.7, 0.9);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testValidateRequestWithRawBody() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError(400, 'Raw error message'));
        
        AI_Connection__c conn = getConnection('GPTfy');
        
        Test.startTest();
        String result = AIGPTfyCalloutController.validateRequest('Test command', 'Test body', conn);
        Test.stopTest();
        
        System.assertEquals('Raw error message', result, 'Result should be raw body');
    }
}