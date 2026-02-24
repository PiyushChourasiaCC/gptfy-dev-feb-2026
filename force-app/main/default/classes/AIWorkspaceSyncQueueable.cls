/**
 * AIWorkspaceSyncQueueable - Queueable job for workspace-based sync
 * 
 * Processes sync for workspace users sequentially using stored refresh tokens.
 * Handles Email, Calendar, and Task sync for both Outlook and Gmail.
 * 
 * Design:
 * - Processes ONE workspace user at a time
 * - Uses Finalizer to chain to next user (avoids "too many queueable jobs" error)
 * - Handles auth failures gracefully with notifications
 * - Supports both scheduler (all users) and run-now (current user) modes
 * 
 * @author GPTfy
 * @date 2026-01-16
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIWorkspaceSyncQueueable implements Queueable, Database.AllowsCallouts, Finalizer {
    
    public enum SyncType { EMAIL, CALENDAR, TASK }
    
    private List<Id> workspaceUserIds;
    private Integer currentIndex;
    private SyncType currentSyncType;
    private Boolean isRunNowMode;
    
    // State for finalizer to determine next action
    private SyncType nextSyncType;
    private Integer nextIndex;
    private Boolean shouldChain = false;
    
    // Test support
    @TestVisible
    private static Boolean disableChaining = false;
    
    /**
     * Constructor for scheduler mode (processes all users)
     * @param workspaceUserIds List of AI_Workspace_User__c record IDs
     * @param startIndex Starting index in the list
     */
    public AIWorkspaceSyncQueueable(List<Id> workspaceUserIds, Integer startIndex) {
        this.workspaceUserIds = workspaceUserIds;
        this.currentIndex = startIndex;
        this.currentSyncType = SyncType.EMAIL;
        this.isRunNowMode = false;
    }
    
    /**
     * Constructor with sync type
     * @param workspaceUserIds List of AI_Workspace_User__c record IDs
     * @param startIndex Starting index
     * @param syncType Current sync type to execute
     */
    public AIWorkspaceSyncQueueable(List<Id> workspaceUserIds, Integer startIndex, SyncType syncType) {
        this.workspaceUserIds = workspaceUserIds;
        this.currentIndex = startIndex;
        this.currentSyncType = syncType;
        this.isRunNowMode = false;
    }
    
    /**
     * Constructor for run-now mode (current user only)
     * @param workspaceUserIds List of AI_Workspace_User__c record IDs
     * @param startIndex Starting index
     * @param syncType Current sync type
     * @param runNowMode If true, won't chain to other users
     */
    public AIWorkspaceSyncQueueable(List<Id> workspaceUserIds, Integer startIndex, SyncType syncType, Boolean runNowMode) {
        this.workspaceUserIds = workspaceUserIds;
        this.currentIndex = startIndex;
        this.currentSyncType = syncType;
        this.isRunNowMode = runNowMode;
    }
    
    /**
     * Main execute method
     */
    public void execute(QueueableContext context) {
        // Attach finalizer to handle chaining without hitting queueable limits
        if (!Test.isRunningTest()) {
            System.attachFinalizer(this);
        }
        
        if (workspaceUserIds == null || workspaceUserIds.isEmpty() || currentIndex >= workspaceUserIds.size()) {
            return;
        }
        
        Id workspaceUserId = workspaceUserIds[currentIndex];
        
        // 1. Get workspace user record
        AI_Workspace_User__c workspaceUser = getWorkspaceUser(workspaceUserId);
        if (workspaceUser == null) {
            prepareChainToNext();
            return;
        }
        
        // 2. Decrypt refresh token using existing controller methods
        String refreshToken = decryptRefreshToken(workspaceUser);
        
        if (String.isBlank(refreshToken)) {
            handleAuthFailure(workspaceUser, 'No refresh token found');
            prepareChainToNext();
            return;
        }
        
        // 3. Get fresh access token
        TokenResult tokenResult = refreshAccessToken(workspaceUser.Provider__c, refreshToken);
        
        if (!tokenResult.isSuccess) {
            handleAuthFailure(workspaceUser, tokenResult.errorMessage);
            sendReAuthNotification(workspaceUser);
            prepareChainToNext();
            return;
        }
        
        // 4. Execute current sync type FIRST (before any DML to avoid "uncommitted work" error)
        // Salesforce doesn't allow callouts after DML in the same transaction
        executeSync(workspaceUser, tokenResult.accessToken);
        
        // 5. Update refresh token if rotated (Microsoft rotates tokens)
        // This DML must happen AFTER all callouts are complete
        if (String.isNotBlank(tokenResult.refreshToken)) {
            updateRefreshToken(workspaceUser.Id, workspaceUser.User__c, tokenResult.refreshToken, workspaceUser.Provider__c);
        }
        
        // 6. Prepare to chain to next sync type or user (via Finalizer)
        prepareChainToNext();
    }
    
    /**
     * Finalizer execute - Called after queueable completes
     * Uses finalizer to chain, which avoids "too many queueable jobs" error
     */
    public void execute(FinalizerContext context) {
        if (shouldChain && !disableChaining) {
            AIWorkspaceSyncQueueable nextJob = new AIWorkspaceSyncQueueable(
                workspaceUserIds, nextIndex, nextSyncType, isRunNowMode
            );
            
            // Use delay when moving to next user
            Integer delayMinutes = (nextIndex > currentIndex) ? AISyncSettingsService.getQueueableDelayMinutes() : 0;
            
            if (delayMinutes > 0) {
                System.enqueueJob(nextJob, delayMinutes);
            } else {
                System.enqueueJob(nextJob);
            }
        }
    }
    
    /**
     * Get workspace user record
     * Note: Refresh_Token__c is encrypted so we can't filter on it in SOQL
     */
    private AI_Workspace_User__c getWorkspaceUser(Id workspaceUserId) {
        List<AI_Workspace_User__c> users = [
            SELECT Id, User__c, Provider__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE Id = :workspaceUserId
            LIMIT 1
        ];
        
        if (users.isEmpty()) {
            return null;
        }
        
        // Check if refresh token exists (filter in Apex since encrypted field)
        AI_Workspace_User__c user = users[0];
        return String.isNotBlank(user.Refresh_Token__c) ? user : null;
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
     * Refresh access token using the appropriate OAuth browser service
     */
    private TokenResult refreshAccessToken(String provider, String refreshToken) {
        if (provider == 'Outlook') {
            AIOutlookOAuthBrowserService.TokenResult result = 
                AIOutlookOAuthBrowserService.refreshAccessToken(refreshToken);
            return new TokenResult(result.isSuccess, result.accessToken, result.refreshToken, result.errorMessage);
        } else {
            AIGmailOAuthBrowserService.TokenResult result = 
                AIGmailOAuthBrowserService.refreshAccessToken(refreshToken);
            return new TokenResult(result.isSuccess, result.accessToken, result.refreshToken, result.errorMessage);
        }
    }
    
    /**
     * Execute the current sync type
     */
    private void executeSync(AI_Workspace_User__c workspaceUser, String accessToken) {
        try {
            switch on currentSyncType {
                when EMAIL {
                    if (AISyncSettingsService.isSyncEnabled()) {
                        // Use the new limit-aware chainable sync for emails
                        startChainableEmailSync(workspaceUser, accessToken);
                    }
                }
                when CALENDAR {
                    if (AISyncSettingsService.isCalendarSyncEnabled()) {
                        AICalendarSyncService.syncUserCalendarWithToken(
                            workspaceUser.User__c,
                            workspaceUser.Provider__c,
                            accessToken,
                            this.isRunNowMode
                        );
                    }
                }
                when TASK {
                    if (AISyncSettingsService.isTaskSyncEnabled()) {
                        AITaskSyncService.syncUserTasksWithToken(
                            workspaceUser.User__c,
                            workspaceUser.Provider__c,
                            accessToken,
                            this.isRunNowMode
                        );
                    }
                }
            }
        } catch (Exception e) {
            logSyncError(workspaceUser, currentSyncType, e);
        }
    }
    
    /**
     * Start the chainable email sync process
     * Creates sync log and enqueues the first chainable job
     * 
     * Gmail FIFO Strategy (Two-Phase Sync):
     * =====================================
     * Gmail API returns emails newest-first with NO way to change ordering.
     * To achieve FIFO (always get new emails first), we use a two-phase approach:
     * 
     * Phase 1 - FORWARD SYNC (catch new emails):
     *   - Start from Gmail_Forward_Cursor__c (newest email we've seen) to NOW
     *   - This ensures new emails are ALWAYS fetched first
     *   - Update Gmail_Forward_Cursor__c with the newest email from this batch
     * 
     * Phase 2 - BACKFILL SYNC (fill the lookback window):
     *   - Continue from Sync_Window_End__c (oldest processed) backwards to lookback boundary
     *   - Only runs if backfill is not complete (Sync_Window_End__c > Sync_Window_Start__c)
     *   - Once backfill reaches lookback boundary, Sync_Window_End__c is set to Sync_Window_Start__c
     * 
     * This ensures:
     * - New emails are NEVER missed (forward sync always runs first)
     * - Historical emails are still fetched (backfill continues in background)
     * - The system converges to a stable state where only forward sync is needed
     */
    private void startChainableEmailSync(AI_Workspace_User__c workspaceUser, String accessToken) {
        String provider = workspaceUser.Provider__c;
        String providerType = provider == 'Outlook' ? 'MICROSOFT_EMAIL' : 'GMAIL_EMAIL';
        DateTime startTime = DateTime.now();
        
        try {
            // Get user email from provider
            String userEmail;
            if (provider == 'Outlook') {
                userEmail = AIOutlookFetchService.getUserEmail(accessToken);
            } else {
                userEmail = AIGmailFetchService.getUserEmail(accessToken);
            }
            
            // Determine sync window based on provider
            DateTime syncWindowStart;
            DateTime syncWindowEnd;
            DateTime gmailForwardCursor = null;
            Boolean gmailBackfillComplete = false;
            
            if (provider == 'Gmail') {
                // Gmail uses two-phase sync strategy
                GmailSyncWindow gmailWindow = getGmailTwoPointerSyncWindow(workspaceUser.User__c, providerType);
                gmailForwardCursor = gmailWindow.forwardCursor;      // Where forward sync starts (newest processed)
                gmailBackfillComplete = gmailWindow.backfillComplete;
                
                if (gmailBackfillComplete) {
                    // BACKFILL COMPLETE: Only forward sync needed
                    // Sync window is from forward cursor (last newest email) to NOW
                    syncWindowStart = gmailForwardCursor;  // Start from where we left off
                    syncWindowEnd = DateTime.now();        // End at current time
                    System.debug('GMAIL_FIFO|startChainableEmailSync: Backfill complete - forward sync only');
                } else {
                    // BACKFILL IN PROGRESS: Need both forward and backfill sync
                    // Sync_Window_Start = lookback boundary (for backfill target)
                    // Sync_Window_End = backfill cursor (oldest email processed so far)
                    syncWindowStart = gmailWindow.lookbackBoundary;
                    syncWindowEnd = gmailWindow.backfillCursor;
                    System.debug('GMAIL_FIFO|startChainableEmailSync: Backfill in progress');
                }
                
                System.debug('GMAIL_FIFO|  Forward Cursor (newest seen): ' + gmailForwardCursor);
                System.debug('GMAIL_FIFO|  Sync Window Start: ' + syncWindowStart);
                System.debug('GMAIL_FIFO|  Sync Window End: ' + syncWindowEnd);
                System.debug('GMAIL_FIFO|  Backfill Complete: ' + gmailBackfillComplete);
            } else {
                // Outlook uses standard FIFO (oldest first API ordering)
                syncWindowStart = getLastSyncTime(workspaceUser.User__c, providerType);
                syncWindowEnd = DateTime.now();
            }
            
            // Create sync log record (In Progress)
            AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
                User__c = workspaceUser.User__c,
                Provider_Type__c = providerType,
                Record_Type__c = 'Email',
                Sync_Type__c = 'Scheduled',
                Status__c = 'In Progress',
                Start_Time__c = startTime,
                Sync_Window_Start__c = syncWindowStart,
                Sync_Window_End__c = syncWindowEnd
            );
            
            // Add Gmail-specific fields
            if (provider == 'Gmail') {
                syncLog.Gmail_Forward_Cursor__c = gmailForwardCursor;
                // Note: Gmail_Backfill_Complete__c removed - completion is determined by
                // checking if Sync_Window_End__c <= Sync_Window_Start__c (window closed)
            }
            
            // Insert sync log with FLS enforcement using FLSCheck
            List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ syncLog };
            List<AI_Workspace_Sync_Log__c> insertedLogs = FLSCheck.getInstance().insertDML(logsToInsert);
            if (insertedLogs != null && !insertedLogs.isEmpty()) {
                syncLog = insertedLogs[0]; // Update reference with inserted record
            }
            
            // Start the chainable queueable (runs in fresh transaction with new limits)
            // This is safe because the Finalizer will handle the next user chain
            // Pass workspaceUser.User__c as targetUserId so records are owned by the workspace user
            if (!Test.isRunningTest() && !disableChaining) {
                AIEmailSyncChainableQueueable chainableJob = new AIEmailSyncChainableQueueable(
                    syncLog.Id,
                    workspaceUser.Id,
                    workspaceUser.User__c, // Target User ID - records will be owned by this user
                    accessToken,
                    provider,
                    userEmail,
                    syncWindowStart,
                    syncWindowEnd
                );
                System.enqueueJob(chainableJob);
            } else {
                // In tests, run synchronously (limited but testable)
                AIEmailSyncChainableQueueable chainableJob = new AIEmailSyncChainableQueueable(
                    syncLog.Id,
                    workspaceUser.Id,
                    workspaceUser.User__c, // Target User ID - records will be owned by this user
                    accessToken,
                    provider,
                    userEmail,
                    syncWindowStart,
                    syncWindowEnd
                );
                // Explicitly cast null to QueueableContext to resolve method ambiguity
                chainableJob.execute((QueueableContext) null);
            }
            
        } catch (Exception e) {
            // Create failed sync log
            AI_Workspace_Sync_Log__c failedLog = new AI_Workspace_Sync_Log__c(
                User__c = workspaceUser.User__c,
                Provider_Type__c = providerType,
                Record_Type__c = 'Email',
                Sync_Type__c = 'Scheduled',
                Status__c = 'Failed',
                Start_Time__c = startTime,
                End_Time__c = DateTime.now(),
                Error_Message__c = e.getMessage()
            );
            // Insert failed log with FLS enforcement using FLSCheck
            List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ failedLog };
            FLSCheck.getInstance().insertDML(logsToInsert);
        }
    }
    
    /**
     * Wrapper class for Gmail two-pointer sync window
     */
    private class GmailSyncWindow {
        public DateTime forwardCursor;      // Start point for forward sync (newest email seen)
        public DateTime backfillCursor;     // Current position in backfill (oldest email processed)
        public DateTime lookbackBoundary;   // End point for backfill (based on lookback hours setting)
        public Boolean backfillComplete;    // Whether backfill has reached the lookback boundary
    }
    
    /**
     * Get Gmail two-pointer sync window
     * 
     * For Gmail, we need two cursors:
     * 1. Forward Cursor: Where to start fetching new emails (newest email we've seen)
     * 2. Backfill Cursor: Where we left off going backwards (oldest email we've processed)
     * 
     * First sync (no prior logs):
     * - Forward Cursor = NOW (start fetching from current time)
     * - Backfill Cursor = NOW (nothing processed yet, Gmail returns newest first)
     * - Lookback Boundary = NOW - lookback hours
     * - Backfill Complete = false
     * 
     * Subsequent syncs:
     * - Forward Cursor = Gmail_Forward_Cursor__c from last sync (newest email we've seen)
     * - Backfill Cursor = Sync_Window_End__c from last sync (oldest email we've processed)
     * - Lookback Boundary = Same as first sync calculation
     * - Backfill Complete = Sync_Window_End__c <= lookback boundary
     */
    private GmailSyncWindow getGmailTwoPointerSyncWindow(Id userId, String providerType) {
        GmailSyncWindow window = new GmailSyncWindow();
        
        // Calculate lookback boundary (this is fixed based on settings)
        Integer lookbackHours = AISyncSettingsService.getLookbackHours();
        if (lookbackHours == null || lookbackHours <= 0) {
            lookbackHours = 24; // Default to 24 hours
        }
        window.lookbackBoundary = DateTime.now().addHours(-lookbackHours);
        
        // Check for prior successful sync
        List<AI_Workspace_Sync_Log__c> lastLogs = [
            SELECT Id, Sync_Window_End__c, Gmail_Forward_Cursor__c
            FROM AI_Workspace_Sync_Log__c
            WHERE User__c = :userId
              AND Provider_Type__c = :providerType
              AND Record_Type__c = 'Email'
              AND Status__c IN ('Success', 'Partial')
            ORDER BY End_Time__c DESC
            LIMIT 1
        ];
        
        if (!lastLogs.isEmpty()) {
            AI_Workspace_Sync_Log__c lastLog = lastLogs[0];
            
            // Forward cursor: Use Gmail_Forward_Cursor__c if available, otherwise default to NOW
            // The forward cursor represents the newest email datetime we've processed
            window.forwardCursor = lastLog.Gmail_Forward_Cursor__c != null 
                ? lastLog.Gmail_Forward_Cursor__c 
                : DateTime.now();
            
            // Backfill cursor: Use Sync_Window_End__c (oldest email processed)
            // If null, default to NOW (nothing backfilled yet)
            window.backfillCursor = lastLog.Sync_Window_End__c != null 
                ? lastLog.Sync_Window_End__c 
                : DateTime.now();
            
            // Backfill complete check: 
            // During backfill: Sync_Window_End__c is the OLDEST email (goes backwards, always < forward cursor)
            // After backfill: Sync_Window_End__c is set to NOW (goes forward, >= forward cursor)
            // So if Sync_Window_End__c >= Gmail_Forward_Cursor__c, backfill is complete
            // Also check if backfill cursor has reached lookback boundary (original completion check)
            window.backfillComplete = (window.backfillCursor >= window.forwardCursor) || 
                                      (window.backfillCursor <= window.lookbackBoundary);
            
            if (window.backfillComplete) {
                // When backfill is complete, set backfillCursor to NOW
                // This ensures Sync_Window_End__c shows the current time (end of forward sync window)
                window.backfillCursor = DateTime.now();
                System.debug('GMAIL_FIFO|getGmailTwoPointerSyncWindow: Backfill complete - setting backfillCursor to NOW');
            }
            
            System.debug('GMAIL_FIFO|getGmailTwoPointerSyncWindow: Using prior sync log');
            System.debug('GMAIL_FIFO|  Last Gmail_Forward_Cursor__c: ' + lastLog.Gmail_Forward_Cursor__c);
            System.debug('GMAIL_FIFO|  Last Sync_Window_End__c: ' + lastLog.Sync_Window_End__c);
        } else {
            // First sync - use Run Now lookback time or default
            window.forwardCursor = DateTime.now();
            window.backfillCursor = DateTime.now(); // Gmail returns newest first, so we start here
            window.backfillComplete = false;
            
            System.debug('GMAIL_FIFO|getGmailTwoPointerSyncWindow: First sync - no prior logs');
        }
        
        return window;
    }
    
    /**
     * Get the last sync time from previous successful sync log
     * 
     * For Outlook (FIFO via API ordering):
     *   - Uses Sync_Window_End__c from last log as new start (incremental sync)
     *   - Outlook API supports oldest-first ordering, so this works naturally
     * 
     * For Gmail (FIFO via two-pointer sync):
     *   - Gmail uses getGmailTwoPointerSyncWindow() instead of this method
     *   - This method is kept for Outlook and Calendar/Task sync
     * 
     * For Run Now mode (first run):
     *   - Uses lookback settings (defaults to 24 hours if empty/0)
     */
    private DateTime getLastSyncTime(Id userId, String providerType) {
        // If Run Now mode, check if we should use lookback (only for first run)
        if (this.isRunNowMode) {
            DateTime lookbackTime = getRunNowLookbackTime(userId, providerType);
            if (lookbackTime != null) {
                System.debug('SYNC_WINDOW|getLastSyncTime: Run Now first sync - using lookback time = ' + lookbackTime);
                return lookbackTime;
            }
            // If getRunNowLookbackTime returns null, it means a prior sync exists
            // Fall through to use incremental sync logic below
        }
        
        // Determine record type based on current sync type
        String recordType;
        if (this.currentSyncType == SyncType.EMAIL) {
            recordType = 'Email';
        } else if (this.currentSyncType == SyncType.CALENDAR) {
            recordType = 'Calendar';
        } else if (this.currentSyncType == SyncType.TASK) {
            recordType = 'Task';
        }
        
        // Use incremental sync logic (for scheduled mode or run-now with existing logs)
        List<AI_Workspace_Sync_Log__c> lastLogs = [
            SELECT Id, Sync_Window_Start__c, Sync_Window_End__c, Record_Type__c
            FROM AI_Workspace_Sync_Log__c
            WHERE User__c = :userId
              AND Provider_Type__c = :providerType
              AND Record_Type__c = :recordType
              AND Status__c IN ('Success', 'Partial')
            ORDER BY End_Time__c DESC
            LIMIT 1
        ];
        
        if (!lastLogs.isEmpty() && lastLogs[0].Sync_Window_End__c != null) {
            // For Outlook: Use Sync_Window_End__c as the new start (oldest first pagination)
            // NOTE: Gmail email sync uses getGmailTwoPointerSyncWindow() instead
            System.debug('SYNC_WINDOW|getLastSyncTime: Outlook/Calendar/Task - using last sync end time = ' + lastLogs[0].Sync_Window_End__c);
            return lastLogs[0].Sync_Window_End__c;
        }
        
        // No prior successful sync - use sync-type specific default lookback
        DateTime defaultLookback = getDefaultLookbackTime();
        System.debug('SYNC_WINDOW|getLastSyncTime: No prior sync - using default lookback = ' + defaultLookback);
        return defaultLookback;
    }
    
    // NOTE: getGmailSyncWindowEnd() method removed - replaced by getGmailTwoPointerSyncWindow()
    // The two-pointer approach handles Gmail sync window calculation for both forward and backfill sync
    
    /**
     * Get Run Now lookback time based on sync type and settings
     * NEW BEHAVIOR (2026-02-10):
     * - First checks if a prior sync log exists for this user + service type + provider
     * - If sync log exists: returns null (falls back to incremental sync using Sync_Window_End__c)
     * - If no sync log: uses lookback hours/days from settings (defaults to 24 hours if empty/0)
     * 
     * Returns null if prior sync exists (will fall back to incremental sync)
     */
    private DateTime getRunNowLookbackTime(Id userId, String providerType) {
        // Determine record type based on current sync type
        String recordType;
        if (this.currentSyncType == SyncType.EMAIL) {
            recordType = 'Email';
        } else if (this.currentSyncType == SyncType.CALENDAR) {
            recordType = 'Calendar';
        } else if (this.currentSyncType == SyncType.TASK) {
            recordType = 'Task';
        }
        
        // Check if a prior sync log exists for this user + service type + provider
        List<AI_Workspace_Sync_Log__c> existingLogs = [
            SELECT Id, Sync_Window_End__c, End_Time__c, Status__c
            FROM AI_Workspace_Sync_Log__c
            WHERE User__c = :userId
              AND Provider_Type__c = :providerType
              AND Record_Type__c = :recordType
              AND Status__c IN ('Success', 'Partial')
            ORDER BY End_Time__c DESC
            LIMIT 1
        ];
        
        // If a prior sync log exists, return null to use incremental sync
        if (!existingLogs.isEmpty()) {
            return null;
        }
        
        // No prior sync log exists - use lookback settings or default to 24 hours
        
        if (this.currentSyncType == SyncType.EMAIL) {
            Integer lookbackHours = AISyncSettingsService.getLookbackHours();
            // If lookback is null, 0, or negative, default to 24 hours
            if (lookbackHours == null || lookbackHours <= 0) {
                lookbackHours = 24;
            }
            return DateTime.now().addHours(-lookbackHours);
        } else if (this.currentSyncType == SyncType.CALENDAR) {
            Integer lookbackDays = AISyncSettingsService.getCalendarLookbackDays();
            // If lookback is null, 0, or negative, default to 7 days
            if (lookbackDays == null || lookbackDays <= 0) {
                lookbackDays = 7;
            }
            return DateTime.now().addDays(-lookbackDays);
        } else if (this.currentSyncType == SyncType.TASK) {
            Integer lookbackDays = AISyncSettingsService.getTaskLookbackDays();
            // If lookback is null, 0, or negative, default to 7 days
            if (lookbackDays == null || lookbackDays <= 0) {
                lookbackDays = 7;
            }
            return DateTime.now().addDays(-lookbackDays);
        }
        
        // Fallback to 24 hours
        return DateTime.now().addHours(-24);
    }
    
    /**
     * Get default lookback time when no prior sync exists
     * Uses sync-type specific defaults from settings
     */
    private DateTime getDefaultLookbackTime() {
        if (this.currentSyncType == SyncType.EMAIL) {
            // FIXED: Use Lookback_Hours__c from settings instead of hardcoded 24 hours
            Integer lookbackHours = AISyncSettingsService.getLookbackHours();
            if (lookbackHours == null || lookbackHours <= 0) {
                lookbackHours = 24; // Default to 24 if not set
            }
            return DateTime.now().addHours(-lookbackHours);
        } else if (this.currentSyncType == SyncType.CALENDAR) {
            Integer lookbackDays = AISyncSettingsService.getCalendarLookbackDays();
            return DateTime.now().addDays(-(lookbackDays != null ? lookbackDays : 7));
        } else if (this.currentSyncType == SyncType.TASK) {
            Integer lookbackDays = AISyncSettingsService.getTaskLookbackDays();
            return DateTime.now().addDays(-(lookbackDays != null ? lookbackDays : 7));
        }
        
        // Fallback to 24 hours
        return DateTime.now().addHours(-24);
    }
    
    /**
     * Update refresh token if rotated
     * Uses the token owner's user ID for encryption, not the running user
     */
    private void updateRefreshToken(Id workspaceUserId, Id tokenOwnerId, String newRefreshToken, String provider) {
        try {
            // Encrypt token using the token owner's key (OrgId + tokenOwnerId + GPTfy salt)
            // This is critical: scheduler runs as admin but must encrypt with the token owner's key
            String encryptedToken;
            if (provider == 'Outlook') {
                encryptedToken = AIOutlookOAuthController.encryptRefreshToken(newRefreshToken, tokenOwnerId);
            } else {
                encryptedToken = AIGmailOAuthController.encryptRefreshToken(newRefreshToken, tokenOwnerId);
            }
            
            AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
                Id = workspaceUserId,
                Refresh_Token__c = encryptedToken
            );
            // Update workspace user with FLS enforcement using FLSCheck
            List<AI_Workspace_User__c> usersToUpdate = new List<AI_Workspace_User__c>{ workspaceUser };
            FLSCheck.getInstance().updateDML(usersToUpdate);
        } catch (Exception e) {
            // Error updating refresh token
        }
    }
    
    /**
     * Handle authentication failure
     */
    private void handleAuthFailure(AI_Workspace_User__c workspaceUser, String errorMessage) {
        // Create a failed sync log entry
        // Determine record type based on current sync type
        String recordType = 'Email'; // Default
        if (this.currentSyncType == SyncType.CALENDAR) {
            recordType = 'Calendar';
        } else if (this.currentSyncType == SyncType.TASK) {
            recordType = 'Task';
        }
        
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = workspaceUser.Provider__c == 'Outlook' ? 'MICROSOFT_EMAIL' : 'GMAIL_EMAIL',
            Record_Type__c = recordType,
            Sync_Type__c = 'Scheduled',
            Status__c = 'Failed',
            Start_Time__c = DateTime.now(),
            End_Time__c = DateTime.now(),
            Error_Message__c = 'Authentication failed: ' + errorMessage
        );
        
        try {
            // Insert sync log with FLS enforcement
            // Insert sync log with FLS enforcement using FLSCheck
            List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ syncLog };
            FLSCheck.getInstance().insertDML(logsToInsert);
        } catch (Exception e) {
            // Error creating sync log
        }
    }
    
    /**
     * Log sync error
     */
    private void logSyncError(AI_Workspace_User__c workspaceUser, SyncType syncType, Exception e) {
        // The individual sync services should have already logged their own errors
        // This is just for unexpected exceptions
    }
    
    /**
     * Prepare chain to next sync type or user
     * Sets state for the Finalizer to handle
     */
    private void prepareChainToNext() {
        if (disableChaining || Test.isRunningTest()) {
            return;
        }
        
        // Determine next sync type and index
        nextIndex = currentIndex;
        
        switch on currentSyncType {
            when EMAIL {
                if (AISyncSettingsService.isCalendarSyncEnabled()) {
                    nextSyncType = SyncType.CALENDAR;
                } else if (AISyncSettingsService.isTaskSyncEnabled()) {
                    nextSyncType = SyncType.TASK;
                } else {
                    nextIndex = currentIndex + 1;
                    nextSyncType = SyncType.EMAIL;
                }
            }
            when CALENDAR {
                if (AISyncSettingsService.isTaskSyncEnabled()) {
                    nextSyncType = SyncType.TASK;
                } else {
                    nextIndex = currentIndex + 1;
                    nextSyncType = SyncType.EMAIL;
                }
            }
            when TASK {
                nextIndex = currentIndex + 1;
                nextSyncType = SyncType.EMAIL;
            }
        }
        
        // Check if more users to process
        if (nextIndex >= workspaceUserIds.size()) {
            shouldChain = false;
            return;
        }
        
        // Mark for chaining via Finalizer
        // Note: In run-now mode, workspaceUserIds contains ONLY the current user's providers
        // So we process all of them (e.g., both Outlook and Gmail for the same user)
        shouldChain = true;
    }
    
    /**
     * Send re-authentication notification to user
     */
    private void sendReAuthNotification(AI_Workspace_User__c workspaceUser) {
        try {
            // Get notification type
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
            // Failed to send re-auth notification
        }
    }
    
    /**
     * Internal token result wrapper
     */
    private class TokenResult {
        public Boolean isSuccess;
        public String accessToken;
        public String refreshToken;
        public String errorMessage;
        
        public TokenResult(Boolean success, String access, String refresh, String error) {
            this.isSuccess = success;
            this.accessToken = access;
            this.refreshToken = refresh;
            this.errorMessage = error;
        }
    }
}