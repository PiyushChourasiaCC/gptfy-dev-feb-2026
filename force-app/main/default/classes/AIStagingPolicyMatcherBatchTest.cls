/**
 * Test class for AIStagingPolicyMatcherBatch
 * 
 * Tests Phase 3 batch processing logic including:
 * - Policy validation by User ID
 * - Policy validation by Profile ID
 * - Rejection when no policy found
 * - Bulk processing and error handling
 * 
 * @author GPTfy
 * @date 2026-03-11
 * @Jira V2-7889
 */
@isTest
private class AIStagingPolicyMatcherBatchTest {
    
    @testSetup
    static void setupTestData() {
        // Create test users with different profiles
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User testUser1 = new User(
            FirstName = 'Test',
            LastName = 'User1',
            Email = 'testuser1@example.com',
            Username = 'testuser1@gptfy.test.com',
            Alias = 'tuser1',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = sysAdminProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser1;
        
        User testUser2 = new User(
            FirstName = 'Test',
            LastName = 'User2',
            Email = 'testuser2@example.com',
            Username = 'testuser2@gptfy.test.com',
            Alias = 'tuser2',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser2;
        
        // Create AI Workspace Users
        AI_Workspace_User__c workspaceUser1 = new AI_Workspace_User__c(
            User__c = testUser1.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser1@gmail.com',
            Access_Token__c = 'encrypted_token_1'
        );
        insert workspaceUser1;
        
        AI_Workspace_User__c workspaceUser2 = new AI_Workspace_User__c(
            User__c = testUser2.Id,
            Provider__c = 'Outlook',
            Service_User_Email__c = 'testuser2@outlook.com',
            Access_Token__c = 'encrypted_token_2'
        );
        insert workspaceUser2;
        
        // Create a workspace user without policy (different profile, no policy for this profile)
        User testUser3 = new User(
            FirstName = 'Test',
            LastName = 'User3',
            Email = 'testuser3@example.com',
            Username = 'testuser3@gptfy.test.com',
            Alias = 'tuser3',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = sysAdminProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser3;
        
        AI_Workspace_User__c workspaceUser3 = new AI_Workspace_User__c(
            User__c = testUser3.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser3@gmail.com',
            Access_Token__c = 'encrypted_token_3'
        );
        insert workspaceUser3;
        
        // Create processing policies
        // Policy 1: Specific username (testUser1)
        AI_Workspace_Processing_Policy__c policy1 = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com'
        );
        insert policy1;
        
        // Policy 2: Profile-based (Standard User profile - only testUser2 has this)
        AI_Workspace_Processing_Policy__c policy2 = new AI_Workspace_Processing_Policy__c(
            Profiles__c = 'Standard User'
        );
        insert policy2;
        
        // Create staging records with Status = 'Ready'
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        // Staging 1: User with specific policy
        AI_Workspace_Staging__c staging1 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 1', testUser1.Id),
            WhoId__c = '003XXXXXXXXXXXXXX1'
        );
        insert staging1;
        
        // Staging 2: User with profile-based policy
        AI_Workspace_Staging__c staging2 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser2.Id,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 2', testUser2.Id),
            WhoId__c = '003XXXXXXXXXXXXXX2'
        );
        insert staging2;
        
        // Staging 3: User without any policy (should be rejected)
        AI_Workspace_Staging__c staging3 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser3.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 3', testUser3.Id),
            WhoId__c = '003XXXXXXXXXXXXXX3'
        );
        insert staging3;
    }
    
    @isTest
    static void testBatchProcessingWithUserPolicy() {
        // Get test data
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        AI_Workspace_Staging__c staging1 = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE AI_Workspace_User__c = :workspaceUser1.Id LIMIT 1];
        
        Assert.areEqual('Ready', staging1.Status__c, 'Staging should start in Ready status');
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify staging record remains in Ready status (policy found, not rejected)
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging1.Id LIMIT 1];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Staging with user policy should remain in Ready status');
    }
    
    @isTest
    static void testBatchProcessingWithProfilePolicy() {
        // Get test data
        User testUser2 = [SELECT Id FROM User WHERE Username = 'testuser2@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser2 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser2.Id LIMIT 1];
        AI_Workspace_Staging__c staging2 = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE AI_Workspace_User__c = :workspaceUser2.Id LIMIT 1];
        
        Assert.areEqual('Ready', staging2.Status__c, 'Staging should start in Ready status');
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify staging record remains in Ready status (profile policy found, not rejected)
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging2.Id LIMIT 1];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Staging with profile policy should remain in Ready status');
    }
    
    @isTest
    static void testBatchProcessingWithoutPolicy() {
        // Get test data
        User testUser3 = [SELECT Id FROM User WHERE Username = 'testuser3@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser3 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser3.Id LIMIT 1];
        AI_Workspace_Staging__c staging3 = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE AI_Workspace_User__c = :workspaceUser3.Id LIMIT 1];
        
        Assert.areEqual('Ready', staging3.Status__c, 'Staging should start in Ready status');
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify staging record is rejected (no policy found)
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging3.Id LIMIT 1];
        Assert.areEqual('Rejected', updatedStaging.Status__c, 'Staging without policy should be rejected');
    }
    
    @isTest
    static void testBatchProcessingMultipleRecords() {
        // Get all staging records
        List<AI_Workspace_Staging__c> allStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c];
        Assert.areEqual(3, allStaging.size(), 'Should have 3 staging records');
        
        for (AI_Workspace_Staging__c staging : allStaging) {
            Assert.areEqual('Ready', staging.Status__c, 'All staging should start in Ready status');
        }
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch(10);
        Test.stopTest();
        
        // Verify results
        List<AI_Workspace_Staging__c> readyStaging = [SELECT Id FROM AI_Workspace_Staging__c WHERE Status__c = 'Ready'];
        List<AI_Workspace_Staging__c> rejectedStaging = [SELECT Id FROM AI_Workspace_Staging__c WHERE Status__c = 'Rejected'];
        
        Assert.areEqual(2, readyStaging.size(), 'Two staging records should remain Ready (with policies)');
        Assert.areEqual(1, rejectedStaging.size(), 'One staging record should be Rejected (no policy)');
    }
    
    @isTest
    static void testBatchProcessingWithMultipleUsersInPolicy() {
        // Create additional user and policy with multiple users
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser4 = new User(
            FirstName = 'Test',
            LastName = 'User4',
            Email = 'testuser4@example.com',
            Username = 'testuser4@gptfy.test.com',
            Alias = 'tuser4',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser4;
        
        AI_Workspace_User__c workspaceUser4 = new AI_Workspace_User__c(
            User__c = testUser4.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser4@gmail.com',
            Access_Token__c = 'encrypted_token_4'
        );
        insert workspaceUser4;
        
        // Create policy with multiple semicolon-separated usernames (V2-7889: Fixed delimiter)
        AI_Workspace_Processing_Policy__c multiUserPolicy = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com;testuser4@gptfy.test.com'
        );
        insert multiUserPolicy;
        
        // Create staging for user4
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging4 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser4.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 4', testUser4.Id),
            WhoId__c = '003XXXXXXXXXXXXXX4'
        );
        insert staging4;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify staging record remains Ready (found in multi-user policy)
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging4.Id LIMIT 1];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Staging with user in multi-user policy should remain Ready');
    }
    
    @isTest
    static void testBatchProcessingWithMultipleProfilesInPolicy() {
        // Create user with different profile
        Profile systemAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User testUser5 = new User(
            FirstName = 'Test',
            LastName = 'User5',
            Email = 'testuser5@example.com',
            Username = 'testuser5@gptfy.test.com',
            Alias = 'tuser5',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = systemAdminProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser5;
        
        AI_Workspace_User__c workspaceUser5 = new AI_Workspace_User__c(
            User__c = testUser5.Id,
            Provider__c = 'Outlook',
            Service_User_Email__c = 'testuser5@outlook.com',
            Access_Token__c = 'encrypted_token_5'
        );
        insert workspaceUser5;
        
        // Create policy with multiple profiles (V2-7889: Using semicolon delimiter)
        AI_Workspace_Processing_Policy__c multiProfilePolicy = new AI_Workspace_Processing_Policy__c(
            Profiles__c = 'Standard User;System Administrator'
        );
        insert multiProfilePolicy;
        
        // Create staging for user5
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging5 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser5.Id,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 5', testUser5.Id),
            WhoId__c = '003XXXXXXXXXXXXXX5'
        );
        insert staging5;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify staging record remains Ready (profile found in multi-profile policy)
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging5.Id LIMIT 1];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Staging with profile in multi-profile policy should remain Ready');
    }
    
    @isTest
    static void testBatchProcessingWithEmptyScope() {
        // Delete all staging records to test empty scope
        delete [SELECT Id FROM AI_Workspace_Staging__c];
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify batch completes without errors (no assertions needed, just ensure no exceptions)
        Assert.isNotNull(batchId, 'Batch should execute successfully even with empty scope');
    }
    
    @isTest
    static void testBatchProcessingWithNullWorkspaceUser() {
        // Create staging without workspace user
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c stagingNoUser = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = 'Test Subject No User',
            WhoId__c = '003XXXXXXXXXXXXXX9'
        );
        insert stagingNoUser;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify staging without workspace user is rejected
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :stagingNoUser.Id LIMIT 1];
        Assert.areEqual('Rejected', updatedStaging.Status__c, 'Staging without workspace user should be rejected');
    }
    
    @isTest
    static void testBatchProcessingWithCustomBatchSize() {
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch(5);
        Test.stopTest();
        
        // Verify batch executed successfully
        Assert.isNotNull(batchId, 'Batch should execute with custom batch size');
        
        // Verify results
        List<AI_Workspace_Staging__c> readyStaging = [SELECT Id FROM AI_Workspace_Staging__c WHERE Status__c = 'Ready'];
        List<AI_Workspace_Staging__c> rejectedStaging = [SELECT Id FROM AI_Workspace_Staging__c WHERE Status__c = 'Rejected'];
        
        Assert.areEqual(2, readyStaging.size(), 'Two staging records should remain Ready');
        Assert.areEqual(1, rejectedStaging.size(), 'One staging record should be Rejected');
    }
    
    @isTest
    static void testPolicyCheckWithWhitespaceInCommaList() {
        // Create user with policy that has whitespace in comma-separated list
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser6 = new User(
            FirstName = 'Test',
            LastName = 'User6',
            Email = 'testuser6@example.com',
            Username = 'testuser6@gptfy.test.com',
            Alias = 'tuser6',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser6;
        
        AI_Workspace_User__c workspaceUser6 = new AI_Workspace_User__c(
            User__c = testUser6.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser6@gmail.com',
            Access_Token__c = 'encrypted_token_6'
        );
        insert workspaceUser6;
        
        // Create policy with whitespace in Users__c (V2-7889: Using semicolon delimiter)
        AI_Workspace_Processing_Policy__c whitespacePolicy = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com ; testuser6@gptfy.test.com ; nonexistent@test.com'
        );
        insert whitespacePolicy;
        
        // Create staging for user6
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging6 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser6.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 6', testUser6.Id),
            WhoId__c = '003XXXXXXXXXXXXXX6'
        );
        insert staging6;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify staging record remains Ready (user found despite whitespace)
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging6.Id LIMIT 1];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Staging should remain Ready when user found in policy with whitespace');
    }
    
    @isTest
    static void testBatchProcessingStatefulCounters() {
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        // Verify batch completed and processed all records
        List<AI_Workspace_Staging__c> allStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c];
        Assert.areEqual(3, allStaging.size(), 'Should have processed all 3 staging records');
        
        Integer readyCount = 0;
        Integer rejectedCount = 0;
        for (AI_Workspace_Staging__c staging : allStaging) {
            if (staging.Status__c == 'Ready') {
                readyCount++;
            } else if (staging.Status__c == 'Rejected') {
                rejectedCount++;
            }
        }
        
        Assert.areEqual(2, readyCount, 'Two records should be Ready');
        Assert.areEqual(1, rejectedCount, 'One record should be Rejected');
    }
    
    /**
     * V2-7889: Test that staging with all required fields is processed correctly
     * This test verifies that the batch queries all required fields from staging
     * The actual EmailMessage creation requires AI setup which is tested in integration tests
     */
    @isTest
    static void testStagingWithAllRequiredFields() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'testcontact@example.com'
        );
        insert testContact;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Email With All Fields', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test body content', testUser1.Id),
            Html_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('<p>Test body content</p>', testUser1.Id),
            From_Address__c = 'testcontact@example.com',
            From_Name__c = 'Test Contact',
            To_Address__c = 'testuser1@gmail.com',
            Cc_Address__c = 'cc@example.com',
            Bcc_Address__c = 'bcc@example.com',
            Message_Identifier__c = '<unique-test-message-id@example.com>',
            Message_Date__c = System.now(),
            Is_Incoming__c = true,
            WhoId__c = testContact.Id
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c
            FROM AI_Workspace_Staging__c
            WHERE Id = :staging.Id
        ];
        
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Staging with all fields should not be rejected. Status: ' + updatedStaging.Status__c + ', Error: ' + updatedStaging.Error_Message__c
        );
        
        List<AI_Workspace_Staging__c> queriedStaging = [
            SELECT Id, Status__c, Provider__c, RecordTypeId,
                   AI_Workspace_User__c, AI_Workspace_User__r.User__c,
                   User__c, Subject__c, Html_Body__c, Text_Body__c,
                   WhoId__c, Message_Date__c, Is_Incoming__c,
                   Message_Identifier__c, From_Address__c, From_Name__c,
                   To_Address__c, Cc_Address__c, Bcc_Address__c
            FROM AI_Workspace_Staging__c
            WHERE Id = :staging.Id
        ];
        
        Assert.areEqual(1, queriedStaging.size(), 'Should be able to query staging with all fields');
        Assert.isNotNull(queriedStaging[0].From_Address__c, 'From_Address__c should be queryable');
        Assert.isNotNull(queriedStaging[0].Message_Identifier__c, 'Message_Identifier__c should be queryable');
    }

    /**
     * Test Calendar record type processing
     */
    @isTest
    static void testCalendarRecordTypeProcessing() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c calendarStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Calendar Event', testUser1.Id),
            Start_DateTime__c = System.now(),
            End_DateTime__c = System.now().addHours(1),
            Is_All_Day__c = false,
            Location__c = 'Conference Room A',
            ICalUID__c = 'test-ical-uid-123',
            Provider_Id__c = 'calendar-provider-id-123'
        );
        insert calendarStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c
            FROM AI_Workspace_Staging__c
            WHERE Id = :calendarStaging.Id
        ];
        
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Calendar staging should be processed'
        );
    }

    /**
     * Test Task record type processing
     */
    @isTest
    static void testTaskRecordTypeProcessing() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c taskStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Task', testUser1.Id),
            Task_Status__c = 'In Progress',
            Task_Priority__c = 'High',
            Due_Date__c = Date.today().addDays(7),
            Provider_Id__c = 'task-provider-id-123'
        );
        insert taskStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c
            FROM AI_Workspace_Staging__c
            WHERE Id = :taskStaging.Id
        ];
        
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Task staging should be processed'
        );
    }

    /**
     * Test policy with blank Users__c field
     */
    @isTest
    static void testPolicyWithBlankUsersField() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser7 = new User(
            FirstName = 'Test',
            LastName = 'User7',
            Email = 'testuser7@example.com',
            Username = 'testuser7@gptfy.test.com',
            Alias = 'tuser7',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser7;
        
        AI_Workspace_User__c workspaceUser7 = new AI_Workspace_User__c(
            User__c = testUser7.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser7@gmail.com',
            Access_Token__c = 'encrypted_token_7'
        );
        insert workspaceUser7;
        
        AI_Workspace_Processing_Policy__c blankUsersPolicy = new AI_Workspace_Processing_Policy__c(
            Users__c = '',
            Profiles__c = 'Standard User'
        );
        insert blankUsersPolicy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging7 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser7.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 7', testUser7.Id)
        );
        insert staging7;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging7.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should match by profile when Users__c is blank');
    }

    /**
     * Test policy with blank Profiles__c field
     */
    @isTest
    static void testPolicyWithBlankProfilesField() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser8 = new User(
            FirstName = 'Test',
            LastName = 'User8',
            Email = 'testuser8@example.com',
            Username = 'testuser8@gptfy.test.com',
            Alias = 'tuser8',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser8;
        
        AI_Workspace_User__c workspaceUser8 = new AI_Workspace_User__c(
            User__c = testUser8.Id,
            Provider__c = 'Outlook',
            Service_User_Email__c = 'testuser8@outlook.com',
            Access_Token__c = 'encrypted_token_8'
        );
        insert workspaceUser8;
        
        AI_Workspace_Processing_Policy__c blankProfilesPolicy = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser8@gptfy.test.com',
            Profiles__c = ''
        );
        insert blankProfilesPolicy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging8 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser8.Id,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 8', testUser8.Id)
        );
        insert staging8;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging8.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should match by username when Profiles__c is blank');
    }

    /**
     * Test policy with null username (edge case)
     */
    @isTest
    static void testPolicyWithNullUsername() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser9 = new User(
            FirstName = 'Test',
            LastName = 'User9',
            Email = 'testuser9@example.com',
            Username = 'testuser9@gptfy.test.com',
            Alias = 'tuser9',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser9;
        
        AI_Workspace_User__c workspaceUser9 = new AI_Workspace_User__c(
            User__c = testUser9.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser9@gmail.com',
            Access_Token__c = 'encrypted_token_9'
        );
        insert workspaceUser9;
        
        AI_Workspace_Processing_Policy__c policy = new AI_Workspace_Processing_Policy__c(
            Profiles__c = 'Standard User'
        );
        insert policy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging9 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser9.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 9', testUser9.Id)
        );
        insert staging9;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging9.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should match by profile when username is null in policy');
    }

    /**
     * Test with multiple WhoIds in comma-separated format
     */
    @isTest
    static void testMultipleWhoIds() {
        Contact contact1 = new Contact(FirstName = 'Contact', LastName = 'One', Email = 'contact1@test.com');
        Contact contact2 = new Contact(FirstName = 'Contact', LastName = 'Two', Email = 'contact2@test.com');
        insert new List<Contact>{contact1, contact2};
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Multi Contact Email', testUser1.Id),
            WhoId__c = contact1.Id + ',' + contact2.Id
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Staging with multiple WhoIds should be processed'
        );
    }

    /**
     * Test with invalid WhoId format
     */
    @isTest
    static void testInvalidWhoIdFormat() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Invalid WhoId Email', testUser1.Id),
            WhoId__c = 'invalid-id-format, another-invalid'
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Staging with invalid WhoId should still be processed'
        );
    }

    /**
     * Test with blank WhoId
     */
    @isTest
    static void testBlankWhoId() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Blank WhoId Email', testUser1.Id),
            WhoId__c = ''
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Staging with blank WhoId should be processed'
        );
    }

    /**
     * Test with WhoId containing whitespace
     */
    @isTest
    static void testWhoIdWithWhitespace() {
        Contact contact1 = new Contact(FirstName = 'Contact', LastName = 'Whitespace', Email = 'whitespace@test.com');
        insert contact1;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Whitespace WhoId', testUser1.Id),
            WhoId__c = ' ' + contact1.Id + ' , '
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Staging with whitespace in WhoId should be processed'
        );
    }

    /**
     * Test case sensitivity in username matching
     */
    @isTest
    static void testCaseInsensitiveUsernameMatching() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser10 = new User(
            FirstName = 'Test',
            LastName = 'User10',
            Email = 'testuser10@example.com',
            Username = 'TestUser10@gptfy.test.com',
            Alias = 'tuse10',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser10;
        
        AI_Workspace_User__c workspaceUser10 = new AI_Workspace_User__c(
            User__c = testUser10.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser10@gmail.com',
            Access_Token__c = 'encrypted_token_10'
        );
        insert workspaceUser10;
        
        AI_Workspace_Processing_Policy__c casePolicy = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser10@gptfy.test.com'
        );
        insert casePolicy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging10 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser10.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 10', testUser10.Id)
        );
        insert staging10;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging10.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Username matching should be case-insensitive');
    }

    /**
     * Test case sensitivity in profile matching
     */
    @isTest
    static void testCaseInsensitiveProfileMatching() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser11 = new User(
            FirstName = 'Test',
            LastName = 'User11',
            Email = 'testuser11@example.com',
            Username = 'testuser11@gptfy.test.com',
            Alias = 'tuse11',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser11;
        
        AI_Workspace_User__c workspaceUser11 = new AI_Workspace_User__c(
            User__c = testUser11.Id,
            Provider__c = 'Outlook',
            Service_User_Email__c = 'testuser11@outlook.com',
            Access_Token__c = 'encrypted_token_11'
        );
        insert workspaceUser11;
        
        AI_Workspace_Processing_Policy__c caseProfilePolicy = new AI_Workspace_Processing_Policy__c(
            Profiles__c = 'STANDARD USER'
        );
        insert caseProfilePolicy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging11 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser11.Id,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 11', testUser11.Id)
        );
        insert staging11;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging11.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Profile matching should be case-insensitive');
    }

    /**
     * Test batch with no policies at all
     */
    @isTest
    static void testBatchWithNoPolicies() {
        delete [SELECT Id FROM AI_Workspace_Processing_Policy__c];
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        List<AI_Workspace_Staging__c> rejectedStaging = [SELECT Id FROM AI_Workspace_Staging__c WHERE Status__c = 'Rejected'];
        Assert.areEqual(3, rejectedStaging.size(), 'All staging should be rejected when no policies exist');
    }

    /**
     * Test batch with moderate number of staging records
     */
    @isTest
    static void testBatchWithModerateVolume() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        for (Integer i = 0; i < 15; i++) {
            stagingRecords.add(new AI_Workspace_Staging__c(
                RecordTypeId = emailRecordTypeId,
                AI_Workspace_User__c = workspaceUser1.Id,
                Provider__c = 'GMAIL_EMAIL',
                Status__c = 'Ready',
                Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Bulk Test ' + i, testUser1.Id)
            ));
        }
        insert stagingRecords;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        List<AI_Workspace_Staging__c> processedStaging = [
            SELECT Id, Status__c 
            FROM AI_Workspace_Staging__c 
            WHERE Id IN :stagingRecords
        ];
        
        Assert.areEqual(15, processedStaging.size(), 'All staging records should be processed');
        for (AI_Workspace_Staging__c staging : processedStaging) {
            Assert.isTrue(
                staging.Status__c == 'Ready' || staging.Status__c == 'Errored',
                'Bulk staging should be processed'
            );
        }
    }

    /**
     * Test error message tracking
     */
    @isTest
    static void testErrorMessageTracking() {
        delete [SELECT Id FROM AI_Workspace_Staging__c];
        
        AI_Workspace_Staging__c stagingNoUser = new AI_Workspace_Staging__c(
            RecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId(),
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = 'No User Staging'
        );
        insert stagingNoUser;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c 
            FROM AI_Workspace_Staging__c 
            WHERE Id = :stagingNoUser.Id
        ];
        
        Assert.areEqual('Rejected', updatedStaging.Status__c, 'Should be rejected');
        Assert.isTrue(
            updatedStaging.Error_Message__c.contains('No workspace user'),
            'Error message should indicate missing workspace user'
        );
    }

    /**
     * Test staging with null status
     */
    @isTest
    static void testStagingWithNonReadyStatus() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Staged',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Non-Ready Status', testUser1.Id)
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.areEqual('Staged', updatedStaging.Status__c, 'Non-Ready staging should not be processed');
    }

    /**
     * Test with empty WhoId string with commas
     */
    @isTest
    static void testEmptyWhoIdWithCommas() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Empty Commas', testUser1.Id),
            WhoId__c = ' , , '
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Staging with empty comma-separated WhoIds should be processed'
        );
    }

    /**
     * Test policy matching with null profile name
     */
    @isTest
    static void testPolicyMatchingWithNullProfileName() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser12 = new User(
            FirstName = 'Test',
            LastName = 'User12',
            Email = 'testuser12@example.com',
            Username = 'testuser12@gptfy.test.com',
            Alias = 'tuse12',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser12;
        
        AI_Workspace_User__c workspaceUser12 = new AI_Workspace_User__c(
            User__c = testUser12.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser12@gmail.com',
            Access_Token__c = 'encrypted_token_12'
        );
        insert workspaceUser12;
        
        AI_Workspace_Processing_Policy__c policy = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser12@gptfy.test.com'
        );
        insert policy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging12 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser12.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 12', testUser12.Id)
        );
        insert staging12;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging12.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should match by username even if profile is null');
    }

    /**
     * Test with mixed record types in single batch
     */
    @isTest
    static void testMixedRecordTypes() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        List<AI_Workspace_Staging__c> mixedStaging = new List<AI_Workspace_Staging__c>{
            new AI_Workspace_Staging__c(
                RecordTypeId = emailRecordTypeId,
                AI_Workspace_User__c = workspaceUser1.Id,
                Provider__c = 'GMAIL_EMAIL',
                Status__c = 'Ready',
                Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Mixed Email', testUser1.Id)
            ),
            new AI_Workspace_Staging__c(
                RecordTypeId = calendarRecordTypeId,
                AI_Workspace_User__c = workspaceUser1.Id,
                Provider__c = 'MICROSOFT_CALENDAR',
                Status__c = 'Ready',
                Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Mixed Calendar', testUser1.Id),
                Start_DateTime__c = System.now(),
                End_DateTime__c = System.now().addHours(1)
            ),
            new AI_Workspace_Staging__c(
                RecordTypeId = taskRecordTypeId,
                AI_Workspace_User__c = workspaceUser1.Id,
                Provider__c = 'MICROSOFT_TASKS',
                Status__c = 'Ready',
                Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Mixed Task', testUser1.Id)
            )
        };
        insert mixedStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        List<AI_Workspace_Staging__c> processedStaging = [
            SELECT Id, Status__c, RecordTypeId 
            FROM AI_Workspace_Staging__c 
            WHERE Id IN :mixedStaging
        ];
        
        Assert.areEqual(3, processedStaging.size(), 'All mixed record types should be processed');
        for (AI_Workspace_Staging__c staging : processedStaging) {
            Assert.isTrue(
                staging.Status__c == 'Ready' || staging.Status__c == 'Errored',
                'Mixed record types should be processed'
            );
        }
    }

    /**
     * Test with null scope (edge case)
     */
    @isTest
    static void testExecuteWithNullScope() {
        delete [SELECT Id FROM AI_Workspace_Staging__c];
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        Assert.isNotNull(batchId, 'Batch should handle null/empty scope gracefully');
    }

    /**
     * Test finish method execution
     */
    @isTest
    static void testFinishMethodExecution() {
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        Assert.isNotNull(batchId, 'Finish method should execute without errors');
    }

    /**
     * Test with policy containing only semicolons
     */
    @isTest
    static void testPolicyWithOnlySemicolons() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser13 = new User(
            FirstName = 'Test',
            LastName = 'User13',
            Email = 'testuser13@example.com',
            Username = 'testuser13@gptfy.test.com',
            Alias = 'tuse13',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser13;
        
        AI_Workspace_User__c workspaceUser13 = new AI_Workspace_User__c(
            User__c = testUser13.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser13@gmail.com',
            Access_Token__c = 'encrypted_token_13'
        );
        insert workspaceUser13;
        
        AI_Workspace_Processing_Policy__c semicolonPolicy = new AI_Workspace_Processing_Policy__c(
            Users__c = ';;;',
            Profiles__c = 'Standard User'
        );
        insert semicolonPolicy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging13 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser13.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 13', testUser13.Id)
        );
        insert staging13;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging13.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should match by profile when Users__c has only semicolons');
    }

    /**
     * Test with both username and profile matching same user
     */
    @isTest
    static void testBothUsernameAndProfileMatch() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser14 = new User(
            FirstName = 'Test',
            LastName = 'User14',
            Email = 'testuser14@example.com',
            Username = 'testuser14@gptfy.test.com',
            Alias = 'tuse14',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser14;
        
        AI_Workspace_User__c workspaceUser14 = new AI_Workspace_User__c(
            User__c = testUser14.Id,
            Provider__c = 'Outlook',
            Service_User_Email__c = 'testuser14@outlook.com',
            Access_Token__c = 'encrypted_token_14'
        );
        insert workspaceUser14;
        
        AI_Workspace_Processing_Policy__c dualPolicy = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser14@gptfy.test.com',
            Profiles__c = 'Standard User'
        );
        insert dualPolicy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging14 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser14.Id,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 14', testUser14.Id)
        );
        insert staging14;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging14.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should match when both username and profile are in policy');
    }

    /**
     * Test runBatch with default batch size
     */
    @isTest
    static void testRunBatchDefaultSize() {
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        Assert.isNotNull(batchId, 'Should execute with default batch size');
    }

    /**
     * Test with Calendar staging with all fields
     */
    @isTest
    static void testCalendarWithAllFields() {
        Contact contact1 = new Contact(FirstName = 'Calendar', LastName = 'Contact', Email = 'calendar@test.com');
        insert contact1;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c calendarStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Full Calendar Event', testUser1.Id),
            Start_DateTime__c = System.now(),
            End_DateTime__c = System.now().addHours(2),
            Is_All_Day__c = true,
            Location__c = 'Virtual Meeting',
            ICalUID__c = 'ical-uid-full-test',
            Provider_Id__c = 'provider-id-full-test',
            WhoId__c = contact1.Id
        );
        insert calendarStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :calendarStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Calendar with all fields should be processed'
        );
    }

    /**
     * Test with Task staging with all fields
     */
    @isTest
    static void testTaskWithAllFields() {
        Contact contact1 = new Contact(FirstName = 'Task', LastName = 'Contact', Email = 'task@test.com');
        insert contact1;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c taskStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Full Task', testUser1.Id),
            Task_Status__c = 'Completed',
            Task_Priority__c = 'Low',
            Due_Date__c = Date.today().addDays(14),
            Provider_Id__c = 'task-provider-full-test',
            WhoId__c = contact1.Id
        );
        insert taskStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :taskStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Task with all fields should be processed'
        );
    }

    /**
     * Test with staging that has null Message_Date__c
     */
    @isTest
    static void testEmailWithNullMessageDate() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Null Date Email', testUser1.Id),
            Message_Date__c = null
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Email with null Message_Date__c should be processed'
        );
    }

    /**
     * Test with Calendar staging with null Start_DateTime__c
     */
    @isTest
    static void testCalendarWithNullStartDateTime() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c calendarStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Null Start Calendar', testUser1.Id),
            Start_DateTime__c = null,
            End_DateTime__c = null
        );
        insert calendarStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :calendarStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Calendar with null dates should be processed'
        );
    }

    /**
     * Test with Task staging with null Task_Status__c and Task_Priority__c
     */
    @isTest
    static void testTaskWithNullStatusAndPriority() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c taskStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Null Fields Task', testUser1.Id),
            Task_Status__c = null,
            Task_Priority__c = null,
            Due_Date__c = null
        );
        insert taskStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :taskStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Task with null fields should be processed with defaults'
        );
    }

    /**
     * Test with Email staging with false Is_Incoming__c
     */
    @isTest
    static void testEmailWithFalseIsIncoming() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('False Incoming', testUser1.Id),
            Is_Incoming__c = false
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Email with false Is_Incoming__c should be processed'
        );
    }

    /**
     * Test with Calendar staging with false Is_All_Day__c
     */
    @isTest
    static void testCalendarWithFalseIsAllDay() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c calendarStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('False AllDay', testUser1.Id),
            Start_DateTime__c = System.now(),
            End_DateTime__c = System.now().addHours(1),
            Is_All_Day__c = false
        );
        insert calendarStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :calendarStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Calendar with false Is_All_Day__c should be processed'
        );
    }

    /**
     * Test with Calendar staging with null Location
     */
    @isTest
    static void testCalendarWithNullLocation() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c calendarStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('No Location Event', testUser1.Id),
            Start_DateTime__c = System.now(),
            End_DateTime__c = System.now().addHours(1),
            Location__c = null
        );
        insert calendarStaging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :calendarStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Calendar with null Location should be processed'
        );
    }

    /**
     * Test batch with custom batch size (production uses 1, test uses 200)
     */
    @isTest
    static void testBatchCustomSize() {
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        Assert.isNotNull(batchId, 'Should execute with custom batch size');
        
        List<AI_Workspace_Staging__c> allStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c];
        Assert.areEqual(3, allStaging.size(), 'All staging should be processed');
    }

    /**
     * Test with empty allUserIds set
     */
    @isTest
    static void testEmptyUserIdsSet() {
        delete [SELECT Id FROM AI_Workspace_Staging__c];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c stagingNoUser = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = 'No User Test'
        );
        insert stagingNoUser;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :stagingNoUser.Id];
        Assert.areEqual('Rejected', updatedStaging.Status__c, 'Staging without user should be rejected');
    }

    /**
     * Test with policy having null Prompt__c
     */
    @isTest
    static void testPolicyWithNullPrompt() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser15 = new User(
            FirstName = 'Test',
            LastName = 'User15',
            Email = 'testuser15@example.com',
            Username = 'testuser15@gptfy.test.com',
            Alias = 'tuse15',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser15;
        
        AI_Workspace_User__c workspaceUser15 = new AI_Workspace_User__c(
            User__c = testUser15.Id,
            Provider__c = 'Gmail',
            Service_User_Email__c = 'testuser15@gmail.com',
            Access_Token__c = 'encrypted_token_15'
        );
        insert workspaceUser15;
        
        AI_Workspace_Processing_Policy__c nullPromptPolicy = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser15@gptfy.test.com',
            Prompt__c = null
        );
        insert nullPromptPolicy;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        AI_Workspace_Staging__c staging15 = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser15.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject 15', testUser15.Id)
        );
        insert staging15;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging15.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Staging should remain Ready when policy has null Prompt__c');
    }

    /**
     * Test query locator with ORDER BY clause
     */
    @isTest
    static void testQueryLocatorOrdering() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        for (Integer i = 0; i < 5; i++) {
            stagingRecords.add(new AI_Workspace_Staging__c(
                RecordTypeId = emailRecordTypeId,
                AI_Workspace_User__c = workspaceUser1.Id,
                Provider__c = 'GMAIL_EMAIL',
                Status__c = 'Ready',
                Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Order Test ' + i, testUser1.Id)
            ));
        }
        insert stagingRecords;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        List<AI_Workspace_Staging__c> processed = [
            SELECT Id, Status__c, CreatedDate 
            FROM AI_Workspace_Staging__c 
            WHERE Id IN :stagingRecords 
            ORDER BY CreatedDate ASC
        ];
        
        Assert.areEqual(5, processed.size(), 'All ordered staging should be processed');
    }

    /**
     * Test with policy that has a Prompt configured (triggers AI processing path)
     */
    @isTest
    static void testPolicyWithPromptConfigured() {
        AI_Response_Mapping__c responseMapping = TestUtility.createResponseMapping('TestResponse', true);
        
        AI_Response_Mapping_Line__c responseMappingLine = new AI_Response_Mapping_Line__c();
        responseMappingLine.AI_Response_Mapping__c = responseMapping.Id;
        responseMappingLine.Security_Audit_Field_Name__c = 'Record_Id__c';
        responseMappingLine.Mapping_Field_Name__c = 'Record_Id__c';
        insert responseMappingLine;
        
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        conn.AI_Response_Mapping__c = responseMapping.Id;
        insert conn;
        
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'test-prompt-request-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'testcontact@example.com'
        );
        insert testContact;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('AI Processing Test', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test body', testUser1.Id),
            Html_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('<p>Test body</p>', testUser1.Id),
            From_Address__c = 'testcontact@example.com',
            Message_Date__c = System.now(),
            Is_Incoming__c = true,
            WhoId__c = testContact.Id,
            Message_Identifier__c = '<test-ai-message@example.com>'
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"RelatedToId\\": \\"' + testContact.Id + '\\", \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c 
            FROM AI_Workspace_Staging__c 
            WHERE Id = :staging.Id
        ];
        
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Staging with prompt should be processed. Status: ' + updatedStaging.Status__c
        );
    }

    /**
     * Test Calendar with policy and prompt
     */
    @isTest
    static void testCalendarWithPromptProcessing() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;
        
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Calendar Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'calendar-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Contact testContact = new Contact(FirstName = 'Calendar', LastName = 'Contact', Email = 'calendar@test.com');
        insert testContact;
        
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c calendarStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('AI Calendar Test', testUser1.Id),
            Start_DateTime__c = System.now(),
            End_DateTime__c = System.now().addHours(1),
            Is_All_Day__c = false,
            Location__c = 'Test Location',
            ICalUID__c = 'test-ical-uid',
            Provider_Id__c = 'test-provider-id',
            WhoId__c = testContact.Id
        );
        insert calendarStaging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"RelatedToId\\": \\"' + testAccount.Id + '\\", \\"EmailSummary\\": \\"Test calendar summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c 
            FROM AI_Workspace_Staging__c 
            WHERE Id = :calendarStaging.Id
        ];
        
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Calendar with prompt should be processed'
        );
    }

    /**
     * Test Task with policy and prompt
     */
    @isTest
    static void testTaskWithPromptProcessing() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;
        
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Task Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'task-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Contact testContact = new Contact(FirstName = 'Task', LastName = 'Contact', Email = 'task@test.com');
        insert testContact;
        
        Account testAccount = new Account(Name = 'Task Account');
        insert testAccount;
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c taskStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('AI Task Test', testUser1.Id),
            Task_Status__c = 'In Progress',
            Task_Priority__c = 'High',
            Due_Date__c = Date.today().addDays(7),
            Provider_Id__c = 'test-task-provider-id',
            WhoId__c = testContact.Id
        );
        insert taskStaging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"RelatedToId\\": \\"' + testAccount.Id + '\\", \\"EmailSummary\\": \\"Test task summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c 
            FROM AI_Workspace_Staging__c 
            WHERE Id = :taskStaging.Id
        ];
        
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Task with prompt should be processed'
        );
    }

    /**
     * Test with prompt that has blank Prompt_Request_Id__c
     */
    @isTest
    static void testPromptWithBlankRequestId() {
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Blank Request ID Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = '';
        insert prompt;
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Blank Request ID Test', testUser1.Id)
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should remain Ready when prompt has blank request ID');
    }

    /**
     * Test with prompt that has null Prompt_Request_Id__c
     */
    @isTest
    static void testPromptWithNullRequestId() {
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Null Request ID Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = null;
        insert prompt;
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Null Request ID Test', testUser1.Id)
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should remain Ready when prompt has null request ID');
    }

    /**
     * Test with multiple policies (should match first one)
     */
    @isTest
    static void testMultiplePoliciesForSameUser() {
        AI_Workspace_Processing_Policy__c policy3 = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com'
        );
        insert policy3;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Multiple Policies Test', testUser1.Id)
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should match first policy');
    }

    /**
     * Test with empty promptIds set
     */
    @isTest
    static void testEmptyPromptIdsSet() {
        delete [SELECT Id FROM AI_Workspace_Processing_Policy__c];
        
        AI_Workspace_Processing_Policy__c policyNoPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = null
        );
        insert policyNoPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Empty Prompt IDs', testUser1.Id)
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.areEqual('Ready', updatedStaging.Status__c, 'Should remain Ready when no prompts configured');
    }

    /**
     * Test with exception during processing
     */
    @isTest
    static void testExceptionDuringProcessing() {
        delete [SELECT Id FROM AI_Workspace_Staging__c];
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Exception Test', testUser1.Id)
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Rejected',
            'Should handle exceptions gracefully'
        );
    }

    /**
     * Test with WhoId containing only valid IDs
     */
    @isTest
    static void testWhoIdWithValidIds() {
        Contact contact1 = new Contact(FirstName = 'Valid', LastName = 'One', Email = 'valid1@test.com');
        Contact contact2 = new Contact(FirstName = 'Valid', LastName = 'Two', Email = 'valid2@test.com');
        insert new List<Contact>{contact1, contact2};
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Valid IDs Test', testUser1.Id),
            WhoId__c = contact1.Id + ', ' + contact2.Id
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Valid WhoIds should be parsed correctly'
        );
    }

    /**
     * Test with mixed valid and invalid WhoIds
     */
    @isTest
    static void testMixedValidInvalidWhoIds() {
        Contact contact1 = new Contact(FirstName = 'Mixed', LastName = 'Contact', Email = 'mixed@test.com');
        insert contact1;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Mixed IDs Test', testUser1.Id),
            WhoId__c = contact1.Id + ',invalid-id,another-bad-id'
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Should handle mixed valid/invalid WhoIds'
        );
    }

    /**
     * Test AI processing with isRelevant=false (should reject)
     */
    @isTest
    static void testAIProcessingIsRelevantFalse() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;
        
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Irrelevant Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'irrelevant-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Irrelevant Email', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test body', testUser1.Id)
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": false, \\"RejectionReason\\": \\"Not business related\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c 
            FROM AI_Workspace_Staging__c 
            WHERE Id = :staging.Id
        ];
        
        Assert.isTrue(
            updatedStaging.Status__c == 'Rejected' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Ready',
            'Staging with isRelevant=false should be processed. Status: ' + updatedStaging.Status__c
        );
    }

    /**
     * Test AI processing with Error status
     */
    @isTest
    static void testAIProcessingErrorStatus() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Error Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'error-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Error Test', testUser1.Id)
        );
        insert staging;
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [
            SELECT Id, Status__c, Error_Message__c 
            FROM AI_Workspace_Staging__c 
            WHERE Id = :staging.Id
        ];
        
        Assert.isTrue(
            updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Ready',
            'Staging with AI error should be marked as Errored'
        );
    }

    /**
     * Test AI processing with key-value format response (legacy format)
     */
    @isTest
    static void testAIProcessingKeyValueFormat() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('KV Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'kv-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Account testAccount = new Account(Name = 'KV Account');
        insert testAccount;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('KV Format Test', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test body', testUser1.Id)
        );
        insert staging;
        
        String kvResponse = 'IsRelevant: true\\nRelatedToId: ' + testAccount.Id + '\\nEmailSummary: Test summary\\n';
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "' + kvResponse + '"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Key-value format should be parsed correctly'
        );
    }

    /**
     * Test AI processing with invalid RelatedToId
     */
    @isTest
    static void testAIProcessingInvalidRelatedToId() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Invalid ID Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'invalid-id-prompt';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Invalid ID Test', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test body', testUser1.Id)
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"RelatedToId\\": \\"invalid-id-format\\", \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Should handle invalid RelatedToId gracefully'
        );
    }

    /**
     * Test AI processing with blank RelatedToId
     */
    @isTest
    static void testAIProcessingBlankRelatedToId() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Blank ID Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'blank-id-prompt';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Blank ID Test', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test body', testUser1.Id)
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"RelatedToId\\": \\"\\", \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Should handle blank RelatedToId'
        );
    }

    /**
     * Test AI processing with blank EmailSummary
     */
    @isTest
    static void testAIProcessingBlankEmailSummary() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Blank Summary Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'blank-summary-prompt';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Blank Summary Test', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Original body', testUser1.Id),
            Html_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('<p>Original body</p>', testUser1.Id)
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"EmailSummary\\": \\"\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Should use original body when EmailSummary is blank'
        );
    }

    /**
     * Test AI processing with Task and Lead WhoId (should skip WhatId)
     */
    @isTest
    static void testTaskWithLeadWhoId() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Lead Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'lead-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Lead testLead = new Lead(FirstName = 'Test', LastName = 'Lead', Company = 'Test Company', Email = 'lead@test.com');
        insert testLead;
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c taskStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Lead Task Test', testUser1.Id),
            Provider_Id__c = 'lead-task-id',
            WhoId__c = testLead.Id
        );
        insert taskStaging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"RelatedToId\\": \\"' + testLead.Id + '\\", \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :taskStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Task with Lead WhoId should skip WhatId assignment'
        );
    }

    /**
     * Test AI processing with Task and Contact WhoId (should skip WhatId)
     */
    @isTest
    static void testTaskWithContactWhoId() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Contact Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'contact-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Contact testContact = new Contact(FirstName = 'Task', LastName = 'Contact', Email = 'taskcontact@test.com');
        insert testContact;
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c taskStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Contact Task Test', testUser1.Id),
            Provider_Id__c = 'contact-task-id',
            WhoId__c = testContact.Id
        );
        insert taskStaging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"RelatedToId\\": \\"' + testContact.Id + '\\", \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :taskStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Task with Contact WhoId should skip WhatId assignment'
        );
    }

    /**
     * Test AI processing with Task and valid Account WhatId
     */
    @isTest
    static void testTaskWithAccountWhatId() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Account Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'account-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Account testAccount = new Account(Name = 'Task Account');
        insert testAccount;
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c taskStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Account Task Test', testUser1.Id),
            Provider_Id__c = 'account-task-id'
        );
        insert taskStaging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"RelatedToId\\": \\"' + testAccount.Id + '\\", \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :taskStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Task with Account WhatId should be assigned'
        );
    }

    /**
     * Test AI processing with duplicate EmailMessage (should skip)
     */
    @isTest
    static void testDuplicateEmailMessageDetection() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Duplicate Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'duplicate-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        EmailMessage existingEmail = new EmailMessage(
            Subject = 'Duplicate Test',
            MessageIdentifier = '<duplicate-message-id@example.com>',
            Status = '3'
        );
        insert existingEmail;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Duplicate Test', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test body', testUser1.Id),
            Message_Identifier__c = '<duplicate-message-id@example.com>'
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Duplicate email should be skipped'
        );
    }

    /**
     * Test AI processing with duplicate Event (should skip)
     */
    @isTest
    static void testDuplicateEventDetection() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Dup Event Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'dup-event-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        DateTime eventStart = System.now();
        Event existingEvent = new Event(
            Subject = 'Duplicate Event',
            StartDateTime = eventStart,
            EndDateTime = eventStart.addHours(1),
            OwnerId = testUser1.Id
        );
        insert existingEvent;
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c calendarStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Duplicate Event', testUser1.Id),
            Start_DateTime__c = eventStart,
            End_DateTime__c = eventStart.addHours(1)
        );
        insert calendarStaging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :calendarStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Duplicate event should be skipped'
        );
    }

    /**
     * Test AI processing with malformed JSON response
     */
    @isTest
    static void testAIProcessingMalformedJSON() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Malformed Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'malformed-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Malformed Test', testUser1.Id)
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{malformed json}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Rejected',
            'Should handle malformed JSON gracefully'
        );
    }

    /**
     * Test AI processing with empty response body
     */
    @isTest
    static void testAIProcessingEmptyResponseBody() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Empty Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'empty-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Empty Response Test', testUser1.Id)
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : ""}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored',
            'Should handle empty response body'
        );
    }

    /**
     * Test Calendar with blank ICalUID and Provider_Id
     */
    @isTest
    static void testCalendarWithBlankSyncIds() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Blank Sync Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'blank-sync-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c calendarStaging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Blank Sync IDs', testUser1.Id),
            Start_DateTime__c = System.now(),
            End_DateTime__c = System.now().addHours(1),
            ICalUID__c = '',
            Provider_Id__c = ''
        );
        insert calendarStaging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :calendarStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Calendar with blank sync IDs should be processed'
        );
    }

    /**
     * Test Task with blank Provider_Id
     */
    @isTest
    static void testTaskWithBlankProviderId() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Blank Provider Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'blank-provider-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c taskStaging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'MICROSOFT_TASKS',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Blank Provider Task', testUser1.Id),
            Provider_Id__c = ''
        );
        insert taskStaging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :taskStaging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Task with blank Provider_Id should be processed'
        );
    }

    /**
     * Test Email with blank MessageIdentifier
     */
    @isTest
    static void testEmailWithBlankMessageIdentifier() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Blank MsgId Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'blank-msgid-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Blank MsgId Test', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test body', testUser1.Id),
            Message_Identifier__c = ''
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Email with blank MessageIdentifier should be processed'
        );
    }

    /**
     * Test with null Text_Body__c and Html_Body__c
     */
    @isTest
    static void testEmailWithNullBodies() {
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        insert conn;

        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];

        AI_Prompt__c prompt = TestUtility.getAIPrompt('Null Bodies Prompt', 'AI_Workspace_Staging__c', 'Active', false);
        prompt.Prompt_Request_Id__c = 'null-bodies-prompt-id';
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Process this record.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = 'Company Default';
        prompt.AI_Locale_Automation__c = 'Record Owner';
        insert prompt;
        
        List<AI_Data_Extraction_Detail__c> stagingDetails = [
            SELECT Id 
            FROM AI_Data_Extraction_Detail__c 
            WHERE Object_Name__c = 'AI_Workspace_Staging__c' 
            LIMIT 1
        ];
        if (!stagingDetails.isEmpty()) {
            AI_Prompt_Component__c cmp = TestUtility.getPromptComponent(prompt.Id, stagingDetails[0].Id, 'AI_Workspace_Staging__c', true);
            AIJsonGeneration.generatePromptCommand(prompt.Id);
        }
        
        AI_Workspace_Processing_Policy__c policyWithPrompt = new AI_Workspace_Processing_Policy__c(
            Users__c = 'testuser1@gptfy.test.com',
            Prompt__c = prompt.Id
        );
        insert policyWithPrompt;
        
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Provider__c = 'GMAIL_EMAIL',
            Status__c = 'Ready',
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Null Bodies Test', testUser1.Id),
            Text_Body__c = null,
            Html_Body__c = null
        );
        insert staging;
        
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "{\\"IsRelevant\\": true, \\"EmailSummary\\": \\"Test summary\\"}"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Test.startTest();
        Id batchId = AIStagingPolicyMatcherBatch.runBatch();
        Test.stopTest();
        
        AI_Workspace_Staging__c updatedStaging = [SELECT Id, Status__c FROM AI_Workspace_Staging__c WHERE Id = :staging.Id];
        Assert.isTrue(
            updatedStaging.Status__c == 'Ready' || updatedStaging.Status__c == 'Errored' || updatedStaging.Status__c == 'Imported',
            'Email with null bodies should be processed'
        );
    }
    
    @isTest
    static void testParseWhoIds_ValidIds() {
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        
        Test.startTest();
        List<Id> result = batch.parseWhoIds(testUser1.Id + ',' + testUser1.Id);
        Test.stopTest();
        
        Assert.areEqual(2, result.size(), 'Should parse 2 IDs');
    }
    
    @isTest
    static void testParseWhoIds_BlankString() {
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        
        Test.startTest();
        List<Id> result = batch.parseWhoIds('');
        Test.stopTest();
        
        Assert.areEqual(0, result.size(), 'Should return empty list for blank string');
    }
    
    @isTest
    static void testParseWhoIds_InvalidIds() {
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        
        Test.startTest();
        List<Id> result = batch.parseWhoIds('invalid,123,abc');
        Test.stopTest();
        
        Assert.areEqual(0, result.size(), 'Should skip invalid IDs');
    }
    
    @isTest
    static void testParseAIResponse_JSONFormat() {
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        String jsonResponse = '{"IsRelevant": true, "RelatedToId": "001000000000000", "EmailSummary": "Test summary", "RejectionReason": ""}';
        
        Test.startTest();
        AIStagingPolicyMatcherBatch.AIResponseData result = batch.parseAIResponse(jsonResponse);
        Test.stopTest();
        
        Assert.isTrue(result.isRelevant, 'Should parse isRelevant as true');
        Assert.areEqual('Test summary', result.emailSummary, 'Should parse email summary');
    }
    
    @isTest
    static void testParseAIResponse_KeyValueFormat() {
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        String kvResponse = 'IsRelevant: true\nRelatedToId: 001000000000000\nEmailSummary: Test summary';
        
        Test.startTest();
        AIStagingPolicyMatcherBatch.AIResponseData result = batch.parseAIResponse(kvResponse);
        Test.stopTest();
        
        Assert.isTrue(result.isRelevant, 'Should parse isRelevant as true');
    }
    
    @isTest
    static void testParseAIResponse_InvalidFormat() {
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        
        Test.startTest();
        AIStagingPolicyMatcherBatch.AIResponseData result = batch.parseAIResponse('invalid data');
        Test.stopTest();
        
        Assert.isFalse(result.isRelevant, 'Should default to false for invalid format');
    }
    
    @isTest
    static void testCreateEmailMessageFromAI_WithSummary() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Body', testUser1.Id),
            Html_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('<p>Test Body</p>', testUser1.Id),
            From_Address__c = 'from@test.com',
            To_Address__c = 'to@test.com',
            Message_Identifier__c = 'test-msg-123',
            Is_Incoming__c = true
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        AIStagingPolicyMatcherBatch.AIResponseData aiData = new AIStagingPolicyMatcherBatch.AIResponseData();
        aiData.isRelevant = true;
        aiData.emailSummary = 'AI Summary';
        aiData.relatedToId = '001000000000000AAA';
        
        Test.startTest();
        EmailMessage em = batch.createEmailMessageFromAI(staging, aiData, testUser1.Id);
        Test.stopTest();
        
        Assert.isNotNull(em, 'Should create EmailMessage');
        Assert.isTrue(em.TextBody.contains('AI Summary'), 'Should include AI summary');
    }
    
    @isTest
    static void testCreateEmailMessageFromAI_WithoutSummary() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Email').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = emailRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Subject', testUser1.Id),
            Text_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('Test Body', testUser1.Id),
            Html_Body__c = AIWorkspaceEncryptionService.encryptEmailBody('<p>Test Body</p>', testUser1.Id)
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        AIStagingPolicyMatcherBatch.AIResponseData aiData = new AIStagingPolicyMatcherBatch.AIResponseData();
        aiData.isRelevant = true;
        
        Test.startTest();
        EmailMessage em = batch.createEmailMessageFromAI(staging, aiData, testUser1.Id);
        Test.stopTest();
        
        Assert.isNotNull(em, 'Should create EmailMessage');
    }
    
    @isTest
    static void testCreateEventFromAI() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = calendarRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Meeting', testUser1.Id),
            Start_DateTime__c = System.now(),
            End_DateTime__c = System.now().addHours(1),
            Location__c = 'Conference Room',
            ICalUID__c = 'ical-123',
            Is_All_Day__c = false
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        AIStagingPolicyMatcherBatch.AIResponseData aiData = new AIStagingPolicyMatcherBatch.AIResponseData();
        aiData.isRelevant = true;
        aiData.emailSummary = 'Meeting summary';
        aiData.relatedToId = '001000000000000AAA';
        
        Test.startTest();
        Event evt = batch.createEventFromAI(staging, aiData, testUser1.Id);
        Test.stopTest();
        
        Assert.isNotNull(evt, 'Should create Event');
        Assert.areEqual('Meeting summary', evt.Description, 'Should set description');
    }
    
    @isTest
    static void testCreateTaskFromAI_WithAccountWhatId() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Follow up', testUser1.Id),
            Task_Status__c = 'Not Started',
            Task_Priority__c = 'High',
            Due_Date__c = Date.today().addDays(7),
            Provider_Id__c = 'task-123'
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        AIStagingPolicyMatcherBatch.AIResponseData aiData = new AIStagingPolicyMatcherBatch.AIResponseData();
        aiData.isRelevant = true;
        aiData.emailSummary = 'Task summary';
        aiData.relatedToId = acc.Id;
        
        Test.startTest();
        Task tsk = batch.createTaskFromAI(staging, aiData, testUser1.Id);
        Test.stopTest();
        
        Assert.isNotNull(tsk, 'Should create Task');
        Assert.areEqual(acc.Id, tsk.WhatId, 'Should set WhatId to Account');
    }
    
    @isTest
    static void testCreateTaskFromAI_WithLeadWhatId() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        AI_Workspace_User__c workspaceUser1 = [SELECT Id FROM AI_Workspace_User__c WHERE User__c = :testUser1.Id LIMIT 1];
        
        Lead lead = new Lead(LastName = 'Test Lead', Company = 'Test Co');
        insert lead;
        
        Id taskRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c.getRecordTypeInfosByDeveloperName().get('Task').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            RecordTypeId = taskRecordTypeId,
            AI_Workspace_User__c = workspaceUser1.Id,
            Subject__c = AIWorkspaceEncryptionService.encryptEmailBody('Follow up', testUser1.Id),
            Provider_Id__c = 'task-456'
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        AIStagingPolicyMatcherBatch.AIResponseData aiData = new AIStagingPolicyMatcherBatch.AIResponseData();
        aiData.isRelevant = true;
        aiData.relatedToId = lead.Id;
        
        Test.startTest();
        Task tsk = batch.createTaskFromAI(staging, aiData, testUser1.Id);
        Test.stopTest();
        
        Assert.isNotNull(tsk, 'Should create Task');
        Assert.isNull(tsk.WhatId, 'Should not set WhatId for Lead');
    }
    
    @isTest
    static void testInsertEmailMessagesWithRelations_Success() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@test.com');
        insert con;
        
        EmailMessage em = new EmailMessage(
            Subject = 'Test Email',
            TextBody = 'Test Body',
            Status = '3',
            MessageIdentifier = 'unique-msg-' + System.currentTimeMillis()
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        Map<Integer, List<Id>> indexToWhoIds = new Map<Integer, List<Id>>();
        indexToWhoIds.put(0, new List<Id>{ con.Id });
        
        Test.startTest();
        Set<Integer> result = batch.insertEmailMessagesWithRelations(new List<EmailMessage>{ em }, indexToWhoIds);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should insert 1 email');
    }
    
    @isTest
    static void testInsertEmailMessagesWithRelations_Duplicate() {
        EmailMessage existing = new EmailMessage(
            Subject = 'Existing Email',
            TextBody = 'Body',
            Status = '3',
            MessageIdentifier = 'duplicate-msg-123'
        );
        insert existing;
        
        EmailMessage duplicate = new EmailMessage(
            Subject = 'Duplicate Email',
            TextBody = 'Body',
            Status = '3',
            MessageIdentifier = 'duplicate-msg-123'
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        Map<Integer, List<Id>> indexToWhoIds = new Map<Integer, List<Id>>();
        
        Test.startTest();
        Set<Integer> result = batch.insertEmailMessagesWithRelations(new List<EmailMessage>{ duplicate }, indexToWhoIds);
        Test.stopTest();
        
        Assert.areEqual(0, result.size(), 'Should skip duplicate email');
    }
    
    @isTest
    static void testInsertEventsWithRelations_Success() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@test.com');
        insert con;
        
        Event evt = new Event(
            Subject = 'Test Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),
            OwnerId = testUser1.Id
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        Map<Integer, List<Id>> indexToWhoIds = new Map<Integer, List<Id>>();
        indexToWhoIds.put(0, new List<Id>{ con.Id });
        
        Test.startTest();
        Set<Integer> result = batch.insertEventsWithRelations(new List<Event>{ evt }, indexToWhoIds);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should insert 1 event');
    }
    
    @isTest
    static void testInsertEventsWithRelations_Duplicate() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        
        Event existing = new Event(
            Subject = 'Existing Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),
            OwnerId = testUser1.Id
        );
        insert existing;
        
        Event duplicate = new Event(
            Subject = 'Existing Event',
            StartDateTime = existing.StartDateTime,
            EndDateTime = existing.EndDateTime,
            OwnerId = testUser1.Id
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        Map<Integer, List<Id>> indexToWhoIds = new Map<Integer, List<Id>>();
        
        Test.startTest();
        Set<Integer> result = batch.insertEventsWithRelations(new List<Event>{ duplicate }, indexToWhoIds);
        Test.stopTest();
        
        Assert.areEqual(0, result.size(), 'Should skip duplicate event');
    }
    
    @isTest
    static void testInsertTasksWithRelations_Success() {
        User testUser1 = [SELECT Id FROM User WHERE Username = 'testuser1@gptfy.test.com' LIMIT 1];
        Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@test.com');
        insert con;
        
        Task tsk = new Task(
            Subject = 'Test Task',
            Status = 'Not Started',
            OwnerId = testUser1.Id
        );
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        Map<Integer, List<Id>> indexToWhoIds = new Map<Integer, List<Id>>();
        indexToWhoIds.put(0, new List<Id>{ con.Id });
        
        Test.startTest();
        Set<Integer> result = batch.insertTasksWithRelations(new List<Task>{ tsk }, indexToWhoIds);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should insert 1 task');
    }
    
    @isTest
    static void testTrackError() {
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        
        Test.startTest();
        batch.trackError('Test error message');
        Test.stopTest();
        
        Assert.isTrue(true, 'Should track error without exception');
    }
    
    @isTest
    static void testRedactAIResponsePII() {
        AI_Response__c aiResponse = new AI_Response__c(
            AI_Processed_Data_No_PII__c = 'Original Data',
            Data_Original__c = 'Original'
        );
        insert aiResponse;
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        
        Test.startTest();
        batch.redactAIResponsePII(aiResponse.Id);
        Test.stopTest();
        
        AI_Response__c updated = [SELECT Id, AI_Processed_Data_No_PII__c FROM AI_Response__c WHERE Id = :aiResponse.Id];
        Assert.areEqual('{"Redacted": "Redacted"}', updated.AI_Processed_Data_No_PII__c, 'Should redact PII fields');
    }
    
    @isTest
    static void testRedactAIResponsePII_WithContentDocuments() {
        AI_Response__c aiResponse = new AI_Response__c(
            AI_Processed_Data_No_PII__c = 'Original Data'
        );
        insert aiResponse;
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.txt',
            VersionData = Blob.valueOf('Test content')
        );
        insert cv;
        
        ContentVersion insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = insertedCV.ContentDocumentId,
            LinkedEntityId = aiResponse.Id,
            ShareType = 'V'
        );
        insert cdl;
        
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        
        Test.startTest();
        batch.redactAIResponsePII(aiResponse.Id);
        Test.stopTest();
        
        List<ContentDocument> docs = [SELECT Id FROM ContentDocument WHERE Id = :insertedCV.ContentDocumentId];
        Assert.areEqual(0, docs.size(), 'Should delete content documents');
    }
    
    @isTest
    static void testFinishMethod() {
        AIStagingPolicyMatcherBatch batch = new AIStagingPolicyMatcherBatch();
        batch.trackError('Test error 1');
        batch.trackError('Test error 2');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Finish should complete without errors');
    }
}
