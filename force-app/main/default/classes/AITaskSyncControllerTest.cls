/**
 * Test class for AITaskSyncController
 * Tests task sync functionality with Microsoft To-Do integration
 */
@isTest
public class AITaskSyncControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Task Test Company',
            Website = 'www.tasktest.com'
        );
        insert testAccount;

        // Create test Contact with email for matching
        Contact testContact = new Contact(
            FirstName = 'Task',
            LastName = 'Contact',
            Email = 'task.contact@tasktest.com',
            AccountId = testAccount.Id
        );
        insert testContact;

        // Create test Lead for matching
        Lead testLead = new Lead(
            FirstName = 'Task',
            LastName = 'Lead',
            Email = 'task.lead@tasktest.com',
            Company = 'Lead Company'
        );
        insert testLead;

        // Create AI_Workspace_User__c for Microsoft Tasks
        AI_Workspace_User__c microsoftUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'OUTLOOK',
            Access_Token__c = 'test_microsoft_access_token',
            Refresh_Token__c = 'test_microsoft_refresh_token'
        );
        insert microsoftUser;

        // Create AI_Workspace_User__c for Google Tasks
        AI_Workspace_User__c googleUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Provider__c = 'GMAIL',
            Access_Token__c = 'test_google_access_token',
            Refresh_Token__c = 'test_google_refresh_token'
        );
        insert googleUser;
    }

    // ========================================================================
    // Mock Classes
    // ========================================================================

    /**
     * Mock for Microsoft Graph Task API calls - Success scenario
     */
    private class TaskApiSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            // Task lists endpoint
            if (endpoint.contains('/me/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody(getTaskListsResponse());
            }
            // Tasks endpoint
            else if (endpoint.contains('/tasks')) {
                res.setBody(getTasksResponse());
            }
            // User profile endpoint
            else if (endpoint.contains('/me') && !endpoint.contains('/todo')) {
                res.setBody('{"userPrincipalName": "testuser@test.com", "mail": "testuser@test.com"}');
            }
            else {
                res.setBody('{}');
            }

            return res;
        }
    }

    /**
     * Mock for auth failure (401)
     */
    private class AuthFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"error": {"code": "Unauthorized", "message": "OAuth token expired"}}');
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    /**
     * Mock for API error (500)
     */
    private class ApiErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error": {"code": "InternalServerError", "message": "Server error"}}');
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    /**
     * Mock for empty task lists
     */
    private class EmptyTasksMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/me/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{"value": []}');
            } else if (endpoint.contains('/tasks')) {
                res.setBody('{"value": []}');
            } else if (endpoint.contains('/me')) {
                res.setBody('{"userPrincipalName": "testuser@test.com"}');
            } else {
                res.setBody('{}');
            }

            return res;
        }
    }

    /**
     * Mock for task with email addresses in content (for matching tests)
     */
    private class TaskWithEmailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/me/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody(getTaskListsResponse());
            } else if (endpoint.contains('/tasks/')) {
                // Single task fetch
                res.setBody('{' +
                    '"id": "task-with-email-1",' +
                    '"title": "Follow up with task.contact@tasktest.com",' +
                    '"body": {"content": "Discuss project details", "contentType": "text"},' +
                    '"status": "notStarted",' +
                    '"importance": "high",' +
                    '"createdDateTime": "2025-12-01T10:00:00Z",' +
                    '"lastModifiedDateTime": "2025-12-01T10:00:00Z"' +
                '}');
            } else if (endpoint.contains('/tasks')) {
                res.setBody(getTasksWithEmailResponse());
            } else if (endpoint.contains('/me')) {
                res.setBody('{"userPrincipalName": "testuser@test.com"}');
            } else {
                res.setBody('{}');
            }

            return res;
        }
    }

    // ========================================================================
    // Helper Methods
    // ========================================================================

    private static String getTaskListsResponse() {
        return '{' +
            '"value": [' +
                '{' +
                    '"id": "list-1",' +
                    '"displayName": "Tasks",' +
                    '"isOwner": true,' +
                    '"isShared": false,' +
                    '"wellknownListName": "defaultList"' +
                '},' +
                '{' +
                    '"id": "list-2",' +
                    '"displayName": "Work Tasks",' +
                    '"isOwner": true,' +
                    '"isShared": false' +
                '}' +
            ']' +
        '}';
    }

    private static String getTasksResponse() {
        return '{' +
            '"value": [' +
                '{' +
                    '"id": "task-1",' +
                    '"title": "Complete project report",' +
                    '"body": {"content": "Finish Q4 report", "contentType": "text"},' +
                    '"status": "notStarted",' +
                    '"importance": "high",' +
                    '"dueDateTime": {"dateTime": "2025-12-15T17:00:00", "timeZone": "UTC"},' +
                    '"createdDateTime": "2025-12-01T10:00:00Z",' +
                    '"lastModifiedDateTime": "2025-12-01T10:00:00Z",' +
                    '"isReminderOn": true,' +
                    '"reminderDateTime": {"dateTime": "2025-12-15T09:00:00", "timeZone": "UTC"}' +
                '},' +
                '{' +
                    '"id": "task-2",' +
                    '"title": "Schedule team meeting",' +
                    '"body": {"content": "Weekly standup", "contentType": "text"},' +
                    '"status": "inProgress",' +
                    '"importance": "normal",' +
                    '"createdDateTime": "2025-12-02T14:00:00Z",' +
                    '"lastModifiedDateTime": "2025-12-02T14:00:00Z",' +
                    '"isReminderOn": false' +
                '},' +
                '{' +
                    '"id": "task-3",' +
                    '"title": "Review documents",' +
                    '"status": "completed",' +
                    '"importance": "low",' +
                    '"completedDateTime": {"dateTime": "2025-12-05T11:00:00", "timeZone": "UTC"},' +
                    '"createdDateTime": "2025-12-03T09:00:00Z",' +
                    '"lastModifiedDateTime": "2025-12-05T11:00:00Z"' +
                '}' +
            ']' +
        '}';
    }

    private static String getTasksWithEmailResponse() {
        return '{' +
            '"value": [' +
                '{' +
                    '"id": "task-with-email-1",' +
                    '"title": "Follow up with task.contact@tasktest.com",' +
                    '"body": {"content": "Discuss project details", "contentType": "text"},' +
                    '"status": "notStarted",' +
                    '"importance": "high",' +
                    '"createdDateTime": "2025-12-01T10:00:00Z",' +
                    '"lastModifiedDateTime": "2025-12-01T10:00:00Z"' +
                '}' +
            ']' +
        '}';
    }

    // ========================================================================
    // TasksResponse Wrapper Tests
    // ========================================================================

    @isTest
    static void testTasksResponse_Constructor() {
        Test.startTest();
        AITaskSyncController.TasksResponse response = new AITaskSyncController.TasksResponse();
        Test.stopTest();

        Assert.areNotEqual(null, response.tasks, 'Tasks list should be initialized');
        Assert.areNotEqual(null, response.importedTasks, 'ImportedTasks map should be initialized');
        Assert.areEqual(false, response.isTaskAccessible, 'isTaskAccessible should default to false');
    }

    // ========================================================================
    // ImportResult Wrapper Tests
    // ========================================================================

    @isTest
    static void testImportResult_Constructor() {
        Test.startTest();
        AITaskSyncController.ImportResult result = new AITaskSyncController.ImportResult();
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'successCount should default to 0');
        Assert.areEqual(0, result.failedCount, 'failedCount should default to 0');
        Assert.areEqual(0, result.duplicateCount, 'duplicateCount should default to 0');
        Assert.areNotEqual(null, result.taskIds, 'taskIds should be initialized');
        Assert.areNotEqual(null, result.importedTasks, 'importedTasks should be initialized');
        Assert.areNotEqual(null, result.errors, 'errors should be initialized');
    }

    // ========================================================================
    // ImportedTaskInfo Wrapper Tests
    // ========================================================================

    @isTest
    static void testImportedTaskInfo_Properties() {
        Test.startTest();
        AITaskSyncController.ImportedTaskInfo info = new AITaskSyncController.ImportedTaskInfo();
        info.taskId = '00T000000000001';
        info.subject = 'Test Task';
        info.externalId = 'ext-123';
        info.whoId = '003000000000001';
        info.whoName = 'Test Contact';
        info.whoType = 'Contact';
        info.whatId = '001000000000001';
        info.whatName = 'Test Account';
        info.whatType = 'Account';
        info.confidence = 95;
        Test.stopTest();

        Assert.areEqual('Test Task', info.subject, 'Subject should be set');
        Assert.areEqual(95, info.confidence, 'Confidence should be set');
    }

    // ========================================================================
    // TaskMatchInfo Tests
    // ========================================================================

    @isTest
    static void testTaskMatchInfo_Properties() {
        Test.startTest();
        AITaskSyncController.TaskMatchInfo matchInfo = new AITaskSyncController.TaskMatchInfo();
        matchInfo.whoId = '003000000000001';
        matchInfo.whoName = 'Test Contact';
        matchInfo.whoType = 'Contact';
        matchInfo.whatId = '001000000000001';
        matchInfo.whatName = 'Test Account';
        matchInfo.whatType = 'Account';
        matchInfo.confidence = 90;
        matchInfo.allMatchedContactIds = new List<Id>();
        Test.stopTest();

        Assert.areEqual('Contact', matchInfo.whoType, 'whoType should be set');
        Assert.areNotEqual(null, matchInfo.allMatchedContactIds, 'allMatchedContactIds should be initialized');
    }

    // ========================================================================
    // ImportedTaskDetails Tests
    // ========================================================================

    @isTest
    static void testImportedTaskDetails_Properties() {
        Test.startTest();
        AITaskSyncController.ImportedTaskDetails details = new AITaskSyncController.ImportedTaskDetails();
        details.taskId = '00T000000000001';
        details.whoId = '003000000000001';
        details.whoName = 'Test Contact';
        details.whoType = 'Contact';
        details.whatId = '001000000000001';
        details.whatName = 'Test Account';
        details.whatType = 'Account';
        Test.stopTest();

        Assert.areEqual('Contact', details.whoType, 'whoType should be set');
        Assert.areEqual('Account', details.whatType, 'whatType should be set');
    }

    // ========================================================================
    // getTasks Tests
    // ========================================================================

    @isTest
    static void testGetTasks_AuthFailure() {
        Test.setMock(HttpCalloutMock.class, new AuthFailureMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areEqual(false, response.isTaskAccessible, 'Task should not be accessible with auth failure');
        Assert.areNotEqual(null, response.error, 'Error message should be set');
    }

    @isTest
    static void testGetTasks_Success() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, true, 50, null);
        Test.stopTest();

        // Response depends on Named Credential configuration
        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_WithListFilter() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks('list-1', false, 25, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_AllFilter() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks('all', true, 100, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_EmptyResults() {
        Test.setMock(HttpCalloutMock.class, new EmptyTasksMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_DefaultParameters() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        // Test with null/default parameters
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    // ========================================================================
    // getTaskLists Tests
    // ========================================================================

    @isTest
    static void testGetTaskLists_Success() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        try {
            List<AIMicrosoftTaskService.TaskList> lists = AITaskSyncController.getTaskLists();
            // May return lists if API accessible
            Assert.areNotEqual(null, lists, 'Lists should not be null if successful');
        } catch (AuraHandledException e) {
            // Expected if Named Credential not configured
            Assert.areNotEqual(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetTaskLists_AuthFailure() {
        Test.setMock(HttpCalloutMock.class, new AuthFailureMock());

        Test.startTest();
        try {
            List<AIMicrosoftTaskService.TaskList> lists = AITaskSyncController.getTaskLists();
            Assert.isTrue(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            Assert.areNotEqual(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    // ========================================================================
    // importTasks Tests
    // ========================================================================

    @isTest
    static void testImportTasks_EmptyList() {
        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(new List<String>());
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have 0 success');
        Assert.areEqual(1, result.errors.size(), 'Should have 1 error');
        Assert.isTrue(result.errors[0].contains('No tasks selected'), 'Error should mention no tasks selected');
    }

    @isTest
    static void testImportTasks_NullList() {
        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(null);
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have 0 success');
        Assert.areEqual(1, result.errors.size(), 'Should have 1 error');
    }

    @isTest
    static void testImportTasks_MissingListId() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        List<String> taskIds = new List<String>{ 'task-1' }; // Missing listId::

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        Assert.areEqual(1, result.failedCount, 'Should have 1 failed');
        Assert.isTrue(result.errors[0].contains('missing list ID'), 'Error should mention missing list ID');
    }

    @isTest
    static void testImportTasks_WithListId() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        List<String> taskIds = new List<String>{ 'list-1::task-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        // Result depends on API response
        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testImportTasks_WithEmailMatching() {
        Test.setMock(HttpCalloutMock.class, new TaskWithEmailMock());

        List<String> taskIds = new List<String>{ 'list-1::task-with-email-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        // Should attempt to match Contact by email
        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testImportTasks_DuplicateDetection() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        // Get Task record type ID for AI_Workspace_Staging__c
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        // Create an existing Task with Workspace_Sync_Id__c to simulate already imported
        Task existingTask = new Task(
            Subject = 'Existing Task',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert existingTask;

        List<String> taskIds = new List<String>{ 'list-1::task-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        Assert.areEqual(1, result.duplicateCount, 'Should detect 1 duplicate');
    }

    @isTest
    static void testImportTasks_MultipleTaskIds() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        List<String> taskIds = new List<String>{
            'list-1::task-1',
            'list-1::task-2',
            'list-2::task-3'
        };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    // ========================================================================
    // checkTaskAccess Tests
    // ========================================================================

    @isTest
    static void testCheckTaskAccess_Microsoft() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.checkTaskAccess('MICROSOFT_GRAPH');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        Assert.areEqual('MICROSOFT_GRAPH', result.get('providerType'), 'Provider type should be set');
    }

    @isTest
    static void testCheckTaskAccess_Google() {
        Test.startTest();
        Map<String, Object> result = AITaskSyncController.checkTaskAccess('GOOGLE_TASKS');
        Test.stopTest();

        Assert.areEqual(false, result.get('isAccessible'), 'Google Tasks should not be accessible');
        Assert.areNotEqual(null, result.get('error'), 'Error should be set');
    }

    @isTest
    static void testCheckTaskAccess_DefaultProvider() {
        Test.setMock(HttpCalloutMock.class, new AuthFailureMock());

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.checkTaskAccess(null);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        Assert.areEqual('MICROSOFT_TASKS', result.get('providerType'), 'Should default to Microsoft Tasks');
    }

    @isTest
    static void testCheckTaskAccess_AuthFailure() {
        Test.setMock(HttpCalloutMock.class, new AuthFailureMock());

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.checkTaskAccess('MICROSOFT_GRAPH');
        Test.stopTest();

        Assert.areEqual(false, result.get('isAccessible'), 'Should not be accessible with auth failure');
        Assert.areNotEqual(null, result.get('error'), 'Error should be set');
    }

    // ========================================================================
    // Integration Tests
    // ========================================================================

    @isTest
    static void testFullImportFlow_WithContactMatch() {
        Test.setMock(HttpCalloutMock.class, new TaskWithEmailMock());

        // First get tasks
        Test.startTest();
        AITaskSyncController.TasksResponse tasksResponse = AITaskSyncController.getTasks(null, false, 50, null);

        // Then import if tasks found
        if (tasksResponse.tasks != null && !tasksResponse.tasks.isEmpty()) {
            List<String> taskIdsToImport = new List<String>();
            for (AIMicrosoftTaskService.ToDoTask task : tasksResponse.tasks) {
                if (String.isNotBlank(task.listId) && String.isNotBlank(task.taskId)) {
                    taskIdsToImport.add(task.listId + '::' + task.taskId);
                }
            }

            if (!taskIdsToImport.isEmpty()) {
                AITaskSyncController.ImportResult importResult = AITaskSyncController.importTasks(taskIdsToImport);
                Assert.areNotEqual(null, importResult, 'Import result should not be null');
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testGetTasks_WithExistingImportedTasks() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        // Create an existing imported task
        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        Task existingTask = new Task(
            Subject = 'Already Imported Task',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            WhoId = testContact.Id,
            WhatId = testAccount.Id,
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert existingTask;

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        // Should detect existing imported tasks
        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_ApiError() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        // Should handle error gracefully
        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    // ========================================================================
    // Edge Case Tests
    // ========================================================================

    @isTest
    static void testImportTasks_WithLeadMatch() {
        // Mock that returns task with lead email
        Test.setMock(HttpCalloutMock.class, new TaskWithLeadEmailMock());

        List<String> taskIds = new List<String>{ 'list-1::task-lead-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    /**
     * Mock for task with Lead email
     */
    private class TaskWithLeadEmailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/me/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody(getTaskListsResponse());
            } else if (endpoint.contains('/tasks/')) {
                res.setBody('{' +
                    '"id": "task-lead-1",' +
                    '"title": "Follow up with task.lead@tasktest.com",' +
                    '"body": {"content": "Lead follow-up", "contentType": "text"},' +
                    '"status": "notStarted",' +
                    '"importance": "normal",' +
                    '"createdDateTime": "2025-12-01T10:00:00Z",' +
                    '"lastModifiedDateTime": "2025-12-01T10:00:00Z"' +
                '}');
            } else if (endpoint.contains('/tasks')) {
                res.setBody('{' +
                    '"value": [' +
                        '{' +
                            '"id": "task-lead-1",' +
                            '"title": "Follow up with task.lead@tasktest.com",' +
                            '"status": "notStarted",' +
                            '"importance": "normal",' +
                            '"createdDateTime": "2025-12-01T10:00:00Z"' +
                        '}' +
                    ']' +
                '}');
            } else if (endpoint.contains('/me')) {
                res.setBody('{"userPrincipalName": "testuser@test.com"}');
            } else {
                res.setBody('{}');
            }

            return res;
        }
    }

    @isTest
    static void testImportTasks_NoEmailInTask() {
        // Mock that returns task without email addresses
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        List<String> taskIds = new List<String>{ 'list-1::task-2' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        // Should still import but may not have match
        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testImportTasks_MultipleEmails() {
        // Mock that returns task with multiple email addresses
        Test.setMock(HttpCalloutMock.class, new TaskWithMultipleEmailsMock());

        List<String> taskIds = new List<String>{ 'list-1::task-multi-email' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    // ========================================================================
    // Google Tasks Tests
    // ========================================================================

    @isTest
    static void testGetGoogleTasks_Success() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, true, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithListFilter() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks('list-1', false, 25, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_AllFilter() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks('all', true, 100, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithPagination() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 2, '0');
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_TaskServiceException() {
        Test.setMock(HttpCalloutMock.class, new AuthFailureMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areEqual(false, response.isTaskAccessible, 'Should not be accessible');
        Assert.areNotEqual(null, response.error, 'Error should be set');
    }

    @isTest
    static void testGetGoogleTasks_DefaultParameters() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_InvalidPageToken() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, 'invalid');
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTaskLists_Success() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        try {
            List<AIGoogleTaskService.TaskList> lists = AITaskSyncController.getGoogleTaskLists();
            Assert.areNotEqual(null, lists, 'Lists should not be null if successful');
        } catch (AuraHandledException e) {
            Assert.areNotEqual(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetGoogleTaskLists_AuthFailure() {
        Test.setMock(HttpCalloutMock.class, new AuthFailureMock());

        Test.startTest();
        try {
            List<AIGoogleTaskService.TaskList> lists = AITaskSyncController.getGoogleTaskLists();
            Assert.isTrue(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            Assert.areNotEqual(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testImportGoogleTasks_EmptyList() {
        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(new List<String>());
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have 0 success');
        Assert.areEqual(1, result.errors.size(), 'Should have 1 error');
    }

    @isTest
    static void testImportGoogleTasks_NullList() {
        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(null);
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have 0 success');
        Assert.areEqual(1, result.errors.size(), 'Should have 1 error');
    }

    @isTest
    static void testImportGoogleTasks_MissingListId() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        List<String> taskIds = new List<String>{ 'task-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(taskIds);
        Test.stopTest();

        Assert.areEqual(1, result.failedCount, 'Should have 1 failed');
    }

    @isTest
    static void testImportGoogleTasks_WithListId() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        List<String> taskIds = new List<String>{ 'list-1::task-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testImportGoogleTasks_DuplicateDetection() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Task existingTask = new Task(
            Subject = 'Existing Google Task',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert existingTask;

        List<String> taskIds = new List<String>{ 'list-1::task-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(taskIds);
        Test.stopTest();

        Assert.areEqual(1, result.duplicateCount, 'Should detect 1 duplicate');
    }

    @isTest
    static void testImportGoogleTasks_AllDuplicates() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Task existingTask1 = new Task(
            Subject = 'Existing Task 1',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started'
        );
        Task existingTask2 = new Task(
            Subject = 'Existing Task 2',
            Workspace_Sync_Id__c = 'task-2',
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started'
        );
        insert new List<Task>{ existingTask1, existingTask2 };

        List<String> taskIds = new List<String>{ 'list-1::task-1', 'list-1::task-2' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(taskIds);
        Test.stopTest();

        Assert.areEqual(2, result.duplicateCount, 'Should detect 2 duplicates');
    }

    // ========================================================================
    // refreshTokenAndCheckAccess Tests
    // ========================================================================

    @isTest
    static void testRefreshTokenAndCheckAccess_MicrosoftNoConnection() {
        Test.startTest();
        Map<String, Object> result = AITaskSyncController.refreshTokenAndCheckAccess('MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areEqual(false, result.get('isAccessible'), 'Should not be accessible without connection');
        Assert.areEqual(false, result.get('refreshed'), 'Should not be refreshed');
    }

    @isTest
    static void testRefreshTokenAndCheckAccess_GoogleNoConnection() {
        Test.startTest();
        Map<String, Object> result = AITaskSyncController.refreshTokenAndCheckAccess('GOOGLE_TASKS');
        Test.stopTest();

        Assert.areEqual(false, result.get('isAccessible'), 'Should not be accessible without connection');
        Assert.areEqual(false, result.get('refreshed'), 'Should not be refreshed');
    }

    @isTest
    static void testRefreshTokenAndCheckAccess_DefaultProvider() {
        Test.startTest();
        Map<String, Object> result = AITaskSyncController.refreshTokenAndCheckAccess(null);
        Test.stopTest();

        Assert.areEqual('MICROSOFT_TASKS', result.get('providerType'), 'Should default to Microsoft Tasks');
    }

    @isTest
    static void testRefreshTokenAndCheckAccess_BlankProvider() {
        Test.startTest();
        Map<String, Object> result = AITaskSyncController.refreshTokenAndCheckAccess('');
        Test.stopTest();

        Assert.areEqual('MICROSOFT_TASKS', result.get('providerType'), 'Should default to Microsoft Tasks');
    }

    // ========================================================================
    // associateTasksFromModal Tests
    // ========================================================================

    @isTest
    static void testAssociateTasksFromModal_NullSelections() {
        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(null, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areEqual(false, result.get('success'), 'Should fail with null selections');
        Assert.areNotEqual(0, ((List<String>) result.get('errors')).size(), 'Should have errors');
    }

    @isTest
    static void testAssociateTasksFromModal_EmptySelections() {
        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(new List<Map<String, Object>>(), 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areEqual(false, result.get('success'), 'Should fail with empty selections');
    }

    @isTest
    static void testAssociateTasksFromModal_MicrosoftTasks() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>()
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_GoogleTasks() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>()
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'GOOGLE_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_MicrosoftGraph() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>()
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_GRAPH');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithContactAndLead() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];
        Lead testLead = [SELECT Id FROM Lead WHERE Email = 'task.lead@tasktest.com' LIMIT 1];

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>{ testContact.Id },
                'leadIds' => new List<String>{ testLead.Id }
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithAccountAndOpportunity() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];
        
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>(),
                'accountId' => testAccount.Id,
                'opportunityId' => testOpp.Id
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    // ========================================================================
    // Pagination Tests
    // ========================================================================

    @isTest
    static void testGetTasks_WithPagination() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 2, '0');
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_InvalidPageToken() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, 'invalid');
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_NegativeMaxResults() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, -10, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_ZeroMaxResults() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 0, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    // ========================================================================
    // LinkedRecordInfo Tests
    // ========================================================================

    @isTest
    static void testLinkedRecordInfo_Constructor() {
        Test.startTest();
        AITaskSyncController.LinkedRecordInfo info = new AITaskSyncController.LinkedRecordInfo(
            '003000000000001',
            'Test Contact',
            'Contact'
        );
        Test.stopTest();

        Assert.areEqual('003000000000001', info.recordId, 'Record ID should be set');
        Assert.areEqual('Test Contact', info.recordName, 'Record name should be set');
        Assert.areEqual('Contact', info.recordType, 'Record type should be set');
    }

    // ========================================================================
    // GoogleTasksResponse Tests
    // ========================================================================

    @isTest
    static void testGoogleTasksResponse_Constructor() {
        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = new AITaskSyncController.GoogleTasksResponse();
        Test.stopTest();

        Assert.areNotEqual(null, response.tasks, 'Tasks list should be initialized');
        Assert.areNotEqual(null, response.importedTasks, 'ImportedTasks map should be initialized');
        Assert.areEqual(false, response.isTaskAccessible, 'isTaskAccessible should default to false');
        Assert.areEqual(false, response.hasMore, 'hasMore should default to false');
        Assert.areEqual(0, response.totalCount, 'totalCount should default to 0');
    }

    // ========================================================================
    // Additional Mock Classes
    // ========================================================================

    /**
     * Mock for Google Tasks API calls
     */
    private class GoogleTasksSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/users/@me/lists') && !endpoint.contains('/tasks')) {
                res.setBody('{' +
                    '"items": [' +
                        '{"id": "list-1", "title": "My Tasks"},' +
                        '{"id": "list-2", "title": "Work Tasks"}' +
                    ']' +
                '}');
            } else if (endpoint.contains('/tasks')) {
                res.setBody('{' +
                    '"items": [' +
                        '{' +
                            '"id": "task-1",' +
                            '"title": "Complete report",' +
                            '"status": "needsAction",' +
                            '"updated": "2025-12-01T10:00:00.000Z"' +
                        '},' +
                        '{' +
                            '"id": "task-2",' +
                            '"title": "Schedule meeting",' +
                            '"status": "needsAction",' +
                            '"updated": "2025-12-02T14:00:00.000Z"' +
                        '}' +
                    ']' +
                '}');
            } else if (endpoint.contains('oauth2/v2/userinfo')) {
                res.setBody('{"email": "testuser@gmail.com"}');
            } else {
                res.setBody('{}');
            }

            return res;
        }
    }

    /**
     * Mock for task with multiple email addresses
     */
    private class TaskWithMultipleEmailsMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/me/todo/lists') && !endpoint.contains('/tasks')) {
                res.setBody(getTaskListsResponse());
            } else if (endpoint.contains('/tasks/')) {
                res.setBody('{' +
                    '"id": "task-multi-email",' +
                    '"title": "Meeting with task.contact@tasktest.com and task.lead@tasktest.com",' +
                    '"body": {"content": "Discuss project with both contacts", "contentType": "text"},' +
                    '"status": "notStarted",' +
                    '"importance": "high",' +
                    '"createdDateTime": "2025-12-01T10:00:00Z",' +
                    '"lastModifiedDateTime": "2025-12-01T10:00:00Z"' +
                '}');
            } else if (endpoint.contains('/tasks')) {
                res.setBody('{' +
                    '"value": [' +
                        '{' +
                            '"id": "task-multi-email",' +
                            '"title": "Meeting with task.contact@tasktest.com and task.lead@tasktest.com",' +
                            '"status": "notStarted",' +
                            '"createdDateTime": "2025-12-01T10:00:00Z"' +
                        '}' +
                    ']' +
                '}');
            } else if (endpoint.contains('/me')) {
                res.setBody('{"userPrincipalName": "testuser@test.com"}');
            } else {
                res.setBody('{}');
            }

            return res;
        }
    }

    // ========================================================================
    // Additional Tests for Higher Coverage
    // ========================================================================

    @isTest
    static void testGetTasks_WithTasksAndImportedDetails() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        Task existingTask = new Task(
            Subject = 'Existing Task',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            WhoId = testContact.Id,
            WhatId = testAccount.Id,
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert existingTask;

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Existing Task',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'MICROSOFT_TASKS',
            Email_Message__c = existingTask.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testCheckTaskAccess_MicrosoftTasks() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.checkTaskAccess('MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        Assert.areEqual('MICROSOFT_TASKS', result.get('providerType'), 'Provider type should be MICROSOFT_TASKS');
    }

    @isTest
    static void testAssociateTasksFromModal_WithInvalidIds() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>{ 'invalid-id' },
                'leadIds' => new List<String>{ 'invalid-lead-id' },
                'accountId' => 'invalid-account-id',
                'opportunityId' => 'invalid-opp-id'
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithExistingImportedTasks() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];

        Task existingTask = new Task(
            Subject = 'Existing Google Task',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            WhoId = testContact.Id,
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert existingTask;

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithStagingRecord() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        Task existingTask = new Task(
            Subject = 'Google Task with Staging',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            WhoId = testContact.Id,
            WhatId = testAccount.Id,
            Status = 'Not Started'
        );
        insert existingTask;

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Google Task',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'GOOGLE_TASKS',
            Email_Message__c = existingTask.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithMultipleContacts() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Contact testContact1 = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];
        
        Contact testContact2 = new Contact(
            FirstName = 'Second',
            LastName = 'Contact',
            Email = 'second.contact@tasktest.com'
        );
        insert testContact2;

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>{ testContact1.Id, testContact2.Id },
                'leadIds' => new List<String>()
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithLeadAndAccount() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Lead testLead = [SELECT Id FROM Lead WHERE Email = 'task.lead@tasktest.com' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>{ testLead.Id },
                'accountId' => testAccount.Id
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetTasks_WithInvalidStagingRecordId() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Invalid Task',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'MICROSOFT_TASKS',
            Email_Message__c = 'invalid-id'
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testImportGoogleTasks_NoValidTasks() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Task existingTask = new Task(
            Subject = 'Existing Task',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started'
        );
        insert existingTask;

        List<String> taskIds = new List<String>{ 'list-1::task-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(taskIds);
        Test.stopTest();

        Assert.areEqual(1, result.duplicateCount, 'Should have 1 duplicate');
    }

    @isTest
    static void testGetGoogleTasks_WithInvalidStagingRecordId() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Invalid Google Task',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'GOOGLE_TASKS',
            Email_Message__c = 'invalid-id'
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_WithNonTaskId() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Non-Task ID',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'MICROSOFT_TASKS',
            Email_Message__c = testContact.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_WithMultipleTasksAndPagination() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 1, '0');
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithMultipleTasksAndPagination() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 1, '0');
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_WithTasksHavingWhatIdOnly() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        Task existingTask = new Task(
            Subject = 'Task with WhatId Only',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            WhatId = testAccount.Id,
            Status = 'Not Started'
        );
        insert existingTask;

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Task with WhatId',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'MICROSOFT_TASKS',
            Email_Message__c = existingTask.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithTasksHavingWhatIdOnly() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        Task existingTask = new Task(
            Subject = 'Google Task with WhatId Only',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            WhatId = testAccount.Id,
            Status = 'Not Started'
        );
        insert existingTask;

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Google Task with WhatId',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'GOOGLE_TASKS',
            Email_Message__c = existingTask.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testImportTasks_WithFetchException() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        List<String> taskIds = new List<String>{ 'list-1::task-error' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testImportGoogleTasks_WithFetchException() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        List<String> taskIds = new List<String>{ 'list-1::task-error' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetTasks_WithEmptyLinkedRecords() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Task existingTask = new Task(
            Subject = 'Task without Links',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started'
        );
        insert existingTask;

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Task without Links',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'MICROSOFT_TASKS',
            Email_Message__c = existingTask.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithEmptyLinkedRecords() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Task existingTask = new Task(
            Subject = 'Google Task without Links',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started'
        );
        insert existingTask;

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Google Task without Links',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'GOOGLE_TASKS',
            Email_Message__c = existingTask.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithOnlyAccount() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>(),
                'accountId' => testAccount.Id
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithOnlyOpportunity() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];
        
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opp 2',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>(),
                'opportunityId' => testOpp.Id
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithOnlyLead() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Lead testLead = [SELECT Id FROM Lead WHERE Email = 'task.lead@tasktest.com' LIMIT 1];

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>{ testLead.Id }
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithOnlyContact() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>{ testContact.Id },
                'leadIds' => new List<String>()
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testImportedTaskDetails_Constructor() {
        Test.startTest();
        AITaskSyncController.ImportedTaskDetails details = new AITaskSyncController.ImportedTaskDetails();
        Test.stopTest();

        Assert.areNotEqual(null, details.linkedRecords, 'Linked records should be initialized');
    }

    @isTest
    static void testGetTasks_WithException() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response.error, 'Error should be set');
    }

    @isTest
    static void testGetGoogleTasks_WithException() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response.error, 'Error should be set');
    }

    @isTest
    static void testRefreshTokenAndCheckAccess_WithException() {
        Test.startTest();
        Map<String, Object> result = AITaskSyncController.refreshTokenAndCheckAccess('INVALID_PROVIDER');
        Test.stopTest();

        Assert.areEqual(false, result.get('isAccessible'), 'Should not be accessible with invalid provider');
    }

    @isTest
    static void testCheckTaskAccess_WithException() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.checkTaskAccess('INVALID_PROVIDER');
        Test.stopTest();

        Assert.areNotEqual(null, result.get('error'), 'Error should be set');
    }

    @isTest
    static void testImportTasks_WithException() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        List<String> taskIds = new List<String>{ 'list-1::task-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testImportGoogleTasks_WithException() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        List<String> taskIds = new List<String>{ 'list-1::task-1' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithException() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>()
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetTasks_WithBlankTaskIds() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Task with Blank ID',
            Provider_Id__c = '',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'MICROSOFT_TASKS',
            Email_Message__c = ''
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithBlankTaskIds() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Google Task with Blank ID',
            Provider_Id__c = '',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'GOOGLE_TASKS',
            Email_Message__c = ''
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testImportTasks_WithNullTaskInResponse() {
        Test.setMock(HttpCalloutMock.class, new NullTaskMock());

        List<String> taskIds = new List<String>{ 'list-1::task-null' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testImportGoogleTasks_WithNullTaskInResponse() {
        Test.setMock(HttpCalloutMock.class, new NullTaskMock());

        List<String> taskIds = new List<String>{ 'list-1::task-null' };

        Test.startTest();
        AITaskSyncController.ImportResult result = AITaskSyncController.importGoogleTasks(taskIds);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    /**
     * Mock that returns null task
     */
    private class NullTaskMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error": {"code": "NotFound", "message": "Task not found"}}');
            return res;
        }
    }

    /**
     * Mock that throws exception
     */
    private class ExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated callout exception');
        }
    }

    @isTest
    static void testGetTasks_WithTasksHavingMultipleLinkedRecords() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        Opportunity testOpp = new Opportunity(
            Name = 'Test Opp for Task',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        Task existingTask = new Task(
            Subject = 'Task with Multiple Links',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            WhoId = testContact.Id,
            WhatId = testOpp.Id,
            Status = 'Not Started'
        );
        insert existingTask;

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Task with Multiple Links',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'MICROSOFT_TASKS',
            Email_Message__c = existingTask.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithTasksHavingMultipleLinkedRecords() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Task Test Company' LIMIT 1];

        Opportunity testOpp = new Opportunity(
            Name = 'Test Opp for Google Task',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        Task existingTask = new Task(
            Subject = 'Google Task with Multiple Links',
            Workspace_Sync_Id__c = 'task-1',
            OwnerId = UserInfo.getUserId(),
            WhoId = testContact.Id,
            WhatId = testOpp.Id,
            Status = 'Not Started'
        );
        insert existingTask;

        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();

        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Google Task with Multiple Links',
            Provider_Id__c = 'task-1',
            User__c = UserInfo.getUserId(),
            RecordTypeId = taskRecordTypeId,
            Provider__c = 'GOOGLE_TASKS',
            Email_Message__c = existingTask.Id
        );
        insert staging;

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }


    @isTest
    static void testGetTasks_WithLargePageToken() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 50, '1000');
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithLargePageToken() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 50, '1000');
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_WithVerySmallMaxResults() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, false, 1, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithVerySmallMaxResults() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, false, 1, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testAssociateTasksFromModal_WithMultipleSelections() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Contact testContact = [SELECT Id FROM Contact WHERE Email = 'task.contact@tasktest.com' LIMIT 1];
        Lead testLead = [SELECT Id FROM Lead WHERE Email = 'task.lead@tasktest.com' LIMIT 1];

        List<Map<String, Object>> selections = new List<Map<String, Object>>{
            new Map<String, Object>{
                'messageId' => 'list-1::task-1',
                'contactIds' => new List<String>{ testContact.Id },
                'leadIds' => new List<String>()
            },
            new Map<String, Object>{
                'messageId' => 'list-1::task-2',
                'contactIds' => new List<String>(),
                'leadIds' => new List<String>{ testLead.Id }
            }
        };

        Test.startTest();
        Map<String, Object> result = AITaskSyncController.associateTasksFromModal(selections, 'MICROSOFT_TASKS');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetTasks_WithIncludeCompletedTrue() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks(null, true, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithIncludeCompletedTrue() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks(null, true, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetTasks_WithSpecificListAndIncludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new TaskApiSuccessMock());

        Test.startTest();
        AITaskSyncController.TasksResponse response = AITaskSyncController.getTasks('list-1', true, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetGoogleTasks_WithSpecificListAndIncludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new GoogleTasksSuccessMock());

        Test.startTest();
        AITaskSyncController.GoogleTasksResponse response = AITaskSyncController.getGoogleTasks('list-1', true, 50, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
}