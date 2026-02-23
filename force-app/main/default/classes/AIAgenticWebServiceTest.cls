@isTest
private class AIAgenticWebServiceTest {

    // Utility method for building RestContext
    private static void setRestContext(String method, String body) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = method;
        req.requestUri = '/services/apexrest/v1/agentic/';
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        RestContext.request = req;
        RestContext.response = res;
    }

    @isTest static void testRunRequestEmptyBody() {
        setRestContext('POST', null);

        Test.startTest();
        AIAgenticWebService.ResponseWrapper response = AIAgenticWebService.runRequest();
        Test.stopTest();

        Assert.areEqual('Error', response.status, 'Status should be Error');
        Assert.areEqual(400, response.statusCode, 'Status code should be 400');
        Assert.isTrue(String.isNotempty(response.message), 'Should use REQUEST_FAILED constant');
    }

    @isTest static void testRunRequestInvalidJson() {
        // Invalid JSON body, should trigger exception branch
        setRestContext('POST', '{invalid json');

        Test.startTest();
        AIAgenticWebService.ResponseWrapper response = AIAgenticWebService.runRequest();
        Test.stopTest();

        Assert.areEqual('Error', response.status, 'Status should remain Error');
        Assert.areEqual(400, response.statusCode, 'Status code should remain 400');
        Assert.areEqual(AIConstants.INCORRECT_JSON, response.message, 'Message should be set to INCORRECT_JSON');
    }

    @isTest static void testRunRequestValidJson() {
        // Build a valid request wrapper JSON
        AIAgenticWebService.RequestWrapper reqWrapper = new AIAgenticWebService.RequestWrapper();
        reqWrapper.agentName = 'Test_Agent';
        reqWrapper.userMessage = 'Hello AI';
        reqWrapper.agenticConfigId = null;
        reqWrapper.promptRequestId = null;
        reqWrapper.recordId = null;
        reqWrapper.namedCredentials = null;
        reqWrapper.model = null;
        reqWrapper.type = null;
        reqWrapper.previousResponseId = null;
        reqWrapper.setOfVectorStoreIds = null;

        String body = JSON.serialize(reqWrapper);
        setRestContext('POST', body);

        // ---- Replace AIAgenticUtility.invokeAgent with fake implementation ----
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new FakeInvokeAgentMock());
        AIAgenticWebService.ResponseWrapper response = AIAgenticWebService.runRequest();
        Test.stopTest();

        Assert.isTrue(String.isNotempty(response.responseBody), 'Message should be Mocked Response');
    }

    // ===========================
    // 🔹 MOCK IMPLEMENTATION
    // ===========================
    private class FakeInvokeAgentMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            // Simulate that AIAgenticUtility.invokeAgent returned a success ResponseWrapper
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"Success","statusCode":200,"message":"Mocked Response"}');
            return res;
        }
    }
}