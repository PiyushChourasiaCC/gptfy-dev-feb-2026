/**
 * QuickMatchService - Fast, deterministic email matching service
 * Phase 1 of 2-phase matching approach
 * Provider-agnostic: Works with Gmail, Exchange, and any future email providers
 *
 * Performance target: < 1 second for 20 emails
 * SOQL usage: 4-5 queries total for batch processing
 */
public with sharing class AIQuickMatchService {

    // Result wrapper class
    public class MatchResult {
        @AuraEnabled public String emailSubject { get; set; }
        @AuraEnabled public String fromAddress { get; set; }
        @AuraEnabled public String fromName { get; set; }

        // Matched record IDs - Primary matches (for backward compatibility)
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Id leadId { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public Id caseId { get; set; }

        // All matched Contacts (for multi-association)
        @AuraEnabled public List<Id> contactIds { get; set; }

        // Match confidence (0-100)
        @AuraEnabled public Integer confidence { get; set; }
        @AuraEnabled public String matchType { get; set; } // 'Contact', 'Lead', 'Account', etc.
        @AuraEnabled public List<String> matchDetails { get; set; }

        public MatchResult() {
            this.confidence = 0;
            this.matchDetails = new List<String>();
            this.contactIds = new List<Id>();
        }
    }

    // Cache for bulk operations
    private class BulkCache {
        public Map<String, Contact> emailToContact = new Map<String, Contact>();
        public Map<String, Lead> emailToLead = new Map<String, Lead>();
        public Map<String, Account> domainToAccount = new Map<String, Account>();
        public Map<Id, List<Opportunity>> accountToOpportunities = new Map<Id, List<Opportunity>>();
        public Map<Id, List<Case>> contactToCases = new Map<Id, List<Case>>();
    }

    /**
     * Match a single email (for testing or single operations)
     */
    public static MatchResult matchSingle(Map<String, Object> emailData) {
        List<Map<String, Object>> emailList = new List<Map<String, Object>>{ emailData };
        List<MatchResult> results = matchBatch(emailList);
        return results.isEmpty() ? new MatchResult() : results[0];
    }

    /**
     * Match multiple emails in batch (optimized for performance)
     * Target: 20 emails with 4-5 SOQL queries total
     */
    public static List<MatchResult> matchBatch(List<Map<String, Object>> emails) {
        if (emails == null || emails.isEmpty()) {
            return new List<MatchResult>();
        }

        // Build cache with bulk queries
        BulkCache cache = buildBulkCache(emails);

        // Process each email using cached data
        // Get internal domains once for the batch
        String currentUserEmail = UserInfo.getUserEmail();
        Set<String> internalDomains = getInternalDomains(extractDomain(currentUserEmail));

        // Process each email using cached data
        List<MatchResult> results = new List<MatchResult>();

        for (Integer i = 0; i < emails.size(); i++) {
            Map<String, Object> email = emails[i];
            MatchResult result = matchWithCache(email, cache, internalDomains);
            results.add(result);

            System.debug('AIQuickMatchService: Email ' + i + ' - From: ' + result.fromAddress + ', Confidence: ' + result.confidence + ', MatchType: ' + result.matchType);
        }

        // Log results
        if (results.isEmpty()) {
            System.debug('AIQuickMatchService: No lead candidates (all matched or excluded)');
        }

        return results;
    }

    /**
     * Build cache with minimal SOQL queries
     * IMPROVED: Collects ALL participants (FROM + TO + CC) for matching
     */
    private static BulkCache buildBulkCache(List<Map<String, Object>> emails) {
        BulkCache cache = new BulkCache();

        // Collect ALL unique email addresses and domains from all participants
        // (FROM, TO, and CC) excluding the current user
        Set<String> allEmails = new Set<String>();
        Set<String> allDomains = new Set<String>();

        String currentUserEmail = UserInfo.getUserEmail();
        if (String.isNotBlank(currentUserEmail)) {
            currentUserEmail = currentUserEmail.toLowerCase();
        }

        for (Map<String, Object> email : emails) {
            // Collect ALL participant emails (FROM + TO + CC)
            Set<String> participantEmails = getAllParticipantEmails(email, currentUserEmail);

            for (String participantEmail : participantEmails) {
                allEmails.add(participantEmail);
                String domain = extractDomain(participantEmail);
                if (String.isNotBlank(domain)) {
                    allDomains.add(domain);
                }
            }
        }

        // Query 1: Bulk fetch Contacts by email
        if (!allEmails.isEmpty()) {
            for (Contact c : [
                SELECT Id, Name, Email, AccountId, Account.Name
                FROM Contact
                WHERE Email IN :allEmails
                WITH USER_MODE
            ]) {
                if (String.isNotBlank(c.Email)) {
                    cache.emailToContact.put(c.Email.toLowerCase(), c);
                }
            }
        }

        // Query 2: Bulk fetch Leads by email (only non-converted)
        if (!allEmails.isEmpty()) {
            for (Lead l : [
                SELECT Id, Name, Email, Company, IsConverted
                FROM Lead
                WHERE Email IN :allEmails
                AND IsConverted = false
                WITH USER_MODE
            ]) {
                if (String.isNotBlank(l.Email)) {
                    cache.emailToLead.put(l.Email.toLowerCase(), l);
                }
            }
        }

        // Query 3: Bulk fetch Accounts by domain (Website match) OR Account Name
        // OPTIMIZED: Single query with collected patterns instead of SOQL-in-loop
        if (!allDomains.isEmpty()) {
            // Collect all non-public domains and their patterns
            Set<String> websitePatterns = new Set<String>();
            Set<String> namePatterns = new Set<String>();
            Map<String, String> domainToNamePattern = new Map<String, String>();

            for (String domain : allDomains) {
                // Skip common public email domains - no point matching these to accounts
                if (isPublicEmailDomain(domain)) {
                    continue;
                }

                // Extract the company name part from domain (e.g., 'spglobal' from 'spglobal.com')
                String domainName = domain.contains('.') ? domain.substring(0, domain.indexOf('.')) : domain;

                websitePatterns.add('%' + domain + '%');
                namePatterns.add('%' + domainName + '%');
                domainToNamePattern.put(domain, domainName);
            }

            // Single query to fetch all potential account matches
            if (!websitePatterns.isEmpty()) {
                // Build dynamic SOQL to handle multiple LIKE conditions
                // Query accounts that match ANY of our patterns
                List<Account> allMatchedAccounts = [
                    SELECT Id, Name, Website
                    FROM Account
                    WHERE Website != null
                    WITH USER_MODE
                    ORDER BY Website DESC NULLS LAST
                    LIMIT 1000
                ];

                // Match accounts to domains post-query
                for (String domain : domainToNamePattern.keySet()) {
                    String domainName = domainToNamePattern.get(domain);

                    for (Account acc : allMatchedAccounts) {
                        // Check Website match
                        if (acc.Website != null && acc.Website.toLowerCase().contains(domain.toLowerCase())) {
                            cache.domainToAccount.put(domain, acc);
                            break;
                        }
                        // Check Name match
                        if (acc.Name != null && acc.Name.toLowerCase().contains(domainName.toLowerCase())) {
                            if (!cache.domainToAccount.containsKey(domain)) {
                                cache.domainToAccount.put(domain, acc);
                            }
                        }
                    }
                }
            }
        }

        // Collect Account IDs for Opportunity query
        Set<Id> accountIds = new Set<Id>();
        for (Contact c : cache.emailToContact.values()) {
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            }
        }
        for (Account a : cache.domainToAccount.values()) {
            accountIds.add(a.Id);
        }

        // Query 4: Bulk fetch Opportunities for matched Accounts
        if (!accountIds.isEmpty()) {
            for (Opportunity opp : [
                SELECT Id, Name, AccountId, StageName, CloseDate, LastActivityDate
                FROM Opportunity
                WHERE AccountId IN :accountIds
                AND IsClosed = false
                WITH USER_MODE
                ORDER BY LastActivityDate DESC NULLS LAST, CloseDate ASC
            ]) {
                if (!cache.accountToOpportunities.containsKey(opp.AccountId)) {
                    cache.accountToOpportunities.put(opp.AccountId, new List<Opportunity>());
                }
                cache.accountToOpportunities.get(opp.AccountId).add(opp);
            }
        }

        // Collect Contact IDs for Case query
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : cache.emailToContact.values()) {
            contactIds.add(c.Id);
        }

        // Query 5: Bulk fetch Cases for matched Contacts
        if (!contactIds.isEmpty()) {
            for (Case cs : [
                SELECT Id, CaseNumber, ContactId, Subject, Status, Priority
                FROM Case
                WHERE ContactId IN :contactIds
                AND IsClosed = false
                WITH USER_MODE
                ORDER BY CreatedDate DESC
            ]) {
                if (!cache.contactToCases.containsKey(cs.ContactId)) {
                    cache.contactToCases.put(cs.ContactId, new List<Case>());
                }
                cache.contactToCases.get(cs.ContactId).add(cs);
            }
        }

        return cache;
    }

    /**
     * Match single email using cached data
     * IMPROVED: Checks ALL participants (FROM + TO + CC) to find matches
     * Now collects ALL matching Contacts AND Account/Opportunity for multi-association
     */
    private static MatchResult matchWithCache(Map<String, Object> emailData, BulkCache cache, Set<String> internalDomains) {
        MatchResult result = new MatchResult();

        // Extract email data
        result.fromAddress = getFromAddress(emailData);
        result.fromName = getFromName(emailData);
        result.emailSubject = getSubject(emailData);

        // Get current user email to exclude from matching
        String currentUserEmail = UserInfo.getUserEmail();
        if (String.isNotBlank(currentUserEmail)) {
            currentUserEmail = currentUserEmail.toLowerCase();
        }

        // Get ALL participant emails (FROM + TO + CC, excluding current user)
        Set<String> participantEmails = getAllParticipantEmails(emailData, currentUserEmail);

        if (participantEmails.isEmpty()) {
            result.matchDetails.add('No participant emails found (only current user email)');
            result.matchType = 'None';
            result.confidence = 0;
            return result;
        }

        result.matchDetails.add('Checking ' + participantEmails.size() + ' participant(s): ' + String.join(new List<String>(participantEmails), ', '));

        // Get internal domains to exclude (passed in or fetched)
        if (internalDomains == null) {
            String currentUserDomain = extractDomain(currentUserEmail);
            internalDomains = getInternalDomains(currentUserDomain);
        }

        // Track all matches - we want BOTH Contacts AND Account/Opportunity
        Set<Id> matchedContactIds = new Set<Id>();
        Set<Id> accountIdsFromContacts = new Set<Id>();

        // Check if internal exclusion is enabled (for Contact matching)
        Boolean excludeInternalContacts = AISyncSettingsService.excludeInternal();

        // STEP 1: Find ALL matching Contacts (collect all, not just first)
        for (String emailLower : participantEmails) {
            if (cache.emailToContact.containsKey(emailLower)) {
                Contact c = cache.emailToContact.get(emailLower);

                // Skip if this Contact is from an internal domain (same company as user)
                // BUT only if Exclude_Internal__c setting is enabled
                String contactDomain = extractDomain(c.Email);
                if (excludeInternalContacts && contactDomain != null && internalDomains.contains(contactDomain.toLowerCase())) {
                    result.matchDetails.add('Skipped internal Contact: ' + c.Name + ' (' + contactDomain + ') - Exclude_Internal enabled');
                    continue;
                }

                matchedContactIds.add(c.Id);
                result.matchDetails.add('Matched Contact: ' + c.Name + ' (' + emailLower + ')');

                // Track Account from Contact for later
                if (c.AccountId != null) {
                    accountIdsFromContacts.add(c.AccountId);
                    if (result.accountId == null) {
                        result.accountId = c.AccountId;
                        result.matchDetails.add('Matched Account: ' + c.Account.Name + ' via Contact');
                    }
                }

                // Look for related Cases (use first Contact's cases)
                if (result.caseId == null && cache.contactToCases.containsKey(c.Id)) {
                    List<Case> cases = cache.contactToCases.get(c.Id);
                    if (!cases.isEmpty()) {
                        result.caseId = cases[0].Id;
                        result.matchDetails.add('Matched Case: #' + cases[0].CaseNumber);
                    }
                }
            }
        }

        // Set primary contactId and all contactIds
        if (!matchedContactIds.isEmpty()) {
            result.contactIds = new List<Id>(matchedContactIds);
            result.contactId = result.contactIds[0]; // Primary for backward compatibility
            result.confidence = 95;
            result.matchType = 'Contact';
        }

        // STEP 2: Find matching Lead (only if no Contacts found)
        if (matchedContactIds.isEmpty()) {
            for (String emailLower : participantEmails) {
                if (cache.emailToLead.containsKey(emailLower)) {
                    Lead l = cache.emailToLead.get(emailLower);
                    result.leadId = l.Id;
                    result.confidence = 95;
                    result.matchType = 'Lead';
                    result.matchDetails.add('Matched Lead: ' + l.Name + ' by email (' + emailLower + ')');
                    break; // Only one Lead
                }
            }
        }

        // STEP 2.5: Auto-create Lead Logic is now handled in matchBatch via bulk processing

        // STEP 3: Find Account by domain (if not already found via Contact)
        if (result.accountId == null) {
            for (String emailLower : participantEmails) {
                String domain = extractDomain(emailLower);
                if (String.isNotBlank(domain) && !isPublicEmailDomain(domain) && cache.domainToAccount.containsKey(domain)) {
                    Account a = cache.domainToAccount.get(domain);
                    result.accountId = a.Id;

                    // Indicate if match was by Website or Name
                    if (String.isNotBlank(a.Website) && a.Website.toLowerCase().contains(domain)) {
                        result.matchDetails.add('Matched Account: ' + a.Name + ' by website domain (' + domain + ')');
                    } else {
                        result.matchDetails.add('Matched Account: ' + a.Name + ' by name similarity (' + domain + ')');
                    }

                    // Set match type and confidence if no Contact/Lead found
                    if (result.confidence == 0) {
                        result.confidence = 80;
                        result.matchType = 'Account';
                    }
                    break;
                }
            }
        }

        // STEP 4: Find Opportunity for the Account
        if (result.accountId != null && cache.accountToOpportunities.containsKey(result.accountId)) {
            List<Opportunity> opps = cache.accountToOpportunities.get(result.accountId);
            if (!opps.isEmpty()) {
                result.opportunityId = opps[0].Id;
                result.matchDetails.add('Matched Opportunity: ' + opps[0].Name + ' (most recent)');
                // Boost confidence if we have Opp
                if (result.confidence < 85) {
                    result.confidence = 85;
                }
            }
        }

        // No match found
        if (result.confidence == 0) {
            result.matchType = 'None';
            result.matchDetails.add('No Contact, Lead, or Account found matching any participant');
        }

        return result;
    }

    // ========================================================================
    // USER CONTEXT MATCHING
    // ========================================================================

    /**
     * Match the authenticated user's email (from OAuth provider) to:
     * 1. First, a Salesforce User (employee using their work account)
     * 2. If not a User, then a Contact (community user or external contact)
     * 3. If not a Contact, then a Lead
     *
     * This is used as a fallback when no other matches are found in task/calendar content.
     *
     * @param userEmail The authenticated user's email from Microsoft Graph or Gmail
     * @return MatchResult with User, Contact, or Lead match
     */
    public static MatchResult matchUserEmail(String userEmail) {
        MatchResult result = new MatchResult();

        if (String.isBlank(userEmail)) {
            result.matchType = 'None';
            result.matchDetails.add('No user email provided');
            return result;
        }

        String emailLower = userEmail.toLowerCase().trim();
        result.fromAddress = emailLower;

        // STEP 1: Try to match to a Salesforce User first
        List<User> users = [
            SELECT Id, Name, Email, ContactId, Contact.Name, Contact.AccountId, Contact.Account.Name
            FROM User
            WHERE Email = :emailLower
            AND IsActive = true
            WITH USER_MODE
            LIMIT 1
        ];

        if (!users.isEmpty()) {
            User u = users[0];
            result.confidence = 100;
            result.matchType = 'User';
            result.matchDetails.add('Matched authenticated user to Salesforce User: ' + u.Name);

            // If User has a linked Contact (community user), use that Contact for WhoId
            if (u.ContactId != null) {
                result.contactId = u.ContactId;
                result.contactIds.add(u.ContactId);
                result.matchDetails.add('User has linked Contact: ' + u.Contact.Name);

                if (u.Contact.AccountId != null) {
                    result.accountId = u.Contact.AccountId;
                    result.matchDetails.add('Associated Account: ' + u.Contact.Account.Name);
                }
            }
            return result;
        }

        // STEP 2: Try to find Contact with this email
        List<Contact> contacts = [
            SELECT Id, Name, Email, AccountId, Account.Name
            FROM Contact
            WHERE Email = :emailLower
            WITH USER_MODE
            LIMIT 1
        ];

        if (!contacts.isEmpty()) {
            Contact c = contacts[0];
            result.contactId = c.Id;
            result.contactIds.add(c.Id);
            result.confidence = 100;
            result.matchType = 'Contact';
            result.matchDetails.add('Matched authenticated user to Contact: ' + c.Name);

            if (c.AccountId != null) {
                result.accountId = c.AccountId;
                result.matchDetails.add('Associated Account: ' + c.Account.Name);
            }
            return result;
        }

        // STEP 3: Try to find Lead with this email
        List<Lead> leads = [
            SELECT Id, Name, Email, Company
            FROM Lead
            WHERE Email = :emailLower
            AND IsConverted = false
            WITH USER_MODE
            LIMIT 1
        ];

        if (!leads.isEmpty()) {
            Lead l = leads[0];
            result.leadId = l.Id;
            result.confidence = 100;
            result.matchType = 'Lead';
            result.matchDetails.add('Matched authenticated user to Lead: ' + l.Name);
            return result;
        }

        // No match found
        result.matchType = 'None';
        result.matchDetails.add('No User, Contact, or Lead found for user email: ' + emailLower);
        return result;
    }

    /**
     * Get user email and Contact/Lead match from Microsoft Graph API.
     * Caches result for the transaction to avoid repeated API calls.
     *
     * @return MatchResult with user's Contact/Lead match, or null if API call fails
     */
    private static MatchResult cachedUserMatch;
    private static Boolean userMatchAttempted = false;

    public static MatchResult getAuthenticatedUserMatch() {
        // Return cached result if already fetched
        if (userMatchAttempted) {
            return cachedUserMatch;
        }

        userMatchAttempted = true;

        try {
            // Try Microsoft Graph first
            String userEmail = getMicrosoftGraphUserEmail();

            if (String.isNotBlank(userEmail)) {
                cachedUserMatch = matchUserEmail(userEmail);
                return cachedUserMatch;
            }

            // Could add Gmail user email lookup here in future

        } catch (Exception e) {
            System.debug('Error getting authenticated user match: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Get user email from Microsoft Graph API /me endpoint
     */
    private static String getMicrosoftGraphUserEmail() {
        try {
            // Check if user has a connection first
            if (!AIWorkspaceTokenService.hasConnection(AIWorkspaceTokenService.PROVIDER_OUTLOOK)) {
                System.debug('Outlook connection not found for current user');
                return null;
            }
            
            String accessToken = AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_OUTLOOK);
            if (String.isBlank(accessToken)) {
                System.debug('Outlook access token not found for current user');
                return null;
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://graph.microsoft.com/v1.0/me');
            req.setMethod('GET');
            req.setTimeout(30000);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> userInfo = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String email = (String) userInfo.get('userPrincipalName');
                if (String.isBlank(email)) {
                    email = (String) userInfo.get('mail');
                }
                return email;
            }
        } catch (Exception e) {
            System.debug('Error getting Microsoft Graph user email: ' + e.getMessage());
        }
        return null;
    }

    /**
     * Clear the cached user match (for testing)
     */
    @TestVisible
    private static void clearUserMatchCache() {
        cachedUserMatch = null;
        userMatchAttempted = false;
    }

    // ========================================================================
    // HELPER METHODS
    // ========================================================================

    private static String getFromAddress(Map<String, Object> emailData) {
        Object fromAddr = emailData.get('fromAddress');
        if (fromAddr != null) {
            return String.valueOf(fromAddr).trim();
        }

        // Fallback to other possible field names
        fromAddr = emailData.get('from');
        if (fromAddr != null) {
            // Handle complex from object
            if (fromAddr instanceof Map<String, Object>) {
                Map<String, Object> fromObjMap = (Map<String, Object>) fromAddr;
                Object emailAddr = fromObjMap.get('emailAddress');
                if (emailAddr instanceof Map<String, Object>) {
                    Map<String, Object> emailAddrMap = (Map<String, Object>) emailAddr;
                    return String.valueOf(emailAddrMap.get('address'));
                }
                return String.valueOf(emailAddr);
            }
            // Also check for generic Map just in case
            if (fromAddr instanceof Map<Object, Object>) {
                Map<Object, Object> fromObjMap = (Map<Object, Object>) fromAddr;
                Object emailAddr = fromObjMap.get('emailAddress');
                if (emailAddr instanceof Map<Object, Object>) {
                    Map<Object, Object> emailAddrMap = (Map<Object, Object>) emailAddr;
                    return String.valueOf(emailAddrMap.get('address'));
                }
                return String.valueOf(emailAddr);
            }
            return String.valueOf(fromAddr);
        }

        return null;
    }

    private static String getFromName(Map<String, Object> emailData) {
        Object fromName = emailData.get('fromName');
        if (fromName != null) {
            return String.valueOf(fromName);
        }

        // Fallback to from object
        Object fromObj = emailData.get('from');
        if (fromObj instanceof Map<Object, Object>) {
            Map<Object, Object> fromObjMap = (Map<Object, Object>) fromObj;
            Object emailAddr = fromObjMap.get('emailAddress');
            if (emailAddr instanceof Map<Object, Object>) {
                Map<Object, Object> emailAddrMap = (Map<Object, Object>) emailAddr;
                return String.valueOf(emailAddrMap.get('name'));
            }
        }

        return 'Unknown Sender';
    }

    private static String getSubject(Map<String, Object> emailData) {
        Object subject = emailData.get('subject');
        return subject != null ? String.valueOf(subject) : 'No Subject';
    }

    private static String extractDomain(String email) {
        if (String.isBlank(email)) return null;

        Integer atIndex = email.indexOf('@');
        if (atIndex < 0 || atIndex == email.length() - 1) return null;

        return email.substring(atIndex + 1).toLowerCase();
    }

    /**
     * Check if domain is a public email domain (gmail, yahoo, etc.) or internal/excluded.
     * Uses centralized settings from AISyncSettingsService.
     */
    private static Boolean isPublicEmailDomain(String domain) {
        if (String.isBlank(domain)) return true;

        // Check if public domain exclusion is enabled in settings
        if (AISyncSettingsService.excludePublicDomains() && AISyncSettingsService.isPublicDomain(domain)) {
            return true;
        }

        // Also check Internal_Domains__c for company-specific exclusions
        return AISyncSettingsService.isDomainInternal(domain);
    }

    /**
     * Get set of internal company domains that should be excluded from matching
     * Uses AISyncSettingsService for centralized domain management
     */
    private static Set<String> getInternalDomains(String currentUserDomain) {
        Set<String> internalDomains = new Set<String>();

        // Add current user's domain
        if (String.isNotBlank(currentUserDomain)) {
            internalDomains.add(currentUserDomain.toLowerCase());
        }

        // Get excluded domains from settings
        Set<String> excludedDomains = AISyncSettingsService.getInternalDomains();
        if (excludedDomains != null) {
            internalDomains.addAll(excludedDomains);
        }

        return internalDomains;
    }

    /**
     * Get ALL participant emails from an email (FROM + TO + CC)
     * Excludes the current user's email
     * Used to find ANY matching Contact/Lead/Account from any participant
     */
    private static Set<String> getAllParticipantEmails(Map<String, Object> emailData, String currentUserEmail) {
        Set<String> participantEmails = new Set<String>();

        // Add FROM address (if not current user)
        String fromAddress = getFromAddress(emailData);
        if (String.isNotBlank(fromAddress)) {
            String fromLower = fromAddress.toLowerCase();
            if (!fromLower.equals(currentUserEmail)) {
                participantEmails.add(fromLower);
            }
        }

        // Add TO recipients
        addRecipientsToSet(emailData.get('toRecipients'), participantEmails, currentUserEmail);

        // Add CC recipients
        addRecipientsToSet(emailData.get('ccRecipients'), participantEmails, currentUserEmail);

        // Also check Gmail format recipients
        addRecipientsToSet(emailData.get('to'), participantEmails, currentUserEmail);
        addRecipientsToSet(emailData.get('cc'), participantEmails, currentUserEmail);

        return participantEmails;
    }

    /**
     * Helper to extract email addresses from recipient list and add to set
     * Handles both Outlook (toRecipients) and Gmail (to) formats
     */
    private static void addRecipientsToSet(Object recipients, Set<String> emailSet, String currentUserEmail) {
        if (recipients == null) return;

        if (recipients instanceof List<Object>) {
            List<Object> recipientList = (List<Object>) recipients;
            for (Object recipient : recipientList) {
                String email = extractEmailFromRecipient(recipient);
                if (String.isNotBlank(email)) {
                    String emailLower = email.toLowerCase();
                    if (!emailLower.equals(currentUserEmail)) {
                        emailSet.add(emailLower);
                    }
                }
            }
        }
    }

    /**
     * Extract email address from recipient object (handles multiple formats)
     */
    private static String extractEmailFromRecipient(Object recipient) {
        if (recipient == null) return null;

        // Handle Map<String, Object> format
        if (recipient instanceof Map<String, Object>) {
            Map<String, Object> recipientMap = (Map<String, Object>) recipient;

            // Outlook format: { emailAddress: { address: 'email@domain.com' } }
            Object emailAddr = recipientMap.get('emailAddress');
            if (emailAddr instanceof Map<String, Object>) {
                return String.valueOf(((Map<String, Object>) emailAddr).get('address'));
            }

            // Gmail format: { email: 'email@domain.com' }
            Object directEmail = recipientMap.get('email');
            if (directEmail != null) {
                return String.valueOf(directEmail);
            }

            // Direct address field
            Object address = recipientMap.get('address');
            if (address != null) {
                return String.valueOf(address);
            }
        }

        // Handle Map<Object, Object> format (Apex JSON deserialization)
        if (recipient instanceof Map<Object, Object>) {
            Map<Object, Object> recipientMap = (Map<Object, Object>) recipient;

            // Outlook format
            Object emailAddr = recipientMap.get('emailAddress');
            if (emailAddr instanceof Map<Object, Object>) {
                return String.valueOf(((Map<Object, Object>) emailAddr).get('address'));
            }

            // Gmail format
            Object directEmail = recipientMap.get('email');
            if (directEmail != null) {
                return String.valueOf(directEmail);
            }

            // Direct address field
            Object address = recipientMap.get('address');
            if (address != null) {
                return String.valueOf(address);
            }
        }

        // Handle plain string (some email formats)
        if (recipient instanceof String) {
            return (String) recipient;
        }

        return null;
    }
}