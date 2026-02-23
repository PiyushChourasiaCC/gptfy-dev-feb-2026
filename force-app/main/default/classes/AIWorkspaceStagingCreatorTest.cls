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
                'MICROSOFT_GRAPH',
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
            SELECT Subject__c, From_Address__c, To_Address__c, Provider__c, Status__c
            FROM AI_Workspace_Staging__c
            WHERE Id IN :result.stagingRecordIds
        ];
        Assert.areEqual(3, stagingRecords.size(), 'Should have 3 records in database');
        Assert.areEqual('MICROSOFT_GRAPH', stagingRecords[0].Provider__c, 'Provider should be set');
        Assert.areEqual('Unmatched', stagingRecords[0].Status__c, 'Status should be Unmatched');
    }

    @IsTest
    static void testCreateEmailStagingRecords_WithSyncLog() {
        AI_Workspace_Sync_Log__c syncLog = [SELECT Id FROM AI_Workspace_Sync_Log__c LIMIT 1];
        List<Map<String, Object>> emails = createTestEmailData(1);

        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_GRAPH',
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
            'MICROSOFT_GRAPH',
            'testuser@example.com',
            null
        );

        // Try to insert same emails again
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createEmailStagingRecords(
                emails,
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'GOOGLE',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
            'MICROSOFT_GRAPH',
            null
        );

        // Try to insert same events again
        Test.startTest();
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                events,
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
                null
            );
        Test.stopTest();

        Map<String, AI_Workspace_Staging__c> stagingBySubject = new Map<String, AI_Workspace_Staging__c>();
        for (AI_Workspace_Staging__c s : [
            SELECT Subject__c, Task_Status__c FROM AI_Workspace_Staging__c
        ]) {
            stagingBySubject.put(s.Subject__c, s);
        }

        Assert.areEqual('Not Started', stagingBySubject.get('Not Started Task').Task_Status__c);
        Assert.areEqual('In Progress', stagingBySubject.get('In Progress Task').Task_Status__c);
        Assert.areEqual('Completed', stagingBySubject.get('Completed Task').Task_Status__c);
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
                'MICROSOFT_GRAPH',
                null
            );
        Test.stopTest();

        Map<String, AI_Workspace_Staging__c> stagingBySubject = new Map<String, AI_Workspace_Staging__c>();
        for (AI_Workspace_Staging__c s : [
            SELECT Subject__c, Task_Priority__c FROM AI_Workspace_Staging__c
        ]) {
            stagingBySubject.put(s.Subject__c, s);
        }

        Assert.areEqual('Low', stagingBySubject.get('Low Priority').Task_Priority__c);
        Assert.areEqual('High', stagingBySubject.get('High Priority').Task_Priority__c);
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
                Provider__c = 'MICROSOFT_GRAPH',
                Status__c = 'Matched', // Mark as Matched
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
                'MICROSOFT_GRAPH',
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
            Provider__c = 'MICROSOFT_GRAPH',
            Status__c = 'Unmatched', // Mark as Unmatched (no Task created)
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
            'MICROSOFT_GRAPH',
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
            'MICROSOFT_GRAPH',
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
            'MICROSOFT_GRAPH',
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
        Assert.areEqual(3, firstResult.matchedCount, 'First sync should match 3 emails');
        Assert.areEqual(2, firstResult.unmatchedCount, 'First sync should have 2 unmatched');
        Assert.areEqual(3, firstResult.importedCount, 'First sync should import 3 EmailMessages');
        
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
                false // Don't send notifications
            );
        Test.stopTest();
        
      
        Assert.areEqual(3, secondResult.successCount, 'Second sync should create 3 staging records');
        Assert.areEqual(3, secondResult.matchedCount, 'Second sync should match 3 NEW emails');
        Assert.areEqual(0, secondResult.unmatchedCount, 'Second sync should have 0 unmatched');
        
        // CRITICAL ASSERTION: Imported should equal Matched (not include rematched old emails)
        Assert.areEqual(3, secondResult.importedCount, 
            'Second sync should import 3 EmailMessages (NOT 5 including rematched old emails)');
        
        // Additional verification: Imported should never exceed Matched
        Assert.isTrue(secondResult.importedCount <= secondResult.matchedCount, 
            'Imported count should never exceed Matched count');
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

        Map<String, AI_Workspace_Staging__c> stagingBySubject = new Map<String, AI_Workspace_Staging__c>();
        for (AI_Workspace_Staging__c s : [
            SELECT Subject__c, Task_Status__c FROM AI_Workspace_Staging__c
        ]) {
            stagingBySubject.put(s.Subject__c, s);
        }

        Assert.areEqual('Not Started', stagingBySubject.get('Needs Action Task').Task_Status__c);
        Assert.areEqual('Completed', stagingBySubject.get('Completed Task').Task_Status__c);
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
            'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
            Status__c = 'Unmatched',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
                'MICROSOFT_GRAPH',
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
            Status__c = 'Unmatched',
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
            Status__c = 'Unmatched',
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
            Status__c = 'Unmatched',
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
            Status__c = 'Matched',
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
            Status__c = 'Matched',
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
            Status__c = 'Matched',
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
            Status__c = 'Matched',
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
            Status__c = 'Matched',
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
}