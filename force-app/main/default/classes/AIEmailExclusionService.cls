/**
 * EmailExclusionService - Provider-aware email filtering service
 * Determines which emails should be excluded from auto-sync based on:
 * - Marketing/promotional content
 * - Confidential/private markers
 * - Internal company emails
 *
 * Supports both Exchange (categories) and Gmail (labels) classification.
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIEmailExclusionService {

    /**
     * Result of exclusion check for a single email
     */
    public class ExclusionResult {
        public Boolean excluded { get; set; }
        public String reason { get; set; }
        public String category { get; set; } // 'Marketing', 'Confidential', 'Internal', 'None'

        public ExclusionResult() {
            this.excluded = false;
            this.reason = null;
            this.category = 'None';
        }

        public ExclusionResult(Boolean excluded, String reason, String category) {
            this.excluded = excluded;
            this.reason = reason;
            this.category = category;
        }
    }

    /**
     * Batch result containing exclusion summary
     */
    public class BatchExclusionResult {
        public List<Map<String, Object>> includedEmails { get; set; }
        public List<Map<String, Object>> excludedEmails { get; set; }
        public Map<String, Integer> exclusionCounts { get; set; } // Category -> count

        public BatchExclusionResult() {
            this.includedEmails = new List<Map<String, Object>>();
            this.excludedEmails = new List<Map<String, Object>>();
            this.exclusionCounts = new Map<String, Integer>{
                'Marketing' => 0,
                'Confidential' => 0,
                'Internal' => 0,
                'Public Domains' => 0
            };
        }
    }

    // Settings cache
    private static AI_Workspace_Sync_Settings__c settings;
    private static Set<String> internalDomains;

    /**
     * Clear cached settings (for testing purposes)
     */
    @TestVisible
    private static void clearCache() {
        settings = null;
        internalDomains = null;
    }

    /**
     * Set cached settings (for testing purposes)
     */
    @TestVisible
    private static void setCachedSettings(AI_Workspace_Sync_Settings__c testSettings) {
        settings = testSettings;
    }

    /**
     * Filter a batch of emails, returning only those that pass all exclusion checks
     * @param emails List of email data from provider
     * @param providerType 'MICROSOFT_EMAIL' or 'GMAIL_EMAIL'
     * @param userEmail The user's email address (for internal domain detection)
     * @return BatchExclusionResult with included/excluded emails and summary
     */
    public static BatchExclusionResult filterBatch(
        List<Map<String, Object>> emails,
        String providerType,
        String userEmail
    ) {
        loadSettings();
        //loadInternalDomains(userEmail);

        BatchExclusionResult result = new BatchExclusionResult();

        for (Map<String, Object> email : emails) {
            ExclusionResult exclusion = checkExclusion(email, providerType);

            if (exclusion.excluded) {
                result.excludedEmails.add(email);
                Integer count = result.exclusionCounts.get(exclusion.category);
                result.exclusionCounts.put(exclusion.category, count + 1);
            } else {
                result.includedEmails.add(email);
            }
        }

        return result;
    }

    /**
     * Check if a single email should be excluded
     * @param emailData Email data from provider
     * @param providerType 'MICROSOFT_EMAIL' or 'GMAIL_EMAIL'
     * @return ExclusionResult with details
     */
    public static ExclusionResult checkExclusion(Map<String, Object> emailData, String providerType) {
        // loadSettings();

        // // Check Marketing exclusion
        // if (settings.Exclude_Marketing__c) {
        //     ExclusionResult marketingCheck = checkMarketingExclusion(emailData, providerType);
        //     if (marketingCheck.excluded) {
        //         return marketingCheck;
        //     }
        // }

        // // Check Confidential exclusion
        // if (settings.Exclude_Confidential__c) {
        //     ExclusionResult confidentialCheck = checkConfidentialExclusion(emailData, providerType);
        //     if (confidentialCheck.excluded) {
        //         return confidentialCheck;
        //     }
        // }

        // // Check Internal exclusion
        // if (settings.Exclude_Internal__c) {
        //     ExclusionResult internalCheck = checkInternalExclusion(emailData);
        //     if (internalCheck.excluded) {
        //         return internalCheck;
        //     }
        // }

        // // Check Public Domain exclusion
        // if (settings.Exclude_Public_Domains__c) {
        //     ExclusionResult publicDomainCheck = checkPublicDomainExclusion(emailData);
        //     if (publicDomainCheck.excluded) {
        //         return publicDomainCheck;
        //     }
        // }

        return new ExclusionResult();
    }

    /**
     * Check for marketing/promotional emails
     * Exchange: categories array contains 'Promotions' or email from known marketing domains
     * Gmail: labelIds contains 'CATEGORY_PROMOTIONS' or 'CATEGORY_SOCIAL'
     */
    private static ExclusionResult checkMarketingExclusion(Map<String, Object> emailData, String providerType) {
        if (providerType == 'MICROSOFT_EMAIL') {
            // Check Exchange categories (user-assigned categories like "Promotions", "Marketing")
            Object categoriesObj = emailData.get('categories');
            List<Object> categories = (List<Object>) categoriesObj;
            if (categories != null && !categories.isEmpty()) {
                for (Object cat : categories) {
                    String category = String.valueOf(cat).toLowerCase();
                    if (category.contains('promotion') || category.contains('marketing') ||
                        category.contains('newsletter') || category.contains('social')) {
                        return new ExclusionResult(true, 'Exchange category: ' + cat, 'Marketing');
                    }
                }
            }

            // Check inferenceClassification (Focused vs Other)
            String classification = (String) emailData.get('inferenceClassification');
            if (classification == 'other') {
                // 'Other' folder often contains promotional content, but let's be conservative
                // Only exclude if combined with other signals
            }
        } else if (providerType == 'GMAIL_EMAIL') {
            // Check Gmail labels
            List<Object> labelIds = (List<Object>) emailData.get('labelIds');
            if (labelIds != null) {
                for (Object label : labelIds) {
                    String labelStr = String.valueOf(label).toUpperCase();
                    if (labelStr == 'CATEGORY_PROMOTIONS' || labelStr == 'CATEGORY_SOCIAL' ||
                        labelStr == 'CATEGORY_UPDATES') {
                        return new ExclusionResult(true, 'Gmail label: ' + label, 'Marketing');
                    }
                }
            }
        }

        // Check common marketing indicators in sender domain
        String fromAddress = getFromAddress(emailData);
        if (String.isNotBlank(fromAddress)) {
            String domain = extractDomain(fromAddress);
            if (isMarketingDomain(domain)) {
                return new ExclusionResult(true, 'Marketing domain: ' + domain, 'Marketing');
            }

            // Check for noreply/marketing sender patterns
            String localPart = fromAddress.contains('@') ?
                fromAddress.substring(0, fromAddress.indexOf('@')).toLowerCase() : '';
            if (localPart.contains('noreply') || localPart.contains('no-reply') ||
                localPart.contains('newsletter') || localPart.contains('marketing') ||
                localPart.contains('promo') || localPart.contains('info@')) {
                return new ExclusionResult(true, 'Marketing sender pattern: ' + fromAddress, 'Marketing');
            }
        }

        return new ExclusionResult();
    }

    /**
     * Check for confidential/private emails
     * Exchange: sensitivity field = 'private' or 'confidential'
     * Gmail: Check subject/headers for confidentiality markers
     */
    private static ExclusionResult checkConfidentialExclusion(Map<String, Object> emailData, String providerType) {
        if (providerType == 'MICROSOFT_EMAIL') {
            // Check sensitivity field
            String sensitivity = (String) emailData.get('sensitivity');
            if (sensitivity != null) {
                sensitivity = sensitivity.toLowerCase();
                if (sensitivity == 'private' || sensitivity == 'confidential' ||
                    sensitivity == 'personal') {
                    return new ExclusionResult(true, 'Exchange sensitivity: ' + sensitivity, 'Confidential');
                }
            }

            // Check importance combined with certain flags
            String importance = (String) emailData.get('importance');
            Boolean isEncrypted = (Boolean) emailData.get('isEncrypted');
            if (isEncrypted == true) {
                return new ExclusionResult(true, 'Encrypted email', 'Confidential');
            }
        } else if (providerType == 'GMAIL_EMAIL') {
            // Gmail doesn't have built-in sensitivity, check headers if available
            List<Object> headers = (List<Object>) emailData.get('headers');
            if (headers != null) {
                for (Object headerObj : headers) {
                    Map<String, Object> header = (Map<String, Object>) headerObj;
                    String name = (String) header.get('name');
                    String value = (String) header.get('value');

                    if (name != null && name.toLowerCase() == 'sensitivity') {
                        if (value != null && (value.toLowerCase().contains('private') ||
                            value.toLowerCase().contains('confidential'))) {
                            return new ExclusionResult(true, 'Gmail header sensitivity: ' + value, 'Confidential');
                        }
                    }
                }
            }
        }

        // Check bodyPreview for Microsoft Information Protection (MIP) sensitivity labels
        // When MIP labels are applied, Microsoft injects "Classified as [Label]" at the start of bodyPreview
        String bodyPreview = (String) emailData.get('bodyPreview');
        if (String.isNotBlank(bodyPreview)) {
            String bodyPreviewLower = bodyPreview.toLowerCase();
            if (bodyPreviewLower.startsWith('classified as confidential') ||
                bodyPreviewLower.startsWith('classified as private') ||
                bodyPreviewLower.startsWith('classified as internal') ||
                bodyPreviewLower.startsWith('classified as restricted') ||
                bodyPreviewLower.startsWith('classified as highly confidential')) {
                return new ExclusionResult(true, 'Microsoft sensitivity label detected in body', 'Confidential');
            }
        }

        // Check subject line for explicit confidentiality markers (fallback for non-MIP scenarios)
        String subject = (String) emailData.get('subject');
        if (String.isNotBlank(subject)) {
            String subjectLower = subject.toLowerCase();
            // Check for bracketed markers like [CONFIDENTIAL] or [PRIVATE]
            if (subjectLower.contains('[confidential]') || subjectLower.contains('[private]') ||
                subjectLower.contains('[internal only]') || subjectLower.contains('[restricted]')) {
                return new ExclusionResult(true, 'Subject contains confidentiality marker', 'Confidential');
            }
        }

        return new ExclusionResult();
    }

    /**
     * Check for internal company emails.
     * An email is considered "internal" if the FROM address is from an internal domain.
     * Only checks the FROM address - TO/CC are NOT considered for internal exclusion.
     */
    private static ExclusionResult checkInternalExclusion(Map<String, Object> emailData) {
        // Check sender domain only - TO/CC are not considered
        String fromAddress = getFromAddress(emailData);
        String senderDomain = String.isNotBlank(fromAddress) ? extractDomain(fromAddress) : null;
        
        // If sender domain is in the internal domains list, exclude this email
        if (String.isNotBlank(senderDomain) && 
            internalDomains != null && 
            internalDomains.contains(senderDomain.toLowerCase())) {
            return new ExclusionResult(true, 'Internal email (FROM: ' + fromAddress + ')', 'Internal');
        }

        // Sender is not from internal domain - don't exclude
        return new ExclusionResult();
    }

    /**
     * Check for public domain emails (gmail.com, yahoo.com, etc.).
     * An email is excluded if the FROM address is from a public domain.
     * This prevents importing emails from personal/public email addresses when the setting is enabled.
     * Only checks the FROM address - TO/CC are NOT considered for public domain exclusion.
     */
    private static ExclusionResult checkPublicDomainExclusion(Map<String, Object> emailData) {
        // V2-7889: Public domain check disabled - method not available in AISyncSettingsService
        // Check sender domain only - TO/CC are not considered
        // String fromAddress = getFromAddress(emailData);
        // String senderDomain = String.isNotBlank(fromAddress) ? extractDomain(fromAddress) : null;
        // 
        // // If sender domain is a public domain, exclude this email
        // if (String.isNotBlank(senderDomain) && AISyncSettingsService.isPublicDomain(senderDomain)) {
        //     return new ExclusionResult(true, 'Public domain email (FROM: ' + fromAddress + ')', 'Public Domains');
        // }

        // Sender is not from a public domain - don't exclude
        return new ExclusionResult();
    }

    /**
     * Extract all recipient domains from email data (To, CC, BCC)
     */
    private static List<String> getRecipientDomains(Map<String, Object> emailData) {
        List<String> domains = new List<String>();

        // Microsoft Graph format: toRecipients, ccRecipients, bccRecipients arrays
        addRecipientsFromList(domains, (List<Object>) emailData.get('toRecipients'));
        addRecipientsFromList(domains, (List<Object>) emailData.get('ccRecipients'));
        addRecipientsFromList(domains, (List<Object>) emailData.get('bccRecipients'));

        // Gmail format: different structure - headers contain To, Cc, Bcc
        // Also check for flattened format
        String toAddress = (String) emailData.get('toAddress');
        if (String.isNotBlank(toAddress)) {
            // NO REGEX - split by comma and semicolon manually
            List<String> addresses = splitByCommaOrSemicolon(toAddress);
            for (String addr : addresses) {
                String domain = extractDomain(addr.trim());
                if (String.isNotBlank(domain)) {
                    domains.add(domain);
                }
            }
        }

        return domains;
    }

    /**
     * Helper to extract domains from Graph API recipient list
     */
    private static void addRecipientsFromList(List<String> domains, List<Object> recipients) {
        if (recipients == null) return;

        for (Object recipientObj : recipients) {
            Map<String, Object> recipient = (Map<String, Object>) recipientObj;
            Map<String, Object> emailAddr = (Map<String, Object>) recipient.get('emailAddress');
            if (emailAddr != null) {
                String address = (String) emailAddr.get('address');
                String domain = extractDomain(address);
                if (String.isNotBlank(domain)) {
                    domains.add(domain);
                }
            }
        }
    }

    /**
     * Load settings from Custom Metadata
     */
    private static void loadSettings() {
        // if (settings == null) {
        //     // Use getOrgDefaults() for org-level settings only
        //     settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            
        //     if (settings == null || settings.Id == null) {
        //         // Create default settings if not configured
        //         settings = new AI_Workspace_Sync_Settings__c();
        //         settings.Exclude_Marketing__c = true;
        //         settings.Exclude_Confidential__c = true;
        //         settings.Exclude_Internal__c = true;
        //         settings.Exclude_Public_Domains__c = true;
        //     }
        // }
    }

    /**
     * Load internal domains from settings and user's domain.
     * Only uses exact domain match - no TLD variations to avoid false positives.
     */
    private static void loadInternalDomains(String userEmail) {
        if (internalDomains == null) {
            internalDomains = new Set<String>();

            // Add user's exact domain only
            if (String.isNotBlank(userEmail)) {
                String userDomain = extractDomain(userEmail);
                if (String.isNotBlank(userDomain)) {
                    internalDomains.add(userDomain.toLowerCase());
                }
            }

            // Add configured internal domains (admins can add variations if needed)
            // NO REGEX - use simple split by comma
            // if (settings != null && String.isNotBlank(settings.Internal_Domains__c)) {
            //     List<String> configuredDomains = splitByComma(settings.Internal_Domains__c);
            //     for (String domain : configuredDomains) {
            //         if (String.isNotBlank(domain)) {
            //             internalDomains.add(domain.trim().toLowerCase());
            //         }
            //     }
            // }
        }
    }

    /**
     * Extract sender email address from email data
     */
    private static String getFromAddress(Map<String, Object> emailData) {
        // Try direct fromAddress field first
        Object fromAddr = emailData.get('fromAddress');
        if (fromAddr != null) {
            return String.valueOf(fromAddr).trim();
        }

        // Try nested from object (Graph API format)
        Map<String, Object> fromObj = (Map<String, Object>) emailData.get('from');
        if (fromObj != null) {
            Map<String, Object> emailAddr = (Map<String, Object>) fromObj.get('emailAddress');
            if (emailAddr != null) {
                return (String) emailAddr.get('address');
            }
        }

        return null;
    }

    /**
     * Extract domain from email address
     */
    private static String extractDomain(String email) {
        if (String.isBlank(email)) return null;
        Integer atIndex = email.indexOf('@');
        if (atIndex < 0 || atIndex == email.length() - 1) return null;
        return email.substring(atIndex + 1).toLowerCase();
    }

    /**
     * Check if domain is a known marketing/transactional email service
     */
    private static Boolean isMarketingDomain(String domain) {
        if (String.isBlank(domain)) return false;

        Set<String> marketingDomains = new Set<String>{
            // Email marketing platforms
            'mailchimp.com', 'sendgrid.net', 'sendgrid.com',
            'mailgun.org', 'mailgun.com', 'constantcontact.com',
            'hubspot.com', 'hubspotemail.net', 'marketo.com',
            'pardot.com', 'eloqua.com', 'responsys.net',
            'exacttarget.com', 'salesforce.com', 'sfmc.com',
            'klaviyo.com', 'drip.com', 'activecampaign.com',
            'convertkit.com', 'getresponse.com', 'aweber.com',
            'campaignmonitor.com', 'sendinblue.com', 'brevo.com',
            // Transactional email services
            'amazonses.com', 'postmarkapp.com', 'sparkpostmail.com',
            'mandrillapp.com', 'mailjet.com',
            // Newsletter platforms
            'substack.com', 'beehiiv.com', 'revue.co',
            // Social/notification services
            'facebookmail.com', 'linkedin.com', 'twitter.com',
            'notifications.google.com', 'e.]]]', 'noreply.github.com'
        };

        return marketingDomains.contains(domain.toLowerCase());
    }

    /**
     * Convert exclusion counts to JSON for storage
     */
    public static String toExclusionSummaryJson(Map<String, Integer> exclusionCounts) {
        return JSON.serialize(exclusionCounts);
    }
    
    /**
     * Convert exclusion counts to a human-readable summary
     * Example: "Marketing: 5, Internal: 3, Confidential: 2"
     */
    public static String toExclusionSummaryText(Map<String, Integer> exclusionCounts) {
        if (exclusionCounts == null || exclusionCounts.isEmpty()) {
            return '';
        }
        
        List<String> summaryParts = new List<String>();
        
        // Order matters for readability - show in priority order
        List<String> orderedCategories = new List<String>{
            'Marketing',
            'Internal',
            'Confidential',
            'Public Domains'
        };
        
        for (String category : orderedCategories) {
            if (exclusionCounts.containsKey(category) && exclusionCounts.get(category) > 0) {
                summaryParts.add(category + ': ' + exclusionCounts.get(category));
            }
        }
        
        // Add any other categories not in the ordered list
        for (String category : exclusionCounts.keySet()) {
            if (!orderedCategories.contains(category) && exclusionCounts.get(category) > 0) {
                summaryParts.add(category + ': ' + exclusionCounts.get(category));
            }
        }
        
        return String.join(summaryParts, ', ');
    }

    /**
     * Split string by comma or semicolon without regex
     * NO REGEX - avoids "regex too complicated" errors
     */
    private static List<String> splitByCommaOrSemicolon(String input) {
        List<String> parts = new List<String>();
        if (String.isBlank(input)) return parts;

        String currentPart = '';
        for (Integer i = 0; i < input.length(); i++) {
            String ch = input.substring(i, i + 1);
            if (ch == ',' || ch == ';') {
                if (String.isNotBlank(currentPart)) {
                    parts.add(currentPart.trim());
                }
                currentPart = '';
            } else {
                currentPart += ch;
            }
        }

        // Add the last part
        if (String.isNotBlank(currentPart)) {
            parts.add(currentPart.trim());
        }

        return parts;
    }

    /**
     * Split string by comma without regex
     * NO REGEX - avoids "regex too complicated" errors
     */
    private static List<String> splitByComma(String input) {
        List<String> parts = new List<String>();
        if (String.isBlank(input)) return parts;

        String currentPart = '';
        for (Integer i = 0; i < input.length(); i++) {
            String ch = input.substring(i, i + 1);
            if (ch == ',') {
                if (String.isNotBlank(currentPart)) {
                    parts.add(currentPart.trim());
                }
                currentPart = '';
            } else {
                currentPart += ch;
            }
        }

        // Add the last part
        if (String.isNotBlank(currentPart)) {
            parts.add(currentPart.trim());
        }

        return parts;
    }
}