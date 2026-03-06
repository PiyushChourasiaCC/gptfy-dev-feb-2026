/**
 * @description Utility class for Salesforce schema introspection for AI Prompt Factory
 * Provides methods to query object and field metadata with caching
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 03-02-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
public with sharing class AISchemaHelper {

    // Static cache for describe results to improve performance
    private static Map<String, Schema.DescribeSObjectResult> describeCache =
        new Map<String, Schema.DescribeSObjectResult>();

    /**
     * @description Wrapper class for child relationship information
     */
    public class ChildRelationship implements Comparable {
        @AuraEnabled public String childObject;
        @AuraEnabled public String relationshipName;
        @AuraEnabled public String field;

        public ChildRelationship(String childObject, String relationshipName, String field) {
            this.childObject = childObject;
            this.relationshipName = relationshipName;
            this.field = field;
        }

        public Integer compareTo(Object compareTo) {
            ChildRelationship compareToRel = (ChildRelationship) compareTo;
            if (childObject == compareToRel.childObject) return 0;
            if (childObject > compareToRel.childObject) return 1;
            return -1;
        }
    }

    /**
     * @description Wrapper class for field metadata
     */
    public class FieldMetadata implements Comparable {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean isAccessible;
        @AuraEnabled public Boolean isUpdateable;
        @AuraEnabled public Boolean isCustom;

        public FieldMetadata(String name, String label, String type,
                           Boolean isAccessible, Boolean isUpdateable, Boolean isCustom) {
            this.name = name;
            this.label = label;
            this.type = type;
            this.isAccessible = isAccessible;
            this.isUpdateable = isUpdateable;
            this.isCustom = isCustom;
        }

        public Integer compareTo(Object compareTo) {
            FieldMetadata compareToField = (FieldMetadata) compareTo;
            if (name == compareToField.name) return 0;
            if (name > compareToField.name) return 1;
            return -1;
        }
    }

    /**
     * @description Gets cached describe result for an object
     * @param objectName API name of the object
     * @return DescribeSObjectResult or null if object doesn't exist
     */
    public static Schema.DescribeSObjectResult getObjectDescribe(String objectName) {
        if (!describeCache.containsKey(objectName)) {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType == null) {
                return null;
            }
            describeCache.put(objectName, objType.getDescribe());
        }
        return describeCache.get(objectName);
    }

    /**
     * @description Gets all child relationships for an object
     * @param objectName API name of the parent object
     * @return List of ChildRelationship wrapper objects
     */
    public static List<ChildRelationship> getChildRelationships(String objectName) {
        Schema.DescribeSObjectResult describe = getObjectDescribe(objectName);
        if (describe == null) {
            return new List<ChildRelationship>();
        }

        List<Schema.ChildRelationship> allRelationships = describe.getChildRelationships();
        List<ChildRelationship> relationships = new List<ChildRelationship>();

        for (Schema.ChildRelationship rel : allRelationships) {
            String childObjectName = rel.getChildSObject().getDescribe().getName();

            // Filter out system and irrelevant objects
            if (isSystemObject(childObjectName)) {
                continue;
            }

            // Filter out Feed, History, Share objects
            if (childObjectName.endsWith('Feed') ||
                childObjectName.endsWith('History') ||
                childObjectName.endsWith('Share')) {
                continue;
            }

            relationships.add(new ChildRelationship(
                childObjectName,
                rel.getRelationshipName(),
                rel.getField().getDescribe().getName()
            ));
        }

        // Sort relationships for deterministic AI prompts
        relationships.sort();

        return relationships;
    }

    /**
     * @description Gets field metadata for an object
     * @param objectName API name of the object
     * @return List of FieldMetadata wrapper objects
     */
    public static List<FieldMetadata> getFields(String objectName) {
        Schema.DescribeSObjectResult objDescribe = getObjectDescribe(objectName);
        if (objDescribe == null) {
            return new List<FieldMetadata>();
        }

        List<FieldMetadata> fields = new List<FieldMetadata>();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

            // Skip most system fields unless they're commonly useful
            if (isSystemField(fieldDescribe.getName()) &&
                !isUsefulSystemField(fieldDescribe.getName())) {
                continue;
            }

            fields.add(new FieldMetadata(
                fieldDescribe.getName(),
                fieldDescribe.getLabel(),
                String.valueOf(fieldDescribe.getType()),
                fieldDescribe.isAccessible(),
                fieldDescribe.isUpdateable(),
                fieldDescribe.isCustom()
            ));
        }

        // Sort fields for deterministic AI prompts
        fields.sort();

        return fields;
    }

    /**
     * @description Checks if an object is accessible to current user
     * @param objectName API name of the object
     * @return true if object is accessible, queryable, and not a system object
     */
    public static Boolean isObjectAccessible(String objectName) {
        Schema.DescribeSObjectResult describe = getObjectDescribe(objectName);

        if (describe == null) {
            return false;
        }

        return describe.isAccessible() &&
               describe.isQueryable() &&
               !describe.getName().endsWith('__ChangeEvent');
    }

    /**
     * @description Checks if a field is accessible to current user
     * @param objectName API name of the object
     * @param fieldName API name of the field
     * @return true if field is accessible
     */
    public static Boolean isFieldAccessible(String objectName, String fieldName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        if (objectType == null) {
            return false;
        }

        Schema.SObjectField field = objectType.getDescribe().fields.getMap().get(fieldName);
        if (field == null) {
            return false;
        }

        return field.getDescribe().isAccessible();
    }

    /**
     * @description Checks if an object name represents a system object
     * @param objectName API name of the object
     * @return true if it's a system object that should be filtered
     */
    private static Boolean isSystemObject(String objectName) {
        return objectName.endsWith('__Tag') ||
               objectName.endsWith('__ChangeEvent') ||
               objectName.endsWith('__ViewStat') ||
               objectName.endsWith('__mdt') ||
               objectName.endsWith('__e');
    }

    /**
     * @description Checks if a field name represents a system field
     * @param fieldName API name of the field
     * @return true if it's a system field
     */
    private static Boolean isSystemField(String fieldName) {
        Set<String> systemFields = new Set<String>{
            'CreatedById', 'CreatedDate', 'LastModifiedById', 'LastModifiedDate',
            'SystemModstamp', 'IsDeleted', 'LastActivityDate', 'LastViewedDate',
            'LastReferencedDate'
        };
        return systemFields.contains(fieldName);
    }

    /**
     * @description Checks if a system field is commonly useful in prompts
     * @param fieldName API name of the field
     * @return true if it's a useful system field for business context
     *
     * Includes:
     * - Id fields for record correlation (parent-child linking)
     * - CreatedDate, LastModifiedDate for timeline context
     * - LastActivityDate for engagement/staleness analysis
     * - OwnerId for ownership context
     */
    private static Boolean isUsefulSystemField(String fieldName) {
        Set<String> usefulFields = new Set<String>{
            'Id', 'Name', 'OwnerId',
            'CreatedDate', 'LastModifiedDate',
            'LastActivityDate'
        };
        return usefulFields.contains(fieldName);
    }

    /**
     * @description Gets safe/queryable fields for an object
     * Some objects like ContentDocumentLink have restrictions on which fields can be queried
     * @param objectName API name of the object
     * @return Set of field names that are safe to query
     */
    public static Set<String> getSafeQueryableFields(String objectName) {
        // ContentDocumentLink has special restrictions - only certain fields are queryable
        if (objectName == 'ContentDocumentLink') {
            return new Set<String>{
                'Id', 'ContentDocumentId', 'LinkedEntityId', 'ShareType', 'Visibility'
            };
        }

        // AttachedContentDocument also has restrictions
        if (objectName == 'AttachedContentDocument') {
            return new Set<String>{
                'Id', 'ContentDocumentId', 'LinkedEntityId', 'Title', 'FileType', 'ContentSize'
            };
        }

        // CombinedAttachment is a special read-only object
        if (objectName == 'CombinedAttachment') {
            return new Set<String>{
                'Id', 'Title', 'Body', 'ContentType', 'ParentId', 'CreatedById', 'CreatedDate', 'LastModifiedById', 'LastModifiedDate'
            };
        }

        // For other objects, return empty set to indicate no restrictions
        return new Set<String>();
    }

    /**
     * @description Checks if a field is queryable on an object
     * Handles special cases like ContentDocumentLink where some fields exist but aren't queryable
     * @param objectName API name of the object
     * @param fieldName API name of the field
     * @return true if the field can be queried in SOQL
     */
    public static Boolean isFieldQueryable(String objectName, String fieldName) {
        // Check if object has restricted fields
        Set<String> safeFields = getSafeQueryableFields(objectName);
        if (!safeFields.isEmpty()) {
            // Object has restrictions - only allow safe fields
            return safeFields.contains(fieldName);
        }

        // No restrictions - check normal accessibility
        return isFieldAccessible(objectName, fieldName);
    }

    /**
     * @description Filters a list of field names to only include queryable fields
     * @param objectName API name of the object
     * @param fieldNames List of field API names to filter
     * @return List of queryable field names
     */
    public static List<String> filterQueryableFields(String objectName, List<String> fieldNames) {
        List<String> queryableFields = new List<String>();
        Set<String> safeFields = getSafeQueryableFields(objectName);

        for (String fieldName : fieldNames) {
            if (!safeFields.isEmpty()) {
                // Object has restrictions - only include safe fields
                if (safeFields.contains(fieldName)) {
                    queryableFields.add(fieldName);
                }
            } else {
                // No restrictions - include if accessible
                if (isFieldAccessible(objectName, fieldName)) {
                    queryableFields.add(fieldName);
                }
            }
        }

        return queryableFields;
    }

    /**
     * @description Validates a list of field names against an object's schema
     * Also checks for special queryability restrictions (e.g., ContentDocumentLink)
     * @param objectName API name of the object
     * @param fieldNames List of field API names to validate
     * @return ValidationResult containing valid and invalid fields
     */
    public static FieldValidationResult validateFields(String objectName, List<String> fieldNames) {
        FieldValidationResult result = new FieldValidationResult();

        Schema.DescribeSObjectResult objDescribe = getObjectDescribe(objectName);
        if (objDescribe == null) {
            // Object doesn't exist - all fields are invalid
            result.invalidFields.addAll(fieldNames);
            result.objectExists = false;
            return result;
        }

        result.objectExists = true;
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

        // Check if object has special queryability restrictions
        Set<String> safeFields = getSafeQueryableFields(objectName);
        Boolean hasRestrictions = !safeFields.isEmpty();

        for (String fieldName : fieldNames) {
            // First check if object has special restrictions
            if (hasRestrictions) {
                if (safeFields.contains(fieldName)) {
                    result.validFields.add(fieldName);
                } else {
                    // Field exists in schema but not queryable on this object
                    result.invalidFields.add(fieldName);
                }
            } else if (fieldMap.containsKey(fieldName.toLowerCase())) {
                // Standard validation - check if field exists and is accessible
                Schema.DescribeFieldResult fieldDesc = fieldMap.get(fieldName.toLowerCase()).getDescribe();
                if (fieldDesc.isAccessible()) {
                    result.validFields.add(fieldName);
                } else {
                    result.inaccessibleFields.add(fieldName);
                }
            } else {
                result.invalidFields.add(fieldName);
            }
        }

        return result;
    }

    /**
     * @description Wrapper class for field validation results
     */
    public class FieldValidationResult {
        @AuraEnabled public Boolean objectExists = true;
        @AuraEnabled public List<String> validFields = new List<String>();
        @AuraEnabled public List<String> invalidFields = new List<String>();
        @AuraEnabled public List<String> inaccessibleFields = new List<String>();

        public Boolean isValid() {
            return objectExists && invalidFields.isEmpty();
        }

        public Boolean hasIssues() {
            return !objectExists || !invalidFields.isEmpty() || !inaccessibleFields.isEmpty();
        }
    }

    /**
     * @description Clears the describe cache (for testing purposes)
     */
    @TestVisible
    private static void clearCache() {
        describeCache.clear();
    }

    /**
     * @description Gets child relationships for multiple objects at once (for grandchild discovery)
     * @param objectNames List of object API names to get children for
     * @return Map of parent object name to list of ChildRelationship
     */
    public static Map<String, List<ChildRelationship>> getChildRelationshipsForObjects(List<String> objectNames) {
        Map<String, List<ChildRelationship>> result = new Map<String, List<ChildRelationship>>();

        for (String objectName : objectNames) {
            result.put(objectName, getChildRelationships(objectName));
        }

        return result;
    }

    /**
     * @description Discovers grandchild relationships (2 levels deep)
     * @param rootObject The root object (e.g., Account)
     * @param selectedChildObjects List of selected child objects to explore for grandchildren
     * @return Map of child object to its child relationships (grandchildren of root)
     */
    public static Map<String, List<ChildRelationship>> discoverGrandchildRelationships(
            String rootObject, List<String> selectedChildObjects) {

        Map<String, List<ChildRelationship>> grandchildMap = new Map<String, List<ChildRelationship>>();

        for (String childObject : selectedChildObjects) {
            // Skip the root object itself
            if (childObject == rootObject) {
                continue;
            }

            // Get children of this child (grandchildren of root)
            List<ChildRelationship> grandchildren = getChildRelationships(childObject);

            // Filter to only meaningful grandchild relationships
            List<ChildRelationship> filteredGrandchildren = new List<ChildRelationship>();
            for (ChildRelationship gc : grandchildren) {
                // Additional filtering for grandchildren - be more selective
                if (isValidGrandchildObject(gc.childObject)) {
                    filteredGrandchildren.add(gc);
                }
            }

            if (!filteredGrandchildren.isEmpty()) {
                grandchildMap.put(childObject, filteredGrandchildren);
            }
        }

        return grandchildMap;
    }

    /**
     * @description Checks if an object is a valid grandchild candidate
     * More restrictive than direct child filtering
     * @param objectName API name of the object
     * @return true if valid grandchild candidate
     */
    private static Boolean isValidGrandchildObject(String objectName) {
        // Skip system objects (same as child filtering)
        if (isSystemObject(objectName)) {
            return false;
        }

        // Skip Feed, History, Share objects
        if (objectName.endsWith('Feed') ||
            objectName.endsWith('History') ||
            objectName.endsWith('Share')) {
            return false;
        }

        // Skip ProcessInstance objects
        if (objectName.contains('ProcessInstance')) {
            return false;
        }

        // Skip ChangeEvent objects
        if (objectName.endsWith('ChangeEvent')) {
            return false;
        }

        // Check if object is accessible
        return isObjectAccessible(objectName);
    }

    /**
     * @description Gets environment information for field selection thresholds
     * @return EnvironmentInfo with sandbox type and density threshold
     */
    public static EnvironmentInfo getEnvironmentInfo() {
        EnvironmentInfo info = new EnvironmentInfo();

        try {
            Organization org = [SELECT Id, IsSandbox, InstanceName, OrganizationType FROM Organization LIMIT 1];
            info.isSandbox = org.IsSandbox;
            info.instanceName = org.InstanceName;
            info.orgType = org.OrganizationType;

            // Determine sandbox type based on instance name patterns
            if (!org.IsSandbox) {
                info.sandboxType = 'Production';
                info.fieldDensityThreshold = 20;
            } else {
                // Infer sandbox type from instance name
                String instance = org.InstanceName != null ? org.InstanceName.toLowerCase() : '';

                if (instance.contains('cs') || instance.contains('sandbox')) {
                    // Full or Partial sandbox
                    info.sandboxType = 'Full/Partial';
                    info.fieldDensityThreshold = 10;
                } else if (instance.contains('dev')) {
                    // Developer sandbox
                    info.sandboxType = 'Developer';
                    info.fieldDensityThreshold = 0;
                } else {
                    // Default to partial sandbox thresholds
                    info.sandboxType = 'Unknown';
                    info.fieldDensityThreshold = 5;
                }
            }
        } catch (Exception e) {
            // Fallback to safe defaults
            info.isSandbox = true;
            info.sandboxType = 'Unknown';
            info.fieldDensityThreshold = 5;
        }

        return info;
    }

    /**
     * @description Wrapper class for environment information
     */
    public class EnvironmentInfo {
        @AuraEnabled public Boolean isSandbox = false;
        @AuraEnabled public String sandboxType = 'Unknown';
        @AuraEnabled public String instanceName;
        @AuraEnabled public String orgType;
        @AuraEnabled public Integer fieldDensityThreshold = 10;
    }
}