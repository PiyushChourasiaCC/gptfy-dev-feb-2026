/**
 * Gmail API service class
 * Handles HTTP requests to Gmail API endpoints
 *
 * AUTHENTICATION: Uses access tokens from AI_Workspace_User__c
 * Tokens are retrieved and refreshed automatically via AIWorkspaceTokenService
 *
 * PERFORMANCE OPTIMIZATION:
 * Uses batch requests to fetch multiple message metadata in a single HTTP call
 * instead of making N separate callouts. This reduces latency from ~16s to ~2s.
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIGmailService {

    private static final Integer DEFAULT_TIMEOUT = 120000; // 2 minutes
    private static final String BATCH_BOUNDARY = 'batch_gmail_boundary';
    private static final Integer MAX_BATCH_SIZE = 20; // Smaller batches to avoid rate limits
    private static final Integer MAX_RETRIES = 3;
    private static final Integer INITIAL_RETRY_DELAY_MS = 1000; // 1 second

    // Gmail API endpoint (direct URL, not Named Credential)
    private static String getGmailApiEndpoint() {
        return AIWorkspaceTokenService.getGmailEndpoint();
    }

    private static String getBatchEndpoint() {
        return AIWorkspaceTokenService.getGmailEndpoint() + '/batch/gmail/v1';
    }
    
    /**
     * Get access token for the current user
     * Retrieves from AI_Workspace_User__c and refreshes if needed
     */
    private static String getAccessToken() {
        return AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_GMAIL);
    }

    public class GmailAPIException extends Exception {}

    /**
     * Retrieves message IDs from Gmail API with pagination
     * Step 1 of the optimized flow: Get IDs only (lightweight)
     * @param maxResults Maximum number of results
     * @param dateFilter Date filter in Gmail format (e.g., "after:timestamp before:timestamp")
     * @param searchTerm Optional search term
     * @return Response with message IDs and pagination info
     */
    public static HttpResponse getMessageIds(Integer maxResults, String dateFilter, String searchTerm) {
        return getMessageIds(maxResults, dateFilter, searchTerm, null);
    }

    /**
     * Retrieves message IDs from Gmail API with pagination and folder filter
     * Step 1 of the optimized flow: Get IDs only (lightweight)
     * @param maxResults Maximum number of results
     * @param dateFilter Date filter in Gmail format (e.g., "after:timestamp before:timestamp")
     * @param searchTerm Optional search term
     * @param folder Gmail label/folder (e.g., "INBOX", "SENT")
     * @return Response with message IDs and pagination info
     */
    public static HttpResponse getMessageIds(Integer maxResults, String dateFilter, String searchTerm, String folder) {
        return getMessageIds(maxResults, dateFilter, searchTerm, folder, null);
    }

    /**
     * Retrieves message IDs from Gmail API with pagination, folder filter, and page token
     * @param maxResults Maximum number of results
     * @param dateFilter Date filter in Gmail format
     * @param searchTerm Optional search term
     * @param folder Gmail label/folder
     * @param pageToken Token for fetching next page of results
     * @return Response with message IDs and pagination info
     */
    public static HttpResponse getMessageIds(Integer maxResults, String dateFilter, String searchTerm, String folder, String pageToken) {
        // Get access token from AI_Workspace_User__c
        String accessToken = getAccessToken();
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(buildMessageIdsEndpoint(maxResults, dateFilter, searchTerm, folder, pageToken));
        req.setMethod('GET');
        req.setTimeout(DEFAULT_TIMEOUT);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + accessToken);

        Http http = new Http();
        return http.send(req);
    }

    /**
     * BATCH REQUEST: Fetch metadata for multiple messages in ONE HTTP call
     * Step 2 of the optimized flow: Get metadata for all IDs at once
     *
     * Uses Gmail Batch API (multipart/mixed) to combine requests.
     * Splits large requests into smaller batches to avoid rate limits.
     * Includes retry logic with exponential backoff for 429 errors.
     *
     * @param messageIds List of Gmail message IDs to fetch
     * @return List of message metadata objects
     */
    public static List<Map<String, Object>> getMessagesBatch(List<String> messageIds) {
        if (messageIds == null || messageIds.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        List<Map<String, Object>> allMessages = new List<Map<String, Object>>();

        // Split into smaller batches to avoid rate limits
        Integer totalBatches = (Integer) Math.ceil((Decimal) messageIds.size() / MAX_BATCH_SIZE);

        for (Integer batchNum = 0; batchNum < totalBatches; batchNum++) {
            Integer startIdx = batchNum * MAX_BATCH_SIZE;
            Integer endIdx = Math.min(startIdx + MAX_BATCH_SIZE, messageIds.size());

            List<String> batchIds = new List<String>();
            for (Integer i = startIdx; i < endIdx; i++) {
                batchIds.add(messageIds[i]);
            }

            // Execute batch with retry logic
            List<Map<String, Object>> batchMessages = executeBatchWithRetry(batchIds, false);
            allMessages.addAll(batchMessages);
        }

        return allMessages;
    }

    /**
     * Executes a single batch request with retry logic for rate limit errors
     * @param messageIds List of message IDs for this batch
     * @param fullFormat Whether to fetch full message content (true) or metadata only (false)
     * @return List of message objects
     */
    private static List<Map<String, Object>> executeBatchWithRetry(List<String> messageIds, Boolean fullFormat) {
        Integer retryCount = 0;
        Integer delayMs = INITIAL_RETRY_DELAY_MS;
        
        // Get access token from AI_Workspace_User__c
        String accessToken = getAccessToken();

        while (retryCount <= MAX_RETRIES) {
            try {
                // Build batch request body
                String batchBody = fullFormat ?
                    buildFullBatchRequestBody(messageIds) :
                    buildBatchRequestBody(messageIds);

                HttpRequest req = new HttpRequest();
                req.setEndpoint(getBatchEndpoint());
                req.setMethod('POST');
                req.setTimeout(DEFAULT_TIMEOUT);
                req.setHeader('Content-Type', 'multipart/mixed; boundary=' + BATCH_BOUNDARY);
                req.setHeader('Authorization', 'Bearer ' + accessToken);
                req.setBody(batchBody);

                Http http = new Http();
                HttpResponse response = http.send(req);

                if (response.getStatusCode() == 200) {
                    // Check if any individual responses have 429 errors
                    List<Map<String, Object>> messages = parseBatchResponseWithRateLimitCheck(response.getBody());
                    if (messages != null) {
                        return messages;
                    }
                    // If null returned, it means we got 429 errors in individual responses
                    // Fall through to retry logic
                } else if (response.getStatusCode() == 429) {
                    // Rate limit hit
                } else {
                    // Non-retryable error
                    throw new GmailAPIException('Gmail batch request failed with status: ' + response.getStatusCode());
                }

                // Rate limit hit - wait and retry
                retryCount++;
                if (retryCount <= MAX_RETRIES) {
                    // Apex doesn't have Thread.sleep, so we use a CPU-based delay
                    Long startTime = System.currentTimeMillis();
                    while (System.currentTimeMillis() - startTime < delayMs) {
                        // Busy wait - not ideal but Apex has limited options
                    }
                    delayMs *= 2; // Exponential backoff
                }
            } catch (GmailAPIException e) {
                throw e; // Re-throw our custom exceptions
            } catch (Exception e) {
                throw new GmailAPIException('Gmail batch request failed: ' + e.getMessage());
            }
        }

        // All retries exhausted
        return new List<Map<String, Object>>();
    }

    /**
     * Parses batch response and checks for rate limit errors in individual responses
     * @return List of messages if successful, null if rate limit errors detected
     */
    private static List<Map<String, Object>> parseBatchResponseWithRateLimitCheck(String responseBody) {
        List<Map<String, Object>> messages = new List<Map<String, Object>>();
        Integer rateLimitErrors = 0;
        Integer partsProcessed = 0;
        Integer parseErrors = 0;
        Integer httpErrors = 0;

        if (String.isBlank(responseBody)) {
            return messages;
        }

        // Find the boundary marker from the response
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

        // Parse each part
        Integer searchStart = 0;
        while (true) {
            Integer partStart = responseBody.indexOf(boundary, searchStart);
            if (partStart == -1) {
                break;
            }

            Integer partEnd = responseBody.indexOf(boundary, partStart + boundary.length());
            if (partEnd == -1) {
                partEnd = responseBody.length();
            }

            String part = responseBody.substring(partStart + boundary.length(), partEnd);
            searchStart = partEnd;

            if (String.isBlank(part) || part.trim() == '--') {
                continue;
            }

            partsProcessed++;

            // Check for 429 rate limit error
            if (part.contains('HTTP/1.1 429')) {
                rateLimitErrors++;
                continue;
            }

            // Check for other HTTP errors
            if (part.contains('HTTP/1.1 4') || part.contains('HTTP/1.1 5')) {
                httpErrors++;
                continue;
            }

            // Find and parse JSON
            Integer jsonStart = part.indexOf('{"id"');
            if (jsonStart == -1) {
                Integer altStart = part.indexOf('{');
                if (altStart >= 0 && part.indexOf('"id"', altStart) > altStart) {
                    jsonStart = altStart;
                }
            }

            if (jsonStart >= 0) {
                String jsonCandidate = part.substring(jsonStart);
                Integer braceDepth = 0;
                Integer jsonEnd = -1;

                for (Integer i = 0; i < jsonCandidate.length(); i++) {
                    String ch = jsonCandidate.substring(i, i + 1);
                    if (ch == '{') {
                        braceDepth++;
                    } else if (ch == '}') {
                        braceDepth--;
                        if (braceDepth == 0) {
                            jsonEnd = i;
                            break;
                        }
                    }
                }

                if (jsonEnd > 0) {
                    String jsonBody = jsonCandidate.substring(0, jsonEnd + 1);
                    try {
                        Map<String, Object> message = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
                        if (message.containsKey('id')) {
                            messages.add(message);
                        } else if (message.containsKey('error')) {
                            httpErrors++;
                        }
                    } catch (Exception e) {
                        parseErrors++;
                    }
                }
            }
        }

        // If we have rate limit errors and no successful messages, signal retry needed
        if (rateLimitErrors > 0 && messages.isEmpty()) {
            return null; // Signal to retry
        }

        return messages;
    }

    /**
     * BATCH REQUEST: Fetch FULL messages (with body) for multiple IDs in ONE HTTP call.
     * Used for importing emails - needs complete content including body.
     * Splits large requests into smaller batches with retry logic.
     *
     * @param messageIds List of Gmail message IDs to fetch
     * @return List of full message objects (with body content)
     */
    public static List<Map<String, Object>> getFullMessagesBatch(List<String> messageIds) {
        if (messageIds == null || messageIds.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        List<Map<String, Object>> allMessages = new List<Map<String, Object>>();

        // Split into smaller batches to avoid rate limits
        Integer totalBatches = (Integer) Math.ceil((Decimal) messageIds.size() / MAX_BATCH_SIZE);

        for (Integer batchNum = 0; batchNum < totalBatches; batchNum++) {
            Integer startIdx = batchNum * MAX_BATCH_SIZE;
            Integer endIdx = Math.min(startIdx + MAX_BATCH_SIZE, messageIds.size());

            List<String> batchIds = new List<String>();
            for (Integer i = startIdx; i < endIdx; i++) {
                batchIds.add(messageIds[i]);
            }

            // Execute batch with retry logic (fullFormat = true for full message content)
            List<Map<String, Object>> batchMessages = executeBatchWithRetry(batchIds, true);
            allMessages.addAll(batchMessages);
        }

        return allMessages;
    }

    /**
     * Builds the multipart batch request body for FULL messages (with body content).
     * Each part is a separate GET request for the complete message.
     */
    private static String buildFullBatchRequestBody(List<String> messageIds) {
        List<String> parts = new List<String>();

        for (Integer i = 0; i < messageIds.size(); i++) {
            String messageId = messageIds[i];

            // Build GET request for full message (format=full includes body)
            String path = '/gmail/v1/users/me/messages/' + messageId + '?format=full';

            String part = '--' + BATCH_BOUNDARY + '\r\n' +
                'Content-Type: application/http\r\n' +
                'Content-ID: <item' + i + '>\r\n\r\n' +
                'GET ' + path + '\r\n';

            parts.add(part);
        }

        // Close the multipart body
        String body = String.join(parts, '\r\n') + '\r\n--' + BATCH_BOUNDARY + '--';

        return body;
    }

    /**
     * Builds the multipart batch request body
     * Each part is a separate GET request for message metadata
     */
    private static String buildBatchRequestBody(List<String> messageIds) {
        List<String> parts = new List<String>();

        for (Integer i = 0; i < messageIds.size(); i++) {
            String messageId = messageIds[i];

            // Build the individual GET request for this message
            // Using tight field mask and metadata format for minimal payload
            // CRITICAL: Message-Id header is required for deduplication against existing EmailMessage records
            String path = '/gmail/v1/users/me/messages/' + messageId +
                '?format=metadata' +
                '&metadataHeaders=From' +
                '&metadataHeaders=Subject' +
                '&metadataHeaders=Date' +
                '&metadataHeaders=To' +
                '&metadataHeaders=Cc' +
                '&metadataHeaders=Message-Id' +
                '&fields=id,threadId,labelIds,internalDate,snippet,payload/headers';

            String part = '--' + BATCH_BOUNDARY + '\r\n' +
                'Content-Type: application/http\r\n' +
                'Content-ID: <item' + i + '>\r\n\r\n' +
                'GET ' + path + '\r\n';

            parts.add(part);
        }

        // Close the multipart body
        String body = String.join(parts, '\r\n') + '\r\n--' + BATCH_BOUNDARY + '--';

        return body;
    }

    /**
     * Parses the multipart batch response into individual message objects
     * Uses indexOf-based boundary parsing to avoid regex complexity limits
     */
    private static List<Map<String, Object>> parseBatchResponse(String responseBody) {
        List<Map<String, Object>> messages = new List<Map<String, Object>>();
        Integer partsProcessed = 0;
        Integer parseErrors = 0;
        Integer httpErrors = 0;

        if (String.isBlank(responseBody)) {
            return messages;
        }

        // Find the boundary marker from the response (format: --batch_xxxxx)
        Integer firstBoundary = responseBody.indexOf('--batch');
        if (firstBoundary == -1) {
            return messages;
        }

        // Extract the boundary string (up to the next line break)
        Integer boundaryEnd = responseBody.indexOf('\r\n', firstBoundary);
        if (boundaryEnd == -1) {
            boundaryEnd = responseBody.indexOf('\n', firstBoundary);
        }
        if (boundaryEnd == -1) {
            return messages;
        }

        String boundary = responseBody.substring(firstBoundary, boundaryEnd);

        // Parse each part by finding boundaries using indexOf
        Integer searchStart = 0;
        while (true) {
            Integer partStart = responseBody.indexOf(boundary, searchStart);
            if (partStart == -1) {
                break;
            }

            Integer partEnd = responseBody.indexOf(boundary, partStart + boundary.length());
            if (partEnd == -1) {
                partEnd = responseBody.length();
            }

            String part = responseBody.substring(partStart + boundary.length(), partEnd);
            searchStart = partEnd;

            // Skip empty parts and closing boundary
            if (String.isBlank(part) || part.trim() == '--') {
                continue;
            }

            partsProcessed++;

            // Check for HTTP error status in the part (e.g., "HTTP/1.1 404 Not Found")
            if (part.contains('HTTP/1.1 4') || part.contains('HTTP/1.1 5')) {
                httpErrors++;
                continue;
            }

            // Find JSON in this part - look for {"id": pattern which starts a message
            Integer jsonStart = part.indexOf('{"id"');
            if (jsonStart == -1) {
                // Try alternate pattern - but only if it looks like valid JSON
                Integer altStart = part.indexOf('{');
                if (altStart >= 0 && part.indexOf('"id"', altStart) > altStart) {
                    jsonStart = altStart;
                }
            }

            if (jsonStart >= 0) {
                // Find matching closing brace by counting brace depth
                String jsonCandidate = part.substring(jsonStart);
                Integer braceDepth = 0;
                Integer jsonEnd = -1;

                for (Integer i = 0; i < jsonCandidate.length(); i++) {
                    String ch = jsonCandidate.substring(i, i + 1);
                    if (ch == '{') {
                        braceDepth++;
                    } else if (ch == '}') {
                        braceDepth--;
                        if (braceDepth == 0) {
                            jsonEnd = i;
                            break;
                        }
                    }
                }

                if (jsonEnd > 0) {
                    String jsonBody = jsonCandidate.substring(0, jsonEnd + 1);
                    try {
                        Map<String, Object> message = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
                        if (message.containsKey('id')) {
                            messages.add(message);
                        } else if (message.containsKey('error')) {
                            // Gmail API error response for this message
                            httpErrors++;
                        }
                    } catch (Exception e) {
                        parseErrors++;
                    }
                }
            }
        }

        return messages;
    }

    /**
     * Legacy method for backwards compatibility
     * Retrieves multiple messages from Gmail API with pagination
     */
    public static HttpResponse getMessages(Integer maxResults, Integer skip, String query, String searchTerm) {
        return getMessageIds(maxResults, query, searchTerm);
    }

    /**
     * Retrieves a single message by ID from Gmail API with full content
     * Used when importing an email - needs full body content
     */
    public static HttpResponse getSingleMessage(String messageId) {
        return getSingleMessage(messageId, 'full');
    }

    /**
     * Retrieves a single message by ID with specified format
     * @param messageId The Gmail message ID
     * @param format 'full' for complete message with body, 'metadata' for headers only
     */
    public static HttpResponse getSingleMessage(String messageId, String format) {
        // Get access token from AI_Workspace_User__c
        String accessToken = getAccessToken();
        
        HttpRequest req = new HttpRequest();
        String endpoint = getGmailApiEndpoint() + '/gmail/v1/users/me/messages/' + messageId +
            '?format=' + format;

        // For metadata format, specify which headers we need
        // CRITICAL: Message-Id header is required for deduplication against existing EmailMessage records
        if (format == 'metadata') {
            endpoint += '&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Date&metadataHeaders=Message-Id';
        }

        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(DEFAULT_TIMEOUT);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + accessToken);

        Http http = new Http();
        return http.send(req);
    }

    /**
     * Builds endpoint for message ID list (lightweight, no metadata)
     * Uses fields mask to return only id and threadId
     * @param maxResults Maximum number of results
     * @param dateFilter Date filter (already in Gmail format from EmailSyncService)
     * @param searchTerm Optional search term
     * @param folder Gmail label/folder (e.g., "INBOX", "SENT")
     * @param pageToken Optional page token for pagination
     */
    private static String buildMessageIdsEndpoint(Integer maxResults, String dateFilter, String searchTerm, String folder, String pageToken) {
        String endpoint = getGmailApiEndpoint() + '/gmail/v1/users/me/messages';

        List<String> queryParams = new List<String>();
        queryParams.add('maxResults=' + maxResults);

        // Use fields mask to return only what we need (IDs)
        queryParams.add('fields=messages(id,threadId),nextPageToken,resultSizeEstimate');

        // Add page token for pagination if provided
        if (String.isNotBlank(pageToken)) {
            queryParams.add('pageToken=' + EncodingUtil.urlEncode(pageToken, 'UTF-8'));
        }

        // Build Gmail query string
        String gmailQuery = buildGmailQuery(dateFilter, searchTerm, folder);
        if (String.isNotBlank(gmailQuery)) {
            queryParams.add('q=' + EncodingUtil.urlEncode(gmailQuery, 'UTF-8'));
        }

        String finalEndpoint = endpoint + '?' + String.join(queryParams, '&');
        return finalEndpoint;
    }

    /**
     * Legacy endpoint builder - kept for backwards compatibility
     */
    private static String buildMessagesEndpoint(Integer maxResults, Integer skip, String query, String searchTerm) {
        return buildMessageIdsEndpoint(maxResults, query, searchTerm, null, null);
    }

    /**
     * Builds Gmail query string from filter criteria and folder
     * Combines date filter (from EmailSyncService), search term, and folder label
     *
     * @param dateFilter Date filter already in Gmail format (e.g., "after:1733222400 before:1733308800")
     * @param searchTerm Optional search term from user
     * @param folder Gmail label/folder (e.g., "INBOX", "SENT")
     * @return Combined Gmail query string
     */
    @TestVisible
    private static String buildGmailQuery(String dateFilter, String searchTerm, String folder) {
        List<String> queryParts = new List<String>();

        // Add folder/label filter
        if (String.isNotBlank(folder)) {
            // Gmail uses "in:" for labels/folders
            // Map common folder names to Gmail labels
            String labelQuery = folder.toUpperCase();
            if (labelQuery == 'INBOX') {
                queryParts.add('in:inbox');
            } else if (labelQuery == 'SENT' || labelQuery == 'SENTITEMS') {
                queryParts.add('in:sent');
            } else if (labelQuery == 'DRAFTS') {
                queryParts.add('in:drafts');
            } else if (labelQuery == 'TRASH') {
                queryParts.add('in:trash');
            } else if (labelQuery == 'SPAM') {
                queryParts.add('in:spam');
            } else {
                // Custom label
                queryParts.add('label:' + folder);
            }
        } else if (String.isBlank(searchTerm)) {
            // When no folder is specified and no search term, include both inbox AND sent
            // This ensures the "today" filter shows all emails (incoming and sent) from today
            // Gmail doesn't support OR in queries directly, so we use {in:inbox in:sent}
            queryParts.add('{in:inbox in:sent}');
        }

        // Add search term if provided
        if (String.isNotBlank(searchTerm)) {
            queryParts.add(searchTerm);
        }

        // Add date filter (EmailSyncService already formats this as "after:timestamp before:timestamp")
        if (String.isNotBlank(dateFilter)) {
            // The dateFilter from EmailSyncService is already in Gmail format
            // e.g., "after:1733222400 before:1733308800"
            queryParts.add(dateFilter);
        }

        String finalQuery = String.join(queryParts, ' ');
        return finalQuery;
    }

    /**
     * Parses Gmail API response JSON
     */
    public static Map<String, Object> parseEmailResponse(String responseBody) {
        Map<String, Object> parsedResponse =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        List<Object> messages = (List<Object>) parsedResponse.get('messages');
        String nextPageToken = (String) parsedResponse.get('nextPageToken');
        Integer resultSizeEstimate = (Integer) parsedResponse.get('resultSizeEstimate');

        return new Map<String, Object>{
            'messages' => messages != null ? messages : new List<Object>(),
            'resultSizeEstimate' => resultSizeEstimate != null ? resultSizeEstimate : 0,
            'hasMore' => String.isNotBlank(nextPageToken),
            'nextPageToken' => nextPageToken
        };
    }

    /**
     * Get accurate message count for a Gmail label using labels.get API
     * This is more reliable than resultSizeEstimate which caps around 200-250
     * 
     * @param labelId Gmail label ID (e.g., 'INBOX', 'SENT', 'UNREAD')
     * @return Accurate count of messages in the label, or -1 if error
     */
    public static Integer getLabelMessageCount(String labelId) {
        try {
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            String endpoint = getGmailApiEndpoint() + '/gmail/v1/users/me/labels/' + 
                EncodingUtil.urlEncode(labelId, 'UTF-8');
            
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> labelData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                Integer messagesTotal = (Integer) labelData.get('messagesTotal');
                return messagesTotal != null ? messagesTotal : 0;
            }
            
            return -1; // Error case
        } catch (Exception e) {
            return -1; // Error case
        }
    }

    /**
     * Get combined message count for INBOX and SENT folders
     * This provides an accurate total for the "all emails" view
     * 
     * @return Combined count of INBOX + SENT messages, or -1 if error
     */
    public static Integer getCombinedInboxSentCount() {
        try {
            Integer inboxCount = getLabelMessageCount('INBOX');
            Integer sentCount = getLabelMessageCount('SENT');
            
            if (inboxCount >= 0 && sentCount >= 0) {
                return inboxCount + sentCount;
            }
            
            return -1; // Error case
        } catch (Exception e) {
            return -1; // Error case
        }
    }
}