/**
 * TaskSyncService - Service for syncing Microsoft To-Do tasks to Salesforce Tasks
 *
 * This service imports tasks from Microsoft To-Do as Salesforce Task records.
 * Uses the Shared Activities pattern when enabled for multi-contact relationships.
 *
 * Key Features:
 * - Imports tasks from all Microsoft To-Do lists
 * - Deduplicates using external task ID
 * - Maps priority and status appropriately
 * - Creates sync log records for audit trail
 * - Supports partial success on bulk operations
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AITaskSyncService {

    // Custom field for task deduplication
    private static final String EXTERNAL_ID_FIELD = 'Workspace_Sync_Id__c';

    /**
     * Result wrapper for task sync operations
     */
    public class TaskSyncResult {
        @AuraEnabled public Integer tasksFetched { get; set; }
        @AuraEnabled public Integer tasksImported { get; set; }     // Actual Salesforce Task records created
        @AuraEnabled public Integer tasksDuplicate { get; set; }
        @AuraEnabled public Integer tasksMatched { get; set; }      // Matched to Lead/Contact
        @AuraEnabled public Integer tasksUnmatched { get; set; }    // Not matched to any Lead/Contact
        @AuraEnabled public Integer tasksFailed { get; set; }
        @AuraEnabled public List<String> errors { get; set; }
        @AuraEnabled public List<Id> taskIds { get; set; }
        @AuraEnabled public DateTime syncWindowStart { get; set; }
        @AuraEnabled public DateTime syncWindowEnd { get; set; }

        public TaskSyncResult() {
            this.tasksFetched = 0;
            this.tasksImported = 0;
            this.tasksDuplicate = 0;
            this.tasksMatched = 0;
            this.tasksUnmatched = 0;
            this.tasksFailed = 0;
            this.errors = new List<String>();
            this.taskIds = new List<Id>();
        }
    }

    /**
     * NEW: Entry point for workspace-based sync (with access token).
     * Used by AIWorkspaceSyncQueueable when syncing via stored refresh tokens.
     * Supports both Outlook (Microsoft To-Do) and Gmail (Google Tasks).
     * 
     * @param userId The user whose tasks should be synced
     * @param provider 'Outlook' or 'Gmail' (from AI_Workspace_User__c.Provider__c)
     * @param accessToken Fresh access token from OAuth refresh
     * @return TaskSyncResult with statistics and created Task IDs
     */
    public static TaskSyncResult syncUserTasksWithToken(Id userId, String provider, String accessToken) {
        return syncUserTasksWithToken(userId, provider, accessToken, false);
    }
    
    /**
     * Overloaded method with isRunNowMode parameter
     * NEW BEHAVIOR (2026-02-10):
     * - Run Now (first time): Uses lookback days from settings (defaults to 7 if empty/0)
     * - Run Now (subsequent): Uses last sync window end as start, current time as end
     * - Scheduler: Always uses lookback days from settings
     * 
     * @param userId The user whose tasks should be synced
     * @param provider 'Outlook' or 'Gmail' (from AI_Workspace_User__c.Provider__c)
     * @param accessToken Fresh access token from OAuth refresh
     * @param isRunNowMode True if triggered by Run Now button, false for scheduled sync
     * @return TaskSyncResult with statistics and created Task IDs
     */
    public static TaskSyncResult syncUserTasksWithToken(Id userId, String provider, String accessToken, Boolean isRunNowMode) {
        TaskSyncResult result = new TaskSyncResult();
        DateTime startTime = DateTime.now();
        String providerType = provider == 'Outlook' ? 'MICROSOFT_TASKS' : 'GOOGLE_TASKS';
        
        // Set sync window dates based on Task Lookback Days setting
        Integer lookbackDays = AISyncSettingsService.getTaskLookbackDays();
        
        // Validate lookback days to prevent invalid date ranges
        if (lookbackDays == null || lookbackDays <= 0) {
            lookbackDays = 7;
        }
        
        // Check if a prior sync log exists for this user + provider
        // Both Run Now and Scheduled modes use incremental sync after first run
        List<AI_Workspace_Sync_Log__c> existingLogs = [
            SELECT Id, Sync_Window_End__c
            FROM AI_Workspace_Sync_Log__c
            WHERE User__c = :userId
              AND Provider_Type__c = :providerType
              AND Record_Type__c = 'Task'
              AND Status__c IN ('Success', 'Partial')
            ORDER BY End_Time__c DESC
            LIMIT 1
        ];
        
        if (!existingLogs.isEmpty() && existingLogs[0].Sync_Window_End__c != null) {
            // Subsequent run (Run Now or Scheduled): Use last sync window end as start
            result.syncWindowStart = existingLogs[0].Sync_Window_End__c;
            result.syncWindowEnd = DateTime.now();
        } else {
            // First run (Run Now or Scheduled): Use lookback days setting
            result.syncWindowStart = DateTime.now().addDays(-lookbackDays);
            result.syncWindowEnd = DateTime.now();
        }
        
        // Check if task sync is enabled
        if (!AISyncSettingsService.isTaskSyncEnabled()) {
            result.errors.add('Task sync is not enabled');
            logSyncResultWithProvider(userId, 'Skipped', startTime, result, 'Task sync is not enabled', providerType);
            return result;
        }
        
        try {
            // Get settings
            Integer maxTasks = AISyncSettingsService.getMaxTasksPerUser();
            Boolean includeCompleted = AISyncSettingsService.includeCompletedTasks();
            
            // Fetch tasks using token-based fetch service WITH date filtering
            // Pass syncWindowStart and syncWindowEnd to filter tasks by lastModifiedDateTime
            List<Map<String, Object>> fetchedTasks;
            if (provider == 'Outlook') {
                fetchedTasks = AIOutlookFetchService.fetchTasks(accessToken, maxTasks, includeCompleted, result.syncWindowStart, result.syncWindowEnd);
            } else {
                fetchedTasks = AIGmailFetchService.fetchTasks(accessToken, maxTasks, includeCompleted, result.syncWindowStart, result.syncWindowEnd);
            }
            
            result.tasksFetched = fetchedTasks != null ? fetchedTasks.size() : 0;
            
            if (fetchedTasks == null || fetchedTasks.isEmpty()) {
                logSyncResultWithProvider(userId, 'Success', startTime, result, null, providerType);
                return result;
            }
            
            // Convert raw task maps to ToDoTask objects
            List<AIMicrosoftTaskService.ToDoTask> toDoTasks = convertToTaskObjects(fetchedTasks, provider);
            
            // Update Sync_Window_End__c to the date of the newest task fetched
            // This ensures the next sync starts from where we left off (not when the sync ran)
            DateTime newestTaskDate = findNewestTaskDate(toDoTasks);
            if (newestTaskDate != null) {
                result.syncWindowEnd = newestTaskDate;
            }
            
            // Deduplicate - check which tasks already exist
            DeduplicationResult dedupeResult = deduplicateTasks(toDoTasks);
            result.tasksDuplicate = dedupeResult.duplicateCount;
            
            if (dedupeResult.newTasks.isEmpty()) {
                logSyncResultWithProvider(userId, 'Success', startTime, result, null, providerType);
                return result;
            }
            
            // Import new tasks to staging
            // Use MICROSOFT_TASKS for Outlook, GOOGLE_TASKS for Gmail (matches picklist values)
            String stagingProviderType = provider == 'Outlook' ? 'MICROSOFT_TASKS' : 'GOOGLE_TASKS';
            // V2-7889: Phase 1 tracking - staging record creation only
            AIWorkspaceStagingCreator.StagingResult stagingResult =
                AIWorkspaceStagingCreator.createTaskStagingRecords(dedupeResult.newTasks, stagingProviderType, null, userId, false);
            result.tasksMatched = stagingResult.successCount;      // Successfully created staging records
            result.tasksUnmatched = stagingResult.failedCount;     // Failed to create staging records
            result.tasksImported = 0;  // Always 0 in Phase 1
            result.tasksFailed = 0;  // No failures in Phase 1
            result.errors.addAll(stagingResult.errors);
            result.taskIds = stagingResult.stagingRecordIds;
            
            // Log result
            String status = result.tasksFailed > 0 ? 'Partial' : 'Success';
            logSyncResultWithProvider(userId, status, startTime, result, null, providerType);
            
        } catch (Exception e) {
            result.errors.add(e.getMessage());
            logSyncResultWithProvider(userId, 'Failed', startTime, result, e.getMessage(), providerType);
        }
        
        return result;
    }
    
    /**
     * Convert raw task maps to ToDoTask objects
     * Handles both Outlook and Google Tasks formats
     * 
     * @param rawTasks List of task data maps from fetch service
     * @param provider 'Outlook' or 'Gmail'
     * @return List of ToDoTask objects
     */
    private static List<AIMicrosoftTaskService.ToDoTask> convertToTaskObjects(
        List<Map<String, Object>> rawTasks, 
        String provider
    ) {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();
        
        for (Map<String, Object> taskMap : rawTasks) {
            try {
                AIMicrosoftTaskService.ToDoTask t = new AIMicrosoftTaskService.ToDoTask();
                
                if (provider == 'Outlook') {
                    // Microsoft To-Do format
                    t.taskId = (String) taskMap.get('id');
                    t.listId = (String) taskMap.get('listId');
                    t.listName = (String) taskMap.get('listName');
                    t.title = (String) taskMap.get('title');
                    t.status = (String) taskMap.get('status');
                    t.importance = (String) taskMap.get('importance');
                    t.isReminderOn = taskMap.get('isReminderOn') == true;
                    
                    // Parse body
                    Map<String, Object> bodyMap = (Map<String, Object>) taskMap.get('body');
                    if (bodyMap != null) {
                        String content = (String) bodyMap.get('content');
                        String contentType = (String) bodyMap.get('contentType');
                        if (contentType == 'html' && String.isNotBlank(content)) {
                            t.body = content.stripHtmlTags();
                        } else {
                            t.body = content;
                        }
                    }
                    
                    // Parse dates
                    Map<String, Object> dueMap = (Map<String, Object>) taskMap.get('dueDateTime');
                    if (dueMap != null) {
                        t.dueDateTime = parseGraphDateTime((String) dueMap.get('dateTime'));
                    }
                    
                    Map<String, Object> completedMap = (Map<String, Object>) taskMap.get('completedDateTime');
                    if (completedMap != null) {
                        t.completedDateTime = parseGraphDateTime((String) completedMap.get('dateTime'));
                    }
                    
                    Map<String, Object> reminderMap = (Map<String, Object>) taskMap.get('reminderDateTime');
                    if (reminderMap != null) {
                        t.reminderDateTime = parseGraphDateTime((String) reminderMap.get('dateTime'));
                    }
                    
                    t.createdDateTime = parseSimpleDateTime((String) taskMap.get('createdDateTime'));
                    t.lastModifiedDateTime = parseSimpleDateTime((String) taskMap.get('lastModifiedDateTime'));
                    
                } else {
                    // Google Tasks format
                    t.taskId = (String) taskMap.get('id');
                    t.listId = (String) taskMap.get('listId');
                    t.listName = (String) taskMap.get('listTitle');
                    t.title = (String) taskMap.get('title');
                    t.body = (String) taskMap.get('notes');
                    
                    // Map Google status to Microsoft format
                    String googleStatus = (String) taskMap.get('status');
                    if (googleStatus == 'completed') {
                        t.status = 'completed';
                    } else {
                        t.status = 'notStarted';
                    }
                    
                    // Google Tasks don't have importance, default to normal
                    t.importance = 'normal';
                    
                    // Parse due date (Google uses RFC 3339 format)
                    String dueDateStr = (String) taskMap.get('due');
                    if (String.isNotBlank(dueDateStr)) {
                        t.dueDateTime = parseRfc3339DateTime(dueDateStr);
                    }
                    
                    // Parse completed date
                    String completedStr = (String) taskMap.get('completed');
                    if (String.isNotBlank(completedStr)) {
                        t.completedDateTime = parseRfc3339DateTime(completedStr);
                    }
                    
                    // Parse updated time
                    String updatedStr = (String) taskMap.get('updated');
                    if (String.isNotBlank(updatedStr)) {
                        t.lastModifiedDateTime = parseRfc3339DateTime(updatedStr);
                    }
                }
                
                t.provider = provider == 'Outlook' ? 'MICROSOFT_TASKS' : 'GOOGLE_TASKS';
                tasks.add(t);
                
            } catch (Exception e) {
                // Continue with other tasks
            }
        }
        
        return tasks;
    }
    
    /**
     * Parse Microsoft Graph datetime string
     */
    private static DateTime parseGraphDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }
        
        try {
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
            }
            dateTimeStr = dateTimeStr.replace('Z', '');
            return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Parse simple ISO datetime string
     */
    private static DateTime parseSimpleDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }
        
        try {
            if (dateTimeStr.contains('Z')) {
                dateTimeStr = dateTimeStr.replace('Z', '');
            }
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
            }
            return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Parse RFC 3339 datetime string (used by Google)
     */
    private static DateTime parseRfc3339DateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }
        
        try {
            // Handle timezone offset
            if (dateTimeStr.contains('+')) {
                dateTimeStr = dateTimeStr.substringBefore('+');
            } else if (dateTimeStr.endsWith('Z')) {
                dateTimeStr = dateTimeStr.removeEnd('Z');
            }
            
            // Handle milliseconds
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
            }
            
            return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Log sync result with specific provider type
     */
    private static void logSyncResultWithProvider(
        Id userId,
        String status,
        DateTime startTime,
        TaskSyncResult result,
        String errorMessage,
        String providerType
    ) {
        try {
            // Use specific provider type for Task sync (MICROSOFT_TASKS or GOOGLE_TASKS)
            String taskProviderType;
            if (providerType == 'MICROSOFT_TASKS') {
                taskProviderType = 'MICROSOFT_TASKS';
            } else if (providerType == 'GOOGLE_TASKS') {
                taskProviderType = 'GOOGLE_TASKS';
            } else {
                taskProviderType = providerType; // Use as-is if already specific
            }
            
            AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c();
            syncLog.User__c = userId;
            syncLog.Provider_Type__c = taskProviderType;
            syncLog.Record_Type__c = 'Task';
            syncLog.Sync_Type__c = 'Scheduled';
            syncLog.Status__c = status;
            syncLog.Start_Time__c = startTime;
            syncLog.End_Time__c = DateTime.now();
            syncLog.Sync_Window_Start__c = result.syncWindowStart;
            syncLog.Sync_Window_End__c = result.syncWindowEnd;
            syncLog.Processing_Time_Seconds__c =
                (syncLog.End_Time__c.getTime() - syncLog.Start_Time__c.getTime()) / 1000.0;

            // V2-7889: Phase 1 tracking - use email fields for task counts
            syncLog.Emails_Fetched__c = result.tasksFetched;
            syncLog.Emails_Matched__c = result.tasksMatched;      // Successfully created staging records
            syncLog.Emails_Duplicate__c = result.tasksDuplicate;
            syncLog.Emails_Unmatched__c = result.tasksUnmatched;  // Failed to create staging records
            syncLog.Emails_Excluded__c = 0;  // TODO: Add exclusion tracking for tasks
            syncLog.Emails_Imported__c = 0;  // Always 0 in Phase 1

            // Error handling
            if (String.isNotBlank(errorMessage)) {
                syncLog.Error_Message__c = AIExchangeEmailHelper.truncateField(errorMessage, 32000);
            } else if (!result.errors.isEmpty()) {
                syncLog.Error_Message__c = AIExchangeEmailHelper.truncateField(String.join(result.errors, '\n'), 32000);
            }

            FLSCheck.getInstance().insertDML(new List<AI_Workspace_Sync_Log__c>{syncLog});
        } catch (Exception e) {
            //ignore
        }
    }

    /**
     * Sync tasks for a user from Google Tasks
     * Entry point for Google task synchronization
     *
     * @param userId The user whose tasks should be synced
     * @return TaskSyncResult with statistics and created Task IDs
     */
    public static TaskSyncResult syncUserGoogleTasks(Id userId) {
        TaskSyncResult result = new TaskSyncResult();
        DateTime startTime = DateTime.now();

        // Set sync window dates based on Task Lookback Days setting
        Integer lookbackDays = AISyncSettingsService.getTaskLookbackDays();
        result.syncWindowStart = DateTime.now().addDays(-lookbackDays);
        result.syncWindowEnd = DateTime.now();

        // Check if task sync is enabled
        if (!AISyncSettingsService.isTaskSyncEnabled()) {
            result.errors.add('Task sync is not enabled');
            logSyncResultWithProvider(userId, 'Skipped', startTime, result, 'Task sync is not enabled', 'GOOGLE_TASKS');
            return result;
        }

        // Check if Google Tasks is accessible
        if (!AIGoogleTaskService.isTaskAccessible()) {
            result.errors.add('Google Tasks is not accessible - check authentication');
            logSyncResultWithProvider(userId, 'Skipped', startTime, result, 'Google Tasks not accessible', 'GOOGLE_TASKS');
            return result;
        }

        try {
            // Get settings
            Integer maxTasks = AISyncSettingsService.getMaxTasksPerUser();
            Boolean includeCompleted = AISyncSettingsService.includeCompletedTasks();

            // Fetch tasks from Google Tasks
            List<AIGoogleTaskService.ToDoTask> fetchedTasks =
                AIGoogleTaskService.getAllTasks(maxTasks, includeCompleted);

            result.tasksFetched = fetchedTasks.size();

            if (fetchedTasks.isEmpty()) {
                logSyncResultWithProvider(userId, 'Success', startTime, result, null, 'GOOGLE_TASKS');
                return result;
            }

            // Deduplicate - check which tasks already exist
            GoogleDeduplicationResult dedupeResult = deduplicateGoogleTasks(fetchedTasks);
            result.tasksDuplicate = dedupeResult.duplicateCount;

            if (dedupeResult.newTasks.isEmpty()) {
                logSyncResultWithProvider(userId, 'Success', startTime, result, null, 'GOOGLE_TASKS');
                return result;
            }

            // Import new tasks to staging
            AIWorkspaceStagingCreator.StagingResult stagingResult = 
                AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(dedupeResult.newTasks, userId, 'GOOGLE_TASKS', false);
            // V2-7889: Phase 1 tracking
            result.tasksMatched = stagingResult.successCount;      // Successfully created staging records
            result.tasksUnmatched = stagingResult.failedCount;     // Failed to create staging records
            result.tasksImported = 0;  // Always 0 in Phase 1
            result.tasksFailed = 0;  // No failures in Phase 1
            result.errors.addAll(stagingResult.errors);
            result.taskIds = stagingResult.stagingRecordIds;

            // Log result
            String status = result.tasksFailed > 0 ? 'Partial' : 'Success';
            logSyncResultWithProvider(userId, status, startTime, result, null, 'GOOGLE_TASKS');

        } catch (Exception e) {
            result.errors.add(e.getMessage());
            logSyncResultWithProvider(userId, 'Failed', startTime, result, e.getMessage(), 'GOOGLE_TASKS');
        }

        return result;
    }

    /**
     * Deduplication result wrapper for Google Tasks
     */
    private class GoogleDeduplicationResult {
        public List<AIGoogleTaskService.ToDoTask> newTasks { get; set; }
        public Integer duplicateCount { get; set; }

        public GoogleDeduplicationResult() {
            this.newTasks = new List<AIGoogleTaskService.ToDoTask>();
            this.duplicateCount = 0;
        }
    }

    /**
     * Deduplicate Google tasks against existing AI_Workspace_Staging__c records
     */
    private static GoogleDeduplicationResult deduplicateGoogleTasks(List<AIGoogleTaskService.ToDoTask> tasks) {
        GoogleDeduplicationResult result = new GoogleDeduplicationResult();

        // Collect external task IDs
        Set<String> externalIds = new Set<String>();
        for (AIGoogleTaskService.ToDoTask task : tasks) {
            if (String.isNotBlank(task.taskId)) {
                externalIds.add(task.taskId);
            }
        }

        // Query existing staging records with these external IDs
        Map<String, Id> existingIds = AIWorkspaceStagingCreator.getExistingTasksByProviderId(externalIds);

        // Filter out duplicates
        for (AIGoogleTaskService.ToDoTask task : tasks) {
            if (String.isBlank(task.taskId) || !existingIds.containsKey(task.taskId)) {
                result.newTasks.add(task);
            } else {
                result.duplicateCount++;
            }
        }

        return result;
    }

    /**
     * Sync tasks for a user from Microsoft To-Do
     * Main entry point for task synchronization
     *
     * @param userId The user whose tasks should be synced
     * @return TaskSyncResult with statistics and created Task IDs
     */
    public static TaskSyncResult syncUserTasks(Id userId) {
        TaskSyncResult result = new TaskSyncResult();
        DateTime startTime = DateTime.now();

        // Set sync window dates based on Task Lookback Days setting
        Integer lookbackDays = AISyncSettingsService.getTaskLookbackDays();
        
        // Validate lookback days to prevent invalid date ranges
        if (lookbackDays == null || lookbackDays <= 0) {
            lookbackDays = 7;
        }
        
        result.syncWindowStart = DateTime.now().addDays(-lookbackDays);
        result.syncWindowEnd = DateTime.now();

        // Check if task sync is enabled
        if (!AISyncSettingsService.isTaskSyncEnabled()) {
            result.errors.add('Task sync is not enabled');
            logSyncResult(userId, 'Skipped', startTime, result, 'Task sync is not enabled');
            return result;
        }

        // Check if Microsoft To-Do is accessible
        if (!AIMicrosoftTaskService.isTaskAccessible()) {
            result.errors.add('Microsoft To-Do is not accessible - check authentication');
            logSyncResult(userId, 'Skipped', startTime, result, 'Microsoft To-Do not accessible');
            return result;
        }

        try {
            // Get settings
            Integer maxTasks = AISyncSettingsService.getMaxTasksPerUser();
            Boolean includeCompleted = AISyncSettingsService.includeCompletedTasks();

            // Fetch tasks from Microsoft To-Do
            List<AIMicrosoftTaskService.ToDoTask> fetchedTasks =
                AIMicrosoftTaskService.getAllTasks(maxTasks, includeCompleted);

            result.tasksFetched = fetchedTasks.size();

            if (fetchedTasks.isEmpty()) {
                logSyncResult(userId, 'Success', startTime, result, null);
                return result;
            }

            // Deduplicate - check which tasks already exist
            DeduplicationResult dedupeResult = deduplicateTasks(fetchedTasks);
            result.tasksDuplicate = dedupeResult.duplicateCount;

            if (dedupeResult.newTasks.isEmpty()) {
                logSyncResult(userId, 'Success', startTime, result, null);
                return result;
            }

            // Import new tasks to staging (use MICROSOFT_TASKS to match picklist)
            AIWorkspaceStagingCreator.StagingResult stagingResult = 
                AIWorkspaceStagingCreator.createTaskStagingRecords(dedupeResult.newTasks, 'MICROSOFT_TASKS', null, userId, false);
            // V2-7889: Phase 1 tracking
            result.tasksMatched = stagingResult.successCount;      // Successfully created staging records
            result.tasksUnmatched = stagingResult.failedCount;     // Failed to create staging records
            result.tasksImported = 0;  // Always 0 in Phase 1
            result.tasksFailed = 0;  // No failures in Phase 1
            result.errors.addAll(stagingResult.errors);
            result.taskIds = stagingResult.stagingRecordIds;

            // Log result
            String status = result.tasksFailed > 0 ? 'Partial' : 'Success';
            logSyncResult(userId, status, startTime, result, null);

        } catch (Exception e) {
            result.errors.add(e.getMessage());
            logSyncResult(userId, 'Failed', startTime, result, e.getMessage());
        }

        return result;
    }

    /**
     * Processes a batch of raw tasks from Microsoft Graph (Delta Sync)
     */
    public static void processDeltaTasks(List<Object> rawTasks, Id userId) {
        if (rawTasks == null || rawTasks.isEmpty()) return;

        TaskSyncResult result = new TaskSyncResult();
        DateTime startTime = DateTime.now();

        try {
            // Convert to ToDoTask objects
            List<AIMicrosoftTaskService.ToDoTask> toDoTasks = new List<AIMicrosoftTaskService.ToDoTask>();
            for (Object obj : rawTasks) {
                Map<String, Object> taskMap = (Map<String, Object>) obj;
                AIMicrosoftTaskService.ToDoTask t = new AIMicrosoftTaskService.ToDoTask();
                t.taskId = (String) taskMap.get('id');
                t.title = (String) taskMap.get('title');
                t.status = (String) taskMap.get('status');
                t.importance = (String) taskMap.get('importance');
                t.isReminderOn = (Boolean) taskMap.get('isReminderOn');
                
                // Parse dates if present (simplified)
                if (taskMap.containsKey('dueDateTime')) {
                     Map<String, Object> dueMap = (Map<String, Object>) taskMap.get('dueDateTime');
                     String dtStr = (String) dueMap.get('dateTime');
                     if (dtStr != null) t.dueDateTime = (DateTime) JSON.deserialize('"' + dtStr + '"', DateTime.class);
                }
                
                String bodyContent = '';
                if (taskMap.containsKey('body')) {
                    Map<String, Object> bodyMap = (Map<String, Object>) taskMap.get('body');
                    bodyContent = (String) bodyMap.get('content');
                }
                t.body = bodyContent;

                toDoTasks.add(t);
            }
            
            result.tasksFetched = toDoTasks.size();

            // Deduplicate
            DeduplicationResult dedupeResult = deduplicateTasks(toDoTasks);
            result.tasksDuplicate = dedupeResult.duplicateCount;

            // Import to staging
            if (!dedupeResult.newTasks.isEmpty()) {
                AIWorkspaceStagingCreator.StagingResult stagingResult = 
                    AIWorkspaceStagingCreator.createTaskStagingRecords(dedupeResult.newTasks, 'MICROSOFT_TASKS', null, userId, false);
                result.tasksImported = stagingResult.importedCount;
            result.tasksMatched = stagingResult.matchedCount;
            result.tasksUnmatched = stagingResult.unmatchedCount;
                result.tasksFailed = stagingResult.failedCount;
                result.errors.addAll(stagingResult.errors);
                result.taskIds = stagingResult.stagingRecordIds;
            }
            
            String status = result.tasksFailed > 0 ? 'Partial' : 'Success';
            logSyncResult(userId, status, startTime, result, null);

        } catch (Exception e) {
            logSyncResult(userId, 'Failed', startTime, result, e.getMessage());
        }
    }

    /**
     * Deduplication result wrapper
     */
    private class DeduplicationResult {
        public List<AIMicrosoftTaskService.ToDoTask> newTasks { get; set; }
        public Integer duplicateCount { get; set; }

        public DeduplicationResult() {
            this.newTasks = new List<AIMicrosoftTaskService.ToDoTask>();
            this.duplicateCount = 0;
        }
    }

    /**
     * Deduplicate tasks against existing AI_Workspace_Staging__c records
     */
    private static DeduplicationResult deduplicateTasks(List<AIMicrosoftTaskService.ToDoTask> tasks) {
        DeduplicationResult result = new DeduplicationResult();

        // Collect external task IDs
        Set<String> externalIds = new Set<String>();
        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            if (String.isNotBlank(task.taskId)) {
                externalIds.add(task.taskId);
            }
        }

        // Query existing staging records with these external IDs
        Map<String, Id> existingIds = AIWorkspaceStagingCreator.getExistingTasksByProviderId(externalIds);

        // Filter out duplicates
        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            if (String.isBlank(task.taskId) || !existingIds.containsKey(task.taskId)) {
                result.newTasks.add(task);
            } else {
                result.duplicateCount++;
            }
        }

        return result;
    }

    /**
     * Import tasks as Salesforce Task records
     */
    private static void importTasks(
        List<AIMicrosoftTaskService.ToDoTask> toDoTasks,
        Id userId,
        TaskSyncResult result
    ) {
        List<Task> tasksToInsert = new List<Task>();

        for (AIMicrosoftTaskService.ToDoTask toDoTask : toDoTasks) {
            try {
                Task t = mapToDoTaskToSalesforceTask(toDoTask, userId);
                tasksToInsert.add(t);
            } catch (Exception e) {
                result.errors.add('Error mapping task "' + toDoTask.title + '": ' + e.getMessage());
                result.tasksFailed++;
            }
        }

        // Bulk insert with FLS/OLS enforcement
        if (!tasksToInsert.isEmpty()) {
            tasksToInsert = (List<Task>)FLSCheck.getInstance().insertCheck(tasksToInsert);
            
            if (tasksToInsert == null || tasksToInsert.isEmpty()) {
                return;
            }
            
            Database.SaveResult[] saveResults = Database.insert(tasksToInsert, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.tasksImported++;
                    result.taskIds.add(saveResults[i].getId());
                } else {
                    result.tasksFailed++;
                    for (Database.Error err : saveResults[i].getErrors()) {
                        result.errors.add(tasksToInsert[i].Subject + ': ' + err.getMessage());
                    }
                }
            }
        }
    }

    /**
     * Map Microsoft To-Do task to Salesforce Task
     * Public method to allow reuse from AITaskSyncController
     */
    public static Task mapToDoTaskToSalesforceTask(AIMicrosoftTaskService.ToDoTask toDoTask, Id userId) {
        Task t = new Task();

        // Subject (required)
        t.Subject = String.isNotBlank(toDoTask.title)
            ? AIExchangeEmailHelper.truncateField(toDoTask.title, 255)
            : '(No Title)';

        // Description with list info
        String description = '';
        if (String.isNotBlank(toDoTask.listName)) {
            description += 'From List: ' + toDoTask.listName + '\n---\n';
        }
        if (String.isNotBlank(toDoTask.body)) {
            description += toDoTask.body;
        }
        t.Description = AIExchangeEmailHelper.truncateField(description, 32000);

        // External ID for deduplication
        t.Workspace_Sync_Id__c = toDoTask.taskId;
        // Note: Provider info is tracked on AI_Workspace_Staging__c, not on Task

        // Owner is the syncing user
        t.OwnerId = userId;

        // Due date
        if (toDoTask.dueDateTime != null) {
            t.ActivityDate = toDoTask.dueDateTime.date();
        }

        // Status mapping
        t.Status = mapStatus(toDoTask.status);

        // Priority mapping
        t.Priority = mapPriority(toDoTask.importance);

        // TaskSubtype = 'Task' (default, not 'Email')
        // No need to set explicitly as it defaults correctly

        // If reminder is on, set reminder
        if (toDoTask.isReminderOn && toDoTask.reminderDateTime != null) {
            t.IsReminderSet = true;
            t.ReminderDateTime = toDoTask.reminderDateTime;
        }

        return t;
    }

    /**
     * Find the newest task date from a list of fetched tasks.
     * Used to determine the checkpoint for the next sync run.
     * For tasks, we use the lastModifiedDateTime (when the task was last updated)
     * rather than the due date, to ensure we capture all changes.
     *
     * @param tasks List of ToDoTask objects
     * @return DateTime of the newest task modification, or null if no valid dates found
     */
    private static DateTime findNewestTaskDate(List<AIMicrosoftTaskService.ToDoTask> tasks) {
        DateTime newestDate = null;
        
        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            // Use lastModifiedDateTime if available (preferred for incremental sync)
            DateTime taskDate = task.lastModifiedDateTime;
            
            // Fallback to createdDateTime if lastModifiedDateTime is not available
            if (taskDate == null) {
                taskDate = task.createdDateTime;
            }
            
            // Fallback to due date if neither modified nor created time is available
            if (taskDate == null) {
                taskDate = task.dueDateTime;
            }
            
            if (taskDate != null && (newestDate == null || taskDate > newestDate)) {
                newestDate = taskDate;
            }
        }
        
        return newestDate;
    }
    
    /**
     * Map Microsoft To-Do status to Salesforce Task status
     */
    private static String mapStatus(String toDoStatus) {
        if (String.isBlank(toDoStatus)) {
            return 'Not Started';
        }

        switch on toDoStatus.toLowerCase() {
            when 'notstarted' {
                return 'Not Started';
            }
            when 'inprogress' {
                return 'In Progress';
            }
            when 'completed' {
                return 'Completed';
            }
            when 'waitingonothers' {
                return 'Waiting on someone else';
            }
            when 'deferred' {
                return 'Deferred';
            }
            when else {
                return 'Not Started';
            }
        }
    }

    /**
     * Map Microsoft To-Do importance to Salesforce Task priority
     */
    private static String mapPriority(String toDoImportance) {
        if (String.isBlank(toDoImportance)) {
            return 'Normal';
        }

        switch on toDoImportance.toLowerCase() {
            when 'high' {
                return 'High';
            }
            when 'low' {
                return 'Low';
            }
            when else {
                return 'Normal';
            }
        }
    }

    /**
     * Log sync result to AI_Workspace_Sync_Log__c
     * (Reusing AI_Workspace_Sync_Log__c for all sync types with different provider type)
     */
    private static void logSyncResult(
        Id userId,
        String status,
        DateTime startTime,
        TaskSyncResult result,
        String errorMessage
    ) {
        try {
            if (!Schema.sObjectType.AI_Workspace_Sync_Log__c.isCreateable()) {
                return;
            }

            AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c();
            syncLog.User__c = userId;
            syncLog.Provider_Type__c = 'MICROSOFT_TASKS'; // Use specific provider type
            syncLog.Record_Type__c = 'Task';
            syncLog.Sync_Type__c = 'Scheduled';
            syncLog.Status__c = status;
            syncLog.Start_Time__c = startTime;
            syncLog.End_Time__c = DateTime.now();
            syncLog.Sync_Window_Start__c = result.syncWindowStart;
            syncLog.Sync_Window_End__c = result.syncWindowEnd;
            syncLog.Processing_Time_Seconds__c =
                (syncLog.End_Time__c.getTime() - syncLog.Start_Time__c.getTime()) / 1000.0;

            // V2-7889: Phase 1 tracking - use email fields for task counts
            syncLog.Emails_Fetched__c = result.tasksFetched;
            syncLog.Emails_Matched__c = result.tasksMatched;      // Successfully created staging records
            syncLog.Emails_Duplicate__c = result.tasksDuplicate;
            syncLog.Emails_Unmatched__c = result.tasksUnmatched;  // Failed to create staging records
            syncLog.Emails_Excluded__c = 0;  // TODO: Add exclusion tracking for tasks
            syncLog.Emails_Imported__c = 0;  // Always 0 in Phase 1

            // Error handling
            if (String.isNotBlank(errorMessage)) {
                syncLog.Error_Message__c = AIExchangeEmailHelper.truncateField(errorMessage, 32000);
            } else if (!result.errors.isEmpty()) {
                syncLog.Error_Message__c = AIExchangeEmailHelper.truncateField(String.join(result.errors, '\n'), 32000);
            }

            FLSCheck.getInstance().insertDML(new List<AI_Workspace_Sync_Log__c>{syncLog});
        } catch (Exception e) {
            //ignore
        }
    }
}