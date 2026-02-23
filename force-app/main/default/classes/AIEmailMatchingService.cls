/**
 * @deprecated Use QuickMatchService instead - this class has SOQL-in-loop issues.
 *
 * AI-Powered Email Matching Service
 * Works with any email provider (Exchange, Gmail, etc.)
 * Intelligently matches emails to Salesforce records using AI entity extraction
 *
 * WARNING: This class contains SOQL queries inside loops in:
 * - matchAccountByDomain()
 * - matchOpportunity()
 * - matchCase()
 * These can hit governor limits with large batches. QuickMatchService implements
 * a fully bulkified approach that pre-loads all data in 5 queries.
 */
public class AIEmailMatchingService {

    // Confidence thresholds
    private static final Integer HIGH_CONFIDENCE = 80;
    private static final Integer MEDIUM_CONFIDENCE = 60;
    private static final Integer LOW_CONFIDENCE = 40;

    // Maximum emails to process in single batch (per governor limits analysis)
    public static final Integer MAX_BATCH_SIZE = 50;

    /**
     * Match a single email to Salesforce records
     */
    public static MatchResult matchEmail(
        Map<String, Object> emailData,
        Id contextRecordId
    ) {
        return matchEmailInternal(emailData, contextRecordId, null);
    }

    /**
     * Batch match multiple emails (optimized with bulk queries)
     */
    public static List<MatchResult> matchEmailsBatch(
        List<Map<String, Object>> emails,
        Id contextRecordId
    ) {
        if (emails == null || emails.isEmpty()) {
            return new List<MatchResult>();
        }

        // Enforce batch size limit
        if (emails.size() > MAX_BATCH_SIZE) {
            throw new EmailMatchingException(
                'Batch size exceeds maximum of ' + MAX_BATCH_SIZE + ' emails. ' +
                'Please process in smaller batches.'
            );
        }

        // Build bulk cache for optimized queries
        BulkMatchCache cache = buildBulkMatchCache(emails);

        // Process each email with cached data
        List<MatchResult> results = new List<MatchResult>();
        
        for (Integer i = 0; i < emails.size(); i++) {
            Map<String, Object> email = emails[i];
            MatchResult result = matchEmailWithCache(email, contextRecordId, cache);
            results.add(result);
        }

        return results;
    }

    // ========================================================================
    // INTERNAL MATCHING LOGIC
    // ========================================================================

    private static MatchResult matchEmailInternal(
        Map<String, Object> emailData,
        Id contextRecordId,
        BulkMatchCache cache
    ) {
        MatchResult result = new MatchResult();
        result.emailSubject = (String) emailData.get('subject');
        result.fromAddress = getFromAddress(emailData);

        // TIER 1: Direct Contact match by email
        matchContactByEmail(result.fromAddress, result, cache);

        // TIER 2: If no Contact, try Lead
        if (result.contactId == null) {
            matchLeadByEmail(result.fromAddress, result, cache);
        }

        // TIER 2.5: Auto-create Lead checks moved to caller (batch/single methods)
        // to avoid DML in loops.

        // TIER 3: AI entity extraction (only if GPTfy available)
        AIEntities entities = extractEntitiesWithAI(emailData);

        // TIER 4: Match Account (by AI entities or domain)
        if (result.accountId == null) {
            matchAccount(result.fromAddress, entities, result, cache);
        }

        // TIER 5: Match Opportunity (if Account found)
        if (result.accountId != null) {
            matchOpportunity(entities, result, contextRecordId);
        }

        // TIER 6: Match Case (if Contact found or case keywords detected)
        if (result.contactId != null || !entities.caseKeywords.isEmpty()) {
            matchCase(entities, result, contextRecordId);
        }

        // TIER 7: Context fallback
        applyContextFallback(result, contextRecordId);

        // Mark urgent if AI detected
        result.isUrgent = (entities.urgency == 'high');

        // Calculate final confidence
        calculateFinalConfidence(result);

        return result;
    }

    private static MatchResult matchEmailWithCache(
        Map<String, Object> emailData,
        Id contextRecordId,
        BulkMatchCache cache
    ) {
        return matchEmailInternal(emailData, contextRecordId, cache);
    }

    // ========================================================================
    // TIER 1: DIRECT CONTACT MATCH (Highest Confidence: 95-100%)
    // ========================================================================

    private static void matchContactByEmail(
        String fromAddress,
        MatchResult result,
        BulkMatchCache cache
    ) {
        if (String.isBlank(fromAddress)) return;

        try {
            Contact c = null;

            // Use cache if available
            if (cache != null && cache.emailToContact.containsKey(fromAddress.toLowerCase())) {
                c = cache.emailToContact.get(fromAddress.toLowerCase());
            } else {
                // Direct query
                List<Contact> contacts = [
                    SELECT Id, Name, Email, AccountId, Account.Name
                    FROM Contact
                    WHERE Email = :fromAddress
                    LIMIT 1
                ];
                if (!contacts.isEmpty()) {
                    c = contacts[0];
                }
            }

            if (c != null) {
                result.contactId = c.Id;
                result.contactName = c.Name;
                result.contactConfidence = 100;
                result.matches.add('Contact: ' + c.Name + ' (email match)');

                // Auto-link to Account if available
                if (c.AccountId != null) {
                    result.accountId = c.AccountId;
                    result.accountName = c.Account != null ? c.Account.Name : null;
                    result.accountConfidence = 100;
                    if (result.accountName != null) {
                        result.matches.add('Account: ' + result.accountName + ' (via Contact)');
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Contact match error: ' + e.getMessage());
        }
    }

    // ========================================================================
    // TIER 2: LEAD MATCH (If no Contact found)
    // ========================================================================

    private static void matchLeadByEmail(
        String fromAddress,
        MatchResult result,
        BulkMatchCache cache
    ) {
        if (String.isBlank(fromAddress)) return;

        try {
            Lead l = null;

            // Use cache if available
            if (cache != null && cache.emailToLead.containsKey(fromAddress.toLowerCase())) {
                l = cache.emailToLead.get(fromAddress.toLowerCase());
            } else {
                // Direct query
                List<Lead> leads = [
                    SELECT Id, Name, Email, Company
                    FROM Lead
                    WHERE Email = :fromAddress
                    AND IsConverted = false
                    LIMIT 1
                ];
                if (!leads.isEmpty()) {
                    l = leads[0];
                }
            }

            if (l != null) {
                result.leadId = l.Id;
                result.leadName = l.Name;
                result.leadConfidence = 100;
                result.matches.add('Lead: ' + l.Name + ' (email match)');
            }
        } catch (Exception e) {
            System.debug('Lead match error: ' + e.getMessage());
        }
    }

    // ========================================================================
    // TIER 3: AI ENTITY EXTRACTION
    // ========================================================================

    /**
     * AI entity extraction placeholder.
     * AI-powered entity extraction is available as an optional enhancement.
     * Currently returns empty entities - matching uses email/domain-based logic.
     */
    private static AIEntities extractEntitiesWithAI(Map<String, Object> emailData) {
        // AI entity extraction is optional - return empty entities
        // Matching will use email address and domain-based logic
        return new AIEntities();
    }

    // ========================================================================
    // TIER 4: ACCOUNT MATCHING (AI + Domain)
    // ========================================================================

    private static void matchAccount(
        String fromAddress,
        AIEntities entities,
        MatchResult result,
        BulkMatchCache cache
    ) {
        // Try AI entity match first
        if (!entities.accountNames.isEmpty() && result.accountId == null) {
            matchAccountByName(entities.accountNames, result);
        }

        // Try domain match if still no Account
        if (result.accountId == null && String.isNotBlank(fromAddress)) {
            matchAccountByDomain(fromAddress, result, cache);
        }
    }

    private static void matchAccountByName(List<String> accountNames, MatchResult result) {
        try {
            for (String accountName : accountNames) {
                if (String.isBlank(accountName)) continue;

                String likePattern = '%' + accountName + '%';
                List<Account> accounts = [
                    SELECT Id, Name
                    FROM Account
                    WHERE Name LIKE :likePattern
                    LIMIT 1
                ];

                if (!accounts.isEmpty()) {
                    Account a = accounts[0];
                    result.accountId = a.Id;
                    result.accountName = a.Name;
                    result.accountConfidence = 85; // AI match
                    result.matches.add('Account: ' + a.Name + ' (AI matched from content)');
                    return;
                }
            }
        } catch (Exception e) {
            System.debug('Account name match error: ' + e.getMessage());
        }
    }

    private static void matchAccountByDomain(
        String emailAddress,
        MatchResult result,
        BulkMatchCache cache
    ) {
        String domain = extractDomain(emailAddress);
        if (String.isBlank(domain)) return;

        try {
            Account a = null;

            // Use cache if available
            if (cache != null && cache.domainToAccount.containsKey(domain)) {
                a = cache.domainToAccount.get(domain);
            } else {
                // Direct query
                String likePattern = '%' + domain + '%';
                List<Account> accounts = [
                    SELECT Id, Name, Website
                    FROM Account
                    WHERE Website LIKE :likePattern
                    LIMIT 1
                ];
                if (!accounts.isEmpty()) {
                    a = accounts[0];
                }
            }

            if (a != null) {
                result.accountId = a.Id;
                result.accountName = a.Name;
                result.accountConfidence = 80; // Domain match
                result.matches.add('Account: ' + a.Name + ' (domain match: ' + domain + ')');
            }
        } catch (Exception e) {
            System.debug('Account domain match error: ' + e.getMessage());
        }
    }

    // ========================================================================
    // TIER 5: OPPORTUNITY MATCHING
    // ========================================================================

    private static void matchOpportunity(
        AIEntities entities,
        MatchResult result,
        Id contextRecordId
    ) {
        if (result.accountId == null) return;

        try {
            // Build query
            String queryStr = 'SELECT Id, Name, StageName, CloseDate ' +
                'FROM Opportunity ' +
                'WHERE AccountId = :result.accountId ' +
                'AND IsClosed = false ';

            // Prioritize context Opportunity if applicable
            String contextObjectType = contextRecordId != null ?
                String.valueOf(contextRecordId.getSObjectType()) : null;

            if (contextObjectType == 'Opportunity') {
                queryStr += 'AND Id = :contextRecordId ';
            }

            queryStr += 'ORDER BY CloseDate ASC LIMIT 1';

            List<Opportunity> opps = Database.query(queryStr);

            if (!opps.isEmpty()) {
                Opportunity opp = opps[0];

                // Calculate confidence
                Integer oppConfidence = 70; // Base

                if (!entities.opportunityKeywords.isEmpty()) {
                    oppConfidence = 85; // Keywords detected
                }

                if (contextObjectType == 'Opportunity' && contextRecordId == opp.Id) {
                    oppConfidence = 90; // Context match
                }

                result.opportunityId = opp.Id;
                result.opportunityName = opp.Name;
                result.opportunityConfidence = oppConfidence;
                result.matches.add('Opportunity: ' + opp.Name + ' (stage: ' + opp.StageName + ')');
            }
        } catch (Exception e) {
            System.debug('Opportunity match error: ' + e.getMessage());
        }
    }

    // ========================================================================
    // TIER 6: CASE MATCHING
    // ========================================================================

    private static void matchCase(
        AIEntities entities,
        MatchResult result,
        Id contextRecordId
    ) {
        try {
            String queryStr = 'SELECT Id, CaseNumber, Subject, Priority ' +
                'FROM Case ' +
                'WHERE IsClosed = false ';

            if (result.contactId != null) {
                queryStr += 'AND ContactId = :result.contactId ';
            }

            String contextObjectType = contextRecordId != null ?
                String.valueOf(contextRecordId.getSObjectType()) : null;

            if (contextObjectType == 'Case') {
                queryStr += 'AND Id = :contextRecordId ';
            }

            queryStr += 'ORDER BY CreatedDate DESC LIMIT 1';

            List<Case> cases = Database.query(queryStr);

            if (!cases.isEmpty()) {
                Case c = cases[0];

                // Calculate confidence
                Integer caseConfidence = 70; // Base

                if (!entities.caseKeywords.isEmpty()) {
                    caseConfidence = 85;
                }

                if (entities.urgency == 'high') {
                    caseConfidence = 90;
                }

                if (contextObjectType == 'Case' && contextRecordId == c.Id) {
                    caseConfidence = 95;
                }

                result.caseId = c.Id;
                result.caseNumber = c.CaseNumber;
                result.caseConfidence = caseConfidence;
                result.matches.add('Case: ' + c.CaseNumber + ' (priority: ' + c.Priority + ')');
            }
        } catch (Exception e) {
            System.debug('Case match error: ' + e.getMessage());
        }
    }

    // ========================================================================
    // TIER 7: CONTEXT FALLBACK
    // ========================================================================

    private static void applyContextFallback(MatchResult result, Id contextRecordId) {
        // Only apply if we have no matches yet
        if (!result.matches.isEmpty() || contextRecordId == null) return;

        String contextObjectType = String.valueOf(contextRecordId.getSObjectType());

        result.contextConfidence = 50; // Low confidence
        result.matches.add(contextObjectType + ' (context fallback - manual review recommended)');

        if (contextObjectType == 'Account') {
            result.accountId = contextRecordId;
        } else if (contextObjectType == 'Contact') {
            result.contactId = contextRecordId;
        } else if (contextObjectType == 'Opportunity') {
            result.opportunityId = contextRecordId;
        } else if (contextObjectType == 'Case') {
            result.caseId = contextRecordId;
        }
    }

    // ========================================================================
    // CONFIDENCE CALCULATION
    // ========================================================================

    private static void calculateFinalConfidence(MatchResult result) {
        Integer totalConfidence = 0;
        Integer confidenceCount = 0;

        if (result.contactConfidence > 0) {
            totalConfidence += result.contactConfidence * 3; // Weight x3
            confidenceCount += 3;
        }

        if (result.leadConfidence > 0) {
            totalConfidence += result.leadConfidence * 3;
            confidenceCount += 3;
        }

        if (result.accountConfidence > 0) {
            totalConfidence += result.accountConfidence * 2; // Weight x2
            confidenceCount += 2;
        }

        if (result.opportunityConfidence > 0) {
            totalConfidence += result.opportunityConfidence;
            confidenceCount += 1;
        }

        if (result.caseConfidence > 0) {
            totalConfidence += result.caseConfidence;
            confidenceCount += 1;
        }

        if (result.contextConfidence > 0) {
            totalConfidence += result.contextConfidence;
            confidenceCount += 1;
        }

        if (confidenceCount > 0) {
            result.overallConfidence = totalConfidence / confidenceCount;
        } else {
            result.overallConfidence = 0;
        }

        // Set status
        if (result.overallConfidence >= HIGH_CONFIDENCE) {
            result.status = 'High Confidence';
        } else if (result.overallConfidence >= MEDIUM_CONFIDENCE) {
            result.status = 'Medium Confidence - Review Recommended';
        } else if (result.overallConfidence >= LOW_CONFIDENCE) {
            result.status = 'Low Confidence - Manual Review Required';
        } else {
            result.status = 'No Match - Manual Association Needed';
        }
    }

    // ========================================================================
    // BULK OPTIMIZATION
    // ========================================================================

    private static BulkMatchCache buildBulkMatchCache(List<Map<String, Object>> emails) {
        BulkMatchCache cache = new BulkMatchCache();

        Set<String> allEmails = new Set<String>();
        Set<String> allDomains = new Set<String>();

        for (Map<String, Object> email : emails) {
            String fromAddr = getFromAddress(email);
            if (String.isNotBlank(fromAddr)) {
                allEmails.add(fromAddr.toLowerCase());
                allDomains.add(extractDomain(fromAddr));
            }
        }

        // Bulk query Contacts
        for (Contact c : [
            SELECT Id, Name, Email, AccountId, Account.Name
            FROM Contact
            WHERE Email IN :allEmails
        ]) {
            cache.emailToContact.put(c.Email.toLowerCase(), c);
        }

        // Bulk query Leads
        for (Lead l : [
            SELECT Id, Name, Email, Company
            FROM Lead
            WHERE Email IN :allEmails
            AND IsConverted = false
        ]) {
            cache.emailToLead.put(l.Email.toLowerCase(), l);
        }

        // Bulk query Accounts by domain
        for (Account a : [
            SELECT Id, Name, Website
            FROM Account
            WHERE Website != null
            LIMIT 1000
        ]) {
            for (String domain : allDomains) {
                if (String.isNotBlank(a.Website) &&
                    a.Website.toLowerCase().contains(domain.toLowerCase())) {
                    cache.domainToAccount.put(domain, a);
                }
            }
        }

        return cache;
    }

    // ========================================================================
    // HELPER METHODS
    // ========================================================================

    private static String getFromAddress(Map<String, Object> emailData) {
        // Handle both Exchange/Graph and Gmail formats
        if (emailData.containsKey('fromAddress')) {
            return (String) emailData.get('fromAddress');
        } else if (emailData.containsKey('from')) {
            Map<String, Object> fromObj = (Map<String, Object>) emailData.get('from');
            if (fromObj != null && fromObj.containsKey('emailAddress')) {
                Map<String, Object> emailAddr = (Map<String, Object>) fromObj.get('emailAddress');
                return (String) emailAddr.get('address');
            }
        }
        return null;
    }

    private static String getFromName(Map<String, Object> emailData) {
        if (emailData.containsKey('fromName')) {
            return (String) emailData.get('fromName');
        } else if (emailData.containsKey('from')) {
            Map<String, Object> fromObj = (Map<String, Object>) emailData.get('from');
            if (fromObj != null && fromObj.containsKey('emailAddress')) {
                Map<String, Object> emailAddr = (Map<String, Object>) fromObj.get('emailAddress');
                return (String) emailAddr.get('name');
            }
        }
        return null;
    }

    private static String getBodyText(Map<String, Object> emailData) {
        if (emailData.containsKey('bodyText')) {
            return (String) emailData.get('bodyText');
        } else if (emailData.containsKey('body')) {
            Map<String, Object> body = (Map<String, Object>) emailData.get('body');
            if (body != null) {
                String content = (String) body.get('content');
                String contentType = (String) body.get('contentType');
                if (contentType == 'html') {
                    // Strip HTML for AI processing
                    return AIExchangeEmailHelper.stripHtmlAdvanced(content);
                }
                return content;
            }
        }
        return null;
    }

    private static String extractDomain(String email) {
        if (String.isBlank(email)) return null;
        Integer atIndex = email.indexOf('@');
        if (atIndex == -1) return null;
        return email.substring(atIndex + 1).toLowerCase();
    }

    // ========================================================================
    // INNER CLASSES
    // ========================================================================

    public class MatchResult {
        @AuraEnabled public String emailSubject { get; set; }
        @AuraEnabled public String fromAddress { get; set; }

        // Matched record IDs
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Id leadId { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public Id caseId { get; set; }

        // Matched record names
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public String leadName { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String opportunityName { get; set; }
        @AuraEnabled public String caseNumber { get; set; }

        // Confidence scores (0-100)
        @AuraEnabled public Integer contactConfidence { get; set; }
        @AuraEnabled public Integer leadConfidence { get; set; }
        @AuraEnabled public Integer accountConfidence { get; set; }
        @AuraEnabled public Integer opportunityConfidence { get; set; }
        @AuraEnabled public Integer caseConfidence { get; set; }
        @AuraEnabled public Integer contextConfidence { get; set; }
        @AuraEnabled public Integer overallConfidence { get; set; }

        // Match details
        @AuraEnabled public List<String> matches { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean isUrgent { get; set; }

        public MatchResult() {
            this.matches = new List<String>();
            this.contactConfidence = 0;
            this.leadConfidence = 0;
            this.accountConfidence = 0;
            this.opportunityConfidence = 0;
            this.caseConfidence = 0;
            this.contextConfidence = 0;
            this.overallConfidence = 0;
            this.isUrgent = false;
        }
    }

    private class AIEntities {
        public List<String> accountNames = new List<String>();
        public List<String> contactNames = new List<String>();
        public List<String> opportunityKeywords = new List<String>();
        public List<String> caseKeywords = new List<String>();
        public List<String> leadKeywords = new List<String>();
        public String sentiment;
        public String urgency;
    }

    private class BulkMatchCache {
        public Map<String, Contact> emailToContact = new Map<String, Contact>();
        public Map<String, Lead> emailToLead = new Map<String, Lead>();
        public Map<String, Account> domainToAccount = new Map<String, Account>();
    }

    public class EmailMatchingException extends Exception {}
}