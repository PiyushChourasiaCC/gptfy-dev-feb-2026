/**
 * AIEmailSyncQueueable - Processes email sync for users in a queueable chain
 * Each execution processes ONE user, then chains to the next.
 *
 * Design:
 * - One user per queueable execution (respects callout limits)
 * - Chains to next user after completion
 * - Configurable delay between executions (for org resource management)
 * - Graceful error handling - skips failed user and continues
 * 
 * Note: Uses 'without sharing' to ensure consistent access to org-wide 
 * AI_Workspace_Sync_Settings__c custom settings regardless of user permissions.
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public without sharing class AIEmailSyncQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> userIds;
    private Integer currentIndex;

    /**
     * Constructor
     * @param userIds List of user IDs to process
     * @param startIndex Index to start processing from
     */
    public AIEmailSyncQueueable(List<Id> userIds, Integer startIndex) {
        this.userIds = userIds;
        this.currentIndex = startIndex;
    }

    /**
     * Execute the queueable job
     */
    public void execute(QueueableContext context) {
        if (userIds == null || userIds.isEmpty() || currentIndex >= userIds.size()) {
            System.debug('Email sync chain complete. Processed ' + currentIndex + ' users.');
            return;
        }

        Id currentUserId = userIds[currentIndex];
        System.debug('Processing email sync for user index ' + currentIndex + ': ' + currentUserId);

        try {
            // Process sync for current user
            AIEmailSyncService.syncUserEmails(currentUserId);
        } catch (Exception e) {
            // Log error but don't stop the chain
            System.debug(LoggingLevel.ERROR, 'Error syncing user ' + currentUserId + ': ' + e.getMessage());

            // Create a failed sync log entry
            try {
                AI_Workspace_Sync_Log__c errorLog = new AI_Workspace_Sync_Log__c(
                    User__c = currentUserId,
                    Sync_Type__c = 'Scheduled',
                    Status__c = 'Failed',
                    Start_Time__c = DateTime.now(),
                    End_Time__c = DateTime.now(),
                    Error_Message__c = 'Queueable error: ' + e.getMessage() + '\n' + e.getStackTraceString()
                );
                
                // Use FLSCheck for security enforcement
                List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ errorLog };
                FLSCheck.getInstance().insertDML(logsToInsert);
            } catch (Exception logError) {
                System.debug(LoggingLevel.ERROR, 'Failed to create error log: ' + logError.getMessage());
            }
        }

        // Chain to next user
        chainToNextUser();
    }

    /**
     * Chain to process the next user
     */
    private void chainToNextUser() {
        Integer nextIndex = currentIndex + 1;

        if (nextIndex < userIds.size()) {
            // Check if sync is still enabled
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            if (settings == null || !settings.Sync_Enabled__c) {
                System.debug('Email sync disabled. Stopping chain at index ' + nextIndex);
                return;
            }

            // Get configured delay in minutes
            Integer delayMinutes = AISyncSettingsService.getQueueableDelayMinutes();

            // Enqueue next job with delay (delay parameter is in minutes)
            AIEmailSyncQueueable nextJob = new AIEmailSyncQueueable(userIds, nextIndex);
            if (delayMinutes > 0) {
                System.enqueueJob(nextJob, delayMinutes);
            } else {
                System.enqueueJob(nextJob);
            }

            System.debug('Chained to next user. Index: ' + nextIndex + ' of ' + userIds.size());
        } else {
            System.debug('Email sync chain complete. Processed all ' + userIds.size() + ' users.');
        }
    }

    /**
     * Get the current progress of the sync chain
     * Useful for monitoring
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
}