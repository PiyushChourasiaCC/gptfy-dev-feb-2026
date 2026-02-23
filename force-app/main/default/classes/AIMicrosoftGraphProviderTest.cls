/**
 * Test class for AIMicrosoftGraphProvider
 * Tests Microsoft Graph API email provider integration
 */
@isTest
public class AIMicrosoftGraphProviderTest {

    /**
     * Helper method to setup workspace user with Outlook token
     */
    private static void setupWorkspaceUser() {
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Access_Token__c = 'test_access_token_12345',
            Refresh_Token__c = 'test_refresh_token_12345',
            Provider__c = 'OUTLOOK'
        );
        insert workspaceUser;
    }

    /**
     * Test getEmails success
     */
    @isTest
    static void testGetEmails_Success() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isTrue(response.emails.size() > 0, 'Should return emails');
        Assert.isNotNull(response.totalCount, 'Should have total count');
    }

    /**
     * Test getEmails with filter criteria
     */
    @isTest
    static void testGetEmails_WithFilter() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00Z';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should return response');
    }

    /**
     * Test getEmails with complex OR filter
     */
    @isTest
    static void testGetEmails_WithComplexFilter() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = '(receivedDateTime ge 2024-01-01T00:00:00Z or sentDateTime ge 2024-01-01T00:00:00Z)';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle complex filter');
    }

    /**
     * Test getEmails with unread filter
     */
    @isTest
    static void testGetEmails_WithUnreadFilter() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'isRead eq false';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle unread filter');
    }

    /**
     * Test getEmails with hasAttachments filter
     */
    @isTest
    static void testGetEmails_WithAttachmentsFilter() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'hasAttachments eq true';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle attachments filter');
    }

    /**
     * Test getEmails with combined filters
     */
    @isTest
    static void testGetEmails_WithCombinedFilters() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = '(receivedDateTime ge 2024-01-01T00:00:00Z or sentDateTime ge 2024-01-01T00:00:00Z) and isRead eq false and hasAttachments eq true';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle combined filters');
    }

    /**
     * Test getEmails with search term
     */
    @isTest
    static void testGetEmails_WithSearchTerm() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.searchTerm = 'important';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle search term');
    }

    /**
     * Test getEmails with API error
     */
    @isTest
    static void testGetEmails_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        
        Test.startTest();
        try {
            AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
            Assert.fail('Should throw EmailProviderException');
        } catch (AIEmailProviderService.EmailProviderException e) {
            Assert.isTrue(e.getMessage().contains('Graph API returned status'), 
                'Should throw exception with status code');
        }
        Test.stopTest();
    }


    /**
     * Test getSingleEmail success
     */
    @isTest
    static void testGetSingleEmail_Success() {
        Test.setMock(HttpCalloutMock.class, new MockSingleEmailResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        Map<String, Object> email = provider.getSingleEmail('msg_123');
        Test.stopTest();
        
        Assert.isNotNull(email, 'Should return email');
        Assert.areEqual('msg_123', email.get('id'), 'Should have correct ID');
    }

    /**
     * Test getSingleEmail with error
     */
    @isTest
    static void testGetSingleEmail_Error() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(404));
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        try {
            Map<String, Object> email = provider.getSingleEmail('invalid_id');
            Assert.fail('Should throw EmailProviderException');
        } catch (AIEmailProviderService.EmailProviderException e) {
            Assert.isTrue(e.getMessage().contains('Graph API returned status'), 
                'Should throw exception');
        }
        Test.stopTest();
    }


    /**
     * Test getProviderType
     */
    @isTest
    static void testGetProviderType() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        AIEmailProviderService.ProviderType providerType = provider.getProviderType();
        Test.stopTest();
        
        Assert.areEqual(AIEmailProviderService.ProviderType.MICROSOFT_GRAPH, providerType, 
            'Should return MICROSOFT_GRAPH provider type');
    }

    /**
     * Test isAuthenticated success
     */
    @isTest
    static void testIsAuthenticated_Success() {
        Test.setMock(HttpCalloutMock.class, new MockAuthResponse(200));
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        Boolean isAuth = provider.isAuthenticated();
        Test.stopTest();
        
        Assert.areEqual(true, isAuth, 'Should return true for authenticated user');
    }

    /**
     * Test isAuthenticated failure
     */
    @isTest
    static void testIsAuthenticated_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockAuthResponse(401));
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        Boolean isAuth = provider.isAuthenticated();
        Test.stopTest();
        
        Assert.areEqual(false, isAuth, 'Should return false for unauthenticated user');
    }

    /**
     * Test getUserEmail success
     */
    @isTest
    static void testGetUserEmail_Success() {
        Test.setMock(HttpCalloutMock.class, new MockUserInfoResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        String email = provider.getUserEmail();
        Test.stopTest();
        
        Assert.areEqual('user@example.com', email, 'Should return user email');
    }

    /**
     * Test getUserEmail with mail fallback
     */
    @isTest
    static void testGetUserEmail_MailFallback() {
        Test.setMock(HttpCalloutMock.class, new MockUserInfoMailFallbackResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        String email = provider.getUserEmail();
        Test.stopTest();
        
        Assert.areEqual('user@example.com', email, 'Should fallback to mail field');
    }

    /**
     * Test getUserEmail with error
     */
    @isTest
    static void testGetUserEmail_Error() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        String email = provider.getUserEmail();
        Test.stopTest();
        
        Assert.areEqual('', email, 'Should return empty string on error');
    }

    /**
     * Test getEmailsBatch success
     */
    @isTest
    static void testGetEmailsBatch_Success() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
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
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        List<String> messageIds = new List<String>();
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(0, emails.size(), 'Should return empty list');
    }

    /**
     * Test getEmailsBatch with null list
     */
    @isTest
    static void testGetEmailsBatch_NullList() {
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(null);
        Test.stopTest();
        
        Assert.areEqual(0, emails.size(), 'Should return empty list for null input');
    }

    /**
     * Test getEmailsBatch with large batch (multiple batches)
     */
    @isTest
    static void testGetEmailsBatch_LargeBatch() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        List<String> messageIds = new List<String>();
        for (Integer i = 0; i < 25; i++) {
            messageIds.add('msg_' + i);
        }
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(25, emails.size(), 'Should handle multiple batches');
    }

    /**
     * Test getEmailsBatch with partial success
     */
    @isTest
    static void testGetEmailsBatch_PartialSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockBatchPartialSuccessResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        List<String> messageIds = new List<String>{'msg_1', 'msg_2', 'msg_3'};
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(3, emails.size(), 'Should return all results');
        Assert.isNotNull(emails[0], 'First email should be present');
        Assert.isNull(emails[1], 'Second email should be null (failed)');
    }

    /**
     * Test getEmailsBatch with batch error
     */
    @isTest
    static void testGetEmailsBatch_BatchError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(500));
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        List<String> messageIds = new List<String>{'msg_1', 'msg_2'};
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(2, emails.size(), 'Should return list with nulls');
        Assert.isNull(emails[0], 'Should be null on batch error');
    }


    /**
     * Test filter simplification with blank filter
     */
    @isTest
    static void testSimplifyFilter_BlankFilter() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = '';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle blank filter');
    }

    /**
     * Test filter simplification with date at end of string
     */
    @isTest
    static void testSimplifyFilter_DateAtEnd() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00.000Z';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle date at end');
    }

    /**
     * Test filter with invalid date format
     */
    @isTest
    static void testSimplifyFilter_InvalidDate() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'receivedDateTime ge invalid-date';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle invalid date gracefully');
    }

    /**
     * Test filter without DateTime pattern
     */
    @isTest
    static void testSimplifyFilter_NoDateTimePattern() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'isRead eq false';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle filter without date pattern');
    }

    // ==================== MOCK CLASSES ====================

    /**
     * Mock for emails response
     */
    private class MockEmailsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'value' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'msg_1',
                        'subject' => 'Test Email 1',
                        'receivedDateTime' => '2024-01-15T10:00:00Z',
                        'isRead' => false,
                        'hasAttachments' => false
                    },
                    new Map<String, Object>{
                        'id' => 'msg_2',
                        'subject' => 'Test Email 2',
                        'receivedDateTime' => '2024-01-16T10:00:00Z',
                        'isRead' => true,
                        'hasAttachments' => true
                    }
                },
                '@odata.count' => 2
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for single email response
     */
    private class MockSingleEmailResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> email = new Map<String, Object>{
                'id' => 'msg_123',
                'subject' => 'Test Email',
                'receivedDateTime' => '2024-01-15T10:00:00Z',
                'from' => new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'sender@example.com'
                    }
                }
            };
            
            res.setBody(JSON.serialize(email));
            return res;
        }
    }

    /**
     * Mock for error response
     */
    private class MockErrorResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockErrorResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Error occurred"}');
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
     * Mock for auth response
     */
    private class MockAuthResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockAuthResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"value":[]}');
            return res;
        }
    }

    /**
     * Mock for user info response
     */
    private class MockUserInfoResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> userInfo = new Map<String, Object>{
                'userPrincipalName' => 'user@example.com',
                'mail' => 'user@example.com',
                'displayName' => 'Test User'
            };
            
            res.setBody(JSON.serialize(userInfo));
            return res;
        }
    }

    /**
     * Mock for user info with mail fallback
     */
    private class MockUserInfoMailFallbackResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> userInfo = new Map<String, Object>{
                'mail' => 'user@example.com',
                'displayName' => 'Test User'
            };
            
            res.setBody(JSON.serialize(userInfo));
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
            res.setHeader('Content-Type', 'application/json');
            
            // Parse request to get number of requests
            Map<String, Object> requestBody = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            List<Object> requests = (List<Object>) requestBody.get('requests');
            
            List<Object> responses = new List<Object>();
            for (Object reqObj : requests) {
                Map<String, Object> request = (Map<String, Object>) reqObj;
                String id = (String) request.get('id');
                
                responses.add(new Map<String, Object>{
                    'id' => id,
                    'status' => 200,
                    'body' => new Map<String, Object>{
                        'id' => 'msg_' + id,
                        'subject' => 'Email ' + id
                    }
                });
            }
            
            Map<String, Object> batchResponse = new Map<String, Object>{
                'responses' => responses
            };
            
            res.setBody(JSON.serialize(batchResponse));
            return res;
        }
    }

    /**
     * Mock for batch partial success
     */
    private class MockBatchPartialSuccessResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> batchResponse = new Map<String, Object>{
                'responses' => new List<Object>{
                    new Map<String, Object>{
                        'id' => '0',
                        'status' => 200,
                        'body' => new Map<String, Object>{
                            'id' => 'msg_1',
                            'subject' => 'Email 1'
                        }
                    },
                    new Map<String, Object>{
                        'id' => '1',
                        'status' => 404,
                        'body' => new Map<String, Object>{
                            'error' => 'Not found'
                        }
                    },
                    new Map<String, Object>{
                        'id' => '2',
                        'status' => 200,
                        'body' => new Map<String, Object>{
                            'id' => 'msg_3',
                            'subject' => 'Email 3'
                        }
                    }
                }
            };
            
            res.setBody(JSON.serialize(batchResponse));
            return res;
        }
    }

    /**
     * Test filter with date containing comma
     */
    @isTest
    static void testParseDateFromFilter_WithComma() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'receivedDateTime ge 2024-01-01T00:00:00.000Z,';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle date with comma');
    }

    /**
     * Test filter with date containing parenthesis
     */
    @isTest
    static void testParseDateFromFilter_WithParenthesis() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = '(receivedDateTime ge 2024-01-01T00:00:00.000Z)';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle date with parenthesis');
    }

    /**
     * Test filter with short date string
     */
    @isTest
    static void testParseDateFromFilter_ShortString() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        request.filterCriteria = 'receivedDateTime ge 2024';
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.isNotNull(response, 'Should handle short date string');
    }

    /**
     * Test getUserEmail with blank userPrincipalName and blank mail
     */
    @isTest
    static void testGetUserEmail_BlankFields() {
        Test.setMock(HttpCalloutMock.class, new MockUserInfoBlankResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        String email = provider.getUserEmail();
        Test.stopTest();
        
        Assert.areEqual('', email, 'Should return empty string for blank fields');
    }

    /**
     * Test getEmails with null response value
     */
    @isTest
    static void testGetEmails_NullValue() {
        Test.setMock(HttpCalloutMock.class, new MockEmailsNullValueResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
        request.recordLimit = 50;
        request.offset = 0;
        
        Test.startTest();
        AIEmailProviderService.EmailProviderResponse response = provider.getEmails(request);
        Test.stopTest();
        
        Assert.areEqual(0, response.emails.size(), 'Should handle null value');
    }

    /**
     * Test getEmailsBatch with exactly 20 messages (single batch)
     */
    @isTest
    static void testGetEmailsBatch_ExactBatchSize() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        List<String> messageIds = new List<String>();
        for (Integer i = 0; i < 20; i++) {
            messageIds.add('msg_' + i);
        }
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(20, emails.size(), 'Should handle exact batch size');
    }

    /**
     * Test getEmailsBatch with 21 messages (two batches)
     */
    @isTest
    static void testGetEmailsBatch_TwoBatches() {
        Test.setMock(HttpCalloutMock.class, new MockBatchResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        List<String> messageIds = new List<String>();
        for (Integer i = 0; i < 21; i++) {
            messageIds.add('msg_' + i);
        }
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(21, emails.size(), 'Should handle two batches');
    }

    /**
     * Test getEmailsBatch with missing response ID
     */
    @isTest
    static void testGetEmailsBatch_MissingResponseId() {
        Test.setMock(HttpCalloutMock.class, new MockBatchMissingIdResponse());
        setupWorkspaceUser();
        
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        List<String> messageIds = new List<String>{'msg_1', 'msg_2', 'msg_3'};
        
        Test.startTest();
        List<Map<String, Object>> emails = provider.getEmailsBatch(messageIds);
        Test.stopTest();
        
        Assert.areEqual(3, emails.size(), 'Should return all results');
        Assert.isNull(emails[1], 'Missing ID should result in null');
    }

    // ==================== ADDITIONAL MOCK CLASSES ====================

    /**
     * Mock for user info with blank fields
     */
    private class MockUserInfoBlankResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> userInfo = new Map<String, Object>{
                'displayName' => 'Test User'
            };
            
            res.setBody(JSON.serialize(userInfo));
            return res;
        }
    }

    /**
     * Mock for emails with null value
     */
    private class MockEmailsNullValueResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                '@odata.count' => 0
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for batch with missing response ID
     */
    private class MockBatchMissingIdResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> batchResponse = new Map<String, Object>{
                'responses' => new List<Object>{
                    new Map<String, Object>{
                        'id' => '0',
                        'status' => 200,
                        'body' => new Map<String, Object>{
                            'id' => 'msg_1',
                            'subject' => 'Email 1'
                        }
                    },
                    new Map<String, Object>{
                        'id' => '2',
                        'status' => 200,
                        'body' => new Map<String, Object>{
                            'id' => 'msg_3',
                            'subject' => 'Email 3'
                        }
                    }
                }
            };
            
            res.setBody(JSON.serialize(batchResponse));
            return res;
        }
    }

    // ==================== TESTS FOR PRIVATE METHODS ====================

    /**
     * Test EmailDateComparator with both dates present
     */
    @isTest
    static void testEmailDateComparator_BothDates() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        AIMicrosoftGraphProvider.EmailDateComparator comparator = new AIMicrosoftGraphProvider.EmailDateComparator();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-15T10:00:00Z'
        };
        Map<String, Object> email2 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-16T10:00:00Z'
        };
        
        Test.startTest();
        Integer result = comparator.compare(email1, email2);
        Test.stopTest();
        
        Assert.areEqual(1, result, 'Should sort newer date first');
    }

    /**
     * Test EmailDateComparator with equal dates
     */
    @isTest
    static void testEmailDateComparator_EqualDates() {
        AIMicrosoftGraphProvider.EmailDateComparator comparator = new AIMicrosoftGraphProvider.EmailDateComparator();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-15T10:00:00Z'
        };
        Map<String, Object> email2 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-15T10:00:00Z'
        };
        
        Test.startTest();
        Integer result = comparator.compare(email1, email2);
        Test.stopTest();
        
        Assert.areEqual(0, result, 'Should return 0 for equal dates');
    }

    /**
     * Test EmailDateComparator with null dates
     */
    @isTest
    static void testEmailDateComparator_NullDates() {
        AIMicrosoftGraphProvider.EmailDateComparator comparator = new AIMicrosoftGraphProvider.EmailDateComparator();
        
        Map<String, Object> email1 = new Map<String, Object>();
        Map<String, Object> email2 = new Map<String, Object>();
        
        Test.startTest();
        Integer result = comparator.compare(email1, email2);
        Test.stopTest();
        
        Assert.areEqual(0, result, 'Should return 0 for both null dates');
    }

    /**
     * Test EmailDateComparator with first date null
     */
    @isTest
    static void testEmailDateComparator_FirstDateNull() {
        AIMicrosoftGraphProvider.EmailDateComparator comparator = new AIMicrosoftGraphProvider.EmailDateComparator();
        
        Map<String, Object> email1 = new Map<String, Object>();
        Map<String, Object> email2 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-15T10:00:00Z'
        };
        
        Test.startTest();
        Integer result = comparator.compare(email1, email2);
        Test.stopTest();
        
        Assert.areEqual(1, result, 'Null date should go to end');
    }

    /**
     * Test EmailDateComparator with second date null
     */
    @isTest
    static void testEmailDateComparator_SecondDateNull() {
        AIMicrosoftGraphProvider.EmailDateComparator comparator = new AIMicrosoftGraphProvider.EmailDateComparator();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-15T10:00:00Z'
        };
        Map<String, Object> email2 = new Map<String, Object>();
        
        Test.startTest();
        Integer result = comparator.compare(email1, email2);
        Test.stopTest();
        
        Assert.areEqual(-1, result, 'Null date should go to end');
    }

    /**
     * Test EmailDateComparator with sentDateTime fallback
     */
    @isTest
    static void testEmailDateComparator_SentDateTimeFallback() {
        AIMicrosoftGraphProvider.EmailDateComparator comparator = new AIMicrosoftGraphProvider.EmailDateComparator();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'sentDateTime' => '2024-01-15T10:00:00Z'
        };
        Map<String, Object> email2 = new Map<String, Object>{
            'sentDateTime' => '2024-01-16T10:00:00Z'
        };
        
        Test.startTest();
        Integer result = comparator.compare(email1, email2);
        Test.stopTest();
        
        Assert.areEqual(1, result, 'Should use sentDateTime when receivedDateTime not present');
    }

    /**
     * Test EmailDateComparator with invalid date format
     */
    @isTest
    static void testEmailDateComparator_InvalidDate() {
        AIMicrosoftGraphProvider.EmailDateComparator comparator = new AIMicrosoftGraphProvider.EmailDateComparator();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'receivedDateTime' => 'invalid-date'
        };
        Map<String, Object> email2 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-16T10:00:00Z'
        };
        
        Test.startTest();
        Integer result = comparator.compare(email1, email2);
        Test.stopTest();
        
        Assert.areEqual(1, result, 'Should handle invalid date gracefully');
    }

    /**
     * Test EmailDateComparator with long date string
     */
    @isTest
    static void testEmailDateComparator_LongDateString() {
        AIMicrosoftGraphProvider.EmailDateComparator comparator = new AIMicrosoftGraphProvider.EmailDateComparator();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-15T10:00:00.123456789Z'
        };
        Map<String, Object> email2 = new Map<String, Object>{
            'receivedDateTime' => '2024-01-16T10:00:00.987654321Z'
        };
        
        Test.startTest();
        Integer result = comparator.compare(email1, email2);
        Test.stopTest();
        
        Assert.areEqual(1, result, 'Should handle long date strings');
    }

    /**
     * Test applyNonDateFilters with blank filter
     */
    @isTest
    static void testApplyNonDateFilters_BlankFilter() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>{
            new Map<String, Object>{'id' => '1'}
        };
        
        Test.startTest();
        List<Map<String, Object>> result = provider.applyNonDateFilters(emails, '');
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return all emails for blank filter');
    }

    /**
     * Test applyNonDateFilters with null emails
     */
    @isTest
    static void testApplyNonDateFilters_NullEmails() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        List<Map<String, Object>> result = provider.applyNonDateFilters(null, 'isRead eq false');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null for null emails');
    }

    /**
     * Test applyNonDateFilters with empty emails
     */
    @isTest
    static void testApplyNonDateFilters_EmptyEmails() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Test.startTest();
        List<Map<String, Object>> result = provider.applyNonDateFilters(emails, 'isRead eq false');
        Test.stopTest();
        
        Assert.areEqual(0, result.size(), 'Should return empty list for empty emails');
    }

    /**
     * Test applyNonDateFilters with unread filter
     */
    @isTest
    static void testApplyNonDateFilters_UnreadFilter() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>{
            new Map<String, Object>{'id' => '1', 'isRead' => false},
            new Map<String, Object>{'id' => '2', 'isRead' => true},
            new Map<String, Object>{'id' => '3', 'isRead' => false}
        };
        
        Test.startTest();
        List<Map<String, Object>> result = provider.applyNonDateFilters(emails, 'isRead eq false');
        Test.stopTest();
        
        Assert.areEqual(2, result.size(), 'Should filter to unread emails only');
    }

    /**
     * Test applyNonDateFilters with hasAttachments filter
     */
    @isTest
    static void testApplyNonDateFilters_HasAttachmentsFilter() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>{
            new Map<String, Object>{'id' => '1', 'hasAttachments' => true},
            new Map<String, Object>{'id' => '2', 'hasAttachments' => false},
            new Map<String, Object>{'id' => '3', 'hasAttachments' => true}
        };
        
        Test.startTest();
        List<Map<String, Object>> result = provider.applyNonDateFilters(emails, 'hasAttachments eq true');
        Test.stopTest();
        
        Assert.areEqual(2, result.size(), 'Should filter to emails with attachments only');
    }

    /**
     * Test applyNonDateFilters with combined filters
     */
    @isTest
    static void testApplyNonDateFilters_CombinedFilters() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>{
            new Map<String, Object>{'id' => '1', 'isRead' => false, 'hasAttachments' => true},
            new Map<String, Object>{'id' => '2', 'isRead' => true, 'hasAttachments' => true},
            new Map<String, Object>{'id' => '3', 'isRead' => false, 'hasAttachments' => false},
            new Map<String, Object>{'id' => '4', 'isRead' => false, 'hasAttachments' => true}
        };
        
        Test.startTest();
        List<Map<String, Object>> result = provider.applyNonDateFilters(emails, 'isRead eq false and hasAttachments eq true');
        Test.stopTest();
        
        Assert.areEqual(2, result.size(), 'Should filter to unread emails with attachments');
    }

    /**
     * Test applyNonDateFilters with no matching filters
     */
    @isTest
    static void testApplyNonDateFilters_NoMatchingFilters() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>{
            new Map<String, Object>{'id' => '1'}
        };
        
        Test.startTest();
        List<Map<String, Object>> result = provider.applyNonDateFilters(emails, 'subject eq test');
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return all emails when no recognized filters');
    }

    /**
     * Test parseDateFromFilter with blank filter
     */
    @isTest
    static void testParseDateFromFilter_Blank() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        DateTime result = provider.parseDateFromFilter('');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null for blank filter');
    }

    /**
     * Test parseDateFromFilter with null filter
     */
    @isTest
    static void testParseDateFromFilter_Null() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        DateTime result = provider.parseDateFromFilter(null);
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null for null filter');
    }

    /**
     * Test parseDateFromFilter without DateTime pattern
     */
    @isTest
    static void testParseDateFromFilter_NoPattern() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        DateTime result = provider.parseDateFromFilter('isRead eq false');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null when no DateTime pattern found');
    }

    /**
     * Test parseDateFromFilter with DateTime at end of string
     */
    @isTest
    static void testParseDateFromFilter_AtEnd() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        DateTime result = provider.parseDateFromFilter('receivedDateTime ge ');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null when DateTime pattern at end');
    }

    /**
     * Test parseDateFromFilter with valid date
     */
    @isTest
    static void testParseDateFromFilter_ValidDate() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        DateTime result = provider.parseDateFromFilter('receivedDateTime ge 2024-01-15T10:00:00Z');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should parse valid date');
    }

    /**
     * Test parseDateFromFilter with date containing fractional seconds
     */
    @isTest
    static void testParseDateFromFilter_FractionalSeconds() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        DateTime result = provider.parseDateFromFilter('receivedDateTime ge 2024-01-15T10:00:00.123456Z');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should parse date with fractional seconds');
    }

    /**
     * Test parseDateFromFilter with long date string
     */
    @isTest
    static void testParseDateFromFilter_LongDateString() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        DateTime result = provider.parseDateFromFilter('receivedDateTime ge 2024-01-15T10:00:00.123456789012345Z');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should handle long date string');
    }

    /**
     * Test parseDateFromFilter with invalid date format
     */
    @isTest
    static void testParseDateFromFilter_InvalidFormat() {
        AIMicrosoftGraphProvider provider = new AIMicrosoftGraphProvider();
        
        Test.startTest();
        DateTime result = provider.parseDateFromFilter('receivedDateTime ge invalid-date-format');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null for invalid date format');
    }
}