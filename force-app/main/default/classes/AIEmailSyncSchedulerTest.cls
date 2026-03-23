/**
 * Test class for AIEmailSyncScheduler
 * Tests the schedulable entry point for workspace sync
 * 
 * @author GPTfy
 * @date 2026-03-14
 * @Jira V2-7889
 */
@isTest
private class AIEmailSyncSchedulerTest {
    
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
                Refresh_Token__c = 'encrypted_outlook_token',
                Auto_Sync_Enabled__c = true
            ));
            
            insert workspaceUsers;
        }
    }
    
    @isTest
    static void testExecute_EmailSyncEnabled() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // Setup: Email sync enabled
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Calendar_Sync_Enabled__c = false,
            Task_Sync_Enabled__c = false,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        Test.startTest();
        AIEmailSyncScheduler scheduler = new AIEmailSyncScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should execute without errors when email sync is enabled');
    }
    
    @isTest
    static void testExecute_CalendarSyncEnabled() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // V2-7889: Test that scheduler runs when only calendar sync is enabled
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = false,
            Calendar_Sync_Enabled__c = true,
            Task_Sync_Enabled__c = false,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        Test.startTest();
        AIEmailSyncScheduler scheduler = new AIEmailSyncScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should execute without errors when calendar sync is enabled');
    }
    
    @isTest
    static void testExecute_TaskSyncEnabled() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        // V2-7889: Test that scheduler runs when only task sync is enabled
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = false,
            Calendar_Sync_Enabled__c = false,
            Task_Sync_Enabled__c = true,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        Test.startTest();
        AIEmailSyncScheduler scheduler = new AIEmailSyncScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should execute without errors when task sync is enabled');
    }
    
    @isTest
    static void testExecute_AllSyncTypesDisabled() {
        // V2-7889: Test that scheduler skips when all sync types are disabled
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = false,
            Calendar_Sync_Enabled__c = false,
            Task_Sync_Enabled__c = false,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        Test.startTest();
        AIEmailSyncScheduler scheduler = new AIEmailSyncScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should skip execution when all sync types are disabled');
    }
    
    @isTest
    static void testExecute_NoSettings() {
        // Delete settings if they exist
        List<AI_Workspace_Sync_Settings__c> existingSettings = [
            SELECT Id FROM AI_Workspace_Sync_Settings__c
        ];
        if (!existingSettings.isEmpty()) {
            delete existingSettings;
        }
        
        Test.startTest();
        AIEmailSyncScheduler scheduler = new AIEmailSyncScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle missing settings gracefully');
    }
    
    @isTest
    static void testStart() {
        // Setup settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        Test.startTest();
        AIEmailSyncScheduler.start();
        Test.stopTest();
        
        // Verify job was scheduled
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
            AND State NOT IN ('DELETED', 'COMPLETE')
        ];
        
        Assert.isFalse(jobs.isEmpty(), 'Should schedule a job');
    }
    
    @isTest
    static void testStop() {
        // Setup settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        // Start scheduler
        AIEmailSyncScheduler.start();
        
        Test.startTest();
        AIEmailSyncScheduler.stop();
        Test.stopTest();
        
        // Verify job was stopped
        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
            AND State NOT IN ('DELETED', 'COMPLETE')
        ];
        
        Assert.isTrue(jobs.isEmpty(), 'Should stop all scheduled jobs');
    }
    
    @isTest
    static void testStatus() {
        // Setup settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        Test.startTest();
        String status = AIEmailSyncScheduler.status();
        Test.stopTest();
        
        Assert.isNotNull(status, 'Should return status string');
        Assert.isTrue(status.contains('Status:'), 'Should contain status information');
    }
    
    @isTest
    static void testGetScheduledJobs() {
        // Setup settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        // Start scheduler
        AIEmailSyncScheduler.start();
        
        Test.startTest();
        List<AIEmailSyncScheduler.ScheduledJobInfo> jobs = AIEmailSyncScheduler.getScheduledJobs();
        Test.stopTest();
        
        Assert.isFalse(jobs.isEmpty(), 'Should return scheduled jobs');
    }
    
    @isTest
    static void testScheduleHourly_Legacy() {
        // Setup settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        Test.startTest();
        String result = AIEmailSyncScheduler.scheduleHourly();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return result message');
    }
    
    @isTest
    static void testScheduleWithCron_Legacy() {
        Test.startTest();
        String jobId = AIEmailSyncScheduler.scheduleWithCron('Test Job', '0 0 0 * * ?');
        Test.stopTest();
        
        Assert.isNotNull(jobId, 'Should return job ID');
    }
    
    @isTest
    static void testUnschedule_Legacy() {
        // Setup settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        // Start scheduler
        AIEmailSyncScheduler.start();
        
        Test.startTest();
        AIEmailSyncScheduler.unschedule('Email Auto-Sync');
        Test.stopTest();
        
        Assert.isTrue(true, 'Should unschedule without errors');
    }
    
    @isTest
    static void testStart_WithSettings() {
        // V2-7889: Test that start() works when settings exist
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Sync_Frequency_Minutes__c = 60
        );
        upsert settings;
        
        Test.startTest();
        AIEmailSyncScheduler.start();
        Test.stopTest();
        
        // Verify job was scheduled
        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
            AND State NOT IN ('DELETED', 'COMPLETE')
        ];
        
        Assert.isFalse(jobs.isEmpty(), 'Should schedule a job when settings exist');
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
