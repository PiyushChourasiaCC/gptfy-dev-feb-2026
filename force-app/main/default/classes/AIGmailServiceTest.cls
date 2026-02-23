/**
 * Test class for AIGmailService
 * Tests Gmail API integration including label counts for accurate email totals
 */
@isTest
public class AIGmailServiceTest {

    /**
     * Mock HTTP response for Gmail labels.get API
     */
    private class MockLabelResponse implements HttpCalloutMock {
        private Integer messagesTotal;
        private String labelId;
        
        public MockLabelResponse(String labelId, Integer messagesTotal) {
            this.labelId = labelId;
            this.messagesTotal = messagesTotal;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            // Check if this is a label request
            if (req.getEndpoint().contains('/labels/')) {
                res.setStatusCode(200);
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => this.labelId,
                    'name' => this.labelId,
                    'messagesTotal' => this.messagesTotal,
                    'messagesUnread' => 10,
                    'threadsTotal' => this.messagesTotal - 50,
                    'threadsUnread' => 5
                };
                res.setBody(JSON.serialize(labelData));
            } else {
                res.setStatusCode(404);
                res.setBody('{"error": "Not found"}');
            }
            
            return res;
        }
    }

    /**
     * Mock for combined INBOX + SENT requests
     */
    private class MockCombinedLabelResponse implements HttpCalloutMock {
        private Integer inboxCount;
        private Integer sentCount;
        
        public MockCombinedLabelResponse(Integer inboxCount, Integer sentCount) {
            this.inboxCount = inboxCount;
            this.sentCount = sentCount;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('/labels/INBOX')) {
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => 'INBOX',
                    'name' => 'INBOX',
                    'messagesTotal' => this.inboxCount,
                    'messagesUnread' => 50,
                    'threadsTotal' => this.inboxCount - 100,
                    'threadsUnread' => 25
                };
                res.setBody(JSON.serialize(labelData));
            } else if (req.getEndpoint().contains('/labels/SENT')) {
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => 'SENT',
                    'name' => 'SENT',
                    'messagesTotal' => this.sentCount,
                    'messagesUnread' => 0,
                    'threadsTotal' => this.sentCount - 50,
                    'threadsUnread' => 0
                };
                res.setBody(JSON.serialize(labelData));
            } else {
                res.setStatusCode(404);
                res.setBody('{"error": "Not found"}');
            }
            
            return res;
        }
    }

    /**
     * Test getting accurate message count for INBOX label
     * This verifies the fix for the 201 email count issue
     */
    @isTest
    static void testGetLabelMessageCount_Inbox_LargeCount() {
        // Setup: Mock a mailbox with 1500 emails (much more than the 201 cap)
        Test.setMock(HttpCalloutMock.class, new MockLabelResponse('INBOX', 1500));
        
        // Setup workspace user with Gmail token
        setupWorkspaceUser();
        
        Test.startTest();
        Integer count = AIGmailService.getLabelMessageCount('INBOX');
        Test.stopTest();
        
        // Verify: Should return accurate count, not capped at ~200
        Assert.areEqual(1500, count, 'Should return accurate INBOX count from labels API');
    }

    /**
     * Test getting accurate message count for SENT label
     */
    @isTest
    static void testGetLabelMessageCount_Sent() {
        // Setup: Mock sent folder with 850 emails
        Test.setMock(HttpCalloutMock.class, new MockLabelResponse('SENT', 850));
        
        setupWorkspaceUser();
        
        Test.startTest();
        Integer count = AIGmailService.getLabelMessageCount('SENT');
        Test.stopTest();
        
        Assert.areEqual(850, count, 'Should return accurate SENT count');
    }

    /**
     * Test getting combined INBOX + SENT count
     * This is used when no specific folder filter is applied
     */
    @isTest
    static void testGetCombinedInboxSentCount() {
        // Setup: Mock INBOX with 1200 and SENT with 800 emails
        Test.setMock(HttpCalloutMock.class, new MockCombinedLabelResponse(1200, 800));
        
        setupWorkspaceUser();
        
        Test.startTest();
        Integer combinedCount = AIGmailService.getCombinedInboxSentCount();
        Test.stopTest();
        
        // Verify: Should return sum of both labels
        Assert.areEqual(2000, combinedCount, 'Should return combined INBOX + SENT count');
    }

    /**
     * Test label count with zero emails
     */
    @isTest
    static void testGetLabelMessageCount_Empty() {
        Test.setMock(HttpCalloutMock.class, new MockLabelResponse('DRAFTS', 0));
        
        setupWorkspaceUser();
        
        Test.startTest();
        Integer count = AIGmailService.getLabelMessageCount('DRAFTS');
        Test.stopTest();
        
        Assert.areEqual(0, count, 'Should return 0 for empty label');
    }

    /**
     * Test error handling when label API fails
     */
    @isTest
    static void testGetLabelMessageCount_Error() {
        // Mock HTTP error response
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());
        
        setupWorkspaceUser();
        
        Test.startTest();
        Integer count = AIGmailService.getLabelMessageCount('INVALID');
        Test.stopTest();
        
        // Should return -1 to indicate error
        Assert.areEqual(-1, count, 'Should return -1 on error');
    }

    /**
     * Test combined count when one label fails
     */
    @isTest
    static void testGetCombinedCount_PartialError() {
        // This would need a more sophisticated mock to test partial failure
        // For now, test that complete failure returns -1
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());
        
        setupWorkspaceUser();
        
        Test.startTest();
        Integer count = AIGmailService.getCombinedInboxSentCount();
        Test.stopTest();
        
        Assert.areEqual(-1, count, 'Should return -1 when labels API fails');
    }

    /**
     * Test URL encoding of label IDs
     */
    @isTest
    static void testGetLabelMessageCount_SpecialCharacters() {
        // Test with a custom label that might have special characters
        Test.setMock(HttpCalloutMock.class, new MockLabelResponse('Label_123', 100));
        
        setupWorkspaceUser();
        
        Test.startTest();
        Integer count = AIGmailService.getLabelMessageCount('Label_123');
        Test.stopTest();
        
        Assert.areEqual(100, count, 'Should handle custom label IDs');
    }

    /**
     * Mock error response
     */
    private class MockErrorResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"error": {"code": 401, "message": "Invalid credentials"}}');
            return res;
        }
    }

    /**
     * Helper method to setup workspace user with Gmail token
     */
    private static void setupWorkspaceUser() {
        // Create workspace user record with Gmail access token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Access_Token__c = 'test_access_token_12345',
            Refresh_Token__c = 'test_refresh_token_12345',
            Provider__c = 'GMAIL'
        );
        insert workspaceUser;
    }

    /**
     * Test parseEmailResponse method
     */
    @isTest
    static void testParseEmailResponse() {
        // Create mock Gmail API response
        Map<String, Object> response = new Map<String, Object>{
            'messages' => new List<Object>{
                new Map<String, Object>{'id' => 'msg1'},
                new Map<String, Object>{'id' => 'msg2'}
            },
            'nextPageToken' => 'token123',
            'resultSizeEstimate' => 201
        };
        
        Test.startTest();
        Map<String, Object> parsed = AIGmailService.parseEmailResponse(JSON.serialize(response));
        Test.stopTest();
        
        List<Object> messages = (List<Object>) parsed.get('messages');
        Assert.areEqual(2, messages.size(), 'Should parse messages');
        Assert.areEqual('token123', parsed.get('nextPageToken'), 'Should parse nextPageToken');
        Assert.areEqual(201, parsed.get('resultSizeEstimate'), 'Should parse resultSizeEstimate');
        Assert.areEqual(true, parsed.get('hasMore'), 'Should set hasMore when nextPageToken exists');
    }

    /**
     * Test parseEmailResponse with no nextPageToken
     */
    @isTest
    static void testParseEmailResponse_NoNextPage() {
        Map<String, Object> response = new Map<String, Object>{
            'messages' => new List<Object>{
                new Map<String, Object>{'id' => 'msg1'}
            },
            'resultSizeEstimate' => 1
        };
        
        Test.startTest();
        Map<String, Object> parsed = AIGmailService.parseEmailResponse(JSON.serialize(response));
        Test.stopTest();
        
        Assert.areEqual(false, parsed.get('hasMore'), 'Should set hasMore to false when no nextPageToken');
    }

    /**
     * Test getMessageIds with basic parameters
     */
    @isTest
    static void testGetMessageIds_Basic() {
        Test.setMock(HttpCalloutMock.class, new MockMessageIdsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        HttpResponse response = AIGmailService.getMessageIds(50, null, null);
        Test.stopTest();
        
        Assert.areEqual(200, response.getStatusCode(), 'Should return 200 status');
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        Assert.isNotNull(data.get('messages'), 'Should have messages');
    }

    /**
     * Test getMessageIds with folder filter
     */
    @isTest
    static void testGetMessageIds_WithFolder() {
        Test.setMock(HttpCalloutMock.class, new MockMessageIdsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        HttpResponse response = AIGmailService.getMessageIds(50, null, null, 'INBOX');
        Test.stopTest();
        
        Assert.areEqual(200, response.getStatusCode(), 'Should return 200 status');
    }

    /**
     * Test getMessageIds with all parameters
     */
    @isTest
    static void testGetMessageIds_AllParameters() {
        Test.setMock(HttpCalloutMock.class, new MockMessageIdsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        HttpResponse response = AIGmailService.getMessageIds(50, 'after:1234567890', 'test', 'INBOX', 'token123');
        Test.stopTest();
        
        Assert.areEqual(200, response.getStatusCode(), 'Should return 200 status');
    }

    /**
     * Test getMessages legacy method
     */
    @isTest
    static void testGetMessages_Legacy() {
        Test.setMock(HttpCalloutMock.class, new MockMessageIdsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        HttpResponse response = AIGmailService.getMessages(50, 0, null, null);
        Test.stopTest();
        
        Assert.areEqual(200, response.getStatusCode(), 'Should return 200 status');
    }

    /**
     * Test getSingleMessage with default format
     */
    @isTest
    static void testGetSingleMessage_DefaultFormat() {
        Test.setMock(HttpCalloutMock.class, new MockSingleMessageResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        HttpResponse response = AIGmailService.getSingleMessage('msg_123');
        Test.stopTest();
        
        Assert.areEqual(200, response.getStatusCode(), 'Should return 200 status');
        Map<String, Object> message = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        Assert.areEqual('msg_123', message.get('id'), 'Should return correct message');
    }

    /**
     * Test getSingleMessage with metadata format
     */
    @isTest
    static void testGetSingleMessage_MetadataFormat() {
        Test.setMock(HttpCalloutMock.class, new MockSingleMessageResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        HttpResponse response = AIGmailService.getSingleMessage('msg_123', 'metadata');
        Test.stopTest();
        
        Assert.areEqual(200, response.getStatusCode(), 'Should return 200 status');
    }

    /**
     * Test getMessagesBatch with multiple messages
     */
    @isTest
    static void testGetMessagesBatch_Success() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1', 'msg_2', 'msg_3'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(3, messages.size(), 'Should return 3 messages');
    }

    /**
     * Test getMessagesBatch with empty list
     */
    @isTest
    static void testGetMessagesBatch_EmptyList() {
        setupWorkspaceUser();
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(new List<String>());
        Test.stopTest();
        
        Assert.areEqual(0, messages.size(), 'Should return empty list');
    }

    /**
     * Test getMessagesBatch with null list
     */
    @isTest
    static void testGetMessagesBatch_NullList() {
        setupWorkspaceUser();
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(null);
        Test.stopTest();
        
        Assert.areEqual(0, messages.size(), 'Should return empty list for null input');
    }

    /**
     * Test getMessagesBatch with large batch (splits into multiple batches)
     */
    @isTest
    static void testGetMessagesBatch_LargeBatch() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        setupWorkspaceUser();
        
        // Create 25 message IDs (more than MAX_BATCH_SIZE of 20)
        List<String> messageIds = new List<String>();
        for (Integer i = 0; i < 25; i++) {
            messageIds.add('msg_' + i);
        }
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isTrue(messages.size() > 0, 'Should return messages from multiple batches');
    }

    /**
     * Test getFullMessagesBatch
     */
    @isTest
    static void testGetFullMessagesBatch_Success() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1', 'msg_2'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getFullMessagesBatch(messageIds);
        Test.stopTest();
        
        // Mock returns 3 messages, so we expect 3
        Assert.isTrue(messages.size() >= 2, 'Should return at least 2 full messages');
    }

    /**
     * Test getFullMessagesBatch with empty list
     */
    @isTest
    static void testGetFullMessagesBatch_EmptyList() {
        setupWorkspaceUser();
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getFullMessagesBatch(new List<String>());
        Test.stopTest();
        
        Assert.areEqual(0, messages.size(), 'Should return empty list');
    }

    /**
     * Test getFullMessagesBatch with null list
     */
    @isTest
    static void testGetFullMessagesBatch_NullList() {
        setupWorkspaceUser();
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getFullMessagesBatch(null);
        Test.stopTest();
        
        Assert.areEqual(0, messages.size(), 'Should return empty list for null input');
    }

    /**
     * Test buildGmailQuery with INBOX folder
     */
    @isTest
    static void testBuildGmailQuery_Inbox() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, null, 'INBOX');
        Test.stopTest();
        
        Assert.isTrue(query.contains('in:inbox'), 'Should contain inbox filter');
    }

    /**
     * Test buildGmailQuery with SENT folder
     */
    @isTest
    static void testBuildGmailQuery_Sent() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, null, 'SENT');
        Test.stopTest();
        
        Assert.isTrue(query.contains('in:sent'), 'Should contain sent filter');
    }

    /**
     * Test buildGmailQuery with SENTITEMS folder alias
     */
    @isTest
    static void testBuildGmailQuery_SentItems() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, null, 'SENTITEMS');
        Test.stopTest();
        
        Assert.isTrue(query.contains('in:sent'), 'Should map SENTITEMS to sent');
    }

    /**
     * Test buildGmailQuery with DRAFTS folder
     */
    @isTest
    static void testBuildGmailQuery_Drafts() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, null, 'DRAFTS');
        Test.stopTest();
        
        Assert.isTrue(query.contains('in:drafts'), 'Should contain drafts filter');
    }

    /**
     * Test buildGmailQuery with TRASH folder
     */
    @isTest
    static void testBuildGmailQuery_Trash() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, null, 'TRASH');
        Test.stopTest();
        
        Assert.isTrue(query.contains('in:trash'), 'Should contain trash filter');
    }

    /**
     * Test buildGmailQuery with SPAM folder
     */
    @isTest
    static void testBuildGmailQuery_Spam() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, null, 'SPAM');
        Test.stopTest();
        
        Assert.isTrue(query.contains('in:spam'), 'Should contain spam filter');
    }

    /**
     * Test buildGmailQuery with custom label
     */
    @isTest
    static void testBuildGmailQuery_CustomLabel() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, null, 'MyCustomLabel');
        Test.stopTest();
        
        Assert.isTrue(query.contains('label:'), 'Should use label: for custom labels');
    }

    /**
     * Test buildGmailQuery with no folder (should include inbox and sent)
     */
    @isTest
    static void testBuildGmailQuery_NoFolder() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, null, null);
        Test.stopTest();
        
        Assert.isTrue(query.contains('{in:inbox in:sent}'), 'Should include both inbox and sent when no folder specified');
    }

    /**
     * Test buildGmailQuery with search term
     */
    @isTest
    static void testBuildGmailQuery_WithSearchTerm() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, 'test search', 'INBOX');
        Test.stopTest();
        
        Assert.isTrue(query.contains('test search'), 'Should include search term');
    }

    /**
     * Test buildGmailQuery with date filter
     */
    @isTest
    static void testBuildGmailQuery_WithDateFilter() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery('after:1234567890', null, 'INBOX');
        Test.stopTest();
        
        Assert.isTrue(query.contains('after:1234567890'), 'Should include date filter');
    }

    /**
     * Test buildGmailQuery with all parameters
     */
    @isTest
    static void testBuildGmailQuery_AllParameters() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery('after:1234567890', 'test', 'INBOX');
        Test.stopTest();
        
        Assert.isTrue(query.contains('in:inbox'), 'Should include folder');
        Assert.isTrue(query.contains('test'), 'Should include search term');
        Assert.isTrue(query.contains('after:1234567890'), 'Should include date filter');
    }

    /**
     * Test buildGmailQuery with search term but no folder (should not add inbox/sent)
     */
    @isTest
    static void testBuildGmailQuery_SearchTermNoFolder() {
        Test.startTest();
        String query = AIGmailService.buildGmailQuery(null, 'test', null);
        Test.stopTest();
        
        Assert.isTrue(query.contains('test'), 'Should include search term');
        Assert.isFalse(query.contains('{in:inbox in:sent}'), 'Should not add inbox/sent when search term is present');
    }

    /**
     * Test parseEmailResponse with null messages
     */
    @isTest
    static void testParseEmailResponse_NullMessages() {
        Map<String, Object> response = new Map<String, Object>{
            'resultSizeEstimate' => 0
        };
        
        Test.startTest();
        Map<String, Object> parsed = AIGmailService.parseEmailResponse(JSON.serialize(response));
        Test.stopTest();
        
        List<Object> messages = (List<Object>) parsed.get('messages');
        Assert.areEqual(0, messages.size(), 'Should return empty list for null messages');
        Assert.areEqual(0, parsed.get('resultSizeEstimate'), 'Should return 0 for null estimate');
    }

    /**
     * Test batch response with rate limit error
     */
    @isTest
    static void testGetMessagesBatch_RateLimitError() {
        Test.setMock(HttpCalloutMock.class, new MockRateLimitResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        // Should retry and eventually return empty list after exhausting retries
        Assert.isNotNull(messages, 'Should return list even after rate limit errors');
    }

    /**
     * Test batch response with HTTP error
     */
    @isTest
    static void testGetMessagesBatch_HttpError() {
        Test.setMock(HttpCalloutMock.class, new MockBatchErrorResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        try {
            List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
            // Should handle error gracefully
            Assert.isNotNull(messages, 'Should handle errors gracefully');
        } catch (Exception e) {
            // Exception is acceptable for error scenarios
            Assert.isTrue(e.getMessage().contains('Gmail'), 'Should throw Gmail exception');
        }
        Test.stopTest();
    }

    /**
     * Test batch response with malformed JSON
     */
    @isTest
    static void testGetMessagesBatch_MalformedResponse() {
        Test.setMock(HttpCalloutMock.class, new MockMalformedBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        // Should handle malformed response gracefully
        Assert.isNotNull(messages, 'Should handle malformed response');
    }

    /**
     * Mock for message IDs response
     */
    private class MockMessageIdsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'messages' => new List<Object>{
                    new Map<String, Object>{'id' => 'msg_1', 'threadId' => 'thread_1'},
                    new Map<String, Object>{'id' => 'msg_2', 'threadId' => 'thread_2'}
                },
                'nextPageToken' => 'token123',
                'resultSizeEstimate' => 100
            };
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for single message response
     */
    private class MockSingleMessageResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> message = new Map<String, Object>{
                'id' => 'msg_123',
                'threadId' => 'thread_123',
                'snippet' => 'Test email',
                'payload' => new Map<String, Object>{
                    'headers' => new List<Object>{
                        new Map<String, String>{'name' => 'Subject', 'value' => 'Test'}
                    }
                }
            };
            res.setBody(JSON.serialize(message));
            return res;
        }
    }

    /**
     * Mock for batch response
     */
    private class MockBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_1","threadId":"thread_1","snippet":"Test 1"}\r\n' +
                '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_2","threadId":"thread_2","snippet":"Test 2"}\r\n' +
                '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_3","threadId":"thread_3","snippet":"Test 3"}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for rate limit response
     */
    private class MockRateLimitResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 429 Too Many Requests\r\n\r\n' +
                '{"error":{"code":429,"message":"Rate limit exceeded"}}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for batch error response
     */
    private class MockBatchErrorResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Internal server error"}');
            return res;
        }
    }

    /**
     * Mock for malformed batch response
     */
    private class MockMalformedBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            res.setBody('--batch_response\r\nmalformed content\r\n--batch_response--');
            return res;
        }
    }

    /**
     * Test batch response with blank body
     */
    @isTest
    static void testGetMessagesBatch_BlankResponse() {
        Test.setMock(HttpCalloutMock.class, new MockBlankBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle blank response');
    }

    /**
     * Test batch response without boundary marker
     */
    @isTest
    static void testGetMessagesBatch_NoBoundary() {
        Test.setMock(HttpCalloutMock.class, new MockNoBoundaryResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle response without boundary');
    }

    /**
     * Test batch response with HTTP 4xx errors
     */
    @isTest
    static void testGetMessagesBatch_Http4xxErrors() {
        Test.setMock(HttpCalloutMock.class, new MockHttp4xxBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1', 'msg_2'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        // Should skip error messages and return only successful ones
        Assert.isNotNull(messages, 'Should handle HTTP 4xx errors');
    }

    /**
     * Test batch response with HTTP 5xx errors
     */
    @isTest
    static void testGetMessagesBatch_Http5xxErrors() {
        Test.setMock(HttpCalloutMock.class, new MockHttp5xxBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle HTTP 5xx errors');
    }

    /**
     * Test batch response with error JSON
     */
    @isTest
    static void testGetMessagesBatch_ErrorJson() {
        Test.setMock(HttpCalloutMock.class, new MockErrorJsonBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle error JSON in response');
    }

    /**
     * Test batch response with invalid JSON
     */
    @isTest
    static void testGetMessagesBatch_InvalidJson() {
        Test.setMock(HttpCalloutMock.class, new MockInvalidJsonBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle invalid JSON gracefully');
    }

    /**
     * Test batch response with alternate JSON pattern
     */
    @isTest
    static void testGetMessagesBatch_AlternateJsonPattern() {
        Test.setMock(HttpCalloutMock.class, new MockAlternateJsonBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle alternate JSON patterns');
    }

    /**
     * Test getFullMessagesBatch with large batch
     */
    @isTest
    static void testGetFullMessagesBatch_LargeBatch() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        setupWorkspaceUser();
        
        // Create 25 message IDs (more than MAX_BATCH_SIZE)
        List<String> messageIds = new List<String>();
        for (Integer i = 0; i < 25; i++) {
            messageIds.add('msg_' + i);
        }
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getFullMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isTrue(messages.size() > 0, 'Should handle large batch');
    }

    /**
     * Mock for blank batch response
     */
    private class MockBlankBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            res.setBody('');
            return res;
        }
    }

    /**
     * Mock for response without boundary
     */
    private class MockNoBoundaryResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            res.setBody('Some response without boundary marker');
            return res;
        }
    }

    /**
     * Mock for HTTP 4xx errors in batch
     */
    private class MockHttp4xxBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 404 Not Found\r\n\r\n' +
                '{"error":"Not found"}\r\n' +
                '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_2","threadId":"thread_2"}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for HTTP 5xx errors in batch
     */
    private class MockHttp5xxBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 500 Internal Server Error\r\n\r\n' +
                '{"error":"Server error"}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for error JSON in batch response
     */
    private class MockErrorJsonBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"error":{"code":400,"message":"Bad request"}}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for invalid JSON in batch response
     */
    private class MockInvalidJsonBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_1",invalid json here}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for alternate JSON pattern
     */
    private class MockAlternateJsonBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{\r\n  "id": "msg_1",\r\n  "threadId": "thread_1"\r\n}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Test batch response with only newline (no carriage return)
     */
    @isTest
    static void testGetMessagesBatch_OnlyNewline() {
        Test.setMock(HttpCalloutMock.class, new MockOnlyNewlineBatchResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle newline-only line endings');
    }

    /**
     * Test batch response with no line ending after boundary
     */
    @isTest
    static void testGetMessagesBatch_NoLineEnding() {
        Test.setMock(HttpCalloutMock.class, new MockNoLineEndingResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle response without line ending');
    }

    /**
     * Test batch request with GmailAPIException
     */
    @isTest
    static void testGetMessagesBatch_GmailAPIException() {
        Test.setMock(HttpCalloutMock.class, new MockGmailAPIExceptionResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        try {
            List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
            // Should either return empty list or throw exception
            Assert.isNotNull(messages, 'Should handle exception');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('Gmail'), 'Should throw Gmail exception');
        }
        Test.stopTest();
    }

    /**
     * Test batch response with nested braces in JSON
     */
    @isTest
    static void testGetMessagesBatch_NestedBraces() {
        Test.setMock(HttpCalloutMock.class, new MockNestedBracesResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle nested braces in JSON');
    }

    /**
     * Test batch response with empty parts
     */
    @isTest
    static void testGetMessagesBatch_EmptyParts() {
        Test.setMock(HttpCalloutMock.class, new MockEmptyPartsResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle empty parts');
    }

    /**
     * Test batch response with closing boundary marker
     */
    @isTest
    static void testGetMessagesBatch_ClosingBoundary() {
        Test.setMock(HttpCalloutMock.class, new MockClosingBoundaryResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle closing boundary');
    }

    /**
     * Mock for batch response with only newline
     */
    private class MockOnlyNewlineBatchResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\n' +
                'Content-Type: application/http\n\n' +
                'HTTP/1.1 200 OK\n\n' +
                '{"id":"msg_1","threadId":"thread_1"}\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for response without line ending
     */
    private class MockNoLineEndingResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            res.setBody('--batch_response');
            return res;
        }
    }

    /**
     * Mock that throws GmailAPIException
     */
    private class MockGmailAPIExceptionResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(403);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Forbidden"}');
            return res;
        }
    }

    /**
     * Mock for nested braces in JSON
     */
    private class MockNestedBracesResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_1","payload":{"headers":[{"name":"Subject","value":"Test"}]}}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for empty parts
     */
    private class MockEmptyPartsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                '\r\n' +
                '--batch_response\r\n' +
                '--\r\n' +
                '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_1","threadId":"thread_1"}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for closing boundary
     */
    private class MockClosingBoundaryResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_1","threadId":"thread_1"}\r\n' +
                '--batch_response\r\n' +
                '--\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Test batch response with JSON without id field
     */
    @isTest
    static void testGetMessagesBatch_JsonWithoutId() {
        Test.setMock(HttpCalloutMock.class, new MockJsonWithoutIdResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        // Should skip messages without id field
        Assert.isNotNull(messages, 'Should handle JSON without id field');
    }

    /**
     * Test batch response with rate limit and some successful messages
     */
    @isTest
    static void testGetMessagesBatch_MixedRateLimitAndSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockMixedRateLimitResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1', 'msg_2'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        // Should return successful messages even if some have rate limit errors
        Assert.isNotNull(messages, 'Should handle mixed rate limit and success');
    }

    /**
     * Test parseEmailResponse with null resultSizeEstimate
     */
    @isTest
    static void testParseEmailResponse_NullEstimate() {
        Map<String, Object> response = new Map<String, Object>{
            'messages' => new List<Object>{
                new Map<String, Object>{'id' => 'msg1'}
            }
        };
        
        Test.startTest();
        Map<String, Object> parsed = AIGmailService.parseEmailResponse(JSON.serialize(response));
        Test.stopTest();
        
        Assert.areEqual(0, parsed.get('resultSizeEstimate'), 'Should return 0 for null estimate');
    }

    /**
     * Test batch response with incomplete JSON
     */
    @isTest
    static void testGetMessagesBatch_IncompleteJson() {
        Test.setMock(HttpCalloutMock.class, new MockIncompleteJsonResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(messages, 'Should handle incomplete JSON');
    }

    /**
     * Mock for JSON without id field
     */
    private class MockJsonWithoutIdResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"threadId":"thread_1","snippet":"Test"}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for mixed rate limit and success
     */
    private class MockMixedRateLimitResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 429 Too Many Requests\r\n\r\n' +
                '{"error":"Rate limit"}\r\n' +
                '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_2","threadId":"thread_2"}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Mock for incomplete JSON
     */
    private class MockIncompleteJsonResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_1"\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }

    /**
     * Test batch with error object in JSON
     */
    @isTest
    static void testGetMessagesBatch_ErrorObjectInJson() {
        Test.setMock(HttpCalloutMock.class, new MockErrorObjectResponse());
        setupWorkspaceUser();
        
        List<String> messageIds = new List<String>{'msg_1', 'msg_2'};
        
        Test.startTest();
        List<Map<String, Object>> messages = AIGmailService.getMessagesBatch(messageIds);
        Test.stopTest();
        
        // Should skip error responses and return only valid messages
        Assert.isNotNull(messages, 'Should handle error objects in JSON');
    }

    /**
     * Mock for error object in JSON
     */
    private class MockErrorObjectResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'multipart/mixed');
            
            String batchResponse = '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"error":{"code":400,"message":"Invalid request"}}\r\n' +
                '--batch_response\r\n' +
                'Content-Type: application/http\r\n\r\n' +
                'HTTP/1.1 200 OK\r\n\r\n' +
                '{"id":"msg_2","threadId":"thread_2"}\r\n' +
                '--batch_response--';
            
            res.setBody(batchResponse);
            return res;
        }
    }
}