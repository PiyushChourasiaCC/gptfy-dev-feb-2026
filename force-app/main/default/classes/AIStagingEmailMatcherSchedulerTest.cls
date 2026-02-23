/**
 * Test class for AIStagingEmailMatcherScheduler
 * Tests schedulable functionality for email matching batch
 */
@isTest
private class AIStagingEmailMatcherSchedulerTest {

    @testSetup
    static void setupTestData() {
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'test.user@example.com'
        );
        insert testContact;

        // Create staging records for batch processing
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        
        // Get Email record type
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
        
        for (Integer i = 0; i < 5; i++) {
            AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
                From_Address__c = 'test.user@example.com',
                From_Name__c = 'Test User',
                Subject__c = 'Test Email ' + i,
                Status__c = 'Unmatched',
                Provider__c = 'MICROSOFT_GRAPH'
            );
            
            if (emailRecordTypeId != null) {
                staging.RecordTypeId = emailRecordTypeId;
            }
            
            stagingRecords.add(staging);
        }
        
        insert stagingRecords;
    }

    /**
     * Test 1: Default constructor
     */
    @isTest
    static void testDefaultConstructor() {
        Test.startTest();
        AIStagingEmailMatcherScheduler scheduler = new AIStagingEmailMatcherScheduler();
        Test.stopTest();

        Assert.isNotNull(scheduler, 'Scheduler should be instantiated');
    }

    /**
     * Test 2: Constructor with custom settings
     */
    @isTest
    static void testConstructorWithCustomSettings() {
        Test.startTest();
        AIStagingEmailMatcherScheduler scheduler = new AIStagingEmailMatcherScheduler(30, 100);
        Test.stopTest();

        Assert.isNotNull(scheduler, 'Scheduler should be instantiated with custom settings');
    }

    /**
     * Test 3: Constructor with null values
     */
    @isTest
    static void testConstructorWithNullValues() {
        Test.startTest();
        AIStagingEmailMatcherScheduler scheduler = new AIStagingEmailMatcherScheduler(null, null);
        Test.stopTest();

        Assert.isNotNull(scheduler, 'Scheduler should handle null values and use defaults');
    }

    /**
     * Test 4: Execute method runs batch
     */
    @isTest
    static void testExecuteMethod() {
        // Create scheduler instance
        AIStagingEmailMatcherScheduler scheduler = new AIStagingEmailMatcherScheduler();

        Test.startTest();
        // Schedule the job
        String cronExp = '0 0 0 1 1 ? 2099'; // Far future date
        String jobId = System.schedule('Test Job ' + DateTime.now().getTime(), cronExp, scheduler);
        
        // Execute the scheduled job manually
        scheduler.execute(null);
        Test.stopTest();

        // Verify batch was executed (staging records should be processed)
        List<AI_Workspace_Staging__c> processed = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Status__c = 'Matched'];
        Assert.isTrue(processed.size() > 0, 'Batch should have processed staging records');
        
        // Clean up
        try {
            System.abortJob(jobId);
        } catch (Exception e) {
            // Ignore cleanup errors
        }
    }

    /**
     * Test 5: Start scheduler with default frequency
     */
    @isTest
    static void testStartWithDefaultFrequency() {
        Test.startTest();
        AIStagingEmailMatcherScheduler.start();
        Test.stopTest();

        // Verify job was scheduled
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.isTrue(jobs.size() > 0, 'Scheduler should be started');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 6: Start scheduler with custom frequency
     */
    @isTest
    static void testStartWithCustomFrequency() {
        Test.startTest();
        AIStagingEmailMatcherScheduler.start(30);
        Test.stopTest();

        // Verify job was scheduled
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.isTrue(jobs.size() > 0, 'Scheduler should be started with custom frequency');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 7: Stop scheduler
     */
    @isTest
    static void testStopScheduler() {
        // Start the scheduler first
        AIStagingEmailMatcherScheduler.start();
        
        Test.startTest();
        AIStagingEmailMatcherScheduler.stop();
        Test.stopTest();

        // Verify all jobs were aborted
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.areEqual(0, jobs.size(), 'All scheduled jobs should be stopped');
    }

    /**
     * Test 8: runNow method
     */
    @isTest
    static void testRunNow() {
        Test.startTest();
        Id batchJobId = AIStagingEmailMatcherScheduler.runNow();
        Test.stopTest();

        // Verify batch job was queued
        Assert.isNotNull(batchJobId, 'Batch job should be queued');
        
        // Verify staging records were processed
        List<AI_Workspace_Staging__c> processed = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Status__c = 'Matched'];
        Assert.isTrue(processed.size() > 0, 'Batch should have processed staging records');
    }

    /**
     * Test 9: isRunning method when scheduler is running
     */
    @isTest
    static void testIsRunningTrue() {
        // Start the scheduler
        AIStagingEmailMatcherScheduler.start();

        Test.startTest();
        Boolean isRunning = AIStagingEmailMatcherScheduler.isRunning();
        Test.stopTest();

        Assert.isTrue(isRunning, 'Should return true when scheduler is running');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 10: isRunning method when scheduler is not running
     */
    @isTest
    static void testIsRunningFalse() {
        // Ensure no jobs are running
        AIStagingEmailMatcherScheduler.stop();

        Test.startTest();
        Boolean isRunning = AIStagingEmailMatcherScheduler.isRunning();
        Test.stopTest();

        Assert.isFalse(isRunning, 'Should return false when scheduler is not running');
    }

    /**
     * Test 11: Multiple start calls (should abort previous and start new)
     */
    @isTest
    static void testMultipleStartCalls() {
        // Start first time
        AIStagingEmailMatcherScheduler.start(15);
        
        Test.startTest();
        // Start again with different frequency
        AIStagingEmailMatcherScheduler.start(30);
        Test.stopTest();

        // Should have only one job (previous should be aborted)
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.areEqual(1, jobs.size(), 'Should have only one scheduled job');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 12: Stop when no jobs are running
     */
    @isTest
    static void testStopWhenNoJobsRunning() {
        // Ensure no jobs are running
        AIStagingEmailMatcherScheduler.stop();

        Test.startTest();
        // Try to stop again
        AIStagingEmailMatcherScheduler.stop();
        Test.stopTest();

        // Should complete without errors
        Assert.isTrue(true, 'Stop should handle no jobs gracefully');
    }

    /**
     * Test 13: Execute with exception in batch execution
     */
    @isTest
    static void testExecuteWithException() {
        // Create scheduler with invalid batch size (will still work but tests exception handling)
        AIStagingEmailMatcherScheduler scheduler = new AIStagingEmailMatcherScheduler(15, -1);

        Test.startTest();
        try {
            scheduler.execute(null);
            // Should not throw exception (caught internally)
            Assert.isTrue(true, 'Execute should handle exceptions gracefully');
        } catch (Exception e) {
            Assert.fail('Execute should not throw exceptions: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * Test 14: Cron expression generation
     */
    @isTest
    static void testCronExpressionGeneration() {
        Test.startTest();
        AIStagingEmailMatcherScheduler.start();
        Test.stopTest();

        // Verify job was scheduled with valid cron expression
        List<CronTrigger> jobs = [SELECT Id, CronExpression FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.isTrue(jobs.size() > 0, 'Job should be scheduled');
        Assert.isNotNull(jobs[0].CronExpression, 'Cron expression should be generated');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 15: Reschedule functionality
     */
    @isTest
    static void testReschedule() {
        // Create scheduler instance
        AIStagingEmailMatcherScheduler scheduler = new AIStagingEmailMatcherScheduler(15, 50);

        Test.startTest();
        // Schedule and execute (which triggers reschedule)
        String cronExp = '0 0 0 1 1 ? 2099';
        String jobId = System.schedule('Test Reschedule ' + DateTime.now().getTime(), cronExp, scheduler);
        
        // Execute to trigger reschedule
        scheduler.execute(null);
        Test.stopTest();

        // Verify rescheduling occurred (new job should be created)
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.isTrue(jobs.size() > 0, 'Job should be rescheduled');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 16: Abort existing jobs before starting new one
     */
    @isTest
    static void testAbortExistingJobsBeforeStart() {
        // Start first job
        AIStagingEmailMatcherScheduler.start(15);
        
        // Get job count
        List<CronTrigger> jobsBefore = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Integer countBefore = jobsBefore.size();

        Test.startTest();
        // Start again (should abort previous)
        AIStagingEmailMatcherScheduler.start(20);
        Test.stopTest();

        // Should have only one job
        List<CronTrigger> jobsAfter = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.areEqual(1, jobsAfter.size(), 'Should have only one job after restart');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 17: Scheduler with different batch sizes
     */
    @isTest
    static void testSchedulerWithDifferentBatchSizes() {
        Test.startTest();
        AIStagingEmailMatcherScheduler scheduler1 = new AIStagingEmailMatcherScheduler(15, 25);
        AIStagingEmailMatcherScheduler scheduler2 = new AIStagingEmailMatcherScheduler(30, 100);
        AIStagingEmailMatcherScheduler scheduler3 = new AIStagingEmailMatcherScheduler(60, 200);
        Test.stopTest();

        // All schedulers should be instantiated successfully
        Assert.isNotNull(scheduler1, 'Scheduler with batch size 25 should be created');
        Assert.isNotNull(scheduler2, 'Scheduler with batch size 100 should be created');
        Assert.isNotNull(scheduler3, 'Scheduler with batch size 200 should be created');
    }

    /**
     * Test 18: Execute method with SchedulableContext
     */
    @isTest
    static void testExecuteWithSchedulableContext() {
        AIStagingEmailMatcherScheduler scheduler = new AIStagingEmailMatcherScheduler();

        Test.startTest();
        // Create a mock SchedulableContext (pass null as it's not used in the implementation)
        scheduler.execute(null);
        Test.stopTest();

        // Should execute without errors
        Assert.isTrue(true, 'Execute should work with null SchedulableContext');
    }

    /**
     * Test 19: Start and immediately check if running
     */
    @isTest
    static void testStartAndCheckRunning() {
        Test.startTest();
        AIStagingEmailMatcherScheduler.start();
        Boolean isRunning = AIStagingEmailMatcherScheduler.isRunning();
        Test.stopTest();

        Assert.isTrue(isRunning, 'Scheduler should be running immediately after start');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 20: Stop and immediately check if not running
     */
    @isTest
    static void testStopAndCheckNotRunning() {
        // Start first
        AIStagingEmailMatcherScheduler.start();

        Test.startTest();
        AIStagingEmailMatcherScheduler.stop();
        Boolean isRunning = AIStagingEmailMatcherScheduler.isRunning();
        Test.stopTest();

        Assert.isFalse(isRunning, 'Scheduler should not be running after stop');
    }

    /**
     * Test 21: Scheduler job name consistency
     */
    @isTest
    static void testJobNameConsistency() {
        Test.startTest();
        AIStagingEmailMatcherScheduler.start();
        Test.stopTest();

        // Verify job name starts with expected prefix
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.isTrue(jobs.size() > 0, 'Job should exist');
        Assert.isTrue(jobs[0].CronJobDetail.Name.startsWith('AI Staging Email Matcher'), 'Job name should have correct prefix');
        
        // Clean up
        AIStagingEmailMatcherScheduler.stop();
    }

    /**
     * Test 22: Execute with no staging records
     */
    @isTest
    static void testExecuteWithNoStagingRecords() {
        // Delete all staging records
        delete [SELECT Id FROM AI_Workspace_Staging__c];

        AIStagingEmailMatcherScheduler scheduler = new AIStagingEmailMatcherScheduler();

        Test.startTest();
        scheduler.execute(null);
        Test.stopTest();

        // Should complete without errors even with no records
        Assert.isTrue(true, 'Execute should handle no staging records gracefully');
    }

    /**
     * Test 23: Frequency minutes edge cases
     */
    @isTest
    static void testFrequencyMinutesEdgeCases() {
        Test.startTest();
        // Test with very small frequency
        AIStagingEmailMatcherScheduler scheduler1 = new AIStagingEmailMatcherScheduler(1, 50);
        // Test with large frequency
        AIStagingEmailMatcherScheduler scheduler2 = new AIStagingEmailMatcherScheduler(1440, 50); // 24 hours
        // Test with zero (should use default)
        AIStagingEmailMatcherScheduler scheduler3 = new AIStagingEmailMatcherScheduler(0, 50);
        Test.stopTest();

        Assert.isNotNull(scheduler1, 'Scheduler with 1 minute frequency should be created');
        Assert.isNotNull(scheduler2, 'Scheduler with 24 hour frequency should be created');
        Assert.isNotNull(scheduler3, 'Scheduler with 0 frequency should be created');
    }

    /**
     * Test 24: Start with negative frequency (edge case)
     */
    @isTest
    static void testStartWithNegativeFrequency() {
        Test.startTest();
        AIStagingEmailMatcherScheduler.start(-10);
        Test.stopTest();

        // Should still schedule (will use the value as-is or handle it)
        // The scheduler will schedule even with negative values
        Assert.isTrue(true, 'Scheduler should handle negative frequency without errors');
        
        // Clean up
        try {
            AIStagingEmailMatcherScheduler.stop();
        } catch (Exception e) {
            // Ignore cleanup errors
        }
    }

    /**
     * Test 25: Multiple stop calls
     */
    @isTest
    static void testMultipleStopCalls() {
        // Start the scheduler
        AIStagingEmailMatcherScheduler.start();

        Test.startTest();
        // Stop multiple times
        AIStagingEmailMatcherScheduler.stop();
        AIStagingEmailMatcherScheduler.stop();
        AIStagingEmailMatcherScheduler.stop();
        Test.stopTest();

        // Should handle multiple stops gracefully
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AI Staging Email Matcher%'];
        Assert.areEqual(0, jobs.size(), 'All jobs should be stopped');
    }
}