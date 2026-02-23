/**
 * AIEmailSyncChainableQueueable - Limit-Aware Continuous Email Sync Engine
 * 
 * This queueable fetches emails in batches using a multi-phase approach:
 * Phase 1: Refresh token (to ensure fresh token for long-running chains)
 * Phase 2: Fetch as many batches as possible (callouts)
 * Phase 3: Process all fetched emails (DML)
 * Then chain to continue if more emails exist AND max limit not reached.
 * 
 * Key Features:
 * - Token refresh at START of each execution (handles hour+ sync processes)
 * - Two-phase design avoids DML-before-callout issues
 * - Respects Max_Emails_Per_User__c limit
 * - Uses Transaction Finalizer to chain without depth limits
 * - Sets correct owner on imported records (targetUserId)
 * 
 * Gmail FIFO Strategy (Two-Phase Sync):
 * =====================================
 * Gmail API returns emails newest-first with NO way to change ordering.
 * To achieve true FIFO (always get new emails first), we use two phases:
 * 
 * 1. FORWARD SYNC (catch new emails) - ALWAYS runs first:
 *    - Fetches from gmailForwardCursor (newest we've seen) to NOW
 *    - Updates gmailForwardCursor with newest email in batch
 *    - This ensures NEW emails are NEVER missed
 * 
 * 2. BACKFILL SYNC (fill historical window) - runs after forward:
 *    - Fetches from oldest processed backwards to lookback boundary
 *    - Updates Sync_Window_End__c with oldest email in batch
 *    - Once reached lookback boundary, sets gmailBackfillComplete = true
 * 
 * Outlook Strategy:
 * =================
 * Outlook API supports oldest-first ordering, so standard FIFO works naturally.
 * 
 * Token Refresh Strategy:
 * - Each queueable execution refreshes the token FIRST
 * - This ensures fresh 1-hour token for each execution
 * - Token refresh callout + DML happens before email fetch callouts
 * - If refresh fails, stops chain and marks sync as failed
 * 
 * @author GPTfy
 * @date 2026-01-19
 * @Jira V2-7695, V2-7696, V2-7796
 */
public class AIEmailSyncChainableQueueable implements Queueable, Database.AllowsCallouts, Finalizer {
    
    // Limit reserves - calculated for worst case scenario:
    // - Token refresh: 1 callout
    // - Gmail batch with 20 emails needs: 1 (list) + 1 (batch fetch) = 2 callouts per batch
    // - Outlook batch needs: 1 callout (single call includes body)
    // - With MAX_BATCHES_PER_EXECUTION=4, that's 1 + (4 * 2) = 9 callouts max per execution
    // - Reserve should be enough for at least one more batch operation
    private static final Integer RESERVE_CALLOUTS = 10;
    private static final Integer CALLOUTS_PER_GMAIL_BATCH = 2; // 1 list + 1 batch fetch (batch API)
    private static final Integer CALLOUTS_PER_OUTLOOK_BATCH = 1; // Single call includes body
    private static final Integer MAX_ERROR_LENGTH = 32000;
    private static final Integer MAX_BATCHES_PER_EXECUTION = 4; // Fetch up to 4 batches per run
    
    // State passed between chained jobs
    private Id syncLogId;
    private Id workspaceUserId;
    private Id targetUserId; // The Salesforce User ID who owns the workspace - records should belong to this user
    private String accessToken; // Initial token (will be refreshed at start of each execution)
    private String provider;
    private DateTime inboxCursor;
    private DateTime sentCursor;
    private DateTime syncWindowStart; // Lookback boundary for backfill
    private DateTime syncWindowEnd;   // Backfill cursor (oldest email processed)
    private Boolean inboxComplete;
    private Boolean sentComplete;
    private Boolean isLastFolderInbox;
    private String userEmail;
    
    // Gmail FIFO: Two-phase sync state
    // Forward sync: catches NEW emails (gmailForwardCursor -> NOW)
    private DateTime gmailForwardCursor;         // Newest email datetime we've seen
    private Boolean gmailForwardInboxComplete;   // Forward sync done for inbox
    private Boolean gmailForwardSentComplete;    // Forward sync done for sent
    // Backfill sync: fills historical window (oldest processed -> lookback boundary)
    private Boolean gmailBackfillComplete;       // Backfill has reached lookback boundary
    
    // Gmail-specific: pageToken for pagination (Gmail returns newest first, must use pageToken)
    private String gmailInboxPageToken;
    private String gmailSentPageToken;
    // Separate page tokens for forward sync
    private String gmailForwardInboxPageToken;
    private String gmailForwardSentPageToken;
    
    // Max emails limit from custom metadata
    private Integer maxEmailsLimit;
    
    // Running totals
    private Integer totalFetched;
    private Integer totalDuplicate;
    private Integer totalExcluded;
    private Integer totalMatched;
    private Integer totalUnmatched;
    private Integer totalImported;
    private Integer totalFailed;
    
    // Track exclusion categories
    private Map<String, Integer> aggregatedExclusionCounts;
    
    // Track the newest email date processed (for Sync_Window_End__c for Outlook - oldest first)
    private DateTime newestProcessedEmailDate;
    
    // Track the oldest email date processed (for Sync_Window_End__c for Gmail - newest first)
    private DateTime oldestProcessedEmailDate;
    
    // Flag for finalizer to know if chaining is needed
    private Boolean needsChaining = false;
    
    // Pending token update (deferred to after all callouts)
    private String pendingNewAccessToken;
    private String pendingNewRefreshToken;
    
    // Pending errors (deferred to after all callouts to avoid DML-before-callout)
    private List<String> pendingErrors = new List<String>();
    
    // Test support
    @TestVisible
    private static Boolean disableChaining = false;
    
    /**
     * Constructor for initial sync start
     * @param targetUserId The Salesforce User ID who owns the workspace - imported records will be owned by this user
     */
    public AIEmailSyncChainableQueueable(
        Id syncLogId,
        Id workspaceUserId,
        Id targetUserId,
        String accessToken,
        String provider,
        String userEmail,
        DateTime syncWindowStart,
        DateTime syncWindowEnd
    ) {
        this.syncLogId = syncLogId;
        this.workspaceUserId = workspaceUserId;
        this.targetUserId = targetUserId;
        this.accessToken = accessToken;
        this.provider = provider;
        this.userEmail = userEmail;
        this.inboxCursor = syncWindowStart;
        this.sentCursor = syncWindowStart;
        this.syncWindowStart = syncWindowStart;
        this.syncWindowEnd = syncWindowEnd;
        this.inboxComplete = false;
        this.sentComplete = false;
        this.isLastFolderInbox = false;
        this.totalFetched = 0;
        this.totalDuplicate = 0;
        this.totalExcluded = 0;
        this.totalMatched = 0;
        this.totalUnmatched = 0;
        this.totalImported = 0;
        this.totalFailed = 0;
        this.aggregatedExclusionCounts = new Map<String, Integer>();
        this.newestProcessedEmailDate = syncWindowStart;
        this.oldestProcessedEmailDate = syncWindowEnd; // Initialize to end so any email will be older
        // Gmail pageTokens start as null (first page)
        this.gmailInboxPageToken = null;
        this.gmailSentPageToken = null;
        // Gmail FIFO: Initialize forward sync state from sync log
        // Forward cursor and backfill complete flag are read from sync log in execute()
        this.gmailForwardCursor = null; // Will be loaded from sync log
        this.gmailForwardInboxComplete = false;
        this.gmailForwardSentComplete = false;
        this.gmailBackfillComplete = false;
        this.gmailForwardInboxPageToken = null;
        this.gmailForwardSentPageToken = null;
        // Get max emails limit from custom metadata
        this.maxEmailsLimit = AISyncSettingsService.getMaxEmailsPerUser();
    }
    
    /**
     * Constructor for chained continuation
     */
    public AIEmailSyncChainableQueueable(
        Id syncLogId,
        Id workspaceUserId,
        Id targetUserId,
        String accessToken,
        String provider,
        String userEmail,
        DateTime inboxCursor,
        DateTime sentCursor,
        DateTime syncWindowStart,
        DateTime syncWindowEnd,
        Boolean inboxComplete,
        Boolean sentComplete,
        Boolean isLastFolderInbox,
        Integer totalFetched,
        Integer totalDuplicate,
        Integer totalExcluded,
        Integer totalMatched,
        Integer totalUnmatched,
        Integer totalImported,
        Integer totalFailed,
        Map<String, Integer> aggregatedExclusionCounts,
        DateTime newestProcessedEmailDate,
        DateTime oldestProcessedEmailDate,
        Integer maxEmailsLimit,
        String gmailInboxPageToken,
        String gmailSentPageToken,
        // Gmail FIFO state
        DateTime gmailForwardCursor,
        Boolean gmailForwardInboxComplete,
        Boolean gmailForwardSentComplete,
        Boolean gmailBackfillComplete,
        String gmailForwardInboxPageToken,
        String gmailForwardSentPageToken
    ) {
        this.syncLogId = syncLogId;
        this.workspaceUserId = workspaceUserId;
        this.targetUserId = targetUserId;
        this.accessToken = accessToken;
        this.provider = provider;
        this.userEmail = userEmail;
        this.inboxCursor = inboxCursor;
        this.sentCursor = sentCursor;
        this.syncWindowStart = syncWindowStart;
        this.syncWindowEnd = syncWindowEnd;
        this.inboxComplete = inboxComplete;
        this.sentComplete = sentComplete;
        this.isLastFolderInbox = isLastFolderInbox;
        this.totalFetched = totalFetched;
        this.totalDuplicate = totalDuplicate;
        this.totalExcluded = totalExcluded;
        this.totalMatched = totalMatched;
        this.totalUnmatched = totalUnmatched;
        this.totalImported = totalImported;
        this.totalFailed = totalFailed;
        this.aggregatedExclusionCounts = aggregatedExclusionCounts != null ? aggregatedExclusionCounts : new Map<String, Integer>();
        this.newestProcessedEmailDate = newestProcessedEmailDate;
        this.oldestProcessedEmailDate = oldestProcessedEmailDate;
        this.maxEmailsLimit = maxEmailsLimit;
        this.gmailInboxPageToken = gmailInboxPageToken;
        this.gmailSentPageToken = gmailSentPageToken;
        // Gmail FIFO state
        this.gmailForwardCursor = gmailForwardCursor;
        this.gmailForwardInboxComplete = gmailForwardInboxComplete == true;
        this.gmailForwardSentComplete = gmailForwardSentComplete == true;
        this.gmailBackfillComplete = gmailBackfillComplete == true;
        this.gmailForwardInboxPageToken = gmailForwardInboxPageToken;
        this.gmailForwardSentPageToken = gmailForwardSentPageToken;
    }
    
    /**
     * Main execute method - Multi-Phase Approach
     * 
     * Phase 1: Refresh token (ensures fresh token for this execution)
     * Phase 2: Load Gmail FIFO state from sync log (for Gmail only)
     * Phase 3: Fetch multiple batches (all callouts)
     *          - Gmail: Forward sync first (new emails), then backfill (historical)
     *          - Outlook: Standard FIFO (oldest first via API)
     * Phase 4: Process all fetched emails (all DML)
     * 
     * Token refresh happens FIRST before any email API callouts.
     * The DML to save the new token happens after refresh callout but before email callouts.
     * This is safe because subsequent callouts are to a DIFFERENT endpoint (Graph API / Gmail API).
     */
    public void execute(QueueableContext context) {
        // Attach finalizer to handle chaining without depth limits
        if (!Test.isRunningTest()) {
            System.attachFinalizer(this);
        }
        
        Integer batchSize = AISyncSettingsService.getEmailsPerBatch();
        String providerType = provider == 'Outlook' ? 'MICROSOFT_GRAPH' : 'GMAIL_EMAIL';
        
        try {
            if (isSyncComplete()) {
                finalizeSyncLog('Success');
                return;
            }
            
            // ========== PHASE 1: REFRESH TOKEN ==========
            // Refresh token at the start of EVERY queueable execution
            // This ensures we always have a fresh token (valid for ~1 hour)
            // Critical for long-running sync processes that chain many times
            String freshToken = refreshTokenForExecution();
            if (freshToken == null) {
                // Token refresh failed - cannot continue
                appendError('Token refresh failed. Please re-authenticate.');
                // Flush the error message before finalizing
                flushPendingErrors();
                finalizeSyncLog('Failed');
                return;
            }
            // Update our access token for this execution
            this.accessToken = freshToken;
            
            // ========== PHASE 2: LOAD GMAIL FIFO STATE ==========
            // For Gmail, load the forward cursor and backfill complete flag from sync log
            // This is needed on first execution of the chain (constructor doesn't have this data)
            if (provider == 'Gmail' && gmailForwardCursor == null) {
                loadGmailFifoState();
            }
            
            // ========== PHASE 3: FETCH (Callouts) ==========
            List<FetchedBatch> fetchedBatches = new List<FetchedBatch>();
            Integer batchesFetched = 0;
            
            // Calculate how many more emails we can fetch before hitting the limit
            Integer remainingQuota = maxEmailsLimit - totalFetched;
            
            if (provider == 'Gmail') {
                // Gmail FIFO: Two-phase fetch approach
                // Phase A: Forward Sync (catch new emails from gmailForwardCursor to NOW)
                // Phase B: Backfill Sync (fill historical window from oldest processed to lookback boundary)
                
                // PHASE A: Forward Sync (new emails)
                // Only do forward sync if there's a forward cursor and forward sync isn't complete
                Boolean forwardSyncNeeded = !isGmailForwardSyncComplete();
                if (forwardSyncNeeded && remainingQuota > 0) {
                    while (!isGmailForwardSyncComplete() && hasEnoughCallouts() && batchesFetched < MAX_BATCHES_PER_EXECUTION && remainingQuota > 0) {
                        String folderToProcess = getNextGmailForwardFolder();
                        if (folderToProcess == null) break;
                        
                        Integer effectiveBatchSize = Math.min(batchSize, remainingQuota);
                        FetchedBatch batch = fetchGmailForwardBatch(folderToProcess, effectiveBatchSize, providerType);
                        
                        if (batch != null && !batch.emails.isEmpty()) {
                            fetchedBatches.add(batch);
                            totalFetched += batch.emails.size();
                            remainingQuota -= batch.emails.size();
                            updateGmailForwardCursor(batch.emails);
                        }
                        batchesFetched++;
                    }
                }
                
                // PHASE B: Backfill Sync (historical emails)
                // Only do backfill if forward sync is complete AND backfill is not complete
                if (isGmailForwardSyncComplete() && !gmailBackfillComplete && remainingQuota > 0) {
                    while (!isGmailBackfillComplete() && hasEnoughCallouts() && batchesFetched < MAX_BATCHES_PER_EXECUTION && remainingQuota > 0) {
                        String folderToProcess = getNextFolder();
                        if (folderToProcess == null) break;
                        
                        Integer effectiveBatchSize = Math.min(batchSize, remainingQuota);
                        FetchedBatch batch = fetchGmailBackfillBatch(folderToProcess, effectiveBatchSize, providerType);
                        
                        if (batch != null && !batch.emails.isEmpty()) {
                            fetchedBatches.add(batch);
                            totalFetched += batch.emails.size();
                            remainingQuota -= batch.emails.size();
                            updateNewestProcessedDate(batch.emails);
                        }
                        batchesFetched++;
                    }
                }
            } else {
                // Outlook: Standard FIFO (oldest first via API ordering)
                while (!isSyncComplete() && hasEnoughCallouts() && batchesFetched < MAX_BATCHES_PER_EXECUTION && remainingQuota > 0) {
                    String folderToProcess = getNextFolder();
                    if (folderToProcess == null) break;
                    
                    // Limit batch size to remaining quota
                    Integer effectiveBatchSize = Math.min(batchSize, remainingQuota);
                    
                    FetchedBatch batch = fetchBatch(folderToProcess, effectiveBatchSize, providerType);
                    if (batch != null && !batch.emails.isEmpty()) {
                        fetchedBatches.add(batch);
                        totalFetched += batch.emails.size();
                        remainingQuota -= batch.emails.size();
                        
                        // Track the newest email date from this batch
                        updateNewestProcessedDate(batch.emails);
                    }
                    batchesFetched++;
                }
            }
            
            // ========== PHASE 4: PROCESS (DML) ==========
            // Now that all callouts are complete, we can safely do DML
            
            // First, save the refreshed tokens (deferred from Phase 1)
            if (String.isNotBlank(pendingNewAccessToken)) {
                saveRefreshedTokens(workspaceUserId, pendingNewAccessToken, pendingNewRefreshToken);
                pendingNewAccessToken = null;
                pendingNewRefreshToken = null;
            }
            
            // Flush any pending errors (deferred from Phase 2)
            flushPendingErrors();
            
            // Process fetched emails
            for (FetchedBatch batch : fetchedBatches) {
                processEmails(batch.emails, providerType);
            }
            
            // Update sync log with current totals
            updateSyncLog();
            
            // Determine if we need to chain
            if (isSyncComplete()) {
                finalizeSyncLog('Success');
            } else {
                needsChaining = true;
            }
            
        } catch (Exception e) {
            appendError('Critical error: ' + e.getMessage());
            // Flush the error message before finalizing
            flushPendingErrors();
            finalizeSyncLog('Failed');
        }
    }
    
    /**
     * Load Gmail FIFO state from sync log
     * Called on first execution when constructor doesn't have this data
     */
    private void loadGmailFifoState() {
        try {
            List<AI_Workspace_Sync_Log__c> logs = [
                SELECT Gmail_Forward_Cursor__c, Sync_Window_Start__c, Sync_Window_End__c
                FROM AI_Workspace_Sync_Log__c
                WHERE Id = :syncLogId
                LIMIT 1
            ];
            
            if (!logs.isEmpty()) {
                AI_Workspace_Sync_Log__c log = logs[0];
                gmailForwardCursor = log.Gmail_Forward_Cursor__c;
                
                // If no forward cursor, default to NOW (first sync scenario)
                if (gmailForwardCursor == null) {
                    gmailForwardCursor = DateTime.now();
                }
                
                // Backfill complete check:
                // When backfill is complete, Sync_Window_Start__c = Gmail_Forward_Cursor__c (forward sync only)
                // When backfill is in progress, Sync_Window_Start__c = lookback boundary (older than forward cursor)
                // So if Sync_Window_Start__c >= Gmail_Forward_Cursor__c, backfill is complete
                gmailBackfillComplete = (log.Sync_Window_Start__c != null && 
                                         log.Sync_Window_Start__c >= gmailForwardCursor);
                
            }
        } catch (Exception e) {
            // Default to NOW if we can't load
            gmailForwardCursor = DateTime.now();
            gmailBackfillComplete = false;
        }
    }
    
    /**
     * Check if Gmail forward sync is complete (both inbox and sent)
     */
    private Boolean isGmailForwardSyncComplete() {
        return gmailForwardInboxComplete && gmailForwardSentComplete;
    }
    
    /**
     * Check if Gmail backfill sync is complete
     */
    private Boolean isGmailBackfillComplete() {
        return gmailBackfillComplete || (inboxComplete && sentComplete);
    }
    
    /**
     * Get next folder for Gmail forward sync (alternating)
     */
    private String getNextGmailForwardFolder() {
        if (gmailForwardInboxComplete && gmailForwardSentComplete) return null;
        
        // Alternate between inbox and sent
        if (!gmailForwardInboxComplete && (gmailForwardSentComplete || !isLastFolderInbox)) {
            return 'inbox';
        } else if (!gmailForwardSentComplete) {
            return 'sent';
        }
        return null;
    }
    
    /**
     * Fetch Gmail forward sync batch (new emails from gmailForwardCursor to NOW)
     * Gmail returns newest first, so we use pageToken pagination within the forward window
     */
    private FetchedBatch fetchGmailForwardBatch(String folder, Integer batchSize, String providerType) {
        String apiFolder = folder == 'inbox' ? 'INBOX' : 'SENT';
        String pageToken = folder == 'inbox' ? gmailForwardInboxPageToken : gmailForwardSentPageToken;
        
        try {
            // Forward sync: fetch from gmailForwardCursor+1sec to NOW
            // We add 1 second to avoid re-fetching the boundary email (Gmail's after: is inclusive)
            // This catches any new emails since the last sync
            DateTime forwardStart = gmailForwardCursor.addSeconds(1); // +1 second to exclude boundary
            DateTime forwardEnd = DateTime.now();
            
            AIGmailFetchService.EmailBatchResult result = 
                AIGmailFetchService.fetchEmailsWithBodyPaginated(
                    accessToken, apiFolder, forwardStart, forwardEnd, batchSize, pageToken
                );
            
            if (String.isNotBlank(result.errorMessage)) {
                appendError('Forward ' + folder + ': ' + result.errorMessage);
                markGmailForwardFolderComplete(folder);
                return null;
            }
            
            // Transform Gmail emails to Graph format
            List<Map<String, Object>> emails = new List<Map<String, Object>>();
            for (Map<String, Object> email : result.emails) {
                try {
                    Map<String, Object> transformed = AIGmailEmailTransformer.transformToGraphFormat(email);
                    emails.add(transformed);
                } catch (Exception transformEx) {
                    appendError('Gmail transform error for email ID ' + email.get('id') + ': ' + transformEx.getMessage());
                }
            }
            
            // Update page token and completion status
            if (folder == 'inbox') {
                gmailForwardInboxPageToken = result.nextPageToken;
                if (!result.hasMore) {
                    gmailForwardInboxComplete = true;
                }
            } else {
                gmailForwardSentPageToken = result.nextPageToken;
                if (!result.hasMore) {
                    gmailForwardSentComplete = true;
                }
            }
            
            // Toggle folder for alternation
            isLastFolderInbox = (folder == 'inbox');
            
            return new FetchedBatch(folder, emails);
            
        } catch (Exception e) {
            appendError('Forward ' + folder + ' fetch error: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Update Gmail forward cursor with the newest email date from a batch
     * For forward sync, we want to track the NEWEST email seen
     */
    private void updateGmailForwardCursor(List<Map<String, Object>> emails) {
        if (emails == null || emails.isEmpty()) return;
        
        for (Map<String, Object> email : emails) {
            DateTime emailDate = parseEmailDate(email);
            if (emailDate != null) {
                // Track newest email date for forward cursor
                if (gmailForwardCursor == null || emailDate > gmailForwardCursor) {
                    gmailForwardCursor = emailDate;
                }
                // Also track oldest for backfill cursor
                if (oldestProcessedEmailDate == null || emailDate < oldestProcessedEmailDate) {
                    oldestProcessedEmailDate = emailDate;
                }
                // Track newest for reporting
                if (newestProcessedEmailDate == null || emailDate > newestProcessedEmailDate) {
                    newestProcessedEmailDate = emailDate;
                }
            }
        }
    }
    
    /**
     * Mark Gmail forward sync folder as complete
     */
    private void markGmailForwardFolderComplete(String folder) {
        if (folder == 'inbox') {
            gmailForwardInboxComplete = true;
        } else {
            gmailForwardSentComplete = true;
        }
    }
    
    /**
     * Fetch Gmail backfill batch (historical emails from oldest processed to lookback boundary)
     * This is similar to the old approach, fetching older emails to fill the lookback window
     */
    private FetchedBatch fetchGmailBackfillBatch(String folder, Integer batchSize, String providerType) {
        String apiFolder = folder == 'inbox' ? 'INBOX' : 'SENT';
        String pageToken = folder == 'inbox' ? gmailInboxPageToken : gmailSentPageToken;
        
        try {
            // Backfill sync: fetch from lookback boundary to oldest processed (syncWindowEnd-1sec)
            // We subtract 1 second from end to avoid re-fetching the boundary email (Gmail's before: is inclusive)
            DateTime backfillStart = syncWindowStart;  // Lookback boundary
            DateTime backfillEnd = syncWindowEnd.addSeconds(-1);  // Oldest email processed so far (-1 sec to exclude)
            
            // Check if backfill window is valid (end must be after start)
            if (backfillEnd <= backfillStart) {
                markFolderComplete(folder);
                gmailBackfillComplete = inboxComplete && sentComplete;
                // Close the window completely when backfill is done
                if (gmailBackfillComplete) {
                    syncWindowEnd = syncWindowStart;
                    oldestProcessedEmailDate = syncWindowStart;
                }
                return null;
            }
            
            AIGmailFetchService.EmailBatchResult result = 
                AIGmailFetchService.fetchEmailsWithBodyPaginated(
                    accessToken, apiFolder, backfillStart, backfillEnd, batchSize, pageToken
                );
            
            if (String.isNotBlank(result.errorMessage)) {
                appendError('Backfill ' + folder + ': ' + result.errorMessage);
                markFolderComplete(folder);
                return null;
            }
            
            // Transform Gmail emails to Graph format
            List<Map<String, Object>> emails = new List<Map<String, Object>>();
            for (Map<String, Object> email : result.emails) {
                try {
                    Map<String, Object> transformed = AIGmailEmailTransformer.transformToGraphFormat(email);
                    emails.add(transformed);
                } catch (Exception transformEx) {
                    appendError('Gmail transform error for email ID ' + email.get('id') + ': ' + transformEx.getMessage());
                }
            }
            
            // Update page token and completion status
            if (folder == 'inbox') {
                gmailInboxPageToken = result.nextPageToken;
                if (!result.hasMore) {
                    inboxComplete = true;
                }
            } else {
                gmailSentPageToken = result.nextPageToken;
                if (!result.hasMore) {
                    sentComplete = true;
                }
            }
            
            // Update backfill cursor (oldest email processed)
            if (result.lastEmailDate != null && (syncWindowEnd == null || result.lastEmailDate < syncWindowEnd)) {
                syncWindowEnd = result.lastEmailDate;
            }
            
            // Check if backfill is complete for all folders
            gmailBackfillComplete = inboxComplete && sentComplete;
            
            // OPTIMIZATION: When backfill is complete (no more emails from Gmail),
            // set Sync_Window_End__c to the lookback boundary (Sync_Window_Start__c).
            // This makes it explicit that the entire window has been synced.
            // Next run will see Sync_Window_End__c == Sync_Window_Start__c and skip backfill.
            if (gmailBackfillComplete) {
                syncWindowEnd = syncWindowStart; // Close the window completely
                oldestProcessedEmailDate = syncWindowStart; // Also update for consistency
            }
            
            // Toggle folder for alternation
            isLastFolderInbox = (folder == 'inbox');
            
            return new FetchedBatch(folder, emails);
            
        } catch (Exception e) {
            appendError('Backfill ' + folder + ' fetch error: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Update the newest and oldest processed email dates from a batch of emails
     * - newestProcessedEmailDate: Used for Outlook (fetches oldest first)
     * - oldestProcessedEmailDate: Used for Gmail (fetches newest first)
     */
    private void updateNewestProcessedDate(List<Map<String, Object>> emails) {
        if (emails == null || emails.isEmpty()) return;
        
        for (Map<String, Object> email : emails) {
            DateTime emailDate = parseEmailDate(email);
            if (emailDate != null) {
                // Track newest (for Outlook - oldest first ordering)
                if (newestProcessedEmailDate == null || emailDate > newestProcessedEmailDate) {
                    newestProcessedEmailDate = emailDate;
                }
                // Track oldest (for Gmail - newest first ordering)
                if (oldestProcessedEmailDate == null || emailDate < oldestProcessedEmailDate) {
                    oldestProcessedEmailDate = emailDate;
                }
            }
        }
    }
    
    /**
     * Parse email date from email map
     */
    private DateTime parseEmailDate(Map<String, Object> email) {
        try {
            // Try receivedDateTime first (Outlook format)
            String dateStr = (String) email.get('receivedDateTime');
            if (String.isBlank(dateStr)) {
                // Try internalDate for Gmail (milliseconds timestamp)
                Object internalDate = email.get('internalDate');
                if (internalDate != null) {
                    Long millis = Long.valueOf(String.valueOf(internalDate));
                    return DateTime.newInstance(millis);
                }
            }
            
            if (String.isNotBlank(dateStr)) {
                // Parse ISO 8601 format
                return (DateTime) JSON.deserialize('"' + dateStr + '"', DateTime.class);
            }
        } catch (Exception e) {
            // Ignore
        }
        return null;
    }
    
    /**
     * Finalizer execute - Called after queueable completes
     * Uses finalizer to chain, which avoids stack depth issues
     */
    public void execute(FinalizerContext context) {
        if (needsChaining && !disableChaining) {
            
            AIEmailSyncChainableQueueable nextJob = new AIEmailSyncChainableQueueable(
                syncLogId,
                workspaceUserId,
                targetUserId,
                accessToken,
                provider,
                userEmail,
                inboxCursor,
                sentCursor,
                syncWindowStart,
                syncWindowEnd,
                inboxComplete,
                sentComplete,
                isLastFolderInbox,
                totalFetched,
                totalDuplicate,
                totalExcluded,
                totalMatched,
                totalUnmatched,
                totalImported,
                totalFailed,
                aggregatedExclusionCounts,
                newestProcessedEmailDate,
                oldestProcessedEmailDate,
                maxEmailsLimit,
                gmailInboxPageToken,
                gmailSentPageToken,
                // Gmail FIFO state
                gmailForwardCursor,
                gmailForwardInboxComplete,
                gmailForwardSentComplete,
                gmailBackfillComplete,
                gmailForwardInboxPageToken,
                gmailForwardSentPageToken
            );
            
            System.enqueueJob(nextJob);
        }
    }
    
    /**
     * Wrapper class for fetched batch data
     */
    private class FetchedBatch {
        public String folder;
        public List<Map<String, Object>> emails;
        
        public FetchedBatch(String folder, List<Map<String, Object>> emails) {
            this.folder = folder;
            this.emails = emails;
        }
    }
    
    /**
     * Get the next folder to process (alternating)
     */
    private String getNextFolder() {
        if (inboxComplete && sentComplete) return null;
        
        Boolean processInbox = shouldProcessInbox();
        
        if (processInbox && !inboxComplete) {
            return 'inbox';
        } else if (!sentComplete) {
            return 'sent';
        } else if (!inboxComplete) {
            return 'inbox';
        }
        return null;
    }
    
    /**
     * Fetch a single batch from a folder (CALLOUT)
     */
    private FetchedBatch fetchBatch(String folder, Integer batchSize, String providerType) {
        DateTime cursor = folder == 'inbox' ? inboxCursor : sentCursor;
        String apiFolder = getApiFolder(folder);
        
        try {
            List<Map<String, Object>> emails;
            DateTime newCursor;
            Boolean hasMore;
            
            if (provider == 'Outlook') {
                // Outlook uses date cursor (oldest first)
                AIOutlookFetchService.EmailBatchResult result = 
                    AIOutlookFetchService.fetchEmailsWithBody(accessToken, apiFolder, cursor, syncWindowEnd, batchSize);
                
                if (String.isNotBlank(result.errorMessage)) {
                    appendError(folder + ': ' + result.errorMessage);
                    markFolderComplete(folder);
                    return null;
                }
                
                emails = result.emails;
                newCursor = result.lastEmailDate;
                hasMore = result.hasMore;
            } else {
                // Gmail uses pageToken (newest first, so we need pageToken pagination)
                String pageToken = folder == 'inbox' ? gmailInboxPageToken : gmailSentPageToken;
                
                AIGmailFetchService.EmailBatchResult result = 
                    AIGmailFetchService.fetchEmailsWithBodyPaginated(
                        accessToken, apiFolder, syncWindowStart, syncWindowEnd, batchSize, pageToken
                    );
                
                if (String.isNotBlank(result.errorMessage)) {
                    appendError(folder + ': ' + result.errorMessage);
                    markFolderComplete(folder);
                    return null;
                }
                
                // Transform Gmail emails to Graph format
                // Use AIGmailEmailTransformer (same as AIGmailProvider)
                emails = new List<Map<String, Object>>();
                for (Map<String, Object> email : result.emails) {
                    try {
                        Map<String, Object> transformed = AIGmailEmailTransformer.transformToGraphFormat(email);
                        emails.add(transformed);
                    } catch (Exception transformEx) {
                        appendError('Gmail transform error for email ID ' + email.get('id') + ': ' + transformEx.getMessage());
                    }
                }
                newCursor = result.lastEmailDate;
                hasMore = result.hasMore;
                
                // Save the nextPageToken for subsequent batches
                if (folder == 'inbox') {
                    gmailInboxPageToken = result.nextPageToken;
                } else {
                    gmailSentPageToken = result.nextPageToken;
                }
            }
            
            // Update cursor and completion status
            if (folder == 'inbox') {
                inboxCursor = newCursor != null ? newCursor : inboxCursor;
                inboxComplete = !hasMore;
            } else {
                sentCursor = newCursor != null ? newCursor : sentCursor;
                sentComplete = !hasMore;
            }
            
            // Toggle folder for alternation
            isLastFolderInbox = (folder == 'inbox');
            
            return new FetchedBatch(folder, emails != null ? emails : new List<Map<String, Object>>());
            
        } catch (Exception e) {
            appendError(folder + ' fetch error: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Process fetched emails: dedupe, exclude, match, import (DML)
     * 
     * Count Flow:
     * 1. Emails come in from fetch (already counted in totalFetched)
     * 2. Apply exclusion filters (marketing, confidential, internal, public domains)
     * 3. Create staging records - AIWorkspaceStagingCreator handles deduplication:
     *    - Checks Staging table for existing records (by Provider_Id__c and Message_Identifier__c)
     *    - Checks EmailMessage table for existing records (by MessageIdentifier)
     *    - Returns accurate counts for matched, unmatched, duplicate, imported
     * 
     * Formula: Fetched = Matched + Unmatched + Duplicate + Excluded
     * Note: Excluded emails are NOT imported (filtered out based on user settings)
     */
    private void processEmails(List<Map<String, Object>> emails, String providerType) {
        if (emails == null || emails.isEmpty()) return;
        
        // Step 1: Apply exclusion filters based on user settings
        // Filters out marketing, confidential, internal, and public domain emails
        AIEmailExclusionService.BatchExclusionResult exclusionResult =
            AIEmailExclusionService.filterBatch(emails, providerType, userEmail);
        
        totalExcluded += exclusionResult.excludedEmails.size();
        
        // Aggregate exclusion counts for reporting
        for (String category : exclusionResult.exclusionCounts.keySet()) {
            Integer count = exclusionResult.exclusionCounts.get(category);
            if (aggregatedExclusionCounts.containsKey(category)) {
                aggregatedExclusionCounts.put(category, aggregatedExclusionCounts.get(category) + count);
            } else {
                aggregatedExclusionCounts.put(category, count);
            }
        }
        
        // If all emails were excluded, return early
        if (exclusionResult.includedEmails.isEmpty()) {
            return;
        }
        
        // Step 2: Create staging records and match them to Lead/Contact
        // Only process non-excluded emails (respects user's exclusion settings)
        // AIWorkspaceStagingCreator handles ALL deduplication (both Staging and EmailMessage tables)
        // This avoids double-counting that occurred when AIEmailSyncService.deduplicateEmails() was called first
        // Pass targetUserId to ensure records are created with correct owner (not the scheduler user)
        // Pass sendNotifications=false because this is auto-sync (not manual)
        try {
            AIWorkspaceStagingCreator.StagingResult stagingResult =
                AIWorkspaceStagingCreator.createEmailStagingRecords(
                    exclusionResult.includedEmails, // Only pass non-excluded emails
                    providerType,
                    userEmail,
                    syncLogId,
                    targetUserId,
                    false // Don't send notifications for auto-sync
                );
            
            // Use the actual counts from staging result
            // These counts are mutually exclusive: Fetched = Matched + Unmatched + Duplicate
            totalMatched += stagingResult.matchedCount;      // Matched to Lead/Contact
            totalUnmatched += stagingResult.unmatchedCount;  // Not matched (includes re-attempt of prior unmatched)
            totalImported += stagingResult.importedCount;    // Actual EmailMessage records created
            totalDuplicate += stagingResult.duplicateCount;  // Duplicates found in staging/EmailMessage
            totalFailed += stagingResult.failedCount;
            
            // DEBUG: Log if staging creation had errors
            if (!stagingResult.errors.isEmpty()) {
                for (String error : stagingResult.errors) {
                    appendError('Staging creation: ' + error);
                }
            }
        } catch (Exception e) {
            appendError('Import error: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
            totalFailed += emails.size();
        }
    }
    
    /**
     * Check if we have enough callouts remaining for at least one more batch
     * Gmail needs more callouts than Outlook due to batch API pattern
     */
    private Boolean hasEnoughCallouts() {
        Integer remaining = Limits.getLimitCallouts() - Limits.getCallouts();
        // Calculate minimum callouts needed for next batch based on provider
        Integer calloutsNeededForNextBatch = (provider == 'Outlook') 
            ? CALLOUTS_PER_OUTLOOK_BATCH 
            : CALLOUTS_PER_GMAIL_BATCH;
        
        // Need enough for next batch PLUS reserve
        return remaining > (calloutsNeededForNextBatch + RESERVE_CALLOUTS);
    }
    
    /**
     * Check if sync is complete
     * Complete when:
     * 1. Max emails limit reached, OR
     * 2. For Outlook: Both folders are done
     * 3. For Gmail: Forward sync complete AND backfill complete (or backfill not needed)
     */
    private Boolean isSyncComplete() {
        // Check if max emails limit reached
        if (totalFetched >= maxEmailsLimit) {
            return true;
        }
        
        if (provider == 'Gmail') {
            // Gmail: Complete when forward sync is done AND backfill is done
            Boolean forwardDone = isGmailForwardSyncComplete();
            Boolean backfillDone = gmailBackfillComplete || (inboxComplete && sentComplete);
            return forwardDone && backfillDone;
        }
        
        // Outlook: Check if both folders are done
        return inboxComplete && sentComplete;
    }
    
    /**
     * Determine which folder to process next
     */
    private Boolean shouldProcessInbox() {
        if (inboxComplete) return false;
        if (sentComplete) return true;
        return !isLastFolderInbox;
    }
    
    /**
     * Mark a folder as complete
     */
    private void markFolderComplete(String folder) {
        if (folder == 'inbox') {
            inboxComplete = true;
        } else {
            sentComplete = true;
        }
    }
    
    /**
     * Get API folder name
     */
    private String getApiFolder(String folder) {
        if (provider == 'Outlook') {
            return folder == 'inbox' ? 'inbox' : 'sentitems';
        } else {
            return folder == 'inbox' ? 'INBOX' : 'SENT';
        }
    }
    
    /**
     * Append error to sync log
     */
    /**
     * Queue an error message to be saved later (after all callouts complete)
     * This avoids DML-before-callout issues during the fetch phase
     */
    private void appendError(String errorMessage) {
        String timestampedError = DateTime.now().format('HH:mm:ss') + ': ' + errorMessage;
        pendingErrors.add(timestampedError);
    }
    
    /**
     * Flush all pending errors to the sync log (DML)
     * Called in the DML phase after all callouts are complete
     */
    private void flushPendingErrors() {
        if (pendingErrors.isEmpty()) return;
        
        try {
            AI_Workspace_Sync_Log__c syncLog = [
                SELECT Id, Error_Message__c 
                FROM AI_Workspace_Sync_Log__c 
                WHERE Id = :syncLogId 
                LIMIT 1
            ];
            
            String existing = syncLog.Error_Message__c;
            if (String.isBlank(existing)) existing = '';
            
            String newErrors = String.join(pendingErrors, '\n');
            String combined = String.isBlank(existing) ? newErrors : existing + '\n' + newErrors;
            
            if (combined.length() <= MAX_ERROR_LENGTH) {
                syncLog.Error_Message__c = combined;
                syncLog.Status__c = 'Partial';
                
                // Use FLSCheck for security enforcement
                List<AI_Workspace_Sync_Log__c> logsToUpdate = new List<AI_Workspace_Sync_Log__c>{ syncLog };
                FLSCheck.getInstance().updateDML(logsToUpdate);
            }
            
            pendingErrors.clear();
        } catch (Exception e) {
            // Ignore
        }
    }
    
    /**
     * Get the correct sync window end date based on provider
     * - Outlook fetches oldest first, so use newestProcessedEmailDate
     * - Gmail fetches newest first, so use oldestProcessedEmailDate
     * This ensures the next sync can continue from where we left off
     */
    private DateTime getSyncWindowEndDate() {
        if (provider == 'Gmail') {
            // Gmail FIFO: When backfill is complete, Sync_Window_End__c should be NOW
            // (representing the end of the forward sync window to current time)
            // When backfill is NOT complete, use syncWindowEnd (oldest email processed during backfill)
            if (gmailBackfillComplete) {
                return DateTime.now();
            } else {
                return syncWindowEnd;
            }
        } else {
            // Outlook returns oldest first, so newestProcessedEmailDate is where we should continue
            return newestProcessedEmailDate;
        }
    }
    
    /**
     * Update sync log with current totals
     */
    private void updateSyncLog() {
        try {
            AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
                Id = syncLogId,
                Emails_Fetched__c = totalFetched,
                Emails_Duplicate__c = totalDuplicate,
                Emails_Excluded__c = totalExcluded,
                Emails_Matched__c = totalMatched,
                Emails_Unmatched__c = totalUnmatched,
                Emails_Imported__c = totalImported,
                // Use provider-specific date for Sync_Window_End__c
                // Gmail (newest first) -> use oldest; Outlook (oldest first) -> use newest
                Sync_Window_End__c = getSyncWindowEndDate()
            );
            
            // Gmail FIFO: Update forward cursor and backfill complete flag
            if (provider == 'Gmail') {
                syncLog.Gmail_Forward_Cursor__c = gmailForwardCursor;
                // Note: Gmail_Backfill_Complete__c removed - completion is determined by
                // checking if Sync_Window_End__c <= Sync_Window_Start__c (window closed)
            }
            
            // Add exclusion summary if there are exclusions
            if (totalExcluded > 0 && !aggregatedExclusionCounts.isEmpty()) {
                syncLog.Exclusion_Summary__c = AIEmailExclusionService.toExclusionSummaryText(aggregatedExclusionCounts);
            }
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Log__c> logsToUpdate = new List<AI_Workspace_Sync_Log__c>{ syncLog };
            FLSCheck.getInstance().updateDML(logsToUpdate);
        } catch (Exception e) {
            // Ignore
        }
    }
    
    /**
     * Finalize sync log
     */
    private void finalizeSyncLog(String status) {
        try {
            AI_Workspace_Sync_Log__c syncLog = [
                SELECT Id, Error_Message__c, Status__c, Start_Time__c
                FROM AI_Workspace_Sync_Log__c 
                WHERE Id = :syncLogId 
                LIMIT 1
            ];
            
            syncLog.Emails_Fetched__c = totalFetched;
            syncLog.Emails_Duplicate__c = totalDuplicate;
            syncLog.Emails_Excluded__c = totalExcluded;
            syncLog.Emails_Matched__c = totalMatched;
            syncLog.Emails_Unmatched__c = totalUnmatched;
            syncLog.Emails_Imported__c = totalImported;
            // Use provider-specific date for Sync_Window_End__c
            // Gmail (newest first) -> use oldest; Outlook (oldest first) -> use newest
            syncLog.Sync_Window_End__c = getSyncWindowEndDate();
            syncLog.End_Time__c = DateTime.now();
            
            // Gmail FIFO: Update forward cursor and backfill complete flag
            if (provider == 'Gmail') {
                syncLog.Gmail_Forward_Cursor__c = gmailForwardCursor;
                // Note: Gmail_Backfill_Complete__c removed - completion is determined by
                // checking if Sync_Window_End__c <= Sync_Window_Start__c (window closed)
                
            }
            
            // Add exclusion summary if there are exclusions
            if (totalExcluded > 0 && !aggregatedExclusionCounts.isEmpty()) {
                syncLog.Exclusion_Summary__c = AIEmailExclusionService.toExclusionSummaryText(aggregatedExclusionCounts);
            }
            
            // Determine final status:
            // - If status is 'Success' but there are errors → 'Partial'
            // - If status is 'Failed' but some emails were imported → 'Partial'
            // - Otherwise use the provided status
            if (status == 'Success' && String.isNotBlank(syncLog.Error_Message__c)) {
                syncLog.Status__c = 'Partial';
            } else if (status == 'Failed' && totalImported > 0) {
                syncLog.Status__c = 'Partial';
            } else {
                syncLog.Status__c = status;
            }
            
            if (syncLog.Start_Time__c != null) {
                syncLog.Processing_Time_Seconds__c = 
                    (DateTime.now().getTime() - syncLog.Start_Time__c.getTime()) / 1000.0;
            }
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Log__c> logsToUpdate = new List<AI_Workspace_Sync_Log__c>{ syncLog };
            FLSCheck.getInstance().updateDML(logsToUpdate);
            
        } catch (Exception e) {
            // Ignore
        }
    }
    
    /**
     * Refresh token at the start of each queueable execution
     * 
     * This method:
     * 1. Queries the AI_Workspace_User__c record for the workspace user
     * 2. Decrypts the stored refresh token
     * 3. Makes a callout to refresh the access token
     * 4. Saves the new tokens (DML) - this happens BEFORE any email API callouts
     * 5. Returns the fresh access token
     * 
     * IMPORTANT: This callout + DML happens BEFORE any email fetch callouts.
     * This is safe because:
     * - The token refresh DML updates AI_Workspace_User__c
     * - The subsequent email callouts are independent of this DML
     * - We're not violating "no callout after uncommitted work" because
     *   the token endpoint and email endpoints are separate callouts
     * 
     * @return The fresh access token, or null if refresh failed
     */
    private String refreshTokenForExecution() {
        try {
            // Query the workspace user record
            List<AI_Workspace_User__c> workspaceUsers = [
                SELECT Id, User__c, Provider__c, Refresh_Token__c
                FROM AI_Workspace_User__c
                WHERE Id = :workspaceUserId
                LIMIT 1
            ];
            
            if (workspaceUsers.isEmpty()) {
                return null;
            }
            
            AI_Workspace_User__c workspaceUser = workspaceUsers[0];
            
            // Decrypt the refresh token
            String refreshToken = decryptRefreshToken(workspaceUser);
            if (String.isBlank(refreshToken)) {
                return null;
            }
            
            // Refresh the access token (CALLOUT)
            TokenRefreshResult refreshResult = callTokenEndpoint(refreshToken);
            
            if (!refreshResult.isSuccess) {
                
                // If it's an invalid_grant error, the user needs to re-authenticate
                if (refreshResult.requiresReauth) {
                    sendReAuthNotification(workspaceUser);
                }
                return null;
            }
            
            // Store tokens for deferred save (will be saved AFTER all callouts complete)
            // This avoids "uncommitted work pending" error by not doing DML before email callouts
            this.pendingNewAccessToken = refreshResult.accessToken;
            this.pendingNewRefreshToken = refreshResult.refreshToken;
            
            return refreshResult.accessToken;
            
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Decrypt refresh token using the appropriate OAuth controller
     * Uses the workspace user's User__c field to get the correct encryption key
     */
    private String decryptRefreshToken(AI_Workspace_User__c workspaceUser) {
        if (String.isBlank(workspaceUser.Refresh_Token__c)) {
            return null;
        }
        
        try {
            // Use the workspace user's User__c field to decrypt with the correct key
            // This is critical for scheduler which runs as admin but needs to decrypt other users' tokens
            Id tokenOwnerId = workspaceUser.User__c;
            
            if (workspaceUser.Provider__c == 'Outlook') {
                return AIOutlookOAuthController.decryptRefreshToken(workspaceUser.Refresh_Token__c, tokenOwnerId);
            } else {
                return AIGmailOAuthController.decryptRefreshToken(workspaceUser.Refresh_Token__c, tokenOwnerId);
            }
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Call the token endpoint to refresh the access token
     * This is isolated to clearly show it's a CALLOUT
     */
    private TokenRefreshResult callTokenEndpoint(String refreshToken) {
        TokenRefreshResult result = new TokenRefreshResult();
        
        try {
            if (provider == 'Outlook') {
                AIOutlookOAuthBrowserService.TokenResult tokenResult = 
                    AIOutlookOAuthBrowserService.refreshAccessToken(refreshToken);
                
                result.isSuccess = tokenResult.isSuccess;
                result.accessToken = tokenResult.accessToken;
                result.refreshToken = tokenResult.refreshToken;
                result.errorMessage = tokenResult.errorMessage;
                result.requiresReauth = String.isNotBlank(tokenResult.errorMessage) && 
                    (tokenResult.errorMessage.contains('invalid_grant') || 
                     tokenResult.errorMessage.contains('expired'));
                     
            } else {
                AIGmailOAuthBrowserService.TokenResult tokenResult = 
                    AIGmailOAuthBrowserService.refreshAccessToken(refreshToken);
                
                result.isSuccess = tokenResult.isSuccess;
                result.accessToken = tokenResult.accessToken;
                result.refreshToken = tokenResult.refreshToken;
                result.errorMessage = tokenResult.errorMessage;
                result.requiresReauth = String.isNotBlank(tokenResult.errorMessage) && 
                    (tokenResult.errorMessage.contains('invalid_grant') || 
                     tokenResult.errorMessage.contains('expired'));
            }
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Token refresh callout failed: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Save the refreshed tokens to AI_Workspace_User__c
     * This is isolated to clearly show it's a DML operation
     * Uses the token owner's user ID for encryption, not the running user
     */
    private void saveRefreshedTokens(Id wsUserId, String newAccessToken, String newRefreshToken) {
        try {
            // Query to get the user ID for encryption
            List<AI_Workspace_User__c> users = [
                SELECT Id, User__c, Provider__c
                FROM AI_Workspace_User__c
                WHERE Id = :wsUserId
                LIMIT 1
            ];
            
            if (users.isEmpty()) return;
            
            AI_Workspace_User__c wsUser = users[0];
            String userProvider = wsUser.Provider__c;
            Id tokenOwnerId = wsUser.User__c; // The actual user who owns this token
            
            // Encrypt the new tokens using the TOKEN OWNER's key, not the running user's key
            // This is critical for scheduler which runs as admin
            String encryptedAccessToken;
            String encryptedRefreshToken;
            
            if (userProvider == 'Outlook') {
                encryptedAccessToken = AIOutlookOAuthController.encryptRefreshToken(newAccessToken, tokenOwnerId);
                if (String.isNotBlank(newRefreshToken)) {
                    encryptedRefreshToken = AIOutlookOAuthController.encryptRefreshToken(newRefreshToken, tokenOwnerId);
                }
            } else {
                encryptedAccessToken = AIGmailOAuthController.encryptRefreshToken(newAccessToken, tokenOwnerId);
                if (String.isNotBlank(newRefreshToken)) {
                    encryptedRefreshToken = AIGmailOAuthController.encryptRefreshToken(newRefreshToken, tokenOwnerId);
                }
            }
            
            // Update the record
            AI_Workspace_User__c updateRecord = new AI_Workspace_User__c(Id = wsUserId);
            updateRecord.Access_Token__c = encryptedAccessToken;
            if (String.isNotBlank(encryptedRefreshToken)) {
                updateRecord.Refresh_Token__c = encryptedRefreshToken;
            }
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_User__c> usersToUpdate = new List<AI_Workspace_User__c>{ updateRecord };
            FLSCheck.getInstance().updateDML(usersToUpdate);
            
        } catch (Exception e) {
            // Log but don't fail - the token is still valid even if we couldn't save it
        }
    }
    
    /**
     * Send re-authentication notification to user
     */
    private void sendReAuthNotification(AI_Workspace_User__c workspaceUser) {
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
            notification.setTitle('Action Required: Re-authenticate ' + workspaceUser.Provider__c);
            notification.setBody('Your ' + workspaceUser.Provider__c + ' connection has expired. Please re-authenticate to continue syncing.');
            notification.setNotificationTypeId(notifTypes[0].Id);
            notification.setTargetId(workspaceUser.User__c);
            
            notification.send(new Set<String>{ workspaceUser.User__c });
        } catch (Exception e) {
        }
    }
    
    /**
     * Internal class for token refresh result
     */
    private class TokenRefreshResult {
        public Boolean isSuccess = false;
        public String accessToken;
        public String refreshToken;
        public String errorMessage;
        public Boolean requiresReauth = false;
    }
}