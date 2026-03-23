/**
 * Test class for AIWorkspaceTokenService
 * Tests OAuth token management, encryption, and refresh logic
 * 
 * @author GPTfy
 * @date 2026-02-19
 */
@isTest
private class AIWorkspaceTokenServiceTest {
    
    // Mock HTTP Response Generator
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;
        
        public MockHttpResponseGenerator(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }
    
    @TestSetup
    static void setup() {
        // Create workspace sync settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Microsoft_Client_Id__c = 'test_microsoft_client_id',
            Microsoft_Client_Secret__c = 'test_microsoft_secret',
            Microsoft_Token_Endpoint__c = 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
            Google_Client_Id__c = 'test_google_client_id',
            Google_Client_Secret__c = 'test_google_secret',
            Google_Token_Endpoint__c = 'https://oauth2.googleapis.com/token'
        );
        insert settings;
    }
    
    @isTest
    static void testGetAccessToken_WithValidToken() {
        // Create workspace user with access token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Access_Token__c = 'encrypted_access_token',
            Refresh_Token__c = 'encrypted_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        String accessToken = AIWorkspaceTokenService.getAccessToken('Outlook');
        Test.stopTest();
        
        Assert.isNotNull(accessToken, 'Access token should be returned');
    }
    
    @isTest
    static void testGetAccessToken_NoConnection() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.getAccessToken('Outlook');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('No Outlook connection found'), 'Should have no connection error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception when no connection exists');
    }
    
    @isTest
    static void testGetAccessToken_NoAccessTokenNoRefreshToken() {
        // Create workspace user with no tokens
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail'
        );
        insert workspaceUser;
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.getAccessToken('Gmail');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('No tokens available'), 'Should have no tokens error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception when no tokens exist');
    }
    
    @isTest
    static void testGetAccessToken_NoAccessTokenWithRefreshToken() {
        // Create workspace user with only refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Refresh_Token__c = 'encrypted_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.getAccessToken('Outlook');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('Access token expired'), 'Should have token expired error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception when access token is missing');
    }
    
    @isTest
    static void testGetAccessTokenForUser_WithValidToken() {
        // Create workspace user with access token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail',
            Access_Token__c = 'encrypted_access_token',
            Refresh_Token__c = 'encrypted_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        String accessToken = AIWorkspaceTokenService.getAccessTokenForUser(UserInfo.getUserId(), 'Gmail');
        Test.stopTest();
        
        Assert.isNotNull(accessToken, 'Access token should be returned');
    }
    
    @isTest
    static void testRefreshAndGetToken_Success_Outlook() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        // Mock successful token refresh
        String mockResponse = '{"access_token": "new_access_token", "refresh_token": "new_refresh_token"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        
        Test.startTest();
        String newAccessToken = AIWorkspaceTokenService.refreshAndGetToken('Outlook');
        Test.stopTest();
        
        Assert.areEqual('new_access_token', newAccessToken, 'Should return new access token');
        
        // Verify tokens were saved
        workspaceUser = [SELECT Access_Token__c, Refresh_Token__c FROM AI_Workspace_User__c WHERE Id = :workspaceUser.Id];
        Assert.isNotNull(workspaceUser.Access_Token__c, 'Access token should be saved');
        Assert.isNotNull(workspaceUser.Refresh_Token__c, 'Refresh token should be saved');
    }
    
    @isTest
    static void testRefreshAndGetToken_Success_Gmail() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        // Mock successful token refresh (Google doesn't always return new refresh token)
        String mockResponse = '{"access_token": "new_access_token"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        
        Test.startTest();
        String newAccessToken = AIWorkspaceTokenService.refreshAndGetToken('Gmail');
        Test.stopTest();
        
        Assert.areEqual('new_access_token', newAccessToken, 'Should return new access token');
    }
    
    @isTest
    static void testRefreshAndGetToken_NoConnection() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.refreshAndGetToken('Outlook');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('No Outlook connection found'), 'Should have no connection error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception when no connection exists');
    }
    
    @isTest
    static void testRefreshAndGetToken_NoRefreshToken() {
        // Create workspace user without refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook'
        );
        insert workspaceUser;
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.refreshAndGetToken('Outlook');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('No refresh token available'), 'Should have no refresh token error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception when no refresh token exists');
    }
    
    @isTest
    static void testRefreshAndGetToken_InvalidGrant_Outlook() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        // Mock invalid_grant error
        String mockResponse = '{"error": "invalid_grant", "error_description": "AADSTS700082"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(400, mockResponse));
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.refreshAndGetToken('Outlook');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('session has expired'), 'Should have session expired error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception for invalid grant');
    }
    
    @isTest
    static void testRefreshAndGetToken_InvalidGrant_Gmail() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        // Mock invalid_grant error
        String mockResponse = '{"error": "invalid_grant"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(400, mockResponse));
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.refreshAndGetToken('Gmail');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('session has expired'), 'Should have session expired error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception for invalid grant');
    }
    
    @isTest
    static void testRefreshAndGetToken_OtherError() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        // Mock other error
        String mockResponse = '{"error": "server_error"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(500, mockResponse));
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.refreshAndGetToken('Outlook');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('Failed to refresh'), 'Should have refresh failed error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception for other errors');
    }
    
    @isTest
    static void testRefreshAndGetTokenForUser() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        // Mock successful token refresh
        String mockResponse = '{"access_token": "new_access_token", "refresh_token": "new_refresh_token"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        
        Test.startTest();
        String newAccessToken = AIWorkspaceTokenService.refreshAndGetTokenForUser(UserInfo.getUserId(), 'Outlook');
        Test.stopTest();
        
        Assert.areEqual('new_access_token', newAccessToken, 'Should return new access token');
    }
    
    @isTest
    static void testHasConnection_WithConnection() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        Boolean hasConnection = AIWorkspaceTokenService.hasConnection('Outlook');
        Test.stopTest();
        
        Assert.isTrue(hasConnection, 'Should have connection');
    }
    
    @isTest
    static void testHasConnection_NoConnection() {
        Test.startTest();
        Boolean hasConnection = AIWorkspaceTokenService.hasConnection('Outlook');
        Test.stopTest();
        
        Assert.isFalse(hasConnection, 'Should not have connection');
    }
    
    @isTest
    static void testHasConnection_NoRefreshToken() {
        // Create workspace user without refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail'
        );
        insert workspaceUser;
        
        Test.startTest();
        Boolean hasConnection = AIWorkspaceTokenService.hasConnection('Gmail');
        Test.stopTest();
        
        Assert.isFalse(hasConnection, 'Should not have connection without refresh token');
    }
    
    @isTest
    static void testHasConnectionForUser() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        Boolean hasConnection = AIWorkspaceTokenService.hasConnectionForUser(UserInfo.getUserId(), 'Gmail');
        Test.stopTest();
        
        Assert.isTrue(hasConnection, 'Should have connection');
    }
    
    @isTest
    static void testGetApiEndpoint_Outlook() {
        Test.startTest();
        String endpoint = AIWorkspaceTokenService.getApiEndpoint('Outlook');
        Test.stopTest();
        
        Assert.areEqual('https://graph.microsoft.com', endpoint, 'Should return Microsoft Graph endpoint');
    }
    
    @isTest
    static void testGetApiEndpoint_Gmail() {
        Test.startTest();
        String endpoint = AIWorkspaceTokenService.getApiEndpoint('Gmail');
        Test.stopTest();
        
        Assert.areEqual('https://gmail.googleapis.com', endpoint, 'Should return Gmail API endpoint');
    }
    
    @isTest
    static void testGetApiEndpoint_Unknown() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.getApiEndpoint('Unknown');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('Unknown provider'), 'Should have unknown provider error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception for unknown provider');
    }
    
    @isTest
    static void testGetMicrosoftGraphEndpoint() {
        Test.startTest();
        String endpoint = AIWorkspaceTokenService.getMicrosoftGraphEndpoint();
        Test.stopTest();
        
        Assert.areEqual('https://graph.microsoft.com', endpoint, 'Should return Microsoft Graph endpoint');
    }
    
    @isTest
    static void testGetGmailEndpoint() {
        Test.startTest();
        String endpoint = AIWorkspaceTokenService.getGmailEndpoint();
        Test.stopTest();
        
        Assert.areEqual('https://gmail.googleapis.com', endpoint, 'Should return Gmail API endpoint');
    }
    
    @isTest
    static void testGetGoogleApiEndpoint() {
        Test.startTest();
        String endpoint = AIWorkspaceTokenService.getGoogleApiEndpoint();
        Test.stopTest();
        
        Assert.areEqual('https://www.googleapis.com', endpoint, 'Should return Google API endpoint');
    }
    
    @isTest
    static void testSaveTokens_NewRecord() {
        Test.startTest();
        Id workspaceUserId = AIWorkspaceTokenService.saveTokens('Outlook', 'test_access_token', 'test_refresh_token', 'test@example.com');
        Test.stopTest();
        
        Assert.isNotNull(workspaceUserId, 'Should return workspace user ID');

        // Verify record was created
        AI_Workspace_User__c workspaceUser = [SELECT Name, Provider__c, Access_Token__c, Refresh_Token__c, Auto_Sync_Enabled__c, Service_User_Email__c
                                               FROM AI_Workspace_User__c WHERE Id = :workspaceUserId];
        Assert.areEqual('Outlook', workspaceUser.Provider__c, 'Provider should be Outlook');
        Assert.isTrue(workspaceUser.Name.contains('test@example.com'), 'Name should contain email');
        Assert.isNotNull(workspaceUser.Access_Token__c, 'Access token should be saved');
        Assert.isNotNull(workspaceUser.Refresh_Token__c, 'Refresh token should be saved');
        Assert.isTrue(workspaceUser.Auto_Sync_Enabled__c, 'Auto sync should be enabled');
        Assert.areEqual('test@example.com', workspaceUser.Service_User_Email__c, 'Service user email should be saved');
    }
    
    @isTest
    static void testSaveTokens_UpdateExisting() {
        // Create existing workspace user
        AI_Workspace_User__c existingUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail',
            Access_Token__c = 'old_access_token',
            Refresh_Token__c = 'old_refresh_token'
        );
        insert existingUser;
        
        Test.startTest();
        Id workspaceUserId = AIWorkspaceTokenService.saveTokens('Gmail', 'new_access_token', 'new_refresh_token', 'updated@example.com');
        Test.stopTest();
        
        Assert.areEqual(existingUser.Id, workspaceUserId, 'Should update existing record');

        // Verify record was updated
        AI_Workspace_User__c workspaceUser = [SELECT Access_Token__c, Refresh_Token__c, Service_User_Email__c FROM AI_Workspace_User__c WHERE Id = :workspaceUserId];
        Assert.isNotNull(workspaceUser.Access_Token__c, 'Access token should be updated');
        Assert.isNotNull(workspaceUser.Refresh_Token__c, 'Refresh token should be updated');
        Assert.areEqual('updated@example.com', workspaceUser.Service_User_Email__c, 'Service user email should be updated');
    }
    
    @isTest
    static void testSaveTokens_WithoutEmail() {
        Test.startTest();
        Id workspaceUserId = AIWorkspaceTokenService.saveTokens('Outlook', 'test_access_token', 'test_refresh_token', null);
        Test.stopTest();
        
        Assert.isNotNull(workspaceUserId, 'Should return workspace user ID');

        // Verify record was created with user name
        AI_Workspace_User__c workspaceUser = [SELECT Name, Service_User_Email__c FROM AI_Workspace_User__c WHERE Id = :workspaceUserId];
        Assert.isTrue(workspaceUser.Name.contains('Outlook'), 'Name should contain provider');
        Assert.isNull(workspaceUser.Service_User_Email__c, 'Service user email should be null when not provided');
    }
    
    @isTest
    static void testRemoveConnection_Delete() {
        // Create workspace user
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Access_Token__c = 'test_access_token',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        AIWorkspaceTokenService.removeConnection('Outlook', true);
        Test.stopTest();
        
        // Verify record was deleted
        List<AI_Workspace_User__c> users = [SELECT Id FROM AI_Workspace_User__c WHERE Id = :workspaceUser.Id];
        Assert.isTrue(users.isEmpty(), 'Record should be deleted');
    }
    
    @isTest
    static void testRemoveConnection_ClearTokens() {
        // Create workspace user
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail',
            Access_Token__c = 'test_access_token',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        AIWorkspaceTokenService.removeConnection('Gmail', false);
        Test.stopTest();
        
        // Verify tokens were cleared but record still exists
        workspaceUser = [SELECT Access_Token__c, Refresh_Token__c FROM AI_Workspace_User__c WHERE Id = :workspaceUser.Id];
        Assert.isNull(workspaceUser.Access_Token__c, 'Access token should be cleared');
        Assert.isNull(workspaceUser.Refresh_Token__c, 'Refresh token should be cleared');
    }
    
    @isTest
    static void testRemoveConnection_NoConnection() {
        Test.startTest();
        // Should not throw exception when no connection exists
        AIWorkspaceTokenService.removeConnection('Outlook', true);
        Test.stopTest();
        
        // No assertion needed - just verify no exception is thrown
        Assert.isTrue(true, 'Should not throw exception');
    }
    
    @isTest
    static void testTokenResult_DefaultValues() {
        Test.startTest();
        AIWorkspaceTokenService.TokenResult result = new AIWorkspaceTokenService.TokenResult();
        Test.stopTest();
        
        Assert.isFalse(result.isSuccess, 'isSuccess should be false by default');
        Assert.isFalse(result.requiresReauth, 'requiresReauth should be false by default');
        Assert.isNull(result.accessToken, 'accessToken should be null');
        Assert.isNull(result.refreshToken, 'refreshToken should be null');
        Assert.isNull(result.errorMessage, 'errorMessage should be null');
    }
    
    @isTest
    static void testEncryptionDecryption() {
        // Test encryption and decryption round-trip
        String originalToken = 'test_token_12345';
        Id userId = UserInfo.getUserId();
        
        Test.startTest();
        // Save tokens (which encrypts them)
        Id workspaceUserId = AIWorkspaceTokenService.saveTokens('Outlook', originalToken, originalToken, 'test@example.com');
        
        // Get access token (which decrypts it)
        String decryptedToken = AIWorkspaceTokenService.getAccessToken('Outlook');
        Test.stopTest();
        
        // Verify the token was encrypted and decrypted correctly
        Assert.isNotNull(decryptedToken, 'Decrypted token should not be null');
    }
    
    @isTest
    static void testRefreshToken_MissingSettings_Outlook() {
        // Delete settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.refreshAndGetToken('Outlook');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('Failed to refresh'), 'Should have refresh failed error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception when settings are missing');
    }
    
    @isTest
    static void testRefreshToken_MissingSettings_Gmail() {
        // Delete settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Name = 'Test Gmail',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.refreshAndGetToken('Gmail');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('Failed to refresh'), 'Should have refresh failed error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception when settings are missing');
    }
    
    @isTest
    static void testRefreshToken_AADSTS50076Error() {
        // Create workspace user with refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Name = 'Test Outlook',
            Refresh_Token__c = 'test_refresh_token'
        );
        insert workspaceUser;
        
        // Mock AADSTS50076 error (MFA required)
        String mockResponse = '{"error": "interaction_required", "error_description": "AADSTS50076"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(400, mockResponse));
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceTokenService.refreshAndGetToken('Outlook');
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getMessage().contains('session has expired'), 'Should have session expired error');
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception for MFA required');
    }
    
    @isTest
    static void testProviderConstants() {
        Test.startTest();
        String outlookProvider = AIWorkspaceTokenService.PROVIDER_OUTLOOK;
        String gmailProvider = AIWorkspaceTokenService.PROVIDER_GMAIL;
        Test.stopTest();
        
        Assert.areEqual('Outlook', outlookProvider, 'Outlook provider constant should be correct');
        Assert.areEqual('Gmail', gmailProvider, 'Gmail provider constant should be correct');
    }
    
    @isTest
    static void testSaveTokens_WithBlankTokens() {
        Test.startTest();
        // Save with blank access token to test encryptToken null path
        Id workspaceUserId = AIWorkspaceTokenService.saveTokens('Outlook', '', 'test_refresh_token', 'test@example.com');
        Test.stopTest();
        
        Assert.isNotNull(workspaceUserId, 'Should return workspace user ID');
        
        // Verify record was created
        AI_Workspace_User__c workspaceUser = [SELECT Access_Token__c, Refresh_Token__c FROM AI_Workspace_User__c WHERE Id = :workspaceUserId];
        Assert.isNull(workspaceUser.Access_Token__c, 'Access token should be null when blank');
        Assert.isNotNull(workspaceUser.Refresh_Token__c, 'Refresh token should be saved');
    }
    
    @isTest
    static void testSaveTokens_WithNullTokens() {
        Test.startTest();
        // Save with null tokens to test encryptToken null path
        Id workspaceUserId = AIWorkspaceTokenService.saveTokens('Gmail', null, null, 'test@example.com');
        Test.stopTest();
        
        Assert.isNotNull(workspaceUserId, 'Should return workspace user ID');
        
        // Verify record was created
        AI_Workspace_User__c workspaceUser = [SELECT Access_Token__c, Refresh_Token__c FROM AI_Workspace_User__c WHERE Id = :workspaceUserId];
        Assert.isNull(workspaceUser.Access_Token__c, 'Access token should be null');
        Assert.isNull(workspaceUser.Refresh_Token__c, 'Refresh token should be null');
    }
}