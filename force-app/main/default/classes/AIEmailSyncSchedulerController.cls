/**
 * EmailSyncSchedulerController - Apex controller for Email Sync Scheduler LWC
 * Provides methods to start, stop, and check status of the email sync scheduler
 */
public with sharing class AIEmailSyncSchedulerController {

    /**
     * Get current scheduler status and all settings
     * @return Map with scheduler status and settings information
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getSchedulerStatus() {
        try {
            Map<String, Object> result = new Map<String, Object>();

            // Get settings
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();

            // Scheduler settings
            result.put('syncEnabled', settings != null ? settings.Sync_Enabled__c : false);
            result.put('frequencyMinutes', settings != null ? settings.Sync_Frequency_Minutes__c : 60);

            // All Custom Metadata settings for display
            Map<String, Object> allSettings = new Map<String, Object>();
            if (settings != null && settings.Id != null) {
                // Email sync settings
                allSettings.put('syncEnabled', settings.Sync_Enabled__c);
                allSettings.put('frequencyMinutes', settings.Sync_Frequency_Minutes__c);
                allSettings.put('lookbackHours', settings.Lookback_Hours__c);
                allSettings.put('maxUsersPerBatch', settings.Max_Users_Per_Batch__c);
                allSettings.put('maxEmailsPerUser', settings.Max_Emails_Per_User__c);
                allSettings.put('notifyUsers', settings.Notify_Users__c);
                allSettings.put('queueableDelayMinutes', settings.Queueable_Delay_Minutes__c);
                allSettings.put('emailsPerBatch', settings.Emails_Per_Batch__c);
                // Calendar sync settings
                allSettings.put('calendarSyncEnabled', settings.Calendar_Sync_Enabled__c);
                allSettings.put('calendarLookbackDays', settings.Calendar_Lookback_Days__c);
                allSettings.put('calendarLookaheadDays', settings.Calendar_Lookahead_Days__c);
                allSettings.put('maxCalendarEventsPerUser', settings.Max_Calendar_Events_Per_User__c);
                // Task sync settings
                allSettings.put('taskSyncEnabled', settings.Task_Sync_Enabled__c);
                allSettings.put('maxTasksPerUser', settings.Max_Tasks_Per_User__c);
                allSettings.put('includeCompletedTasks', settings.Include_Completed_Tasks__c);
                // Provider enabled settings
                allSettings.put('outlookEnabled', settings.WS_Outlook_Enabled__c);
                allSettings.put('gmailEnabled', settings.WS_Gmail_Enabled__c);
                // Other settings
                allSettings.put('digestEnabled', settings.Digest_Enabled__c);
                allSettings.put('digestFrequency', settings.Digest_Frequency__c);
                allSettings.put('digestHour', settings.Digest_Hour__c);
            } else {
                // Defaults - Email
                allSettings.put('syncEnabled', false);
                allSettings.put('frequencyMinutes', 60);
                allSettings.put('lookbackHours', 24);
                allSettings.put('maxUsersPerBatch', 10);
                allSettings.put('maxEmailsPerUser', 50);
                allSettings.put('notifyUsers', false);
                allSettings.put('queueableDelayMinutes', 1);
                allSettings.put('emailsPerBatch', 20);
                // Defaults - Calendar
                allSettings.put('calendarSyncEnabled', false);
                allSettings.put('calendarLookbackDays', 7);
                allSettings.put('calendarLookaheadDays', 30);
                allSettings.put('maxCalendarEventsPerUser', 50);
                // Defaults - Task
                allSettings.put('taskSyncEnabled', false);
                allSettings.put('maxTasksPerUser', 50);
                allSettings.put('includeCompletedTasks', false);
                // Defaults - Provider enabled (NEW)
                allSettings.put('outlookEnabled', true);
                allSettings.put('gmailEnabled', true);
                // Defaults - Other
                allSettings.put('leadAutoCreateEnabled', false);
                allSettings.put('useSharedActivities', false);
                allSettings.put('digestEnabled', false);
                allSettings.put('digestFrequency', 'Daily');
                allSettings.put('digestHour', 8);
            }
            result.put('settings', allSettings);

            // Add calendar sync enabled to top level for highlight panel
            result.put('calendarSyncEnabled', settings != null ? settings.Calendar_Sync_Enabled__c : false);
            // Add task sync enabled to top level for highlight panel
            result.put('taskSyncEnabled', settings != null ? settings.Task_Sync_Enabled__c : false);

            // Get scheduled jobs
            List<CronTrigger> jobs = [
                SELECT Id, CronJobDetail.Name, NextFireTime, PreviousFireTime, State
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
                AND State NOT IN ('DELETED', 'COMPLETE')
                ORDER BY NextFireTime ASC
                LIMIT 1
            ];

            if (!jobs.isEmpty()) {
                CronTrigger job = jobs[0];
                result.put('isRunning', true);
                result.put('jobId', job.Id);
                result.put('jobName', job.CronJobDetail.Name);
                result.put('nextRunTime', job.NextFireTime);
                result.put('state', job.State);
            } else {
                result.put('isRunning', false);
                result.put('jobId', null);
                result.put('jobName', null);
                result.put('nextRunTime', null);
                result.put('state', 'NOT_SCHEDULED');
            }

            // Get last sync time from AI_Workspace_Sync_Log__c
            // Include Success, Partial, and Failed - any completed run counts as "last run"
            List<AI_Workspace_Sync_Log__c> recentLogs = [
                SELECT CreatedDate, End_Time__c
                FROM AI_Workspace_Sync_Log__c
                WHERE Status__c IN ('Success', 'Partial', 'Failed')
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!recentLogs.isEmpty()) {
                // Use End_Time if available, otherwise CreatedDate
                DateTime lastRun = recentLogs[0].End_Time__c != null 
                    ? recentLogs[0].End_Time__c 
                    : recentLogs[0].CreatedDate;
                result.put('lastRunTime', lastRun);
            } else {
                result.put('lastRunTime', null);
            }

            result.put('success', true);
            return result;

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * Wrapper class for sync log data (namespace-agnostic for managed package compatibility)
     */
    public class SyncLogWrapper {
        @AuraEnabled public Id Id { get; set; }
        @AuraEnabled public String Name { get; set; }
        @AuraEnabled public Id userId { get; set; }
        @AuraEnabled public String userName { get; set; }
        @AuraEnabled public String providerType { get; set; }
        @AuraEnabled public String syncType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public DateTime startTime { get; set; }
        @AuraEnabled public DateTime endTime { get; set; }
        @AuraEnabled public Decimal processingTimeSeconds { get; set; }
        @AuraEnabled public Decimal emailsFetched { get; set; }
        @AuraEnabled public Decimal emailsMatched { get; set; }
        @AuraEnabled public Decimal emailsImported { get; set; }
        @AuraEnabled public Decimal emailsDuplicate { get; set; }
        @AuraEnabled public Decimal emailsExcluded { get; set; }
        @AuraEnabled public Decimal emailsUnmatched { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
    }

    /**
     * Get recent sync logs for display
     * @param limitCount Number of records to return
     * @return List of sync log wrapper objects (namespace-agnostic)
     */
    @AuraEnabled(cacheable=false)
    public static List<SyncLogWrapper> getRecentSyncLogs(Integer limitCount) {
        if (limitCount == null || limitCount <= 0) {
            limitCount = 10;
        }
        if (limitCount > 50) {
            limitCount = 50;
        }

        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Id, Name, User__c, User__r.Name, Provider_Type__c, Sync_Type__c,
                   Status__c, Start_Time__c, End_Time__c, Processing_Time_Seconds__c,
                   Emails_Fetched__c, Emails_Matched__c, Emails_Imported__c,
                   Emails_Duplicate__c, Emails_Excluded__c, Emails_Unmatched__c,
                   Error_Message__c, CreatedDate
            FROM AI_Workspace_Sync_Log__c
            ORDER BY CreatedDate DESC
            LIMIT :limitCount
        ];

        List<SyncLogWrapper> wrappers = new List<SyncLogWrapper>();
        for (AI_Workspace_Sync_Log__c log : logs) {
            SyncLogWrapper wrapper = new SyncLogWrapper();
            wrapper.Id = log.Id;
            wrapper.Name = log.Name;
            wrapper.userId = log.User__c;
            wrapper.userName = log.User__r != null ? log.User__r.Name : null;
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
            wrappers.add(wrapper);
        }
        return wrappers;
    }
    
    /**
     * Get aggregate totals across ALL sync logs
     * This returns the sum of all emails fetched, matched, imported, etc.
     * regardless of pagination.
     * @return Map with total counts
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getSyncLogTotals() {
        // Use aggregate query to sum all numeric fields across ALL sync logs
        List<AggregateResult> results = [
            SELECT 
                SUM(Emails_Fetched__c) totalFetched,
                SUM(Emails_Matched__c) totalMatched,
                SUM(Emails_Imported__c) totalImported,
                SUM(Emails_Duplicate__c) totalDuplicate,
                SUM(Emails_Excluded__c) totalExcluded,
                SUM(Emails_Unmatched__c) totalUnmatched,
                COUNT(Id) totalLogs
            FROM AI_Workspace_Sync_Log__c
        ];
        
        Map<String, Object> totals = new Map<String, Object>();
        
        if (!results.isEmpty()) {
            AggregateResult agg = results[0];
            totals.put('totalFetched', agg.get('totalFetched') != null ? (Decimal) agg.get('totalFetched') : 0);
            totals.put('totalMatched', agg.get('totalMatched') != null ? (Decimal) agg.get('totalMatched') : 0);
            totals.put('totalImported', agg.get('totalImported') != null ? (Decimal) agg.get('totalImported') : 0);
            totals.put('totalDuplicate', agg.get('totalDuplicate') != null ? (Decimal) agg.get('totalDuplicate') : 0);
            totals.put('totalExcluded', agg.get('totalExcluded') != null ? (Decimal) agg.get('totalExcluded') : 0);
            totals.put('totalUnmatched', agg.get('totalUnmatched') != null ? (Decimal) agg.get('totalUnmatched') : 0);
            totals.put('totalLogs', agg.get('totalLogs') != null ? (Integer) agg.get('totalLogs') : 0);
        } else {
            totals.put('totalFetched', 0);
            totals.put('totalMatched', 0);
            totals.put('totalImported', 0);
            totals.put('totalDuplicate', 0);
            totals.put('totalExcluded', 0);
            totals.put('totalUnmatched', 0);
            totals.put('totalLogs', 0);
        }
        
        return totals;
    }

    /**
     * Start the email sync scheduler
     * @return Map with result status
     */
    @AuraEnabled
    public static Map<String, Object> startScheduler() {
        try {
            // Check if at least one sync type is enabled
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            Boolean emailEnabled = settings != null && settings.Sync_Enabled__c;
            Boolean calendarEnabled = settings != null && settings.Calendar_Sync_Enabled__c;
            Boolean taskEnabled = settings != null && settings.Task_Sync_Enabled__c;

            if (!emailEnabled && !calendarEnabled && !taskEnabled) {
                return new Map<String, Object>{
                    'success' => false,
                    'type' => 'warning',
                    'message' => 'Email, Calendar, and Task sync are all disabled. Please enable at least one sync type in AI Email Sync Settings before starting the scheduler.'
                };
            }

            AIEmailSyncScheduler.start();

            // Get updated status
            return getSchedulerStatus();

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * Stop the email sync scheduler
     * @return Map with result status
     */
    @AuraEnabled
    public static Map<String, Object> stopScheduler() {
        try {
            AIEmailSyncScheduler.stop();

            // Get updated status
            return getSchedulerStatus();

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * Check if a sync job is currently running for the current user
     * @return Boolean true if a job is running
     */
    @AuraEnabled
    public static Boolean isSyncJobRunning() {
        return getSyncJobStatus().isRunning;
    }
    
    /**
     * Wrapper class for sync job status
     */
    public class SyncJobStatus {
        @AuraEnabled public Boolean isRunning { get; set; }
        @AuraEnabled public Boolean isSchedulerActive { get; set; }
        @AuraEnabled public String jobId { get; set; }
        @AuraEnabled public String jobName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public String createdByName { get; set; }
        
        public SyncJobStatus() {
            this.isRunning = false;
            this.isSchedulerActive = false;
        }
    }
    
    /**
     * Get detailed status of any running sync jobs
     * Checks for both scheduled jobs and manual "Run Now" jobs
     * @return SyncJobStatus with details about running job
     */
    @AuraEnabled
    public static SyncJobStatus getSyncJobStatus() {
        SyncJobStatus result = new SyncJobStatus();
        
        // 1. Check if the scheduler (CronTrigger) is active
        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Email Auto-Sync%'
            AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ];
        result.isSchedulerActive = !scheduledJobs.isEmpty();
        
        // 2. Check for any running queueable jobs (org-wide, not just current user)
        // This prevents multiple concurrent syncs from different users
        List<AsyncApexJob> runningJobs = [
            SELECT Id, Status, ApexClass.Name, CreatedDate, CreatedBy.Name
            FROM AsyncApexJob
            WHERE Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            AND ApexClass.Name IN ('AIWorkspaceSyncQueueable', 'AIEmailSyncChainableQueueable', 'AIUserSyncQueueable', 'AIEmailSyncQueueable')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (!runningJobs.isEmpty()) {
            AsyncApexJob job = runningJobs[0];
            result.isRunning = true;
            result.jobId = job.Id;
            result.jobName = job.ApexClass.Name;
            result.status = job.Status;
            result.createdDate = job.CreatedDate;
            result.createdByName = job.CreatedBy.Name;
        }
        
        return result;
    }

    /**
     * Run sync immediately (one-time, without scheduling)
     * Uses workspace-based sync for current user only
     * @return Map with result status
     */
    @AuraEnabled
    public static Map<String, Object> runSyncNow() {
        try {
            // Get detailed job status
            SyncJobStatus jobStatus = getSyncJobStatus();
            
            // Check if the scheduler is running - if so, user should stop it first
            if (jobStatus.isSchedulerActive && jobStatus.isRunning) {
                String message = 'The scheduler is currently running a sync job';
                if (String.isNotBlank(jobStatus.createdByName)) {
                    message += ' (started by ' + jobStatus.createdByName + ')';
                }
                message += '. Please stop the scheduler first, then use Run Now.';
                
                return new Map<String, Object>{
                    'success' => false,
                    'type' => 'warning',
                    'message' => message,
                    'jobId' => jobStatus.jobId,
                    'jobStatus' => jobStatus.status
                };
            }
            
            // Check if any sync job is already running (from any user)
            if (jobStatus.isRunning) {
                String message = 'A sync job is already in progress';
                if (String.isNotBlank(jobStatus.createdByName)) {
                    message += ' (started by ' + jobStatus.createdByName + ')';
                }
                if (String.isNotBlank(jobStatus.jobId)) {
                    message += '. Job ID: ' + jobStatus.jobId;
                }
                message += '. Please wait until it finishes before starting a new one.';
                
                return new Map<String, Object>{
                    'success' => false,
                    'type' => 'warning',
                    'message' => message,
                    'jobId' => jobStatus.jobId,
                    'jobStatus' => jobStatus.status
                };
            }

            // Check if at least one sync type is enabled
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            Boolean emailEnabled = settings != null && settings.Sync_Enabled__c;
            Boolean calendarEnabled = settings != null && settings.Calendar_Sync_Enabled__c;
            Boolean taskEnabled = settings != null && settings.Task_Sync_Enabled__c;

            if (!emailEnabled && !calendarEnabled && !taskEnabled) {
                return new Map<String, Object>{
                    'success' => false,
                    'type' => 'warning',
                    'message' => 'Email, Calendar, and Task sync are all disabled. Please enable at least one sync type in AI Email Sync Settings before running sync.'
                };
            }
            
            // Check if user has a workspace connection
            if (!AIWorkspaceSyncOrchestrator.hasWorkspaceConnection()) {
                return new Map<String, Object>{
                    'success' => false,
                    'type' => 'warning',
                    'message' => 'No connected email provider found. Please connect your Outlook or Gmail account first.'
                };
            }

            // Use workspace-based sync for current user (uses stored refresh tokens)
            AIWorkspaceSyncOrchestrator.runNowForCurrentUser();

            // Build success message based on what's enabled
            List<String> enabledTypes = new List<String>();
            if (emailEnabled) enabledTypes.add('Email');
            if (calendarEnabled) enabledTypes.add('Calendar');
            if (taskEnabled) enabledTypes.add('Task');

            String syncTypes = String.join(enabledTypes, ', ');

            return new Map<String, Object>{
                'success' => true,
                'message' => syncTypes + ' sync started. Check Workspace Sync Log for results.'
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * Save settings to Custom Setting
     * Creates org defaults if they don't exist
     * @param settingsJson JSON string with settings to save
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> saveSettings(String settingsJson) {
        try {
            Map<String, Object> settingsMap = (Map<String, Object>) JSON.deserializeUntyped(settingsJson);
            
            // Get or create org defaults
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            if (settings == null || settings.Id == null) {
                settings = new AI_Workspace_Sync_Settings__c();
                settings.SetupOwnerId = UserInfo.getOrganizationId();
            }
            
            // Email sync settings
            if (settingsMap.containsKey('syncEnabled')) {
                settings.Sync_Enabled__c = (Boolean) settingsMap.get('syncEnabled');
            }
            if (settingsMap.containsKey('frequencyMinutes')) {
                settings.Sync_Frequency_Minutes__c = settingsMap.get('frequencyMinutes') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('frequencyMinutes'))) : null;
            }
            if (settingsMap.containsKey('lookbackHours')) {
                settings.Lookback_Hours__c = settingsMap.get('lookbackHours') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('lookbackHours'))) : null;
            }
            if (settingsMap.containsKey('maxUsersPerBatch')) {
                settings.Max_Users_Per_Batch__c = settingsMap.get('maxUsersPerBatch') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('maxUsersPerBatch'))) : null;
            }
            if (settingsMap.containsKey('maxEmailsPerUser')) {
                settings.Max_Emails_Per_User__c = settingsMap.get('maxEmailsPerUser') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('maxEmailsPerUser'))) : null;
            }
            if (settingsMap.containsKey('notifyUsers')) {
                settings.Notify_Users__c = (Boolean) settingsMap.get('notifyUsers');
            }
            if (settingsMap.containsKey('excludedDomains')) {
                settings.Excluded_Domains__c = (String) settingsMap.get('excludedDomains');
            }
            if (settingsMap.containsKey('excludedLabelsCategories')) {
                settings.Excluded_Labels_Categories__c = (String) settingsMap.get('excludedLabelsCategories');
            }
            // if (settingsMap.containsKey('excludeMarketing')) {
            //     settings.Exclude_Marketing__c = (Boolean) settingsMap.get('excludeMarketing');
            // }
            // if (settingsMap.containsKey('excludeConfidential')) {
            //     settings.Exclude_Confidential__c = (Boolean) settingsMap.get('excludeConfidential');
            // }
            // if (settingsMap.containsKey('excludeInternal')) {
            //     settings.Exclude_Internal__c = (Boolean) settingsMap.get('excludeInternal');
            // }
            // if (settingsMap.containsKey('internalDomains')) {
            //     settings.Internal_Domains__c = (String) settingsMap.get('internalDomains');
            // }
            // if (settingsMap.containsKey('excludePublicDomains')) {
            //     settings.Exclude_Public_Domains__c = (Boolean) settingsMap.get('excludePublicDomains');
            // }
            if (settingsMap.containsKey('queueableDelayMinutes')) {
                settings.Queueable_Delay_Minutes__c = settingsMap.get('queueableDelayMinutes') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('queueableDelayMinutes'))) : null;
            }
            if (settingsMap.containsKey('emailsPerBatch')) {
                settings.Emails_Per_Batch__c = settingsMap.get('emailsPerBatch') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('emailsPerBatch'))) : null;
            }
            
            // Calendar sync settings
            if (settingsMap.containsKey('calendarSyncEnabled')) {
                settings.Calendar_Sync_Enabled__c = (Boolean) settingsMap.get('calendarSyncEnabled');
            }
            if (settingsMap.containsKey('calendarLookbackDays')) {
                settings.Calendar_Lookback_Days__c = settingsMap.get('calendarLookbackDays') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('calendarLookbackDays'))) : null;
            }
            if (settingsMap.containsKey('calendarLookaheadDays')) {
                settings.Calendar_Lookahead_Days__c = settingsMap.get('calendarLookaheadDays') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('calendarLookaheadDays'))) : null;
            }
            if (settingsMap.containsKey('maxCalendarEventsPerUser')) {
                settings.Max_Calendar_Events_Per_User__c = settingsMap.get('maxCalendarEventsPerUser') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('maxCalendarEventsPerUser'))) : null;
            }
            
            // Task sync settings
            if (settingsMap.containsKey('taskSyncEnabled')) {
                settings.Task_Sync_Enabled__c = (Boolean) settingsMap.get('taskSyncEnabled');
            }
            if (settingsMap.containsKey('maxTasksPerUser')) {
                settings.Max_Tasks_Per_User__c = settingsMap.get('maxTasksPerUser') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('maxTasksPerUser'))) : null;
            }
            if (settingsMap.containsKey('includeCompletedTasks')) {
                settings.Include_Completed_Tasks__c = (Boolean) settingsMap.get('includeCompletedTasks');
            }
            
            // Provider enabled settings
            if (settingsMap.containsKey('outlookEnabled')) {
                settings.WS_Outlook_Enabled__c = (Boolean) settingsMap.get('outlookEnabled');
            }
            if (settingsMap.containsKey('gmailEnabled')) {
                settings.WS_Gmail_Enabled__c = (Boolean) settingsMap.get('gmailEnabled');
            }
            
            // Digest settings
            if (settingsMap.containsKey('digestEnabled')) {
                settings.Digest_Enabled__c = (Boolean) settingsMap.get('digestEnabled');
            }
            if (settingsMap.containsKey('digestFrequency')) {
                settings.Digest_Frequency__c = (String) settingsMap.get('digestFrequency');
            }
            if (settingsMap.containsKey('digestHour')) {
                settings.Digest_Hour__c = settingsMap.get('digestHour') != null ? 
                    Decimal.valueOf(String.valueOf(settingsMap.get('digestHour'))) : null;
            }
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Settings__c> settingsToUpsert = new List<AI_Workspace_Sync_Settings__c>{ settings };
            FLSCheck.getInstance().upsertDML(settingsToUpsert);
            
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Settings saved successfully',
                'settingsId' => settings.Id
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * Initialize default settings if none exist
     * @return Map with success status and whether settings were created
     */
    @AuraEnabled
    public static Map<String, Object> initializeDefaultSettings() {
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            
            if (settings != null && settings.Id != null) {
                return new Map<String, Object>{
                    'success' => true,
                    'created' => false,
                    'message' => 'Settings already exist'
                };
            }
            
            // Create new settings with defaults
            settings = new AI_Workspace_Sync_Settings__c();
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            
            // Email sync defaults
            settings.Sync_Enabled__c = false;
            settings.Sync_Frequency_Minutes__c = 60;
            settings.Lookback_Hours__c = 24;
            settings.Max_Users_Per_Batch__c = 10;
            settings.Max_Emails_Per_User__c = 50;
            settings.Emails_Per_Batch__c = 20;
            settings.Queueable_Delay_Minutes__c = 1;
            settings.Notify_Users__c = false;
            settings.Excluded_Domains__c = '';
            settings.Excluded_Labels_Categories__c = '';
            // settings.Exclude_Marketing__c = true;
            // settings.Exclude_Confidential__c = true;
            // settings.Exclude_Internal__c = true;
            // settings.Exclude_Public_Domains__c = true;
            
            // Calendar sync defaults
            settings.Calendar_Sync_Enabled__c = false;
            settings.Calendar_Lookback_Days__c = 7;
            settings.Calendar_Lookahead_Days__c = 30;
            settings.Max_Calendar_Events_Per_User__c = 50;
            
            // Task sync defaults
            settings.Task_Sync_Enabled__c = false;
            settings.Max_Tasks_Per_User__c = 50;
            settings.Include_Completed_Tasks__c = false;
            
            // Provider defaults
            settings.WS_Outlook_Enabled__c = true;
            settings.WS_Gmail_Enabled__c = true;
            
            // Other defaults
            settings.Digest_Enabled__c = false;
            settings.Digest_Frequency__c = 'Daily';
            settings.Digest_Hour__c = 8;
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Settings__c> settingsToInsert = new List<AI_Workspace_Sync_Settings__c>{ settings };
            FLSCheck.getInstance().insertDML(settingsToInsert);
            
            return new Map<String, Object>{
                'success' => true,
                'created' => true,
                'message' => 'Default settings created successfully',
                'settingsId' => settings.Id
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }
}