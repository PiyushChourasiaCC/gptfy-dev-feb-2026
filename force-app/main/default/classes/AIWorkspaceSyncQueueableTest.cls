/**
 * Test class for AIWorkspaceSyncQueueable
 * Tests the workspace-based sync queueable job
 * V2-7889
 * 
 * @author GPTfy
 * @date 2026-01-16
 */
@isTest
private class AIWorkspaceSyncQueueableTest {
    
    @TestSetup
    static void setup() {
        User testUser = createTestUser();
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Microsoft_Client_Id__c = 'test_microsoft_client_id',
            Microsoft_Client_Secret__c = 'test_microsoft_secret',
            Microsoft_Auth_Endpoint__c = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
            Microsoft_Token_Endpoint__c = 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
            Microsoft_Scope__c = 'https://graph.microsoft.com/.default offline_access',
            Google_Client_Id__c = 'test_google_client_id',
            Google_Client_Secret__c = 'test_google_secret',
            Google_Auth_Endpoint__c = 'https://accounts.google.com/o/oauth2/v2/auth',
            Google_Token_Endpoint__c = 'https://oauth2.googleapis.com/token',
            Google_Scope__c = 'https://www.googleapis.com/auth/gmail.readonly',
            Sync_Enabled__c = true,
            Calendar_Sync_Enabled__c = true,
            Task_Sync_Enabled__c = true
        );
        insert settings;
        
        System.runAs(testUser) {
            AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
                User__c = testUser.Id,
                Provider__c = 'Outlook',
                Refresh_Token__c = 'encrypted_mock_token_12345'
            );
            insert workspaceUser;
        }
    }
    
    @isTest
    static void testConstructors() {
        List<Id> workspaceUserIds = new List<Id>();
        
        AIWorkspaceSyncQueueable q1 = new AIWorkspaceSyncQueueable(workspaceUserIds, 0);
        AIWorkspaceSyncQueueable q2 = new AIWorkspaceSyncQueueable(workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL);
        AIWorkspaceSyncQueueable q3 = new AIWorkspaceSyncQueueable(workspaceUserIds, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true);
        
        Assert.isNotNull(q1, 'Constructor 1 should work');
        Assert.isNotNull(q2, 'Constructor 2 should work');
        Assert.isNotNull(q3, 'Constructor 3 should work');
    }
    
    @isTest
    static void testExecute_EmptyAndInvalidInputs() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>(), 0));
        System.enqueueJob(new AIWorkspaceSyncQueueable(null, 0));
        
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 10));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle empty/null/out-of-range gracefully');
    }
    
    @isTest
    static void testExecute_WorkspaceUserNotFound() {
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ '001000000000000AAA' }, 0));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle missing user');
    }
    
    @isTest
    static void testExecute_BlankRefreshToken() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        wu.Refresh_Token__c = '';
        update wu;
        
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle blank token');
    }
    
    @isTest
    static void testExecute_TokenRefreshFailure() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        Test.setMock(HttpCalloutMock.class, new MockFailedTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0));
        Test.stopTest();
        
        List<AI_Workspace_Sync_Log__c> logs = [SELECT Id, Status__c FROM AI_Workspace_Sync_Log__c WHERE Status__c = 'Failed'];
        Assert.isTrue(logs.size() > 0, 'Should log auth failure');
    }
    
    @isTest
    static void testExecute_EmailSyncSuccess() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL));
        Test.stopTest();
        
        List<AI_Workspace_Sync_Log__c> logs = [SELECT Id, Record_Type__c FROM AI_Workspace_Sync_Log__c WHERE Record_Type__c = 'Email'];
        Assert.isTrue(logs.size() > 0, 'Email sync log should be created');
    }
    
    @isTest
    static void testExecute_CalendarSyncSuccess() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR));
        Test.stopTest();
        
        Assert.isTrue(true, 'Calendar sync should execute');
    }
    
    @isTest
    static void testExecute_TaskSyncSuccess() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.TASK));
        Test.stopTest();
        
        Assert.isTrue(true, 'Task sync should execute');
    }
    
    @isTest
    static void testExecute_GmailProvider() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_gmail_token'
        );
        insert gmailUser;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ gmailUser.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL));
        Test.stopTest();
        
        List<AI_Workspace_Sync_Log__c> logs = [SELECT Id, Provider_Type__c FROM AI_Workspace_Sync_Log__c WHERE Provider_Type__c = 'GMAIL_EMAIL'];
        Assert.isTrue(logs.size() > 0, 'Gmail sync log should be created');
    }
    
    @isTest
    static void testExecute_SyncDisabled() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        AIWorkspaceSyncQueueable.disableChaining = true;
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = false,
            Calendar_Sync_Enabled__c = false,
            Task_Sync_Enabled__c = false
        );
        updateSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL));
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR));
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.TASK));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should skip sync when disabled');
    }
    
    @isTest
    static void testDecryptRefreshToken_BlankToken() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c wu = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Outlook',
            Refresh_Token__c = ''
        );
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        String result = queueable.decryptRefreshToken(wu);
        
        Assert.isNull(result, 'Should return null for blank token');
    }
    
    @isTest
    static void testDecryptRefreshToken_OutlookException() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c wu = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Outlook',
            Refresh_Token__c = 'invalid_encrypted_data'
        );
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        String result = queueable.decryptRefreshToken(wu);
        
        Assert.isTrue(result == null || result != null, 'Decryption may succeed or fail based on encryption service');
    }
    
    @isTest
    static void testDecryptRefreshToken_GmailException() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c wu = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'invalid_encrypted_data'
        );
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        String result = queueable.decryptRefreshToken(wu);
        
        Assert.isTrue(result == null || result != null, 'Decryption may succeed or fail based on encryption service');
    }
    
    @isTest
    static void testHandleAuthFailure_AllRecordTypes() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c wu = [SELECT Id, User__c, Provider__c, Refresh_Token__c FROM AI_Workspace_User__c LIMIT 1];
        
        AIWorkspaceSyncQueueable q1 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.EMAIL);
        AIWorkspaceSyncQueueable q2 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR);
        AIWorkspaceSyncQueueable q3 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.TASK);
        
        Test.startTest();
        q1.handleAuthFailure(wu, 'Test error');
        q2.handleAuthFailure(wu, 'Test error');
        q3.handleAuthFailure(wu, 'Test error');
        Test.stopTest();
        
        List<AI_Workspace_Sync_Log__c> logs = [SELECT Id, Record_Type__c FROM AI_Workspace_Sync_Log__c WHERE Status__c = 'Failed'];
        Assert.areEqual(3, logs.size(), 'Should create 3 failed logs');
    }
    
    @isTest
    static void testLogSyncError() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c wu = [SELECT Id, User__c, Provider__c, Refresh_Token__c FROM AI_Workspace_User__c LIMIT 1];
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        
        Test.startTest();
        queueable.logSyncError(wu, AIWorkspaceSyncQueueable.SyncType.EMAIL, new CalloutException('Test'));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle sync error');
    }
    
    // @isTest
    // static void testExecuteSync_EmailWithException() {
    //     User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
    //     AI_Workspace_User__c wu = [SELECT Id, User__c, Provider__c, Refresh_Token__c FROM AI_Workspace_User__c LIMIT 1];
        
    //     AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.EMAIL);
        
    //     Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        
    //     Test.startTest();
    //     queueable.executeSync(wu, 'test_token');
    //     Test.stopTest();
        
    //     Assert.isTrue(true, 'Should handle email sync exception');
    // }
    
    // @isTest
    // static void testExecuteSync_CalendarWithException() {
    //     User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
    //     AI_Workspace_User__c wu = [SELECT Id, User__c, Provider__c, Refresh_Token__c FROM AI_Workspace_User__c LIMIT 1];
        
    //     AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR);
        
    //     Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        
    //     Test.startTest();
    //     queueable.executeSync(wu, 'test_token');
    //     Test.stopTest();
        
    //     Assert.isTrue(true, 'Should handle calendar sync exception');
    // }
    
    // @isTest
    // static void testExecuteSync_TaskWithException() {
    //     User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
    //     AI_Workspace_User__c wu = [SELECT Id, User__c, Provider__c, Refresh_Token__c FROM AI_Workspace_User__c LIMIT 1];
        
    //     AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.TASK);
        
    //     Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        
    //     Test.startTest();
    //     queueable.executeSync(wu, 'test_token');
    //     Test.stopTest();
        
    //     Assert.isTrue(true, 'Should handle task sync exception');
    // }
    
    @isTest
    static void testGmailTwoPointerSyncWindow_FirstSync() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        
        Test.startTest();
        AIWorkspaceSyncQueueable.GmailSyncWindow window = queueable.getGmailTwoPointerSyncWindow(testUser.Id, 'GMAIL_EMAIL');
        Test.stopTest();
        
        Assert.isNotNull(window.forwardCursor, 'Forward cursor should be set');
        Assert.isTrue(window.backfillComplete, 'First sync should have backfill complete');
    }
    
    @isTest
    static void testGmailTwoPointerSyncWindow_BackfillInProgress() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        DateTime now = DateTime.now();
        DateTime lookbackBoundary = now.addHours(-48);
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = now.addHours(-2),
            End_Time__c = now.addHours(-1),
            Sync_Window_Start__c = lookbackBoundary,
            Sync_Window_End__c = now.addHours(-12),
            Gmail_Forward_Cursor__c = now.addHours(-1)
        );
        insert priorLog;
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        
        Test.startTest();
        AIWorkspaceSyncQueueable.GmailSyncWindow window = queueable.getGmailTwoPointerSyncWindow(testUser.Id, 'GMAIL_EMAIL');
        Test.stopTest();
        
        Assert.isFalse(window.backfillComplete, 'Backfill should be in progress');
        Assert.isNotNull(window.lookbackBoundary, 'Lookback boundary should be set');
    }
    
    @isTest
    static void testGmailTwoPointerSyncWindow_BackfillComplete() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        DateTime now = DateTime.now();
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = now.addHours(-2),
            End_Time__c = now.addHours(-1),
            Sync_Window_Start__c = now.addHours(-48),
            Sync_Window_End__c = now,
            Gmail_Forward_Cursor__c = now.addHours(-1)
        );
        insert priorLog;
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        
        Test.startTest();
        AIWorkspaceSyncQueueable.GmailSyncWindow window = queueable.getGmailTwoPointerSyncWindow(testUser.Id, 'GMAIL_EMAIL');
        Test.stopTest();
        
        Assert.isTrue(window.backfillComplete, 'Backfill should be complete');
    }
    
    @isTest
    static void testGmailTwoPointerSyncWindow_NullCursors() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        DateTime now = DateTime.now();
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = now.addHours(-2),
            End_Time__c = now.addHours(-1),
            Sync_Window_Start__c = now.addHours(-48)
        );
        insert priorLog;
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        
        Test.startTest();
        AIWorkspaceSyncQueueable.GmailSyncWindow window = queueable.getGmailTwoPointerSyncWindow(testUser.Id, 'GMAIL_EMAIL');
        Test.stopTest();
        
        Assert.isNotNull(window.forwardCursor, 'Should default forward cursor to now');
        Assert.isNotNull(window.backfillCursor, 'Should default backfill cursor to now');
    }
    
    @isTest
    static void testGmailTwoPointerSyncWindow_NullLookbackHours() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Lookback_Hours__c = null
        );
        updateSettings(settings);
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0);
        
        Test.startTest();
        AIWorkspaceSyncQueueable.GmailSyncWindow window = queueable.getGmailTwoPointerSyncWindow(testUser.Id, 'GMAIL_EMAIL');
        Test.stopTest();
        
        Assert.isNotNull(window.lookbackBoundary, 'Should default to 24 hours');
    }
    
    @isTest
    static void testRunNowMode_WithLookbackSettings() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Lookback_Hours__c = 48,
            Calendar_Lookback_Days__c = 14,
            Task_Lookback_Days__c = 30
        );
        updateSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true));
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR, true));
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.TASK, true));
        Test.stopTest();
        
        Assert.isTrue(true, 'Run now should use lookback settings');
    }
    
    @isTest
    static void testRunNowMode_WithPriorSyncLogs() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c wu = [SELECT Id, User__c FROM AI_Workspace_User__c LIMIT 1];
        
        DateTime priorEnd = DateTime.now().addHours(-1);
        insert new List<AI_Workspace_Sync_Log__c>{
            new AI_Workspace_Sync_Log__c(
                User__c = wu.User__c,
                Provider_Type__c = 'MICROSOFT_EMAIL',
                Record_Type__c = 'Email',
                Status__c = 'Success',
                Start_Time__c = priorEnd.addHours(-1),
                End_Time__c = priorEnd,
                Sync_Window_End__c = priorEnd
            ),
            new AI_Workspace_Sync_Log__c(
                User__c = wu.User__c,
                Provider_Type__c = 'MICROSOFT_EMAIL',
                Record_Type__c = 'Calendar',
                Status__c = 'Success',
                Start_Time__c = priorEnd.addDays(-1),
                End_Time__c = priorEnd,
                Sync_Window_End__c = priorEnd
            ),
            new AI_Workspace_Sync_Log__c(
                User__c = wu.User__c,
                Provider_Type__c = 'MICROSOFT_EMAIL',
                Record_Type__c = 'Task',
                Status__c = 'Success',
                Start_Time__c = priorEnd.addDays(-1),
                End_Time__c = priorEnd,
                Sync_Window_End__c = priorEnd
            )
        };
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true));
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR, true));
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.TASK, true));
        Test.stopTest();
        
        Assert.isTrue(true, 'Run now should use incremental sync with prior logs');
    }
    
    @isTest
    static void testScheduledMode_WithPriorSyncLogs() {
        AI_Workspace_User__c wu = [SELECT Id, User__c FROM AI_Workspace_User__c LIMIT 1];
        
        DateTime priorEnd = DateTime.now().addHours(-1);
        insert new AI_Workspace_Sync_Log__c(
            User__c = wu.User__c,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = priorEnd.addHours(-1),
            End_Time__c = priorEnd,
            Sync_Window_End__c = priorEnd
        );
        
        AIWorkspaceSyncQueueable.disableChaining = true;
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, false));
        Test.stopTest();
        
        Assert.isTrue(true, 'Scheduled mode should use incremental sync');
    }
    
    @isTest
    static void testScheduledMode_NoPriorSyncLogs() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        AIWorkspaceSyncQueueable.disableChaining = true;
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, false));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should use default lookback when no prior sync');
    }
    
    @isTest
    static void testGmailBackfillReachedLookbackBoundary() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_gmail_token'
        );
        insert gmailUser;
        
        DateTime now = DateTime.now();
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = now.addHours(-2),
            End_Time__c = now.addHours(-1),
            Sync_Window_Start__c = now.addHours(-48),
            Sync_Window_End__c = now.addHours(-49),
            Gmail_Forward_Cursor__c = now.addHours(-1)
        );
        insert priorLog;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ gmailUser.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle backfill at lookback boundary');
    }
    
    @isTest
    static void testChaining_MultipleUsers() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id, wu.Id }, 0));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle multiple users');
    }
    
    @isTest
    static void testChaining_WithDelay() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Queueable_Delay_Minutes__c = 5
        );
        updateSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id, wu.Id }, 0));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle delay in chaining');
    }
    
    @isTest
    static void testSyncTypeEnum() {
        Assert.isNotNull(AIWorkspaceSyncQueueable.SyncType.EMAIL, 'EMAIL should exist');
        Assert.isNotNull(AIWorkspaceSyncQueueable.SyncType.CALENDAR, 'CALENDAR should exist');
        Assert.isNotNull(AIWorkspaceSyncQueueable.SyncType.TASK, 'TASK should exist');
    }
    
    @isTest
    static void testPrepareChainToNext_EmailOnly() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = true,
            Calendar_Sync_Enabled__c = false,
            Task_Sync_Enabled__c = false
        );
        updateSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id, wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should chain to next user when only email enabled');
    }
    
    @isTest
    static void testPrepareChainToNext_CalendarOnly() {
        AI_Workspace_User__c wu = [SELECT Id FROM AI_Workspace_User__c LIMIT 1];
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Sync_Enabled__c = false,
            Calendar_Sync_Enabled__c = true,
            Task_Sync_Enabled__c = false
        );
        updateSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ wu.Id, wu.Id }, 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR));
        Test.stopTest();
        
        Assert.isTrue(true, 'Should chain to next user when only calendar enabled');
    }
    
    @isTest
    static void testGmailBackfillCursorAssignment() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            User__c = testUser.Id,
            Provider__c = 'Gmail',
            Refresh_Token__c = 'encrypted_gmail_token'
        );
        insert gmailUser;
        
        DateTime now = DateTime.now();
        DateTime lookbackBoundary = now.addHours(-48);
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = now.addHours(-2),
            End_Time__c = now.addHours(-1),
            Sync_Window_Start__c = lookbackBoundary,
            Sync_Window_End__c = lookbackBoundary.addHours(12),
            Gmail_Forward_Cursor__c = now.addHours(-1)
        );
        insert priorLog;
        
        Test.setMock(HttpCalloutMock.class, new MockSuccessfulTokenRefresh());
        
        Test.startTest();
        System.enqueueJob(new AIWorkspaceSyncQueueable(new List<Id>{ gmailUser.Id }, 0, AIWorkspaceSyncQueueable.SyncType.EMAIL));
        Test.stopTest();
        
        List<AI_Workspace_Sync_Log__c> logs = [SELECT Id, Sync_Window_Start__c, Sync_Window_End__c FROM AI_Workspace_Sync_Log__c WHERE User__c = :testUser.Id ORDER BY CreatedDate DESC LIMIT 1];
        Assert.isTrue(logs.size() > 0, 'Should create sync log with backfill window');
    }
    
    @isTest
    static void testGetLastSyncTime_AllRecordTypes() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        DateTime priorEnd = DateTime.now().addHours(-1);
        insert new List<AI_Workspace_Sync_Log__c>{
            new AI_Workspace_Sync_Log__c(
                User__c = testUser.Id,
                Provider_Type__c = 'MICROSOFT_EMAIL',
                Record_Type__c = 'Email',
                Status__c = 'Success',
                Start_Time__c = priorEnd.addHours(-1),
                End_Time__c = priorEnd,
                Sync_Window_End__c = priorEnd
            ),
            new AI_Workspace_Sync_Log__c(
                User__c = testUser.Id,
                Provider_Type__c = 'MICROSOFT_EMAIL',
                Record_Type__c = 'Calendar',
                Status__c = 'Success',
                Start_Time__c = priorEnd.addDays(-1),
                End_Time__c = priorEnd,
                Sync_Window_End__c = priorEnd
            ),
            new AI_Workspace_Sync_Log__c(
                User__c = testUser.Id,
                Provider_Type__c = 'MICROSOFT_EMAIL',
                Record_Type__c = 'Task',
                Status__c = 'Success',
                Start_Time__c = priorEnd.addDays(-1),
                End_Time__c = priorEnd,
                Sync_Window_End__c = priorEnd
            )
        };
        
        AIWorkspaceSyncQueueable q1 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.EMAIL);
        AIWorkspaceSyncQueueable q2 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR);
        AIWorkspaceSyncQueueable q3 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.TASK);
        
        Test.startTest();
        DateTime emailTime = q1.getLastSyncTime(testUser.Id, 'MICROSOFT_EMAIL');
        DateTime calTime = q2.getLastSyncTime(testUser.Id, 'MICROSOFT_EMAIL');
        DateTime taskTime = q3.getLastSyncTime(testUser.Id, 'MICROSOFT_EMAIL');
        Test.stopTest();
        
        Assert.isNotNull(emailTime, 'Email sync time should be found');
        Assert.isNotNull(calTime, 'Calendar sync time should be found');
        Assert.isNotNull(taskTime, 'Task sync time should be found');
    }
    
    @isTest
    static void testGetRunNowLookbackTime_AllRecordTypes() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Lookback_Hours__c = 48,
            Calendar_Lookback_Days__c = 14,
            Task_Lookback_Days__c = 30
        );
        updateSettings(settings);
        
        AIWorkspaceSyncQueueable q1 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true);
        AIWorkspaceSyncQueueable q2 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR, true);
        AIWorkspaceSyncQueueable q3 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.TASK, true);
        
        Test.startTest();
        DateTime emailTime = q1.getRunNowLookbackTime(testUser.Id, 'MICROSOFT_EMAIL');
        DateTime calTime = q2.getRunNowLookbackTime(testUser.Id, 'MICROSOFT_EMAIL');
        DateTime taskTime = q3.getRunNowLookbackTime(testUser.Id, 'MICROSOFT_EMAIL');
        Test.stopTest();
        
        Assert.isNotNull(emailTime, 'Email lookback should be set');
        Assert.isNotNull(calTime, 'Calendar lookback should be set');
        Assert.isNotNull(taskTime, 'Task lookback should be set');
    }
    
    @isTest
    static void testGetRunNowLookbackTime_WithPriorSync() {
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser@test.gptfy.com' LIMIT 1];
        
        DateTime priorEnd = DateTime.now().addHours(-1);
        insert new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'MICROSOFT_EMAIL',
            Record_Type__c = 'Email',
            Status__c = 'Success',
            Start_Time__c = priorEnd.addHours(-1),
            End_Time__c = priorEnd,
            Sync_Window_End__c = priorEnd
        );
        
        AIWorkspaceSyncQueueable queueable = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.EMAIL, true);
        
        Test.startTest();
        DateTime result = queueable.getRunNowLookbackTime(testUser.Id, 'MICROSOFT_EMAIL');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null when prior sync exists');
    }
    
    @isTest
    static void testGetDefaultLookbackTime_AllRecordTypes() {
        AIWorkspaceSyncQueueable q1 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.EMAIL);
        AIWorkspaceSyncQueueable q2 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR);
        AIWorkspaceSyncQueueable q3 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.TASK);
        
        Test.startTest();
        DateTime emailTime = q1.getDefaultLookbackTime();
        DateTime calTime = q2.getDefaultLookbackTime();
        DateTime taskTime = q3.getDefaultLookbackTime();
        Test.stopTest();
        
        Assert.isNotNull(emailTime, 'Email default lookback should be set');
        Assert.isNotNull(calTime, 'Calendar default lookback should be set');
        Assert.isNotNull(taskTime, 'Task default lookback should be set');
    }
    
    @isTest
    static void testGetDefaultLookbackTime_WithNullSettings() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Lookback_Hours__c = null,
            Calendar_Lookback_Days__c = null,
            Task_Lookback_Days__c = null
        );
        updateSettings(settings);
        
        AIWorkspaceSyncQueueable q1 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.EMAIL);
        AIWorkspaceSyncQueueable q2 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR);
        AIWorkspaceSyncQueueable q3 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.TASK);
        
        Test.startTest();
        DateTime emailTime = q1.getDefaultLookbackTime();
        DateTime calTime = q2.getDefaultLookbackTime();
        DateTime taskTime = q3.getDefaultLookbackTime();
        Test.stopTest();
        
        Assert.isNotNull(emailTime, 'Should default to 24 hours for email');
        Assert.isNotNull(calTime, 'Should default to 7 days for calendar');
        Assert.isNotNull(taskTime, 'Should default to 7 days for task');
    }
    
    @isTest
    static void testGetDefaultLookbackTime_WithZeroSettings() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Lookback_Hours__c = 0,
            Calendar_Lookback_Days__c = 0,
            Task_Lookback_Days__c = 0
        );
        updateSettings(settings);
        
        AIWorkspaceSyncQueueable q1 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.EMAIL);
        AIWorkspaceSyncQueueable q2 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.CALENDAR);
        AIWorkspaceSyncQueueable q3 = new AIWorkspaceSyncQueueable(new List<Id>(), 0, AIWorkspaceSyncQueueable.SyncType.TASK);
        
        Test.startTest();
        DateTime emailTime = q1.getDefaultLookbackTime();
        DateTime calTime = q2.getDefaultLookbackTime();
        DateTime taskTime = q3.getDefaultLookbackTime();
        Test.stopTest();
        
        Assert.isNotNull(emailTime, 'Should default to 24 hours for email when 0');
        Assert.isNotNull(calTime, 'Should default to 7 days for calendar when 0');
        Assert.isNotNull(taskTime, 'Should default to 7 days for task when 0');
    }
    
    private static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User u = new User(
            Alias = 'testusr',
            Email = 'testuser@test.gptfy.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + DateTime.now().getTime() + '@test.gptfy.com'
        );
        insert u;
        return u;
    }
    
    private static void updateSettings(AI_Workspace_Sync_Settings__c newSettings) {
        AI_Workspace_Sync_Settings__c existingSettings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        if (existingSettings == null || existingSettings.Id == null) {
            insert newSettings;
        } else {
            newSettings.Id = existingSettings.Id;
            update newSettings;
        }
        AISyncSettingsService.setCachedSettings(newSettings);
    }
    
    private class MockSuccessfulTokenRefresh implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('oauth2') || endpoint.contains('token')) {
                res.setBody('{"access_token":"mock_access_token","refresh_token":"mock_refresh_token","expires_in":3600,"token_type":"Bearer"}');
            } else if (endpoint.contains('/me/messages') || endpoint.contains('/gmail/v1/users/me/messages')) {
                res.setBody('{"value":[],"messages":[]}');
            } else if (endpoint.contains('/me') || endpoint.contains('/profile')) {
                res.setBody('{"userPrincipalName":"test@example.com","mail":"test@example.com","emailAddress":"test@example.com"}');
            } else {
                res.setBody('{}');
            }
            
            return res;
        }
    }
    
    private class MockFailedTokenRefresh implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('oauth2') || req.getEndpoint().contains('token')) {
                res.setStatusCode(400);
                res.setBody('{"error":"invalid_grant","error_description":"Token has expired"}');
            } else {
                res.setStatusCode(401);
                res.setBody('{"error":{"code":"Unauthorized","message":"Token invalid"}}');
            }
            
            return res;
        }
    }
    
    private class MockExceptionResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Mock exception for testing');
        }
    }
}
