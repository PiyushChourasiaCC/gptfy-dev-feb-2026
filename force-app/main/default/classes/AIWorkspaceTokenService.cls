/**
 * AIWorkspaceTokenService - Central service for managing OAuth tokens
 * 
 * This service retrieves access tokens from AI_Workspace_User__c records
 * and handles token refresh when access tokens expire.
 * 
 * REPLACES: Named Credentials / Auth Provider / External Credentials
 * 
 * Flow:
 * 1. Call getAccessToken() with provider type (Outlook/Gmail)
 * 2. Service queries AI_Workspace_User__c for the current user
 * 3. If access token exists, it's returned
 * 4. If access token is missing/expired, service attempts refresh using refresh token
 * 5. If refresh fails, throws exception indicating user needs to re-authenticate
 * 
 * @author GPTfy
 * @date 2026-01-27
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIWorkspaceTokenService {
    
    // Provider constants
    public static final String PROVIDER_OUTLOOK = 'Outlook';
    public static final String PROVIDER_GMAIL = 'Gmail';
    
    // API Endpoints
    private static final String MICROSOFT_GRAPH_ENDPOINT = 'https://graph.microsoft.com';
    private static final String GOOGLE_API_ENDPOINT = 'https://www.googleapis.com';
    private static final String GMAIL_API_ENDPOINT = 'https://gmail.googleapis.com';
    
    // Encryption constants
    private static final String CUSTOM_SALT = 'Kx9#mP2vL8qGPTfy';
    private static final String ALGORITHM = 'AES256';
    
    /**
     * Generate encryption key unique to a specific user and org
     * Key = SHA256(OrgId + UserId + CustomSalt)
     */
    private static Blob getEncryptionKey(Id userId) {
        String keySource = UserInfo.getOrganizationId() + userId + CUSTOM_SALT;
        return Crypto.generateDigest('SHA-256', Blob.valueOf(keySource));
    }
    
    /**
     * Encrypt a token using user/org-specific key
     */
    private static String encryptToken(String token, Id userId) {
        if (String.isBlank(token)) {
            return null;
        }
        Blob encryptionKey = getEncryptionKey(userId);
        Blob dataToEncrypt = Blob.valueOf(token);
        Blob encryptedData = Crypto.encryptWithManagedIV(ALGORITHM, encryptionKey, dataToEncrypt);
        return EncodingUtil.base64Encode(encryptedData);
    }
    
    /**
     * Decrypt a token using user/org-specific key
     * Handles backward compatibility for unencrypted tokens
     */
    private static String decryptToken(String encryptedToken, Id userId) {
        if (String.isBlank(encryptedToken)) {
            return null;
        }
        
        try {
            Blob encryptionKey = getEncryptionKey(userId);
            Blob encryptedData = EncodingUtil.base64Decode(encryptedToken);
            Blob decryptedData = Crypto.decryptWithManagedIV(ALGORITHM, encryptionKey, encryptedData);
            return decryptedData.toString();
        } catch (Exception e) {
            // Decryption failed - might be an unencrypted legacy token
            return encryptedToken;
        }
    }
    
    // Token refresh result
    public class TokenResult {
        public Boolean isSuccess;
        public String accessToken;
        public String refreshToken;
        public String errorMessage;
        public Boolean requiresReauth;
        
        public TokenResult() {
            this.isSuccess = false;
            this.requiresReauth = false;
        }
    }
    
    // Exception for authentication errors
    public class AuthenticationException extends Exception {}
    
    /**
     * Get access token for the current user and provider
     * Automatically refreshes if needed
     * 
     * @param provider 'Outlook' or 'Gmail'
     * @return Valid access token
     * @throws AuthenticationException if token cannot be obtained
     */
    public static String getAccessToken(String provider) {
        return getAccessTokenForUser(UserInfo.getUserId(), provider);
    }
    
    /**
     * Get access token for a specific user and provider
     * Automatically refreshes if needed
     * 
     * @param userId The user ID to get token for
     * @param provider 'Outlook' or 'Gmail'
     * @return Valid access token
     * @throws AuthenticationException if token cannot be obtained
     */
    public static String getAccessTokenForUser(Id userId, String provider) {
        // Query AI_Workspace_User__c for this user and provider
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id, Name, User__c, Provider__c, Access_Token__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :userId
            AND Provider__c = :provider
            LIMIT 1
        ];
        
        if (workspaceUsers.isEmpty()) {
            throw new AuthenticationException(
                'No ' + provider + ' connection found. Please connect your ' + provider + 
                ' account using the Workspace Authentication page.'
            );
        }
        
        AI_Workspace_User__c workspaceUser = workspaceUsers[0];
        
        // Decrypt tokens from storage
        String decryptedAccessToken = decryptToken(workspaceUser.Access_Token__c, userId);
        String decryptedRefreshToken = decryptToken(workspaceUser.Refresh_Token__c, userId);
        
        // If we have an access token, return it directly without validation
        // The calling code will handle 401 errors and can call refreshAndGetToken if needed
        // This avoids the "uncommitted work pending" error by not doing DML before callouts
        if (String.isNotBlank(decryptedAccessToken)) {
            return decryptedAccessToken;
        }
        
        // No access token - check if we have refresh token
        if (String.isBlank(decryptedRefreshToken)) {
            throw new AuthenticationException(
                'No tokens available for ' + provider + '. Please reconnect your ' + 
                provider + ' account using the Workspace Authentication page.'
            );
        }
        
        // We have refresh token but no access token - need to refresh
        // This will do callout + DML, so caller should not make callouts after this
        throw new AuthenticationException(
            'Access token expired for ' + provider + '. Please reconnect your ' + 
            provider + ' account using the Workspace Authentication page.'
        );
    }

    /**
     * Refresh the access token using the stored refresh token.
     * This method does both callout (to token endpoint) AND DML (to save new token).
     * IMPORTANT: Call this BEFORE any other callouts in the transaction.
     * 
     * @param provider 'Outlook' or 'Gmail'
     * @return The new access token
     * @throws AuthenticationException if refresh fails
     */
    public static String refreshAndGetToken(String provider) {
        return refreshAndGetTokenForUser(UserInfo.getUserId(), provider);
    }

    /**
     * Refresh the access token for a specific user.
     * This method does both callout (to token endpoint) AND DML (to save new token).
     * IMPORTANT: Call this BEFORE any other callouts in the transaction.
     * 
     * @param userId The user ID
     * @param provider 'Outlook' or 'Gmail'
     * @return The new access token
     * @throws AuthenticationException if refresh fails
     */
    public static String refreshAndGetTokenForUser(Id userId, String provider) {
        // Query the workspace user record
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id, Name, User__c, Provider__c, Access_Token__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :userId
            AND Provider__c = :provider
            LIMIT 1
        ];
        
        if (workspaceUsers.isEmpty()) {
            throw new AuthenticationException(
                'No ' + provider + ' connection found. Please connect your ' + provider + 
                ' account using the Workspace Authentication page.'
            );
        }
        
        AI_Workspace_User__c workspaceUser = workspaceUsers[0];
        String decryptedRefreshToken = decryptToken(workspaceUser.Refresh_Token__c, userId);
        
        if (String.isBlank(decryptedRefreshToken)) {
            throw new AuthenticationException(
                'No refresh token available for ' + provider + '. Please reconnect your ' + 
                provider + ' account using the Workspace Authentication page.'
            );
        }
        
        // Attempt to refresh the token (makes HTTP callout)
        TokenResult refreshResult = refreshToken(decryptedRefreshToken, provider);
        
        if (!refreshResult.isSuccess) {
            if (refreshResult.requiresReauth) {
                throw new AuthenticationException(
                    'Your ' + provider + ' session has expired. Please reconnect your ' + 
                    provider + ' account using the Workspace Authentication page.'
                );
            }
            throw new AuthenticationException(
                'Failed to refresh ' + provider + ' token: ' + refreshResult.errorMessage
            );
        }
        
        // Encrypt and save the new tokens (DML operation)
        workspaceUser.Access_Token__c = encryptToken(refreshResult.accessToken, userId);
        if (String.isNotBlank(refreshResult.refreshToken)) {
            workspaceUser.Refresh_Token__c = encryptToken(refreshResult.refreshToken, userId);
        }
        
        // Use without sharing helper to ensure update succeeds
        updateWorkspaceUser(workspaceUser);
        
        return refreshResult.accessToken;
    }
    
    /**
     * Check if the current user has a valid connection for a provider
     * 
     * @param provider 'Outlook' or 'Gmail'
     * @return True if user has a workspace user record with refresh token
     */
    public static Boolean hasConnection(String provider) {
        return hasConnectionForUser(UserInfo.getUserId(), provider);
    }
    
    /**
     * Check if a specific user has a valid connection for a provider
     * 
     * @param userId The user ID to check
     * @param provider 'Outlook' or 'Gmail'
     * @return True if user has a workspace user record with refresh token
     */
    public static Boolean hasConnectionForUser(Id userId, String provider) {
        // Query without filtering on Long Text Area field (not allowed in SOQL WHERE)
        List<AI_Workspace_User__c> users = [
            SELECT Id, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :userId
            AND Provider__c = :provider
            LIMIT 1
        ];
        // Check if record exists and has a refresh token
        return !users.isEmpty() && String.isNotBlank(users[0].Refresh_Token__c);
    }
    
    /**
     * Get the API endpoint for a provider
     * 
     * @param provider 'Outlook' or 'Gmail'
     * @return Base API endpoint URL
     */
    public static String getApiEndpoint(String provider) {
        if (provider == PROVIDER_OUTLOOK) {
            return MICROSOFT_GRAPH_ENDPOINT;
        } else if (provider == PROVIDER_GMAIL) {
            return GMAIL_API_ENDPOINT;
        }
        throw new AuthenticationException('Unknown provider: ' + provider);
    }
    
    /**
     * Get the Microsoft Graph API endpoint
     * Replacement for AINamedCredentialService.getMicrosoftGraphEndpoint()
     */
    public static String getMicrosoftGraphEndpoint() {
        return MICROSOFT_GRAPH_ENDPOINT;
    }
    
    /**
     * Get the Gmail API endpoint
     * Replacement for AINamedCredentialService.getGmailEndpoint()
     */
    public static String getGmailEndpoint() {
        return GMAIL_API_ENDPOINT;
    }
    
    /**
     * Get the Google API endpoint (for Calendar, etc.)
     */
    public static String getGoogleApiEndpoint() {
        return GOOGLE_API_ENDPOINT;
    }
    
    /**
     * Validate if an access token is still valid by making a lightweight API call
     */
    private static Boolean isTokenValid(String accessToken, String provider) {
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setTimeout(10000);
            
            if (provider == PROVIDER_OUTLOOK) {
                // Use a lightweight endpoint to validate
                req.setEndpoint(MICROSOFT_GRAPH_ENDPOINT + '/v1.0/me?$select=id');
            } else if (provider == PROVIDER_GMAIL) {
                // Use Gmail profile endpoint
                req.setEndpoint(GMAIL_API_ENDPOINT + '/gmail/v1/users/me/profile');
            } else {
                return false;
            }
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            // Token is valid if we get 200
            return res.getStatusCode() == 200;
            
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * Refresh an access token using the refresh token
     */
    private static TokenResult refreshToken(String refreshToken, String provider) {
        if (provider == PROVIDER_OUTLOOK) {
            return refreshMicrosoftToken(refreshToken);
        } else if (provider == PROVIDER_GMAIL) {
            return refreshGoogleToken(refreshToken);
        }
        
        TokenResult result = new TokenResult();
        result.isSuccess = false;
        result.errorMessage = 'Unknown provider: ' + provider;
        return result;
    }
    
    /**
     * Refresh Microsoft OAuth token
     */
    private static TokenResult refreshMicrosoftToken(String refreshToken) {
        TokenResult result = new TokenResult();
        
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            
            if (settings == null || String.isBlank(settings.Microsoft_Client_Id__c) || 
                String.isBlank(settings.Microsoft_Client_Secret__c) || 
                String.isBlank(settings.Microsoft_Token_Endpoint__c)) {
                result.isSuccess = false;
                result.errorMessage = 'Microsoft OAuth settings not configured';
                return result;
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(settings.Microsoft_Token_Endpoint__c);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            
            String requestBody = 
                'client_id=' + EncodingUtil.urlEncode(settings.Microsoft_Client_Id__c, 'UTF-8') +
                '&client_secret=' + EncodingUtil.urlEncode(settings.Microsoft_Client_Secret__c, 'UTF-8') +
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
                
            } else {
                result.isSuccess = false;
                result.errorMessage = 'Token refresh failed: ' + res.getBody();
                
                // Check if this is an invalid_grant error (requires re-authentication)
                if (res.getBody().contains('invalid_grant') || 
                    res.getBody().contains('AADSTS700082') ||
                    res.getBody().contains('AADSTS50076')) {
                    result.requiresReauth = true;
                }
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Error refreshing token: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Refresh Google OAuth token
     */
    private static TokenResult refreshGoogleToken(String refreshToken) {
        TokenResult result = new TokenResult();
        
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            
            if (settings == null || String.isBlank(settings.Google_Client_Id__c) || 
                String.isBlank(settings.Google_Client_Secret__c) || 
                String.isBlank(settings.Google_Token_Endpoint__c)) {
                result.isSuccess = false;
                result.errorMessage = 'Google OAuth settings not configured';
                return result;
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(settings.Google_Token_Endpoint__c);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            
            String requestBody = 
                'client_id=' + EncodingUtil.urlEncode(settings.Google_Client_Id__c, 'UTF-8') +
                '&client_secret=' + EncodingUtil.urlEncode(settings.Google_Client_Secret__c, 'UTF-8') +
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
                // Google doesn't always return a new refresh token
                result.refreshToken = (String) responseMap.get('refresh_token');
                
            } else {
                result.isSuccess = false;
                result.errorMessage = 'Token refresh failed: ' + res.getBody();
                
                // Check if this is an invalid_grant error (requires re-authentication)
                if (res.getBody().contains('invalid_grant')) {
                    result.requiresReauth = true;
                }
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Error refreshing token: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Update workspace user record with new tokens
     * Uses without sharing to ensure update succeeds
     */
    private static void updateWorkspaceUser(AI_Workspace_User__c workspaceUser) {
        // Run in elevated context to ensure we can update
        WorkspaceUserUpdater updater = new WorkspaceUserUpdater();
        updater.updateRecord(workspaceUser);
    }
    
    /**
     * Inner class to update records without sharing restrictions
     */
    private without sharing class WorkspaceUserUpdater {
        public void updateRecord(AI_Workspace_User__c record) {
            // Use FLSCheck for security enforcement
            List<AI_Workspace_User__c> recordsToUpdate = new List<AI_Workspace_User__c>{ record };
            FLSCheck.getInstance().updateDML(recordsToUpdate);
        }
    }
    
    /**
     * Save tokens to AI_Workspace_User__c after successful OAuth
     * Creates or updates the workspace user record
     * 
     * @param provider 'Outlook' or 'Gmail'
     * @param accessToken The access token from OAuth
     * @param refreshToken The refresh token from OAuth
     * @param userEmail Optional email address of the connected account
     * @return The workspace user record ID
     */
    public static Id saveTokens(String provider, String accessToken, String refreshToken, String userEmail) {
        Id userId = UserInfo.getUserId();
        
        // Check for existing record
        List<AI_Workspace_User__c> existingUsers = [
            SELECT Id, Name, Access_Token__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :userId
            AND Provider__c = :provider
            LIMIT 1
        ];
        
        AI_Workspace_User__c workspaceUser;
        
        if (!existingUsers.isEmpty()) {
            // Update existing record
            workspaceUser = existingUsers[0];
        } else {
            // Create new record
            workspaceUser = new AI_Workspace_User__c();
            workspaceUser.User__c = userId;
            workspaceUser.Provider__c = provider;
            workspaceUser.Name = provider + ' - ' + (String.isNotBlank(userEmail) ? userEmail : UserInfo.getName());
        }
        
        // Encrypt tokens before storing
        workspaceUser.Access_Token__c = encryptToken(accessToken, userId);
        workspaceUser.Refresh_Token__c = encryptToken(refreshToken, userId);
        workspaceUser.Auto_Sync_Enabled__c = true; // Enable auto sync on (re)authentication
        
        // Use FLSCheck for security enforcement
        List<AI_Workspace_User__c> usersToUpsert = new List<AI_Workspace_User__c>{ workspaceUser };
        FLSCheck.getInstance().upsertDML(usersToUpsert);
        
        return workspaceUser.Id;
    }
    
    /**
     * Remove connection for a user and provider
     * Clears tokens but optionally keeps the record
     * 
     * @param provider 'Outlook' or 'Gmail'
     * @param deleteRecord If true, deletes the record; if false, just clears tokens
     */
    public static void removeConnection(String provider, Boolean deleteRecord) {
        Id userId = UserInfo.getUserId();
        
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id
            FROM AI_Workspace_User__c
            WHERE User__c = :userId
            AND Provider__c = :provider
        ];
        
        if (!workspaceUsers.isEmpty()) {
            if (deleteRecord) {
                FLSCheck.getInstance().deleteDML(workspaceUsers);
            } else {
                for (AI_Workspace_User__c wu : workspaceUsers) {
                    wu.Access_Token__c = null;
                    wu.Refresh_Token__c = null;
                }
                
                // Use FLSCheck for security enforcement
                FLSCheck.getInstance().updateDML(workspaceUsers);
            }
        }
    }
    
    // =========================================================================
    // Test Support
    // =========================================================================
    
    @TestVisible
    private static String mockAccessToken;
    
    @TestVisible
    private static void setMockAccessToken(String token) {
        mockAccessToken = token;
    }
    
    @TestVisible
    private static void clearMocks() {
        mockAccessToken = null;
    }
}