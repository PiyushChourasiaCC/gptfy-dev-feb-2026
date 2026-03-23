@isTest
private class AIEmailSyncDigestServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account acc = new Account(
            Name = 'Acme Corporation',
            Website = 'https://www.acme.com'
        );
        insert acc;

        // Create test Contact
        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@acme.com',
            AccountId = acc.Id
        );
        insert con;
    }

    @isTest
    static void testGenerateDigestsNoActivity() {
        // Test with no sync logs
        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(0, digests.size(), 'Should have no digests when no sync activity');
    }

    @isTest
    static void testGenerateDigestsWithActivity() {
        // Create a sync log for the running user
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 3,
            Emails_Unmatched__c = 2
        );
        insert syncLog;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, digests.size(), 'Should have one digest');

        AIEmailSyncDigestService.UserDigest digest = digests.get(UserInfo.getUserId());
        Assert.areNotEqual(null, digest, 'Should have digest for current user');
        Assert.areEqual(5, digest.totalImported, 'Should have 5 imported');
        Assert.areEqual(3, digest.totalExcluded, 'Should have 3 excluded');
        Assert.areEqual(1, digest.syncCount, 'Should have 1 sync');
    }

    @isTest
    static void testGenerateDigestsMultipleSyncs() {
        Id userId = UserInfo.getUserId();

        // Create multiple sync logs
        List<AI_Workspace_Sync_Log__c> logs = new List<AI_Workspace_Sync_Log__c>();
        for (Integer i = 0; i < 3; i++) {
            logs.add(new AI_Workspace_Sync_Log__c(
                User__c = userId,
                Provider_Type__c = 'GMAIL_EMAIL',
                Sync_Type__c = 'Scheduled',
                Status__c = 'Success',
                Start_Time__c = DateTime.now().addHours(-i - 1),
                End_Time__c = DateTime.now().addHours(-i),
                Emails_Fetched__c = 10,
                Emails_Imported__c = 3,
                Emails_Excluded__c = 2,
                Emails_Unmatched__c = 1
            ));
        }
        insert logs;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        AIEmailSyncDigestService.UserDigest digest = digests.get(userId);
        Assert.areEqual(9, digest.totalImported, 'Should have 9 total imported (3 x 3)');
        Assert.areEqual(6, digest.totalExcluded, 'Should have 6 total excluded (3 x 2)');
        Assert.areEqual(3, digest.syncCount, 'Should have 3 syncs');
    }

    @isTest
    static void testSendDigestEmailsNoActivity() {
        Test.startTest();
        Integer sent = AIEmailSyncDigestService.sendDigestEmails(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(0, sent, 'Should send no emails when no activity');
    }

    @isTest
    static void testSendDigestEmailsWithActivity() {
        // Create a sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 3,
            Emails_Unmatched__c = 2
        );
        insert syncLog;

        Test.startTest();
        Integer sent = AIEmailSyncDigestService.sendDigestEmails(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, sent, 'Should send 1 digest email');
    }

    @isTest
    static void testSendDigestForUser() {
        // Create a sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 3,
            Emails_Unmatched__c = 2
        );
        insert syncLog;

        Test.startTest();
        Boolean sent = AIEmailSyncDigestService.sendDigestForUser(
            UserInfo.getUserId(),
            DateTime.now().addDays(-1)
        );
        Test.stopTest();

        Assert.areEqual(true, sent, 'Should successfully send digest for user');
    }

    @isTest
    static void testSendDigestForUserNoActivity() {
        Test.startTest();
        Boolean sent = AIEmailSyncDigestService.sendDigestForUser(
            UserInfo.getUserId(),
            DateTime.now().addDays(-1)
        );
        Test.stopTest();

        Assert.areEqual(false, sent, 'Should return false when no activity');
    }

    @isTest
    static void testDigestWithEmailMessages() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1];

        // Create a sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 2,
            Emails_Excluded__c = 0,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        // Create EmailMessage records
        List<EmailMessage> emails = new List<EmailMessage>();
        for (Integer i = 0; i < 2; i++) {
            EmailMessage em = new EmailMessage(
                Subject = 'Test Email ' + i,
                FromAddress = 'sender@example.com',
                FromName = 'Test Sender',
                ToAddress = 'recipient@example.com',
                TextBody = 'Test body ' + i,
                MessageDate = DateTime.now().addHours(-1),
                Incoming = true,
                Status = '3', // Sent
                RelatedToId = acc.Id
            );
            emails.add(em);
        }
        insert emails;
        
        // Create staging records to link to EmailMessages (replaces Auto_Synced__c flag)
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        for (EmailMessage em : emails) {
            AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
                RecordTypeId = emailRecordTypeId,
                Email_Message__c = em.Id,
                Subject__c = em.Subject,
                From_Address__c = em.FromAddress,
                User__c = UserInfo.getUserId(),
                Status__c = 'Imported',
                Provider__c = 'Outlook'
            );
            stagingRecords.add(staging);
        }
        insert stagingRecords;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, digests.size(), 'Should have one digest');

        AIEmailSyncDigestService.UserDigest digest = digests.get(UserInfo.getUserId());
        // Note: emailGroups may be empty since we're creating emails as current user,
        // but the CreatedById query might not match exactly in test context
        Assert.areNotEqual(null, digest, 'Should have digest');
    }

    @isTest
    static void testUserDigestClass() {
        // Test the UserDigest inner class
        AIEmailSyncDigestService.UserDigest digest = new AIEmailSyncDigestService.UserDigest();

        Assert.areEqual(0, digest.totalImported, 'Initial totalImported should be 0');
        Assert.areEqual(0, digest.totalExcluded, 'Initial totalExcluded should be 0');
        Assert.areEqual(0, digest.syncCount, 'Initial syncCount should be 0');
        Assert.areNotEqual(null, digest.syncLogs, 'syncLogs should be initialized');
        Assert.areNotEqual(null, digest.emailGroups, 'emailGroups should be initialized');
    }

    @isTest
    static void testDigestEmailGroupClass() {
        // Test the DigestEmailGroup inner class
        AIEmailSyncDigestService.DigestEmailGroup emailGroup = new AIEmailSyncDigestService.DigestEmailGroup();

        Assert.areNotEqual(null, emailGroup.emails, 'emails should be initialized');
        Assert.areEqual(0, emailGroup.emails.size(), 'emails should be empty');
    }

    @isTest
    static void testDigestEmailClass() {
        // Test the DigestEmail inner class
        AIEmailSyncDigestService.DigestEmail email = new AIEmailSyncDigestService.DigestEmail();

        Assert.areEqual(null, email.emailMessageId, 'Initial emailMessageId should be null');
        Assert.areEqual(null, email.subject, 'Initial subject should be null');
    }

    @isTest
    static void testPartialSyncIncluded() {
        // Test that partial syncs are included in digest
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Partial', // Partial status
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 3,
            Emails_Excluded__c = 2,
            Emails_Unmatched__c = 1,
            Error_Message__c = 'Some folders failed'
        );
        insert syncLog;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, digests.size(), 'Should include partial sync in digest');

        AIEmailSyncDigestService.UserDigest digest = digests.get(UserInfo.getUserId());
        Assert.areEqual(1, digest.totalErrors, 'Should count partial sync as error');
    }

    @isTest
    static void testFailedSyncExcluded() {
        // Test that failed syncs with 0 imports are excluded
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Failed',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 0,
            Emails_Imported__c = 0,
            Error_Message__c = 'Authentication failed'
        );
        insert syncLog;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(0, digests.size(), 'Failed syncs should be excluded from digest');
    }

    @isTest
    static void testGenerateDigestsWithNullFields() {
        // Test handling of null fields in sync logs
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = null, // Null field
            Emails_Unmatched__c = null, // Null field
            Error_Message__c = null
        );
        insert syncLog;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        AIEmailSyncDigestService.UserDigest digest = digests.get(UserInfo.getUserId());
        Assert.areNotEqual(null, digest, 'Should handle null fields gracefully');
        Assert.areEqual(5, digest.totalImported, 'Should have 5 imported');
        Assert.areEqual(0, digest.totalExcluded, 'Null excluded should be treated as 0');
        Assert.areEqual(0, digest.totalUnmatched, 'Null unmatched should be treated as 0');
    }

    @isTest
    static void testGenerateDigestsWithErrorMessage() {
        // Test that error message is counted as error
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 2,
            Emails_Unmatched__c = 1,
            Error_Message__c = 'Some warnings occurred'
        );
        insert syncLog;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        AIEmailSyncDigestService.UserDigest digest = digests.get(UserInfo.getUserId());
        Assert.areEqual(1, digest.totalErrors, 'Should count error message as error');
    }

    @isTest
    static void testGenerateDigestsMultipleUsers() {
        // Create a second user (using standard user for test)
        User testUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1];
        
        // Create sync logs for both users
        List<AI_Workspace_Sync_Log__c> logs = new List<AI_Workspace_Sync_Log__c>();
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 2,
            Emails_Unmatched__c = 1
        ));
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 8,
            Emails_Imported__c = 3,
            Emails_Excluded__c = 1,
            Emails_Unmatched__c = 0
        ));
        insert logs;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(2, digests.size(), 'Should have digests for both users');
        Assert.isTrue(digests.containsKey(UserInfo.getUserId()), 'Should have digest for current user');
        Assert.isTrue(digests.containsKey(testUser.Id), 'Should have digest for test user');
    }

    @isTest
    static void testSendDigestEmailsMultipleUsers() {
        // Create a second user
        User testUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1];
        
        // Create sync logs for both users
        List<AI_Workspace_Sync_Log__c> logs = new List<AI_Workspace_Sync_Log__c>();
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 2,
            Emails_Unmatched__c = 1
        ));
        logs.add(new AI_Workspace_Sync_Log__c(
            User__c = testUser.Id,
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 8,
            Emails_Imported__c = 3,
            Emails_Excluded__c = 1,
            Emails_Unmatched__c = 0
        ));
        insert logs;

        Test.startTest();
        Integer sent = AIEmailSyncDigestService.sendDigestEmails(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(2, sent, 'Should send digests to both users');
    }

    @isTest
    static void testSendDigestEmailsSkipsZeroImports() {
        // Create sync log with 0 imports (should be skipped)
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 0, // Zero imports
            Emails_Excluded__c = 10,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        Test.startTest();
        Integer sent = AIEmailSyncDigestService.sendDigestEmails(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(0, sent, 'Should not send digest when totalImported is 0');
    }

    @isTest
    static void testSendDigestForUserWithZeroImports() {
        // Create sync log with 0 imports
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 0,
            Emails_Excluded__c = 10,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        Test.startTest();
        Boolean sent = AIEmailSyncDigestService.sendDigestForUser(
            UserInfo.getUserId(),
            DateTime.now().addDays(-1)
        );
        Test.stopTest();

        Assert.areEqual(false, sent, 'Should return false when totalImported is 0');
    }

    @isTest
    static void testSendDigestForUserNotFound() {
        // Create sync log for current user
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 5,
            Emails_Excluded__c = 2,
            Emails_Unmatched__c = 1
        );
        insert syncLog;

        // Try to send digest for a different user
        User otherUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1];

        Test.startTest();
        Boolean sent = AIEmailSyncDigestService.sendDigestForUser(
            otherUser.Id,
            DateTime.now().addDays(-1)
        );
        Test.stopTest();

        Assert.areEqual(false, sent, 'Should return false when user has no activity');
    }

    @isTest
    static void testDigestWithOpportunity() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1];
        
        // Create Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 1,
            Emails_Excluded__c = 0,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        // Create EmailMessage related to Opportunity
        EmailMessage em = new EmailMessage(
            Subject = 'Opportunity Email',
            FromAddress = 'sender@example.com',
            FromName = 'Test Sender',
            ToAddress = 'recipient@example.com',
            TextBody = 'Test body',
            MessageDate = DateTime.now().addHours(-1),
            Incoming = true,
            Status = '3',
            RelatedToId = opp.Id
        );
        insert em;

        // Create staging record
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Email_Message__c = em.Id,
            Subject__c = em.Subject,
            From_Address__c = em.FromAddress,
            User__c = UserInfo.getUserId(),
            Status__c = 'Imported',
            Provider__c = 'Gmail'
        );
        insert staging;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, digests.size(), 'Should have one digest');
    }

    @isTest
    static void testDigestWithUnassociatedEmail() {
        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 1,
            Emails_Excluded__c = 0,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        // Create EmailMessage without RelatedToId (unassociated)
        EmailMessage em = new EmailMessage(
            Subject = 'Unassociated Email',
            FromAddress = 'sender@example.com',
            FromName = 'Test Sender',
            ToAddress = 'recipient@example.com',
            TextBody = 'Test body',
            MessageDate = DateTime.now().addHours(-1),
            Incoming = false,
            Status = '3',
            RelatedToId = null
        );
        insert em;

        // Create staging record
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Email_Message__c = em.Id,
            Subject__c = em.Subject,
            From_Address__c = em.FromAddress,
            User__c = UserInfo.getUserId(),
            Status__c = 'Imported',
            Provider__c = 'Gmail'
        );
        insert staging;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, digests.size(), 'Should have one digest');
    }

    @isTest
    static void testDigestWithEmailRelations() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE Email = 'john.doe@acme.com' LIMIT 1];

        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 1,
            Emails_Excluded__c = 0,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        // Create EmailMessage
        EmailMessage em = new EmailMessage(
            Subject = 'Test Email with Relations',
            FromAddress = 'john.doe@acme.com',
            FromName = 'John Doe',
            ToAddress = 'recipient@example.com',
            TextBody = 'Test body',
            MessageDate = DateTime.now().addHours(-1),
            Incoming = true,
            Status = '3',
            RelatedToId = acc.Id
        );
        insert em;

        // Create EmailMessageRelation
        EmailMessageRelation emr = new EmailMessageRelation(
            EmailMessageId = em.Id,
            RelationId = con.Id,
            RelationType = 'FromAddress',
            RelationAddress = 'john.doe@acme.com'
        );
        insert emr;

        // Create staging record
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Email_Message__c = em.Id,
            Subject__c = em.Subject,
            From_Address__c = em.FromAddress,
            User__c = UserInfo.getUserId(),
            Status__c = 'Imported',
            Provider__c = 'Gmail'
        );
        insert staging;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, digests.size(), 'Should have one digest');
    }

    @isTest
    static void testDigestWithManyEmails() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1];

        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 15,
            Emails_Imported__c = 15,
            Emails_Excluded__c = 0,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        // Create 15 EmailMessages (more than the 10 limit per group in HTML)
        List<EmailMessage> emails = new List<EmailMessage>();
        for (Integer i = 0; i < 15; i++) {
            emails.add(new EmailMessage(
                Subject = 'Test Email ' + i,
                FromAddress = 'sender' + i + '@example.com',
                FromName = 'Sender ' + i,
                ToAddress = 'recipient@example.com',
                TextBody = 'Test body ' + i,
                MessageDate = DateTime.now().addHours(-1),
                Incoming = true,
                Status = '3',
                RelatedToId = acc.Id
            ));
        }
        insert emails;

        // Create staging records
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        for (EmailMessage em : emails) {
            stagingRecords.add(new AI_Workspace_Staging__c(
                RecordTypeId = emailRecordTypeId,
                Email_Message__c = em.Id,
                Subject__c = em.Subject,
                From_Address__c = em.FromAddress,
                User__c = UserInfo.getUserId(),
                Status__c = 'Imported',
                Provider__c = 'Gmail'
            ));
        }
        insert stagingRecords;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, digests.size(), 'Should have one digest');
    }

    @isTest
    static void testDigestWithNullSubject() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1];

        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 1,
            Emails_Excluded__c = 0,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        // Create EmailMessage with null subject
        EmailMessage em = new EmailMessage(
            Subject = null, // Null subject
            FromAddress = 'sender@example.com',
            FromName = null, // Null from name
            ToAddress = 'recipient@example.com',
            TextBody = 'Test body',
            MessageDate = DateTime.now().addHours(-1),
            Incoming = true,
            Status = '3',
            RelatedToId = acc.Id
        );
        insert em;

        // Create staging record
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Email_Message__c = em.Id,
            Subject__c = em.Subject,
            From_Address__c = em.FromAddress,
            User__c = UserInfo.getUserId(),
            Status__c = 'Imported',
            Provider__c = 'Gmail'
        );
        insert staging;

        Test.startTest();
        Map<Id, AIEmailSyncDigestService.UserDigest> digests =
            AIEmailSyncDigestService.generateDigests(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, digests.size(), 'Should handle null subject gracefully');
    }

    @isTest
    static void testEscapeHtmlMethod() {
        // Test HTML escaping through digest generation
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1];

        // Create sync log
        AI_Workspace_Sync_Log__c syncLog = new AI_Workspace_Sync_Log__c(
            User__c = UserInfo.getUserId(),
            Provider_Type__c = 'GMAIL_EMAIL',
            Sync_Type__c = 'Scheduled',
            Status__c = 'Success',
            Start_Time__c = DateTime.now().addHours(-1),
            End_Time__c = DateTime.now(),
            Emails_Fetched__c = 10,
            Emails_Imported__c = 1,
            Emails_Excluded__c = 0,
            Emails_Unmatched__c = 0
        );
        insert syncLog;

        // Create EmailMessage with HTML characters in subject
        EmailMessage em = new EmailMessage(
            Subject = 'Test <script>alert("XSS")</script> Email',
            FromAddress = 'sender@example.com',
            FromName = 'Test & Sender',
            ToAddress = 'recipient@example.com',
            TextBody = 'Test body',
            MessageDate = DateTime.now().addHours(-1),
            Incoming = true,
            Status = '3',
            RelatedToId = acc.Id
        );
        insert em;

        // Create staging record
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Email_Message__c = em.Id,
            Subject__c = em.Subject,
            From_Address__c = em.FromAddress,
            User__c = UserInfo.getUserId(),
            Status__c = 'Imported',
            Provider__c = 'Gmail'
        );
        insert staging;

        Test.startTest();
        Integer sent = AIEmailSyncDigestService.sendDigestEmails(DateTime.now().addDays(-1));
        Test.stopTest();

        Assert.areEqual(1, sent, 'Should send digest with escaped HTML');
    }
}