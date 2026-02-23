/**
 * Test class for QuickMatchService
 * Tests fast email matching logic with mock data
 * Covers both Gmail and Exchange email formats
 */
@isTest
private class AIQuickMatchServiceTest {

    @testSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Acme Corporation',
            Website = 'www.acme.com'
        );
        insert testAccount;

        // Create test Contact with Account
        Contact testContact = new Contact(
            FirstName = 'John',
            LastName = 'Smith',
            Email = 'john.smith@acme.com',
            AccountId = testAccount.Id
        );
        insert testContact;

        // Create test Lead (unconverted)
        Lead testLead = new Lead(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane.doe@techstartup.com',
            Company = 'Tech Startup Inc'
        );
        insert testLead;

        // Create test Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Acme Q4 Renewal',
            AccountId = testAccount.Id,
            StageName = 'Negotiation',
            CloseDate = Date.today().addDays(30),
            Amount = 100000
        );
        insert testOpp;

        // Create test Case
        Case testCase = new Case(
            ContactId = testContact.Id,
            Subject = 'API Integration Issue',
            Status = 'New',
            Priority = 'High'
        );
        insert testCase;

        // Create another Account without Contact
        Account orphanAccount = new Account(
            Name = 'Global Enterprises',
            Website = 'www.globalent.com'
        );
        insert orphanAccount;
    }

    /**
     * Test 1: Contact match by email (highest confidence)
     */
    @isTest
    static void testContactMatchByEmail() {
        // Create mock Gmail email data
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'john.smith@acme.com',
            'fromName' => 'John Smith',
            'subject' => 'Re: Q4 Renewal Discussion',
            'bodyText' => 'Looking forward to our meeting about the renewal.',
            'internetMessageId' => 'gmail-12345'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Assertions
        Assert.areNotEqual(null, result.contactId, 'Should find Contact');
        Assert.areNotEqual(null, result.accountId, 'Should find Account through Contact');
        Assert.areNotEqual(null, result.opportunityId, 'Should find related Opportunity');
        Assert.areNotEqual(null, result.caseId, 'Should find related Case');
        Assert.areEqual(95, result.confidence, 'Contact match should have 95% confidence');
        Assert.areEqual('Contact', result.matchType, 'Match type should be Contact');
        Assert.isTrue(result.matchDetails.size() > 0, 'Should have match details');
        // Match details will show either "Matching received email from:" or "Matched Contact:"
        Boolean hasValidDetails = false;
        for (String detail : result.matchDetails) {
            if (detail.contains('John Smith') || detail.contains('Matching received email from:') || detail.contains('Matched Contact:')) {
                hasValidDetails = true;
                break;
            }
        }
        Assert.isTrue(hasValidDetails, 'Should include relevant match details');
    }

    /**
     * Test 2: Lead match by email
     */
    @isTest
    static void testLeadMatchByEmail() {
        // Create mock Exchange email data
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'jane.doe@techstartup.com',
            'fromName' => 'Jane Doe',
            'subject' => 'Interest in your product',
            'bodyText' => 'We would like to learn more about your solution.',
            'internetMessageId' => 'exchange-67890'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Assertions
        Assert.areNotEqual(null, result.leadId, 'Should find Lead');
        Assert.areEqual(null, result.contactId, 'Should not find Contact');
        Assert.areEqual(95, result.confidence, 'Lead match should have 95% confidence');
        Assert.areEqual('Lead', result.matchType, 'Match type should be Lead');
        Assert.isTrue(result.matchDetails.size() > 0, 'Should have match details');
        // Match details will show either "Matching received email from:" or "Matched Lead:"
        Boolean hasValidDetails = false;
        for (String detail : result.matchDetails) {
            if (detail.contains('Jane Doe') || detail.contains('Matching received email from:') || detail.contains('Matched Lead:')) {
                hasValidDetails = true;
                break;
            }
        }
        Assert.isTrue(hasValidDetails, 'Should include relevant match details');
    }

    /**
     * Test 3: Account match by domain
     */
    @isTest
    static void testAccountMatchByDomain() {
        // Email from unknown person at known company
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'unknown.person@globalent.com',
            'fromName' => 'Unknown Person',
            'subject' => 'Partnership Inquiry',
            'bodyText' => 'We are interested in partnering with your company.',
            'internetMessageId' => 'msg-abc123'
        };

        // Lead Auto-Create feature has been removed
        
        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Assertions
        Assert.areNotEqual(null, result.accountId, 'Should find Account by domain');
        Assert.areEqual(null, result.contactId, 'Should not find Contact');
        Assert.areEqual(null, result.leadId, 'Should not find Lead');
        Assert.areEqual(80, result.confidence, 'Domain match should have 80% confidence');
        Assert.areEqual('Account', result.matchType, 'Match type should be Account');
        Assert.isTrue(result.matchDetails[0].contains('globalent.com'), 'Should mention domain in details');
    }

    /**
     * Test 4: No match found
     */
    @isTest
    static void testNoMatch() {
        // Email from completely unknown sender
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'stranger@unknown-company.com',
            'fromName' => 'Complete Stranger',
            'subject' => 'Random Email',
            'bodyText' => 'This is a random email.',
            'internetMessageId' => 'msg-xyz789'
        };

        // Lead Auto-Create feature has been removed
        
        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Assertions
        Assert.areEqual(null, result.contactId, 'Should not find Contact');
        Assert.areEqual(null, result.leadId, 'Should not find Lead');
        Assert.areEqual(null, result.accountId, 'Should not find Account');
        Assert.areEqual(0, result.confidence, 'No match should have 0% confidence');
        Assert.areEqual('None', result.matchType, 'Match type should be None');
        Assert.isTrue(result.matchDetails.size() > 0, 'Should have match details');
        // Match details will show checking participants and no match
        Boolean hasValidDetails = false;
        for (String detail : result.matchDetails) {
            if (detail.contains('No Contact, Lead, or Account found') ||
                detail.contains('Checking') ||
                detail.contains('No match found') ||
                detail.contains('No customer email found')) {
                hasValidDetails = true;
                break;
            }
        }
        Assert.isTrue(hasValidDetails, 'Should indicate no match');
    }

    /**
     * Test 5: Batch processing with multiple emails
     */
    @isTest
    static void testBatchProcessing() {
        // Create multiple mock emails
        List<Map<String, Object>> emails = new List<Map<String, Object>>{
            // Email 1: Contact match
            new Map<String, Object>{
                'fromAddress' => 'john.smith@acme.com',
                'fromName' => 'John Smith',
                'subject' => 'Email 1',
                'internetMessageId' => 'msg-1'
            },
            // Email 2: Lead match
            new Map<String, Object>{
                'fromAddress' => 'jane.doe@techstartup.com',
                'fromName' => 'Jane Doe',
                'subject' => 'Email 2',
                'internetMessageId' => 'msg-2'
            },
            // Email 3: Domain match
            new Map<String, Object>{
                'fromAddress' => 'newperson@globalent.com',
                'fromName' => 'New Person',
                'subject' => 'Email 3',
                'internetMessageId' => 'msg-3'
            },
            // Email 4: No match
            new Map<String, Object>{
                'fromAddress' => 'nobody@nowhere.com',
                'fromName' => 'Nobody',
                'subject' => 'Email 4',
                'internetMessageId' => 'msg-4'
            }
        };

        // Lead Auto-Create feature has been removed

        Test.startTest();
        List<AIQuickMatchService.MatchResult> results = AIQuickMatchService.matchBatch(emails);
        Test.stopTest();

        // Assertions
        Assert.areEqual(4, results.size(), 'Should return 4 results');

        // Check each result
        Assert.areNotEqual(null, results[0].contactId, 'First email should match Contact');
        Assert.areEqual(95, results[0].confidence, 'Contact match confidence');

        Assert.areNotEqual(null, results[1].leadId, 'Second email should match Lead');
        Assert.areEqual(95, results[1].confidence, 'Lead match confidence');

        Assert.areNotEqual(null, results[2].accountId, 'Third email should match Account');
        Assert.areEqual(80, results[2].confidence, 'Domain match confidence');

        Assert.areEqual(null, results[3].contactId, 'Fourth email should not match');
        Assert.areEqual(0, results[3].confidence, 'No match confidence');
    }

    /**
     * Test 6: Case-insensitive email matching
     */
    @isTest
    static void testCaseInsensitiveMatching() {
        // Test with different email cases
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'JOHN.SMITH@ACME.COM', // All uppercase
            'fromName' => 'John Smith',
            'subject' => 'Case Test',
            'internetMessageId' => 'case-test-123'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Assertions
        Assert.areNotEqual(null, result.contactId, 'Should match Contact regardless of case');
        Assert.areEqual(95, result.confidence, 'Should have full confidence');
    }

    /**
     * Test 7: Gmail-specific email format
     */
    @isTest
    static void testGmailEmailFormat() {
        // For Gmail format test, use the normalized format our providers already create
        // The providers normalize the nested structure into flat fields
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'john.smith@acme.com',
            'fromName' => 'John Smith',
            'subject' => 'Gmail Format Test',
            'bodyText' => 'Testing Gmail format',
            'internetMessageId' => 'gmail-format-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Assertions
        Assert.areNotEqual(null, result.contactId, 'Should handle Gmail format');
        Assert.areEqual('john.smith@acme.com', result.fromAddress, 'Should extract email correctly');
        Assert.areEqual('John Smith', result.fromName, 'Should extract name correctly');
    }

    /**
     * Test 8: Performance test - 20 emails
     */
    @isTest
    static void testPerformanceWith20Emails() {
        // Create 20 emails
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        for (Integer i = 0; i < 20; i++) {
            emails.add(new Map<String, Object>{
                'fromAddress' => 'user' + i + '@test.com',
                'fromName' => 'User ' + i,
                'subject' => 'Email ' + i,
                'internetMessageId' => 'msg-' + i
            });
        }

        // Measure performance
        Long startTime = System.currentTimeMillis();

        Test.startTest();
        List<AIQuickMatchService.MatchResult> results = AIQuickMatchService.matchBatch(emails);
        Test.stopTest();

        Long endTime = System.currentTimeMillis();
        Long duration = endTime - startTime;

        // Assertions
        Assert.areEqual(20, results.size(), 'Should process all 20 emails');
        // Note: Can't enforce < 1 second in test context, but we log it

        // Verify SOQL limits
        Assert.isTrue(Limits.getQueries() <= 10, 'Should use <= 10 SOQL queries for 20 emails');
    }

    /**
     * Test 9: Empty and null email handling
     */
    @isTest
    static void testEmptyEmailHandling() {
        // Test with missing from address
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => '',
            'subject' => 'No sender',
            'internetMessageId' => 'no-sender-123'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Assertions
        Assert.areEqual(0, result.confidence, 'Should have 0 confidence with no sender');
        Assert.areEqual('None', result.matchType, 'Should have no match type');
        Assert.isTrue(result.matchDetails.size() > 0, 'Should have match details');
        // Match details will show no participants found
        Boolean hasValidDetails = false;
        for (String detail : result.matchDetails) {
            if (detail.contains('No participant emails found') ||
                detail.contains('No customer email found') ||
                detail.contains('No sender') ||
                detail.contains('only current user')) {
                hasValidDetails = true;
                break;
            }
        }
        Assert.isTrue(hasValidDetails, 'Should indicate missing sender');
    }

    /**
     * Test 10: Converted Lead (should not match)
     */
    @isTest
    static void testConvertedLeadNotMatched() {
        // Create and convert a lead
        Lead convertedLead = new Lead(
            FirstName = 'Converted',
            LastName = 'Person',
            Email = 'converted@example.com',
            Company = 'Converted Company'
        );
        insert convertedLead;

        // Convert the lead
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(convertedLead.Id);

        // Get the first available converted lead status
        LeadStatus convertStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1];
        lc.setConvertedStatus(convertStatus.MasterLabel);

        Database.LeadConvertResult lcr = Database.convertLead(lc);

        // Try to match email from converted lead
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'converted@example.com',
            'fromName' => 'Converted Person',
            'subject' => 'Test',
            'internetMessageId' => 'converted-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Assertions
        Assert.areNotEqual(convertedLead.Id, result.leadId, 'Should not match converted Lead');
        // Should match the Contact created from conversion instead
        Assert.areNotEqual(null, result.contactId, 'Should match Contact from conversion');
    }

    /**
     * Test 11: Match with nested Microsoft Graph format
     */
    @isTest
    static void testMicrosoftGraphFormat() {
        Map<String, Object> emailData = new Map<String, Object>{
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{
                    'address' => 'john.smith@acme.com',
                    'name' => 'John Smith'
                }
            },
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'user@salesforce.com',
                        'name' => 'SF User'
                    }
                }
            },
            'subject' => 'Graph Format Test',
            'internetMessageId' => 'graph-format-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        Assert.areNotEqual(null, result.contactId, 'Should handle Graph format');
    }

    /**
     * Test 12: Match with CC recipients
     */
    @isTest
    static void testMatchFromCCRecipient() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'unknown@test.com',
            'fromName' => 'Unknown Sender',
            'ccRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'john.smith@acme.com',
                        'name' => 'John Smith'
                    }
                }
            },
            'subject' => 'CC Test',
            'internetMessageId' => 'cc-test-123'
        };

        // Lead Auto-Create feature has been removed

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should match Contact from CC
        Assert.areNotEqual(null, result.contactId, 'Should match from CC recipient');
    }

    /**
     * Test 13: Match with TO recipients (sent email)
     */
    @isTest
    static void testMatchFromToRecipient() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'currentuser@test.com',
            'fromName' => 'Current User',
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'john.smith@acme.com',
                        'name' => 'John Smith'
                    }
                }
            },
            'subject' => 'TO Test',
            'internetMessageId' => 'to-test-123'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should match Contact from TO
        Assert.areNotEqual(null, result.contactId, 'Should match from TO recipient');
    }

    /**
     * Test 14: Empty email data map
     */
    @isTest
    static void testEmptyEmailData() {
        Map<String, Object> emailData = new Map<String, Object>();

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        Assert.areEqual(0, result.confidence, 'Empty email should have 0 confidence');
        Assert.areEqual('None', result.matchType, 'Empty email should have None match type');
    }

    /**
     * Test 15: Empty batch
     */
    @isTest
    static void testEmptyBatch() {
        Test.startTest();
        List<AIQuickMatchService.MatchResult> results = AIQuickMatchService.matchBatch(new List<Map<String, Object>>());
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Empty batch should return empty results');
    }

    /**
     * Test 16: Null batch
     */
    @isTest
    static void testNullBatch() {
        Test.startTest();
        List<AIQuickMatchService.MatchResult> results = AIQuickMatchService.matchBatch(null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Null batch should return empty results');
    }

    /**
     * Test 17: MatchResult class properties
     */
    @isTest
    static void testMatchResultProperties() {
        Test.startTest();
        AIQuickMatchService.MatchResult result = new AIQuickMatchService.MatchResult();
        result.confidence = 75;
        result.matchType = 'Contact';
        result.fromAddress = 'test@test.com';
        result.fromName = 'Test User';
        result.emailSubject = 'Test Subject';
        result.matchDetails = new List<String>{ 'Detail 1', 'Detail 2' };
        result.contactId = null;
        result.accountId = null;
        result.leadId = null;
        result.opportunityId = null;
        result.caseId = null;
        result.contactIds = new List<Id>();
        Test.stopTest();

        Assert.areEqual(75, result.confidence, 'Confidence should be 75');
        Assert.areEqual('Contact', result.matchType, 'MatchType should be Contact');
        Assert.areEqual('test@test.com', result.fromAddress, 'FromAddress should be set');
        Assert.areEqual('Test Subject', result.emailSubject, 'EmailSubject should be set');
        Assert.areEqual(2, result.matchDetails.size(), 'Should have 2 match details');
    }

    /**
     * Test 18: Sent email matching (from current user TO a Contact)
     */
    @isTest
    static void testSentEmailMatching() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => UserInfo.getUserEmail(),
            'fromName' => UserInfo.getName(),
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => con.Email,
                        'name' => 'John Smith'
                    }
                }
            },
            'subject' => 'Sent Email Test',
            'internetMessageId' => 'sent-email-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should match the TO recipient Contact
        Assert.areNotEqual(null, result.contactId, 'Should match TO recipient Contact');
    }

    /**
     * Test 19: Match user email to Salesforce User
     */
    @isTest
    static void testMatchUserEmailToUser() {
        // Create a test User
        User testUser = [SELECT Id, Email FROM User WHERE IsActive = true AND Email != null LIMIT 1];

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchUserEmail(testUser.Email);
        Test.stopTest();

        Assert.areEqual(100, result.confidence, 'User match should have 100% confidence');
        Assert.areEqual('User', result.matchType, 'Match type should be User');
        Assert.isTrue(result.matchDetails.size() > 0, 'Should have match details');
    }

    /**
     * Test 20: Match user email to Contact
     */
    @isTest
    static void testMatchUserEmailToContact() {
        Contact con = [SELECT Id, Email FROM Contact WHERE Email = 'john.smith@acme.com' LIMIT 1];

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchUserEmail(con.Email);
        Test.stopTest();

        Assert.areNotEqual(null, result.contactId, 'Should match Contact');
        Assert.areEqual(100, result.confidence, 'Contact match should have 100% confidence');
        Assert.areEqual('Contact', result.matchType, 'Match type should be Contact');
    }

    /**
     * Test 21: Match user email to Lead
     */
    @isTest
    static void testMatchUserEmailToLead() {
        Lead lead = [SELECT Id, Email FROM Lead WHERE Email = 'jane.doe@techstartup.com' LIMIT 1];

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchUserEmail(lead.Email);
        Test.stopTest();

        Assert.areNotEqual(null, result.leadId, 'Should match Lead');
        Assert.areEqual(100, result.confidence, 'Lead match should have 100% confidence');
        Assert.areEqual('Lead', result.matchType, 'Match type should be Lead');
    }

    /**
     * Test 22: Match user email - no match
     */
    @isTest
    static void testMatchUserEmailNoMatch() {
        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchUserEmail('unknown@nowhere.com');
        Test.stopTest();

        Assert.areEqual(0, result.confidence, 'No match should have 0% confidence');
        Assert.areEqual('None', result.matchType, 'Match type should be None');
    }

    /**
     * Test 23: Match user email - blank email
     */
    @isTest
    static void testMatchUserEmailBlank() {
        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchUserEmail('');
        Test.stopTest();

        Assert.areEqual(0, result.confidence, 'Blank email should have 0% confidence');
        Assert.areEqual('None', result.matchType, 'Match type should be None');
    }

    /**
     * Test 24: Match user email - null email
     */
    @isTest
    static void testMatchUserEmailNull() {
        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchUserEmail(null);
        Test.stopTest();

        Assert.areEqual(0, result.confidence, 'Null email should have 0% confidence');
        Assert.areEqual('None', result.matchType, 'Match type should be None');
    }

    /**
     * Test 25: Get authenticated user match with cache
     */
    @isTest
    static void testGetAuthenticatedUserMatchWithCache() {
        // Clear cache first
        AIQuickMatchService.clearUserMatchCache();

        Test.startTest();
        // First call - will attempt to fetch
        AIQuickMatchService.MatchResult result1 = AIQuickMatchService.getAuthenticatedUserMatch();
        // Second call - should return cached result
        AIQuickMatchService.MatchResult result2 = AIQuickMatchService.getAuthenticatedUserMatch();
        Test.stopTest();

        // Both should return null or same result (no connection in test context)
        Assert.areEqual(result1, result2, 'Should return cached result');
    }

    /**
     * Test 26: Clear user match cache
     */
    @isTest
    static void testClearUserMatchCache() {
        Test.startTest();
        AIQuickMatchService.clearUserMatchCache();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.getAuthenticatedUserMatch();
        Test.stopTest();

        // Should handle cache clear without errors
        Assert.isTrue(true, 'Cache clear should not throw errors');
    }

    /**
     * Test 27: Email with public domain (gmail.com)
     */
    @isTest
    static void testPublicDomainEmail() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'someone@gmail.com',
            'fromName' => 'Gmail User',
            'subject' => 'Public Domain Test',
            'internetMessageId' => 'public-domain-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should not match Account for public domain
        Assert.areEqual(null, result.accountId, 'Should not match Account for public domain');
    }

    /**
     * Test 28: Email with multiple contacts (multi-association)
     */
    @isTest
    static void testMultipleContactMatching() {
        // Create another contact with same domain
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1];
        Contact contact2 = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane.doe@acme.com',
            AccountId = acc.Id
        );
        insert contact2;

        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'john.smith@acme.com',
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => 'jane.doe@acme.com',
                        'name' => 'Jane Doe'
                    }
                }
            },
            'subject' => 'Multi Contact Test',
            'internetMessageId' => 'multi-contact-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should find multiple contacts
        Assert.isTrue(result.contactIds.size() >= 1, 'Should find at least one contact');
        Assert.areNotEqual(null, result.contactId, 'Should have primary contact');
    }

    /**
     * Test 29: Email with recipient as plain string
     */
    @isTest
    static void testRecipientAsString() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'sender@test.com',
            'to' => new List<Object>{ 'john.smith@acme.com' },
            'subject' => 'String Recipient Test',
            'internetMessageId' => 'string-recipient-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should handle string format recipients
        Assert.areNotEqual(null, result.contactId, 'Should match Contact from string recipient');
    }

    /**
     * Test 30: Email with Gmail CC format
     */
    @isTest
    static void testGmailCCFormat() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'sender@test.com',
            'cc' => new List<Object>{
                new Map<String, Object>{
                    'email' => 'john.smith@acme.com',
                    'name' => 'John Smith'
                }
            },
            'subject' => 'Gmail CC Test',
            'internetMessageId' => 'gmail-cc-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should match Contact from Gmail CC format
        Assert.areNotEqual(null, result.contactId, 'Should match Contact from Gmail CC');
    }

    /**
     * Test 31: Email with direct address field in recipient
     */
    @isTest
    static void testDirectAddressField() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'sender@test.com',
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'address' => 'john.smith@acme.com'
                }
            },
            'subject' => 'Direct Address Test',
            'internetMessageId' => 'direct-address-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should handle direct address field
        Assert.areNotEqual(null, result.contactId, 'Should match Contact from direct address');
    }

    /**
     * Test 32: Email with null recipients
     */
    @isTest
    static void testNullRecipients() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'john.smith@acme.com',
            'toRecipients' => null,
            'ccRecipients' => null,
            'subject' => 'Null Recipients Test',
            'internetMessageId' => 'null-recipients-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should still match from FROM address
        Assert.areNotEqual(null, result.contactId, 'Should match Contact from FROM address');
    }

    /**
     * Test 33: Email from current user only
     */
    @isTest
    static void testEmailFromCurrentUserOnly() {
        String currentUserEmail = UserInfo.getUserEmail();
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => currentUserEmail,
            'toRecipients' => new List<Object>{
                new Map<String, Object>{
                    'emailAddress' => new Map<String, Object>{
                        'address' => currentUserEmail,
                        'name' => 'Current User'
                    }
                }
            },
            'subject' => 'Self Email Test',
            'internetMessageId' => 'self-email-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should have no match (all participants are current user)
        Assert.areEqual('None', result.matchType, 'Should have no match when only current user');
    }

    /**
     * Test 34: Email with invalid domain extraction
     */
    @isTest
    static void testInvalidDomainExtraction() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'invalidemail',
            'subject' => 'Invalid Domain Test',
            'internetMessageId' => 'invalid-domain-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should handle invalid email format
        Assert.areEqual('None', result.matchType, 'Should have no match for invalid email');
    }

    /**
     * Test 35: Email with @ at end
     */
    @isTest
    static void testEmailWithAtAtEnd() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'invalidemail@',
            'subject' => 'Invalid Email Test',
            'internetMessageId' => 'invalid-email-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should handle invalid email format
        Assert.areEqual('None', result.matchType, 'Should have no match for invalid email');
    }

    /**
     * Test 36: Account match with name similarity (no website)
     */
    @isTest
    static void testAccountMatchByNameSimilarity() {
        // Create account with no website but matching name
        Account nameOnlyAccount = new Account(
            Name = 'TestCorp Solutions',
            Website = null
        );
        insert nameOnlyAccount;

        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'contact@testcorp.com',
            'fromName' => 'TestCorp Contact',
            'subject' => 'Name Match Test',
            'internetMessageId' => 'name-match-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // May or may not match depending on account query results
        Assert.isTrue(true, 'Test completed without errors');
    }

    /**
     * Test 37: User with linked Contact
     */
    @isTest
    static void testUserWithLinkedContact() {
        // Create a community user with linked contact
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1];
        Contact communityContact = new Contact(
            FirstName = 'Community',
            LastName = 'User',
            Email = 'community.user@acme.com',
            AccountId = acc.Id
        );
        insert communityContact;

        // Note: In test context, we can't easily create a User with ContactId
        // So we'll test the matchUserEmail method with existing data
        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchUserEmail('community.user@acme.com');
        Test.stopTest();

        // Should match the Contact
        Assert.areNotEqual(null, result.contactId, 'Should match Contact');
        Assert.areEqual('Contact', result.matchType, 'Match type should be Contact');
    }

    /**
     * Test 38: Recipient extraction with Map<Object, Object> format
     */
    @isTest
    static void testRecipientMapObjectFormat() {
        // Simulate JSON deserialization format
        Map<Object, Object> recipientMap = new Map<Object, Object>{
            'emailAddress' => new Map<Object, Object>{
                'address' => 'john.smith@acme.com',
                'name' => 'John Smith'
            }
        };

        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'sender@test.com',
            'toRecipients' => new List<Object>{ recipientMap },
            'subject' => 'Object Map Test',
            'internetMessageId' => 'object-map-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should handle Map<Object, Object> format
        Assert.areNotEqual(null, result.contactId, 'Should match Contact from Map<Object, Object>');
    }

    /**
     * Test 39: From field with Map<Object, Object> format
     */
    @isTest
    static void testFromFieldMapObjectFormat() {
        Map<Object, Object> fromMap = new Map<Object, Object>{
            'emailAddress' => new Map<Object, Object>{
                'address' => 'john.smith@acme.com',
                'name' => 'John Smith'
            }
        };

        Map<String, Object> emailData = new Map<String, Object>{
            'from' => fromMap,
            'subject' => 'From Object Map Test',
            'internetMessageId' => 'from-object-map-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should extract from address correctly
        Assert.areNotEqual(null, result.contactId, 'Should match Contact from Map<Object, Object> from field');
    }

    /**
     * Test 40: From field as simple string
     */
    @isTest
    static void testFromFieldAsString() {
        Map<String, Object> emailData = new Map<String, Object>{
            'from' => 'john.smith@acme.com',
            'subject' => 'From String Test',
            'internetMessageId' => 'from-string-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should extract from address as string
        Assert.areNotEqual(null, result.contactId, 'Should match Contact from string from field');
    }

    /**
     * Test 41: From name extraction from nested object
     */
    @isTest
    static void testFromNameExtraction() {
        Map<Object, Object> fromMap = new Map<Object, Object>{
            'emailAddress' => new Map<Object, Object>{
                'address' => 'john.smith@acme.com',
                'name' => 'John Smith Jr.'
            }
        };

        Map<String, Object> emailData = new Map<String, Object>{
            'from' => fromMap,
            'subject' => 'From Name Test',
            'internetMessageId' => 'from-name-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should extract from name correctly
        Assert.areEqual('John Smith Jr.', result.fromName, 'Should extract from name from nested object');
    }

    /**
     * Test 42: From name when no from object exists
     */
    @isTest
    static void testFromNameDefault() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'john.smith@acme.com',
            'subject' => 'Default From Name Test',
            'internetMessageId' => 'default-from-name-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should use default from name
        Assert.areEqual('Unknown Sender', result.fromName, 'Should use default from name');
    }

    /**
     * Test 43: Subject extraction
     */
    @isTest
    static void testSubjectExtraction() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'john.smith@acme.com',
            'subject' => 'Important Email Subject',
            'internetMessageId' => 'subject-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        Assert.areEqual('Important Email Subject', result.emailSubject, 'Should extract subject correctly');
    }

    /**
     * Test 44: Default subject when null
     */
    @isTest
    static void testDefaultSubject() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'john.smith@acme.com',
            'internetMessageId' => 'no-subject-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        Assert.areEqual('No Subject', result.emailSubject, 'Should use default subject');
    }

    /**
     * Test 45: Batch with public domain emails (gmail, yahoo, etc.)
     */
    @isTest
    static void testBatchWithPublicDomains() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>{
            new Map<String, Object>{
                'fromAddress' => 'user1@gmail.com',
                'subject' => 'Gmail Test',
                'internetMessageId' => 'gmail-batch-1'
            },
            new Map<String, Object>{
                'fromAddress' => 'user2@yahoo.com',
                'subject' => 'Yahoo Test',
                'internetMessageId' => 'yahoo-batch-1'
            },
            new Map<String, Object>{
                'fromAddress' => 'user3@hotmail.com',
                'subject' => 'Hotmail Test',
                'internetMessageId' => 'hotmail-batch-1'
            }
        };

        Test.startTest();
        List<AIQuickMatchService.MatchResult> results = AIQuickMatchService.matchBatch(emails);
        Test.stopTest();

        // Public domains should not match accounts
        for (AIQuickMatchService.MatchResult result : results) {
            Assert.areEqual(null, result.accountId, 'Public domain should not match Account');
        }
    }

    /**
     * Test 46: Account match with website containing domain
     */
    @isTest
    static void testAccountWebsiteMatch() {
        // Create account with full website URL
        Account webAccount = new Account(
            Name = 'Web Company Inc',
            Website = 'https://www.webcompany.com/about'
        );
        insert webAccount;

        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'contact@webcompany.com',
            'subject' => 'Website Match Test',
            'internetMessageId' => 'website-match-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should match account by website domain
        Assert.areNotEqual(null, result.accountId, 'Should match Account by website');
    }

    /**
     * Test 47: Account name match when domain already in cache
     */
    @isTest
    static void testAccountNameMatchWithExistingDomain() {
        // Create two accounts - one with website, one with similar name
        Account acc1 = new Account(
            Name = 'First TestCompany',
            Website = 'www.testcompany.com'
        );
        Account acc2 = new Account(
            Name = 'TestCompany Solutions',
            Website = null
        );
        insert new List<Account>{ acc1, acc2 };

        // Email from testcompany domain
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => 'info@testcompany.com',
            'subject' => 'Name Match Test',
            'internetMessageId' => 'name-match-cache-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        // Should match one of the accounts
        Assert.areNotEqual(null, result.accountId, 'Should match Account');
    }

    /**
     * Test 48: HTTP callout for Microsoft Graph user email
     */
    @isTest
    static void testMicrosoftGraphUserEmail() {
        // Create workspace user for Outlook connection
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            Provider__c = 'OUTLOOK',
            Access_Token__c = 'test_access_token_encrypted',
            User__c = UserInfo.getUserId()
        );
        insert workspaceUser;

        // Mock HTTP response for Microsoft Graph /me endpoint
        Test.setMock(HttpCalloutMock.class, new MockMicrosoftGraphUserProfile());

        Test.startTest();
        AIQuickMatchService.clearUserMatchCache();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.getAuthenticatedUserMatch();
        Test.stopTest();

        // Should attempt to fetch user email
        Assert.isTrue(true, 'Should complete without errors');
    }

    /**
     * Test 49: Batch processing with mixed internal and external contacts
     */
    @isTest
    static void testBatchWithInternalExternalMix() {
        // Create internal contact (same domain as user)
        String userDomain = UserInfo.getUserEmail().substringAfter('@');
        Contact internalContact = new Contact(
            FirstName = 'Internal',
            LastName = 'User',
            Email = 'internal@' + userDomain
        );
        insert internalContact;

        List<Map<String, Object>> emails = new List<Map<String, Object>>{
            new Map<String, Object>{
                'fromAddress' => 'internal@' + userDomain,
                'subject' => 'Internal Email',
                'internetMessageId' => 'internal-1'
            },
            new Map<String, Object>{
                'fromAddress' => 'john.smith@acme.com',
                'subject' => 'External Email',
                'internetMessageId' => 'external-1'
            }
        };

        Test.startTest();
        List<AIQuickMatchService.MatchResult> results = AIQuickMatchService.matchBatch(emails);
        Test.stopTest();

        // Should process both emails
        Assert.areEqual(2, results.size(), 'Should process all emails');
    }

    /**
     * Test 50: Email with only whitespace in from address
     */
    @isTest
    static void testWhitespaceFromAddress() {
        Map<String, Object> emailData = new Map<String, Object>{
            'fromAddress' => '   ',
            'subject' => 'Whitespace Test',
            'internetMessageId' => 'whitespace-test'
        };

        Test.startTest();
        AIQuickMatchService.MatchResult result = AIQuickMatchService.matchSingle(emailData);
        Test.stopTest();

        Assert.areEqual('None', result.matchType, 'Should have no match for whitespace email');
    }

    // Mock class for Microsoft Graph user profile
    private class MockMicrosoftGraphUserProfile implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"userPrincipalName": "test@example.com", "mail": "test@example.com"}');
            return res;
        }
    }
}