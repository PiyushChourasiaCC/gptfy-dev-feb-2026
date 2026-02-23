/**
 * Virtual base class for email provider integrations (Exchange, Gmail, etc.)
 * Defines the contract that all email providers must implement
 */
public virtual class AIEmailProviderService {

    public enum ProviderType { MICROSOFT_GRAPH, GMAIL }

    /**
     * Request object for fetching emails from provider
     */
    public class EmailProviderRequest {
        public Integer recordLimit { get; set; }
        public Integer offset { get; set; }
        public String filterCriteria { get; set; }
        public String searchTerm { get; set; }
        public String providerType { get; set; }
        public String folder { get; set; } // Mail folder: inbox, sentitems, etc.
        public String pageToken { get; set; } // Token for cursor-based pagination (Gmail)

        public EmailProviderRequest() {
            this.recordLimit = 50;
            this.offset = 0;
        }
    }

    /**
     * Response object containing emails and metadata
     */
    public class EmailProviderResponse {
        @AuraEnabled public List<Map<String, Object>> emails { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public String nextPageToken { get; set; }

        public EmailProviderResponse() {
            this.emails = new List<Map<String, Object>>();
            this.totalCount = 0;
            this.hasMore = false;
        }
    }

    /**
     * Custom exception for provider-specific errors
     */
    public class EmailProviderException extends Exception {}

    /**
     * Retrieves emails from the provider with pagination and filtering
     * @param request EmailProviderRequest with filter/search criteria
     * @return EmailProviderResponse with emails and metadata
     */
    public virtual EmailProviderResponse getEmails(EmailProviderRequest request) {
        throw new EmailProviderException('getEmails() must be implemented by provider subclass');
    }

    /**
     * Retrieves a single email by provider-specific message ID
     * @param messageId Provider's unique message identifier
     * @return Email data as Map<String, Object>
     */
    public virtual Map<String, Object> getSingleEmail(String messageId) {
        throw new EmailProviderException('getSingleEmail() must be implemented by provider subclass');
    }

    /**
     * Gets the provider type identifier
     * @return ProviderType enum value
     */
    public virtual ProviderType getProviderType() {
        throw new EmailProviderException('getProviderType() must be implemented by provider subclass');
    }

    /**
     * Validates provider-specific authentication
     * @return true if authenticated, false otherwise
     */
    public virtual Boolean isAuthenticated() {
        throw new EmailProviderException('isAuthenticated() must be implemented by provider subclass');
    }

    /**
     * Gets the authenticated user's email address from the provider
     * @return User's email address, or empty string if not authenticated
     */
    public virtual String getUserEmail() {
        throw new EmailProviderException('getUserEmail() must be implemented by provider subclass');
    }

    /**
     * Retrieves multiple emails by their provider-specific message IDs in a single batch request.
     * Default implementation falls back to sequential getSingleEmail calls.
     * Providers should override this to use their native batch API for better performance.
     *
     * @param messageIds List of provider message IDs to fetch
     * @return List of email data maps (in same order as input, null for failed fetches)
     */
    public virtual List<Map<String, Object>> getEmailsBatch(List<String> messageIds) {
        // Default fallback: sequential calls (override in providers that support batch API)
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (String messageId : messageIds) {
            try {
                results.add(getSingleEmail(messageId));
            } catch (Exception e) {
                results.add(null);
            }
        }
        return results;
    }
}