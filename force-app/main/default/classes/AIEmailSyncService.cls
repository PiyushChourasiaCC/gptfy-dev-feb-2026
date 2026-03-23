/**
 * EmailSyncService - Core service for automated email synchronization
 * PROVIDER-AGNOSTIC: Works with Exchange, Gmail, and any future providers
 *
 * Key Design:
 * - Queries AI_Workspace_Sync_Log__c to determine where last sync left off (per provider)
 * - Creates SEPARATE sync log records for each provider (if user has multiple)
 * - Each provider's sync window is independent
 * - Uses Named Credentials with "Per User" principal for OAuth
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIEmailSyncService {

    private static AI_Workspace_Sync_Settings__c settings;

    /**
     * NEW: Entry point for workspace-based sync (with access token).
     * Used by AIWorkspaceSyncQueueable when syncing via stored refresh tokens.
     * Does NOT rely on Named Credentials or user context.
     * 
     * @param userId The user whose mailbox should be synced
     * @param provider 'Outlook' or 'Gmail' (from AI_Workspace_User__c.Provider__c)
     * @param accessToken Fresh access token from OAuth refresh
     */
    public static void syncUserEmailsWithToken(Id userId, String provider, String accessToken) {
        loadSettings();
        
        // Map provider picklist value to provider type
        String providerType = provider == 'Outlook' ? 'MICROSOFT_EMAIL' : 'GMAIL_EMAIL';
        DateTime startTime = DateTime.now();
        
        // Validate inputs early
        if (String.isBlank(provider) || String.isBlank(accessToken)) {
            createFailedSyncLog(userId, providerType, startTime, 'Provider and access token are required');
            return;
        }
        
        try {
            // Get user email from provider API using the access token
            String userEmail = getUserEmailFromProvider(provider, accessToken);
            
            // Create a token-based provider context
            TokenBasedProviderContext ctx = new TokenBasedProviderContext(provider, providerType, accessToken);
            
            // Sync with token-based context
            syncProviderForUserWithToken(userId, ctx, userEmail);
        } catch (Exception e) {
            // If we fail before sync log is created, create one now
            createFailedSyncLog(userId, providerType, startTime, e.getMessage());
        }
    }
    
    /**
     * Create a failed sync log when sync fails before normal log creation
     */
    private static void createFailedSyncLog(Id userId, String providerType, DateTime startTime, String errorMessage) {
        try {
            AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
                User__c = userId,
                Provider_Type__c = providerType,
                Sync_Type__c = 'Scheduled',
                Status__c = 'Failed',
                Start_Time__c = startTime,
                End_Time__c = DateTime.now(),
                Error_Message__c = AIExchangeEmailHelper.truncateField(errorMessage, 32000)
            );
            syncLog.Processing_Time_Seconds__c = 
                (syncLog.End_Time__c.getTime() - syncLog.Start_Time__c.getTime()) / 1000.0;
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ syncLog };
            FLSCheck.getInstance().insertDML(logsToInsert);
        } catch (Exception e) {
            // Ignore
        }
    }
    
    /**
     * Get user email from provider API using access token
     */
    private static String getUserEmailFromProvider(String provider, String accessToken) {
        if (provider == 'Outlook') {
            return AIOutlookFetchService.getUserEmail(accessToken);
        } else {
            return AIGmailFetchService.getUserEmail(accessToken);
        }
    }
    
    /**
     * Token-based provider context for workspace sync
     */
    public class TokenBasedProviderContext {
        public String provider { get; set; }      // 'Outlook' or 'Gmail'
        public String providerType { get; set; }  // 'MICROSOFT_EMAIL' or 'GMAIL_EMAIL'
        public String accessToken { get; set; }
        
        public TokenBasedProviderContext(String provider, String providerType, String accessToken) {
            this.provider = provider;
            this.providerType = providerType;
            this.accessToken = accessToken;
        }
    }
    
    /**
     * Sync emails for a specific provider using token-based authentication.
     * Creates its own AI_Workspace_Sync_Log__c record.
     */
    private static void syncProviderForUserWithToken(Id userId, TokenBasedProviderContext ctx, String userEmail) {
        DateTime startTime = DateTime.now();
        
        // Initialize sync log for this provider
        // Provider type is already specific for Email sync (MICROSOFT_EMAIL or GMAIL_EMAIL)
        String emailProviderType = ctx.providerType;
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = userId,
            Provider_Type__c = emailProviderType,
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = startTime
        );
        
        try {
            // Query last successful sync log for THIS provider to determine start time
            // Use emailProviderType to match the Provider_Type__c value stored in sync logs
            DateTime syncWindowStart = getLastSyncTime(userId, emailProviderType);
            DateTime syncWindowEnd = DateTime.now();
            
            syncLog.Sync_Window_Start__c = syncWindowStart;
            syncLog.Sync_Window_End__c = syncWindowEnd;
            
            // Process sync with token-based fetching
            processSyncForUserWithToken(userId, ctx, userEmail, syncWindowStart, syncWindowEnd, syncLog);
            
            // Mark success if still in progress (no errors)
            if (syncLog.Status__c == 'In Progress') {
                syncLog.Status__c = 'Success';
            }
            
        } catch (Exception e) {
            syncLog.Status__c = 'Failed';
            syncLog.Error_Message__c = e.getMessage();
        }
        
        // Finalize sync log
        syncLog.End_Time__c = DateTime.now();
        syncLog.Processing_Time_Seconds__c =
            (syncLog.End_Time__c.getTime() - syncLog.Start_Time__c.getTime()) / 1000.0;
        
        // Use FLSCheck for security enforcement
        List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ syncLog };
        logsToInsert = FLSCheck.getInstance().insertDML(logsToInsert);
        syncLog = logsToInsert[0];
        
        // Send failure notification if sync failed
        if (settings.Notify_Users__c && (syncLog.Status__c == 'Failed' || syncLog.Status__c == 'Partial')) {
            sendErrorNotification(userId, syncLog);
        }
    }
    
    /**
     * Process sync for user using token-based fetching
     */
    private static void processSyncForUserWithToken(
        Id userId,
        TokenBasedProviderContext ctx,
        String userEmail,
        DateTime syncWindowStart,
        DateTime syncWindowEnd,
        AI_Workspace_Sync_Log__c syncLog
    ) {
        // Fetch emails from BOTH inbox and sent folders using token-based fetch services
        List<Map<String, Object>> fetchedEmails = new List<Map<String, Object>>();
        
        // Define folders to sync based on provider type
        List<FolderConfig> foldersToSync = getFoldersToSync(ctx.providerType);
        
        // Track folder-level errors for granular reporting
        List<String> folderErrors = new List<String>();
        List<String> foldersSucceeded = new List<String>();
        
        // CRITICAL FIX: For Gmail, fetch from BOTH folders with a high limit, then merge and sort by date
        // This ensures we don't lose emails due to arbitrary folder limits
        // We'll fetch more than needed, merge, sort by date, and trim to the actual limit
        Integer maxEmails = (Integer) settings.Max_Emails_Per_User__c;
        
        // For Gmail: Fetch generously from both folders (2x the limit to ensure we get all emails in the time window)
        // For Outlook: Keep the old behavior (split limit between folders)
        Integer fetchLimit = ctx.provider == 'Gmail' ? (maxEmails * 2) : ((maxEmails + 1) / 2);
        
        for (FolderConfig folderConfig : foldersToSync) {
            try {
                List<Map<String, Object>> folderEmails;
                
                if (ctx.provider == 'Outlook') {
                    // Outlook: Use split limits (old behavior)
                    Boolean isInbox = (folderConfig.folderName == 'inbox');
                    Integer folderLimit = isInbox ? ((maxEmails + 1) / 2) : (maxEmails / 2);
                    
                    if (folderConfig.folderName == 'inbox') {
                        folderEmails = AIOutlookFetchService.fetchInboxEmails(
                            ctx.accessToken, syncWindowStart, syncWindowEnd, folderLimit
                        );
                    } else {
                        folderEmails = AIOutlookFetchService.fetchSentEmails(
                            ctx.accessToken, syncWindowStart, syncWindowEnd, folderLimit
                        );
                    }
                } else {
                    // Gmail: Fetch generously from both folders
                    if (folderConfig.folderName == 'INBOX') {
                        folderEmails = AIGmailFetchService.fetchInboxEmails(
                            ctx.accessToken, syncWindowStart, syncWindowEnd, fetchLimit
                        );
                    } else {
                        folderEmails = AIGmailFetchService.fetchSentEmails(
                            ctx.accessToken, syncWindowStart, syncWindowEnd, fetchLimit
                        );
                    }
                    
                    // Transform Gmail emails to Graph format for compatibility
                    List<Map<String, Object>> transformedEmails = new List<Map<String, Object>>();
                    for (Map<String, Object> email : folderEmails) {
                        transformedEmails.add(AIGmailEmailTransformer.transformToGraphFormat(email));
                    }
                    folderEmails = transformedEmails;
                }
                
                if (folderEmails != null) {
                    fetchedEmails.addAll(folderEmails);
                }
                foldersSucceeded.add(folderConfig.folderName);
            } catch (Exception e) {
                String errorMsg = 'Failed to fetch from ' + folderConfig.folderName + ': ' + e.getMessage();
                folderErrors.add(errorMsg);
            }
        }
        
        // CRITICAL FIX: For Gmail, sort all fetched emails by date and trim to the limit
        // This ensures we sync emails in chronological order regardless of folder
        if (ctx.provider == 'Gmail' && fetchedEmails.size() > maxEmails) {
            fetchedEmails = sortAndTrimEmailsByDate(fetchedEmails, maxEmails);
        }
        
        // CRITICAL FIX: For Gmail, sort all fetched emails by date and trim to the limit
        // This ensures we sync emails in chronological order regardless of folder
        if (ctx.provider == 'Gmail' && fetchedEmails.size() > maxEmails) {
            fetchedEmails = sortAndTrimEmailsByDate(fetchedEmails, maxEmails);
        }
        
        // If ANY folder failed, mark sync as Partial
        if (!folderErrors.isEmpty()) {
            String existingErrors = syncLog.Error_Message__c != null ? syncLog.Error_Message__c + '\n' : '';
            syncLog.Error_Message__c = existingErrors + String.join(folderErrors, '\n');
            
            if (!fetchedEmails.isEmpty() || !foldersSucceeded.isEmpty()) {
                syncLog.Status__c = 'Partial';
            }
        }
        
        syncLog.Emails_Fetched__c = fetchedEmails.size();
        
        if (fetchedEmails.isEmpty()) {
            syncLog.Emails_Imported__c = 0;
            return;
        }
        
        // Update Sync_Window_End__c to the date of the newest email fetched
        // This ensures the next sync starts from where we left off (not when the sync ran)
        // IMPORTANT: This fixes the issue where emails are skipped when batch limit is reached
        DateTime newestEmailDate = findNewestEmailDate(fetchedEmails);
        if (newestEmailDate != null) {
            syncLog.Sync_Window_End__c = newestEmailDate;
        }
        
        // Step 1: Deduplicate - remove already-imported emails
        DeduplicationResult dedupeResult = deduplicateEmails(fetchedEmails);
        syncLog.Emails_Duplicate__c = dedupeResult.duplicateCount;
        
        if (dedupeResult.newEmails.isEmpty()) {
            syncLog.Emails_Imported__c = 0;
            return;
        }
        
        // Step 2: Apply exclusion filters (V2-7889: New filtering service)
        String excludedDomains = AISyncSettingsService.getExcludedDomains();
        String excludedLabels = AISyncSettingsService.getExcludedLabelsCategories();
        
        AIWorkspaceFilterService.FilterResult filterResult =
            AIWorkspaceFilterService.applyAllFilters(
                dedupeResult.newEmails, 
                excludedDomains, 
                excludedLabels, 
                'Email', 
                ctx.provider
            );
        
        syncLog.Emails_Excluded__c = filterResult.excludedCount;
        syncLog.Exclusion_Summary__c = 'Excluded by domain: ' + filterResult.exclusionReasons.get('domain') + 
                                        ', by label: ' + filterResult.exclusionReasons.get('label');
        
        if (filterResult.includedRecords.isEmpty()) {
            syncLog.Emails_Imported__c = 0;
            return;
        }
        
        // Step 3: Fetch full email details (including body)
        List<Map<String, Object>> fullEmails = fetchFullEmailDetailsWithToken(
            filterResult.includedRecords, ctx.provider, ctx.accessToken
        );
        
        if (fullEmails.isEmpty()) {
            syncLog.Emails_Matched__c = 0;
            syncLog.Emails_Unmatched__c = 0;
            syncLog.Emails_Imported__c = 0;
            return;
        }
        
        // Step 4: Create staging records for ALL emails and match them
        // The staging creator now performs inline matching and returns accurate counts
        AIWorkspaceStagingCreator.StagingResult stagingResult =
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                fullEmails,
                ctx.providerType,
                userEmail,
                syncLog.Id,
                userId,
                false // Don't send notifications for auto-sync
            );
        
        Integer failedCount = stagingResult.failedCount;
        List<String> importErrors = stagingResult.errors;
        
        // Use the actual counts from the staging result
        // matchedCount = staging records that matched to Lead/Contact
        // unmatchedCount = staging records that didn't match any Lead/Contact
        // importedCount = actual EmailMessage records created in Salesforce
        // V2-7889: Add staging-level duplicates to the sync log duplicate count
        syncLog.Emails_Duplicate__c += stagingResult.duplicateCount;
        syncLog.Emails_Matched__c = stagingResult.matchedCount;
        syncLog.Emails_Unmatched__c = stagingResult.unmatchedCount;
        syncLog.Emails_Imported__c = stagingResult.importedCount;
        
        // Log any import errors
        if (!importErrors.isEmpty()) {
            String existingErrors = syncLog.Error_Message__c != null ? syncLog.Error_Message__c + '\n' : '';
            syncLog.Error_Message__c = existingErrors + String.join(importErrors, '\n');
            
            if (failedCount > 0) {
                syncLog.Status__c = 'Partial';
            }
        }
    }
    
    /**
     * Fetch full email details using token-based services
     */
    private static List<Map<String, Object>> fetchFullEmailDetailsWithToken(
        List<Map<String, Object>> emails,
        String provider,
        String accessToken
    ) {
        if (emails == null || emails.isEmpty()) {
            return new List<Map<String, Object>>();
        }
        
        // Collect message IDs
        List<String> messageIds = new List<String>();
        for (Map<String, Object> email : emails) {
            String emailId = (String) email.get('id');
            if (String.isNotBlank(emailId)) {
                messageIds.add(emailId);
            }
        }
        
        if (messageIds.isEmpty()) {
            return emails;
        }
        
        try {
            List<Map<String, Object>> fullEmails;
            
            if (provider == 'Outlook') {
                fullEmails = AIOutlookFetchService.getEmailDetailsBatch(accessToken, messageIds);
            } else {
                fullEmails = AIGmailFetchService.getEmailDetailsBatch(accessToken, messageIds);
                
                // Transform Gmail emails to Graph format
                List<Map<String, Object>> transformedEmails = new List<Map<String, Object>>();
                for (Map<String, Object> email : fullEmails) {
                    if (email != null) {
                        transformedEmails.add(AIGmailEmailTransformer.transformToGraphFormat(email));
                    } else {
                        transformedEmails.add(null);
                    }
                }
                fullEmails = transformedEmails;
            }
            
            // Filter out nulls and return
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (Integer i = 0; i < fullEmails.size(); i++) {
                Map<String, Object> fullEmail = fullEmails[i];
                if (fullEmail != null) {
                    result.add(fullEmail);
                } else if (i < emails.size()) {
                    result.add(emails[i]);
                }
            }
            return result;
        } catch (Exception e) {
            return emails;
        }
    }

    /**
     * Main entry point - sync emails for one user.
     * Detects ALL authenticated providers and syncs each independently.
     * Creates separate AI_Workspace_Sync_Log__c record for each provider.
     *
     * @param userId The user whose mailbox should be synced
     */
    public static void syncUserEmails(Id userId) {
        loadSettings();

        // Detect ALL providers the user has authenticated with
        List<ProviderContext> authenticatedProviders = detectAllUserProviders(userId);

        if (authenticatedProviders.isEmpty()) {
            // Create a single "Skipped" log entry
            AI_Workspace_Sync_Log__c skipLog = new AI_Workspace_Sync_Log__c(
                User__c = userId,
                Sync_Type__c = 'Scheduled',
                Status__c = 'Skipped',
                Start_Time__c = DateTime.now(),
                End_Time__c = DateTime.now(),
                Error_Message__c = 'No authenticated email provider found'
            );
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ skipLog };
            FLSCheck.getInstance().insertDML(logsToInsert);
            return;
        }

        // Process EACH authenticated provider independently
        for (ProviderContext ctx : authenticatedProviders) {
            syncProviderForUser(userId, ctx);
        }
    }

    /**
     * Sync emails for a specific provider.
     * Creates its own AI_Workspace_Sync_Log__c record.
     */
    private static void syncProviderForUser(Id userId, ProviderContext ctx) {
        DateTime startTime = DateTime.now();

        // Initialize sync log for this provider
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = userId,
            Provider_Type__c = ctx.providerType,
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = startTime
        );

        try {
            // Query last successful sync log for THIS provider to determine start time
            DateTime syncWindowStart = getLastSyncTime(userId, ctx.providerType);
            DateTime syncWindowEnd = DateTime.now();

            syncLog.Sync_Window_Start__c = syncWindowStart;
            syncLog.Sync_Window_End__c = syncWindowEnd;

            // Process sync
            processSyncForUser(userId, ctx, syncWindowStart, syncWindowEnd, syncLog);

            // Mark success if still in progress (no errors)
            if (syncLog.Status__c == 'In Progress') {
                syncLog.Status__c = 'Success';
            }

        } catch (Exception e) {
            syncLog.Status__c = 'Failed';
            syncLog.Error_Message__c = e.getMessage();
        }

        // Finalize sync log
        syncLog.End_Time__c = DateTime.now();
        syncLog.Processing_Time_Seconds__c =
            (syncLog.End_Time__c.getTime() - syncLog.Start_Time__c.getTime()) / 1000.0;

        // Use FLSCheck for security enforcement
        List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ syncLog };
        logsToInsert = FLSCheck.getInstance().insertDML(logsToInsert);
        syncLog = logsToInsert[0];

        // Send failure notification if sync failed (individual email notifications are sent in processSyncForUser)
        if (settings.Notify_Users__c && (syncLog.Status__c == 'Failed' || syncLog.Status__c == 'Partial')) {
            sendErrorNotification(userId, syncLog);
        }
    }

    /**
     * Core processing logic - completely provider-agnostic.
     * Works with any provider that implements AIEmailProviderService.
     * Fetches from BOTH inbox (received) and sentitems (sent) folders.
     */
    /**
     * Processes a batch of raw emails from Microsoft Graph (Delta Sync)
     */
    public static void processDeltaEmails(List<Object> rawEmails, Id userId) {
        if (rawEmails == null || rawEmails.isEmpty()) return;

        // Convert List<Object> to List<Map<String, Object>>
        List<Map<String, Object>> fetchedEmails = new List<Map<String, Object>>();
        for (Object obj : rawEmails) {
            fetchedEmails.add((Map<String, Object>) obj);
        }

        // IMPORTANT: Get provider and make any callouts BEFORE any DML operations
        // Salesforce doesn't allow callouts after uncommitted DML
        loadSettings();
        AIEmailProviderService provider = AIEmailProviderFactory.getProvider('MICROSOFT_EMAIL');
        String userEmail = provider.getUserEmail();

        // Initialize a sync log for this delta batch
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = userId,
            Provider_Type__c = 'MICROSOFT_EMAIL', // Use specific email provider type
            Record_Type__c = 'Email',
            Sync_Type__c = 'Delta',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        
        // Use FLSCheck for security enforcement
        List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ syncLog };
        logsToInsert = FLSCheck.getInstance().insertDML(logsToInsert);
        syncLog = logsToInsert[0];

        try {
            syncLog.Emails_Fetched__c = fetchedEmails.size();

            // Deduplicate
            DeduplicationResult dedupeResult = deduplicateEmails(fetchedEmails);
            syncLog.Emails_Duplicate__c = dedupeResult.duplicateCount;

            if (!dedupeResult.newEmails.isEmpty()) {

                // Exclude (V2-7889: New filtering service)
                String excludedDomains = AISyncSettingsService.getExcludedDomains();
                String excludedLabels = AISyncSettingsService.getExcludedLabelsCategories();
                
        AIWorkspaceFilterService.FilterResult filterResult =
            AIWorkspaceFilterService.applyAllFilters(
                dedupeResult.newEmails,
                excludedDomains,
                excludedLabels,
                'Email',
                'MICROSOFT_EMAIL'
            );
                
                syncLog.Emails_Excluded__c = filterResult.excludedCount;
                
                if (!filterResult.includedRecords.isEmpty()) {
                    // Fetch full email details
                    List<Map<String, Object>> fullEmails = fetchFullEmailDetails(filterResult.includedRecords, provider);

                    if (!fullEmails.isEmpty()) {
                        // Create staging records and match them
                        AIWorkspaceStagingCreator.StagingResult stagingResult =
                            AIWorkspaceStagingCreator.createEmailStagingRecords(
                                fullEmails,
                                'MICROSOFT_EMAIL',
                                userEmail,
                                syncLog.Id,
                                userId,
                                false // Don't send notifications for auto-sync
                            );
                        
                        // Use actual counts from staging result
                        // V2-7889: Add staging-level duplicates to the sync log duplicate count
                        syncLog.Emails_Duplicate__c += stagingResult.duplicateCount;
                        syncLog.Emails_Matched__c = stagingResult.matchedCount;
                        syncLog.Emails_Unmatched__c = stagingResult.unmatchedCount;
                        syncLog.Emails_Imported__c = stagingResult.importedCount;
                    }
                }
            }
            
            syncLog.Status__c = 'Success';

        } catch (Exception e) {
            syncLog.Status__c = 'Failed';
            syncLog.Error_Message__c = e.getMessage();
        } finally {
            syncLog.End_Time__c = DateTime.now();
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Log__c> logsToUpdate = new List<AI_Workspace_Sync_Log__c>{ syncLog };
            FLSCheck.getInstance().updateDML(logsToUpdate);
        }
    }

    private static void processSyncForUser(
        Id userId,
        ProviderContext ctx,
        DateTime syncWindowStart,
        DateTime syncWindowEnd,
        AI_Workspace_Sync_Log__c syncLog
    ) {
        // Fetch emails from BOTH inbox and sent folders
        List<Map<String, Object>> fetchedEmails = new List<Map<String, Object>>();

        // Define folders to sync based on provider type
        List<FolderConfig> foldersToSync = getFoldersToSync(ctx.providerType);

        // Track folder-level errors for granular reporting
        List<String> folderErrors = new List<String>();
        List<String> foldersSucceeded = new List<String>();

        // Calculate emails per folder with priority to Inbox
        // If Max_Emails_Per_User__c is odd, Inbox gets the extra email
        // Example: 15 emails -> 8 inbox + 7 sent
        Integer maxEmails = (Integer) settings.Max_Emails_Per_User__c;
        Integer inboxLimit = (maxEmails + 1) / 2;  // Rounds up for odd numbers
        Integer sentLimit = maxEmails / 2;          // Rounds down for odd numbers

        for (FolderConfig folderConfig : foldersToSync) {
            AIEmailProviderService.EmailProviderRequest request = new AIEmailProviderService.EmailProviderRequest();
            // Apply folder-specific limit (inbox gets priority for odd numbers)
            Boolean isInbox = (folderConfig.folderName == 'inbox' || folderConfig.folderName == 'INBOX');
            request.recordLimit = isInbox ? inboxLimit : sentLimit;
            request.folder = folderConfig.folderName;

            // Build date filter based on provider type and folder
            String dateFilter = buildDateFilter(ctx.providerType, syncWindowStart, syncWindowEnd, folderConfig.dateField);
            request.filterCriteria = dateFilter;

            try {
                AIEmailProviderService.EmailProviderResponse response = ctx.provider.getEmails(request);
                if (response.emails != null) {
                    fetchedEmails.addAll(response.emails);
                }
                foldersSucceeded.add(folderConfig.folderName);
            } catch (Exception e) {
                String errorMsg = 'Failed to fetch from ' + folderConfig.folderName + ': ' + e.getMessage();
                folderErrors.add(errorMsg);
                // Continue with other folders but track the error
            }
        }

        // If ANY folder failed, mark sync as Partial (not complete failure)
        // This ensures users know some data may be missing
        if (!folderErrors.isEmpty()) {
            String existingErrors = syncLog.Error_Message__c != null ? syncLog.Error_Message__c + '\n' : '';
            syncLog.Error_Message__c = existingErrors + String.join(folderErrors, '\n');

            // Only mark as Partial if we got SOME emails (otherwise it's truly Failed)
            if (!fetchedEmails.isEmpty() || !foldersSucceeded.isEmpty()) {
                syncLog.Status__c = 'Partial';
            }
        }

        syncLog.Emails_Fetched__c = fetchedEmails.size();

        if (fetchedEmails.isEmpty()) {
            syncLog.Emails_Imported__c = 0;
            return;
        }
        
        // Update Sync_Window_End__c to the date of the newest email fetched
        // This ensures the next sync starts from where we left off (not when the sync ran)
        DateTime newestEmailDate = findNewestEmailDate(fetchedEmails);
        if (newestEmailDate != null) {
            syncLog.Sync_Window_End__c = newestEmailDate;
        }

        // Get user's email for exclusion checks
        String userEmail = ctx.provider.getUserEmail();

        // Step 1: Deduplicate - remove already-imported emails
        DeduplicationResult dedupeResult = deduplicateEmails(fetchedEmails);
        syncLog.Emails_Duplicate__c = dedupeResult.duplicateCount;

        if (dedupeResult.newEmails.isEmpty()) {
            syncLog.Emails_Imported__c = 0;
            return;
        }

        // Step 2: Apply exclusion filters (V2-7889: New filtering service)
        String excludedDomains = AISyncSettingsService.getExcludedDomains();
        String excludedLabels = AISyncSettingsService.getExcludedLabelsCategories();
        
        AIWorkspaceFilterService.FilterResult filterResult =
            AIWorkspaceFilterService.applyAllFilters(
                dedupeResult.newEmails, 
                excludedDomains, 
                excludedLabels, 
                'Email', 
                ctx.providerType
            );

        syncLog.Emails_Excluded__c = filterResult.excludedCount;
        syncLog.Exclusion_Summary__c = 'Excluded by domain: ' + filterResult.exclusionReasons.get('domain') + 
                                        ', by label: ' + filterResult.exclusionReasons.get('label');

        if (filterResult.includedRecords.isEmpty()) {
            syncLog.Emails_Imported__c = 0;
            return;
        }

        // Step 3: Fetch full email details (including body)
        List<Map<String, Object>> fullEmails = fetchFullEmailDetails(filterResult.includedRecords, ctx.provider);

        if (fullEmails.isEmpty()) {
            syncLog.Emails_Matched__c = 0;
            syncLog.Emails_Unmatched__c = 0;
            syncLog.Emails_Imported__c = 0;
            return;
        }

        // Step 4: Create staging records and match them
        // The staging creator performs inline matching and returns accurate counts
        AIWorkspaceStagingCreator.StagingResult stagingResult =
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                fullEmails,
                ctx.providerType,
                userEmail,
                syncLog.Id,
                userId,
                false // Don't send notifications for auto-sync
            );

        Integer failedCount = stagingResult.failedCount;
        List<String> importErrors = stagingResult.errors;
        List<Id> createdRecordIds = stagingResult.stagingRecordIds;

        // Use actual counts from staging result
        // V2-7889: Add staging-level duplicates to the sync log duplicate count
        syncLog.Emails_Duplicate__c += stagingResult.duplicateCount;
        syncLog.Emails_Matched__c = stagingResult.matchedCount;
        syncLog.Emails_Unmatched__c = stagingResult.unmatchedCount;
        syncLog.Emails_Imported__c = stagingResult.importedCount;

        // Log any import errors
        if (!importErrors.isEmpty()) {
            String existingErrors = syncLog.Error_Message__c != null ? syncLog.Error_Message__c + '\n' : '';
            syncLog.Error_Message__c = existingErrors + String.join(importErrors, '\n');

            if (failedCount > 0) {
                syncLog.Status__c = 'Partial';
            }
        }
    }

    /**
     * Get the last successful sync time for a user + provider combination.
     * Queries AI_Workspace_Sync_Log__c to find where we left off.
     *
     * NOTE: Sync_Window_End__c now stores the date of the newest email that was actually
     * fetched (not when the sync ran). This ensures that if the batch limit is reached 
     * before all emails are processed, the next sync will pick up where we left off
     * instead of skipping emails.
     *
     * @param userId The user being synced
     * @param providerType The provider type stored in sync logs (e.g., MICROSOFT_EMAIL, GMAIL_EMAIL)
     * @return DateTime of last synced email, or default lookback if no prior sync
     */
    private static DateTime getLastSyncTime(Id userId, String providerType) {
        List<AI_Workspace_Sync_Log__c> lastLogs = [
            SELECT Id, End_Time__c, Sync_Window_End__c
            FROM AI_Workspace_Sync_Log__c
            WHERE User__c = :userId
              AND Provider_Type__c = :providerType
              AND Status__c IN ('Success', 'Partial')
            WITH USER_MODE
            ORDER BY End_Time__c DESC
            LIMIT 1
        ];

        if (!lastLogs.isEmpty() && lastLogs[0].Sync_Window_End__c != null) {
            // Use Sync_Window_End__c which now contains the date of the newest email fetched
            return lastLogs[0].Sync_Window_End__c;
        }

        // No prior successful sync - use default lookback
        return DateTime.now().addHours(-((Integer) settings.Lookback_Hours__c));
    }
    
    /**
     * Find the newest email date from a list of fetched emails.
     * Used to determine the checkpoint for the next sync run.
     *
     * @param emails List of email data maps
     * @return DateTime of the newest email, or null if no valid dates found
     */
    private static DateTime findNewestEmailDate(List<Map<String, Object>> emails) {
        DateTime newestDate = null;
        
        for (Map<String, Object> email : emails) {
            // Try receivedDateTime first (for inbox), then sentDateTime (for sent)
            String dateStr = (String) email.get('receivedDateTime');
            if (String.isBlank(dateStr)) {
                dateStr = (String) email.get('sentDateTime');
            }
            
            if (String.isNotBlank(dateStr)) {
                try {
                    // Parse ISO 8601 date format (e.g., "2026-01-12T03:50:49Z")
                    DateTime emailDate = parseISODateTime(dateStr);
                    if (emailDate != null && (newestDate == null || emailDate > newestDate)) {
                        newestDate = emailDate;
                    }
                } catch (Exception e) {
                    // Ignore
                }
            }
        }
        
        return newestDate;
    }
    
    /**
     * Parse an ISO 8601 date string to DateTime.
     * Handles formats like "2026-01-12T03:50:49Z" and "2026-01-12T03:50:49.000Z"
     */
    private static DateTime parseISODateTime(String isoString) {
        if (String.isBlank(isoString)) {
            return null;
        }
        
        try {
            // Remove the 'Z' suffix and milliseconds if present
            String cleanStr = isoString.replace('Z', '').replace('+00:00', '');
            
            // Handle milliseconds
            if (cleanStr.contains('.')) {
                cleanStr = cleanStr.substringBefore('.');
            }
            
            // Parse: yyyy-MM-ddTHH:mm:ss
            List<String> parts = cleanStr.split('T');
            if (parts.size() != 2) return null;
            
            List<String> dateParts = parts[0].split('-');
            List<String> timeParts = parts[1].split(':');
            
            if (dateParts.size() != 3 || timeParts.size() < 2) return null;
            
            Integer year = Integer.valueOf(dateParts[0]);
            Integer month = Integer.valueOf(dateParts[1]);
            Integer day = Integer.valueOf(dateParts[2]);
            Integer hour = Integer.valueOf(timeParts[0]);
            Integer minute = Integer.valueOf(timeParts[1]);
            Integer second = timeParts.size() > 2 ? Integer.valueOf(timeParts[2]) : 0;
            
            return DateTime.newInstanceGmt(year, month, day, hour, minute, second);
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Sort emails by date (oldest first) and trim to the specified maximum count.
     * This ensures we sync emails in chronological order across all folders.
     * CRITICAL for Gmail to prevent losing emails when sync window advances.
     * 
     * @param emails List of email data maps
     * @param maxCount Maximum number of emails to return
     * @return Sorted and trimmed list of emails
     */
    private static List<Map<String, Object>> sortAndTrimEmailsByDate(List<Map<String, Object>> emails, Integer maxCount) {
        if (emails == null || emails.isEmpty()) {
            return emails;
        }
        
        // Create a wrapper class for sorting
        List<EmailWithDate> emailsWithDates = new List<EmailWithDate>();
        
        for (Map<String, Object> email : emails) {
            DateTime emailDate = null;
            
            // Try receivedDateTime first (for inbox), then sentDateTime (for sent), then internalDate (Gmail)
            String dateStr = (String) email.get('receivedDateTime');
            if (String.isBlank(dateStr)) {
                dateStr = (String) email.get('sentDateTime');
            }
            
            if (String.isNotBlank(dateStr)) {
                emailDate = parseISODateTime(dateStr);
            }
            
            // Fallback to internalDate for Gmail
            if (emailDate == null) {
                Object internalDateObj = email.get('internalDate');
                if (internalDateObj != null) {
                    try {
                        Long internalDateMs;
                        if (internalDateObj instanceof Long) {
                            internalDateMs = (Long) internalDateObj;
                        } else {
                            internalDateMs = Long.valueOf(String.valueOf(internalDateObj));
                        }
                        emailDate = DateTime.newInstance(internalDateMs);
                    } catch (Exception e) {
                        // Use current time as fallback
                        emailDate = DateTime.now();
                    }
                }
            }
            
            // If still no date, use current time
            if (emailDate == null) {
                emailDate = DateTime.now();
            }
            
            emailsWithDates.add(new EmailWithDate(email, emailDate));
        }
        
        // Sort by date (oldest first)
        emailsWithDates.sort();
        
        // Trim to maxCount and extract emails
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        Integer itemsToTake = Math.min(maxCount, emailsWithDates.size());
        for (Integer idx = 0; idx < itemsToTake; idx++) {
            result.add(emailsWithDates[idx].email);
        }
        
        return result;
    }
    
    /**
     * Wrapper class for sorting emails by date
     */
    private class EmailWithDate implements Comparable {
        public Map<String, Object> email;
        public DateTime emailDate;
        
        public EmailWithDate(Map<String, Object> email, DateTime emailDate) {
            this.email = email;
            this.emailDate = emailDate;
        }
        
        public Integer compareTo(Object other) {
            EmailWithDate otherEmail = (EmailWithDate) other;
            
            if (this.emailDate == otherEmail.emailDate) {
                return 0;
            }
            
            // Sort oldest first (ascending order)
            return this.emailDate < otherEmail.emailDate ? -1 : 1;
        }
    }

    /**
     * Wrapper class for provider context
     */
    private class ProviderContext {
        public AIEmailProviderService provider { get; set; }
        public String providerType { get; set; }

        public ProviderContext(AIEmailProviderService provider, String providerType) {
            this.provider = provider;
            this.providerType = providerType;
        }
    }

    /**
     * Detect ALL providers the user has authenticated with.
     * Returns list of all authenticated providers (could be multiple).
     * 
     * Uses AI_Workspace_User__c to check which providers the user has connected,
     * combined with AI_Workspace_Sync_Settings__c to check which providers are enabled.
     *
     * @param userId The user to check authentication for
     */
    private static List<ProviderContext> detectAllUserProviders(Id userId) {
        List<ProviderContext> authenticatedProviders = new List<ProviderContext>();
        
        // Get providers that are both authenticated by user AND enabled in settings
        List<String> activeProviderTypes = AIEmailProviderFactory.getActiveAuthenticatedProviders(userId);

        for (String providerType : activeProviderTypes) {
            try {
                AIEmailProviderService provider = AIEmailProviderFactory.getProvider(providerType);

                // Double-check authentication via provider service
                if (provider.isAuthenticated()) {
                    // Map provider type to sync type (Outlook -> MICROSOFT_EMAIL, Gmail -> GMAIL_EMAIL)
                    String syncProviderType = providerType == 'Outlook' ? 'MICROSOFT_EMAIL' : 'GMAIL_EMAIL';
                    authenticatedProviders.add(new ProviderContext(provider, syncProviderType));
                }
            } catch (Exception e) {
                // Provider not configured or error - try next
            }
        }

        return authenticatedProviders;
    }

    /**
     * Folder configuration for syncing
     */
    private class FolderConfig {
        public String folderName { get; set; }
        public String dateField { get; set; }

        public FolderConfig(String folderName, String dateField) {
            this.folderName = folderName;
            this.dateField = dateField;
        }
    }

    /**
     * Get list of folders to sync based on provider type
     */
    private static List<FolderConfig> getFoldersToSync(String providerType) {
        List<FolderConfig> folders = new List<FolderConfig>();

        if (providerType == 'MICROSOFT_EMAIL') {
            // Inbox uses receivedDateTime, Sent uses sentDateTime
            folders.add(new FolderConfig('inbox', 'receivedDateTime'));
            folders.add(new FolderConfig('sentitems', 'sentDateTime'));
        } else if (providerType == 'GMAIL_EMAIL') {
            // Gmail uses labels instead of folders
            folders.add(new FolderConfig('INBOX', 'internalDate'));
            folders.add(new FolderConfig('SENT', 'internalDate'));
        }

        return folders;
    }

    /**
     * Build date filter string based on provider type and date field
     */
    private static String buildDateFilter(String providerType, DateTime startDate, DateTime endDate, String dateField) {
        if (providerType == 'MICROSOFT_EMAIL') {
            // OData filter format for Microsoft Graph
            String startStr = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            return dateField + ' ge ' + startStr + ' and ' + dateField + ' le ' + endStr;
        } else if (providerType == 'GMAIL_EMAIL') {
            // Gmail search query format
            // IMPORTANT: Gmail's after: and before: operators are EXCLUSIVE (not inclusive)
            // To ensure we capture all emails in the range, subtract 1 second from start and add 1 second to end
            Long startEpoch = (startDate.getTime() / 1000) - 1;
            Long endEpoch = (endDate.getTime() / 1000) + 1;
            return 'after:' + startEpoch + ' before:' + endEpoch;
        }
        return null;
    }

    /**
     * Deduplication result wrapper
     */
    public class DeduplicationResult {
        public List<Map<String, Object>> newEmails { get; set; }
        public Integer duplicateCount { get; set; }

        public DeduplicationResult() {
            this.newEmails = new List<Map<String, Object>>();
            this.duplicateCount = 0;
        }
    }

    /**
     * Remove emails that have already been imported
     */
    public static DeduplicationResult deduplicateEmails(List<Map<String, Object>> emails) {
        DeduplicationResult result = new DeduplicationResult();

        // Collect message IDs
        Set<String> messageIds = new Set<String>();
        for (Map<String, Object> email : emails) {
            String msgId = (String) email.get('internetMessageId');
            if (String.isNotBlank(msgId)) {
                messageIds.add(msgId);
            }
        }

        // Query existing EmailMessages
        Set<String> existingMessageIds = new Set<String>();
        if (!messageIds.isEmpty()) {
            for (EmailMessage em : [
                SELECT MessageIdentifier
                FROM EmailMessage
                WHERE MessageIdentifier IN :messageIds
                WITH USER_MODE
            ]) {
                if (String.isNotBlank(em.MessageIdentifier)) {
                    existingMessageIds.add(em.MessageIdentifier);
                }
            }
        }

        // Filter out duplicates
        for (Map<String, Object> email : emails) {
            String msgId = (String) email.get('internetMessageId');
            if (String.isBlank(msgId) || !existingMessageIds.contains(msgId)) {
                result.newEmails.add(email);
            } else {
                result.duplicateCount++;
            }
        }

        return result;
    }

    /**
     * Fetch full email details (including body) for emails to import.
     * The list view API excludes body for performance.
     * OPTIMIZED: Uses batch API to reduce callouts from N to ceil(N/20).
     *
     * @param emails List of email data (with 'id' field)
     * @param provider The email provider to use for fetching
     * @return List of full email data including body content
     */
    private static List<Map<String, Object>> fetchFullEmailDetails(
        List<Map<String, Object>> emails,
        AIEmailProviderService provider
    ) {
        List<Map<String, Object>> fullEmails = new List<Map<String, Object>>();

        if (emails == null || emails.isEmpty()) {
            return fullEmails;
        }

        // Collect all message IDs
        List<String> messageIds = new List<String>();
        Map<Integer, Map<String, Object>> originalEmailsByIndex = new Map<Integer, Map<String, Object>>();

        for (Integer i = 0; i < emails.size(); i++) {
            Map<String, Object> email = emails[i];
            String emailId = (String) email.get('id');
            if (String.isNotBlank(emailId)) {
                messageIds.add(emailId);
                originalEmailsByIndex.put(i, email);
            }
        }

        if (messageIds.isEmpty()) {
            return emails; // Return originals if no IDs found
        }

        try {
            // Use batch API to fetch all emails efficiently
            List<Map<String, Object>> batchResults = provider.getEmailsBatch(messageIds);

            // Process results, falling back to original data if batch fetch failed
            for (Integer i = 0; i < batchResults.size(); i++) {
                Map<String, Object> fullEmail = batchResults[i];
                if (fullEmail != null) {
                    fullEmails.add(fullEmail);
                } else {
                    // Fallback to original data (no body)
                    Map<String, Object> original = originalEmailsByIndex.get(i);
                    fullEmails.add(original != null ? original : new Map<String, Object>());
                }
            }
        } catch (Exception e) {
            fullEmails.addAll(emails);
        }

        return fullEmails;
    }

    // Method removed: updateEmailsWithSyncLog
    // Custom fields on EmailMessage are no longer used.
    // All metadata is stored on AI_Workspace_Staging__c which has a lookup to EmailMessage.

    /**
     * Send notification for sync errors/failures
     */
    private static void sendErrorNotification(Id userId, AI_Workspace_Sync_Log__c syncLog) {
        try {
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];

            if (notifTypes.isEmpty()) {
                return;
            }

            Messaging.CustomNotification notification = new Messaging.CustomNotification();

            String title = syncLog.Status__c == 'Failed' ? '❌ Email Sync Failed' : '⚠️ Email Sync Partial';
            String body = syncLog.Status__c == 'Failed'
                ? 'Sync from ' + syncLog.Provider_Type__c + ' failed. Check sync logs.'
                : syncLog.Emails_Imported__c + ' emails synced (some errors occurred)';

            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(notifTypes[0].Id);
            notification.setTargetId(syncLog.Id);

            notification.send(new Set<String>{ userId });
        } catch (Exception e) {
            // Ignore
        }
    }

    /**
     * Load settings from Custom Metadata
     */
    private static void loadSettings() {
        if (settings == null) {
            settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            if (settings == null) {
                throw new EmailSyncException('AI_Workspace_Sync_Settings__c.Default not configured');
            }
        }
    }

    /**
     * Custom exception for sync errors
     */
    public class EmailSyncException extends Exception {}
}