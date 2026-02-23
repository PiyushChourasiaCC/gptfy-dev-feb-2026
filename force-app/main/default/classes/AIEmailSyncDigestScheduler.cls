/**
 * EmailSyncDigestScheduler - Scheduled job to send daily/weekly digest emails
 *
 * Usage:
 *   // Start daily digest at 8 AM
 *   AIEmailSyncDigestScheduler.start();
 *
 *   // Stop the scheduler
 *   AIEmailSyncDigestScheduler.stop();
 *
 *   // Check status
 *   System.debug(AIEmailSyncDigestScheduler.status());
 *
 *   // Send digest manually (e.g., for testing)
 *   AIEmailSyncDigestScheduler.sendNow();
 */
public with sharing class AIEmailSyncDigestScheduler implements Schedulable {

    private static final String JOB_NAME_PREFIX = 'Email Sync Digest';

    /**
     * Schedulable execute method - called by Salesforce scheduler
     */
    public void execute(SchedulableContext ctx) {
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();

        if (settings == null || !settings.Digest_Enabled__c) {
            System.debug('Email sync digest is disabled');
            return;
        }

        // Calculate the time window based on frequency
        DateTime sinceDatetime = calculateSinceDateTime(settings);

        // Send digests
        Integer digestsSent = AIEmailSyncDigestService.sendDigestEmails(sinceDatetime);
        System.debug('Sent ' + digestsSent + ' digest emails');

        // Reschedule for next run
        rescheduleFromSettings(settings);
    }

    /**
     * Calculate the start of the digest window based on frequency setting
     */
    private DateTime calculateSinceDateTime(AI_Workspace_Sync_Settings__c settings) {
        String frequency = settings.Digest_Frequency__c;

        if (frequency == 'Weekly') {
            return DateTime.now().addDays(-7);
        } else {
            // Default to Daily
            return DateTime.now().addDays(-1);
        }
    }

    /**
     * Reschedule the job for the next run
     */
    private void rescheduleFromSettings(AI_Workspace_Sync_Settings__c settings) {
        // Abort current job if exists
        abortExistingJobs();

        if (!settings.Digest_Enabled__c) {
            return;
        }

        Integer digestHour = settings.Digest_Hour__c != null ? (Integer) settings.Digest_Hour__c : 8;
        String frequency = settings.Digest_Frequency__c != null ? settings.Digest_Frequency__c : 'Daily';

        // Build cron expression
        String cronExp;
        if (frequency == 'Weekly') {
            // Weekly on Monday at specified hour
            cronExp = '0 0 ' + digestHour + ' ? * MON';
        } else {
            // Daily at specified hour
            cronExp = '0 0 ' + digestHour + ' * * ?';
        }

        String jobName = JOB_NAME_PREFIX + ' - ' + frequency;
        System.schedule(jobName, cronExp, new AIEmailSyncDigestScheduler());
    }

    /**
     * Start the digest scheduler
     * Call this once to begin scheduled digests
     */
    public static void start() {
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();

        if (settings == null) {
            throw new DigestException('AI_Workspace_Sync_Settings__c.Default not configured');
        }

        // Abort any existing jobs first
        abortExistingJobs();

        Integer digestHour = settings.Digest_Hour__c != null ? (Integer) settings.Digest_Hour__c : 8;
        String frequency = settings.Digest_Frequency__c != null ? settings.Digest_Frequency__c : 'Daily';

        // Build cron expression
        String cronExp;
        if (frequency == 'Weekly') {
            cronExp = '0 0 ' + digestHour + ' ? * MON';
        } else {
            cronExp = '0 0 ' + digestHour + ' * * ?';
        }

        String jobName = JOB_NAME_PREFIX + ' - ' + frequency;
        System.schedule(jobName, cronExp, new AIEmailSyncDigestScheduler());

        System.debug('Email Sync Digest scheduled: ' + frequency + ' at hour ' + digestHour);
    }

    /**
     * Stop the digest scheduler
     */
    public static void stop() {
        abortExistingJobs();
        System.debug('Email Sync Digest scheduler stopped');
    }

    /**
     * Get current scheduler status
     */
    public static String status() {
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
            LIMIT 5
        ];

        if (jobs.isEmpty()) {
            return 'Not scheduled';
        }

        String result = 'Email Sync Digest Status:\n';
        for (CronTrigger job : jobs) {
            result += '- Job: ' + job.CronJobDetail.Name + '\n';
            result += '  State: ' + job.State + '\n';
            result += '  Next Fire: ' + (job.NextFireTime != null ? String.valueOf(job.NextFireTime) : 'N/A') + '\n';
            result += '  Previous Fire: ' + (job.PreviousFireTime != null ? String.valueOf(job.PreviousFireTime) : 'Never') + '\n';
        }

        return result;
    }

    /**
     * Send digest immediately (for testing or manual trigger)
     * Uses the last 24 hours as the window
     */
    public static Integer sendNow() {
        DateTime sinceDatetime = DateTime.now().addDays(-1);
        return AIEmailSyncDigestService.sendDigestEmails(sinceDatetime);
    }

    /**
     * Send digest for a specific time window
     */
    public static Integer sendForPeriod(DateTime sinceDatetime) {
        return AIEmailSyncDigestService.sendDigestEmails(sinceDatetime);
    }

    /**
     * Abort all existing digest scheduler jobs
     */
    private static void abortExistingJobs() {
        List<CronTrigger> existingJobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
        ];

        for (CronTrigger job : existingJobs) {
            System.abortJob(job.Id);
        }
    }

    /**
     * Custom exception for digest errors
     */
    public class DigestException extends Exception {}
}