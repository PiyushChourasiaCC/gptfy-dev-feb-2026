/**
 * Test class for AIGoogleTaskService
 * Tests Google Tasks API integration
 */
@isTest
public class AIGoogleTaskServiceTest {

    /**
     * Helper method to setup workspace user with Gmail/Google token
     */
    private static void setupWorkspaceUser() {
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Access_Token__c = 'test_access_token_12345',
            Refresh_Token__c = 'test_refresh_token_12345',
            Provider__c = 'GMAIL'
        );
        insert workspaceUser;
    }

    /**
     * Test getTaskLists success
     */
    @isTest
    static void testGetTaskLists_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTaskListsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.TaskList> taskLists = AIGoogleTaskService.getTaskLists();
        Test.stopTest();
        
        Assert.isTrue(taskLists.size() > 0, 'Should return task lists');
        Assert.areEqual('list_1', taskLists[0].listId, 'Should have correct list ID');
        Assert.areEqual('My Tasks', taskLists[0].displayName, 'Should have correct display name');
    }

    /**
     * Test getTaskLists with 401 error
     */
    @isTest
    static void testGetTaskLists_AuthenticationError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIGoogleTaskService.TaskList> taskLists = AIGoogleTaskService.getTaskLists();
            Assert.fail('Should throw TaskServiceException');
        } catch (AIGoogleTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Authentication expired'), 
                'Should throw authentication error');
        }
        Test.stopTest();
    }

    /**
     * Test getTaskLists with 403 error
     */
    @isTest
    static void testGetTaskLists_ForbiddenError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(403));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIGoogleTaskService.TaskList> taskLists = AIGoogleTaskService.getTaskLists();
            Assert.fail('Should throw TaskServiceException');
        } catch (AIGoogleTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Google Tasks access not granted'), 
                'Should throw forbidden error');
        }
        Test.stopTest();
    }

    /**
     * Test getTaskLists with generic error
     */
    @isTest
    static void testGetTaskLists_GenericError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(500));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIGoogleTaskService.TaskList> taskLists = AIGoogleTaskService.getTaskLists();
            Assert.fail('Should throw TaskServiceException');
        } catch (AIGoogleTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch task lists'), 
                'Should throw generic error');
        }
        Test.stopTest();
    }


    /**
     * Test getAllTasks success
     */
    @isTest
    static void testGetAllTasks_Success() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = AIGoogleTaskService.getAllTasks(50, false);
        Test.stopTest();
        
        Assert.isTrue(tasks.size() > 0, 'Should return tasks');
        Assert.areEqual('task_1', tasks[0].taskId, 'Should have correct task ID');
    }

    /**
     * Test getAllTasks with null maxResults
     */
    @isTest
    static void testGetAllTasks_NullMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = AIGoogleTaskService.getAllTasks(null, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks with default max results');
    }

    /**
     * Test getAllTasks with zero maxResults
     */
    @isTest
    static void testGetAllTasks_ZeroMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = AIGoogleTaskService.getAllTasks(0, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks with default max results');
    }

    /**
     * Test getAllTasks with includeCompleted
     */
    @isTest
    static void testGetAllTasks_IncludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = AIGoogleTaskService.getAllTasks(50, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks including completed');
    }

    /**
     * Test getAllTasks with empty task lists
     */
    @isTest
    static void testGetAllTasks_EmptyTaskLists() {
        Test.setMock(HttpCalloutMock.class, new MockEmptyTaskListsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = AIGoogleTaskService.getAllTasks(50, false);
        Test.stopTest();
        
        Assert.areEqual(0, tasks.size(), 'Should return empty list when no task lists');
    }

    /**
     * Test getAllTasks with task list error
     */
    @isTest
    static void testGetAllTasks_TaskListError() {
        Test.setMock(HttpCalloutMock.class, new MockTaskListErrorResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = AIGoogleTaskService.getAllTasks(50, false);
        Test.stopTest();
        
        // Should continue with other lists
        Assert.isNotNull(tasks, 'Should handle task list errors gracefully');
    }

    /**
     * Test getAllTasks with trimming
     */
    @isTest
    static void testGetAllTasks_Trimming() {
        Test.setMock(HttpCalloutMock.class, new MockLargeTaskListResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = AIGoogleTaskService.getAllTasks(5, false);
        Test.stopTest();
        
        Assert.areEqual(5, tasks.size(), 'Should trim to max results');
    }

    /**
     * Test getTasksFromList success
     */
    @isTest
    static void testGetTasksFromList_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromList('list_1', 'My Tasks', 50, false);
        Test.stopTest();
        
        Assert.isTrue(tasks.size() > 0, 'Should return tasks');
        Assert.areEqual('list_1', tasks[0].listId, 'Should have correct list ID');
    }

    /**
     * Test getTasksFromList with blank listId
     */
    @isTest
    static void testGetTasksFromList_BlankListId() {
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromList('', 'My Tasks', 50, false);
        Test.stopTest();
        
        Assert.areEqual(0, tasks.size(), 'Should return empty list for blank list ID');
    }

    /**
     * Test getTasksFromList with null maxResults
     */
    @isTest
    static void testGetTasksFromList_NullMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromList('list_1', 'My Tasks', null, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle null max results');
    }

    /**
     * Test getTasksFromList with includeCompleted true
     */
    @isTest
    static void testGetTasksFromList_IncludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromList('list_1', 'My Tasks', 50, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks including completed');
    }

    /**
     * Test getTasksFromList with includeCompleted false
     */
    @isTest
    static void testGetTasksFromList_ExcludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromList('list_1', 'My Tasks', 50, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks excluding completed');
    }

    /**
     * Test getTasksFromList with 401 error
     */
    @isTest
    static void testGetTasksFromList_AuthError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIGoogleTaskService.ToDoTask> tasks = 
                AIGoogleTaskService.getTasksFromList('list_1', 'My Tasks', 50, false);
            Assert.fail('Should throw TaskServiceException');
        } catch (AIGoogleTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Authentication expired'), 
                'Should throw auth error');
        }
        Test.stopTest();
    }

    /**
     * Test getTasksFromList with generic error
     */
    @isTest
    static void testGetTasksFromList_GenericError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(500));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIGoogleTaskService.ToDoTask> tasks = 
                AIGoogleTaskService.getTasksFromList('list_1', 'My Tasks', 50, false);
            Assert.fail('Should throw TaskServiceException');
        } catch (AIGoogleTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch tasks'), 
                'Should throw generic error');
        }
        Test.stopTest();
    }

    /**
     * Test getAllTasksWithOffset success
     */
    @isTest
    static void testGetAllTasksWithOffset_Success() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getAllTasksWithOffset(10, 0, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks');
    }

    /**
     * Test getAllTasksWithOffset with offset
     */
    @isTest
    static void testGetAllTasksWithOffset_WithOffset() {
        Test.setMock(HttpCalloutMock.class, new MockLargeTaskListResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getAllTasksWithOffset(5, 2, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks with offset');
    }

    /**
     * Test getAllTasksWithOffset with null parameters
     */
    @isTest
    static void testGetAllTasksWithOffset_NullParameters() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getAllTasksWithOffset(null, null, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle null parameters');
    }

    /**
     * Test getAllTasksWithOffset with negative offset
     */
    @isTest
    static void testGetAllTasksWithOffset_NegativeOffset() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getAllTasksWithOffset(10, -5, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle negative offset');
    }

    /**
     * Test getAllTasksWithOffset with empty task lists
     */
    @isTest
    static void testGetAllTasksWithOffset_EmptyTaskLists() {
        Test.setMock(HttpCalloutMock.class, new MockEmptyTaskListsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getAllTasksWithOffset(10, 0, false);
        Test.stopTest();
        
        Assert.areEqual(0, tasks.size(), 'Should return empty list');
    }

    /**
     * Test getTasksFromListWithOffset success
     */
    @isTest
    static void testGetTasksFromListWithOffset_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', 10, 0, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks');
    }

    /**
     * Test getTasksFromListWithOffset with blank listId
     */
    @isTest
    static void testGetTasksFromListWithOffset_BlankListId() {
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromListWithOffset('', 'My Tasks', 10, 0, false);
        Test.stopTest();
        
        Assert.areEqual(0, tasks.size(), 'Should return empty list for blank list ID');
    }

    /**
     * Test getTasksFromListWithOffset with null parameters
     */
    @isTest
    static void testGetTasksFromListWithOffset_NullParameters() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', null, null, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle null parameters');
    }

    /**
     * Test getTasksFromListWithOffset with offset
     */
    @isTest
    static void testGetTasksFromListWithOffset_WithOffset() {
        Test.setMock(HttpCalloutMock.class, new MockLargeTaskListResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', 3, 2, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks with offset');
    }

    /**
     * Test getTasksFromListWithOffset with includeCompleted
     */
    @isTest
    static void testGetTasksFromListWithOffset_IncludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', 10, 0, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks including completed');
    }

    /**
     * Test getTasksFromListWithOffset with 401 error
     */
    @isTest
    static void testGetTasksFromListWithOffset_AuthError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIGoogleTaskService.ToDoTask> tasks = 
                AIGoogleTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', 10, 0, false);
            Assert.fail('Should throw TaskServiceException');
        } catch (AIGoogleTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Authentication expired'), 
                'Should throw auth error');
        }
        Test.stopTest();
    }

    /**
     * Test getTask success
     */
    @isTest
    static void testGetTask_Success() {
        Test.setMock(HttpCalloutMock.class, new MockSingleTaskResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
        Test.stopTest();
        
        Assert.isNotNull(task, 'Should return task');
        Assert.areEqual('task_123', task.taskId, 'Should have correct task ID');
        Assert.areEqual('Test Task', task.title, 'Should have correct title');
    }

    /**
     * Test getTask with 404 error
     */
    @isTest
    static void testGetTask_NotFound() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(404));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'invalid_id');
            Assert.fail('Should throw TaskServiceException');
        } catch (AIGoogleTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Task not found'), 
                'Should throw not found error');
        }
        Test.stopTest();
    }

    /**
     * Test getTask with generic error
     */
    @isTest
    static void testGetTask_GenericError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(500));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
            Assert.fail('Should throw TaskServiceException');
        } catch (AIGoogleTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch task'), 
                'Should throw generic error');
        }
        Test.stopTest();
    }


    /**
     * Test isTaskAccessible success
     */
    @isTest
    static void testIsTaskAccessible_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTaskAccessibleResponse(200));
        setupWorkspaceUser();
        
        Test.startTest();
        Boolean isAccessible = AIGoogleTaskService.isTaskAccessible();
        Test.stopTest();
        
        Assert.areEqual(true, isAccessible, 'Should return true for accessible tasks');
    }

    /**
     * Test isTaskAccessible failure
     */
    @isTest
    static void testIsTaskAccessible_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockTaskAccessibleResponse(401));
        setupWorkspaceUser();
        
        Test.startTest();
        Boolean isAccessible = AIGoogleTaskService.isTaskAccessible();
        Test.stopTest();
        
        Assert.areEqual(false, isAccessible, 'Should return false for inaccessible tasks');
    }


    /**
     * Test parsing task with completed status
     */
    @isTest
    static void testParseTask_CompletedStatus() {
        Test.setMock(HttpCalloutMock.class, new MockCompletedTaskResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
        Test.stopTest();
        
        Assert.areEqual('completed', task.status, 'Should map completed status');
        Assert.isNotNull(task.completedDateTime, 'Should have completed datetime');
    }

    /**
     * Test parsing task with needsAction status
     */
    @isTest
    static void testParseTask_NeedsActionStatus() {
        Test.setMock(HttpCalloutMock.class, new MockNeedsActionTaskResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
        Test.stopTest();
        
        Assert.areEqual('notStarted', task.status, 'Should map needsAction to notStarted');
    }

    /**
     * Test parsing task with parent task
     */
    @isTest
    static void testParseTask_WithParent() {
        Test.setMock(HttpCalloutMock.class, new MockSubtaskResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
        Test.stopTest();
        
        Assert.isNotNull(task.parentTaskId, 'Should have parent task ID');
    }

    /**
     * Test parsing task with due date
     */
    @isTest
    static void testParseTask_WithDueDate() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithDueDateResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
        Test.stopTest();
        
        Assert.isNotNull(task.dueDateTime, 'Should have due datetime');
    }

    /**
     * Test parsing datetime with fractional seconds
     */
    @isTest
    static void testParseDateTime_WithFractionalSeconds() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithFractionalSecondsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
        Test.stopTest();
        
        Assert.isNotNull(task.dueDateTime, 'Should parse datetime with fractional seconds');
    }

    /**
     * Test parsing datetime without Z suffix
     */
    @isTest
    static void testParseDateTime_WithoutZ() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithDateTimeNoZResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
        Test.stopTest();
        
        Assert.isNotNull(task.dueDateTime, 'Should parse datetime without Z');
    }

    /**
     * Test parsing null task data
     */
    @isTest
    static void testParseTask_NullData() {
        Test.setMock(HttpCalloutMock.class, new MockNullTaskResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIGoogleTaskService.ToDoTask> tasks = 
            AIGoogleTaskService.getTasksFromList('list_1', 'My Tasks', 50, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle null task data');
    }

    /**
     * Test parsing invalid datetime
     */
    @isTest
    static void testParseDateTime_Invalid() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithInvalidDateResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = AIGoogleTaskService.getTask('list_1', 'task_123');
        Test.stopTest();
        
        Assert.isNotNull(task, 'Should handle invalid datetime gracefully');
    }

    /**
     * Test ToDoTask constructor
     */
    @isTest
    static void testToDoTaskConstructor() {
        Test.startTest();
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        Test.stopTest();
        
        Assert.areEqual('GOOGLE_TASKS', task.provider, 'Should set provider');
        Assert.areEqual(false, task.isImported, 'Should set isImported to false');
        Assert.areEqual('normal', task.importance, 'Should set importance to normal');
        Assert.isNotNull(task.linkedRecords, 'Should initialize linkedRecords');
    }

    /**
     * Test LinkedRecord constructor
     */
    @isTest
    static void testLinkedRecordConstructor() {
        Test.startTest();
        AIGoogleTaskService.LinkedRecord linkedRecord = 
            new AIGoogleTaskService.LinkedRecord('001000000000001', 'Test Account', 'Account');
        Test.stopTest();
        
        Assert.areEqual('001000000000001', linkedRecord.recordId, 'Should set record ID');
        Assert.areEqual('Test Account', linkedRecord.recordName, 'Should set record name');
        Assert.areEqual('Account', linkedRecord.recordType, 'Should set record type');
    }

    // ==================== MOCK CLASSES ====================

    /**
     * Mock for task lists response
     */
    private class MockTaskListsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'kind' => 'tasks#taskLists',
                'items' => new List<Object>{
                    new Map<String, Object>{
                        'kind' => 'tasks#taskList',
                        'id' => 'list_1',
                        'title' => 'My Tasks',
                        'updated' => '2024-01-15T10:00:00.000Z'
                    },
                    new Map<String, Object>{
                        'kind' => 'tasks#taskList',
                        'id' => 'list_2',
                        'title' => 'Work Tasks',
                        'updated' => '2024-01-16T10:00:00.000Z'
                    }
                }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for tasks response
     */
    private class MockTasksResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'kind' => 'tasks#tasks',
                'items' => new List<Object>{
                    new Map<String, Object>{
                        'kind' => 'tasks#task',
                        'id' => 'task_1',
                        'title' => 'Task 1',
                        'notes' => 'Task notes',
                        'status' => 'needsAction',
                        'updated' => '2024-01-15T10:00:00.000Z'
                    },
                    new Map<String, Object>{
                        'kind' => 'tasks#task',
                        'id' => 'task_2',
                        'title' => 'Task 2',
                        'status' => 'needsAction',
                        'updated' => '2024-01-16T10:00:00.000Z'
                    }
                }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for single task response
     */
    private class MockSingleTaskResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'kind' => 'tasks#task',
                'id' => 'task_123',
                'title' => 'Test Task',
                'notes' => 'Test notes',
                'status' => 'needsAction',
                'updated' => '2024-01-15T10:00:00.000Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for error response
     */
    private class MockErrorResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockErrorResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Error occurred"}');
            return res;
        }
    }

    /**
     * Mock for exception response
     */
    private class MockExceptionResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Network error');
        }
    }

    /**
     * Mock for all tasks response
     */
    private class MockAllTasksResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            if (req.getEndpoint().contains('/users/@me/lists')) {
                // Task lists response
                Map<String, Object> response = new Map<String, Object>{
                    'items' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'list_1',
                            'title' => 'My Tasks',
                            'updated' => '2024-01-15T10:00:00.000Z'
                        }
                    }
                };
                res.setBody(JSON.serialize(response));
            } else {
                // Tasks response
                Map<String, Object> response = new Map<String, Object>{
                    'items' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'task_1',
                            'title' => 'Task 1',
                            'status' => 'needsAction',
                            'updated' => '2024-01-15T10:00:00.000Z'
                        }
                    }
                };
                res.setBody(JSON.serialize(response));
            }
            
            return res;
        }
    }

    /**
     * Mock for empty task lists
     */
    private class MockEmptyTaskListsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'items' => new List<Object>()
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for task list error
     */
    private class MockTaskListErrorResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('/users/@me/lists')) {
                res.setStatusCode(200);
                Map<String, Object> response = new Map<String, Object>{
                    'items' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'list_1',
                            'title' => 'My Tasks'
                        }
                    }
                };
                res.setBody(JSON.serialize(response));
            } else {
                res.setStatusCode(500);
                res.setBody('{"error":"Error"}');
            }
            
            return res;
        }
    }

    /**
     * Mock for large task list
     */
    private class MockLargeTaskListResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            if (req.getEndpoint().contains('/users/@me/lists')) {
                Map<String, Object> response = new Map<String, Object>{
                    'items' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'list_1',
                            'title' => 'My Tasks'
                        }
                    }
                };
                res.setBody(JSON.serialize(response));
            } else {
                List<Object> tasks = new List<Object>();
                for (Integer i = 0; i < 10; i++) {
                    tasks.add(new Map<String, Object>{
                        'id' => 'task_' + i,
                        'title' => 'Task ' + i,
                        'status' => 'needsAction'
                    });
                }
                Map<String, Object> response = new Map<String, Object>{
                    'items' => tasks
                };
                res.setBody(JSON.serialize(response));
            }
            
            return res;
        }
    }

    /**
     * Mock for task accessible response
     */
    private class MockTaskAccessibleResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockTaskAccessibleResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"items":[]}');
            return res;
        }
    }

    /**
     * Mock for completed task
     */
    private class MockCompletedTaskResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_123',
                'title' => 'Completed Task',
                'status' => 'completed',
                'completed' => '2024-01-15T12:00:00.000Z',
                'updated' => '2024-01-15T12:00:00.000Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for needsAction task
     */
    private class MockNeedsActionTaskResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_123',
                'title' => 'Needs Action Task',
                'status' => 'needsAction',
                'updated' => '2024-01-15T10:00:00.000Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for subtask
     */
    private class MockSubtaskResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_123',
                'title' => 'Subtask',
                'status' => 'needsAction',
                'parent' => 'parent_task_id',
                'position' => '00000000000000000001',
                'updated' => '2024-01-15T10:00:00.000Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with due date
     */
    private class MockTaskWithDueDateResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_123',
                'title' => 'Task with Due Date',
                'status' => 'needsAction',
                'due' => '2024-01-20T00:00:00.000Z',
                'updated' => '2024-01-15T10:00:00.000Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with fractional seconds
     */
    private class MockTaskWithFractionalSecondsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_123',
                'title' => 'Task',
                'status' => 'needsAction',
                'due' => '2024-01-20T10:30:45.123Z',
                'updated' => '2024-01-15T10:00:00.000Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with datetime without Z
     */
    private class MockTaskWithDateTimeNoZResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_123',
                'title' => 'Task',
                'status' => 'needsAction',
                'due' => '2024-01-20T10:30:45.123',
                'updated' => '2024-01-15T10:00:00.000Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for null task
     */
    private class MockNullTaskResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'items' => new List<Object>{ null }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for task with invalid date
     */
    private class MockTaskWithInvalidDateResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_123',
                'title' => 'Task',
                'status' => 'needsAction',
                'due' => 'invalid-date',
                'updated' => 'invalid-date'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }
}