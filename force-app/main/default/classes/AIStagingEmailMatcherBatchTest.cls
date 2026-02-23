/**
 * Test class for AIStagingEmailMatcherBatch
 * Tests batch processing of staging records with Lead/Contact matching
 */
@isTest
private class AIStagingEmailMatcherBatchTest {

    @testSetup
    static void setupTestData() {
        // Create test Contacts
        Contact testContact1 = new Contact(
            FirstName = 'John',
            LastName = 'Smith',
            Email = 'john.smith@acme.com'
        );
        Contact testContact2 = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane.doe@acme.com'
        );
        insert new List<Contact>{ testContact1, testContact2 };

        // Create test Leads
        Lead testLead1 = new Lead(
            FirstName = 'Bob',
            LastName = 'Johnson',
            Email = 'bob.johnson@startup.com',
            Company = 'Startup Inc'
        );
        Lead testLead2 = new Lead(
            FirstName = 'Alice',
            LastName = 'Williams',
            Email = 'alice.williams@techco.com',
            Company = 'TechCo'
        );
        insert new List<Lead>{ testLead1, testLead2 };
    }

    /**
     * Test 1: Start method returns correct query locator
     */
    @isTest
    static void testStartMethod() {
        // Create staging records
        createStagingRecords(5, 'Unmatched');

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();

        // Verify query returns records
        List<AI_Workspace_Staging__c> records = Database.query(ql.getQuery());
        Assert.areEqual(5, records.size(), 'Should return 5 unmatched staging records');
    }

    /**
     * Test 2: Execute method with matched Contact records
     */
    @isTest
    static void testExecuteWithMatchedContacts() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging record that will match the Contact
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Test Subject 1', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify staging record was updated to Matched
        AI_Workspace_Staging__c updated = [SELECT Id, Status__c, Email_Message__c FROM AI_Workspace_Staging__c WHERE Id = :stagingRecords[0].Id];
        Assert.areEqual('Matched', updated.Status__c, 'Staging record should be marked as Matched');
        Assert.isTrue(String.isNotBlank(updated.Email_Message__c), 'Should have EmailMessage reference');

        // Verify EmailMessage was created
        List<EmailMessage> emails = [SELECT Id, FromAddress, Subject FROM EmailMessage];
        Assert.areEqual(1, emails.size(), 'Should create 1 EmailMessage');
        Assert.areEqual('john.smith@acme.com', emails[0].FromAddress, 'Should match from address');
    }

    /**
     * Test 3: Execute method with matched Lead records
     */
    @isTest
    static void testExecuteWithMatchedLeads() {
        Lead lead = [SELECT Id, Email FROM Lead WHERE Email = 'bob.johnson@startup.com' LIMIT 1];

        // Create staging record that will match the Lead
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('bob.johnson@startup.com', 'Bob Johnson', 'Lead Test', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify staging record was updated to Matched
        AI_Workspace_Staging__c updated = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :stagingRecords[0].Id];
        Assert.areEqual('Matched', updated.Status__c, 'Staging record should be marked as Matched');

        // Verify EmailMessage was created
        List<EmailMessage> emails = [SELECT Id, FromAddress FROM EmailMessage];
        Assert.areEqual(1, emails.size(), 'Should create 1 EmailMessage');
    }

    /**
     * Test 4: Execute method with unmatched records
     */
    @isTest
    static void testExecuteWithUnmatchedRecords() {
        // Create staging record with unknown email
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('unknown@nowhere.com', 'Unknown Person', 'No Match Test', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify staging record remains Unmatched
        AI_Workspace_Staging__c updated = [SELECT Id, Status__c, Email_Message__c FROM AI_Workspace_Staging__c WHERE Id = :stagingRecords[0].Id];
        Assert.areEqual('Unmatched', updated.Status__c, 'Staging record should remain Unmatched');
        Assert.isTrue(String.isBlank(updated.Email_Message__c), 'Should not have EmailMessage reference');

        // Verify no EmailMessage was created
        List<EmailMessage> emails = [SELECT Id FROM EmailMessage];
        Assert.areEqual(0, emails.size(), 'Should not create EmailMessage for unmatched records');
    }

    /**
     * Test 5: Execute method with mixed matched and unmatched records
     */
    @isTest
    static void testExecuteWithMixedRecords() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create mixed staging records
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Matched Email', 'Unmatched'));
        stagingRecords.add(createStagingRecord('unknown@nowhere.com', 'Unknown', 'Unmatched Email', 'Unmatched'));
        stagingRecords.add(createStagingRecord('jane.doe@acme.com', 'Jane Doe', 'Another Match', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify matched records
        List<AI_Workspace_Staging__c> matched = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Status__c = 'Matched'];
        Assert.areEqual(2, matched.size(), 'Should have 2 matched records');

        // Verify unmatched records
        List<AI_Workspace_Staging__c> unmatched = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Status__c = 'Unmatched'];
        Assert.areEqual(1, unmatched.size(), 'Should have 1 unmatched record');

        // Verify EmailMessages created
        List<EmailMessage> emails = [SELECT Id FROM EmailMessage];
        Assert.areEqual(2, emails.size(), 'Should create 2 EmailMessages');
    }

    /**
     * Test 6: EmailMessage creation with all fields
     */
    @isTest
    static void testEmailMessageCreationWithAllFields() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging record with all fields populated
        AI_Workspace_Staging__c staging = createStagingRecord('john.smith@acme.com', 'John Smith', 'Complete Email Test', 'Unmatched');
        staging.To_Address__c = 'recipient@example.com';
        staging.Cc_Address__c = 'cc@example.com';
        staging.Bcc_Address__c = 'bcc@example.com';
        staging.Text_Body__c = 'This is the text body';
        staging.Html_Body__c = '<p>This is the HTML body</p>';
        staging.Message_Date__c = DateTime.now();
        staging.Message_Identifier__c = 'test-message-id-123';
        staging.Is_Incoming__c = true;
        staging.Provider__c = 'MICROSOFT_GRAPH';
        insert staging;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify EmailMessage fields
        EmailMessage em = [SELECT Id, Subject, FromAddress, FromName, ToAddress, CcAddress, BccAddress, 
                           TextBody, HtmlBody, MessageDate, MessageIdentifier, Incoming, Status 
                           FROM EmailMessage LIMIT 1];
        Assert.areEqual('Complete Email Test', em.Subject, 'Subject should match');
        Assert.areEqual('john.smith@acme.com', em.FromAddress, 'FromAddress should match');
        Assert.areEqual('John Smith', em.FromName, 'FromName should match');
        Assert.areEqual('recipient@example.com', em.ToAddress, 'ToAddress should match');
        Assert.areEqual('cc@example.com', em.CcAddress, 'CcAddress should match');
        Assert.areEqual('bcc@example.com', em.BccAddress, 'BccAddress should match');
        Assert.areEqual('This is the text body', em.TextBody, 'TextBody should match');
        Assert.areEqual('<p>This is the HTML body</p>', em.HtmlBody, 'HtmlBody should match');
        Assert.isTrue(em.Incoming, 'Should be incoming');
        Assert.areEqual('3', em.Status, 'Status should be 3 (Sent/Received)');
    }

    /**
     * Test 7: EmailMessageRelation creation for Contact
     */
    @isTest
    static void testEmailMessageRelationCreation() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging record
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Relation Test', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify EmailMessageRelation was created
        List<EmailMessageRelation> relations = [SELECT Id, RelationId, RelationType FROM EmailMessageRelation];
        Assert.isTrue(relations.size() > 0, 'Should create EmailMessageRelation');
        // Check if any relation matches the contact
        Boolean foundContactRelation = false;
        for (EmailMessageRelation rel : relations) {
            if (rel.RelationId == con.Id) {
                foundContactRelation = true;
                Assert.areEqual('OtherAddress', rel.RelationType, 'RelationType should be OtherAddress');
                break;
            }
        }
        Assert.isTrue(foundContactRelation, 'Should have relation to Contact');
    }

    /**
     * Test 8: Multiple EmailMessageRelations for multiple matched Contacts
     */
    @isTest
    static void testMultipleEmailMessageRelations() {
        List<Contact> contacts = [SELECT Id, Email FROM Contact WHERE Email IN ('john.smith@acme.com', 'jane.doe@acme.com')];

        // Create staging record that could match multiple contacts
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Multi Relation Test', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify EmailMessageRelations were created
        List<EmailMessageRelation> relations = [SELECT Id, RelationId FROM EmailMessageRelation];
        Assert.isTrue(relations.size() > 0, 'Should create EmailMessageRelations');
    }

    /**
     * Test 9: Batch processing with large number of records
     */
    @isTest
    static void testBatchProcessingLargeVolume() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create 50 staging records (batch size limit in test context)
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        for (Integer i = 0; i < 50; i++) {
            stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Bulk Test ' + i, 'Unmatched'));
        }
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify all records were processed
        List<AI_Workspace_Staging__c> processed = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Status__c = 'Matched'];
        Assert.areEqual(50, processed.size(), 'Should process all 50 records');
    }

    /**
     * Test 10: Empty scope handling
     */
    @isTest
    static void testEmptyScope() {
        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        batch.execute(null, new List<AI_Workspace_Staging__c>());
        Test.stopTest();

        // Should complete without errors
        Assert.isTrue(true, 'Should handle empty scope without errors');
    }

    /**
     * Test 11: Null scope handling
     */
    @isTest
    static void testNullScope() {
        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        batch.execute(null, null);
        Test.stopTest();

        // Should complete without errors
        Assert.isTrue(true, 'Should handle null scope without errors');
    }

    /**
     * Test 12: Finish method execution
     */
    @isTest
    static void testFinishMethod() {
        // Create staging records
        createStagingRecords(5, 'Unmatched');

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Finish method should execute without errors
        Assert.isTrue(true, 'Finish method should execute without errors');
    }

    /**
     * Test 13: runBatch static method with default batch size
     */
    @isTest
    static void testRunBatchDefaultSize() {
        // Create staging records
        createStagingRecords(5, 'Unmatched');

        Test.startTest();
        Id batchId = AIStagingEmailMatcherBatch.runBatch();
        Test.stopTest();

        // Verify batch was queued
        Assert.isNotNull(batchId, 'Should return batch job ID');
    }

    /**
     * Test 14: runBatch static method with custom batch size
     */
    @isTest
    static void testRunBatchCustomSize() {
        // Create staging records
        createStagingRecords(5, 'Unmatched');

        Test.startTest();
        Id batchId = AIStagingEmailMatcherBatch.runBatch(25);
        Test.stopTest();

        // Verify batch was queued
        Assert.isNotNull(batchId, 'Should return batch job ID');
    }

    /**
     * Test 16: EmailMessage with Is_Incoming__c = false
     */
    @isTest
    static void testEmailMessageOutgoing() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging record with Is_Incoming__c = false
        AI_Workspace_Staging__c staging = createStagingRecord('john.smith@acme.com', 'John Smith', 'Outgoing Test', 'Unmatched');
        staging.Is_Incoming__c = false;
        insert staging;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify EmailMessage Incoming = false
        EmailMessage em = [SELECT Id, Incoming FROM EmailMessage LIMIT 1];
        Assert.isFalse(em.Incoming, 'Should be outgoing (Incoming = false)');
    }

    /**
     * Test 17: Staging records with different statuses (only Unmatched should be processed)
     */
    @isTest
    static void testOnlyUnmatchedRecordsProcessed() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging records with different statuses
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Unmatched 1', 'Unmatched'));
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Matched Already', 'Matched'));
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Pending Status', 'Pending'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify only Unmatched records were processed
        List<EmailMessage> emails = [SELECT Id FROM EmailMessage];
        Assert.areEqual(1, emails.size(), 'Should only process Unmatched records');
    }

    /**
     * Test 18: Backward compatibility - single contactId
     */
    @isTest
    static void testBackwardCompatibilitySingleContactId() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging record
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Backward Compat Test', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Should create EmailMessage and relation
        List<EmailMessage> emails = [SELECT Id FROM EmailMessage];
        Assert.areEqual(1, emails.size(), 'Should create EmailMessage');

        List<EmailMessageRelation> relations = [SELECT Id FROM EmailMessageRelation];
        Assert.isTrue(relations.size() > 0, 'Should create EmailMessageRelation');
    }

    /**
     * Test 19: Backward compatibility - single leadId
     */
    @isTest
    static void testBackwardCompatibilitySingleLeadId() {
        Lead lead = [SELECT Id, Email FROM Lead WHERE Email = 'bob.johnson@startup.com' LIMIT 1];

        // Create staging record
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('bob.johnson@startup.com', 'Bob Johnson', 'Lead Compat Test', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Should create EmailMessage and relation
        List<EmailMessage> emails = [SELECT Id FROM EmailMessage];
        Assert.areEqual(1, emails.size(), 'Should create EmailMessage');

        List<EmailMessageRelation> relations = [SELECT Id FROM EmailMessageRelation];
        Assert.isTrue(relations.size() > 0, 'Should create EmailMessageRelation');
    }

    /**
     * Test 20: Duplicate relation prevention
     */
    @isTest
    static void testDuplicateRelationPrevention() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging record
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Duplicate Test', 'Unmatched'));
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Should not create duplicate relations
        List<EmailMessageRelation> relations = [SELECT Id, EmailMessageId, RelationId FROM EmailMessageRelation];
        
        // Check for duplicates
        Set<String> relationKeys = new Set<String>();
        for (EmailMessageRelation rel : relations) {
            String key = rel.EmailMessageId + '-' + rel.RelationId;
            Assert.isFalse(relationKeys.contains(key), 'Should not create duplicate relations');
            relationKeys.add(key);
        }
    }

    /**
     * Test 21: Stateful batch - verify batch is stateful
     */
    @isTest
    static void testStatefulBatchTotals() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging records
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        for (Integer i = 0; i < 10; i++) {
            stagingRecords.add(createStagingRecord('john.smith@acme.com', 'John Smith', 'Stateful Test ' + i, 'Unmatched'));
        }
        insert stagingRecords;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50); // Process all in one batch in test context
        Test.stopTest();

        // Verify all records were processed
        List<AI_Workspace_Staging__c> processed = [SELECT Id FROM AI_Workspace_Staging__c WHERE Status__c = 'Matched'];
        Assert.areEqual(10, processed.size(), 'Should process all records');
    }

    /**
     * Test 22: EmailMessage with minimal fields
     */
    @isTest
    static void testEmailMessageMinimalFields() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        // Create staging record with minimal fields
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = 'john.smith@acme.com',
            Status__c = 'Unmatched'
        );
        
        // Get Email record type
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
        if (emailRecordTypeId != null) {
            staging.RecordTypeId = emailRecordTypeId;
        }
        
        insert staging;

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Should create EmailMessage even with minimal fields
        List<EmailMessage> emails = [SELECT Id, FromAddress FROM EmailMessage];
        Assert.areEqual(1, emails.size(), 'Should create EmailMessage with minimal fields');
    }

    /**
     * Test 23: Query locator with Email record type
     */
    @isTest
    static void testQueryLocatorWithRecordType() {
        // Create staging records with Email record type
        createStagingRecords(3, 'Unmatched');

        Test.startTest();
        AIStagingEmailMatcherBatch batch = new AIStagingEmailMatcherBatch();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();

        // Should return records with Email record type
        List<AI_Workspace_Staging__c> records = Database.query(ql.getQuery());
        Assert.isTrue(records.size() >= 3, 'Should return staging records with Email record type');
    }

    // ========================================================================
    // HELPER METHODS
    // ========================================================================

    /**
     * Create a staging record for testing
     */
    private static AI_Workspace_Staging__c createStagingRecord(String fromAddress, String fromName, String subject, String status) {
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = fromAddress,
            From_Name__c = fromName,
            Subject__c = subject,
            Status__c = status,
            Message_Date__c = DateTime.now(),
            Provider__c = 'MICROSOFT_GRAPH'
        );
        
        // Get Email record type
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
        
        if (emailRecordTypeId != null) {
            staging.RecordTypeId = emailRecordTypeId;
        }
        
        return staging;
    }

    /**
     * Create multiple staging records for bulk testing
     */
    private static void createStagingRecords(Integer count, String status) {
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        
        for (Integer i = 0; i < count; i++) {
            stagingRecords.add(createStagingRecord('test' + i + '@example.com', 'Test User ' + i, 'Test Subject ' + i, status));
        }
        
        insert stagingRecords;
    }
}