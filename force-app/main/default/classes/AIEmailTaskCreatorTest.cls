@IsTest
private class AIEmailTaskCreatorTest {

    @TestSetup
    static void setup() {
        // Create test Account (with ShippingCountry for orgs with validation rules)
        Account acc = new Account(
            Name = 'Test Account',
            ShippingCountry = 'United States'
        );
        insert acc;

        // Create test Contact
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test.contact@example.com',
            AccountId = acc.Id
        );
        insert con;

        // Create test Lead (with Country for orgs with validation rules)
        Lead lead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Email = 'test.lead@example.com',
            Company = 'Test Lead Company',
            Country = 'United States'
        );
        insert lead;
    }

    @IsTest
    static void testCreateEmailTasks_Success() {
        // Get test data
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Build email data
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        emailDataList.add(buildTestEmailData('Test Subject 1', 'msg-id-001'));
        emailDataList.add(buildTestEmailData('Test Subject 2', 'msg-id-002'));

        // Build match results
        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();

        AIQuickMatchService.MatchResult match1 = new AIQuickMatchService.MatchResult();
        match1.contactId = con.Id;
        match1.contactIds = new List<Id>{ con.Id };
        match1.accountId = acc.Id;
        match1.confidence = 100;
        matchResults.add(match1);

        AIQuickMatchService.MatchResult match2 = new AIQuickMatchService.MatchResult();
        match2.contactId = con.Id;
        match2.contactIds = new List<Id>{ con.Id };
        match2.accountId = acc.Id;
        match2.confidence = 100;
        matchResults.add(match2);

        Test.startTest();
        AIEmailTaskCreator.EmailImportResult result = AIEmailTaskCreator.createEmailTasks(
            emailDataList,
            matchResults,
            'MICROSOFT_EMAIL',
            'user@company.com'
        );
        Test.stopTest();

        // Verify results
        Assert.areEqual(2, result.successCount, 'Should have 2 successful imports');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');
        Assert.areEqual(0, result.duplicateCount, 'Should have no duplicates');
        Assert.areEqual(2, result.taskIds.size(), 'Should have 2 Task IDs');

        // Verify Tasks were created
        List<Task> tasks = [
            SELECT Id, Subject, TaskSubtype, Description, Workspace_Sync_Id__c, WhatId, Status, Priority
            FROM Task
            WHERE Id IN :result.taskIds
        ];
        Assert.areEqual(2, tasks.size(), 'Should have 2 Tasks');

        for (Task t : tasks) {
            Assert.areEqual('Email', t.TaskSubtype, 'TaskSubtype should be Email');
            Assert.areEqual('Completed', t.Status, 'Status should be Completed');
            Assert.areEqual(acc.Id, t.WhatId, 'WhatId should be Account');
            Assert.areNotEqual(null, t.Workspace_Sync_Id__c, 'Workspace_Sync_Id__c should be set');
            // Note: Email_From__c field removed - from address now stored in Description
            Assert.isTrue(t.Description.contains('To:'), 'Description should contain To header');
            Assert.isTrue(t.Description.contains('---'), 'Description should contain separator');
        }

        // Verify WhoId is set (works with or without Shared Activities)
        // Note: TaskRelation is only available if Shared Activities is enabled
        // For compatibility, we check WhoId which works in all orgs
        List<Task> tasksWithWho = [SELECT Id, WhoId FROM Task WHERE Id IN :result.taskIds];
        for (Task t : tasksWithWho) {
            Assert.areNotEqual(null, t.WhoId, 'WhoId should be set');
        }
    }

    @IsTest
    static void testCreateEmailTasks_WithLead() {
        // Get test data
        Lead lead = [SELECT Id FROM Lead LIMIT 1];

        // Build email data
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        emailDataList.add(buildTestEmailData('Lead Email', 'msg-id-lead-001'));

        // Build match result with Lead
        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.leadId = lead.Id;
        match.confidence = 90;
        matchResults.add(match);

        Test.startTest();
        AIEmailTaskCreator.EmailImportResult result = AIEmailTaskCreator.createEmailTasks(
            emailDataList,
            matchResults,
            'GMAIL_EMAIL',
            'user@company.com'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should have 1 successful import');
        Assert.areEqual(1, result.taskIds.size(), 'Should have 1 Task ID');

        // Verify WhoId points to Lead (works with or without Shared Activities)
        Task t = [SELECT Id, WhoId FROM Task WHERE Id = :result.taskIds[0]];
        Assert.areEqual(lead.Id, t.WhoId, 'WhoId should point to Lead');
    }

    @IsTest
    static void testCreateEmailTasks_MultipleContacts() {
        // Get test data and create additional contact
        Contact con1 = [SELECT Id FROM Contact LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Contact con2 = new Contact(
            FirstName = 'Second',
            LastName = 'Contact',
            Email = 'second.contact@example.com',
            AccountId = acc.Id
        );
        insert con2;

        // Build email data
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        emailDataList.add(buildTestEmailData('Multi-Contact Email', 'msg-id-multi-001'));

        // Build match result with multiple contacts
        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = con1.Id;
        match.contactIds = new List<Id>{ con1.Id, con2.Id };
        match.accountId = acc.Id;
        match.confidence = 100;
        matchResults.add(match);

        Test.startTest();
        AIEmailTaskCreator.EmailImportResult result = AIEmailTaskCreator.createEmailTasks(
            emailDataList,
            matchResults,
            'MICROSOFT_EMAIL',
            'user@company.com'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should have 1 successful import');

        // Verify WhoId is set to first contact
        // Note: Without Shared Activities, only one Contact can be linked via WhoId
        // TaskRelation would link multiple contacts if Shared Activities were enabled
        Task t = [SELECT Id, WhoId FROM Task WHERE Id = :result.taskIds[0]];
        Assert.areNotEqual(null, t.WhoId, 'WhoId should be set');
        Assert.isTrue(t.WhoId == con1.Id || t.WhoId == con2.Id, 'WhoId should be one of the contacts');
    }

    @IsTest
    static void testCreateEmailTasks_Deduplication() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        // Create existing Task with same message ID
        Task existingTask = new Task(
            Subject = 'Existing Email',
            TaskSubtype = 'Email',
            Workspace_Sync_Id__c = 'msg-id-existing'
        );
        insert existingTask;

        // Build email data with same message ID
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        emailDataList.add(buildTestEmailData('Duplicate Email', 'msg-id-existing'));

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = con.Id;
        match.contactIds = new List<Id>{ con.Id };
        match.confidence = 100;
        matchResults.add(match);

        Test.startTest();
        AIEmailTaskCreator.EmailImportResult result = AIEmailTaskCreator.createEmailTasks(
            emailDataList,
            matchResults,
            'MICROSOFT_EMAIL',
            'user@company.com'
        );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have no new imports');
        Assert.areEqual(1, result.duplicateCount, 'Should have 1 duplicate');
        Assert.areEqual(0, result.taskIds.size(), 'Should have no new Task IDs');
    }

    @IsTest
    static void testCreateEmailTasks_HtmlBodyStripping() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        // Build email with HTML body
        Map<String, Object> emailData = new Map<String, Object>{
            'id' => 'test-id-html',
            'internetMessageId' => 'msg-id-html-001',
            'subject' => 'HTML Email',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender Name'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com'
                    }
                }
            },
            'ccRecipients' => new List<Object>(),
            'body' => new Map<String, Object>{
                'contentType' => 'html',
                'content' => '<html><body><p>This is <strong>bold</strong> text.</p><br/><p>Second paragraph.</p></body></html>'
            },
            'importance' => 'normal'
        };

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>{ emailData };

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = con.Id;
        match.contactIds = new List<Id>{ con.Id };
        match.confidence = 100;
        matchResults.add(match);

        Test.startTest();
        AIEmailTaskCreator.EmailImportResult result = AIEmailTaskCreator.createEmailTasks(
            emailDataList,
            matchResults,
            'MICROSOFT_EMAIL',
            'user@company.com'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should have 1 successful import');

        Task t = [SELECT Description FROM Task WHERE Id = :result.taskIds[0]];

        // Verify HTML tags were stripped
        Assert.isTrue(!t.Description.contains('<p>'), 'Description should not contain <p> tags');
        Assert.isTrue(!t.Description.contains('<strong>'), 'Description should not contain <strong> tags');
        Assert.isTrue(t.Description.contains('bold'), 'Description should contain text content');
        Assert.isTrue(t.Description.contains('Second paragraph'), 'Description should preserve paragraph content');
    }

    @IsTest
    static void testCreateEmailTasks_HighPriority() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        Map<String, Object> emailData = buildTestEmailData('Urgent Email', 'msg-id-urgent');
        emailData.put('importance', 'high');

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>{ emailData };

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = con.Id;
        match.contactIds = new List<Id>{ con.Id };
        match.confidence = 100;
        matchResults.add(match);

        Test.startTest();
        AIEmailTaskCreator.EmailImportResult result = AIEmailTaskCreator.createEmailTasks(
            emailDataList,
            matchResults,
            'MICROSOFT_EMAIL',
            'user@company.com'
        );
        Test.stopTest();

        Task t = [SELECT Priority FROM Task WHERE Id = :result.taskIds[0]];
        Assert.areEqual('High', t.Priority, 'High importance should set High priority');
    }

    @IsTest
    static void testCreateEmailTasks_InvalidInput() {
        Test.startTest();

        // Test null emailDataList
        AIEmailTaskCreator.EmailImportResult result1 = AIEmailTaskCreator.createEmailTasks(
            null,
            new List<AIQuickMatchService.MatchResult>(),
            'MICROSOFT_EMAIL',
            'user@company.com'
        );
        Assert.isTrue(!result1.errors.isEmpty(), 'Should have error for null input');

        // Test size mismatch
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        emailDataList.add(buildTestEmailData('Test', 'msg-1'));
        emailDataList.add(buildTestEmailData('Test', 'msg-2'));

        AIEmailTaskCreator.EmailImportResult result2 = AIEmailTaskCreator.createEmailTasks(
            emailDataList,
            new List<AIQuickMatchService.MatchResult>{ new AIQuickMatchService.MatchResult() },
            'MICROSOFT_EMAIL',
            'user@company.com'
        );
        Assert.isTrue(!result2.errors.isEmpty(), 'Should have error for size mismatch');

        Test.stopTest();
    }

    @IsTest
    static void testCreateEmailTasks_DescriptionFormat() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        // Build email with To and CC
        Map<String, Object> emailData = new Map<String, Object>{
            'id' => 'test-id-format',
            'internetMessageId' => 'msg-id-format-001',
            'subject' => 'Format Test',
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{ 'address' => 'to1@example.com' }
                },
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{ 'address' => 'to2@example.com' }
                }
            },
            'ccRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{ 'address' => 'cc@example.com' }
                }
            },
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'This is the email body.'
            },
            'importance' => 'normal'
        };

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>{ emailData };

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = con.Id;
        match.contactIds = new List<Id>{ con.Id };
        match.confidence = 100;
        matchResults.add(match);

        Test.startTest();
        AIEmailTaskCreator.EmailImportResult result = AIEmailTaskCreator.createEmailTasks(
            emailDataList,
            matchResults,
            'MICROSOFT_EMAIL',
            'user@company.com'
        );
        Test.stopTest();

        Task t = [SELECT Description FROM Task WHERE Id = :result.taskIds[0]];

        // Verify description format
        Assert.isTrue(t.Description.startsWith('To:'), 'Description should start with To:');
        Assert.isTrue(t.Description.contains('to1@example.com'), 'Description should contain first recipient');
        Assert.isTrue(t.Description.contains('to2@example.com'), 'Description should contain second recipient');
        Assert.isTrue(t.Description.contains('CC: cc@example.com'), 'Description should contain CC');
        Assert.isTrue(t.Description.contains('---'), 'Description should contain separator');
        Assert.isTrue(t.Description.contains('This is the email body.'), 'Description should contain body');
    }

    /**
     * Helper method to build test email data
     */
    private static Map<String, Object> buildTestEmailData(String subject, String messageId) {
        return new Map<String, Object>{
            'id' => 'test-id-' + messageId,
            'internetMessageId' => messageId,
            'subject' => subject,
            'receivedDateTime' => '2024-01-15T10:30:00Z',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'sender@example.com',
                    'name' => 'Sender Name'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'recipient@example.com'
                    }
                }
            },
            'ccRecipients' => new List<Object>(),
            'body' => new Map<String, Object>{
                'contentType' => 'text',
                'content' => 'This is the email body content.'
            },
            'importance' => 'normal'
        };
    }
}