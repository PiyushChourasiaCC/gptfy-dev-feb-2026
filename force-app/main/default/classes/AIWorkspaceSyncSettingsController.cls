/**
 * @description Controller for Workspace Sync Settings management in AI Settings page.
 * Handles CRUD operations for AI_Workspace_Sync_Settings__c custom setting.
 * Includes security masking for sensitive OAuth credentials.
 * 
 * Namespace-aware for managed package compatibility.
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIWorkspaceSyncSettingsController {
    
    // Mask pattern for sensitive fields (16 asterisks)
    private static final String MASKED_VALUE = '****************';
    private static final Integer MASK_LENGTH = 16;
    
    // Namespace prefix for managed package support
    private static final String NAMESPACE = getNameSpace();
    
    /**
     * @description Wrapper class containing all settings for the UI
     */
    public class WorkspaceSyncSettings {
        // Providers
        @AuraEnabled public Boolean wsOutlookEnabled { get; set; }
        @AuraEnabled public Boolean wsGmailEnabled { get; set; }
        
        // Microsoft OAuth (masked for display)
        @AuraEnabled public String microsoftClientId { get; set; }
        @AuraEnabled public String microsoftClientSecret { get; set; }
        @AuraEnabled public String microsoftAuthEndpoint { get; set; }
        @AuraEnabled public String microsoftTokenEndpoint { get; set; }
        @AuraEnabled public String microsoftScope { get; set; }
        @AuraEnabled public Boolean hasMicrosoftClientId { get; set; }
        @AuraEnabled public Boolean hasMicrosoftClientSecret { get; set; }
        
        // Google OAuth (masked for display)
        @AuraEnabled public String googleClientId { get; set; }
        @AuraEnabled public String googleClientSecret { get; set; }
        @AuraEnabled public String googleAuthEndpoint { get; set; }
        @AuraEnabled public String googleTokenEndpoint { get; set; }
        @AuraEnabled public String googleScope { get; set; }
        @AuraEnabled public Boolean hasGoogleClientId { get; set; }
        @AuraEnabled public Boolean hasGoogleClientSecret { get; set; }
        
        // Email Sync Settings
        @AuraEnabled public Boolean syncEnabled { get; set; }
        @AuraEnabled public Decimal syncFrequencyMinutes { get; set; }
        @AuraEnabled public Decimal lookbackHours { get; set; }
        @AuraEnabled public Decimal maxEmailsPerUser { get; set; }
        @AuraEnabled public Decimal emailsPerBatch { get; set; }
        
        // Calendar Sync Settings
        @AuraEnabled public Boolean calendarSyncEnabled { get; set; }
        @AuraEnabled public Decimal calendarLookbackDays { get; set; }
        @AuraEnabled public Decimal calendarLookaheadDays { get; set; }
        @AuraEnabled public Decimal maxCalendarEventsPerUser { get; set; }
        
        // Task Sync Settings
        @AuraEnabled public Boolean taskSyncEnabled { get; set; }
        @AuraEnabled public Decimal taskLookbackDays { get; set; }
        @AuraEnabled public Decimal maxTasksPerUser { get; set; }
        @AuraEnabled public Boolean includeCompletedTasks { get; set; }
        
        // Digest Settings
        @AuraEnabled public Boolean digestEnabled { get; set; }
        @AuraEnabled public String digestFrequency { get; set; }
        @AuraEnabled public Decimal digestHour { get; set; }
        @AuraEnabled public Boolean notifyUsers { get; set; }
        
        // Matching Precedence
        @AuraEnabled public String syncPrecedence { get; set; }
        
        // Exclusion Rules (V2-7889: Removed old fields)
        @AuraEnabled public String excludedDomains { get; set; }
        @AuraEnabled public String excludedLabelsCategories { get; set; }
        
        // Email Sync Additional Settings (moved from Additional Settings section)
        @AuraEnabled public Decimal maxUsersPerBatch { get; set; }
        @AuraEnabled public Decimal queueableDelayMinutes { get; set; }
    }
    
    /**
     * @description Retrieves all workspace sync settings with masked sensitive fields.
     * If no settings record exists, returns default values (without creating a record).
     * @return WorkspaceSyncSettings wrapper with all settings
     */
    @AuraEnabled
    public static WorkspaceSyncSettings getSettings() {
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            Boolean hasExistingRecord = settings.Id != null;
            
            WorkspaceSyncSettings result = new WorkspaceSyncSettings();
            
            // Providers - default to false
            result.wsOutlookEnabled = settings.WS_Outlook_Enabled__c == true;
            result.wsGmailEnabled = settings.WS_Gmail_Enabled__c == true;
            
            // Microsoft OAuth - mask sensitive fields
            result.hasMicrosoftClientId = String.isNotBlank(settings.Microsoft_Client_Id__c);
            result.hasMicrosoftClientSecret = String.isNotBlank(settings.Microsoft_Client_Secret__c);
            result.microsoftClientId = result.hasMicrosoftClientId ? MASKED_VALUE : '';
            result.microsoftClientSecret = result.hasMicrosoftClientSecret ? MASKED_VALUE : '';
            result.microsoftAuthEndpoint = settings.Microsoft_Auth_Endpoint__c;
            result.microsoftTokenEndpoint = settings.Microsoft_Token_Endpoint__c;
            result.microsoftScope = settings.Microsoft_Scope__c;
            
            // Google OAuth - mask sensitive fields
            result.hasGoogleClientId = String.isNotBlank(settings.Google_Client_Id__c);
            result.hasGoogleClientSecret = String.isNotBlank(settings.Google_Client_Secret__c);
            result.googleClientId = result.hasGoogleClientId ? MASKED_VALUE : '';
            result.googleClientSecret = result.hasGoogleClientSecret ? MASKED_VALUE : '';
            result.googleAuthEndpoint = settings.Google_Auth_Endpoint__c;
            result.googleTokenEndpoint = settings.Google_Token_Endpoint__c;
            result.googleScope = settings.Google_Scope__c;
            
            // Email Sync Settings - use defaults if no record exists
            result.syncEnabled = hasExistingRecord ? settings.Sync_Enabled__c == true : true;
            result.syncFrequencyMinutes = hasExistingRecord ? settings.Sync_Frequency_Minutes__c : 60;
            result.lookbackHours = hasExistingRecord ? settings.Lookback_Hours__c : 24;
            result.maxEmailsPerUser = hasExistingRecord ? settings.Max_Emails_Per_User__c : 50;
            result.emailsPerBatch = hasExistingRecord ? settings.Emails_Per_Batch__c : 20;
            
            // Calendar Sync Settings - use defaults if no record exists
            result.calendarSyncEnabled = hasExistingRecord ? settings.Calendar_Sync_Enabled__c == true : false;
            result.calendarLookbackDays = hasExistingRecord ? settings.Calendar_Lookback_Days__c : 7;
            result.calendarLookaheadDays = hasExistingRecord ? settings.Calendar_Lookahead_Days__c : 30;
            result.maxCalendarEventsPerUser = hasExistingRecord ? settings.Max_Calendar_Events_Per_User__c : 50;
            
            // Task Sync Settings - use defaults if no record exists
            result.taskSyncEnabled = hasExistingRecord ? settings.Task_Sync_Enabled__c == true : false;
            result.taskLookbackDays = (hasExistingRecord && settings.Task_Lookback_Days__c != null) ? settings.Task_Lookback_Days__c : 7;
            result.maxTasksPerUser = hasExistingRecord ? settings.Max_Tasks_Per_User__c : 50;
            result.includeCompletedTasks = hasExistingRecord ? settings.Include_Completed_Tasks__c == true : false;
            
            // Digest Settings - use defaults if no record exists
            result.digestEnabled = hasExistingRecord ? settings.Digest_Enabled__c == true : false;
            result.digestFrequency = hasExistingRecord ? settings.Digest_Frequency__c : 'Daily';
            result.digestHour = hasExistingRecord ? settings.Digest_Hour__c : 8;
            result.notifyUsers = hasExistingRecord ? settings.Notify_Users__c == true : false;
            
            // Matching Precedence - use defaults if no record exists
            result.syncPrecedence = hasExistingRecord ? settings.Sync_Precedence__c : '{"1": ["Lead","Contact","User"], "2": ["Lead","Contact"], "3": ["Lead"], "4": ["Contact"], "5": ["User"]}';
            
            // Exclusion Rules (V2-7889: New fields only)
            result.excludedDomains = settings.Excluded_Domains__c;
            result.excludedLabelsCategories = settings.Excluded_Labels_Categories__c;
            
            // Email Sync Additional Settings - use defaults if no record exists
            result.maxUsersPerBatch = hasExistingRecord ? settings.Max_Users_Per_Batch__c : 10;
            result.queueableDelayMinutes = hasExistingRecord ? settings.Queueable_Delay_Minutes__c : 1;
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving settings: ' + e.getMessage());
        }
    }
    
    /**
     * @description Updates a single field in the workspace sync settings
     * @param fieldName The API name of the field to update
     * @param value The new value (can be String, Boolean, or Number)
     * @return Boolean indicating success
     */
    @AuraEnabled
    public static Boolean updateField(String fieldName, Object value) {
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            
            // If settings don't exist, create them with default values
            if (settings.Id == null) {
                settings = createSettingsWithDefaults();
            }
            
            // Ensure SetupOwnerId is always set to Organization ID (org-level setting)
            // This is critical for making settings available to all users with permissions
            if (settings.SetupOwnerId != UserInfo.getOrganizationId()) {
                settings.SetupOwnerId = UserInfo.getOrganizationId();
            }
            
            // Skip update if the value is the masked value (user didn't change it)
            if (value instanceof String && ((String)value) == MASKED_VALUE) {
                return true;
            }
            
            // Map field names to actual API names (with namespace prefix for managed package)
            Map<String, String> fieldMapping = new Map<String, String>{
                // Providers
                'wsOutlookEnabled' => NAMESPACE + 'WS_Outlook_Enabled__c',
                'wsGmailEnabled' => NAMESPACE + 'WS_Gmail_Enabled__c',
                
                // Microsoft OAuth
                'microsoftClientId' => NAMESPACE + 'Microsoft_Client_Id__c',
                'microsoftClientSecret' => NAMESPACE + 'Microsoft_Client_Secret__c',
                'microsoftAuthEndpoint' => NAMESPACE + 'Microsoft_Auth_Endpoint__c',
                'microsoftTokenEndpoint' => NAMESPACE + 'Microsoft_Token_Endpoint__c',
                'microsoftScope' => NAMESPACE + 'Microsoft_Scope__c',
                
                // Google OAuth
                'googleClientId' => NAMESPACE + 'Google_Client_Id__c',
                'googleClientSecret' => NAMESPACE + 'Google_Client_Secret__c',
                'googleAuthEndpoint' => NAMESPACE + 'Google_Auth_Endpoint__c',
                'googleTokenEndpoint' => NAMESPACE + 'Google_Token_Endpoint__c',
                'googleScope' => NAMESPACE + 'Google_Scope__c',
                
                // Email Sync Settings
                'syncEnabled' => NAMESPACE + 'Sync_Enabled__c',
                'syncFrequencyMinutes' => NAMESPACE + 'Sync_Frequency_Minutes__c',
                'lookbackHours' => NAMESPACE + 'Lookback_Hours__c',
                'maxEmailsPerUser' => NAMESPACE + 'Max_Emails_Per_User__c',
                'emailsPerBatch' => NAMESPACE + 'Emails_Per_Batch__c',
                
                // Calendar Sync Settings
                'calendarSyncEnabled' => NAMESPACE + 'Calendar_Sync_Enabled__c',
                'calendarLookbackDays' => NAMESPACE + 'Calendar_Lookback_Days__c',
                'calendarLookaheadDays' => NAMESPACE + 'Calendar_Lookahead_Days__c',
                'maxCalendarEventsPerUser' => NAMESPACE + 'Max_Calendar_Events_Per_User__c',
                
                // Task Sync Settings
                'taskSyncEnabled' => NAMESPACE + 'Task_Sync_Enabled__c',
                'taskLookbackDays' => NAMESPACE + 'Task_Lookback_Days__c',
                'maxTasksPerUser' => NAMESPACE + 'Max_Tasks_Per_User__c',
                'includeCompletedTasks' => NAMESPACE + 'Include_Completed_Tasks__c',
                
                // Digest Settings
                'digestEnabled' => NAMESPACE + 'Digest_Enabled__c',
                'digestFrequency' => NAMESPACE + 'Digest_Frequency__c',
                'digestHour' => NAMESPACE + 'Digest_Hour__c',
                'notifyUsers' => NAMESPACE + 'Notify_Users__c',
                
                // Matching Precedence
                'syncPrecedence' => NAMESPACE + 'Sync_Precedence__c',
                
                // Exclusion Rules
                'excludedDomains' => NAMESPACE + 'Excluded_Domains__c',
                'excludedLabelsCategories' => NAMESPACE + 'Excluded_Labels_Categories__c',
                
                // Email Sync Additional Settings
                'maxUsersPerBatch' => NAMESPACE + 'Max_Users_Per_Batch__c',
                'queueableDelayMinutes' => NAMESPACE + 'Queueable_Delay_Minutes__c'
            };
            
            String actualFieldName = fieldMapping.get(fieldName);
            if (actualFieldName == null) {
                throw new AuraHandledException('Invalid field name: ' + fieldName);
            }
            
            // Set the field value dynamically
            settings.put(actualFieldName, value);
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Settings__c> settingsToUpdate = new List<AI_Workspace_Sync_Settings__c>{ settings };
            FLSCheck.getInstance().updateDML(settingsToUpdate);
            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating field: ' + e.getMessage());
        }
    }
    
    /**
     * @description Validates required fields based on provider enablement
     * @param wsOutlookEnabled Whether Outlook is enabled
     * @param wsGmailEnabled Whether Gmail is enabled
     * @return List of missing required field names
     */
    @AuraEnabled
    public static List<String> validateRequiredFields(Boolean wsOutlookEnabled, Boolean wsGmailEnabled) {
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            List<String> missingFields = new List<String>();
            
            if (wsOutlookEnabled == true) {
                if (String.isBlank(settings.Microsoft_Client_Id__c)) {
                    missingFields.add('Microsoft Client Id');
                }
                if (String.isBlank(settings.Microsoft_Client_Secret__c)) {
                    missingFields.add('Microsoft Client Secret');
                }
                if (String.isBlank(settings.Microsoft_Auth_Endpoint__c)) {
                    missingFields.add('Microsoft Auth Endpoint');
                }
                if (String.isBlank(settings.Microsoft_Token_Endpoint__c)) {
                    missingFields.add('Microsoft Token Endpoint');
                }
                if (String.isBlank(settings.Microsoft_Scope__c)) {
                    missingFields.add('Microsoft Scope');
                }
            }
            
            if (wsGmailEnabled == true) {
                if (String.isBlank(settings.Google_Client_Id__c)) {
                    missingFields.add('Google Client Id');
                }
                if (String.isBlank(settings.Google_Client_Secret__c)) {
                    missingFields.add('Google Client Secret');
                }
                if (String.isBlank(settings.Google_Auth_Endpoint__c)) {
                    missingFields.add('Google Auth Endpoint');
                }
                if (String.isBlank(settings.Google_Token_Endpoint__c)) {
                    missingFields.add('Google Token Endpoint');
                }
                if (String.isBlank(settings.Google_Scope__c)) {
                    missingFields.add('Google Scope');
                }
            }
            
            return missingFields;
        } catch (Exception e) {
            throw new AuraHandledException('Error validating fields: ' + e.getMessage());
        }
    }
    
    /**
     * @description Creates a new settings record with sensible default values.
     * Called when user saves any field for the first time (no existing record).
     * @return AI_Workspace_Sync_Settings__c The newly created settings record
     */
    private static AI_Workspace_Sync_Settings__c createSettingsWithDefaults() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        
        // CRITICAL: Set SetupOwnerId to Organization ID to make this an org-level setting
        // This ensures all users with appropriate permissions can access these settings
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        
        // Email Sync Settings - Email enabled by default
        settings.Sync_Enabled__c = true;
        settings.Sync_Frequency_Minutes__c = 60;
        settings.Lookback_Hours__c = 24;
        settings.Max_Emails_Per_User__c = 50;
        settings.Emails_Per_Batch__c = 20;
        settings.Max_Users_Per_Batch__c = 10;
        settings.Queueable_Delay_Minutes__c = 1;
        
        // Calendar Sync Settings - Disabled by default
        settings.Calendar_Sync_Enabled__c = false;
        settings.Calendar_Lookback_Days__c = 7;
        settings.Calendar_Lookahead_Days__c = 30;
        settings.Max_Calendar_Events_Per_User__c = 50;
        
        // Task Sync Settings - Disabled by default
        settings.Task_Sync_Enabled__c = false;
        settings.Max_Tasks_Per_User__c = 50;
        settings.Include_Completed_Tasks__c = false;
        
        // Digest Settings - Disabled by default
        settings.Digest_Enabled__c = false;
        settings.Notify_Users__c = false;
        settings.Digest_Frequency__c = 'Daily';
        settings.Digest_Hour__c = 8;
        
        // Matching Precedence - Default precedence order (Lead and Contact only - User not supported)
        settings.Sync_Precedence__c = '{"1": ["Lead","Contact"], "2": ["Lead"], "3": ["Contact"]}';
        
        // Exclusion Rules - All exclusions enabled by default
        settings.Excluded_Domains__c = '';
        settings.Excluded_Labels_Categories__c = '';
        
        // Use FLSCheck for security enforcement
        List<AI_Workspace_Sync_Settings__c> settingsToInsert = new List<AI_Workspace_Sync_Settings__c>{ settings };
        FLSCheck.getInstance().insertDML(settingsToInsert);
        return AI_Workspace_Sync_Settings__c.getOrgDefaults();
    }
    
    /**
     * @description Ensures the Custom Settings record is at org-level.
     * If an existing record is not org-level, this method will fix it.
     * This is useful for migration or fixing misconfigured settings.
     * @return Map with status and message
     */
    @AuraEnabled
    public static Map<String, Object> ensureOrgLevelSettings() {
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            
            if (settings.Id == null) {
                // No settings exist, create org-level settings
                settings = createSettingsWithDefaults();
                return new Map<String, Object>{
                    'success' => true,
                    'message' => 'Created new org-level settings',
                    'recordId' => settings.Id,
                    'setupOwnerId' => settings.SetupOwnerId
                };
            }
            
            // Check if SetupOwnerId is correct
            if (settings.SetupOwnerId != UserInfo.getOrganizationId()) {
                // Fix the SetupOwnerId
                settings.SetupOwnerId = UserInfo.getOrganizationId();
                FLSCheck.getInstance().updateDML(new List<AI_Workspace_Sync_Settings__c>{settings});
                
                return new Map<String, Object>{
                    'success' => true,
                    'message' => 'Fixed SetupOwnerId to org-level',
                    'recordId' => settings.Id,
                    'setupOwnerId' => settings.SetupOwnerId
                };
            }
            
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Settings are already at org-level',
                'recordId' => settings.Id,
                'setupOwnerId' => settings.SetupOwnerId
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Error: ' + e.getMessage()
            };
        }
    }
    
    /**
     * @description Gets the namespace prefix for the managed package.
     * Returns empty string for unpackaged orgs, or 'namespace__' for packaged orgs.
     * @return String The namespace prefix (with trailing __) or empty string
     */
    private static String getNameSpace() {
        String np = '';
        try {
            String className = 'AIWorkspaceSyncSettingsController';
            String query = 'SELECT NamespacePrefix FROM ApexClass WHERE Name = \'' + className + '\' LIMIT 1';
            ApexClass queryResult = Database.query(query);
            np = queryResult.NamespacePrefix;
            if (np == null) {
                np = '';
            } else {
                np = np + '__';
            }
        } catch (Exception ex) {
            // If query fails, assume no namespace
            np = '';
        }
        return np;
    }
}