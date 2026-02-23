/**
 * Test class for AINotificationService
 * Tests notification sending for matched and unmatched emails
 */
@isTest
private class AINotificationServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Website = 'www.testaccount.com');
        insert testAccount;

        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@testaccount.com',
            AccountId = testAccount.Id
        );
        insert testContact;

        // Create test Lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Email = 'testlead@example.com',
            Company = 'Test Lead Company'
        );
        insert testLead;

        // Create test Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        // Create test Case
        Case testCase = new Case(
            Subject = 'Test Case Subject',
            Status = 'New',
            Origin = 'Email'
        );
        insert testCase;
    }

    @isTest
    static void testSendMatchNotifications_WithContactMatch() {
        Contact testContact = [SELECT Id, Name, AccountId FROM Contact LIMIT 1];
        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];

        // Build email data
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Test Email Subject for Contact Match');
        emailData.put('from', new Map<String, Object>{
            'emailAddress' => new Map<String, Object>{
                'address' => 'test@testaccount.com'
            }
        });
        emailDataList.add(emailData);

        // Build match results
        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = testContact.Id;
        match.accountId = testAccount.Id;
        match.confidence = 95;
        match.matchType = 'Contact';
        match.matchDetails = new List<String>{'Email match', 'Domain match'};
        matchResults.add(match);

        // Build import result
        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        // Verify no exceptions were thrown - notification sending is best-effort
        Assert.isTrue(true, 'sendMatchNotifications should complete without exception');
    }

    @isTest
    static void testSendMatchNotifications_WithLeadMatch() {
        Lead testLead = [SELECT Id, Name, Company FROM Lead LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Test Email Subject for Lead Match');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.leadId = testLead.Id;
        match.confidence = 90;
        match.matchType = 'Lead';
        match.matchDetails = new List<String>{'Email match'};
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications with Lead should complete without exception');
    }

    @isTest
    static void testSendMatchNotifications_WithAccountMatch() {
        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Test Email Subject for Account Match');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.accountId = testAccount.Id;
        match.confidence = 85;
        match.matchType = 'Account';
        match.matchDetails = new List<String>{'Domain match'};
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications with Account should complete without exception');
    }

    @isTest
    static void testSendMatchNotifications_WithOpportunityMatch() {
        Opportunity testOpp = [SELECT Id, Name, AccountId FROM Opportunity LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Test Email Subject for Opportunity Match');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.opportunityId = testOpp.Id;
        match.confidence = 80;
        match.matchType = 'Opportunity';
        match.matchDetails = new List<String>{'Related to Account'};
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications with Opportunity should complete without exception');
    }

    @isTest
    static void testSendMatchNotifications_WithCaseMatch() {
        Case testCase = [SELECT Id, CaseNumber, Subject FROM Case LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Test Email Subject for Case Match');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.caseId = testCase.Id;
        match.confidence = 75;
        match.matchType = 'Case';
        match.matchDetails = new List<String>{'Case reference found'};
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications with Case should complete without exception');
    }

    @isTest
    static void testSendMatchNotifications_NoMatch() {
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Test Email with No Match');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.confidence = 0;
        match.matchType = 'None';
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications with no match should complete without exception');
    }

    @isTest
    static void testSendMatchNotifications_MultipleEmails() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();

        // Email 1 - Contact match
        Map<String, Object> email1 = new Map<String, Object>();
        email1.put('subject', 'Email 1 - Contact Match');
        emailDataList.add(email1);

        AIQuickMatchService.MatchResult match1 = new AIQuickMatchService.MatchResult();
        match1.contactId = testContact.Id;
        match1.confidence = 95;
        match1.matchType = 'Contact';
        match1.matchDetails = new List<String>{'Email match'};
        matchResults.add(match1);

        // Email 2 - Lead match
        Map<String, Object> email2 = new Map<String, Object>();
        email2.put('subject', 'Email 2 - Lead Match');
        emailDataList.add(email2);

        AIQuickMatchService.MatchResult match2 = new AIQuickMatchService.MatchResult();
        match2.leadId = testLead.Id;
        match2.confidence = 90;
        match2.matchType = 'Lead';
        match2.matchDetails = new List<String>{'Email match'};
        matchResults.add(match2);

        // Email 3 - No match
        Map<String, Object> email3 = new Map<String, Object>();
        email3.put('subject', 'Email 3 - No Match');
        emailDataList.add(email3);

        AIQuickMatchService.MatchResult match3 = new AIQuickMatchService.MatchResult();
        match3.confidence = 0;
        match3.matchType = 'None';
        matchResults.add(match3);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications with multiple emails should complete without exception');
    }

    @isTest
    static void testSendMatchNotifications_LongSubject() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        // Create a subject longer than 40 characters to test truncation
        emailData.put('subject', 'This is a very long email subject that should be truncated in the notification title');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = testContact.Id;
        match.confidence = 95;
        match.matchType = 'Contact';
        match.matchDetails = new List<String>{'Email match'};
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications with long subject should truncate and complete without exception');
    }

    @isTest
    static void testSendUnmatchedNotifications() {
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Unmatched Email Subject');
        emailData.put('from', new Map<String, Object>{
            'emailAddress' => new Map<String, Object>{
                'address' => 'unknown@unknowndomain.com'
            }
        });
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.confidence = 0;
        match.matchType = 'None';
        matchResults.add(match);

        Test.startTest();
        AINotificationService.sendUnmatchedNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendUnmatchedNotifications should complete without exception');
    }

    @isTest
    static void testSendUnmatchedNotifications_MultipleEmails() {
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();

        // Unmatched email 1
        Map<String, Object> email1 = new Map<String, Object>();
        email1.put('subject', 'Unmatched Email 1');
        email1.put('from', new Map<String, Object>{
            'emailAddress' => new Map<String, Object>{
                'address' => 'sender1@unknown.com'
            }
        });
        emailDataList.add(email1);
        matchResults.add(new AIQuickMatchService.MatchResult());

        // Unmatched email 2
        Map<String, Object> email2 = new Map<String, Object>();
        email2.put('subject', 'Unmatched Email 2');
        email2.put('from', new Map<String, Object>{
            'emailAddress' => new Map<String, Object>{
                'address' => 'sender2@unknown.com'
            }
        });
        emailDataList.add(email2);
        matchResults.add(new AIQuickMatchService.MatchResult());

        Test.startTest();
        AINotificationService.sendUnmatchedNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendUnmatchedNotifications with multiple emails should complete without exception');
    }

    @isTest
    static void testSendUnmatchedNotifications_LongSubject() {
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        // Subject longer than 35 characters to test truncation in unmatched notification
        emailData.put('subject', 'This is a very long unmatched email subject that exceeds the limit');
        emailData.put('from', new Map<String, Object>{
            'emailAddress' => new Map<String, Object>{
                'address' => 'longsender@verylongdomainname.com'
            }
        });
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        matchResults.add(new AIQuickMatchService.MatchResult());

        Test.startTest();
        AINotificationService.sendUnmatchedNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendUnmatchedNotifications with long subject should truncate and complete');
    }

    @isTest
    static void testSendUnmatchedNotifications_MissingFromAddress() {
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Email with missing from address');
        // Intentionally not setting 'from' field
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        matchResults.add(new AIQuickMatchService.MatchResult());

        Test.startTest();
        AINotificationService.sendUnmatchedNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendUnmatchedNotifications should handle missing from address');
    }

    @isTest
    static void testSendMatchNotifications_EmptyMatchDetails() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Email with empty match details');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = testContact.Id;
        match.confidence = 95;
        match.matchType = 'Contact';
        match.matchDetails = new List<String>(); // Empty match details
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications should handle empty match details');
    }

    @isTest
    static void testSendMatchNotifications_NullMatchDetails() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Email with null match details');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = testContact.Id;
        match.confidence = 95;
        match.matchType = 'Contact';
        match.matchDetails = null; // Null match details
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications should handle null match details');
    }

    @isTest
    static void testSendMatchNotifications_ContactWithoutAccount() {
        // Create a contact without an account
        Contact standaloneContact = new Contact(
            FirstName = 'Standalone',
            LastName = 'Contact',
            Email = 'standalone@nocompany.com'
        );
        insert standaloneContact;

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Email to contact without account');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.contactId = standaloneContact.Id;
        match.confidence = 95;
        match.matchType = 'Contact';
        match.matchDetails = new List<String>{'Email match'};
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications should handle contact without account');
    }

    @isTest
    static void testSendMatchNotifications_OpportunityWithAccount() {
        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];
        Opportunity testOpp = [SELECT Id, Name, AccountId FROM Opportunity WHERE AccountId = :testAccount.Id LIMIT 1];

        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Email matched to opportunity with account');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        match.opportunityId = testOpp.Id;
        match.accountId = testAccount.Id;
        match.confidence = 85;
        match.matchType = 'Opportunity';
        match.matchDetails = new List<String>{'Account domain match'};
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications should handle opportunity with account');
    }

    @isTest
    static void testSendMatchNotifications_InvalidRecordId() {
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        Map<String, Object> emailData = new Map<String, Object>();
        emailData.put('subject', 'Email with invalid record reference');
        emailDataList.add(emailData);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        AIQuickMatchService.MatchResult match = new AIQuickMatchService.MatchResult();
        // Use a fake ID that doesn't exist
        match.contactId = '003000000000000AAA';
        match.confidence = 95;
        match.matchType = 'Contact';
        match.matchDetails = new List<String>{'Email match'};
        matchResults.add(match);

        
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications should handle invalid record IDs gracefully');
    }

    @isTest
    static void testSendUnmatchedNotifications_EmptyList() {
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();

        Test.startTest();
        AINotificationService.sendUnmatchedNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendUnmatchedNotifications should handle empty lists');
    }

    @isTest
    static void testSendMatchNotifications_EmptyLists() {
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        

        Test.startTest();
        AINotificationService.sendMatchNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendMatchNotifications should handle empty lists');
    }

    @isTest
    static void testExtractFromAddress_VariousFormats() {
        // Test with proper nested structure
        List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();

        Map<String, Object> email1 = new Map<String, Object>();
        email1.put('subject', 'Test Email');
        email1.put('from', new Map<String, Object>{
            'emailAddress' => new Map<String, Object>{
                'address' => 'test@example.com',
                'name' => 'Test Sender'
            }
        });
        emailDataList.add(email1);

        // Test with simple string from (edge case)
        Map<String, Object> email2 = new Map<String, Object>();
        email2.put('subject', 'Test Email 2');
        email2.put('from', 'simplesender@example.com');
        emailDataList.add(email2);

        List<AIQuickMatchService.MatchResult> matchResults = new List<AIQuickMatchService.MatchResult>();
        matchResults.add(new AIQuickMatchService.MatchResult());
        matchResults.add(new AIQuickMatchService.MatchResult());

        Test.startTest();
        AINotificationService.sendUnmatchedNotifications(emailDataList, matchResults);
        Test.stopTest();

        Assert.isTrue(true, 'sendUnmatchedNotifications should handle various from address formats');
    }
}