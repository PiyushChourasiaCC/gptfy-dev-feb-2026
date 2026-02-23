@isTest
private class AIExchangeEmailServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create AI_Workspace_User__c record for Outlook provider
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            Name = 'Test Outlook Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Access_Token__c = 'test_access_token_12345',
            Refresh_Token__c = 'test_refresh_token_67890'
        );
        insert workspaceUser;
    }

    @isTest
    static void testGetMessages() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        HttpResponse res = AIExchangeEmailService.getMessages(10, 0, '', null);
        Test.stopTest();

        Assert.areEqual(200, res.getStatusCode());
    }

    @isTest
    static void testGetMessagesWithSearch() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        HttpResponse res = AIExchangeEmailService.getMessages(10, 0, '', 'test');
        Test.stopTest();

        Assert.areEqual(200, res.getStatusCode());
    }

    @isTest
    static void testGetSingleMessage() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        HttpResponse res = AIExchangeEmailService.getSingleMessage('123');
        Test.stopTest();

        Assert.areEqual(200, res.getStatusCode());
    }

    @isTest
    static void testParseEmailResponse() {
        String jsonResponse = '{"value": [{"id": "123", "subject": "Test"}], "@odata.nextLink": "http://next"}';
        Map<String, Object> result = AIExchangeEmailService.parseEmailResponse(jsonResponse);

        Assert.areEqual(1, result.get('totalCount'));
        Assert.areEqual(true, result.get('hasMore'));
    }

    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"value": [{"id": "123", "subject": "Test"}]}');
            res.setStatusCode(200);
            return res;
        }
    }
}