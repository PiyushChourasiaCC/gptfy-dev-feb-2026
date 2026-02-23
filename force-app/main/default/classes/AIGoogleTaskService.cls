/**
 * Google Tasks API service
 * Handles low-level API calls for task retrieval from Google Tasks
 *
 * AUTHENTICATION: Uses access tokens from AI_Workspace_User__c
 * Tokens are retrieved and refreshed automatically via AIWorkspaceTokenService
 *
 * Google Tasks API Reference:
 * - List task lists: GET /tasks/v1/users/@me/lists
 * - Get tasks: GET /tasks/v1/lists/{taskListId}/tasks
 */
public with sharing class AIGoogleTaskService {

    private static final Integer DEFAULT_TIMEOUT = 120000;
    private static final Integer MAX_RESULTS = 50;

    // Google Tasks API endpoint
    private static final String TASKS_API_ENDPOINT = 'https://tasks.googleapis.com';
    
    /**
     * Get access token for the current user
     * Retrieves from AI_Workspace_User__c and refreshes if needed
     */
    private static String getAccessToken() {
        return AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_GMAIL);
    }

    /**
     * Inner class representing a normalized to-do task
     * Compatible with AIMicrosoftTaskService.ToDoTask for unified handling
     */
    public class ToDoTask {
        @AuraEnabled public String taskId;
        @AuraEnabled public String listId;
        @AuraEnabled public String listName;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String status; // needsAction, completed
        @AuraEnabled public String importance; // normal (Google doesn't have importance levels)
        @AuraEnabled public DateTime dueDateTime;
        @AuraEnabled public DateTime completedDateTime;
        @AuraEnabled public DateTime createdDateTime;
        @AuraEnabled public DateTime lastModifiedDateTime;
        @AuraEnabled public Boolean isReminderOn;
        @AuraEnabled public DateTime reminderDateTime;
        @AuraEnabled public String provider;
        @AuraEnabled public Boolean isImported;
        // Parent task for subtasks
        @AuraEnabled public String parentTaskId;
        // Position in the list
        @AuraEnabled public String position;
        // Linked record info (populated after import)
        @AuraEnabled public Id linkedRecordId;
        @AuraEnabled public String linkedRecordName;
        @AuraEnabled public String linkedRecordType;
        @AuraEnabled public List<LinkedRecord> linkedRecords;

        public ToDoTask() {
            this.provider = 'GOOGLE_TASKS';
            this.isImported = false;
            this.importance = 'normal'; // Google doesn't have importance
            this.linkedRecords = new List<LinkedRecord>();
        }
    }
    
    /**
     * Represents a linked Salesforce record (Contact, Lead, Account, Opportunity)
     */
    public class LinkedRecord {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String recordType;
        
        public LinkedRecord(Id recordId, String recordName, String recordType) {
            this.recordId = recordId;
            this.recordName = recordName;
            this.recordType = recordType;
        }
    }

    /**
     * Inner class representing a task list
     */
    public class TaskList {
        @AuraEnabled public String listId;
        @AuraEnabled public String displayName;
        @AuraEnabled public DateTime updatedDateTime;
    }

    /**
     * Fetch all task lists for the user
     * @return List of task lists
     */
    public static List<TaskList> getTaskLists() {
        List<TaskList> taskLists = new List<TaskList>();

        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            String endpoint = TASKS_API_ENDPOINT + '/tasks/v1/users/@me/lists';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Accept', 'application/json');

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                taskLists = parseTaskListsResponse(response.getBody());
            } else if (response.getStatusCode() == 401) {
                throw new TaskServiceException('Authentication expired. Please reconnect your Google account.');
            } else if (response.getStatusCode() == 403) {
                throw new TaskServiceException('Google Tasks access not granted. Please ensure tasks.readonly scope is enabled and reconnect your Google account.');
            } else {
                System.debug('Task Lists API error: ' + response.getStatusCode() + ' - ' + response.getBody());
                throw new TaskServiceException('Failed to fetch task lists: ' + response.getStatusCode());
            }
        } catch (TaskServiceException e) {
            throw e;
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            throw new TaskServiceException('Authentication required: ' + e.getMessage());
        } catch (Exception e) {
            System.debug('Task service error: ' + e.getMessage());
            throw new TaskServiceException('Task service error: ' + e.getMessage());
        }

        return taskLists;
    }

    /**
     * Fetch tasks from all task lists
     * @param maxResults Maximum number of tasks to return (default 50)
     * @param includeCompleted Whether to include completed tasks
     * @return List of normalized tasks
     */
    public static List<ToDoTask> getAllTasks(Integer maxResults, Boolean includeCompleted) {
        List<ToDoTask> allTasks = new List<ToDoTask>();

        if (maxResults == null || maxResults <= 0) {
            maxResults = MAX_RESULTS;
        }

        // Get all task lists first
        List<TaskList> taskLists = getTaskLists();

        if (taskLists.isEmpty()) {
            return allTasks;
        }

        // Fetch all tasks from each list - use higher limit to ensure we get all tasks
        Integer tasksPerList = Math.max(maxResults, 100);

        for (TaskList tl : taskLists) {
            try {
                List<ToDoTask> listTasks = getTasksFromList(tl.listId, tl.displayName, tasksPerList, includeCompleted);
                allTasks.addAll(listTasks);
            } catch (Exception e) {
                System.debug('Error fetching tasks from list ' + tl.displayName + ': ' + e.getMessage());
                // Continue with other lists
            }
        }

        // Trim to max results
        if (allTasks.size() > maxResults) {
            List<ToDoTask> trimmed = new List<ToDoTask>();
            for (Integer i = 0; i < maxResults; i++) {
                trimmed.add(allTasks[i]);
            }
            return trimmed;
        }

        return allTasks;
    }

    /**
     * Fetch tasks from a specific task list
     * @param listId The task list ID
     * @param listName The task list display name (for reference)
     * @param maxResults Maximum number of tasks to return
     * @param includeCompleted Whether to include completed tasks
     * @return List of tasks from this list
     */
    public static List<ToDoTask> getTasksFromList(String listId, String listName, Integer maxResults, Boolean includeCompleted) {
        List<ToDoTask> tasks = new List<ToDoTask>();

        if (String.isBlank(listId)) {
            return tasks;
        }

        if (maxResults == null || maxResults <= 0) {
            maxResults = MAX_RESULTS;
        }

        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            // Build endpoint with parameters
            String endpoint = TASKS_API_ENDPOINT + '/tasks/v1/lists/' + EncodingUtil.urlEncode(listId, 'UTF-8') + '/tasks';
            endpoint += '?maxResults=' + String.valueOf(maxResults);
            
            // Google Tasks API: showCompleted and showHidden parameters
            if (includeCompleted) {
                endpoint += '&showCompleted=true&showHidden=true';
            } else {
                endpoint += '&showCompleted=false';
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Accept', 'application/json');

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                tasks = parseTasksResponse(response.getBody(), listId, listName);
            } else if (response.getStatusCode() == 401) {
                throw new TaskServiceException('Authentication expired. Please reconnect your Google account.');
            } else {
                System.debug('Tasks API error for list ' + listId + ': ' + response.getStatusCode() + ' - ' + response.getBody());
                throw new TaskServiceException('Failed to fetch tasks: ' + response.getStatusCode());
            }
        } catch (TaskServiceException e) {
            throw e;
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            throw new TaskServiceException('Authentication required: ' + e.getMessage());
        } catch (Exception e) {
            System.debug('Task service error: ' + e.getMessage());
            throw new TaskServiceException('Task service error: ' + e.getMessage());
        }

        return tasks;
    }

    /**
     * Fetch tasks from all task lists with offset-based pagination
     * @param maxResults Maximum number of tasks to return
     * @param offset Number of tasks to skip (for pagination)
     * @param includeCompleted Whether to include completed tasks
     * @return List of normalized tasks
     */
    public static List<ToDoTask> getAllTasksWithOffset(Integer maxResults, Integer offset, Boolean includeCompleted) {
        List<ToDoTask> allTasks = new List<ToDoTask>();

        if (maxResults == null || maxResults <= 0) {
            maxResults = MAX_RESULTS;
        }
        if (offset == null || offset < 0) {
            offset = 0;
        }

        // Get all task lists first
        List<TaskList> taskLists = getTaskLists();

        if (taskLists.isEmpty()) {
            return allTasks;
        }

        // Fetch all tasks from each list - use higher limit to ensure we get all
        Integer totalNeeded = offset + maxResults;
        Integer tasksPerList = Math.max(totalNeeded, 100);

        List<ToDoTask> fetchedTasks = new List<ToDoTask>();
        for (TaskList tl : taskLists) {
            try {
                List<ToDoTask> listTasks = getTasksFromList(tl.listId, tl.displayName, tasksPerList, includeCompleted);
                fetchedTasks.addAll(listTasks);
            } catch (Exception e) {
                System.debug('Error fetching tasks from list ' + tl.displayName + ': ' + e.getMessage());
                // Continue with other lists
            }
        }

        // Apply offset and limit
        for (Integer i = offset; i < fetchedTasks.size() && allTasks.size() < maxResults; i++) {
            allTasks.add(fetchedTasks[i]);
        }

        return allTasks;
    }

    /**
     * Fetch tasks from a specific task list with offset-based pagination
     * @param listId The task list ID
     * @param listName The task list display name (for reference)
     * @param maxResults Maximum number of tasks to return
     * @param offset Number of tasks to skip (for pagination)
     * @param includeCompleted Whether to include completed tasks
     * @return List of tasks from this list
     */
    public static List<ToDoTask> getTasksFromListWithOffset(String listId, String listName, Integer maxResults, Integer offset, Boolean includeCompleted) {
        List<ToDoTask> tasks = new List<ToDoTask>();

        if (String.isBlank(listId)) {
            return tasks;
        }

        if (maxResults == null || maxResults <= 0) {
            maxResults = MAX_RESULTS;
        }
        if (offset == null || offset < 0) {
            offset = 0;
        }

        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            // Fetch offset + maxResults to handle pagination
            Integer fetchLimit = offset + maxResults;
            
            // Build endpoint with parameters
            String endpoint = TASKS_API_ENDPOINT + '/tasks/v1/lists/' + EncodingUtil.urlEncode(listId, 'UTF-8') + '/tasks';
            endpoint += '?maxResults=' + String.valueOf(fetchLimit);
            
            // Google Tasks API: showCompleted and showHidden parameters
            if (includeCompleted) {
                endpoint += '&showCompleted=true&showHidden=true';
            } else {
                endpoint += '&showCompleted=false';
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Accept', 'application/json');

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                List<ToDoTask> allTasks = parseTasksResponse(response.getBody(), listId, listName);
                
                // Apply offset and limit
                for (Integer i = offset; i < allTasks.size() && tasks.size() < maxResults; i++) {
                    tasks.add(allTasks[i]);
                }
            } else if (response.getStatusCode() == 401) {
                throw new TaskServiceException('Authentication expired. Please reconnect your Google account.');
            } else {
                System.debug('Tasks API error for list ' + listId + ': ' + response.getStatusCode() + ' - ' + response.getBody());
                throw new TaskServiceException('Failed to fetch tasks: ' + response.getStatusCode());
            }
        } catch (TaskServiceException e) {
            throw e;
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            throw new TaskServiceException('Authentication required: ' + e.getMessage());
        } catch (Exception e) {
            System.debug('Task service error: ' + e.getMessage());
            throw new TaskServiceException('Task service error: ' + e.getMessage());
        }

        return tasks;
    }

    /**
     * Fetch a single task by ID
     * @param listId The task list ID
     * @param taskId The task ID
     * @return The task details
     */
    public static ToDoTask getTask(String listId, String taskId) {
        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            String endpoint = TASKS_API_ENDPOINT + '/tasks/v1/lists/' 
                + EncodingUtil.urlEncode(listId, 'UTF-8') + '/tasks/'
                + EncodingUtil.urlEncode(taskId, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Accept', 'application/json');

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> taskData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                return parseTaskData(taskData, listId, null);
            } else if (response.getStatusCode() == 404) {
                throw new TaskServiceException('Task not found');
            } else {
                throw new TaskServiceException('Failed to fetch task: ' + response.getStatusCode());
            }
        } catch (TaskServiceException e) {
            throw e;
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            throw new TaskServiceException('Authentication required: ' + e.getMessage());
        } catch (Exception e) {
            throw new TaskServiceException('Error fetching task: ' + e.getMessage());
        }
    }

    /**
     * Check if Google Tasks API is accessible with current credentials
     * @return true if authenticated and tasks are accessible
     */
    public static Boolean isTaskAccessible() {
        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(TASKS_API_ENDPOINT + '/tasks/v1/users/@me/lists?maxResults=1');
            req.setMethod('GET');
            req.setTimeout(30000);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Accept', 'application/json');

            Http http = new Http();
            HttpResponse response = http.send(req);

            return response.getStatusCode() == 200;
        } catch (Exception e) {
            System.debug('Task access check failed: ' + e.getMessage());
            return false;
        }
    }

    /**
     * Parse the task lists response from Google Tasks API
     * Response format:
     * {
     *   "kind": "tasks#taskLists",
     *   "items": [
     *     { "kind": "tasks#taskList", "id": "...", "title": "...", "updated": "..." }
     *   ]
     * }
     */
    private static List<TaskList> parseTaskListsResponse(String responseBody) {
        List<TaskList> taskLists = new List<TaskList>();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> listArray = (List<Object>) parsed.get('items');

        if (listArray != null) {
            for (Object listObj : listArray) {
                Map<String, Object> listData = (Map<String, Object>) listObj;
                TaskList tl = new TaskList();
                tl.listId = (String) listData.get('id');
                tl.displayName = (String) listData.get('title');
                tl.updatedDateTime = parseDateTime((String) listData.get('updated'));
                taskLists.add(tl);
            }
        }

        return taskLists;
    }

    /**
     * Parse the tasks response from Google Tasks API
     * Response format:
     * {
     *   "kind": "tasks#tasks",
     *   "items": [
     *     { "kind": "tasks#task", "id": "...", "title": "...", ... }
     *   ]
     * }
     */
    private static List<ToDoTask> parseTasksResponse(String responseBody, String listId, String listName) {
        List<ToDoTask> tasks = new List<ToDoTask>();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> taskList = (List<Object>) parsed.get('items');

        if (taskList != null) {
            for (Object taskObj : taskList) {
                Map<String, Object> taskData = (Map<String, Object>) taskObj;
                ToDoTask task = parseTaskData(taskData, listId, listName);
                if (task != null) {
                    tasks.add(task);
                }
            }
        }

        return tasks;
    }

    /**
     * Parse a single task data map into ToDoTask object
     * Google Tasks task format:
     * {
     *   "kind": "tasks#task",
     *   "id": "...",
     *   "title": "...",
     *   "notes": "...",
     *   "status": "needsAction" | "completed",
     *   "due": "2024-01-15T00:00:00.000Z",
     *   "completed": "2024-01-14T12:00:00.000Z",
     *   "updated": "2024-01-14T12:00:00.000Z",
     *   "parent": "parentTaskId",
     *   "position": "00000000000000000001"
     * }
     */
    private static ToDoTask parseTaskData(Map<String, Object> taskData, String listId, String listName) {
        if (taskData == null) {
            return null;
        }

        ToDoTask task = new ToDoTask();
        task.taskId = (String) taskData.get('id');
        task.listId = listId;
        task.listName = listName;
        task.title = (String) taskData.get('title');
        task.body = (String) taskData.get('notes'); // Google uses "notes" for task body
        task.parentTaskId = (String) taskData.get('parent');
        task.position = (String) taskData.get('position');
        
        // Map Google status to normalized status
        String googleStatus = (String) taskData.get('status');
        task.status = mapGoogleStatus(googleStatus);
        
        // Google doesn't have importance levels
        task.importance = 'normal';

        // Parse dates
        task.dueDateTime = parseDateTime((String) taskData.get('due'));
        task.completedDateTime = parseDateTime((String) taskData.get('completed'));
        task.lastModifiedDateTime = parseDateTime((String) taskData.get('updated'));
        
        // Google Tasks doesn't have reminders in the same way
        task.isReminderOn = false;

        return task;
    }

    /**
     * Map Google Tasks status to normalized status
     * Google: "needsAction", "completed"
     * Normalized: "notStarted", "inProgress", "completed"
     */
    private static String mapGoogleStatus(String googleStatus) {
        if (googleStatus == 'completed') {
            return 'completed';
        }
        // Google only has needsAction and completed
        // Map needsAction to notStarted
        return 'notStarted';
    }

    /**
     * Parse ISO 8601 datetime string to Apex DateTime
     * Google format: "2024-01-15T14:00:00.000Z" or "2024-01-15T00:00:00.000Z" (for dates)
     */
    private static DateTime parseDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }

        try {
            // Remove fractional seconds if present
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
                // Add back the Z if it was after the fractional seconds
                if (!dateTimeStr.endsWith('Z')) {
                    dateTimeStr += 'Z';
                }
            }

            // Remove trailing Z
            dateTimeStr = dateTimeStr.replace('Z', '');

            // Parse the datetime
            return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
        } catch (Exception e) {
            System.debug('Error parsing datetime: ' + dateTimeStr + ' - ' + e.getMessage());
            return null;
        }
    }

    /**
     * Custom exception for task service errors
     */
    public class TaskServiceException extends Exception {}
}