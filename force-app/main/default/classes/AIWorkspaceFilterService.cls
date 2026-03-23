/**
 * AIWorkspaceFilterService - Centralized filtering service for workspace sync
 * 
 * This service filters emails, calendar events, and tasks based on:
 * 1. Excluded domains - checks ONLY:
 *    - From address for emails
 *    - Organizer email for calendar events
 *    - From address for tasks
 * 2. Excluded labels/categories (Gmail labels or Outlook categories)
 * 
 * Note: Recipients (to/cc/bcc) and attendees are NOT checked for domain exclusion
 * 
 * Replaces the old exclusion logic that used separate boolean fields
 * (Exclude_Internal__c, Exclude_Marketing__c, etc.)
 * 
 * @author GPTfy
 * @date 2026-03-09
 * @Jira V2-7889
 */
public with sharing class AIWorkspaceFilterService {
    
    /**
     * Result class for filter operations
     */
    public class FilterResult {
        public List<Map<String, Object>> includedRecords;
        public List<Map<String, Object>> excludedRecords;
        public Integer totalCount;
        public Integer includedCount;
        public Integer excludedCount;
        public Map<String, Integer> exclusionReasons;
        
        public FilterResult() {
            this.includedRecords = new List<Map<String, Object>>();
            this.excludedRecords = new List<Map<String, Object>>();
            this.totalCount = 0;
            this.includedCount = 0;
            this.excludedCount = 0;
            this.exclusionReasons = new Map<String, Integer>{
                'domain' => 0,
                'label' => 0
            };
        }
    }
    
    /**
     * Apply all filters (domains + labels) to a list of records
     * 
     * @param records List of email/event/task records from API
     * @param excludedDomains Comma-separated list of domains to exclude
     * @param excludedLabels Comma-separated list of labels/categories to exclude
     * @param recordType Type of record: 'Email', 'Calendar', or 'Task'
     * @param provider Provider type: 'Outlook' or 'Gmail'
     * @return FilterResult with included/excluded records and counts
     */
    public static FilterResult applyAllFilters(
        List<Map<String, Object>> records,
        String excludedDomains,
        String excludedLabels,
        String recordType,
        String provider
    ) {
        FilterResult result = new FilterResult();
        
        if (records == null || records.isEmpty()) {
            return result;
        }
        
        result.totalCount = records.size();
        
        Set<String> excludedDomainSet = parseCommaSeparatedList(excludedDomains);
        Set<String> excludedLabelSet = parseCommaSeparatedList(excludedLabels);
        
        for (Map<String, Object> record : records) {
            Boolean excluded = false;
            String exclusionReason = null;
            
            if (!excludedDomainSet.isEmpty()) {
                if (isExcludedByDomain(record, excludedDomainSet, recordType)) {
                    excluded = true;
                    exclusionReason = 'domain';
                }
            }
            
            if (!excluded && !excludedLabelSet.isEmpty()) {
                if (isExcludedByLabel(record, excludedLabelSet, provider)) {
                    excluded = true;
                    exclusionReason = 'label';
                }
            }
            
            if (excluded) {
                result.excludedRecords.add(record);
                result.excludedCount++;
                if (exclusionReason != null) {
                    Integer count = result.exclusionReasons.get(exclusionReason);
                    result.exclusionReasons.put(exclusionReason, count + 1);
                }
            } else {
                result.includedRecords.add(record);
                result.includedCount++;
            }
        }
        
        return result;
    }
    
    /**
     * Check if a record should be excluded based on domain
     */
    private static Boolean isExcludedByDomain(
        Map<String, Object> record,
        Set<String> excludedDomains,
        String recordType
    ) {
        Set<String> emailAddresses = extractEmailAddresses(record, recordType);
        
        for (String email : emailAddresses) {
            String domain = extractDomain(email);
            if (String.isNotBlank(domain) && excludedDomains.contains(domain.toLowerCase())) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Check if a record should be excluded based on label/category
     * V2-7889: Supports both provider formats (MICROSOFT_EMAIL/Outlook, Gmail/GOOGLE_CALENDAR)
     */
    private static Boolean isExcludedByLabel(
        Map<String, Object> record,
        Set<String> excludedLabels,
        String provider
    ) {
        // Normalize provider name to handle different formats
        Boolean isMicrosoft = provider == 'Outlook' || 
                             provider == 'MICROSOFT_EMAIL' || 
                             provider == 'MICROSOFT_CALENDAR' ||
                             provider == 'MICROSOFT_TASKS';
        Boolean isGoogle = provider == 'Gmail' || 
                          provider == 'GMAIL_EMAIL' ||
                          provider == 'GOOGLE_CALENDAR' || 
                          provider == 'GOOGLE_TASKS';
        
        if (isMicrosoft) {
            List<Object> categories = (List<Object>) record.get('categories');
            if (categories != null) {
                for (Object category : categories) {
                    String categoryStr = String.valueOf(category).toLowerCase().trim();
                    if (excludedLabels.contains(categoryStr)) {
                        return true;
                    }
                }
            }
        } else if (isGoogle) {
            List<Object> labelIds = (List<Object>) record.get('labelIds');
            if (labelIds != null) {
                for (Object labelId : labelIds) {
                    String labelStr = String.valueOf(labelId).toLowerCase().trim();
                    if (excludedLabels.contains(labelStr)) {
                        return true;
                    }
                }
            }
        }
        
        return false;
    }
    
    /**
     * Extract all email addresses from a record based on type
     * V2-7889: Only check From address (emails/tasks) and Organizer (calendar events)
     */
    private static Set<String> extractEmailAddresses(Map<String, Object> record, String recordType) {
        Set<String> emails = new Set<String>();
        
        if (recordType == 'Email') {
            addEmailFromField(emails, record, 'from');
        } else if (recordType == 'Calendar') {
            addEmailFromField(emails, record, 'organizer');
        } else if (recordType == 'Task') {
            addEmailFromField(emails, record, 'from');
        }
        
        return emails;
    }
    
    /**
     * Add email from a single field (from, organizer)
     */
    private static void addEmailFromField(Set<String> emails, Map<String, Object> record, String fieldName) {
        Object fieldValue = record.get(fieldName);
        if (fieldValue != null) {
            Map<String, Object> emailObj = (Map<String, Object>) fieldValue;
            Map<String, Object> emailAddress = (Map<String, Object>) emailObj.get('emailAddress');
            if (emailAddress != null) {
                String email = (String) emailAddress.get('address');
                if (String.isNotBlank(email)) {
                    emails.add(email.toLowerCase().trim());
                }
            }
        }
    }
    
    /**
     * Add emails from recipients array (toRecipients, ccRecipients, bccRecipients)
     */
    private static void addEmailsFromRecipients(Set<String> emails, Map<String, Object> record, String fieldName) {
        List<Object> recipients = (List<Object>) record.get(fieldName);
        if (recipients != null) {
            for (Object recipient : recipients) {
                Map<String, Object> recipientObj = (Map<String, Object>) recipient;
                Map<String, Object> emailAddress = (Map<String, Object>) recipientObj.get('emailAddress');
                if (emailAddress != null) {
                    String email = (String) emailAddress.get('address');
                    if (String.isNotBlank(email)) {
                        emails.add(email.toLowerCase().trim());
                    }
                }
            }
        }
    }
    
    /**
     * Add emails from attendees array (calendar events)
     */
    private static void addEmailsFromAttendees(Set<String> emails, Map<String, Object> record) {
        List<Object> attendees = (List<Object>) record.get('attendees');
        if (attendees != null) {
            for (Object attendee : attendees) {
                Map<String, Object> attendeeObj = (Map<String, Object>) attendee;
                Map<String, Object> emailAddress = (Map<String, Object>) attendeeObj.get('emailAddress');
                if (emailAddress != null) {
                    String email = (String) emailAddress.get('address');
                    if (String.isNotBlank(email)) {
                        emails.add(email.toLowerCase().trim());
                    }
                }
            }
        }
    }
    
    /**
     * Extract domain from email address
     */
    private static String extractDomain(String email) {
        if (String.isBlank(email)) {
            return null;
        }
        
        Integer atIndex = email.indexOf('@');
        if (atIndex > 0 && atIndex < email.length() - 1) {
            return email.substring(atIndex + 1);
        }
        
        return null;
    }
    
    /**
     * Parse comma-separated list into a set (case-insensitive, trimmed)
     */
    private static Set<String> parseCommaSeparatedList(String input) {
        Set<String> result = new Set<String>();
        
        if (String.isBlank(input)) {
            return result;
        }
        
        List<String> items = input.split(',');
        for (String item : items) {
            String trimmed = item.trim();
            if (String.isNotBlank(trimmed)) {
                result.add(trimmed.toLowerCase());
            }
        }
        
        return result;
    }
    
    /**
     * Filter records by excluded domains only
     */
    public static List<Map<String, Object>> filterByExcludedDomains(
        List<Map<String, Object>> records,
        String excludedDomains,
        String recordType
    ) {
        if (String.isBlank(excludedDomains)) {
            return records;
        }
        
        FilterResult result = applyAllFilters(records, excludedDomains, null, recordType, null);
        return result.includedRecords;
    }
    
    /**
     * Filter records by excluded labels only
     */
    public static List<Map<String, Object>> filterByExcludedLabels(
        List<Map<String, Object>> records,
        String excludedLabels,
        String provider
    ) {
        if (String.isBlank(excludedLabels)) {
            return records;
        }
        
        FilterResult result = applyAllFilters(records, null, excludedLabels, 'Email', provider);
        return result.includedRecords;
    }
}
