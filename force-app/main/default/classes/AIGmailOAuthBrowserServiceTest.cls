/**
 * @description Test class for AIGmailOAuthBrowserService
 * Tests OAuth browser-based authentication flows using Custom Settings
 * 
 * @author GPTfy
 * @date 2026-01-21
 */
@isTest
private class AIGmailOAuthBrowserServiceTest {
    
    /**
     * @description Setup test data - create Custom Setting record
     * Note: Both Microsoft and Google fields are included as Custom Setting is shared
     */
    @TestSetup
    static void setupTestData() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            // Google OAuth settings (required for Gmail tests)
            Google_Client_Id__c = 'test-google-client-id-12345',
            Google_Client_Secret__c = 'test-google-client-secret-67890',
            Google_Auth_Endpoint__c = 'https://accounts.google.com/o/oauth2/v2/auth',
            Google_Token_Endpoint__c = 'https://oauth2.googleapis.com/token',
            Google_Scope__c = 'openid email profile https://www.googleapis.com/auth/gmail.readonly',
            // Microsoft OAuth settings (required fields on Custom Setting)
            Microsoft_Client_Id__c = 'test-microsoft-client-id',
            Microsoft_Client_Secret__c = 'test-microsoft-client-secret',
            Microsoft_Auth_Endpoint__c = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize',
            Microsoft_Token_Endpoint__c = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token',
            Microsoft_Scope__c = 'https://graph.microsoft.com/Mail.Read offline_access'
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
                'access_token' => 'mock_google_access_token_12345',
                'refresh_token' => 'mock_google_refresh_token_67890',
                'expires_in' => 3600,
                'token_type' => 'Bearer',
                'scope' => 'openid email profile gmail.readonly'
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
                'error_description' => 'Test error: ' + errorType
            }));
            return res;
        }
    }
    
    /**
     * @description Mock class for successful API calls
     */
    private class SuccessApiMock implements HttpCalloutMock {
        private String responseBody;
        
        public SuccessApiMock(String responseBody) {
            this.responseBody = responseBody;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * @description Mock class for failed API calls
     */
    private class ErrorApiMock implements HttpCalloutMock {
        private Integer statusCode;
        
        public ErrorApiMock(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody('{"error": "Unauthorized"}');
            return res;
        }
    }
    
    // ==================== getAuthorizationUrl Tests ====================
    
    /**
     * @description Test getAuthorizationUrl with valid settings
     */
    @isTest
    static void testGetAuthorizationUrlWithSettings() {
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        String authUrl = AIGmailOAuthBrowserService.getAuthorizationUrl('test-state');
        Test.stopTest();
        
        Assert.isNotNull(authUrl, 'Auth URL should not be null');
        Assert.isTrue(authUrl.contains('accounts.google.com'), 'URL should contain Google auth endpoint');
        Assert.isTrue(authUrl.contains('test-google-client-id-12345'), 'URL should contain client ID');
        Assert.isTrue(authUrl.contains('test-state'), 'URL should contain state parameter');
        Assert.isTrue(authUrl.contains('access_type=offline'), 'URL should request offline access');
        Assert.isTrue(authUrl.contains('prompt=consent'), 'URL should prompt for consent');
    }
    
    /**
     * @description Test getAuthorizationUrl with blank state generates random state
     */
    @isTest
    static void testGetAuthorizationUrlBlankState() {
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        String authUrl = AIGmailOAuthBrowserService.getAuthorizationUrl('');
        Test.stopTest();
        
        Assert.isNotNull(authUrl, 'Auth URL should not be null');
        Assert.isTrue(authUrl.contains('state='), 'URL should contain state parameter');
    }
    
    /**
     * @description Test getAuthorizationUrl with null state generates random state
     */
    @isTest
    static void testGetAuthorizationUrlNullState() {
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        String authUrl = AIGmailOAuthBrowserService.getAuthorizationUrl(null);
        Test.stopTest();
        
        Assert.isNotNull(authUrl, 'Auth URL should not be null');
        Assert.isTrue(authUrl.contains('state='), 'URL should contain state parameter');
    }
    
    /**
     * @description Test getAuthorizationUrl without settings throws error
     */
    @isTest
    static void testGetAuthorizationUrlNoSettings() {
        // Delete the settings created in TestSetup
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIGmailOAuthBrowserService.getAuthorizationUrl('test-state');
            Assert.fail('Should have thrown exception');
        } catch (AuraHandledException e) {
            // AuraHandledException is thrown when settings are not configured
            exceptionThrown = true;
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'AuraHandledException should be thrown when settings are not configured');
    }
    
    // ==================== exchangeCodeForTokens Tests ====================
    
    /**
     * @description Test exchange code for tokens success
     */
    @isTest
    static void testExchangeCodeForTokensSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.exchangeCodeForTokens('valid_auth_code');
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Token exchange should succeed');
        Assert.areEqual('mock_google_access_token_12345', result.accessToken, 'Access token should match');
        Assert.areEqual('mock_google_refresh_token_67890', result.refreshToken, 'Refresh token should match');
        Assert.areEqual(3600, result.expiresIn, 'Expires in should be 3600');
        Assert.areEqual('Bearer', result.tokenType, 'Token type should be Bearer');
    }
    
    /**
     * @description Test exchange code with blank code
     */
    @isTest
    static void testExchangeCodeForTokensBlankCode() {
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.exchangeCodeForTokens('');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Should fail with blank code');
        Assert.isTrue(result.errorMessage.contains('Authorization code is required'), 
            'Error should mention authorization code required');
    }
    
    /**
     * @description Test exchange code with null code
     */
    @isTest
    static void testExchangeCodeForTokensNullCode() {
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.exchangeCodeForTokens(null);
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Should fail with null code');
    }
    
    /**
     * @description Test exchange code with invalid_grant error
     */
    @isTest
    static void testExchangeCodeForTokensInvalidGrant() {
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock('invalid_grant'));
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.exchangeCodeForTokens('expired_code');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token exchange should fail');
        Assert.isTrue(result.errorMessage.contains('expired') || result.errorMessage.contains('invalid'), 
            'Error message should mention expired or invalid');
    }
    
    /**
     * @description Test exchange code with invalid_client error
     */
    @isTest
    static void testExchangeCodeForTokensInvalidClient() {
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock('invalid_client'));
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.exchangeCodeForTokens('valid_code');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token exchange should fail');
        Assert.isTrue(result.errorMessage.contains('AI Workspace OAuth'), 
            'Error message should mention AI Workspace OAuth');
    }
    
    // ==================== refreshAccessToken Tests ====================
    
    /**
     * @description Test refresh access token success
     */
    @isTest
    static void testRefreshAccessTokenSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.refreshAccessToken('valid_refresh_token');
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Token refresh should succeed');
        Assert.areEqual('mock_google_access_token_12345', result.accessToken, 'Access token should match');
    }
    
    /**
     * @description Test refresh token with blank token
     */
    @isTest
    static void testRefreshAccessTokenBlank() {
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.refreshAccessToken('');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Should fail with blank token');
        Assert.isTrue(result.errorMessage.contains('Refresh token is required'), 
            'Error should mention refresh token required');
    }
    
    /**
     * @description Test refresh token with null token
     */
    @isTest
    static void testRefreshAccessTokenNull() {
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.refreshAccessToken(null);
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Should fail with null token');
    }
    
    /**
     * @description Test refresh token with error response
     */
    @isTest
    static void testRefreshAccessTokenError() {
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock('invalid_grant'));
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = 
            AIGmailOAuthBrowserService.refreshAccessToken('expired_refresh_token');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Token refresh should fail');
    }
    
    // ==================== getUserProfile Tests ====================
    
    /**
     * @description Test get user profile success
     */
    @isTest
    static void testGetUserProfileSuccess() {
        String profileJson = '{"id":"12345","email":"test@gmail.com","name":"Test User"}';
        Test.setMock(HttpCalloutMock.class, new SuccessApiMock(profileJson));
        
        Test.startTest();
        AIGmailOAuthBrowserService.ApiResult result = 
            AIGmailOAuthBrowserService.getUserProfile('valid_access_token');
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Profile fetch should succeed');
        Assert.areEqual(200, result.statusCode, 'Status code should be 200');
        Assert.isTrue(result.responseBody.contains('test@gmail.com'), 'Response should contain email');
    }
    
    /**
     * @description Test get user profile with blank token
     */
    @isTest
    static void testGetUserProfileBlankToken() {
        Test.startTest();
        AIGmailOAuthBrowserService.ApiResult result = 
            AIGmailOAuthBrowserService.getUserProfile('');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Should fail with blank token');
        Assert.isTrue(result.errorMessage.contains('Access token is required'), 
            'Error should mention access token required');
    }
    
    /**
     * @description Test get user profile with null token
     */
    @isTest
    static void testGetUserProfileNullToken() {
        Test.startTest();
        AIGmailOAuthBrowserService.ApiResult result = 
            AIGmailOAuthBrowserService.getUserProfile(null);
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Should fail with null token');
    }
    
    /**
     * @description Test get user profile with expired token
     */
    @isTest
    static void testGetUserProfileExpiredToken() {
        Test.setMock(HttpCalloutMock.class, new ErrorApiMock(401));
        
        Test.startTest();
        AIGmailOAuthBrowserService.ApiResult result = 
            AIGmailOAuthBrowserService.getUserProfile('expired_token');
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Should fail with expired token');
        Assert.areEqual(401, result.statusCode, 'Status code should be 401');
    }
    
    // ==================== getUserEmails Tests ====================
    
    /**
     * @description Test get user emails success
     */
    @isTest
    static void testGetUserEmailsSuccess() {
        String emailsJson = '{"messages":[{"id":"msg1"},{"id":"msg2"}],"resultSizeEstimate":2}';
        Test.setMock(HttpCalloutMock.class, new SuccessApiMock(emailsJson));
        
        Test.startTest();
        AIGmailOAuthBrowserService.ApiResult result = 
            AIGmailOAuthBrowserService.getUserEmails('valid_access_token', 10);
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Emails fetch should succeed');
        Assert.areEqual(200, result.statusCode, 'Status code should be 200');
        Assert.isTrue(result.responseBody.contains('messages'), 'Response should contain messages');
    }
    
    /**
     * @description Test get user emails with blank token
     */
    @isTest
    static void testGetUserEmailsBlankToken() {
        Test.startTest();
        AIGmailOAuthBrowserService.ApiResult result = 
            AIGmailOAuthBrowserService.getUserEmails('', 10);
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Should fail with blank token');
    }
    
    /**
     * @description Test get user emails with default max results
     */
    @isTest
    static void testGetUserEmailsDefaultMaxResults() {
        String emailsJson = '{"messages":[{"id":"msg1"}],"resultSizeEstimate":1}';
        Test.setMock(HttpCalloutMock.class, new SuccessApiMock(emailsJson));
        
        Test.startTest();
        AIGmailOAuthBrowserService.ApiResult result = 
            AIGmailOAuthBrowserService.getUserEmails('valid_access_token', null);
        Test.stopTest();
        
        Assert.areEqual(true, result.isSuccess, 'Emails fetch should succeed with null maxResults');
    }
    
    // ==================== Wrapper Class Tests ====================
    
    /**
     * @description Test TokenResult initialization
     */
    @isTest
    static void testTokenResultInitialization() {
        Test.startTest();
        AIGmailOAuthBrowserService.TokenResult result = new AIGmailOAuthBrowserService.TokenResult();
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Default isSuccess should be false');
    }
    
    /**
     * @description Test ApiResult initialization
     */
    @isTest
    static void testApiResultInitialization() {
        Test.startTest();
        AIGmailOAuthBrowserService.ApiResult result = new AIGmailOAuthBrowserService.ApiResult();
        Test.stopTest();
        
        Assert.areEqual(false, result.isSuccess, 'Default isSuccess should be false');
    }
    
    /**
     * @description Test getSettings returns cached value
     */
    @isTest
    static void testSettingsCaching() {
        AIGmailOAuthBrowserService.clearSettingsCache();
        
        Test.startTest();
        // First call - should load from database
        AI_Workspace_Sync_Settings__c settings1 = AIGmailOAuthBrowserService.getSettings();
        // Second call - should use cache
        AI_Workspace_Sync_Settings__c settings2 = AIGmailOAuthBrowserService.getSettings();
        Test.stopTest();
        
        Assert.isNotNull(settings1, 'Settings should be loaded');
        Assert.areEqual(settings1, settings2, 'Should return same cached instance');
    }
}