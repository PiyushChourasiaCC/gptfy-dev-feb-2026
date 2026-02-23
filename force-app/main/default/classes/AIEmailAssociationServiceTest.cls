/**
 * Test class for AIEmailAssociationService
 */
@isTest
private class AIEmailAssociationServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        // Create test Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = testAccount.Id
        );
        insert testOpp;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Create test Lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'lead@example.com'
        );
        insert testLead;
        
        // Create test Case
        Case testCase = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Origin = 'Email'
        );
        insert testCase;
    }

    @isTest
    static void testEnrichEmailsWithAssociations_NullInput() {
        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(null);
        Test.stopTest();

        Assert.areEqual(null, result, 'Should return null for null input');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_EmptyInput() {
        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(
            new List<Map<String, Object>>()
        );
        Test.stopTest();

        Assert.areEqual(0, result.size(), 'Should return empty list for empty input');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_NoMessageId() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        // No internetMessageId
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(1, result.size(), 'Should return same number of emails');
        Assert.areEqual(false, result[0].get('isImported'), 'Email without messageId should not be imported');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithEmailMessage() {
        // Create EmailMessage
        EmailMessage em = new EmailMessage(
            Subject = 'Test Email Message',
            TextBody = 'Test body',
            MessageIdentifier = 'test-message-id-123',
            Status = '3',
            Incoming = true
        );
        insert em;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-message-id-123');
        email.put('subject', 'Test Email Message');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(1, result.size(), 'Should return same number of emails');
        Assert.areEqual(true, result[0].get('isImported'), 'Email with EmailMessage should be imported');
        Assert.areNotEqual(null, result[0].get('associations'), 'Should have associations field');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithEmailMessageAndContact() {
        Contact testContact = [SELECT Id, Name FROM Contact LIMIT 1];
        
        // Create EmailMessage
        EmailMessage em = new EmailMessage(
            Subject = 'Test Email with Contact',
            TextBody = 'Test body',
            MessageIdentifier = 'test-message-contact-123',
            Status = '3',
            Incoming = true
        );
        insert em;
        
        // Create EmailMessageRelation
        EmailMessageRelation emr = new EmailMessageRelation(
            EmailMessageId = em.Id,
            RelationId = testContact.Id,
            RelationType = 'ToAddress'
        );
        insert emr;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-message-contact-123');
        email.put('subject', 'Test Email with Contact');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(true, result[0].get('isImported'), 'Email should be imported');
        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        Assert.isTrue(associations.size() > 0, 'Should have at least one association');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithEmailMessageAndLead() {
        Lead testLead = [SELECT Id, Name FROM Lead LIMIT 1];
        
        // Create EmailMessage
        EmailMessage em = new EmailMessage(
            Subject = 'Test Email with Lead',
            TextBody = 'Test body',
            MessageIdentifier = 'test-message-lead-123',
            Status = '3',
            Incoming = true
        );
        insert em;
        
        // Create EmailMessageRelation
        EmailMessageRelation emr = new EmailMessageRelation(
            EmailMessageId = em.Id,
            RelationId = testLead.Id,
            RelationType = 'ToAddress'
        );
        insert emr;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-message-lead-123');
        email.put('subject', 'Test Email with Lead');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(true, result[0].get('isImported'), 'Email should be imported');
        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        Assert.isTrue(associations.size() > 0, 'Should have at least one association');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithOpportunity() {
        Opportunity testOpp = [SELECT Id, Name, AccountId FROM Opportunity LIMIT 1];
        
        // Create EmailMessage with Opportunity
        EmailMessage em = new EmailMessage(
            Subject = 'Test Email with Opportunity',
            TextBody = 'Test body',
            MessageIdentifier = 'test-message-opp-123',
            RelatedToId = testOpp.Id,
            Status = '3',
            Incoming = true
        );
        insert em;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-message-opp-123');
        email.put('subject', 'Test Email with Opportunity');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(true, result[0].get('isImported'), 'Email should be imported');
        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        Assert.isTrue(associations.size() >= 2, 'Should have Opportunity and Account associations');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithCase() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        
        // Create EmailMessage with Case
        EmailMessage em = new EmailMessage(
            Subject = 'Test Email with Case',
            TextBody = 'Test body',
            MessageIdentifier = 'test-message-case-123',
            ParentId = testCase.Id,
            Status = '3',
            Incoming = true
        );
        insert em;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-message-case-123');
        email.put('subject', 'Test Email with Case');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(true, result[0].get('isImported'), 'Email should be imported');
        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        Assert.isTrue(associations.size() > 0, 'Should have Case association');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithTask() {
        Contact testContact = [SELECT Id, Name FROM Contact LIMIT 1];
        
        // Create Task with Workspace_Sync_Id__c
        Task testTask = new Task(
            Subject = 'Email: Test Task Email',
            TaskSubtype = 'Email',
            WhoId = testContact.Id,
            Workspace_Sync_Id__c = 'test-task-message-123',
            Status = 'Completed'
        );
        insert testTask;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-task-message-123');
        email.put('subject', 'Test Task Email');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(true, result[0].get('isImported'), 'Email should be imported');
        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        Assert.isTrue(associations.size() > 0, 'Should have Contact association from Task');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithTaskAndOpportunity() {
        Opportunity testOpp = [SELECT Id, Name, AccountId FROM Opportunity LIMIT 1];
        
        // Create Task with Opportunity
        Task testTask = new Task(
            Subject = 'Email: Test Task with Opp',
            TaskSubtype = 'Email',
            WhatId = testOpp.Id,
            Workspace_Sync_Id__c = 'test-task-opp-123',
            Status = 'Completed'
        );
        insert testTask;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-task-opp-123');
        email.put('subject', 'Test Task with Opp');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(true, result[0].get('isImported'), 'Email should be imported');
        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        Assert.isTrue(associations.size() >= 2, 'Should have Opportunity and Account associations');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithStagingMatched() {
        // Get Email record type ID
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        // Create EmailMessage first
        EmailMessage em = new EmailMessage(
            Subject = 'Test Staging Email',
            TextBody = 'Test body',
            MessageIdentifier = 'test-staging-123',
            Status = '3',
            Incoming = true
        );
        insert em;
        
        // Create Staging record with Matched status
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Test Staging Email',
            Message_Identifier__c = 'test-staging-123',
            Status__c = 'Matched',
            Email_Message__c = em.Id,
            User__c = UserInfo.getUserId(),
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR'
        );
        insert staging;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-staging-123');
        email.put('subject', 'Test Staging Email');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(true, result[0].get('isImported'), 'Email with Matched staging should be imported');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithStagingUnmatched() {
        // Get Email record type ID
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        // Create Staging record with Unmatched status
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Test Unmatched Email',
            Message_Identifier__c = 'test-unmatched-123',
            Status__c = 'Unmatched',
            User__c = UserInfo.getUserId(),
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR'
        );
        insert staging;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-unmatched-123');
        email.put('subject', 'Test Unmatched Email');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(false, result[0].get('isImported'), 'Email with Unmatched staging should not be imported');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithStagingDeletedEmailMessage() {
        // Get Email record type ID
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        // Create EmailMessage
        EmailMessage em = new EmailMessage(
            Subject = 'Test Deleted Email',
            TextBody = 'Test body',
            MessageIdentifier = 'test-deleted-123',
            Status = '3',
            Incoming = true
        );
        insert em;
        
        // Create Staging record
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Test Deleted Email',
            Message_Identifier__c = 'test-deleted-123',
            Status__c = 'Matched',
            Email_Message__c = em.Id,
            User__c = UserInfo.getUserId(),
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR'
        );
        insert staging;
        
        // Delete the EmailMessage
        delete em;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-deleted-123');
        email.put('subject', 'Test Deleted Email');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(false, result[0].get('isImported'), 'Email with deleted EmailMessage should not be imported');
        
        // Verify staging was reset
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Status__c, Email_Message__c 
            FROM AI_Workspace_Staging__c 
            WHERE Id = :staging.Id
        ];
        Assert.areEqual('Unmatched', updatedStaging.Status__c, 'Staging status should be reset to Unmatched');
        Assert.areEqual(null, updatedStaging.Email_Message__c, 'Email_Message__c should be cleared');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_WithStagingInvalidEmailMessageId() {
        // Get Email record type ID
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        // Create Staging record with invalid Email_Message__c
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Test Invalid ID',
            Message_Identifier__c = 'test-invalid-id-123',
            Status__c = 'Matched',
            Email_Message__c = 'invalid-id',
            User__c = UserInfo.getUserId(),
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR'
        );
        insert staging;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-invalid-id-123');
        email.put('subject', 'Test Invalid ID');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(false, result[0].get('isImported'), 'Email with invalid EmailMessage ID should not be imported');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_MultipleEmails() {
        Contact testContact = [SELECT Id, Name FROM Contact LIMIT 1];
        Lead testLead = [SELECT Id, Name FROM Lead LIMIT 1];
        
        // Create EmailMessage for first email
        EmailMessage em1 = new EmailMessage(
            Subject = 'First Email',
            TextBody = 'Test body 1',
            MessageIdentifier = 'test-multi-1',
            Status = '3',
            Incoming = true
        );
        insert em1;
        
        EmailMessageRelation emr1 = new EmailMessageRelation(
            EmailMessageId = em1.Id,
            RelationId = testContact.Id,
            RelationType = 'ToAddress'
        );
        insert emr1;
        
        // Create EmailMessage for second email
        EmailMessage em2 = new EmailMessage(
            Subject = 'Second Email',
            TextBody = 'Test body 2',
            MessageIdentifier = 'test-multi-2',
            Status = '3',
            Incoming = true
        );
        insert em2;
        
        EmailMessageRelation emr2 = new EmailMessageRelation(
            EmailMessageId = em2.Id,
            RelationId = testLead.Id,
            RelationType = 'ToAddress'
        );
        insert emr2;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email1 = new Map<String, Object>();
        email1.put('internetMessageId', 'test-multi-1');
        email1.put('subject', 'First Email');
        emails.add(email1);
        
        Map<String, Object> email2 = new Map<String, Object>();
        email2.put('internetMessageId', 'test-multi-2');
        email2.put('subject', 'Second Email');
        emails.add(email2);
        
        Map<String, Object> email3 = new Map<String, Object>();
        email3.put('internetMessageId', 'test-multi-3');
        email3.put('subject', 'Third Email');
        emails.add(email3);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(3, result.size(), 'Should return all emails');
        Assert.areEqual(true, result[0].get('isImported'), 'First email should be imported');
        Assert.areEqual(true, result[1].get('isImported'), 'Second email should be imported');
        Assert.areEqual(false, result[2].get('isImported'), 'Third email should not be imported');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_DuplicateAssociations() {
        Contact testContact = [SELECT Id, Name FROM Contact LIMIT 1];
        
        // Create EmailMessage
        EmailMessage em = new EmailMessage(
            Subject = 'Test Duplicate',
            TextBody = 'Test body',
            MessageIdentifier = 'test-duplicate-123',
            Status = '3',
            Incoming = true
        );
        insert em;
        
        // Create multiple EmailMessageRelations to same Contact
        EmailMessageRelation emr1 = new EmailMessageRelation(
            EmailMessageId = em.Id,
            RelationId = testContact.Id,
            RelationType = 'ToAddress'
        );
        insert emr1;
        
        EmailMessageRelation emr2 = new EmailMessageRelation(
            EmailMessageId = em.Id,
            RelationId = testContact.Id,
            RelationType = 'CcAddress'
        );
        insert emr2;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-duplicate-123');
        email.put('subject', 'Test Duplicate');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        // Should deduplicate - only one Contact association
        Integer contactCount = 0;
        for (Map<String, String> assoc : associations) {
            if (assoc.get('type') == 'Contact') {
                contactCount++;
            }
        }
        Assert.areEqual(1, contactCount, 'Should have only one Contact association (deduplicated)');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_CaseAsRelatedAndParent() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        
        // Create EmailMessage with Case as both RelatedTo and Parent
        EmailMessage em = new EmailMessage(
            Subject = 'Test Case Duplicate',
            TextBody = 'Test body',
            MessageIdentifier = 'test-case-dup-123',
            RelatedToId = testCase.Id,
            ParentId = testCase.Id,
            Status = '3',
            Incoming = true
        );
        insert em;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-case-dup-123');
        email.put('subject', 'Test Case Duplicate');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        // Should deduplicate - only one Case association
        Integer caseCount = 0;
        for (Map<String, String> assoc : associations) {
            if (assoc.get('type') == 'Case') {
                caseCount++;
            }
        }
        Assert.areEqual(1, caseCount, 'Should have only one Case association (deduplicated)');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_TaskWithContactAndOpportunity() {
        Contact testContact = [SELECT Id, Name FROM Contact LIMIT 1];
        Opportunity testOpp = [SELECT Id, Name, AccountId FROM Opportunity LIMIT 1];
        
        // Create Task with both Contact and Opportunity
        Task testTask = new Task(
            Subject = 'Email: Test Full Task',
            TaskSubtype = 'Email',
            WhoId = testContact.Id,
            WhatId = testOpp.Id,
            Workspace_Sync_Id__c = 'test-full-task-123',
            Status = 'Completed'
        );
        insert testTask;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-full-task-123');
        email.put('subject', 'Test Full Task');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        Assert.isTrue(associations.size() >= 3, 'Should have Contact, Opportunity, and Account associations');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_OpportunityWithoutAccount() {
        // Create Opportunity without Account
        Opportunity oppNoAccount = new Opportunity(
            Name = 'Opp Without Account',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert oppNoAccount;
        
        // Create EmailMessage with Opportunity
        EmailMessage em = new EmailMessage(
            Subject = 'Test Opp No Account',
            TextBody = 'Test body',
            MessageIdentifier = 'test-opp-no-acct-123',
            RelatedToId = oppNoAccount.Id,
            Status = '3',
            Incoming = true
        );
        insert em;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-opp-no-acct-123');
        email.put('subject', 'Test Opp No Account');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        List<Map<String, String>> associations = (List<Map<String, String>>) result[0].get('associations');
        // Should have Opportunity but not Account
        Boolean hasOpp = false;
        Boolean hasAccount = false;
        for (Map<String, String> assoc : associations) {
            if (assoc.get('type') == 'Opportunity') {
                hasOpp = true;
            }
            if (assoc.get('type') == 'Account') {
                hasAccount = true;
            }
        }
        Assert.areEqual(true, hasOpp, 'Should have Opportunity association');
        Assert.areEqual(false, hasAccount, 'Should not have Account association');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_TaskWithNullWorkspaceSyncId() {
        Contact testContact = [SELECT Id, Name FROM Contact LIMIT 1];
        
        // Create Task without Workspace_Sync_Id__c
        Task testTask = new Task(
            Subject = 'Email: Test No Sync ID',
            TaskSubtype = 'Email',
            WhoId = testContact.Id,
            Status = 'Completed'
        );
        insert testTask;

        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        Map<String, Object> email = new Map<String, Object>();
        email.put('internetMessageId', 'test-no-sync-id-123');
        email.put('subject', 'Test No Sync ID');
        emails.add(email);

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(false, result[0].get('isImported'), 'Email should not be imported without matching Task');
    }

    @isTest
    static void testEnrichEmailsWithAssociations_BulkEmails() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        // Create 200 emails
        for (Integer i = 0; i < 200; i++) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('internetMessageId', 'bulk-test-' + i);
            email.put('subject', 'Bulk Test Email ' + i);
            emails.add(email);
        }

        Test.startTest();
        List<Map<String, Object>> result = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
        Test.stopTest();

        Assert.areEqual(200, result.size(), 'Should handle bulk emails');
        for (Map<String, Object> email : result) {
            Assert.areNotEqual(null, email.get('isImported'), 'Each email should have isImported flag');
        }
    }
}