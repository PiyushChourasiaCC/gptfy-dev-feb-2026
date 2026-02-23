/**
 * AIOutlookFetchService - Direct Microsoft Graph API calls using access token
 * 
 * This service bypasses Named Credential OAuth and uses a provided access token
 * for authentication. Used by the workspace-based sync flow where tokens are
 * stored in AI_Workspace_User__c.
 * 
 * Uses AI_Microsoft_Graph_Direct Named Credential (no auth header injection).
 * 
 * @author GPTfy
 * @date 2026-01-16
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIOutlookFetchService {
    
    // Direct Microsoft Graph API endpoint
    // Note: Requires Remote Site Setting for https://graph.microsoft.com
    private static final String GRAPH_ENDPOINT = 'https://graph.microsoft.com/v1.0';
    private static final Integer DEFAULT_TIMEOUT = 120000;
    private static final Integer BATCH_SIZE = 20; // Graph API batch limit
    
    // ========================================================================
    // USER METHODS
    // ========================================================================
    
    /**
     * Get user's email address from Microsoft Graph
     * @param accessToken Valid access token
     * @return User's email address
     */
    public static String getUserEmail(String accessToken) {
        if (String.isBlank(accessToken)) {
            throw new OutlookFetchException('Access token is required');
        }
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(GRAPH_ENDPOINT + '/me');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                Map<String, Object> userInfo = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                
                // Try userPrincipalName first, fallback to mail
                String email = (String) userInfo.get('userPrincipalName');
                if (String.isBlank(email)) {
                    email = (String) userInfo.get('mail');
                }
                
                return String.isNotBlank(email) ? email : '';
            } else {
                throw new OutlookFetchException('Failed to get user profile: ' + response.getStatusCode());
            }
        } catch (OutlookFetchException e) {
            throw e;
        } catch (Exception e) {
            throw new OutlookFetchException('Error fetching user email: ' + e.getMessage());
        }
    }
    
    // ========================================================================
    // EMAIL METHODS
    // ========================================================================
    
    /**
     * Fetch emails from inbox folder
     * @param accessToken Valid access token
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of emails to return
     * @return List of email data maps
     */
    public static List<Map<String, Object>> fetchInboxEmails(
        String accessToken,
        DateTime startDate,
        DateTime endDate,
        Integer maxResults
    ) {
        return fetchEmailsFromFolder(accessToken, 'inbox', 'receivedDateTime', startDate, endDate, maxResults);
    }
    
    /**
     * Fetch emails from sent items folder
     * @param accessToken Valid access token
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of emails to return
     * @return List of email data maps
     */
    public static List<Map<String, Object>> fetchSentEmails(
        String accessToken,
        DateTime startDate,
        DateTime endDate,
        Integer maxResults
    ) {
        return fetchEmailsFromFolder(accessToken, 'sentitems', 'sentDateTime', startDate, endDate, maxResults);
    }
    
    /**
     * Fetch emails from a specific folder with date filter
     * @param accessToken Valid access token
     * @param folder Folder name (inbox, sentitems, etc.)
     * @param dateField Date field to filter on (receivedDateTime, sentDateTime)
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of emails to return
     * @return List of email data maps
     */
    private static List<Map<String, Object>> fetchEmailsFromFolder(
        String accessToken,
        String folder,
        String dateField,
        DateTime startDate,
        DateTime endDate,
        Integer maxResults
    ) {
        if (String.isBlank(accessToken)) {
            throw new OutlookFetchException('Access token is required');
        }
        
        if (maxResults == null || maxResults <= 0) {
            maxResults = 50;
        }
        
        try {
            // Build date filter - Microsoft Graph requires ISO 8601 format
            String startStr = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            
            // Build endpoint with OData query parameters
            // Note: Don't URL encode individual parts, build the raw query then encode the filter value only
            // IMPORTANT: Include 'categories' for marketing email exclusion detection
            // IMPORTANT: Include 'bccRecipients' for BCC address capture
            String selectFields = 'id,subject,from,toRecipients,ccRecipients,bccRecipients,receivedDateTime,sentDateTime,hasAttachments,importance,isRead,internetMessageId,bodyPreview,categories,inferenceClassification';
            
            // Build endpoint with OData query parameters
            // Using 'asc' ordering to get oldest emails first (FIFO - First In First Out)
            String endpoint = GRAPH_ENDPOINT + '/me/mailFolders/' + folder + '/messages'
                + '?$top=' + maxResults
                + '&$orderby=' + EncodingUtil.urlEncode(dateField + ' asc', 'UTF-8')
                + '&$filter=' + EncodingUtil.urlEncode(dateField + ' ge ' + startStr + ' and ' + dateField + ' le ' + endStr, 'UTF-8')
                + '&$select=' + selectFields;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            // Don't set body-content-type preference - let Graph return HTML by default to preserve forwarded content
            // req.setHeader('Prefer', 'outlook.body-content-type="text"');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                return parseEmailsResponse(response.getBody());
            } else {
                String errorBody = response.getBody();
                
                // Parse error message if available
                String errorDetail = '';
                try {
                    Map<String, Object> errorResponse = (Map<String, Object>) JSON.deserializeUntyped(errorBody);
                    Map<String, Object> error = (Map<String, Object>) errorResponse.get('error');
                    if (error != null) {
                        errorDetail = ': ' + (String) error.get('message');
                    }
                } catch (Exception e) {
                    // Ignore parse errors
                }
                
                throw new OutlookFetchException('Failed to fetch emails from ' + folder + ': ' + response.getStatusCode() + errorDetail);
            }
        } catch (OutlookFetchException e) {
            throw e;
        } catch (Exception e) {
            throw new OutlookFetchException('Error fetching emails: ' + e.getMessage());
        }
    }
    
    // ========================================================================
    // NEW: SINGLE-CALL FETCH WITH BODY (Limit-Aware Continuous Sync)
    // ========================================================================
    
    /**
     * Result wrapper for fetchEmailsWithBody - includes cursor info for pagination
     */
    public class EmailBatchResult {
        public List<Map<String, Object>> emails { get; set; }
        public DateTime lastEmailDate { get; set; }  // Date cursor for next batch
        public Boolean hasMore { get; set; }         // Whether more emails exist
        public String errorMessage { get; set; }     // Error if any (partial success)
        
        public EmailBatchResult() {
            this.emails = new List<Map<String, Object>>();
            this.hasMore = false;
        }
    }
    
    /**
     * Fetch emails from a folder WITH FULL BODY in a single API call.
     * Uses date-based cursor for pagination across queueable chains.
     * 
     * @param accessToken Valid access token
     * @param folder Folder name ('inbox' or 'sentitems')
     * @param cursorDate Start fetching from this date (exclusive). Use syncWindowStart for first batch.
     * @param endDate End of date range (inclusive)
     * @param batchSize Number of emails to fetch (default 20, max recommended 50)
     * @return EmailBatchResult with emails, cursor, and hasMore flag
     */
    public static EmailBatchResult fetchEmailsWithBody(
        String accessToken,
        String folder,
        DateTime cursorDate,
        DateTime endDate,
        Integer batchSize
    ) {
        EmailBatchResult result = new EmailBatchResult();
        
        if (String.isBlank(accessToken)) {
            result.errorMessage = 'Access token is required';
            return result;
        }
        
        if (batchSize == null || batchSize <= 0) {
            batchSize = 20;
        }
        // Cap at 50 to prevent heap issues
        if (batchSize > 50) {
            batchSize = 50;
        }
        
        String dateField = folder == 'sentitems' ? 'sentDateTime' : 'receivedDateTime';
        
        try {
            // Build date filter - use 'gt' (greater than) for cursor to avoid re-fetching same email
            String cursorStr = cursorDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            
            // Select fields INCLUDING body for single-call fetch
            // IMPORTANT: Include 'categories' and 'inferenceClassification' for marketing email exclusion detection
            // IMPORTANT: Include 'bccRecipients' for BCC address capture
            String selectFields = 'id,subject,body,from,toRecipients,ccRecipients,bccRecipients,receivedDateTime,sentDateTime,hasAttachments,importance,isRead,internetMessageId,conversationId,categories,inferenceClassification';
            
            // Build filter: cursorDate < dateField <= endDate (FIFO order)
            String filterQuery = dateField + ' gt ' + cursorStr + ' and ' + dateField + ' le ' + endStr;
            
            // Request one extra to determine if more exist
            Integer fetchCount = batchSize + 1;
            
            String endpoint = GRAPH_ENDPOINT + '/me/mailFolders/' + folder + '/messages'
                + '?$top=' + fetchCount
                + '&$orderby=' + EncodingUtil.urlEncode(dateField + ' asc', 'UTF-8')
                + '&$filter=' + EncodingUtil.urlEncode(filterQuery, 'UTF-8')
                + '&$select=' + selectFields;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            // Don't set body-content-type preference - let Graph return HTML by default to preserve forwarded content
            // req.setHeader('Prefer', 'outlook.body-content-type="text"');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            Integer statusCode = response.getStatusCode();
            
            // 200 = OK with data, 204 = OK but no content (empty folder or no emails in date range)
            if (statusCode == 200 || statusCode == 204) {
                
                // 204 means no content - treat as empty result (success, no emails)
                if (statusCode == 204 || String.isBlank(response.getBody())) {
                    result.hasMore = false;
                    result.emails = new List<Map<String, Object>>();
                } else {
                    List<Map<String, Object>> allEmails = parseEmailsResponse(response.getBody());
                    
                    // Check if we got more than batchSize (means there are more emails)
                    if (allEmails.size() > batchSize) {
                        result.hasMore = true;
                        // Only keep batchSize emails
                        for (Integer i = 0; i < batchSize; i++) {
                            result.emails.add(allEmails[i]);
                        }
                    } else {
                        result.hasMore = false;
                        result.emails = allEmails;
                    }
                    
                    // Set cursor to last email's date for next batch
                    if (!result.emails.isEmpty()) {
                        Map<String, Object> lastEmail = result.emails[result.emails.size() - 1];
                        String lastDateStr = (String) lastEmail.get(dateField);
                        if (String.isNotBlank(lastDateStr)) {
                            result.lastEmailDate = parseDateTime(lastDateStr);
                        }
                    }
                }
                
            } else {
                String errorBody = response.getBody();
                
                String errorDetail = '';
                try {
                    Map<String, Object> errorResponse = (Map<String, Object>) JSON.deserializeUntyped(errorBody);
                    Map<String, Object> error = (Map<String, Object>) errorResponse.get('error');
                    if (error != null) {
                        errorDetail = (String) error.get('message');
                    }
                } catch (Exception e) {
                    errorDetail = errorBody;
                }
                
                result.errorMessage = 'Failed to fetch from ' + folder + ': ' + response.getStatusCode() + ' - ' + errorDetail;
            }
            
        } catch (Exception e) {
            result.errorMessage = 'Error fetching emails: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Parse ISO 8601 datetime string to Apex DateTime
     */
    private static DateTime parseDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }
        try {
            // Handle format: 2026-01-19T14:30:00Z or 2026-01-19T14:30:00.0000000Z
            String normalized = dateTimeStr.replace('.0000000', '');
            if (!normalized.endsWith('Z')) {
                normalized = normalized + 'Z';
            }
            return (DateTime) JSON.deserialize('"' + normalized + '"', DateTime.class);
        } catch (Exception e) {
            return null;
        }
    }
    
    // ========================================================================
    // LEGACY: BATCH GET (kept for backward compatibility)
    // ========================================================================
    
    /**
     * Batch get email details (including body) for multiple message IDs
     * Uses Graph API $batch endpoint for efficiency
     * @deprecated Use fetchEmailsWithBody() instead for new implementations
     * @param accessToken Valid access token
     * @param messageIds List of message IDs to fetch
     * @return List of full email data maps
     */
    public static List<Map<String, Object>> getEmailDetailsBatch(
        String accessToken,
        List<String> messageIds
    ) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        
        if (String.isBlank(accessToken) || messageIds == null || messageIds.isEmpty()) {
            return results;
        }
        
        // Process in batches of 20 (Graph API limit)
        Integer totalBatches = (Integer) Math.ceil((Decimal) messageIds.size() / BATCH_SIZE);
        
        for (Integer batchNum = 0; batchNum < totalBatches; batchNum++) {
            Integer startIdx = batchNum * BATCH_SIZE;
            Integer endIdx = Math.min(startIdx + BATCH_SIZE, messageIds.size());
            
            // Build batch request
            List<Map<String, Object>> requests = new List<Map<String, Object>>();
            for (Integer i = startIdx; i < endIdx; i++) {
                requests.add(new Map<String, Object>{
                    'id' => String.valueOf(i),
                    'method' => 'GET',
                    'url' => '/me/messages/' + messageIds[i]
                });
            }
            
            Map<String, Object> batchBody = new Map<String, Object>{
                'requests' => requests
            };
            
            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(GRAPH_ENDPOINT + '/$batch');
                req.setMethod('POST');
                req.setTimeout(DEFAULT_TIMEOUT);
                req.setHeader('Authorization', 'Bearer ' + accessToken);
                req.setHeader('Content-Type', 'application/json');
                req.setBody(JSON.serialize(batchBody));
                
                Http http = new Http();
                HttpResponse response = http.send(req);
                
                if (response.getStatusCode() == 200) {
                    Map<String, Object> batchResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    List<Object> responses = (List<Object>) batchResponse.get('responses');
                    
                    // Create a map of id -> response body for ordering
                    Map<String, Map<String, Object>> responseMap = new Map<String, Map<String, Object>>();
                    for (Object respObj : responses) {
                        Map<String, Object> resp = (Map<String, Object>) respObj;
                        String respId = (String) resp.get('id');
                        Integer status = (Integer) resp.get('status');
                        if (status == 200) {
                            responseMap.put(respId, (Map<String, Object>) resp.get('body'));
                        }
                    }
                    
                    // Add results in original order
                    for (Integer i = startIdx; i < endIdx; i++) {
                        String respId = String.valueOf(i);
                        if (responseMap.containsKey(respId)) {
                            results.add(responseMap.get(respId));
                        } else {
                            results.add(null);
                        }
                    }
                } else {
                    // Batch failed, add nulls for this batch
                    for (Integer i = startIdx; i < endIdx; i++) {
                        results.add(null);
                    }
                }
            } catch (Exception e) {
                // Batch failed, add nulls for this batch
                for (Integer i = startIdx; i < endIdx; i++) {
                    results.add(null);
                }
            }
        }
        
        return results;
    }
    
    // ========================================================================
    // CALENDAR METHODS
    // ========================================================================
    
    /**
     * Fetch calendar events within a date range
     * @param accessToken Valid access token
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of events to return
     * @return List of calendar event data maps
     */
    public static List<Map<String, Object>> fetchCalendarEvents(
        String accessToken,
        DateTime startDate,
        DateTime endDate,
        Integer maxResults
    ) {
        if (String.isBlank(accessToken)) {
            throw new OutlookFetchException('Access token is required');
        }
        
        if (maxResults == null || maxResults <= 0) {
            maxResults = 50;
        }
        
        try {
            // Format dates for Graph API (ISO 8601)
            String startDateStr = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endDateStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            
            // Use calendarView endpoint for proper recurring event expansion
            String endpoint = GRAPH_ENDPOINT + '/me/calendar/calendarView'
                + '?startDateTime=' + EncodingUtil.urlEncode(startDateStr, 'UTF-8')
                + '&endDateTime=' + EncodingUtil.urlEncode(endDateStr, 'UTF-8')
                + '&$top=' + maxResults
                + '&$orderby=start/dateTime'
                + '&$select=id,subject,bodyPreview,body,start,end,location,attendees,organizer,iCalUId,onlineMeeting,isAllDay,showAs,responseStatus';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Prefer', 'outlook.timezone="UTC"');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                return parseValueResponse(response.getBody());
            } else {
                throw new OutlookFetchException('Failed to fetch calendar events: ' + response.getStatusCode());
            }
        } catch (OutlookFetchException e) {
            throw e;
        } catch (Exception e) {
            throw new OutlookFetchException('Error fetching calendar events: ' + e.getMessage());
        }
    }
    
    // ========================================================================
    // TASK METHODS
    // ========================================================================
    
    /**
     * Fetch To-Do task lists
     * @param accessToken Valid access token
     * @return List of task list data maps
     */
    public static List<Map<String, Object>> fetchTaskLists(String accessToken) {
        if (String.isBlank(accessToken)) {
            throw new OutlookFetchException('Access token is required');
        }
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(GRAPH_ENDPOINT + '/me/todo/lists');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                return parseValueResponse(response.getBody());
            } else {
                throw new OutlookFetchException('Failed to fetch task lists: ' + response.getStatusCode());
            }
        } catch (OutlookFetchException e) {
            throw e;
        } catch (Exception e) {
            throw new OutlookFetchException('Error fetching task lists: ' + e.getMessage());
        }
    }
    
    /**
     * Fetch To-Do tasks from all lists (without date filter - fetches all tasks)
     * @param accessToken Valid access token
     * @param maxResults Maximum number of tasks to return
     * @param includeCompleted Whether to include completed tasks
     * @return List of task data maps
     */
    public static List<Map<String, Object>> fetchTasks(
        String accessToken,
        Integer maxResults,
        Boolean includeCompleted
    ) {
        // Delegate to overloaded method with null dates (no filtering)
        return fetchTasks(accessToken, maxResults, includeCompleted, null, null);
    }
    
    /**
     * Fetch To-Do tasks from all lists with date filtering
     * @param accessToken Valid access token
     * @param maxResults Maximum number of tasks to return
     * @param includeCompleted Whether to include completed tasks
     * @param startDate Start of sync window (filter tasks modified on or after this date)
     * @param endDate End of sync window (filter tasks modified on or before this date)
     * @return List of task data maps
     */
    public static List<Map<String, Object>> fetchTasks(
        String accessToken,
        Integer maxResults,
        Boolean includeCompleted,
        DateTime startDate,
        DateTime endDate
    ) {
        if (String.isBlank(accessToken)) {
            throw new OutlookFetchException('Access token is required');
        }
        
        if (maxResults == null || maxResults <= 0) {
            maxResults = 50;
        }
        
        List<Map<String, Object>> allTasks = new List<Map<String, Object>>();
        
        try {
            // Get all task lists first
            List<Map<String, Object>> taskLists = fetchTaskLists(accessToken);
            
            if (taskLists.isEmpty()) {
                return allTasks;
            }
            
            // Distribute max results across lists
            Integer tasksPerList = Math.max(maxResults / taskLists.size(), 10);
            
            for (Map<String, Object> taskList : taskLists) {
                String listId = (String) taskList.get('id');
                String listName = (String) taskList.get('displayName');
                
                try {
                    List<Map<String, Object>> listTasks = fetchTasksFromList(accessToken, listId, listName, tasksPerList, includeCompleted, startDate, endDate);
                    allTasks.addAll(listTasks);
                    
                    if (allTasks.size() >= maxResults) {
                        break;
                    }
                } catch (Exception e) {
                    // Continue with other lists
                }
            }
            
            // Trim to max results
            if (allTasks.size() > maxResults) {
                List<Map<String, Object>> trimmed = new List<Map<String, Object>>();
                for (Integer i = 0; i < maxResults; i++) {
                    trimmed.add(allTasks[i]);
                }
                return trimmed;
            }
            
            return allTasks;
        } catch (Exception e) {
            throw new OutlookFetchException('Error fetching tasks: ' + e.getMessage());
        }
    }
    
    /**
     * Fetch tasks from a specific task list (without date filter)
     * @param accessToken Valid access token
     * @param listId Task list ID
     * @param listName Task list display name
     * @param maxResults Maximum number of tasks to return
     * @param includeCompleted Whether to include completed tasks
     * @return List of task data maps
     */
    private static List<Map<String, Object>> fetchTasksFromList(
        String accessToken,
        String listId,
        String listName,
        Integer maxResults,
        Boolean includeCompleted
    ) {
        return fetchTasksFromList(accessToken, listId, listName, maxResults, includeCompleted, null, null);
    }
    
    /**
     * Fetch tasks from a specific task list with date filtering
     * @param accessToken Valid access token
     * @param listId Task list ID
     * @param listName Task list display name
     * @param maxResults Maximum number of tasks to return
     * @param includeCompleted Whether to include completed tasks
     * @param startDate Start of sync window (filter tasks modified on or after this date)
     * @param endDate End of sync window (filter tasks modified on or before this date)
     * @return List of task data maps
     */
    private static List<Map<String, Object>> fetchTasksFromList(
        String accessToken,
        String listId,
        String listName,
        Integer maxResults,
        Boolean includeCompleted,
        DateTime startDate,
        DateTime endDate
    ) {
        List<Map<String, Object>> tasks = new List<Map<String, Object>>();
        
        try {
            String endpoint = GRAPH_ENDPOINT + '/me/todo/lists/'
                + EncodingUtil.urlEncode(listId, 'UTF-8') + '/tasks';
            
            // Build filter for date range using lastModifiedDateTime
            // Microsoft Graph To-Do API supports OData filtering
            List<String> filters = new List<String>();
            
            if (startDate != null) {
                String startStr = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                filters.add('lastModifiedDateTime ge ' + startStr);
            }
            if (endDate != null) {
                String endStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                filters.add('lastModifiedDateTime le ' + endStr);
            }
            
            // Add filter query parameters if date filters exist
            if (!filters.isEmpty()) {
                String filterQuery = String.join(filters, ' and ');
                endpoint += '?$filter=' + EncodingUtil.urlEncode(filterQuery, 'UTF-8');
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                List<Map<String, Object>> allTasks = parseValueResponse(response.getBody());
                
                // Filter and add list info
                for (Map<String, Object> task : allTasks) {
                    String status = (String) task.get('status');
                    
                    // Skip completed tasks if not including them
                    if (!includeCompleted && status == 'completed') {
                        continue;
                    }
                    
                    // Add list info
                    task.put('listId', listId);
                    task.put('listName', listName);
                    
                    tasks.add(task);
                    
                    if (tasks.size() >= maxResults) {
                        break;
                    }
                }
            }
        } catch (Exception e) {
            // Error fetching tasks from list
        }
        
        return tasks;
    }
    
    // ========================================================================
    // HELPER METHODS
    // ========================================================================
    
    /**
     * Parse emails response from Graph API
     * @param responseBody JSON response body
     * @return List of email data maps
     */
    private static List<Map<String, Object>> parseEmailsResponse(String responseBody) {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> emailList = (List<Object>) parsed.get('value');
        
        if (emailList != null) {
            for (Object emailObj : emailList) {
                emails.add((Map<String, Object>) emailObj);
            }
        }
        
        return emails;
    }
    
    /**
     * Parse generic value array response from Graph API
     * @param responseBody JSON response body
     * @return List of data maps
     */
    private static List<Map<String, Object>> parseValueResponse(String responseBody) {
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> valueList = (List<Object>) parsed.get('value');
        
        if (valueList != null) {
            for (Object itemObj : valueList) {
                items.add((Map<String, Object>) itemObj);
            }
        }
        
        return items;
    }
    
    /**
     * Custom exception for Outlook fetch errors
     */
    public class OutlookFetchException extends Exception {}
}