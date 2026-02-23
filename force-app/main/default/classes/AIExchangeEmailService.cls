/**
 * AIExchangeEmailService - Microsoft Graph API service for email operations
 * 
 * AUTHENTICATION: Uses access tokens from AI_Workspace_User__c
 * Tokens are retrieved and refreshed automatically via AIWorkspaceTokenService
 * 
 * @author GPTfy
 */
public with sharing class AIExchangeEmailService {

    private static final Integer DEFAULT_TIMEOUT = 120000; // 2 minutes

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
    
    public class GraphAPIException extends Exception {}
    
    /**
     * Retrieves multiple messages from Graph API with pagination (default: all messages)
     * @param top Number of records to fetch
     * @param skip Number of records to skip (pagination)
     * @param filter OData filter string
     * @param searchTerm Search term for $search query
     */
    public static HttpResponse getMessages(Integer top, Integer skip, String filter, String searchTerm) {
        return getMessages(top, skip, filter, searchTerm, null);
    }

    /**
     * Retrieves multiple messages from a specific folder with pagination
     * @param folder Mail folder to query (inbox, sentitems, drafts, etc.) - null for all messages
     */
    public static HttpResponse getMessages(Integer top, Integer skip, String filter, String searchTerm, String folder) {
        // Get access token from AI_Workspace_User__c
        String accessToken = getAccessToken();
        
        HttpRequest req = new HttpRequest();
        String endpoint = buildMessagesEndpoint(top, skip, filter, searchTerm, folder);
        System.debug('Graph API Endpoint: ' + endpoint);
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(DEFAULT_TIMEOUT);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        // Required for advanced queries like $search
        req.setHeader('ConsistencyLevel', 'eventual');

        Http http = new Http();
        HttpResponse response = http.send(req);

        // Log response for debugging
        if (response.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, 'Graph API Error Response: ' + response.getBody());
        }

        return response;
    }
    
    /**
     * Retrieves a single message by ID from Graph API
     */
    public static HttpResponse getSingleMessage(String messageId) {
        // Get access token from AI_Workspace_User__c
        String accessToken = getAccessToken();
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(getGraphApiEndpoint() + '/v1.0/me/messages/' + messageId);
        req.setMethod('GET');
        req.setTimeout(DEFAULT_TIMEOUT);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        
        Http http = new Http();
        return http.send(req);
    }
    
    /**
     * Builds the endpoint URL with query parameters
     * OPTIMIZED: Only fetches lightweight fields for list view (no body content)
     * Full body is fetched only when importing via getSingleMessage()
     *
     * @param folder Mail folder (inbox, sentitems, drafts) - null queries all messages
     */
    private static String buildMessagesEndpoint(Integer top, Integer skip, String filter, String searchTerm, String folder) {
        String endpoint = getGraphApiEndpoint() + '/v1.0';

        Boolean hasFilter = String.isNotBlank(filter);
        Boolean isSearch = String.isNotBlank(searchTerm);

        // Build path based on folder
        // IMPORTANT: When using $filter, we must use /me/messages endpoint
        // The /me/mailFolders/{folder}/messages endpoint has severe restrictions with $filter
        if (String.isNotBlank(folder) && !hasFilter) {
            // No filter - can use mailFolders path
            endpoint += '/me/mailFolders/' + folder + '/messages';
        } else {
            // With filter OR no folder - use /me/messages endpoint
            endpoint += '/me/messages';
        }

        List<String> queryParams = new List<String>();
        queryParams.add('$top=' + top);

        // PERFORMANCE: Only fetch fields needed for list view
        // Excludes 'body' which is large - fetch only when importing
        queryParams.add('$select=id,subject,bodyPreview,from,toRecipients,ccRecipients,receivedDateTime,sentDateTime,hasAttachments,internetMessageId,conversationId,importance,isRead,categories,parentFolderId');

        if (isSearch) {
            // If it's a search, we CANNOT use $skip and $orderby
            queryParams.add('$search=' + EncodingUtil.urlEncode('"' + searchTerm + '"', 'UTF-8'));
            queryParams.add('$count=true');
        } else {
            // Standard list view
            queryParams.add('$skip=' + skip);

            // Always request $count - works with ConsistencyLevel: eventual header
            queryParams.add('$count=true');

            // Apply $orderby to ensure newest emails appear first
            // Skip $orderby only when filter contains properties that don't support ordering
            // (e.g., hasAttachments, importance, isRead - boolean/enum properties)
            Boolean canApplyOrderBy = !hasFilter || 
                (!filter.contains('hasAttachments') && 
                 !filter.contains('importance') && 
                 !filter.contains('isRead'));
            
            if (canApplyOrderBy) {
                if (folder == 'sentitems') {
                    queryParams.add('$orderby=sentDateTime%20desc');
                } else {
                    queryParams.add('$orderby=receivedDateTime%20desc');
                }
            }
        }

        if (hasFilter) {
            queryParams.add('$filter=' + EncodingUtil.urlEncode(filter, 'UTF-8'));
        }

        return endpoint + '?' + String.join(queryParams, '&');
    }
    
    /**
     * Parses Graph API response JSON
     * Extracts total count from @odata.count (requires $count=true in request)
     */
    public static Map<String, Object> parseEmailResponse(String responseBody) {
        Map<String, Object> parsedResponse =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        List<Object> emails = (List<Object>) parsedResponse.get('value');
        String nextLink = (String) parsedResponse.get('@odata.nextLink');

        // Get total count from @odata.count (returned when $count=true is requested)
        // Falls back to current page size if not available
        Integer totalCount = 0;
        Object countObj = parsedResponse.get('@odata.count');
        if (countObj != null) {
            totalCount = Integer.valueOf(countObj);
        } else {
            totalCount = emails != null ? emails.size() : 0;
        }

        return new Map<String, Object>{
            'value' => emails,
            'totalCount' => totalCount,
            'hasMore' => String.isNotBlank(nextLink)
        };
    }
}