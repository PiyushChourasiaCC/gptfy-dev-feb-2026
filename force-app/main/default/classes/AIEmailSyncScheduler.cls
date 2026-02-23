/**
 * AIEmailSyncScheduler - Schedulable entry point for automated email sync
 *
 * SELF-SCHEDULING: Uses Sync_Frequency_Minutes__c from Custom Metadata to
 * automatically reschedule itself at the configured interval.
 *
 * Usage:
 * Just call start() once - it will keep running based on settings:
 *   AIEmailSyncScheduler.start();
 *
 * To stop:
 *   AIEmailSyncScheduler.stop();
 *
 * The scheduler reads Sync_Frequency_Minutes__c and reschedules itself
 * after each execution. Change the setting to adjust frequency without
 * needing to manually reschedule.
 */
public with sharing class AIEmailSyncScheduler implements Schedulable {

    private static final String JOB_NAME = 'Email Auto-Sync';

    /**
     * Execute the scheduled job.
     * After running, reschedules itself based on Sync_Frequency_Minutes__c.
     */
    public void execute(SchedulableContext ctx) {
        // Load settings
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();

        if (settings == null) {
            System.debug('AI_Workspace_Sync_Settings__c.Default not configured. Stopping scheduler.');
            return;
        }

        // Check if sync is enabled
        if (!settings.Sync_Enabled__c) {
            System.debug('Email sync is disabled. Skipping this run but will reschedule.');
            // Still reschedule so it can pick up when enabled again
            rescheduleFromSettings(settings);
            return;
        }

        System.debug('Starting scheduled email sync at ' + DateTime.now());

        try {
            // Use workspace-based sync (processes all AI_Workspace_User__c records)
            AIWorkspaceSyncOrchestrator.startScheduledSync();
        } catch (Exception e) {
            System.debug('Error during sync: ' + e.getMessage());
        }

        // Reschedule for next run based on settings
        rescheduleFromSettings(settings);
    }

    /**
     * Reschedule the job based on Sync_Frequency_Minutes__c setting.
     * Uses System.scheduleBatch pattern with DateTime for precise scheduling.
     */
    private void rescheduleFromSettings(AI_Workspace_Sync_Settings__c settings) {
        Integer frequencyMinutes = (Integer) settings.Sync_Frequency_Minutes__c;
        if (frequencyMinutes == null || frequencyMinutes < 1) {
            frequencyMinutes = 60; // Default to hourly
        }

        // Calculate next run time
        DateTime nextRun = DateTime.now().addMinutes(frequencyMinutes);

        // Build CRON expression for specific datetime
        // Format: Seconds Minutes Hours DayOfMonth Month DayOfWeek Year
        String cronExp = '0 ' + nextRun.minute() + ' ' + nextRun.hour() + ' ' +
                         nextRun.day() + ' ' + nextRun.month() + ' ? ' + nextRun.year();

        // Schedule next run (use unique name with timestamp to avoid conflicts)
        String jobName = JOB_NAME + ' - ' + nextRun.format('HH:mm');

        try {
            // Abort any existing jobs with our prefix
            abortExistingJobs();

            // Schedule new job
            System.schedule(jobName, cronExp, new AIEmailSyncScheduler());
            System.debug('Rescheduled sync for: ' + nextRun + ' (every ' + frequencyMinutes + ' minutes)');
        } catch (Exception e) {
            System.debug('Error rescheduling: ' + e.getMessage());
        }
    }

    /**
     * Abort existing Email Auto-Sync jobs to prevent duplicates.
     */
    private static void abortExistingJobs() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
            AND State NOT IN ('DELETED', 'COMPLETE')
        ]) {
            try {
                System.abortJob(ct.Id);
            } catch (Exception e) {
                // Job may have already completed
            }
        }
    }

    /**
     * START the email sync scheduler.
     * Call this once - it will keep running based on Custom Metadata settings.
     *
     * Usage: AIEmailSyncScheduler.start();
     */
    public static void start() {
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();

        if (settings == null) {
            throw new EmailSyncException('AI_Workspace_Sync_Settings__c.Default must be configured first.');
        }

        Integer frequencyMinutes = (Integer) settings.Sync_Frequency_Minutes__c;
        if (frequencyMinutes == null || frequencyMinutes < 1) {
            frequencyMinutes = 60;
        }

        // Abort any existing jobs
        abortExistingJobs();

        // Schedule first run in 1 minute
        DateTime firstRun = DateTime.now().addMinutes(1);
        String cronExp = '0 ' + firstRun.minute() + ' ' + firstRun.hour() + ' ' +
                         firstRun.day() + ' ' + firstRun.month() + ' ? ' + firstRun.year();

        String jobName = JOB_NAME + ' - ' + firstRun.format('HH:mm');
        String jobId = System.schedule(jobName, cronExp, new AIEmailSyncScheduler());

        System.debug('Email sync scheduler started!');
        System.debug('First run: ' + firstRun);
        System.debug('Frequency: Every ' + frequencyMinutes + ' minutes');
        System.debug('Job ID: ' + jobId);
    }

    /**
     * STOP the email sync scheduler.
     *
     * Usage: AIEmailSyncScheduler.stop();
     */
    public static void stop() {
        Integer aborted = 0;
        for (CronTrigger ct : [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
            AND State NOT IN ('DELETED', 'COMPLETE')
        ]) {
            System.abortJob(ct.Id);
            aborted++;
            System.debug('Aborted: ' + ct.CronJobDetail.Name);
        }
        System.debug('Stopped ' + aborted + ' scheduled sync job(s).');
    }

    /**
     * Get current scheduler status.
     *
     * Usage: AIEmailSyncScheduler.status();
     */
    public static String status() {
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name, NextFireTime, PreviousFireTime, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
            AND State NOT IN ('DELETED', 'COMPLETE')
            ORDER BY NextFireTime ASC
            LIMIT 1
        ];

        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();

        String result = '=== Email Sync Scheduler Status ===\n';
        result += 'Sync Enabled: ' + (settings != null ? settings.Sync_Enabled__c : false) + '\n';
        result += 'Frequency: ' + (settings != null ? String.valueOf(settings.Sync_Frequency_Minutes__c) : 'N/A') + ' minutes\n';

        if (jobs.isEmpty()) {
            result += 'Status: NOT RUNNING\n';
            result += 'Run AIEmailSyncScheduler.start() to begin.\n';
        } else {
            CronTrigger job = jobs[0];
            result += 'Status: RUNNING\n';
            result += 'Next Run: ' + job.NextFireTime + '\n';
            result += 'Last Run: ' + (job.PreviousFireTime != null ? String.valueOf(job.PreviousFireTime) : 'Never') + '\n';
            result += 'Job ID: ' + job.Id + '\n';
        }

        System.debug(result);
        return result;
    }

    /**
     * Get scheduled job info for UI display.
     */
    public static List<ScheduledJobInfo> getScheduledJobs() {
        List<ScheduledJobInfo> jobInfos = new List<ScheduledJobInfo>();

        for (CronTrigger ct : [
            SELECT Id, CronJobDetail.Name, CronExpression, NextFireTime, PreviousFireTime, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
            AND State NOT IN ('DELETED', 'COMPLETE')
        ]) {
            ScheduledJobInfo info = new ScheduledJobInfo();
            info.jobId = ct.Id;
            info.jobName = ct.CronJobDetail.Name;
            info.cronExpression = ct.CronExpression;
            info.nextFireTime = ct.NextFireTime;
            info.previousFireTime = ct.PreviousFireTime;
            info.state = ct.State;
            jobInfos.add(info);
        }

        return jobInfos;
    }

    // Legacy methods for backwards compatibility
    public static String scheduleHourly() {
        start();
        return 'Started with settings-based frequency';
    }

    public static String scheduleWithCron(String jobName, String cronExpression) {
        return System.schedule(jobName, cronExpression, new AIEmailSyncScheduler());
    }

    public static void unschedule(String jobName) {
        stop();
    }

    /**
     * Wrapper class for scheduled job information
     */
    public class ScheduledJobInfo {
        @AuraEnabled public Id jobId { get; set; }
        @AuraEnabled public String jobName { get; set; }
        @AuraEnabled public String cronExpression { get; set; }
        @AuraEnabled public DateTime nextFireTime { get; set; }
        @AuraEnabled public DateTime previousFireTime { get; set; }
        @AuraEnabled public String state { get; set; }
    }

    public class EmailSyncException extends Exception {}
}