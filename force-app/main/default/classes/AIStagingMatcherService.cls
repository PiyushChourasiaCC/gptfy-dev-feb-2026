/**
 * AIStagingMatcherService - Service class for matching staging records to Lead/Contact
 * 
 * Uses configurable precedence rules from AI_Workspace_Sync_Settings__c custom setting (Sync_Precedence__c field)
 * to determine the order in which to match sender emails.
 * 
 * PRECEDENCE LOGIC:
 * 
 * 1. If Sync_Precedence__c is EMPTY or NULL:
 *    - Default behavior: Try to match both Lead AND Contact
 *    - If both match → Link to both
 *    - If only Lead matches → Link to Lead
 *    - If only Contact matches → Link to Contact
 * 
 * 2. If Sync_Precedence__c has a value:
 *    - Follow the configured precedence rules exactly
 *    - For each level, ALL objects in that level must match for it to be used
 *    - Examples:
 *      - {"1": ["Lead"]} → Only match Leads
 *      - {"1": ["Contact"]} → Only match Contacts
 *      - {"1": ["Lead", "Contact"]} → Must match BOTH Lead AND Contact
 *      - {"1": ["Lead", "Contact"], "2": ["Lead"], "3": ["Contact"]} → Standard cascading
 * 
 * NOTE: User object matching is NOT supported - only Lead and Contact
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIStagingMatcherService {
    
    /**
     * Wrapper for single match result - contains ALL matched IDs at the successful precedence level
     * NOTE: Lead, Contact, and Account (via domain) are supported
     */
    public class MatchResult {
        // Single ID fields for backward compatibility
        public Id leadId;
        public Id contactId;
        public Id accountId;
        
        // Lists of ALL matched IDs at the successful precedence level
        public List<Id> matchedLeadIds;
        public List<Id> matchedContactIds;
        public List<Id> matchedAccountIds; // Domain-based Account matches (independent)
        public List<String> matchedObjectTypes; // All object types that matched at this level
        
        public Integer precedenceLevel;
        public String matchedObjectType; // Primary object type (first in list)
        public Boolean isMatched;
        public String matchedEmail; // The email that was matched
        
        public MatchResult() {
            this.isMatched = false;
            this.precedenceLevel = 0;
            this.matchedLeadIds = new List<Id>();
            this.matchedContactIds = new List<Id>();
            this.matchedAccountIds = new List<Id>();
            this.matchedObjectTypes = new List<String>();
        }
        
        /**
         * Get total count of all matched records
         */
        public Integer getTotalMatchCount() {
            return matchedLeadIds.size() + matchedContactIds.size() + matchedAccountIds.size();
        }
        
        /**
         * Check if there are multiple matches (for creating multiple relations)
         */
        public Boolean hasMultipleMatches() {
            return getTotalMatchCount() > 1;
        }
    }
    
    /**
     * Wrapper for multiple match results (for emails with From, To, CC)
     * NOTE: Lead, Contact, and Account (via domain) are supported
     */
    public class MultiMatchResult {
        public MatchResult primaryMatch; // Match for the sender (From)
        public List<MatchResult> allMatches; // All matches (From, To, CC) - each with potentially multiple IDs
        public Boolean hasPrimaryMatch;
        public Boolean hasAnyMatch;
        
        public MultiMatchResult() {
            this.primaryMatch = new MatchResult();
            this.allMatches = new List<MatchResult>();
            this.hasPrimaryMatch = false;
            this.hasAnyMatch = false;
        }
        
        /**
         * Get all unique Lead IDs from all matches
         */
        public Set<Id> getAllLeadIds() {
            Set<Id> ids = new Set<Id>();
            for (MatchResult match : allMatches) {
                ids.addAll(match.matchedLeadIds);
            }
            return ids;
        }
        
        /**
         * Get all unique Contact IDs from all matches
         */
        public Set<Id> getAllContactIds() {
            Set<Id> ids = new Set<Id>();
            for (MatchResult match : allMatches) {
                ids.addAll(match.matchedContactIds);
            }
            return ids;
        }
        
        /**
         * Get total relation count (for determining if async processing is needed)
         */
        public Integer getTotalRelationCount() {
            return getAllLeadIds().size() + getAllContactIds().size();
        }
    }
    
    /**
     * Cache for bulk email lookups
     * NOTE: Only Lead and Contact are supported - User matching is not supported
     */
    public class EmailMatchCache {
        public Map<String, Id> emailToLeadId = new Map<String, Id>();
        public Map<String, Id> emailToContactId = new Map<String, Id>();
        public Map<String, Id> emailToContactAccountId = new Map<String, Id>(); // Contact Email -> Contact's Account ID
        public Map<String, List<Id>> domainToAccountIds = new Map<String, List<Id>>(); // Domain -> Account IDs (domain-based matching)
    }
    
    /**
     * Parsed precedence configuration
     */
    private static Map<Integer, List<String>> precedenceConfig;
    
    /**
     * Parse the precedence configuration from AI_Workspace_Sync_Settings__c Custom Setting
     * 
     * If Sync_Precedence__c is EMPTY or NULL:
     *   Returns DEFAULT config: Try both, then Lead, then Contact
     *   {"1": ["Lead", "Contact"], "2": ["Lead"], "3": ["Contact"]}
     * 
     * If Sync_Precedence__c has a value:
     *   Parses and returns the configured precedence rules
     * 
     * @return Map of precedence level to list of object types
     */
    public static Map<Integer, List<String>> getPrecedenceConfig() {
        if (precedenceConfig != null) {
            return precedenceConfig;
        }
        
        precedenceConfig = new Map<Integer, List<String>>();
        
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            
            if (settings == null || String.isBlank(settings.Sync_Precedence__c)) {
                // Return DEFAULT config when field is empty:
                // Level 1: Try to match BOTH Lead AND Contact
                // Level 2: If not both, try Lead only
                // Level 3: If not Lead, try Contact only
                precedenceConfig.put(1, new List<String>{ 'Lead', 'Contact' });
                precedenceConfig.put(2, new List<String>{ 'Lead' });
                precedenceConfig.put(3, new List<String>{ 'Contact' });
                return precedenceConfig;
            }
            
            String jsonConfig = settings.Sync_Precedence__c;
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonConfig);
            
            for (String key : parsed.keySet()) {
                Integer level = Integer.valueOf(key);
                List<Object> objectTypes = (List<Object>) parsed.get(key);
                List<String> types = new List<String>();
                for (Object obj : objectTypes) {
                    // Only allow Lead and Contact (skip any User entries)
                    String objType = (String) obj;
                    if (objType == 'Lead' || objType == 'Contact') {
                        types.add(objType);
                    }
                }
                if (!types.isEmpty()) {
                    precedenceConfig.put(level, types);
                }
            }
            
            // If after parsing we have no valid levels, use default
            if (precedenceConfig.isEmpty()) {
                precedenceConfig.put(1, new List<String>{ 'Lead', 'Contact' });
                precedenceConfig.put(2, new List<String>{ 'Lead' });
                precedenceConfig.put(3, new List<String>{ 'Contact' });
            }
            
        } catch (Exception e) {
            // Return default config on error
            precedenceConfig.put(1, new List<String>{ 'Lead', 'Contact' });
            precedenceConfig.put(2, new List<String>{ 'Lead' });
            precedenceConfig.put(3, new List<String>{ 'Contact' });
        }
        
        return precedenceConfig;
    }
    
    /**
     * Check if matching is enabled
     * Matching is ALWAYS enabled since we have a default config
     * @return true always (matching uses default config if none specified)
     */
    public static Boolean isMatchingEnabled() {
        return true;
    }
    
    /**
     * Clear cached precedence config (for testing)
     */
    @TestVisible
    private static void clearCache() {
        precedenceConfig = null;
    }
    
    /**
     * Build email match cache by querying Lead and Contact in bulk
     * Also builds domain-based Account cache (independent feature)
     * NOTE: User matching is not supported
     * @param emails Set of email addresses to match
     * @return EmailMatchCache with mappings
     */
    public static EmailMatchCache buildEmailMatchCache(Set<String> emails) {
        EmailMatchCache cache = new EmailMatchCache();
        
        if (emails == null || emails.isEmpty()) {
            return cache;
        }
        
        // Normalize emails to lowercase for case-insensitive matching
        Set<String> normalizedEmails = new Set<String>();
        Set<String> domains = new Set<String>();
        
        for (String email : emails) {
            if (String.isNotBlank(email)) {
                String normalized = email.toLowerCase();
                normalizedEmails.add(normalized);
                
                // Extract domain for Account matching
                String domain = extractDomain(normalized);
                if (String.isNotBlank(domain) && !isPublicEmailDomain(domain)) {
                    domains.add(domain);
                }
            }
        }
        
        if (normalizedEmails.isEmpty()) {
            return cache;
        }
        
        // Query Leads
        try {
            for (Lead l : [
                SELECT Id, Email 
                FROM Lead 
                WHERE Email IN :normalizedEmails 
                AND IsConverted = false
                WITH USER_MODE
            ]) {
                if (String.isNotBlank(l.Email)) {
                    cache.emailToLeadId.put(l.Email.toLowerCase(), l.Id);
                }
            }
        } catch (Exception e) {
            //ignore
        }
        
        // Query Contacts (with AccountId to check if Contact has an Account)
        Map<String, Id> emailToContactAccountId = new Map<String, Id>();
        try {
            List<Contact> contacts = [
                SELECT Id, Email, AccountId
                FROM Contact 
                WHERE Email IN :normalizedEmails
                WITH USER_MODE
            ];
            
            
            for (Contact c : contacts) {
                if (String.isNotBlank(c.Email)) {
                    cache.emailToContactId.put(c.Email.toLowerCase(), c.Id);
                    if (c.AccountId != null) {
                        emailToContactAccountId.put(c.Email.toLowerCase(), c.AccountId);
                    }
                }
            }
        } catch (Exception e) {
            //ignore
        }
        
        // Store Contact->Account mapping in cache for precedence logic
        cache.emailToContactAccountId = emailToContactAccountId;
        
        // Query Accounts by domain (INDEPENDENT feature - always runs)
        if (!domains.isEmpty()) {
            try {
                // Query all Accounts with Website field populated
                List<Account> accounts = [
                    SELECT Id, Name, Website
                    FROM Account
                    WHERE Website != null
                    WITH USER_MODE
                    LIMIT 1000
                ];
                
                
                // Match domains against Account websites (contains match)
                for (String domain : domains) {
                    List<Id> matchedAccountIds = new List<Id>();
                    
                    for (Account acc : accounts) {
                        if (String.isNotBlank(acc.Website) && 
                            acc.Website.toLowerCase().contains(domain.toLowerCase())) {
                            matchedAccountIds.add(acc.Id);
                        }
                    }
                    
                    if (!matchedAccountIds.isEmpty()) {
                        cache.domainToAccountIds.put(domain, matchedAccountIds);
                    }
                }
            } catch (Exception e) {
                //ignore
            }
        }
        
        return cache;
    }
    
    
    /**
     * Match a single email address using precedence rules
     * Also performs domain-based Account matching (INDEPENDENT feature)
     * 
     * LOGIC: ALL objects in a precedence level must have the email for that level to be used.
     * When a level matches, returns ALL matched IDs (Lead, Contact) at that level.
     * Domain-based Account matching runs independently and always adds matched Accounts.
     * 
     * Example: Precedence 1 = ["Lead", "Contact"]
     * - If email exists in Lead AND Contact -> Returns both IDs
     * - If email exists in only Lead -> Try Precedence 2
     * - Domain-based Accounts are ALWAYS added regardless of precedence
     * 
     * NOTE: User matching is NOT supported
     * 
     * @param email Email address to match
     * @param cache Pre-built email match cache
     * @return MatchResult with ALL matched IDs at the successful precedence level + domain-based Accounts
     */
    public static MatchResult matchEmail(String email, EmailMatchCache cache) {
        MatchResult result = new MatchResult();
        
        if (String.isBlank(email) || cache == null) {
            return result;
        }
        
        String normalizedEmail = email.toLowerCase();
        Map<Integer, List<String>> config = getPrecedenceConfig();
        
        
        // Get sorted precedence levels
        List<Integer> levels = new List<Integer>(config.keySet());
        levels.sort();
        
        // Try each precedence level in order
        for (Integer level : levels) {
            List<String> objectTypes = config.get(level);
            
            // Check if ALL object types at this level have a match
            Boolean allMatch = true;
            Id tempLeadId = null;
            Id tempContactId = null;
            List<String> matchedTypes = new List<String>();
            
            for (String objectType : objectTypes) {
                if (objectType == 'Lead') {
                    if (cache.emailToLeadId.containsKey(normalizedEmail)) {
                        tempLeadId = cache.emailToLeadId.get(normalizedEmail);
                        matchedTypes.add('Lead');
                    } else {
                        allMatch = false;
                        break;
                    }
                } else if (objectType == 'Contact') {
                    if (cache.emailToContactId.containsKey(normalizedEmail)) {
                        tempContactId = cache.emailToContactId.get(normalizedEmail);
                        matchedTypes.add('Contact');
                    } else {
                        allMatch = false;
                        break;
                    }
                }
                // User matching is NOT supported - skip any User entries in config
            }
            
            // If ALL objects at this level matched, return the result with ALL matched IDs
            if (allMatch && !matchedTypes.isEmpty()) {
                result.precedenceLevel = level;
                result.isMatched = true;
                result.matchedObjectTypes = matchedTypes;
                result.matchedObjectType = matchedTypes[0]; // Primary type for backward compatibility
                
                // Populate single ID fields for backward compatibility
                if (tempLeadId != null) {
                    result.leadId = tempLeadId;
                    result.matchedLeadIds.add(tempLeadId);
                }
                if (tempContactId != null) {
                    result.contactId = tempContactId;
                    result.matchedContactIds.add(tempContactId);
                    
                    // If Contact has an Account, set it as the accountId
                    if (cache.emailToContactAccountId.containsKey(normalizedEmail)) {
                        Id contactAccountId = cache.emailToContactAccountId.get(normalizedEmail);
                        if (contactAccountId != null) {
                            result.accountId = contactAccountId;
                        }
                    }
                }
                
                
                // INDEPENDENT FEATURE: Add domain-based Account matches (always runs)
                addDomainBasedAccountMatches(normalizedEmail, cache, result);
                
                return result;
            }
        }
        
        // No match found at any precedence level
        
        // INDEPENDENT FEATURE: Even if no Lead/Contact match, add domain-based Account matches
        addDomainBasedAccountMatches(normalizedEmail, cache, result);
        
        return result;
    }
    
    /**
     * Add domain-based Account matches to the result (INDEPENDENT feature)
     * This feature always runs regardless of precedence configuration
     * @param email Email address
     * @param cache Email match cache with domain mappings
     * @param result MatchResult to populate with Account IDs
     */
    private static void addDomainBasedAccountMatches(String email, EmailMatchCache cache, MatchResult result) {
        String domain = extractDomain(email);
        
        if (String.isBlank(domain)) return;
        
        if (cache.domainToAccountIds.containsKey(domain)) {
            List<Id> accountIds = cache.domainToAccountIds.get(domain);
            if (accountIds != null && !accountIds.isEmpty()) {
                result.matchedAccountIds.addAll(accountIds);
                
                // Set primary accountId if not already set by Contact
                if (result.accountId == null && !accountIds.isEmpty()) {
                    result.accountId = accountIds[0];
                }
                
            }
        }
    }
    
    /**
     * Match multiple staging records in bulk (for Emails - uses From_Address__c only)
     * @deprecated Use matchEmailStagingRecordsMulti for full From/To/CC matching
     * @param stagingRecords List of staging records to match
     * @return Map of staging record ID to MatchResult
     */
    public static Map<Id, MatchResult> matchStagingRecords(List<AI_Workspace_Staging__c> stagingRecords) {
        Map<Id, MatchResult> results = new Map<Id, MatchResult>();
        
        if (stagingRecords == null || stagingRecords.isEmpty()) {
            return results;
        }
        
        // Check if matching is enabled
        if (!isMatchingEnabled()) {
            // Return empty results for all records
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                results.put(staging.Id, new MatchResult());
            }
            return results;
        }
        
        // Collect all sender emails
        Set<String> emails = new Set<String>();
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            if (String.isNotBlank(staging.From_Address__c)) {
                emails.add(staging.From_Address__c);
            }
        }
        
        // Build cache
        EmailMatchCache cache = buildEmailMatchCache(emails);
        
        // Match each staging record
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            MatchResult match = matchEmail(staging.From_Address__c, cache);
            results.put(staging.Id, match);
        }
        
        return results;
    }
    
    /**
     * Match email staging records with FULL matching (From, To, CC)
     * Returns multiple matches per staging record for creating multiple EmailMessageRelations
     * @param stagingRecords List of email staging records to match
     * @return Map of staging record ID to MultiMatchResult
     */
    public static Map<Id, MultiMatchResult> matchEmailStagingRecordsMulti(List<AI_Workspace_Staging__c> stagingRecords) {
        return matchEmailStagingRecordsMulti(stagingRecords, null);
    }
    
    /**
     * Match email staging records with FULL matching (From, To, CC)
     * Returns multiple matches per staging record for creating multiple EmailMessageRelations
     * Excludes the connected account email from matching (V2-8XXX)
     * @param stagingRecords List of email staging records to match
     * @param connectedAccountEmail The connected account email to exclude from matching (e.g., piyush2@gptfy.dev)
     * @return Map of staging record ID to MultiMatchResult
     */
    public static Map<Id, MultiMatchResult> matchEmailStagingRecordsMulti(List<AI_Workspace_Staging__c> stagingRecords, String connectedAccountEmail) {
        Map<Id, MultiMatchResult> results = new Map<Id, MultiMatchResult>();
        
        if (stagingRecords == null || stagingRecords.isEmpty()) {
            return results;
        }
        
        // Check if matching is enabled
        if (!isMatchingEnabled()) {
            // Return empty results for all records
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                results.put(staging.Id, new MultiMatchResult());
            }
            return results;
        }
        
        // Normalize connected account email for exclusion
        String excludeEmail = null;
        if (String.isNotBlank(connectedAccountEmail)) {
            excludeEmail = connectedAccountEmail.toLowerCase().trim();
        }
        
        // Collect ALL emails from From, To, CC (excluding connected account email)
        Set<String> allEmails = new Set<String>();
        Map<Id, String> stagingToFromEmail = new Map<Id, String>();
        Map<Id, Set<String>> stagingToAllEmails = new Map<Id, Set<String>>();
        
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            Set<String> emailsForThisRecord = new Set<String>();
            
            // From address (primary)
            if (String.isNotBlank(staging.From_Address__c)) {
                String fromEmail = staging.From_Address__c.toLowerCase().trim();
                stagingToFromEmail.put(staging.Id, fromEmail);
                // Only add to matching if not the connected account email
                if (excludeEmail == null || !fromEmail.equals(excludeEmail)) {
                    emailsForThisRecord.add(fromEmail);
                    allEmails.add(fromEmail);
                }
            }
            
            // To addresses
            if (String.isNotBlank(staging.To_Address__c)) {
                for (String toEmail : parseEmailList(staging.To_Address__c)) {
                    String normalizedToEmail = toEmail.toLowerCase().trim();
                    // Only add to matching if not the connected account email
                    if (excludeEmail == null || !normalizedToEmail.equals(excludeEmail)) {
                        emailsForThisRecord.add(normalizedToEmail);
                        allEmails.add(normalizedToEmail);
                    }
                }
            }
            
            // CC addresses
            if (String.isNotBlank(staging.Cc_Address__c)) {
                for (String ccEmail : parseEmailList(staging.Cc_Address__c)) {
                    String normalizedCcEmail = ccEmail.toLowerCase().trim();
                    // Only add to matching if not the connected account email
                    if (excludeEmail == null || !normalizedCcEmail.equals(excludeEmail)) {
                        emailsForThisRecord.add(normalizedCcEmail);
                        allEmails.add(normalizedCcEmail);
                    }
                }
            }
            stagingToAllEmails.put(staging.Id, emailsForThisRecord);
        }
        
        
        // Build cache for all emails
        EmailMatchCache cache = buildEmailMatchCache(allEmails);
        
        // Match each staging record
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            MultiMatchResult multiResult = new MultiMatchResult();
            
            // Track matched IDs to avoid duplicates
            Set<Id> matchedIds = new Set<Id>();
            MatchResult bestMatch = null;
            
            // Match ALL emails (From, To, CC) and find the best match
            Set<String> emailsForRecord = stagingToAllEmails.get(staging.Id);
            String fromEmail = stagingToFromEmail.get(staging.Id);
            
            if (emailsForRecord != null) {
                for (String email : emailsForRecord) {
                    MatchResult emailMatch = matchEmail(email, cache);
                    
                    if (emailMatch.isMatched) {
                        emailMatch.matchedEmail = email;
                        
                        // Check if this ID was already matched
                        Id matchedId = emailMatch.leadId != null ? emailMatch.leadId : emailMatch.contactId;
                        
                        if (matchedId != null && !matchedIds.contains(matchedId)) {
                            multiResult.allMatches.add(emailMatch);
                            multiResult.hasAnyMatch = true;
                            matchedIds.add(matchedId);
                            
                            // Determine best match: Prefer FROM address, then lowest precedence level
                            if (bestMatch == null) {
                                bestMatch = emailMatch;
                            } else if (email == fromEmail) {
                                // FROM address always wins as primary
                                bestMatch = emailMatch;
                            } else if (bestMatch.matchedEmail != fromEmail && emailMatch.precedenceLevel < bestMatch.precedenceLevel) {
                                // If current best is not FROM, use lowest precedence
                                bestMatch = emailMatch;
                            }
                        }
                    }
                }
            }
            
            // Set primary match to the best match found
            if (bestMatch != null) {
                multiResult.primaryMatch = bestMatch;
                multiResult.hasPrimaryMatch = true;
            }
            
            // Continue matching remaining emails for secondary matches (already done above)
            // This code block is now redundant but kept for compatibility
            if (emailsForRecord != null) {
                for (String email : emailsForRecord) {
                    // Skip if already processed
                    if (email == fromEmail && multiResult.hasPrimaryMatch) continue;
                    
                    MatchResult match = matchEmail(email, cache);
                    if (match.isMatched) {
                        // Check if this ID was already matched
                        Id matchedId = match.leadId != null ? match.leadId : match.contactId;
                        
                        if (matchedId != null && !matchedIds.contains(matchedId)) {
                            match.matchedEmail = email;
                            multiResult.allMatches.add(match);
                            multiResult.hasAnyMatch = true;
                            matchedIds.add(matchedId);
                        }
                    }
                }
            }
            
            results.put(staging.Id, multiResult);
        }
        
        return results;
    }
    
    /**
     * Parse a comma/semicolon separated email list
     * @param emailList String containing multiple emails
     * @return Set of normalized email addresses
     */
    private static Set<String> parseEmailList(String emailList) {
        Set<String> emails = new Set<String>();
        
        if (String.isBlank(emailList)) {
            return emails;
        }
        
        // Split by comma, semicolon, or newline
        List<String> parts = emailList.split('[,;\\n]');
        
        for (String part : parts) {
            String email = extractEmailFromField(part.trim());
            if (String.isNotBlank(email)) {
                emails.add(email.toLowerCase());
            }
        }
        
        return emails;
    }
    
    /**
     * Match calendar staging records in bulk (returns single best match)
     * @deprecated Use matchCalendarStagingRecordsMulti for full attendee matching
     * Matches based on attendee emails (excluding current user/organizer)
     * Prioritizes Lead/Contact matches over User matches
     * @param stagingRecords List of calendar staging records to match
     * @return Map of staging record ID to MatchResult
     */
    public static Map<Id, MatchResult> matchCalendarStagingRecords(List<AI_Workspace_Staging__c> stagingRecords) {
        Map<Id, MatchResult> results = new Map<Id, MatchResult>();
        
        if (stagingRecords == null || stagingRecords.isEmpty()) {
            return results;
        }
        
        // Check if matching is enabled
        if (!isMatchingEnabled()) {
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                results.put(staging.Id, new MatchResult());
            }
            return results;
        }
        
        // Get current user's email to exclude from matching
        String currentUserEmail = UserInfo.getUserEmail();
        if (String.isNotBlank(currentUserEmail)) {
            currentUserEmail = currentUserEmail.toLowerCase();
        }
        
        // Collect all emails from attendees (excluding organizer/current user)
        Set<String> allEmails = new Set<String>();
        Map<Id, Set<String>> stagingToEmails = new Map<Id, Set<String>>();
        Map<Id, String> stagingToOrganizerEmail = new Map<Id, String>();
        
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            Set<String> eventEmails = new Set<String>();
            
            // Extract organizer email - INCLUDE in matching
            String organizerEmail = extractEmailFromField(staging.Organizer__c);
            if (String.isNotBlank(organizerEmail)) {
                String normalizedOrgEmail = organizerEmail.toLowerCase();
                stagingToOrganizerEmail.put(staging.Id, normalizedOrgEmail);
                // Add organizer email to matching (match against Lead/Contact)
                eventEmails.add(normalizedOrgEmail);
                allEmails.add(normalizedOrgEmail);
            }
            
            // Extract attendee emails (primary for matching)
            if (String.isNotBlank(staging.Attendees__c)) {
                for (String attendee : staging.Attendees__c.split('\n')) {
                    String email = extractEmailFromField(attendee);
                    if (String.isNotBlank(email)) {
                        String normalizedEmail = email.toLowerCase();
                        // Include ALL emails - match against Lead/Contact
                        eventEmails.add(normalizedEmail);
                        allEmails.add(normalizedEmail);
                    }
                }
            }
            
            stagingToEmails.put(staging.Id, eventEmails);
        }
        
        // Build cache
        EmailMatchCache cache = buildEmailMatchCache(allEmails);
        
        // Match each staging record - find the best match among attendees
        // Prioritize Lead/Contact over User matches
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            Set<String> eventEmails = stagingToEmails.get(staging.Id);
            MatchResult bestMatch = new MatchResult();
            
            if (eventEmails != null && !eventEmails.isEmpty()) {
                for (String email : eventEmails) {
                    MatchResult match = matchEmail(email, cache);
                    // Keep the best match (lowest precedence level, or first match if same level)
                    if (match.isMatched) {
                        if (!bestMatch.isMatched || match.precedenceLevel < bestMatch.precedenceLevel) {
                            bestMatch = match;
                        }
                    }
                }
            }
            
            results.put(staging.Id, bestMatch);
        }
        
        return results;
    }
    
    /**
     * Match calendar staging records with FULL matching for ALL attendees
     * Returns multiple matches per staging record for creating EventRelations
     * @param stagingRecords List of calendar staging records to match
     * @return Map of staging record ID to MultiMatchResult
     */
    public static Map<Id, MultiMatchResult> matchCalendarStagingRecordsMulti(List<AI_Workspace_Staging__c> stagingRecords) {
        return matchCalendarStagingRecordsMulti(stagingRecords, null);
    }
    
    /**
     * Match calendar staging records with FULL matching for ALL attendees
     * Returns multiple matches per staging record for creating EventRelations
     * Excludes the connected account email from matching (V2-8XXX)
     * @param stagingRecords List of calendar staging records to match
     * @param connectedAccountEmail The connected account email to exclude from matching (e.g., piyush2@gptfy.dev)
     * @return Map of staging record ID to MultiMatchResult
     */
    public static Map<Id, MultiMatchResult> matchCalendarStagingRecordsMulti(List<AI_Workspace_Staging__c> stagingRecords, String connectedAccountEmail) {
        Map<Id, MultiMatchResult> results = new Map<Id, MultiMatchResult>();
        
        if (stagingRecords == null || stagingRecords.isEmpty()) {
            return results;
        }
        
        // Check if matching is enabled
        if (!isMatchingEnabled()) {
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                results.put(staging.Id, new MultiMatchResult());
            }
            return results;
        }
        
        // Normalize connected account email for exclusion
        String excludeEmail = null;
        if (String.isNotBlank(connectedAccountEmail)) {
            excludeEmail = connectedAccountEmail.toLowerCase().trim();
        }
        
        // Collect all emails from attendees (excluding connected account email)
        Set<String> allEmails = new Set<String>();
        Map<Id, Set<String>> stagingToEmails = new Map<Id, Set<String>>();
        Map<Id, String> stagingToOrganizerEmail = new Map<Id, String>();
        
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            Set<String> eventEmails = new Set<String>();
            
            // Extract organizer email - INCLUDE in matching only if not the connected account
            String organizerEmail = extractEmailFromField(staging.Organizer__c);
            if (String.isNotBlank(organizerEmail)) {
                String normalizedOrgEmail = organizerEmail.toLowerCase().trim();
                stagingToOrganizerEmail.put(staging.Id, normalizedOrgEmail);
                // Only add to matching if not the connected account email
                if (excludeEmail == null || !normalizedOrgEmail.equals(excludeEmail)) {
                    eventEmails.add(normalizedOrgEmail);
                    allEmails.add(normalizedOrgEmail);
                }
            }
            
            // Extract attendee emails
            if (String.isNotBlank(staging.Attendees__c)) {
                for (String attendee : staging.Attendees__c.split('\n')) {
                    String email = extractEmailFromField(attendee);
                    if (String.isNotBlank(email)) {
                        String normalizedEmail = email.toLowerCase().trim();
                        // Only add to matching if not the connected account email
                        if (excludeEmail == null || !normalizedEmail.equals(excludeEmail)) {
                            eventEmails.add(normalizedEmail);
                            allEmails.add(normalizedEmail);
                        }
                    }
                }
            }
            
            stagingToEmails.put(staging.Id, eventEmails);
        }
        
        // Build cache for all emails
        EmailMatchCache cache = buildEmailMatchCache(allEmails);
        
        // Match each staging record - return ALL matches for ALL attendees
        for (AI_Workspace_Staging__c staging : stagingRecords) {
            MultiMatchResult multiResult = new MultiMatchResult();
            Set<String> eventEmails = stagingToEmails.get(staging.Id);
            
            if (eventEmails != null && !eventEmails.isEmpty()) {
                // Track matched IDs to avoid duplicates
                Set<Id> matchedIds = new Set<Id>();
                MatchResult bestMatch = null;
                
                for (String email : eventEmails) {
                    MatchResult match = matchEmail(email, cache);
                    
                    if (match.isMatched) {
                        // Check if this ID was already matched
                        Id matchedId = match.leadId != null ? match.leadId : match.contactId;
                        
                        if (matchedId != null && !matchedIds.contains(matchedId)) {
                            match.matchedEmail = email;
                            multiResult.allMatches.add(match);
                            multiResult.hasAnyMatch = true;
                            matchedIds.add(matchedId);
                            
                            // Track best match (lowest precedence level)
                            if (bestMatch == null || match.precedenceLevel < bestMatch.precedenceLevel) {
                                bestMatch = match;
                            }
                        }
                    }
                }
                
                // Set primary match to the best match
                if (bestMatch != null) {
                    multiResult.primaryMatch = bestMatch;
                    multiResult.hasPrimaryMatch = true;
                }
            }
            
            results.put(staging.Id, multiResult);
        }
        
        return results;
    }
    
    /**
     * Extract email address from a field that may contain "Name <email>" format
     * @param field Field value that may contain name and email
     * @return Extracted email address or null
     */
    private static String extractEmailFromField(String field) {
        if (String.isBlank(field)) {
            return null;
        }
        
        // Check for "Name <email@domain.com>" format
        if (field.contains('<') && field.contains('>')) {
            Integer startIdx = field.indexOf('<');
            Integer endIdx = field.indexOf('>');
            if (startIdx < endIdx && startIdx >= 0) {
                return field.substring(startIdx + 1, endIdx).trim().toLowerCase();
            }
        }
        
        // If it looks like an email (contains @), return it directly
        if (field.contains('@')) {
            return field.trim().toLowerCase();
        }
        
        return null;
    }
    
    /**
     * Extract domain from email address
     * @param email Email address
     * @return Domain part (e.g., 'example.com' from 'user@example.com')
     */
    private static String extractDomain(String email) {
        if (String.isBlank(email)) return null;
        
        String normalized = email.trim().toLowerCase();
        Integer atIndex = normalized.indexOf('@');
        
        if (atIndex > 0 && atIndex < normalized.length() - 1) {
            return normalized.substring(atIndex + 1);
        }
        
        return null;
    }
    
    /**
     * Check if domain is a public email provider
     * @param domain Domain to check
     * @return true if domain is a public email provider
     */
    private static Boolean isPublicEmailDomain(String domain) {
        if (String.isBlank(domain)) return false;
        
        Set<String> publicDomains = new Set<String>{
            'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 
            'live.com', 'msn.com', 'aol.com', 'icloud.com',
            'mail.com', 'protonmail.com', 'yandex.com', 'zoho.com'
        };
        
        return publicDomains.contains(domain.toLowerCase());
    }
}