/**
 * @description Controller for GmailOAuth Visualforce page
 * Handles OAuth flow, token exchange, and API testing for Gmail
 * 
 * @author GPTfy
 * @date 2026-01-16
 */
public with sharing class AIGmailOAuthController {
    
    // Encryption constants
    private static final String CUSTOM_SALT = 'Kx9#mP2vL8qGPTfy';
    private static final String ALGORITHM = 'AES256';
    
    /**
     * Generate encryption key unique to the current user and org
     * Key = SHA256(OrgId + UserId + CustomSalt)
     */
    private static Blob getEncryptionKey() {
        return getEncryptionKey(UserInfo.getUserId());
    }
    
    /**
     * Generate encryption key for a specific user
     * Used by scheduler to decrypt tokens for other users
     * Key = SHA256(OrgId + UserId + CustomSalt)
     */
    private static Blob getEncryptionKey(Id userId) {
        String keySource = UserInfo.getOrganizationId() + String.valueOf(userId) + CUSTOM_SALT;
        return Crypto.generateDigest('SHA-256', Blob.valueOf(keySource));
    }
    
    // Public properties for VF page binding
    public Boolean showConnectButton { get; set; }
    public Boolean isSuccess { get; set; }
    public Boolean hasError { get; set; }
    public Boolean showInfo { get; set; }
    public String errorMessage { get; set; }
    public String accessToken { get; set; }
    public String refreshToken { get; set; }
    public Integer expiresIn { get; set; }
    public String userEmail { get; set; }
    public String apiResponse { get; set; }
    public String authUrl { get; set; }
    public String redirectUrl { get; set; }
    
    /**
     * @description Constructor - checks if OAuth callback occurred
     */
    public AIGmailOAuthController() {
        // Set namespace-aware redirect URL
        redirectUrl = getWorkspaceAuthenticationUrl();
        
        // Check if this is a callback from Google (has 'code' parameter)
        String authCode = ApexPages.currentPage().getParameters().get('code');
        String error = ApexPages.currentPage().getParameters().get('error');
        String errorDescription = ApexPages.currentPage().getParameters().get('error_description');
        
        if (String.isNotBlank(error)) {
            // OAuth error occurred
            handleOAuthError(error, errorDescription);
        } else if (String.isNotBlank(authCode)) {
            // Success - exchange code for tokens
            exchangeCodeForTokens(authCode);
        } else {
            // Initial page load - show connect button and prepare auth URL
            showConnectButton = true;
            showInfo = true;
            isSuccess = false;
            hasError = false;
            authUrl = AIGmailOAuthBrowserService.getAuthorizationUrl(UserInfo.getUserId());
        }
    }
    
    /**
     * @description Initiates OAuth flow by redirecting to Google
     */
    public PageReference initiateOAuth() {
        String authUrl = AIGmailOAuthBrowserService.getAuthorizationUrl(UserInfo.getUserId());
        PageReference pageRef = new PageReference(authUrl);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    /**
     * @description Exchanges authorization code for tokens
     */
    private void exchangeCodeForTokens(String authCode) {
        try {
            AIGmailOAuthBrowserService.TokenResult result = 
                AIGmailOAuthBrowserService.exchangeCodeForTokens(authCode);
            
            if (result.isSuccess) {
                // Store tokens in controller properties
                accessToken = result.accessToken;
                refreshToken = result.refreshToken;
                expiresIn = result.expiresIn;
                
                // Get user profile
                getUserProfile();
                
                // Note: Refresh token will be saved via VF page action to avoid DML-in-constructor error
                
                // Set display flags
                isSuccess = true;
                hasError = false;
                showConnectButton = false;
                showInfo = false;
                
            } else {
                // Token exchange failed
                hasError = true;
                isSuccess = false;
                showConnectButton = false;
                showInfo = false;
                errorMessage = result.errorMessage;
            }
            
        } catch (Exception e) {
            hasError = true;
            isSuccess = false;
            showConnectButton = false;
            showInfo = false;
            errorMessage = 'Unexpected error: ' + e.getMessage();
        }
    }
    
    /**
     * @description Handles OAuth errors from Google callback
     */
    private void handleOAuthError(String error, String errorDescription) {
        hasError = true;
        isSuccess = false;
        showConnectButton = true;
        showInfo = false;
        
        if (String.isNotBlank(errorDescription)) {
            errorMessage = errorDescription;
        } else {
            errorMessage = 'OAuth error: ' + error;
        }
        
        // Common error translations
        if (error == 'access_denied') {
            errorMessage = 'Access denied. You must grant permission to connect your Gmail account.';
        } else if (error == 'invalid_request') {
            errorMessage = 'Invalid request. Please try again.';
        } else if (error == 'unauthorized_client') {
            errorMessage = 'Application not authorized. Please contact your administrator.';
        }
    }
    
    /**
     * @description Public action method to save refresh token
     * Called from VF page after successful authentication
     * This avoids "DML currently not allowed" error in constructor
     * Throws exceptions to surface any errors to the user
     */
    public void saveRefreshTokenToWorkspaceUser() {
        if (String.isBlank(refreshToken)) {
            throw new AuraHandledException('Refresh token is blank, cannot save workspace user.');
        }
        
        Id currentUserId = UserInfo.getUserId();
        
        // Check CRUD permissions
        if (!Schema.sObjectType.AI_Workspace_User__c.isAccessible() ||
            !Schema.sObjectType.AI_Workspace_User__c.isCreateable() ||
            !Schema.sObjectType.AI_Workspace_User__c.isUpdateable()) {
            String errorMsg = 'User does not have access to AI_Workspace_User__c object';
            throw new AuraHandledException(errorMsg);
        }
        
        // Check if record already exists for Gmail provider
        List<AI_Workspace_User__c> existingUsers = [
            SELECT Id, User__c, Refresh_Token__c, Access_Token__c, Provider__c
            FROM AI_Workspace_User__c
            WHERE User__c = :currentUserId
            AND Provider__c = 'Gmail'
            LIMIT 1
        ];
        
        AI_Workspace_User__c workspaceUser;
        
        // Encrypt tokens using user/org-specific key before storing
        String encryptedRefreshToken = encryptRefreshToken(refreshToken);
        String encryptedAccessToken = String.isNotBlank(accessToken) ? encryptRefreshToken(accessToken) : null;
        
        if (!existingUsers.isEmpty()) {
            // Update existing record
            workspaceUser = existingUsers[0];
            workspaceUser.Refresh_Token__c = encryptedRefreshToken;
            workspaceUser.Access_Token__c = encryptedAccessToken;
            workspaceUser.Provider__c = 'Gmail';
            workspaceUser.Auto_Sync_Enabled__c = true; // Enable auto sync on (re)authentication
            // V2-7889: Store the service user email for matching staging records
            workspaceUser.Service_User_Email__c = userEmail;
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_User__c> usersToUpdate = new List<AI_Workspace_User__c>{ workspaceUser };
            FLSCheck.getInstance().updateDML(usersToUpdate);
        } else {
            // Create new record
            workspaceUser = new AI_Workspace_User__c(
                Name = UserInfo.getName() + ' - Gmail',
                User__c = currentUserId,
                Provider__c = 'Gmail',
                Refresh_Token__c = encryptedRefreshToken,
                Access_Token__c = encryptedAccessToken,
                Auto_Sync_Enabled__c = true, // Enable auto sync by default
                Service_User_Email__c = userEmail // V2-7889: Store service user email
            );
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_User__c> usersToInsert = new List<AI_Workspace_User__c>{ workspaceUser };
            FLSCheck.getInstance().insertDML(usersToInsert);
        }
    }
    
    /**
     * @description Gets user profile from Google
     */
    private void getUserProfile() {
        if (String.isNotBlank(accessToken)) {
            AIGmailOAuthBrowserService.ApiResult result = 
                AIGmailOAuthBrowserService.getUserProfile(accessToken);
            
            if (result.isSuccess) {
                // Parse email from response
                Map<String, Object> profileData = 
                    (Map<String, Object>) JSON.deserializeUntyped(result.responseBody);
                userEmail = (String) profileData.get('email');
            }
        }
    }
    
    /**
     * @description Test method - Gets user profile
     */
    public void testGetProfile() {
        if (String.isNotBlank(accessToken)) {
            AIGmailOAuthBrowserService.ApiResult result = 
                AIGmailOAuthBrowserService.getUserProfile(accessToken);
            
            if (result.isSuccess) {
                // Pretty print JSON
                apiResponse = prettyPrintJson(result.responseBody);
            } else {
                apiResponse = 'Error: ' + result.errorMessage + '\nStatus: ' + result.statusCode;
            }
        }
    }
    
    /**
     * @description Test method - Gets user emails
     */
    public void testGetEmails() {
        if (String.isNotBlank(accessToken)) {
            AIGmailOAuthBrowserService.ApiResult result = 
                AIGmailOAuthBrowserService.getUserEmails(accessToken, 5);
            
            if (result.isSuccess) {
                // Pretty print JSON
                apiResponse = prettyPrintJson(result.responseBody);
            } else {
                apiResponse = 'Error: ' + result.errorMessage + '\nStatus: ' + result.statusCode;
            }
        }
    }
    
    /**
     * @description Test method - Refreshes access token
     */
    public void testRefreshToken() {
        if (String.isNotBlank(refreshToken)) {
            AIGmailOAuthBrowserService.TokenResult result = 
                AIGmailOAuthBrowserService.refreshAccessToken(refreshToken);
            
            if (result.isSuccess) {
                // Update tokens
                accessToken = result.accessToken;
                Boolean hasNewRefreshToken = false;
                if (String.isNotBlank(result.refreshToken)) {
                    refreshToken = result.refreshToken;
                    // Save updated refresh token
                    saveRefreshTokenToWorkspaceUser();
                    hasNewRefreshToken = true;
                }
                expiresIn = result.expiresIn;
                
                apiResponse = '✓ Token refreshed successfully!\n\n' +
                             'New Access Token: ' + accessToken.substring(0, 50) + '...\n' +
                             'Expires In: ' + expiresIn + ' seconds' +
                             (hasNewRefreshToken ? '\n\n✓ Updated refresh token stored in AI_Workspace_User__c' : '');
            } else {
                apiResponse = 'Error refreshing token: ' + result.errorMessage;
            }
        }
    }
    
    /**
     * @description Resets the page to initial state
     */
    public PageReference reset() {
        // Clear all properties
        showConnectButton = true;
        showInfo = true;
        isSuccess = false;
        hasError = false;
        errorMessage = null;
        accessToken = null;
        refreshToken = null;
        expiresIn = null;
        userEmail = null;
        apiResponse = null;
        
        // Redirect to clean URL
        PageReference pageRef = Page.GmailOAuth;
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    /**
     * @description Pretty prints JSON for display
     */
    private String prettyPrintJson(String jsonString) {
        try {
            Object parsed = JSON.deserializeUntyped(jsonString);
            return JSON.serializePretty(parsed);
        } catch (Exception e) {
            return jsonString;
        }
    }
    
    /**
     * @description Encrypts a refresh token using AES256 encryption
     * Key is unique per user/org: SHA256(OrgId + UserId + CustomSalt)
     * @param refreshToken The plain text refresh token to encrypt
     * @return String The encrypted and Base64-encoded refresh token
     */
    public static String encryptRefreshToken(String refreshToken) {
        return encryptRefreshToken(refreshToken, UserInfo.getUserId());
    }
    
    /**
     * @description Encrypts a refresh token using AES256 encryption for a specific user
     * Used by scheduler to encrypt tokens for other users
     * Key is unique per user/org: SHA256(OrgId + UserId + CustomSalt)
     * @param refreshToken The plain text refresh token to encrypt
     * @param userId The user ID to use for generating the encryption key
     * @return String The encrypted and Base64-encoded refresh token
     */
    public static String encryptRefreshToken(String refreshToken, Id userId) {
        if (String.isBlank(refreshToken)) {
            throw new AuraHandledException('Cannot encrypt blank refresh token');
        }
        
        Blob encryptionKey = getEncryptionKey(userId);
        
        // Convert the refresh token to a Blob
        Blob dataToEncrypt = Blob.valueOf(refreshToken);
        
        // Encrypt the data using AES256 with managed IV
        Blob encryptedData = Crypto.encryptWithManagedIV(ALGORITHM, encryptionKey, dataToEncrypt);
        
        // Convert to Base64 for storage
        String encryptedString = EncodingUtil.base64Encode(encryptedData);
        
        return encryptedString;
    }
    
    /**
     * @description Decrypts an encrypted refresh token for the current user
     * Handles backward compatibility for unencrypted tokens
     * Key is unique per user/org: SHA256(OrgId + UserId + CustomSalt)
     * @param encryptedToken The encrypted and Base64-encoded refresh token (or unencrypted legacy token)
     * @return String The decrypted plain text refresh token
     */
    public static String decryptRefreshToken(String encryptedToken) {
        return decryptRefreshToken(encryptedToken, UserInfo.getUserId());
    }
    
    /**
     * @description Decrypts an encrypted refresh token for a specific user
     * Used by scheduler to decrypt tokens for other users
     * Key is unique per user/org: SHA256(OrgId + UserId + CustomSalt)
     * @param encryptedToken The encrypted and Base64-encoded refresh token (or unencrypted legacy token)
     * @param userId The Salesforce User ID whose key was used to encrypt the token
     * @return String The decrypted plain text refresh token
     */
    public static String decryptRefreshToken(String encryptedToken, Id userId) {
        if (String.isBlank(encryptedToken)) {
            return null;
        }
        
        // Always try to decrypt first (since all new tokens are encrypted)
        try {
            Blob encryptionKey = getEncryptionKey(userId);
            Blob encryptedData = EncodingUtil.base64Decode(encryptedToken);
            Blob decryptedData = Crypto.decryptWithManagedIV(ALGORITHM, encryptionKey, encryptedData);
            String decryptedToken = decryptedData.toString();
            return decryptedToken;
        } catch (Exception e) {
            // Decryption failed - might be an unencrypted legacy token
            
            // If it looks like a Gmail refresh token (starts with "1/"), return as-is
            if (encryptedToken.startsWith('1/')) {
                return encryptedToken;
            }
            
            // Otherwise, log error and return the token (might work, might not)
            return encryptedToken;
        }
    }
    
    /**
     * @description Checks if a string appears to be Base64 encoded
     * @param value The string to check
     * @return Boolean True if the string appears to be Base64 encoded
     */
    private static Boolean isBase64Encoded(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        
        // Gmail refresh tokens typically start with "1/" followed by more characters
        // Check for this specific pattern first
        if (value.startsWith('1/') && value.length() > 20) {
            return false;
        }
        
        // Check if it matches Base64 character set (A-Z, a-z, 0-9, +, /, =)
        // Valid Base64 must match this pattern and have proper length
        String base64Pattern = '^[A-Za-z0-9+/]*={0,2}$';
        if (!Pattern.matches(base64Pattern, value)) {
            return false;
        }
        
        // Additional check: encrypted tokens should be significantly long (our AES256 encryption produces at least 44 chars)
        // Gmail refresh tokens are usually much longer (>100 chars) but don't look like pure Base64
        return value.length() >= 40;
    }
    
    /**
     * @description Gets the namespace-aware Workspace Authentication tab URL
     * @return String The URL to the Workspace Authentication tab with namespace if applicable
     */
    private static String getWorkspaceAuthenticationUrl() {
        String namespace = AIConstants.NAMESPACE;
        if (String.isNotBlank(namespace)) {
            return '/lightning/n/' + namespace + 'AI_Workspace_Sync';
        }
        return '/lightning/n/AI_Workspace_Sync';
    }
}