/**
 * Test class for AIOutlookFetchService
 * Tests direct Microsoft Graph API calls using access token
 * 
 * @author GPTfy
 * @date 2026-01-16
 */
@isTest
private class AIOutlookFetchServiceTest {
    
    private static final String MOCK_ACCESS_TOKEN = 'mock_access_token_12345';
    
    // ========================================================================
    // USER EMAIL TESTS
    // ========================================================================
    
    @isTest
    static void testGetUserEmail_Success() {
        // Setup mock
        Test.setMock(HttpCalloutMock.class, new MockGraphUserResponse());
        
        Test.startTest();
        String email = AIOutlookFetchService.getUserEmail(MOCK_ACCESS_TOKEN);
        Test.stopTest();
        
        Assert.areEqual('user@example.com', email, 'Should return user email');
    }
    
    @isTest
    static void testGetUserEmail_BlankToken() {
        Test.startTest();
        try {
            AIOutlookFetchService.getUserEmail('');
            Assert.fail('Should throw exception for blank token');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetUserEmail_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        
        Test.startTest();
        try {
            AIOutlookFetchService.getUserEmail(MOCK_ACCESS_TOKEN);
            Assert.fail('Should throw exception for API error');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
            Assert.isTrue(e.getMessage().contains('Failed to get user profile'), 'Should indicate failure');
        }
        Test.stopTest();
    }
    
    // ========================================================================
    // EMAIL FETCH TESTS
    // ========================================================================
    
    @isTest
    static void testFetchInboxEmails_Success() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.fetchInboxEmails(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now(),
            50
        );
        Test.stopTest();
        
        Assert.areEqual(2, emails.size(), 'Should return 2 emails');
        Assert.areEqual('Test Subject 1', emails[0].get('subject'), 'Should have correct subject');
    }
    
    @isTest
    static void testFetchSentEmails_Success() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.fetchSentEmails(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now(),
            50
        );
        Test.stopTest();
        
        Assert.areEqual(2, emails.size(), 'Should return 2 emails');
    }
    
    @isTest
    static void testFetchInboxEmails_BlankToken() {
        Test.startTest();
        try {
            AIOutlookFetchService.fetchInboxEmails(
                '',
                DateTime.now().addDays(-7),
                DateTime.now(),
                50
            );
            Assert.fail('Should throw exception for blank token');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testFetchInboxEmails_DefaultMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.fetchInboxEmails(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now(),
            null // Should default to 50
        );
        Test.stopTest();
        
        Assert.areEqual(2, emails.size(), 'Should return emails');
    }
    
    // ========================================================================
    // EMAIL BATCH TESTS
    // ========================================================================
    
    @isTest
    static void testGetEmailDetailsBatch_Success() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        
        List<String> messageIds = new List<String>{ 'msg1', 'msg2' };
        
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.getEmailDetailsBatch(
            MOCK_ACCESS_TOKEN,
            messageIds
        );
        Test.stopTest();
        
        Assert.areEqual(2, emails.size(), 'Should return 2 emails');
    }
    
    @isTest
    static void testGetEmailDetailsBatch_EmptyList() {
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.getEmailDetailsBatch(
            MOCK_ACCESS_TOKEN,
            new List<String>()
        );
        Test.stopTest();
        
        Assert.isTrue(emails.isEmpty(), 'Should return empty list');
    }
    
    @isTest
    static void testGetEmailDetailsBatch_BlankToken() {
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.getEmailDetailsBatch(
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
        Test.setMock(HttpCalloutMock.class, new MockCalendarResponse());
        
        Test.startTest();
        List<Map<String, Object>> events = AIOutlookFetchService.fetchCalendarEvents(
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
            AIOutlookFetchService.fetchCalendarEvents(
                '',
                DateTime.now().addDays(-7),
                DateTime.now().addDays(30),
                50
            );
            Assert.fail('Should throw exception for blank token');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
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
        List<Map<String, Object>> taskLists = AIOutlookFetchService.fetchTaskLists(MOCK_ACCESS_TOKEN);
        Test.stopTest();
        
        Assert.areEqual(2, taskLists.size(), 'Should return 2 task lists');
    }
    
    @isTest
    static void testFetchTaskLists_BlankToken() {
        Test.startTest();
        try {
            AIOutlookFetchService.fetchTaskLists('');
            Assert.fail('Should throw exception for blank token');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testFetchTasks_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        
        Test.startTest();
        List<Map<String, Object>> tasks = AIOutlookFetchService.fetchTasks(
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
            AIOutlookFetchService.fetchTasks('', 50, false);
            Assert.fail('Should throw exception for blank token');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
            Assert.isTrue(e.getMessage().contains('Access token is required'), 'Should indicate token required');
        }
        Test.stopTest();
    }

    @isTest
    static void testFetchTasks_WithDateRange() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        
        Test.startTest();
        List<Map<String, Object>> tasks = AIOutlookFetchService.fetchTasks(
            MOCK_ACCESS_TOKEN,
            50,
            true,
            DateTime.now().addDays(-7),
            DateTime.now()
        );
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks');
    }

    @isTest
    static void testFetchTasks_DefaultMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        
        Test.startTest();
        List<Map<String, Object>> tasks = AIOutlookFetchService.fetchTasks(
            MOCK_ACCESS_TOKEN,
            null,
            true
        );
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle null maxResults');
    }

    @isTest
    static void testFetchTasks_EmptyTaskLists() {
        Test.setMock(HttpCalloutMock.class, new MockEmptyTaskListsResponse());
        
        Test.startTest();
        List<Map<String, Object>> tasks = AIOutlookFetchService.fetchTasks(
            MOCK_ACCESS_TOKEN,
            50,
            false
        );
        Test.stopTest();
        
        Assert.isTrue(tasks.isEmpty(), 'Should return empty list');
    }

    @isTest
    static void testFetchTasks_ExcludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new MockTasksWithCompletedResponse());
        
        Test.startTest();
        List<Map<String, Object>> tasks = AIOutlookFetchService.fetchTasks(
            MOCK_ACCESS_TOKEN,
            50,
            false
        );
        Test.stopTest();
        
        // Should only return non-completed tasks
        for (Map<String, Object> task : tasks) {
            Assert.areNotEqual('completed', task.get('status'), 'Should not include completed tasks');
        }
    }

    @isTest
    static void testFetchTasks_Trimming() {
        Test.setMock(HttpCalloutMock.class, new MockManyTasksResponse());
        
        Test.startTest();
        List<Map<String, Object>> tasks = AIOutlookFetchService.fetchTasks(
            MOCK_ACCESS_TOKEN,
            5,
            true
        );
        Test.stopTest();
        
        Assert.isTrue(tasks.size() <= 5, 'Should trim to max results');
    }

    @isTest
    static void testFetchTasks_TaskListError() {
        Test.setMock(HttpCalloutMock.class, new MockMixedTasksResponse());
        
        Test.startTest();
        List<Map<String, Object>> tasks = AIOutlookFetchService.fetchTasks(
            MOCK_ACCESS_TOKEN,
            50,
            true
        );
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle partial failures');
    }

    // ========================================================================
    // FETCH EMAILS WITH BODY TESTS
    // ========================================================================

    @isTest
    static void testFetchEmailsWithBody_Success() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            20
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return result');
        Assert.areEqual(2, result.emails.size(), 'Should return 2 emails');
        Assert.areEqual(false, result.hasMore, 'Should not have more');
    }

    @isTest
    static void testFetchEmailsWithBody_BlankToken() {
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            '',
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            20
        );
        Test.stopTest();
        
        Assert.isNotNull(result.errorMessage, 'Should have error message');
        Assert.isTrue(result.errorMessage.contains('Access token is required'), 'Should indicate token required');
    }

    @isTest
    static void testFetchEmailsWithBody_DefaultBatchSize() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            null
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should handle null batch size');
    }

    @isTest
    static void testFetchEmailsWithBody_MaxBatchSize() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            100 // Should cap at 50
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should cap batch size');
    }

    @isTest
    static void testFetchEmailsWithBody_SentItems() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'sentitems',
            DateTime.now().addDays(-7),
            DateTime.now(),
            20
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should fetch sent items');
    }

    @isTest
    static void testFetchEmailsWithBody_HasMore() {
        Test.setMock(HttpCalloutMock.class, new MockManyEmailsResponse());
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            2
        );
        Test.stopTest();
        
        Assert.areEqual(true, result.hasMore, 'Should indicate more emails exist');
        Assert.areEqual(2, result.emails.size(), 'Should return only batch size');
    }

    @isTest
    static void testFetchEmailsWithBody_NoContent() {
        Test.setMock(HttpCalloutMock.class, new MockNoContentResponse());
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            20
        );
        Test.stopTest();
        
        Assert.areEqual(false, result.hasMore, 'Should not have more');
        Assert.isTrue(result.emails.isEmpty(), 'Should return empty list');
    }

    @isTest
    static void testFetchEmailsWithBody_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            20
        );
        Test.stopTest();
        
        Assert.isNotNull(result.errorMessage, 'Should have error message');
    }

    @isTest
    static void testFetchEmailsWithBody_WithCursor() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsWithDateResponse());
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            20
        );
        Test.stopTest();
        
        Assert.isNotNull(result.lastEmailDate, 'Should set cursor date');
    }

    // ========================================================================
    // ERROR HANDLING TESTS
    // ========================================================================

    @isTest
    static void testGetUserEmail_FallbackToMail() {
        Test.setMock(HttpCalloutMock.class, new MockUserMailFallbackResponse());
        
        Test.startTest();
        String email = AIOutlookFetchService.getUserEmail(MOCK_ACCESS_TOKEN);
        Test.stopTest();
        
        Assert.areEqual('user@example.com', email, 'Should fallback to mail field');
    }

    @isTest
    static void testGetUserEmail_BlankEmail() {
        Test.setMock(HttpCalloutMock.class, new MockUserBlankEmailResponse());
        
        Test.startTest();
        String email = AIOutlookFetchService.getUserEmail(MOCK_ACCESS_TOKEN);
        Test.stopTest();
        
        Assert.areEqual('', email, 'Should return empty string for blank email');
    }

    @isTest
    static void testFetchInboxEmails_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(500));
        
        Test.startTest();
        try {
            AIOutlookFetchService.fetchInboxEmails(
                MOCK_ACCESS_TOKEN,
                DateTime.now().addDays(-7),
                DateTime.now(),
                50
            );
            Assert.fail('Should throw exception for API error');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch emails'), 'Should indicate failure');
        }
        Test.stopTest();
    }

    @isTest
    static void testFetchCalendarEvents_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(403));
        
        Test.startTest();
        try {
            AIOutlookFetchService.fetchCalendarEvents(
                MOCK_ACCESS_TOKEN,
                DateTime.now().addDays(-7),
                DateTime.now().addDays(30),
                50
            );
            Assert.fail('Should throw exception for API error');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch calendar events'), 'Should indicate failure');
        }
        Test.stopTest();
    }

    @isTest
    static void testFetchCalendarEvents_DefaultMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarResponse());
        
        Test.startTest();
        List<Map<String, Object>> events = AIOutlookFetchService.fetchCalendarEvents(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now().addDays(30),
            null
        );
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should handle null maxResults');
    }

    @isTest
    static void testFetchTaskLists_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(404));
        
        Test.startTest();
        try {
            AIOutlookFetchService.fetchTaskLists(MOCK_ACCESS_TOKEN);
            Assert.fail('Should throw exception for API error');
        } catch (AIOutlookFetchService.OutlookFetchException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch task lists'), 'Should indicate failure');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetEmailDetailsBatch_LargeBatch() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        
        List<String> messageIds = new List<String>();
        for (Integer i = 0; i < 25; i++) {
            messageIds.add('msg' + i);
        }
        
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.getEmailDetailsBatch(
            MOCK_ACCESS_TOKEN,
            messageIds
        );
        Test.stopTest();
        
        Assert.areEqual(25, emails.size(), 'Should handle multiple batches');
    }

    @isTest
    static void testGetEmailDetailsBatch_PartialSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockBatchPartialSuccessResponse());
        
        List<String> messageIds = new List<String>{ 'msg1', 'msg2', 'msg3' };
        
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.getEmailDetailsBatch(
            MOCK_ACCESS_TOKEN,
            messageIds
        );
        Test.stopTest();
        
        Assert.areEqual(3, emails.size(), 'Should return all results');
        Assert.isNull(emails[1], 'Failed message should be null');
    }

    @isTest
    static void testGetEmailDetailsBatch_BatchError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(500));
        
        List<String> messageIds = new List<String>{ 'msg1', 'msg2' };
        
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.getEmailDetailsBatch(
            MOCK_ACCESS_TOKEN,
            messageIds
        );
        Test.stopTest();
        
        Assert.areEqual(2, emails.size(), 'Should return list with nulls');
        Assert.isNull(emails[0], 'Should be null on batch error');
    }

    @isTest
    static void testFetchInboxEmails_ZeroMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        List<Map<String, Object>> emails = AIOutlookFetchService.fetchInboxEmails(
            MOCK_ACCESS_TOKEN,
            DateTime.now().addDays(-7),
            DateTime.now(),
            0 // Should default to 50
        );
        Test.stopTest();
        
        Assert.isNotNull(emails, 'Should handle zero maxResults');
    }

    @isTest
    static void testFetchEmailsWithBody_ZeroBatchSize() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        
        Test.startTest();
        AIOutlookFetchService.EmailBatchResult result = AIOutlookFetchService.fetchEmailsWithBody(
            MOCK_ACCESS_TOKEN,
            'inbox',
            DateTime.now().addDays(-7),
            DateTime.now(),
            0 // Should default to 20
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should handle zero batch size');
    }
    
    // ========================================================================
    // MOCK HTTP CLASSES
    // ========================================================================
    
    private class MockGraphUserResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"userPrincipalName":"user@example.com","mail":"user@example.com","displayName":"Test User"}');
            return res;
        }
    }
    
    private class MockEmailsResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"value":[{"id":"msg1","subject":"Test Subject 1","internetMessageId":"<test1@example.com>"},{"id":"msg2","subject":"Test Subject 2","internetMessageId":"<test2@example.com>"}]}');
            return res;
        }
    }
    
    private class MockBatchResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"responses":[{"id":"0","status":200,"body":{"id":"msg1","subject":"Test 1","body":{"content":"Body 1"}}},{"id":"1","status":200,"body":{"id":"msg2","subject":"Test 2","body":{"content":"Body 2"}}}]}');
            return res;
        }
    }
    
    private class MockCalendarResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"value":[{"id":"evt1","subject":"Meeting 1","iCalUId":"ical1"},{"id":"evt2","subject":"Meeting 2","iCalUId":"ical2"}]}');
            return res;
        }
    }
    
    private class MockTaskListsResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"value":[{"id":"list1","displayName":"Tasks"},{"id":"list2","displayName":"Work"}]}');
            return res;
        }
    }
    
    private class MockTasksResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            // Return task lists first, then tasks
            if (req.getEndpoint().contains('/tasks')) {
                res.setBody('{"value":[{"id":"task1","title":"Task 1","status":"notStarted"},{"id":"task2","title":"Task 2","status":"inProgress"}]}');
            } else {
                res.setBody('{"value":[{"id":"list1","displayName":"Tasks"}]}');
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
            res.setBody('{"error":{"code":"Unauthorized","message":"Invalid token"}}');
            return res;
        }
    }

    private class MockEmptyTaskListsResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"value":[]}');
            return res;
        }
    }

    private class MockTasksWithCompletedResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('/tasks')) {
                res.setBody('{"value":[{"id":"task1","title":"Active Task","status":"notStarted"},{"id":"task2","title":"Completed Task","status":"completed"}]}');
            } else {
                res.setBody('{"value":[{"id":"list1","displayName":"Tasks"}]}');
            }
            return res;
        }
    }

    private class MockManyTasksResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('/tasks')) {
                String tasks = '{"value":[';
                for (Integer i = 1; i <= 10; i++) {
                    if (i > 1) tasks += ',';
                    tasks += '{"id":"task' + i + '","title":"Task ' + i + '","status":"notStarted"}';
                }
                tasks += ']}';
                res.setBody(tasks);
            } else {
                res.setBody('{"value":[{"id":"list1","displayName":"Tasks"}]}');
            }
            return res;
        }
    }

    private class MockMixedTasksResponse implements HttpCalloutMock {
        private Integer callCount = 0;
        
        public HttpResponse respond(HttpRequest req) {
            if (req.getEndpoint().contains('/todo/lists') && !req.getEndpoint().contains('/tasks')) {
                HttpResponse res = new HttpResponse();
                res.setStatusCode(200);
                res.setBody('{"value":[{"id":"list1","displayName":"Tasks"},{"id":"list2","displayName":"Work"}]}');
                return res;
            } else {
                callCount++;
                HttpResponse res = new HttpResponse();
                if (callCount == 1) {
                    res.setStatusCode(500);
                    res.setBody('{"error":"Server error"}');
                } else {
                    res.setStatusCode(200);
                    res.setBody('{"value":[{"id":"task1","title":"Task 1","status":"notStarted"}]}');
                }
                return res;
            }
        }
    }

    private class MockManyEmailsResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String emails = '{"value":[';
            for (Integer i = 1; i <= 5; i++) {
                if (i > 1) emails += ',';
                emails += '{"id":"msg' + i + '","subject":"Test ' + i + '","receivedDateTime":"2024-01-' + String.valueOf(10 + i) + 'T10:00:00Z"}';
            }
            emails += ']}';
            res.setBody(emails);
            return res;
        }
    }

    private class MockNoContentResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(204);
            return res;
        }
    }

    private class MockEmailsWithDateResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"value":[{"id":"msg1","subject":"Test 1","receivedDateTime":"2024-01-15T10:00:00Z"},{"id":"msg2","subject":"Test 2","receivedDateTime":"2024-01-16T10:00:00Z"}]}');
            return res;
        }
    }

    private class MockUserMailFallbackResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"mail":"user@example.com","displayName":"Test User"}');
            return res;
        }
    }

    private class MockUserBlankEmailResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"displayName":"Test User"}');
            return res;
        }
    }

    private class MockBatchPartialSuccessResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"responses":[{"id":"0","status":200,"body":{"id":"msg1","subject":"Test 1"}},{"id":"1","status":404,"body":{"error":"Not found"}},{"id":"2","status":200,"body":{"id":"msg3","subject":"Test 3"}}]}');
            return res;
        }
    }
}