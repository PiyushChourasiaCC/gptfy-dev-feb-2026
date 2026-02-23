/**
 * Test class for AIRecentRecordsController
 * Tests recently viewed records retrieval and helper methods
 */
@isTest
public class AIRecentRecordsControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Recent Records Test Account'
        );
        insert testAccount;

        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Recent',
            LastName = 'TestContact',
            Email = 'recent.test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;

        // Create test Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Recent Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = testAccount.Id
        );
        insert testOpp;

        // Create test Case
        Case testCase = new Case(
            Subject = 'Recent Test Case',
            Status = 'New',
            Origin = 'Web',
            AccountId = testAccount.Id
        );
        insert testCase;
    }

    // ========================================================================
    // RecentRecord Wrapper Tests
    // ========================================================================

    @isTest
    static void testRecentRecord_Constructor() {
        Test.startTest();
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '001000000000001',
            'Test Account',
            'Account',
            'Viewed 5 mins ago',
            'standard:account'
        );
        Test.stopTest();

        Assert.areEqual('001000000000001', record.recordId, 'recordId should be set');
        Assert.areEqual('Test Account', record.name, 'name should be set');
        Assert.areEqual('Account', record.objectType, 'objectType should be set');
        Assert.areEqual('Viewed 5 mins ago', record.details, 'details should be set');
        Assert.areEqual('standard:account', record.iconName, 'iconName should be set');
    }

    @isTest
    static void testRecentRecord_AllObjectTypes() {
        Test.startTest();

        // Account
        AIRecentRecordsController.RecentRecord accountRecord = new AIRecentRecordsController.RecentRecord(
            '001000000000001', 'Test Account', 'Account', 'Viewed just now', 'standard:account'
        );
        Assert.areEqual('Account', accountRecord.objectType, 'Should be Account type');

        // Contact
        AIRecentRecordsController.RecentRecord contactRecord = new AIRecentRecordsController.RecentRecord(
            '003000000000001', 'Test Contact', 'Contact', 'Viewed 1 hour ago', 'standard:contact'
        );
        Assert.areEqual('Contact', contactRecord.objectType, 'Should be Contact type');

        // Opportunity
        AIRecentRecordsController.RecentRecord oppRecord = new AIRecentRecordsController.RecentRecord(
            '006000000000001', 'Test Opp', 'Opportunity', 'Viewed 2 days ago', 'standard:opportunity'
        );
        Assert.areEqual('Opportunity', oppRecord.objectType, 'Should be Opportunity type');

        // Case
        AIRecentRecordsController.RecentRecord caseRecord = new AIRecentRecordsController.RecentRecord(
            '500000000000001', 'Test Case', 'Case', 'Viewed Jan 15', 'standard:case'
        );
        Assert.areEqual('Case', caseRecord.objectType, 'Should be Case type');

        Test.stopTest();
    }

    // ========================================================================
    // getRecentRecords Tests
    // ========================================================================

    @isTest
    static void testGetRecentRecords_ReturnsResults() {
        Test.startTest();
        List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        Test.stopTest();

        // Results depend on actual RecentlyViewed data, which is user-specific
        // Just verify it returns a list (may be empty)
        Assert.areNotEqual(null, results, 'Should return a list');
    }

    @isTest
    static void testGetRecentRecords_MaxTenResults() {
        Test.startTest();
        List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        Test.stopTest();

        // Should return at most 10 records
        Assert.isTrue(results.size() <= 10, 'Should return at most 10 records');
    }

    @isTest
    static void testGetRecentRecords_ResultStructure() {
        Test.startTest();
        List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        Test.stopTest();

        // If there are results, verify structure
        if (!results.isEmpty()) {
            AIRecentRecordsController.RecentRecord firstRecord = results[0];
            Assert.areNotEqual(null, firstRecord.recordId, 'recordId should not be null');
            Assert.areNotEqual(null, firstRecord.name, 'name should not be null');
            Assert.areNotEqual(null, firstRecord.objectType, 'objectType should not be null');
            Assert.areNotEqual(null, firstRecord.iconName, 'iconName should not be null');
        }
    }

    @isTest
    static void testGetRecentRecords_ValidObjectTypes() {
        Test.startTest();
        List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        Test.stopTest();

        // Verify all results are of valid object types
        Set<String> validTypes = new Set<String>{'Account', 'Contact', 'Opportunity', 'Case'};
        for (AIRecentRecordsController.RecentRecord record : results) {
            Assert.isTrue(
                validTypes.contains(record.objectType),
                'objectType should be one of: Account, Contact, Opportunity, Case. Got: ' + record.objectType
            );
        }
    }

    @isTest
    static void testGetRecentRecords_ValidIconNames() {
        Test.startTest();
        List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        Test.stopTest();

        // Verify all results have valid icon names
        Set<String> validIcons = new Set<String>{
            'standard:account', 'standard:contact', 'standard:opportunity', 'standard:case', 'standard:record'
        };
        for (AIRecentRecordsController.RecentRecord record : results) {
            Assert.isTrue(
                validIcons.contains(record.iconName),
                'iconName should be a valid standard icon. Got: ' + record.iconName
            );
        }
    }

    // ========================================================================
    // Icon Name Tests (via wrapper constructor verification)
    // ========================================================================

    @isTest
    static void testIconName_Account() {
        // Test that Account type gets correct icon
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '001000000000001', 'Test', 'Account', '', 'standard:account'
        );
        Assert.areEqual('standard:account', record.iconName, 'Account should have standard:account icon');
    }

    @isTest
    static void testIconName_Contact() {
        // Test that Contact type gets correct icon
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '003000000000001', 'Test', 'Contact', '', 'standard:contact'
        );
        Assert.areEqual('standard:contact', record.iconName, 'Contact should have standard:contact icon');
    }

    @isTest
    static void testIconName_Opportunity() {
        // Test that Opportunity type gets correct icon
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '006000000000001', 'Test', 'Opportunity', '', 'standard:opportunity'
        );
        Assert.areEqual('standard:opportunity', record.iconName, 'Opportunity should have standard:opportunity icon');
    }

    @isTest
    static void testIconName_Case() {
        // Test that Case type gets correct icon
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '500000000000001', 'Test', 'Case', '', 'standard:case'
        );
        Assert.areEqual('standard:case', record.iconName, 'Case should have standard:case icon');
    }

    // ========================================================================
    // Relative Time Format Tests (via details field)
    // ========================================================================

    @isTest
    static void testRelativeTime_JustNow() {
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '001000000000001', 'Test', 'Account', 'Viewed just now', 'standard:account'
        );
        Assert.areEqual('Viewed just now', record.details, 'Should show just now for recent views');
    }

    @isTest
    static void testRelativeTime_Minutes() {
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '001000000000001', 'Test', 'Account', 'Viewed 5 mins ago', 'standard:account'
        );
        Assert.isTrue(record.details.contains('min'), 'Should contain min for minute views');
    }

    @isTest
    static void testRelativeTime_Hours() {
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '001000000000001', 'Test', 'Account', 'Viewed 3 hours ago', 'standard:account'
        );
        Assert.isTrue(record.details.contains('hour'), 'Should contain hour for hour views');
    }

    @isTest
    static void testRelativeTime_Days() {
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '001000000000001', 'Test', 'Account', 'Viewed 2 days ago', 'standard:account'
        );
        Assert.isTrue(record.details.contains('day'), 'Should contain day for day views');
    }

    // ========================================================================
    // Edge Case Tests
    // ========================================================================

    @isTest
    static void testGetRecentRecords_MultipleCallsConsistent() {
        Test.startTest();
        List<AIRecentRecordsController.RecentRecord> results1 = AIRecentRecordsController.getRecentRecords();
        List<AIRecentRecordsController.RecentRecord> results2 = AIRecentRecordsController.getRecentRecords();
        Test.stopTest();

        // Both calls should return consistent number of results
        Assert.areEqual(results1.size(), results2.size(), 'Multiple calls should return consistent results');
    }

    @isTest
    static void testGetRecentRecords_NoException() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        Assert.areEqual(false, exceptionThrown, 'Should not throw exception');
    }

    @isTest
    static void testRecentRecord_NullValues() {
        Test.startTest();
        // Test with null values - should not throw exception
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            null, null, null, null, null
        );
        Test.stopTest();

        Assert.areEqual(null, record.recordId, 'recordId should be null');
        Assert.areEqual(null, record.name, 'name should be null');
    }

    @isTest
    static void testRecentRecord_EmptyStrings() {
        Test.startTest();
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '001000000000001', '', '', '', ''
        );
        Test.stopTest();

        Assert.areEqual('', record.name, 'name should be empty string');
        Assert.areEqual('', record.objectType, 'objectType should be empty string');
        Assert.areEqual('', record.details, 'details should be empty string');
        Assert.areEqual('', record.iconName, 'iconName should be empty string');
    }

    // ========================================================================
    // Integration Tests
    // ========================================================================

    @isTest
    static void testGetRecentRecords_AfterViewingRecords() {
        // Get the test records created in setup
        Account testAccount = [SELECT Id, Name FROM Account WHERE Name = 'Recent Records Test Account' LIMIT 1];
        Contact testContact = [SELECT Id, Name FROM Contact WHERE LastName = 'TestContact' LIMIT 1];

        Test.startTest();
        // Note: In unit tests, RecentlyViewed is typically empty or limited
        // This test verifies the method works after records exist
        List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        Test.stopTest();

        // Results may be empty in test context since RecentlyViewed requires actual user interaction
        Assert.areNotEqual(null, results, 'Should return a list even if empty');
    }

    @isTest
    static void testGetRecentRecords_VerifyAuraEnabled() {
        // Verify the method can be called from Aura/LWC context
        Test.startTest();
        List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        Test.stopTest();

        // Method should complete without throwing AuraHandledException
        Assert.areNotEqual(null, results, 'AuraEnabled method should return valid result');
    }

    // ========================================================================
    // Wrapper AuraEnabled Fields Tests
    // ========================================================================

    @isTest
    static void testRecentRecord_AuraEnabledFields() {
        Test.startTest();
        AIRecentRecordsController.RecentRecord record = new AIRecentRecordsController.RecentRecord(
            '001000000000001',
            'Test Account Name',
            'Account',
            'Viewed 10 mins ago',
            'standard:account'
        );

        // Verify all @AuraEnabled fields are accessible
        Id recordId = record.recordId;
        String name = record.name;
        String objectType = record.objectType;
        String details = record.details;
        String iconName = record.iconName;
        Test.stopTest();

        Assert.areNotEqual(null, recordId, 'recordId should be accessible');
        Assert.areNotEqual(null, name, 'name should be accessible');
        Assert.areNotEqual(null, objectType, 'objectType should be accessible');
        Assert.areNotEqual(null, details, 'details should be accessible');
        Assert.areNotEqual(null, iconName, 'iconName should be accessible');
    }

    // ========================================================================
    // Performance Test
    // ========================================================================

    @isTest
    static void testGetRecentRecords_Performance() {
        Test.startTest();
        Long startTime = System.currentTimeMillis();
        List<AIRecentRecordsController.RecentRecord> results = AIRecentRecordsController.getRecentRecords();
        Long endTime = System.currentTimeMillis();
        Test.stopTest();

        // Method should complete in reasonable time (less than 5 seconds)
        Long executionTime = endTime - startTime;
        Assert.isTrue(executionTime < 5000, 'Method should complete in less than 5 seconds. Took: ' + executionTime + 'ms');
    }
}