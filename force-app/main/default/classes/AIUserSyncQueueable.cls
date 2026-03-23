/**
 * AIUserSyncQueueable - Queueable for email, calendar, AND task sync
 *
 * Processes email, calendar, and task sync for each user in SEPARATE queueable jobs
 * to avoid hitting callout limits when multiple sync types are enabled.
 *
 * Design:
 * - One user + one sync type per queueable execution (respects callout limits)
 * - Chains: Email -> Calendar -> Task -> Next User's Email -> ...
 * - Each sync type gets fresh governor limits (100 callouts, 10s CPU, etc.)
 * - Graceful error handling - errors in one sync don't block the others
 */
public with sharing class AIUserSyncQueueable implements Queueable, Database.AllowsCallouts {

    // Sync type enum for cleaner code
    public enum SyncType { EMAIL, CALENDAR, TASK }

    private List<Id> userIds;
    private Integer currentIndex;
    private SyncType currentSyncType;

    // Test support: allows tests to disable chaining to prevent stack overflow
    @TestVisible
    private static Boolean disableChaining = false;

    /**
     * Constructor - starts with EMAIL sync for first user
     * @param userIds List of user IDs to process
     * @param startIndex Index to start processing from
     */
    public AIUserSyncQueueable(List<Id> userIds, Integer startIndex) {
        this.userIds = userIds;
        this.currentIndex = startIndex;
        this.currentSyncType = SyncType.EMAIL;
    }

    /**
     * Constructor with specific sync type
     * @param userIds List of user IDs to process
     * @param startIndex Index to start processing from
     * @param syncType The sync type to execute
     */
    public AIUserSyncQueueable(List<Id> userIds, Integer startIndex, SyncType syncType) {
        this.userIds = userIds;
        this.currentIndex = startIndex;
        this.currentSyncType = syncType;
    }

    /**
     * Execute the queueable job - processes ONE sync type for ONE user
     */
    public void execute(QueueableContext context) {
        if (userIds == null || userIds.isEmpty() || currentIndex >= userIds.size()) {
            return;
        }

        Id currentUserId = userIds[currentIndex];

        // Execute the current sync type
        switch on currentSyncType {
            when EMAIL {
                if (AISyncSettingsService.isSyncEnabled()) {
                    syncEmail(currentUserId);
                }
            }
            when CALENDAR {
                if (AISyncSettingsService.isCalendarSyncEnabled()) {
                    syncCalendar(currentUserId);
                }
            }
            when TASK {
                if (AISyncSettingsService.isTaskSyncEnabled()) {
                    syncTasks(currentUserId);
                }
            }
        }

        // Chain to next sync type or next user
        chainToNext();
    }

    /**
     * Sync email for the current user
     */
    private void syncEmail(Id userId) {
        try {
            AIEmailSyncService.syncUserEmails(userId);
        } catch (Exception e) {
            logSyncError(userId, 'MICROSOFT_EMAIL', 'Email', e);
        }
    }

    /**
     * Sync calendar for the current user
     */
    private void syncCalendar(Id userId) {
        try {
            AICalendarSyncService.syncUserCalendar(userId);
        } catch (Exception e) {
            logSyncError(userId, 'MICROSOFT_CALENDAR', 'Calendar', e);
        }
    }

    /**
     * Sync tasks for the current user
     */
    private void syncTasks(Id userId) {
        try {
            AITaskSyncService.syncUserTasks(userId);
        } catch (Exception e) {
            logSyncError(userId, 'MICROSOFT_TASKS', 'Task', e);
        }
    }

    /**
     * Log a sync error to AI_Workspace_Sync_Log__c
     */
    private void logSyncError(Id userId, String providerType, String recordType, Exception e) {
        try {
            if (!Schema.sObjectType.AI_Workspace_Sync_Log__c.isCreateable()) {
                return;
            }

            AI_Workspace_Sync_Log__c errorLog = new AI_Workspace_Sync_Log__c(
                User__c = userId,
                Sync_Type__c = 'Scheduled',
                Provider_Type__c = providerType,
                Record_Type__c = recordType,
                Status__c = 'Failed',
                Start_Time__c = DateTime.now(),
                End_Time__c = DateTime.now(),
                Error_Message__c = 'Queueable error: ' + e.getMessage() + '\n' + e.getStackTraceString()
            );
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ errorLog };
            FLSCheck.getInstance().insertDML(logsToInsert);
        } catch (Exception logError) {
        }
    }

    /**
     * Chain to the next sync type or next user
     * Order: EMAIL -> CALENDAR -> TASK -> (next user) EMAIL -> ...
     */
    private void chainToNext() {
        // Check if chaining is disabled (for tests) or if running in test context
        // In test context, we don't chain to avoid "Maximum stack depth" errors
        // since Test.stopTest() synchronously executes all enqueued jobs
        if (disableChaining || Test.isRunningTest()) {
            return;
        }

        // Determine next sync type and user index
        SyncType nextSyncType;
        Integer nextUserIndex = currentIndex;

        switch on currentSyncType {
            when EMAIL {
                // After Email, try Calendar
                if (AISyncSettingsService.isCalendarSyncEnabled()) {
                    nextSyncType = SyncType.CALENDAR;
                } else if (AISyncSettingsService.isTaskSyncEnabled()) {
                    nextSyncType = SyncType.TASK;
                } else {
                    // No Calendar or Task, move to next user
                    nextUserIndex = currentIndex + 1;
                    nextSyncType = SyncType.EMAIL;
                }
            }
            when CALENDAR {
                // After Calendar, try Task
                if (AISyncSettingsService.isTaskSyncEnabled()) {
                    nextSyncType = SyncType.TASK;
                } else {
                    // No Task, move to next user
                    nextUserIndex = currentIndex + 1;
                    nextSyncType = SyncType.EMAIL;
                }
            }
            when TASK {
                // After Task, move to next user
                nextUserIndex = currentIndex + 1;
                nextSyncType = SyncType.EMAIL;
            }
        }

        // Check if we should continue
        if (nextUserIndex >= userIds.size()) {
            return;
        }

        // Check if at least one sync type is enabled (for next user)
        if (nextUserIndex > currentIndex) {
            Boolean emailEnabled = AISyncSettingsService.isSyncEnabled();
            Boolean calendarEnabled = AISyncSettingsService.isCalendarSyncEnabled();
            Boolean taskEnabled = AISyncSettingsService.isTaskSyncEnabled();

            if (!emailEnabled && !calendarEnabled && !taskEnabled) {
                return;
            }

            // Find the first enabled sync type for the next user
            if (emailEnabled) {
                nextSyncType = SyncType.EMAIL;
            } else if (calendarEnabled) {
                nextSyncType = SyncType.CALENDAR;
            } else {
                nextSyncType = SyncType.TASK;
            }
        }

        // Get configured delay from settings service (in minutes)
        // Only apply delay when moving to the next user, not between sync types
        Integer delayMinutes = 0;
        if (nextUserIndex > currentIndex) {
            delayMinutes = AISyncSettingsService.getQueueableDelayMinutes();
        }

        // Enqueue next job
        AIUserSyncQueueable nextJob = new AIUserSyncQueueable(userIds, nextUserIndex, nextSyncType);
        if (delayMinutes > 0) {
            System.enqueueJob(nextJob, delayMinutes);
        } else {
            System.enqueueJob(nextJob);
        }

    }

    /**
     * Get the current progress of the sync chain
     */
    public Integer getCurrentIndex() {
        return this.currentIndex;
    }

    /**
     * Get total users to process
     */
    public Integer getTotalUsers() {
        return this.userIds != null ? this.userIds.size() : 0;
    }

    /**
     * Get the current sync type
     */
    public SyncType getCurrentSyncType() {
        return this.currentSyncType;
    }
}