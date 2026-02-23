/**
 * AIGmailFetchService - Direct Google API calls using access token
 * 
 * This service bypasses Named Credential OAuth and uses a provided access token
 * for authentication. Used by the workspace-based sync flow where tokens are
 * stored in AI_Workspace_User__c.
 * 
 * Uses direct Named Credentials (no auth header injection):
 * - AI_Google_Gmail_Direct for Gmail API
 * - AI_Google_APIs_Direct for Calendar and Tasks APIs
 * 
 * @author GPTfy
 * @date 2026-01-16
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIGmailFetchService {
    
    // Direct Google API endpoints
    // Note: Requires Remote Site Settings for https://gmail.googleapis.com and https://www.googleapis.com
    private static final String GMAIL_ENDPOINT = 'https://gmail.googleapis.com/gmail/v1';
    private static final String CALENDAR_ENDPOINT = 'https://www.googleapis.com/calendar/v3';
    private static final String TASKS_ENDPOINT = 'https://www.googleapis.com/tasks/v1';
    
    private static final Integer DEFAULT_TIMEOUT = 120000;
    private static final String BATCH_BOUNDARY = 'batch_gmail_boundary';
    // Max emails per single batch API call - Gmail batch API limit
    private static final Integer MAX_BATCH_SIZE = 20;
    // Max emails to process in a single queueable execution
    // Increased from 3 to 20 to match Outlook's efficiency and properly chain across queueables
    // CPU timeout was caused by trying to process too many emails in one queueable instead of chaining
    private static final Integer MAX_EMAILS_PER_EXECUTION = 20;
    
    // ========================================================================
    // USER METHODS
    // ========================================================================
    
    /**
     * Get user's email address from Gmail API
     * @param accessToken Valid access token
     * @return User's email address
     */
    public static String getUserEmail(String accessToken) {
        if (String.isBlank(accessToken)) {
            throw new GmailFetchException('Access token is required');
        }
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(GMAIL_ENDPOINT + '/users/me/profile');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                Map<String, Object> profile = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String email = (String) profile.get('emailAddress');
                return String.isNotBlank(email) ? email : '';
            } else {
                throw new GmailFetchException('Failed to get user profile: ' + response.getStatusCode());
            }
        } catch (GmailFetchException e) {
            throw e;
        } catch (Exception e) {
            throw new GmailFetchException('Error fetching user email: ' + e.getMessage());
        }
    }
    
    // ========================================================================
    // EMAIL METHODS
    // ========================================================================
    
    /**
     * Fetch emails from INBOX label
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
        return fetchEmailsFromLabel(accessToken, 'INBOX', startDate, endDate, maxResults);
    }
    
    /**
     * Fetch emails from SENT label
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
        return fetchEmailsFromLabel(accessToken, 'SENT', startDate, endDate, maxResults);
    }
    
    /**
     * Fetch emails from a specific Gmail label with date filter
     * @param accessToken Valid access token
     * @param label Gmail label (INBOX, SENT, etc.)
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of emails to return
     * @return List of email data maps
     */
    private static List<Map<String, Object>> fetchEmailsFromLabel(
        String accessToken,
        String label,
        DateTime startDate,
        DateTime endDate,
        Integer maxResults
    ) {
        if (String.isBlank(accessToken)) {
            throw new GmailFetchException('Access token is required');
        }
        
        if (maxResults == null || maxResults <= 0) {
            maxResults = 50;
        }
        
        try {
            // Build Gmail query with date filter
            Long startTimestamp = startDate.getTime() / 1000;
            Long endTimestamp = endDate.getTime() / 1000;
            
            String labelQuery = label == 'INBOX' ? 'in:inbox' : (label == 'SENT' ? 'in:sent' : 'label:' + label);
            String dateQuery = 'after:' + startTimestamp + ' before:' + endTimestamp;
            String fullQuery = labelQuery + ' ' + dateQuery;
            
            // Step 1: Get message IDs
            String endpoint = GMAIL_ENDPOINT + '/users/me/messages'
                + '?maxResults=' + maxResults
                + '&q=' + EncodingUtil.urlEncode(fullQuery, 'UTF-8')
                + '&fields=messages(id,threadId),nextPageToken';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() != 200) {
                throw new GmailFetchException('Failed to fetch emails from ' + label + ': ' + response.getStatusCode());
            }
            
            Map<String, Object> listData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> messageList = (List<Object>) listData.get('messages');
            
            if (messageList == null || messageList.isEmpty()) {
                return new List<Map<String, Object>>();
            }
            
            // Extract message IDs
            List<String> messageIds = new List<String>();
            for (Object msgObj : messageList) {
                Map<String, Object> msg = (Map<String, Object>) msgObj;
                String messageId = (String) msg.get('id');
                if (String.isNotBlank(messageId)) {
                    messageIds.add(messageId);
                }
            }
            
            // Step 2: Batch fetch message metadata
            return getMessagesBatch(accessToken, messageIds, false);
        } catch (GmailFetchException e) {
            throw e;
        } catch (Exception e) {
            throw new GmailFetchException('Error fetching emails: ' + e.getMessage());
        }
    }
    
    /**
     * Get full email details for multiple message IDs
     * @deprecated Use fetchEmailsWithBody() instead for new implementations
     * @param accessToken Valid access token
     * @param messageIds List of message IDs to fetch
     * @return List of full email data maps
     */
    public static List<Map<String, Object>> getEmailDetailsBatch(
        String accessToken,
        List<String> messageIds
    ) {
        return getMessagesBatch(accessToken, messageIds, true);
    }
    
    // ========================================================================
    // NEW: SINGLE-CALL FETCH WITH BODY (Limit-Aware Continuous Sync)
    // ========================================================================
    
    /**
     * Result wrapper for fetchEmailsWithBody - includes cursor info for pagination
     */
    public class EmailBatchResult {
        public List<Map<String, Object>> emails { get; set; }
        public DateTime lastEmailDate { get; set; }  // Date of oldest email in batch (for tracking progress)
        public String nextPageToken { get; set; }    // Gmail pageToken for next batch
        public Boolean hasMore { get; set; }         // Whether more emails exist
        public String errorMessage { get; set; }     // Error if any (partial success)
        
        public EmailBatchResult() {
            this.emails = new List<Map<String, Object>>();
            this.hasMore = false;
        }
    }
    
    /**
     * Fetch emails from a label WITH FULL BODY in a single API flow.
     * 
     * IMPORTANT: Gmail API returns emails in DESCENDING order (newest first) 
     * and there's NO way to change this. We use pageToken-based pagination
     * to properly iterate through all emails.
     * 
     * The cursorDate/endDate parameters are only used for the INITIAL query
     * to filter by date range. After the first batch, use the pageToken
     * from the result to get subsequent pages.
     * 
     * @param accessToken Valid access token
     * @param label Gmail label ('INBOX' or 'SENT')
     * @param cursorDate Start of date range (only used if pageToken is null)
     * @param endDate End of date range (only used if pageToken is null)
     * @param batchSize Number of emails to fetch (default 20, max recommended 50)
     * @return EmailBatchResult with emails, pageToken, and hasMore flag
     */
    public static EmailBatchResult fetchEmailsWithBody(
        String accessToken,
        String label,
        DateTime cursorDate,
        DateTime endDate,
        Integer batchSize
    ) {
        // Delegate to the overloaded method with null pageToken (initial fetch)
        return fetchEmailsWithBodyPaginated(accessToken, label, cursorDate, endDate, batchSize, null);
    }
    
    /**
     * Fetch emails with pageToken-based pagination.
     * This is the main method that handles Gmail's descending order results.
     * 
     * @param accessToken Valid access token
     * @param label Gmail label ('INBOX' or 'SENT')
     * @param startDate Start of date range (only used if pageToken is null)
     * @param endDate End of date range (only used if pageToken is null)
     * @param batchSize Number of emails to fetch
     * @param pageToken Token for next page (null for first page)
     * @return EmailBatchResult with emails, nextPageToken, and hasMore flag
     */
    public static EmailBatchResult fetchEmailsWithBodyPaginated(
        String accessToken,
        String label,
        DateTime startDate,
        DateTime endDate,
        Integer batchSize,
        String pageToken
    ) {
        EmailBatchResult result = new EmailBatchResult();
        
        if (String.isBlank(accessToken)) {
            result.errorMessage = 'Access token is required';
            return result;
        }
        
        if (batchSize == null || batchSize <= 0) {
            batchSize = MAX_EMAILS_PER_EXECUTION;
        }
        // Cap at MAX_EMAILS_PER_EXECUTION to prevent CPU timeout 
        // Gmail emails with full body are much heavier than Outlook
        if (batchSize > MAX_EMAILS_PER_EXECUTION) {
            batchSize = MAX_EMAILS_PER_EXECUTION;
        }
        
        try {
            // Build the endpoint URL
            String labelQuery = label == 'INBOX' ? 'in:inbox' : (label == 'SENT' ? 'in:sent' : 'label:' + label);
            
            // CRITICAL FIX: Gmail's after/before operators work on UNIX timestamps (seconds since epoch)
            // They filter emails based on the internal date of the email
            // after:TIMESTAMP means "received after this timestamp"
            // before:TIMESTAMP means "received before this timestamp"
            Long startTimestamp = startDate.getTime() / 1000;
            Long endTimestamp = endDate.getTime() / 1000;
            
            // Build date query - Gmail uses "after:" for start and "before:" for end
            // NOTE: Gmail's operators are INCLUSIVE on the boundaries
            String dateQuery = 'after:' + startTimestamp + ' before:' + endTimestamp;
            String fullQuery = labelQuery + ' ' + dateQuery;
            
            // Step 1: Get message IDs
            // Gmail returns newest first, use pageToken to get next pages
            String endpoint = GMAIL_ENDPOINT + '/users/me/messages'
                + '?maxResults=' + batchSize
                + '&q=' + EncodingUtil.urlEncode(fullQuery, 'UTF-8')
                + '&fields=messages(id,threadId),nextPageToken,resultSizeEstimate';
            
            // Add pageToken if continuing pagination
            if (String.isNotBlank(pageToken)) {
                endpoint += '&pageToken=' + EncodingUtil.urlEncode(pageToken, 'UTF-8');
            }
            
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            Integer statusCode = response.getStatusCode();
            
            // 200 = OK with data, 204 = OK but no content (empty result)
            if (statusCode != 200 && statusCode != 204) {
                result.errorMessage = 'Failed to fetch from ' + label + ': ' + statusCode;
                return result;
            }
            
            // 204 or empty body means no emails - treat as success with empty result
            if (statusCode == 204 || String.isBlank(response.getBody())) {
                result.hasMore = false;
                return result;
            }
            
            Map<String, Object> listData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> messageList = (List<Object>) listData.get('messages');
            
            if (messageList == null || messageList.isEmpty()) {
                result.hasMore = false;
                return result;
            }
            
            // Check for nextPageToken - this is the correct way to paginate Gmail
            String nextToken = (String) listData.get('nextPageToken');
            result.nextPageToken = nextToken;
            result.hasMore = String.isNotBlank(nextToken);
            
            
            // Extract message IDs
            List<String> messageIds = new List<String>();
            for (Object msgObj : messageList) {
                Map<String, Object> msg = (Map<String, Object>) msgObj;
                String messageId = (String) msg.get('id');
                if (String.isNotBlank(messageId)) {
                    messageIds.add(messageId);
                }
            }
            
            // Step 2: Batch fetch messages with FULL content (including body)
            List<Map<String, Object>> fullMessages = getMessagesBatch(accessToken, messageIds, true);
            
            // Filter out nulls and find the oldest date (for tracking progress)
            DateTime oldestDate = null;
            for (Map<String, Object> msg : fullMessages) {
                if (msg != null) {
                    result.emails.add(msg);
                    
                    // Extract internalDate (Gmail uses milliseconds since epoch)
                    Object internalDateObj = msg.get('internalDate');
                    if (internalDateObj != null) {
                        try {
                            Long internalDateMs;
                            if (internalDateObj instanceof Long) {
                                internalDateMs = (Long) internalDateObj;
                            } else {
                                internalDateMs = Long.valueOf(String.valueOf(internalDateObj));
                            }
                            DateTime msgDate = DateTime.newInstance(internalDateMs);
                            // Track oldest date (since Gmail returns newest first)
                            if (oldestDate == null || msgDate < oldestDate) {
                                oldestDate = msgDate;
                            }
                        } catch (Exception e) {
                            // Ignore date parse errors
                        }
                    }
                }
            }
            
            // Set lastEmailDate to oldest email in batch (for progress tracking)
            result.lastEmailDate = oldestDate;
            
        } catch (Exception e) {
            result.errorMessage = 'Error fetching emails: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Fetch messages using Gmail's batch API for efficiency.
     * This uses a single HTTP request to fetch multiple messages, similar to how Outlook works.
     * Falls back to individual fetches only if batch API fails.
     * 
     * @param accessToken Valid access token
     * @param messageIds List of message IDs
     * @param fullFormat Whether to fetch full content (true) or metadata only (false)
     * @return List of message data maps
     */
    private static List<Map<String, Object>> getMessagesBatch(
        String accessToken,
        List<String> messageIds,
        Boolean fullFormat
    ) {
        if (String.isBlank(accessToken) || messageIds == null || messageIds.isEmpty()) {
            return new List<Map<String, Object>>();
        }
        
        List<Map<String, Object>> allMessages = new List<Map<String, Object>>();
        
        // Process in batches of MAX_BATCH_SIZE (Gmail batch API limit is ~100, but we use 20 for safety)
        Integer totalBatches = (Integer) Math.ceil((Decimal) messageIds.size() / MAX_BATCH_SIZE);
        
        for (Integer batchNum = 0; batchNum < totalBatches; batchNum++) {
            Integer startIdx = batchNum * MAX_BATCH_SIZE;
            Integer endIdx = Math.min(startIdx + MAX_BATCH_SIZE, messageIds.size());
            
            List<String> batchIds = new List<String>();
            for (Integer i = startIdx; i < endIdx; i++) {
                batchIds.add(messageIds[i]);
            }
            
            // Use the batch API for efficiency (1 callout per batch instead of 1 per email)
            List<Map<String, Object>> batchMessages = executeBatch(accessToken, batchIds, fullFormat);
            
            // If batch failed, fall back to individual fetches for this batch
            if (batchMessages.isEmpty() && !batchIds.isEmpty()) {
                batchMessages = fetchMessagesIndividually(accessToken, batchIds, fullFormat);
            }
            
            allMessages.addAll(batchMessages);
        }
        
        return allMessages;
    }
    
    /**
     * Fallback method: Fetch messages individually when batch API fails.
     * This is less efficient but more reliable.
     */
    private static List<Map<String, Object>> fetchMessagesIndividually(
        String accessToken,
        List<String> messageIds,
        Boolean fullFormat
    ) {
        List<Map<String, Object>> messages = new List<Map<String, Object>>();
        
        for (String messageId : messageIds) {
            try {
                Map<String, Object> message = fetchSingleMessage(accessToken, messageId, fullFormat);
                if (message != null) {
                    messages.add(message);
                }
            } catch (Exception e) {
                // Continue with next message
            }
        }
        
        return messages;
    }
    
    /**
     * Fetch a single message by ID
     */
    private static Map<String, Object> fetchSingleMessage(String accessToken, String messageId, Boolean fullFormat) {
        String path = GMAIL_ENDPOINT + '/users/me/messages/' + messageId;
        if (fullFormat) {
            path += '?format=full';
        } else {
            path += '?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date&metadataHeaders=To&metadataHeaders=Cc&metadataHeaders=Bcc&fields=id,threadId,labelIds,internalDate,snippet,payload/headers';
        }
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(path);
        req.setMethod('GET');
        req.setTimeout(DEFAULT_TIMEOUT);
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        
        Http http = new Http();
        HttpResponse response = http.send(req);
        
        if (response.getStatusCode() == 200) {
            return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        }
        
        return null;
    }
    
    /**
     * Execute a single batch request
     */
    private static List<Map<String, Object>> executeBatch(
        String accessToken,
        List<String> messageIds,
        Boolean fullFormat
    ) {
        List<Map<String, Object>> messages = new List<Map<String, Object>>();
        
        // Build batch request body
        List<String> parts = new List<String>();
        for (Integer i = 0; i < messageIds.size(); i++) {
            String path = '/gmail/v1/users/me/messages/' + messageIds[i];
            if (fullFormat) {
                path += '?format=full';
            } else {
                path += '?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date&metadataHeaders=To&metadataHeaders=Cc&metadataHeaders=Bcc&fields=id,threadId,labelIds,internalDate,snippet,payload/headers';
            }
            
            String part = '--' + BATCH_BOUNDARY + '\r\n' +
                'Content-Type: application/http\r\n' +
                'Content-ID: <item' + i + '>\r\n\r\n' +
                'GET ' + path + '\r\n';
            
            parts.add(part);
        }
        
        String batchBody = String.join(parts, '\r\n') + '\r\n--' + BATCH_BOUNDARY + '--';
        
        try {
            // Gmail batch endpoint
            String batchEndpoint = GMAIL_ENDPOINT.replace('/gmail/v1', '/batch/gmail/v1');
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(batchEndpoint);
            req.setMethod('POST');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'multipart/mixed; boundary=' + BATCH_BOUNDARY);
            req.setBody(batchBody);
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                messages = parseBatchResponse(response.getBody());
            } 
        } catch (Exception e) {
            //ignore
        }
        
        return messages;
    }
    
    /**
     * Parse multipart batch response
     * Uses indexOf-based splitting to avoid regex "too complicated" errors
     */
    private static List<Map<String, Object>> parseBatchResponse(String responseBody) {
        List<Map<String, Object>> messages = new List<Map<String, Object>>();
        
        if (String.isBlank(responseBody)) {
            return messages;
        }
        
        // Find boundary - Gmail batch responses start with --batch_xxxxx
        Integer firstBoundary = responseBody.indexOf('--batch');
        if (firstBoundary == -1) {
            return messages;
        }
        
        Integer boundaryEnd = responseBody.indexOf('\r\n', firstBoundary);
        if (boundaryEnd == -1) {
            boundaryEnd = responseBody.indexOf('\n', firstBoundary);
        }
        if (boundaryEnd == -1) {
            return messages;
        }
        
        String boundary = responseBody.substring(firstBoundary, boundaryEnd);
        
        // Use indexOf-based splitting instead of regex split to avoid "Regex too complicated" error
        List<String> parts = splitByBoundary(responseBody, boundary);
        
        for (String part : parts) {
            if (String.isBlank(part) || part.trim() == '--') {
                continue;
            }
            
            // Check for HTTP errors
            if (part.contains('HTTP/1.1 4') || part.contains('HTTP/1.1 5')) {
                continue;
            }
            
            // Find JSON start - look for {"id"
            Integer jsonStart = part.indexOf('{"id"');
            if (jsonStart == -1) {
                // Try alternative: find first { that's followed by "id"
                Integer altStart = part.indexOf('{');
                if (altStart >= 0 && part.indexOf('"id"', altStart) > altStart) {
                    jsonStart = altStart;
                }
            }
            
            if (jsonStart >= 0) {
                // Find the JSON end by looking for the last } in the part
                String jsonCandidate = part.substring(jsonStart);
                Integer jsonEnd = jsonCandidate.lastIndexOf('}');
                
                if (jsonEnd > 0) {
                    String jsonBody = jsonCandidate.substring(0, jsonEnd + 1).trim();
                    try {
                        Map<String, Object> message = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
                        if (message.containsKey('id')) {
                            messages.add(message);
                        }
                    } catch (Exception e) {
                        //ignore
                    }
                }
            }
        }
        
        return messages;
    }
    
    /**
     * Split string by delimiter using indexOf (no regex).
     * This avoids the "Regex too complicated" error that occurs with complex batch boundaries.
     */
    private static List<String> splitByBoundary(String input, String delimiter) {
        List<String> result = new List<String>();
        
        if (String.isBlank(input) || String.isBlank(delimiter)) {
            return result;
        }
        
        Integer startIndex = 0;
        Integer delimiterIndex = input.indexOf(delimiter, startIndex);
        
        while (delimiterIndex != -1) {
            // Add the part before the delimiter
            if (delimiterIndex > startIndex) {
                result.add(input.substring(startIndex, delimiterIndex));
            }
            
            // Move past the delimiter
            startIndex = delimiterIndex + delimiter.length();
            
            // Find next occurrence
            delimiterIndex = input.indexOf(delimiter, startIndex);
        }
        
        // Add the remaining part after the last delimiter
        if (startIndex < input.length()) {
            result.add(input.substring(startIndex));
        }
        
        return result;
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
            throw new GmailFetchException('Access token is required');
        }
        
        if (maxResults == null || maxResults <= 0) {
            maxResults = 50;
        }
        
        try {
            // Format dates for Google Calendar API (RFC 3339)
            String timeMin = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String timeMax = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            
            String endpoint = CALENDAR_ENDPOINT + '/calendars/primary/events'
                + '?timeMin=' + EncodingUtil.urlEncode(timeMin, 'UTF-8')
                + '&timeMax=' + EncodingUtil.urlEncode(timeMax, 'UTF-8')
                + '&maxResults=' + maxResults
                + '&singleEvents=true'
                + '&orderBy=startTime';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                List<Object> items = (List<Object>) data.get('items');
                
                List<Map<String, Object>> events = new List<Map<String, Object>>();
                if (items != null) {
                    for (Object item : items) {
                        events.add((Map<String, Object>) item);
                    }
                }
                return events;
            } else {
                throw new GmailFetchException('Failed to fetch calendar events: ' + response.getStatusCode());
            }
        } catch (GmailFetchException e) {
            throw e;
        } catch (Exception e) {
            throw new GmailFetchException('Error fetching calendar events: ' + e.getMessage());
        }
    }
    
    // ========================================================================
    // TASK METHODS (Google Tasks API)
    // ========================================================================
    
    /**
     * Fetch task lists from Google Tasks
     * @param accessToken Valid access token
     * @return List of task list data maps
     */
    public static List<Map<String, Object>> fetchTaskLists(String accessToken) {
        if (String.isBlank(accessToken)) {
            throw new GmailFetchException('Access token is required');
        }
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(TASKS_ENDPOINT + '/users/@me/lists');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                List<Object> items = (List<Object>) data.get('items');
                
                List<Map<String, Object>> taskLists = new List<Map<String, Object>>();
                if (items != null) {
                    for (Object item : items) {
                        taskLists.add((Map<String, Object>) item);
                    }
                }
                return taskLists;
            } else {
                throw new GmailFetchException('Failed to fetch task lists: ' + response.getStatusCode());
            }
        } catch (GmailFetchException e) {
            throw e;
        } catch (Exception e) {
            throw new GmailFetchException('Error fetching task lists: ' + e.getMessage());
        }
    }
    
    /**
     * Fetch tasks from all task lists
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
     * Fetch tasks from Google Tasks with date filtering
     * @param accessToken Valid access token
     * @param maxResults Maximum number of tasks to return
     * @param includeCompleted Whether to include completed tasks
     * @param startDate Start of sync window (filter tasks updated on or after this date)
     * @param endDate End of sync window (filter tasks updated on or before this date)
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
            throw new GmailFetchException('Access token is required');
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
                String listTitle = (String) taskList.get('title');
                
                try {
                    List<Map<String, Object>> listTasks = fetchTasksFromList(
                        accessToken, listId, listTitle, tasksPerList, includeCompleted, startDate, endDate
                    );
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
            throw new GmailFetchException('Error fetching tasks: ' + e.getMessage());
        }
    }
    
    /**
     * Fetch tasks from a specific task list (without date filter)
     * @param accessToken Valid access token
     * @param listId Task list ID
     * @param listTitle Task list title
     * @param maxResults Maximum number of tasks to return
     * @param includeCompleted Whether to include completed tasks
     * @return List of task data maps
     */
    private static List<Map<String, Object>> fetchTasksFromList(
        String accessToken,
        String listId,
        String listTitle,
        Integer maxResults,
        Boolean includeCompleted
    ) {
        return fetchTasksFromList(accessToken, listId, listTitle, maxResults, includeCompleted, null, null);
    }
    
    /**
     * Fetch tasks from a specific task list with date filtering
     * @param accessToken Valid access token
     * @param listId Task list ID
     * @param listTitle Task list title
     * @param maxResults Maximum number of tasks to return
     * @param includeCompleted Whether to include completed tasks
     * @param startDate Start of sync window (filter tasks updated on or after this date)
     * @param endDate End of sync window (not used by Google Tasks API, filtering done in-memory)
     * @return List of task data maps
     */
    private static List<Map<String, Object>> fetchTasksFromList(
        String accessToken,
        String listId,
        String listTitle,
        Integer maxResults,
        Boolean includeCompleted,
        DateTime startDate,
        DateTime endDate
    ) {
        List<Map<String, Object>> tasks = new List<Map<String, Object>>();
        
        try {
            String endpoint = TASKS_ENDPOINT + '/lists/' + EncodingUtil.urlEncode(listId, 'UTF-8') + '/tasks'
                + '?maxResults=' + maxResults
                + '&showCompleted=' + (includeCompleted ? 'true' : 'false');
            
            // Google Tasks API supports updatedMin parameter for filtering by updated date
            // Format: RFC 3339 timestamp (e.g., 2024-01-15T00:00:00Z)
            if (startDate != null) {
                String updatedMin = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                endpoint += '&updatedMin=' + EncodingUtil.urlEncode(updatedMin, 'UTF-8');
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
                Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                List<Object> items = (List<Object>) data.get('items');
                
                if (items != null) {
                    for (Object item : items) {
                        Map<String, Object> task = (Map<String, Object>) item;
                        // Add list info
                        task.put('listId', listId);
                        task.put('listTitle', listTitle);
                        tasks.add(task);
                    }
                }
            } 
        } catch (Exception e) {
            //ignore
        }
        
        return tasks;
    }
    
    /**
     * Custom exception for Gmail fetch errors
     */
    public class GmailFetchException extends Exception {}
}