/**
 * Test class for AIEmailExclusionService
 */
@isTest
private class AIEmailExclusionServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create org-level settings
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Exclude_Marketing__c = true,
            Exclude_Confidential__c = true,
            Exclude_Internal__c = true,
            Internal_Domains__c = 'mycompany.com,internal.org'
        );
        insert settings;
    }

    @isTest
    static void testExclusionResult_DefaultConstructor() {
        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = new AIEmailExclusionService.ExclusionResult();
        Test.stopTest();

        Assert.areEqual(false, result.excluded, 'Should default to not excluded');
        Assert.areEqual(null, result.reason, 'Reason should be null');
        Assert.areEqual('None', result.category, 'Category should be None');
    }

    @isTest
    static void testExclusionResult_ParameterizedConstructor() {
        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = new AIEmailExclusionService.ExclusionResult(
            true,
            'Test reason',
            'Marketing'
        );
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Test reason', result.reason, 'Reason should match');
        Assert.areEqual('Marketing', result.category, 'Category should match');
    }

    @isTest
    static void testBatchExclusionResult_Constructor() {
        Test.startTest();
        AIEmailExclusionService.BatchExclusionResult result = new AIEmailExclusionService.BatchExclusionResult();
        Test.stopTest();

        Assert.areNotEqual(null, result.includedEmails, 'Included emails should be initialized');
        Assert.areNotEqual(null, result.excludedEmails, 'Excluded emails should be initialized');
        Assert.areNotEqual(null, result.exclusionCounts, 'Exclusion counts should be initialized');
        Assert.areEqual(0, result.exclusionCounts.get('Marketing'), 'Marketing count should be 0');
        Assert.areEqual(0, result.exclusionCounts.get('Confidential'), 'Confidential count should be 0');
        Assert.areEqual(0, result.exclusionCounts.get('Internal'), 'Internal count should be 0');
    }

    @isTest
    static void testCheckExclusion_MarketingExchangeCategory() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('categories', new List<String>{'Promotions'});

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testCheckExclusion_MarketingExchangeMultipleCategories() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('categories', new List<String>{'Work', 'Marketing', 'Important'});

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testCheckExclusion_MarketingGmailLabel() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('labelIds', new List<String>{'INBOX', 'CATEGORY_PROMOTIONS'});

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'GMAIL_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testCheckExclusion_MarketingGmailSocialLabel() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('labelIds', new List<String>{'CATEGORY_SOCIAL'});

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'GMAIL_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testCheckExclusion_MarketingDomain() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'sender@mailchimp.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testCheckExclusion_MarketingNoReplySender() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'noreply@example.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testCheckExclusion_MarketingNewsletterSender() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'newsletter@example.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testCheckExclusion_ConfidentialExchangeSensitivity() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('sensitivity', 'private');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Confidential', result.category, 'Should be Confidential category');
    }

    @isTest
    static void testCheckExclusion_ConfidentialExchangeEncrypted() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('isEncrypted', true);

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Confidential', result.category, 'Should be Confidential category');
    }

    @isTest
    static void testCheckExclusion_ConfidentialGmailHeader() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        
        List<Map<String, Object>> headers = new List<Map<String, Object>>();
        Map<String, Object> header = new Map<String, Object>();
        header.put('name', 'Sensitivity');
        header.put('value', 'Private');
        headers.add(header);
        email.put('headers', headers);

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'GMAIL_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Confidential', result.category, 'Should be Confidential category');
    }

    @isTest
    static void testCheckExclusion_ConfidentialBodyPreview() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('bodyPreview', 'Classified as Confidential - This is a test email');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Confidential', result.category, 'Should be Confidential category');
    }

    @isTest
    static void testCheckExclusion_ConfidentialSubject() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', '[CONFIDENTIAL] Test Email');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Confidential', result.category, 'Should be Confidential category');
    }

    @isTest
    static void testCheckExclusion_InternalFromAddress() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@mycompany.com');

        Test.startTest();
        List<Map<String, Object>> emails = new List<Map<String, Object>>{email};
        AIEmailExclusionService.BatchExclusionResult batchResult = AIEmailExclusionService.filterBatch(
            emails,
            'MICROSOFT_EMAIL',
            'test@mycompany.com'
        );
        Test.stopTest();

        Assert.areEqual(1, batchResult.excludedEmails.size(), 'Should have 1 excluded email');
        Assert.areEqual(0, batchResult.includedEmails.size(), 'Should have 0 included emails');
        Assert.areEqual(1, batchResult.exclusionCounts.get('Internal'), 'Should have 1 internal exclusion');
    }

    @isTest
    static void testCheckExclusion_InternalFromObject() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        
        Map<String, Object> fromObj = new Map<String, Object>();
        Map<String, Object> emailAddress = new Map<String, Object>();
        emailAddress.put('address', 'user@internal.org');
        fromObj.put('emailAddress', emailAddress);
        email.put('from', fromObj);

        Test.startTest();
        List<Map<String, Object>> emails = new List<Map<String, Object>>{email};
        AIEmailExclusionService.BatchExclusionResult batchResult = AIEmailExclusionService.filterBatch(
            emails,
            'MICROSOFT_EMAIL',
            'test@internal.org'
        );
        Test.stopTest();

        Assert.areEqual(1, batchResult.excludedEmails.size(), 'Should have 1 excluded email');
        Assert.areEqual(0, batchResult.includedEmails.size(), 'Should have 0 included emails');
        Assert.areEqual(1, batchResult.exclusionCounts.get('Internal'), 'Should have 1 internal exclusion');
    }

    @isTest
    static void testCheckExclusion_NotExcluded() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@external.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(false, result.excluded, 'Should not be excluded');
        Assert.areEqual('None', result.category, 'Should be None category');
    }

    @isTest
    static void testCheckExclusion_MarketingDisabled() {
        AIEmailExclusionService.clearCache();
        
        // Create settings with Marketing disabled
        AI_Workspace_Sync_Settings__c testSettings = new AI_Workspace_Sync_Settings__c(
            Exclude_Marketing__c = false,
            Exclude_Confidential__c = true,
            Exclude_Internal__c = true
        );
        AIEmailExclusionService.setCachedSettings(testSettings);
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'noreply@example.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(false, result.excluded, 'Should not be excluded when marketing filter is disabled');
    }

    @isTest
    static void testCheckExclusion_ConfidentialDisabled() {
        AIEmailExclusionService.clearCache();
        
        // Create settings with Confidential disabled
        AI_Workspace_Sync_Settings__c testSettings = new AI_Workspace_Sync_Settings__c(
            Exclude_Marketing__c = true,
            Exclude_Confidential__c = false,
            Exclude_Internal__c = true
        );
        AIEmailExclusionService.setCachedSettings(testSettings);
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('sensitivity', 'private');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(false, result.excluded, 'Should not be excluded when confidential filter is disabled');
    }

    @isTest
    static void testCheckExclusion_InternalDisabled() {
        AIEmailExclusionService.clearCache();
        
        // Create settings with Internal disabled
        AI_Workspace_Sync_Settings__c testSettings = new AI_Workspace_Sync_Settings__c(
            Exclude_Marketing__c = true,
            Exclude_Confidential__c = true,
            Exclude_Internal__c = false
        );
        AIEmailExclusionService.setCachedSettings(testSettings);
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@mycompany.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(false, result.excluded, 'Should not be excluded when internal filter is disabled');
    }

    @isTest
    static void testFilterBatch_MixedEmails() {
        AIEmailExclusionService.clearCache();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        // Marketing email
        Map<String, Object> email1 = new Map<String, Object>();
        email1.put('subject', 'Marketing Email');
        email1.put('fromAddress', 'noreply@example.com');
        emails.add(email1);
        
        // Confidential email
        Map<String, Object> email2 = new Map<String, Object>();
        email2.put('subject', '[CONFIDENTIAL] Secret Email');
        emails.add(email2);
        
        // Internal email
        Map<String, Object> email3 = new Map<String, Object>();
        email3.put('subject', 'Internal Email');
        email3.put('fromAddress', 'user@mycompany.com');
        emails.add(email3);
        
        // Normal email
        Map<String, Object> email4 = new Map<String, Object>();
        email4.put('subject', 'Normal Email');
        email4.put('fromAddress', 'user@external.com');
        emails.add(email4);

        Test.startTest();
        AIEmailExclusionService.BatchExclusionResult result = AIEmailExclusionService.filterBatch(
            emails,
            'MICROSOFT_EMAIL',
            'test@mycompany.com'
        );
        Test.stopTest();

        Assert.areEqual(1, result.includedEmails.size(), 'Should have 1 included email');
        Assert.areEqual(3, result.excludedEmails.size(), 'Should have 3 excluded emails');
        Assert.areEqual(1, result.exclusionCounts.get('Marketing'), 'Should have 1 marketing exclusion');
        Assert.areEqual(1, result.exclusionCounts.get('Confidential'), 'Should have 1 confidential exclusion');
        Assert.areEqual(1, result.exclusionCounts.get('Internal'), 'Should have 1 internal exclusion');
    }

    @isTest
    static void testFilterBatch_AllIncluded() {
        AIEmailExclusionService.clearCache();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        for (Integer i = 0; i < 5; i++) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('subject', 'Email ' + i);
            email.put('fromAddress', 'user' + i + '@external.com');
            emails.add(email);
        }

        Test.startTest();
        AIEmailExclusionService.BatchExclusionResult result = AIEmailExclusionService.filterBatch(
            emails,
            'MICROSOFT_EMAIL',
            'test@mycompany.com'
        );
        Test.stopTest();

        Assert.areEqual(5, result.includedEmails.size(), 'Should have 5 included emails');
        Assert.areEqual(0, result.excludedEmails.size(), 'Should have 0 excluded emails');
    }

    @isTest
    static void testFilterBatch_AllExcluded() {
        AIEmailExclusionService.clearCache();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        for (Integer i = 0; i < 5; i++) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('subject', 'Email ' + i);
            email.put('fromAddress', 'user' + i + '@mycompany.com');
            emails.add(email);
        }

        Test.startTest();
        AIEmailExclusionService.BatchExclusionResult result = AIEmailExclusionService.filterBatch(
            emails,
            'MICROSOFT_EMAIL',
            'test@mycompany.com'
        );
        Test.stopTest();

        Assert.areEqual(0, result.includedEmails.size(), 'Should have 0 included emails');
        Assert.areEqual(5, result.excludedEmails.size(), 'Should have 5 excluded emails');
        Assert.areEqual(5, result.exclusionCounts.get('Internal'), 'Should have 5 internal exclusions');
    }

    @isTest
    static void testToExclusionSummaryJson() {
        Map<String, Integer> counts = new Map<String, Integer>();
        counts.put('Marketing', 5);
        counts.put('Internal', 3);
        counts.put('Confidential', 2);

        Test.startTest();
        String json = AIEmailExclusionService.toExclusionSummaryJson(counts);
        Test.stopTest();

        Assert.isTrue(json.contains('Marketing'), 'JSON should contain Marketing');
        Assert.isTrue(json.contains('Internal'), 'JSON should contain Internal');
        Assert.isTrue(json.contains('Confidential'), 'JSON should contain Confidential');
    }

    @isTest
    static void testToExclusionSummaryText() {
        Map<String, Integer> counts = new Map<String, Integer>();
        counts.put('Marketing', 5);
        counts.put('Internal', 3);
        counts.put('Confidential', 2);

        Test.startTest();
        String text = AIEmailExclusionService.toExclusionSummaryText(counts);
        Test.stopTest();

        Assert.isTrue(text.contains('Marketing: 5'), 'Text should contain Marketing count');
        Assert.isTrue(text.contains('Internal: 3'), 'Text should contain Internal count');
        Assert.isTrue(text.contains('Confidential: 2'), 'Text should contain Confidential count');
    }

    @isTest
    static void testToExclusionSummaryText_ZeroCounts() {
        Map<String, Integer> counts = new Map<String, Integer>();
        counts.put('Marketing', 0);
        counts.put('Internal', 0);
        counts.put('Confidential', 5);

        Test.startTest();
        String text = AIEmailExclusionService.toExclusionSummaryText(counts);
        Test.stopTest();

        Assert.isFalse(text.contains('Marketing'), 'Text should not contain Marketing with 0 count');
        Assert.isFalse(text.contains('Internal'), 'Text should not contain Internal with 0 count');
        Assert.isTrue(text.contains('Confidential: 5'), 'Text should contain Confidential count');
    }

    @isTest
    static void testToExclusionSummaryText_Empty() {
        Map<String, Integer> counts = new Map<String, Integer>();

        Test.startTest();
        String text = AIEmailExclusionService.toExclusionSummaryText(counts);
        Test.stopTest();

        Assert.areEqual('', text, 'Text should be empty for empty counts');
    }

    @isTest
    static void testToExclusionSummaryText_Null() {
        Test.startTest();
        String text = AIEmailExclusionService.toExclusionSummaryText(null);
        Test.stopTest();

        Assert.areEqual('', text, 'Text should be empty for null counts');
    }

    @isTest
    static void testMarketingDomains_SendGrid() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'sender@sendgrid.net');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testMarketingDomains_HubSpot() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'sender@hubspot.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testInternalDomains_UserDomain() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@testdomain.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        // Should not be excluded because testdomain.com is not in internal domains
        Assert.areEqual(false, result.excluded, 'Should not be excluded');
    }

    @isTest
    static void testExclusionPriority_MarketingFirst() {
        AIEmailExclusionService.clearCache();
        
        // Email that matches both marketing and confidential
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', '[CONFIDENTIAL] Newsletter');
        email.put('fromAddress', 'newsletter@example.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        // Marketing check comes first, so it should be excluded as Marketing
        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category (checked first)');
    }

    @isTest
    static void testExclusionPriority_ConfidentialSecond() {
        AIEmailExclusionService.clearCache();
        
        // Email that matches both confidential and internal
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', '[CONFIDENTIAL] Internal Email');
        email.put('fromAddress', 'user@mycompany.com');
        email.put('sensitivity', 'private');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        // Confidential check comes before Internal, so it should be excluded as Confidential
        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Confidential', result.category, 'Should be Confidential category (checked second)');
    }

    @isTest
    static void testGmailLabels_CategoryUpdates() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('labelIds', new List<String>{'CATEGORY_UPDATES'});

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'GMAIL_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
    }

    @isTest
    static void testConfidentialBodyPreview_Variations() {
        AIEmailExclusionService.clearCache();
        
        List<String> variations = new List<String>{
            'Classified as Private - content',
            'Classified as Internal - content',
            'Classified as Restricted - content',
            'Classified as Highly Confidential - content'
        };

        for (String bodyPreview : variations) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('subject', 'Test Email');
            email.put('bodyPreview', bodyPreview);

            AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
            Assert.areEqual(true, result.excluded, 'Should be excluded for: ' + bodyPreview);
            Assert.areEqual('Confidential', result.category, 'Should be Confidential category');
        }
    }

    @isTest
    static void testConfidentialSubject_Variations() {
        AIEmailExclusionService.clearCache();
        
        List<String> variations = new List<String>{
            '[CONFIDENTIAL] Test',
            '[PRIVATE] Test',
            '[INTERNAL ONLY] Test',
            '[RESTRICTED] Test'
        };

        for (String subject : variations) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('subject', subject);

            AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
            Assert.areEqual(true, result.excluded, 'Should be excluded for: ' + subject);
            Assert.areEqual('Confidential', result.category, 'Should be Confidential category');
        }
    }

    @isTest
    static void testMarketingSenderPatterns() {
        AIEmailExclusionService.clearCache();
        
        List<String> patterns = new List<String>{
            'noreply@example.com',
            'no-reply@example.com',
            'newsletter@example.com',
            'marketing@example.com',
            'promo@example.com'
        };

        for (String fromAddress : patterns) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('subject', 'Test Email');
            email.put('fromAddress', fromAddress);

            AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
            Assert.areEqual(true, result.excluded, 'Should be excluded for: ' + fromAddress);
            Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
        }
    }

    @isTest
    static void testExchangeCategories_CaseInsensitive() {
        AIEmailExclusionService.clearCache();
        
        List<String> categories = new List<String>{
            'PROMOTION',
            'Promotion',
            'promotion',
            'MARKETING',
            'Marketing',
            'NEWSLETTER',
            'Newsletter',
            'SOCIAL',
            'Social'
        };

        for (String category : categories) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('subject', 'Test Email');
            email.put('categories', new List<String>{category});

            AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
            Assert.areEqual(true, result.excluded, 'Should be excluded for: ' + category);
            Assert.areEqual('Marketing', result.category, 'Should be Marketing category');
        }
    }

    @isTest
    static void testSensitivity_CaseInsensitive() {
        AIEmailExclusionService.clearCache();
        
        List<String> sensitivities = new List<String>{
            'PRIVATE',
            'Private',
            'private',
            'CONFIDENTIAL',
            'Confidential',
            'PERSONAL',
            'Personal'
        };

        for (String sensitivity : sensitivities) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('subject', 'Test Email');
            email.put('sensitivity', sensitivity);

            AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
            Assert.areEqual(true, result.excluded, 'Should be excluded for: ' + sensitivity);
            Assert.areEqual('Confidential', result.category, 'Should be Confidential category');
        }
    }

    @isTest
    static void testExtractDomain_ValidEmail() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@EXAMPLE.COM');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        // Domain should be extracted and lowercased
        Assert.areEqual(false, result.excluded, 'Should not be excluded');
    }

    @isTest
    static void testExtractDomain_InvalidEmail() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'invalid-email');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(false, result.excluded, 'Should not be excluded for invalid email');
    }

    @isTest
    static void testLoadSettings_NoSettings() {
        AIEmailExclusionService.clearCache();
        
        // Delete all settings
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'noreply@example.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        // Should use default settings (all exclusions enabled)
        Assert.areEqual(true, result.excluded, 'Should be excluded with default settings');
    }

    @isTest
    static void testBulkEmails() {
        AIEmailExclusionService.clearCache();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        // Create 200 emails
        for (Integer i = 0; i < 200; i++) {
            Map<String, Object> email = new Map<String, Object>();
            email.put('subject', 'Email ' + i);
            if (Math.mod(i, 2) == 0) {
                email.put('fromAddress', 'user' + i + '@mycompany.com'); // Internal
            } else {
                email.put('fromAddress', 'user' + i + '@external.com'); // External
            }
            emails.add(email);
        }

        Test.startTest();
        AIEmailExclusionService.BatchExclusionResult result = AIEmailExclusionService.filterBatch(
            emails,
            'MICROSOFT_EMAIL',
            'test@mycompany.com'
        );
        Test.stopTest();

        Assert.areEqual(100, result.includedEmails.size(), 'Should have 100 included emails');
        Assert.areEqual(100, result.excludedEmails.size(), 'Should have 100 excluded emails');
        Assert.areEqual(100, result.exclusionCounts.get('Internal'), 'Should have 100 internal exclusions');
    }

    @isTest
    static void testCheckExclusion_PublicDomainGmail() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@gmail.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Public Domains', result.category, 'Should be Public Domains category');
        Assert.isTrue(result.reason.contains('gmail.com'), 'Reason should mention gmail.com');
    }

    @isTest
    static void testCheckExclusion_PublicDomainYahoo() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@yahoo.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Public Domains', result.category, 'Should be Public Domains category');
    }

    @isTest
    static void testCheckExclusion_PublicDomainOutlook() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@outlook.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Public Domains', result.category, 'Should be Public Domains category');
    }

    @isTest
    static void testCheckExclusion_PublicDomainHotmail() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@hotmail.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Public Domains', result.category, 'Should be Public Domains category');
    }

    @isTest
    static void testCheckExclusion_PublicDomainIcloud() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@icloud.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Public Domains', result.category, 'Should be Public Domains category');
    }

    @isTest
    static void testCheckExclusion_PublicDomainDisabled() {
        AIEmailExclusionService.clearCache();
        
        // Create settings with Public Domain exclusion disabled
        AI_Workspace_Sync_Settings__c testSettings = new AI_Workspace_Sync_Settings__c(
            Exclude_Marketing__c = true,
            Exclude_Confidential__c = true,
            Exclude_Internal__c = true,
            Exclude_Public_Domains__c = false
        );
        AIEmailExclusionService.setCachedSettings(testSettings);
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@gmail.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(false, result.excluded, 'Should not be excluded when public domain filter is disabled');
    }

    @isTest
    static void testCheckExclusion_NonPublicDomain() {
        AIEmailExclusionService.clearCache();
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@company.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        Assert.areEqual(false, result.excluded, 'Should not be excluded for non-public domain');
    }

    @isTest
    static void testFilterBatch_PublicDomains() {
        AIEmailExclusionService.clearCache();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        // Public domain email (Gmail)
        Map<String, Object> email1 = new Map<String, Object>();
        email1.put('subject', 'Gmail Email');
        email1.put('fromAddress', 'user@gmail.com');
        emails.add(email1);
        
        // Public domain email (Yahoo)
        Map<String, Object> email2 = new Map<String, Object>();
        email2.put('subject', 'Yahoo Email');
        email2.put('fromAddress', 'user@yahoo.com');
        emails.add(email2);
        
        // Company domain email
        Map<String, Object> email3 = new Map<String, Object>();
        email3.put('subject', 'Company Email');
        email3.put('fromAddress', 'user@company.com');
        emails.add(email3);

        Test.startTest();
        AIEmailExclusionService.BatchExclusionResult result = AIEmailExclusionService.filterBatch(
            emails,
            'MICROSOFT_EMAIL',
            'test@company.com'
        );
        Test.stopTest();

        Assert.areEqual(3, result.excludedEmails.size(), 'Should have 3 excluded emails');
        Assert.areEqual(2, result.exclusionCounts.get('Public Domains'), 'Should have 2 public domain exclusions');
    }

    @isTest
    static void testExclusionPriority_PublicDomainLast() {
        AIEmailExclusionService.clearCache();
        
        // Email from public domain that also matches marketing pattern
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Newsletter');
        email.put('fromAddress', 'newsletter@gmail.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        // Marketing check comes first, so it should be excluded as Marketing
        Assert.areEqual(true, result.excluded, 'Should be excluded');
        Assert.areEqual('Marketing', result.category, 'Should be Marketing category (checked before public domains)');
    }

    @isTest
    static void testFilterBatch_MixedWithPublicDomains() {
        AIEmailExclusionService.clearCache();
        
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        // Marketing email
        Map<String, Object> email1 = new Map<String, Object>();
        email1.put('subject', 'Marketing Email');
        email1.put('fromAddress', 'noreply@example.com');
        emails.add(email1);
        
        // Public domain email
        Map<String, Object> email2 = new Map<String, Object>();
        email2.put('subject', 'Gmail Email');
        email2.put('fromAddress', 'user@gmail.com');
        emails.add(email2);
        
        // Internal email
        Map<String, Object> email3 = new Map<String, Object>();
        email3.put('subject', 'Internal Email');
        email3.put('fromAddress', 'user@mycompany.com');
        emails.add(email3);
        
        // Normal email
        Map<String, Object> email4 = new Map<String, Object>();
        email4.put('subject', 'Normal Email');
        email4.put('fromAddress', 'user@external.com');
        emails.add(email4);

        Test.startTest();
        AIEmailExclusionService.BatchExclusionResult result = AIEmailExclusionService.filterBatch(
            emails,
            'MICROSOFT_EMAIL',
            'test@mycompany.com'
        );
        Test.stopTest();

        Assert.areEqual(1, result.includedEmails.size(), 'Should have 1 included email');
        Assert.areEqual(3, result.excludedEmails.size(), 'Should have 3 excluded emails');
        Assert.areEqual(1, result.exclusionCounts.get('Marketing'), 'Should have 1 marketing exclusion');
        Assert.areEqual(1, result.exclusionCounts.get('Public Domains'), 'Should have 1 public domain exclusion');
        Assert.areEqual(1, result.exclusionCounts.get('Internal'), 'Should have 1 internal exclusion');
    }

    @isTest
    static void testLoadSettings_DefaultPublicDomainExclusion() {
        AIEmailExclusionService.clearCache();
        
        // Delete all settings to test defaults
        delete [SELECT Id FROM AI_Workspace_Sync_Settings__c];
        
        Map<String, Object> email = new Map<String, Object>();
        email.put('subject', 'Test Email');
        email.put('fromAddress', 'user@gmail.com');

        Test.startTest();
        AIEmailExclusionService.ExclusionResult result = AIEmailExclusionService.checkExclusion(email, 'MICROSOFT_EMAIL');
        Test.stopTest();

        // Should use default settings (public domain exclusion enabled by default)
        Assert.areEqual(true, result.excluded, 'Should be excluded with default settings');
        Assert.areEqual('Public Domains', result.category, 'Should be Public Domains category');
    }
}