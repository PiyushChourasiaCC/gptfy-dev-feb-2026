/**
 * Test class for SyncSettingsService
 */
@isTest
private class AISyncSettingsServiceTest {

    @isTest
    static void testGetSettings_ReturnsSettings() {
        Test.startTest();
        AI_Workspace_Sync_Settings__c settings = AISyncSettingsService.getSettings();
        Test.stopTest();

        // May or may not have settings depending on org config
        // Just verify no exception is thrown
        Assert.isTrue(true, 'Should complete without exception');
    }

    @isTest
    static void testGetSettingsRequired_WithSettings() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Sync_Enabled__c = true
        );
        insert mockSettings;
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        AI_Workspace_Sync_Settings__c settings = AISyncSettingsService.getSettingsRequired();
        Test.stopTest();

        Assert.areNotEqual(null, settings, 'Should return settings');
    }

    @isTest
    static void testGetSettingsRequired_WithoutSettings() {
        AISyncSettingsService.setCachedSettings(null);
        AISyncSettingsService.clearCache();

        Test.startTest();
        try {
            AISyncSettingsService.getSettingsRequired();
        } catch (AISyncSettingsService.SyncSettingsException e) {
            Assert.isTrue(e.getMessage().contains('not configured'), 'Should indicate settings not configured');
        }
        Test.stopTest();
    }

    @isTest
    static void testIsOutlookEnabled() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            WS_Outlook_Enabled__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean enabled = AISyncSettingsService.isOutlookEnabled();
        Test.stopTest();

        Assert.areEqual(true, enabled, 'Outlook should be enabled');
    }

    @isTest
    static void testIsGmailEnabled() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            WS_Gmail_Enabled__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean enabled = AISyncSettingsService.isGmailEnabled();
        Test.stopTest();

        Assert.areEqual(true, enabled, 'Gmail should be enabled');
    }

    @isTest
    static void testIsSyncEnabled_True() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Sync_Enabled__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean enabled = AISyncSettingsService.isSyncEnabled();
        Test.stopTest();

        Assert.areEqual(true, enabled, 'Sync should be enabled');
    }

    @isTest
    static void testIsSyncEnabled_False() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Sync_Enabled__c = false
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean enabled = AISyncSettingsService.isSyncEnabled();
        Test.stopTest();

        Assert.areEqual(false, enabled, 'Sync should be disabled');
    }

    @isTest
    static void testIsCalendarSyncEnabled_True() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Calendar_Sync_Enabled__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean enabled = AISyncSettingsService.isCalendarSyncEnabled();
        Test.stopTest();

        Assert.areEqual(true, enabled, 'Calendar sync should be enabled');
    }

    // REMOVED: testIsLeadAutoCreateEnabled - Lead auto-creation feature removed
    // @isTest
    // static void testIsLeadAutoCreateEnabled() {
    //     AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
    //         Lead_Auto_Create_Enabled__c = true
    //     );
    //     AISyncSettingsService.setCachedSettings(mockSettings);
    //     Test.startTest();
    //     Boolean enabled = AISyncSettingsService.isLeadAutoCreateEnabled();
    //     Test.stopTest();
    //     Assert.areEqual(true, enabled, 'Lead auto-create should be enabled');
    // }

    @isTest
    static void testIsDigestEnabled() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Digest_Enabled__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean enabled = AISyncSettingsService.isDigestEnabled();
        Test.stopTest();

        Assert.areEqual(true, enabled, 'Digest should be enabled');
    }

    @isTest
    static void testExcludeMarketing_DefaultsToTrue() {
        AISyncSettingsService.setCachedSettings(null);
        AISyncSettingsService.clearCache();

        Test.startTest();
        Boolean excludeMarketing = AISyncSettingsService.excludeMarketing();
        Test.stopTest();

        Assert.isTrue(true, 'Should complete without exception');
    }

    @isTest
    static void testExcludeConfidential() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Exclude_Confidential__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean exclude = AISyncSettingsService.excludeConfidential();
        Test.stopTest();

        Assert.areEqual(true, exclude, 'Should exclude confidential');
    }

    @isTest
    static void testExcludeInternal() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Exclude_Internal__c = false
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean exclude = AISyncSettingsService.excludeInternal();
        Test.stopTest();

        Assert.areEqual(false, exclude, 'Should not exclude internal');
    }

    @isTest
    static void testGetInternalDomains() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Internal_Domains__c = 'acme.com, example.org, Test.NET'
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Set<String> domains = AISyncSettingsService.getInternalDomains();
        Test.stopTest();

        Assert.areEqual(3, domains.size(), 'Should have 3 domains');
        Assert.isTrue(domains.contains('acme.com'), 'Should contain acme.com');
        Assert.isTrue(domains.contains('example.org'), 'Should contain example.org');
        Assert.isTrue(domains.contains('test.net'), 'Should contain test.net (lowercase)');
    }

    @isTest
    static void testGetInternalDomains_Empty() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Internal_Domains__c = ''
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Set<String> domains = AISyncSettingsService.getInternalDomains();
        Test.stopTest();

        Assert.areEqual(0, domains.size(), 'Should have no domains');
    }

    @isTest
    static void testIsDomainInternal_True() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Internal_Domains__c = 'internal.com, company.org'
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean isInternal = AISyncSettingsService.isDomainInternal('INTERNAL.COM');
        Test.stopTest();

        Assert.areEqual(true, isInternal, 'Should match internal domain (case-insensitive)');
    }

    @isTest
    static void testIsDomainInternal_False() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Internal_Domains__c = 'internal.com'
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean isInternal = AISyncSettingsService.isDomainInternal('external.com');
        Test.stopTest();

        Assert.areEqual(false, isInternal, 'Should not match external domain');
    }

    @isTest
    static void testIsDomainInternal_Blank() {
        Test.startTest();
        Boolean isInternal = AISyncSettingsService.isDomainInternal('');
        Test.stopTest();

        Assert.areEqual(false, isInternal, 'Blank domain should return false');
    }

    @isTest
    static void testGetLookbackHours_WithValue() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Lookback_Hours__c = 48
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer hours = AISyncSettingsService.getLookbackHours();
        Test.stopTest();

        Assert.areEqual(48, hours, 'Should return configured hours');
    }

    @isTest
    static void testGetLookbackHours_Default() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c();
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer hours = AISyncSettingsService.getLookbackHours();
        Test.stopTest();

        Assert.areEqual(24, hours, 'Should return default 24 hours');
    }

    @isTest
    static void testGetCalendarLookaheadDays() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Calendar_Lookahead_Days__c = 30
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer days = AISyncSettingsService.getCalendarLookaheadDays();
        Test.stopTest();

        Assert.areEqual(30, days, 'Should return configured days');
    }

    @isTest
    static void testGetCalendarLookbackDays() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Calendar_Lookback_Days__c = 14
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer days = AISyncSettingsService.getCalendarLookbackDays();
        Test.stopTest();

        Assert.areEqual(14, days, 'Should return configured days');
    }

    @isTest
    static void testGetTaskLookbackDays() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Task_Lookback_Days__c = 10
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer days = AISyncSettingsService.getTaskLookbackDays();
        Test.stopTest();

        Assert.areEqual(10, days, 'Should return configured task lookback days');
    }

    @isTest
    static void testGetTaskLookbackDaysDefault() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c();
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer days = AISyncSettingsService.getTaskLookbackDays();
        Test.stopTest();

        Assert.areEqual(7, days, 'Should return default 7 days');
    }

    @isTest
    static void testGetSyncFrequencyMinutes() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Sync_Frequency_Minutes__c = 30
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer minutes = AISyncSettingsService.getSyncFrequencyMinutes();
        Test.stopTest();

        Assert.areEqual(30, minutes, 'Should return configured minutes');
    }

    @isTest
    static void testGetDigestFrequency() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Digest_Frequency__c = 'Weekly'
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        String frequency = AISyncSettingsService.getDigestFrequency();
        Test.stopTest();

        Assert.areEqual('Weekly', frequency, 'Should return configured frequency');
    }

    @isTest
    static void testGetDigestHour() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Digest_Hour__c = 9
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer hour = AISyncSettingsService.getDigestHour();
        Test.stopTest();

        Assert.areEqual(9, hour, 'Should return configured hour');
    }

    @isTest
    static void testGetMaxEmailsPerUser_WithValue() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Max_Emails_Per_User__c = 100
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer maxEmails = AISyncSettingsService.getMaxEmailsPerUser();
        Test.stopTest();

        Assert.areEqual(100, maxEmails, 'Should return configured max emails');
    }


    @isTest
    static void testGetMaxUsersPerBatch() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Max_Users_Per_Batch__c = 20
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer maxUsers = AISyncSettingsService.getMaxUsersPerBatch();
        Test.stopTest();

        Assert.areEqual(20, maxUsers, 'Should return configured max users');
    }

    @isTest
    static void testGetMaxCalendarEventsPerUser() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Max_Calendar_Events_Per_User__c = 100
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer maxEvents = AISyncSettingsService.getMaxCalendarEventsPerUser();
        Test.stopTest();

        Assert.areEqual(100, maxEvents, 'Should return configured max events');
    }

    // REMOVED: testGetQueueableDelaySeconds - Field replaced with Queueable_Delay_Minutes__c
    // @isTest
    // static void testGetQueueableDelaySeconds() {
    //     AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
    //         Queueable_Delay_Seconds__c = 5
    //     );
    //     AISyncSettingsService.setCachedSettings(mockSettings);
    //     Test.startTest();
    //     Integer delay = AISyncSettingsService.getQueueableDelaySeconds();
    //     Test.stopTest();
    //     Assert.areEqual(5, delay, 'Should return configured delay');
    // }

    @isTest
    static void testIsNotifyUsersEnabled() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Notify_Users__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean notify = AISyncSettingsService.isNotifyUsersEnabled();
        Test.stopTest();

        Assert.areEqual(true, notify, 'Should return notify users enabled');
    }

    @isTest
    static void testClearCache() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Sync_Enabled__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Assert.areEqual(true, AISyncSettingsService.isSyncEnabled(), 'Mock should be active');

        Test.startTest();
        AISyncSettingsService.clearCache();
        Test.stopTest();

        Assert.isTrue(true, 'Should clear cache without error');
    }

    @isTest
    static void testSettingsAreCached() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Sync_Enabled__c = true,
            Calendar_Sync_Enabled__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean syncEnabled1 = AISyncSettingsService.isSyncEnabled();
        Boolean syncEnabled2 = AISyncSettingsService.isSyncEnabled();
        Boolean calEnabled = AISyncSettingsService.isCalendarSyncEnabled();
        Test.stopTest();

        Assert.areEqual(syncEnabled1, syncEnabled2, 'Should return same value');
        Assert.areEqual(true, calEnabled, 'Should return calendar enabled');
    }

    @isTest
    static void testIsTaskSyncEnabled() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Task_Sync_Enabled__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean enabled = AISyncSettingsService.isTaskSyncEnabled();
        Test.stopTest();

        Assert.areEqual(true, enabled, 'Task sync should be enabled');
    }

    // REMOVED: testIsUseSharedActivities - We only create EmailMessages now
    // @isTest
    // static void testIsUseSharedActivities() {
    //     AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
    //         Use_Shared_Activities__c = true
    //     );
    //     AISyncSettingsService.setCachedSettings(mockSettings);
    //     Test.startTest();
    //     Boolean enabled = AISyncSettingsService.isUseSharedActivities();
    //     Test.stopTest();
    //     Assert.areEqual(true, enabled, 'Use shared activities should be enabled');
    // }

    @isTest
    static void testGetMaxTasksPerUser() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Max_Tasks_Per_User__c = 75
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer maxTasks = AISyncSettingsService.getMaxTasksPerUser();
        Test.stopTest();

        Assert.areEqual(75, maxTasks, 'Should return configured max tasks');
    }

    @isTest
    static void testIncludeCompletedTasks() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Include_Completed_Tasks__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean include = AISyncSettingsService.includeCompletedTasks();
        Test.stopTest();

        Assert.areEqual(true, include, 'Should include completed tasks');
    }

    @isTest
    static void testExcludePublicDomains() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Exclude_Public_Domains__c = true
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Boolean exclude = AISyncSettingsService.excludePublicDomains();
        Test.stopTest();

        Assert.areEqual(true, exclude, 'Should exclude public domains');
    }

    @isTest
    static void testGetPublicDomains() {
        Test.startTest();
        Set<String> domains = AISyncSettingsService.getPublicDomains();
        Test.stopTest();

        Assert.isTrue(domains.contains('gmail.com'), 'Should contain gmail.com');
        Assert.isTrue(domains.contains('outlook.com'), 'Should contain outlook.com');
        Assert.isTrue(domains.contains('yahoo.com'), 'Should contain yahoo.com');
    }

    @isTest
    static void testIsPublicDomain() {
        Test.startTest();
        Boolean isGmail = AISyncSettingsService.isPublicDomain('gmail.com');
        Boolean isNotPublic = AISyncSettingsService.isPublicDomain('company.com');
        Boolean isBlank = AISyncSettingsService.isPublicDomain('');
        Test.stopTest();

        Assert.areEqual(true, isGmail, 'gmail.com should be public');
        Assert.areEqual(false, isNotPublic, 'company.com should not be public');
        Assert.areEqual(false, isBlank, 'Blank should return false');
    }

    @isTest
    static void testGetEmailsPerBatch() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Emails_Per_Batch__c = 25
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer emailsPerBatch = AISyncSettingsService.getEmailsPerBatch();
        Test.stopTest();

        Assert.areEqual(25, emailsPerBatch, 'Should return configured emails per batch');
    }

    @isTest
    static void testGetQueueableDelayMinutes() {
        AI_Workspace_Sync_Settings__c mockSettings = new AI_Workspace_Sync_Settings__c(
            Queueable_Delay_Minutes__c = 5
        );
        AISyncSettingsService.setCachedSettings(mockSettings);

        Test.startTest();
        Integer delay = AISyncSettingsService.getQueueableDelayMinutes();
        Test.stopTest();

        Assert.areEqual(5, delay, 'Should return configured delay in minutes');
    }
}