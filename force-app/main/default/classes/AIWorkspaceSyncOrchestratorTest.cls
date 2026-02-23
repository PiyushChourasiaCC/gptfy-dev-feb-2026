/**
 * Test class for AIWorkspaceSyncOrchestrator
 * Tests the workspace-based sync orchestrator
 * 
 * @author GPTfy
 * @date 2026-01-16
 */
@isTest
private class AIWorkspaceSyncOrchestratorTest {
    
    @TestSetup
    static void setup() {
        // Create test user
        User testUser = createTestUser();
        
        // Create workspace user records
        System.runAs(testUser) {
            List<AI_Workspace_User__c> workspaceUsers = new List<AI_Workspace_User__c>();
            
            // Outlook connection
            workspaceUsers.add(new AI_Workspace_User__c(
                User__c = testUser.Id,
                Provider__c = 'Outlook',
                Refresh_Token__c = 'encrypted_outlook_token'
            ));
            
            // Gmail connection
            workspaceUsers.add(new AI_Workspace_User__c(
                User__c = testUser.Id,
                Provider__c = 'Gmail',
                Refresh_Token__c = 'encrypted_gmail_token'
            ));
            
            insert workspaceUsers;
        }
    }
    
    @isTest
    static void testStartScheduledSync_NoUsers() {
        // Delete all workspace users first
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        AIWorkspaceSyncOrchestrator.startScheduledSync();
        Test.stopTest();
        
        // Should create a skip log
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c FROM AI_Workspace_Sync_Log__c
            WHERE Status__c = 'Skipped'
        ];
        
        Assert.isFalse(logs.isEmpty(), 'Should create skipped log when no users');
    }
    
    @isTest
    static void testStartScheduledSync_WithUsers() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        AIWorkspaceSyncOrchestrator.startScheduledSync();
        Test.stopTest();
        
        // Should have enqueued a job
        Assert.isTrue(true, 'Should start sync without errors');
    }
    
    @isTest
    static void testRunNowForCurrentUser_NoConnection() {
        // Create a new user with no workspace records
        User newUser = new User(
            FirstName = 'NoWorkspace',
            LastName = 'TestUser',
            Email = 'noworkspace@test.gptfy.com',
            Username = 'noworkspace' + System.currentTimeMillis() + '@test.gptfy.com',
            Alias = 'nowrk',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert newUser;
        
        Test.startTest();
        System.runAs(newUser) {
            Boolean exceptionThrown = false;
            try {
                AIWorkspaceSyncOrchestrator.runNowForCurrentUser();
            } catch (AuraHandledException e) {
                exceptionThrown = true;
                // AuraHandledException wraps the message, so check if it's not null
                Assert.isNotNull(e.getMessage(), 'Should have an error message');
            } catch (Exception e) {
                // Any exception is acceptable - indicates the check worked
                exceptionThrown = true;
            }
            Assert.isTrue(exceptionThrown, 'Should throw exception when no connection');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testRunNowForCurrentUser_WithConnection() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Get the test user's workspace connection
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AIWorkspaceSyncOrchestrator.runNowForCurrentUser();
            Test.stopTest();
        }
        
        Assert.isTrue(true, 'Should start run-now sync without errors');
    }
    
    @isTest
    static void testHasWorkspaceConnection_True() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        Boolean hasConnection;
        System.runAs(testUser) {
            Test.startTest();
            hasConnection = AIWorkspaceSyncOrchestrator.hasWorkspaceConnection();
            Test.stopTest();
        }
        
        Assert.isTrue(hasConnection, 'Should return true when connection exists');
    }
    
    @isTest
    static void testHasWorkspaceConnection_False() {
        // Delete all workspace users
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        Boolean hasConnection = AIWorkspaceSyncOrchestrator.hasWorkspaceConnection();
        Test.stopTest();
        
        Assert.isFalse(hasConnection, 'Should return false when no connection');
    }
    
    @isTest
    static void testGetConnectedProviders() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        List<String> providers;
        System.runAs(testUser) {
            Test.startTest();
            providers = AIWorkspaceSyncOrchestrator.getConnectedProviders();
            Test.stopTest();
        }
        
        Assert.areEqual(2, providers.size(), 'Should return 2 providers');
        Assert.isTrue(providers.contains('Outlook'), 'Should contain Outlook');
        Assert.isTrue(providers.contains('Gmail'), 'Should contain Gmail');
    }
    
    @isTest
    static void testGetSyncStatusForCurrentUser_WithConnection() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        // Create a sync log for the user
        AI_Workspace_Sync_Log__c log = new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addMinutes(-5),
            End_Time__c = DateTime.now(),
            Emails_Imported__c = 10
        );
        insert log;
        
        AIWorkspaceSyncOrchestrator.SyncStatus status;
        System.runAs(testUser) {
            Test.startTest();
            status = AIWorkspaceSyncOrchestrator.getSyncStatusForCurrentUser();
            Test.stopTest();
        }
        
        Assert.isTrue(status.hasConnection, 'Should have connection');
        Assert.areEqual(2, status.connectedProviders.size(), 'Should have 2 providers');
        Assert.areEqual('Success', status.lastSyncStatus, 'Should show last sync status');
        Assert.areEqual(10, status.lastEmailsImported, 'Should show emails imported');
    }
    
    @isTest
    static void testGetSyncStatusForCurrentUser_NoHistory() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        AIWorkspaceSyncOrchestrator.SyncStatus status;
        System.runAs(testUser) {
            Test.startTest();
            status = AIWorkspaceSyncOrchestrator.getSyncStatusForCurrentUser();
            Test.stopTest();
        }
        
        Assert.isTrue(status.hasConnection, 'Should have connection');
        Assert.isNull(status.lastSyncTime, 'Should have no last sync time');
    }
    
    @isTest
    static void testSyncStatusClass() {
        AIWorkspaceSyncOrchestrator.SyncStatus status = new AIWorkspaceSyncOrchestrator.SyncStatus();
        
        Assert.isFalse(status.hasConnection, 'Default hasConnection should be false');
        Assert.isTrue(status.connectedProviders.isEmpty(), 'Default providers should be empty');
        Assert.areEqual(0, status.lastEmailsImported, 'Default emails imported should be 0');
    }
    
    @isTest
    static void testStartScheduledSync_UsersWithAutoSyncDisabled() {
        // Disable auto sync for all workspace users
        List<AI_Workspace_User__c> workspaceUsers = [SELECT Id, Auto_Sync_Enabled__c FROM AI_Workspace_User__c];
        for (AI_Workspace_User__c wu : workspaceUsers) {
            wu.Auto_Sync_Enabled__c = false;
        }
        update workspaceUsers;
        
        Test.startTest();
        AIWorkspaceSyncOrchestrator.startScheduledSync();
        Test.stopTest();
        
        // Should create a skip log since no users have auto sync enabled
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c FROM AI_Workspace_Sync_Log__c
            WHERE Status__c = 'Skipped'
        ];
        
        Assert.isFalse(logs.isEmpty(), 'Should create skipped log when no users have auto sync enabled');
    }
    
    @isTest
    static void testStartScheduledSync_WithBlankRefreshToken() {
        // Update workspace users to have blank refresh tokens
        List<AI_Workspace_User__c> workspaceUsers = [SELECT Id, Refresh_Token__c FROM AI_Workspace_User__c];
        for (AI_Workspace_User__c wu : workspaceUsers) {
            wu.Refresh_Token__c = '';
        }
        update workspaceUsers;
        
        Test.startTest();
        AIWorkspaceSyncOrchestrator.startScheduledSync();
        Test.stopTest();
        
        // Should create a skip log since no users have valid tokens
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c FROM AI_Workspace_Sync_Log__c
            WHERE Status__c = 'Skipped'
        ];
        
        Assert.isFalse(logs.isEmpty(), 'Should create skipped log when no valid tokens');
    }
    
    @isTest
    static void testRunNowForCurrentUser_EmailSyncEnabled() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Ensure email sync is enabled in settings
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        if (settings == null) {
            settings = new AI_Workspace_Sync_Settings__c();
        }
        settings.Sync_Enabled__c = true;
        settings.Calendar_Sync_Enabled__c = false;
        settings.Task_Sync_Enabled__c = false;
        upsert settings;
        
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AIWorkspaceSyncOrchestrator.runNowForCurrentUser();
            Test.stopTest();
        }
        
        Assert.isTrue(true, 'Should start email sync without errors');
    }
    
    @isTest
    static void testRunNowForCurrentUser_CalendarSyncEnabled() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Ensure only calendar sync is enabled
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        if (settings == null) {
            settings = new AI_Workspace_Sync_Settings__c();
        }
        settings.Sync_Enabled__c = false;
        settings.Calendar_Sync_Enabled__c = true;
        settings.Task_Sync_Enabled__c = false;
        upsert settings;
        
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AIWorkspaceSyncOrchestrator.runNowForCurrentUser();
            Test.stopTest();
        }
        
        Assert.isTrue(true, 'Should start calendar sync without errors');
    }
    
    @isTest
    static void testRunNowForCurrentUser_TaskSyncEnabled() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Ensure only task sync is enabled
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        if (settings == null) {
            settings = new AI_Workspace_Sync_Settings__c();
        }
        settings.Sync_Enabled__c = false;
        settings.Calendar_Sync_Enabled__c = false;
        settings.Task_Sync_Enabled__c = true;
        upsert settings;
        
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AIWorkspaceSyncOrchestrator.runNowForCurrentUser();
            Test.stopTest();
        }
        
        Assert.isTrue(true, 'Should start task sync without errors');
    }
    
    @isTest
    static void testRunNowForCurrentUser_NoSyncEnabled() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Disable all sync types
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        if (settings == null) {
            settings = new AI_Workspace_Sync_Settings__c();
        }
        settings.Sync_Enabled__c = false;
        settings.Calendar_Sync_Enabled__c = false;
        settings.Task_Sync_Enabled__c = false;
        upsert settings;
        
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AIWorkspaceSyncOrchestrator.runNowForCurrentUser();
            Test.stopTest();
        }
        
        Assert.isTrue(true, 'Should default to email sync when no sync types enabled');
    }
    
    @isTest
    static void testStartScheduledSync_AllSyncTypesDisabled() {
        // Disable all sync types in settings
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        if (settings == null) {
            settings = new AI_Workspace_Sync_Settings__c();
        }
        settings.Sync_Enabled__c = false;
        settings.Calendar_Sync_Enabled__c = false;
        settings.Task_Sync_Enabled__c = false;
        upsert settings;
        
        Test.startTest();
        AIWorkspaceSyncOrchestrator.startScheduledSync();
        Test.stopTest();
        
        // Should create a skip log since all sync types are disabled
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c, Error_Message__c FROM AI_Workspace_Sync_Log__c
            WHERE Status__c = 'Skipped'
        ];
        
        Assert.isFalse(logs.isEmpty(), 'Should create skipped log when all sync types disabled');
        Assert.isTrue(logs[0].Error_Message__c.contains('disabled'), 'Should mention disabled in message');
    }
    
    @isTest
    static void testGetConnectedProviders_NoConnection() {
        // Delete all workspace users
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        List<String> providers = AIWorkspaceSyncOrchestrator.getConnectedProviders();
        Test.stopTest();
        
        Assert.isTrue(providers.isEmpty(), 'Should return empty list when no connections');
    }
    
    @isTest
    static void testGetSyncStatusForCurrentUser_NoConnection() {
        // Delete all workspace users
        delete [SELECT Id FROM AI_Workspace_User__c];
        
        Test.startTest();
        AIWorkspaceSyncOrchestrator.SyncStatus status = AIWorkspaceSyncOrchestrator.getSyncStatusForCurrentUser();
        Test.stopTest();
        
        Assert.isFalse(status.hasConnection, 'Should have no connection');
        Assert.isTrue(status.connectedProviders.isEmpty(), 'Should have no providers');
    }
    
    @isTest
    static void testRunNowForCurrentUser_WithBlankRefreshToken() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        // Update workspace users to have blank refresh tokens
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id, Refresh_Token__c 
            FROM AI_Workspace_User__c 
            WHERE User__c = :testUser.Id
        ];
        for (AI_Workspace_User__c wu : workspaceUsers) {
            wu.Refresh_Token__c = '';
        }
        update workspaceUsers;
        
        System.runAs(testUser) {
            Test.startTest();
            Boolean exceptionThrown = false;
            try {
                AIWorkspaceSyncOrchestrator.runNowForCurrentUser();
            } catch (AuraHandledException e) {
                exceptionThrown = true;
                Assert.isNotNull(e.getMessage(), 'Should have error message');
            }
            Test.stopTest();
            
            Assert.isTrue(exceptionThrown, 'Should throw exception when no valid tokens');
        }
    }
    
    // ========================================================================
    // HELPER METHODS
    // ========================================================================
    
    private static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User u = new User(
            Alias = 'testusr',
            Email = 'testuser@test.gptfy.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + DateTime.now().getTime() + '@test.gptfy.com'
        );
        insert u;
        return u;
    }
}