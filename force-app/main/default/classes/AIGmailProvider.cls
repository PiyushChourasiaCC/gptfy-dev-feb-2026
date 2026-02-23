/**
 * Gmail API provider implementation
 * Handles email retrieval from Gmail via Gmail API
 *
 * FILTER CONVERSION:
 * The LWC sends filters in OData format (Microsoft Graph syntax) as the common
 * interface. This provider converts OData filters to Gmail query syntax:
 *   - receivedDateTime ge DATETIME -> after:UNIX_TIMESTAMP
 *   - isRead eq false -> is:unread
 *   - hasAttachments eq true -> has:attachment
 *
 * PERFORMANCE OPTIMIZATION:
 * Uses 2-step batch approach for fast list view rendering:
 * 1. Get message IDs (lightweight, single call)
 * 2. Batch fetch metadata for all IDs (single HTTP call with multipart)
 *
 * This reduces latency from ~16s (20 sequential calls) to ~2s (2 calls total)
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIGmailProvider extends AIEmailProviderService {

    private static final Integer DEFAULT_TIMEOUT = 120000;

    // Gmail API endpoint (direct URL, not Named Credential)
    private static String getGmailApiEndpoint() {
        return AIWorkspaceTokenService.getGmailEndpoint();
    }
    
    /**
     * Get access token for the current user
     */
    private static String getAccessToken() {
        return AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_GMAIL);
    }

    public override EmailProviderResponse getEmails(EmailProviderRequest request) {
        try {
            Long startTime = System.currentTimeMillis();

            // Convert OData filter to Gmail query format
            String gmailDateFilter = convertODataToGmailFilter(request.filterCriteria);

            // Step 1: Get list of message IDs (lightweight - just IDs)
            // Pass folder to filter by INBOX, SENT, etc.
            // Pass pageToken for pagination
            HttpResponse listResponse = AIGmailService.getMessageIds(
                request.recordLimit,
                gmailDateFilter,
                request.searchTerm,
                request.folder,
                request.pageToken
            );

            if (listResponse.getStatusCode() != 200) {
                throw new EmailProviderException(
                    'Gmail API list returned status: ' + listResponse.getStatusCode()
                );
            }

            Map<String, Object> listData = (Map<String, Object>) JSON.deserializeUntyped(listResponse.getBody());
            List<Object> messageList = (List<Object>) listData.get('messages');

            Integer listCount = messageList != null ? messageList.size() : 0;

            List<Map<String, Object>> transformedEmails = new List<Map<String, Object>>();

            // Step 2: BATCH fetch metadata for all messages in ONE HTTP call
            if (messageList != null && !messageList.isEmpty()) {
                // Extract message IDs
                List<String> messageIds = new List<String>();
                for (Object msgObj : messageList) {
                    Map<String, Object> msg = (Map<String, Object>) msgObj;
                    String messageId = (String) msg.get('id');
                    if (String.isNotBlank(messageId)) {
                        messageIds.add(messageId);
                    }
                }


                // Batch fetch all message metadata in ONE call
                List<Map<String, Object>> batchMessages = AIGmailService.getMessagesBatch(messageIds);

               
                // Transform each message to Graph-compatible format
                Integer transformErrors = 0;
                for (Map<String, Object> metadataMessage : batchMessages) {
                    try {
                        Map<String, Object> transformedEmail =
                            AIGmailEmailTransformer.transformToGraphFormat(metadataMessage);
                        transformedEmails.add(transformedEmail);
                    } catch (Exception transformEx) {
                        transformErrors++;
                    }
                }

            }

            Long endTime = System.currentTimeMillis();

            // Get accurate total count using Gmail labels API
            // IMPORTANT: Only use labels API when NO date/search filters are applied
            // Labels API returns total for entire label, not filtered results
            // When filters are applied, we rely on pagination to determine total count
            Integer accurateTotalCount = -1;
            Boolean hasDateFilter = String.isNotBlank(gmailDateFilter);
            Boolean hasSearchFilter = String.isNotBlank(request.searchTerm);
            
            // Only fetch label counts when showing ALL emails (no filters)
            if (!hasDateFilter && !hasSearchFilter) {
                // Determine which label count to fetch based on folder filter
                if (String.isNotBlank(request.folder)) {
                    String folderUpper = request.folder.toUpperCase();
                    if (folderUpper == 'INBOX') {
                        accurateTotalCount = AIGmailService.getLabelMessageCount('INBOX');
                    } else if (folderUpper == 'SENT' || folderUpper == 'SENTITEMS') {
                        accurateTotalCount = AIGmailService.getLabelMessageCount('SENT');
                    }
                } else {
                    // No specific folder - get combined INBOX + SENT count
                    accurateTotalCount = AIGmailService.getCombinedInboxSentCount();
                }
            }
            
            // Determine total count:
            // 1. Use accurate label count if available (no filters applied)
            // 2. Otherwise, don't set a specific total - let frontend calculate from pagination
            Integer totalCount = accurateTotalCount >= 0 ? 
                accurateTotalCount : 
                0; // Return 0 to indicate unknown total (filtered results)

            EmailProviderResponse providerResponse = new EmailProviderResponse();
            providerResponse.emails = transformedEmails;
            providerResponse.totalCount = totalCount;
            providerResponse.nextPageToken = (String) listData.get('nextPageToken');
            providerResponse.hasMore = String.isNotBlank(providerResponse.nextPageToken);

            return providerResponse;
        } catch (Exception e) {
            throw new EmailProviderException('Gmail API error: ' + e.getMessage());
        }
    }

    public override Map<String, Object> getSingleEmail(String messageId) {
        try {
            HttpResponse response = AIGmailService.getSingleMessage(messageId);

            if (response.getStatusCode() == 200) {
                Map<String, Object> gmailMessage = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                // Transform to Graph format so EmailMessageCreator can process it correctly
                return AIGmailEmailTransformer.transformToGraphFormat(gmailMessage);
            } else {
                throw new EmailProviderException(
                    'Gmail API returned status: ' + response.getStatusCode()
                );
            }
        } catch (Exception e) {
            throw new EmailProviderException('Gmail API error: ' + e.getMessage());
        }
    }

    public override ProviderType getProviderType() {
        return ProviderType.GMAIL;
    }

    public override Boolean isAuthenticated() {
        // Check if user has a valid connection in AI_Workspace_User__c
        try {
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(getGmailApiEndpoint() + '/gmail/v1/users/me/profile');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);


            return response.getStatusCode() == 200;
        } catch (Exception e) {
            return false;
        }
    }

    public override String getUserEmail() {
        try {
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(getGmailApiEndpoint() + '/gmail/v1/users/me/profile');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> profile =
                    (Map<String, Object>) JSON.deserializeUntyped(response.getBody());

                String email = (String) profile.get('emailAddress');
                return String.isNotBlank(email) ? email : '';
            }

            return '';
        } catch (Exception e) {
            return '';
        }
    }

    /**
     * Batch fetch multiple emails by ID using Gmail batch API.
     * Fetches FULL email content (including body) for import.
     * Uses AIGmailService.getFullMessagesBatch for efficient batch processing.
     *
     * @param messageIds List of Gmail message IDs to fetch
     * @return List of email data maps with full content (in same order as input)
     */
    public override List<Map<String, Object>> getEmailsBatch(List<String> messageIds) {
        if (messageIds == null || messageIds.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        try {
            // Use batch API to fetch full email content
            List<Map<String, Object>> batchResults = AIGmailService.getFullMessagesBatch(messageIds);

            // Transform each message to Graph-compatible format
            List<Map<String, Object>> transformedResults = new List<Map<String, Object>>();
            for (Map<String, Object> gmailMessage : batchResults) {
                try {
                    if (gmailMessage != null) {
                        Map<String, Object> transformed = AIGmailEmailTransformer.transformToGraphFormat(gmailMessage);
                        transformedResults.add(transformed);
                    } else {
                        transformedResults.add(null);
                    }
                } catch (Exception e) {
                    transformedResults.add(null);
                }
            }

            return transformedResults;
        } catch (Exception e) {
            // Fall back to base class sequential implementation
            return super.getEmailsBatch(messageIds);
        }
    }

    /**
     * Converts OData filter syntax (used by Microsoft Graph) to Gmail query syntax.
     * The LWC sends OData filters like "receivedDateTime ge 2025-12-04T00:00:00Z"
     * which need to be converted to Gmail format like "after:1733270400".
     *
     * Supported conversions:
     * - receivedDateTime ge DATETIME -> after:UNIX_TIMESTAMP
     * - receivedDateTime le DATETIME -> before:UNIX_TIMESTAMP
     * - isRead eq false -> is:unread
     * - isRead eq true -> is:read
     * - hasAttachments eq true -> has:attachment
     *
     * @param odataFilter The OData filter string from the LWC
     * @return Gmail query string, or null if no conversion needed
     * NO REGEX - uses simple string parsing
     */
    @TestVisible
    private static String convertODataToGmailFilter(String odataFilter) {
        if (String.isBlank(odataFilter)) {
            return null;
        }

        List<String> gmailParts = new List<String>();

        // Handle date filter: receivedDateTime ge 2025-12-04T00:00:00Z
        // NO REGEX - parse manually
        parseDateFilter(odataFilter, 'receivedDateTime ge ', 'after:', gmailParts);
        parseDateFilter(odataFilter, 'receivedDateTime le ', 'before:', gmailParts);

        // Handle unread filter: isRead eq false
        if (odataFilter.containsIgnoreCase('isRead eq false')) {
            gmailParts.add('is:unread');
        } else if (odataFilter.containsIgnoreCase('isRead eq true')) {
            gmailParts.add('is:read');
        }

        // Handle attachments filter: hasAttachments eq true
        if (odataFilter.containsIgnoreCase('hasAttachments eq true')) {
            gmailParts.add('has:attachment');
        }

        if (gmailParts.isEmpty()) {
            // If we couldn't convert anything, return null to avoid passing invalid query
            return null;
        }

        String result = String.join(gmailParts, ' ');
        return result;
    }

    /**
     * Parse date filter from OData string without regex
     * @param odataFilter The OData filter string
     * @param prefix The prefix to look for (e.g., "receivedDateTime ge ")
     * @param gmailPrefix The Gmail prefix to use (e.g., "after:")
     * @param gmailParts List to add the result to
     */
    private static void parseDateFilter(String odataFilter, String prefix, String gmailPrefix, List<String> gmailParts) {
        Integer startPos = odataFilter.indexOf(prefix);
        if (startPos < 0) {
            return;
        }

        // Find the date string after the prefix
        Integer dateStart = startPos + prefix.length();
        if (dateStart >= odataFilter.length()) {
            return;
        }

        // Find the end of the date string (next space or end of string)
        Integer dateEnd = odataFilter.indexOf(' ', dateStart);
        if (dateEnd < 0) {
            dateEnd = odataFilter.length();
        }

        // Also check for "and" keyword
        Integer andPos = odataFilter.indexOf(' and ', dateStart);
        if (andPos > 0 && andPos < dateEnd) {
            dateEnd = andPos;
        }

        String dateStr = odataFilter.substring(dateStart, dateEnd).trim();

        try {
            // Parse the ISO date string
            // Format: 2025-12-04T00:00:00Z or 2025-12-04T00:00:00.000Z
            dateStr = dateStr.replace('Z', '');
            // Remove timezone info, we'll parse as GMT
            if (dateStr.contains('+')) {
                dateStr = dateStr.substringBefore('+');
            }

            // Ensure we have at least 19 characters for DateTime parsing
            String parseStr = dateStr.replace('T', ' ');
            if (parseStr.length() > 19) {
                parseStr = parseStr.substring(0, 19);
            }

            DateTime dt = DateTime.valueOf(parseStr);
            Long unixTimestamp = dt.getTime() / 1000;

            gmailParts.add(gmailPrefix + unixTimestamp);
        } catch (Exception e) {
        }
    }
}