/**
 * Test class for AIStagingMatcherService
 * Tests the precedence-based email matching logic
 * 
 * PRECEDENCE LOGIC:
 * - For a precedence level to be used, ALL objects in that level must have a match for the email
 * - When a level matches, MatchResult contains ALL matched IDs (Lead, Contact)
 * - User matching is NOT supported
 */
@isTest
private class AIStagingMatcherServiceTest {
    
    private static final String TEST_EMAIL = 'test@example.com';
    
    @testSetup
    static void setupTestData() {
        // Create test Accounts with Website
        Account testAccount1 = new Account(
            Name = 'Example Corporation',
            Website = 'https://www.example.com'
        );
        insert testAccount1;
        
        Account testAccount2 = new Account(
            Name = 'Acme Industries',
            Website = 'acme.com'
        );
        insert testAccount2;
        
        // Create test Lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = TEST_EMAIL
        );
        insert testLead;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = TEST_EMAIL,
            AccountId = testAccount1.Id
        );
        insert testContact;
    }
    
    @isTest
    static void testBuildEmailMatchCache() {
        Set<String> emails = new Set<String>{ TEST_EMAIL };
        
        Test.startTest();
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        Test.stopTest();
        
        Assert.isTrue(cache.emailToLeadId.containsKey(TEST_EMAIL), 'Should find Lead');
        Assert.isTrue(cache.emailToContactId.containsKey(TEST_EMAIL), 'Should find Contact');
    }
    
    @isTest
    static void testBuildEmailMatchCacheNormalizesCase() {
        Set<String> emails = new Set<String>{ 'TEST@EXAMPLE.COM' };
        
        Test.startTest();
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        Test.stopTest();
        
        // Should normalize to lowercase
        Assert.isTrue(cache.emailToLeadId.containsKey(TEST_EMAIL), 'Should find Lead with normalized email');
        Assert.isTrue(cache.emailToContactId.containsKey(TEST_EMAIL), 'Should find Contact with normalized email');
    }
    
    @isTest
    static void testBuildEmailMatchCacheEmpty() {
        Test.startTest();
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(new Set<String>());
        Test.stopTest();
        
        Assert.isTrue(cache.emailToLeadId.isEmpty(), 'Should return empty cache');
        Assert.isTrue(cache.emailToContactId.isEmpty(), 'Should return empty cache');
    }
    
    @isTest
    static void testBuildEmailMatchCacheNull() {
        Test.startTest();
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(null);
        Test.stopTest();
        
        Assert.isTrue(cache.emailToLeadId.isEmpty(), 'Should return empty cache');
    }
    
    @isTest
    static void testMatchEmailWithPrecedenceAllMatch() {
        // Set up precedence config where Lead, Contact must ALL match
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"]}';
        insert settings;
        
        // Clear cache
        AIStagingMatcherService.clearCache();
        
        // Build cache - email exists in both Lead and Contact
        Set<String> emails = new Set<String>{ TEST_EMAIL };
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        
        Test.startTest();
        AIStagingMatcherService.MatchResult result = 
            AIStagingMatcherService.matchEmail(TEST_EMAIL, cache);
        Test.stopTest();
        
        // Should match at precedence 1 and return BOTH Lead and Contact
        // Plus domain-based Account matches (independent feature)
        Assert.isTrue(result.isMatched, 'Should match');
        Assert.areEqual(1, result.precedenceLevel, 'Should match at precedence 1');
        Assert.isFalse(result.matchedLeadIds.isEmpty(), 'Should have matched Lead IDs');
        Assert.isFalse(result.matchedContactIds.isEmpty(), 'Should have matched Contact IDs');
        // Total count includes Lead (1) + Contact (1) + domain-based Accounts (1+)
        Assert.isTrue(result.getTotalMatchCount() >= 2, 'Should have at least 2 total matches (Lead + Contact, plus optional domain Accounts)');
    }
    
    @isTest
    static void testMatchEmailWithPrecedencePartialMatch() {
        // Create a unique email that exists only in Lead, not in Contact
        String leadOnlyEmail = 'leadonly@example.com';
        Lead leadOnlyLead = new Lead(
            FirstName = 'Lead',
            LastName = 'Only',
            Company = 'Lead Only Company',
            Email = leadOnlyEmail
        );
        insert leadOnlyLead;
        
        // Set up precedence config: Level 1 requires both, Level 2 is just Lead
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"], "2": ["Lead"]}';
        insert settings;
        
        // Clear cache
        AIStagingMatcherService.clearCache();
        
        Set<String> emails = new Set<String>{ leadOnlyEmail };
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        
        Test.startTest();
        AIStagingMatcherService.MatchResult result = 
            AIStagingMatcherService.matchEmail(leadOnlyEmail, cache);
        Test.stopTest();
        
        // Should fail Level 1 (no Contact) but match Level 2 (just Lead)
        Assert.isTrue(result.isMatched, 'Should match at Level 2');
        Assert.areEqual(2, result.precedenceLevel, 'Should match at precedence 2');
        Assert.isFalse(result.matchedLeadIds.isEmpty(), 'Should have matched Lead ID');
        Assert.isTrue(result.matchedContactIds.isEmpty(), 'Should NOT have Contact ID');
    }
    
    @isTest
    static void testMatchEmailNoMatch() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"]}';
        insert settings;
        
        // Clear cache
        AIStagingMatcherService.clearCache();
        
        // Use a domain that won't match any Account (not example.com which has Account)
        String nonExistentEmail = 'nonexistent@nowhere-domain-xyz.com';
        Set<String> emails = new Set<String>{ nonExistentEmail };
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        
        Test.startTest();
        AIStagingMatcherService.MatchResult result = 
            AIStagingMatcherService.matchEmail(nonExistentEmail, cache);
        Test.stopTest();
        
        Assert.isFalse(result.isMatched, 'Should not match Lead/Contact');
        Assert.areEqual(0, result.getTotalMatchCount(), 'Should have 0 matches (no Lead, Contact, or domain Account)');
    }
    
    @isTest
    static void testMatchEmailBlankEmail() {
        Set<String> emails = new Set<String>{ TEST_EMAIL };
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        
        Test.startTest();
        AIStagingMatcherService.MatchResult result = 
            AIStagingMatcherService.matchEmail('', cache);
        Test.stopTest();
        
        Assert.isFalse(result.isMatched, 'Blank email should not match');
    }
    
    @isTest
    static void testMatchEmailNullCache() {
        Test.startTest();
        AIStagingMatcherService.MatchResult result = 
            AIStagingMatcherService.matchEmail(TEST_EMAIL, null);
        Test.stopTest();
        
        Assert.isFalse(result.isMatched, 'Null cache should not match');
    }
    
    @isTest
    static void testIsMatchingEnabled() {
        // Clear any existing settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        AIStagingMatcherService.clearCache();
        
        Test.startTest();
        // Matching is ALWAYS enabled (uses default config when empty)
        Boolean enabledWithoutSettings = AIStagingMatcherService.isMatchingEnabled();
        
        // Now add settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead"]}';
        insert settings;
        AIStagingMatcherService.clearCache();
        
        Boolean enabledWithSettings = AIStagingMatcherService.isMatchingEnabled();
        Test.stopTest();
        
        Assert.isTrue(enabledWithoutSettings, 'Should be enabled even without settings (uses default)');
        Assert.isTrue(enabledWithSettings, 'Should be enabled with settings');
    }
    
    @isTest
    static void testDefaultPrecedenceWhenEmpty() {
        // Clear any existing settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        AIStagingMatcherService.clearCache();
        
        Test.startTest();
        Map<Integer, List<String>> config = AIStagingMatcherService.getPrecedenceConfig();
        Test.stopTest();
        
        // Should have default config
        Assert.isFalse(config.isEmpty(), 'Should have default config when empty');
        Assert.isTrue(config.containsKey(1), 'Should have level 1');
        Assert.isTrue(config.containsKey(2), 'Should have level 2');
        Assert.isTrue(config.containsKey(3), 'Should have level 3');
        
        // Verify default structure
        Assert.areEqual(2, config.get(1).size(), 'Level 1 should have Lead and Contact');
        Assert.areEqual(1, config.get(2).size(), 'Level 2 should have Lead only');
        Assert.areEqual(1, config.get(3).size(), 'Level 3 should have Contact only');
    }
    
    @isTest
    static void testCustomPrecedenceLeadOnly() {
        // Set up precedence config with ONLY Lead
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        Test.startTest();
        Map<Integer, List<String>> config = AIStagingMatcherService.getPrecedenceConfig();
        Test.stopTest();
        
        // Should only have Lead in level 1
        Assert.areEqual(1, config.size(), 'Should have only 1 level');
        Assert.areEqual(1, config.get(1).size(), 'Level 1 should have only Lead');
        Assert.areEqual('Lead', config.get(1)[0], 'Should be Lead');
    }
    
    @isTest
    static void testCustomPrecedenceContactOnly() {
        // Set up precedence config with ONLY Contact
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Contact"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        Test.startTest();
        Map<Integer, List<String>> config = AIStagingMatcherService.getPrecedenceConfig();
        Test.stopTest();
        
        // Should only have Contact in level 1
        Assert.areEqual(1, config.size(), 'Should have only 1 level');
        Assert.areEqual(1, config.get(1).size(), 'Level 1 should have only Contact');
        Assert.areEqual('Contact', config.get(1)[0], 'Should be Contact');
    }
    
    @isTest
    static void testUserEntriesAreIgnored() {
        // Set up precedence config with User (should be ignored)
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "User", "Contact"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        Test.startTest();
        Map<Integer, List<String>> config = AIStagingMatcherService.getPrecedenceConfig();
        Test.stopTest();
        
        // User should be filtered out
        Assert.areEqual(2, config.get(1).size(), 'Level 1 should have only Lead and Contact (User ignored)');
    }
    
    @isTest
    static void testMatchResultHelperMethods() {
        AIStagingMatcherService.MatchResult result = new AIStagingMatcherService.MatchResult();
        
        // Initially empty
        Assert.areEqual(0, result.getTotalMatchCount(), 'Initial count should be 0');
        Assert.isFalse(result.hasMultipleMatches(), 'Should not have multiple matches');
        
        // Add some IDs
        result.matchedLeadIds.add('00Q000000000001AAA');
        result.matchedContactIds.add('003000000000001AAA');
        
        Assert.areEqual(2, result.getTotalMatchCount(), 'Should have 2 matches');
        Assert.isTrue(result.hasMultipleMatches(), 'Should have multiple matches');
    }
    
    @isTest
    static void testMultiMatchResultHelperMethods() {
        AIStagingMatcherService.MultiMatchResult result = new AIStagingMatcherService.MultiMatchResult();
        
        // Add some match results
        AIStagingMatcherService.MatchResult match1 = new AIStagingMatcherService.MatchResult();
        match1.matchedLeadIds.add('00Q000000000001AAA');
        match1.matchedContactIds.add('003000000000001AAA');
        
        AIStagingMatcherService.MatchResult match2 = new AIStagingMatcherService.MatchResult();
        match2.matchedLeadIds.add('00Q000000000002AAA');
        
        result.allMatches.add(match1);
        result.allMatches.add(match2);
        
        Set<Id> allLeadIds = result.getAllLeadIds();
        Set<Id> allContactIds = result.getAllContactIds();
        Integer totalRelations = result.getTotalRelationCount();
        
        Assert.areEqual(2, allLeadIds.size(), 'Should have 2 unique Lead IDs');
        Assert.areEqual(1, allContactIds.size(), 'Should have 1 unique Contact ID');
        Assert.areEqual(3, totalRelations, 'Should have 3 total relations');
    }
    
    @isTest
    static void testMatchEmailStagingRecordsMulti() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"], "2": ["Lead"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        // Create a staging record (mocked - we just need the From_Address__c)
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = TEST_EMAIL,
            To_Address__c = 'recipient@example.com',
            Subject__c = 'Test Subject',
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, From_Address__c, To_Address__c, Cc_Address__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchEmailStagingRecordsMulti(records);
        Test.stopTest();
        
        Assert.isTrue(results.containsKey(staging.Id), 'Should have result for staging record');
        AIStagingMatcherService.MultiMatchResult multiResult = results.get(staging.Id);
        Assert.isTrue(multiResult.hasPrimaryMatch, 'Should have primary match from From address');
    }
    
    @isTest
    static void testBuildEmailMatchCache_WithDomainMatching() {
        Set<String> emails = new Set<String>{ 'user@example.com', 'sales@acme.com' };
        
        Test.startTest();
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        Test.stopTest();
        
        // Should have domain-based Account mappings
        Assert.isTrue(cache.domainToAccountIds.containsKey('example.com'), 'Should find example.com domain');
        Assert.isTrue(cache.domainToAccountIds.containsKey('acme.com'), 'Should find acme.com domain');
        
        // Verify Account IDs are populated
        Assert.isFalse(cache.domainToAccountIds.get('example.com').isEmpty(), 'Should have Account IDs for example.com');
        Assert.isFalse(cache.domainToAccountIds.get('acme.com').isEmpty(), 'Should have Account IDs for acme.com');
    }
    
    @isTest
    static void testMatchEmail_WithDomainBasedAccountMatching() {
        // Set up precedence config
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        // Build cache with email that matches Contact/Lead AND has domain for Account
        Set<String> emails = new Set<String>{ TEST_EMAIL };
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        
        Test.startTest();
        AIStagingMatcherService.MatchResult result = 
            AIStagingMatcherService.matchEmail(TEST_EMAIL, cache);
        Test.stopTest();
        
        // Should match Lead and Contact (precedence) AND Account (domain-based)
        Assert.isTrue(result.isMatched, 'Should match');
        Assert.isFalse(result.matchedLeadIds.isEmpty(), 'Should have matched Lead');
        Assert.isFalse(result.matchedContactIds.isEmpty(), 'Should have matched Contact');
        Assert.isFalse(result.matchedAccountIds.isEmpty(), 'Should have matched Account via domain');
    }
    
    @isTest
    static void testMatchEmail_DomainMatchOnly_NoContactOrLead() {
        // Create email with domain that matches Account but no Contact/Lead
        String domainOnlyEmail = 'newuser@acme.com';
        
        // Set up precedence config
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        // Build cache
        Set<String> emails = new Set<String>{ domainOnlyEmail };
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        
        Test.startTest();
        AIStagingMatcherService.MatchResult result = 
            AIStagingMatcherService.matchEmail(domainOnlyEmail, cache);
        Test.stopTest();
        
        // Should NOT match Lead/Contact but SHOULD match Account via domain
        Assert.isFalse(result.isMatched, 'Should not match precedence (no Lead/Contact)');
        Assert.isTrue(result.matchedLeadIds.isEmpty(), 'Should not have matched Lead');
        Assert.isTrue(result.matchedContactIds.isEmpty(), 'Should not have matched Contact');
        Assert.isFalse(result.matchedAccountIds.isEmpty(), 'Should have matched Account via domain (independent)');
    }
    
    @isTest
    static void testBuildEmailMatchCache_PublicDomainSkipped() {
        // Create Account with public domain (should not be cached)
        Account gmailAccount = new Account(
            Name = 'Gmail Account',
            Website = 'https://gmail.com'
        );
        insert gmailAccount;
        
        Set<String> emails = new Set<String>{ 'user@gmail.com' };
        
        Test.startTest();
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        Test.stopTest();
        
        // Should NOT have gmail.com in domain mappings (public domain)
        Assert.isFalse(cache.domainToAccountIds.containsKey('gmail.com'), 'Should skip public email domain');
    }
    
    @isTest
    static void testMatchResult_WithAccountIds() {
        AIStagingMatcherService.MatchResult result = new AIStagingMatcherService.MatchResult();
        
        // Add Lead, Contact, and Account IDs
        result.matchedLeadIds.add('00Q000000000001AAA');
        result.matchedContactIds.add('003000000000001AAA');
        result.matchedAccountIds.add('001000000000001AAA');
        result.matchedAccountIds.add('001000000000002AAA');
        
        // Should count all matched records including Accounts
        Assert.areEqual(4, result.getTotalMatchCount(), 'Should count Lead + Contact + Accounts');
        Assert.isTrue(result.hasMultipleMatches(), 'Should have multiple matches');
    }
    
    @isTest
    static void testMatchEmailStagingRecordsMulti_ExcludesConnectedAccountEmail() {
        // Test the connected account email exclusion feature (V2-8XXX)
        // When a user connects their Outlook/Gmail account, their connected email should be 
        // excluded from automatch to avoid matching to themselves
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"], "2": ["Lead"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        // Create a staging record where the From address is the connected account email
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
        
        // The connected account email exists in both Lead and Contact
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = TEST_EMAIL,  // This email exists in Lead and Contact
            To_Address__c = 'recipient@example.com',
            Subject__c = 'Test Subject',
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, From_Address__c, To_Address__c, Cc_Address__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        // Pass the connected account email (same as From address) - should be excluded
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchEmailStagingRecordsMulti(records, TEST_EMAIL);
        Test.stopTest();
        
        // The From address should be excluded, so no primary match
        Assert.isTrue(results.containsKey(staging.Id), 'Should have result for staging record');
        AIStagingMatcherService.MultiMatchResult multiResult = results.get(staging.Id);
        
        // Since From address = connected email and is excluded, there should be no match from From
        // The To address (recipient@example.com) doesn't exist in Lead/Contact either
        Assert.isFalse(multiResult.hasPrimaryMatch, 'Should NOT have primary match when connected email is excluded');
    }
    
    @isTest
    static void testMatchEmailStagingRecordsMulti_ExcludesConnectedAccountEmail_InToAndCc() {
        // Test that connected account email is also excluded from To and CC
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"], "2": ["Lead"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        // Create another Lead/Contact with a different email
        String otherEmail = 'other@different.com';
        Lead otherLead = new Lead(
            FirstName = 'Other',
            LastName = 'Person',
            Company = 'Other Company',
            Email = otherEmail
        );
        insert otherLead;
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
        
        // Create staging where From is other person but To includes connected email
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = otherEmail,
            To_Address__c = TEST_EMAIL,  // Connected account email in To
            Cc_Address__c = 'cc@example.com',
            Subject__c = 'Test Subject',
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, From_Address__c, To_Address__c, Cc_Address__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        // Pass TEST_EMAIL as connected account email - should exclude it from To field matching
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchEmailStagingRecordsMulti(records, TEST_EMAIL);
        Test.stopTest();
        
        AIStagingMatcherService.MultiMatchResult multiResult = results.get(staging.Id);
        
        // Should match the From address (other@different.com -> Lead)
        // But should NOT match the To address (TEST_EMAIL is excluded)
        Assert.isTrue(multiResult.hasAnyMatch, 'Should have match from From address');
        
        // Check that the excluded email is not in the matches
        for (AIStagingMatcherService.MatchResult match : multiResult.allMatches) {
            Assert.areNotEqual(TEST_EMAIL.toLowerCase(), match.matchedEmail, 
                'Connected account email should not appear in matches');
        }
    }
    
    @isTest
    static void testMatchCalendarStagingRecordsMulti_ExcludesConnectedAccountEmail() {
        // Test that connected account email is excluded from calendar event matching
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"], "2": ["Lead"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Calendar')
            ?.getRecordTypeId();
        
        // Create calendar staging where organizer is the connected account email
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Organizer__c = 'Connected User <' + TEST_EMAIL + '>',
            Attendees__c = 'attendee@different.com\nother@person.com',
            Subject__c = 'Test Meeting',
            Start_DateTime__c = DateTime.now().addHours(1),
            End_DateTime__c = DateTime.now().addHours(2),
            RecordTypeId = calendarRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, Organizer__c, Attendees__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        // Pass TEST_EMAIL as connected account email - should exclude it from organizer matching
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchCalendarStagingRecordsMulti(records, TEST_EMAIL);
        Test.stopTest();
        
        AIStagingMatcherService.MultiMatchResult multiResult = results.get(staging.Id);
        
        // The organizer email (TEST_EMAIL) should be excluded
        // Other attendees don't exist in Lead/Contact, so no match expected
        // Check that the excluded email is not in any matches
        for (AIStagingMatcherService.MatchResult match : multiResult.allMatches) {
            Assert.areNotEqual(TEST_EMAIL.toLowerCase(), match.matchedEmail, 
                'Connected account email should not appear in calendar matches');
        }
    }
    
    @isTest
    static void testMatchEmailStagingRecordsMulti_NullConnectedEmailBehavior() {
        // Test that passing null for connected email doesn't affect normal matching
        
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead", "Contact"], "2": ["Lead"]}';
        insert settings;
        
        AIStagingMatcherService.clearCache();
        
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = TEST_EMAIL,
            To_Address__c = 'recipient@example.com',
            Subject__c = 'Test Subject',
            RecordTypeId = emailRecordTypeId,
            Provider__c = 'MICROSOFT_EMAIL',
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, From_Address__c, To_Address__c, Cc_Address__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        // Pass null for connected email - should match normally
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchEmailStagingRecordsMulti(records, null);
        Test.stopTest();
        
        // Should have normal matching behavior
        AIStagingMatcherService.MultiMatchResult multiResult = results.get(staging.Id);
        Assert.isTrue(multiResult.hasPrimaryMatch, 'Should have primary match when no email is excluded');
    }
    
    /**
     * Test precedence config with invalid JSON
     */
    @isTest
    static void testPrecedenceConfigWithInvalidJSON() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = 'invalid json {{{';
        insert settings;
        
        // Clear cache
        AIStagingMatcherService.clearCache();
        
        Test.startTest();
        Map<Integer, List<String>> config = AIStagingMatcherService.getPrecedenceConfig();
        Test.stopTest();
        
        // Should return default config on JSON parse error
        Assert.isFalse(config.isEmpty(), 'Should return default config on error');
        Assert.isTrue(config.containsKey(1), 'Should have precedence level 1');
    }
    
    /**
     * Test precedence config with only User entries (should be filtered out)
     */
    @isTest
    static void testPrecedenceConfigWithOnlyUserEntries() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["User"]}';
        insert settings;
        
        // Clear cache
        AIStagingMatcherService.clearCache();
        
        Test.startTest();
        Map<Integer, List<String>> config = AIStagingMatcherService.getPrecedenceConfig();
        Test.stopTest();
        
        // Should return default config when all entries are filtered out
        Assert.isFalse(config.isEmpty(), 'Should return default config');
        Assert.isTrue(config.containsKey(1), 'Should have default precedence levels');
    }
    
    /**
     * Test parseEmailList with various delimiters
     */
    @isTest
    static void testParseEmailListWithVariousDelimiters() {
        // Create staging record with comma-separated emails
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
            
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = TEST_EMAIL,
            To_Address__c = 'user1@test.com,user2@test.com;user3@test.com',
            Cc_Address__c = 'user4@test.com',
            RecordTypeId = emailRecordTypeId,
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, From_Address__c, To_Address__c, Cc_Address__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchEmailStagingRecordsMulti(records);
        Test.stopTest();
        
        // Should parse all emails
        Assert.isTrue(results.containsKey(staging.Id), 'Should process staging record');
    }
    
    /**
     * Test extractEmailFromField with various formats
     */
    @isTest
    static void testExtractEmailFromFieldVariousFormats() {
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Calendar')
            ?.getRecordTypeId();
            
        // Test with "Name <email>" format
        AI_Workspace_Staging__c staging1 = new AI_Workspace_Staging__c(
            Organizer__c = 'John Doe <john@example.com>',
            Attendees__c = 'Jane Smith <jane@example.com>',
            RecordTypeId = calendarRecordTypeId,
            Status__c = 'Staged'
        );
        insert staging1;
        
        // Test with plain email format
        AI_Workspace_Staging__c staging2 = new AI_Workspace_Staging__c(
            Organizer__c = 'organizer@test.com',
            Attendees__c = 'attendee@test.com',
            RecordTypeId = calendarRecordTypeId,
            Status__c = 'Staged'
        );
        insert staging2;
        
        // Test with name only (no email)
        AI_Workspace_Staging__c staging3 = new AI_Workspace_Staging__c(
            Organizer__c = 'John Doe',
            Attendees__c = 'Jane Smith',
            RecordTypeId = calendarRecordTypeId,
            Status__c = 'Staged'
        );
        insert staging3;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, Organizer__c, Attendees__c
            FROM AI_Workspace_Staging__c 
            WHERE Id IN (:staging1.Id, :staging2.Id, :staging3.Id)
        ];
        
        Test.startTest();
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchCalendarStagingRecordsMulti(records);
        Test.stopTest();
        
        // Should handle all formats
        Assert.areEqual(3, results.size(), 'Should process all staging records');
    }
    
    /**
     * Test matchCalendarStagingRecords (deprecated single match method)
     */
    @isTest
    static void testMatchCalendarStagingRecordsSingleMatch() {
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Calendar')
            ?.getRecordTypeId();
            
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Organizer__c = TEST_EMAIL,
            Attendees__c = 'other@test.com',
            RecordTypeId = calendarRecordTypeId,
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, Organizer__c, Attendees__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        Map<Id, AIStagingMatcherService.MatchResult> results = 
            AIStagingMatcherService.matchCalendarStagingRecords(records);
        Test.stopTest();
        
        // Should return single best match
        Assert.isTrue(results.containsKey(staging.Id), 'Should have result');
        AIStagingMatcherService.MatchResult result = results.get(staging.Id);
        Assert.isTrue(result.isMatched, 'Should match organizer email');
    }
    
    /**
     * Test matchStagingRecords (deprecated method)
     */
    @isTest
    static void testMatchStagingRecordsDeprecated() {
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
            
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = TEST_EMAIL,
            RecordTypeId = emailRecordTypeId,
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, From_Address__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        Map<Id, AIStagingMatcherService.MatchResult> results = 
            AIStagingMatcherService.matchStagingRecords(records);
        Test.stopTest();
        
        // Should match using From_Address__c only
        Assert.isTrue(results.containsKey(staging.Id), 'Should have result');
        Assert.isTrue(results.get(staging.Id).isMatched, 'Should match');
    }
    
    /**
     * Test matchStagingRecords with empty list
     */
    @isTest
    static void testMatchStagingRecordsEmpty() {
        Test.startTest();
        Map<Id, AIStagingMatcherService.MatchResult> results = 
            AIStagingMatcherService.matchStagingRecords(new List<AI_Workspace_Staging__c>());
        Test.stopTest();
        
        Assert.isTrue(results.isEmpty(), 'Should return empty map');
    }
    
    /**
     * Test matchStagingRecords with null list
     */
    @isTest
    static void testMatchStagingRecordsNull() {
        Test.startTest();
        Map<Id, AIStagingMatcherService.MatchResult> results = 
            AIStagingMatcherService.matchStagingRecords(null);
        Test.stopTest();
        
        Assert.isTrue(results.isEmpty(), 'Should return empty map');
    }
    
    /**
     * Test matchEmailStagingRecordsMulti with empty list
     */
    @isTest
    static void testMatchEmailStagingRecordsMultiEmpty() {
        Test.startTest();
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchEmailStagingRecordsMulti(new List<AI_Workspace_Staging__c>());
        Test.stopTest();
        
        Assert.isTrue(results.isEmpty(), 'Should return empty map');
    }
    
    /**
     * Test matchEmailStagingRecordsMulti with null list
     */
    @isTest
    static void testMatchEmailStagingRecordsMultiNull() {
        Test.startTest();
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchEmailStagingRecordsMulti(null);
        Test.stopTest();
        
        Assert.isTrue(results.isEmpty(), 'Should return empty map');
    }
    
    /**
     * Test matchCalendarStagingRecordsMulti with empty list
     */
    @isTest
    static void testMatchCalendarStagingRecordsMultiEmpty() {
        Test.startTest();
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchCalendarStagingRecordsMulti(new List<AI_Workspace_Staging__c>());
        Test.stopTest();
        
        Assert.isTrue(results.isEmpty(), 'Should return empty map');
    }
    
    /**
     * Test matchCalendarStagingRecordsMulti with null list
     */
    @isTest
    static void testMatchCalendarStagingRecordsMultiNull() {
        Test.startTest();
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchCalendarStagingRecordsMulti(null);
        Test.stopTest();
        
        Assert.isTrue(results.isEmpty(), 'Should return empty map');
    }
    
    /**
     * Test matchCalendarStagingRecords with empty list
     */
    @isTest
    static void testMatchCalendarStagingRecordsEmpty() {
        Test.startTest();
        Map<Id, AIStagingMatcherService.MatchResult> results = 
            AIStagingMatcherService.matchCalendarStagingRecords(new List<AI_Workspace_Staging__c>());
        Test.stopTest();
        
        Assert.isTrue(results.isEmpty(), 'Should return empty map');
    }
    
    /**
     * Test matchCalendarStagingRecords with null list
     */
    @isTest
    static void testMatchCalendarStagingRecordsNull() {
        Test.startTest();
        Map<Id, AIStagingMatcherService.MatchResult> results = 
            AIStagingMatcherService.matchCalendarStagingRecords(null);
        Test.stopTest();
        
        Assert.isTrue(results.isEmpty(), 'Should return empty map');
    }
    
    /**
     * Test extractDomain with edge cases
     */
    @isTest
    static void testExtractDomainEdgeCases() {
        // Test with emails that have domains
        Set<String> emails = new Set<String>{ 
            'user@domain.com',
            'test@sub.domain.com',
            'invalid-email',
            '@nodomain.com',
            'noatsign.com'
        };
        
        Test.startTest();
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        Test.stopTest();
        
        // Should handle various email formats
        Assert.isNotNull(cache, 'Should return cache');
    }
    
    /**
     * Test buildEmailMatchCache with blank emails in set
     */
    @isTest
    static void testBuildEmailMatchCacheWithBlankEmails() {
        Set<String> emails = new Set<String>{ '', '   ', null, TEST_EMAIL };
        
        Test.startTest();
        AIStagingMatcherService.EmailMatchCache cache = 
            AIStagingMatcherService.buildEmailMatchCache(emails);
        Test.stopTest();
        
        // Should filter out blank emails and process valid ones
        Assert.isTrue(cache.emailToLeadId.containsKey(TEST_EMAIL), 'Should find Lead for valid email');
    }
    
    /**
     * Test precedence config caching
     */
    @isTest
    static void testPrecedenceConfigCaching() {
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c();
        settings.Sync_Precedence__c = '{"1": ["Lead"]}';
        insert settings;
        
        // Clear cache
        AIStagingMatcherService.clearCache();
        
        Test.startTest();
        // First call - should query and cache
        Map<Integer, List<String>> config1 = AIStagingMatcherService.getPrecedenceConfig();
        // Second call - should return cached value
        Map<Integer, List<String>> config2 = AIStagingMatcherService.getPrecedenceConfig();
        Test.stopTest();
        
        // Both should return same config
        Assert.areEqual(config1.size(), config2.size(), 'Should return cached config');
    }
    
    /**
     * Test matchEmailStagingRecordsMulti with duplicate matches
     */
    @isTest
    static void testMatchEmailStagingRecordsMultiDuplicatePrevention() {
        Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName()
            .get('Email')
            ?.getRecordTypeId();
            
        // Create staging with same email in To and CC
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            From_Address__c = 'sender@test.com',
            To_Address__c = TEST_EMAIL,
            Cc_Address__c = TEST_EMAIL,
            RecordTypeId = emailRecordTypeId,
            Status__c = 'Staged'
        );
        insert staging;
        
        List<AI_Workspace_Staging__c> records = [
            SELECT Id, From_Address__c, To_Address__c, Cc_Address__c
            FROM AI_Workspace_Staging__c WHERE Id = :staging.Id
        ];
        
        Test.startTest();
        Map<Id, AIStagingMatcherService.MultiMatchResult> results = 
            AIStagingMatcherService.matchEmailStagingRecordsMulti(records);
        Test.stopTest();
        
        // Should not create duplicate matches for same email
        AIStagingMatcherService.MultiMatchResult multiResult = results.get(staging.Id);
        // When same email appears in To and CC, it should only match once (duplicate prevention)
        Assert.areEqual(1, multiResult.allMatches.size(), 'Should have only one match (duplicate prevented)');
        Assert.isTrue(multiResult.hasPrimaryMatch, 'Should have primary match');
    }
}