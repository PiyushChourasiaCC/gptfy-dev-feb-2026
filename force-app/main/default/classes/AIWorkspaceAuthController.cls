/**
 * @description Controller for AI Workspace Authenticator LWC
 * Manages Microsoft Outlook and Gmail OAuth connection status and disconnection
 * 
 * @author GPTfy
 * @date 2026-01-16
 */
public with sharing class AIWorkspaceAuthController {
    
    /**
     * @description Checks if the current user has an active connection for a specific provider
     * @param provider The provider to check ('Outlook' or 'Gmail')
     * @return ConnectionStatus Wrapper containing connection status and user email
     */
    @AuraEnabled(cacheable=true)
    public static ConnectionStatus checkConnectionStatus(String provider) {
        ConnectionStatus status = new ConnectionStatus();
        
        try {
            Id currentUserId = UserInfo.getUserId();
            
            // Check if user has read access to AI_Workspace_User__c
            if (!Schema.sObjectType.AI_Workspace_User__c.isAccessible()) {
                status.isConnected = false;
                status.errorMessage = 'Insufficient permissions to access workspace user data.';
                return status;
            }
            
            // Query for existing workspace user record for this provider
            // Note: Cannot filter on encrypted field Refresh_Token__c
            List<AI_Workspace_User__c> workspaceUsers = [
                SELECT Id, Name, User__c, Refresh_Token__c, Provider__c
                FROM AI_Workspace_User__c
                WHERE User__c = :currentUserId
                AND Provider__c = :provider
                LIMIT 1
            ];
            
            if (!workspaceUsers.isEmpty() && String.isNotBlank(workspaceUsers[0].Refresh_Token__c)) {
                status.isConnected = true;
                status.workspaceUserId = workspaceUsers[0].Id;
                status.userName = workspaceUsers[0].Name;
                status.provider = workspaceUsers[0].Provider__c;
            } else {
                status.isConnected = false;
            }
            
        } catch (Exception e) {
            status.isConnected = false;
            status.errorMessage = 'Error checking connection status: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Exception in checkConnectionStatus: ' + e.getMessage());
        }
        
        return status;
    }
    
    /**
     * @description Returns the OAuth authorization URL (VF page) for a specific provider
     * @param provider The provider to get URL for ('Outlook' or 'Gmail')
     * @return String The URL to the OAuth VF page
     */
    @AuraEnabled
    public static String getAuthorizationUrl(String provider) {
        try {
            // Return the VF page URL for OAuth flow
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            
            if (provider == 'Gmail') {
                return baseUrl + '/apex/GmailOAuth';
            } else if (provider == 'Outlook') {
                return baseUrl + '/apex/OutlookOAuth';
            } else {
                throw new AuraHandledException('Invalid provider: ' + provider);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Exception in getAuthorizationUrl: ' + e.getMessage());
            throw new AuraHandledException('Error getting authorization URL: ' + e.getMessage());
        }
    }
    
    /**
     * @description Disconnects the current user's account for a specific provider by deleting the workspace user record
     * @param provider The provider to disconnect ('Outlook' or 'Gmail')
     * @return DisconnectResult Wrapper containing success status and message
     */
    @AuraEnabled
    public static DisconnectResult disconnectAccount(String provider) {
        DisconnectResult result = new DisconnectResult();
        
        try {
            Id currentUserId = UserInfo.getUserId();
            
            // Check CRUD permissions
            if (!Schema.sObjectType.AI_Workspace_User__c.isAccessible() ||
                !Schema.sObjectType.AI_Workspace_User__c.isDeletable()) {
                result.isSuccess = false;
                result.message = 'Insufficient permissions to disconnect account.';
                return result;
            }
            
            // Query for existing workspace user record for this provider
            List<AI_Workspace_User__c> workspaceUsers = [
                SELECT Id, Name, Provider__c
                FROM AI_Workspace_User__c
                WHERE User__c = :currentUserId
                AND Provider__c = :provider
                LIMIT 1
            ];
            
            if (!workspaceUsers.isEmpty()) {
                delete workspaceUsers[0];
                result.isSuccess = true;
                result.message = 'Successfully disconnected ' + provider + ' account.';
                System.debug('Disconnected workspace user: ' + workspaceUsers[0].Id);
            } else {
                result.isSuccess = false;
                result.message = 'No connected ' + provider + ' account found.';
            }
            
        } catch (DmlException e) {
            result.isSuccess = false;
            result.message = 'Error disconnecting account: ' + e.getDmlMessage(0);
            System.debug(LoggingLevel.ERROR, 'DML Exception in disconnectAccount: ' + e.getMessage());
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'Unexpected error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Exception in disconnectAccount: ' + e.getMessage());
        }
        
        return result;
    }
    
    /**
     * @description Fetches Outlook user profile to validate token and get user info
     * @return UserProfile Wrapper containing email and display name from Outlook
     */
    @AuraEnabled
    public static UserProfile getOutlookUserProfile() {
        UserProfile profile = new UserProfile();
        profile.provider = 'Outlook';
        
        try {
            // Get access token - this just returns the stored token without DML
            String accessToken = AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_OUTLOOK);
            
            // Try to get user profile with current token
            AIOutlookOAuthBrowserService.GraphResult graphResult = 
                AIOutlookOAuthBrowserService.getUserProfile(accessToken);
            
            // If 401, token is expired - need to refresh
            if (!graphResult.isSuccess && graphResult.errorMessage != null && 
                graphResult.errorMessage.contains('401')) {
                // Token expired - tell user to refresh
                profile.isSuccess = false;
                profile.errorMessage = 'Your session has expired. Please click Re-Connect Outlook to refresh your connection.';
                profile.isTokenExpired = true;
                return profile;
            }
            
            if (!graphResult.isSuccess) {
                profile.isSuccess = false;
                profile.errorMessage = 'Failed to fetch user profile: ' + graphResult.errorMessage;
                return profile;
            }
            
            // Parse the JSON response
            Map<String, Object> userProfile = (Map<String, Object>) JSON.deserializeUntyped(graphResult.responseBody);
            
            profile.isSuccess = true;
            profile.email = (String) userProfile.get('mail');
            if (String.isBlank(profile.email)) {
                profile.email = (String) userProfile.get('userPrincipalName');
            }
            profile.displayName = (String) userProfile.get('displayName');
            profile.givenName = (String) userProfile.get('givenName');
            profile.surname = (String) userProfile.get('surname');
            profile.jobTitle = (String) userProfile.get('jobTitle');
            
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            profile.isSuccess = false;
            // Set a user-friendly message - the LWC will auto-refresh the token
            profile.errorMessage = 'Refreshing your Outlook connection...';
            profile.isTokenExpired = true;
            System.debug(LoggingLevel.INFO, 'Token expired for Outlook, will auto-refresh: ' + e.getMessage());
        } catch (Exception e) {
            profile.isSuccess = false;
            profile.errorMessage = 'Error fetching Outlook profile: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Exception in getOutlookUserProfile: ' + e.getMessage());
        }
        
        return profile;
    }
    
    /**
     * @description Refreshes the Outlook token and returns the user profile
     * Call this when the token has expired (isTokenExpired = true)
     * @return UserProfile with refreshed token data
     */
    @AuraEnabled
    public static UserProfile refreshOutlookAndGetProfile() {
        UserProfile profile = new UserProfile();
        profile.provider = 'Outlook';
        
        try {
            // Step 1: Refresh the token (callout to token endpoint + DML to save)
            String accessToken = AIWorkspaceTokenService.refreshAndGetToken(AIWorkspaceTokenService.PROVIDER_OUTLOOK);
            
            // Step 2: Return success - the UI should call getOutlookUserProfile again
            profile.isSuccess = true;
            profile.errorMessage = 'Token refreshed successfully';
            
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            profile.isSuccess = false;
            profile.errorMessage = e.getMessage();
            profile.isTokenExpired = true;
        } catch (Exception e) {
            profile.isSuccess = false;
            profile.errorMessage = 'Error refreshing token: ' + e.getMessage();
        }
        
        return profile;
    }
    
    /**
     * @description Fetches Gmail user profile to validate token and get user info
     * @return UserProfile Wrapper containing email and display name from Gmail
     */
    @AuraEnabled
    public static UserProfile getGmailUserProfile() {
        UserProfile profile = new UserProfile();
        profile.provider = 'Gmail';
        
        try {
            // Get access token - this just returns the stored token without DML
            String accessToken = AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_GMAIL);
            
            // Try to get user profile with current token
            AIGmailOAuthBrowserService.ApiResult apiResult = 
                AIGmailOAuthBrowserService.getUserProfile(accessToken);
            
            // If 401, token is expired - need to refresh
            if (!apiResult.isSuccess && apiResult.errorMessage != null && 
                apiResult.errorMessage.contains('401')) {
                // Token expired - tell user to refresh
                profile.isSuccess = false;
                profile.errorMessage = 'Your session has expired. Please click Re-Connect Google to refresh your connection.';
                profile.isTokenExpired = true;
                return profile;
            }
            
            if (!apiResult.isSuccess) {
                profile.isSuccess = false;
                profile.errorMessage = 'Failed to fetch user profile: ' + apiResult.errorMessage;
                return profile;
            }
            
            // Parse the JSON response
            Map<String, Object> userProfile = (Map<String, Object>) JSON.deserializeUntyped(apiResult.responseBody);
            
            profile.isSuccess = true;
            profile.email = (String) userProfile.get('email');
            profile.displayName = (String) userProfile.get('name');
            profile.givenName = (String) userProfile.get('given_name');
            profile.surname = (String) userProfile.get('family_name');
            
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            profile.isSuccess = false;
            // Set a user-friendly message - the LWC will auto-refresh the token
            profile.errorMessage = 'Refreshing your Gmail connection...';
            profile.isTokenExpired = true;
            System.debug(LoggingLevel.INFO, 'Token expired for Gmail, will auto-refresh: ' + e.getMessage());
        } catch (Exception e) {
            profile.isSuccess = false;
            profile.errorMessage = 'Error fetching Gmail profile: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Exception in getGmailUserProfile: ' + e.getMessage());
        }
        
        return profile;
    }
    
    /**
     * @description Refreshes the Gmail token and returns the user profile
     * Call this when the token has expired (isTokenExpired = true)
     * @return UserProfile with refreshed token data
     */
    @AuraEnabled
    public static UserProfile refreshGmailAndGetProfile() {
        UserProfile profile = new UserProfile();
        profile.provider = 'Gmail';
        
        try {
            // Step 1: Refresh the token (callout to token endpoint + DML to save)
            String accessToken = AIWorkspaceTokenService.refreshAndGetToken(AIWorkspaceTokenService.PROVIDER_GMAIL);
            
            // Step 2: Return success - the UI should call getGmailUserProfile again
            profile.isSuccess = true;
            profile.errorMessage = 'Token refreshed successfully';
            
        } catch (AIWorkspaceTokenService.AuthenticationException e) {
            profile.isSuccess = false;
            profile.errorMessage = e.getMessage();
            profile.isTokenExpired = true;
        } catch (Exception e) {
            profile.isSuccess = false;
            profile.errorMessage = 'Error refreshing token: ' + e.getMessage();
        }
        
        return profile;
    }
    
    /**
     * @description Gets the Auto Sync Enabled status for the current user
     * Returns true if ANY of the user's workspace records has Auto_Sync_Enabled__c = true
     * @return AutoSyncStatus Wrapper containing the current status
     */
    @AuraEnabled
    public static AutoSyncStatus getAutoSyncStatus() {
        AutoSyncStatus status = new AutoSyncStatus();
        
        try {
            Id currentUserId = UserInfo.getUserId();
            
            // Check if user has read access
            if (!Schema.sObjectType.AI_Workspace_User__c.isAccessible()) {
                status.hasAnyConnection = false;
                status.isEnabled = false;
                return status;
            }
            
            // Query all workspace user records for this user
            List<AI_Workspace_User__c> workspaceUsers = [
                SELECT Id, Provider__c, Auto_Sync_Enabled__c, Refresh_Token__c
                FROM AI_Workspace_User__c
                WHERE User__c = :currentUserId
            ];
            
            // Check if user has any authenticated connections
            for (AI_Workspace_User__c wu : workspaceUsers) {
                if (String.isNotBlank(wu.Refresh_Token__c)) {
                    status.hasAnyConnection = true;
                    // Check if ANY record has Auto Sync enabled
                    if (wu.Auto_Sync_Enabled__c == true) {
                        status.isEnabled = true;
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Exception in getAutoSyncStatus: ' + e.getMessage());
        }
        
        return status;
    }
    
    /**
     * @description Sets the Auto Sync Enabled status for ALL of the current user's workspace records
     * @param enabled The new enabled status
     * @return AutoSyncStatus Wrapper containing the updated status
     */
    @AuraEnabled
    public static AutoSyncStatus setAutoSyncStatus(Boolean enabled) {
        AutoSyncStatus status = new AutoSyncStatus();
        
        try {
            Id currentUserId = UserInfo.getUserId();
            
            // Check CRUD permissions
            if (!Schema.sObjectType.AI_Workspace_User__c.isAccessible() ||
                !Schema.sObjectType.AI_Workspace_User__c.isUpdateable()) {
                status.hasAnyConnection = false;
                status.isEnabled = false;
                status.errorMessage = 'Insufficient permissions to update settings.';
                return status;
            }
            
            // Query all workspace user records for this user
            List<AI_Workspace_User__c> workspaceUsers = [
                SELECT Id, Provider__c, Auto_Sync_Enabled__c, Refresh_Token__c
                FROM AI_Workspace_User__c
                WHERE User__c = :currentUserId
            ];
            
            // Update all records
            List<AI_Workspace_User__c> recordsToUpdate = new List<AI_Workspace_User__c>();
            for (AI_Workspace_User__c wu : workspaceUsers) {
                if (String.isNotBlank(wu.Refresh_Token__c)) {
                    status.hasAnyConnection = true;
                    wu.Auto_Sync_Enabled__c = enabled;
                    recordsToUpdate.add(wu);
                }
            }
            
            if (!recordsToUpdate.isEmpty()) {
                // Use FLSCheck for security enforcement
                FLSCheck.getInstance().updateDML(recordsToUpdate);
                status.isEnabled = enabled;
            }
            
        } catch (Exception e) {
            status.errorMessage = 'Error updating Auto Sync status: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Exception in setAutoSyncStatus: ' + e.getMessage());
        }
        
        return status;
    }
    
    /**
     * @description Wrapper class for Auto Sync status
     */
    public class AutoSyncStatus {
        @AuraEnabled public Boolean hasAnyConnection { get; set; }
        @AuraEnabled public Boolean isEnabled { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public AutoSyncStatus() {
            this.hasAnyConnection = false;
            this.isEnabled = false;
            this.errorMessage = null;
        }
    }
    
    /**
     * @description Wrapper class for connection status
     */
    public class ConnectionStatus {
        @AuraEnabled public Boolean isConnected { get; set; }
        @AuraEnabled public String workspaceUserId { get; set; }
        @AuraEnabled public String userName { get; set; }
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public ConnectionStatus() {
            this.isConnected = false;
            this.workspaceUserId = null;
            this.userName = null;
            this.provider = null;
            this.errorMessage = null;
        }
    }
    
    /**
     * @description Wrapper class for user profile (Outlook or Gmail)
     */
    public class UserProfile {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String displayName { get; set; }
        @AuraEnabled public String givenName { get; set; }
        @AuraEnabled public String surname { get; set; }
        @AuraEnabled public String jobTitle { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Boolean isTokenExpired { get; set; }
        
        public UserProfile() {
            this.isSuccess = false;
            this.provider = null;
            this.email = null;
            this.displayName = null;
            this.givenName = null;
            this.surname = null;
            this.jobTitle = null;
            this.errorMessage = null;
            this.isTokenExpired = false;
        }
    }
    
    /**
     * @description Wrapper class for disconnect result
     */
    public class DisconnectResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        
        public DisconnectResult() {
            this.isSuccess = false;
            this.message = null;
        }
    }
}