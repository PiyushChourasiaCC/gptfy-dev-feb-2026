/**
 * EmailSyncOrchestrator - Coordinates the email, calendar, AND task sync process
 * Entry point from scheduler, determines eligible users and starts queueable chain.
 *
 * Smart Prioritization:
 * - Users who haven't been synced today are processed first
 * - This ensures all users get synced even if we can't process everyone in one run
 * - Users who were already synced today are added if capacity remains
 *
 * Combined Sync:
 * - Uses AIUserSyncQueueable which handles email, calendar, and task sync
 * - Each user is processed once per scheduled run (not multiple times)
 * - Reduces async job count significantly
 */
public with sharing class AIEmailSyncOrchestrator {

    /**
     * Start the sync process - called by scheduler
     * Handles email, calendar, and task sync based on settings
     */
    public static void startSync() {
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();

        Boolean emailEnabled = settings != null && settings.Sync_Enabled__c;
        Boolean calendarEnabled = settings != null && settings.Calendar_Sync_Enabled__c;
        Boolean taskEnabled = settings != null && settings.Task_Sync_Enabled__c;

        if (!emailEnabled && !calendarEnabled && !taskEnabled) {
            System.debug('Email, calendar, and task sync are all disabled');
            createSystemSyncLog('Skipped', 'Email, calendar, and task sync are all disabled in settings');
            return;
        }

        // Get eligible users with smart prioritization
        List<Id> userIds = getEligibleUserIds();

        if (userIds.isEmpty()) {
            System.debug('No eligible users for sync');
            createSystemSyncLog('Skipped', 'No eligible users found. Ensure users have AI_Exchange_Email_Access, Exchange_Email_Access_Credential, or Gmail_Integration_Access_Credential permission set assigned.');
            return;
        }

        String syncTypes = '';
        if (emailEnabled) syncTypes += 'email';
        if (calendarEnabled) syncTypes += (syncTypes.length() > 0 ? ' + calendar' : 'calendar');
        if (taskEnabled) syncTypes += (syncTypes.length() > 0 ? ' + task' : 'task');

        System.debug('Starting ' + syncTypes + ' sync for ' + userIds.size() + ' users');

        // Start combined queueable chain with first user
        System.enqueueJob(new AIUserSyncQueueable(userIds, 0));
    }

    /**
     * Get users who are eligible for sync.
     * Eligibility is based on:
     * 1. Permission Set Assignment (AI_Exchange_Email_Access, Exchange_Email_Access_Credential, or Gmail_Integration_Access_Credential)
     * 2. Active user status
     *
     * Prioritization:
     * - Users who haven't been synced today are processed first
     * - This ensures all users get synced even if we can't process everyone in one run
     * - Users who were already synced today are added if capacity remains
     *
     * OAuth authentication is checked later per-provider in AIEmailSyncService.
     */
    public static List<Id> getEligibleUserIds() {
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        Integer maxUsers = settings != null && settings.Max_Users_Per_Batch__c != null ?
            (Integer) settings.Max_Users_Per_Batch__c : 1000;

        // Get users with email-related permission sets
        // These permission sets grant access to email provider external credentials
        Set<Id> usersWithPermSet = new Set<Id>();

        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name IN (
                'AI_Exchange_Email_Access',           // Main Exchange permission set
                'Exchange_Email_Access_Credential',   // Credential-specific permission set
                'Gmail_Integration_Access_Credential' // Gmail credential permission set
            )
        ]) {
            usersWithPermSet.add(psa.AssigneeId);
        }

        if (usersWithPermSet.isEmpty()) {
            return new List<Id>();
        }

        // Get users who were successfully synced today (any provider)
        Set<Id> syncedToday = new Set<Id>();
        for (AI_Workspace_Sync_Log__c log : [
            SELECT User__c
            FROM AI_Workspace_Sync_Log__c
            WHERE CreatedDate = TODAY
            AND Status__c IN ('Success', 'Partial')
        ]) {
            syncedToday.add(log.User__c);
        }

        List<Id> eligibleUserIds = new List<Id>();

        // First: Get users NOT synced today (prioritize these)
        for (User u : [
            SELECT Id
            FROM User
            WHERE Id IN :usersWithPermSet
            AND IsActive = true
            AND Id NOT IN :syncedToday
            ORDER BY Id
            LIMIT :maxUsers
        ]) {
            eligibleUserIds.add(u.Id);
        }

        // If we have capacity, add users who were already synced today
        if (eligibleUserIds.size() < maxUsers && !syncedToday.isEmpty()) {
            Integer remainingCapacity = maxUsers - eligibleUserIds.size();
            for (User u : [
                SELECT Id
                FROM User
                WHERE Id IN :usersWithPermSet
                AND IsActive = true
                AND Id IN :syncedToday
                ORDER BY Id
                LIMIT :remainingCapacity
            ]) {
                eligibleUserIds.add(u.Id);
            }
        }

        return eligibleUserIds;
    }

    /**
     * Get sync status summary for admin dashboard
     */
    public static SyncStatusSummary getSyncStatus() {
        SyncStatusSummary summary = new SyncStatusSummary();

        // Get today's sync statistics
        AggregateResult[] results = [
            SELECT
                Status__c status,
                Provider_Type__c provider,
                COUNT(Id) logCount,
                SUM(Emails_Fetched__c) totalFetched,
                SUM(Emails_Imported__c) totalImported,
                SUM(Emails_Excluded__c) totalExcluded,
                SUM(Emails_Duplicate__c) totalDuplicate,
                AVG(Processing_Time_Seconds__c) avgProcessingTime
            FROM AI_Workspace_Sync_Log__c
            WHERE CreatedDate = TODAY
            GROUP BY Status__c, Provider_Type__c
        ];

        for (AggregateResult ar : results) {
            ProviderStats stats = new ProviderStats();
            stats.status = (String) ar.get('status');
            stats.provider = (String) ar.get('provider');
            stats.logCount = (Integer) ar.get('logCount');
            stats.totalFetched = ar.get('totalFetched') != null ? ((Decimal) ar.get('totalFetched')).intValue() : 0;
            stats.totalImported = ar.get('totalImported') != null ? ((Decimal) ar.get('totalImported')).intValue() : 0;
            stats.totalExcluded = ar.get('totalExcluded') != null ? ((Decimal) ar.get('totalExcluded')).intValue() : 0;
            stats.totalDuplicate = ar.get('totalDuplicate') != null ? ((Decimal) ar.get('totalDuplicate')).intValue() : 0;
            stats.avgProcessingTime = ar.get('avgProcessingTime') != null ? (Decimal) ar.get('avgProcessingTime') : 0;

            summary.providerStats.add(stats);
        }

        // Get unique users synced today
        summary.uniqueUsersSynced = [
            SELECT COUNT_DISTINCT(User__c)
            FROM AI_Workspace_Sync_Log__c
            WHERE CreatedDate = TODAY
        ][0].get('expr0') != null ? (Integer) [
            SELECT COUNT_DISTINCT(User__c) cnt
            FROM AI_Workspace_Sync_Log__c
            WHERE CreatedDate = TODAY
        ][0].get('cnt') : 0;

        return summary;
    }

    /**
     * Create a system-level sync log entry (not tied to a specific user).
     * Used for recording orchestrator-level events like "no users found".
     */
    private static void createSystemSyncLog(String status, String message) {
        try {
            AI_Workspace_Sync_Log__c log = new AI_Workspace_Sync_Log__c(
                Sync_Type__c = 'Scheduled',
                Status__c = status,
                Start_Time__c = DateTime.now(),
                End_Time__c = DateTime.now(),
                Error_Message__c = message
            );
            FLSCheck.getInstance().insertDML(new List<AI_Workspace_Sync_Log__c>{log});
            System.debug('Created system sync log: ' + status + ' - ' + message);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to create system sync log: ' + e.getMessage());
        }
    }

    /**
     * Wrapper class for sync status summary
     */
    public class SyncStatusSummary {
        @AuraEnabled public List<ProviderStats> providerStats { get; set; }
        @AuraEnabled public Integer uniqueUsersSynced { get; set; }

        public SyncStatusSummary() {
            this.providerStats = new List<ProviderStats>();
            this.uniqueUsersSynced = 0;
        }
    }

    /**
     * Wrapper class for provider statistics
     */
    public class ProviderStats {
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public Integer logCount { get; set; }
        @AuraEnabled public Integer totalFetched { get; set; }
        @AuraEnabled public Integer totalImported { get; set; }
        @AuraEnabled public Integer totalExcluded { get; set; }
        @AuraEnabled public Integer totalDuplicate { get; set; }
        @AuraEnabled public Decimal avgProcessingTime { get; set; }
    }
}