@isTest
private class AISmartMatchingEngineTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test Account with Website
        Account testAccount1 = new Account(
            Name = 'Acme Corporation',
            Website = 'https://www.acme.com'
        );
        insert testAccount1;
        
        Account testAccount2 = new Account(
            Name = 'Global Industries',
            Website = 'globalindustries.com'
        );
        insert testAccount2;
        
        Account testAccount3 = new Account(
            Name = 'Tech Solutions',
            Website = 'http://tech-solutions.io'
        );
        insert testAccount3;
        
        // Create test Contact with exact email match
        Contact testContact = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@acme.com',
            AccountId = testAccount1.Id
        );
        insert testContact;
        
        // Create test Lead with exact email match
        Lead testLead = new Lead(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'jane.smith@globalindustries.com',
            Company = 'Global Industries'
        );
        insert testLead;
    }
    
    @isTest
    static void testFindMatches_ExactEmailMatch_Contact() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'john.doe@acme.com',
            'John Doe',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should find the Contact with exact email match
        Assert.isTrue(results.size() > 0, 'Should find at least one match');
        
        Boolean foundContact = false;
        for (AISmartMatchingEngine.MatchResult result : results) {
            if (result.objectType == 'Contact' && result.email == 'john.doe@acme.com') {
                foundContact = true;
                Assert.areEqual(95, result.confidence, 'Contact exact match should have 95 confidence');
                break;
            }
        }
        
        Assert.isTrue(foundContact, 'Should find Contact with exact email match');
    }
    
    @isTest
    static void testFindMatches_ExactEmailMatch_Lead() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'jane.smith@globalindustries.com',
            'Jane Smith',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should find the Lead with exact email match
        Assert.isTrue(results.size() > 0, 'Should find at least one match');
        
        Boolean foundLead = false;
        for (AISmartMatchingEngine.MatchResult result : results) {
            if (result.objectType == 'Lead' && result.email == 'jane.smith@globalindustries.com') {
                foundLead = true;
                Assert.areEqual(95, result.confidence, 'Lead exact match should have 95 confidence');
                break;
            }
        }
        
        Assert.isTrue(foundLead, 'Should find Lead with exact email match');
    }
    
    @isTest
    static void testFindMatches_DomainMatch_Account() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'sales@acme.com',
            'Sales Team',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should find the Account with domain match
        Assert.isTrue(results.size() > 0, 'Should find at least one match');
        
        Boolean foundAccount = false;
        for (AISmartMatchingEngine.MatchResult result : results) {
            if (result.objectType == 'Account' && result.recordName == 'Acme Corporation') {
                foundAccount = true;
                Assert.areEqual(80, result.confidence, 'Account domain match should have 80 confidence');
                Assert.isTrue(result.details.contains('acme.com'), 'Details should contain domain');
                break;
            }
        }
        
        Assert.isTrue(foundAccount, 'Should find Account with domain match');
    }
    
    @isTest
    static void testFindMatches_DomainMatch_MultipleFormats() {
        Test.startTest();
        
        // Test with different email formats for the same domain
        List<AISmartMatchingEngine.MatchResult> results1 = AISmartMatchingEngine.findMatches(
            'info@globalindustries.com',
            'Info Team',
            'Test Subject'
        );
        
        List<AISmartMatchingEngine.MatchResult> results2 = AISmartMatchingEngine.findMatches(
            'support@tech-solutions.io',
            'Support Team',
            'Test Subject'
        );
        
        Test.stopTest();
        
        // Should find Global Industries account
        Boolean foundGlobal = false;
        for (AISmartMatchingEngine.MatchResult result : results1) {
            if (result.objectType == 'Account' && result.recordName == 'Global Industries') {
                foundGlobal = true;
                break;
            }
        }
        Assert.isTrue(foundGlobal, 'Should find Global Industries with domain match');
        
        // Should find Tech Solutions account
        Boolean foundTech = false;
        for (AISmartMatchingEngine.MatchResult result : results2) {
            if (result.objectType == 'Account' && result.recordName == 'Tech Solutions') {
                foundTech = true;
                break;
            }
        }
        Assert.isTrue(foundTech, 'Should find Tech Solutions with domain match');
    }
    
    @isTest
    static void testFindMatches_CombinedResults_ContactAndAccount() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'john.doe@acme.com',
            'John Doe',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should find both Contact (exact match) and Account (domain match)
        Boolean foundContact = false;
        Boolean foundAccount = false;
        
        for (AISmartMatchingEngine.MatchResult result : results) {
            if (result.objectType == 'Contact' && result.email == 'john.doe@acme.com') {
                foundContact = true;
            }
            if (result.objectType == 'Account' && result.recordName == 'Acme Corporation') {
                foundAccount = true;
            }
        }
        
        Assert.isTrue(foundContact, 'Should find Contact with exact email match');
        Assert.isTrue(foundAccount, 'Should find Account with domain match');
    }
    
    @isTest
    static void testFindMatches_NoMatches() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'nomatch@example.com',
            'No Match',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should return empty list when no matches found
        Assert.areEqual(0, results.size(), 'Should return empty list when no matches found');
    }
    
    @isTest
    static void testFindMatches_NullEmail() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            null,
            'Test Name',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should return empty list for null email
        Assert.areEqual(0, results.size(), 'Should return empty list for null email');
    }
    
    @isTest
    static void testFindMatches_BlankEmail() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            '',
            'Test Name',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should return empty list for blank email
        Assert.areEqual(0, results.size(), 'Should return empty list for blank email');
    }
    
    @isTest
    static void testFindMatches_InvalidEmail() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'invalidemail',
            'Test Name',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should return empty list for invalid email format
        Assert.areEqual(0, results.size(), 'Should return empty list for invalid email format');
    }
    
    @isTest
    static void testFindMatches_ResultsSortedByConfidence() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'john.doe@acme.com',
            'John Doe',
            'Test Subject'
        );
        Test.stopTest();
        
        // Results should be sorted by confidence (descending)
        if (results.size() > 1) {
            for (Integer i = 0; i < results.size() - 1; i++) {
                Assert.isTrue(
                    results[i].confidence >= results[i + 1].confidence,
                    'Results should be sorted by confidence (descending)'
                );
            }
        }
    }
    
    @isTest
    static void testFindMatches_NoDuplicates() {
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'john.doe@acme.com',
            'John Doe',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should not have duplicate record IDs
        Set<Id> recordIds = new Set<Id>();
        for (AISmartMatchingEngine.MatchResult result : results) {
            Assert.isFalse(recordIds.contains(result.recordId), 'Should not have duplicate records');
            recordIds.add(result.recordId);
        }
    }
    
    @isTest
    static void testMatchResult_Comparable() {
        AISmartMatchingEngine.MatchResult result1 = new AISmartMatchingEngine.MatchResult(
            null, 'Test 1', 'Contact', 'test1@example.com', 'Details', 'standard:contact', 95
        );
        
        AISmartMatchingEngine.MatchResult result2 = new AISmartMatchingEngine.MatchResult(
            null, 'Test 2', 'Account', 'test2@example.com', 'Details', 'standard:account', 80
        );
        
        // Test compareTo method
        Assert.isTrue(result1.compareTo(result2) < 0, 'Higher confidence should come first');
        Assert.isTrue(result2.compareTo(result1) > 0, 'Lower confidence should come after');
        Assert.areEqual(0, result1.compareTo(result1), 'Same object should be equal');
    }
    
    @isTest
    static void testFindMatches_PublicEmailDomain_NoAccountMatch() {
        // Create Account with gmail domain (should not match)
        Account gmailAccount = new Account(
            Name = 'Gmail Test Account',
            Website = 'https://gmail.com'
        );
        insert gmailAccount;
        
        Test.startTest();
        List<AISmartMatchingEngine.MatchResult> results = AISmartMatchingEngine.findMatches(
            'user@gmail.com',
            'Test User',
            'Test Subject'
        );
        Test.stopTest();
        
        // Should NOT find Account with public email domain
        Boolean foundGmailAccount = false;
        for (AISmartMatchingEngine.MatchResult result : results) {
            if (result.objectType == 'Account' && result.recordName == 'Gmail Test Account') {
                foundGmailAccount = true;
                break;
            }
        }
        
        Assert.isFalse(foundGmailAccount, 'Should not match Accounts with public email domains');
    }
}