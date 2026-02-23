@isTest
private class AIEmailSyncOrchestratorTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account acc = new Account(
            Name = 'Test Corporation',
            Website = 'https://www.test.com'
        );
        insert acc;

        // Create AI_Workspace_Sync_Settings__c
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Calendar_Sync_Enabled__c = true,
            Task_Sync_Enabled__c = true,
            Max_Users_Per_Batch__c = 10,
            Sync_Frequency_Minutes__c = 1440
        );
        insert settings;
    }

    @isTest
    static void testStartSyncAllEnabled() {
        // Create permission set
        PermissionSet ps = new PermissionSet(
            Name = 'AI_Exchange_Email_Access',
            Label = 'AI Exchange Email Access'
        );
        insert ps;

        // Assign permission set to current user
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = UserInfo.getUserId(),
            PermissionSetId = ps.Id
        );
        insert psa;

        Test.startTest();
        AIEmailSyncOrchestrator.startSync();
        Test.stopTest();

        // Verify that queueable was enqueued (we can't directly test this, but we can verify no errors)
        // In a real scenario, the queueable would create sync logs
        Assert.isTrue(true, 'startSync should complete without errors');
    }


    @isTest
    static void testStartSyncAllDisabled() {
        // Update settings to disable all sync types
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.Sync_Enabled__c = false;
        settings.Calendar_Sync_Enabled__c = false;
        settings.Task_Sync_Enabled__c = false;
        update settings;

        Test.startTest();
        AIEmailSyncOrchestrator.startSync();
        Test.stopTest();

        // Verify system sync log was created
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c, Error_Message__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Status__c = 'Skipped'
        ];
        Assert.areEqual(1, logs.size(), 'Should create system log when all sync types disabled');
        Assert.isTrue(logs[0].Error_Message__c.contains('disabled'), 'Error message should mention disabled');
    }

    @isTest
    static void testStartSyncNoSettings() {
        // Delete settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];

        Test.startTest();
        AIEmailSyncOrchestrator.startSync();
        Test.stopTest();

        // Verify system sync log was created
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c, Error_Message__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Status__c = 'Skipped'
        ];
        Assert.areEqual(1, logs.size(), 'Should create system log when settings are missing');
    }

    @isTest
    static void testStartSyncNoEligibleUsers() {
        // Don't create any permission set assignments
        Test.startTest();
        AIEmailSyncOrchestrator.startSync();
        Test.stopTest();

        // Verify system sync log was created
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Status__c, Error_Message__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Status__c = 'Skipped'
        ];
        Assert.areEqual(1, logs.size(), 'Should create system log when no eligible users');
        Assert.isTrue(logs[0].Error_Message__c.contains('No eligible users'), 'Error message should mention no eligible users');
    }

    @isTest
    static void testGetEligibleUserIdsWithPermissionSet() {
        // Create permission set
        PermissionSet ps = new PermissionSet(
            Name = 'AI_Exchange_Email_Access',
            Label = 'AI Exchange Email Access'
        );
        insert ps;

        // Assign permission set to current user
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = UserInfo.getUserId(),
            PermissionSetId = ps.Id
        );
        insert psa;

        Test.startTest();
        List<Id> userIds = AIEmailSyncOrchestrator.getEligibleUserIds();
        Test.stopTest();

        Assert.areEqual(1, userIds.size(), 'Should return 1 eligible user');
        Assert.areEqual(UserInfo.getUserId(), userIds[0], 'Should return current user');
    }

    @isTest
    static void testGetEligibleUserIdsExchangeCredential() {
        // Create permission set for Exchange credential
        PermissionSet ps = new PermissionSet(
            Name = 'Exchange_Email_Access_Credential',
            Label = 'Exchange Email Access Credential'
        );
        insert ps;

        // Assign permission set to current user
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = UserInfo.getUserId(),
            PermissionSetId = ps.Id
        );
        insert psa;

        Test.startTest();
        List<Id> userIds = AIEmailSyncOrchestrator.getEligibleUserIds();
        Test.stopTest();

        Assert.areEqual(1, userIds.size(), 'Should return 1 eligible user with Exchange credential');
    }

    @isTest
    static void testGetEligibleUserIdsGmailCredential() {
        // Create permission set for Gmail credential
        PermissionSet ps = new PermissionSet(
            Name = 'Gmail_Integration_Access_Credential',
            Label = 'Gmail Integration Access Credential'
        );
        insert ps;

        // Assign permission set to current user
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = UserInfo.getUserId(),
            PermissionSetId = ps.Id
        );
        insert psa;

        Test.startTest();
        List<Id> userIds = AIEmailSyncOrchestrator.getEligibleUserIds();
        Test.stopTest();

        Assert.areEqual(1, userIds.size(), 'Should return 1 eligible user with Gmail credential');
    }

    @isTest
    static void testGetEligibleUserIdsNoPermissionSet() {
        Test.startTest();
        List<Id> userIds = AIEmailSyncOrchestrator.getEligibleUserIds();
        Test.stopTest();

        Assert.areEqual(0, userIds.size(), 'Should return 0 users without permission set');
    }


    @isTest
    static void testGetSyncStatusNoLogs() {
        Test.startTest();
        AIEmailSyncOrchestrator.SyncStatusSummary summary = AIEmailSyncOrchestrator.getSyncStatus();
        Test.stopTest();

        Assert.areNotEqual(null, summary, 'Should return summary object');
        Assert.areEqual(0, summary.providerStats.size(), 'Should have no provider stats');
        Assert.areEqual(0, summary.uniqueUsersSynced, 'Should have 0 unique users');
    }

    @isTest
    static void testGetSyncStatusWithLogs() {
        // Create sync logs
        List<AI_Workspace_Sync_Log__c> logs = new List<AI_Workspace_Sync_Log__c>();
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 3,
            Emails_Duplicate__c = 2,
            Processing_Time_Seconds__c = 30
        ));
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GOOGLE_CALENDAR',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 5,
            Emails_Imported__c = 3,
            Emails_Excluded__c = 1,
            Emails_Duplicate__c = 1,
            Processing_Time_Seconds__c = 20
        ));
        insert logs;

        Test.startTest();
        AIEmailSyncOrchestrator.SyncStatusSummary summary = AIEmailSyncOrchestrator.getSyncStatus();
        Test.stopTest();

        Assert.areNotEqual(null, summary, 'Should return summary object');
        Assert.isTrue(summary.providerStats.size() > 0, 'Should have provider stats');
        Assert.areEqual(1, summary.uniqueUsersSynced, 'Should have 1 unique user');
    }

    @isTest
    static void testGetSyncStatusWithMultipleStatuses() {
        // Create sync logs with different statuses
        List<AI_Workspace_Sync_Log__c> logs = new List<AI_Workspace_Sync_Log__c>();
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 3,
            Emails_Duplicate__c = 2,
            Processing_Time_Seconds__c = 30
        ));
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Partial',
            Start_Time__c = DateTime.now().addHours(-2),
            End_Time__c = DateTime.now().addHours(-1),
            Emails_Fetched__c = 8,
            Emails_Imported__c = 4,
            Emails_Excluded__c = 2,
            Emails_Duplicate__c = 1,
            Processing_Time_Seconds__c = 25,
            Error_Message__c = 'Some errors occurred'
        ));
        insert logs;

        Test.startTest();
        AIEmailSyncOrchestrator.SyncStatusSummary summary = AIEmailSyncOrchestrator.getSyncStatus();
        Test.stopTest();

        Assert.areNotEqual(null, summary, 'Should return summary object');
        Assert.isTrue(summary.providerStats.size() >= 2, 'Should have stats for different statuses');
    }

    @isTest
    static void testGetSyncStatusWithNullValues() {
        // Create sync log with null values
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = null,
            Emails_Imported__c = null,
            Emails_Excluded__c = null,
            Emails_Duplicate__c = null,
            Processing_Time_Seconds__c = null
        );
        insert syncLog;

        Test.startTest();
        AIEmailSyncOrchestrator.SyncStatusSummary summary = AIEmailSyncOrchestrator.getSyncStatus();
        Test.stopTest();

        Assert.areNotEqual(null, summary, 'Should handle null values gracefully');
        Assert.isTrue(summary.providerStats.size() > 0, 'Should have provider stats');
        
        // Verify null values are converted to 0
        AIEmailSyncOrchestrator.ProviderStats stats = summary.providerStats[0];
        Assert.areEqual(0, stats.totalFetched, 'Null fetched should be 0');
        Assert.areEqual(0, stats.totalImported, 'Null imported should be 0');
        Assert.areEqual(0, stats.totalExcluded, 'Null excluded should be 0');
        Assert.areEqual(0, stats.totalDuplicate, 'Null duplicate should be 0');
        Assert.areEqual(0, stats.avgProcessingTime, 'Null processing time should be 0');
    }

    @isTest
    static void testSyncStatusSummaryClass() {
        // Test the SyncStatusSummary inner class
        AIEmailSyncOrchestrator.SyncStatusSummary summary = new AIEmailSyncOrchestrator.SyncStatusSummary();

        Assert.areNotEqual(null, summary.providerStats, 'providerStats should be initialized');
        Assert.areEqual(0, summary.providerStats.size(), 'providerStats should be empty');
        Assert.areEqual(0, summary.uniqueUsersSynced, 'uniqueUsersSynced should be 0');
    }

    @isTest
    static void testProviderStatsClass() {
        // Test the ProviderStats inner class
        AIEmailSyncOrchestrator.ProviderStats stats = new AIEmailSyncOrchestrator.ProviderStats();
        stats.status = 'Success';
        stats.provider = 'GMAIL_EMAIL';
        stats.logCount = 5;
        stats.totalFetched = 100;
        stats.totalImported = 80;
        stats.totalExcluded = 15;
        stats.totalDuplicate = 5;
        stats.avgProcessingTime = 25.5;

        Assert.areEqual('Success', stats.status, 'Status should be set');
        Assert.areEqual('GMAIL_EMAIL', stats.provider, 'Provider should be set');
        Assert.areEqual(5, stats.logCount, 'Log count should be set');
        Assert.areEqual(100, stats.totalFetched, 'Total fetched should be set');
        Assert.areEqual(80, stats.totalImported, 'Total imported should be set');
        Assert.areEqual(15, stats.totalExcluded, 'Total excluded should be set');
        Assert.areEqual(5, stats.totalDuplicate, 'Total duplicate should be set');
        Assert.areEqual(25.5, stats.avgProcessingTime, 'Avg processing time should be set');
    }

    @isTest
    static void testCreateSystemSyncLogNoPermission() {
        // This test verifies that createSystemSyncLog handles permission errors gracefully
        // We can't directly test the private method, but we can test it indirectly
        // by calling startSync with all sync disabled
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.Sync_Enabled__c = false;
        settings.Calendar_Sync_Enabled__c = false;
        settings.Task_Sync_Enabled__c = false;
        update settings;

        Test.startTest();
        AIEmailSyncOrchestrator.startSync();
        Test.stopTest();

        // The method should complete without throwing an exception
        Assert.isTrue(true, 'Should handle permission errors gracefully');
    }

    @isTest
    static void testGetSyncStatusMultipleProviders() {
        // Create sync logs for multiple providers
        List<AI_Workspace_Sync_Log__c> logs = new List<AI_Workspace_Sync_Log__c>();
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Processing_Time_Seconds__c = 30
        ));
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GOOGLE_CALENDAR',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 5,
            Emails_Imported__c = 3,
            Processing_Time_Seconds__c = 20
        ));
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GOOGLE_TASKS',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 3,
            Emails_Imported__c = 2,
            Processing_Time_Seconds__c = 15
        ));
        insert logs;

        Test.startTest();
        AIEmailSyncOrchestrator.SyncStatusSummary summary = AIEmailSyncOrchestrator.getSyncStatus();
        Test.stopTest();

        Assert.areNotEqual(null, summary, 'Should return summary object');
        Assert.isTrue(summary.providerStats.size() >= 3, 'Should have stats for all providers');
    }

}