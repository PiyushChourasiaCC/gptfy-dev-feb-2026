/**
 * @description Service class for Gmail OAuth using Authorization Code Flow
 * This flow works with MFA-enabled accounts and uses browser-based authentication
 * 
 * SECURITY: Uses Custom Setting (AI_Workspace_Sync_Settings__c) for credential storage.
 * Custom Settings provide:
 * - Hierarchy-based access (org, profile, user level)
 * - Protected visibility (only accessible via Apex)
 * - No SOQL needed for access
 * - Cacheable for performance
 * 
 * Flow:
 * 1. User clicks "Connect Gmail" button in LWC/VF
 * 2. Browser redirects to Google login page
 * 3. User authenticates (with MFA if enabled)
 * 4. Google redirects back to Salesforce callback
 * 5. Apex exchanges authorization code for tokens
 * 6. Refresh token stored for future use
 * 
 * SETUP REQUIRED:
 * 1. Go to Setup > Custom Settings > AI Workspace OAuth > Manage
 * 2. Click "New" to create org-level defaults
 * 3. Fill in ALL Google fields:
 *    - Google Client Id: Your Google Cloud Console Client ID
 *    - Google Client Secret: Your Google Cloud Console Client Secret
 *    - Google Auth Endpoint: Authorization URL
 *    - Google Token Endpoint: Token URL
 *    - Google Scope: OAuth scopes for Gmail/Calendar/Tasks
 * 
 * Note: Uses 'without sharing' to ensure all users can access org-wide 
 * AI_Workspace_Sync_Settings__c custom settings for OAuth configuration.
 * 
 * @author GPTfy
 * @date 2026-01-16
 * @Jira V2-7695, V2-7696, V2-7796
 */
public without sharing class AIGmailOAuthBrowserService {
    
    // Gmail API base URL (fixed, well-known endpoint)
    private static final String GMAIL_API_ENDPOINT = 'https://gmail.googleapis.com';
    
    // Cache for settings (to avoid repeated getInstance calls)
    private static AI_Workspace_Sync_Settings__c cachedSettings;
    
    // Callback URL - This needs to be registered in Google Cloud Console
    // Format: https://YOUR_DOMAIN.my.salesforce.com/apex/GmailOAuth (or with namespace prefix)
    private static String REDIRECT_URI {
        get {
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            PageReference pageRef = Page.GmailOAuth;
            return baseUrl + pageRef.getUrl();
        }
    }
    
    /**
     * @description Gets the OAuth settings from Custom Setting
     * Uses hierarchy to allow org, profile, or user-level overrides
     * 
     * @return AI_Workspace_Sync_Settings__c The settings instance
     */
    @TestVisible
    private static AI_Workspace_Sync_Settings__c getSettings() {
        if (cachedSettings == null) {
            cachedSettings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        }
        return cachedSettings;
    }
    
    /**
     * @description Clears the settings cache (useful for testing)
     */
    @TestVisible
    private static void clearSettingsCache() {
        cachedSettings = null;
    }
    
    /**
     * @description Gets the Client ID from Custom Setting
     * @return String The Google Client ID
     */
    private static String getClientId() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings == null || String.isBlank(settings.Google_Client_Id__c)) {
            return null;
        }
        return settings.Google_Client_Id__c;
    }
    
    /**
     * @description Gets the Client Secret from Custom Setting
     * @return String The Google Client Secret
     */
    private static String getClientSecret() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings == null || String.isBlank(settings.Google_Client_Secret__c)) {
            return null;
        }
        return settings.Google_Client_Secret__c;
    }
    
    /**
     * @description Gets the OAuth scope from Custom Setting
     * @return String The OAuth scope, or null if not configured
     */
    private static String getScope() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings == null || String.isBlank(settings.Google_Scope__c)) {
            return null;
        }
        return settings.Google_Scope__c;
    }
    
    /**
     * @description Gets the Auth Endpoint from Custom Setting
     * @return String The authorization endpoint URL, or null if not configured
     */
    private static String getAuthEndpoint() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings == null || String.isBlank(settings.Google_Auth_Endpoint__c)) {
            return null;
        }
        return settings.Google_Auth_Endpoint__c;
    }
    
    /**
     * @description Gets the Token Endpoint from Custom Setting
     * @return String The token endpoint URL, or null if not configured
     */
    private static String getTokenEndpoint() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings == null || String.isBlank(settings.Google_Token_Endpoint__c)) {
            return null;
        }
        return settings.Google_Token_Endpoint__c;
    }
    
    /**
     * @description Gets the Gmail API Endpoint (hardcoded as it's a fixed Google URL)
     * @return String The Gmail API base URL
     */
    private static String getGmailApiEndpoint() {
        return GMAIL_API_ENDPOINT;
    }
    
    /**
     * @description Validates that all required Google OAuth settings are configured
     * @throws AuraHandledException if any required setting is missing
     */
    private static void validateSettings() {
        List<String> missingFields = new List<String>();
        
        if (String.isBlank(getClientId())) {
            missingFields.add('Google Client Id');
        }
        if (String.isBlank(getClientSecret())) {
            missingFields.add('Google Client Secret');
        }
        if (String.isBlank(getAuthEndpoint())) {
            missingFields.add('Google Auth Endpoint');
        }
        if (String.isBlank(getTokenEndpoint())) {
            missingFields.add('Google Token Endpoint');
        }
        if (String.isBlank(getScope())) {
            missingFields.add('Google Scope');
        }
        
        if (!missingFields.isEmpty()) {
            throw new AuraHandledException(
                'Missing Google OAuth configuration: ' + String.join(missingFields, ', ') + 
                '. Please go to Setup > Custom Settings > AI Workspace OAuth > Manage and configure all Google fields.'
            );
        }
    }
    
    /**
     * @description Generates the OAuth authorization URL for browser redirect
     * This URL should be used to redirect the user's browser to Google login
     * 
     * All configuration values are retrieved from Custom Setting AI_Workspace_Sync_Settings__c.
     * 
     * @param state Optional state parameter for CSRF protection (use user ID or random string)
     * @return String The complete authorization URL
     * 
     * @example
     * String authUrl = AIGmailOAuthBrowserService.getAuthorizationUrl(UserInfo.getUserId());
     * // Redirect browser to authUrl
     */
    @AuraEnabled
    public static String getAuthorizationUrl(String state) {
        // Validate all settings are configured
        validateSettings();
        
        if (String.isBlank(state)) {
            state = String.valueOf(Crypto.getRandomLong());
        }
        
        // Get credential values from Custom Setting
        String clientId = getClientId();
        String scope = getScope();
        String authEndpoint = getAuthEndpoint();
        
        String authUrl = authEndpoint +
            '?client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8') +
            '&response_type=code' +
            '&redirect_uri=' + EncodingUtil.urlEncode(REDIRECT_URI, 'UTF-8') +
            '&scope=' + EncodingUtil.urlEncode(scope, 'UTF-8') +
            '&state=' + EncodingUtil.urlEncode(state, 'UTF-8') +
            '&access_type=offline' +
            '&prompt=consent';
        
        return authUrl;
    }
    
    /**
     * @description Exchanges authorization code for access and refresh tokens
     * This is called from the VF callback page after Google redirects back
     * 
     * @param authorizationCode The code received from Google OAuth callback
     * @return TokenResult containing tokens and status
     */
    @AuraEnabled
    public static TokenResult exchangeCodeForTokens(String authorizationCode) {
        TokenResult result = new TokenResult();
        
        try {
            if (String.isBlank(authorizationCode)) {
                result.isSuccess = false;
                result.errorMessage = 'Authorization code is required.';
                return result;
            }
            
            // Validate all settings are configured
            validateSettings();
            
            String clientId = getClientId();
            String clientSecret = getClientSecret();
            String tokenEndpoint = getTokenEndpoint();
            
            // Prepare HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint(tokenEndpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            
            // Build request body
            String requestBody = 
                'client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8') +
                '&client_secret=' + EncodingUtil.urlEncode(clientSecret, 'UTF-8') +
                '&code=' + EncodingUtil.urlEncode(authorizationCode, 'UTF-8') +
                '&redirect_uri=' + EncodingUtil.urlEncode(REDIRECT_URI, 'UTF-8') +
                '&grant_type=authorization_code';
            
            req.setBody(requestBody);
            req.setTimeout(120000);
            
            // Make callout
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                result.isSuccess = true;
                result.accessToken = (String) responseMap.get('access_token');
                result.refreshToken = (String) responseMap.get('refresh_token');
                result.expiresIn = (Integer) responseMap.get('expires_in');
                result.tokenType = (String) responseMap.get('token_type');
                result.scope = (String) responseMap.get('scope');
                
                System.debug('Access Token received successfully');
                
            } else {
                result.isSuccess = false;
                result.errorMessage = parseErrorResponse(res);
                System.debug('Token exchange failed: ' + res.getBody());
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Error exchanging code for tokens: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Exception: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Refreshes access token using refresh token
     * 
     * @param refreshToken The refresh token obtained from initial authentication
     * @return TokenResult containing new access token
     */
    @AuraEnabled
    public static TokenResult refreshAccessToken(String refreshToken) {
        TokenResult result = new TokenResult();
        
        try {
            if (String.isBlank(refreshToken)) {
                result.isSuccess = false;
                result.errorMessage = 'Refresh token is required.';
                return result;
            }
            
            // Validate all settings are configured
            validateSettings();
            
            String clientId = getClientId();
            String clientSecret = getClientSecret();
            String tokenEndpoint = getTokenEndpoint();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(tokenEndpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            
            String requestBody = 
                'client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8') +
                '&client_secret=' + EncodingUtil.urlEncode(clientSecret, 'UTF-8') +
                '&refresh_token=' + EncodingUtil.urlEncode(refreshToken, 'UTF-8') +
                '&grant_type=refresh_token';
            
            req.setBody(requestBody);
            req.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                result.isSuccess = true;
                result.accessToken = (String) responseMap.get('access_token');
                result.refreshToken = (String) responseMap.get('refresh_token');
                result.expiresIn = (Integer) responseMap.get('expires_in');
                result.tokenType = (String) responseMap.get('token_type');
                
            } else {
                result.isSuccess = false;
                result.errorMessage = parseErrorResponse(res);
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Error refreshing token: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Exception: ' + e.getMessage());
        }
        
        return result;
    }
    
    /**
     * @description Gets user profile from Google using access token
     * 
     * @param accessToken Valid access token
     * @return ApiResult containing user profile data
     */
    @AuraEnabled
    public static ApiResult getUserProfile(String accessToken) {
        ApiResult result = new ApiResult();
        
        try {
            if (String.isBlank(accessToken)) {
                result.isSuccess = false;
                result.errorMessage = 'Access token is required.';
                return result;
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://www.googleapis.com/oauth2/v2/userinfo');
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(60000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            result.statusCode = res.getStatusCode();
            result.responseBody = res.getBody();
            result.isSuccess = (res.getStatusCode() == 200);
            
            if (!result.isSuccess) {
                result.errorMessage = 'API call failed with status: ' + res.getStatusCode();
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Error calling Google API: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * @description Gets user's Gmail messages
     * 
     * @param accessToken Valid access token
     * @param maxResults Maximum number of messages to retrieve
     * @return ApiResult containing messages
     */
    @AuraEnabled
    public static ApiResult getUserEmails(String accessToken, Integer maxResults) {
        ApiResult result = new ApiResult();
        
        try {
            if (String.isBlank(accessToken)) {
                result.isSuccess = false;
                result.errorMessage = 'Access token is required.';
                return result;
            }
            
            Integer top = maxResults != null ? maxResults : 10;
            String endpoint = getGmailApiEndpoint() + '/gmail/v1/users/me/messages?maxResults=' + top;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(60000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            result.statusCode = res.getStatusCode();
            result.responseBody = res.getBody();
            result.isSuccess = (res.getStatusCode() == 200);
            
            if (!result.isSuccess) {
                result.errorMessage = 'API call failed with status: ' + res.getStatusCode();
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Error calling Gmail API: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * @description Parses error response from Google OAuth
     */
    private static String parseErrorResponse(HttpResponse res) {
        String errorMessage = 'Request failed with status: ' + res.getStatusCode();
        
        try {
            Map<String, Object> errorMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String error = (String) errorMap.get('error');
            String errorDescription = (String) errorMap.get('error_description');
            
            if (String.isNotBlank(errorDescription)) {
                errorMessage = errorDescription;
            } else if (String.isNotBlank(error)) {
                errorMessage = error;
            }
            
            // Provide user-friendly messages for common errors
            if (error == 'invalid_grant') {
                errorMessage = 'The authorization code has expired or is invalid. Please try connecting again.';
            } else if (error == 'invalid_client') {
                errorMessage = 'Invalid OAuth client configuration. Please verify the AI Workspace OAuth settings.';
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not parse error: ' + e.getMessage());
        }
        
        return errorMessage;
    }
    
    /**
     * @description Saves tokens to AI_Workspace_User__c after successful OAuth
     * This creates or updates the workspace user record for the current user
     * 
     * @param accessToken The access token from OAuth
     * @param refreshToken The refresh token from OAuth
     * @param userEmail The user's email address (from profile)
     * @return SaveResult with success status
     */
    @AuraEnabled
    public static SaveResult saveTokensToWorkspaceUser(String accessToken, String refreshToken, String userEmail) {
        SaveResult result = new SaveResult();
        
        try {
            if (String.isBlank(refreshToken)) {
                result.isSuccess = false;
                result.errorMessage = 'Refresh token is required to save connection.';
                return result;
            }
            
            Id workspaceUserId = AIWorkspaceTokenService.saveTokens(
                AIWorkspaceTokenService.PROVIDER_GMAIL,
                accessToken,
                refreshToken,
                userEmail
            );
            
            result.isSuccess = true;
            result.workspaceUserId = workspaceUserId;
            result.message = 'Successfully connected Gmail account.';
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Failed to save connection: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'saveTokensToWorkspaceUser error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Wrapper class for save result
     */
    public class SaveResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public Id workspaceUserId { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public SaveResult() {
            this.isSuccess = false;
        }
    }
    
    /**
     * @description Wrapper class for token result
     */
    public class TokenResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String accessToken { get; set; }
        @AuraEnabled public String refreshToken { get; set; }
        @AuraEnabled public Integer expiresIn { get; set; }
        @AuraEnabled public String tokenType { get; set; }
        @AuraEnabled public String scope { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public TokenResult() {
            this.isSuccess = false;
        }
    }
    
    /**
     * @description Wrapper class for API result
     */
    public class ApiResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public Integer statusCode { get; set; }
        @AuraEnabled public String responseBody { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public ApiResult() {
            this.isSuccess = false;
        }
    }
}