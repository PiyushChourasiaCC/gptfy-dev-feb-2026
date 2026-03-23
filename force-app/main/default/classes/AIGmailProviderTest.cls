/**
 * Test class for AIGmailProvider
 * Tests accurate email count retrieval using Gmail labels API
 */
@isTest
public class AIGmailProviderTest {

    /**
     * Mock HTTP response for Gmail API calls (messages list + labels)
     */
    private class MockGmailApiResponse implements HttpCalloutMock {
        private Integer labelCount;
        private String labelId;
        private Integer pageSize;
        
        public MockGmailApiResponse(String labelId, Integer labelCount, Integer pageSize) {
            this.labelId = labelId;
            this.labelCount = labelCount;
            this.pageSize = pageSize;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            // Handle labels.get request (for accurate count)
            if (req.getEndpoint().contains('/labels/')) {
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => this.labelId,
                    'name' => this.labelId,
                    'messagesTotal' => this.labelCount,
                    'messagesUnread' => 50,
                    'threadsTotal' => this.labelCount - 100,
                    'threadsUnread' => 25
                };
                res.setBody(JSON.serialize(labelData));
            }
            // Handle messages.list request
            else if (req.getEndpoint().contains('/messages')) {
                List<Map<String, Object>> messages = new List<Map<String, Object>>();
                for (Integer i = 0; i < this.pageSize; i++) {
                    messages.add(new Map<String, Object>{
                        'id' => 'msg_' + i,
                        'threadId' => 'thread_' + i
                    });
                }
                
                Map<String, Object> response = new Map<String, Object>{
                    'messages' => messages,
                    'nextPageToken' => 'token_next_page',
                    'resultSizeEstimate' => 201 // This is the problematic capped value
                };
                res.setBody(JSON.serialize(response));
            }
            // Handle batch request for message metadata
            else if (req.getEndpoint().contains('/batch/gmail')) {
                String batchResponse = buildBatchResponse(this.pageSize);
                res.setBody(batchResponse);
            }
            
            return res;
        }
        
        private String buildBatchResponse(Integer count) {
            List<String> parts = new List<String>();
            for (Integer i = 0; i < count; i++) {
                String part = '--batch_response\r\n' +
                    'Content-Type: application/http\r\n\r\n' +
                    'HTTP/1.1 200 OK\r\n' +
                    'Content-Type: application/json\r\n\r\n' +
                    '{"id":"msg_' + i + '","threadId":"thread_' + i + '","snippet":"Test email",' +
                    '"labelIds":["INBOX"],"internalDate":"1700000000000",' +
                    '"payload":{"headers":[' +
                    '{"name":"Subject","value":"Test Email ' + i + '"},' +
                    '{"name":"From","value":"sender@example.com"},' +
                    '{"name":"To","value":"recipient@example.com"},' +
                    '{"name":"Date","value":"Wed, 15 Nov 2023 10:00:00 -0800"},' +
                    '{"name":"Message-Id","value":"<msg' + i + '@example.com>"}' +
                    ']}}\r\n';
                parts.add(part);
            }
            return String.join(parts, '') + '--batch_response--';
        }
    }

    /**
     * Mock for combined INBOX + SENT requests
     */
    private class MockCombinedResponse implements HttpCalloutMock {
        private Integer inboxCount;
        private Integer sentCount;
        private Integer pageSize;
        
        public MockCombinedResponse(Integer inboxCount, Integer sentCount, Integer pageSize) {
            this.inboxCount = inboxCount;
            this.sentCount = sentCount;
            this.pageSize = pageSize;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            // Handle labels requests
            if (req.getEndpoint().contains('/labels/INBOX')) {
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => 'INBOX',
                    'messagesTotal' => this.inboxCount
                };
                res.setBody(JSON.serialize(labelData));
            } else if (req.getEndpoint().contains('/labels/SENT')) {
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => 'SENT',
                    'messagesTotal' => this.sentCount
                };
                res.setBody(JSON.serialize(labelData));
            }
            // Handle messages.list
            else if (req.getEndpoint().contains('/messages')) {
                List<Map<String, Object>> messages = new List<Map<String, Object>>();
                for (Integer i = 0; i < this.pageSize; i++) {
                    messages.add(new Map<String, Object>{
                        'id' => 'msg_' + i,
                        'threadId' => 'thread_' + i
                    });
                }
                
                Map<String, Object> response = new Map<String, Object>{
                    'messages' => messages,
                    'nextPageToken' => 'token_next',
                    'resultSizeEstimate' => 201
                };
                res.setBody(JSON.serialize(response));
            }
            // Handle batch request
            else if (req.getEndpoint().contains('/batch/gmail')) {
                res.setBody('--batch_response\r\nContent-Type: application/http\r\n\r\nHTTP/1.1 200 OK\r\n\r\n' +
                    '{"id":"msg_1","threadId":"thread_1","snippet":"Test",' +
                    '"labelIds":["INBOX"],"internalDate":"1700000000000",' +
                    '"payload":{"headers":[' +
                    '{"name":"Subject","value":"Test"},' +
                    '{"name":"From","value":"test@example.com"},' +
                    '{"name":"To","value":"user@example.com"},' +
                    '{"name":"Date","value":"Wed, 15 Nov 2023 10:00:00 -0800"},' +
                    '{"name":"Message-Id","value":"<msg1@example.com>"}' +
                    ']}}\r\n--batch_response--');
            }
            
            return res;
        }
    }

    /**
     * Test that provider returns accurate count from labels API for unfiltered views
     * This is the main fix for the 201 email count issue
     */
    @isTest
    static void testGetEmails_UsesAccurateLabelCount_NoFilters() {
        // Setup: Mock Gmail API with 1500 actual emails but resultSizeEstimate capped at 201
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 1500, 50));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = ''; // No date filter - should use labels API
        request.folder = 'INBOX';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Verify: Should use accurate label count (1500), not resultSizeEstimate (201)
        Assert.areEqual(1500, response.totalCount, 
            'Should return accurate count from labels API when no filters applied');
        Assert.areEqual(true, response.hasMore, 'Should indicate more emails available');
        Assert.isNotNull(response.nextPageToken, 'Should have nextPageToken for pagination');
    }
    
    /**
     * Test that provider returns 0 total count when date filters are applied
     * Labels API returns total for entire label, not filtered results
     */
    @isTest
    static void testGetEmails_WithDateFilter_ReturnsZeroTotal() {
        // Setup: Mock Gmail API with date filter (Today filter)
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 1500, 6));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00Z'; // Date filter applied
        request.folder = 'INBOX';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Verify: Should return 0 total (unknown) when date filter is applied
        // Frontend will calculate actual count from pagination
        Assert.areEqual(0, response.totalCount, 
            'Should return 0 total when date filter applied (labels API not used)');
        Assert.areEqual(6, response.emails.size(), 'Should return 6 emails matching today filter');
    }

    /**
     * Test SENT folder uses accurate label count (no filters)
     */
    @isTest
    static void testGetEmails_SentFolder_AccurateCount() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('SENT', 850, 50));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.folder = 'SENT';
        request.filterCriteria = ''; // No filters
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.areEqual(850, response.totalCount, 'Should return accurate SENT folder count when no filters');
    }

    /**
     * Test no folder filter uses combined INBOX + SENT count (no date filters)
     */
    @isTest
    static void testGetEmails_NoFolder_CombinedCount() {
        // Mock INBOX with 1200 and SENT with 800 emails
        Test.setMock(HttpCalloutMock.class, new MockCombinedResponse(1200, 800, 50));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.filterCriteria = ''; // No filters
        // No folder specified - should get combined count
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Should return combined INBOX + SENT count
        Assert.areEqual(2000, response.totalCount, 
            'Should return combined INBOX + SENT count when no folder and no filters');
    }

    /**
     * Test returns 0 when labels API fails (no filters applied)
     */
    @isTest
    static void testGetEmails_LabelApiFails_ReturnsZero() {
        Test.setMock(HttpCalloutMock.class, new MockLabelApiFailure());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.folder = 'INBOX';
        request.filterCriteria = ''; // No filters
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Should return 0 when labels API fails (frontend will calculate from pagination)
        Assert.areEqual(0, response.totalCount, 
            'Should return 0 when labels API fails');
    }

    /**
     * Test pagination with accurate counts (no filters)
     */
    @isTest
    static void testGetEmails_Pagination_WithAccurateCount() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 2500, 50));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.pageToken = null; // First page
        request.filterCriteria = ''; // No filters - should use labels API
        request.folder = 'INBOX'; // Specify INBOX folder
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.areEqual(2500, response.totalCount, 'Should have accurate total count from labels API');
        // The mock returns 50 messages, so we should get 50 emails
        Assert.isTrue(response.emails.size() > 0, 'Should return emails');
        Assert.areEqual(true, response.hasMore, 'Should have more pages');
        
        // Verify pagination can continue beyond 201 emails
        Assert.isNotNull(response.nextPageToken, 'Should have token for next page');
    }

    /**
     * Test DRAFTS folder (no filters) - DRAFTS is not INBOX or SENT so no label count
     */
    @isTest
    static void testGetEmails_DraftsFolder() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('DRAFT', 25, 25));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.folder = 'DRAFTS';
        request.filterCriteria = ''; // No filters
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // DRAFTS folder is not INBOX or SENT, so it returns 0 (unknown total)
        Assert.areEqual(0, response.totalCount, 'Should return 0 for DRAFTS folder (not INBOX/SENT)');
    }
    
    /**
     * Test with search term - should not use labels API
     */
    @isTest
    static void testGetEmails_WithSearchTerm_ReturnsZeroTotal() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 1500, 10));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.searchTerm = 'invoice'; // Search filter applied
        request.folder = 'INBOX';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Should return 0 total when search is applied (labels API not used)
        Assert.areEqual(0, response.totalCount, 
            'Should return 0 total when search term applied');
        Assert.areEqual(10, response.emails.size(), 'Should return emails matching search');
    }

    /**
     * Mock for label API failure scenario
     */
    private class MockLabelApiFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            // Labels API fails
            if (req.getEndpoint().contains('/labels/')) {
                res.setStatusCode(401);
                res.setBody('{"error": "Unauthorized"}');
            }
            // Messages list succeeds
            else if (req.getEndpoint().contains('/messages')) {
                res.setStatusCode(200);
                Map<String, Object> response = new Map<String, Object>{
                    'messages' => new List<Object>{
                        new Map<String, Object>{'id' => 'msg_1', 'threadId' => 'thread_1'}
                    },
                    'nextPageToken' => 'token',
                    'resultSizeEstimate' => 201
                };
                res.setBody(JSON.serialize(response));
            }
            // Batch succeeds
            else if (req.getEndpoint().contains('/batch/gmail')) {
                res.setStatusCode(200);
                res.setBody('--batch_response\r\nContent-Type: application/http\r\n\r\nHTTP/1.1 200 OK\r\n\r\n' +
                    '{"id":"msg_1","threadId":"thread_1","snippet":"Test",' +
                    '"labelIds":["INBOX"],"internalDate":"1700000000000",' +
                    '"payload":{"headers":[' +
                    '{"name":"Subject","value":"Test"},' +
                    '{"name":"From","value":"test@example.com"},' +
                    '{"name":"To","value":"user@example.com"},' +
                    '{"name":"Date","value":"Wed, 15 Nov 2023 10:00:00 -0800"},' +
                    '{"name":"Message-Id","value":"<msg1@example.com>"}' +
                    ']}}\r\n--batch_response--');
            }
            
            return res;
        }
    }

    /**
     * Helper to setup workspace user
     */
    private static void setupWorkspaceUser() {
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Access_Token__c = 'test_access_token',
            Refresh_Token__c = 'test_refresh_token',
            Provider__c = 'GMAIL_EMAIL'
        );
        insert workspaceUser;
    }

    /**
     * Test OData to Gmail filter conversion
     */
    @isTest
    static void testConvertODataToGmailFilter() {
        // This tests the private method through the public getEmails method
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 10));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00Z and isRead eq false';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // If conversion works, we should get results
        Assert.isNotNull(response, 'Should successfully convert OData filter to Gmail format');
    }

    /**
     * Test getSingleEmail method
     */
    @isTest
    static void testGetSingleEmail_Success() {
        Test.setMock(HttpCalloutMock.class, new MockSingleEmailResponse(200));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        Map<String, Object> email = provider.getSingleEmail('msg_123');
        Test.stopTest();
        
        Assert.isNotNull(email, 'Should return email data');
        Assert.areEqual('msg_123', email.get('id'), 'Should return correct message ID');
    }

    /**
     * Test getSingleEmail with error response
     */
    @isTest
    static void testGetSingleEmail_Error() {
        Test.setMock(HttpCalloutMock.class, new MockSingleEmailResponse(404));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        try {
            Map<String, Object> email = provider.getSingleEmail('invalid_msg');
            Assert.fail('Should throw EmailProviderException');
        } catch (AIEmailProviderService.EmailProviderException e) {
            Assert.isTrue(e.getMessage().contains('Gmail API returned status'), 
                'Should throw exception with status code');
        }
        Test.stopTest();
    }

    /**
     * Test isAuthenticated method - authenticated user
     */
    @isTest
    static void testIsAuthenticated_Success() {
        Test.setMock(HttpCalloutMock.class, new MockProfileResponse(200));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        Boolean isAuth = provider.isAuthenticated();
        Test.stopTest();
        
        Assert.areEqual(true, isAuth, 'Should return true for authenticated user');
    }

    /**
     * Test isAuthenticated method - not authenticated
     */
    @isTest
    static void testIsAuthenticated_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockProfileResponse(401));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        Boolean isAuth = provider.isAuthenticated();
        Test.stopTest();
        
        Assert.areEqual(false, isAuth, 'Should return false for unauthenticated user');
    }

    /**
     * Test isAuthenticated with exception
     */
    @isTest
    static void testIsAuthenticated_Exception() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        Boolean isAuth = provider.isAuthenticated();
        Test.stopTest();
        
        Assert.areEqual(false, isAuth, 'Should return false when exception occurs');
    }

    /**
     * Test getUserEmail method - success
     */
    @isTest
    static void testGetUserEmail_Success() {
        Test.setMock(HttpCalloutMock.class, new MockProfileResponse(200));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        String email = provider.getUserEmail();
        Test.stopTest();
        
        Assert.areEqual('user@example.com', email, 'Should return user email address');
    }

    /**
     * Test getUserEmail method - error
     */
    @isTest
    static void testGetUserEmail_Error() {
        Test.setMock(HttpCalloutMock.class, new MockProfileResponse(401));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        String email = provider.getUserEmail();
        Test.stopTest();
        
        Assert.areEqual('', email, 'Should return empty string on error');
    }

    /**
     * Test getUserEmail with exception
     */
    @isTest
    static void testGetUserEmail_Exception() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        String email = provider.getUserEmail();
        Test.stopTest();
        
        Assert.areEqual('', email, 'Should return empty string when exception occurs');
    }

    /**
     * Test getProviderType method
     */
    @isTest
    static void testGetProviderType() {
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        AIEmailProviderService.ProviderType providerType = provider.getProviderType();
        Test.stopTest();
        
        Assert.areEqual(AIEmailProviderService.ProviderType.GMAIL_EMAIL, providerType, 
            'Should return GMAIL_EMAIL provider type');
    }

    /**
     * Test getEmailsBatch method - success
     */
    @isTest
    static void testGetEmailsBatch_Success() {
        Test.setMock(HttpCalloutMock.class, new MockBatchEmailsResponse(true));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        List<String> messageIds = new List<String>{'msg_1', 'msg_2', 'msg_3'};
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(3, emails.size(), 'Should return 3 emails');
        Assert.isNotNull(emails[0], 'First email should not be null');
    }

    /**
     * Test getEmailsBatch with empty list
     */
    @isTest
    static void testGetEmailsBatch_EmptyList() {
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        List<String> messageIds = new List<String>();
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(0, emails.size(), 'Should return empty list for empty input');
    }

    /**
     * Test getEmailsBatch with null list
     */
    @isTest
    static void testGetEmailsBatch_NullList() {
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(null);
        Test.stopTest();
        
        Assert.areEqual(0, emails.size(), 'Should return empty list for null input');
    }

    /**
     * Test getEmailsBatch with exception fallback
     */
    @isTest
    static void testGetEmailsBatch_ExceptionFallback() {
        Test.setMock(HttpCalloutMock.class, new MockBatchEmailsResponse(false));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        List<String> messageIds = new List<String>{'msg_1'};
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        // Should fall back to base class implementation
        Assert.isNotNull(emails, 'Should return result from fallback');
    }

    /**
     * Test getEmails with API error
     */
    @isTest
    static void testGetEmails_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockApiErrorResponse());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        
        Test.startTest();
        try {
            AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
            Assert.fail('Should throw EmailProviderException');
        } catch (AIEmailProviderService.EmailProviderException e) {
            Assert.isTrue(e.getMessage().contains('Gmail API'), 
                'Should throw exception with Gmail API error');
        }
        Test.stopTest();
    }

    /**
     * Test getEmails with empty message list
     */
    @isTest
    static void testGetEmails_EmptyMessageList() {
        Test.setMock(HttpCalloutMock.class, new MockEmptyMessageListResponse());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.areEqual(0, response.emails.size(), 'Should return empty list');
        Assert.areEqual(false, response.hasMore, 'Should not have more emails');
    }

    /**
     * Test filter conversion - hasAttachments
     */
    @isTest
    static void testConvertODataFilter_HasAttachments() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'hasAttachments eq true';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle hasAttachments filter');
    }

    /**
     * Test filter conversion - isRead eq true
     */
    @isTest
    static void testConvertODataFilter_IsReadTrue() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'isRead eq true';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle isRead eq true filter');
    }

    /**
     * Test filter conversion - receivedDateTime le (before)
     */
    @isTest
    static void testConvertODataFilter_BeforeDate() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'receivedDateTime le 2024-12-31T23:59:59Z';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle receivedDateTime le filter');
    }

    /**
     * Test filter conversion - combined filters
     */
    @isTest
    static void testConvertODataFilter_CombinedFilters() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00Z and receivedDateTime le 2024-12-31T23:59:59Z and isRead eq false and hasAttachments eq true';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle combined filters');
    }

    /**
     * Test SENTITEMS folder alias
     */
    @isTest
    static void testGetEmails_SentItemsFolder() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('SENT', 500, 20));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.folder = 'SENTITEMS'; // Test alias
        request.filterCriteria = '';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.areEqual(500, response.totalCount, 'Should handle SENTITEMS alias');
    }

    /**
     * Mock for single email response
     */
    private class MockSingleEmailResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockSingleEmailResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);
            
            if (this.statusCode == 200) {
                Map<String, Object> message = new Map<String, Object>{
                    'id' => 'msg_123',
                    'threadId' => 'thread_123',
                    'snippet' => 'Test email content',
                    'labelIds' => new List<String>{'INBOX'},
                    'internalDate' => '1700000000000',
                    'payload' => new Map<String, Object>{
                        'headers' => new List<Object>{
                            new Map<String, String>{'name' => 'Subject', 'value' => 'Test Subject'},
                            new Map<String, String>{'name' => 'From', 'value' => 'sender@example.com'},
                            new Map<String, String>{'name' => 'To', 'value' => 'recipient@example.com'},
                            new Map<String, String>{'name' => 'Date', 'value' => 'Wed, 15 Nov 2023 10:00:00 -0800'},
                            new Map<String, String>{'name' => 'Message-Id', 'value' => '<msg123@example.com>'}
                        }
                    }
                };
                res.setBody(JSON.serialize(message));
            } else {
                res.setBody('{"error": "Not found"}');
            }
            
            return res;
        }
    }

    /**
     * Mock for profile response (isAuthenticated and getUserEmail)
     */
    private class MockProfileResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockProfileResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);
            
            if (this.statusCode == 200) {
                Map<String, Object> profile = new Map<String, Object>{
                    'emailAddress' => 'user@example.com',
                    'messagesTotal' => 1500,
                    'threadsTotal' => 1200,
                    'historyId' => '12345'
                };
                res.setBody(JSON.serialize(profile));
            } else {
                res.setBody('{"error": "Unauthorized"}');
            }
            
            return res;
        }
    }

    /**
     * Mock for exception response
     */
    private class MockExceptionResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Network error');
        }
    }

    /**
     * Mock for batch emails response
     */
    private class MockBatchEmailsResponse implements HttpCalloutMock {
        private Boolean shouldSucceed;
        
        public MockBatchEmailsResponse(Boolean shouldSucceed) {
            this.shouldSucceed = shouldSucceed;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            if (this.shouldSucceed) {
                res.setStatusCode(200);
                String batchResponse = '--batch_response\r\n' +
                    'Content-Type: application/http\r\n\r\n' +
                    'HTTP/1.1 200 OK\r\n\r\n' +
                    '{"id":"msg_1","threadId":"thread_1","snippet":"Test 1",' +
                    '"labelIds":["INBOX"],"internalDate":"1700000000000",' +
                    '"payload":{"headers":[' +
                    '{"name":"Subject","value":"Test 1"},' +
                    '{"name":"From","value":"test@example.com"},' +
                    '{"name":"To","value":"user@example.com"},' +
                    '{"name":"Date","value":"Wed, 15 Nov 2023 10:00:00 -0800"},' +
                    '{"name":"Message-Id","value":"<msg1@example.com>"}' +
                    '],"body":{"data":"VGVzdCBib2R5"}}}\r\n' +
                    '--batch_response\r\n' +
                    'Content-Type: application/http\r\n\r\n' +
                    'HTTP/1.1 200 OK\r\n\r\n' +
                    '{"id":"msg_2","threadId":"thread_2","snippet":"Test 2",' +
                    '"labelIds":["INBOX"],"internalDate":"1700000000000",' +
                    '"payload":{"headers":[' +
                    '{"name":"Subject","value":"Test 2"},' +
                    '{"name":"From","value":"test@example.com"},' +
                    '{"name":"To","value":"user@example.com"},' +
                    '{"name":"Date","value":"Wed, 15 Nov 2023 10:00:00 -0800"},' +
                    '{"name":"Message-Id","value":"<msg2@example.com>"}' +
                    '],"body":{"data":"VGVzdCBib2R5"}}}\r\n' +
                    '--batch_response\r\n' +
                    'Content-Type: application/http\r\n\r\n' +
                    'HTTP/1.1 200 OK\r\n\r\n' +
                    '{"id":"msg_3","threadId":"thread_3","snippet":"Test 3",' +
                    '"labelIds":["INBOX"],"internalDate":"1700000000000",' +
                    '"payload":{"headers":[' +
                    '{"name":"Subject","value":"Test 3"},' +
                    '{"name":"From","value":"test@example.com"},' +
                    '{"name":"To","value":"user@example.com"},' +
                    '{"name":"Date","value":"Wed, 15 Nov 2023 10:00:00 -0800"},' +
                    '{"name":"Message-Id","value":"<msg3@example.com>"}' +
                    '],"body":{"data":"VGVzdCBib2R5"}}}\r\n' +
                    '--batch_response--';
                res.setBody(batchResponse);
            } else {
                res.setStatusCode(500);
                res.setBody('{"error": "Internal server error"}');
            }
            
            return res;
        }
    }

    /**
     * Mock for API error response
     */
    private class MockApiErrorResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"error": "Internal server error"}');
            return res;
        }
    }

    /**
     * Mock for empty message list response
     */
    private class MockEmptyMessageListResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('/messages')) {
                Map<String, Object> response = new Map<String, Object>{
                    'messages' => new List<Object>(),
                    'resultSizeEstimate' => 0
                };
                res.setBody(JSON.serialize(response));
            } else if (req.getEndpoint().contains('/labels/')) {
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => 'INBOX',
                    'messagesTotal' => 0
                };
                res.setBody(JSON.serialize(labelData));
            }
            
            return res;
        }
    }

    /**
     * Test getEmails with transformation errors
     */
    @isTest
    static void testGetEmails_TransformationErrors() {
        Test.setMock(HttpCalloutMock.class, new MockTransformErrorResponse());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.folder = 'INBOX';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Should handle transformation errors gracefully
        Assert.isNotNull(response, 'Should return response even with transformation errors');
    }

    /**
     * Mock for transformation error response
     */
    private class MockTransformErrorResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('/messages')) {
                List<Map<String, Object>> messages = new List<Map<String, Object>>();
                messages.add(new Map<String, Object>{'id' => 'msg_1', 'threadId' => 'thread_1'});
                
                Map<String, Object> response = new Map<String, Object>{
                    'messages' => messages,
                    'resultSizeEstimate' => 1
                };
                res.setBody(JSON.serialize(response));
            } else if (req.getEndpoint().contains('/batch/gmail')) {
                // Return malformed batch response to trigger transformation error
                res.setBody('--batch_response\r\nContent-Type: application/http\r\n\r\nHTTP/1.1 200 OK\r\n\r\n' +
                    '{"id":"msg_1","threadId":"thread_1"}\r\n--batch_response--');
            } else if (req.getEndpoint().contains('/labels/')) {
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => 'INBOX',
                    'messagesTotal' => 100
                };
                res.setBody(JSON.serialize(labelData));
            }
            
            return res;
        }
    }

    /**
     * Test filter conversion with null filter
     */
    @isTest
    static void testConvertODataFilter_NullFilter() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = null;
        request.folder = 'INBOX';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle null filter');
    }

    /**
     * Test filter conversion with invalid date format
     */
    @isTest
    static void testConvertODataFilter_InvalidDateFormat() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'receivedDateTime ge invalid-date';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Should handle invalid date format gracefully
        Assert.isNotNull(response, 'Should handle invalid date format');
    }

    /**
     * Test filter conversion with date containing timezone
     */
    @isTest
    static void testConvertODataFilter_DateWithTimezone() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00+05:30';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle date with timezone');
    }

    /**
     * Test filter conversion with date at end of string
     */
    @isTest
    static void testConvertODataFilter_DateAtEndOfString() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00Z';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle date at end of filter string');
    }

    /**
     * Test filter conversion with unrecognized filter
     */
    @isTest
    static void testConvertODataFilter_UnrecognizedFilter() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'someUnknownField eq value';
        request.folder = 'INBOX';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Should treat unrecognized filter as no filter (returns label count)
        Assert.areEqual(100, response.totalCount, 'Should use label count when filter is unrecognized');
    }

    /**
     * Test getEmailsBatch with null result from transformer
     */
    @isTest
    static void testGetEmailsBatch_NullTransformResult() {
        Test.setMock(HttpCalloutMock.class, new MockBatchWithNullResponse());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        List<String> messageIds = new List<String>{'msg_1', 'msg_2'};
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.isNotNull(emails, 'Should return list even with null results');
    }

    /**
     * Mock for batch response with null results
     */
    private class MockBatchWithNullResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            // Return malformed batch response
            res.setBody('--batch_response\r\nContent-Type: application/http\r\n\r\nHTTP/1.1 200 OK\r\n\r\n' +
                'null\r\n--batch_response--');
            
            return res;
        }
    }

    /**
     * Test getSingleEmail with exception
     */
    @isTest
    static void testGetSingleEmail_Exception() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        
        Test.startTest();
        try {
            Map<String, Object> email = provider.getSingleEmail('msg_123');
            Assert.fail('Should throw EmailProviderException');
        } catch (AIEmailProviderService.EmailProviderException e) {
            Assert.isTrue(e.getMessage().contains('Gmail API error'), 
                'Should throw exception with Gmail API error message');
        }
        Test.stopTest();
    }

    /**
     * Test getEmails with null messages in list
     */
    @isTest
    static void testGetEmails_NullMessagesInList() {
        Test.setMock(HttpCalloutMock.class, new MockNullMessagesResponse());
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.folder = 'INBOX';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle null messages in list');
    }

    /**
     * Mock for null messages in response
     */
    private class MockNullMessagesResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('/messages')) {
                Map<String, Object> response = new Map<String, Object>{
                    'messages' => null,
                    'resultSizeEstimate' => 0
                };
                res.setBody(JSON.serialize(response));
            } else if (req.getEndpoint().contains('/labels/')) {
                Map<String, Object> labelData = new Map<String, Object>{
                    'id' => 'INBOX',
                    'messagesTotal' => 100
                };
                res.setBody(JSON.serialize(labelData));
            }
            
            return res;
        }
    }

    /**
     * Test filter with short date string
     */
    @isTest
    static void testConvertODataFilter_ShortDateString() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        // Should handle short date format gracefully
        Assert.isNotNull(response, 'Should handle short date format');
    }

    /**
     * Test with milliseconds in date
     */
    @isTest
    static void testConvertODataFilter_DateWithMilliseconds() {
        Test.setMock(HttpCalloutMock.class, new MockGmailApiResponse('INBOX', 100, 5));
        setupWorkspaceUser();
        
        AIGmailProvider provider = new AIGmailProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 10;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00.000Z';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle date with milliseconds');
    }
}