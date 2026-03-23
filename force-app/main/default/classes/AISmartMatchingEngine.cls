/**
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AISmartMatchingEngine {
    
    // Confidence thresholds
    private static final Integer CONFIDENCE_EXACT_EMAIL = 95;
    private static final Integer CONFIDENCE_DOMAIN_MATCH = 80;
    
    public class MatchResult implements Comparable {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String objectType;
        @AuraEnabled public String email;
        @AuraEnabled public String details;
        @AuraEnabled public String iconName;
        @AuraEnabled public Integer confidence;
        @AuraEnabled public Boolean shouldPreSelect; // Flag for auto-selection in modal
        
        public MatchResult(Id id, String name, String type, String email, String details, String icon, Integer conf) {
            this.recordId = id;
            this.recordName = name;
            this.objectType = type;
            this.email = email;
            this.details = details;
            this.iconName = icon;
            this.confidence = conf;
            this.shouldPreSelect = false; // Default to false
        }

        public Integer compareTo(Object compareTo) {
            MatchResult other = (MatchResult) compareTo;
            // Sort descending by confidence
            if (this.confidence > other.confidence) return -1;
            if (this.confidence < other.confidence) return 1;
            return 0;
        }
    }
    
    /**
     * Find matches for a given email with precedence-based pre-selection
     * 
     * MATCHING APPROACH:
     * - Exact email match for Contacts and Leads only (respects precedence)
     * - Domain-based Account matching (independent, always runs)
     */
    public static List<MatchResult> findMatches(String senderEmail, String senderName, String subject) {
        return findMatches(senderEmail, senderName, subject, null);
    }
    
    /**
     * Find matches for a given email with precedence-based pre-selection
     * Optionally excludes matches for the connected account email
     * 
     * MATCHING APPROACH:
     * - Exact email match for Contacts and Leads only (respects precedence)
     * - Domain-based Account matching (independent, always runs)
     * 
     * @param senderEmail The email address to find matches for
     * @param senderName The sender's display name
     * @param subject The email/event subject
     * @param connectedAccountEmail Optional email address of the connected provider account to exclude from matching
     */
    public static List<MatchResult> findMatches(String senderEmail, String senderName, String subject, String connectedAccountEmail) {
        List<MatchResult> matches = new List<MatchResult>();
        Set<Id> matchedIds = new Set<Id>();
        
        try {
            if (String.isBlank(senderEmail)) return matches;
            
            // Normalize connected account email for comparison
            String normalizedConnectedEmail = null;
            if (String.isNotBlank(connectedAccountEmail)) {
                normalizedConnectedEmail = connectedAccountEmail.toLowerCase().trim();
            }
            
            // Skip matching if this email is the connected account email
            String normalizedSenderEmail = senderEmail.toLowerCase().trim();
            if (normalizedConnectedEmail != null && normalizedSenderEmail.equals(normalizedConnectedEmail)) {
                return matches;
            }
            
            // Get precedence configuration to determine which object types to search
            Map<Integer, List<String>> precedenceConfig = getPrecedenceConfig();
            Set<String> allowedObjectTypes = getAllowedObjectTypes(precedenceConfig);
            
            // Exact Email Match (Contact/Lead only) - respects precedence
            // V2-7889: Pass connectedAccountEmail to exclude matches with that email
            findEmailMatches(senderEmail, matches, matchedIds, allowedObjectTypes, normalizedConnectedEmail);
            
            // Domain-based Account matching (INDEPENDENT - always runs)
            findAccountMatchesByDomain(senderEmail, matches, matchedIds);
            
            // Apply precedence-based pre-selection (only for Contact/Lead)
            applyPrecedencePreSelection(matches, senderEmail);
            
            // Sort by confidence desc
            matches.sort();
            
        } catch (Exception e) {
            //ignore
            // Return empty list on error rather than throwing exception
        }
        
        return matches;
    }
    
    /**
     * Get all allowed object types from precedence configuration
     */
    private static Set<String> getAllowedObjectTypes(Map<Integer, List<String>> precedenceConfig) {
        Set<String> allowedTypes = new Set<String>();
        
        for (List<String> objectTypes : precedenceConfig.values()) {
            allowedTypes.addAll(objectTypes);
        }
        
        return allowedTypes;
    }
    
    /**
     * Apply precedence rules to mark which matches should be pre-selected
     * Uses the same precedence logic as AIStagingMatcherService for consistency
     */
    private static void applyPrecedencePreSelection(List<MatchResult> matches, String email) {
        if (matches.isEmpty()) return;
        
        // Get precedence configuration
        Map<Integer, List<String>> precedenceConfig = getPrecedenceConfig();
        
        // Build maps of matched IDs by object type
        Map<String, List<MatchResult>> matchesByType = new Map<String, List<MatchResult>>{
            'Contact' => new List<MatchResult>(),
            'Lead' => new List<MatchResult>()
        };
        
        for (MatchResult match : matches) {
            if (matchesByType.containsKey(match.objectType)) {
                matchesByType.get(match.objectType).add(match);
            }
        }
        
        // Get sorted precedence levels
        List<Integer> levels = new List<Integer>(precedenceConfig.keySet());
        levels.sort();
        
        // Try each precedence level in order
        for (Integer level : levels) {
            List<String> objectTypes = precedenceConfig.get(level);
            
            // Check if ALL object types at this level have a match
            Boolean allMatch = true;
            List<MatchResult> matchesToPreSelect = new List<MatchResult>();
            
            for (String objectType : objectTypes) {
                List<MatchResult> typeMatches = matchesByType.get(objectType);
                if (typeMatches != null && !typeMatches.isEmpty()) {
                    // Take the first match (highest confidence due to sorting)
                    matchesToPreSelect.add(typeMatches[0]);
                } else {
                    allMatch = false;
                    break;
                }
            }
            
            // If ALL objects at this level matched, mark them for pre-selection
            if (allMatch && !matchesToPreSelect.isEmpty()) {
                for (MatchResult match : matchesToPreSelect) {
                    match.shouldPreSelect = true;
                }
                return; // Stop at first matching precedence level
            }
        }
    }
    
    /**
     * Get precedence configuration from AI_Workspace_Sync_Settings__c
     * Same logic as AIStagingMatcherService for consistency
     */
    private static Map<Integer, List<String>> getPrecedenceConfig() {
        Map<Integer, List<String>> config = new Map<Integer, List<String>>();
        
        try {
            AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
            
            if (settings == null || String.isBlank(settings.Sync_Precedence__c)) {
                // Default config: Try both, then Lead, then Contact
                config.put(1, new List<String>{ 'Lead', 'Contact' });
                config.put(2, new List<String>{ 'Lead' });
                config.put(3, new List<String>{ 'Contact' });
                return config;
            }
            
            String jsonConfig = settings.Sync_Precedence__c;
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonConfig);
            
            for (String key : parsed.keySet()) {
                Integer level = Integer.valueOf(key);
                List<Object> objectList = (List<Object>) parsed.get(key);
                List<String> objectTypes = new List<String>();
                for (Object obj : objectList) {
                    objectTypes.add((String) obj);
                }
                config.put(level, objectTypes);
            }
        } catch (Exception e) {
            // Return default config on error
            config.put(1, new List<String>{ 'Lead', 'Contact' });
            config.put(2, new List<String>{ 'Lead' });
            config.put(3, new List<String>{ 'Contact' });
        }
        
        return config;
    }
    
    private static void findEmailMatches(String email, List<MatchResult> matches, Set<Id> matchedIds, Set<String> allowedObjectTypes, String normalizedConnectedEmail) {
        try {
            // Search Contacts - only if Contact is in precedence configuration
            if (allowedObjectTypes.contains('Contact')) {
                try {
                    for (Contact c : [SELECT Id, Name, Account.Name, Email FROM Contact WHERE Email = :email WITH USER_MODE LIMIT 5]) {
                        if (!matchedIds.contains(c.Id)) {
                            // V2-7889: Exclude matches where Contact email equals connected account email
                            if (normalizedConnectedEmail != null && String.isNotBlank(c.Email)) {
                                String normalizedContactEmail = c.Email.toLowerCase().trim();
                                if (normalizedContactEmail.equals(normalizedConnectedEmail)) {
                                    continue; // Skip this Contact
                                }
                            }
                            
                            matches.add(new MatchResult(
                                c.Id,
                                c.Name,
                                'Contact',
                                c.Email,
                                'Exact email match • ' + (c.Account.Name != null ? c.Account.Name : ''),
                                'standard:contact',
                                CONFIDENCE_EXACT_EMAIL
                            ));
                            matchedIds.add(c.Id);
                        }
                    }
                } catch (Exception contactEx) {
                    //ignore
                }
            }

            // Search Leads - only if Lead is in precedence configuration
            if (allowedObjectTypes.contains('Lead')) {
                try {
                    for (Lead l : [SELECT Id, Name, Company, Email FROM Lead WHERE Email = :email AND IsConverted = false WITH USER_MODE LIMIT 5]) {
                        if (!matchedIds.contains(l.Id)) {
                            // V2-7889: Exclude matches where Lead email equals connected account email
                            if (normalizedConnectedEmail != null && String.isNotBlank(l.Email)) {
                                String normalizedLeadEmail = l.Email.toLowerCase().trim();
                                if (normalizedLeadEmail.equals(normalizedConnectedEmail)) {
                                    continue; // Skip this Lead
                                }
                            }
                            
                            matches.add(new MatchResult(
                                l.Id,
                                l.Name,
                                'Lead',
                                l.Email,
                                'Exact email match • ' + (l.Company != null ? l.Company : ''),
                                'standard:lead',
                                CONFIDENCE_EXACT_EMAIL
                            ));
                            matchedIds.add(l.Id);
                        }
                    }
                } catch (Exception leadEx) {
                    //ignore
                }
            }
        } catch (Exception e) {
            //ignore
        }
    }
    
    /**
     * Find Account matches by domain (INDEPENDENT feature - always runs)
     * Extracts domain from email and matches against Account Website field (contains match)
     * This feature is independent of precedence configuration
     */
    private static void findAccountMatchesByDomain(String email, List<MatchResult> matches, Set<Id> matchedIds) {
        try {
            if (String.isBlank(email)) {
                return;
            }
            
            // Extract domain from email
            String domain = extractDomain(email);
            if (String.isBlank(domain)) return;
            
            
            // Query Accounts where Website contains the domain
            String likePattern = '%' + domain + '%';
            
            try {
                // Check FLS for Account fields
                if (!Schema.sObjectType.Account.fields.Name.isAccessible() ||
                    !Schema.sObjectType.Account.fields.Website.isAccessible()) {
                    return;
                }
                
                List<Account> accountList = [
                    SELECT Id, Name, Website 
                    FROM Account 
                    WHERE Website LIKE :likePattern 
                    LIMIT 10
                ];
                
                
                for (Account acc : accountList) {
                    if (!matchedIds.contains(acc.Id)) {
                        matches.add(new MatchResult(
                            acc.Id,
                            acc.Name,
                            'Account',
                            email,
                            'Domain match: ' + domain + ' • ' + (acc.Website != null ? acc.Website : ''),
                            'standard:account',
                            CONFIDENCE_DOMAIN_MATCH
                        ));
                        matchedIds.add(acc.Id);
                    }
                }
            } catch (Exception accEx) {
                //ignore
            }
        } catch (Exception e) {
            //ignore
        }
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
}