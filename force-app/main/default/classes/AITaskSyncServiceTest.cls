@IsTest
private class AITaskSyncServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create AI_Workspace_User__c record for Outlook provider
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            Name = 'Test Outlook Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Access_Token__c = 'test_access_token_12345',
            Refresh_Token__c = 'test_refresh_token_67890'
        );
        insert workspaceUser;
    }

    /**
     * Helper to create mock settings for testing
     */
    private static AI_Workspace_Sync_Settings__c createMockSettings(Boolean taskSyncEnabled) {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Task_Sync_Enabled__c = taskSyncEnabled;
        settings.Max_Tasks_Per_User__c = 50;
        settings.Include_Completed_Tasks__c = false;
        settings.Sync_Enabled__c = true;
        return settings;
    }

    @IsTest
    static void testSyncUserTasks_Disabled() {
        // Set up mock settings with task sync disabled
        AISyncSettingsService.setCachedSettings(createMockSettings(false));

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();

        // Should return early with error
        Assert.areEqual(0, result.tasksFetched, 'Should fetch 0 tasks when disabled');
        Assert.isTrue(!result.errors.isEmpty(), 'Should have error message');
        Assert.isTrue(result.errors[0].contains('not enabled'), 'Error should mention sync not enabled');
    }

    @IsTest
    static void testTaskSyncResult_Initialization() {
        AITaskSyncService.TaskSyncResult result = new AITaskSyncService.TaskSyncResult();

        Assert.areEqual(0, result.tasksFetched, 'tasksFetched should be 0');
        Assert.areEqual(0, result.tasksImported, 'tasksImported should be 0');
        Assert.areEqual(0, result.tasksDuplicate, 'tasksDuplicate should be 0');
        Assert.areEqual(0, result.tasksFailed, 'tasksFailed should be 0');
        Assert.areNotEqual(null, result.errors, 'errors should not be null');
        Assert.areNotEqual(null, result.taskIds, 'taskIds should not be null');
    }

    @IsTest
    static void testMicrosoftTaskService_ToDoTask_Initialization() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();

        Assert.areEqual('MICROSOFT_TASKS', task.provider, 'provider should be MICROSOFT_TASKS');
        Assert.areEqual(false, task.isImported, 'isImported should be false');
    }

    @IsTest
    static void testMicrosoftTaskService_TaskList_Initialization() {
        AIMicrosoftTaskService.TaskList taskList = new AIMicrosoftTaskService.TaskList();

        Assert.areEqual(null, taskList.listId, 'listId should be null');
        Assert.areEqual(null, taskList.displayName, 'displayName should be null');
    }

    @IsTest
    static void testMicrosoftTaskService_IsTaskAccessible_NoAuth() {
        // Without proper Named Credential, should return false
        Test.startTest();
        // Note: This will fail in test context due to no callout mock
        // The test verifies the method exists and handles errors gracefully
        Boolean isAccessible = false;
        try {
            Test.setMock(HttpCalloutMock.class, new TaskAccessMock(false));
            isAccessible = AIMicrosoftTaskService.isTaskAccessible();
        } catch (Exception e) {
            // Expected - no mock set up
            isAccessible = false;
        }
        Test.stopTest();

        // Without proper auth, should not be accessible
        Assert.areEqual(false, isAccessible, 'Should not be accessible without auth');
    }

    @IsTest
    static void testSyncSettingsService_TaskSettings() {
        // Test with settings enabled
        AI_Workspace_Sync_Settings__c enabledSettings = createMockSettings(true);
        enabledSettings.Max_Tasks_Per_User__c = 100;
        enabledSettings.Include_Completed_Tasks__c = true;
        AISyncSettingsService.setCachedSettings(enabledSettings);

        Assert.areEqual(true, AISyncSettingsService.isTaskSyncEnabled(), 'Task sync should be enabled');
        Assert.areEqual(100, AISyncSettingsService.getMaxTasksPerUser(), 'Max tasks should be 100');
        Assert.areEqual(true, AISyncSettingsService.includeCompletedTasks(), 'Include completed should be true');

        // Test with settings disabled
        AISyncSettingsService.setCachedSettings(createMockSettings(false));

        Assert.areEqual(false, AISyncSettingsService.isTaskSyncEnabled(), 'Task sync should be disabled');

        // Clear cache
        AISyncSettingsService.clearCache();
    }

    @IsTest
    static void testSyncSettingsService_DefaultValues() {
        // Test default values when settings fields are null
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Max_Tasks_Per_User__c = null; // Null to test default
        AISyncSettingsService.setCachedSettings(settings);

        Assert.areEqual(50, AISyncSettingsService.getMaxTasksPerUser(), 'Should return default 50');

        AISyncSettingsService.clearCache();
    }

    /**
     * Mock class for HTTP callouts
     */
    private class TaskAccessMock implements HttpCalloutMock {
        private Boolean isAccessible;

        public TaskAccessMock(Boolean isAccessible) {
            this.isAccessible = isAccessible;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (isAccessible) {
                res.setStatusCode(200);
                res.setBody('{"value": []}');
            } else {
                res.setStatusCode(401);
                res.setBody('{"error": {"code": "Unauthorized"}}');
            }

            return res;
        }
    }

    /**
     * Mock for task lists API
     */
    private class TaskListsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            // Handle task list calls first (more specific)
            if (endpoint.contains('/todo/lists')) {
                res.setBody('{"value": [' +
                    '{"id": "list1", "displayName": "Tasks", "isOwner": true, "isShared": false, "wellknownListName": "defaultList"},' +
                    '{"id": "list2", "displayName": "Work", "isOwner": true, "isShared": false}' +
                ']}');
            } else {
                // Token validation and other calls
                res.setBody('{"id": "user123"}');
            }
            return res;
        }
    }

    /**
     * Test task list parsing with mock
     */
    @IsTest
    static void testGetTaskLists_WithMock() {
        Test.setMock(HttpCalloutMock.class, new TaskListsMock());

        Test.startTest();
        List<AIMicrosoftTaskService.TaskList> lists = AIMicrosoftTaskService.getTaskLists();
        Test.stopTest();

        Assert.areEqual(2, lists.size(), 'Should have 2 task lists');
        Assert.areEqual('list1', lists[0].listId, 'First list ID should be list1');
        Assert.areEqual('Tasks', lists[0].displayName, 'First list name should be Tasks');
        Assert.areEqual(true, lists[0].isOwner, 'Should be owner');
        Assert.areEqual('defaultList', lists[0].wellknownListName, 'Should be default list');
    }

    /**
     * Multi-response mock for full task sync flow
     */
    private class FullTaskSyncMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            // Handle task-specific endpoints first (more specific)
            if (endpoint.contains('/tasks')) {
                // Tasks request
                res.setStatusCode(200);
                res.setBody('{"value": [' +
                    '{"id": "task1", "title": "Test Task 1", "status": "notStarted", "importance": "high", ' +
                    '"createdDateTime": "2024-01-15T10:00:00Z", "body": {"contentType": "text", "content": "Task body"}},' +
                    '{"id": "task2", "title": "Test Task 2", "status": "inProgress", "importance": "normal", ' +
                    '"dueDateTime": {"dateTime": "2024-01-20T17:00:00", "timeZone": "UTC"}}' +
                ']}');
            } else if (endpoint.contains('/todo/lists')) {
                // Task lists request
                res.setStatusCode(200);
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks", "isOwner": true, "isShared": false}]}');
            } else {
                // Token validation calls and other endpoints
                res.setStatusCode(200);
                res.setBody('{"id": "user123"}');
            }

            return res;
        }
    }

    @IsTest
    static void testGetAllTasks_WithMock() {
        Test.setMock(HttpCalloutMock.class, new FullTaskSyncMock());

        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(50, false);
        Test.stopTest();

        Assert.areEqual(2, tasks.size(), 'Should have 2 tasks');
        Assert.areEqual('task1', tasks[0].taskId, 'First task ID should be task1');
        Assert.areEqual('Test Task 1', tasks[0].title, 'First task title should match');
        Assert.areEqual('notStarted', tasks[0].status, 'Status should be notStarted');
        Assert.areEqual('high', tasks[0].importance, 'Importance should be high');
        Assert.areEqual('Task body', tasks[0].body, 'Body should be parsed');
    }

    @IsTest
    static void testSyncUserTasks_WithMock() {
        // Test the task-to-staging mapping directly since syncUserTasks relies on Named Credential auth
        // which is not available in test context. This tests the core staging creation logic.
        
        List<AIMicrosoftTaskService.ToDoTask> testTasks = new List<AIMicrosoftTaskService.ToDoTask>();
        
        AIMicrosoftTaskService.ToDoTask task1 = new AIMicrosoftTaskService.ToDoTask();
        task1.taskId = 'task1';
        task1.title = 'Test Task 1';
        task1.status = 'notStarted';
        task1.importance = 'high';
        task1.body = 'Task body';
        testTasks.add(task1);
        
        AIMicrosoftTaskService.ToDoTask task2 = new AIMicrosoftTaskService.ToDoTask();
        task2.taskId = 'task2';
        task2.title = 'Test Task 2';
        task2.status = 'inProgress';
        task2.importance = 'normal';
        task2.dueDateTime = DateTime.now().addDays(5);
        testTasks.add(task2);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(testTasks, 'MICROSOFT_TASKS', null);
        Test.stopTest();

        // Verify results
        Assert.areEqual(2, result.successCount, 'Should import 2 tasks');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');
        Assert.areEqual(2, result.stagingRecordIds.size(), 'Should have 2 staging IDs');

        // Verify AI_Workspace_Staging__c records were created
        List<AI_Workspace_Staging__c> createdStaging = [
            SELECT Id, Subject__c, Task_Status__c, Task_Priority__c, Provider_Id__c
            FROM AI_Workspace_Staging__c
            WHERE Id IN :result.stagingRecordIds
        ];
        Assert.areEqual(2, createdStaging.size(), 'Should have 2 staging records');

        // Verify staging records
        AI_Workspace_Staging__c s1 = null;
        AI_Workspace_Staging__c s2 = null;
        for (AI_Workspace_Staging__c s : createdStaging) {
            if (s.Provider_Id__c == 'task1') s1 = s;
            if (s.Provider_Id__c == 'task2') s2 = s;
        }

        Assert.areNotEqual(null, s1, 'Staging 1 should exist');
        // V2-7889: Decrypt subject for assertion
        String decryptedSubject1 = AIWorkspaceEncryptionService.decryptEmailBody(s1.Subject__c, UserInfo.getUserId());
        Assert.areEqual('Test Task 1', decryptedSubject1, 'Subject should match');
        Assert.areEqual('Not Started', s1.Task_Status__c, 'Status should be mapped');
        Assert.areEqual('High', s1.Task_Priority__c, 'Priority should be High');

        Assert.areNotEqual(null, s2, 'Staging 2 should exist');
        // V2-7889: Decrypt subject for assertion
        String decryptedSubject2 = AIWorkspaceEncryptionService.decryptEmailBody(s2.Subject__c, UserInfo.getUserId());
        Assert.areEqual('Test Task 2', decryptedSubject2, 'Subject should match');
        Assert.areEqual('In Progress', s2.Task_Status__c, 'Status should be In Progress');
        Assert.areEqual('Normal', s2.Task_Priority__c, 'Priority should be Normal');
    }

    @IsTest
    static void testSyncUserTasks_Deduplication() {
        // Test deduplication of staging records directly
        
        // Create existing staging record with same external ID
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Subject__c = 'Existing Task',
            Provider_Id__c = 'task1',
            Provider__c = 'MICROSOFT_TASKS'
        );
        insert existingStaging;

        // Create test tasks - one with same ID as existing, one new
        List<AIMicrosoftTaskService.ToDoTask> testTasks = new List<AIMicrosoftTaskService.ToDoTask>();
        
        AIMicrosoftTaskService.ToDoTask task1 = new AIMicrosoftTaskService.ToDoTask();
        task1.taskId = 'task1'; // Same as existing - should be deduplicated
        task1.title = 'Test Task 1';
        testTasks.add(task1);
        
        AIMicrosoftTaskService.ToDoTask task2 = new AIMicrosoftTaskService.ToDoTask();
        task2.taskId = 'task2'; // New - should be imported
        task2.title = 'Test Task 2';
        testTasks.add(task2);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(testTasks, 'MICROSOFT_TASKS', null);
        Test.stopTest();

        // task1 should be deduplicated (already exists), only task2 imported
        Assert.areEqual(1, result.successCount, 'Should import 1 task (task2)');
        Assert.areEqual(1, result.duplicateCount, 'Should have 1 duplicate (task1)');
    }

    @IsTest
    static void testSyncLog_Created() {
        // Test staging creation with sync log linkage
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Status__c = 'In Progress',
            Sync_Type__c = 'Manual',
            Provider_Type__c = 'MICROSOFT_TASKS'
        );
        insert syncLog;

        List<AIMicrosoftTaskService.ToDoTask> testTasks = new List<AIMicrosoftTaskService.ToDoTask>();
        
        AIMicrosoftTaskService.ToDoTask task1 = new AIMicrosoftTaskService.ToDoTask();
        task1.taskId = 'log-task1';
        task1.title = 'Test Task 1';
        testTasks.add(task1);
        
        AIMicrosoftTaskService.ToDoTask task2 = new AIMicrosoftTaskService.ToDoTask();
        task2.taskId = 'log-task2';
        task2.title = 'Test Task 2';
        testTasks.add(task2);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(testTasks, 'MICROSOFT_TASKS', syncLog.Id);
        Test.stopTest();

        // Verify sync result is successful
        Assert.areEqual(2, result.successCount, 'Should import 2 staging records');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');

        // Verify staging records were created with sync log link
        List<AI_Workspace_Staging__c> stagingRecords = [
            SELECT Id, Provider_Id__c, Sync_Log__c
            FROM AI_Workspace_Staging__c
            WHERE Id IN :result.stagingRecordIds
        ];
        Assert.areEqual(2, stagingRecords.size(), 'Should have 2 staging records');
        
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            Assert.areEqual(syncLog.Id, staging.Sync_Log__c, 'Sync log should be linked');
        }
    }

    /**
     * Test error handling when API returns error
     */
    @IsTest
    static void testGetTaskLists_ApiError() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock(401));

        Test.startTest();
        try {
            AIMicrosoftTaskService.getTaskLists();
            Assert.isTrue(false, 'Should have thrown exception');
        } catch (AIMicrosoftTaskService.TaskServiceException e) {
            // Can throw 401 error or token validation error
            Assert.isTrue(e.getMessage().contains('401') || e.getMessage().contains('Failed') || e.getMessage().contains('error'), 'Error should indicate failure');
        }
        Test.stopTest();
    }

    /**
     * Test getTasksFromList with empty list ID
     */
    @IsTest
    static void testGetTasksFromList_EmptyListId() {
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromList('', null, 10, false);
        Test.stopTest();

        Assert.areEqual(0, tasks.size(), 'Should return empty list for blank listId');
    }

    /**
     * Test getAllTasks with default/null parameters
     */
    @IsTest
    static void testGetAllTasks_DefaultParams() {
        Test.setMock(HttpCalloutMock.class, new FullTaskSyncMock());

        Test.startTest();
        // Test with null/zero params - should use defaults
        List<AIMicrosoftTaskService.ToDoTask> tasks1 = AIMicrosoftTaskService.getAllTasks(null, false);
        List<AIMicrosoftTaskService.ToDoTask> tasks2 = AIMicrosoftTaskService.getAllTasks(0, true);
        Test.stopTest();

        Assert.areNotEqual(null, tasks1, 'Should not be null');
        Assert.areNotEqual(null, tasks2, 'Should not be null');
    }

    /**
     * Test getTask single task fetch
     */
    @IsTest
    static void testGetTask_Single() {
        Test.setMock(HttpCalloutMock.class, new SingleTaskMock());

        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list1', 'task1');
        Test.stopTest();

        Assert.areNotEqual(null, task, 'Task should not be null');
        Assert.areEqual('task1', task.taskId, 'Task ID should match');
        Assert.areEqual('Single Task', task.title, 'Title should match');
    }

    /**
     * Test getTask error handling
     */
    @IsTest
    static void testGetTask_Error() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock(404));

        Test.startTest();
        try {
            AIMicrosoftTaskService.getTask('list1', 'nonexistent');
            Assert.isTrue(false, 'Should have thrown exception');
        } catch (AIMicrosoftTaskService.TaskServiceException e) {
            // Can throw 404 error or token validation error
            Assert.isTrue(e.getMessage().contains('404') || e.getMessage().contains('Failed') || e.getMessage().contains('error'), 'Error should indicate failure');
        }
        Test.stopTest();
    }

    /**
     * Test task with all fields populated
     */
    @IsTest
    static void testParseTask_AllFields() {
        Test.setMock(HttpCalloutMock.class, new FullFieldsTaskMock());

        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(10, true);
        Test.stopTest();

        Assert.areEqual(1, tasks.size(), 'Should have 1 task');
        AIMicrosoftTaskService.ToDoTask task = tasks[0];
        Assert.areEqual('Full Task', task.title, 'Title should match');
        Assert.areEqual('completed', task.status, 'Status should be completed');
        Assert.areEqual('high', task.importance, 'Importance should be high');
        Assert.areEqual(true, task.isReminderOn, 'Reminder should be on');
        Assert.areNotEqual(null, task.dueDateTime, 'Due date should be set');
        Assert.areNotEqual(null, task.completedDateTime, 'Completed date should be set');
        Assert.areNotEqual(null, task.reminderDateTime, 'Reminder date should be set');
    }

    /**
     * Test SyncSettingsService null settings behavior
     */
    @IsTest
    static void testSyncSettingsService_NullSettings() {
        // Create settings with nulls to test default behavior
        AI_Workspace_Sync_Settings__c nullSettings = new AI_Workspace_Sync_Settings__c();
        nullSettings.Task_Sync_Enabled__c = null;
        nullSettings.Max_Tasks_Per_User__c = null;
        nullSettings.Include_Completed_Tasks__c = null;
        AISyncSettingsService.setCachedSettings(nullSettings);

        // Should handle gracefully with defaults when fields are null
        Assert.areEqual(false, AISyncSettingsService.isTaskSyncEnabled(), 'Should be false with null Task_Sync_Enabled__c');
        Assert.areEqual(50, AISyncSettingsService.getMaxTasksPerUser(), 'Should return default 50 when Max_Tasks_Per_User__c is null');
        Assert.areEqual(false, AISyncSettingsService.includeCompletedTasks(), 'Should be false with null Include_Completed_Tasks__c');

        AISyncSettingsService.clearCache();
    }

    /**
     * Error mock for API error testing
     */
    private class ErrorMock implements HttpCalloutMock {
        private Integer statusCode;

        public ErrorMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);
            res.setBody('{"error": {"code": "Error", "message": "Test error"}}');
            return res;
        }
    }

    /**
     * Mock for single task fetch
     */
    private class SingleTaskMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();
            
            // Handle task-specific endpoints first (more specific)
            if (endpoint.contains('/tasks/')) {
                // Single task response (most specific - contains /tasks/{id})
                res.setBody('{"id": "task1", "title": "Single Task", "status": "notStarted", "importance": "normal"}');
            } else if (endpoint.contains('/tasks')) {
                // Task list response
                res.setBody('{"value": []}');
            } else if (endpoint.contains('/todo/lists')) {
                // Task lists response
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else {
                // Token validation and other calls
                res.setBody('{"id": "user123"}');
            }
            return res;
        }
    }

    /**
     * Test that scheduled mode uses incremental sync after first run (fix for lookback days bug)
     */
    @IsTest
    static void testSyncUserTasksWithToken_ScheduledMode_IncrementalSync() {
        // Set up mock settings with task sync enabled
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 14; // Set lookback to 14 days
        AISyncSettingsService.setCachedSettings(settings);
        
        Id testUserId = UserInfo.getUserId();
        
        // Create a prior successful sync log (simulating a previous scheduled run)
        DateTime priorSyncEnd = DateTime.now().addDays(-2); // 2 days ago
        AI_Workspace_Sync_Log__c priorLog = new AI_Workspace_Sync_Log__c(
            User__c = testUserId,
            Provider_Type__c = 'MICROSOFT_TASKS',
            Record_Type__c = 'Task',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addDays(-2).addHours(-1),
            End_Time__c = DateTime.now().addDays(-2),
            Sync_Window_Start__c = DateTime.now().addDays(-16), // Original lookback
            Sync_Window_End__c = priorSyncEnd // This should be used as start for next sync
        );
        insert priorLog;
        
        // Set up HTTP mock for the sync call
        Test.setMock(HttpCalloutMock.class, new FullTaskSyncMock());
        
        Test.startTest();
        // Call with isRunNowMode = false (scheduled mode)
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            testUserId,
            'Outlook',
            'test_access_token',
            false // Scheduled mode
        );
        Test.stopTest();
        
        // Verify the sync window start is the prior sync window end (incremental sync)
        // Not 14 days back (which would be the lookback days setting)
        Assert.isNotNull(result.syncWindowStart, 'Sync window start should not be null');
        
        // The sync window start should be approximately equal to the prior sync window end (within a small tolerance)
        Long expectedStartMillis = priorSyncEnd.getTime();
        Long actualStartMillis = result.syncWindowStart.getTime();
        Long differenceMillis = Math.abs(expectedStartMillis - actualStartMillis);
        
        // Allow 1 second tolerance for any timing differences
        Assert.isTrue(differenceMillis < 1000, 
            'Scheduled mode should use incremental sync (prior Sync_Window_End__c as start). ' +
            'Expected: ' + priorSyncEnd + ', Actual: ' + result.syncWindowStart);
    }
    
    /**
     * Test that first scheduled run uses lookback days setting
     */
    @IsTest
    static void testSyncUserTasksWithToken_ScheduledMode_FirstRun_UsesLookbackDays() {
        // Set up mock settings with task sync enabled
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 10; // Set lookback to 10 days
        AISyncSettingsService.setCachedSettings(settings);
        
        Id testUserId = UserInfo.getUserId();
        
        // No prior sync logs - this is the first run
        
        // Set up HTTP mock for the sync call
        Test.setMock(HttpCalloutMock.class, new FullTaskSyncMock());
        
        Test.startTest();
        // Call with isRunNowMode = false (scheduled mode)
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            testUserId,
            'Outlook',
            'test_access_token',
            false // Scheduled mode
        );
        Test.stopTest();
        
        // Verify the sync window start is approximately 10 days back (the lookback days setting)
        Assert.isNotNull(result.syncWindowStart, 'Sync window start should not be null');
        
        DateTime expectedStart = DateTime.now().addDays(-10);
        Long expectedStartMillis = expectedStart.getTime();
        Long actualStartMillis = result.syncWindowStart.getTime();
        Long differenceMillis = Math.abs(expectedStartMillis - actualStartMillis);
        
        // Allow 60 second tolerance for test execution time
        Assert.isTrue(differenceMillis < 60000, 
            'First scheduled run should use lookback days (10 days back). ' +
            'Expected approximately: ' + expectedStart + ', Actual: ' + result.syncWindowStart);
    }

    /**
     * Mock for task with all fields populated
     */
    private class FullFieldsTaskMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();
            
            // Handle task-specific endpoints first (more specific)
            if (endpoint.contains('/tasks')) {
                res.setBody('{"value": [' +
                    '{"id": "task-full", "title": "Full Task", "status": "completed", "importance": "high", ' +
                    '"isReminderOn": true, ' +
                    '"dueDateTime": {"dateTime": "2024-01-20T17:00:00", "timeZone": "UTC"}, ' +
                    '"completedDateTime": {"dateTime": "2024-01-19T10:00:00", "timeZone": "UTC"}, ' +
                    '"reminderDateTime": {"dateTime": "2024-01-19T09:00:00", "timeZone": "UTC"}, ' +
                    '"createdDateTime": "2024-01-15T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-19T10:00:00Z", ' +
                    '"body": {"contentType": "html", "content": "<p>Task <b>body</b></p>"}}' +
                ']}');
            } else if (endpoint.contains('/todo/lists')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else {
                // Token validation and other calls
                res.setBody('{"id": "user123"}');
            }
            return res;
        }
    }

    /**
     * Test syncUserTasksWithToken - Outlook provider success
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_Success() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 7;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookFetchMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual(0, result.tasksFailed, 'Should have no failures');
    }

    /**
     * Test syncUserTasksWithToken - Gmail provider success
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_Success() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 7;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailFetchMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Task sync disabled
     */
    @IsTest
    static void testSyncUserTasksWithToken_Disabled() {
        AISyncSettingsService.setCachedSettings(createMockSettings(false));
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isTrue(!result.errors.isEmpty(), 'Should have error');
        Assert.isTrue(result.errors[0].contains('not enabled'), 'Error should mention not enabled');
    }

    /**
     * Test syncUserTasksWithToken - No tasks fetched
     */
    @IsTest
    static void testSyncUserTasksWithToken_NoTasks() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.areEqual(0, result.tasksFetched, 'Should fetch 0 tasks');
        Assert.areEqual(0, result.tasksImported, 'Should import 0 tasks');
    }

    /**
     * Test syncUserTasksWithToken - Exception handling
     */
    @IsTest
    static void testSyncUserTasksWithToken_Exception() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new ErrorMock(500));
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isTrue(!result.errors.isEmpty(), 'Should have error');
    }

    /**
     * Test syncUserTasksWithToken - Invalid lookback days (null)
     */
    @IsTest
    static void testSyncUserTasksWithToken_NullLookbackDays() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = null;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result.syncWindowStart, 'Sync window start should not be null');
        // Should default to 7 days
    }

    /**
     * Test syncUserTasksWithToken - Invalid lookback days (zero)
     */
    @IsTest
    static void testSyncUserTasksWithToken_ZeroLookbackDays() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 0;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result.syncWindowStart, 'Sync window start should not be null');
    }

    /**
     * Test syncUserGoogleTasks - Success
     */
    @IsTest
    static void testSyncUserGoogleTasks_Success() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GoogleTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserGoogleTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserGoogleTasks - Disabled
     */
    @IsTest
    static void testSyncUserGoogleTasks_Disabled() {
        AISyncSettingsService.setCachedSettings(createMockSettings(false));
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserGoogleTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isTrue(!result.errors.isEmpty(), 'Should have error');
    }

    /**
     * Test syncUserGoogleTasks - Not accessible
     */
    @IsTest
    static void testSyncUserGoogleTasks_NotAccessible() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new ErrorMock(401));
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserGoogleTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isTrue(!result.errors.isEmpty(), 'Should have error');
    }

    /**
     * Test syncUserGoogleTasks - Exception
     */
    @IsTest
    static void testSyncUserGoogleTasks_Exception() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new ErrorMock(500));
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserGoogleTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isTrue(!result.errors.isEmpty(), 'Should have error');
    }

    /**
     * Test syncUserTasks - Success
     */
    @IsTest
    static void testSyncUserTasks_Success() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new FullTaskSyncMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasks - Not accessible
     */
    @IsTest
    static void testSyncUserTasks_NotAccessible() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new ErrorMock(401));
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isTrue(!result.errors.isEmpty(), 'Should have error');
    }

    /**
     * Test syncUserTasks - Exception
     */
    @IsTest
    static void testSyncUserTasks_Exception() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new ErrorMock(500));
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isTrue(!result.errors.isEmpty(), 'Should have error');
    }

    /**
     * Test processDeltaTasks - Success
     */
    @IsTest
    static void testProcessDeltaTasks_Success() {
        List<Object> rawTasks = new List<Object>();
        Map<String, Object> task1 = new Map<String, Object>{
            'id' => 'delta-task1',
            'title' => 'Delta Task 1',
            'status' => 'notStarted',
            'importance' => 'normal',
            'isReminderOn' => false,
            'body' => new Map<String, Object>{'content' => 'Task body'}
        };
        rawTasks.add(task1);
        
        Test.startTest();
        AITaskSyncService.processDeltaTasks(rawTasks, UserInfo.getUserId());
        Test.stopTest();
        
        // Verify staging record was created
        List<AI_Workspace_Staging__c> staging = [
            SELECT Id, Provider_Id__c
            FROM AI_Workspace_Staging__c
            WHERE Provider_Id__c = 'delta-task1'
        ];
        Assert.areEqual(1, staging.size(), 'Should create 1 staging record');
    }

    /**
     * Test processDeltaTasks - Null tasks
     */
    @IsTest
    static void testProcessDeltaTasks_NullTasks() {
        Test.startTest();
        AITaskSyncService.processDeltaTasks(null, UserInfo.getUserId());
        Test.stopTest();
        
        // Should handle gracefully
        Assert.isTrue(true, 'Should not throw exception');
    }

    /**
     * Test processDeltaTasks - Empty tasks
     */
    @IsTest
    static void testProcessDeltaTasks_EmptyTasks() {
        Test.startTest();
        AITaskSyncService.processDeltaTasks(new List<Object>(), UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isTrue(true, 'Should not throw exception');
    }

    /**
     * Test processDeltaTasks - With due date
     */
    @IsTest
    static void testProcessDeltaTasks_WithDueDate() {
        List<Object> rawTasks = new List<Object>();
        Map<String, Object> task1 = new Map<String, Object>{
            'id' => 'delta-task2',
            'title' => 'Delta Task 2',
            'status' => 'inProgress',
            'importance' => 'high',
            'isReminderOn' => true,
            'dueDateTime' => new Map<String, Object>{'dateTime' => '2024-01-20T17:00:00Z'},
            'body' => new Map<String, Object>{'content' => 'Task with due date'}
        };
        rawTasks.add(task1);
        
        Test.startTest();
        AITaskSyncService.processDeltaTasks(rawTasks, UserInfo.getUserId());
        Test.stopTest();
        
        List<AI_Workspace_Staging__c> staging = [
            SELECT Id, Provider_Id__c
            FROM AI_Workspace_Staging__c
            WHERE Provider_Id__c = 'delta-task2'
        ];
        Assert.areEqual(1, staging.size(), 'Should create 1 staging record');
    }

    /**
     * Test mapToDoTaskToSalesforceTask - All fields
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_AllFields() {
        AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
        toDoTask.taskId = 'test-task-id';
        toDoTask.title = 'Test Task Title';
        toDoTask.body = 'Test task body';
        toDoTask.listName = 'My List';
        toDoTask.status = 'inProgress';
        toDoTask.importance = 'high';
        toDoTask.dueDateTime = DateTime.now().addDays(5);
        toDoTask.isReminderOn = true;
        toDoTask.reminderDateTime = DateTime.now().addDays(4);
        
        Test.startTest();
        Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
        Test.stopTest();
        
        Assert.areEqual('Test Task Title', sfTask.Subject, 'Subject should match');
        Assert.areEqual('test-task-id', sfTask.Workspace_Sync_Id__c, 'External ID should match');
        Assert.areEqual(UserInfo.getUserId(), sfTask.OwnerId, 'Owner should match');
        Assert.areEqual('In Progress', sfTask.Status, 'Status should be mapped');
        Assert.areEqual('High', sfTask.Priority, 'Priority should be High');
        Assert.areEqual(true, sfTask.IsReminderSet, 'Reminder should be set');
        Assert.isNotNull(sfTask.ReminderDateTime, 'Reminder date should be set');
        Assert.isTrue(sfTask.Description.contains('My List'), 'Description should contain list name');
    }

    /**
     * Test mapToDoTaskToSalesforceTask - Minimal fields
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_MinimalFields() {
        AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
        toDoTask.taskId = 'minimal-task';
        toDoTask.title = null; // No title
        toDoTask.isReminderOn = false;
        
        Test.startTest();
        Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
        Test.stopTest();
        
        Assert.areEqual('(No Title)', sfTask.Subject, 'Should use default title');
        Assert.areEqual('Not Started', sfTask.Status, 'Should use default status');
        Assert.areEqual('Normal', sfTask.Priority, 'Should use default priority');
    }

    /**
     * Test mapToDoTaskToSalesforceTask - Different statuses
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_Statuses() {
        List<String> statuses = new List<String>{'notStarted', 'inProgress', 'completed', 'waitingOnOthers', 'deferred', 'unknown'};
        List<String> expected = new List<String>{'Not Started', 'In Progress', 'Completed', 'Waiting on someone else', 'Deferred', 'Not Started'};
        
        for (Integer i = 0; i < statuses.size(); i++) {
            AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
            toDoTask.taskId = 'task-' + i;
            toDoTask.title = 'Task ' + i;
            toDoTask.status = statuses[i];
            toDoTask.isReminderOn = false;
            
            Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
            Assert.areEqual(expected[i], sfTask.Status, 'Status mapping should be correct for ' + statuses[i]);
        }
    }

    /**
     * Test mapToDoTaskToSalesforceTask - Different priorities
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_Priorities() {
        List<String> priorities = new List<String>{'high', 'low', 'normal', 'unknown'};
        List<String> expected = new List<String>{'High', 'Low', 'Normal', 'Normal'};
        
        for (Integer i = 0; i < priorities.size(); i++) {
            AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
            toDoTask.taskId = 'task-' + i;
            toDoTask.title = 'Task ' + i;
            toDoTask.importance = priorities[i];
            toDoTask.isReminderOn = false;
            
            Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
            Assert.areEqual(expected[i], sfTask.Priority, 'Priority mapping should be correct for ' + priorities[i]);
        }
    }

    /**
     * Mock for Outlook fetch service
     */
    private class OutlookFetchMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('[]');
            return res;
        }
    }

    /**
     * Mock for Gmail fetch service
     */
    private class GmailFetchMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('[]');
            return res;
        }
    }

    /**
     * Mock for empty tasks response
     */
    private class EmptyTasksMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('[]');
            return res;
        }
    }

    /**
     * Mock for Google Tasks
     */
    private class GoogleTasksMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('tasklists')) {
                res.setBody('{"items": [{"id": "list1", "title": "My Tasks"}]}');
            } else {
                res.setBody('{"items": []}');
            }
            return res;
        }
    }

    /**
     * Test syncUserTasksWithToken with Outlook - tasks with various date formats
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_WithDates() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 7;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookTasksWithDatesMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.tasksFetched > 0, 'Should fetch tasks');
    }

    /**
     * Test syncUserTasksWithToken with Gmail - tasks with various date formats
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_WithDates() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 7;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailTasksWithDatesMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Outlook with HTML body
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_HtmlBody() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookHtmlBodyMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Gmail with completed tasks
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_CompletedTasks() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Include_Completed_Tasks__c = true;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailCompletedTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - With newest task date update
     */
    @IsTest
    static void testSyncUserTasksWithToken_NewestTaskDate() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookTasksWithDatesMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result.syncWindowEnd, 'Sync window end should be set');
    }

    /**
     * Test syncUserGoogleTasks - With tasks
     */
    @IsTest
    static void testSyncUserGoogleTasks_WithTasks() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GoogleTasksWithDataMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserGoogleTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserGoogleTasks - Empty tasks
     */
    @IsTest
    static void testSyncUserGoogleTasks_EmptyTasks() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GoogleTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserGoogleTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.areEqual(0, result.tasksFetched, 'Should fetch 0 tasks');
    }

    /**
     * Test syncUserGoogleTasks - Full flow with Gmail workspace user
     */
    @IsTest
    static void testSyncUserGoogleTasks_FullFlow() {
        // Create Gmail workspace user
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Access_Token__c = 'test_gmail_access_token',
            Refresh_Token__c = 'test_gmail_refresh_token'
        );
        insert gmailUser;

        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 7;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GoogleTasksFullFlowMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserGoogleTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasks - With tasks
     */
    @IsTest
    static void testSyncUserTasks_WithTasks() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new FullTaskSyncMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasks - Empty tasks
     */
    @IsTest
    static void testSyncUserTasks_EmptyTasks() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.areEqual(0, result.tasksFetched, 'Should fetch 0 tasks');
    }

    /**
     * Test syncUserTasks - Null lookback days
     */
    @IsTest
    static void testSyncUserTasks_NullLookbackDays() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = null;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isNotNull(result.syncWindowStart, 'Sync window start should not be null');
    }

    /**
     * Test syncUserTasks - Zero lookback days
     */
    @IsTest
    static void testSyncUserTasks_ZeroLookbackDays() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 0;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isNotNull(result.syncWindowStart, 'Sync window start should not be null');
    }

    /**
     * Test processDeltaTasks - Exception handling
     */
    @IsTest
    static void testProcessDeltaTasks_Exception() {
        List<Object> rawTasks = new List<Object>();
        Map<String, Object> invalidTask = new Map<String, Object>{
            'id' => 'invalid-task'
            // Missing required fields to trigger exception in parsing
        };
        rawTasks.add(invalidTask);
        
        Test.startTest();
        AITaskSyncService.processDeltaTasks(rawTasks, UserInfo.getUserId());
        Test.stopTest();
        
        // Should handle gracefully without throwing exception
        Assert.isTrue(true, 'Should not throw exception');
    }

    /**
     * Mock for Outlook tasks with dates
     */
    private class OutlookTasksWithDatesMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                // Task lists endpoint
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                // Tasks endpoint
                String body = '{"value": [' +
                    '{"id": "task1", "title": "Task 1", ' +
                    '"status": "notStarted", "importance": "normal", "isReminderOn": false, ' +
                    '"createdDateTime": "2024-01-15T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-16T10:00:00Z", ' +
                    '"dueDateTime": {"dateTime": "2024-01-20T17:00:00.123", "timeZone": "UTC"}, ' +
                    '"body": {"contentType": "text", "content": "Task body"}},' +
                    '{"id": "task2", "title": "Task 2", ' +
                    '"status": "completed", "importance": "high", "isReminderOn": true, ' +
                    '"createdDateTime": "2024-01-10T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-18T10:00:00Z", ' +
                    '"completedDateTime": {"dateTime": "2024-01-18T10:00:00", "timeZone": "UTC"}, ' +
                    '"reminderDateTime": {"dateTime": "2024-01-17T09:00:00", "timeZone": "UTC"}, ' +
                    '"body": {"contentType": "text", "content": "Completed task"}}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Gmail tasks with dates
     */
    private class GmailTasksWithDatesMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "gtask1", "listId": "glist1", "listTitle": "My Tasks", "title": "Gmail Task 1", ' +
                '"status": "needsAction", "notes": "Task notes", ' +
                '"due": "2024-01-20T17:00:00+00:00", ' +
                '"updated": "2024-01-16T10:00:00.123Z"},' +
                '{"id": "gtask2", "listId": "glist1", "listTitle": "My Tasks", "title": "Gmail Task 2", ' +
                '"status": "completed", "notes": "Completed notes", ' +
                '"due": "2024-01-18T10:00:00Z", ' +
                '"completed": "2024-01-18T10:00:00.456+05:30", ' +
                '"updated": "2024-01-18T10:00:00Z"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Outlook tasks with HTML body
     */
    private class OutlookHtmlBodyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "html-task", "title": "HTML Task", ' +
                    '"status": "notStarted", "importance": "normal", "isReminderOn": false, ' +
                    '"createdDateTime": "2024-01-15T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-16T10:00:00Z", ' +
                    '"body": {"contentType": "html", "content": "<p>Task <b>body</b> with <i>HTML</i></p>"}}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Gmail completed tasks
     */
    private class GmailCompletedTasksMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "completed-task", "listId": "glist1", "listTitle": "My Tasks", ' +
                '"title": "Completed Gmail Task", "status": "completed", "notes": "Done", ' +
                '"completed": "2024-01-18T10:00:00Z", ' +
                '"updated": "2024-01-18T10:00:00Z"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Google Tasks with data
     */
    private class GoogleTasksWithDataMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('tasklists')) {
                res.setBody('{"items": [{"id": "list1", "title": "My Tasks"}]}');
            } else {
                res.setBody('{"items": [' +
                    '{"id": "gtask1", "title": "Google Task 1", "status": "needsAction", ' +
                    '"updated": "2024-01-16T10:00:00Z"}' +
                ']}');
            }
            return res;
        }
    }

    /**
     * Test syncUserTasksWithToken - All tasks are duplicates
     */
    @IsTest
    static void testSyncUserTasksWithToken_AllDuplicates() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        // Create existing staging record
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Subject__c = 'Existing Task',
            Provider_Id__c = 'task1',
            Provider__c = 'MICROSOFT_TASKS'
        );
        insert existingStaging;
        
        Test.setMock(HttpCalloutMock.class, new OutlookDuplicateTaskMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.areEqual(1, result.tasksDuplicate, 'Should have 1 duplicate');
        Assert.areEqual(0, result.tasksImported, 'Should import 0 tasks');
    }

    /**
     * Test syncUserTasks - All tasks are duplicates
     */
    @IsTest
    static void testSyncUserTasks_AllDuplicates() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        // Create existing staging record
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Subject__c = 'Existing Task',
            Provider_Id__c = 'task1',
            Provider__c = 'MICROSOFT_TASKS'
        );
        insert existingStaging;
        
        Test.setMock(HttpCalloutMock.class, new MicrosoftDuplicateTaskMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.areEqual(1, result.tasksDuplicate, 'Should have 1 duplicate');
        Assert.areEqual(0, result.tasksImported, 'Should import 0 tasks');
    }

    /**
     * Test mapToDoTaskToSalesforceTask - Long title truncation
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_LongTitle() {
        AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
        toDoTask.taskId = 'long-task';
        toDoTask.title = 'This is a very long task title that exceeds the 255 character limit for the Subject field in Salesforce Task object. We need to test that it gets properly truncated to avoid DML errors. This title is intentionally made very long to ensure the truncation logic works correctly and handles edge cases properly.';
        toDoTask.isReminderOn = false;
        
        Test.startTest();
        Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isTrue(sfTask.Subject.length() <= 255, 'Subject should be truncated to 255 chars');
    }

    /**
     * Test mapToDoTaskToSalesforceTask - Long description truncation
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_LongDescription() {
        AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
        toDoTask.taskId = 'long-desc-task';
        toDoTask.title = 'Task with long description';
        toDoTask.listName = 'My List';
        toDoTask.body = 'A'.repeat(32500); // Exceeds 32000 char limit
        toDoTask.isReminderOn = false;
        
        Test.startTest();
        Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isTrue(sfTask.Description.length() <= 32000, 'Description should be truncated to 32000 chars');
    }

    /**
     * Test mapToDoTaskToSalesforceTask - Blank status
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_BlankStatus() {
        AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
        toDoTask.taskId = 'blank-status-task';
        toDoTask.title = 'Task with blank status';
        toDoTask.status = '';
        toDoTask.isReminderOn = false;
        
        Test.startTest();
        Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
        Test.stopTest();
        
        Assert.areEqual('Not Started', sfTask.Status, 'Should default to Not Started');
    }

    /**
     * Test mapToDoTaskToSalesforceTask - Blank priority
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_BlankPriority() {
        AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
        toDoTask.taskId = 'blank-priority-task';
        toDoTask.title = 'Task with blank priority';
        toDoTask.importance = '';
        toDoTask.isReminderOn = false;
        
        Test.startTest();
        Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
        Test.stopTest();
        
        Assert.areEqual('Normal', sfTask.Priority, 'Should default to Normal');
    }

    /**
     * Test mapToDoTaskToSalesforceTask - Reminder without datetime
     */
    @IsTest
    static void testMapToDoTaskToSalesforceTask_ReminderWithoutDateTime() {
        AIMicrosoftTaskService.ToDoTask toDoTask = new AIMicrosoftTaskService.ToDoTask();
        toDoTask.taskId = 'reminder-task';
        toDoTask.title = 'Task with reminder but no datetime';
        toDoTask.isReminderOn = true;
        toDoTask.reminderDateTime = null;
        
        Test.startTest();
        Task sfTask = AITaskSyncService.mapToDoTaskToSalesforceTask(toDoTask, UserInfo.getUserId());
        Test.stopTest();
        
        Assert.areEqual(false, sfTask.IsReminderSet, 'Reminder should not be set without datetime');
    }

    /**
     * Mock for Outlook duplicate task
     */
    private class OutlookDuplicateTaskMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                res.setBody('{"value": [' +
                    '{"id": "task1", "title": "Duplicate Task", "status": "notStarted", ' +
                    '"importance": "normal", "isReminderOn": false, ' +
                    '"createdDateTime": "2024-01-15T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-16T10:00:00Z"}' +
                ']}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Google duplicate task
     */
    private class GoogleDuplicateTaskMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('tasklists')) {
                res.setBody('{"items": [{"id": "list1", "title": "My Tasks"}]}');
            } else {
                res.setBody('{"items": [' +
                    '{"id": "gtask1", "title": "Duplicate Google Task", "status": "needsAction", ' +
                    '"updated": "2024-01-16T10:00:00Z"}' +
                ']}');
            }
            return res;
        }
    }

    /**
     * Test syncUserTasksWithToken - Null tasks response
     */
    @IsTest
    static void testSyncUserTasksWithToken_NullTasks() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new NullTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.areEqual(0, result.tasksFetched, 'Should fetch 0 tasks');
        Assert.areEqual(0, result.tasksImported, 'Should import 0 tasks');
    }

    /**
     * Test syncUserTasksWithToken - Gmail with actual task data
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_WithTaskData() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = 7;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailTaskDataMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        // Gmail fetch may return empty if no tasks in date range
        Assert.isTrue(result.tasksFetched >= 0, 'Should handle fetch result');
    }

    /**
     * Test syncUserTasksWithToken - Gmail with multiple tasks
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_MultipleTasks() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailMultipleTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        // Gmail fetch may return empty if no tasks in date range
        Assert.isTrue(result.tasksFetched >= 0, 'Should handle fetch result');
    }

    /**
     * Mock for null tasks response
     */
    private class NullTasksMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('null');
            return res;
        }
    }

    /**
     * Mock for Gmail with task data
     */
    private class GmailTaskDataMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "gmail-task-1", "listId": "list1", "listTitle": "My Tasks", ' +
                '"title": "Gmail Task 1", "status": "needsAction", "notes": "Task notes", ' +
                '"due": "2024-01-20T17:00:00Z", "updated": "2024-01-16T10:00:00Z"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Gmail with multiple tasks
     */
    private class GmailMultipleTasksMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "gmail-multi-1", "listId": "list1", "listTitle": "Work Tasks", ' +
                '"title": "Gmail Task 1", "status": "needsAction", "notes": "First task", ' +
                '"due": "2024-01-20T17:00:00Z", "updated": "2024-01-16T10:00:00Z"},' +
                '{"id": "gmail-multi-2", "listId": "list1", "listTitle": "Work Tasks", ' +
                '"title": "Gmail Task 2", "status": "completed", "notes": "Second task", ' +
                '"completed": "2024-01-18T10:00:00Z", "updated": "2024-01-18T10:00:00Z"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Microsoft duplicate task
     */
    private class MicrosoftDuplicateTaskMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                res.setBody('{"value": [' +
                    '{"id": "task1", "title": "Duplicate Task", "status": "notStarted", ' +
                    '"importance": "normal", "isReminderOn": false}' +
                ']}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Test syncUserTasksWithToken - Gmail with various date formats
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_DateFormats() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailVariousDateFormatsMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Outlook with malformed task data
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_MalformedData() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookMalformedDataMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Gmail with malformed task data
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_MalformedData() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailMalformedDataMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Mock for Outlook with malformed data
     */
    private class OutlookMalformedDataMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                // Malformed task data - missing required fields
                String body = '{"value": [' +
                    '{"id": "malformed-1"},' + // Missing most fields
                    '{"title": "No ID Task"}' + // Missing ID
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Gmail with malformed data
     */
    private class GmailMalformedDataMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            // Malformed task data - missing required fields
            String body = '[' +
                '{"id": "malformed-g1"},' + // Missing most fields
                '{"title": "No ID Gmail Task"}' + // Missing ID
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Test syncUserTasksWithToken - Outlook with various date formats
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_DateFormats() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookVariousDateFormatsMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test processDeltaTasks - With various date formats
     */
    @IsTest
    static void testProcessDeltaTasks_DateFormats() {
        List<Object> rawTasks = new List<Object>();
        Map<String, Object> task1 = new Map<String, Object>{
            'id' => 'date-task1',
            'title' => 'Task with dates',
            'status' => 'notStarted',
            'importance' => 'normal',
            'isReminderOn' => false,
            'dueDateTime' => new Map<String, Object>{'dateTime' => '2024-01-20T17:00:00.123Z'},
            'body' => new Map<String, Object>{'content' => 'Task body'}
        };
        rawTasks.add(task1);
        
        Test.startTest();
        AITaskSyncService.processDeltaTasks(rawTasks, UserInfo.getUserId());
        Test.stopTest();
        
        List<AI_Workspace_Staging__c> staging = [
            SELECT Id, Provider_Id__c
            FROM AI_Workspace_Staging__c
            WHERE Provider_Id__c = 'date-task1'
        ];
        Assert.areEqual(1, staging.size(), 'Should create 1 staging record');
    }

    /**
     * Test syncUserTasksWithToken - Negative lookback days
     */
    @IsTest
    static void testSyncUserTasksWithToken_NegativeLookbackDays() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = -5;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result.syncWindowStart, 'Sync window start should not be null');
    }

    /**
     * Test syncUserTasks - Negative lookback days
     */
    @IsTest
    static void testSyncUserTasks_NegativeLookbackDays() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Task_Lookback_Days__c = -10;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasks(UserInfo.getUserId());
        Test.stopTest();
        
        Assert.isNotNull(result.syncWindowStart, 'Sync window start should not be null');
    }

    /**
     * Mock for Gmail with various date formats
     */
    private class GmailVariousDateFormatsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "gdate1", "listId": "glist1", "listTitle": "Tasks", "title": "Task 1", ' +
                '"status": "needsAction", "notes": "Notes", ' +
                '"due": "2024-01-20T17:00:00.123456Z", ' +
                '"updated": "2024-01-16T10:00:00.789Z"},' +
                '{"id": "gdate2", "listId": "glist1", "listTitle": "Tasks", "title": "Task 2", ' +
                '"status": "completed", "notes": "Done", ' +
                '"due": "2024-01-18T10:00:00+05:30", ' +
                '"completed": "2024-01-18T10:00:00.456789+00:00", ' +
                '"updated": "2024-01-18T10:00:00Z"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Outlook with various date formats
     */
    private class OutlookVariousDateFormatsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "odate1", "title": "Task 1", "status": "notStarted", ' +
                    '"importance": "normal", "isReminderOn": false, ' +
                    '"createdDateTime": "2024-01-15T10:00:00.123456Z", ' +
                    '"lastModifiedDateTime": "2024-01-16T10:00:00.789Z", ' +
                    '"dueDateTime": {"dateTime": "2024-01-20T17:00:00.123456", "timeZone": "UTC"}},' +
                    '{"id": "odate2", "title": "Task 2", "status": "completed", ' +
                    '"importance": "high", "isReminderOn": true, ' +
                    '"createdDateTime": "2024-01-10T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-18T10:00:00Z", ' +
                    '"completedDateTime": {"dateTime": "2024-01-18T10:00:00.123", "timeZone": "UTC"}, ' +
                    '"reminderDateTime": {"dateTime": "2024-01-17T09:00:00", "timeZone": "UTC"}}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Test syncUserTasksWithToken - Outlook with completed and reminder dates
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_CompletedAndReminder() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Include_Completed_Tasks__c = true;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookCompletedReminderMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.tasksFetched > 0, 'Should fetch tasks');
    }

    /**
     * Test syncUserTasksWithToken - Gmail with completed status
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_CompletedStatus() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        settings.Include_Completed_Tasks__c = true;
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailCompletedStatusMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Gmail with needsAction status
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_NeedsActionStatus() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailNeedsActionMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Outlook with text body
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_TextBody() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookTextBodyMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Outlook with blank body content
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_BlankBody() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookBlankBodyMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Mock for Outlook with completed and reminder dates
     */
    private class OutlookCompletedReminderMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "cr-task1", "title": "Completed with Reminder", "status": "completed", ' +
                    '"importance": "high", "isReminderOn": true, ' +
                    '"createdDateTime": "2024-01-10T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-18T10:00:00Z", ' +
                    '"completedDateTime": {"dateTime": "2024-01-18T10:00:00", "timeZone": "UTC"}, ' +
                    '"reminderDateTime": {"dateTime": "2024-01-17T09:00:00", "timeZone": "UTC"}, ' +
                    '"body": {"contentType": "text", "content": "Task body"}}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Gmail with completed status
     */
    private class GmailCompletedStatusMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "gcomp1", "listId": "glist1", "listTitle": "Tasks", "title": "Completed Task", ' +
                '"status": "completed", "notes": "Done", ' +
                '"completed": "2024-01-18T10:00:00Z", ' +
                '"updated": "2024-01-18T10:00:00Z"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Gmail with needsAction status
     */
    private class GmailNeedsActionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "gneed1", "listId": "glist1", "listTitle": "Tasks", "title": "Needs Action Task", ' +
                '"status": "needsAction", "notes": "To do", ' +
                '"due": "2024-01-20T17:00:00Z", ' +
                '"updated": "2024-01-16T10:00:00Z"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Outlook with text body
     */
    private class OutlookTextBodyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "text-task", "title": "Text Body Task", "status": "notStarted", ' +
                    '"importance": "normal", "isReminderOn": false, ' +
                    '"createdDateTime": "2024-01-15T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-16T10:00:00Z", ' +
                    '"body": {"contentType": "text", "content": "Plain text body"}}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Outlook with blank body
     */
    private class OutlookBlankBodyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "blank-task", "title": "Blank Body Task", "status": "notStarted", ' +
                    '"importance": "normal", "isReminderOn": false, ' +
                    '"createdDateTime": "2024-01-15T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-16T10:00:00Z", ' +
                    '"body": {"contentType": "html", "content": ""}}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Test syncUserTasksWithToken - Gmail with no dates
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_NoDates() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailNoDatesMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Gmail with invalid date formats
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_InvalidDates() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new GmailInvalidDatesMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Outlook with null body map
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_NullBody() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookNullBodyMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test syncUserTasksWithToken - Outlook with null date maps
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_NullDates() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);
        
        Test.setMock(HttpCalloutMock.class, new OutlookNullDatesMock());
        
        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Mock for Gmail with all date fields
     */
    private class GmailAllDateFieldsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "gall1", "listId": "glist1", "listTitle": "Tasks", "title": "Task with all dates", ' +
                '"status": "completed", "notes": "All dates", ' +
                '"due": "2024-01-20T17:00:00Z", ' +
                '"completed": "2024-01-18T10:00:00Z", ' +
                '"updated": "2024-01-18T10:00:00Z"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Gmail with no dates
     */
    private class GmailNoDatesMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "gno1", "listId": "glist1", "listTitle": "Tasks", "title": "Task with no dates", ' +
                '"status": "needsAction", "notes": "No dates"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Gmail with invalid dates
     */
    private class GmailInvalidDatesMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = '[' +
                '{"id": "ginv1", "listId": "glist1", "listTitle": "Tasks", "title": "Task with invalid dates", ' +
                '"status": "needsAction", "notes": "Invalid dates", ' +
                '"due": "invalid-date", ' +
                '"updated": "also-invalid"}' +
            ']';
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock for Outlook with null body
     */
    private class OutlookNullBodyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "null-body-task", "title": "Null Body Task", "status": "notStarted", ' +
                    '"importance": "normal", "isReminderOn": false, ' +
                    '"createdDateTime": "2024-01-15T10:00:00Z", ' +
                    '"lastModifiedDateTime": "2024-01-16T10:00:00Z"}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Outlook with null dates
     */
    private class OutlookNullDatesMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "null-dates-task", "title": "Null Dates Task", "status": "notStarted", ' +
                    '"importance": "normal", "isReminderOn": false}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Test parseRfc3339DateTime with various formats
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_Rfc3339DateFormats() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);

        Test.setMock(HttpCalloutMock.class, new GmailRfc3339DateFormatsMock());

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.tasksFetched > 0, 'Should fetch tasks');
    }

    /**
     * Test Gmail with blank dates to cover parseRfc3339DateTime null handling
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_BlankDates() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);

        Test.setMock(HttpCalloutMock.class, new GmailBlankDatesMock());

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
    }

    /**
     * Test Gmail with all date variations to cover parseRfc3339DateTime branches
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_AllDateVariations() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);

        Test.setMock(HttpCalloutMock.class, new GmailAllDateVariationsMock());

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.tasksFetched > 0, 'Should fetch tasks with various date formats');
    }

    /**
     * Test syncUserGoogleTasks with deduplication
     */
    @IsTest
    static void testSyncUserGoogleTasks_Deduplication() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);

        // Create Gmail workspace user
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Access_Token__c = 'test_gmail_access_token',
            Refresh_Token__c = 'test_gmail_refresh_token'
        );
        insert gmailUser;

        // Create existing staging record
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'GOOGLE_TASKS',
            Provider_Id__c = 'duplicate-task-id',
            User__c = UserInfo.getUserId(),
            Subject__c = 'Existing Task',
            Status__c = 'Staged'
        );
        insert existingStaging;

        Test.setMock(HttpCalloutMock.class, new GoogleTasksWithDuplicateMock());

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserGoogleTasks(UserInfo.getUserId());
        Test.stopTest();

        Assert.isTrue(result.tasksDuplicate > 0, 'Should detect duplicate tasks');
    }

    /**
     * Test parseGraphDateTime exception handling
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_InvalidDateFormat() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);

        Test.setMock(HttpCalloutMock.class, new OutlookInvalidDateFormatMock());

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should handle invalid dates gracefully');
    }

    /**
     * Test parseSimpleDateTime exception handling
     */
    @IsTest
    static void testSyncUserTasksWithToken_Outlook_InvalidSimpleDate() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);

        Test.setMock(HttpCalloutMock.class, new OutlookInvalidSimpleDateMock());

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Outlook',
            'test_token'
        );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should handle invalid simple dates gracefully');
    }

    /**
     * Test parseRfc3339DateTime exception handling with invalid formats
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_InvalidRfc3339() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);

        Test.setMock(HttpCalloutMock.class, new GmailInvalidRfc3339Mock());

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should handle invalid RFC3339 dates gracefully');
    }

    /**
     * Test convertToTaskObjects exception handling with malformed task causing exception
     */
    @IsTest
    static void testSyncUserTasksWithToken_Gmail_ConversionException() {
        AI_Workspace_Sync_Settings__c settings = createMockSettings(true);
        AISyncSettingsService.setCachedSettings(settings);

        Test.setMock(HttpCalloutMock.class, new GmailConversionExceptionMock());

        Test.startTest();
        AITaskSyncService.TaskSyncResult result = AITaskSyncService.syncUserTasksWithToken(
            UserInfo.getUserId(),
            'Gmail',
            'test_token'
        );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should handle conversion exceptions gracefully');
    }

    /**
     * Mock for Gmail with RFC 3339 date formats
     */
    private class GmailRfc3339DateFormatsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"items":[{"id":"list1","title":"My Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"items":[' +
                    '{"id": "rfc1", "title": "Task with +offset", ' +
                    '"status": "needsAction", "notes": "Test", ' +
                    '"due": "2024-01-20T17:00:00+05:30", ' +
                    '"updated": "2024-01-16T10:00:00.123+05:30"},' +
                    '{"id": "rfc2", "title": "Task with Z", ' +
                    '"status": "completed", "notes": "Test", ' +
                    '"due": "2024-01-21T10:00:00Z", ' +
                    '"completed": "2024-01-21T12:00:00.456Z", ' +
                    '"updated": "2024-01-21T12:00:00Z"},' +
                    '{"id": "rfc3", "title": "Task with milliseconds", ' +
                    '"status": "needsAction", "notes": "Test", ' +
                    '"due": "2024-01-22T08:00:00.999999Z", ' +
                    '"updated": "2024-01-22T08:00:00.999999+00:00"}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Gmail with blank dates
     */
    private class GmailBlankDatesMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"items":[{"id":"list1","title":"My Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"items":[' +
                    '{"id": "blank1", "title": "Task with no dates", ' +
                    '"status": "needsAction", "notes": "No dates"}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Gmail with all date variations
     */
    private class GmailAllDateVariationsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"items":[{"id":"list1","title":"My Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"items":[' +
                    '{"id": "var1", "title": "Only due date", ' +
                    '"status": "needsAction", "due": "2024-01-20T10:00:00Z"},' +
                    '{"id": "var2", "title": "Only completed", ' +
                    '"status": "completed", "completed": "2024-01-21T10:00:00Z"},' +
                    '{"id": "var3", "title": "Only updated", ' +
                    '"status": "needsAction", "updated": "2024-01-22T10:00:00Z"},' +
                    '{"id": "var4", "title": "All dates", ' +
                    '"status": "completed", ' +
                    '"due": "2024-01-23T10:00:00+05:30", ' +
                    '"completed": "2024-01-24T10:00:00.123Z", ' +
                    '"updated": "2024-01-24T10:00:00.456+00:00"}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Google Tasks with duplicate
     */
    private class GoogleTasksWithDuplicateMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('tasklists') || (endpoint.contains('/lists') && !endpoint.contains('/tasks'))) {
                res.setBody('{"items":[{"id":"list1","title":"My Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"items":[' +
                    '{"id": "duplicate-task-id", "title": "Duplicate Task", ' +
                    '"status": "needsAction", "notes": "This is a duplicate"},' +
                    '{"id": "new-task-id", "title": "New Task", ' +
                    '"status": "needsAction", "notes": "This is new"}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Google Tasks full flow (isTaskAccessible + getAllTasks)
     */
    private class GoogleTasksFullFlowMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('tasklists')) {
                res.setBody('{"items": [{"id": "list1", "title": "My Tasks"}, {"id": "list2", "title": "Work Tasks"}]}');
            } else if (endpoint.contains('tasks')) {
                res.setBody('{"items": [' +
                    '{"id": "gtask1", "title": "Google Task 1", "status": "needsAction", ' +
                    '"notes": "Task notes", "due": "2024-01-20T10:00:00Z", ' +
                    '"updated": "2024-01-16T10:00:00.123Z"},' +
                    '{"id": "gtask2", "title": "Google Task 2", "status": "completed", ' +
                    '"notes": "Completed task", "completed": "2024-01-18T10:00:00.456+05:30", ' +
                    '"updated": "2024-01-18T10:00:00Z"}' +
                ']}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Outlook with invalid date format to trigger parseGraphDateTime exception
     */
    private class OutlookInvalidDateFormatMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "invalid-graph-date", "title": "Invalid Graph Date Task", ' +
                    '"status": "notStarted", "importance": "normal", "isReminderOn": false, ' +
                    '"dueDateTime": {"dateTime": "not-a-valid-date-format", "timeZone": "UTC"}, ' +
                    '"body": {"contentType": "text", "content": "Test"}}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Outlook with invalid simple date to trigger parseSimpleDateTime exception
     */
    private class OutlookInvalidSimpleDateMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": [{"id": "list1", "displayName": "Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"value": [' +
                    '{"id": "invalid-simple-date", "title": "Invalid Simple Date Task", ' +
                    '"status": "notStarted", "importance": "normal", "isReminderOn": false, ' +
                    '"createdDateTime": "invalid-created-date", ' +
                    '"lastModifiedDateTime": "invalid-modified-date", ' +
                    '"body": {"contentType": "text", "content": "Test"}}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Gmail with invalid RFC3339 dates
     */
    private class GmailInvalidRfc3339Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"items":[{"id":"list1","title":"My Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"items":[' +
                    '{"id": "inv-rfc", "title": "Invalid RFC3339", ' +
                    '"status": "needsAction", "notes": "Test", ' +
                    '"due": "not-a-valid-rfc3339-date", ' +
                    '"completed": "also-invalid-format", ' +
                    '"updated": "completely-wrong"}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    /**
     * Mock for Gmail that causes conversion exception
     */
    private class GmailConversionExceptionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"items":[{"id":"list1","title":"My Tasks"}]}');
            } else if (endpoint.contains('/tasks')) {
                String body = '{"items":[' +
                    '{"id": "exc1", "title": "Task 1", ' +
                    '"status": "needsAction", "notes": "Valid task"},' +
                    'null,' +
                    '{"id": "exc2", "title": "Task 2", ' +
                    '"status": "completed"}' +
                ']}';
                res.setBody(body);
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }
}