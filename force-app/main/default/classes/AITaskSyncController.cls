/**
 * TaskSyncController
 * Apex controller for task sync LWC functionality
 *
 * Provides methods for:
 * - Fetching tasks from Microsoft To-Do
 * - Importing tasks into Salesforce
 * - Checking which tasks are already imported
 */
public with sharing class AITaskSyncController {

    /**
     * Response wrapper for tasks
     */
    public class TasksResponse {
        @AuraEnabled public List<AIMicrosoftTaskService.ToDoTask> tasks;
        @AuraEnabled public Map<String, Id> importedTasks;
        @AuraEnabled public String error;
        @AuraEnabled public Boolean isTaskAccessible;
        @AuraEnabled public String userEmail;
        @AuraEnabled public String nextPageToken;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer totalCount;

        public TasksResponse() {
            this.tasks = new List<AIMicrosoftTaskService.ToDoTask>();
            this.importedTasks = new Map<String, Id>();
            this.isTaskAccessible = false;
            this.hasMore = false;
            this.totalCount = 0;
        }
    }

    /**
     * Import result wrapper
     */
    public class ImportResult {
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failedCount { get; set; }
        @AuraEnabled public Integer duplicateCount { get; set; }
        @AuraEnabled public List<Id> taskIds { get; set; }
        @AuraEnabled public List<ImportedTaskInfo> importedTasks { get; set; }
        @AuraEnabled public List<String> errors { get; set; }

        public ImportResult() {
            this.successCount = 0;
            this.failedCount = 0;
            this.duplicateCount = 0;
            this.taskIds = new List<Id>();
            this.importedTasks = new List<ImportedTaskInfo>();
            this.errors = new List<String>();
        }
    }

    /**
     * Info about an imported task for UI display
     */
    public class ImportedTaskInfo {
        @AuraEnabled public Id taskId { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String externalId { get; set; }
        @AuraEnabled public Id whoId { get; set; }
        @AuraEnabled public String whoName { get; set; }
        @AuraEnabled public String whoType { get; set; }
        @AuraEnabled public Id whatId { get; set; }
        @AuraEnabled public String whatName { get; set; }
        @AuraEnabled public String whatType { get; set; }
        @AuraEnabled public Integer confidence { get; set; }
    }

    /**
     * Match info for a task (similar to AICalendarEventCreator.EventMatchInfo)
     * V2-7889: Made @TestVisible for test coverage
     */
    @TestVisible
    public class TaskMatchInfo {
        public Id whoId;
        public String whoName;
        public String whoType;
        public Id whatId;
        public String whatName;
        public String whatType;
        public Integer confidence;
        public List<Id> allMatchedContactIds;
    }

    /**
     * Cache for bulkified Contact/Lead lookup
     * V2-7889: Made @TestVisible for test coverage
     */
    @TestVisible
    private class MatchCache {
        public Map<String, Contact> emailToContact = new Map<String, Contact>();
        public Map<String, Lead> emailToLead = new Map<String, Lead>();
    }

    /**
     * Get tasks from Microsoft To-Do with pagination support
     * @param listFilter Optional filter for task list ('all', specific list ID, or null for all)
     * @param includeCompleted Whether to include completed tasks
     * @param maxResults Maximum tasks to return per page
     * @param pageToken Optional pagination token (offset)
     * @return TasksResponse with tasks, import status, and pagination info
     */
    @AuraEnabled(cacheable=false)
    public static TasksResponse getTasks(String listFilter, Boolean includeCompleted, Integer maxResults, String pageToken) {
        TasksResponse response = new TasksResponse();

        try {
            // Check task access
            response.isTaskAccessible = AIMicrosoftTaskService.isTaskAccessible();

            if (!response.isTaskAccessible) {
                response.error = 'Microsoft To-Do access not available. Please ensure Tasks.Read permission is granted in your Microsoft 365 configuration.';
                return response;
            }

            // Get user email for display
            response.userEmail = getUserEmail();

            // Default values
            if (maxResults == null || maxResults <= 0) {
                maxResults = AISyncSettingsService.getMaxTasksPerUser();
            }
            if (includeCompleted == null) {
                includeCompleted = AISyncSettingsService.includeCompletedTasks();
            }
            
            // Parse offset from pageToken
            Integer offset = 0;
            if (String.isNotBlank(pageToken)) {
                try {
                    offset = Integer.valueOf(pageToken);
                } catch (Exception e) {
                    offset = 0;
                }
            }

            // Fetch one extra to check if there are more
            Integer fetchLimit = maxResults + 1;

            // Fetch tasks
            List<AIMicrosoftTaskService.ToDoTask> tasks;
            if (String.isNotBlank(listFilter) && listFilter != 'all') {
                // Fetch from specific list with offset
                tasks = AIMicrosoftTaskService.getTasksFromListWithOffset(listFilter, null, fetchLimit, offset, includeCompleted);
            } else {
                // Fetch from all lists with offset
                tasks = AIMicrosoftTaskService.getAllTasksWithOffset(fetchLimit, offset, includeCompleted);
            }

            // V2-7889: Note - Tasks don't have organizer/from fields (they're personal to-do items)
            // Domain exclusion filtering is not applicable to tasks
            // If needed in future, filtering logic can be added here

            // Check if there are more tasks
            if (tasks.size() > maxResults) {
                response.hasMore = true;
                response.nextPageToken = String.valueOf(offset + maxResults);
                // Remove the extra task we fetched
                tasks.remove(tasks.size() - 1);
            } else {
                response.hasMore = false;
                response.nextPageToken = null;
            }

            response.tasks = tasks;
            // Don't set totalCount here - task APIs don't provide accurate totals
            // The LWC will calculate display based on pagination state
            // totalCount stays at 0 (default) to indicate "unknown"

            // Check which tasks are already imported
            Set<String> taskIds = new Set<String>();
            for (AIMicrosoftTaskService.ToDoTask task : tasks) {
                if (String.isNotBlank(task.taskId)) {
                    taskIds.add(task.taskId);
                }
            }

            if (!taskIds.isEmpty()) {
                response.importedTasks = getImportedTasksMap(taskIds);

                // Get detailed info including linked records
                Map<String, ImportedTaskDetails> taskDetails = getImportedTaskDetails(taskIds);

                // Mark tasks as imported and populate linked record info
                // Only show badges for real Salesforce records (Lead, Contact, Account, Opportunity)
                // Don't expose staging records or tasks without associations
                for (AIMicrosoftTaskService.ToDoTask task : response.tasks) {
                    task.isImported = response.importedTasks.containsKey(task.taskId);
                    if (task.isImported) {
                        // Get linked record details from the actual Salesforce Task
                        ImportedTaskDetails details = taskDetails.get(task.taskId);
                        if (details != null) {
                            // Populate linkedRecords list for multiple pills display
                            if (details.linkedRecords != null && !details.linkedRecords.isEmpty()) {
                                for (AITaskSyncController.LinkedRecordInfo lr : details.linkedRecords) {
                                    task.linkedRecords.add(new AIMicrosoftTaskService.LinkedRecord(
                                        lr.recordId, lr.recordName, lr.recordType
                                    ));
                                }
                            }
                            
                            // Also keep the old single-record fields for backwards compatibility
                            // Prefer WhoId (Contact/Lead) over WhatId (Account/Opportunity)
                            if (details.whoId != null) {
                                task.linkedRecordId = details.whoId;
                                task.linkedRecordName = details.whoName;
                                task.linkedRecordType = details.whoType;
                            } else if (details.whatId != null) {
                                task.linkedRecordId = details.whatId;
                                task.linkedRecordName = details.whatName;
                                task.linkedRecordType = details.whatType;
                            }
                            // If no WhoId or WhatId, don't set linkedRecord fields
                            // This will show "✓ Imported" instead of exposing staging record
                        }
                    }
                }
            }

        } catch (Exception e) {
            response.error = 'Error fetching tasks: ' + e.getMessage();
        }

        return response;
    }

    /**
     * Get task lists from Microsoft To-Do
     * @return List of task lists
     */
    @AuraEnabled(cacheable=false)
    public static List<AIMicrosoftTaskService.TaskList> getTaskLists() {
        try {
            return AIMicrosoftTaskService.getTaskLists();
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get task lists: ' + e.getMessage());
        }
    }

    /**
     * Get task lists from Google Tasks
     * @return List of Google task lists
     */
    @AuraEnabled(cacheable=false)
    public static List<AIGoogleTaskService.TaskList> getGoogleTaskLists() {
        try {
            return AIGoogleTaskService.getTaskLists();
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get Google task lists: ' + e.getMessage());
        }
    }

    /**
     * Response wrapper for Google tasks
     */
    public class GoogleTasksResponse {
        @AuraEnabled public List<AIGoogleTaskService.ToDoTask> tasks;
        @AuraEnabled public Map<String, Id> importedTasks;
        @AuraEnabled public String error;
        @AuraEnabled public Boolean isTaskAccessible;
        @AuraEnabled public String userEmail;
        @AuraEnabled public String nextPageToken;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer totalCount;

        public GoogleTasksResponse() {
            this.tasks = new List<AIGoogleTaskService.ToDoTask>();
            this.importedTasks = new Map<String, Id>();
            this.isTaskAccessible = false;
            this.hasMore = false;
            this.totalCount = 0;
        }
    }

    /**
     * Get tasks from Google Tasks with pagination support
     * @param listFilter Optional filter for task list ('all', specific list ID, or null for all)
     * @param includeCompleted Whether to include completed tasks
     * @param maxResults Maximum tasks to return per page
     * @param pageToken Optional pagination token (offset)
     * @return GoogleTasksResponse with tasks, import status, and pagination info
     */
    @AuraEnabled(cacheable=false)
    public static GoogleTasksResponse getGoogleTasks(String listFilter, Boolean includeCompleted, Integer maxResults, String pageToken) {
        GoogleTasksResponse response = new GoogleTasksResponse();

        try {
            // Check task access
            response.isTaskAccessible = AIGoogleTaskService.isTaskAccessible();

            if (!response.isTaskAccessible) {
                response.error = 'Google Tasks access not available. Please ensure tasks.readonly scope is granted and reconnect your Google account.';
                return response;
            }

            // Get user email for display (Google)
            response.userEmail = getUserEmailForProvider('GOOGLE_TASKS');

            // Default values
            if (maxResults == null || maxResults <= 0) {
                maxResults = AISyncSettingsService.getMaxTasksPerUser();
            }
            if (includeCompleted == null) {
                includeCompleted = AISyncSettingsService.includeCompletedTasks();
            }
            
            // Parse offset from pageToken
            Integer offset = 0;
            if (String.isNotBlank(pageToken)) {
                try {
                    offset = Integer.valueOf(pageToken);
                } catch (Exception e) {
                    offset = 0;
                }
            }

            // Fetch one extra to check if there are more
            Integer fetchLimit = maxResults + 1;

            // Fetch tasks
            List<AIGoogleTaskService.ToDoTask> tasks;
            if (String.isNotBlank(listFilter) && listFilter != 'all') {
                // Fetch from specific list with offset
                tasks = AIGoogleTaskService.getTasksFromListWithOffset(listFilter, null, fetchLimit, offset, includeCompleted);
            } else {
                // Fetch from all lists with offset
                tasks = AIGoogleTaskService.getAllTasksWithOffset(fetchLimit, offset, includeCompleted);
            }

            // Check if there are more tasks
            if (tasks.size() > maxResults) {
                response.hasMore = true;
                response.nextPageToken = String.valueOf(offset + maxResults);
                // Remove the extra task we fetched
                tasks.remove(tasks.size() - 1);
            } else {
                response.hasMore = false;
                response.nextPageToken = null;
            }

            response.tasks = tasks;
            // Don't set totalCount here - task APIs don't provide accurate totals
            // The LWC will calculate display based on pagination state
            // totalCount stays at 0 (default) to indicate "unknown"

            // Check which tasks are already imported
            Set<String> taskIds = new Set<String>();
            for (AIGoogleTaskService.ToDoTask task : tasks) {
                if (String.isNotBlank(task.taskId)) {
                    taskIds.add(task.taskId);
                }
            }

            if (!taskIds.isEmpty()) {
                response.importedTasks = getImportedTasksMap(taskIds);

                // Get detailed info including linked records
                Map<String, ImportedTaskDetails> taskDetails = getImportedTaskDetails(taskIds);

                // Mark tasks as imported and populate linked record info
                // Only show badges for real Salesforce records (Lead, Contact, Account, Opportunity)
                // Don't expose staging records or tasks without associations
                for (AIGoogleTaskService.ToDoTask task : response.tasks) {
                    task.isImported = response.importedTasks.containsKey(task.taskId);
                    if (task.isImported) {
                        // Get linked record details from the actual Salesforce Task
                        ImportedTaskDetails details = taskDetails.get(task.taskId);
                        if (details != null) {
                            // Populate linkedRecords list for multiple pills display
                            if (details.linkedRecords != null && !details.linkedRecords.isEmpty()) {
                                for (AITaskSyncController.LinkedRecordInfo lr : details.linkedRecords) {
                                    task.linkedRecords.add(new AIGoogleTaskService.LinkedRecord(
                                        lr.recordId, lr.recordName, lr.recordType
                                    ));
                                }
                            }
                            
                            // Also keep the old single-record fields for backwards compatibility
                            // Prefer WhoId (Contact/Lead) over WhatId (Account/Opportunity)
                            if (details.whoId != null) {
                                task.linkedRecordId = details.whoId;
                                task.linkedRecordName = details.whoName;
                                task.linkedRecordType = details.whoType;
                            } else if (details.whatId != null) {
                                task.linkedRecordId = details.whatId;
                                task.linkedRecordName = details.whatName;
                                task.linkedRecordType = details.whatType;
                            }
                            // If no WhoId or WhatId, don't set linkedRecord fields
                            // This will show "✓ Imported" instead of exposing staging record
                        }
                    }
                }
            }
        } catch (AIGoogleTaskService.TaskServiceException e) {
            response.error = 'Google Tasks service error: ' + e.getMessage();
            response.isTaskAccessible = false;
        } catch (Exception e) {
            response.error = 'Error fetching Google tasks: ' + e.getMessage();
        }

        return response;
    }

    /**
     * Import selected Google tasks into Salesforce (as staging records)
     * @param taskIds List of task IDs to import (in format "listId::taskId")
     * @return ImportResult with success/failure details
     */
    @AuraEnabled
    public static ImportResult importGoogleTasks(List<String> taskIds) {
        ImportResult result = new ImportResult();

        if (taskIds == null || taskIds.isEmpty()) {
            result.errors.add('No tasks selected for import');
            return result;
        }

        try {
            // Fetch full task details
            List<AIGoogleTaskService.ToDoTask> tasksToImport = new List<AIGoogleTaskService.ToDoTask>();
            
            // Check existing tasks first
            Set<String> allTaskIds = new Set<String>();
            for (String taskIdPair : taskIds) {
                String taskId = taskIdPair.contains('::') ? taskIdPair.substringAfter('::') : taskIdPair;
                allTaskIds.add(taskId);
            }

            Map<String, Id> alreadyImported = getImportedTasksMap(allTaskIds);
            result.duplicateCount = 0;

            for (String taskIdPair : taskIds) {
                try {
                    String listId;
                    String taskId;

                    if (taskIdPair.contains('::')) {
                        listId = taskIdPair.substringBefore('::');
                        taskId = taskIdPair.substringAfter('::');
                    } else {
                        taskId = taskIdPair;
                        result.errors.add('Task ' + taskId + ' is missing list ID');
                        result.failedCount++;
                        continue;
                    }

                    // Check if already imported
                    if (alreadyImported.containsKey(taskId)) {
                        result.duplicateCount++;
                        continue;
                    }

                    // Fetch full task details
                    AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask(listId, taskId);
                    if (task != null) {
                        task.listId = listId;
                        tasksToImport.add(task);
                    }
                } catch (Exception e) {
                    result.errors.add('Failed to fetch task: ' + e.getMessage());
                    result.failedCount++;
                }
            }

            if (tasksToImport.isEmpty() && result.duplicateCount > 0) {
                // All were duplicates
                return result;
            }

            if (tasksToImport.isEmpty()) {
                result.errors.add('No valid tasks to import');
                return result;
            }

            // Create staging records for Google tasks with precedence-based matching
            // sendNotifications = true for manual imports from modal
            AIWorkspaceStagingCreator.StagingResult stagingResult = 
                AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                    tasksToImport,
                    UserInfo.getUserId(),
                    'GOOGLE_TASKS',
                    true
                );

            result.successCount = stagingResult.successCount;
            result.failedCount += stagingResult.failedCount;
            result.duplicateCount += stagingResult.duplicateCount; // Add duplicates from staging layer

            // Query staging records to get the created Task IDs and match info
            Map<Id, AI_Workspace_Staging__c> stagingMap = new Map<Id, AI_Workspace_Staging__c>();
            if (!stagingResult.stagingRecordIds.isEmpty()) {
                for (AI_Workspace_Staging__c staging : [
                    SELECT Id, Email_Message__c, Status__c, Provider_Id__c
                    FROM AI_Workspace_Staging__c
                    WHERE Id IN :stagingResult.stagingRecordIds
                ]) {
                    stagingMap.put(staging.Id, staging);
                }
            }
            
            // Collect Task IDs (not staging IDs!) for linking
            Set<Id> taskRecordIds = new Set<Id>();
            for (AI_Workspace_Staging__c staging : stagingMap.values()) {
                if (String.isNotBlank(staging.Email_Message__c)) {
                    try {
                        Id taskId = Id.valueOf(staging.Email_Message__c);
                        taskRecordIds.add(taskId);
                        result.taskIds.add(taskId); // Add actual Task ID, not staging ID
                    } catch (Exception e) {
                        // Not a valid Id, skip
                    }
                }
            }
            
            // Query Tasks to get WhoId information
            Map<Id, Task> taskMap = new Map<Id, Task>();
            if (!taskRecordIds.isEmpty()) {
                for (Task t : [
                    SELECT Id, WhoId, Who.Name, Who.Type
                    FROM Task
                    WHERE Id IN :taskRecordIds
                ]) {
                    taskMap.put(t.Id, t);
                }
            }

            // Create ImportedTaskInfo for each imported task with match details
            for (Integer i = 0; i < stagingResult.stagingRecordIds.size() && i < tasksToImport.size(); i++) {
                Id stagingId = stagingResult.stagingRecordIds[i];
                AI_Workspace_Staging__c staging = stagingMap.get(stagingId);
                
                ImportedTaskInfo info = new ImportedTaskInfo();
                info.subject = tasksToImport[i].title;
                info.externalId = tasksToImport[i].taskId;
                
                // Populate Task ID and WhoId info from the created Task
                if (staging != null && String.isNotBlank(staging.Email_Message__c)) {
                    try {
                        Id taskRecordId = Id.valueOf(staging.Email_Message__c);
                        info.taskId = taskRecordId; // Use actual Task record ID for notification navigation
                        Task t = taskMap.get(taskRecordId);
                        if (t != null && t.WhoId != null) {
                            info.whoId = t.WhoId;
                            info.whoName = t.Who.Name;
                            info.whoType = t.Who.Type;
                        }
                    } catch (Exception e) {
                        // Skip if not a valid ID - no notification will be sent for this task
                    }
                }
                
                // Only add to result if we have a valid Task ID (staging succeeded)
                if (info.taskId != null) {
                    result.importedTasks.add(info);
                }
            }

        } catch (Exception e) {
            result.errors.add('Import error: ' + e.getMessage());
        }

        // COMMENTED OUT: Bell notifications disabled for auto-sync (scheduler/Run Now)
        // Only manual matches from the modal should send bell notifications
        // if (!result.importedTasks.isEmpty()) {
        //     sendTaskImportNotifications(result.importedTasks);
        // }

        return result;
    }

    /**
     * Import selected tasks into Salesforce
     * @param taskIds List of task IDs to import (in format "listId::taskId")
     * @return ImportResult with success/failure details
     */
    @AuraEnabled
    public static ImportResult importTasks(List<String> taskIds) {
        ImportResult result = new ImportResult();

        if (taskIds == null || taskIds.isEmpty()) {
            result.errors.add('No tasks selected for import');
            return result;
        }

        try {
            // Fetch full task details and deduplicate
            List<AIMicrosoftTaskService.ToDoTask> tasksToImport = new List<AIMicrosoftTaskService.ToDoTask>();
            Set<String> existingIds = new Set<String>();

            // Check existing tasks first
            Set<String> allTaskIds = new Set<String>();
            for (String taskIdPair : taskIds) {
                // Format: "listId::taskId" or just "taskId"
                String taskId = taskIdPair.contains('::') ? taskIdPair.substringAfter('::') : taskIdPair;
                allTaskIds.add(taskId);
            }

            Map<String, Id> alreadyImported = getImportedTasksMap(allTaskIds);
            result.duplicateCount = 0;

            for (String taskIdPair : taskIds) {
                try {
                    String listId;
                    String taskId;

                    if (taskIdPair.contains('::')) {
                        listId = taskIdPair.substringBefore('::');
                        taskId = taskIdPair.substringAfter('::');
                    } else {
                        taskId = taskIdPair;
                        // Need to find the list ID - for now skip these
                        result.errors.add('Task ' + taskId + ' is missing list ID');
                        result.failedCount++;
                        continue;
                    }

                    // Check if already imported
                    if (alreadyImported.containsKey(taskId)) {
                        result.duplicateCount++;
                        continue;
                    }

                    // Fetch full task details
                    AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask(listId, taskId);
                    if (task != null) {
                        task.listId = listId;
                        tasksToImport.add(task);
                    }
                } catch (Exception e) {
                    result.errors.add('Failed to fetch task: ' + e.getMessage());
                    result.failedCount++;
                }
            }

            // Create staging records for all tasks with precedence-based matching
            // sendNotifications = true for manual imports from modal
            if (!tasksToImport.isEmpty()) {
                AIWorkspaceStagingCreator.StagingResult stagingResult =
                    AIWorkspaceStagingCreator.createTaskStagingRecords(
                        tasksToImport,
                        'MICROSOFT_TASKS',
                        null,  // No sync log for manual imports
                        null,  // targetUserId = null (use current user)
                        true   // sendNotifications = true for manual imports
                    );

                result.successCount = stagingResult.successCount;
                result.failedCount += stagingResult.failedCount;
                result.duplicateCount += stagingResult.duplicateCount; // Add duplicates from staging layer
                result.errors.addAll(stagingResult.errors);

                // Query staging records to get the created Task IDs and match info
                Map<Id, AI_Workspace_Staging__c> stagingMap = new Map<Id, AI_Workspace_Staging__c>();
                if (!stagingResult.stagingRecordIds.isEmpty()) {
                    for (AI_Workspace_Staging__c staging : [
                        SELECT Id, Email_Message__c, Status__c, Provider_Id__c
                        FROM AI_Workspace_Staging__c
                        WHERE Id IN :stagingResult.stagingRecordIds
                    ]) {
                        stagingMap.put(staging.Id, staging);
                    }
                }
                
                // Collect Task IDs to query for WhoId info
                Set<Id> taskRecordIds = new Set<Id>();
                for (AI_Workspace_Staging__c staging : stagingMap.values()) {
                    if (String.isNotBlank(staging.Email_Message__c)) {
                        try {
                            taskRecordIds.add(Id.valueOf(staging.Email_Message__c));
                        } catch (Exception e) {
                            // Not a valid Id, skip
                        }
                    }
                }
                
                // Query Tasks to get WhoId information
                Map<Id, Task> taskMap = new Map<Id, Task>();
                if (!taskRecordIds.isEmpty()) {
                    for (Task t : [
                        SELECT Id, WhoId, Who.Name, Who.Type
                        FROM Task
                        WHERE Id IN :taskRecordIds
                    ]) {
                        taskMap.put(t.Id, t);
                    }
                }

                // Track imported task info with match details
                for (Integer i = 0; i < stagingResult.stagingRecordIds.size() && i < tasksToImport.size(); i++) {
                    Id stagingId = stagingResult.stagingRecordIds[i];
                    AI_Workspace_Staging__c staging = stagingMap.get(stagingId);
                    
                    ImportedTaskInfo info = new ImportedTaskInfo();
                    info.subject = tasksToImport[i].title;
                    info.externalId = tasksToImport[i].taskId;
                    
                    // Populate Task ID and WhoId info from the created Task
                    if (staging != null && String.isNotBlank(staging.Email_Message__c)) {
                        try {
                            Id taskRecordId = Id.valueOf(staging.Email_Message__c);
                            info.taskId = taskRecordId; // Use actual Task record ID for notification navigation
                            result.taskIds.add(taskRecordId); // Add actual Task ID for linking, not staging ID
                            Task t = taskMap.get(taskRecordId);
                            if (t != null && t.WhoId != null) {
                                info.whoId = t.WhoId;
                                info.whoName = t.Who.Name;
                                info.whoType = t.Who.Type;
                            }
                        } catch (Exception e) {
                            // Skip if not a valid ID - no notification will be sent for this task
                        }
                    }
                    
                    // Only add to importedTasks if we have a valid Task ID (staging succeeded)
                    if (info.taskId != null) {
                        result.importedTasks.add(info);
                    }
                }
            }

        } catch (Exception e) {
            result.errors.add('Error importing tasks: ' + e.getMessage());
        }

        // NOTE: Manual imports do NOT create sync logs
        // Sync logs are only for automated/scheduled syncs

        // COMMENTED OUT: Bell notifications disabled for auto-sync (scheduler/Run Now)
        // Only manual matches from the modal should send bell notifications
        // if (!result.importedTasks.isEmpty()) {
        //     sendTaskImportNotifications(result.importedTasks);
        // }

        return result;
    }

    /**
     * Create a sync log record for task import
     * NOTE: Currently unused. Reserved for future scheduled/automated task sync functionality.
     * Manual imports do NOT create sync logs.
     */
    private static void createTaskSyncLog(ImportResult result, Integer totalRequested) {
        try {
            String status = 'Success';
            if (result.failedCount > 0 && result.successCount == 0) {
                status = 'Failed';
            } else if (result.failedCount > 0) {
                status = 'Partial';
            }

            AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c();
            syncLog.User__c = UserInfo.getUserId();
            syncLog.Provider_Type__c = 'MICROSOFT_TASKS';
            syncLog.Record_Type__c = 'Task';
            syncLog.Sync_Type__c = 'Manual';
            syncLog.Status__c = status;
            syncLog.Start_Time__c = DateTime.now();
            syncLog.End_Time__c = DateTime.now();

            // Use email fields for task counts (repurposing fields)
            syncLog.Emails_Fetched__c = totalRequested;
            syncLog.Emails_Imported__c = result.successCount;
            syncLog.Emails_Duplicate__c = result.duplicateCount;

            // Error handling
            if (!result.errors.isEmpty()) {
                syncLog.Error_Message__c = AIExchangeEmailHelper.truncateField(String.join(result.errors, '\n'), 32000);
            }

            FLSCheck.getInstance().insertDML(new List<AI_Workspace_Sync_Log__c>{syncLog});
        } catch (Exception e) {
        }
    }

    /**
     * Build cache of Contacts/Leads from all email addresses in tasks
     * BULKIFIED: Single SOQL query for Contacts, single for Leads
     * NO REGEX - uses simple string parsing
     * V2-7889: Made @TestVisible for test coverage
     */
    @TestVisible
    private static MatchCache buildMatchCache(List<AIMicrosoftTaskService.ToDoTask> tasks) {
        MatchCache cache = new MatchCache();

        // Collect all email addresses from task titles and bodies
        Set<String> allEmails = new Set<String>();

        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            String searchText = (task.title != null ? task.title : '') + ' ' +
                               (task.body != null ? task.body : '');
            // Use simple email extraction - no regex
            Set<String> extractedEmails = extractEmailsSimple(searchText);
            allEmails.addAll(extractedEmails);
        }

        if (allEmails.isEmpty()) {
            return cache;
        }

        // Query 1: Bulk fetch Contacts by email
        for (Contact c : [
            SELECT Id, Name, Email, AccountId
            FROM Contact
            WHERE Email IN :allEmails
        ]) {
            if (String.isNotBlank(c.Email)) {
                cache.emailToContact.put(c.Email.toLowerCase(), c);
            }
        }

        // Query 2: Bulk fetch Leads by email (only non-converted)
        for (Lead l : [
            SELECT Id, Name, Email, Company
            FROM Lead
            WHERE Email IN :allEmails
            AND IsConverted = false
        ]) {
            if (String.isNotBlank(l.Email)) {
                cache.emailToLead.put(l.Email.toLowerCase(), l);
            }
        }

        return cache;
    }

    /**
     * Match task content to Contact/Lead using cached data (no SOQL in loop)
     * Sets WhoId on Task and collects ALL matched contacts for TaskRelation
     * NO REGEX - uses simple string parsing
     * V2-7889: Made @TestVisible for test coverage
     * @param toDoTask The Microsoft To-Do task
     * @param sfTask The Salesforce Task to update with WhoId
     * @param cache Pre-built cache of email -> Contact/Lead mappings
     * @return TaskMatchInfo with primary match and all matched contact IDs
     */
    @TestVisible
    private static TaskMatchInfo matchTaskWithCache(
        AIMicrosoftTaskService.ToDoTask toDoTask,
        Task sfTask,
        MatchCache cache
    ) {
        // Extract any email addresses from task title or body
        String searchText = (toDoTask.title != null ? toDoTask.title : '') + ' ' +
                           (toDoTask.body != null ? toDoTask.body : '');

        // Use simple email extraction - no regex
        Set<String> extractedEmails = extractEmailsSimple(searchText);

        // Collect ALL matching Contacts and Leads from emails in task
        List<Id> allMatchedContactIds = new List<Id>();
        List<Id> allMatchedLeadIds = new List<Id>();
        Contact primaryContact = null;
        Lead primaryLead = null;

        for (String email : extractedEmails) {
            // Check for Contact match
            if (cache.emailToContact.containsKey(email)) {
                Contact c = cache.emailToContact.get(email);
                allMatchedContactIds.add(c.Id);
                if (primaryContact == null) {
                    primaryContact = c;
                }
            }
            // Check for Lead match (only if no Contact for this email)
            else if (cache.emailToLead.containsKey(email)) {
                Lead l = cache.emailToLead.get(email);
                allMatchedLeadIds.add(l.Id);
                if (primaryLead == null) {
                    primaryLead = l;
                }
            }
        }

        // No email matches found
        if (allMatchedContactIds.isEmpty() && allMatchedLeadIds.isEmpty()) {
            return null;
        }

        // Build match info
        TaskMatchInfo matchInfo = new TaskMatchInfo();
        matchInfo.confidence = 95; // Direct email match

        // Prefer Contacts over Leads for primary WhoId
        if (primaryContact != null) {
            sfTask.WhoId = primaryContact.Id;
            matchInfo.whoId = primaryContact.Id;
            matchInfo.whoName = primaryContact.Name;
            matchInfo.whoType = 'Contact';
            // Store ALL matched Contact IDs for TaskRelation
            matchInfo.allMatchedContactIds = allMatchedContactIds;
        } else if (primaryLead != null) {
            sfTask.WhoId = primaryLead.Id;
            matchInfo.whoId = primaryLead.Id;
            matchInfo.whoName = primaryLead.Name;
            matchInfo.whoType = 'Lead';
            // Store ALL matched Lead IDs for TaskRelation
            matchInfo.allMatchedContactIds = allMatchedLeadIds;
        }

        return matchInfo;
    }

    /**
     * Create TaskRelation records for Shared Activities
     * Links additional Contacts/Leads beyond the primary WhoId
     * @param taskIdToRelationIds Map of Task ID to list of Contact/Lead IDs
     */
    private static void createTaskRelations(Map<Id, List<Id>> taskIdToRelationIds) {
        if (taskIdToRelationIds == null || taskIdToRelationIds.isEmpty()) {
            return;
        }

        List<SObject> relationsToInsert = new List<SObject>();
        Schema.SObjectType taskRelationType = Schema.getGlobalDescribe().get('TaskRelation');

        // TaskRelation may not exist in all orgs (requires Shared Activities enabled)
        if (taskRelationType == null) {
            return;
        }

        for (Id taskId : taskIdToRelationIds.keySet()) {
            for (Id relationId : taskIdToRelationIds.get(taskId)) {
                SObject tr = taskRelationType.newSObject();
                tr.put('TaskId', taskId);
                tr.put('RelationId', relationId);
                tr.put('IsWhat', false);
                relationsToInsert.add(tr);
            }
        }

        if (!relationsToInsert.isEmpty()) {
            // Use FLSCheck for FLS/OLS enforcement
            List<SObject> accessibleRelations = FLSCheck.getInstance().insertCheck(relationsToInsert);
            
            if (accessibleRelations == null || accessibleRelations.isEmpty()) {
                return;
            }
            
            // V2-7889: Use FLSCheck for FLS/CRUD enforcement
            FLSCheck.getInstance().insertDML(accessibleRelations, false);
        }
    }

    /**
     * Send bell notifications for imported tasks
     */
    private static void sendTaskImportNotifications(List<ImportedTaskInfo> importedTasks) {
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];

            if (notifTypes.isEmpty()) {
                return;
            }

            CustomNotificationType notifType = notifTypes[0];

            for (ImportedTaskInfo taskInfo : importedTasks) {
                try {
                    // Only send notification if we have a valid Task ID
                    if (taskInfo.taskId == null) {
                        continue;
                    }
                    
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();

                    // Truncate subject for title
                    String truncatedSubject = taskInfo.subject.length() > 40
                        ? taskInfo.subject.substring(0, 40) + '...'
                        : taskInfo.subject;

                    notification.setTitle('✅ Task imported: ' + truncatedSubject);
                    notification.setBody('Task imported successfully.\nClick to view the task.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(taskInfo.taskId);

                    notification.send(new Set<String>{UserInfo.getUserId()});
                } catch (Exception e) {
                }
            }
        } catch (Exception e) {
        }
    }

    /**
     * Refreshes the access token and returns task access status.
     * Call this method when the page loads to ensure a fresh token before any API calls.
     * This handles token refresh (DML) BEFORE any callouts happen.
     * 
     * @param providerType - Provider type: 'MICROSOFT_TASKS' or 'GOOGLE_TASKS'
     * @return Map with isAccessible, providerType, and any errors
     */
    @AuraEnabled
    public static Map<String, Object> refreshTokenAndCheckAccess(String providerType) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Default to Microsoft if not specified
            if (String.isBlank(providerType)) {
                providerType = 'MICROSOFT_TASKS';
            }
            
            // Convert provider type to AIWorkspaceTokenService format
            String tokenProvider = providerType == 'GOOGLE_TASKS' ? 'Gmail' : 'Outlook';
            
            // Check if user has a connection
            if (!AIWorkspaceTokenService.hasConnection(tokenProvider)) {
                result.put('isAccessible', false);
                result.put('providerType', providerType);
                result.put('namespace', AIPromptController.getNameSpace());
                result.put('refreshed', false);
                result.put('message', 'No connection found for ' + tokenProvider);
                return result;
            }
            
            // Attempt to refresh the token (this does callout + DML)
            try {
                AIWorkspaceTokenService.refreshAndGetToken(tokenProvider);
            } catch (AIWorkspaceTokenService.AuthenticationException e) {
                // Token refresh failed - user needs to re-authenticate
                result.put('isAccessible', false);
                result.put('providerType', providerType);
                result.put('namespace', AIPromptController.getNameSpace());
                result.put('refreshed', false);
                result.put('error', e.getMessage());
                return result;
            }
            
            // Token refreshed successfully - we assume access is available
            // IMPORTANT: We cannot call isTaskAccessible() here because:
            // 1. refreshAndGetToken() does callout + DML (saves refreshed token)
            // 2. Calling isTaskAccessible() would be another callout after DML
            // 3. This causes "You have uncommitted work pending" error
            // 
            // Since the token refresh succeeded, we assume the user has valid credentials.
            // If there's an actual permission issue, it will be caught when fetching tasks.
            result.put('isAccessible', true);
            result.put('providerType', providerType);
            result.put('namespace', AIPromptController.getNameSpace());
            result.put('refreshed', true);
            
        } catch (Exception e) {
            result.put('isAccessible', false);
            result.put('error', 'Error refreshing token: ' + e.getMessage());
            result.put('namespace', AIPromptController.getNameSpace());
            result.put('refreshed', false);
        }
        
        return result;
    }

    /**
     * Check if task sync is available for current user
     * @param providerType The task provider to check (MICROSOFT_TASKS or GOOGLE_TASKS)
     * @return Map with access status and any error message
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> checkTaskAccess(String providerType) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Default to Microsoft if not specified
            if (String.isBlank(providerType)) {
                providerType = 'MICROSOFT_TASKS';
            }

            Boolean isAccessible = false;
            String errorMessage = '';

            if (providerType == 'GOOGLE_TASKS') {
                // Google Tasks - check access
                isAccessible = AIGoogleTaskService.isTaskAccessible();
                if (!isAccessible) {
                    errorMessage = 'Google Tasks access not available. Please ensure tasks.readonly scope is granted and reconnect your Google account.';
                }
            } else {
                // Microsoft To-Do
                isAccessible = AIMicrosoftTaskService.isTaskAccessible();
                if (!isAccessible) {
                    errorMessage = 'Microsoft To-Do access not available. Please ensure Tasks.Read permission is granted.';
                }
            }

            result.put('isAccessible', isAccessible);
            result.put('providerType', providerType);
            result.put('namespace', AIPromptController.getNameSpace());

            if (isAccessible) {
                result.put('userEmail', getUserEmailForProvider(providerType));
            } else {
                result.put('error', errorMessage);
            }
        } catch (Exception e) {
            result.put('isAccessible', false);
            result.put('error', 'Error checking task access: ' + e.getMessage());
            result.put('namespace', AIPromptController.getNameSpace());
        }

        return result;
    }

    /**
     * Details about an imported task including linked records
     */
    public class ImportedTaskDetails {
        public Id taskId;
        public Id whoId;
        public String whoName;
        public String whoType;
        public Id whatId;
        public String whatName;
        public String whatType;
        @AuraEnabled public List<LinkedRecordInfo> linkedRecords;
        
        public ImportedTaskDetails() {
            this.linkedRecords = new List<LinkedRecordInfo>();
        }
    }
    
    /**
     * Info about a single linked record (Lead/Contact/Account/Opportunity)
     */
    public class LinkedRecordInfo {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String recordType; // 'Lead', 'Contact', 'Account', or 'Opportunity'
        
        public LinkedRecordInfo(Id recordId, String recordName, String recordType) {
            this.recordId = recordId;
            this.recordName = recordName;
            this.recordType = recordType;
        }
    }

    /**
     * Get map of imported tasks by external ID (Provider_Id__c or Workspace_Sync_Id__c)
     * 
     * This method checks BOTH:
     * 1. AI_Workspace_Staging__c - for staged/matched records
     * 2. Task records directly - for cases where staging was deleted but Task exists
     * 
     * This ensures that even if staging records are deleted, we still detect imported tasks.
     */
    private static Map<String, Id> getImportedTasksMap(Set<String> externalIds) {
        Map<String, Id> importedMap = new Map<String, Id>();

        if (externalIds == null || externalIds.isEmpty()) {
            return importedMap;
        }

        try {
            // Step 1: Query AI_Workspace_Staging__c with Task record type (for linked record info)
            // ONLY mark as imported if Email_Message__c has a valid Task ID
            // This ensures we don't show "Imported" badge for staging records without actual Tasks
            for (AI_Workspace_Staging__c staging : [
                SELECT Id, Provider_Id__c, Email_Message__c
                FROM AI_Workspace_Staging__c
                WHERE Provider_Id__c IN :externalIds
                AND RecordType.DeveloperName = 'Task'
                AND User__c = :UserInfo.getUserId()
                AND Email_Message__c != null
            ]) {
                if (String.isNotBlank(staging.Provider_Id__c) && String.isNotBlank(staging.Email_Message__c)) {
                    // Only add to map if Email_Message__c contains a valid Task ID
                    try {
                        Id taskId = Id.valueOf(staging.Email_Message__c);
                        // Verify it's actually a Task ID (starts with '00T')
                        if (String.valueOf(taskId).startsWith('00T')) {
                            importedMap.put(staging.Provider_Id__c, taskId);
                        }
                    } catch (Exception e) {
                        // Invalid ID format, skip this record
                    }
                }
            }
            
            // Step 2: ALSO query Task records directly for Workspace_Sync_Id__c
            // This catches tasks where the staging record was deleted
            // Use namespace-aware field name for dynamic query
            String workspaceSyncIdField = AIConstants.NAMESPACE + 'Workspace_Sync_Id__c';
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Task.fields.getMap();
            if (fieldMap.containsKey(workspaceSyncIdField)) {
                // Find IDs not yet in the map
                Set<String> remainingIds = new Set<String>();
                for (String externalId : externalIds) {
                    if (!importedMap.containsKey(externalId)) {
                        remainingIds.add(externalId);
                    }
                }
                
                if (!remainingIds.isEmpty()) {
                    String queryStr = 'SELECT Id, ' + workspaceSyncIdField + ' FROM Task ' +
                                     'WHERE ' + workspaceSyncIdField + ' IN :remainingIds ' +
                                     'AND OwnerId = \'' + UserInfo.getUserId() + '\'';
                    for (Task t : Database.query(queryStr)) {
                        String providerId = (String) t.get(workspaceSyncIdField);
                        if (String.isNotBlank(providerId) && !importedMap.containsKey(providerId)) {
                            importedMap.put(providerId, t.Id);
                        }
                    }
                }
            }
        } catch (Exception e) {
        }

        return importedMap;
    }

    /**
     * Get detailed info about imported tasks including linked Lead/Contact
     * 
     * This method checks BOTH:
     * 1. AI_Workspace_Staging__c - for linked record info from staging
     * 2. Task records directly - for cases where staging was deleted but Task exists
     * 
     * This ensures badges display correctly even after staging records are deleted.
     */
    private static Map<String, ImportedTaskDetails> getImportedTaskDetails(Set<String> externalIds) {
        Map<String, ImportedTaskDetails> detailsMap = new Map<String, ImportedTaskDetails>();

        if (externalIds == null || externalIds.isEmpty()) {
            return detailsMap;
        }

        try {
            // Step 1: Query staging records to get the Salesforce Task IDs
            // ONLY include staging records that have actual Task records (Email_Message__c populated)
            Map<String, Id> providerIdToTaskId = new Map<String, Id>();
            Map<String, Id> providerIdToStagingId = new Map<String, Id>();
            Set<String> foundProviderIds = new Set<String>();
            
            
            for (AI_Workspace_Staging__c staging : [
                SELECT Id, Provider_Id__c, Email_Message__c
                FROM AI_Workspace_Staging__c
                WHERE Provider_Id__c IN :externalIds
                AND RecordType.DeveloperName = 'Task'
                AND User__c = :UserInfo.getUserId()
                AND Email_Message__c != null
            ]) {
                if (String.isNotBlank(staging.Provider_Id__c) && String.isNotBlank(staging.Email_Message__c)) {
                    // Email_Message__c stores the Salesforce Task ID
                    try {
                        Id taskId = Id.valueOf(staging.Email_Message__c);
                        // Verify it's actually a Task ID (starts with '00T')
                        if (String.valueOf(taskId).startsWith('00T')) {
                            providerIdToStagingId.put(staging.Provider_Id__c, staging.Id);
                            providerIdToTaskId.put(staging.Provider_Id__c, taskId);
                            foundProviderIds.add(staging.Provider_Id__c);
                        }
                    } catch (Exception e) {
                        // Not a valid Id, skip
                    }
                }
            }
            
            // Step 2: Query Task records directly for IDs not found via staging
            // This handles cases where staging was deleted but Task exists
            // Use namespace-aware field name for dynamic query
            String workspaceSyncIdField = AIConstants.NAMESPACE + 'Workspace_Sync_Id__c';
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Task.fields.getMap();
            if (fieldMap.containsKey(workspaceSyncIdField)) {
                Set<String> remainingIds = new Set<String>();
                for (String externalId : externalIds) {
                    if (!foundProviderIds.contains(externalId)) {
                        remainingIds.add(externalId);
                    }
                }
                
                if (!remainingIds.isEmpty()) {
                    String queryStr = 'SELECT Id, ' + workspaceSyncIdField + ', WhoId, Who.Name, Who.Type, WhatId, What.Name, What.Type ' +
                                     'FROM Task WHERE ' + workspaceSyncIdField + ' IN :remainingIds ' +
                                     'AND OwnerId = \'' + UserInfo.getUserId() + '\'';
                    for (Task t : Database.query(queryStr)) {
                        String providerId = (String) t.get(workspaceSyncIdField);
                        if (String.isNotBlank(providerId)) {
                            providerIdToTaskId.put(providerId, t.Id);
                            providerIdToStagingId.put(providerId, t.Id); // Use Task Id when no staging
                            foundProviderIds.add(providerId);
                        }
                    }
                }
            }
            
            // Step 3: Query ALL the actual Task records to get WhoId (Lead/Contact)
            Set<Id> taskIds = new Set<Id>(providerIdToTaskId.values());
            Map<Id, Task> taskMap = new Map<Id, Task>();
            
            
            if (!taskIds.isEmpty()) {
                for (Task t : [
                    SELECT Id, WhoId, Who.Name, Who.Type, WhatId, What.Name, What.Type
                    FROM Task
                    WHERE Id IN :taskIds
                ]) {
                    taskMap.put(t.Id, t);
                }
            }
            
            // Step 4: Build the details map with linked record info
            for (String providerId : foundProviderIds) {
                ImportedTaskDetails details = new ImportedTaskDetails();
                details.taskId = providerIdToStagingId.get(providerId);
                
                // Get linked record info from the actual Task
                Id taskId = providerIdToTaskId.get(providerId);
                if (taskId != null && taskMap.containsKey(taskId)) {
                    Task t = taskMap.get(taskId);
                    
                    // Populate WhoId (Lead/Contact) - for backwards compatibility
                    if (t.WhoId != null) {
                        details.whoId = t.WhoId;
                        details.whoName = t.Who.Name;
                        details.whoType = t.Who.Type;
                        
                        // Add to linkedRecords list for pill display
                        LinkedRecordInfo linkedRecord = new LinkedRecordInfo(
                            t.WhoId,
                            t.Who.Name,
                            t.Who.Type
                        );
                        details.linkedRecords.add(linkedRecord);
                    }
                    
                    // Populate WhatId (Account/Opportunity)
                    if (t.WhatId != null) {
                        details.whatId = t.WhatId;
                        details.whatName = t.What.Name;
                        details.whatType = t.What.Type;
                        
                        // Add to linkedRecords list for pill display
                        LinkedRecordInfo linkedRecord = new LinkedRecordInfo(
                            t.WhatId,
                            t.What.Name,
                            t.What.Type
                        );
                        details.linkedRecords.add(linkedRecord);
                    }
                }
                
                detailsMap.put(providerId, details);
            }
            
            // Step 5: Query TaskRelation for additional Contacts/Leads (if Shared Activities enabled)
            if (!taskIds.isEmpty() && Schema.getGlobalDescribe().containsKey('TaskRelation')) {
                queryTaskRelations(taskIds, providerIdToTaskId, detailsMap);
            }
        } catch (Exception e) {
        }

        return detailsMap;
    }

    /**
     * Query TaskRelation records to get all linked Contacts/Leads
     * Adds them to the linkedRecords list (avoiding duplicates)
     */
    private static void queryTaskRelations(
        Set<Id> taskIds,
        Map<String, Id> providerIdToTaskId,
        Map<String, ImportedTaskDetails> detailsMap
    ) {
        try {
            // Build reverse map: Task ID -> Provider ID
            Map<Id, String> taskIdToProviderId = new Map<Id, String>();
            for (String providerId : providerIdToTaskId.keySet()) {
                Id taskId = providerIdToTaskId.get(providerId);
                if (taskId != null) {
                    taskIdToProviderId.put(taskId, providerId);
                }
            }
            
            // Query TaskRelation records
            String queryStr = 'SELECT TaskId, RelationId, Relation.Name, Relation.Type ' +
                             'FROM TaskRelation ' +
                             'WHERE TaskId IN :taskIds ' +
                             'AND Relation.Type IN (\'Contact\', \'Lead\')';
            
            for (SObject trObj : Database.query(queryStr)) {
                Id taskId = (Id) trObj.get('TaskId');
                Id relationId = (Id) trObj.get('RelationId');
                
                // Get Relation.Name and Relation.Type
                SObject relation = trObj.getSObject('Relation');
                String relationName = (String) relation.get('Name');
                String relationType = (String) relation.get('Type');
                
                // Find the corresponding ImportedTaskDetails
                String providerId = taskIdToProviderId.get(taskId);
                if (providerId != null && detailsMap.containsKey(providerId)) {
                    ImportedTaskDetails details = detailsMap.get(providerId);
                    
                    // Check if this relation is already in the list (avoid duplicates)
                    Boolean alreadyExists = false;
                    for (LinkedRecordInfo existing : details.linkedRecords) {
                        if (existing.recordId == relationId) {
                            alreadyExists = true;
                            break;
                        }
                    }
                    
                    if (!alreadyExists) {
                        LinkedRecordInfo linkedRecord = new LinkedRecordInfo(
                            relationId,
                            relationName,
                            relationType
                        );
                        details.linkedRecords.add(linkedRecord);
                    }
                }
            }
        } catch (Exception e) {
        }
    }
    
    /**
     * Get user email from Microsoft Graph using tokens from AI_Workspace_User__c
     */
    private static String getUserEmail() {
        return getUserEmailForProvider('MICROSOFT_TASKS');
    }
    
    /**
     * Get the authenticated user's email address for a specific provider
     * @param providerType 'MICROSOFT_TASKS' or 'GOOGLE_TASKS'
     */
    private static String getUserEmailForProvider(String providerType) {
        try {
            if (providerType == 'GOOGLE_TASKS') {
                // Google Tasks - use Gmail API
                String accessToken = AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_GMAIL);
                if (String.isBlank(accessToken)) {
                    return '';
                }
                
                HttpRequest req = new HttpRequest();
                req.setEndpoint('https://www.googleapis.com/oauth2/v2/userinfo');
                req.setMethod('GET');
                req.setTimeout(30000);
                req.setHeader('Authorization', 'Bearer ' + accessToken);
                
                Http http = new Http();
                HttpResponse response = http.send(req);
                
                if (response.getStatusCode() == 200) {
                    Map<String, Object> userInfo = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    String email = (String) userInfo.get('email');
                    return String.isNotBlank(email) ? email : '';
                }
            } else {
                // Microsoft To-Do - use Graph API
                String accessToken = AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_OUTLOOK);
                if (String.isBlank(accessToken)) {
                    return '';
                }
                
                HttpRequest req = new HttpRequest();
                req.setEndpoint(AIWorkspaceTokenService.getMicrosoftGraphEndpoint() + '/v1.0/me');
                req.setMethod('GET');
                req.setTimeout(30000);
                req.setHeader('Authorization', 'Bearer ' + accessToken);

                Http http = new Http();
                HttpResponse response = http.send(req);

                if (response.getStatusCode() == 200) {
                    Map<String, Object> userInfo = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    String email = (String) userInfo.get('userPrincipalName');
                    if (String.isBlank(email)) {
                        email = (String) userInfo.get('mail');
                    }
                    return String.isNotBlank(email) ? email : '';
                }
            }
        } catch (Exception e) {
        }
        return '';
    }

    /**
     * Extract email addresses from text without using regex
     * NO REGEX - avoids "regex too complicated" errors
     * V2-7889: Made @TestVisible for test coverage
     * @param text The text to search for email addresses
     * @return Set of lowercase email addresses found
     */
    @TestVisible
    private static Set<String> extractEmailsSimple(String text) {
        Set<String> emails = new Set<String>();
        if (String.isBlank(text)) {
            return emails;
        }

        // Extract words by scanning character by character - NO REGEX
        List<String> words = splitByDelimiters(text);

        for (String word : words) {
            word = word.trim();
            if (isValidEmail(word)) {
                emails.add(word.toLowerCase());
            }
        }

        return emails;
    }

    /**
     * Split text by common delimiters without regex
     * V2-7889: Made @TestVisible for test coverage
     */
    @TestVisible
    private static List<String> splitByDelimiters(String text) {
        List<String> words = new List<String>();
        String currentWord = '';
        String delimiters = ' \t\n\r,;:<>()[]{}"\'\\/|';

        for (Integer i = 0; i < text.length(); i++) {
            String ch = text.substring(i, i + 1);
            if (delimiters.contains(ch)) {
                if (String.isNotBlank(currentWord)) {
                    words.add(currentWord);
                    currentWord = '';
                }
            } else {
                currentWord += ch;
            }
        }

        if (String.isNotBlank(currentWord)) {
            words.add(currentWord);
        }

        return words;
    }

    /**
     * Check if a string looks like a valid email address
     * NO REGEX - simple character validation
     * V2-7889: Made @TestVisible for test coverage
     */
    @TestVisible
    private static Boolean isValidEmail(String word) {
        if (String.isBlank(word) || word.length() < 5) {
            return false;
        }

        // Must contain exactly one @
        Integer atPos = word.indexOf('@');
        if (atPos < 1 || atPos == word.length() - 1) {
            return false;
        }

        // Check for multiple @
        if (word.indexOf('@', atPos + 1) > -1) {
            return false;
        }

        // Domain must have at least one dot
        String domain = word.substring(atPos + 1);
        Integer dotPos = domain.lastIndexOf('.');
        if (dotPos < 1 || dotPos == domain.length() - 1) {
            return false;
        }

        // TLD must be at least 2 characters
        String tld = domain.substring(dotPos + 1);
        if (tld.length() < 2) {
            return false;
        }

        // Basic character validation - no spaces or obvious invalid chars
        String invalidChars = ' \t\n\r<>()[]{}';
        for (Integer i = 0; i < invalidChars.length(); i++) {
            if (word.contains(invalidChars.substring(i, i + 1))) {
                return false;
            }
        }

        return true;
    }
    
    
    /**
     * Associate tasks from modal with selected Contacts/Leads/Accounts/Opportunities
     * This method will be called from the aiAutoRecordMatchingModal component
     * 
     * @param selections List of selections containing task IDs and associated record IDs
     * @param providerType Provider type (MICROSOFT_TASKS or GOOGLE_TASKS)
     * @return Map with success status and counts
     */
    @AuraEnabled
    public static Map<String, Object> associateTasksFromModal(
        List<Map<String, Object>> selections,
        String providerType
    ) {
        
        Map<String, Object> result = new Map<String, Object>{
            'success' => true,
            'successCount' => 0,
            'failedCount' => 0,
            'duplicateCount' => 0,
            'excludedCount' => 0,
            'errors' => new List<String>()
        };
        
        try {
            if (selections == null || selections.isEmpty()) {
                throw new IllegalArgumentException('No selections provided');
            }
            
            // Extract task IDs
            List<String> taskIds = new List<String>();
            for (Map<String, Object> selection : selections) {
                taskIds.add((String) selection.get('messageId')); // Using messageId for consistency with email modal
            }
            
            
            // Import the tasks first - call appropriate method based on provider
            ImportResult importResult;
            if (providerType == 'GOOGLE_TASKS') {
                importResult = importGoogleTasks(taskIds);
            } else {
                // Handle MICROSOFT_TASKS
                importResult = importTasks(taskIds);
            }
            
            // Check if there were any errors
            if (importResult.errors != null && !importResult.errors.isEmpty()) {
                result.put('success', false);
                result.put('failedCount', importResult.failedCount);
                ((List<String>) result.get('errors')).addAll(importResult.errors);
                return result;
            }
            
            result.put('successCount', importResult.successCount);
            result.put('failedCount', importResult.failedCount);
            
            // Link tasks to Contacts/Leads/Accounts/Opportunities
            if (!importResult.taskIds.isEmpty()) {
                linkTasksToRecords(importResult.taskIds, selections);
            } else {
            }
            
            // NOTE: Notifications are already sent by:
            // 1. createTasksFromStagingInlineWithEmail -> sendTaskNotifications (in AIWorkspaceStagingCreator)
            // 2. importTasks -> sendTaskImportNotifications (at line 722)
            // No additional notification call needed here
            
        } catch (Exception e) {
            result.put('success', false);
            result.put('failedCount', selections != null ? selections.size() : 0);
            ((List<String>) result.get('errors')).add(e.getMessage());
        }
        
        return result;
    }
    
    /**
     * Link Tasks to Salesforce records (Contacts, Leads, Accounts, Opportunities)
     * Respects Salesforce limitations:
     * - WhatId can be set to ONE Opportunity or Account (Opportunity takes priority)
     * - TaskRelation can link to multiple Contacts/Leads (if Shared Activities enabled)
     * - If TaskRelation NOT available, fallback to WhoId (single Contact or Lead)
     * - CRITICAL: Cannot link to Lead if WhatId is set (Account/Opportunity)
     * 
     * @param taskIds List of created Task IDs
     * @param selections List of user selections with contactIds, leadIds, accountId, opportunityId
     */
    private static void linkTasksToRecords(List<Id> taskIds, List<Map<String, Object>> selections) {
        
        if (taskIds == null || taskIds.isEmpty() || selections == null || selections.isEmpty()) {
            return;
        }
        
        
        // Check if TaskRelation is available (Shared Activities enabled)
        Boolean hasTaskRelation = Schema.getGlobalDescribe().containsKey('TaskRelation');
        
        // Build map of task index to selection
        // Assumption: taskIds are in the same order as successful selections
        Map<Integer, Map<String, Object>> taskIndexToSelection = new Map<Integer, Map<String, Object>>();
        Integer successfulIndex = 0;
        for (Map<String, Object> selection : selections) {
            if (successfulIndex < taskIds.size()) {
                taskIndexToSelection.put(successfulIndex, selection);
                successfulIndex++;
            }
        }
        
        // Step 1: Update Tasks with WhatId (Account or Opportunity) and WhoId (if TaskRelation not available)
        List<Task> tasksToUpdate = new List<Task>();
        Map<Id, Boolean> taskIdHasWhatId = new Map<Id, Boolean>();
        Map<Id, List<Id>> taskIdToRelationIds = new Map<Id, List<Id>>();
        
        for (Integer i = 0; i < taskIds.size(); i++) {
            Id taskId = taskIds[i];
            Map<String, Object> selection = taskIndexToSelection.get(i);
            
            
            if (selection == null) {
                continue;
            }
            
            String opportunityId = (String) selection.get('opportunityId');
            String accountId = (String) selection.get('accountId');
            List<Object> contactIdsList = (List<Object>) selection.get('contactIds');
            List<Object> leadIdsList = (List<Object>) selection.get('leadIds');
            
            // Validate and filter out invalid IDs (e.g., staging record IDs)
            if (String.isNotBlank(opportunityId) && !isValidOpportunityId(opportunityId)) {
                opportunityId = null;
            }
            if (String.isNotBlank(accountId) && !isValidAccountId(accountId)) {
                accountId = null;
            }
            
            Task t = new Task(Id = taskId);
            Boolean hasWhatId = false;
            
            // Priority: Opportunity first, then Account
            if (String.isNotBlank(opportunityId)) {
                t.WhatId = opportunityId;
                hasWhatId = true;
            } else if (String.isNotBlank(accountId)) {
                t.WhatId = accountId;
                hasWhatId = true;
            }
            
            taskIdHasWhatId.put(taskId, hasWhatId);
            
            // If TaskRelation NOT available, set WhoId to first Contact or Lead
            if (!hasTaskRelation) {
                if (contactIdsList != null && !contactIdsList.isEmpty()) {
                    Id firstContactId = (Id) contactIdsList[0];
                    if (isValidContactId(String.valueOf(firstContactId))) {
                        t.WhoId = firstContactId;
                    }
                } else if (leadIdsList != null && !leadIdsList.isEmpty()) {
                    Id firstLeadId = (Id) leadIdsList[0];
                    if (isValidLeadId(String.valueOf(firstLeadId))) {
                        t.WhoId = firstLeadId;
                    }
                }
            } else {
                // TaskRelation available - collect relation IDs
                List<Id> relationIds = new List<Id>();
                
                // Add Contacts (with validation)
                if (contactIdsList != null && !contactIdsList.isEmpty()) {
                    for (Object contactIdObj : contactIdsList) {
                        String contactIdStr = String.valueOf(contactIdObj);
                        if (isValidContactId(contactIdStr)) {
                            relationIds.add((Id) contactIdObj);
                        } else {
                        }
                    }
                }
                
                // Add Leads ONLY if WhatId is NOT set (Salesforce restriction)
                if (!hasWhatId && leadIdsList != null && !leadIdsList.isEmpty()) {
                    for (Object leadIdObj : leadIdsList) {
                        String leadIdStr = String.valueOf(leadIdObj);
                        if (isValidLeadId(leadIdStr)) {
                            relationIds.add((Id) leadIdObj);
                        } else {
                        }
                    }
                } else if (hasWhatId && leadIdsList != null && !leadIdsList.isEmpty()) {
                }
                
                if (!relationIds.isEmpty()) {
                    taskIdToRelationIds.put(taskId, relationIds);
                }
            }
            
            tasksToUpdate.add(t);
        }
        
        
        // Update Tasks with WhatId and WhoId (if applicable) - with FLS enforcement
        if (!tasksToUpdate.isEmpty()) {
            // Check object-level update permission
            // Use FLSCheck for FLS/OLS enforcement
            List<Task> accessibleTasks = FLSCheck.getInstance().updateCheck(tasksToUpdate);
            
            if (accessibleTasks == null || accessibleTasks.isEmpty()) {
            } else {
                // V2-7889: Use FLSCheck for FLS/CRUD enforcement
                try {
                    FLSCheck.getInstance().updateDML(accessibleTasks, false);
                } catch (Exception e) {
                    // Throw exception to show user which field has invalid ID
                    throw new AuraHandledException('Error linking task: ' + e.getMessage());
                }
            }
        }
        
        // Step 2: Create TaskRelation records (if Shared Activities enabled)
        if (hasTaskRelation && !taskIdToRelationIds.isEmpty()) {
            createTaskRelations(taskIdToRelationIds);
        }
        
    }
    
    /**
     * Validate if the ID is a valid Contact ID (starts with '003')
     */
    private static Boolean isValidContactId(String idStr) {
        return String.isNotBlank(idStr) && idStr.startsWith('003');
    }
    
    /**
     * Validate if the ID is a valid Lead ID (starts with '00Q')
     */
    private static Boolean isValidLeadId(String idStr) {
        return String.isNotBlank(idStr) && idStr.startsWith('00Q');
    }
    
    /**
     * Validate if the ID is a valid Account ID (starts with '001')
     */
    private static Boolean isValidAccountId(String idStr) {
        return String.isNotBlank(idStr) && idStr.startsWith('001');
    }
    
    /**
     * Validate if the ID is a valid Opportunity ID (starts with '006')
     */
    private static Boolean isValidOpportunityId(String idStr) {
        return String.isNotBlank(idStr) && idStr.startsWith('006');
    }
}