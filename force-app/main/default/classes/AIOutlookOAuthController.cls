/**
 * @description Controller for OutlookOAuth Visualforce page
 * Handles OAuth flow, token exchange, and API testing
 * 
 * @author GPTfy
 * @date 2026-01-15
 */
public with sharing class AIOutlookOAuthController {
    
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
    public Boolean isLoading { get; set; }
    public Boolean isCallback { get; set; }
    public String errorMessage { get; set; }
    public String accessToken { get; set; }
    public String refreshToken { get; set; }
    public Integer expiresIn { get; set; }
    public String userEmail { get; set; }
    public String apiResponse { get; set; }
    public String authUrl { get; set; }
    public String redirectUrl { get; set; }
    
    // Store the auth code for processing via action function
    private String pendingAuthCode { get; set; }
    
    /**
     * @description Constructor - checks if OAuth callback occurred
     * NOTE: Cannot make HTTP callouts in constructor - use action functions instead
     */
    public AIOutlookOAuthController() {
        // Check if this is a callback from Microsoft (has 'code' parameter)
        String authCode = ApexPages.currentPage().getParameters().get('code');
        String error = ApexPages.currentPage().getParameters().get('error');
        String errorDescription = ApexPages.currentPage().getParameters().get('error_description');
        
        // Initialize default state
        showConnectButton = false;
        showInfo = false;
        isSuccess = false;
        hasError = false;
        isLoading = true;
        isCallback = false;
        
        // Set namespace-aware redirect URL
        redirectUrl = getWorkspaceAuthenticationUrl();
        
        if (String.isNotBlank(error)) {
            // OAuth error occurred - can handle in constructor (no callout needed)
            handleOAuthError(error, errorDescription);
            isLoading = false;
        } else if (String.isNotBlank(authCode)) {
            // Success - need to exchange code for tokens via action function (requires callout)
            pendingAuthCode = authCode;
            isCallback = true;
            // exchangeCodeForTokens will be called via action function from VF page
        } else {
            // Initial page load - need to get auth URL via action function (requires callout)
            showConnectButton = true;
            showInfo = true;
            // authUrl will be populated via action function from VF page
        }
    }
    
    /**
     * @description Action function to initialize the page after constructor
     * This is called via JavaScript on page load to perform callouts
     */
    public void initializePage() {
        try {
            if (isCallback && String.isNotBlank(pendingAuthCode)) {
                // Process the OAuth callback
                exchangeCodeForTokens(pendingAuthCode);
            } else if (showConnectButton) {
                // Get the authorization URL
                authUrl = AIOutlookOAuthBrowserService.getAuthorizationUrl(UserInfo.getUserId());
            }
        } catch (Exception e) {
            hasError = true;
            isSuccess = false;
            errorMessage = 'Initialization error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Error in initializePage: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        isLoading = false;
    }
    
    /**
     * @description Initiates OAuth flow by redirecting to Microsoft
     */
    public PageReference initiateOAuth() {
        try {
            String oauthUrl = AIOutlookOAuthBrowserService.getAuthorizationUrl(UserInfo.getUserId());
            PageReference pageRef = new PageReference(oauthUrl);
            pageRef.setRedirect(true);
            return pageRef;
        } catch (Exception e) {
            hasError = true;
            errorMessage = 'Error initiating OAuth: ' + e.getMessage();
            return null;
        }
    }
    
    /**
     * @description Exchanges authorization code for tokens
     */
    private void exchangeCodeForTokens(String authCode) {
        try {
            AIOutlookOAuthBrowserService.TokenResult result = 
                AIOutlookOAuthBrowserService.exchangeCodeForTokens(authCode);
            
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
            System.debug(LoggingLevel.ERROR, 'Exception in exchangeCodeForTokens: ' + e.getMessage());
        }
    }
    
    /**
     * @description Handles OAuth errors from Microsoft callback
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
            errorMessage = 'Access denied. You must grant permission to connect your Outlook account.';
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
            System.debug(LoggingLevel.WARN, 'Refresh token is blank, cannot save');
            throw new AuraHandledException('Refresh token is blank, cannot save workspace user.');
        }
        
        Id currentUserId = UserInfo.getUserId();
        System.debug('Attempting to save tokens for user: ' + currentUserId);
        
        // Check CRUD permissions
        if (!Schema.sObjectType.AI_Workspace_User__c.isAccessible() ||
            !Schema.sObjectType.AI_Workspace_User__c.isCreateable() ||
            !Schema.sObjectType.AI_Workspace_User__c.isUpdateable()) {
            String errorMsg = 'User does not have access to AI_Workspace_User__c object';
            System.debug(LoggingLevel.ERROR, errorMsg);
            throw new AuraHandledException(errorMsg);
        }
        
        // Check if record already exists for Outlook provider
        List<AI_Workspace_User__c> existingUsers = [
            SELECT Id, User__c, Refresh_Token__c, Access_Token__c, Provider__c
            FROM AI_Workspace_User__c
            WHERE User__c = :currentUserId
            AND Provider__c = 'Outlook'
            LIMIT 1
        ];
        
        System.debug('Found ' + existingUsers.size() + ' existing workspace user records');
        
        AI_Workspace_User__c workspaceUser;
        
        // Encrypt tokens using user/org-specific key before storing
        String encryptedRefreshToken = encryptRefreshToken(refreshToken);
        String encryptedAccessToken = String.isNotBlank(accessToken) ? encryptRefreshToken(accessToken) : null;
        
        System.debug('Refresh token length: ' + refreshToken.length());
        System.debug('Access token length: ' + (String.isNotBlank(accessToken) ? String.valueOf(accessToken.length()) : 'NULL'));
        System.debug('Encrypted refresh token length: ' + encryptedRefreshToken.length());
        
        if (!existingUsers.isEmpty()) {
            // Update existing record
            workspaceUser = existingUsers[0];
            workspaceUser.Refresh_Token__c = encryptedRefreshToken;
            workspaceUser.Access_Token__c = encryptedAccessToken;
            workspaceUser.Provider__c = 'Outlook';
            workspaceUser.Auto_Sync_Enabled__c = true; // Enable auto sync on (re)authentication
            System.debug('About to update workspace user record: ' + workspaceUser.Id);
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_User__c> usersToUpdate = new List<AI_Workspace_User__c>{ workspaceUser };
            FLSCheck.getInstance().updateDML(usersToUpdate);
            System.debug('Successfully updated AI_Workspace_User__c record: ' + workspaceUser.Id);
        } else {
            // Create new record
            workspaceUser = new AI_Workspace_User__c(
                Name = UserInfo.getName() + ' - Outlook',
                User__c = currentUserId,
                Provider__c = 'Outlook',
                Refresh_Token__c = encryptedRefreshToken,
                Access_Token__c = encryptedAccessToken,
                Auto_Sync_Enabled__c = true // Enable auto sync by default
            );
            System.debug('About to insert new workspace user record');
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_User__c> usersToInsert = new List<AI_Workspace_User__c>{ workspaceUser };
            FLSCheck.getInstance().insertDML(usersToInsert);
            System.debug('Successfully created new AI_Workspace_User__c record: ' + workspaceUser.Id);
        }
    }
    
    /**
     * @description Gets user profile from Microsoft Graph
     */
    private void getUserProfile() {
        if (String.isNotBlank(accessToken)) {
            AIOutlookOAuthBrowserService.GraphResult result = 
                AIOutlookOAuthBrowserService.getUserProfile(accessToken);
            
            if (result.isSuccess) {
                // Parse email from response
                Map<String, Object> profileData = 
                    (Map<String, Object>) JSON.deserializeUntyped(result.responseBody);
                userEmail = (String) profileData.get('mail');
                if (String.isBlank(userEmail)) {
                    userEmail = (String) profileData.get('userPrincipalName');
                }
            }
        }
    }
    
    /**
     * @description Test method - Gets user profile
     */
    public void testGetProfile() {
        if (String.isNotBlank(accessToken)) {
            AIOutlookOAuthBrowserService.GraphResult result = 
                AIOutlookOAuthBrowserService.getUserProfile(accessToken);
            
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
            AIOutlookOAuthBrowserService.GraphResult result = 
                AIOutlookOAuthBrowserService.getUserEmails(accessToken, 5);
            
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
            AIOutlookOAuthBrowserService.TokenResult result = 
                AIOutlookOAuthBrowserService.refreshAccessToken(refreshToken);
            
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
        PageReference pageRef = new PageReference('/apex/OutlookOAuth');
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
     * @description Encrypts a refresh token using AES256 encryption for the current user
     * Key is unique per user/org: SHA256(OrgId + UserId + CustomSalt)
     * @param refreshToken The plain text refresh token to encrypt
     * @return String The encrypted and Base64-encoded refresh token
     */
    public static String encryptRefreshToken(String refreshToken) {
        return encryptRefreshToken(refreshToken, UserInfo.getUserId());
    }
    
    /**
     * @description Encrypts a refresh token using AES256 encryption for a specific user
     * Used for token migration/re-encryption
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
        System.debug('Encrypting refresh token. Token length: ' + refreshToken.length());
        System.debug('Using encryption algorithm: ' + ALGORITHM);
        System.debug('Encryption key length: ' + encryptionKey.size());
        
        // Convert the refresh token to a Blob
        Blob dataToEncrypt = Blob.valueOf(refreshToken);
        System.debug('Data to encrypt blob size: ' + dataToEncrypt.size());
        
        // Encrypt the data using AES256 with managed IV
        Blob encryptedData = Crypto.encryptWithManagedIV(ALGORITHM, encryptionKey, dataToEncrypt);
        System.debug('Encrypted data blob size: ' + encryptedData.size());
        
        // Convert to Base64 for storage
        String encryptedString = EncodingUtil.base64Encode(encryptedData);
        System.debug('Base64 encoded string length: ' + encryptedString.length());
        
        System.debug('Refresh token encrypted successfully');
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
        
        try {
            // Check if token looks like it's Base64 encoded (encrypted)
            // Base64 only contains: A-Z, a-z, 0-9, +, /, =
            // Refresh tokens from Microsoft typically start with "0." or "1." and contain many special chars
            if (isBase64Encoded(encryptedToken)) {
                // Try to decrypt using the specified user's key
                Blob encryptionKey = getEncryptionKey(userId);
                Blob encryptedData = EncodingUtil.base64Decode(encryptedToken);
                Blob decryptedData = Crypto.decryptWithManagedIV(ALGORITHM, encryptionKey, encryptedData);
                String decryptedToken = decryptedData.toString();
                System.debug('Refresh token decrypted successfully for user: ' + userId);
                return decryptedToken;
            } else {
                // Token is not Base64 encoded, likely an old unencrypted token
                System.debug(LoggingLevel.WARN, 'Token appears to be unencrypted (legacy token). Returning as-is.');
                return encryptedToken;
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error decrypting refresh token for user ' + userId + ': ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Decryption stack trace: ' + e.getStackTraceString());
            // If decryption fails, might be an old unencrypted token
            System.debug(LoggingLevel.WARN, 'Decryption failed, returning token as-is for backward compatibility');
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
        
        // Base64 pattern: contains only A-Z, a-z, 0-9, +, /, = and length is multiple of 4
        // Microsoft refresh tokens start with version number like "0." or "1."
        // If it starts with a digit followed by a dot, it's likely unencrypted
        if (value.startsWith('0.') || value.startsWith('1.')) {
            return false;
        }
        
        // Check if it matches Base64 character set
        String base64Pattern = '^[A-Za-z0-9+/]*={0,2}$';
        return Pattern.matches(base64Pattern, value);
    }
    
    /**
     * @description Gets the namespace-aware Workspace Authentication tab URL
     * @return String The URL to the Workspace Authentication tab with namespace if applicable
     */
    private static String getWorkspaceAuthenticationUrl() {
        String namespace = AIConstants.NAMESPACE;
        if (String.isNotBlank(namespace)) {
            return '/lightning/n/' + namespace + 'Workspace_Authentication';
        }
        return '/lightning/n/Workspace_Authentication';
    }
}