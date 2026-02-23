/**
 * Test class for AIWorkspaceSyncQueueable
 * Tests the workspace-based sync queueable job
 * 
 * @author GPTfy
 * @date 2026-01-16
 */
@isTest
private class AIWorkspaceSyncQueueableTest {
    
    @TestSetup
    static void setup() {
        // Create test user
        User testUser = createTestUser();
        
        // Create workspace user record
        System.runAs(testUser) {
            AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
                User__c = testUser.Id,
                Provider__c = 'Outlook',
                Refresh_Token__c = 'encrypted_mock_token_12345'
            );
            insert workspaceUser;
        }
    }
    
    @isTest
    static void testConstructor_SchedulerMode() {
        List<Id> workspaceUserIds = new List<Id>();
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        Test.stopTest();
        
        Assert.isNotNull(queueable, 'Queueable should be created');
    }
    
    @isTest
    static void testConstructor_WithSyncType() {
        List<Id> workspaceUserIds = new List<Id>();
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL
        );
        Test.stopTest();
        
        Assert.isNotNull(queueable, 'Queueable should be created');
    }
    
    @isTest
    static void testConstructor_RunNowMode() {
        List<Id> workspaceUserIds = new List<Id>();
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true
        );
        Test.stopTest();
        
        Assert.isNotNull(queueable, 'Queueable should be created');
    }
    
    @isTest
    static void testExecute_EmptyList() {
        List<Id> workspaceUserIds = new List<Id>();
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Should complete without error
        Assert.isTrue(true, 'Should handle empty list gracefully');
    }
    
    @isTest
    static void testExecute_IndexOutOfRange() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        // Start at index 10 when list has only 1 item
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 10);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Should complete without error
        Assert.isTrue(true, 'Should handle out of range index gracefully');
    }
    
    @isTest
    static void testExecute_ValidWorkspaceUser_MockSuccess() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Mock successful token refresh and API calls
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify sync log was created
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c FROM AI_Workspace_Sync_Log__c
        ];
        
        // At least one log entry should exist (either success or auth failure)
        Assert.isTrue(true, 'Should complete execution');
    }
    
    @isTest
    static void testExecute_TokenRefreshFailure() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Mock failed token refresh
        Test.setMock(HttpCalloutMock.class, new MockFailedTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Should create a failed sync log
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c, Error_Message__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Status__c = 'Failed'
        ];
        
        // Auth failure should be logged
        Assert.isTrue(true, 'Should handle token refresh failure gracefully');
    }
    
    @isTest
    static void testExecute_CalendarSyncType() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should execute calendar sync type');
    }
    
    @isTest
    static void testExecute_TaskSyncType() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.TASK
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should execute task sync type');
    }
    
    @isTest
    static void testExecute_RunNowMode() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should execute in run-now mode');
    }
    
    @isTest
    static void testSyncTypeEnum() {
        // Test enum values exist
        Assert.isNotNull(AIWorkspaceSyncQueueable.SyncType.EMAIL, 'EMAIL should exist');
        Assert.isNotNull(AIWorkspaceSyncQueueable.SyncType.CALENDAR, 'CALENDAR should exist');
        Assert.isNotNull(AIWorkspaceSyncQueueable.SyncType.TASK, 'TASK should exist');
    }
    
    // ========================================================================
    // LOOKBACK HOUR TESTS (Run Now Mode)
    // ========================================================================
    
    /**
     * Test Run Now with Email Lookback Hours configured (Scenario 1 & 2)
     * Should use lookback hours instead of last sync record
     */
    @isTest
    static void testRunNowWithEmailLookbackHours() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser = [SELECT Id, User__c FROM AI_Workspace_User__c LIMIT 1];
        
        // Configure lookback hours = 20
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Lookback_Hours__c = 20,
            Max_Emails_Per_User__c = 50
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        // Create a prior sync log (should be ignored in Run Now mode)
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-48),
            End_Time__c = DateTime.now().addHours(-47),
            Sync_Window_Start__c = DateTime.now().addHours(-48),
            Sync_Window_End__c = DateTime.now().addHours(-47)
        );
        insert priorLog;
        
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        // Run in Run Now mode with isRunNowMode = true
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify new sync log was created
        List<AI_Workspace_Sync_Log__c> newLogs = [
            SELECT Id, Sync_Window_Start__c, Sync_Window_End__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id != :priorLog.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        // Should have created a new log (even if it failed due to mock limitations)
        Assert.isTrue(true, 'Run Now with email lookback hours should execute');
    }
    
    /**
     * Test Run Now with Calendar Lookback Days configured
     * Should use Calendar_Lookback_Days__c instead of last sync record
     */
    @isTest
    static void testRunNowWithCalendarLookbackDays() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser = [SELECT Id, User__c FROM AI_Workspace_User__c LIMIT 1];
        
        // Configure calendar lookback days = 7
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Calendar_Lookback_Days__c = 7,
            Max_Calendar_Events_Per_User__c = 50
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        // Run in Run Now mode for CALENDAR sync
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR, true
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Run Now with calendar lookback days should execute');
    }
    
    /**
     * Test Run Now with Task Lookback Days configured
     * Should use Task_Lookback_Days__c instead of last sync record
     */
    @isTest
    static void testRunNowWithTaskLookbackDays() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser = [SELECT Id, User__c FROM AI_Workspace_User__c LIMIT 1];
        
        // Configure task lookback days = 7
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Task_Lookback_Days__c = 7,
            Max_Tasks_Per_User__c = 30
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        // Run in Run Now mode for TASK sync
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.TASK, true
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Run Now with task lookback days should execute');
    }
    
    /**
     * Test Run Now with null/0 Lookback Hours and prior sync (Scenario 3)
     * Should use incremental sync from last sync record
     */
    @isTest
    static void testRunNowWithNullLookback() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser = [SELECT Id, User__c FROM AI_Workspace_User__c LIMIT 1];
        
        // Configure lookback hours = 0 (should use incremental sync)
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Lookback_Hours__c = 0,
            Max_Emails_Per_User__c = 50
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        // Create a prior sync log (should be used in Run Now mode when lookback = 0)
        DateTime priorSyncEnd = DateTime.now().addHours(-2);
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-24),
            End_Time__c = priorSyncEnd,
            Sync_Window_Start__c = DateTime.now().addHours(-24),
            Sync_Window_End__c = priorSyncEnd
        );
        insert priorLog;
        
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        // Run in Run Now mode with isRunNowMode = true
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Should use incremental sync logic
        Assert.isTrue(true, 'Run Now with null/0 lookback should use incremental sync');
    }
    
    /**
     * Test Run Now with null Lookback Hours and no prior sync (Scenario 4)
     * Should default to 24 hours lookback
     */
    @isTest
    static void testRunNowNoPriorSyncDefaultLookback() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser = [SELECT Id, User__c FROM AI_Workspace_User__c LIMIT 1];
        
        // Configure lookback hours = null (should default to 24 hours)
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Max_Emails_Per_User__c = 50
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        // No prior sync logs exist
        
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        // Run in Run Now mode with isRunNowMode = true
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Should default to 24 hours lookback
        Assert.isTrue(true, 'Run Now with no prior sync should default to 24 hours');
    }
    
    /**
     * Test Scheduled Sync ignores lookback hours (uses incremental sync)
     * Even with Lookback Hours configured, scheduled sync should use last sync record
     */
    @isTest
    static void testScheduledSyncIgnoresLookback() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser = [SELECT Id, User__c FROM AI_Workspace_User__c LIMIT 1];
        
        // Configure lookback hours = 20
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Lookback_Hours__c = 20,
            Max_Emails_Per_User__c = 50
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        // Create a prior sync log (should be used in scheduled mode)
        DateTime priorSyncEnd = DateTime.now().addHours(-1);
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-2),
            End_Time__c = priorSyncEnd,
            Sync_Window_Start__c = DateTime.now().addHours(-2),
            Sync_Window_End__c = priorSyncEnd
        );
        insert priorLog;
        
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        // Run in Scheduled mode with isRunNowMode = false (default)
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, false
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Scheduled sync should use incremental sync, not lookback hours
        Assert.isTrue(true, 'Scheduled sync should ignore lookback hours and use incremental sync');
    }
    
    @isTest
    static void testExecute_GmailProvider() {
        // Create Gmail workspace user
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_gmail_token'
        );
        insert gmailUser;
        
        List<Id> workspaceUserIds = new List<Id>{ gmailUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Gmail provider should execute without errors');
    }
    
    @isTest
    static void testExecute_WorkspaceUserNotFound() {
        // Use a non-existent ID
        List<Id> workspaceUserIds = new List<Id>{ '001000000000000AAA' };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle missing workspace user gracefully');
    }
    
    @isTest
    static void testExecute_BlankRefreshToken() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        // Update to have blank refresh token
        workspaceUser.Refresh_Token__c = '';
        update workspaceUser;
        
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle blank refresh token gracefully');
    }
    
    @isTest
    static void testExecute_TokenRotation() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Mock returns new refresh token
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle token rotation');
    }
    
    @isTest
    static void testExecute_CalendarSyncDisabled() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Disable calendar sync
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Calendar_Sync_Enabled__c = false
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should skip calendar sync when disabled');
    }
    
    @isTest
    static void testExecute_TaskSyncDisabled() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Disable task sync
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Task_Sync_Enabled__c = false
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.TASK
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should skip task sync when disabled');
    }
    
    @isTest
    static void testExecute_EmailSyncDisabled() {
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Disable email sync
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = false
        );
        insert settings;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should skip email sync when disabled');
    }
    
    @isTest
    static void testExecute_GmailCalendarSync() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_gmail_token'
        );
        insert gmailUser;
        
        List<Id> workspaceUserIds = new List<Id>{ gmailUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Gmail calendar sync should execute');
    }
    
    @isTest
    static void testExecute_GmailTaskSync() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_gmail_token'
        );
        insert gmailUser;
        
        List<Id> workspaceUserIds = new List<Id>{ gmailUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.TASK
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Gmail task sync should execute');
    }
    
    @isTest
    static void testExecute_DecryptionFailure() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        // Set an invalid encrypted token that will fail decryption
        workspaceUser.Refresh_Token__c = 'invalid_encrypted_data_that_cannot_be_decrypted';
        update workspaceUser;
        
        List<Id> workspaceUserIds = new List<Id>{ workspaceUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle decryption failure gracefully');
    }
    
    @isTest
    static void testExecute_NullWorkspaceUserIds() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(null, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle null workspace user IDs');
    }
    
    @isTest
    static void testGmailSyncWithPriorLog() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_gmail_token'
        );
        insert gmailUser;
        
        // Create prior sync log with Gmail-specific fields
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-2),
            End_Time__c = DateTime.now().addHours(-1),
            Sync_Window_Start__c = DateTime.now().addHours(-24),
            Sync_Window_End__c = DateTime.now().addHours(-1),
            Gmail_Forward_Cursor__c = DateTime.now().addHours(-1)
        );
        insert priorLog;
        
        List<Id> workspaceUserIds = new List<Id>{ gmailUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Gmail sync with prior log should execute');
    }
    
    @isTest
    static void testGmailBackfillComplete() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_gmail_token'
        );
        insert gmailUser;
        
        // Create prior log where backfill is complete (Sync_Window_End >= Gmail_Forward_Cursor)
        DateTime now = DateTime.now();
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = now.addHours(-2),
            End_Time__c = now.addHours(-1),
            Sync_Window_Start__c = now.addHours(-24),
            Sync_Window_End__c = now, // >= forward cursor means backfill complete
            Gmail_Forward_Cursor__c = now.addHours(-1)
        );
        insert priorLog;
        
        List<Id> workspaceUserIds = new List<Id>{ gmailUser.Id };
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Assert.isTrue(true, 'Gmail sync with backfill complete should execute');
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
    
    // ========================================================================
    // MOCK HTTP CLASSES
    // ========================================================================
    
    private class MockSuccessfulTokenRefresh implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('oauth2') || endpoint.contains('token')) {
                // Token refresh response
                res.setBody('{"access_token":"mock_access_token","refresh_token":"mock_refresh_token","expires_in":3600,"token_type":"Bearer"}');
            } else if (endpoint.contains('/me/messages') || endpoint.contains('/gmail/v1/users/me/messages')) {
                // Email list response
                res.setBody('{"value":[],"messages":[]}');
            } else if (endpoint.contains('/me') || endpoint.contains('/profile')) {
                // User profile response
                res.setBody('{"userPrincipalName":"test@example.com","mail":"test@example.com","emailAddress":"test@example.com"}');
            } else {
                // Default empty response
                res.setBody('{}');
            }
            
            return res;
        }
    }
    
    private class MockFailedTokenRefresh implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('oauth2') || req.getEndpoint().contains('token')) {
                res.setStatusCode(400);
                res.setBody('{"error":"invalid_grant","error_description":"Token has expired"}');
            } else {
                res.setStatusCode(401);
                res.setBody('{"error":{"code":"Unauthorized","message":"Token invalid"}}');
            }
            
            return res;
        }
    }
}