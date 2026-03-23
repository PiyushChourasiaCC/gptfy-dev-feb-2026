/**
 * Test class for AIWorkspaceFilterService
 * 
 * Tests filtering of emails, calendar events, and tasks based on:
 * - Excluded domains
 * - Excluded labels/categories
 * 
 * @author GPTfy
 * @date 2026-03-09
 * @Jira V2-7889
 */
@isTest
private class AIWorkspaceFilterServiceTest {
    
    @isTest
    static void testFilterByExcludedDomains_Email() {
        List<Map<String, Object>> emails = createTestEmails();
        String excludedDomains = 'example.com,test.org';
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            emails, excludedDomains, null, 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(3, result.totalCount, 'Should process 3 emails');
        Assert.areEqual(1, result.includedCount, 'Should include 1 email');
        Assert.areEqual(2, result.excludedCount, 'Should exclude 2 emails');
        Assert.areEqual(2, result.exclusionReasons.get('domain'), 'Should exclude 2 by domain');
    }
    
    @isTest
    static void testFilterByExcludedLabels_Outlook() {
        List<Map<String, Object>> emails = createTestEmailsWithCategories();
        String excludedLabels = 'marketing,confidential';
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            emails, null, excludedLabels, 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(3, result.totalCount, 'Should process 3 emails');
        Assert.areEqual(1, result.includedCount, 'Should include 1 email');
        Assert.areEqual(2, result.excludedCount, 'Should exclude 2 emails');
        Assert.areEqual(2, result.exclusionReasons.get('label'), 'Should exclude 2 by label');
    }
    
    @isTest
    static void testFilterByExcludedLabels_Gmail() {
        List<Map<String, Object>> emails = createTestEmailsWithLabelIds();
        String excludedLabels = 'label_marketing,label_confidential';
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            emails, null, excludedLabels, 'Email', 'Gmail'
        );
        Test.stopTest();
        
        Assert.areEqual(3, result.totalCount, 'Should process 3 emails');
        Assert.areEqual(1, result.includedCount, 'Should include 1 email');
        Assert.areEqual(2, result.excludedCount, 'Should exclude 2 emails');
    }
    
    @isTest
    static void testFilterByBothDomainsAndLabels() {
        List<Map<String, Object>> emails = createTestEmailsWithCategories();
        String excludedDomains = 'example.com';
        String excludedLabels = 'marketing';
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            emails, excludedDomains, excludedLabels, 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.isTrue(result.excludedCount > 0, 'Should exclude some emails');
        Assert.isTrue(result.includedCount >= 0, 'Should include some or no emails');
    }
    
    @isTest
    static void testFilterByExcludedDomains_CalendarEvents() {
        List<Map<String, Object>> events = createTestCalendarEvents();
        String excludedDomains = 'example.com';
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            events, excludedDomains, null, 'Calendar', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(2, result.totalCount, 'Should process 2 events');
        Assert.isTrue(result.excludedCount >= 1, 'Should exclude at least 1 event');
    }
    
    @isTest
    static void testFilterByExcludedDomains_NoDomains() {
        List<Map<String, Object>> emails = createTestEmails();
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            emails, null, null, 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(3, result.includedCount, 'Should include all emails when no exclusions');
        Assert.areEqual(0, result.excludedCount, 'Should exclude no emails');
    }
    
    @isTest
    static void testFilterByExcludedDomains_EmptyString() {
        List<Map<String, Object>> emails = createTestEmails();
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            emails, '', '', 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(3, result.includedCount, 'Should include all emails when exclusions are empty');
        Assert.areEqual(0, result.excludedCount, 'Should exclude no emails');
    }
    
    @isTest
    static void testFilterByExcludedDomains_CaseInsensitive() {
        List<Map<String, Object>> emails = createTestEmails();
        String excludedDomains = 'EXAMPLE.COM,TEST.ORG';
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            emails, excludedDomains, null, 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(2, result.excludedCount, 'Should exclude emails case-insensitively');
    }
    
    @isTest
    static void testFilterByExcludedDomains_WithSpaces() {
        List<Map<String, Object>> emails = createTestEmails();
        String excludedDomains = ' example.com , test.org ';
        
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            emails, excludedDomains, null, 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(2, result.excludedCount, 'Should handle spaces in domain list');
    }
    
    @isTest
    static void testFilterByExcludedDomains_EmptyList() {
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            new List<Map<String, Object>>(), 'example.com', null, 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(0, result.totalCount, 'Empty list should return 0 count');
    }
    
    @isTest
    static void testFilterByExcludedDomains_NullList() {
        Test.startTest();
        AIWorkspaceFilterService.FilterResult result = AIWorkspaceFilterService.applyAllFilters(
            null, 'example.com', null, 'Email', 'Outlook'
        );
        Test.stopTest();
        
        Assert.areEqual(0, result.totalCount, 'Null list should return 0 count');
    }
    
    @isTest
    static void testFilterByExcludedDomains_OnlyMethod() {
        List<Map<String, Object>> emails = createTestEmails();
        
        Test.startTest();
        List<Map<String, Object>> filtered = AIWorkspaceFilterService.filterByExcludedDomains(
            emails, 'example.com', 'Email'
        );
        Test.stopTest();
        
        Assert.isTrue(filtered.size() < emails.size(), 'Should filter some emails');
    }
    
    @isTest
    static void testFilterByExcludedLabels_OnlyMethod() {
        List<Map<String, Object>> emails = createTestEmailsWithCategories();
        
        Test.startTest();
        List<Map<String, Object>> filtered = AIWorkspaceFilterService.filterByExcludedLabels(
            emails, 'marketing', 'Outlook'
        );
        Test.stopTest();
        
        Assert.isTrue(filtered.size() < emails.size(), 'Should filter some emails');
    }
    
    private static List<Map<String, Object>> createTestEmails() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'id' => 'email1',
            'subject' => 'Test Email 1',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@example.com'}
            },
            'toRecipients' => new List<Object>()
        };
        
        Map<String, Object> email2 = new Map<String, Object>{
            'id' => 'email2',
            'subject' => 'Test Email 2',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@test.org'}
            },
            'toRecipients' => new List<Object>()
        };
        
        Map<String, Object> email3 = new Map<String, Object>{
            'id' => 'email3',
            'subject' => 'Test Email 3',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@company.com'}
            },
            'toRecipients' => new List<Object>()
        };
        
        emails.add(email1);
        emails.add(email2);
        emails.add(email3);
        
        return emails;
    }
    
    private static List<Map<String, Object>> createTestEmailsWithCategories() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'id' => 'email1',
            'subject' => 'Marketing Email',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@company.com'}
            },
            'categories' => new List<Object>{'Marketing'}
        };
        
        Map<String, Object> email2 = new Map<String, Object>{
            'id' => 'email2',
            'subject' => 'Confidential Email',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@company.com'}
            },
            'categories' => new List<Object>{'Confidential'}
        };
        
        Map<String, Object> email3 = new Map<String, Object>{
            'id' => 'email3',
            'subject' => 'Normal Email',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@company.com'}
            },
            'categories' => new List<Object>{'Work'}
        };
        
        emails.add(email1);
        emails.add(email2);
        emails.add(email3);
        
        return emails;
    }
    
    private static List<Map<String, Object>> createTestEmailsWithLabelIds() {
        List<Map<String, Object>> emails = new List<Map<String, Object>>();
        
        Map<String, Object> email1 = new Map<String, Object>{
            'id' => 'email1',
            'subject' => 'Marketing Email',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@company.com'}
            },
            'labelIds' => new List<Object>{'LABEL_MARKETING'}
        };
        
        Map<String, Object> email2 = new Map<String, Object>{
            'id' => 'email2',
            'subject' => 'Confidential Email',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@company.com'}
            },
            'labelIds' => new List<Object>{'LABEL_CONFIDENTIAL'}
        };
        
        Map<String, Object> email3 = new Map<String, Object>{
            'id' => 'email3',
            'subject' => 'Normal Email',
            'from' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'user@company.com'}
            },
            'labelIds' => new List<Object>{'INBOX'}
        };
        
        emails.add(email1);
        emails.add(email2);
        emails.add(email3);
        
        return emails;
    }
    
    private static List<Map<String, Object>> createTestCalendarEvents() {
        List<Map<String, Object>> events = new List<Map<String, Object>>();
        
        Map<String, Object> event1 = new Map<String, Object>{
            'id' => 'event1',
            'subject' => 'Meeting 1',
            'organizer' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'organizer@example.com'}
            },
            'attendees' => new List<Object>()
        };
        
        Map<String, Object> event2 = new Map<String, Object>{
            'id' => 'event2',
            'subject' => 'Meeting 2',
            'organizer' => new Map<String, Object>{
                'emailAddress' => new Map<String, Object>{'address' => 'organizer@company.com'}
            },
            'attendees' => new List<Object>()
        };
        
        events.add(event1);
        events.add(event2);
        
        return events;
    }
}
