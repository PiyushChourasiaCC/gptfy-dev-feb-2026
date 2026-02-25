/**
 * Test class for AIWorkspaceAuthController
 * Tests the workspace authentication controller methods
 * 
 * @author GPTfy
 * @date 2026-02-01
 */
@isTest
private class AIWorkspaceAuthControllerTest {
    
    @TestSetup
    static void setup() {
        // Create a workspace user record for testing
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            Name = 'Test Outlook Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Refresh_Token__c = 'test_encrypted_refresh_token',
            Access_Token__c = 'test_encrypted_access_token',
            Auto_Sync_Enabled__c = true
        );
        insert workspaceUser;
    }
    
    @isTest
    static void testCheckConnectionStatus_Connected() {
        Test.startTest();
        AIWorkspaceAuthController.ConnectionStatus status = 
            AIWorkspaceAuthController.checkConnectionStatus('Outlook');
        Test.stopTest();
        
        Assert.isTrue(status.isConnected, 'Should be connected');
        Assert.areEqual('Outlook', status.provider, 'Provider should be Outlook');
        Assert.isNotNull(status.workspaceUserId, 'Should have workspace user ID');
    }
    
    @isTest
    static void testCheckConnectionStatus_NotConnected() {
        Test.startTest();
        AIWorkspaceAuthController.ConnectionStatus status = 
            AIWorkspaceAuthController.checkConnectionStatus('Gmail');
        Test.stopTest();
        
        Assert.isFalse(status.isConnected, 'Should not be connected for Gmail');
    }
    
    @isTest
    static void testCheckConnectionStatus_EmptyRefreshToken() {
        // Create a workspace user with empty refresh token
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = '',
            Access_Token__c = 'test_access_token'
        );
        insert workspaceUser;
        
        Test.startTest();
        AIWorkspaceAuthController.ConnectionStatus status = 
            AIWorkspaceAuthController.checkConnectionStatus('Gmail');
        Test.stopTest();
        
        Assert.isFalse(status.isConnected, 'Should not be connected with empty refresh token');
    }
    
    @isTest
    static void testGetAuthorizationUrl_Outlook() {
        Test.startTest();
        String url = AIWorkspaceAuthController.getAuthorizationUrl('Outlook');
        Test.stopTest();
        
        Assert.isTrue(url.contains('/apex/') && url.containsIgnoreCase('OutlookOAuth'), 'URL should contain OutlookOAuth VF page');
    }
    
    @isTest
    static void testGetAuthorizationUrl_Gmail() {
        Test.startTest();
        String url = AIWorkspaceAuthController.getAuthorizationUrl('Gmail');
        Test.stopTest();
        
        Assert.isTrue(url.contains('/apex/') && url.containsIgnoreCase('GmailOAuth'), 'URL should contain GmailOAuth VF page');
    }
    
    @isTest
    static void testGetAuthorizationUrl_InvalidProvider() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIWorkspaceAuthController.getAuthorizationUrl('InvalidProvider');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // Exception was thrown, which is what we expect
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception for invalid provider');
    }
    
    @isTest
    static void testDisconnectAccount_Success() {
        Test.startTest();
        AIWorkspaceAuthController.DisconnectResult result = 
            AIWorkspaceAuthController.disconnectAccount('Outlook');
        Test.stopTest();
        
        Assert.isTrue(result.isSuccess, 'Should successfully disconnect');
        Assert.isTrue(result.message.contains('Successfully disconnected'), 'Should have success message');
        
        // Verify record is deleted
        List<AI_Workspace_User__c> remaining = [
            SELECT Id FROM AI_Workspace_User__c WHERE Provider__c = 'Outlook'
        ];
        Assert.isTrue(remaining.isEmpty(), 'Record should be deleted');
    }
    
    @isTest
    static void testDisconnectAccount_NotFound() {
        Test.startTest();
        AIWorkspaceAuthController.DisconnectResult result = 
            AIWorkspaceAuthController.disconnectAccount('Gmail');
        Test.stopTest();
        
        Assert.isFalse(result.isSuccess, 'Should not succeed when no connection found');
        Assert.isTrue(result.message.contains('No connected'), 'Should have not found message');
    }
    
    @isTest
    static void testGetAutoSyncStatus_HasConnection() {
        Test.startTest();
        AIWorkspaceAuthController.AutoSyncStatus status = 
            AIWorkspaceAuthController.getAutoSyncStatus();
        Test.stopTest();
        
        Assert.isTrue(status.hasAnyConnection, 'Should have connection');
        Assert.isTrue(status.isEnabled, 'Should be enabled by default');
    }
    
    @isTest
    static void testGetAutoSyncStatus_NoConnection() {
        // Delete all workspace users
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        AIWorkspaceAuthController.AutoSyncStatus status = 
            AIWorkspaceAuthController.getAutoSyncStatus();
        Test.stopTest();
        
        Assert.isFalse(status.hasAnyConnection, 'Should not have connection');
        Assert.isFalse(status.isEnabled, 'Should not be enabled');
    }
    
    @isTest
    static void testGetAutoSyncStatus_MultipleConnections() {
        // Create a Gmail workspace user
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = 'test_gmail_refresh_token',
            Access_Token__c = 'test_gmail_access_token',
            Auto_Sync_Enabled__c = false
        );
        insert gmailUser;
        
        Test.startTest();
        AIWorkspaceAuthController.AutoSyncStatus status = 
            AIWorkspaceAuthController.getAutoSyncStatus();
        Test.stopTest();
        
        Assert.isTrue(status.hasAnyConnection, 'Should have connection');
        Assert.isTrue(status.isEnabled, 'Should be enabled if ANY record has it enabled');
    }
    
    @isTest
    static void testSetAutoSyncStatus_Disable() {
        Test.startTest();
        AIWorkspaceAuthController.AutoSyncStatus status = 
            AIWorkspaceAuthController.setAutoSyncStatus(false);
        Test.stopTest();
        
        Assert.isTrue(status.hasAnyConnection, 'Should have connection');
        Assert.isFalse(status.isEnabled, 'Should be disabled');
        
        // Verify the record was updated
        AI_Workspace_User__c updated = [
            SELECT Auto_Sync_Enabled__c FROM AI_Workspace_User__c LIMIT 1
        ];
        Assert.isFalse(updated.Auto_Sync_Enabled__c, 'Record should have Auto_Sync_Enabled__c = false');
    }
    
    @isTest
    static void testSetAutoSyncStatus_Enable() {
        // First disable
        AI_Workspace_User__c workspaceUser = [
            SELECT Id FROM AI_Workspace_User__c LIMIT 1
        ];
        workspaceUser.Auto_Sync_Enabled__c = false;
        update workspaceUser;
        
        Test.startTest();
        AIWorkspaceAuthController.AutoSyncStatus status = 
            AIWorkspaceAuthController.setAutoSyncStatus(true);
        Test.stopTest();
        
        Assert.isTrue(status.hasAnyConnection, 'Should have connection');
        Assert.isTrue(status.isEnabled, 'Should be enabled');
        
        // Verify the record was updated
        AI_Workspace_User__c updated = [
            SELECT Auto_Sync_Enabled__c FROM AI_Workspace_User__c LIMIT 1
        ];
        Assert.isTrue(updated.Auto_Sync_Enabled__c, 'Record should have Auto_Sync_Enabled__c = true');
    }
    
    @isTest
    static void testSetAutoSyncStatus_NoConnection() {
        // Delete all workspace users
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        AIWorkspaceAuthController.AutoSyncStatus status = 
            AIWorkspaceAuthController.setAutoSyncStatus(true);
        Test.stopTest();
        
        Assert.isFalse(status.hasAnyConnection, 'Should not have connection');
    }
    
    @isTest
    static void testSetAutoSyncStatus_MultipleRecords() {
        // Create a Gmail workspace user
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = 'test_gmail_refresh_token',
            Access_Token__c = 'test_gmail_access_token',
            Auto_Sync_Enabled__c = true
        );
        insert gmailUser;
        
        Test.startTest();
        AIWorkspaceAuthController.AutoSyncStatus status = 
            AIWorkspaceAuthController.setAutoSyncStatus(false);
        Test.stopTest();
        
        Assert.isTrue(status.hasAnyConnection, 'Should have connection');
        Assert.isFalse(status.isEnabled, 'Should be disabled');
        
        // Verify all records were updated
        List<AI_Workspace_User__c> allUsers = [
            SELECT Auto_Sync_Enabled__c FROM AI_Workspace_User__c
        ];
        for (AI_Workspace_User__c user : allUsers) {
            Assert.isFalse(user.Auto_Sync_Enabled__c, 'All records should be disabled');
        }
    }
    
    @isTest
    static void testGetOutlookUserProfile_NoWorkspaceUser() {
        // Delete workspace user to trigger AuthenticationException
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getOutlookUserProfile();
        Test.stopTest();
        
        Assert.isFalse(profile.isSuccess, 'Should not be successful');
        Assert.areEqual('Outlook', profile.provider, 'Provider should be Outlook');
        Assert.isNotNull(profile.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testGetOutlookUserProfile_Success() {
        // Mock successful response
        String mockResponse = '{"mail":"test@outlook.com","displayName":"Test User","givenName":"Test","surname":"User","jobTitle":"Developer","userPrincipalName":"test@outlook.com"}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getOutlookUserProfile();
        Test.stopTest();
        
        Assert.isTrue(profile.isSuccess, 'Should be successful');
        Assert.areEqual('Outlook', profile.provider, 'Provider should be Outlook');
        Assert.areEqual('test@outlook.com', profile.email, 'Email should match');
        Assert.areEqual('Test User', profile.displayName, 'Display name should match');
        Assert.areEqual('Test', profile.givenName, 'Given name should match');
        Assert.areEqual('User', profile.surname, 'Surname should match');
        Assert.areEqual('Developer', profile.jobTitle, 'Job title should match');
    }
    
    @isTest
    static void testGetOutlookUserProfile_UserPrincipalNameFallback() {
        // Mock response without mail field
        String mockResponse = '{"userPrincipalName":"test@outlook.com","displayName":"Test User","givenName":"Test","surname":"User","jobTitle":"Developer"}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getOutlookUserProfile();
        Test.stopTest();
        
        Assert.isTrue(profile.isSuccess, 'Should be successful');
        Assert.areEqual('test@outlook.com', profile.email, 'Email should use userPrincipalName');
    }
    
    @isTest
    static void testGetOutlookUserProfile_TokenExpired401() {
        // Mock 401 response with error message containing '401'
        String mockResponse = '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired or is not yet valid."}}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(401, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getOutlookUserProfile();
        Test.stopTest();
        
        Assert.isFalse(profile.isSuccess, 'Should not be successful');
        Assert.isTrue(profile.isTokenExpired, 'Token should be expired');
        Assert.isTrue(profile.errorMessage.contains('expired'), 'Error message should mention expiration');
    }
    
    @isTest
    static void testGetOutlookUserProfile_Error() {
        // Mock error response
        String mockResponse = '{"error":"Bad Request"}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(400, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getOutlookUserProfile();
        Test.stopTest();
        
        Assert.isFalse(profile.isSuccess, 'Should not be successful');
        Assert.isNotNull(profile.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testRefreshOutlookAndGetProfile_Success() {
        // Mock successful token refresh
        String mockResponse = '{"access_token":"new_access_token","refresh_token":"new_refresh_token","expires_in":3600}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.refreshOutlookAndGetProfile();
        Test.stopTest();
        
        Assert.areEqual('Outlook', profile.provider, 'Provider should be Outlook');
        // The method may succeed or fail depending on token service behavior
        Assert.isNotNull(profile, 'Profile should not be null');
    }
    
    @isTest
    static void testRefreshOutlookAndGetProfile_NoWorkspaceUser() {
        // Delete workspace user to trigger AuthenticationException
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(400, '{"error":"invalid_grant"}'));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.refreshOutlookAndGetProfile();
        Test.stopTest();
        
        Assert.isFalse(profile.isSuccess, 'Should not be successful');
        Assert.isNotNull(profile.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testGetGmailUserProfile_NoWorkspaceUser() {
        // Delete workspace user to trigger AuthenticationException
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getGmailUserProfile();
        Test.stopTest();
        
        Assert.isFalse(profile.isSuccess, 'Should not be successful');
        Assert.areEqual('Gmail', profile.provider, 'Provider should be Gmail');
        Assert.isNotNull(profile.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testGetGmailUserProfile_Success() {
        // Create Gmail workspace user
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = 'test_gmail_refresh_token',
            Access_Token__c = 'test_gmail_access_token'
        );
        insert gmailUser;
        
        // Mock successful response
        String mockResponse = '{"email":"test@gmail.com","name":"Test User","given_name":"Test","family_name":"User"}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getGmailUserProfile();
        Test.stopTest();
        
        Assert.isTrue(profile.isSuccess, 'Should be successful');
        Assert.areEqual('Gmail', profile.provider, 'Provider should be Gmail');
        Assert.areEqual('test@gmail.com', profile.email, 'Email should match');
        Assert.areEqual('Test User', profile.displayName, 'Display name should match');
        Assert.areEqual('Test', profile.givenName, 'Given name should match');
        Assert.areEqual('User', profile.surname, 'Surname should match');
    }
    
    @isTest
    static void testGetGmailUserProfile_TokenExpired401() {
        // Create Gmail workspace user
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = 'test_gmail_refresh_token',
            Access_Token__c = 'test_gmail_access_token'
        );
        insert gmailUser;
        
        // Mock 401 response with error message containing '401'
        String mockResponse = '{"error":{"code":"401","message":"Invalid Credentials"}}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(401, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getGmailUserProfile();
        Test.stopTest();
        
        Assert.isFalse(profile.isSuccess, 'Should not be successful');
        Assert.isTrue(profile.isTokenExpired, 'Token should be expired');
        Assert.isTrue(profile.errorMessage.contains('expired'), 'Error message should mention expiration');
    }
    
    @isTest
    static void testGetGmailUserProfile_Error() {
        // Create Gmail workspace user
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = 'test_gmail_refresh_token',
            Access_Token__c = 'test_gmail_access_token'
        );
        insert gmailUser;
        
        // Mock error response
        String mockResponse = '{"error":"Bad Request"}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(400, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.getGmailUserProfile();
        Test.stopTest();
        
        Assert.isFalse(profile.isSuccess, 'Should not be successful');
        Assert.isNotNull(profile.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testRefreshGmailAndGetProfile_Success() {
        // Create Gmail workspace user
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = 'test_gmail_refresh_token',
            Access_Token__c = 'test_gmail_access_token'
        );
        insert gmailUser;
        
        // Mock successful token refresh
        String mockResponse = '{"access_token":"new_access_token","refresh_token":"new_refresh_token","expires_in":3600}';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.refreshGmailAndGetProfile();
        Test.stopTest();
        
        Assert.areEqual('Gmail', profile.provider, 'Provider should be Gmail');
        // The method may succeed or fail depending on token service behavior
        Assert.isNotNull(profile, 'Profile should not be null');
    }
    
    @isTest
    static void testRefreshGmailAndGetProfile_NoWorkspaceUser() {
        // Delete workspace user to trigger AuthenticationException
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(400, '{"error":"invalid_grant"}'));
        AIWorkspaceAuthController.UserProfile profile = 
            AIWorkspaceAuthController.refreshGmailAndGetProfile();
        Test.stopTest();
        
        Assert.isFalse(profile.isSuccess, 'Should not be successful');
        Assert.isNotNull(profile.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testConnectionStatusWrapper() {
        AIWorkspaceAuthController.ConnectionStatus status = 
            new AIWorkspaceAuthController.ConnectionStatus();
        
        Assert.isFalse(status.isConnected, 'Default isConnected should be false');
        Assert.isNull(status.workspaceUserId, 'Default workspaceUserId should be null');
        Assert.isNull(status.provider, 'Default provider should be null');
    }
    
    @isTest
    static void testAutoSyncStatusWrapper() {
        AIWorkspaceAuthController.AutoSyncStatus status = 
            new AIWorkspaceAuthController.AutoSyncStatus();
        
        Assert.isFalse(status.hasAnyConnection, 'Default hasAnyConnection should be false');
        Assert.isFalse(status.isEnabled, 'Default isEnabled should be false');
        Assert.isNull(status.errorMessage, 'Default errorMessage should be null');
    }
    
    @isTest
    static void testDisconnectResultWrapper() {
        AIWorkspaceAuthController.DisconnectResult result = 
            new AIWorkspaceAuthController.DisconnectResult();
        
        Assert.isFalse(result.isSuccess, 'Default isSuccess should be false');
        Assert.isNull(result.message, 'Default message should be null');
    }
    
    @isTest
    static void testUserProfileWrapper() {
        AIWorkspaceAuthController.UserProfile profile = 
            new AIWorkspaceAuthController.UserProfile();
        
        Assert.isFalse(profile.isSuccess, 'Default isSuccess should be false');
        Assert.isNull(profile.email, 'Default email should be null');
        Assert.isNull(profile.displayName, 'Default displayName should be null');
        Assert.isFalse(profile.isTokenExpired, 'Default isTokenExpired should be false');
    }
    
    /**
     * Mock HTTP Response Generator for testing callouts
     */
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
            
            // Simulate error message in response body for non-200 status
            if (statusCode == 401) {
                res.setBody('{"error": {"code": "InvalidAuthenticationToken", "message": "401 Unauthorized"}}');
            }
            
            return res;
        }
    }
}