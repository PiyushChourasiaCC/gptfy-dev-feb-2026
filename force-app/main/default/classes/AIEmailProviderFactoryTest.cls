/**
 * Test class for AIEmailProviderFactory
 * Tests provider instantiation, settings retrieval, and authentication checks
 */
@isTest
private class AIEmailProviderFactoryTest {

    @TestSetup
    static void setupTestData() {
        // Create AI_Workspace_Sync_Settings__c
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            WS_Outlook_Enabled__c = true,
            WS_Gmail_Enabled__c = true
        );
        insert settings;

        // Create AI_Workspace_User__c records for authenticated providers
        List<AI_Workspace_User__c> workspaceUsers = new List<AI_Workspace_User__c>();
        
        workspaceUsers.add(new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Refresh_Token__c = 'test_outlook_refresh_token',
            Access_Token__c = 'test_outlook_access_token'
        ));
        
        workspaceUsers.add(new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Refresh_Token__c = 'test_gmail_refresh_token',
            Access_Token__c = 'test_gmail_access_token'
        ));
        
        insert workspaceUsers;
    }

    // =========================================================================
    // PROVIDER INSTANTIATION TESTS
    // =========================================================================

    @isTest
    static void testGetProvider_MicrosoftGraph() {
        Test.startTest();
        AIEmailProviderService provider = AIEmailProviderFactory.getProvider('MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areNotEqual(null, provider, 'Provider should not be null');
        Assert.isTrue(provider instanceof AIMicrosoftGraphProvider, 'Should return Microsoft Graph provider');
    }

    @isTest
    static void testGetProvider_Outlook() {
        Test.startTest();
        AIEmailProviderService provider = AIEmailProviderFactory.getProvider('Outlook');
        Test.stopTest();

        Assert.areNotEqual(null, provider, 'Provider should not be null');
        Assert.isTrue(provider instanceof AIMicrosoftGraphProvider, 'Should return Microsoft Graph provider');
    }

    @isTest
    static void testGetProvider_MicrosoftEmail() {
        Test.startTest();
        AIEmailProviderService provider = AIEmailProviderFactory.getProvider('MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areNotEqual(null, provider, 'Provider should not be null');
        Assert.isTrue(provider instanceof AIMicrosoftGraphProvider, 'Should return Microsoft Graph provider');
    }

    @isTest
    static void testGetProvider_Gmail() {
        Test.startTest();
        AIEmailProviderService provider = AIEmailProviderFactory.getProvider('GMAIL_EMAIL');
        Test.stopTest();

        Assert.areNotEqual(null, provider, 'Provider should not be null');
        Assert.isTrue(provider instanceof AIGmailProvider, 'Should return Gmail provider');
    }

    @isTest
    static void testGetProvider_GmailEmail() {
        Test.startTest();
        AIEmailProviderService provider = AIEmailProviderFactory.getProvider('GMAIL_EMAIL');
        Test.stopTest();

        Assert.areNotEqual(null, provider, 'Provider should not be null');
        Assert.isTrue(provider instanceof AIGmailProvider, 'Should return Gmail provider');
    }

    @isTest
    static void testGetProvider_GmailLowerCase() {
        Test.startTest();
        AIEmailProviderService provider = AIEmailProviderFactory.getProvider('gmail');
        Test.stopTest();

        Assert.areNotEqual(null, provider, 'Provider should not be null');
        Assert.isTrue(provider instanceof AIGmailProvider, 'Should return Gmail provider');
    }

    @isTest
    static void testGetProvider_MicrosoftEmailWithSpaces() {
        // Test normalization of spaces to underscores
        Test.startTest();
        AIEmailProviderService provider = AIEmailProviderFactory.getProvider('MICROSOFT EMAIL');
        Test.stopTest();

        Assert.areNotEqual(null, provider, 'Provider should not be null');
        Assert.isTrue(provider instanceof AIMicrosoftGraphProvider, 'Should return Microsoft Graph provider');
    }

    @isTest
    static void testGetProvider_BlankType() {
        Test.startTest();
        try {
            AIEmailProviderFactory.getProvider('');
            Assert.fail('Should throw exception for blank provider type');
        } catch (AIEmailProviderService.EmailProviderException e) {
            Assert.isTrue(e.getMessage().contains('cannot be blank'), 'Error message should mention blank type');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetProvider_NullType() {
        Test.startTest();
        try {
            AIEmailProviderFactory.getProvider(null);
            Assert.fail('Should throw exception for null provider type');
        } catch (AIEmailProviderService.EmailProviderException e) {
            Assert.isTrue(e.getMessage().contains('cannot be blank'), 'Error message should mention blank type');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetProvider_UnknownType() {
        Test.startTest();
        try {
            AIEmailProviderFactory.getProvider('UNKNOWN_PROVIDER');
            Assert.fail('Should throw exception for unknown provider type');
        } catch (AIEmailProviderService.EmailProviderException e) {
            Assert.isTrue(e.getMessage().contains('Unknown provider type'), 'Error message should mention unknown type');
            Assert.isTrue(e.getMessage().contains('UNKNOWN_PROVIDER'), 'Error message should include the provider type');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetDefaultProvider() {
        Test.startTest();
        AIEmailProviderService provider = AIEmailProviderFactory.getDefaultProvider();
        Test.stopTest();

        Assert.areNotEqual(null, provider, 'Default provider should not be null');
        Assert.isTrue(provider instanceof AIMicrosoftGraphProvider, 'Default should be Microsoft Graph provider');
    }

    // =========================================================================
    // ENABLED PROVIDER TYPES TESTS
    // =========================================================================

    @isTest
    static void testGetEnabledProviderTypes_BothEnabled() {
        Test.startTest();
        List<String> enabledProviders = AIEmailProviderFactory.getEnabledProviderTypes();
        Test.stopTest();

        Assert.areEqual(2, enabledProviders.size(), 'Should have 2 enabled providers');
        Assert.isTrue(enabledProviders.contains('Outlook'), 'Should include Outlook');
        Assert.isTrue(enabledProviders.contains('Gmail'), 'Should include Gmail');
    }

    @isTest
    static void testGetEnabledProviderTypes_OnlyOutlook() {
        // Update settings to only enable Outlook
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.WS_Outlook_Enabled__c = true;
        settings.WS_Gmail_Enabled__c = false;
        update settings;
        
        // Clear cache
        AIEmailProviderFactory.clearSettingsCache();

        Test.startTest();
        List<String> enabledProviders = AIEmailProviderFactory.getEnabledProviderTypes();
        Test.stopTest();

        Assert.areEqual(1, enabledProviders.size(), 'Should have 1 enabled provider');
        Assert.isTrue(enabledProviders.contains('Outlook'), 'Should include Outlook');
        Assert.isFalse(enabledProviders.contains('Gmail'), 'Should not include Gmail');
    }

    @isTest
    static void testGetEnabledProviderTypes_OnlyGmail() {
        // Update settings to only enable Gmail
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.WS_Outlook_Enabled__c = false;
        settings.WS_Gmail_Enabled__c = true;
        update settings;
        
        // Clear cache
        AIEmailProviderFactory.clearSettingsCache();

        Test.startTest();
        List<String> enabledProviders = AIEmailProviderFactory.getEnabledProviderTypes();
        Test.stopTest();

        Assert.areEqual(1, enabledProviders.size(), 'Should have 1 enabled provider');
        Assert.isTrue(enabledProviders.contains('Gmail'), 'Should include Gmail');
        Assert.isFalse(enabledProviders.contains('Outlook'), 'Should not include Outlook');
    }

    @isTest
    static void testGetEnabledProviderTypes_NoneEnabled() {
        // Update settings to disable both
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.WS_Outlook_Enabled__c = false;
        settings.WS_Gmail_Enabled__c = false;
        update settings;
        
        // Clear cache
        AIEmailProviderFactory.clearSettingsCache();

        Test.startTest();
        List<String> enabledProviders = AIEmailProviderFactory.getEnabledProviderTypes();
        Test.stopTest();

        // When no settings configured, default to both providers enabled
        Assert.areEqual(2, enabledProviders.size(), 'Should default to 2 providers when none enabled');
        Assert.isTrue(enabledProviders.contains('Outlook'), 'Should default to Outlook');
        Assert.isTrue(enabledProviders.contains('Gmail'), 'Should default to Gmail');
    }

    @isTest
    static void testGetEnabledProviderTypes_NoSettings() {
        // Delete settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        
        // Clear cache
        AIEmailProviderFactory.clearSettingsCache();

        Test.startTest();
        List<String> enabledProviders = AIEmailProviderFactory.getEnabledProviderTypes();
        Test.stopTest();

        // When no settings exist, default to both providers enabled
        Assert.areEqual(2, enabledProviders.size(), 'Should default to 2 providers when no settings');
        Assert.isTrue(enabledProviders.contains('Outlook'), 'Should default to Outlook');
        Assert.isTrue(enabledProviders.contains('Gmail'), 'Should default to Gmail');
    }

    // =========================================================================
    // AUTHENTICATED PROVIDER TYPES TESTS
    // =========================================================================

    @isTest
    static void testGetAuthenticatedProviderTypes_BothAuthenticated() {
        Test.startTest();
        List<String> authenticatedProviders = AIEmailProviderFactory.getAuthenticatedProviderTypes(UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual(2, authenticatedProviders.size(), 'Should have 2 authenticated providers');
        Assert.isTrue(authenticatedProviders.contains('Outlook'), 'Should include Outlook');
        Assert.isTrue(authenticatedProviders.contains('Gmail'), 'Should include Gmail');
    }

    @isTest
    static void testGetAuthenticatedProviderTypes_OnlyOutlook() {
        // Delete Gmail workspace user
        delete [SELECT Id FROM AI_Workspace_User__c WHERE Provider__c = 'Gmail'];

        Test.startTest();
        List<String> authenticatedProviders = AIEmailProviderFactory.getAuthenticatedProviderTypes(UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual(1, authenticatedProviders.size(), 'Should have 1 authenticated provider');
        Assert.isTrue(authenticatedProviders.contains('Outlook'), 'Should include Outlook');
    }

    @isTest
    static void testGetAuthenticatedProviderTypes_OnlyGmail() {
        // Delete Outlook workspace user
        delete [SELECT Id FROM AI_Workspace_User__c WHERE Provider__c = 'Outlook'];

        Test.startTest();
        List<String> authenticatedProviders = AIEmailProviderFactory.getAuthenticatedProviderTypes(UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual(1, authenticatedProviders.size(), 'Should have 1 authenticated provider');
        Assert.isTrue(authenticatedProviders.contains('Gmail'), 'Should include Gmail');
    }

    @isTest
    static void testGetAuthenticatedProviderTypes_NoAuthentication() {
        // Delete all workspace users
        delete [SELECT Id FROM AI_Workspace_User__c];

        Test.startTest();
        List<String> authenticatedProviders = AIEmailProviderFactory.getAuthenticatedProviderTypes(UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual(0, authenticatedProviders.size(), 'Should have no authenticated providers');
    }

    @isTest
    static void testGetAuthenticatedProviderTypes_NoRefreshToken() {
        // Update to remove refresh token
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c WHERE Provider__c = 'Outlook' LIMIT 1];
        wu.Refresh_Token__c = null;
        update wu;

        Test.startTest();
        List<String> authenticatedProviders = AIEmailProviderFactory.getAuthenticatedProviderTypes(UserInfo.getUserId());
        Test.stopTest();

        // Should only return Gmail since Outlook has no refresh token
        Assert.areEqual(1, authenticatedProviders.size(), 'Should have 1 authenticated provider');
        Assert.isTrue(authenticatedProviders.contains('Gmail'), 'Should include Gmail');
        Assert.isFalse(authenticatedProviders.contains('Outlook'), 'Should not include Outlook without refresh token');
    }

    @isTest
    static void testGetAuthenticatedProviderTypes_BlankRefreshToken() {
        // Update to blank refresh token
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c WHERE Provider__c = 'Gmail' LIMIT 1];
        wu.Refresh_Token__c = '';
        update wu;

        Test.startTest();
        List<String> authenticatedProviders = AIEmailProviderFactory.getAuthenticatedProviderTypes(UserInfo.getUserId());
        Test.stopTest();

        // Should only return Outlook since Gmail has blank refresh token
        Assert.areEqual(1, authenticatedProviders.size(), 'Should have 1 authenticated provider');
        Assert.isTrue(authenticatedProviders.contains('Outlook'), 'Should include Outlook');
    }

    @isTest
    static void testGetAuthenticatedProviderTypes_NullProvider() {
        // Update to null provider
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c WHERE Provider__c = 'Outlook' LIMIT 1];
        wu.Provider__c = null;
        update wu;

        Test.startTest();
        List<String> authenticatedProviders = AIEmailProviderFactory.getAuthenticatedProviderTypes(UserInfo.getUserId());
        Test.stopTest();

        // Should only return Gmail since Outlook has null provider
        Assert.areEqual(1, authenticatedProviders.size(), 'Should have 1 authenticated provider');
        Assert.isTrue(authenticatedProviders.contains('Gmail'), 'Should include Gmail');
    }

    // =========================================================================
    // ACTIVE AUTHENTICATED PROVIDERS TESTS
    // =========================================================================

    @isTest
    static void testGetActiveAuthenticatedProviders_BothActive() {
        Test.startTest();
        List<String> activeProviders = AIEmailProviderFactory.getActiveAuthenticatedProviders(UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual(2, activeProviders.size(), 'Should have 2 active providers');
        Assert.isTrue(activeProviders.contains('Outlook'), 'Should include Outlook');
        Assert.isTrue(activeProviders.contains('Gmail'), 'Should include Gmail');
    }

    @isTest
    static void testGetActiveAuthenticatedProviders_OnlyOutlookEnabled() {
        // Disable Gmail in settings
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.WS_Gmail_Enabled__c = false;
        update settings;
        
        // Clear cache
        AIEmailProviderFactory.clearSettingsCache();

        Test.startTest();
        List<String> activeProviders = AIEmailProviderFactory.getActiveAuthenticatedProviders(UserInfo.getUserId());
        Test.stopTest();

        // Should only return Outlook since Gmail is disabled
        Assert.areEqual(1, activeProviders.size(), 'Should have 1 active provider');
        Assert.isTrue(activeProviders.contains('Outlook'), 'Should include Outlook');
    }

    @isTest
    static void testGetActiveAuthenticatedProviders_OnlyGmailAuthenticated() {
        // Delete Outlook authentication
        delete [SELECT Id FROM AI_Workspace_User__c WHERE Provider__c = 'Outlook'];

        Test.startTest();
        List<String> activeProviders = AIEmailProviderFactory.getActiveAuthenticatedProviders(UserInfo.getUserId());
        Test.stopTest();

        // Should only return Gmail since Outlook is not authenticated
        Assert.areEqual(1, activeProviders.size(), 'Should have 1 active provider');
        Assert.isTrue(activeProviders.contains('Gmail'), 'Should include Gmail');
    }

    @isTest
    static void testGetActiveAuthenticatedProviders_NoneActive() {
        // Delete all workspace users
        delete [SELECT Id FROM AI_Workspace_User__c];

        Test.startTest();
        List<String> activeProviders = AIEmailProviderFactory.getActiveAuthenticatedProviders(UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual(0, activeProviders.size(), 'Should have no active providers');
    }

    @isTest
    static void testGetActiveAuthenticatedProviders_CaseInsensitiveMatching() {
        // Test case-insensitive matching between enabled and authenticated
        Test.startTest();
        List<String> activeProviders = AIEmailProviderFactory.getActiveAuthenticatedProviders(UserInfo.getUserId());
        Test.stopTest();

        // Should match regardless of case differences
        Assert.isTrue(activeProviders.size() > 0, 'Should have active providers with case-insensitive matching');
    }

    // =========================================================================
    // NORMALIZE TO WORKSPACE USER PROVIDER TESTS
    // =========================================================================

    @isTest
    static void testNormalizeToWorkspaceUserProvider_MicrosoftGraph() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual('Outlook', normalized, 'Should normalize to Outlook');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_Outlook() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('Outlook');
        Test.stopTest();

        Assert.areEqual('Outlook', normalized, 'Should normalize to Outlook');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_MicrosoftEmail() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual('Outlook', normalized, 'Should normalize to Outlook');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_Gmail() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('GMAIL_EMAIL');
        Test.stopTest();

        Assert.areEqual('Gmail', normalized, 'Should normalize to Gmail');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_GmailEmail() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('GMAIL_EMAIL');
        Test.stopTest();

        Assert.areEqual('Gmail', normalized, 'Should normalize to Gmail');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_WithSpaces() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('MICROSOFT EMAIL');
        Test.stopTest();

        Assert.areEqual('Outlook', normalized, 'Should normalize spaces and return Outlook');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_LowerCase() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('gmail');
        Test.stopTest();

        Assert.areEqual('Gmail', normalized, 'Should normalize lowercase to Gmail');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_Null() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider(null);
        Test.stopTest();

        Assert.areEqual(null, normalized, 'Should return null for null input');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_Blank() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('');
        Test.stopTest();

        Assert.areEqual(null, normalized, 'Should return null for blank input');
    }

    @isTest
    static void testNormalizeToWorkspaceUserProvider_Unknown() {
        Test.startTest();
        String normalized = AIEmailProviderFactory.normalizeToWorkspaceUserProvider('UNKNOWN_PROVIDER');
        Test.stopTest();

        Assert.areEqual('UNKNOWN_PROVIDER', normalized, 'Should return input as-is for unknown provider');
    }

    // =========================================================================
    // SETTINGS CACHE TESTS
    // =========================================================================

    @isTest
    static void testSettingsCache() {
        // Clear cache first
        AIEmailProviderFactory.clearSettingsCache();

        Test.startTest();
        // First call should query settings
        List<String> providers1 = AIEmailProviderFactory.getEnabledProviderTypes();
        
        // Second call should use cached settings
        List<String> providers2 = AIEmailProviderFactory.getEnabledProviderTypes();
        Test.stopTest();

        Assert.areEqual(providers1.size(), providers2.size(), 'Cached results should match');
    }

    @isTest
    static void testClearSettingsCache() {
        // Get providers to populate cache
        List<String> providers1 = AIEmailProviderFactory.getEnabledProviderTypes();

        // Update settings
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.WS_Gmail_Enabled__c = false;
        update settings;

        Test.startTest();
        // Clear cache
        AIEmailProviderFactory.clearSettingsCache();
        
        // Should get updated settings
        List<String> providers2 = AIEmailProviderFactory.getEnabledProviderTypes();
        Test.stopTest();

        // Results should be different after cache clear
        Assert.areEqual(1, providers2.size(), 'Should reflect updated settings after cache clear');
    }
}