/**
 * Microsoft Graph API provider implementation
 * Handles email retrieval from Microsoft Exchange/Outlook via Graph API
 *
 * AUTHENTICATION: Uses access tokens from AI_Workspace_User__c
 * Tokens are retrieved and refreshed automatically via AIWorkspaceTokenService
 *
 * PERFORMANCE: Microsoft Graph supports $select to fetch only needed fields
 * in a single request, unlike Gmail which requires batch requests.
 * List view excludes body content for faster loading.
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIMicrosoftGraphProvider extends AIEmailProviderService {

    private static final Integer DEFAULT_TIMEOUT = 120000;

    // Microsoft Graph API endpoint (direct URL, not Named Credential)
    private static String getGraphApiEndpoint() {
        return AIWorkspaceTokenService.getMicrosoftGraphEndpoint();
    }
    
    /**
     * Get access token for the current user
     */
    private static String getAccessToken() {
        return AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_OUTLOOK);
    }

    public override EmailProviderResponse getEmails(EmailProviderRequest request) {
        try {
            Long startTime = System.currentTimeMillis();
            
            List<Map<String, Object>> allEmails = new List<Map<String, Object>>();
            Integer totalCount = 0;
            Boolean hasMore = false;
            
            // Simplify the filter - remove the OR clause for date filtering
            // The Graph API /me/messages endpoint returns all emails sorted by receivedDateTime
            // For sent items, receivedDateTime is populated (it's when the email was received by the mailbox system)
            String simplifiedFilter = simplifyFilter(request.filterCriteria);

            // Use /me/messages for all queries (no folder) - this returns inbox+sent+drafts
            // sorted by receivedDateTime desc which works for all email types
            HttpResponse response = AIExchangeEmailService.getMessages(
                request.recordLimit,
                request.offset,
                simplifiedFilter,
                request.searchTerm,
                null // No folder - use /me/messages which returns all
            );

            if (response.getStatusCode() == 200) {
                Map<String, Object> parsedResponse = AIExchangeEmailService.parseEmailResponse(response.getBody());
                List<Object> emailObjects = (List<Object>) parsedResponse.get('value');
                
                if (emailObjects != null) {
                    for (Object emailObj : emailObjects) {
                        allEmails.add((Map<String, Object>) emailObj);
                    }
                }
                totalCount = (Integer) parsedResponse.get('totalCount');
                hasMore = (Boolean) parsedResponse.get('hasMore');
            } else {
                throw new EmailProviderException(
                    'Graph API returned status: ' + response.getStatusCode() + ' - ' + response.getBody()
                );
            }

            Long endTime = System.currentTimeMillis();

            EmailProviderResponse providerResponse = new EmailProviderResponse();
            providerResponse.emails = allEmails;
            providerResponse.totalCount = totalCount;
            providerResponse.hasMore = hasMore;

            return providerResponse;
        } catch (Exception e) {
            throw new EmailProviderException('Microsoft Graph error: ' + e.getMessage());
        }
    }
    
    /**
     * Simplify the filter criteria from LWC
     * Converts the OR-based date filter to a simple receivedDateTime filter
     * because Microsoft Graph API doesn't support complex OR filters well
     */
    private String simplifyFilter(String filterCriteria) {
        if (String.isBlank(filterCriteria)) {
            return null;
        }
        
        // If filter contains the OR pattern for date filtering, simplify it
        // "(receivedDateTime ge 2026-02-03... or sentDateTime ge 2026-02-03...)"
        // becomes: "receivedDateTime ge 2026-02-03..."
        if (filterCriteria.contains('receivedDateTime') && filterCriteria.contains('sentDateTime')) {
            // Extract just the receivedDateTime part
            DateTime filterDate = parseDateFromFilter(filterCriteria);
            if (filterDate != null) {
                String dateStr = filterDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                
                // Check if there are other filters (unread, hasAttachments)
                List<String> otherFilters = new List<String>();
                if (filterCriteria.containsIgnoreCase('isRead eq false')) {
                    otherFilters.add('isRead eq false');
                }
                if (filterCriteria.containsIgnoreCase('hasAttachments eq true')) {
                    otherFilters.add('hasAttachments eq true');
                }
                
                // Build simplified filter
                String dateFilter = 'receivedDateTime ge ' + dateStr;
                if (!otherFilters.isEmpty()) {
                    return dateFilter + ' and ' + String.join(otherFilters, ' and ');
                }
                return dateFilter;
            }
        }
        
        // Return original filter for simple cases (unread, hasAttachments)
        return filterCriteria;
    }
    
    /**
     * Comparator to sort emails by date (newest first)
     * Uses receivedDateTime for inbox emails, sentDateTime for sent items
     */
    @TestVisible
    private class EmailDateComparator implements Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            DateTime dateA = getEmailDate(a);
            DateTime dateB = getEmailDate(b);
            
            // Sort descending (newest first)
            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1; // null dates go to end
            if (dateB == null) return -1;
            
            if (dateB > dateA) return 1;
            if (dateA > dateB) return -1;
            return 0;
        }
        
        private DateTime getEmailDate(Map<String, Object> email) {
            // Try receivedDateTime first (inbox emails)
            String receivedStr = (String) email.get('receivedDateTime');
            if (String.isNotBlank(receivedStr)) {
                return parseIsoDateTime(receivedStr);
            }
            
            // Fall back to sentDateTime (sent items)
            String sentStr = (String) email.get('sentDateTime');
            if (String.isNotBlank(sentStr)) {
                return parseIsoDateTime(sentStr);
            }
            
            return null;
        }
        
        private DateTime parseIsoDateTime(String isoStr) {
            try {
                // Format: 2026-02-03T10:30:00Z
                String cleaned = isoStr.replace('T', ' ').replace('Z', '');
                if (cleaned.length() > 19) {
                    cleaned = cleaned.substring(0, 19);
                }
                return DateTime.valueOf(cleaned);
            } catch (Exception e) {
                return null;
            }
        }
    }
    
    /**
     * Parse date from OData filter string
     * Looks for patterns like "receivedDateTime ge 2026-02-03T00:00:00.000Z"
     * Returns the date if found, null otherwise
     */
    @TestVisible
    private DateTime parseDateFromFilter(String filterCriteria) {
        if (String.isBlank(filterCriteria)) {
            return null;
        }
        
        // Look for date patterns in the filter
        // Format: receivedDateTime ge 2026-02-03T00:00:00.000Z
        // or: (receivedDateTime ge 2026-02-03... or sentDateTime ge 2026-02-03...)
        
        String searchPattern = 'DateTime ge ';
        Integer idx = filterCriteria.indexOf(searchPattern);
        if (idx < 0) {
            return null;
        }
        
        Integer dateStart = idx + searchPattern.length();
        if (dateStart >= filterCriteria.length()) {
            return null;
        }
        
        // Find end of date string (space, parenthesis, or end of string)
        Integer dateEnd = filterCriteria.length();
        for (Integer i = dateStart; i < filterCriteria.length(); i++) {
            String c = filterCriteria.substring(i, i + 1);
            if (c == ' ' || c == ')' || c == ',') {
                dateEnd = i;
                break;
            }
        }
        
        String dateStr = filterCriteria.substring(dateStart, dateEnd).trim();
        
        try {
            String cleaned = dateStr.replace('T', ' ').replace('Z', '');
            if (cleaned.contains('.')) {
                cleaned = cleaned.substringBefore('.');
            }
            if (cleaned.length() > 19) {
                cleaned = cleaned.substring(0, 19);
            }
            return DateTime.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Apply non-date filters to email list
     * Handles: isRead eq false, hasAttachments eq true
     */
    @TestVisible
    private List<Map<String, Object>> applyNonDateFilters(List<Map<String, Object>> emails, String filterCriteria) {
        if (String.isBlank(filterCriteria) || emails == null || emails.isEmpty()) {
            return emails;
        }
        
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        
        Boolean filterUnread = filterCriteria.containsIgnoreCase('isRead eq false');
        Boolean filterHasAttachments = filterCriteria.containsIgnoreCase('hasAttachments eq true');
        
        // If no non-date filters, return original list
        if (!filterUnread && !filterHasAttachments) {
            return emails;
        }
        
        for (Map<String, Object> email : emails) {
            Boolean include = true;
            
            if (filterUnread) {
                Boolean isRead = (Boolean) email.get('isRead');
                if (isRead == true) {
                    include = false;
                }
            }
            
            if (include && filterHasAttachments) {
                Boolean hasAttachments = (Boolean) email.get('hasAttachments');
                if (hasAttachments != true) {
                    include = false;
                }
            }
            
            if (include) {
                filtered.add(email);
            }
        }
        
        return filtered;
    }

    public override Map<String, Object> getSingleEmail(String messageId) {
        try {
            HttpResponse response = AIExchangeEmailService.getSingleMessage(messageId);

            if (response.getStatusCode() == 200) {
                return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            } else {
                throw new EmailProviderException(
                    'Graph API returned status: ' + response.getStatusCode()
                );
            }
        } catch (Exception e) {
            throw new EmailProviderException('Microsoft Graph error: ' + e.getMessage());
        }
    }

    public override ProviderType getProviderType() {
        return ProviderType.MICROSOFT_EMAIL;
    }

    public override Boolean isAuthenticated() {
        // Check if user has a valid connection in AI_Workspace_User__c
        try {
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(getGraphApiEndpoint() + '/v1.0/me/messages?$top=1');
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
            req.setEndpoint(getGraphApiEndpoint() + '/v1.0/me');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> userInfo =
                    (Map<String, Object>) JSON.deserializeUntyped(response.getBody());

                // Try userPrincipalName first, fallback to mail
                String email = (String) userInfo.get('userPrincipalName');
                if (String.isBlank(email)) {
                    email = (String) userInfo.get('mail');
                }

                return String.isNotBlank(email) ? email : '';
            }

            return '';
        } catch (Exception e) {
            return '';
        }
    }

    /**
     * Batch fetch multiple emails using Graph API $batch endpoint.
     * Microsoft Graph supports up to 20 requests per batch.
     * This reduces callouts from N to ceil(N/20).
     */
    public override List<Map<String, Object>> getEmailsBatch(List<String> messageIds) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();

        if (messageIds == null || messageIds.isEmpty()) {
            return results;
        }

        // Graph API batch limit is 20 requests per batch
        Integer batchSize = 20;
        Integer totalBatches = (Integer) Math.ceil((Decimal) messageIds.size() / batchSize);

        for (Integer batchNum = 0; batchNum < totalBatches; batchNum++) {
            Integer startIdx = batchNum * batchSize;
            Integer endIdx = Math.min(startIdx + batchSize, messageIds.size());

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
                String accessToken = getAccessToken();
                
                HttpRequest req = new HttpRequest();
                req.setEndpoint(getGraphApiEndpoint() + '/v1.0/$batch');
                req.setMethod('POST');
                req.setTimeout(DEFAULT_TIMEOUT);
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Authorization', 'Bearer ' + accessToken);
                req.setBody(JSON.serialize(batchBody));

                Http http = new Http();
                HttpResponse response = http.send(req);

                if (response.getStatusCode() == 200) {
                    Map<String, Object> batchResponse =
                        (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
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
}