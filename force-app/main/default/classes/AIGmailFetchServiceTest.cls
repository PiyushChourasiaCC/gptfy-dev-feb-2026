/**
 * Test class for AIGmailFetchService
 * Tests direct Google API calls using access token
 * 
 * @author GPTfy
 * @date 2026-01-16
 */
@isTest
private class AIGmailFetchServiceTest {
    
    private static final String MOCK_ACCESS_TOKEN = 'mock_access_token_12345';
    
    // ========================================================================
    // USER EMAIL TESTS
    // ========================================================================
    
    @isTest
    static void testGetUserEmail_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGmailProfileResponse());
        
        Test.startTest();
        String email = AIGmailFetchService.getUserEmail(MOCK_ACCESS_TOKEN);
        Test.stopTest();
        
        Assert.areEqual('user@gmail.com', email, 'Should return user email');
    }
    
    @isTest
    static void testGetUserEmail_BlankToken() {
        Test.startTest();
        try {
            AIGmailFetchService.getUserEmail('');
            Assert.fail('Should throw exception for blank token');
        } catch (AIGmailFetchService.GmailFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetUserEmail_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        
        Test.startTest();
        try {
            AIGmailFetchService.getUserEmail(MOCK_ACCESS_TOKEN);
            Assert.fail('Should throw exception for API error');
        } catch (AIGmailFetchService.GmailFetchException e) {
            Assert.isTrue(e.getMessage().contains('Failed to get user profile'), 'Should indicate failure');
        }
        Test.stopTest();
    }
    
    // ========================================================================
    // EMAIL FETCH TESTS
    // ========================================================================
    
    @isTest
    static void testFetchInboxEmails_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGmailMessagesResponse());
        
        Test.startTest();
        List<Map<String, Object>> emails = AIGmailFetchService.fetchInboxEmails(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now(),
            50
        );
        Test.stopTest();
        
        Assert.isFalse(emails.isEmpty(), 'Should return emails');
    }
    
    @isTest
    static void testFetchSentEmails_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGmailMessagesResponse());
        
        Test.startTest();
        List<Map<String, Object>> emails = AIGmailFetchService.fetchSentEmails(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now(),
            50
        );
        Test.stopTest();
        
        Assert.isFalse(emails.isEmpty(), 'Should return emails');
    }
    
    @isTest
    static void testFetchInboxEmails_BlankToken() {
        Test.startTest();
        try {
            AIGmailFetchService.fetchInboxEmails(
                '',
                DateTime.now().addDays(-7),
                DateTime.now(),
                50
            );
            Assert.fail('Should throw exception for blank token');
        } catch (AIGmailFetchService.GmailFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testFetchInboxEmails_EmptyResponse() {
        Test.setMock(HttpCalloutMock.class, new MockEmptyMessagesResponse());
        
        Test.startTest();
        List<Map<String, Object>> emails = AIGmailFetchService.fetchInboxEmails(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now(),
            50
        );
        Test.stopTest();
        
        Assert.isTrue(emails.isEmpty(), 'Should return empty list for empty response');
    }
    
    // ========================================================================
    // EMAIL BATCH TESTS
    // ========================================================================
    
    @isTest
    static void testGetEmailDetailsBatch_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGmailBatchResponse());
        
        List<String> messageIds = new List<String>{ 'msg1', 'msg2' };
        
        Test.startTest();
        List<Map<String, Object>> emails = AIGmailFetchService.getEmailDetailsBatch(
            MOCK_ACCESS_TOKEN,
            messageIds
        );
        Test.stopTest();
        
        Assert.isFalse(emails.isEmpty(), 'Should return emails from batch');
    }
    
    @isTest
    static void testGetEmailDetailsBatch_EmptyList() {
        Test.startTest();
        List<Map<String, Object>> emails = AIGmailFetchService.getEmailDetailsBatch(
            MOCK_ACCESS_TOKEN,
            new List<String>()
        );
        Test.stopTest();
        
        Assert.isTrue(emails.isEmpty(), 'Should return empty list');
    }
    
    @isTest
    static void testGetEmailDetailsBatch_BlankToken() {
        Test.startTest();
        List<Map<String, Object>> emails = AIGmailFetchService.getEmailDetailsBatch(
            '',
            new List<String>{ 'msg1' }
        );
        Test.stopTest();
        
        Assert.isTrue(emails.isEmpty(), 'Should return empty list for blank token');
    }
    
    // ========================================================================
    // CALENDAR TESTS
    // ========================================================================
    
    @isTest
    static void testFetchCalendarEvents_Success() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        
        Test.startTest();
        List<Map<String, Object>> events = AIGmailFetchService.fetchCalendarEvents(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now().addDays(30),
            50
        );
        Test.stopTest();
        
        Assert.areEqual(2, events.size(), 'Should return 2 events');
    }
    
    @isTest
    static void testFetchCalendarEvents_BlankToken() {
        Test.startTest();
        try {
            AIGmailFetchService.fetchCalendarEvents(
                '',
                DateTime.now().addDays(-7),
                DateTime.now().addDays(30),
                50
            );
            Assert.fail('Should throw exception for blank token');
        } catch (AIGmailFetchService.GmailFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }
    
    // ========================================================================
    // TASK TESTS
    // ========================================================================
    
    @isTest
    static void testFetchTaskLists_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTaskListsResponse());
        
        Test.startTest();
        List<Map<String, Object>> taskLists = AIGmailFetchService.fetchTaskLists(MOCK_ACCESS_TOKEN);
        Test.stopTest();
        
        Assert.areEqual(2, taskLists.size(), 'Should return 2 task lists');
    }
    
    @isTest
    static void testFetchTaskLists_BlankToken() {
        Test.startTest();
        try {
            AIGmailFetchService.fetchTaskLists('');
            Assert.fail('Should throw exception for blank token');
        } catch (AIGmailFetchService.GmailFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testFetchTasks_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        
        Test.startTest();
        List<Map<String, Object>> tasks = AIGmailFetchService.fetchTasks(
            MOCK_ACCESS_TOKEN,
            50,
            false
        );
        Test.stopTest();
        
        Assert.isFalse(tasks.isEmpty(), 'Should return tasks');
    }
    
    @isTest
    static void testFetchTasks_BlankToken() {
        Test.startTest();
        try {
            AIGmailFetchService.fetchTasks('', 50, false);
            Assert.fail('Should throw exception for blank token');
        } catch (AIGmailFetchService.GmailFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }
    
    // ========================================================================
    // MOCK HTTP CLASSES
    // ========================================================================
    
    private class MockGmailProfileResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"emailAddress":"user@gmail.com","messagesTotal":1000,"threadsTotal":500}');
            return res;
        }
    }
    
    private class MockGmailMessagesResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('/batch/')) {
                // Batch response format
                String batchResponse = 
                    '--batch_abc123\r\n' +
                    'Content-Type: application/http\r\n\r\n' +
                    'HTTP/1.1 200 OK\r\n' +
                    'Content-Type: application/json\r\n\r\n' +
                    '{"id":"msg1","threadId":"thread1","labelIds":["INBOX"],"snippet":"Test email 1"}\r\n' +
                    '--batch_abc123\r\n' +
                    'Content-Type: application/http\r\n\r\n' +
                    'HTTP/1.1 200 OK\r\n' +
                    'Content-Type: application/json\r\n\r\n' +
                    '{"id":"msg2","threadId":"thread2","labelIds":["INBOX"],"snippet":"Test email 2"}\r\n' +
                    '--batch_abc123--';
                res.setBody(batchResponse);
            } else {
                // List response
                res.setBody('{"messages":[{"id":"msg1","threadId":"thread1"},{"id":"msg2","threadId":"thread2"}],"resultSizeEstimate":2}');
            }
            return res;
        }
    }
    
    private class MockEmptyMessagesResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"resultSizeEstimate":0}');
            return res;
        }
    }
    
    private class MockGmailBatchResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String batchResponse = 
                '--batch_abc123\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n' +
                'Content-Type: application/json\r\n\r\n' +
                '{"id":"msg1","threadId":"thread1","snippet":"Test 1"}\r\n' +
                '--batch_abc123\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n' +
                'Content-Type: application/json\r\n\r\n' +
                '{"id":"msg2","threadId":"thread2","snippet":"Test 2"}\r\n' +
                '--batch_abc123--';
            res.setBody(batchResponse);
            return res;
        }
    }
    
    private class MockCalendarEventsResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"items":[{"id":"evt1","summary":"Meeting 1","status":"confirmed"},{"id":"evt2","summary":"Meeting 2","status":"confirmed"}]}');
            return res;
        }
    }
    
    private class MockTaskListsResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"items":[{"id":"list1","title":"My Tasks"},{"id":"list2","title":"Work"}]}');
            return res;
        }
    }
    
    private class MockTasksResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('/tasks')) {
                res.setBody('{"items":[{"id":"task1","title":"Task 1","status":"needsAction"},{"id":"task2","title":"Task 2","status":"needsAction"}]}');
            } else {
                res.setBody('{"items":[{"id":"list1","title":"My Tasks"}]}');
            }
            return res;
        }
    }
    
    private class MockErrorResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockErrorResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody('{"error":{"code":' + statusCode + ',"message":"Unauthorized"}}');
            return res;
        }
    }
}