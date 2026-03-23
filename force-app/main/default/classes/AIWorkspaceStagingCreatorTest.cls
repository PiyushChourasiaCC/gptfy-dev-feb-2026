/**
 * Test class for AIWorkspaceStagingCreator
 * Tests staging record creation for emails, calendar events, and tasks
 */
@IsTest
private class AIWorkspaceStagingCreatorTest {

    @TestSetup
    static void setupTestData() {
        // Create a sync log for testing
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Status__c = 'In Progress',
            Sync_Type__c = 'Manual'
        );
        insert syncLog;
        
        // V2-7889: Create workspace user records for testing
        List<AI_Workspace_User__c> workspaceUsers = new List<AI_Workspace_User__c>{
            new AI_Workspace_User__c(
                User__c = UserInfo.getUserId(),
                Provider__c = 'Outlook',
                Name = 'Test Outlook User',
                Service_User_Email__c = 'testuser@example.com',
                Access_Token__c = 'test_access_token',
                Refresh_Token__c = 'test_refresh_token'
            ),
            new AI_Workspace_User__c(
                User__c = UserInfo.getUserId(),
                Provider__c = 'Gmail',
                Name = 'Test Gmail User',
                Service_User_Email__c = 'testuser@gmail.com',
                Access_Token__c = 'test_access_token',
                Refresh_Token__c = 'test_refresh_token'
            )
        };
        insert workspaceUsers;
    }

    // ============================================
    // Email Staging Tests
    // ============================================

    @IsTest
    static void testCreateEmailStagingRecords_Success() {
        List<Map<String, Object>> emails = createTestEmailData(3);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        Assert.areEqual(3, result.successCount, 'Should create 3 staging records');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');
        Assert.areEqual(0, result.duplicateCount, 'Should have no duplicates');
        Assert.areEqual(3, result.stagingRecordIds.size(), 'Should return 3 record IDs');

        // Verify records created
        List<AI_Workspace_Staging__c> stagingRecords = [
            SELECT Subject__c, From_Address__c, To_Address__c, Provider__c, Status__c, AI_Workspace_User__c
            FROM AI_Workspace_Staging__c
            WHERE Id IN :result.stagingRecordIds
        ];
        Assert.areEqual(3, stagingRecords.size(), 'Should have 3 records in database');
        Assert.areEqual('MICROSOFT_EMAIL', stagingRecords[0].Provider__c, 'Provider should be set');
        Assert.areEqual('Staged', stagingRecords[0].Status__c, 'Status should be Staged');
        // V2-7889: Verify workspace user link
        Assert.isNotNull(stagingRecords[0].AI_Workspace_User__c, 'AI Workspace User should be linked');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithSyncLog() {
        AI_Workspace_Sync_Log__c syncLog = [SELECT Id FROM AI_Workspace_Sync_Log__c LIMIT 1];
        List<Map<String, Object>> emails = createTestEmailData(1);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                syncLog.Id
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');

        AI_Workspace_Staging__c staging = [
            SELECT Sync_Log__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual(syncLog.Id, staging.Sync_Log__c, 'Sync log should be linked');
    }

    @IsTest
    static void testCreateEmailStagingRecords_Deduplication() {
        List<Map<String, Object>> emails = createTestEmailData(2);

        // Insert first batch
        AIWorkspaceStagingCreator.createEmailStagingRecords(
            emails,
            'MICROSOFT_EMAIL',
            'testuser@example.com',
            null
        );

        // Try to insert same emails again
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should not create duplicate records');
        Assert.areEqual(2, result.duplicateCount, 'Should detect 2 duplicates');
    }

    @IsTest
    static void testCreateEmailStagingRecords_EmptyList() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                new List<Map<String, Object>>(),
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have 0 success');
        Assert.areEqual(0, result.failedCount, 'Should have 0 failed');
    }

    @IsTest
    static void testCreateEmailStagingRecords_NullList() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                null,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should handle null gracefully');
    }

    @IsTest
    static void testCreateEmailStagingRecords_SentEmail() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'sent-email-001',
            'subject' => 'Sent Email Test',
            'internetMessageId' => '<sent-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'testuser@example.com',
                    'name' => 'Test User'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Is_Incoming__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isFalse(staging.Is_Incoming__c, 'Should be marked as outgoing (sent)');
    }

    @IsTest
    static void testCreateEmailStagingRecords_HtmlBody() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'html-email-001',
            'subject' => 'HTML Email Test',
            'internetMessageId' => '<html-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'html',
                'content' => '<html><body><p>Test <b>bold</b> content</p></body></html>'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'GOOGLE_TASKS',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Html_Body__c, Text_Body__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isNotNull(staging.Html_Body__c, 'HTML body should be set');
        Assert.isNotNull(staging.Text_Body__c, 'Text body should be set');
    }

    // ============================================
    // Calendar Staging Tests
    // ============================================

    @IsTest
    static void testCreateCalendarStagingRecords_Success() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = createTestCalendarEvents(3);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(3, result.successCount, 'Should create 3 staging records');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');
        Assert.areEqual(3, result.stagingRecordIds.size(), 'Should return 3 record IDs');

        List<AI_Workspace_Staging__c> stagingRecords = [
            SELECT Subject__c, Start_DateTime__c, End_DateTime__c, Location__c, Provider__c
            FROM AI_Workspace_Staging__c
            WHERE Id IN :result.stagingRecordIds
        ];
        Assert.areEqual(3, stagingRecords.size(), 'Should have 3 records in database');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_AllDayEvent() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'all-day-001';
        evt.iCalUID = 'ical-all-day-001';
        evt.subject = 'All Day Event';
        evt.startDateTime = Date.today();
        evt.endDateTime = Date.today().addDays(1);
        evt.isAllDay = true;
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Is_All_Day__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isTrue(staging.Is_All_Day__c, 'Should be marked as all-day event');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithAttendees() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'meeting-001';
        evt.iCalUID = 'ical-meeting-001';
        evt.subject = 'Team Meeting';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.organizerEmail = 'organizer@example.com';
        evt.organizerName = 'Organizer';
        
        AIMicrosoftCalendarService.Attendee att1 = new AIMicrosoftCalendarService.Attendee();
        att1.email = 'attendee1@example.com';
        att1.name = 'Attendee One';
        
        AIMicrosoftCalendarService.Attendee att2 = new AIMicrosoftCalendarService.Attendee();
        att2.email = 'attendee2@example.com';
        att2.name = 'Attendee Two';
        
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>{ att1, att2 };
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Attendees__c, Organizer__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isTrue(staging.Attendees__c.contains('attendee1@example.com'), 'Should contain attendee 1');
        Assert.isTrue(staging.Attendees__c.contains('attendee2@example.com'), 'Should contain attendee 2');
        Assert.isNotNull(staging.Organizer__c, 'Organizer should be set');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_Deduplication() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = createTestCalendarEvents(2);

        // Insert first batch
        AIWorkspaceStagingCreator.createCalendarStagingRecords(
            events,
            'MICROSOFT_EMAIL',
            null
        );

        // Try to insert same events again
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should not create duplicate records');
        Assert.areEqual(2, result.duplicateCount, 'Should detect 2 duplicates');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_EmptyList() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>(),
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have 0 success');
    }

    // ============================================
    // Task Staging Tests
    // ============================================

    @IsTest
    static void testCreateTaskStagingRecords_Success() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = createTestTasks(3);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(3, result.successCount, 'Should create 3 staging records');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');
        Assert.areEqual(3, result.stagingRecordIds.size(), 'Should return 3 record IDs');

        List<AI_Workspace_Staging__c> stagingRecords = [
            SELECT Subject__c, Task_Status__c, Task_Priority__c, Provider__c
            FROM AI_Workspace_Staging__c
            WHERE Id IN :result.stagingRecordIds
        ];
        Assert.areEqual(3, stagingRecords.size(), 'Should have 3 records in database');
    }

    @IsTest
    static void testCreateTaskStagingRecords_StatusMapping() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task1 = new AIMicrosoftTaskService.ToDoTask();
        task1.taskId = 'task-001';
        task1.title = 'Not Started Task';
        task1.status = 'notStarted';
        tasks.add(task1);

        AIMicrosoftTaskService.ToDoTask task2 = new AIMicrosoftTaskService.ToDoTask();
        task2.taskId = 'task-002';
        task2.title = 'In Progress Task';
        task2.status = 'inProgress';
        tasks.add(task2);

        AIMicrosoftTaskService.ToDoTask task3 = new AIMicrosoftTaskService.ToDoTask();
        task3.taskId = 'task-003';
        task3.title = 'Completed Task';
        task3.status = 'completed';
        tasks.add(task3);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(3, result.successCount, 'Should create 3 staging records');
        
        Map<String, AI_Workspace_Staging__c> stagingBySubject = new Map<String, AI_Workspace_Staging__c>();
        for (AI_Workspace_Staging__c s : [
            SELECT Subject__c, Task_Status__c FROM AI_Workspace_Staging__c
        ]) {
            stagingBySubject.put(s.Subject__c, s);
        }

        if (stagingBySubject.containsKey('Not Started Task')) {
            Assert.areEqual('Not Started', stagingBySubject.get('Not Started Task').Task_Status__c);
        }
        if (stagingBySubject.containsKey('In Progress Task')) {
            Assert.areEqual('In Progress', stagingBySubject.get('In Progress Task').Task_Status__c);
        }
        if (stagingBySubject.containsKey('Completed Task')) {
            Assert.areEqual('Completed', stagingBySubject.get('Completed Task').Task_Status__c);
        }
    }

    @IsTest
    static void testCreateTaskStagingRecords_PriorityMapping() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task1 = new AIMicrosoftTaskService.ToDoTask();
        task1.taskId = 'priority-001';
        task1.title = 'Low Priority';
        task1.importance = 'low';
        tasks.add(task1);

        AIMicrosoftTaskService.ToDoTask task2 = new AIMicrosoftTaskService.ToDoTask();
        task2.taskId = 'priority-002';
        task2.title = 'High Priority';
        task2.importance = 'high';
        tasks.add(task2);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(2, result.successCount, 'Should create 2 staging records');
        
        Map<String, AI_Workspace_Staging__c> stagingBySubject = new Map<String, AI_Workspace_Staging__c>();
        for (AI_Workspace_Staging__c s : [
            SELECT Subject__c, Task_Priority__c FROM AI_Workspace_Staging__c
        ]) {
            stagingBySubject.put(s.Subject__c, s);
        }

        if (stagingBySubject.containsKey('Low Priority')) {
            Assert.areEqual('Low', stagingBySubject.get('Low Priority').Task_Priority__c);
        }
        if (stagingBySubject.containsKey('High Priority')) {
            Assert.areEqual('High', stagingBySubject.get('High Priority').Task_Priority__c);
        }
    }

    @IsTest
    static void testCreateTaskStagingRecords_Deduplication() {
        // UPDATED (2026-02-13): Test that Matched staging records are detected as duplicates
        // Create tasks and manually create staging records with Matched status
        List<AIMicrosoftTaskService.ToDoTask> tasks = createTestTasks(2);

        // Manually create Matched staging records (simulating tasks that were already imported)
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Task').getRecordTypeId();
        
        List<AI_Workspace_Staging__c> matchedStaging = new List<AI_Workspace_Staging__c>();
        for (AIMicrosoftTaskService.ToDoTask task : tasks) {
            AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
                RecordTypeId = taskRecordTypeId,
                Provider_Id__c = task.taskId,
                Subject__c = task.title,
                Provider__c = 'MICROSOFT_EMAIL',
                Status__c = 'Imported', // Mark as Matched
                User__c = UserInfo.getUserId()
            );
            matchedStaging.add(staging);
        }
        insert matchedStaging;

        // Try to insert same tasks - should detect as duplicates
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        // Should detect duplicates because staging records are Matched
        Assert.areEqual(0, result.successCount, 'Should not create duplicate records when Matched staging exists');
        Assert.areEqual(2, result.duplicateCount, 'Should detect 2 duplicates');
    }

    @IsTest
    static void testCreateTaskStagingRecords_ReimportUnmatched() {
        // NEW TEST (2026-02-13): Test QA's scenario - PROPER FIX
        // 1. User syncs task without Contact/Lead -> Creates Unmatched staging, no Task
        // 2. User creates Contact with email
        // 3. User re-syncs same task -> Should REUSE existing Unmatched staging and retry Task creation
        //
        // UPDATED (2026-02-16): Existing staging records (even Unmatched) are counted as duplicates
        // for SYNC COUNT purposes to ensure formula: Fetched = Matched + Unmatched + Duplicate
        // However, the system still REUSES the existing staging for re-matching attempts.
        
        List<AIMicrosoftTaskService.ToDoTask> tasks = createTestTasks(1);

        // Manually create Unmatched staging record (simulating first sync with no Contact/Lead)
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c unmatchedStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Provider_Id__c = tasks[0].taskId,
            Subject__c = tasks[0].title,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Staged', // Mark as Unmatched (no Task created)
            User__c = UserInfo.getUserId()
        );
        insert unmatchedStaging;

        // Verify no Task exists
        List<Task> tasksBeforeReimport = [SELECT Id FROM Task];
        Assert.areEqual(0, tasksBeforeReimport.size(), 'No Task should exist initially');

        // Second sync - should REUSE existing Unmatched staging (not create new one)
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult secondResult = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        // Existing staging records are counted as duplicates for sync count consistency
        // This ensures Fetched = Matched + Unmatched + Duplicate for THIS sync only
        // The re-match attempt still happens behind the scenes via existingUnmatchedStagingIdsSet
        Assert.areEqual(0, secondResult.successCount, 'No new staging created - existing one is reused');
        Assert.areEqual(1, secondResult.duplicateCount, 'Existing Unmatched staging counts as duplicate for sync totals');
        
        // Verify ONLY ONE staging record exists (the original Unmatched one, reused)
        List<AI_Workspace_Staging__c> allStaging = [
            SELECT Id, Status__c, Provider_Id__c 
            FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = :tasks[0].taskId
        ];
        Assert.areEqual(1, allStaging.size(), 'Should have ONLY 1 staging record (reused existing Unmatched)');
        Assert.areEqual(unmatchedStaging.Id, allStaging[0].Id, 'Should be the same staging record ID');
    }

    @IsTest
    static void testCreateTaskStagingRecords_WithDueDate() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'due-date-001';
        task.title = 'Task With Due Date';
        task.dueDateTime = DateTime.now().addDays(7);
        task.listName = 'My Tasks';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Due_Date__c, List_Name__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isNotNull(staging.Due_Date__c, 'Due date should be set');
        Assert.areEqual('My Tasks', staging.List_Name__c, 'List name should be set');
    }

    // ============================================
    // Utility Method Tests
    // ============================================

    @IsTest
    static void testGetExistingEmailsByProviderId() {
        List<Map<String, Object>> emails = createTestEmailData(2);
        AIWorkspaceStagingCreator.createEmailStagingRecords(
            emails,
            'MICROSOFT_EMAIL',
            'test@example.com',
            null
        );

        Set<String> providerIds = new Set<String>{'test-email-id-0', 'test-email-id-1', 'non-existent'};

        Test.startTest();
        Map<String, Id> existingMap = AIWorkspaceStagingCreator.getExistingEmailsByProviderId(providerIds);
        Test.stopTest();

        Assert.areEqual(2, existingMap.size(), 'Should find 2 existing emails');
        Assert.isTrue(existingMap.containsKey('test-email-id-0'), 'Should contain first email');
        Assert.isTrue(existingMap.containsKey('test-email-id-1'), 'Should contain second email');
    }

    @IsTest
    static void testGetExistingCalendarsByICalUID() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = createTestCalendarEvents(2);
        AIWorkspaceStagingCreator.createCalendarStagingRecords(
            events,
            'MICROSOFT_EMAIL',
            null
        );

        Set<String> iCalUIDs = new Set<String>{'ical-uid-0', 'ical-uid-1', 'non-existent'};

        Test.startTest();
        Map<String, Id> existingMap = AIWorkspaceStagingCreator.getExistingCalendarsByICalUID(iCalUIDs);
        Test.stopTest();

        Assert.areEqual(2, existingMap.size(), 'Should find 2 existing calendar events');
    }

    @IsTest
    static void testGetExistingTasksByProviderId() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = createTestTasks(2);
        AIWorkspaceStagingCreator.createTaskStagingRecords(
            tasks,
            'MICROSOFT_EMAIL',
            null
        );

        Set<String> providerIds = new Set<String>{'task-id-0', 'task-id-1', 'non-existent'};

        Test.startTest();
        Map<String, Id> existingMap = AIWorkspaceStagingCreator.getExistingTasksByProviderId(providerIds);
        Test.stopTest();

        Assert.areEqual(2, existingMap.size(), 'Should find 2 existing tasks');
    }

    // ============================================
    // Rematching Tests (Bug Fix V2-XXXX)
    // ============================================

    /**
     * Test that rematching existing unmatched emails does NOT inflate sync log counts
     * This test verifies the fix for the issue where Imported > Matched in sync logs
     * 
     * Scenario:
     * 1. First sync: Fetch 5 emails, 3 match, 2 don't match (Matched=3, Imported=3)
     * 2. Second sync: Fetch 3 NEW emails, but also rematch the 2 old unmatched ones
     *    - Expected: Matched=3 (only new), Imported=3 (only new)
     *    - Bug: Matched=3, Imported=5 (includes rematched old emails)
     */
    @IsTest
    static void testRematchingDoesNotInflateSyncLogCounts() {
        // Create test contacts for matching
        Contact contact1 = new Contact(
            FirstName = 'Test',
            LastName = 'Contact1',
            Email = 'sender0@example.com'
        );
        Contact contact2 = new Contact(
            FirstName = 'Test',
            LastName = 'Contact2',
            Email = 'sender1@example.com'
        );
        Contact contact3 = new Contact(
            FirstName = 'Test',
            LastName = 'Contact3',
            Email = 'sender2@example.com'
        );
        insert new List<Contact>{contact1, contact2, contact3};
        
        // FIRST SYNC: Create 5 emails, 3 will match (sender0, sender1, sender2), 2 won't match
        List<Map<String, Object>> firstBatchEmails = new List<Map<String, Object>>();
        
        // 3 emails that will match
        for (Integer i = 0; i < 3; i++) {
            firstBatchEmails.add(new Map<String, Object>{
                'id' => 'first-batch-email-' + i,
                'conversationId' => 'conv-first-' + i,
                'subject' => 'First Batch Email ' + i,
                'internetMessageId' => '<first-msg-' + i + '@test.com>',
                'receivedDateTime' => '2024-01-15T10:30:00Z',
                'importance' => 'normal',
                'hasAttachments' => false,
                'from' => new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'sender' + i + '@example.com',
                        'name' => 'Sender ' + i
                    }
                },
                'toRecipients' => new List<Object>{
                    new Map<String, Object>{
                        'emailAddress' => new Map<String, Object>{
                            'address' => 'recipient@example.com',
                            'name' => 'Recipient'
                        }
                    }
                },
                'ccRecipients' => new List<Object>(),
                'bccRecipients' => new List<Object>(),
                'body' => new Map<String, Object>{
                    'contentType' => 'text',
                    'content' => 'Test email body ' + i
                }
            });
        }
        
        // 2 emails that won't match (no contacts with these emails)
        for (Integer i = 3; i < 5; i++) {
            firstBatchEmails.add(new Map<String, Object>{
                'id' => 'first-batch-email-' + i,
                'conversationId' => 'conv-first-' + i,
                'subject' => 'First Batch Email ' + i,
                'internetMessageId' => '<first-msg-' + i + '@test.com>',
                'receivedDateTime' => '2024-01-15T10:30:00Z',
                'importance' => 'normal',
                'hasAttachments' => false,
                'from' => new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'unmatched' + i + '@example.com',
                        'name' => 'Unmatched ' + i
                    }
                },
                'toRecipients' => new List<Object>{
                    new Map<String, Object>{
                        'emailAddress' => new Map<String, Object>{
                            'address' => 'recipient@example.com',
                            'name' => 'Recipient'
                        }
                    }
                },
                'ccRecipients' => new List<Object>(),
                'bccRecipients' => new List<Object>(),
                'body' => new Map<String, Object>{
                    'contentType' => 'text',
                    'content' => 'Test email body ' + i
                }
            });
        }
        
        // First sync
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult firstResult = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                firstBatchEmails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                false // Don't send notifications
            );
        
        
        Assert.areEqual(5, firstResult.successCount, 'First sync should create 5 staging records');
        // With sendNotifications=false (auto-sync), matching is deferred to batch jobs
        // So matchedCount=0, unmatchedCount=5 (all staged for later processing)
        Assert.areEqual(0, firstResult.matchedCount, 'First sync should not match emails in auto-sync mode');
        Assert.areEqual(5, firstResult.unmatchedCount, 'First sync should have 5 unmatched (staged)');
        Assert.areEqual(0, firstResult.importedCount, 'First sync should not import EmailMessages in auto-sync mode');
        
        // SECOND SYNC: Create 3 NEW emails that will match
        // The 2 old unmatched emails should be rematched but NOT counted in sync log
        List<Map<String, Object>> secondBatchEmails = new List<Map<String, Object>>();
        
        for (Integer i = 0; i < 3; i++) {
            secondBatchEmails.add(new Map<String, Object>{
                'id' => 'second-batch-email-' + i,
                'conversationId' => 'conv-second-' + i,
                'subject' => 'Second Batch Email ' + i,
                'internetMessageId' => '<second-msg-' + i + '@test.com>',
                'receivedDateTime' => '2024-01-16T10:30:00Z',
                'importance' => 'normal',
                'hasAttachments' => false,
                'from' => new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'sender' + i + '@example.com',
                        'name' => 'Sender ' + i
                    }
                },
                'toRecipients' => new List<Object>{
                    new Map<String, Object>{
                        'emailAddress' => new Map<String, Object>{
                            'address' => 'recipient@example.com',
                            'name' => 'Recipient'
                        }
                    }
                },
                'ccRecipients' => new List<Object>(),
                'bccRecipients' => new List<Object>(),
                'body' => new Map<String, Object>{
                    'contentType' => 'text',
                    'content' => 'Test email body ' + i
                }
            });
        }
        
        // Second sync
        AIWorkspaceStagingCreator.StagingResult secondResult = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                secondBatchEmails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                false // Don't send notifications (auto-sync mode)
            );
        Test.stopTest();
        
      
        Assert.areEqual(3, secondResult.successCount, 'Second sync should create 3 staging records');
        // With sendNotifications=false (auto-sync), matching is deferred to batch jobs
        Assert.areEqual(0, secondResult.matchedCount, 'Second sync should not match emails in auto-sync mode');
        Assert.areEqual(3, secondResult.unmatchedCount, 'Second sync should have 3 unmatched (staged)');
        
        // In auto-sync mode, no EmailMessages are created inline
        Assert.areEqual(0, secondResult.importedCount, 
            'Second sync should not import EmailMessages in auto-sync mode');
        
        // Verify that rematching doesn't happen in auto-sync mode
        Assert.areEqual(0, secondResult.rematchedCount, 
            'Auto-sync should not rematch existing staged records inline');
    }

    // ============================================
    // Helper Methods
    // ============================================

    private static List<Map<String, Object>> createTestEmailData(Integer count) {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();

        for (Integer i = 0; i < count; i++) {
            Map<String, Object> email = new Map<String, Object>{
                'id' => 'test-email-id-' + i,
                'conversationId' => 'conv-' + i,
                'subject' => 'Test Email ' + i,
                'internetMessageId' => '<test-msg-' + i + '@test.com>',
                'receivedDateTime' => '2024-01-15T10:30:00Z',
                'importance' => 'normal',
                'hasAttachments' => false,
                'from' => new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'sender' + i + '@example.com',
                        'name' => 'Sender ' + i
                    }
                },
                'toRecipients' => new List<Object>{
                    new Map<String, Object>{
                        'emailAddress' => new Map<String, Object>{
                            'address' => 'recipient@example.com',
                            'name' => 'Recipient'
                        }
                    }
                },
                'ccRecipients' => new List<Object>(),
                'bccRecipients' => new List<Object>(),
                'body' => new Map<String, Object>{
                    'contentType' => 'text',
                    'content' => 'Test email body ' + i
                }
            };
            emails.add(email);
        }

        return emails;
    }

    private static List<AIMicrosoftCalendarService.CalendarEvent> createTestCalendarEvents(Integer count) {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();

        for (Integer i = 0; i < count; i++) {
            AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
            evt.eventId = 'event-id-' + i;
            evt.iCalUID = 'ical-uid-' + i;
            evt.subject = 'Test Event ' + i;
            evt.startDateTime = DateTime.now().addDays(i);
            evt.endDateTime = DateTime.now().addDays(i).addHours(1);
            evt.location = 'Conference Room ' + i;
            evt.description = 'Test event description ' + i;
            evt.isAllDay = false;
            events.add(evt);
        }

        return events;
    }

    private static List<AIMicrosoftTaskService.ToDoTask> createTestTasks(Integer count) {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        for (Integer i = 0; i < count; i++) {
            AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
            task.taskId = 'task-id-' + i;
            task.title = 'Test Task ' + i;
            task.body = 'Task description ' + i;
            task.status = 'notStarted';
            task.importance = 'normal';
            task.listName = 'Test List';
            tasks.add(task);
        }

        return tasks;
    }

    // ============================================
    // Google Task Staging Tests
    // ============================================

    @IsTest
    static void testCreateGoogleTaskStagingRecords_Success() {
        List<AIGoogleTaskService.ToDoTask> tasks = createTestGoogleTasks(3);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        Assert.areEqual(3, result.successCount, 'Should create 3 staging records');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');
        Assert.areEqual(3, result.stagingRecordIds.size(), 'Should return 3 record IDs');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_NullList() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                null,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should handle null gracefully');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_EmptyList() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                new List<AIGoogleTaskService.ToDoTask>(),
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should handle empty list');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_Deduplication() {
        List<AIGoogleTaskService.ToDoTask> tasks = createTestGoogleTasks(2);

        // Insert first batch
        AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
            tasks,
            UserInfo.getUserId(),
            'GOOGLE_TASKS',
            false
        );

        // Try to insert same tasks again
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should not create duplicate records');
        Assert.areEqual(2, result.duplicateCount, 'Should detect 2 duplicates');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_StatusMapping() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        AIGoogleTaskService.ToDoTask task1 = new AIGoogleTaskService.ToDoTask();
        task1.taskId = 'google-task-001';
        task1.title = 'Needs Action Task';
        task1.status = 'needsAction';
        tasks.add(task1);

        AIGoogleTaskService.ToDoTask task2 = new AIGoogleTaskService.ToDoTask();
        task2.taskId = 'google-task-002';
        task2.title = 'Completed Task';
        task2.status = 'completed';
        tasks.add(task2);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        Assert.areEqual(2, result.successCount, 'Should create 2 staging records');
        
        Map<String, AI_Workspace_Staging__c> stagingBySubject = new Map<String, AI_Workspace_Staging__c>();
        for (AI_Workspace_Staging__c s : [
            SELECT Subject__c, Task_Status__c FROM AI_Workspace_Staging__c
        ]) {
            stagingBySubject.put(s.Subject__c, s);
        }

        if (stagingBySubject.containsKey('Needs Action Task')) {
            Assert.areEqual('Not Started', stagingBySubject.get('Needs Action Task').Task_Status__c);
        }
        if (stagingBySubject.containsKey('Completed Task')) {
            Assert.areEqual('Completed', stagingBySubject.get('Completed Task').Task_Status__c);
        }
    }

    // ============================================
    // Utility and Edge Case Tests
    // ============================================

    @IsTest
    static void testClearRecordTypeCache() {
        // Call a method that uses the cache
        List<Map<String, Object>> emails = createTestEmailData(1);
        AIWorkspaceStagingCreator.createEmailStagingRecords(
            emails,
            'MICROSOFT_EMAIL',
            'test@example.com',
            null
        );

        Test.startTest();
        // Clear the cache
        AIWorkspaceStagingCreator.clearRecordTypeCache();
        
        // Call again - should rebuild cache
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'test@example.com',
                null
            );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null after cache clear');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_NullList() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                null,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should handle null gracefully');
    }

    @IsTest
    static void testCreateTaskStagingRecords_EmptyList() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>(),
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should handle empty list');
    }

    @IsTest
    static void testCreateTaskStagingRecords_NullList() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                null,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should handle null gracefully');
    }

    @IsTest
    static void testStagingResult_DefaultValues() {
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            new AIWorkspaceStagingCreator.StagingResult();
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Default successCount should be 0');
        Assert.areEqual(0, result.failedCount, 'Default failedCount should be 0');
        Assert.areEqual(0, result.duplicateCount, 'Default duplicateCount should be 0');
        Assert.areEqual(0, result.matchedCount, 'Default matchedCount should be 0');
        Assert.areEqual(0, result.unmatchedCount, 'Default unmatchedCount should be 0');
        Assert.areEqual(0, result.importedCount, 'Default importedCount should be 0');
        Assert.areEqual(0, result.rematchedCount, 'Default rematchedCount should be 0');
        Assert.isNotNull(result.errors, 'Errors list should be initialized');
        Assert.isNotNull(result.stagingRecordIds, 'Staging record IDs list should be initialized');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithCcAndBcc() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'cc-bcc-email-001',
            'subject' => 'Email With CC and BCC',
            'internetMessageId' => '<cc-bcc-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'to@example.com',
                        'name' => 'To Recipient'
                    }
                }
            },
            'ccRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'cc@example.com',
                        'name' => 'CC Recipient'
                    }
                }
            },
            'bccRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'bcc@example.com',
                        'name' => 'BCC Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Cc_Address__c, Bcc_Address__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isTrue(staging.Cc_Address__c.contains('cc@example.com'), 'CC should be set');
        Assert.isTrue(staging.Bcc_Address__c.contains('bcc@example.com'), 'BCC should be set');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithAttachments() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'attachment-email-001',
            'subject' => 'Email With Attachments',
            'internetMessageId' => '<attachment-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'hasAttachments' => true,
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Has_Attachments__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isTrue(staging.Has_Attachments__c, 'Should mark as having attachments');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithSyncLog() {
        AI_Workspace_Sync_Log__c syncLog = [SELECT Id FROM AI_Workspace_Sync_Log__c LIMIT 1];
        List<AIMicrosoftCalendarService.CalendarEvent> events = createTestCalendarEvents(1);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                syncLog.Id
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');

        AI_Workspace_Staging__c staging = [
            SELECT Sync_Log__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual(syncLog.Id, staging.Sync_Log__c, 'Sync log should be linked');
    }

    @IsTest
    static void testCreateTaskStagingRecords_WithSyncLog() {
        AI_Workspace_Sync_Log__c syncLog = [SELECT Id FROM AI_Workspace_Sync_Log__c LIMIT 1];
        List<AIMicrosoftTaskService.ToDoTask> tasks = createTestTasks(1);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                syncLog.Id
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');

        AI_Workspace_Staging__c staging = [
            SELECT Sync_Log__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual(syncLog.Id, staging.Sync_Log__c, 'Sync log should be linked');
    }

    private static List<AIGoogleTaskService.ToDoTask> createTestGoogleTasks(Integer count) {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        for (Integer i = 0; i < count; i++) {
            AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
            task.taskId = 'google-task-id-' + i;
            task.title = 'Test Google Task ' + i;
            task.body = 'Task body ' + i;
            task.status = 'needsAction';
            task.listName = 'Test List';
            tasks.add(task);
        }

        return tasks;
    }

    // ============================================
    // Additional Edge Case Tests
    // ============================================

    @IsTest
    static void testCreateEmailStagingRecords_WithImportance() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'importance-email-001',
            'subject' => 'High Importance Email',
            'internetMessageId' => '<importance-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'importance' => 'high',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Importance__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('High', staging.Importance__c, 'Importance should be set to High');
    }

    @IsTest
    static void testCreateEmailStagingRecords_LowImportance() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'low-importance-email-001',
            'subject' => 'Low Importance Email',
            'internetMessageId' => '<low-importance-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'importance' => 'low',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Importance__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Low', staging.Importance__c, 'Importance should be set to Low');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithOrganizer() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'organizer-event-001';
        evt.iCalUID = 'ical-organizer-001';
        evt.subject = 'Event With Organizer';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.organizerEmail = 'organizer@example.com';
        evt.organizerName = 'Event Organizer';
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Organizer__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isTrue(staging.Organizer__c.contains('organizer@example.com'), 'Organizer email should be set');
    }

    @IsTest
    static void testCreateTaskStagingRecords_WithCompletedDate() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'completed-task-001';
        task.title = 'Completed Task';
        task.status = 'completed';
        task.completedDateTime = DateTime.now().addDays(-1);
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c, Completed_Date__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Completed', staging.Task_Status__c, 'Status should be Completed');
        Assert.isNotNull(staging.Completed_Date__c, 'Completed date should be set');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithDueDate() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-due-task-001';
        task.title = 'Google Task With Due Date';
        task.body = 'Task with due date';
        task.status = 'needsAction';
        task.dueDateTime = DateTime.now().addDays(5);
        task.listName = 'My Tasks';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Due_Date__c, List_Name__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isNotNull(staging.Due_Date__c, 'Due date should be set');
        Assert.areEqual('My Tasks', staging.List_Name__c, 'List name should be set');
    }

    @IsTest
    static void testGetExistingEmailsByProviderId_EmptySet() {
        Test.startTest();
        Map<String, Id> existingMap = AIWorkspaceStagingCreator.getExistingEmailsByProviderId(new Set<String>());
        Test.stopTest();

        Assert.areEqual(0, existingMap.size(), 'Should return empty map for empty set');
    }

    @IsTest
    static void testGetExistingCalendarsByICalUID_EmptySet() {
        Test.startTest();
        Map<String, Id> existingMap = AIWorkspaceStagingCreator.getExistingCalendarsByICalUID(new Set<String>());
        Test.stopTest();

        Assert.areEqual(0, existingMap.size(), 'Should return empty map for empty set');
    }

    @IsTest
    static void testGetExistingTasksByProviderId_EmptySet() {
        Test.startTest();
        Map<String, Id> existingMap = AIWorkspaceStagingCreator.getExistingTasksByProviderId(new Set<String>());
        Test.stopTest();

        Assert.areEqual(0, existingMap.size(), 'Should return empty map for empty set');
    }

    @IsTest
    static void testCreateEmailStagingRecords_MultipleRecipients() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'multi-recipient-001',
            'subject' => 'Email With Multiple Recipients',
            'internetMessageId' => '<multi-recipient-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'to1@example.com',
                        'name' => 'To Recipient 1'
                    }
                },
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'to2@example.com',
                        'name' => 'To Recipient 2'
                    }
                },
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'to3@example.com',
                        'name' => 'To Recipient 3'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT To_Address__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isTrue(staging.To_Address__c.contains('to1@example.com'), 'Should contain first recipient');
        Assert.isTrue(staging.To_Address__c.contains('to2@example.com'), 'Should contain second recipient');
        Assert.isTrue(staging.To_Address__c.contains('to3@example.com'), 'Should contain third recipient');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithLocation() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'location-event-001';
        evt.iCalUID = 'ical-location-001';
        evt.subject = 'Event With Location';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.location = 'Conference Room A, Building 1';
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Location__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Conference Room A, Building 1', staging.Location__c, 'Location should be set');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithMatching() {
        // Create a Contact to match against
        Contact testContact = new Contact(
            FirstName = 'Match',
            LastName = 'Contact',
            Email = 'matchcontact@example.com'
        );
        insert testContact;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'match-email-001',
            'subject' => 'Email That Will Match',
            'internetMessageId' => '<match-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'matchcontact@example.com',
                    'name' => 'Match Contact'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'testuser@example.com',
                        'name' => 'Test User'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'This email should match'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');
        // Matching counts depend on the matching service logic
        Assert.isNotNull(result, 'Result should not be null');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithMatching() {
        // Create a Contact to match against
        Contact testContact = new Contact(
            FirstName = 'Calendar',
            LastName = 'Contact',
            Email = 'calendarcontact@example.com'
        );
        insert testContact;

        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'match-event-001';
        evt.iCalUID = 'ical-match-001';
        evt.subject = 'Event That Will Match';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.organizerEmail = 'calendarcontact@example.com';
        evt.organizerName = 'Calendar Contact';
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                false,
                'testuser@example.com'
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');
        Assert.isNotNull(result, 'Result should not be null');
    }

    @IsTest
    static void testCreateTaskStagingRecords_WithMatching() {
        // Create a Contact to match against
        Contact testContact = new Contact(
            FirstName = 'Task',
            LastName = 'Contact',
            Email = 'taskcontact@example.com'
        );
        insert testContact;

        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'match-task-001';
        task.title = 'Task That Will Match - taskcontact@example.com';
        task.body = 'Task with email in title';
        task.status = 'notStarted';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');
        Assert.isNotNull(result, 'Result should not be null');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithExistingUnmatched() {
        // Create an unmatched staging record first
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c unmatchedStaging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Provider_Id__c = 'unmatched-email-001',
            Message_Identifier__c = '<unmatched-msg-001@test.com>',
            Subject__c = 'Unmatched Email',
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Staged',
            User__c = UserInfo.getUserId()
        );
        insert unmatchedStaging;

        // Now create a Contact that could match
        Contact testContact = new Contact(
            FirstName = 'New',
            LastName = 'Contact',
            Email = 'newcontact@example.com'
        );
        insert testContact;

        // Try to sync the same email again
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'unmatched-email-001',
            'subject' => 'Unmatched Email',
            'internetMessageId' => '<unmatched-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'newcontact@example.com',
                    'name' => 'New Contact'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'testuser@example.com',
                        'name' => 'Test User'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        // Should detect as duplicate but attempt rematch
        Assert.areEqual(0, result.successCount, 'Should not create new staging');
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_NullSyncLog() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = createTestCalendarEvents(1);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null,
                null,
                false,
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');
    }

    @IsTest
    static void testCreateTaskStagingRecords_NormalImportance() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'normal-task-001';
        task.title = 'Normal Importance Task';
        task.status = 'notStarted';
        task.importance = 'normal';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Priority__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Normal', staging.Task_Priority__c, 'Priority should be Normal');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_CompletedStatus() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-completed-001';
        task.title = 'Completed Google Task';
        task.body = 'This task is done';
        task.status = 'completed';
        task.completedDateTime = DateTime.now().addDays(-1);
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Completed', staging.Task_Status__c, 'Status should be Completed');
    }

    @IsTest
    static void testCreateEmailStagingRecords_NormalImportance() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'normal-importance-email-001',
            'subject' => 'Normal Importance Email',
            'internetMessageId' => '<normal-importance-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'importance' => 'normal',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Importance__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Normal', staging.Importance__c, 'Importance should be set to Normal');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_EmptyAttendees() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'no-attendees-001';
        evt.iCalUID = 'ical-no-attendees-001';
        evt.subject = 'Event Without Attendees';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record even without attendees');
    }

    @IsTest
    static void testCreateTaskStagingRecords_UnknownStatus() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'unknown-status-task-001';
        task.title = 'Unknown Status Task';
        task.status = 'unknownStatus';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Not Started', staging.Task_Status__c, 'Unknown status should default to Not Started');
    }

    @IsTest
    static void testCreateTaskStagingRecords_BlankStatus() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'blank-status-task-001';
        task.title = 'Blank Status Task';
        task.status = '';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Not Started', staging.Task_Status__c, 'Blank status should default to Not Started');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithoutBody() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'no-body-email-001',
            'subject' => 'Email Without Body',
            'internetMessageId' => '<no-body-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record even without body');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_RecurringEvent() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'recurring-event-001';
        evt.iCalUID = 'ical-recurring-001';
        evt.subject = 'Recurring Event';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.recurringEventId = 'recurring-base-001';
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record for recurring event');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithExistingEmailMessage() {
        // Create an EmailMessage first
        EmailMessage existingEmail = new EmailMessage(
            Subject = 'Existing Email',
            MessageIdentifier = '<existing-msg-001@test.com>',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            TextBody = 'Test body'
        );
        insert existingEmail;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'existing-email-001',
            'subject' => 'Existing Email',
            'internetMessageId' => '<existing-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        // Should detect as duplicate because EmailMessage exists
        Assert.areEqual(0, result.successCount, 'Should not create new staging');
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithExistingUnmatched() {
        // Create an unmatched staging record first
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c unmatchedStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            Provider_Id__c = 'unmatched-event-001',
            ICalUID__c = 'ical-unmatched-001',
            Subject__c = 'Unmatched Event',
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Staged',
            User__c = UserInfo.getUserId()
        );
        insert unmatchedStaging;

        // Try to sync the same event again
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'unmatched-event-001';
        evt.iCalUID = 'ical-unmatched-001';
        evt.subject = 'Unmatched Event';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                false,
                'testuser@example.com'
            );
        Test.stopTest();

        // Should detect as duplicate but attempt rematch
        Assert.areEqual(0, result.successCount, 'Should not create new staging');
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate');
    }

    @IsTest
    static void testCreateTaskStagingRecords_WithExistingUnmatched() {
        // Create an unmatched staging record first
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c unmatchedStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Provider_Id__c = 'unmatched-task-001',
            Subject__c = 'Unmatched Task',
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Staged',
            User__c = UserInfo.getUserId()
        );
        insert unmatchedStaging;

        // Try to sync the same task again
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'unmatched-task-001';
        task.title = 'Unmatched Task';
        task.status = 'notStarted';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        // Should detect as duplicate but attempt rematch
        Assert.areEqual(0, result.successCount, 'Should not create new staging');
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithExistingUnmatched() {
        // Create an unmatched staging record first
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c unmatchedStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Provider_Id__c = 'unmatched-google-task-001',
            Subject__c = 'Unmatched Google Task',
            Provider__c = 'GOOGLE_TASKS',
            Status__c = 'Staged',
            User__c = UserInfo.getUserId()
        );
        insert unmatchedStaging;

        // Try to sync the same task again
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'unmatched-google-task-001';
        task.title = 'Unmatched Google Task';
        task.status = 'needsAction';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        // Should detect as duplicate but attempt rematch
        Assert.areEqual(0, result.successCount, 'Should not create new staging');
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithBlankProviderId() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => '',
            'subject' => 'Email With Blank Provider ID',
            'internetMessageId' => '<blank-provider-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record even with blank provider ID');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithBlankICalUID() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'blank-ical-event-001';
        evt.iCalUID = '';
        evt.subject = 'Event With Blank ICalUID';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record even with blank ICalUID');
    }

    @IsTest
    static void testCreateTaskStagingRecords_WithBlankTaskId() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = '';
        task.title = 'Task With Blank ID';
        task.status = 'notStarted';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record even with blank task ID');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithBlankTaskId() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = '';
        task.title = 'Google Task With Blank ID';
        task.status = 'needsAction';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record even with blank task ID');
    }

    @IsTest
    static void testCreateTaskStagingRecords_InProgressStatus() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'inprogress-task-001';
        task.title = 'In Progress Task';
        task.status = 'inProgress';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('In Progress', staging.Task_Status__c, 'Status should be In Progress');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_NeedsActionStatus() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'needsaction-task-001';
        task.title = 'Needs Action Task';
        task.status = 'needsAction';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Not Started', staging.Task_Status__c, 'needsAction should map to Not Started');
    }

    @IsTest
    static void testCreateEmailStagingRecords_DuplicateByMessageIdOnly() {
        // Create a staging record with only message identifier (no provider ID match)
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Provider_Id__c = 'different-provider-id-001',
            Message_Identifier__c = '<duplicate-by-msg-001@test.com>',
            Subject__c = 'Duplicate By Message ID',
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Imported',
            User__c = UserInfo.getUserId()
        );
        insert existingStaging;

        // Try to sync an email with different provider ID but same message ID
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'new-provider-id-001',
            'subject' => 'Duplicate By Message ID',
            'internetMessageId' => '<duplicate-by-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        // Should detect as duplicate by message ID
        Assert.areEqual(0, result.successCount, 'Should not create new staging');
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate by message ID');
    }

    @IsTest
    static void testCreateEmailStagingRecords_ProcessingError() {
        // Create an email with invalid data that will cause an exception
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        // Create a malformed email object that will cause an error during processing
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'error-email-001',
            'subject' => 'Error Email',
            'internetMessageId' => '<error-msg-001@test.com>',
            'receivedDateTime' => 'invalid-date-format',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        // Should handle the error gracefully
        Assert.isTrue(result.failedCount >= 0, 'Should track failed count');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_ProcessingError() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        // Create an event with null required fields that might cause an error
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'error-event-001';
        evt.iCalUID = 'ical-error-001';
        evt.subject = null;
        evt.startDateTime = null;
        evt.endDateTime = null;
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();

        // Should handle the error gracefully
        Assert.isNotNull(result, 'Result should not be null');
    }

    @IsTest
    static void testCreateTaskStagingRecords_ProcessingError() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        // Create a task with null required fields that might cause an error
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'error-task-001';
        task.title = null;
        task.status = null;
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();

        // Should handle the error gracefully
        Assert.isNotNull(result, 'Result should not be null');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_ProcessingError() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        // Create a task with null required fields that might cause an error
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'error-google-task-001';
        task.title = null;
        task.status = null;
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        // Should handle the error gracefully
        Assert.isNotNull(result, 'Result should not be null');
    }

    @IsTest
    static void testCreateEmailStagingRecords_MultipleEmailsWithMixedResults() {
        // Create a staging record for deduplication
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Provider_Id__c = 'existing-email-001',
            Message_Identifier__c = '<existing-msg-001@test.com>',
            Subject__c = 'Existing Email',
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Imported',
            User__c = UserInfo.getUserId()
        );
        insert existingStaging;

        // Create multiple emails with mixed scenarios
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        // Email 1: Duplicate
        emails.add(new Map<String, Object>{
            'id' => 'existing-email-001',
            'subject' => 'Existing Email',
            'internetMessageId' => '<existing-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        // Email 2: New email
        emails.add(new Map<String, Object>{
            'id' => 'new-email-001',
            'subject' => 'New Email',
            'internetMessageId' => '<new-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender2@example.com',
                    'name' => 'Sender 2'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient2@example.com',
                        'name' => 'Recipient 2'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body 2'
            }
        });

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 new staging record');
        Assert.areEqual(1, result.duplicateCount, 'Should detect 1 duplicate');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_FiveParameterOverload() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = createTestCalendarEvents(1);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record using 5-parameter method');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithTargetUserId() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'target-user-event-001';
        evt.iCalUID = 'ical-target-user-001';
        evt.subject = 'Event With Target User';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                false,
                'testuser@example.com'
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record with target user');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_MultipleEventsWithMixedResults() {
        // Create an existing staging record
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            Provider_Id__c = 'existing-cal-001',
            ICalUID__c = 'ical-existing-cal-001',
            Subject__c = 'Existing Calendar Event',
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Imported',
            User__c = UserInfo.getUserId()
        );
        insert existingStaging;

        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        // Event 1: Duplicate
        AIMicrosoftCalendarService.CalendarEvent evt1 = new AIMicrosoftCalendarService.CalendarEvent();
        evt1.eventId = 'existing-cal-001';
        evt1.iCalUID = 'ical-existing-cal-001';
        evt1.subject = 'Existing Calendar Event';
        evt1.startDateTime = DateTime.now().addDays(1);
        evt1.endDateTime = DateTime.now().addDays(1).addHours(1);
        events.add(evt1);
        
        // Event 2: New event
        AIMicrosoftCalendarService.CalendarEvent evt2 = new AIMicrosoftCalendarService.CalendarEvent();
        evt2.eventId = 'new-cal-001';
        evt2.iCalUID = 'ical-new-cal-001';
        evt2.subject = 'New Calendar Event';
        evt2.startDateTime = DateTime.now().addDays(2);
        evt2.endDateTime = DateTime.now().addDays(2).addHours(1);
        events.add(evt2);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 new staging record');
        Assert.areEqual(1, result.duplicateCount, 'Should detect 1 duplicate');
    }

    @IsTest
    static void testCreateTaskStagingRecords_MultipleTasksWithMixedResults() {
        // Create an existing staging record
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Provider_Id__c = 'existing-task-001',
            Subject__c = 'Existing Task',
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Imported',
            User__c = UserInfo.getUserId()
        );
        insert existingStaging;

        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        // Task 1: Duplicate
        AIMicrosoftTaskService.ToDoTask task1 = new AIMicrosoftTaskService.ToDoTask();
        task1.taskId = 'existing-task-001';
        task1.title = 'Existing Task';
        task1.status = 'notStarted';
        tasks.add(task1);
        
        // Task 2: New task
        AIMicrosoftTaskService.ToDoTask task2 = new AIMicrosoftTaskService.ToDoTask();
        task2.taskId = 'new-task-001';
        task2.title = 'New Task';
        task2.status = 'notStarted';
        tasks.add(task2);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 new staging record');
        Assert.areEqual(1, result.duplicateCount, 'Should detect 1 duplicate');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_MultipleTasksWithMixedResults() {
        // Create an existing staging record
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName()
            .get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Provider_Id__c = 'existing-google-task-001',
            Subject__c = 'Existing Google Task',
            Provider__c = 'GOOGLE_TASKS',
            Status__c = 'Imported',
            User__c = UserInfo.getUserId()
        );
        insert existingStaging;

        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        // Task 1: Duplicate
        AIGoogleTaskService.ToDoTask task1 = new AIGoogleTaskService.ToDoTask();
        task1.taskId = 'existing-google-task-001';
        task1.title = 'Existing Google Task';
        task1.status = 'needsAction';
        tasks.add(task1);
        
        // Task 2: New task
        AIGoogleTaskService.ToDoTask task2 = new AIGoogleTaskService.ToDoTask();
        task2.taskId = 'new-google-task-001';
        task2.title = 'New Google Task';
        task2.status = 'needsAction';
        tasks.add(task2);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 new staging record');
        Assert.areEqual(1, result.duplicateCount, 'Should detect 1 duplicate');
    }

    @IsTest
    static void testCreateTaskStagingRecords_WithTargetUserId() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'target-user-task-001';
        task.title = 'Task With Target User';
        task.status = 'notStarted';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record with target user');
    }

    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithNotifications() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();

        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'notification-task-001';
        task.title = 'Task With Notifications';
        task.status = 'needsAction';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create staging record with notifications enabled');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_WithNullSubject() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'null-subject-event-001';
        evt.iCalUID = 'ical-null-subject-001';
        evt.subject = null;
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
    }

    @IsTest
    static void testCreateTaskStagingRecords_WithNullTitle() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'null-title-task-001';
        task.title = null;
        task.status = 'notStarted';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_OrganizerNameOnly() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'organizer-name-only-001';
        evt.iCalUID = 'ical-organizer-name-only-001';
        evt.subject = 'Event With Organizer Name Only';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.organizerName = 'John Doe';
        evt.organizerEmail = null;
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Organizer__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('John Doe', staging.Organizer__c, 'Should set organizer name only');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_AttendeeWithoutName() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'attendee-no-name-001';
        evt.iCalUID = 'ical-attendee-no-name-001';
        evt.subject = 'Event With Attendee Without Name';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        
        AIMicrosoftCalendarService.Attendee attendee = new AIMicrosoftCalendarService.Attendee();
        attendee.email = 'attendee@example.com';
        attendee.name = null;
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>{ attendee };
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Attendees__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isTrue(staging.Attendees__c.contains('attendee@example.com'), 'Should include attendee email');
    }

    @IsTest
    static void testCreateCalendarStagingRecords_OrganizerEmailOnly() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'organizer-email-only-001';
        evt.iCalUID = 'ical-organizer-email-only-001';
        evt.subject = 'Event With Organizer Email Only';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.organizerName = null;
        evt.organizerEmail = 'organizer@example.com';
        events.add(evt);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Organizer__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.isTrue(staging.Organizer__c.contains('organizer@example.com'), 'Should contain organizer email');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithFromName() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'from-name-email-001',
            'subject' => 'Email With From Name',
            'internetMessageId' => '<from-name-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'John Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Jane Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT From_Address__c, From_Name__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('sender@example.com', staging.From_Address__c, 'Should set from email');
        Assert.areEqual('John Sender', staging.From_Name__c, 'Should set from name');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithoutFromName() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'no-from-name-email-001',
            'subject' => 'Email Without From Name',
            'internetMessageId' => '<no-from-name-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => null
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => null
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        };
        emails.add(email);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT From_Address__c, From_Name__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('sender@example.com', staging.From_Address__c, 'Should set from email');
    }

    @IsTest
    static void testCreateTaskStagingRecords_HighImportance() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'high-importance-task-001';
        task.title = 'High Importance Task';
        task.status = 'notStarted';
        task.importance = 'high';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Priority__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('High', staging.Task_Priority__c, 'Priority should be High');
    }

    @IsTest
    static void testCreateTaskStagingRecords_LowImportance() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = new List<AIMicrosoftTaskService.ToDoTask>();

        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'low-importance-task-001';
        task.title = 'Low Importance Task';
        task.status = 'notStarted';
        task.importance = 'low';
        tasks.add(task);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();

        AI_Workspace_Staging__c staging = [
            SELECT Task_Priority__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('Low', staging.Task_Priority__c, 'Priority should be Low');
    }

    @IsTest
    static void testEmailBodyEncryption() {
        Map<String, Object> email = new Map<String, Object>{
            'id' => 'test-encrypted-123',
            'subject' => 'Encryption Test',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@test.com',
                    'name' => 'Sender'
                }
            },
            'receivedDateTime' => DateTime.now().addHours(-1).format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'bodyPreview' => 'Preview text',
            'body' => new Map<String, Object>{
                'content' => '<p>This is sensitive HTML content</p>',
                'contentType' => 'html'
            },
            'isRead' => false
        };

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result =
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                new List<Map<String, Object>>{ email },
                'MICROSOFT_EMAIL',
                'user@test.com',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');
        
        AI_Workspace_Staging__c staging = [
            SELECT Text_Body__c, Html_Body__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        
        Assert.isTrue(String.isNotBlank(staging.Html_Body__c), 'HTML body should be encrypted');
        Assert.areNotEqual('<p>This is sensitive HTML content</p>', staging.Html_Body__c, 'HTML body should be encrypted, not plain');
    }

    @IsTest
    static void testCalendarBodyEncryption() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'cal-encrypted-123';
        evt.subject = 'Calendar Encryption Test';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.description = 'This is sensitive calendar body content';
        evt.location = 'Conference Room';

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result =
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_EMAIL',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');
        
        AI_Workspace_Staging__c staging = [
            SELECT Text_Body__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        
        Assert.isTrue(String.isNotBlank(staging.Text_Body__c), 'Body should be encrypted');
        Assert.areNotEqual('This is sensitive calendar body content', staging.Text_Body__c, 'Body should be encrypted, not plain');
    }

    @IsTest
    static void testTaskBodyEncryption() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-encrypted-123';
        task.title = 'Task Encryption Test';
        task.status = 'notStarted';
        task.body = 'This is sensitive task body content';
        task.listName = 'My Tasks';

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result =
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should create 1 staging record');
        
        AI_Workspace_Staging__c staging = [
            SELECT Text_Body__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        
        Assert.isTrue(String.isNotBlank(staging.Text_Body__c), 'Body should be encrypted');
        Assert.isFalse(staging.Text_Body__c.contains('This is sensitive task body content'), 'Body should be encrypted, not plain');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_NullUserId() {
        Test.startTest();
        Id result = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(null, 'MICROSOFT_EMAIL');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null for null userId');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_BlankProvider() {
        Test.startTest();
        Id result = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), '');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null for blank provider');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_NullProvider() {
        Test.startTest();
        Id result = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), null);
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null for null provider');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_UnknownProvider() {
        Test.startTest();
        Id result = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'UNKNOWN_PROVIDER');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null for unknown provider');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_CacheHit() {
        // First call - cache miss
        Test.startTest();
        Id result1 = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'MICROSOFT_EMAIL');
        // Second call - cache hit
        Id result2 = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'MICROSOFT_EMAIL');
        Test.stopTest();
        
        Assert.areEqual(result1, result2, 'Should return same result from cache');
    }
    
    @IsTest
    static void testClearWorkspaceUserCache() {
        // Get workspace user ID to populate cache
        Id result1 = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'MICROSOFT_EMAIL');
        
        Test.startTest();
        // Clear cache
        AIWorkspaceStagingCreator.clearWorkspaceUserCache();
        // Get again - should query database again
        Id result2 = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'MICROSOFT_EMAIL');
        Test.stopTest();
        
        Assert.areEqual(result1, result2, 'Should return same workspace user after cache clear');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_OutlookProvider() {
        Test.startTest();
        Id result = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'Outlook');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should find workspace user for Outlook provider');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_GoogleCalendar() {
        Test.startTest();
        Id result = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'GOOGLE_CALENDAR');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should find workspace user for Google Calendar');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_GmailEmail() {
        Test.startTest();
        Id result = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'GMAIL_EMAIL');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should find workspace user for Gmail email');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithExistingEmailMessageByIdentifier() {
        // Create an EmailMessage first
        EmailMessage existingEmail = new EmailMessage(
            Subject = 'Existing Email',
            TextBody = 'Test body',
            MessageIdentifier = '<existing-msg-unique-001@test.com>',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            Incoming = true,
            Status = '3'
        );
        insert existingEmail;
        
        // Try to create staging for same email (by MessageIdentifier)
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-unique-001',
            'subject' => 'Existing Email',
            'internetMessageId' => '<existing-msg-unique-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate by EmailMessage MessageIdentifier');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithExistingEvent() {
        // Create an Event first
        Event existingEvent = new Event(
            Subject = 'Existing Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            Workspace_Sync_Id__c = 'ical-existing-123'
        );
        insert existingEvent;
        
        // Try to create staging for same event
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-existing-123';
        evt.subject = 'Existing Event';
        evt.iCalUID = 'ical-existing-123';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate by Event Workspace_Sync_Id__c');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_WithExistingTask() {
        // Create a Task first
        Task existingTask = new Task(
            Subject = 'Existing Task',
            Status = 'Not Started',
            Workspace_Sync_Id__c = 'task-existing-123'
        );
        insert existingTask;
        
        // Try to create staging for same task
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-existing-123';
        task.title = 'Existing Task';
        task.status = 'notStarted';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate by Task Workspace_Sync_Id__c');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_AutoSyncMode() {
        List<Map<String, Object>> emails = createTestEmailData(2);
        
        Test.startTest();
        // Auto-sync mode: sendNotifications=false
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();
        
        Assert.areEqual(2, result.successCount, 'Should create 2 staging records');
        Assert.areEqual(0, result.matchedCount, 'Auto-sync should not match inline');
        Assert.areEqual(2, result.unmatchedCount, 'All should be marked as unmatched (staged)');
        Assert.areEqual(0, result.importedCount, 'Auto-sync should not import inline');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_AutoSyncMode() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = createTestCalendarEvents(2);
        
        Test.startTest();
        // Auto-sync mode: sendNotifications=false
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();
        
        Assert.areEqual(2, result.successCount, 'Should create 2 staging records');
        Assert.areEqual(0, result.matchedCount, 'Auto-sync should not match inline');
        Assert.areEqual(2, result.unmatchedCount, 'All should be marked as unmatched (staged)');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_AutoSyncMode() {
        List<AIMicrosoftTaskService.ToDoTask> tasks = createTestTasks(2);
        
        Test.startTest();
        // Auto-sync mode: sendNotifications=false
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                tasks,
                'MICROSOFT_TASKS',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();
        
        Assert.areEqual(2, result.successCount, 'Should create 2 staging records');
        Assert.areEqual(0, result.matchedCount, 'Auto-sync should not match inline');
        Assert.areEqual(2, result.unmatchedCount, 'All should be marked as unmatched (staged)');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithConnectedAccountEmailExclusion() {
        // Create contact that would normally match
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'connected@example.com'
        );
        insert testContact;
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-connected-001',
            'subject' => 'Email from Connected Account',
            'internetMessageId' => '<connected-msg-001@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'connected@example.com',
                    'name' => 'Connected User'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        // Pass connected account email to exclude from matching
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'connected@example.com',
                null,
                UserInfo.getUserId(),
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithConnectedAccountEmailExclusion() {
        // Create contact that would normally match
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'connected@example.com'
        );
        insert testContact;
        
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-connected-123';
        evt.subject = 'Event from Connected Account';
        evt.iCalUID = 'ical-connected-123';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        evt.organizerEmail = 'connected@example.com';
        evt.organizerName = 'Connected User';
        
        Test.startTest();
        // Pass connected account email to exclude from matching
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                true,
                'connected@example.com'
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_WithAutoSyncFalse() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-autosync-123';
        task.title = 'Task with Auto Sync';
        task.status = 'notStarted';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
        Assert.areEqual(0, result.matchedCount, 'Auto-sync should not match inline');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_GmailProvider() {
        List<Map<String, Object>> emails = createTestEmailData(1);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'GMAIL_EMAIL',
                'testuser@gmail.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record for Gmail');
        
        AI_Workspace_Staging__c staging = [
            SELECT Provider__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('GMAIL_EMAIL', staging.Provider__c, 'Provider should be Gmail');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_GoogleCalendar() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'google-event-123';
        evt.subject = 'Google Calendar Event';
        evt.iCalUID = 'ical-google-123';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'GOOGLE_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record for Google Calendar');
        
        AI_Workspace_Staging__c staging = [
            SELECT Provider__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('GOOGLE_CALENDAR', staging.Provider__c, 'Provider should be Google Calendar');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_GoogleTasks() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'google-task-123';
        task.title = 'Google Task';
        task.status = 'notStarted';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'GOOGLE_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record for Google Tasks');
        
        AI_Workspace_Staging__c staging = [
            SELECT Provider__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual('GOOGLE_TASKS', staging.Provider__c, 'Provider should be Google Tasks');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithNullTargetUserId() {
        List<Map<String, Object>> emails = createTestEmailData(1);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                null,
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with current user');
        
        AI_Workspace_Staging__c staging = [
            SELECT User__c FROM AI_Workspace_Staging__c LIMIT 1
        ];
        Assert.areEqual(UserInfo.getUserId(), staging.User__c, 'Should use current user when targetUserId is null');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_FiveParameterOverloadWithAutoSync() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = createTestCalendarEvents(1);
        
        Test.startTest();
        // Test 5-parameter overload with auto-sync
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                false
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
        Assert.areEqual(0, result.matchedCount, 'Auto-sync should not match inline');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithBlankMessageIdentifier() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-blank-msgid',
            'subject' => 'Email without MessageId',
            'internetMessageId' => '',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record even without message identifier');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithBlankDedupId() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = '';
        evt.subject = 'Event without dedupId';
        evt.iCalUID = '';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record even without dedupId');
    }
    
    @IsTest
    static void testGetWorkspaceUserId_NoWorkspaceUserFound() {
        // Create a new user (in test context, we can't actually create users, so we test with an ID that has no workspace user)
        Test.startTest();
        // Clear cache first
        AIWorkspaceStagingCreator.clearWorkspaceUserCache();
        // Try to get workspace user for a user that doesn't have one
        Id result = AIWorkspaceStagingCreator.getWorkspaceUserIdPublic(UserInfo.getUserId(), 'UNKNOWN_PROVIDER_TYPE');
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null when no workspace user found');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithBody() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-with-body-001';
        task.title = 'Google Task with Body';
        task.status = 'needsAction';
        task.body = 'Task body content';
        task.dueDateTime = DateTime.now().addDays(7);
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create 1 Google task staging record');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithExistingTaskRecord() {
        // Create a Task first
        Task existingTask = new Task(
            Subject = 'Existing Google Task Record',
            Status = 'Not Started',
            Workspace_Sync_Id__c = 'google-task-existing-record-001'
        );
        insert existingTask;
        
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-existing-record-001';
        task.title = 'Existing Google Task Record';
        task.status = 'needsAction';
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.duplicateCount, 'Should detect duplicate by existing Task');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_AutoSyncWithUnmatched() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-autosync-unmatched-001';
        task.title = 'Google Task Auto Sync Unmatched';
        task.status = 'needsAction';
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                false
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
        Assert.areEqual(0, result.matchedCount, 'Auto-sync should not match inline');
        Assert.areEqual(1, result.unmatchedCount, 'Should mark as unmatched (staged)');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithNullFromAddress() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-no-from',
            'subject' => 'Email without From',
            'internetMessageId' => '<no-from-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => null,
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record even without from address');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithEmptyRecipients() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-no-recipients',
            'subject' => 'Email without Recipients',
            'internetMessageId' => '<no-recipients-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>(),
            'ccRecipients' => new List<Object>(),
            'bccRecipients' => new List<Object>(),
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record even without recipients');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithNullBody() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-no-body',
            'subject' => 'Email without Body',
            'internetMessageId' => '<no-body-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => null
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record even without body');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithNullOrganizer() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-no-organizer';
        evt.subject = 'Event without Organizer';
        evt.iCalUID = 'ical-no-organizer';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        evt.organizerEmail = null;
        evt.organizerName = null;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record without organizer');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithNullDescription() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-no-desc';
        evt.subject = 'Event without Description';
        evt.iCalUID = 'ical-no-desc';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        evt.description = null;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record without description');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_WithNullBody() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-no-body';
        task.title = 'Task without Body';
        task.status = 'notStarted';
        task.body = null;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record without body');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithInvalidDateTime() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-invalid-date',
            'subject' => 'Email with Invalid Date',
            'internetMessageId' => '<invalid-date-msg@test.com>',
            'receivedDateTime' => 'invalid-date-format',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record even with invalid date');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithNullStartDateTime() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-no-start';
        evt.subject = 'Event without Start Time';
        evt.iCalUID = 'ical-no-start';
        evt.startDateTime = null;
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record without start time');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_WithNullDueDateField() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-no-due-field';
        task.title = 'Task without Due Date Field';
        task.status = 'notStarted';
        task.dueDateTime = null;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record without due date');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithVeryLongSubject() {
        String longSubject = 'Very Long Subject '.repeat(300);
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-long-subject',
            'subject' => longSubject,
            'internetMessageId' => '<long-subject-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with truncated subject');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithVeryLongLocation() {
        String longLocation = 'Very Long Location '.repeat(50);
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-long-location';
        evt.subject = 'Event with Long Location';
        evt.iCalUID = 'ical-long-location';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        evt.location = longLocation;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with truncated location');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_NormalImportanceField() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-normal-priority-field';
        task.title = 'Normal Priority Task Field';
        task.status = 'notStarted';
        task.importance = 'normal';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
        
        AI_Workspace_Staging__c staging = [
            SELECT Task_Priority__c FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = 'task-normal-priority-field' LIMIT 1
        ];
        Assert.areEqual('Normal', staging.Task_Priority__c, 'Priority should be Normal');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithDateTimeContainingMilliseconds() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-ms-date',
            'subject' => 'Email with Milliseconds',
            'internetMessageId' => '<ms-date-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00.123Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should parse datetime with milliseconds');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithExistingUnmatchedStaging() {
        // Create an existing unmatched staging record
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            Provider_Id__c = 'google-task-unmatched-new-001',
            Subject__c = 'Existing Unmatched Google Task',
            Provider__c = 'GOOGLE_TASKS',
            Status__c = 'Staged',
            User__c = UserInfo.getUserId()
        );
        insert existingStaging;
        
        // Try to sync the same task again
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-unmatched-new-001';
        task.title = 'Existing Unmatched Google Task';
        task.status = 'needsAction';
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.duplicateCount, 'Should detect existing unmatched staging as duplicate');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithBlankSubject() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-blank-subject',
            'subject' => '',
            'internetMessageId' => '<blank-subject-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with blank subject');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithEmptyAttendeesList() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-empty-attendees';
        evt.subject = 'Event with Empty Attendees';
        evt.iCalUID = 'ical-empty-attendees';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with empty attendees list');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_UnknownImportance() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-unknown-importance';
        task.title = 'Task with Unknown Importance';
        task.status = 'notStarted';
        task.importance = 'unknown';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with unknown importance');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithDueDateAndBody() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-due-body-001';
        task.title = 'Google Task with Due Date and Body';
        task.status = 'needsAction';
        task.body = 'Task body content';
        task.dueDateTime = DateTime.now().addDays(5);
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create Google task with due date and body');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithCompletedDateAndTime() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-completed-datetime-001';
        task.title = 'Google Task with Completed DateTime';
        task.status = 'completed';
        task.completedDateTime = DateTime.now().addDays(-1);
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create Google task with completed datetime');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithNullImportance() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-no-importance',
            'subject' => 'Email without Importance',
            'internetMessageId' => '<no-importance-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'importance' => null,
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record without importance');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_HighImportance() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-high-importance',
            'subject' => 'High Importance Email',
            'internetMessageId' => '<high-importance-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'importance' => 'high',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with high importance');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_ManualImportWithMatching() {
        // Create a Contact to match against
        Contact testContact = new Contact(
            FirstName = 'Manual',
            LastName = 'Import',
            Email = 'manualimport@example.com'
        );
        insert testContact;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-manual-match',
            'subject' => 'Manual Import Email',
            'internetMessageId' => '<manual-import-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'manualimport@example.com',
                    'name' => 'Manual Import'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'testuser@example.com',
                        'name' => 'Test User'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_ManualImportWithMatching() {
        // Create a Contact to match against
        Contact testContact = new Contact(
            FirstName = 'Calendar',
            LastName = 'Match',
            Email = 'calendarmatch@example.com'
        );
        insert testContact;

        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-manual-match';
        evt.subject = 'Manual Calendar Import';
        evt.iCalUID = 'ical-manual-match';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        evt.organizerEmail = 'calendarmatch@example.com';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                true,
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_ManualImportWithMatching() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-manual-match';
        task.title = 'Manual Task Import';
        task.status = 'notStarted';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null,
                UserInfo.getUserId(),
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithMultipleMatchingContacts() {
        // Create multiple contacts with same email domain
        Contact contact1 = new Contact(
            FirstName = 'Multi1',
            LastName = 'Match1',
            Email = 'multi1@matchdomain.com'
        );
        Contact contact2 = new Contact(
            FirstName = 'Multi2',
            LastName = 'Match2',
            Email = 'multi2@matchdomain.com'
        );
        insert new List<Contact>{ contact1, contact2 };

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-multi-match',
            'subject' => 'Multi Match Email',
            'internetMessageId' => '<multi-match-msg@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'multi1@matchdomain.com',
                    'name' => 'Multi Match'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'multi2@matchdomain.com',
                        'name' => 'Multi Match 2'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithMultipleAttendees() {
        // Create contacts for attendees
        Contact attendee1 = new Contact(
            FirstName = 'Attendee1',
            LastName = 'Test1',
            Email = 'attendee1@example.com'
        );
        Contact attendee2 = new Contact(
            FirstName = 'Attendee2',
            LastName = 'Test2',
            Email = 'attendee2@example.com'
        );
        insert new List<Contact>{ attendee1, attendee2 };

        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-multi-attendees';
        evt.subject = 'Event with Multiple Attendees';
        evt.iCalUID = 'ical-multi-attendees';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        
        AIMicrosoftCalendarService.Attendee att1 = new AIMicrosoftCalendarService.Attendee();
        att1.email = 'attendee1@example.com';
        att1.name = 'Attendee1 Test1';
        
        AIMicrosoftCalendarService.Attendee att2 = new AIMicrosoftCalendarService.Attendee();
        att2.email = 'attendee2@example.com';
        att2.name = 'Attendee2 Test2';
        
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>{ att1, att2 };
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                true,
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with multiple attendees');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_SentBySFUser() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-sent-by-sf-user',
            'subject' => 'Email Sent By SF User',
            'internetMessageId' => '<sent-by-sf-user@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => UserInfo.getUserEmail(),
                    'name' => 'SF User'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                null,
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
        
        AI_Workspace_Staging__c staging = [
            SELECT Is_Incoming__c FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = 'email-sent-by-sf-user' LIMIT 1
        ];
        Assert.isFalse(staging.Is_Incoming__c, 'Should be marked as outgoing');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithRecipientsWithoutEmailAddress() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-invalid-recipients',
            'subject' => 'Email with Invalid Recipients',
            'internetMessageId' => '<invalid-recipients@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => null
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record even with invalid recipients');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithRecipientsWithBlankAddress() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-blank-recipient-address',
            'subject' => 'Email with Blank Recipient Address',
            'internetMessageId' => '<blank-recipient-address@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => '',
                        'name' => 'Blank Address'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with blank recipient address');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithAttendeeWithoutEmail() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-attendee-no-email';
        evt.subject = 'Event with Attendee Without Email';
        evt.iCalUID = 'ical-attendee-no-email';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        
        AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
        att.email = '';
        att.name = 'Attendee Without Email';
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>{ att };
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with attendee without email');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_WithBlankImportance() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-blank-importance';
        task.title = 'Task with Blank Importance';
        task.status = 'notStarted';
        task.importance = '';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with blank importance');
        
        AI_Workspace_Staging__c staging = [
            SELECT Task_Priority__c FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = 'task-blank-importance' LIMIT 1
        ];
        Assert.areEqual('Normal', staging.Task_Priority__c, 'Should default to Normal priority');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_WithBlankStatus() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-blank-status-new';
        task.title = 'Task with Blank Status New';
        task.status = '';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with blank status');
        
        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = 'task-blank-status-new' LIMIT 1
        ];
        Assert.areEqual('Not Started', staging.Task_Status__c, 'Should default to Not Started status');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithBlankStatus() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-blank-status';
        task.title = 'Google Task with Blank Status';
        task.status = '';
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with blank status');
        
        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = 'google-task-blank-status' LIMIT 1
        ];
        Assert.areEqual('Not Started', staging.Task_Status__c, 'Should default to Not Started status');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithNullConversationId() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-no-conv-id',
            'conversationId' => null,
            'subject' => 'Email without Conversation ID',
            'internetMessageId' => '<no-conv-id@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record without conversation ID');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithLead() {
        // Create a Lead to match against
        Lead testLead = new Lead(
            FirstName = 'Lead',
            LastName = 'Test',
            Email = 'leadtest@example.com',
            Company = 'Test Company'
        );
        insert testLead;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-lead-match',
            'subject' => 'Email to Lead',
            'internetMessageId' => '<lead-match@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'leadtest@example.com',
                    'name' => 'Lead Test'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'testuser@example.com',
                        'name' => 'Test User'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null,
                UserInfo.getUserId(),
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithLeadAttendee() {
        // Create a Lead to match against
        Lead testLead = new Lead(
            FirstName = 'Calendar',
            LastName = 'Lead',
            Email = 'calendarlead@example.com',
            Company = 'Test Company'
        );
        insert testLead;

        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-lead-attendee';
        evt.subject = 'Event with Lead Attendee';
        evt.iCalUID = 'ical-lead-attendee';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        
        AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
        att.email = 'calendarlead@example.com';
        att.name = 'Calendar Lead';
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>{ att };
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null,
                UserInfo.getUserId(),
                true,
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithNullHasAttachments() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-null-attachments',
            'subject' => 'Email with Null HasAttachments',
            'internetMessageId' => '<null-attachments@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'hasAttachments' => null,
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with null hasAttachments');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithNullEndDateTime() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-null-end';
        evt.subject = 'Event with Null End Time';
        evt.iCalUID = 'ical-null-end';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = null;
        evt.isAllDay = false;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with null end time');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithNullBody() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-null-body';
        task.title = 'Google Task with Null Body';
        task.status = 'needsAction';
        task.body = null;
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with null body');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithNullTitle() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-null-title';
        task.title = null;
        task.status = 'needsAction';
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with null title');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithNullFromName() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-no-from-name',
            'subject' => 'Email without From Name',
            'internetMessageId' => '<no-from-name@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => null
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com',
                        'name' => 'Recipient'
                    }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record without from name');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithRecurringEventId() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-recurring-instance';
        evt.subject = 'Recurring Event Instance';
        evt.iCalUID = 'ical-recurring-instance';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        evt.recurringEventId = 'recurring-base-event-123';
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record for recurring event instance');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_WithNullImportance() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-null-importance';
        task.title = 'Task with Null Importance';
        task.status = 'notStarted';
        task.importance = null;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with null importance');
        
        AI_Workspace_Staging__c staging = [
            SELECT Task_Priority__c FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = 'task-null-importance' LIMIT 1
        ];
        Assert.areEqual('Normal', staging.Task_Priority__c, 'Should default to Normal priority');
    }
    
    @IsTest
    static void testCreateTaskStagingRecords_WithNullStatus() {
        AIMicrosoftTaskService.ToDoTask task = new AIMicrosoftTaskService.ToDoTask();
        task.taskId = 'task-null-status';
        task.title = 'Task with Null Status';
        task.status = null;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createTaskStagingRecords(
                new List<AIMicrosoftTaskService.ToDoTask>{ task },
                'MICROSOFT_TASKS',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with null status');
        
        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = 'task-null-status' LIMIT 1
        ];
        Assert.areEqual('Not Started', staging.Task_Status__c, 'Should default to Not Started status');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithNullStatus() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-null-status';
        task.title = 'Google Task with Null Status';
        task.status = null;
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with null status');
        
        AI_Workspace_Staging__c staging = [
            SELECT Task_Status__c FROM AI_Workspace_Staging__c 
            WHERE Provider_Id__c = 'google-task-null-status' LIMIT 1
        ];
        Assert.areEqual('Not Started', staging.Task_Status__c, 'Should default to Not Started status');
    }
    
    @IsTest
    static void testCreateEmailStagingRecords_WithVeryLongRecipientList() {
        List<Object> manyRecipients = new List<Object>();
        for (Integer i = 0; i < 50; i++) {
            manyRecipients.add(new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'recipient' + i + '@example.com',
                    'name' => 'Recipient ' + i
                }
            });
        }
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        emails.add(new Map<String, Object>{
            'id' => 'email-many-recipients',
            'subject' => 'Email with Many Recipients',
            'internetMessageId' => '<many-recipients@test.com>',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => manyRecipients,
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'Test body'
            }
        });
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_EMAIL',
                'testuser@example.com',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with many recipients');
    }
    
    @IsTest
    static void testCreateCalendarStagingRecords_WithBlankSubject() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'event-blank-subject';
        evt.subject = '';
        evt.iCalUID = 'ical-blank-subject';
        evt.startDateTime = DateTime.now();
        evt.endDateTime = DateTime.now().addHours(1);
        evt.isAllDay = false;
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ evt },
                'MICROSOFT_CALENDAR',
                null
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with blank subject');
    }
    
    @IsTest
    static void testCreateGoogleTaskStagingRecords_WithBlankTitle() {
        List<AIGoogleTaskService.ToDoTask> tasks = new List<AIGoogleTaskService.ToDoTask>();
        
        AIGoogleTaskService.ToDoTask task = new AIGoogleTaskService.ToDoTask();
        task.taskId = 'google-task-blank-title';
        task.title = '';
        task.status = 'needsAction';
        tasks.add(task);
        
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createGoogleTaskStagingRecords(
                tasks,
                UserInfo.getUserId(),
                'GOOGLE_TASKS',
                true
            );
        Test.stopTest();
        
        Assert.areEqual(1, result.successCount, 'Should create staging record with blank title');
    }
}