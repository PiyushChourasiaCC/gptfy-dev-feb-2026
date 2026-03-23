/**
 * SyncSettingsService - Centralized access to AI_Workspace_Sync_Settings__c
 * Provides a single source of truth for all sync settings across the application.
 *
 * Benefits:
 * - Single cache instance across all services
 * - Consistent access patterns
 * - Easier to mock in tests via setCachedSettings()
 * - Clear separation of concerns
 * - Hierarchy Custom Setting allows org, profile, and user-level overrides
 * 
 * Note: Uses 'without sharing' to ensure all users can access org-wide 
 * AI_Workspace_Sync_Settings__c custom settings regardless of their profile permissions.
 * These are org-wide configuration settings that should be accessible to all sync operations.
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public without sharing class AISyncSettingsService {

    // Cached settings - shared across all callers
    private static AI_Workspace_Sync_Settings__c cachedSettings;

    /**
     * Get the org-default sync settings.
     * Uses cached instance if available.
     * @return AI_Workspace_Sync_Settings__c or instance with defaults if not configured
     */
    public static AI_Workspace_Sync_Settings__c getSettings() {
        if (cachedSettings == null) {
            // getOrgDefaults() returns null if no org-level record exists
            cachedSettings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            if (cachedSettings == null) {
                // Return empty instance with defaults
                cachedSettings = new AI_Workspace_Sync_Settings__c();
            }
        }
        return cachedSettings;
    }

    /**
     * Get settings with validation - throws if not configured
     * @return AI_Workspace_Sync_Settings__c
     * @throws SyncSettingsException if settings are not configured
     */
    public static AI_Workspace_Sync_Settings__c getSettingsRequired() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings == null || settings.Id == null) {
            throw new SyncSettingsException('AI_Workspace_Sync_Settings__c org defaults are not configured');
        }
        return settings;
    }

    // =========================================================================
    // Provider Enabled Settings (NEW)
    // =========================================================================

    /**
     * Check if Outlook/Microsoft 365 workspace sync is enabled
     */
    public static Boolean isOutlookEnabled() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null && settings.WS_Outlook_Enabled__c == true;
    }

    /**
     * Check if Gmail/Google Workspace sync is enabled
     */
    public static Boolean isGmailEnabled() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null && settings.WS_Gmail_Enabled__c == true;
    }
    
    /**
     * Get provider enabled status for LWC components.
     * Returns which providers (Outlook/Gmail) are enabled in org settings.
     * Used by Email Sync, Calendar Sync, and Task Sync LWC components
     * to determine whether to show provider switcher or auto-select the enabled provider.
     * 
     * @return ProviderSettings wrapper with enabled status for each provider
     */
    @AuraEnabled(cacheable=true)
    public static ProviderSettings getProviderSettings() {
        ProviderSettings result = new ProviderSettings();
        AI_Workspace_Sync_Settings__c settings = getSettings();
        
        result.outlookEnabled = settings != null && settings.WS_Outlook_Enabled__c == true;
        result.gmailEnabled = settings != null && settings.WS_Gmail_Enabled__c == true;
        result.bothEnabled = result.outlookEnabled && result.gmailEnabled;
        result.neitherEnabled = !result.outlookEnabled && !result.gmailEnabled;
        
        // Determine which single provider to use (when only one is enabled)
        if (result.outlookEnabled && !result.gmailEnabled) {
            result.singleProvider = 'MICROSOFT_EMAIL';
        } else if (result.gmailEnabled && !result.outlookEnabled) {
            result.singleProvider = 'GMAIL_EMAIL';
        } else {
            result.singleProvider = null;
        }
        
        return result;
    }
    
    /**
     * Wrapper class for provider settings returned to LWC
     */
    public class ProviderSettings {
        @AuraEnabled public Boolean outlookEnabled { get; set; }
        @AuraEnabled public Boolean gmailEnabled { get; set; }
        @AuraEnabled public Boolean bothEnabled { get; set; }
        @AuraEnabled public Boolean neitherEnabled { get; set; }
        @AuraEnabled public String singleProvider { get; set; }
        
        public ProviderSettings() {
            this.outlookEnabled = false;
            this.gmailEnabled = false;
            this.bothEnabled = false;
            this.neitherEnabled = true;
            this.singleProvider = null;
        }
    }

    // =========================================================================
    // Sync Enabled Settings
    // =========================================================================

    /**
     * Check if email sync is enabled
     */
    public static Boolean isSyncEnabled() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null && settings.Sync_Enabled__c == true;
    }

    /**
     * Check if calendar sync is enabled
     */
    public static Boolean isCalendarSyncEnabled() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null && settings.Calendar_Sync_Enabled__c == true;
    }

    /**
     * Check if Task (To-Do) sync is enabled
     */
    public static Boolean isTaskSyncEnabled() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null && settings.Task_Sync_Enabled__c == true;
    }

    /**
     * Get max tasks per user for sync
     */
    public static Integer getMaxTasksPerUser() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Max_Tasks_Per_User__c != null) {
            return Integer.valueOf(settings.Max_Tasks_Per_User__c);
        }
        return 50; // Default
    }

    /**
     * Check if completed tasks should be included in sync
     */
    public static Boolean includeCompletedTasks() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null && settings.Include_Completed_Tasks__c == true;
    }

    /**
     * Check if digest notifications are enabled
     */
    public static Boolean isDigestEnabled() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null && settings.Digest_Enabled__c == true;
    }

    // =========================================================================
    // Exclusion Settings (V2-7889)
    // =========================================================================

    /**
     * Get excluded domains from settings
     * @return Comma-separated string of domains to exclude, or null
     */
    public static String getExcludedDomains() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null ? settings.Excluded_Domains__c : null;
    }

    /**
     * Get excluded labels/categories from settings
     * @return Comma-separated string of labels/categories to exclude, or null
     */
    public static String getExcludedLabelsCategories() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null ? settings.Excluded_Labels_Categories__c : null;
    }

    /**
     * Get excluded domains as a list
     * @return List of domains to exclude (lowercase, trimmed)
     */
    public static List<String> getExcludedDomainsList() {
        List<String> domains = new List<String>();
        String excludedDomains = getExcludedDomains();
        
        if (String.isBlank(excludedDomains)) {
            return domains;
        }
        
        for (String domain : excludedDomains.split(',')) {
            String trimmed = domain.trim().toLowerCase();
            if (String.isNotBlank(trimmed)) {
                domains.add(trimmed);
            }
        }
        
        return domains;
    }

    /**
     * Get excluded labels/categories as a list
     * @return List of labels/categories to exclude (lowercase, trimmed)
     */
    public static List<String> getExcludedLabelsList() {
        List<String> labels = new List<String>();
        String excludedLabels = getExcludedLabelsCategories();
        
        if (String.isBlank(excludedLabels)) {
            return labels;
        }
        
        for (String label : excludedLabels.split(',')) {
            String trimmed = label.trim().toLowerCase();
            if (String.isNotBlank(trimmed)) {
                labels.add(trimmed);
            }
        }
        
        return labels;
    }

    // =========================================================================
    // Time Window Settings
    // =========================================================================

    /**
     * Get sync lookback hours (how far back to sync)
     */
    public static Integer getLookbackHours() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Lookback_Hours__c != null) {
            return Integer.valueOf(settings.Lookback_Hours__c);
        }
        return 24; // Default to 24 hours
    }

    /**
     * Get calendar lookahead days
     */
    public static Integer getCalendarLookaheadDays() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Calendar_Lookahead_Days__c != null) {
            return Integer.valueOf(settings.Calendar_Lookahead_Days__c);
        }
        return 14; // Default to 14 days
    }

    /**
     * Get calendar lookback days
     */
    public static Integer getCalendarLookbackDays() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Calendar_Lookback_Days__c != null) {
            return Integer.valueOf(settings.Calendar_Lookback_Days__c);
        }
        return 7; // Default to 7 days
    }

    /**
     * Get task lookback days
     */
    public static Integer getTaskLookbackDays() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Task_Lookback_Days__c != null) {
            return Integer.valueOf(settings.Task_Lookback_Days__c);
        }
        return 7; // Default to 7 days
    }

    /**
     * Get sync frequency minutes
     */
    public static Integer getSyncFrequencyMinutes() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Sync_Frequency_Minutes__c != null) {
            return Integer.valueOf(settings.Sync_Frequency_Minutes__c);
        }
        return 60; // Default to 60 minutes
    }

    /**
     * Get digest frequency (e.g., 'Daily', 'Weekly')
     */
    public static String getDigestFrequency() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && String.isNotBlank(settings.Digest_Frequency__c)) {
            return settings.Digest_Frequency__c;
        }
        return 'Daily'; // Default to daily
    }

    /**
     * Get digest hour (0-23)
     */
    public static Integer getDigestHour() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Digest_Hour__c != null) {
            return Integer.valueOf(settings.Digest_Hour__c);
        }
        return 8; // Default to 8 AM
    }

    // =========================================================================
    // Batch Settings
    // =========================================================================

    /**
     * Get max emails per user for processing
     */
    public static Integer getMaxEmailsPerUser() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Max_Emails_Per_User__c != null) {
            return Integer.valueOf(settings.Max_Emails_Per_User__c);
        }
        return 10; // Default emails per user (changed from 50 to 10)
    }

    /**
     * Get max users per batch
     */
    public static Integer getMaxUsersPerBatch() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Max_Users_Per_Batch__c != null) {
            return Integer.valueOf(settings.Max_Users_Per_Batch__c);
        }
        return 10; // Default users per batch
    }

    /**
     * Get max calendar events per user
     */
    public static Integer getMaxCalendarEventsPerUser() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Max_Calendar_Events_Per_User__c != null) {
            return Integer.valueOf(settings.Max_Calendar_Events_Per_User__c);
        }
        return 50; // Default events per user
    }

    /**
     * Get emails per batch - number of emails to fetch per API call (with body).
     * Lower values are safer for heap size, higher values use fewer callouts.
     */
    public static Integer getEmailsPerBatch() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Emails_Per_Batch__c != null) {
            return Integer.valueOf(settings.Emails_Per_Batch__c);
        }
        return 20; // Default 20 emails per batch
    }

    /**
     * Get queueable delay in minutes
     */
    public static Integer getQueueableDelayMinutes() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        if (settings != null && settings.Queueable_Delay_Minutes__c != null) {
            return Integer.valueOf(settings.Queueable_Delay_Minutes__c);
        }
        return 1; // Default 1 minute
    }

    /**
     * Check if user notifications are enabled
     */
    public static Boolean isNotifyUsersEnabled() {
        AI_Workspace_Sync_Settings__c settings = getSettings();
        return settings != null && settings.Notify_Users__c == true;
    }

    // =========================================================================
    // Test Support
    // =========================================================================

    /**
     * Set cached settings for testing purposes.
     * This allows tests to mock settings without database access.
     */
    @TestVisible
    private static void setCachedSettings(AI_Workspace_Sync_Settings__c settings) {
        cachedSettings = settings;
    }

    /**
     * Clear the settings cache.
     * Useful for tests that need to reset state.
     */
    @TestVisible
    private static void clearCache() {
        cachedSettings = null;
    }

    // =========================================================================
    // Exception
    // =========================================================================

    /**
     * Exception thrown when settings are not configured
     */
    public class SyncSettingsException extends Exception {}
}