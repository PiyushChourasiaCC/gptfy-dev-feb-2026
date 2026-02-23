/**
 * Microsoft Graph To-Do API service
 * Handles low-level API calls for task retrieval from Microsoft To-Do
 *
 * AUTHENTICATION: Uses access tokens from AI_Workspace_User__c
 * Tokens are retrieved and refreshed automatically via AIWorkspaceTokenService
 *
 * Microsoft To-Do API Reference:
 * - List task lists: GET /me/todo/lists
 * - Get tasks: GET /me/todo/lists/{listId}/tasks
 */
public with sharing class AIMicrosoftTaskService {

    private static final Integer DEFAULT_TIMEOUT = 120000;
    private static final Integer MAX_RESULTS = 50;

    // Microsoft Graph API endpoint (direct URL, not Named Credential)
    private static String getGraphApiEndpoint() {
        return AIWorkspaceTokenService.getMicrosoftGraphEndpoint();
    }
    
    /**
     * Get access token for the current user
     * Retrieves from AI_Workspace_User__c and refreshes if needed
     */
    private static String getAccessToken() {
        return AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_OUTLOOK);
    }

    /**
     * Inner class representing a normalized to-do task
     */
    public class ToDoTask {
        @AuraEnabled public String taskId;
        @AuraEnabled public String listId;
        @AuraEnabled public String listName;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String status; // notStarted, inProgress, completed
        @AuraEnabled public String importance; // low, normal, high
        @AuraEnabled public DateTime dueDateTime;
        @AuraEnabled public DateTime completedDateTime;
        @AuraEnabled public DateTime createdDateTime;
        @AuraEnabled public DateTime lastModifiedDateTime;
        @AuraEnabled public Boolean isReminderOn;
        @AuraEnabled public DateTime reminderDateTime;
        @AuraEnabled public String provider;
        @AuraEnabled public Boolean isImported;
        // Linked record info (populated after import)
        @AuraEnabled public Id linkedRecordId;
        @AuraEnabled public String linkedRecordName;
        @AuraEnabled public String linkedRecordType;
        @AuraEnabled public List<LinkedRecord> linkedRecords;

        public ToDoTask() {
            this.provider = 'MICROSOFT_TASKS';
            this.isImported = false;
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
        @AuraEnabled public Boolean isOwner;
        @AuraEnabled public Boolean isShared;
        @AuraEnabled public String wellknownListName; // defaultList, flaggedEmails, etc.
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
            
            String endpoint = getGraphApiEndpoint() + '/v1.0/me/todo/lists';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                taskLists = parseTaskListsResponse(response.getBody());
            } else {
                System.debug('Task Lists API error: ' + response.getStatusCode() + ' - ' + response.getBody());
                throw new TaskServiceException('Failed to fetch task lists: ' + response.getStatusCode());
            }
        } catch (TaskServiceException e) {
            throw e;
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

        // Fetch all tasks from each list - we want to get the full set
        // Use a higher limit per list to ensure we get all tasks
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
            
            // Build endpoint with OData parameters for proper pagination
            // Microsoft Graph default page size is only ~10-25, so we must specify $top
            // Fetch more than needed to handle filtering in Apex
            Integer fetchLimit = includeCompleted ? maxResults : maxResults * 2;
            fetchLimit = Math.min(fetchLimit, 200); // Graph API max is typically 200
            
            String endpoint = getGraphApiEndpoint() + '/v1.0/me/todo/lists/'
                + EncodingUtil.urlEncode(listId, 'UTF-8') + '/tasks'
                + '?$top=' + fetchLimit;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                List<ToDoTask> allTasks = parseTasksResponse(response.getBody(), listId, listName);

                // Filter and limit in Apex
                for (ToDoTask t : allTasks) {
                    // Skip completed tasks if not including them
                    if (!includeCompleted && t.status == 'completed') {
                        continue;
                    }
                    tasks.add(t);
                    // Stop when we reach max results
                    if (tasks.size() >= maxResults) {
                        break;
                    }
                }
            } else {
                System.debug('Tasks API error for list ' + listId + ': ' + response.getStatusCode() + ' - ' + response.getBody());
                throw new TaskServiceException('Failed to fetch tasks: ' + response.getStatusCode());
            }
        } catch (TaskServiceException e) {
            throw e;
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
            // When filtering out completed tasks, we need to fetch more to account for the filter
            Integer baseLimit = offset + maxResults;
            Integer fetchLimit = includeCompleted ? baseLimit : baseLimit * 2;
            fetchLimit = Math.min(fetchLimit, 200); // Graph API max is typically 200
            
            String endpoint = getGraphApiEndpoint() + '/v1.0/me/todo/lists/'
                + EncodingUtil.urlEncode(listId, 'UTF-8') + '/tasks'
                + '?$top=' + fetchLimit;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                List<ToDoTask> allTasks = parseTasksResponse(response.getBody(), listId, listName);

                // Filter, apply offset, and limit in Apex
                Integer currentIndex = 0;
                for (ToDoTask t : allTasks) {
                    // Skip completed tasks if not including them
                    if (!includeCompleted && t.status == 'completed') {
                        continue;
                    }
                    
                    // Skip tasks before offset
                    if (currentIndex < offset) {
                        currentIndex++;
                        continue;
                    }
                    
                    tasks.add(t);
                    currentIndex++;
                    
                    // Stop when we reach max results
                    if (tasks.size() >= maxResults) {
                        break;
                    }
                }
            } else {
                System.debug('Tasks API error for list ' + listId + ': ' + response.getStatusCode() + ' - ' + response.getBody());
                throw new TaskServiceException('Failed to fetch tasks: ' + response.getStatusCode());
            }
        } catch (TaskServiceException e) {
            throw e;
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
            
            String endpoint = getGraphApiEndpoint() + '/v1.0/me/todo/lists/'
                + EncodingUtil.urlEncode(listId, 'UTF-8') + '/tasks/'
                + EncodingUtil.urlEncode(taskId, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> taskData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                return parseTaskData(taskData, listId, null);
            } else {
                throw new TaskServiceException('Failed to fetch task: ' + response.getStatusCode());
            }
        } catch (TaskServiceException e) {
            throw e;
        } catch (Exception e) {
            throw new TaskServiceException('Error fetching task: ' + e.getMessage());
        }
    }

    /**
     * Check if To-Do API is accessible with current credentials
     * @return true if authenticated and tasks are accessible
     */
    public static Boolean isTaskAccessible() {
        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(getGraphApiEndpoint() + '/v1.0/me/todo/lists');
            req.setMethod('GET');
            req.setTimeout(30000);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            return response.getStatusCode() == 200;
        } catch (Exception e) {
            System.debug('Task access check failed: ' + e.getMessage());
            return false;
        }
    }

    /**
     * Parse the task lists response from Graph API
     */
    private static List<TaskList> parseTaskListsResponse(String responseBody) {
        List<TaskList> taskLists = new List<TaskList>();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> listArray = (List<Object>) parsed.get('value');

        if (listArray != null) {
            for (Object listObj : listArray) {
                Map<String, Object> listData = (Map<String, Object>) listObj;
                TaskList tl = new TaskList();
                tl.listId = (String) listData.get('id');
                tl.displayName = (String) listData.get('displayName');
                tl.isOwner = listData.get('isOwner') == true;
                tl.isShared = listData.get('isShared') == true;
                tl.wellknownListName = (String) listData.get('wellknownListName');
                taskLists.add(tl);
            }
        }

        return taskLists;
    }

    /**
     * Parse the tasks response from Graph API
     */
    private static List<ToDoTask> parseTasksResponse(String responseBody, String listId, String listName) {
        List<ToDoTask> tasks = new List<ToDoTask>();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> taskList = (List<Object>) parsed.get('value');

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
        task.status = (String) taskData.get('status');
        task.importance = (String) taskData.get('importance');
        task.isReminderOn = taskData.get('isReminderOn') == true;

        // Parse body (rich text content)
        Map<String, Object> body = (Map<String, Object>) taskData.get('body');
        if (body != null) {
            String content = (String) body.get('content');
            String contentType = (String) body.get('contentType');
            if (contentType == 'html' && String.isNotBlank(content)) {
                task.body = stripHtml(content);
            } else {
                task.body = content;
            }
        }

        // Parse dates
        Map<String, Object> dueDateObj = (Map<String, Object>) taskData.get('dueDateTime');
        if (dueDateObj != null) {
            task.dueDateTime = parseGraphDateTime((String) dueDateObj.get('dateTime'));
        }

        Map<String, Object> completedDateObj = (Map<String, Object>) taskData.get('completedDateTime');
        if (completedDateObj != null) {
            task.completedDateTime = parseGraphDateTime((String) completedDateObj.get('dateTime'));
        }

        Map<String, Object> reminderDateObj = (Map<String, Object>) taskData.get('reminderDateTime');
        if (reminderDateObj != null) {
            task.reminderDateTime = parseGraphDateTime((String) reminderDateObj.get('dateTime'));
        }

        // Parse simple datetime strings
        task.createdDateTime = parseSimpleDateTime((String) taskData.get('createdDateTime'));
        task.lastModifiedDateTime = parseSimpleDateTime((String) taskData.get('lastModifiedDateTime'));

        return task;
    }

    /**
     * Parse Microsoft Graph datetime object to Apex DateTime
     * Graph format: "2024-01-15T14:00:00.0000000"
     */
    private static DateTime parseGraphDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }

        try {
            // Remove fractional seconds if present
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
            }

            // Remove trailing Z if present
            dateTimeStr = dateTimeStr.replace('Z', '');

            // Parse the datetime
            return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
        } catch (Exception e) {
            System.debug('Error parsing datetime: ' + dateTimeStr + ' - ' + e.getMessage());
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
            // Handle ISO 8601 format with timezone
            if (dateTimeStr.contains('Z')) {
                dateTimeStr = dateTimeStr.replace('Z', '');
            }
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
            }
            return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
        } catch (Exception e) {
            System.debug('Error parsing datetime: ' + dateTimeStr + ' - ' + e.getMessage());
            return null;
        }
    }

    /**
     * Strip HTML tags from content
     * NO REGEX - uses Salesforce built-in stripHtmlTags()
     */
    private static String stripHtml(String html) {
        if (String.isBlank(html)) {
            return '';
        }

        // Use Salesforce built-in method - no regex
        String text = html.stripHtmlTags();

        // Decode common HTML entities using simple replace() - no regex
        text = text.replace('&nbsp;', ' ');
        text = text.replace('&amp;', '&');
        text = text.replace('&lt;', '<');
        text = text.replace('&gt;', '>');
        text = text.replace('&quot;', '"');

        return text.trim();
    }

    /**
     * Custom exception for task service errors
     */
    public class TaskServiceException extends Exception {}
}