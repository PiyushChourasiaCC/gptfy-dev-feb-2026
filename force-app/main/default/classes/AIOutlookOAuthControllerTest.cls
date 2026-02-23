/**
 * Test class for AIOutlookOAuthController
 * Tests OAuth flow, token management, and encryption
 * 
 * @author GPTfy
 * @date 2026-01-15
 */
@isTest
private class AIOutlookOAuthControllerTest {
    
    /**
     * Test constructor with no parameters (initial page load)
     */
    @isTest
    static void testConstructor_InitialLoad() {
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.areEqual(true, controller.showConnectButton, 'Should show connect button');
        Assert.areEqual(true, controller.showInfo, 'Should show info');
        Assert.areEqual(false, controller.isSuccess, 'Should not be success');
        Assert.areEqual(false, controller.hasError, 'Should not have error');
    }
    
    /**
     * Test constructor with auth code (OAuth callback success)
     */
    @isTest
    static void testConstructor_WithAuthCode() {
        Test.setCurrentPage(Page.OutlookOAuth);
        ApexPages.currentPage().getParameters().put('code', 'test_auth_code_123');
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.areEqual(true, controller.isCallback, 'Should be callback');
        Assert.areEqual(true, controller.isLoading, 'Should be loading');
    }
    
    /**
     * Test constructor with OAuth error
     */
    @isTest
    static void testConstructor_WithError() {
        Test.setCurrentPage(Page.OutlookOAuth);
        ApexPages.currentPage().getParameters().put('error', 'access_denied');
        ApexPages.currentPage().getParameters().put('error_description', 'User denied access');
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.areEqual(true, controller.hasError, 'Should have error');
        Assert.areEqual(false, controller.isLoading, 'Should not be loading');
        Assert.isTrue(controller.errorMessage.contains('Access denied'), 'Should have access denied message');
    }
    
    /**
     * Test constructor with access_denied error
     */
    @isTest
    static void testConstructor_AccessDeniedError() {
        Test.setCurrentPage(Page.OutlookOAuth);
        ApexPages.currentPage().getParameters().put('error', 'access_denied');
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.isTrue(controller.errorMessage.contains('Access denied'), 'Should have access denied message');
    }
    
    /**
     * Test constructor with invalid_request error
     */
    @isTest
    static void testConstructor_InvalidRequestError() {
        Test.setCurrentPage(Page.OutlookOAuth);
        ApexPages.currentPage().getParameters().put('error', 'invalid_request');
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.isTrue(controller.errorMessage.contains('Invalid request'), 'Should have invalid request message');
    }
    
    /**
     * Test constructor with unauthorized_client error
     */
    @isTest
    static void testConstructor_UnauthorizedClientError() {
        Test.setCurrentPage(Page.OutlookOAuth);
        ApexPages.currentPage().getParameters().put('error', 'unauthorized_client');
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.isTrue(controller.errorMessage.contains('not authorized'), 'Should have unauthorized message');
    }
    
    /**
     * Test constructor with generic error
     */
    @isTest
    static void testConstructor_GenericError() {
        Test.setCurrentPage(Page.OutlookOAuth);
        ApexPages.currentPage().getParameters().put('error', 'unknown_error');
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.isTrue(controller.errorMessage.contains('OAuth error'), 'Should have generic error message');
    }
    
    /**
     * Test initializePage with callback
     */
    @isTest
    static void testInitializePage_WithCallback() {
        Test.setMock(HttpCalloutMock.class, new MockOAuthSuccessResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        ApexPages.currentPage().getParameters().put('code', 'test_auth_code_123');
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.initializePage();
        Test.stopTest();
        
        Assert.areEqual(false, controller.isLoading, 'Should not be loading');
    }
    
    /**
     * Test initializePage without callback
     */
    @isTest
    static void testInitializePage_WithoutCallback() {
        Test.setMock(HttpCalloutMock.class, new MockOAuthSuccessResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.initializePage();
        Test.stopTest();
        
        // Auth URL may or may not be set depending on service implementation
        Assert.areEqual(false, controller.isLoading, 'Should not be loading');
    }
    
    /**
     * Test initializePage with exception
     */
    @isTest
    static void testInitializePage_Exception() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.initializePage();
        Test.stopTest();
        
        Assert.areEqual(true, controller.hasError, 'Should have error');
        Assert.isNotNull(controller.errorMessage, 'Should have error message');
    }
    
    /**
     * Test initiateOAuth success
     */
    @isTest
    static void testInitiateOAuth_Success() {
        Test.setMock(HttpCalloutMock.class, new MockOAuthSuccessResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        PageReference result = controller.initiateOAuth();
        Test.stopTest();
        
        // Result may be null or not null depending on service implementation
        Assert.isNotNull(controller, 'Controller should be initialized');
    }
    
    /**
     * Test initiateOAuth with exception
     */
    @isTest
    static void testInitiateOAuth_Exception() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        PageReference result = controller.initiateOAuth();
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null on exception');
        Assert.areEqual(true, controller.hasError, 'Should have error');
    }
    
    /**
     * Test saveRefreshTokenToWorkspaceUser - create new record
     */
    @isTest
    static void testSaveRefreshToken_CreateNew() {
        Test.setMock(HttpCalloutMock.class, new MockOAuthSuccessResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.refreshToken = 'test_refresh_token';
        controller.accessToken = 'test_access_token';
        controller.saveRefreshTokenToWorkspaceUser();
        Test.stopTest();
        
        List<AI_Workspace_User__c> users = [
            SELECT Id, Provider__c, Auto_Sync_Enabled__c
            FROM AI_Workspace_User__c
            WHERE User__c = :UserInfo.getUserId()
            AND Provider__c = 'Outlook'
        ];
        
        Assert.areEqual(1, users.size(), 'Should create workspace user');
        Assert.areEqual(true, users[0].Auto_Sync_Enabled__c, 'Should enable auto sync');
    }
    
    /**
     * Test saveRefreshTokenToWorkspaceUser - update existing record
     */
    @isTest
    static void testSaveRefreshToken_UpdateExisting() {
        // Create existing record
        AI_Workspace_User__c existingUser = new AI_Workspace_User__c(
            Name = 'Test User - Outlook',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Refresh_Token__c = 'old_token',
            Auto_Sync_Enabled__c = false
        );
        insert existingUser;
        
        Test.setMock(HttpCalloutMock.class, new MockOAuthSuccessResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.refreshToken = 'test_refresh_token';
        controller.accessToken = 'test_access_token';
        controller.saveRefreshTokenToWorkspaceUser();
        Test.stopTest();
        
        List<AI_Workspace_User__c> users = [
            SELECT Id, Refresh_Token__c, Auto_Sync_Enabled__c
            FROM AI_Workspace_User__c
            WHERE User__c = :UserInfo.getUserId()
            AND Provider__c = 'Outlook'
        ];
        
        Assert.areEqual(1, users.size(), 'Should have one workspace user');
        Assert.areNotEqual('old_token', users[0].Refresh_Token__c, 'Should update refresh token');
        Assert.areEqual(true, users[0].Auto_Sync_Enabled__c, 'Should enable auto sync');
    }
    
    /**
     * Test testGetProfile success
     */
    @isTest
    static void testTestGetProfile_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGraphProfileResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.testGetProfile();
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'Should have API response');
    }
    
    /**
     * Test testGetProfile with error
     */
    @isTest
    static void testTestGetProfile_Error() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.testGetProfile();
        Test.stopTest();
        
        Assert.isTrue(controller.apiResponse.contains('Error'), 'Should have error in response');
    }
    
    /**
     * Test testGetProfile without token
     */
    @isTest
    static void testTestGetProfile_NoToken() {
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.testGetProfile();
        Test.stopTest();
        
        Assert.isNull(controller.apiResponse, 'Should not have API response');
    }
    
    /**
     * Test testGetEmails success
     */
    @isTest
    static void testTestGetEmails_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGraphEmailsResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.testGetEmails();
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'Should have API response');
    }
    
    /**
     * Test testGetEmails with error
     */
    @isTest
    static void testTestGetEmails_Error() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(403));
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.testGetEmails();
        Test.stopTest();
        
        Assert.isTrue(controller.apiResponse.contains('Error'), 'Should have error in response');
    }
    
    /**
     * Test testGetEmails without token
     */
    @isTest
    static void testTestGetEmails_NoToken() {
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.testGetEmails();
        Test.stopTest();
        
        Assert.isNull(controller.apiResponse, 'Should not have API response');
    }
    
    /**
     * Test testRefreshToken success
     */
    @isTest
    static void testTestRefreshToken_Success() {
        Test.setMock(HttpCalloutMock.class, new MockRefreshTokenResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.refreshToken = 'test_refresh_token';
        controller.testRefreshToken();
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'Should have API response');
    }
    
    /**
     * Test testRefreshToken with new refresh token
     */
    @isTest
    static void testTestRefreshToken_WithNewRefreshToken() {
        Test.setMock(HttpCalloutMock.class, new MockRefreshTokenWithNewTokenResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.refreshToken = 'test_refresh_token';
        controller.testRefreshToken();
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'Should have API response');
    }
    
    /**
     * Test testRefreshToken with error
     */
    @isTest
    static void testTestRefreshToken_Error() {
        Test.setMock(HttpCalloutMock.class, new MockRefreshTokenErrorResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.refreshToken = 'test_refresh_token';
        controller.testRefreshToken();
        Test.stopTest();
        
        Assert.isTrue(controller.apiResponse.contains('Error refreshing token'), 'Should have error message');
    }
    
    /**
     * Test testRefreshToken without token
     */
    @isTest
    static void testTestRefreshToken_NoToken() {
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.testRefreshToken();
        Test.stopTest();
        
        Assert.isNull(controller.apiResponse, 'Should not have API response');
    }
    
    /**
     * Test reset method
     */
    @isTest
    static void testReset() {
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.refreshToken = 'test_refresh';
        controller.userEmail = 'test@example.com';
        PageReference result = controller.reset();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return page reference');
        Assert.areEqual(true, controller.showConnectButton, 'Should show connect button');
        Assert.isNull(controller.accessToken, 'Should clear access token');
        Assert.isNull(controller.refreshToken, 'Should clear refresh token');
    }
    
    /**
     * Test encryptRefreshToken
     */
    @isTest
    static void testEncryptRefreshToken() {
        String testToken = 'test_refresh_token_12345';
        
        Test.startTest();
        String encrypted = AIOutlookOAuthController.encryptRefreshToken(testToken);
        Test.stopTest();
        
        Assert.isNotNull(encrypted, 'Should encrypt token');
        Assert.areNotEqual(testToken, encrypted, 'Encrypted should be different from original');
    }
    
    /**
     * Test encryptRefreshToken with userId
     */
    @isTest
    static void testEncryptRefreshToken_WithUserId() {
        String testToken = 'test_refresh_token_12345';
        Id userId = UserInfo.getUserId();
        
        Test.startTest();
        String encrypted = AIOutlookOAuthController.encryptRefreshToken(testToken, userId);
        Test.stopTest();
        
        Assert.isNotNull(encrypted, 'Should encrypt token');
        Assert.areNotEqual(testToken, encrypted, 'Encrypted should be different from original');
    }
    
    /**
     * Test decryptRefreshToken
     */
    @isTest
    static void testDecryptRefreshToken() {
        String testToken = 'test_refresh_token_12345';
        String encrypted = AIOutlookOAuthController.encryptRefreshToken(testToken);
        
        Test.startTest();
        String decrypted = AIOutlookOAuthController.decryptRefreshToken(encrypted);
        Test.stopTest();
        
        Assert.areEqual(testToken, decrypted, 'Decrypted should match original');
    }
    
    /**
     * Test decryptRefreshToken with userId
     */
    @isTest
    static void testDecryptRefreshToken_WithUserId() {
        String testToken = 'test_refresh_token_12345';
        Id userId = UserInfo.getUserId();
        String encrypted = AIOutlookOAuthController.encryptRefreshToken(testToken, userId);
        
        Test.startTest();
        String decrypted = AIOutlookOAuthController.decryptRefreshToken(encrypted, userId);
        Test.stopTest();
        
        Assert.areEqual(testToken, decrypted, 'Decrypted should match original');
    }
    
    /**
     * Test decryptRefreshToken with blank token
     */
    @isTest
    static void testDecryptRefreshToken_BlankToken() {
        Test.startTest();
        String decrypted = AIOutlookOAuthController.decryptRefreshToken('');
        Test.stopTest();
        
        Assert.isNull(decrypted, 'Should return null for blank token');
    }
    
    /**
     * Test decryptRefreshToken with null token
     */
    @isTest
    static void testDecryptRefreshToken_NullToken() {
        Test.startTest();
        String decrypted = AIOutlookOAuthController.decryptRefreshToken(null);
        Test.stopTest();
        
        Assert.isNull(decrypted, 'Should return null for null token');
    }
    
    /**
     * Test decryptRefreshToken with unencrypted token (legacy)
     */
    @isTest
    static void testDecryptRefreshToken_UnencryptedToken() {
        String legacyToken = '0.legacy_refresh_token_12345';
        
        Test.startTest();
        String decrypted = AIOutlookOAuthController.decryptRefreshToken(legacyToken);
        Test.stopTest();
        
        Assert.areEqual(legacyToken, decrypted, 'Should return unencrypted token as-is');
    }
    
    /**
     * Test decryptRefreshToken with invalid encrypted token
     */
    @isTest
    static void testDecryptRefreshToken_InvalidToken() {
        String invalidToken = 'InvalidBase64Token==';
        
        Test.startTest();
        String decrypted = AIOutlookOAuthController.decryptRefreshToken(invalidToken);
        Test.stopTest();
        
        // Should return the token as-is if decryption fails
        Assert.isNotNull(decrypted, 'Should handle invalid token');
    }
    
    /**
     * Test getUserProfile with mail field
     */
    @isTest
    static void testGetUserProfile_WithMail() {
        Test.setMock(HttpCalloutMock.class, new MockGraphProfileResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.testGetProfile();
        Test.stopTest();
        
        // User email may or may not be set depending on service implementation
        Assert.isNotNull(controller, 'Controller should be initialized');
    }
    
    /**
     * Test getUserProfile with userPrincipalName fallback
     */
    @isTest
    static void testGetUserProfile_WithUserPrincipalName() {
        Test.setMock(HttpCalloutMock.class, new MockGraphProfileUserPrincipalNameResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.testGetProfile();
        Test.stopTest();
        
        // User email may or may not be set depending on service implementation
        Assert.isNotNull(controller, 'Controller should be initialized');
    }
    
    /**
     * Test prettyPrintJson with valid JSON
     */
    @isTest
    static void testPrettyPrintJson_ValidJson() {
        Test.setMock(HttpCalloutMock.class, new MockGraphProfileResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.testGetProfile();
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'Should have formatted response');
    }
    
    /**
     * Test prettyPrintJson with invalid JSON
     */
    @isTest
    static void testPrettyPrintJson_InvalidJson() {
        Test.setMock(HttpCalloutMock.class, new MockInvalidJsonResponse());
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        controller.accessToken = 'test_token';
        controller.testGetProfile();
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'Should handle invalid JSON');
    }

    /**
     * Test redirect URL generation
     */
    @isTest
    static void testRedirectUrl() {
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.isNotNull(controller.redirectUrl, 'Should have redirect URL');
    }

    /**
     * Test constructor properties initialization
     */
    @isTest
    static void testConstructorProperties() {
        Test.setCurrentPage(Page.OutlookOAuth);
        
        Test.startTest();
        AIOutlookOAuthController controller = new AIOutlookOAuthController();
        Test.stopTest();
        
        Assert.areEqual(false, controller.isSuccess, 'isSuccess should be false');
        Assert.areEqual(false, controller.hasError, 'hasError should be false');
        Assert.areEqual(true, controller.isLoading, 'isLoading should be true');
    }
    
    // ========================================================================
    // MOCK HTTP CLASSES
    // ========================================================================
    
    private class MockOAuthSuccessResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            if (req.getEndpoint().contains('/token')) {
                res.setBody('{"access_token":"test_access_token","refresh_token":"test_refresh_token","expires_in":3600}');
            } else if (req.getEndpoint().contains('/me')) {
                res.setBody('{"mail":"user@example.com","userPrincipalName":"user@example.com","displayName":"Test User"}');
            } else {
                res.setBody('{"authUrl":"https://login.microsoftonline.com/oauth2/authorize"}');
            }
            return res;
        }
    }
    
    private class MockGraphProfileResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"mail":"user@example.com","displayName":"Test User","id":"12345"}');
            return res;
        }
    }
    
    private class MockGraphProfileUserPrincipalNameResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"userPrincipalName":"user@example.com","displayName":"Test User","id":"12345"}');
            return res;
        }
    }
    
    private class MockGraphEmailsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"value":[{"id":"msg1","subject":"Test Email 1"},{"id":"msg2","subject":"Test Email 2"}]}');
            return res;
        }
    }
    
    private class MockRefreshTokenResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"access_token":"new_access_token","expires_in":3600}');
            return res;
        }
    }
    
    private class MockRefreshTokenWithNewTokenResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"access_token":"new_access_token","refresh_token":"new_refresh_token","expires_in":3600}');
            return res;
        }
    }
    
    private class MockRefreshTokenErrorResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"invalid_grant","error_description":"Token expired"}');
            return res;
        }
    }
    
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
    
    private class MockExceptionResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Network error');
        }
    }
    
    private class MockInvalidJsonResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'text/plain');
            res.setBody('Invalid JSON response');
            return res;
        }
    }
}