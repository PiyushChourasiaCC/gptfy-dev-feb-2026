/**
 * @description Test class for AIGmailOAuthController
 * Tests OAuth controller functionality including VF page interactions,
 * token encryption/decryption, and workspace user managementP
 * 
 * @author GPTfy
 * @date 2026-02-18
 */
@isTest
private class AIGmailOAuthControllerTest {
    
    /**
     * @description Setup test data - create Custom Setting record
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
            
            // Check if this is a token request or profile request
            if (req.getEndpoint().contains('userinfo')) {
                // User profile request
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'email' => 'testuser@example.com',
                    'name' => 'Test User',
                    'id' => '123456789'
                }));
            } else {
                // Token exchange request - make access token longer than 50 chars
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'access_token' => 'mock_google_access_token_12345_that_is_definitely_longer_than_fifty_characters',
                    'refresh_token' => '1/mock_google_refresh_token_67890',
                    'expires_in' => 3600,
                    'token_type' => 'Bearer',
                    'scope' => 'openid email profile gmail.readonly'
                }));
            }
            return res;
        }
    }
    
    /**
     * @description Mock class for successful user profile response
     */
    private class SuccessProfileMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'email' => 'testuser@example.com',
                'name' => 'Test User',
                'id' => '123456789'
            }));
            return res;
        }
    }
    
    /**
     * @description Mock class for failed token exchange response
     */
    private class ErrorTokenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'error' => 'invalid_grant',
                'error_description' => 'The authorization code has expired or is invalid.'
            }));
            return res;
        }
    }
    
    /**
     * @description Test constructor with no parameters (initial page load)
     */
    @isTest
    static void testConstructor_InitialLoad() {
        Test.startTest();
        
        // Set up VF page context with no parameters
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        // Create controller
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        // Verify initial state
        Assert.areEqual(true, controller.showConnectButton, 'Connect button should be shown');
        Assert.areEqual(true, controller.showInfo, 'Info should be shown');
        Assert.areEqual(false, controller.isSuccess, 'Success should be false');
        Assert.areEqual(false, controller.hasError, 'Error should be false');
        Assert.isNotNull(controller.authUrl, 'Auth URL should be set');
        Assert.isNotNull(controller.redirectUrl, 'Redirect URL should be set');
    }
    
    /**
     * @description Test constructor with OAuth error parameter
     */
    @isTest
    static void testConstructor_OAuthError_AccessDenied() {
        Test.startTest();
        
        // Set up VF page context with error parameter
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('error', 'access_denied');
        Test.setCurrentPage(pageRef);
        
        // Create controller
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        // Verify error state
        Assert.areEqual(true, controller.hasError, 'Error should be true');
        Assert.areEqual(false, controller.isSuccess, 'Success should be false');
        Assert.areEqual(true, controller.showConnectButton, 'Connect button should be shown');
        Assert.areEqual(false, controller.showInfo, 'Info should be hidden');
        Assert.areEqual('Access denied. You must grant permission to connect your Gmail account.', 
                       controller.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test constructor with OAuth error - invalid_request
     */
    @isTest
    static void testConstructor_OAuthError_InvalidRequest() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('error', 'invalid_request');
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        Assert.areEqual(true, controller.hasError, 'Error should be true');
        Assert.areEqual('Invalid request. Please try again.', controller.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test constructor with OAuth error - unauthorized_client
     */
    @isTest
    static void testConstructor_OAuthError_UnauthorizedClient() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('error', 'unauthorized_client');
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        Assert.areEqual(true, controller.hasError, 'Error should be true');
        Assert.areEqual('Application not authorized. Please contact your administrator.', 
                       controller.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test constructor with OAuth error - custom error description
     */
    @isTest
    static void testConstructor_OAuthError_WithDescription() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('error', 'custom_error');
        pageRef.getParameters().put('error_description', 'Custom error description');
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        Assert.areEqual(true, controller.hasError, 'Error should be true');
        Assert.areEqual('Custom error description', controller.errorMessage, 'Error message should match');
    }
    
    /**
     * @description Test constructor with successful OAuth callback
     */
    @isTest
    static void testConstructor_SuccessfulCallback() {
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        
        Test.startTest();
        
        // Set up VF page context with code parameter
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('code', 'test_auth_code_12345');
        Test.setCurrentPage(pageRef);
        
        // Create controller
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        // Verify success state
        Assert.areEqual(true, controller.isSuccess, 'Success should be true');
        Assert.areEqual(false, controller.hasError, 'Error should be false');
        Assert.areEqual(false, controller.showConnectButton, 'Connect button should be hidden');
        Assert.areEqual(false, controller.showInfo, 'Info should be hidden');
        Assert.isNotNull(controller.accessToken, 'Access token should be set');
        Assert.isNotNull(controller.refreshToken, 'Refresh token should be set');
        Assert.areEqual(3600, controller.expiresIn, 'Expires in should be set');
    }
    
    /**
     * @description Test constructor with failed token exchange
     */
    @isTest
    static void testConstructor_FailedTokenExchange() {
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('code', 'test_auth_code_12345');
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        Assert.areEqual(true, controller.hasError, 'Error should be true');
        Assert.areEqual(false, controller.isSuccess, 'Success should be false');
        Assert.isNotNull(controller.errorMessage, 'Error message should be set');
    }
    
    /**
     * @description Test initiateOAuth method
     */
    @isTest
    static void testInitiateOAuth() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        PageReference result = controller.initiateOAuth();
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'PageReference should not be null');
        Assert.isTrue(result.getUrl().contains('accounts.google.com'), 'URL should contain Google auth endpoint');
    }
    
    /**
     * @description Test saveRefreshTokenToWorkspaceUser - create new record
     */
    @isTest
    static void testSaveRefreshTokenToWorkspaceUser_CreateNew() {
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('code', 'test_auth_code_12345');
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        // Save refresh token
        controller.saveRefreshTokenToWorkspaceUser();
        
        Test.stopTest();
        
        // Verify record was created
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id, User__c, Provider__c, Refresh_Token__c, Auto_Sync_Enabled__c
            FROM AI_Workspace_User__c
            WHERE User__c = :UserInfo.getUserId()
            AND Provider__c = 'Gmail'
        ];
        
        Assert.areEqual(1, workspaceUsers.size(), 'One workspace user should be created');
        Assert.areEqual('Gmail', workspaceUsers[0].Provider__c, 'Provider should be Gmail');
        Assert.areEqual(true, workspaceUsers[0].Auto_Sync_Enabled__c, 'Auto sync should be enabled');
        Assert.isNotNull(workspaceUsers[0].Refresh_Token__c, 'Refresh token should be set');
    }
    
    /**
     * @description Test saveRefreshTokenToWorkspaceUser - update existing record
     */
    @isTest
    static void testSaveRefreshTokenToWorkspaceUser_UpdateExisting() {
        // Create existing workspace user
        AI_Workspace_User__c existingUser = new AI_Workspace_User__c(
            Name = UserInfo.getName() + ' - Gmail',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = 'old_encrypted_token',
            Auto_Sync_Enabled__c = false
        );
        insert existingUser;
        
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('code', 'test_auth_code_12345');
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.saveRefreshTokenToWorkspaceUser();
        
        Test.stopTest();
        
        // Verify record was updated
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id, Refresh_Token__c, Auto_Sync_Enabled__c
            FROM AI_Workspace_User__c
            WHERE User__c = :UserInfo.getUserId()
            AND Provider__c = 'Gmail'
        ];
        
        Assert.areEqual(1, workspaceUsers.size(), 'Should still have one workspace user');
        Assert.areEqual(true, workspaceUsers[0].Auto_Sync_Enabled__c, 'Auto sync should be enabled');
        Assert.areNotEqual('old_encrypted_token', workspaceUsers[0].Refresh_Token__c, 'Token should be updated');
    }
    
    /**
     * @description Test saveRefreshTokenToWorkspaceUser with blank refresh token
     */
    @isTest
    static void testSaveRefreshTokenToWorkspaceUser_BlankToken() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.refreshToken = null;
        
        Boolean exceptionThrown = false;
        try {
            controller.saveRefreshTokenToWorkspaceUser();
            Assert.fail('Should have thrown exception');
        } catch (Exception e) {
            exceptionThrown = true;
            // Just verify an exception was thrown
        }
        
        Assert.isTrue(exceptionThrown, 'Exception should have been thrown');
        Test.stopTest();
    }
    
    /**
     * @description Test testGetProfile method
     */
    @isTest
    static void testTestGetProfile() {
        Test.setMock(HttpCalloutMock.class, new SuccessProfileMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.accessToken = 'test_access_token';
        
        controller.testGetProfile();
        
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'API response should be set');
        Assert.isTrue(controller.apiResponse.contains('testuser@example.com'), 'Response should contain email');
    }
    
    /**
     * @description Test testGetEmails method
     */
    @isTest
    static void testTestGetEmails() {
        Test.setMock(HttpCalloutMock.class, new SuccessProfileMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.accessToken = 'test_access_token';
        
        controller.testGetEmails();
        
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'API response should be set');
    }
    
    /**
     * @description Test testRefreshToken method - success
     */
    @isTest
    static void testTestRefreshToken_Success() {
        // Create workspace user first
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            Name = UserInfo.getName() + ' - Gmail',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = AIGmailOAuthController.encryptRefreshToken('1/old_token'),
            Auto_Sync_Enabled__c = true
        );
        insert workspaceUser;
        
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.refreshToken = '1/test_refresh_token_that_is_definitely_longer_than_fifty_characters_for_substring';
        
        controller.testRefreshToken();
        
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'API response should be set');
        Assert.isTrue(controller.apiResponse.contains('Token refreshed successfully'), 'Response should indicate success');
        Assert.isNotNull(controller.accessToken, 'Access token should be updated');
    }
    
    /**
     * @description Test testRefreshToken method - with new refresh token
     */
    @isTest
    static void testTestRefreshToken_WithNewRefreshToken() {
        // Create workspace user first
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            Name = UserInfo.getName() + ' - Gmail',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = AIGmailOAuthController.encryptRefreshToken('1/old_token'),
            Auto_Sync_Enabled__c = true
        );
        insert workspaceUser;
        
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.refreshToken = '1/test_refresh_token_that_is_definitely_longer_than_fifty_characters_for_substring';
        
        controller.testRefreshToken();
        
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'API response should be set');
    }
    
    /**
     * @description Test testRefreshToken method - error
     */
    @isTest
    static void testTestRefreshToken_Error() {
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.refreshToken = '1/test_refresh_token';
        
        controller.testRefreshToken();
        
        Test.stopTest();
        
        Assert.isNotNull(controller.apiResponse, 'API response should be set');
        Assert.isTrue(controller.apiResponse.contains('Error'), 'Response should indicate error');
    }
    
    /**
     * @description Test reset method
     */
    @isTest
    static void testReset() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.accessToken = 'test_token';
        controller.refreshToken = 'test_refresh';
        controller.errorMessage = 'test error';
        
        PageReference result = controller.reset();
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'PageReference should not be null');
        Assert.isTrue(result.getUrl().containsIgnoreCase('GmailOAuth'), 'Should redirect to GmailOAuth page');
    }
    
    /**
     * @description Test encryptRefreshToken method
     */
    @isTest
    static void testEncryptRefreshToken() {
        Test.startTest();
        
        String plainToken = '1/test_refresh_token_12345';
        String encryptedToken = AIGmailOAuthController.encryptRefreshToken(plainToken);
        
        Test.stopTest();
        
        Assert.isNotNull(encryptedToken, 'Encrypted token should not be null');
        Assert.areNotEqual(plainToken, encryptedToken, 'Encrypted token should be different from plain token');
        Assert.isTrue(encryptedToken.length() > 40, 'Encrypted token should be at least 40 characters');
    }
    
    /**
     * @description Test encryptRefreshToken with user ID parameter
     */
    @isTest
    static void testEncryptRefreshToken_WithUserId() {
        Test.startTest();
        
        String plainToken = '1/test_refresh_token_12345';
        Id userId = UserInfo.getUserId();
        String encryptedToken = AIGmailOAuthController.encryptRefreshToken(plainToken, userId);
        
        Test.stopTest();
        
        Assert.isNotNull(encryptedToken, 'Encrypted token should not be null');
        Assert.areNotEqual(plainToken, encryptedToken, 'Encrypted token should be different from plain token');
    }
    
    /**
     * @description Test encryptRefreshToken with blank token
     */
    @isTest
    static void testEncryptRefreshToken_BlankToken() {
        Test.startTest();
        
        Boolean exceptionThrown = false;
        try {
            AIGmailOAuthController.encryptRefreshToken('');
            Assert.fail('Should have thrown exception');
        } catch (Exception e) {
            exceptionThrown = true;
            // Just verify an exception was thrown
        }
        
        Assert.isTrue(exceptionThrown, 'Exception should have been thrown');
        Test.stopTest();
    }
    
    /**
     * @description Test decryptRefreshToken method
     */
    @isTest
    static void testDecryptRefreshToken() {
        Test.startTest();
        
        String plainToken = '1/test_refresh_token_12345';
        String encryptedToken = AIGmailOAuthController.encryptRefreshToken(plainToken);
        String decryptedToken = AIGmailOAuthController.decryptRefreshToken(encryptedToken);
        
        Test.stopTest();
        
        Assert.areEqual(plainToken, decryptedToken, 'Decrypted token should match original');
    }
    
    /**
     * @description Test decryptRefreshToken with user ID parameter
     */
    @isTest
    static void testDecryptRefreshToken_WithUserId() {
        Test.startTest();
        
        String plainToken = '1/test_refresh_token_12345';
        Id userId = UserInfo.getUserId();
        String encryptedToken = AIGmailOAuthController.encryptRefreshToken(plainToken, userId);
        String decryptedToken = AIGmailOAuthController.decryptRefreshToken(encryptedToken, userId);
        
        Test.stopTest();
        
        Assert.areEqual(plainToken, decryptedToken, 'Decrypted token should match original');
    }
    
    /**
     * @description Test decryptRefreshToken with blank token
     */
    @isTest
    static void testDecryptRefreshToken_BlankToken() {
        Test.startTest();
        
        String result = AIGmailOAuthController.decryptRefreshToken('');
        
        Test.stopTest();
        
        Assert.isNull(result, 'Result should be null for blank token');
    }
    
    /**
     * @description Test decryptRefreshToken with null token
     */
    @isTest
    static void testDecryptRefreshToken_NullToken() {
        Test.startTest();
        
        String result = AIGmailOAuthController.decryptRefreshToken(null);
        
        Test.stopTest();
        
        Assert.isNull(result, 'Result should be null for null token');
    }
    
    /**
     * @description Test decryptRefreshToken with legacy unencrypted token (starts with 1/)
     */
    @isTest
    static void testDecryptRefreshToken_LegacyToken() {
        Test.startTest();
        
        String legacyToken = '1/legacy_unencrypted_token_12345';
        String result = AIGmailOAuthController.decryptRefreshToken(legacyToken);
        
        Test.stopTest();
        
        Assert.areEqual(legacyToken, result, 'Legacy token should be returned as-is');
    }
    
    /**
     * @description Test decryptRefreshToken with invalid encrypted token
     */
    @isTest
    static void testDecryptRefreshToken_InvalidEncryptedToken() {
        Test.startTest();
        
        String invalidToken = 'invalid_base64_encrypted_token_that_cannot_be_decrypted';
        String result = AIGmailOAuthController.decryptRefreshToken(invalidToken);
        
        Test.stopTest();
        
        // Should return the token as-is when decryption fails
        Assert.areEqual(invalidToken, result, 'Invalid token should be returned as-is');
    }
    
    /**
     * @description Test encryption/decryption with different users
     */
    @isTest
    static void testEncryptDecrypt_DifferentUsers() {
        // Create a test user
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + System.currentTimeMillis() + '@example.com'
        );
        insert testUser;
        
        Test.startTest();
        
        String plainToken = '1/test_refresh_token_12345';
        
        // Encrypt with current user
        String encryptedToken1 = AIGmailOAuthController.encryptRefreshToken(plainToken, UserInfo.getUserId());
        
        // Encrypt with test user
        String encryptedToken2 = AIGmailOAuthController.encryptRefreshToken(plainToken, testUser.Id);
        
        // Decrypt with correct users
        String decryptedToken1 = AIGmailOAuthController.decryptRefreshToken(encryptedToken1, UserInfo.getUserId());
        String decryptedToken2 = AIGmailOAuthController.decryptRefreshToken(encryptedToken2, testUser.Id);
        
        Test.stopTest();
        
        // Tokens encrypted with different users should be different
        Assert.areNotEqual(encryptedToken1, encryptedToken2, 'Encrypted tokens should be different for different users');
        
        // But both should decrypt correctly with their respective user IDs
        Assert.areEqual(plainToken, decryptedToken1, 'Token 1 should decrypt correctly');
        Assert.areEqual(plainToken, decryptedToken2, 'Token 2 should decrypt correctly');
    }
    
    /**
     * @description Test getUserProfile private method through constructor
     */
    @isTest
    static void testGetUserProfile_ThroughConstructor() {
        // Use the SuccessTokenMock which handles both token and profile requests
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('code', 'test_auth_code_12345');
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        Assert.isNotNull(controller.userEmail, 'User email should be set');
        Assert.areEqual('testuser@example.com', controller.userEmail, 'Email should match mock response');
    }
    
    /**
     * @description Test prettyPrintJson with valid JSON
     */
    @isTest
    static void testPrettyPrintJson_ValidJson() {
        Test.setMock(HttpCalloutMock.class, new SuccessProfileMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.accessToken = 'test_access_token';
        
        controller.testGetProfile();
        
        Test.stopTest();
        
        // The response should be pretty-printed JSON
        Assert.isNotNull(controller.apiResponse, 'API response should be set');
        Assert.isTrue(controller.apiResponse.contains('\n') || controller.apiResponse.contains('  '), 
                     'Response should be formatted');
    }
    
    /**
     * @description Test constructor exception handling
     */
    @isTest
    static void testConstructor_ExceptionHandling() {
        // Mock that throws an exception
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock());
        
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        pageRef.getParameters().put('code', 'test_auth_code');
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        
        Test.stopTest();
        
        Assert.areEqual(true, controller.hasError, 'Error should be true');
        Assert.isNotNull(controller.errorMessage, 'Error message should be set');
    }
    
    /**
     * @description Test testGetProfile with blank access token
     */
    @isTest
    static void testTestGetProfile_BlankToken() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.accessToken = null;
        
        controller.testGetProfile();
        
        Test.stopTest();
        
        // Should not throw exception, just not set apiResponse
        Assert.isNull(controller.apiResponse, 'API response should be null');
    }
    
    /**
     * @description Test testGetEmails with blank access token
     */
    @isTest
    static void testTestGetEmails_BlankToken() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.accessToken = null;
        
        controller.testGetEmails();
        
        Test.stopTest();
        
        Assert.isNull(controller.apiResponse, 'API response should be null');
    }
    
    /**
     * @description Test testRefreshToken with blank refresh token
     */
    @isTest
    static void testTestRefreshToken_BlankToken() {
        Test.startTest();
        
        PageReference pageRef = Page.GmailOAuth;
        Test.setCurrentPage(pageRef);
        
        AIGmailOAuthController controller = new AIGmailOAuthController();
        controller.refreshToken = null;
        
        controller.testRefreshToken();
        
        Test.stopTest();
        
        Assert.isNull(controller.apiResponse, 'API response should be null');
    }
}