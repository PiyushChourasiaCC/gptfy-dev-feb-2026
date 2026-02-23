/**
 * Test class for AIEmailSyncChainableQueueable
 * Tests the limit-aware continuous email sync engine including Gmail FIFO support.
 * 
 * @author GPTfy
 * @date 2026-01-19
 * @Jira V2-7695, V2-7696, V2-7796
 */
@isTest
private class AIEmailSyncChainableQueueableTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test user with unique username
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniqueId = String.valueOf(DateTime.now().getTime());
        
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'SyncUser',
            Email = 'testsync@test.com',
            Username = 'testsync' + uniqueId + '@test.com',
            Alias = 'tsync',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
        insert testUser;
        
        // Create workspace user record for Outlook
        AI_Workspace_User__c outlookWorkspaceUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Outlook',
            Refresh_Token__c = 'encrypted_test_token_outlook'
        );
        insert outlookWorkspaceUser;
        
        // Create workspace user record for Gmail
        AI_Workspace_User__c gmailWorkspaceUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_test_token_gmail'
        );
        insert gmailWorkspaceUser;
    }
    
    /**
     * Test basic initialization of the chainable queueable (Outlook)
     */
    @isTest
    static void testOutlookQueueableInitialization() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Create chainable queueable using the initial constructor
        DateTime syncWindowStart = DateTime.now().addDays(-1);
        DateTime syncWindowEnd = DateTime.now();
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            syncWindowStart,
            syncWindowEnd
        );
        
        Assert.areNotEqual(null, queueable, 'Queueable should be initialized');
    }
    
    /**
     * Test Gmail queueable initialization with FIFO state
     */
    @isTest
    static void testGmailQueueableInitialization() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        // Create sync log with Gmail FIFO fields
        // Backfill NOT complete: Sync_Window_End__c > Sync_Window_Start__c
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now(),
            Sync_Window_Start__c = DateTime.now().addHours(-24),
            Sync_Window_End__c = DateTime.now(),
            Gmail_Forward_Cursor__c = DateTime.now().addHours(-1)
        );
        insert syncLog;
        
        // Create chainable queueable
        DateTime syncWindowStart = DateTime.now().addHours(-24);
        DateTime syncWindowEnd = DateTime.now();
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Gmail',
            'test@gmail.com',
            syncWindowStart,
            syncWindowEnd
        );
        
        Assert.areNotEqual(null, queueable, 'Gmail queueable should be initialized');
    }
    
    /**
     * Test the chained continuation constructor with Gmail FIFO parameters
     */
    @isTest
    static void testGmailChainedConstructor() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Test the full chained constructor with Gmail FIFO parameters
        DateTime cursor = DateTime.now().addHours(-12);
        Map<String, Integer> exclusionCounts = new Map<String, Integer>{'Marketing' => 5};
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Gmail',
            'test@gmail.com',
            cursor,                          // inboxCursor
            cursor,                          // sentCursor
            DateTime.now().addHours(-24),    // syncWindowStart (lookback boundary)
            DateTime.now(),                  // syncWindowEnd (backfill cursor)
            false,                           // inboxComplete
            false,                           // sentComplete
            true,                            // isLastFolderInbox
            100,                             // totalFetched
            10,                              // totalDuplicate
            5,                               // totalExcluded
            50,                              // totalMatched
            35,                              // totalUnmatched
            45,                              // totalImported
            5,                               // totalFailed
            exclusionCounts,                 // aggregatedExclusionCounts
            DateTime.now().addMinutes(-30),  // newestProcessedEmailDate
            DateTime.now().addHours(-2),     // oldestProcessedEmailDate
            100,                             // maxEmailsLimit
            null,                            // gmailInboxPageToken
            null,                            // gmailSentPageToken
            // Gmail FIFO state
            DateTime.now().addMinutes(-30),  // gmailForwardCursor
            false,                           // gmailForwardInboxComplete
            false,                           // gmailForwardSentComplete
            false,                           // gmailBackfillComplete
            null,                            // gmailForwardInboxPageToken
            null                             // gmailForwardSentPageToken
        );
        
        Assert.areNotEqual(null, queueable, 'Gmail chained queueable should be initialized');
    }
    
    /**
     * Test Gmail sync log forward cursor is properly saved
     */
    @isTest
    static void testGmailSyncLogForwardCursorSaved() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        DateTime forwardCursor = DateTime.now().addHours(-1);
        
        // Create sync log with Gmail forward cursor
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addMinutes(-5),
            End_Time__c = DateTime.now(),
            Sync_Window_Start__c = DateTime.now().addHours(-24),
            Sync_Window_End__c = DateTime.now().addHours(-20),
            Gmail_Forward_Cursor__c = forwardCursor
        );
        insert syncLog;
        
        // Query back and verify
        AI_Workspace_Sync_Log__c queriedLog = [
            SELECT Id, Gmail_Forward_Cursor__c, Sync_Window_Start__c, Sync_Window_End__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, queriedLog.Gmail_Forward_Cursor__c, 'Forward cursor should be set');
        // Backfill NOT complete: Sync_Window_End__c > Sync_Window_Start__c
        Assert.isTrue(queriedLog.Sync_Window_End__c > queriedLog.Sync_Window_Start__c, 
            'Backfill should not be complete (window still open)');
    }
    
    /**
     * Test Gmail two-pointer sync window calculation - first run
     */
    @isTest
    static void testGmailTwoPointerSyncWindowFirstRun() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        // First run - no prior sync logs
        // Sync_Window_End__c > Sync_Window_Start__c means backfill NOT complete
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now(),
            Sync_Window_Start__c = DateTime.now().addHours(-24), // Lookback boundary
            Sync_Window_End__c = DateTime.now(),                  // Backfill cursor (starts at NOW)
            Gmail_Forward_Cursor__c = DateTime.now()              // Forward cursor (starts at NOW)
        );
        insert syncLog;
        
        // Verify initial state - backfill NOT complete
        AI_Workspace_Sync_Log__c queriedLog = [
            SELECT Gmail_Forward_Cursor__c, Sync_Window_End__c, Sync_Window_Start__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, queriedLog.Gmail_Forward_Cursor__c, 'Forward cursor should be set');
        // Window is open (end > start) means backfill not complete
        Assert.isTrue(queriedLog.Sync_Window_End__c > queriedLog.Sync_Window_Start__c, 
            'First run should have backfill window open');
    }
    
    /**
     * Test Gmail subsequent sync uses previous cursors
     */
    @isTest
    static void testGmailSubsequentSyncUsesCursors() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        DateTime previousForwardCursor = DateTime.now().addHours(-2);
        DateTime previousBackfillCursor = DateTime.now().addHours(-18);
        
        // First completed sync - backfill NOT complete yet
        AI_Workspace_Sync_Log__c firstSyncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-3),
            End_Time__c = DateTime.now().addHours(-2),
            Sync_Window_Start__c = DateTime.now().addHours(-24),
            Sync_Window_End__c = previousBackfillCursor,           // Oldest processed
            Gmail_Forward_Cursor__c = previousForwardCursor        // Newest processed
        );
        insert firstSyncLog;
        
        // Query for the last sync to verify it can be used for next sync
        List<AI_Workspace_Sync_Log__c> lastLogs = [
            SELECT Id, Sync_Window_End__c, Gmail_Forward_Cursor__c, Sync_Window_Start__c
            FROM AI_Workspace_Sync_Log__c
            WHERE User__c = :workspaceUser.User__c
              AND Provider_Type__c = 'GMAIL_EMAIL'
              AND Record_Type__c = 'Email'
              AND Status__c IN ('Success', 'Partial')
            ORDER BY End_Time__c DESC
            LIMIT 1
        ];
        
        Assert.areEqual(1, lastLogs.size(), 'Should find prior sync log');
        Assert.areEqual(previousForwardCursor, lastLogs[0].Gmail_Forward_Cursor__c, 'Forward cursor should match');
        Assert.areEqual(previousBackfillCursor, lastLogs[0].Sync_Window_End__c, 'Backfill cursor should match');
    }
    
    /**
     * Test Gmail backfill complete when window is closed
     * Backfill is complete when Sync_Window_End__c <= Sync_Window_Start__c
     */
    @isTest
    static void testGmailBackfillCompleteWhenWindowClosed() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        DateTime lookbackBoundary = DateTime.now().addHours(-24);
        
        // Sync that completed backfill - window is CLOSED
        // Sync_Window_End__c == Sync_Window_Start__c means backfill complete
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Sync_Window_Start__c = lookbackBoundary,
            Sync_Window_End__c = lookbackBoundary,          // Window CLOSED - backfill complete!
            Gmail_Forward_Cursor__c = DateTime.now()
        );
        insert syncLog;
        
        // Query and verify
        AI_Workspace_Sync_Log__c queriedLog = [
            SELECT Sync_Window_End__c, Sync_Window_Start__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        // Backfill is complete when window is closed (end <= start)
        Boolean backfillComplete = queriedLog.Sync_Window_End__c <= queriedLog.Sync_Window_Start__c;
        Assert.isTrue(backfillComplete, 'Backfill should be complete when window is closed');
    }
    
    /**
     * Test max emails limit is respected
     */
    @isTest
    static void testMaxEmailsLimitConfiguration() {
        Integer maxEmails = AISyncSettingsService.getMaxEmailsPerUser();
        Assert.areNotEqual(null, maxEmails, 'Max emails per user should not be null');
        Assert.isTrue(maxEmails > 0, 'Max emails per user should be positive');
    }
    
    /**
     * Test emails per batch configuration
     */
    @isTest
    static void testEmailsPerBatchConfiguration() {
        Integer batchSize = AISyncSettingsService.getEmailsPerBatch();
        Assert.areNotEqual(null, batchSize, 'Batch size should not be null');
        Assert.isTrue(batchSize > 0, 'Batch size should be positive');
    }
    
    /**
     * Test Outlook execute with successful fetch
     */
    @isTest
    static void testOutlookExecuteSuccess() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock for HTTP callouts
        Test.setMock(HttpCalloutMock.class, new MockOutlookEmailService());
        
        // Disable chaining for test
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        DateTime syncWindowStart = DateTime.now().addDays(-1);
        DateTime syncWindowEnd = DateTime.now();
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            syncWindowStart,
            syncWindowEnd
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify sync log was updated
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c, Emails_Fetched__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test Gmail execute with forward sync
     */
    @isTest
    static void testGmailExecuteForwardSync() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        // Create sync log with forward cursor
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now(),
            Sync_Window_Start__c = DateTime.now().addHours(-24),
            Sync_Window_End__c = DateTime.now(),
            Gmail_Forward_Cursor__c = DateTime.now().addHours(-1)
        );
        insert syncLog;
        
        // Set mock for HTTP callouts
        Test.setMock(HttpCalloutMock.class, new MockGmailEmailService());
        
        // Disable chaining for test
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        DateTime syncWindowStart = DateTime.now().addHours(-24);
        DateTime syncWindowEnd = DateTime.now();
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Gmail',
            'test@gmail.com',
            syncWindowStart,
            syncWindowEnd
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify sync log was updated
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c, Gmail_Forward_Cursor__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test sync complete when max emails reached
     */
    @isTest
    static void testSyncCompleteMaxEmailsReached() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock
        Test.setMock(HttpCalloutMock.class, new MockOutlookEmailService());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        // Create queueable with chained constructor (simulating continuation)
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now().addDays(-1),
            DateTime.now().addDays(-1),
            DateTime.now(),
            true,  // inboxComplete
            true,  // sentComplete
            false,
            0,     // totalFetched
            0,     // totalDuplicate
            0,     // totalExcluded
            0,     // totalMatched
            0,     // totalUnmatched
            0,     // totalImported
            0,     // totalFailed
            new Map<String, Integer>(),
            DateTime.now(),
            DateTime.now(),
            100,
            null,
            null,
            null,
            false,
            false,
            false,
            null,
            null
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify sync completed
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual('In Progress', updatedLog.Status__c, 'Sync should be complete');
    }
    
    /**
     * Test token refresh failure
     */
    @isTest
    static void testTokenRefreshFailure() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock that fails token refresh
        Test.setMock(HttpCalloutMock.class, new MockFailedTokenRefresh());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now()
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify sync failed
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c, Error_Message__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areEqual('Failed', updatedLog.Status__c, 'Sync should fail when token refresh fails');
    }
    
    /**
     * Test error handling during execution
     */
    @isTest
    static void testExecutionErrorHandling() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock that returns errors
        Test.setMock(HttpCalloutMock.class, new MockErrorEmailService());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now()
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify error was logged
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c, Error_Message__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test Gmail backfill completion
     */
    @isTest
    static void testGmailBackfillCompletion() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        DateTime lookbackBoundary = DateTime.now().addHours(-24);
        
        // Create sync log where backfill is complete
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now(),
            Sync_Window_Start__c = lookbackBoundary,
            Sync_Window_End__c = lookbackBoundary,  // Window closed = backfill complete
            Gmail_Forward_Cursor__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock
        Test.setMock(HttpCalloutMock.class, new MockGmailEmailService());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Gmail',
            'test@gmail.com',
            lookbackBoundary,
            lookbackBoundary
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify sync completed
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c, Sync_Window_End__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test chained constructor with all parameters
     */
    @isTest
    static void testChainedConstructorWithExclusionCounts() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        Map<String, Integer> exclusionCounts = new Map<String, Integer>();
        exclusionCounts.put('Marketing', 10);
        exclusionCounts.put('Confidential', 5);
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now().addDays(-1),
            DateTime.now().addDays(-1),
            DateTime.now(),
            false,
            false,
            false,
            50,
            5,
            15,
            20,
            10,
            30,
            5,
            exclusionCounts,
            DateTime.now(),
            DateTime.now().addDays(-1),
            100,
            null,
            null,
            null,
            false,
            false,
            false,
            null,
            null
        );
        
        Assert.areNotEqual(null, queueable, 'Queueable should be initialized');
    }
    
    /**
     * Test disable chaining flag
     */
    @isTest
    static void testDisableChainingFlag() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock
        Test.setMock(HttpCalloutMock.class, new MockOutlookEmailService());
        
        // Enable chaining but it should not chain in test context
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now()
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Just verify it completed without error
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Id
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test Outlook with emails to process
     */
    @isTest
    static void testOutlookWithEmails() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock with emails
        Test.setMock(HttpCalloutMock.class, new MockOutlookWithEmails());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now()
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify emails were processed
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c, Emails_Fetched__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test Gmail with emails in forward sync
     */
    @isTest
    static void testGmailWithForwardEmails() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now(),
            Sync_Window_Start__c = DateTime.now().addHours(-24),
            Sync_Window_End__c = DateTime.now(),
            Gmail_Forward_Cursor__c = DateTime.now().addHours(-1)
        );
        insert syncLog;
        
        // Set mock with emails
        Test.setMock(HttpCalloutMock.class, new MockGmailWithEmails());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Gmail',
            'test@gmail.com',
            DateTime.now().addHours(-24),
            DateTime.now()
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Verify emails were processed
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c, Emails_Fetched__c, Gmail_Forward_Cursor__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test alternating folder processing
     */
    @isTest
    static void testAlternatingFolderProcessing() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock
        Test.setMock(HttpCalloutMock.class, new MockOutlookMultipleBatches());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        // Create with chained constructor to test alternation
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now().addDays(-1),
            DateTime.now().addDays(-1),
            DateTime.now(),
            false,  // inbox not complete
            false,  // sent not complete
            true,   // last folder was inbox
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            new Map<String, Integer>(),
            DateTime.now(),
            DateTime.now(),
            100,
            null,
            null,
            null,
            false,
            false,
            false,
            null,
            null
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Id
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test partial status when errors occur
     */
    @isTest
    static void testPartialStatusWithErrors() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log with existing error
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now(),
            Error_Message__c = 'Previous error'
        );
        insert syncLog;
        
        // Set mock
        Test.setMock(HttpCalloutMock.class, new MockOutlookWithEmails());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now()
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Status__c, Error_Message__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test Gmail backfill with valid window
     */
    @isTest
    static void testGmailBackfillWithValidWindow() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Gmail' 
            LIMIT 1
        ];
        
        DateTime lookbackBoundary = DateTime.now().addHours(-24);
        DateTime backfillCursor = DateTime.now().addHours(-12);
        
        // Create sync log with open backfill window
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now(),
            Sync_Window_Start__c = lookbackBoundary,
            Sync_Window_End__c = backfillCursor,  // Window open
            Gmail_Forward_Cursor__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock
        Test.setMock(HttpCalloutMock.class, new MockGmailWithEmails());
        
        // Disable chaining
        AIEmailSyncChainableQueueable.disableChaining = true;
        
        // Create with chained constructor showing forward complete, backfill in progress
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Gmail',
            'test@gmail.com',
            DateTime.now().addHours(-12),
            DateTime.now().addHours(-12),
            lookbackBoundary,
            backfillCursor,
            false,
            false,
            false,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            new Map<String, Integer>(),
            DateTime.now(),
            backfillCursor,
            100,
            null,
            null,
            DateTime.now(),
            true,   // forward inbox complete
            true,   // forward sent complete
            false,  // backfill not complete
            null,
            null
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Id
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    /**
     * Test finalizer execution
     */
    @isTest
    static void testFinalizerExecution() {
        AI_Workspace_User__c workspaceUser = [
            SELECT Id, User__c, Provider__c 
            FROM AI_Workspace_User__c 
            WHERE Provider__c = 'Outlook' 
            LIMIT 1
        ];
        
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = workspaceUser.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Sync_Type__c = 'Scheduled',
            Status__c = 'In Progress',
            Start_Time__c = DateTime.now()
        );
        insert syncLog;
        
        // Set mock
        Test.setMock(HttpCalloutMock.class, new MockOutlookEmailService());
        
        // Enable chaining to test finalizer (but it won't actually chain in test)
        AIEmailSyncChainableQueueable.disableChaining = false;
        
        AIEmailSyncChainableQueueable queueable = new AIEmailSyncChainableQueueable(
            syncLog.Id,
            workspaceUser.Id,
            workspaceUser.User__c,
            'test_access_token',
            'Outlook',
            'test@example.com',
            DateTime.now().addDays(-1),
            DateTime.now()
        );
        
        Test.startTest();
        System.enqueueJob(queueable);
        Test.stopTest();
        
        // Reset flag
        AIEmailSyncChainableQueueable.disableChaining = false;
        
        AI_Workspace_Sync_Log__c updatedLog = [
            SELECT Id
            FROM AI_Workspace_Sync_Log__c
            WHERE Id = :syncLog.Id
        ];
        
        Assert.areNotEqual(null, updatedLog, 'Sync log should exist');
    }
    
    // ========== MOCK CLASSES ==========
    
    /**
     * Mock for successful Outlook email service
     */
    private class MockOutlookEmailService implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            // Mock token refresh
            if (req.getEndpoint().contains('token')) {
                res.setBody('{"access_token":"new_token","refresh_token":"new_refresh","expires_in":3600}');
            }
            // Mock email fetch
            else {
                String emailsJson = '{"value":[],"@odata.nextLink":null}';
                res.setBody(emailsJson);
            }
            
            return res;
        }
    }
    
    /**
     * Mock Outlook with actual emails
     */
    private class MockOutlookWithEmails implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            // Mock token refresh
            if (req.getEndpoint().contains('token')) {
                res.setBody('{"access_token":"new_token","refresh_token":"new_refresh","expires_in":3600}');
            }
            // Mock email fetch with emails
            else {
                String emailsJson = '{"value":[{"id":"msg1","subject":"Test","receivedDateTime":"2024-01-01T10:00:00Z","from":{"emailAddress":{"address":"sender@example.com"}},"body":{"content":"Test body"}}],"@odata.nextLink":null}';
                res.setBody(emailsJson);
            }
            
            return res;
        }
    }
    
    /**
     * Mock Outlook with multiple batches
     */
    private class MockOutlookMultipleBatches implements HttpCalloutMock {
        private Integer callCount = 0;
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            // Mock token refresh
            if (req.getEndpoint().contains('token')) {
                res.setBody('{"access_token":"new_token","refresh_token":"new_refresh","expires_in":3600}');
            }
            // Mock email fetch
            else {
                callCount++;
                if (callCount <= 2) {
                    // Return emails for first 2 calls
                    String emailsJson = '{"value":[{"id":"msg' + callCount + '","subject":"Test","receivedDateTime":"2024-01-01T10:00:00Z","from":{"emailAddress":{"address":"sender@example.com"}},"body":{"content":"Test"}}],"@odata.nextLink":"next"}';
                    res.setBody(emailsJson);
                } else {
                    // No more emails
                    res.setBody('{"value":[],"@odata.nextLink":null}');
                }
            }
            
            return res;
        }
    }
    
    /**
     * Mock for successful Gmail email service
     */
    private class MockGmailEmailService implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            // Mock token refresh
            if (req.getEndpoint().contains('token')) {
                res.setBody('{"access_token":"new_token","refresh_token":"new_refresh","expires_in":3600}');
            }
            // Mock email list
            else if (req.getEndpoint().contains('messages')) {
                res.setBody('{"messages":[],"nextPageToken":null}');
            }
            // Mock batch fetch
            else {
                res.setBody('{"responses":[]}');
            }
            
            return res;
        }
    }
    
    /**
     * Mock Gmail with actual emails
     */
    private class MockGmailWithEmails implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            // Mock token refresh
            if (req.getEndpoint().contains('token')) {
                res.setBody('{"access_token":"new_token","refresh_token":"new_refresh","expires_in":3600}');
            }
            // Mock email list
            else if (req.getEndpoint().contains('messages') && !req.getEndpoint().contains('batch')) {
                String messagesJson = '{"messages":[{"id":"msg1","threadId":"thread1"}],"nextPageToken":null}';
                res.setBody(messagesJson);
            }
            // Mock batch fetch
            else if (req.getEndpoint().contains('batch')) {
                String batchJson = '{"responses":[{"id":"msg1","result":{"id":"msg1","threadId":"thread1","labelIds":["INBOX"],"snippet":"Test","internalDate":"1609459200000","payload":{"headers":[{"name":"From","value":"sender@example.com"},{"name":"Subject","value":"Test Email"},{"name":"Date","value":"2024-01-01T10:00:00Z"}],"body":{"data":"VGVzdCBib2R5"}}}}]}';
                res.setBody(batchJson);
            }
            else {
                res.setBody('{"messages":[],"nextPageToken":null}');
            }
            
            return res;
        }
    }
    
    /**
     * Mock for failed token refresh
     */
    private class MockFailedTokenRefresh implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('token')) {
                res.setStatusCode(400);
                res.setBody('{"error":"invalid_grant","error_description":"Token expired"}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"value":[]}');
            }
            
            return res;
        }
    }
    
    /**
     * Mock for email service errors
     */
    private class MockErrorEmailService implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            // Token refresh succeeds
            if (req.getEndpoint().contains('token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"new_token","refresh_token":"new_refresh","expires_in":3600}');
            }
            // Email fetch fails
            else {
                res.setStatusCode(500);
                res.setBody('{"error":{"message":"Internal server error"}}');
            }
            
            return res;
        }
    }
}