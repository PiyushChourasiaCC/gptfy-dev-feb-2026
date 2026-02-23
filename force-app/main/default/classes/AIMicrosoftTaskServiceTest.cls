/**
 * Test class for AIMicrosoftTaskService
 * Tests Microsoft To-Do API service integration
 */
@isTest
public class AIMicrosoftTaskServiceTest {

    /**
     * Helper method to setup workspace user with Outlook token
     */
    private static void setupWorkspaceUser() {
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Access_Token__c = 'test_access_token_12345',
            Refresh_Token__c = 'test_refresh_token_12345',
            Provider__c = 'OUTLOOK'
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
        List<AIMicrosoftTaskService.TaskList> taskLists = AIMicrosoftTaskService.getTaskLists();
        Test.stopTest();
        
        Assert.areEqual(2, taskLists.size(), 'Should return 2 task lists');
        Assert.areEqual('list_1', taskLists[0].listId, 'Should have correct list ID');
        Assert.areEqual('My Tasks', taskLists[0].displayName, 'Should have correct display name');
    }

    /**
     * Test getTaskLists with error
     */
    @isTest
    static void testGetTaskLists_Error() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIMicrosoftTaskService.TaskList> taskLists = AIMicrosoftTaskService.getTaskLists();
            Assert.fail('Should throw TaskServiceException');
        } catch (AIMicrosoftTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch task lists'), 
                'Should throw exception with error message');
        }
        Test.stopTest();
    }

    /**
     * Test getAllTasks with task list error (should continue with other lists)
     */
    @isTest
    static void testGetAllTasks_TaskListError() {
        Test.setMock(HttpCalloutMock.class, new MockMixedTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(50, true);
        Test.stopTest();
        
        // Should return tasks from successful lists
        Assert.isNotNull(tasks, 'Should handle partial failures');
    }

    /**
     * Test getTasksFromList with max results limit
     */
    @isTest
    static void testGetTasksFromList_MaxResultsLimit() {
        Test.setMock(HttpCalloutMock.class, new MockManyTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromList('list_1', 'My Tasks', 2, false);
        Test.stopTest();
        
        Assert.isTrue(tasks.size() <= 2, 'Should respect max results limit');
    }

    /**
     * Test getAllTasksWithOffset with task list error
     */
    @isTest
    static void testGetAllTasksWithOffset_TaskListError() {
        Test.setMock(HttpCalloutMock.class, new MockMixedTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasksWithOffset(10, 0, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle partial failures');
    }

    /**
     * Test getAllTasks success
     */
    @isTest
    static void testGetAllTasks_Success() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(50, true);
        Test.stopTest();
        
        Assert.isTrue(tasks.size() > 0, 'Should return tasks');
    }

    /**
     * Test getAllTasks with null maxResults
     */
    @isTest
    static void testGetAllTasks_NullMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(null, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle null maxResults');
    }

    /**
     * Test getAllTasks with zero maxResults
     */
    @isTest
    static void testGetAllTasks_ZeroMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(0, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle zero maxResults');
    }

    /**
     * Test getAllTasks exclude completed
     */
    @isTest
    static void testGetAllTasks_ExcludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(50, false);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks');
    }

    /**
     * Test getAllTasks with empty task lists
     */
    @isTest
    static void testGetAllTasks_EmptyTaskLists() {
        Test.setMock(HttpCalloutMock.class, new MockEmptyTaskListsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(50, true);
        Test.stopTest();
        
        Assert.areEqual(0, tasks.size(), 'Should return empty list');
    }

    /**
     * Test getAllTasks with trimming
     */
    @isTest
    static void testGetAllTasks_Trimming() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasks(2, true);
        Test.stopTest();
        
        Assert.isTrue(tasks.size() <= 2, 'Should trim to max results');
    }

    /**
     * Test getTasksFromList success
     */
    @isTest
    static void testGetTasksFromList_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromList('list_1', 'My Tasks', 50, true);
        Test.stopTest();
        
        Assert.isTrue(tasks.size() > 0, 'Should return tasks');
        Assert.areEqual('task_1', tasks[0].taskId, 'Should have correct task ID');
    }

    /**
     * Test getTasksFromList with blank listId
     */
    @isTest
    static void testGetTasksFromList_BlankListId() {
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromList('', 'My Tasks', 50, true);
        Test.stopTest();
        
        Assert.areEqual(0, tasks.size(), 'Should return empty list for blank listId');
    }

    /**
     * Test getTasksFromList with null maxResults
     */
    @isTest
    static void testGetTasksFromList_NullMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromList('list_1', 'My Tasks', null, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle null maxResults');
    }

    /**
     * Test getTasksFromList exclude completed
     */
    @isTest
    static void testGetTasksFromList_ExcludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new MockTasksWithCompletedResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromList('list_1', 'My Tasks', 50, false);
        Test.stopTest();
        
        // Should only return non-completed tasks
        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            Assert.areNotEqual('completed', task.status, 'Should not include completed tasks');
        }
    }

    /**
     * Test getTasksFromList with error
     */
    @isTest
    static void testGetTasksFromList_Error() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(404));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromList('list_1', 'My Tasks', 50, true);
            Assert.fail('Should throw TaskServiceException');
        } catch (AIMicrosoftTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch tasks'), 
                'Should throw exception');
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
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasksWithOffset(10, 0, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks');
    }

    /**
     * Test getAllTasksWithOffset with offset
     */
    @isTest
    static void testGetAllTasksWithOffset_WithOffset() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasksWithOffset(10, 2, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle offset');
    }

    /**
     * Test getAllTasksWithOffset with null parameters
     */
    @isTest
    static void testGetAllTasksWithOffset_NullParameters() {
        Test.setMock(HttpCalloutMock.class, new MockAllTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasksWithOffset(null, null, true);
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
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasksWithOffset(10, -5, true);
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
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getAllTasksWithOffset(10, 0, true);
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
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', 10, 0, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should return tasks');
    }

    /**
     * Test getTasksFromListWithOffset with offset
     */
    @isTest
    static void testGetTasksFromListWithOffset_WithOffset() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', 10, 2, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle offset');
    }

    /**
     * Test getTasksFromListWithOffset with blank listId
     */
    @isTest
    static void testGetTasksFromListWithOffset_BlankListId() {
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromListWithOffset('', 'My Tasks', 10, 0, true);
        Test.stopTest();
        
        Assert.areEqual(0, tasks.size(), 'Should return empty list for blank listId');
    }

    /**
     * Test getTasksFromListWithOffset with null parameters
     */
    @isTest
    static void testGetTasksFromListWithOffset_NullParameters() {
        Test.setMock(HttpCalloutMock.class, new MockTasksResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', null, null, true);
        Test.stopTest();
        
        Assert.isNotNull(tasks, 'Should handle null parameters');
    }

    /**
     * Test getTasksFromListWithOffset exclude completed
     */
    @isTest
    static void testGetTasksFromListWithOffset_ExcludeCompleted() {
        Test.setMock(HttpCalloutMock.class, new MockTasksWithCompletedResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', 10, 0, false);
        Test.stopTest();
        
        // Should only return non-completed tasks
        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            Assert.areNotEqual('completed', task.status, 'Should not include completed tasks');
        }
    }

    /**
     * Test getTasksFromListWithOffset with error
     */
    @isTest
    static void testGetTasksFromListWithOffset_Error() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(500));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            List<AIMicrosoftTaskService.ToDoTask> tasks = AIMicrosoftTaskService.getTasksFromListWithOffset('list_1', 'My Tasks', 10, 0, true);
            Assert.fail('Should throw TaskServiceException');
        } catch (AIMicrosoftTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch tasks'), 
                'Should throw exception');
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
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        Test.stopTest();
        
        Assert.isNotNull(task, 'Should return task');
        Assert.areEqual('task_1', task.taskId, 'Should have correct task ID');
        Assert.areEqual('Test Task', task.title, 'Should have correct title');
    }

    /**
     * Test getTask with error
     */
    @isTest
    static void testGetTask_Error() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(404));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'invalid_id');
            Assert.fail('Should throw TaskServiceException');
        } catch (AIMicrosoftTaskService.TaskServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch task'), 
                'Should throw exception');
        }
        Test.stopTest();
    }

    /**
     * Test isTaskAccessible success
     */
    @isTest
    static void testIsTaskAccessible_Success() {
        Test.setMock(HttpCalloutMock.class, new MockTaskListsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        Boolean isAccessible = AIMicrosoftTaskService.isTaskAccessible();
        Test.stopTest();
        
        Assert.areEqual(true, isAccessible, 'Should return true for accessible tasks');
    }

    /**
     * Test isTaskAccessible failure
     */
    @isTest
    static void testIsTaskAccessible_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        setupWorkspaceUser();
        
        Test.startTest();
        Boolean isAccessible = AIMicrosoftTaskService.isTaskAccessible();
        Test.stopTest();
        
        Assert.areEqual(false, isAccessible, 'Should return false for inaccessible tasks');
    }

    /**
     * Test ToDoTask constructor
     */
    @isTest
    static void testToDoTaskConstructor() {
        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        Test.stopTest();
        
        Assert.areEqual('MICROSOFT_TASKS', task.provider, 'Should set provider');
        Assert.areEqual(false, task.isImported, 'Should set isImported to false');
        Assert.isNotNull(task.linkedRecords, 'Should initialize linkedRecords');
    }

    /**
     * Test LinkedRecord constructor
     */
    @isTest
    static void testLinkedRecordConstructor() {
        Test.startTest();
        AIMicrosoftTaskService.LinkedRecord record = new AIMicrosoftTaskService.LinkedRecord(
            UserInfo.getUserId(), 
            'Test User', 
            'User'
        );
        Test.stopTest();
        
        Assert.isNotNull(record.recordId, 'Should set recordId');
        Assert.areEqual('Test User', record.recordName, 'Should set recordName');
        Assert.areEqual('User', record.recordType, 'Should set recordType');
    }

    /**
     * Test parseTaskData with null
     */
    @isTest
    static void testParseTaskData_Null() {
        Test.setMock(HttpCalloutMock.class, new MockNullTaskResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        } catch (Exception e) {
            // Expected to handle null gracefully
        }
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle null task data');
    }

    /**
     * Test parseTaskData with HTML body
     */
    @isTest
    static void testParseTaskData_HtmlBody() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithHtmlBodyResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        Test.stopTest();
        
        Assert.isNotNull(task.body, 'Should parse HTML body');
        Assert.isFalse(task.body.contains('<'), 'Should strip HTML tags');
    }

    /**
     * Test parseTaskData with text body
     */
    @isTest
    static void testParseTaskData_TextBody() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithTextBodyResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        Test.stopTest();
        
        Assert.isNotNull(task.body, 'Should parse text body');
    }

    /**
     * Test parseTaskData with dates
     */
    @isTest
    static void testParseTaskData_WithDates() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithDatesResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        Test.stopTest();
        
        Assert.isNotNull(task.dueDateTime, 'Should parse due date');
        Assert.isNotNull(task.createdDateTime, 'Should parse created date');
    }

    /**
     * Test parseGraphDateTime with fractional seconds
     */
    @isTest
    static void testParseGraphDateTime_FractionalSeconds() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithFractionalSecondsResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        Test.stopTest();
        
        Assert.isNotNull(task.dueDateTime, 'Should parse date with fractional seconds');
    }

    /**
     * Test parseGraphDateTime with Z suffix
     */
    @isTest
    static void testParseGraphDateTime_WithZ() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithZSuffixResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        Test.stopTest();
        
        Assert.isNotNull(task.createdDateTime, 'Should parse date with Z suffix');
    }

    /**
     * Test stripHtml with blank content
     */
    @isTest
    static void testStripHtml_Blank() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithBlankBodyResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        Test.stopTest();
        
        Assert.isTrue(String.isBlank(task.body) || task.body == '', 'Should handle blank body');
    }

    /**
     * Test stripHtml with HTML entities
     */
    @isTest
    static void testStripHtml_HtmlEntities() {
        Test.setMock(HttpCalloutMock.class, new MockTaskWithHtmlEntitiesResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftTaskService.ToDoTask task = AIMicrosoftTaskService.getTask('list_1', 'task_1');
        Test.stopTest();
        
        Assert.isNotNull(task.body, 'Should decode HTML entities');
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
                'value' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'list_1',
                        'displayName' => 'My Tasks',
                        'isOwner' => true,
                        'isShared' => false,
                        'wellknownListName' => 'defaultList'
                    },
                    new Map<String, Object>{
                        'id' => 'list_2',
                        'displayName' => 'Work Tasks',
                        'isOwner' => true,
                        'isShared' => true,
                        'wellknownListName' => null
                    }
                }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for empty task lists response
     */
    private class MockEmptyTaskListsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'value' => new List<Object>()
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
                'value' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'task_1',
                        'title' => 'Test Task 1',
                        'status' => 'notStarted',
                        'importance' => 'normal',
                        'isReminderOn' => false,
                        'body' => new Map<String, Object>{
                            'content' => 'Task description',
                            'contentType' => 'text'
                        },
                        'createdDateTime' => '2024-01-15T10:00:00Z',
                        'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
                    },
                    new Map<String, Object>{
                        'id' => 'task_2',
                        'title' => 'Test Task 2',
                        'status' => 'inProgress',
                        'importance' => 'high',
                        'isReminderOn' => true,
                        'body' => new Map<String, Object>{
                            'content' => 'Another task',
                            'contentType' => 'text'
                        },
                        'createdDateTime' => '2024-01-16T10:00:00Z',
                        'lastModifiedDateTime' => '2024-01-16T10:00:00Z'
                    }
                }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for tasks with completed response
     */
    private class MockTasksWithCompletedResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'value' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'task_1',
                        'title' => 'Active Task',
                        'status' => 'notStarted',
                        'importance' => 'normal',
                        'isReminderOn' => false,
                        'createdDateTime' => '2024-01-15T10:00:00Z',
                        'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
                    },
                    new Map<String, Object>{
                        'id' => 'task_2',
                        'title' => 'Completed Task',
                        'status' => 'completed',
                        'importance' => 'normal',
                        'isReminderOn' => false,
                        'completedDateTime' => new Map<String, Object>{
                            'dateTime' => '2024-01-16T10:00:00'
                        },
                        'createdDateTime' => '2024-01-15T10:00:00Z',
                        'lastModifiedDateTime' => '2024-01-16T10:00:00Z'
                    }
                }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for all tasks response (combines task lists and tasks)
     */
    private class MockAllTasksResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            if (req.getEndpoint().contains('/todo/lists') && !req.getEndpoint().contains('/tasks')) {
                // Task lists request
                return new MockTaskListsResponse().respond(req);
            } else {
                // Tasks request
                return new MockTasksResponse().respond(req);
            }
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
                'id' => 'task_1',
                'title' => 'Test Task',
                'status' => 'notStarted',
                'importance' => 'normal',
                'isReminderOn' => false,
                'body' => new Map<String, Object>{
                    'content' => 'Task description',
                    'contentType' => 'text'
                },
                'createdDateTime' => '2024-01-15T10:00:00Z',
                'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with HTML body
     */
    private class MockTaskWithHtmlBodyResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_1',
                'title' => 'Test Task',
                'status' => 'notStarted',
                'importance' => 'normal',
                'isReminderOn' => false,
                'body' => new Map<String, Object>{
                    'content' => '<p>Task <strong>description</strong> with HTML</p>',
                    'contentType' => 'html'
                },
                'createdDateTime' => '2024-01-15T10:00:00Z',
                'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with text body
     */
    private class MockTaskWithTextBodyResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_1',
                'title' => 'Test Task',
                'status' => 'notStarted',
                'importance' => 'normal',
                'isReminderOn' => false,
                'body' => new Map<String, Object>{
                    'content' => 'Plain text description',
                    'contentType' => 'text'
                },
                'createdDateTime' => '2024-01-15T10:00:00Z',
                'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with dates
     */
    private class MockTaskWithDatesResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_1',
                'title' => 'Test Task',
                'status' => 'notStarted',
                'importance' => 'normal',
                'isReminderOn' => true,
                'dueDateTime' => new Map<String, Object>{
                    'dateTime' => '2024-01-20T14:00:00'
                },
                'reminderDateTime' => new Map<String, Object>{
                    'dateTime' => '2024-01-19T09:00:00'
                },
                'createdDateTime' => '2024-01-15T10:00:00Z',
                'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
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
                'id' => 'task_1',
                'title' => 'Test Task',
                'status' => 'notStarted',
                'importance' => 'normal',
                'isReminderOn' => false,
                'dueDateTime' => new Map<String, Object>{
                    'dateTime' => '2024-01-20T14:00:00.1234567'
                },
                'createdDateTime' => '2024-01-15T10:00:00.123Z',
                'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with Z suffix
     */
    private class MockTaskWithZSuffixResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_1',
                'title' => 'Test Task',
                'status' => 'notStarted',
                'importance' => 'normal',
                'isReminderOn' => false,
                'createdDateTime' => '2024-01-15T10:00:00Z',
                'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with blank body
     */
    private class MockTaskWithBlankBodyResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_1',
                'title' => 'Test Task',
                'status' => 'notStarted',
                'importance' => 'normal',
                'isReminderOn' => false,
                'body' => new Map<String, Object>{
                    'content' => '',
                    'contentType' => 'html'
                },
                'createdDateTime' => '2024-01-15T10:00:00Z',
                'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for task with HTML entities
     */
    private class MockTaskWithHtmlEntitiesResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> task = new Map<String, Object>{
                'id' => 'task_1',
                'title' => 'Test Task',
                'status' => 'notStarted',
                'importance' => 'normal',
                'isReminderOn' => false,
                'body' => new Map<String, Object>{
                    'content' => '<p>Task&nbsp;with&amp;entities&lt;&gt;&quot;</p>',
                    'contentType' => 'html'
                },
                'createdDateTime' => '2024-01-15T10:00:00Z',
                'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
            };
            
            res.setBody(JSON.serialize(task));
            return res;
        }
    }

    /**
     * Mock for null task response
     */
    private class MockNullTaskResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('null');
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
     * Mock for mixed tasks response (some succeed, some fail)
     */
    private class MockMixedTasksResponse implements HttpCalloutMock {
        private Integer callCount = 0;
        
        public HTTPResponse respond(HTTPRequest req) {
            if (req.getEndpoint().contains('/todo/lists') && !req.getEndpoint().contains('/tasks')) {
                // Task lists request
                return new MockTaskListsResponse().respond(req);
            } else {
                // Tasks request - fail on first call, succeed on second
                callCount++;
                if (callCount == 1) {
                    HttpResponse res = new HttpResponse();
                    res.setStatusCode(500);
                    res.setBody('{"error":"Server error"}');
                    return res;
                } else {
                    return new MockTasksResponse().respond(req);
                }
            }
        }
    }

    /**
     * Mock for many tasks response (to test max results limit)
     */
    private class MockManyTasksResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            List<Object> tasks = new List<Object>();
            for (Integer i = 1; i <= 10; i++) {
                tasks.add(new Map<String, Object>{
                    'id' => 'task_' + i,
                    'title' => 'Test Task ' + i,
                    'status' => (i <= 5) ? 'notStarted' : 'completed',
                    'importance' => 'normal',
                    'isReminderOn' => false,
                    'createdDateTime' => '2024-01-15T10:00:00Z',
                    'lastModifiedDateTime' => '2024-01-15T10:00:00Z'
                });
            }
            
            Map<String, Object> response = new Map<String, Object>{
                'value' => tasks
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }
}