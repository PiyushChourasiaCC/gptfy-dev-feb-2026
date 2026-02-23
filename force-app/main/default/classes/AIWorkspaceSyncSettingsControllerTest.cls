/**
 * Test class for AIWorkspaceSyncSettingsController
 * Tests CRUD operations and validation for workspace sync settings
 * 
 * @author GPTfy
 * @date 2026-02-19
 */
@isTest
private class AIWorkspaceSyncSettingsControllerTest {
    
    @isTest
    static void testGetSettings_NoExistingRecord() {
        // Delete any existing settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        
        Test.startTest();
        AIWorkspaceSyncSettingsController.WorkspaceSyncSettings result = 
            AIWorkspaceSyncSettingsController.getSettings();
        Test.stopTest();
        
        // Verify default values are returned
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual(true, result.syncEnabled, 'Email sync should be enabled by default');
        Assert.areEqual(60, result.syncFrequencyMinutes, 'Sync frequency should be 60 minutes');
        Assert.areEqual(24, result.lookbackHours, 'Lookback hours should be 24');
        Assert.areEqual(50, result.maxEmailsPerUser, 'Max emails should be 50');
        Assert.areEqual(false, result.calendarSyncEnabled, 'Calendar sync should be disabled by default');
        Assert.areEqual(false, result.taskSyncEnabled, 'Task sync should be disabled by default');
    }
    
    @isTest
    static void testGetSettings_WithExistingRecord() {
        // Create settings record
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = false,
            Sync_Frequency_Minutes__c = 30,
            Lookback_Hours__c = 48,
            Max_Emails_Per_User__c = 100,
            Calendar_Sync_Enabled__c = true,
            Calendar_Lookback_Days__c = 14,
            Task_Sync_Enabled__c = true,
            Task_Lookback_Days__c = 30,
            Microsoft_Client_Id__c = 'test_client_id',
            Microsoft_Client_Secret__c = 'test_secret',
            Google_Client_Id__c = 'google_client_id',
            Google_Client_Secret__c = 'google_secret'
        );
        insert settings;
        
        Test.startTest();
        AIWorkspaceSyncSettingsController.WorkspaceSyncSettings result = 
            AIWorkspaceSyncSettingsController.getSettings();
        Test.stopTest();
        
        // Verify settings are returned
        Assert.isFalse(result.syncEnabled, 'Email sync should be disabled');
        Assert.areEqual(30, result.syncFrequencyMinutes, 'Sync frequency should be 30');
        Assert.areEqual(48, result.lookbackHours, 'Lookback hours should be 48');
        Assert.areEqual(100, result.maxEmailsPerUser, 'Max emails should be 100');
        Assert.isTrue(result.calendarSyncEnabled, 'Calendar sync should be enabled');
        Assert.isTrue(result.taskSyncEnabled, 'Task sync should be enabled');
        
        // Verify sensitive fields are masked
        Assert.isTrue(result.hasMicrosoftClientId, 'Should have Microsoft Client ID');
        Assert.isTrue(result.hasMicrosoftClientSecret, 'Should have Microsoft Client Secret');
        Assert.areEqual('****************', result.microsoftClientId, 'Client ID should be masked');
        Assert.areEqual('****************', result.microsoftClientSecret, 'Client Secret should be masked');
        
        Assert.isTrue(result.hasGoogleClientId, 'Should have Google Client ID');
        Assert.isTrue(result.hasGoogleClientSecret, 'Should have Google Client Secret');
        Assert.areEqual('****************', result.googleClientId, 'Google Client ID should be masked');
        Assert.areEqual('****************', result.googleClientSecret, 'Google Client Secret should be masked');
    }
    
    @isTest
    static void testGetSettings_WithBlankSensitiveFields() {
        // Create settings with blank sensitive fields
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true
        );
        insert settings;
        
        Test.startTest();
        AIWorkspaceSyncSettingsController.WorkspaceSyncSettings result = 
            AIWorkspaceSyncSettingsController.getSettings();
        Test.stopTest();
        
        // Verify sensitive fields are empty, not masked
        Assert.isFalse(result.hasMicrosoftClientId, 'Should not have Microsoft Client ID');
        Assert.isFalse(result.hasMicrosoftClientSecret, 'Should not have Microsoft Client Secret');
        Assert.areEqual('', result.microsoftClientId, 'Client ID should be empty');
        Assert.areEqual('', result.microsoftClientSecret, 'Client Secret should be empty');
        
        Assert.isFalse(result.hasGoogleClientId, 'Should not have Google Client ID');
        Assert.isFalse(result.hasGoogleClientSecret, 'Should not have Google Client Secret');
        Assert.areEqual('', result.googleClientId, 'Google Client ID should be empty');
        Assert.areEqual('', result.googleClientSecret, 'Google Client Secret should be empty');
    }
    
    @isTest
    static void testUpdateField_CreateNewRecord() {
        // Delete any existing settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        
        Test.startTest();
        Boolean result = AIWorkspaceSyncSettingsController.updateField('syncEnabled', true);
        Test.stopTest();
        
        Assert.isTrue(result, 'Update should succeed');
        
        // Verify record was created
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.isNotNull(settings.Id, 'Settings record should be created');
        Assert.areEqual(UserInfo.getOrganizationId(), settings.SetupOwnerId, 'Should be org-level');
    }
    
    @isTest
    static void testUpdateField_UpdateExistingRecord() {
        // Create settings record
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Lookback_Hours__c = 24
        );
        insert settings;
        
        Test.startTest();
        Boolean result = AIWorkspaceSyncSettingsController.updateField('lookbackHours', 48);
        Test.stopTest();
        
        Assert.isTrue(result, 'Update should succeed');
        
        // Verify field was updated
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areEqual(48, settings.Lookback_Hours__c, 'Lookback hours should be updated');
    }
    
    @isTest
    static void testUpdateField_BooleanField() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Calendar_Sync_Enabled__c = false
        );
        insert settings;
        
        Test.startTest();
        Boolean result = AIWorkspaceSyncSettingsController.updateField('calendarSyncEnabled', true);
        Test.stopTest();
        
        Assert.isTrue(result, 'Update should succeed');
        
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.isTrue(settings.Calendar_Sync_Enabled__c, 'Calendar sync should be enabled');
    }
    
    @isTest
    static void testUpdateField_StringField() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        Boolean result = AIWorkspaceSyncSettingsController.updateField('digestFrequency', 'Weekly');
        Test.stopTest();
        
        Assert.isTrue(result, 'Update should succeed');
        
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areEqual('Weekly', settings.Digest_Frequency__c, 'Digest frequency should be updated');
    }
    
    @isTest
    static void testUpdateField_MaskedValue() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Microsoft_Client_Secret__c = 'original_secret'
        );
        insert settings;
        
        Test.startTest();
        // Try to update with masked value
        Boolean result = AIWorkspaceSyncSettingsController.updateField('microsoftClientSecret', '****************');
        Test.stopTest();
        
        Assert.isTrue(result, 'Update should succeed');
        
        // Verify value was NOT changed
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areEqual('original_secret', settings.Microsoft_Client_Secret__c, 'Secret should not be changed');
    }
    
    @isTest
    static void testUpdateField_InvalidFieldName() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        try {
            AIWorkspaceSyncSettingsController.updateField('invalidFieldName', 'value');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionThrown, 'Should throw exception for invalid field');
        Assert.isTrue(exceptionMessage.contains('Invalid field name') || exceptionMessage.contains('Error updating field') || exceptionMessage.contains('Script-thrown exception'), 
            'Should have error message, got: ' + exceptionMessage);
    }
    
    @isTest
    static void testUpdateField_FixSetupOwnerId() {
        // Create settings with wrong SetupOwnerId (user-level instead of org-level)
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getUserId(),
            Sync_Enabled__c = true
        );
        insert settings;
        
        Test.startTest();
        Boolean result = AIWorkspaceSyncSettingsController.updateField('syncFrequencyMinutes', 30);
        Test.stopTest();
        
        Assert.isTrue(result, 'Update should succeed');
        
        // Verify SetupOwnerId was fixed to org-level
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areEqual(UserInfo.getOrganizationId(), settings.SetupOwnerId, 'Should be fixed to org-level');
    }
    
    @isTest
    static void testValidateRequiredFields_OutlookEnabled_AllFieldsPresent() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Microsoft_Client_Id__c = 'test_id',
            Microsoft_Client_Secret__c = 'test_secret',
            Microsoft_Auth_Endpoint__c = 'https://auth.example.com',
            Microsoft_Token_Endpoint__c = 'https://token.example.com',
            Microsoft_Scope__c = 'offline_access'
        );
        insert settings;
        
        Test.startTest();
        List<String> missingFields = AIWorkspaceSyncSettingsController.validateRequiredFields(true, false);
        Test.stopTest();
        
        Assert.isTrue(missingFields.isEmpty(), 'Should have no missing fields');
    }
    
    @isTest
    static void testValidateRequiredFields_OutlookEnabled_MissingFields() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        List<String> missingFields = AIWorkspaceSyncSettingsController.validateRequiredFields(true, false);
        Test.stopTest();
        
        Assert.isFalse(missingFields.isEmpty(), 'Should have missing fields');
        Assert.isTrue(missingFields.contains('Microsoft Client Id'), 'Should be missing Client Id');
        Assert.isTrue(missingFields.contains('Microsoft Client Secret'), 'Should be missing Client Secret');
        Assert.isTrue(missingFields.contains('Microsoft Auth Endpoint'), 'Should be missing Auth Endpoint');
        Assert.isTrue(missingFields.contains('Microsoft Token Endpoint'), 'Should be missing Token Endpoint');
        Assert.isTrue(missingFields.contains('Microsoft Scope'), 'Should be missing Scope');
    }
    
    @isTest
    static void testValidateRequiredFields_GmailEnabled_AllFieldsPresent() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Google_Client_Id__c = 'test_id',
            Google_Client_Secret__c = 'test_secret',
            Google_Auth_Endpoint__c = 'https://auth.google.com',
            Google_Token_Endpoint__c = 'https://token.google.com',
            Google_Scope__c = 'https://www.googleapis.com/auth/gmail.readonly'
        );
        insert settings;
        
        Test.startTest();
        List<String> missingFields = AIWorkspaceSyncSettingsController.validateRequiredFields(false, true);
        Test.stopTest();
        
        Assert.isTrue(missingFields.isEmpty(), 'Should have no missing fields');
    }
    
    @isTest
    static void testValidateRequiredFields_GmailEnabled_MissingFields() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        List<String> missingFields = AIWorkspaceSyncSettingsController.validateRequiredFields(false, true);
        Test.stopTest();
        
        Assert.isFalse(missingFields.isEmpty(), 'Should have missing fields');
        Assert.isTrue(missingFields.contains('Google Client Id'), 'Should be missing Client Id');
        Assert.isTrue(missingFields.contains('Google Client Secret'), 'Should be missing Client Secret');
        Assert.isTrue(missingFields.contains('Google Auth Endpoint'), 'Should be missing Auth Endpoint');
        Assert.isTrue(missingFields.contains('Google Token Endpoint'), 'Should be missing Token Endpoint');
        Assert.isTrue(missingFields.contains('Google Scope'), 'Should be missing Scope');
    }
    
    @isTest
    static void testValidateRequiredFields_BothEnabled_MixedFields() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Microsoft_Client_Id__c = 'test_id',
            Microsoft_Client_Secret__c = 'test_secret',
            Google_Client_Id__c = 'google_id'
        );
        insert settings;
        
        Test.startTest();
        List<String> missingFields = AIWorkspaceSyncSettingsController.validateRequiredFields(true, true);
        Test.stopTest();
        
        Assert.isFalse(missingFields.isEmpty(), 'Should have missing fields');
        // Should have missing Microsoft fields
        Assert.isTrue(missingFields.contains('Microsoft Auth Endpoint'), 'Should be missing Microsoft Auth Endpoint');
        // Should have missing Google fields
        Assert.isTrue(missingFields.contains('Google Client Secret'), 'Should be missing Google Client Secret');
    }
    
    @isTest
    static void testValidateRequiredFields_BothDisabled() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        List<String> missingFields = AIWorkspaceSyncSettingsController.validateRequiredFields(false, false);
        Test.stopTest();
        
        Assert.isTrue(missingFields.isEmpty(), 'Should have no missing fields when both disabled');
    }
    
    @isTest
    static void testEnsureOrgLevelSettings_NoExistingRecord() {
        // Delete any existing settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        
        Test.startTest();
        Map<String, Object> result = AIWorkspaceSyncSettingsController.ensureOrgLevelSettings();
        Test.stopTest();
        
        Assert.isTrue((Boolean)result.get('success'), 'Should succeed');
        Assert.isTrue(((String)result.get('message')).contains('Created'), 'Should create new settings');
        Assert.isNotNull(result.get('recordId'), 'Should have record ID');
        Assert.areEqual(UserInfo.getOrganizationId(), result.get('setupOwnerId'), 'Should be org-level');
    }
    
    @isTest
    static void testEnsureOrgLevelSettings_ExistingOrgLevel() {
        // Create org-level settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true
        );
        insert settings;
        
        Test.startTest();
        Map<String, Object> result = AIWorkspaceSyncSettingsController.ensureOrgLevelSettings();
        Test.stopTest();
        
        Assert.isTrue((Boolean)result.get('success'), 'Should succeed');
        Assert.isTrue(((String)result.get('message')).contains('already'), 'Should indicate already org-level');
        Assert.areEqual(settings.Id, result.get('recordId'), 'Should have same record ID');
    }
    
    @isTest
    static void testEnsureOrgLevelSettings_FixUserLevel() {
        // Create user-level settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getUserId(),
            Sync_Enabled__c = true
        );
        insert settings;
        
        Test.startTest();
        Map<String, Object> result = AIWorkspaceSyncSettingsController.ensureOrgLevelSettings();
        Test.stopTest();
        
        Assert.isTrue((Boolean)result.get('success'), 'Should succeed');
        String message = (String)result.get('message');
        // The method might create a new org-level record or fix the existing one
        Assert.isTrue(message.contains('Fixed') || message.contains('already') || message.contains('Created'), 
            'Should fix, create, or already be org-level, got: ' + message);
        Assert.areEqual(UserInfo.getOrganizationId(), result.get('setupOwnerId'), 'Should be org-level');
        
        // Verify an org-level record exists
        List<AI_Workspace_Sync_Settings__c> orgSettings = [SELECT SetupOwnerId FROM AI_Workspace_Sync_Settings__c WHERE SetupOwnerId = :UserInfo.getOrganizationId()];
        Assert.isFalse(orgSettings.isEmpty(), 'Should have org-level settings');
    }
    
    @isTest
    static void testUpdateField_AllProviderFields() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        AIWorkspaceSyncSettingsController.updateField('wsOutlookEnabled', true);
        AIWorkspaceSyncSettingsController.updateField('wsGmailEnabled', true);
        Test.stopTest();
        
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.isTrue(settings.WS_Outlook_Enabled__c, 'Outlook should be enabled');
        Assert.isTrue(settings.WS_Gmail_Enabled__c, 'Gmail should be enabled');
    }
    
    @isTest
    static void testUpdateField_AllOAuthFields() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        AIWorkspaceSyncSettingsController.updateField('microsoftClientId', 'new_client_id');
        AIWorkspaceSyncSettingsController.updateField('microsoftClientSecret', 'new_secret');
        AIWorkspaceSyncSettingsController.updateField('microsoftAuthEndpoint', 'https://auth.com');
        AIWorkspaceSyncSettingsController.updateField('microsoftTokenEndpoint', 'https://token.com');
        AIWorkspaceSyncSettingsController.updateField('microsoftScope', 'offline_access');
        
        AIWorkspaceSyncSettingsController.updateField('googleClientId', 'google_client_id');
        AIWorkspaceSyncSettingsController.updateField('googleClientSecret', 'google_secret');
        AIWorkspaceSyncSettingsController.updateField('googleAuthEndpoint', 'https://google.auth.com');
        AIWorkspaceSyncSettingsController.updateField('googleTokenEndpoint', 'https://google.token.com');
        AIWorkspaceSyncSettingsController.updateField('googleScope', 'gmail.readonly');
        Test.stopTest();
        
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areEqual('new_client_id', settings.Microsoft_Client_Id__c, 'Microsoft Client ID should be updated');
        Assert.areEqual('google_client_id', settings.Google_Client_Id__c, 'Google Client ID should be updated');
    }
    
    @isTest
    static void testUpdateField_AllSyncSettings() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        // Email sync settings
        AIWorkspaceSyncSettingsController.updateField('syncEnabled', false);
        AIWorkspaceSyncSettingsController.updateField('syncFrequencyMinutes', 120);
        AIWorkspaceSyncSettingsController.updateField('lookbackHours', 72);
        AIWorkspaceSyncSettingsController.updateField('maxEmailsPerUser', 200);
        AIWorkspaceSyncSettingsController.updateField('emailsPerBatch', 50);
        
        // Calendar sync settings
        AIWorkspaceSyncSettingsController.updateField('calendarSyncEnabled', true);
        AIWorkspaceSyncSettingsController.updateField('calendarLookbackDays', 30);
        AIWorkspaceSyncSettingsController.updateField('calendarLookaheadDays', 60);
        AIWorkspaceSyncSettingsController.updateField('maxCalendarEventsPerUser', 100);
        
        // Task sync settings
        AIWorkspaceSyncSettingsController.updateField('taskSyncEnabled', true);
        AIWorkspaceSyncSettingsController.updateField('taskLookbackDays', 14);
        AIWorkspaceSyncSettingsController.updateField('maxTasksPerUser', 75);
        AIWorkspaceSyncSettingsController.updateField('includeCompletedTasks', true);
        Test.stopTest();
        
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.isFalse(settings.Sync_Enabled__c, 'Email sync should be disabled');
        Assert.areEqual(120, settings.Sync_Frequency_Minutes__c, 'Sync frequency should be updated');
        Assert.isTrue(settings.Calendar_Sync_Enabled__c, 'Calendar sync should be enabled');
        Assert.isTrue(settings.Task_Sync_Enabled__c, 'Task sync should be enabled');
    }
    
    @isTest
    static void testUpdateField_DigestAndExclusionSettings() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
        
        Test.startTest();
        // Digest settings
        AIWorkspaceSyncSettingsController.updateField('digestEnabled', true);
        AIWorkspaceSyncSettingsController.updateField('digestFrequency', 'Weekly');
        AIWorkspaceSyncSettingsController.updateField('digestHour', 10);
        AIWorkspaceSyncSettingsController.updateField('notifyUsers', true);
        
        // Exclusion rules
        AIWorkspaceSyncSettingsController.updateField('excludeInternal', false);
        AIWorkspaceSyncSettingsController.updateField('excludeMarketing', false);
        AIWorkspaceSyncSettingsController.updateField('excludeConfidential', false);
        AIWorkspaceSyncSettingsController.updateField('excludePublicDomains', false);
        AIWorkspaceSyncSettingsController.updateField('internalDomains', 'example.com,test.com');
        
        // Matching precedence
        AIWorkspaceSyncSettingsController.updateField('syncPrecedence', '{"1": ["Lead"]}');
        
        // Additional settings
        AIWorkspaceSyncSettingsController.updateField('maxUsersPerBatch', 20);
        AIWorkspaceSyncSettingsController.updateField('queueableDelayMinutes', 5);
        Test.stopTest();
        
        settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.isTrue(settings.Digest_Enabled__c, 'Digest should be enabled');
        Assert.areEqual('Weekly', settings.Digest_Frequency__c, 'Digest frequency should be updated');
        Assert.isFalse(settings.Exclude_Internal__c, 'Exclude internal should be false');
        Assert.areEqual('example.com,test.com', settings.Internal_Domains__c, 'Internal domains should be updated');
    }
    
    @isTest
    static void testGetSettings_AllFieldsPopulated() {
        // Create comprehensive settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            WS_Outlook_Enabled__c = true,
            WS_Gmail_Enabled__c = true,
            Digest_Enabled__c = true,
            Digest_Frequency__c = 'Weekly',
            Digest_Hour__c = 9,
            Notify_Users__c = true,
            Sync_Precedence__c = '{"1": ["Lead"]}',
            Exclude_Internal__c = false,
            Exclude_Marketing__c = false,
            Exclude_Confidential__c = false,
            Exclude_Public_Domains__c = false,
            Internal_Domains__c = 'example.com',
            Max_Users_Per_Batch__c = 15,
            Queueable_Delay_Minutes__c = 2
        );
        insert settings;
        
        Test.startTest();
        AIWorkspaceSyncSettingsController.WorkspaceSyncSettings result = 
            AIWorkspaceSyncSettingsController.getSettings();
        Test.stopTest();
        
        // Verify all fields
        Assert.isTrue(result.wsOutlookEnabled, 'Outlook should be enabled');
        Assert.isTrue(result.wsGmailEnabled, 'Gmail should be enabled');
        Assert.isTrue(result.digestEnabled, 'Digest should be enabled');
        Assert.areEqual('Weekly', result.digestFrequency, 'Digest frequency should be Weekly');
        Assert.areEqual(9, result.digestHour, 'Digest hour should be 9');
        Assert.isTrue(result.notifyUsers, 'Notify users should be true');
        Assert.areEqual('{"1": ["Lead"]}', result.syncPrecedence, 'Sync precedence should match');
        Assert.isFalse(result.excludeInternal, 'Exclude internal should be false');
        Assert.areEqual('example.com', result.internalDomains, 'Internal domains should match');
        Assert.areEqual(15, result.maxUsersPerBatch, 'Max users per batch should be 15');
        Assert.areEqual(2, result.queueableDelayMinutes, 'Queueable delay should be 2');
    }
}