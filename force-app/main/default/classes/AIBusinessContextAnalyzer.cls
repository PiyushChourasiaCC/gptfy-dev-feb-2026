/**
 * @description Analyzes business context to intelligently detect Salesforce objects
 *              and determine data context mapping based on user intent
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 03-04-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
public with sharing class AIBusinessContextAnalyzer {
    
    private static final String LOG_PREFIX = '[AIBusinessContextAnalyzer]';
    
    /**
     * Wrapper class for analysis results
     */
    public class AnalysisResult {
        @AuraEnabled public List<String> detectedObjects { get; set; }
        @AuraEnabled public List<String> priorityChildObjects { get; set; }
        @AuraEnabled public Boolean hasExplicitObjectReferences { get; set; }
        @AuraEnabled public String analysisNotes { get; set; }
        
        public AnalysisResult() {
            this.detectedObjects = new List<String>();
            this.priorityChildObjects = new List<String>();
            this.hasExplicitObjectReferences = false;
            this.analysisNotes = '';
        }
    }
    
    /**
     * Analyzes business context to detect Salesforce object references
     * @param businessContext User's business context description
     * @param targetObject The main target object
     * @return AnalysisResult containing detected objects and priorities
     */
    public static AnalysisResult analyzeBusinessContext(String businessContext, String targetObject) {
        AnalysisResult result = new AnalysisResult();
        
        if (String.isBlank(businessContext)) {
            result.analysisNotes = 'No business context provided. Using default priority objects.';
            result.priorityChildObjects = getDefaultPriorityChildren(targetObject);
            return result;
        }
        
        // Normalize business context for analysis
        String normalizedContext = businessContext.toLowerCase();
        
        // Get all available child relationships for the target object
        List<AISchemaHelper.ChildRelationship> allChildren = AISchemaHelper.getChildRelationships(targetObject);
        Map<String, AISchemaHelper.ChildRelationship> childObjectMap = new Map<String, AISchemaHelper.ChildRelationship>();
        Map<String, AISchemaHelper.ChildRelationship> childObjectByNameMap = new Map<String, AISchemaHelper.ChildRelationship>();
        
        for (AISchemaHelper.ChildRelationship child : allChildren) {
            if (String.isNotBlank(child.childObject)) {
                childObjectMap.put(child.childObject.toLowerCase(), child);
                // Also map by relationship name for better matching
                if (String.isNotBlank(child.relationshipName)) {
                    childObjectByNameMap.put(child.relationshipName.toLowerCase(), child);
                }
            }
        }
        
        // Step 1: Detect EXACT object mentions (highest priority)
        Set<String> detectedSet = new Set<String>();
        List<String> objectKeywords = getObjectKeywords();
        
        for (String keyword : objectKeywords) {
            String keywordLower = keyword.toLowerCase();
            
            // Check for exact word boundaries to avoid false matches
            if (normalizedContext.contains(' ' + keywordLower + ' ') ||
                normalizedContext.contains(' ' + keywordLower + ',') ||
                normalizedContext.contains(' ' + keywordLower + '.') ||
                normalizedContext.startsWith(keywordLower + ' ') ||
                normalizedContext.endsWith(' ' + keywordLower)) {
                
                // Find exact matching child object
                for (String childObjKey : childObjectMap.keySet()) {
                    if (childObjKey.equals(keywordLower) || 
                        childObjKey.equals(keywordLower.replace('s', ''))) { // Handle plurals
                        AISchemaHelper.ChildRelationship child = childObjectMap.get(childObjKey);
                        detectedSet.add(child.childObject);
                        result.hasExplicitObjectReferences = true;
                        System.debug(LOG_PREFIX + ' Exact match found: ' + keyword + ' -> ' + child.childObject);
                    }
                }
                
                // Also check relationship names (e.g., "opportunity roles" -> OpportunityContactRole)
                for (String relNameKey : childObjectByNameMap.keySet()) {
                    if (relNameKey.contains(keywordLower) || keywordLower.contains(relNameKey)) {
                        AISchemaHelper.ChildRelationship child = childObjectByNameMap.get(relNameKey);
                        detectedSet.add(child.childObject);
                        result.hasExplicitObjectReferences = true;
                        System.debug(LOG_PREFIX + ' Relationship match found: ' + keyword + ' -> ' + child.childObject);
                    }
                }
            }
        }
        
        result.detectedObjects = new List<String>(detectedSet);
        
        // Determine priority child objects based on analysis
        if (result.hasExplicitObjectReferences && !result.detectedObjects.isEmpty()) {
            // User explicitly mentioned objects - ONLY use those (max 3)
            result.priorityChildObjects = new List<String>();
            for (Integer i = 0; i < Math.min(result.detectedObjects.size(), 3); i++) {
                result.priorityChildObjects.add(result.detectedObjects[i]);
            }
            result.analysisNotes = 'Detected ' + result.priorityChildObjects.size() + 
                                  ' object(s) in business context: ' + 
                                  String.join(result.priorityChildObjects, ', ');
        } else {
            // No explicit mentions - use intelligent defaults based on context keywords
            result.priorityChildObjects = inferPriorityFromContext(normalizedContext, targetObject, allChildren);
            result.analysisNotes = 'No explicit object references found. Inferred priorities based on context keywords.';
        }
        
        System.debug(LOG_PREFIX + ' Analysis Result: ' + JSON.serializePretty(result));
        
        return result;
    }
    
    /**
     * Gets default priority child objects based on target object (max 3)
     */
    private static List<String> getDefaultPriorityChildren(String targetObject) {
        // Object-specific defaults (limited to 3 most important)
        Map<String, List<String>> objectDefaults = new Map<String, List<String>>{
            'Account' => new List<String>{'Opportunity', 'Contact', 'Case'},
            'Contact' => new List<String>{'Opportunity', 'Case', 'Task'},
            'Opportunity' => new List<String>{'OpportunityLineItem', 'OpportunityContactRole', 'Task'},
            'Case' => new List<String>{'CaseComment', 'EmailMessage', 'Task'},
            'Lead' => new List<String>{'Task', 'Event', 'CampaignMember'}
        };
        
        if (objectDefaults.containsKey(targetObject)) {
            return objectDefaults.get(targetObject);
        }
        
        // Generic defaults (max 3)
        return new List<String>{'Task', 'Event', 'Note'};
    }
    
    /**
     * Infers priority objects from context keywords
     */
    private static List<String> inferPriorityFromContext(String normalizedContext, 
                                                          String targetObject,
                                                          List<AISchemaHelper.ChildRelationship> allChildren) {
        List<String> priorities = new List<String>();
        Set<String> prioritySet = new Set<String>();
        
        // Context-based inference rules (ONLY used if no explicit objects detected)
        Map<String, List<String>> contextRules = new Map<String, List<String>>{
            'opportunity' => new List<String>{'Opportunity', 'OpportunityContactRole', 'OpportunityLineItem'},
            'opportunities' => new List<String>{'Opportunity', 'OpportunityContactRole', 'OpportunityLineItem'},
            'role' => new List<String>{'OpportunityContactRole', 'AccountContactRole'},
            'roles' => new List<String>{'OpportunityContactRole', 'AccountContactRole'},
            'sales' => new List<String>{'Opportunity', 'Quote', 'OpportunityLineItem'},
            'revenue' => new List<String>{'Opportunity', 'OpportunityLineItem', 'Quote'},
            'pipeline' => new List<String>{'Opportunity', 'OpportunityLineItem'},
            'deal' => new List<String>{'Opportunity', 'Quote'},
            'service' => new List<String>{'Case', 'EmailMessage', 'CaseComment'},
            'support' => new List<String>{'Case', 'EmailMessage', 'Task'},
            'case' => new List<String>{'Case', 'CaseComment', 'EmailMessage'},
            'ticket' => new List<String>{'Case', 'CaseComment'},
            'activity' => new List<String>{'Task', 'Event', 'EmailMessage'},
            'engagement' => new List<String>{'Task', 'Event', 'EmailMessage'},
            'communication' => new List<String>{'EmailMessage', 'Task', 'Event'},
            'email' => new List<String>{'EmailMessage', 'Task'},
            'contact' => new List<String>{'Contact', 'Task', 'Event'},
            'relationship' => new List<String>{'OpportunityContactRole', 'AccountContactRole', 'Contact'},
            'order' => new List<String>{'Order', 'OrderItem'},
            'product' => new List<String>{'OpportunityLineItem', 'OrderItem', 'Asset'},
            'contract' => new List<String>{'Contract', 'Order'},
            'campaign' => new List<String>{'CampaignMember', 'Lead'},
            'partner' => new List<String>{'AccountPartner', 'Partner'}
        };
        
        // Check each rule
        for (String keyword : contextRules.keySet()) {
            if (normalizedContext.contains(keyword)) {
                List<String> suggestedObjects = contextRules.get(keyword);
                for (String obj : suggestedObjects) {
                    // Verify the object exists as a child relationship
                    if (isValidChildObject(obj, allChildren)) {
                        prioritySet.add(obj);
                    }
                }
            }
        }
        
        priorities = new List<String>(prioritySet);
        
        // If no matches, use defaults
        if (priorities.isEmpty()) {
            priorities = getDefaultPriorityChildren(targetObject);
        }
        
        // Limit to top 3 objects (level 1) to avoid governor limits and follow best practices
        if (priorities.size() > 3) {
            List<String> limited = new List<String>();
            for (Integer i = 0; i < 3; i++) {
                limited.add(priorities[i]);
            }
            priorities = limited;
        }
        
        return priorities;
    }
    
    /**
     * Validates if an object exists as a child relationship
     */
    private static Boolean isValidChildObject(String objectName, List<AISchemaHelper.ChildRelationship> allChildren) {
        for (AISchemaHelper.ChildRelationship child : allChildren) {
            if (child.childObject.equalsIgnoreCase(objectName)) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * Returns list of Salesforce object keywords to search for
     */
    private static List<String> getObjectKeywords() {
        return new List<String>{
            // Standard Objects
            'Account', 'Contact', 'Lead', 'Opportunity', 'Case', 'Task', 'Event',
            'Campaign', 'CampaignMember', 'Contract', 'Order', 'OrderItem',
            'Quote', 'QuoteLineItem', 'Asset', 'Product', 'Pricebook',
            'OpportunityLineItem', 'OpportunityContactRole', 'AccountContactRole',
            'EmailMessage', 'Note', 'Attachment', 'ContentDocument',
            'CaseComment', 'Solution', 'User', 'Group',
            // Common plurals
            'Accounts', 'Contacts', 'Leads', 'Opportunities', 'Cases', 'Tasks', 'Events',
            'Campaigns', 'Contracts', 'Orders', 'Quotes', 'Assets', 'Products',
            'Emails', 'Notes', 'Attachments', 'Documents', 'Comments', 'Solutions',
            // Role-specific keywords
            'opportunity role', 'opportunity roles', 'contact role', 'contact roles',
            'account role', 'account roles', 'partner', 'partners',
            // Line item keywords
            'line item', 'line items', 'products', 'items'
        };
    }
    
    /**
     * Filters child relationships based on detected priorities
     * @param allChildren All available child relationships
     * @param priorityObjects List of priority object names
     * @return Filtered list of child relationships matching priorities
     */
    public static List<AISchemaHelper.ChildRelationship> filterChildRelationships(
        List<AISchemaHelper.ChildRelationship> allChildren,
        List<String> priorityObjects) {
        
        List<AISchemaHelper.ChildRelationship> filtered = new List<AISchemaHelper.ChildRelationship>();
        Set<String> prioritySet = new Set<String>();
        
        for (String obj : priorityObjects) {
            prioritySet.add(obj.toLowerCase());
        }
        
        for (AISchemaHelper.ChildRelationship child : allChildren) {
            if (prioritySet.contains(child.childObject.toLowerCase())) {
                filtered.add(child);
            }
        }
        
        return filtered;
    }
    
    /**
     * Gets level 2 (grandchildren) relationships for a given child object
     * Returns the most relevant grandchild based on business context
     * @param childObject The child object to get grandchildren for
     * @param businessContext User's business context
     * @return Single most relevant grandchild object, or null if none found
     */
    public static AISchemaHelper.ChildRelationship getLevel2Relationship(
        String childObject, 
        String businessContext) {
        
        try {
            // Get all grandchildren for this child object
            List<AISchemaHelper.ChildRelationship> grandchildren = 
                AISchemaHelper.getChildRelationships(childObject);
            
            if (grandchildren == null || grandchildren.isEmpty()) {
                return null;
            }
            
            // Normalize business context
            String normalizedContext = String.isNotBlank(businessContext) ? 
                businessContext.toLowerCase() : '';
            
            // Priority mapping for common patterns
            Map<String, List<String>> level2Priorities = new Map<String, List<String>>{
                'Opportunity' => new List<String>{'OpportunityLineItem', 'OpportunityContactRole', 'Task'},
                'Case' => new List<String>{'CaseComment', 'EmailMessage', 'Task'},
                'Account' => new List<String>{'Contact', 'Opportunity', 'Task'},
                'Contact' => new List<String>{'Task', 'Event', 'EmailMessage'},
                'Order' => new List<String>{'OrderItem', 'Task'},
                'Quote' => new List<String>{'QuoteLineItem', 'Task'}
            };
            
            // Get priority list for this child object
            List<String> priorities = level2Priorities.containsKey(childObject) ?
                level2Priorities.get(childObject) : new List<String>();
            
            // First, try to match with priorities
            for (String priority : priorities) {
                for (AISchemaHelper.ChildRelationship grandchild : grandchildren) {
                    if (grandchild.childObject.equalsIgnoreCase(priority)) {
                        System.debug(LOG_PREFIX + ' Selected level 2: ' + priority + ' for ' + childObject);
                        return grandchild;
                    }
                }
            }
            
            // If no priority match, return the first accessible grandchild
            if (!grandchildren.isEmpty()) {
                System.debug(LOG_PREFIX + ' Selected first available level 2: ' + 
                           grandchildren[0].childObject + ' for ' + childObject);
                return grandchildren[0];
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' Error getting level 2 relationship: ' + e.getMessage());
            return null;
        }
    }
}
