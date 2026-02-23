/**
 * @description Test class for AIOutlookOAuthBrowserService
 * Tests OAuth browser-based authentication flows using Custom Settings
 * 
 * @author GPTfy
 * @date 2026-01-20
 */
@isTest
private class AIOutlookOAuthBrowserServiceTest {
    
    /**
     * @description Setup test data - create Custom Setting record
     */
    @TestSetup
    static void setupTestData() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Microsoft_Client_Id__c = 'test-client-id-12345',
            Microsoft_Client_Secret__c = 'test-client-secret-67890',
            Microsoft_Auth_Endpoint__c = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize',
            Microsoft_Token_Endpoint__c = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token',
            Microsoft_Scope__c = 'https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/User.Read offline_access'
        );
        insert settings;
    }
    
    /**
     * @description Mock class for successful token exchange response
     */
    private class SuccessTokenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'access_token' => 'mock_access_token_browser_12345',
                'refresh_token' => 'mock_refresh_token_browser_67890',
                'expires_in' => 3600,
                'token_type' => 'Bearer',
                'scope' => 'Mail.Read User.Read offline_access'
            }));
            return res;
        }
    }
    
    /**
     * @description Mock class for token exchange error response
     */
    private class ErrorTokenMock implements HttpCalloutMock {
        private String errorType;
        
        public ErrorTokenMock(String errorType) {
            this.errorType = errorType;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'error' => errorType,
                'error_description' => 'Test error description for ' + errorType
            }));
            return res;
        }
    }
    
    /**
     * @description Mock class for successful Graph API response
     */
    private class SuccessGraphMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'id' => 'user123',
                'displayName' => 'Test User',
                'mail' => 'test@example.com',
                'userPrincipalName' => 'test@example.com'
            }));
            return res;
        }
    }
    
    /**
     * @description Mock class for Graph API error response
     */
    private class ErrorGraphMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"error": {"code": "InvalidAuthenticationToken", "message": "Access token is expired."}}');
            return res;
        }
    }
    
    /**
     * @description Mock class for emails response
     */
    private class EmailsGraphMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'value' => new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'id' => 'email1',
                        'subject' => 'Test Email 1',
                        'receivedDateTime' => '2026-01-20T10:00:00Z'
                    },
                    new Map<String, Object>{
                        'id' => 'email2',
                        'subject' => 'Test Email 2',
                        'receivedDateTime' => '2026-01-20T09:00:00Z'
                    }
                }
            }));
            return res;
        }
    }
    
    /**
     * @description Test getAuthorizationUrl with Custom Settings configured
     */
    @isTest
    static void testGetAuthorizationUrlWithSettings() {
        // Clear cache to ensure fresh settings are loaded
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        String authUrl = AIOutlookOAuthBrowserService.getAuthorizationUrl('test-state-123');
        Test.stopTest();
        
        // Verify URL contains expected components
        Assert.isTrue(authUrl.contains('client_id=test-client-id-12345'), 'Auth URL should contain client_id from settings');
        Assert.isTrue(authUrl.contains('redirect_uri='), 'Auth URL should contain redirect_uri');
        Assert.isTrue(authUrl.contains('state=test-state-123'), 'Auth URL should contain the provided state');
        Assert.isTrue(authUrl.contains('response_type=code'), 'Auth URL should contain response_type=code');
        Assert.isTrue(authUrl.contains('scope='), 'Auth URL should contain scope');
        Assert.isTrue(authUrl.startsWith('https://login.microsoftonline.com'), 'Auth URL should use configured auth endpoint');
    }
    
    /**
     * @description Test getAuthorizationUrl with null state generates random state
     */
    @isTest
    static void testGetAuthorizationUrlNullState() {
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        String authUrl = AIOutlookOAuthBrowserService.getAuthorizationUrl(null);
        Test.stopTest();
        
        // Should have a state parameter (randomly generated)
        Assert.isTrue(authUrl.contains('state='), 'Auth URL should contain state parameter');
    }
    
    /**
     * @description Test getAuthorizationUrl with blank state generates random state
     */
    @isTest
    static void testGetAuthorizationUrlBlankState() {
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        String authUrl = AIOutlookOAuthBrowserService.getAuthorizationUrl('');
        Test.stopTest();
        
        // Should have a state parameter (randomly generated)
        Assert.isTrue(authUrl.contains('state='), 'Auth URL should contain state parameter');
    }
    
    /**
     * @description Test getAuthorizationUrl without settings throws error
     */
    @isTest
    static void testGetAuthorizationUrlNoSettings() {
        // Delete the settings created in TestSetup
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIOutlookOAuthBrowserService.getAuthorizationUrl('test-state');
            Assert.fail('Should have thrown exception');
        } catch (AuraHandledException e) {
            // AuraHandledException is thrown when Client ID is not configured
            // The message content isn't accessible in test context, just verify exception is thrown
            exceptionThrown = true;
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'AuraHandledException should be thrown when settings are not configured');
    }
    
    /**
     * @description Test exchange code for tokens success
     */
    @isTest
    static void testExchangeCodeForTokensSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.exchangeCodeForTokens('valid_auth_code');
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Token exchange should succeed');
        Assert.areEqual('mock_access_token_browser_12345', result.accessToken, 'Access token should match');
        Assert.areEqual('mock_refresh_token_browser_67890', result.refreshToken, 'Refresh token should match');
        Assert.areEqual(3600, result.expiresIn, 'Expires in should be 3600');
        Assert.areEqual('Bearer', result.tokenType, 'Token type should be Bearer');
    }
    
    /**
     * @description Test exchange code with blank code
     */
    @isTest
    static void testExchangeCodeForTokensBlankCode() {
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.exchangeCodeForTokens('');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token exchange should fail');
        Assert.areEqual('Authorization code is required.', result.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test exchange code with null code
     */
    @isTest
    static void testExchangeCodeForTokensNullCode() {
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.exchangeCodeForTokens(null);
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token exchange should fail');
        Assert.areEqual('Authorization code is required.', result.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test exchange code with invalid_grant error
     */
    @isTest
    static void testExchangeCodeForTokensInvalidGrant() {
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock('invalid_grant'));
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.exchangeCodeForTokens('expired_code');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token exchange should fail');
        Assert.isTrue(result.errorMessage.contains('expired') || result.errorMessage.contains('invalid'), 
            'Error message should indicate expired/invalid code');
    }
    
    /**
     * @description Test exchange code with invalid_client error
     */
    @isTest
    static void testExchangeCodeForTokensInvalidClient() {
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock('invalid_client'));
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.exchangeCodeForTokens('valid_code');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token exchange should fail');
        Assert.isTrue(result.errorMessage.contains('AI Workspace OAuth'), 
            'Error message should mention AI Workspace OAuth');
    }
    
    /**
     * @description Test refresh access token success
     */
    @isTest
    static void testRefreshAccessTokenSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.refreshAccessToken('valid_refresh_token');
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Token refresh should succeed');
        Assert.areEqual('mock_access_token_browser_12345', result.accessToken, 'Access token should match');
    }
    
    /**
     * @description Test refresh access token with blank token
     */
    @isTest
    static void testRefreshAccessTokenBlank() {
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.refreshAccessToken('');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token refresh should fail');
        Assert.areEqual('Refresh token is required.', result.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test refresh access token with null token
     */
    @isTest
    static void testRefreshAccessTokenNull() {
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.refreshAccessToken(null);
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token refresh should fail');
        Assert.areEqual('Refresh token is required.', result.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test refresh access token with error response
     */
    @isTest
    static void testRefreshAccessTokenError() {
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock('invalid_grant'));
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = 
            AIOutlookOAuthBrowserService.refreshAccessToken('expired_refresh_token');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token refresh should fail');
    }
    
    /**
     * @description Test get user profile success
     */
    @isTest
    static void testGetUserProfileSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessGraphMock());
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.GraphResult result = 
            AIOutlookOAuthBrowserService.getUserProfile('valid_access_token');
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Get user profile should succeed');
        Assert.areEqual(200, result.statusCode, 'Status code should be 200');
        Assert.isTrue(result.responseBody.contains('Test User'), 'Response should contain user data');
    }
    
    /**
     * @description Test get user profile with blank token
     */
    @isTest
    static void testGetUserProfileBlankToken() {
        Test.startTest();
        AIOutlookOAuthBrowserService.GraphResult result = 
            AIOutlookOAuthBrowserService.getUserProfile('');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Get user profile should fail');
        Assert.areEqual('Access token is required.', result.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test get user profile with null token
     */
    @isTest
    static void testGetUserProfileNullToken() {
        Test.startTest();
        AIOutlookOAuthBrowserService.GraphResult result = 
            AIOutlookOAuthBrowserService.getUserProfile(null);
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Get user profile should fail');
        Assert.areEqual('Access token is required.', result.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test get user profile with expired token
     */
    @isTest
    static void testGetUserProfileExpiredToken() {
        Test.setMock(HttpCalloutMock.class, new ErrorGraphMock());
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.GraphResult result = 
            AIOutlookOAuthBrowserService.getUserProfile('expired_access_token');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Get user profile should fail');
        Assert.areEqual(401, result.statusCode, 'Status code should be 401');
    }
    
    /**
     * @description Test get user emails success
     */
    @isTest
    static void testGetUserEmailsSuccess() {
        Test.setMock(HttpCalloutMock.class, new EmailsGraphMock());
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.GraphResult result = 
            AIOutlookOAuthBrowserService.getUserEmails('valid_access_token', 10);
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Get user emails should succeed');
        Assert.areEqual(200, result.statusCode, 'Status code should be 200');
        Assert.isTrue(result.responseBody.contains('Test Email 1'), 'Response should contain email data');
    }
    
    /**
     * @description Test get user emails with default max results
     */
    @isTest
    static void testGetUserEmailsDefaultMaxResults() {
        Test.setMock(HttpCalloutMock.class, new EmailsGraphMock());
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIOutlookOAuthBrowserService.GraphResult result = 
            AIOutlookOAuthBrowserService.getUserEmails('valid_access_token', null);
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Get user emails should succeed');
    }
    
    /**
     * @description Test get user emails with blank token
     */
    @isTest
    static void testGetUserEmailsBlankToken() {
        Test.startTest();
        AIOutlookOAuthBrowserService.GraphResult result = 
            AIOutlookOAuthBrowserService.getUserEmails('', 10);
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Get user emails should fail');
        Assert.areEqual('Access token is required.', result.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test TokenResult wrapper class initialization
     */
    @isTest
    static void testTokenResultInitialization() {
        Test.startTest();
        AIOutlookOAuthBrowserService.TokenResult result = new AIOutlookOAuthBrowserService.TokenResult();
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'isSuccess should be false by default');
    }
    
    /**
     * @description Test GraphResult wrapper class initialization
     */
    @isTest
    static void testGraphResultInitialization() {
        Test.startTest();
        AIOutlookOAuthBrowserService.GraphResult result = new AIOutlookOAuthBrowserService.GraphResult();
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'isSuccess should be false by default');
    }
    
    /**
     * @description Test getSettings returns cached value
     */
    @isTest
    static void testSettingsCaching() {
        AIOutlookOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        // First call - should load from database
        AI_Workspace_Sync_Settings__c settings1 = AIOutlookOAuthBrowserService.getSettings();
        // Second call - should use cache
        AI_Workspace_Sync_Settings__c settings2 = AIOutlookOAuthBrowserService.getSettings();
        Test.stopTest();
        
        Assert.isNotNull(settings1, 'Settings should be loaded');
        Assert.areEqual(settings1, settings2, 'Should return same cached instance');
    }
}