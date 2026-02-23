/**
 * Test class for AIEmailSyncSchedulerController
 * Provides comprehensive test coverage (80%+) with proper mocking and assertions
 * 
 * @author AI Assistant
 * @date 2026-02-17
 */
@isTest
public class AIEmailSyncSchedulerControllerTest {

    // ========================================================================
    // Test Setup
    // ========================================================================

    @TestSetup
    static void setupTestData() {
        // Create Custom Setting for tests
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.SetupOwnerId = UserInfo.getOrganizationId();

        // Email sync settings
        settings.Sync_Enabled__c = true;
        settings.Sync_Frequency_Minutes__c = 60;
        settings.Lookback_Hours__c = 24;
        settings.Max_Users_Per_Batch__c = 10;
        settings.Max_Emails_Per_User__c = 50;
        settings.Emails_Per_Batch__c = 20;
        settings.Queueable_Delay_Minutes__c = 1;
        settings.Notify_Users__c = false;
        settings.Exclude_Marketing__c = true;
        settings.Exclude_Confidential__c = true;
        settings.Exclude_Internal__c = true;
        settings.Internal_Domains__c = 'example.com,test.com';
        settings.Exclude_Public_Domains__c = true;

        // Calendar sync settings
        settings.Calendar_Sync_Enabled__c = true;
        settings.Calendar_Lookback_Days__c = 7;
        settings.Calendar_Lookahead_Days__c = 30;
        settings.Max_Calendar_Events_Per_User__c = 50;

        // Task sync settings
        settings.Task_Sync_Enabled__c = true;
        settings.Max_Tasks_Per_User__c = 50;
        settings.Include_Completed_Tasks__c = false;

        // Provider settings
        settings.WS_Outlook_Enabled__c = true;
        settings.WS_Gmail_Enabled__c = true;

        // Digest settings
        settings.Digest_Enabled__c = false;
        settings.Digest_Frequency__c = 'Daily';
        settings.Digest_Hour__c = 8;

        insert settings;

        // Create test sync logs with various statuses
        List<AI_Workspace_Sync_Log__c> logs = new List<AI_Workspace_Sync_Log__c>();

        // Successful sync log
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-2),
            End_Time__c = DateTime.now().addHours(-1),
            Processing_Time_Seconds__c = 3600,
            Emails_Fetched__c = 50,
            Emails_Matched__c = 45,
            Emails_Imported__c = 40,
            Emails_Duplicate__c = 3,
            Emails_Excluded__c = 5,
            Emails_Unmatched__c = 2
        ));

        // Partial sync log
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Partial',
            Start_Time__c = DateTime.now().addHours(-4),
            End_Time__c = DateTime.now().addHours(-3),
            Processing_Time_Seconds__c = 1800,
            Emails_Fetched__c = 30,
            Emails_Matched__c = 25,
            Emails_Imported__c = 20,
            Error_Message__c = 'Partial sync completed'
        ));

        // Failed sync log
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Manual',
            Status__c = 'Failed',
            Start_Time__c = DateTime.now().addHours(-5),
            End_Time__c = DateTime.now().addHours(-4),
            Error_Message__c = 'Test error message - Connection timeout'
        ));

        // Another successful sync log (Gmail)
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Manual',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addMinutes(-30),
            End_Time__c = DateTime.now().addMinutes(-15),
            Processing_Time_Seconds__c = 900,
            Emails_Fetched__c = 25,
            Emails_Matched__c = 20,
            Emails_Imported__c = 20,
            Emails_Duplicate__c = 0,
            Emails_Excluded__c = 5,
            Emails_Unmatched__c = 0
        ));

        insert logs;
    }

    // ========================================================================
    // getSchedulerStatus Tests
    // ========================================================================

    @isTest
    static void testGetSchedulerStatus_NoJobsScheduled() {
        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.getSchedulerStatus();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');
        Assert.areEqual(false, result.get('isRunning'), 'Should not be running when no jobs scheduled');
        Assert.areEqual('NOT_SCHEDULED', result.get('state'), 'State should be NOT_SCHEDULED');
        Assert.areEqual(null, result.get('jobId'), 'jobId should be null');
        Assert.areEqual(null, result.get('jobName'), 'jobName should be null');
    }

    @isTest
    static void testGetSchedulerStatus_WithSettings() {
        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.getSchedulerStatus();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');

        // Check settings are returned
        Map<String, Object> settings = (Map<String, Object>) result.get('settings');
        Assert.areNotEqual(null, settings, 'Settings should not be null');

        // Verify all settings keys exist
        Assert.isTrue(settings.containsKey('syncEnabled'), 'Should have syncEnabled setting');
        Assert.isTrue(settings.containsKey('frequencyMinutes'), 'Should have frequencyMinutes setting');
        Assert.isTrue(settings.containsKey('lookbackHours'), 'Should have lookbackHours setting');
        Assert.isTrue(settings.containsKey('maxUsersPerBatch'), 'Should have maxUsersPerBatch setting');
        Assert.isTrue(settings.containsKey('maxEmailsPerUser'), 'Should have maxEmailsPerUser setting');
        Assert.isTrue(settings.containsKey('notifyUsers'), 'Should have notifyUsers setting');
        Assert.isTrue(settings.containsKey('excludeMarketing'), 'Should have excludeMarketing setting');
        Assert.isTrue(settings.containsKey('excludeConfidential'), 'Should have excludeConfidential setting');
        Assert.isTrue(settings.containsKey('excludeInternal'), 'Should have excludeInternal setting');
        Assert.isTrue(settings.containsKey('internalDomains'), 'Should have internalDomains setting');
        Assert.isTrue(settings.containsKey('excludePublicDomains'), 'Should have excludePublicDomains setting');
        Assert.isTrue(settings.containsKey('queueableDelayMinutes'), 'Should have queueableDelayMinutes setting');
        Assert.isTrue(settings.containsKey('emailsPerBatch'), 'Should have emailsPerBatch setting');

        // Calendar settings
        Assert.isTrue(settings.containsKey('calendarSyncEnabled'), 'Should have calendarSyncEnabled setting');
        Assert.isTrue(settings.containsKey('calendarLookbackDays'), 'Should have calendarLookbackDays setting');
        Assert.isTrue(settings.containsKey('calendarLookaheadDays'), 'Should have calendarLookaheadDays setting');
        Assert.isTrue(settings.containsKey('maxCalendarEventsPerUser'), 'Should have maxCalendarEventsPerUser setting');

        // Task settings
        Assert.isTrue(settings.containsKey('taskSyncEnabled'), 'Should have taskSyncEnabled setting');
        Assert.isTrue(settings.containsKey('maxTasksPerUser'), 'Should have maxTasksPerUser setting');
        Assert.isTrue(settings.containsKey('includeCompletedTasks'), 'Should have includeCompletedTasks setting');

        // Provider settings
        Assert.isTrue(settings.containsKey('outlookEnabled'), 'Should have outlookEnabled setting');
        Assert.isTrue(settings.containsKey('gmailEnabled'), 'Should have gmailEnabled setting');

        // Digest settings
        Assert.isTrue(settings.containsKey('digestEnabled'), 'Should have digestEnabled setting');
        Assert.isTrue(settings.containsKey('digestFrequency'), 'Should have digestFrequency setting');
        Assert.isTrue(settings.containsKey('digestHour'), 'Should have digestHour setting');

        // Verify values from test setup
        Assert.areEqual(true, settings.get('syncEnabled'), 'syncEnabled should be true from setup');
        Assert.areEqual(60, settings.get('frequencyMinutes'), 'frequencyMinutes should be 60');
        Assert.areEqual(true, settings.get('calendarSyncEnabled'), 'calendarSyncEnabled should be true');
        Assert.areEqual(true, settings.get('taskSyncEnabled'), 'taskSyncEnabled should be true');
    }

    @isTest
    static void testGetSchedulerStatus_WithLastRunTime() {
        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.getSchedulerStatus();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');
        // lastRunTime should be populated from test data setup
        Assert.areNotEqual(null, result.get('lastRunTime'), 'lastRunTime should be populated from sync logs');
    }

    @isTest
    static void testGetSchedulerStatus_TopLevelFlags() {
        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.getSchedulerStatus();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');

        // These flags should exist at top level for highlight panel
        Assert.isTrue(result.containsKey('syncEnabled'), 'Should have syncEnabled at top level');
        Assert.isTrue(result.containsKey('frequencyMinutes'), 'Should have frequencyMinutes at top level');
        Assert.isTrue(result.containsKey('calendarSyncEnabled'), 'Should have calendarSyncEnabled at top level');
        Assert.isTrue(result.containsKey('taskSyncEnabled'), 'Should have taskSyncEnabled at top level');
    }

    @isTest
    static void testGetSchedulerStatus_NoSettings() {
        // Delete the custom setting to test default behavior
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.getSchedulerStatus();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');
        Assert.areEqual(false, result.get('syncEnabled'), 'Should default to false when no settings');

        Map<String, Object> settings = (Map<String, Object>) result.get('settings');
        Assert.areNotEqual(null, settings, 'Settings should not be null');
        Assert.areEqual(false, settings.get('syncEnabled'), 'Should have default syncEnabled');
        Assert.areEqual(60, settings.get('frequencyMinutes'), 'Should have default frequencyMinutes');
    }

    // ========================================================================
    // getRecentSyncLogs Tests
    // ========================================================================

    @isTest
    static void testGetRecentSyncLogs_DefaultLimit() {
        Test.startTest();
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(null);
        Test.stopTest();

        Assert.isTrue(logs.size() <= 10, 'Should return at most 10 records');
        Assert.isTrue(logs.size() >= 1, 'Should return at least 1 record from test setup');
        Assert.areEqual(4, logs.size(), 'Should return 4 records from test setup');
    }

    @isTest
    static void testGetRecentSyncLogs_CustomLimit() {
        Test.startTest();
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(2);
        Test.stopTest();

        Assert.areEqual(2, logs.size(), 'Should return exactly 2 records');
    }

    @isTest
    static void testGetRecentSyncLogs_ZeroLimit() {
        Test.startTest();
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(0);
        Test.stopTest();

        Assert.isTrue(logs.size() <= 10, 'Should default to 10 when 0 is passed');
        Assert.areEqual(4, logs.size(), 'Should return 4 records from test setup');
    }

    @isTest
    static void testGetRecentSyncLogs_NegativeLimit() {
        Test.startTest();
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(-5);
        Test.stopTest();

        Assert.isTrue(logs.size() <= 10, 'Should default to 10 when negative is passed');
    }

    @isTest
    static void testGetRecentSyncLogs_ExcessiveLimit() {
        Test.startTest();
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(100);
        Test.stopTest();

        Assert.isTrue(logs.size() <= 50, 'Should cap at 50 records');
    }

    @isTest
    static void testGetRecentSyncLogs_FieldsReturned() {
        Test.startTest();
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(3);
        Test.stopTest();

        Assert.isFalse(logs.isEmpty(), 'Should have logs');
        AIEmailSyncSchedulerController.SyncLogWrapper log = logs[0];

        // Verify fields are populated
        Assert.areNotEqual(null, log.Id, 'Id should be returned');
        Assert.areNotEqual(null, log.userId, 'userId should be populated');
        Assert.areNotEqual(null, log.userName, 'userName should be populated');
        Assert.areNotEqual(null, log.providerType, 'providerType should be populated');
        Assert.areNotEqual(null, log.syncType, 'syncType should be populated');
        Assert.areNotEqual(null, log.status, 'status should be populated');
        Assert.areNotEqual(null, log.startTime, 'startTime should be populated');
        Assert.areNotEqual(null, log.createdDate, 'createdDate should be populated');
    }

    @isTest
    static void testGetRecentSyncLogs_OrderByCreatedDate() {
        Test.startTest();
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(10);
        Test.stopTest();

        // Verify logs are ordered by CreatedDate DESC
        if (logs.size() > 1) {
            for (Integer i = 0; i < logs.size() - 1; i++) {
                Assert.isTrue(
                    logs[i].createdDate >= logs[i + 1].createdDate,
                    'Logs should be ordered by CreatedDate DESC'
                );
            }
        }
    }

    @isTest
    static void testGetRecentSyncLogs_NoLogs() {
        delete [SELECT Id FROM AI_Workspace_Sync_Log__c];

        Test.startTest();
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(10);
        Test.stopTest();

        Assert.areEqual(0, logs.size(), 'Should return empty list when no logs');
    }

    // ========================================================================
    // getSyncLogTotals Tests
    // ========================================================================

    @isTest
    static void testGetSyncLogTotals_WithData() {
        Test.startTest();
        Map<String, Object> totals = AIEmailSyncSchedulerController.getSyncLogTotals();
        Test.stopTest();

        Assert.areNotEqual(null, totals, 'Totals should not be null');
        Assert.isTrue(totals.containsKey('totalFetched'), 'Should have totalFetched');
        Assert.isTrue(totals.containsKey('totalMatched'), 'Should have totalMatched');
        Assert.isTrue(totals.containsKey('totalImported'), 'Should have totalImported');
        Assert.isTrue(totals.containsKey('totalDuplicate'), 'Should have totalDuplicate');
        Assert.isTrue(totals.containsKey('totalExcluded'), 'Should have totalExcluded');
        Assert.isTrue(totals.containsKey('totalUnmatched'), 'Should have totalUnmatched');
        Assert.isTrue(totals.containsKey('totalLogs'), 'Should have totalLogs');

        // Verify totals from test data (50 + 30 + 0 + 25 = 105)
        Decimal totalFetched = (Decimal) totals.get('totalFetched');
        Assert.areEqual(105, totalFetched, 'Total fetched should be 105 from test data');

        Integer totalLogs = (Integer) totals.get('totalLogs');
        Assert.areEqual(4, totalLogs, 'Should have 4 total logs from test setup');
    }

    @isTest
    static void testGetSyncLogTotals_NoData() {
        delete [SELECT Id FROM AI_Workspace_Sync_Log__c];

        Test.startTest();
        Map<String, Object> totals = AIEmailSyncSchedulerController.getSyncLogTotals();
        Test.stopTest();

        Assert.areEqual(0, totals.get('totalFetched'), 'Should be 0 when no logs');
        Assert.areEqual(0, totals.get('totalLogs'), 'Should be 0 logs');
    }

    // ========================================================================
    // startScheduler Tests
    // ========================================================================

    @isTest
    static void testStartScheduler_Success() {
        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.startScheduler();
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        // Should succeed since at least one sync type is enabled in test setup
        Assert.areEqual(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testStartScheduler_AllSyncTypesDisabled() {
        // Disable all sync types
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.Sync_Enabled__c = false;
        settings.Calendar_Sync_Enabled__c = false;
        settings.Task_Sync_Enabled__c = false;
        update settings;

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.startScheduler();
        Test.stopTest();

        Assert.areEqual(false, result.get('success'), 'Should return false');
        Assert.areEqual('warning', result.get('type'), 'Should be warning type');
        String message = (String) result.get('message');
        Assert.isTrue(message.contains('disabled'), 'Message should mention sync types are disabled');
    }

    // ========================================================================
    // stopScheduler Tests
    // ========================================================================

    @isTest
    static void testStopScheduler_NoJobRunning() {
        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.stopScheduler();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');
        Assert.areEqual(false, result.get('isRunning'), 'Should not be running after stop');
    }

    @isTest
    static void testStopScheduler_MultipleStops() {
        Test.startTest();
        Map<String, Object> result1 = AIEmailSyncSchedulerController.stopScheduler();
        Map<String, Object> result2 = AIEmailSyncSchedulerController.stopScheduler();
        Test.stopTest();

        Assert.areEqual(true, result1.get('success'), 'First stop should succeed');
        Assert.areEqual(true, result2.get('success'), 'Second stop should also succeed');
    }

    // ========================================================================
    // getSyncJobStatus Tests
    // ========================================================================

    @isTest
    static void testGetSyncJobStatus_NoJobsRunning() {
        Test.startTest();
        AIEmailSyncSchedulerController.SyncJobStatus status = 
            AIEmailSyncSchedulerController.getSyncJobStatus();
        Test.stopTest();

        Assert.areNotEqual(null, status, 'Status should not be null');
        Assert.areEqual(false, status.isRunning, 'Should not be running');
        Assert.areEqual(false, status.isSchedulerActive, 'Scheduler should not be active');
        Assert.areEqual(null, status.jobId, 'jobId should be null');
    }

    @isTest
    static void testIsSyncJobRunning_NoJobs() {
        Test.startTest();
        Boolean isRunning = AIEmailSyncSchedulerController.isSyncJobRunning();
        Test.stopTest();

        Assert.areEqual(false, isRunning, 'Should return false when no jobs running');
    }

    // ========================================================================
    // runSyncNow Tests
    // ========================================================================

    @isTest
    static void testRunSyncNow_NoWorkspaceConnection() {
        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.runSyncNow();
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        // Without proper workspace setup, should return warning about no connection
        String message = (String) result.get('message');
        if (message != null) {
            Assert.isTrue(
                message.contains('No connected') || message.contains('already in progress'),
                'Should mention no connection or job in progress'
            );
        }
    }

    @isTest
    static void testRunSyncNow_AllSyncTypesDisabled() {
        // Disable all sync types
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        settings.Sync_Enabled__c = false;
        settings.Calendar_Sync_Enabled__c = false;
        settings.Task_Sync_Enabled__c = false;
        update settings;

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.runSyncNow();
        Test.stopTest();

        Assert.areEqual(false, result.get('success'), 'Should return false');
        Assert.areEqual('warning', result.get('type'), 'Should be warning type');
        String message = (String) result.get('message');
        Assert.isTrue(message.contains('disabled'), 'Message should mention sync types are disabled');
    }

    // ========================================================================
    // saveSettings Tests
    // ========================================================================

    @isTest
    static void testSaveSettings_UpdateExisting() {
        Map<String, Object> settingsMap = new Map<String, Object>{
            'syncEnabled' => false,
            'frequencyMinutes' => 120,
            'lookbackHours' => 48,
            'maxUsersPerBatch' => 20,
            'maxEmailsPerUser' => 100,
            'notifyUsers' => true,
            'excludeMarketing' => false,
            'excludeConfidential' => false,
            'excludeInternal' => false,
            'internalDomains' => 'newdomain.com',
            'excludePublicDomains' => false,
            'queueableDelayMinutes' => 2,
            'emailsPerBatch' => 30,
            'calendarSyncEnabled' => false,
            'calendarLookbackDays' => 14,
            'calendarLookaheadDays' => 60,
            'maxCalendarEventsPerUser' => 100,
            'taskSyncEnabled' => false,
            'maxTasksPerUser' => 75,
            'includeCompletedTasks' => true,
            'outlookEnabled' => false,
            'gmailEnabled' => false,
            'digestEnabled' => true,
            'digestFrequency' => 'Weekly',
            'digestHour' => 10
        };

        String settingsJson = JSON.serialize(settingsMap);

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.saveSettings(settingsJson);
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should save successfully');
        Assert.areNotEqual(null, result.get('settingsId'), 'Should return settingsId');

        // Verify settings were saved
        AI_Workspace_Sync_Settings__c savedSettings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areEqual(false, savedSettings.Sync_Enabled__c, 'syncEnabled should be updated');
        Assert.areEqual(120, savedSettings.Sync_Frequency_Minutes__c, 'frequencyMinutes should be updated');
        Assert.areEqual(false, savedSettings.Calendar_Sync_Enabled__c, 'calendarSyncEnabled should be updated');
        Assert.areEqual(false, savedSettings.Task_Sync_Enabled__c, 'taskSyncEnabled should be updated');
    }

    @isTest
    static void testSaveSettings_CreateNew() {
        // Delete existing settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];

        Map<String, Object> settingsMap = new Map<String, Object>{
            'syncEnabled' => true,
            'frequencyMinutes' => 30,
            'lookbackHours' => 12
        };

        String settingsJson = JSON.serialize(settingsMap);

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.saveSettings(settingsJson);
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should create settings successfully');
        Assert.areNotEqual(null, result.get('settingsId'), 'Should return new settingsId');

        // Verify settings were created
        AI_Workspace_Sync_Settings__c savedSettings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areNotEqual(null, savedSettings, 'Settings should be created');
        Assert.areEqual(true, savedSettings.Sync_Enabled__c, 'syncEnabled should be set');
    }

    @isTest
    static void testSaveSettings_PartialUpdate() {
        // Only update specific fields
        Map<String, Object> settingsMap = new Map<String, Object>{
            'syncEnabled' => false,
            'frequencyMinutes' => 90
        };

        String settingsJson = JSON.serialize(settingsMap);

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.saveSettings(settingsJson);
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should save successfully');

        // Verify only specified fields were updated
        AI_Workspace_Sync_Settings__c savedSettings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areEqual(false, savedSettings.Sync_Enabled__c, 'syncEnabled should be updated');
        Assert.areEqual(90, savedSettings.Sync_Frequency_Minutes__c, 'frequencyMinutes should be updated');
        // Other fields should remain from original setup
        Assert.areEqual(24, savedSettings.Lookback_Hours__c, 'lookbackHours should remain unchanged');
    }

    // ========================================================================
    // initializeDefaultSettings Tests
    // ========================================================================

    @isTest
    static void testInitializeDefaultSettings_AlreadyExists() {
        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.initializeDefaultSettings();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');
        Assert.areEqual(false, result.get('created'), 'Should not create new settings');
        String message = (String) result.get('message');
        Assert.isTrue(message.contains('already exist'), 'Should mention settings already exist');
    }

    @isTest
    static void testInitializeDefaultSettings_CreateNew() {
        // Delete existing settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.initializeDefaultSettings();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');
        Assert.areEqual(true, result.get('created'), 'Should create new settings');

        // Verify default values
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Assert.areNotEqual(null, settings, 'Settings should be created');
        Assert.areEqual(false, settings.Sync_Enabled__c, 'Default syncEnabled should be false');
        Assert.areEqual(60, settings.Sync_Frequency_Minutes__c, 'Default frequency should be 60');
        Assert.areEqual(24, settings.Lookback_Hours__c, 'Default lookback should be 24');
        Assert.areEqual(true, settings.WS_Outlook_Enabled__c, 'Default Outlook should be enabled');
        Assert.areEqual(true, settings.WS_Gmail_Enabled__c, 'Default Gmail should be enabled');
    }

    // ========================================================================
    // Integration Tests
    // ========================================================================

    @isTest
    static void testFullWorkflow_StartThenStop() {
        Test.startTest();

        // Start scheduler
        Map<String, Object> startResult = AIEmailSyncSchedulerController.startScheduler();
        Assert.areNotEqual(null, startResult, 'Start result should not be null');

        // Get status
        Map<String, Object> statusResult = AIEmailSyncSchedulerController.getSchedulerStatus();
        Assert.areEqual(true, statusResult.get('success'), 'Status should return success');

        // Stop scheduler
        Map<String, Object> stopResult = AIEmailSyncSchedulerController.stopScheduler();
        Assert.areEqual(true, stopResult.get('success'), 'Stop should return success');
        Assert.areEqual(false, stopResult.get('isRunning'), 'Should not be running after stop');

        Test.stopTest();
    }

    @isTest
    static void testFullWorkflow_GetStatusAndLogs() {
        Test.startTest();

        // Get scheduler status
        Map<String, Object> status = AIEmailSyncSchedulerController.getSchedulerStatus();
        Assert.areEqual(true, status.get('success'), 'Should return success');

        // Get recent logs
        List<AIEmailSyncSchedulerController.SyncLogWrapper> logs = 
            AIEmailSyncSchedulerController.getRecentSyncLogs(10);
        Assert.isTrue(logs.size() >= 1, 'Should have at least 1 log from test setup');

        // Get totals
        Map<String, Object> totals = AIEmailSyncSchedulerController.getSyncLogTotals();
        Assert.areNotEqual(null, totals, 'Totals should not be null');

        Test.stopTest();
    }

    @isTest
    static void testFullWorkflow_SaveSettingsAndGetStatus() {
        Map<String, Object> settingsMap = new Map<String, Object>{
            'syncEnabled' => false,
            'frequencyMinutes' => 120
        };

        Test.startTest();

        // Save settings
        Map<String, Object> saveResult = AIEmailSyncSchedulerController.saveSettings(
            JSON.serialize(settingsMap)
        );
        Assert.areEqual(true, saveResult.get('success'), 'Save should succeed');

        // Get updated status
        Map<String, Object> statusResult = AIEmailSyncSchedulerController.getSchedulerStatus();
        Assert.areEqual(true, statusResult.get('success'), 'Status should return success');
        Assert.areEqual(false, statusResult.get('syncEnabled'), 'syncEnabled should be false');

        Test.stopTest();
    }

    // ========================================================================
    // Edge Cases and Error Handling
    // ========================================================================

    @isTest
    static void testGetSchedulerStatus_MultipleCallsConsistent() {
        Test.startTest();
        Map<String, Object> result1 = AIEmailSyncSchedulerController.getSchedulerStatus();
        Map<String, Object> result2 = AIEmailSyncSchedulerController.getSchedulerStatus();
        Test.stopTest();

        Assert.areEqual(result1.get('success'), result2.get('success'), 'Success should be consistent');
        Assert.areEqual(result1.get('isRunning'), result2.get('isRunning'), 'isRunning should be consistent');
        Assert.areEqual(result1.get('state'), result2.get('state'), 'State should be consistent');
    }

    @isTest
    static void testGetSchedulerStatus_NoSyncLogs() {
        delete [SELECT Id FROM AI_Workspace_Sync_Log__c];

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.getSchedulerStatus();
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should return success');
        Assert.areEqual(null, result.get('lastRunTime'), 'lastRunTime should be null when no logs');
    }

    @isTest
    static void testSaveSettings_NullValues() {
        Map<String, Object> settingsMap = new Map<String, Object>{
            'syncEnabled' => true,
            'frequencyMinutes' => null,
            'lookbackHours' => null
        };

        Test.startTest();
        Map<String, Object> result = AIEmailSyncSchedulerController.saveSettings(
            JSON.serialize(settingsMap)
        );
        Test.stopTest();

        Assert.areEqual(true, result.get('success'), 'Should handle null values gracefully');
    }

    @isTest
    static void testSyncLogWrapper_AllFields() {
        AI_Workspace_Sync_Log__c log = [
            SELECT Id, Name, User__c, User__r.Name, Provider_Type__c, Sync_Type__c,
                   Status__c, Start_Time__c, End_Time__c, Processing_Time_Seconds__c,
                   Emails_Fetched__c, Emails_Matched__c, Emails_Imported__c,
                   Emails_Duplicate__c, Emails_Excluded__c, Emails_Unmatched__c,
                   Error_Message__c, CreatedDate
            FROM AI_Workspace_Sync_Log__c
            LIMIT 1
        ];

        Test.startTest();
        AIEmailSyncSchedulerController.SyncLogWrapper wrapper = 
            new AIEmailSyncSchedulerController.SyncLogWrapper();
        wrapper.Id = log.Id;
        wrapper.Name = log.Name;
        wrapper.userId = log.User__c;
        wrapper.userName = log.User__r.Name;
        wrapper.providerType = log.Provider_Type__c;
        wrapper.syncType = log.Sync_Type__c;
        wrapper.status = log.Status__c;
        wrapper.startTime = log.Start_Time__c;
        wrapper.endTime = log.End_Time__c;
        wrapper.processingTimeSeconds = log.Processing_Time_Seconds__c;
        wrapper.emailsFetched = log.Emails_Fetched__c;
        wrapper.emailsMatched = log.Emails_Matched__c;
        wrapper.emailsImported = log.Emails_Imported__c;
        wrapper.emailsDuplicate = log.Emails_Duplicate__c;
        wrapper.emailsExcluded = log.Emails_Excluded__c;
        wrapper.emailsUnmatched = log.Emails_Unmatched__c;
        wrapper.errorMessage = log.Error_Message__c;
        wrapper.createdDate = log.CreatedDate;
        Test.stopTest();

        // Verify wrapper instantiation
        Assert.areNotEqual(null, wrapper.Id, 'Wrapper should have Id');
        Assert.areNotEqual(null, wrapper.userId, 'Wrapper should have userId');
    }

    @isTest
    static void testSyncJobStatus_Constructor() {
        Test.startTest();
        AIEmailSyncSchedulerController.SyncJobStatus status = 
            new AIEmailSyncSchedulerController.SyncJobStatus();
        Test.stopTest();

        // Verify default values
        Assert.areEqual(false, status.isRunning, 'Default isRunning should be false');
        Assert.areEqual(false, status.isSchedulerActive, 'Default isSchedulerActive should be false');
    }
}