/**
 * Factory for instantiating email provider implementations
 * Uses AI_Workspace_User__c and AI_Workspace_Sync_Settings__c for configuration
 * 
 * Provider Type Mapping:
 * - 'MICROSOFT_GRAPH', 'MICROSOFT_EMAIL', 'Outlook' -> AIMicrosoftGraphProvider
 * - 'GMAIL', 'GMAIL_EMAIL', 'Gmail' -> AIGmailProvider
 * 
 * Note: Uses 'without sharing' to ensure consistent access to org-wide 
 * AI_Workspace_Sync_Settings__c custom settings regardless of user permissions.
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public without sharing class AIEmailProviderFactory {

    // Supported provider types (normalized to uppercase)
    public static final String PROVIDER_OUTLOOK = 'OUTLOOK';
    public static final String PROVIDER_GMAIL = 'GMAIL';
    public static final String PROVIDER_MICROSOFT_GRAPH = 'MICROSOFT_GRAPH';
    public static final String PROVIDER_MICROSOFT_EMAIL = 'MICROSOFT_EMAIL';
    public static final String PROVIDER_GMAIL_EMAIL = 'GMAIL_EMAIL';

    // Cached settings
    private static AI_Workspace_Sync_Settings__c cachedSettings;

    /**
     * Gets the appropriate email provider based on provider type
     * Supports multiple naming conventions for backward compatibility
     * 
     * @param providerType Provider type string (e.g., 'MICROSOFT_GRAPH', 'Outlook', 'GMAIL')
     * @return AIEmailProviderService instance
     */
    public static AIEmailProviderService getProvider(String providerType) {
        if (String.isBlank(providerType)) {
            throw new AIEmailProviderService.EmailProviderException('Provider type cannot be blank');
        }

        // Normalize provider type - replace spaces with underscores and uppercase
        String normalizedType = providerType.replace(' ', '_').toUpperCase();

        // Map to concrete provider class
        if (isOutlookProvider(normalizedType)) {
            return new AIMicrosoftGraphProvider();
        } else if (isGmailProvider(normalizedType)) {
            return new AIGmailProvider();
        }

        throw new AIEmailProviderService.EmailProviderException(
            'Unknown provider type: ' + providerType + '. Supported types: Outlook, Gmail, MICROSOFT_GRAPH, GMAIL'
        );
    }

    /**
     * Gets the default provider (Microsoft Graph/Outlook)
     */
    public static AIEmailProviderService getDefaultProvider() {
        return new AIMicrosoftGraphProvider();
    }

    /**
     * Check if provider type maps to Outlook/Microsoft Graph
     */
    private static Boolean isOutlookProvider(String normalizedType) {
        return normalizedType == PROVIDER_OUTLOOK ||
               normalizedType == PROVIDER_MICROSOFT_GRAPH ||
               normalizedType == PROVIDER_MICROSOFT_EMAIL;
    }

    /**
     * Check if provider type maps to Gmail
     */
    private static Boolean isGmailProvider(String normalizedType) {
        return normalizedType == PROVIDER_GMAIL ||
               normalizedType == PROVIDER_GMAIL_EMAIL;
    }

    /**
     * Gets all enabled providers based on AI_Workspace_Sync_Settings__c
     * Returns list of provider type strings that are enabled
     * 
     * @return List of enabled provider types (e.g., ['Outlook', 'Gmail'])
     */
    public static List<String> getEnabledProviderTypes() {
        List<String> enabledProviders = new List<String>();
        AI_Workspace_Sync_Settings__c settings = getSettings();

        if (settings != null) {
            if (settings.WS_Outlook_Enabled__c == true) {
                enabledProviders.add('Outlook');
            }
            if (settings.WS_Gmail_Enabled__c == true) {
                enabledProviders.add('Gmail');
            }
        }

        // If no settings configured, default to both providers enabled
        if (enabledProviders.isEmpty()) {
            enabledProviders.add('Outlook');
            enabledProviders.add('Gmail');
        }

        return enabledProviders;
    }

    /**
     * Gets all authenticated providers for a specific user
     * Queries AI_Workspace_User__c to find which providers the user has connected
     * 
     * @param userId The user to check
     * @return List of provider type strings the user has authenticated with
     */
    public static List<String> getAuthenticatedProviderTypes(Id userId) {
        List<String> authenticatedProviders = new List<String>();

        // Query AI_Workspace_User__c for this user's connections
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id, Provider__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :userId
        ];

        for (AI_Workspace_User__c wu : workspaceUsers) {
            // Check if has refresh token (indicates valid connection)
            if (String.isNotBlank(wu.Refresh_Token__c) && String.isNotBlank(wu.Provider__c)) {
                authenticatedProviders.add(wu.Provider__c);
            }
        }

        return authenticatedProviders;
    }

    /**
     * Gets authenticated providers that are also enabled in settings
     * Combines AI_Workspace_User__c check with AI_Workspace_Sync_Settings__c
     * 
     * @param userId The user to check
     * @return List of provider type strings that are both authenticated and enabled
     */
    public static List<String> getActiveAuthenticatedProviders(Id userId) {
        List<String> enabledProviders = getEnabledProviderTypes();
        List<String> authenticatedProviders = getAuthenticatedProviderTypes(userId);
        List<String> activeProviders = new List<String>();

        // Find intersection - providers that are both enabled and authenticated
        Set<String> enabledSet = new Set<String>();
        for (String p : enabledProviders) {
            enabledSet.add(p.toUpperCase());
        }

        for (String authProvider : authenticatedProviders) {
            if (enabledSet.contains(authProvider.toUpperCase())) {
                activeProviders.add(authProvider);
            }
        }

        return activeProviders;
    }

    /**
     * Normalizes provider type to standard format used in AI_Workspace_User__c
     * Converts MICROSOFT_GRAPH -> Outlook, GMAIL_EMAIL -> Gmail, etc.
     * 
     * @param providerType Input provider type
     * @return Normalized provider type ('Outlook' or 'Gmail')
     */
    public static String normalizeToWorkspaceUserProvider(String providerType) {
        if (String.isBlank(providerType)) {
            return null;
        }

        String normalized = providerType.replace(' ', '_').toUpperCase();

        if (isOutlookProvider(normalized)) {
            return 'Outlook';
        } else if (isGmailProvider(normalized)) {
            return 'Gmail';
        }

        return providerType; // Return as-is if unknown
    }

    /**
     * Get cached settings
     */
    private static AI_Workspace_Sync_Settings__c getSettings() {
        if (cachedSettings == null) {
            cachedSettings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        }
        return cachedSettings;
    }

    /**
     * Clear settings cache (for testing)
     */
    @TestVisible
    private static void clearSettingsCache() {
        cachedSettings = null;
    }
}