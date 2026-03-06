/**
 * @description Test class for AISchemaHelper
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 03-02-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
@isTest
private class AISchemaHelperTest {
    
    @isTest
    static void testGetFields() {
        Test.startTest();
        List<AISchemaHelper.FieldMetadata> fields = AISchemaHelper.getFields('Account');
        Test.stopTest();
        
        Assert.isTrue(fields.size() > 0, 'Should return fields for Account');
        
        Boolean hasNameField = false;
        Boolean hasIdField = false;
        for (AISchemaHelper.FieldMetadata field : fields) {
            if (field.name == 'Name') {
                hasNameField = true;
                Assert.isNotNull(field.label, 'Field label should not be null');
                Assert.isNotNull(field.type, 'Field type should not be null');
            }
            if (field.name == 'Id') {
                hasIdField = true;
            }
        }
        
        Assert.isTrue(hasNameField, 'Should include Name field');
        Assert.isTrue(hasIdField, 'Should include Id field');
    }
    
    @isTest
    static void testGetFieldsInvalidObject() {
        Test.startTest();
        List<AISchemaHelper.FieldMetadata> fields = AISchemaHelper.getFields('InvalidObject__c');
        Test.stopTest();
        
        Assert.areEqual(0, fields.size(), 'Should return empty list for invalid object');
    }
    
    @isTest
    static void testGetChildRelationships() {
        Test.startTest();
        List<AISchemaHelper.ChildRelationship> children = AISchemaHelper.getChildRelationships('Account');
        Test.stopTest();
        
        Assert.isTrue(children.size() > 0, 'Account should have child relationships');
        
        Boolean hasContacts = false;
        for (AISchemaHelper.ChildRelationship child : children) {
            Assert.isNotNull(child.childObject, 'Child object should not be null');
            if (child.childObject == 'Contact') {
                hasContacts = true;
                Assert.areEqual('Contacts', child.relationshipName, 'Should have Contacts relationship');
            }
        }
        
        Assert.isTrue(hasContacts, 'Account should have Contacts child relationship');
    }
    
    @isTest
    static void testGetChildRelationshipsInvalidObject() {
        Test.startTest();
        List<AISchemaHelper.ChildRelationship> children = AISchemaHelper.getChildRelationships('InvalidObject__c');
        Test.stopTest();
        
        Assert.areEqual(0, children.size(), 'Should return empty list for invalid object');
    }
    
    @isTest
    static void testIsObjectAccessible() {
        Test.startTest();
        Boolean accountAccessible = AISchemaHelper.isObjectAccessible('Account');
        Boolean invalidAccessible = AISchemaHelper.isObjectAccessible('InvalidObject__c');
        Test.stopTest();
        
        Assert.isTrue(accountAccessible, 'Account should be accessible');
        Assert.isFalse(invalidAccessible, 'Invalid object should not be accessible');
    }
    
    @isTest
    static void testIsFieldAccessible() {
        Test.startTest();
        Boolean nameAccessible = AISchemaHelper.isFieldAccessible('Account', 'Name');
        Boolean invalidFieldAccessible = AISchemaHelper.isFieldAccessible('Account', 'InvalidField__c');
        Boolean invalidObjectField = AISchemaHelper.isFieldAccessible('InvalidObject__c', 'Name');
        Test.stopTest();
        
        Assert.isTrue(nameAccessible, 'Name field should be accessible on Account');
        Assert.isFalse(invalidFieldAccessible, 'Invalid field should not be accessible');
        Assert.isFalse(invalidObjectField, 'Field on invalid object should not be accessible');
    }
    
    @isTest
    static void testGetSafeQueryableFields() {
        Test.startTest();
        Set<String> contentDocFields = AISchemaHelper.getSafeQueryableFields('ContentDocumentLink');
        Set<String> accountFields = AISchemaHelper.getSafeQueryableFields('Account');
        Test.stopTest();
        
        Assert.isTrue(contentDocFields.size() > 0, 'ContentDocumentLink should have restricted fields');
        Assert.isTrue(contentDocFields.contains('Id'), 'Should include Id field');
        Assert.areEqual(0, accountFields.size(), 'Account should have no restrictions');
    }
    
    @isTest
    static void testIsFieldQueryable() {
        Test.startTest();
        Boolean accountNameQueryable = AISchemaHelper.isFieldQueryable('Account', 'Name');
        Boolean contentDocIdQueryable = AISchemaHelper.isFieldQueryable('ContentDocumentLink', 'Id');
        Test.stopTest();
        
        Assert.isTrue(accountNameQueryable, 'Account Name should be queryable');
        Assert.isTrue(contentDocIdQueryable, 'ContentDocumentLink Id should be queryable');
    }
    
    @isTest
    static void testFilterQueryableFields() {
        List<String> fieldNames = new List<String>{'Id', 'Name', 'InvalidField__c'};
        
        Test.startTest();
        List<String> queryableFields = AISchemaHelper.filterQueryableFields('Account', fieldNames);
        Test.stopTest();
        
        Assert.isTrue(queryableFields.contains('Id'), 'Should include Id');
        Assert.isTrue(queryableFields.contains('Name'), 'Should include Name');
        Assert.isFalse(queryableFields.contains('InvalidField__c'), 'Should not include invalid field');
    }
    
    @isTest
    static void testValidateFields() {
        List<String> fieldNames = new List<String>{'Id', 'Name', 'InvalidField__c'};
        
        Test.startTest();
        AISchemaHelper.FieldValidationResult result = AISchemaHelper.validateFields('Account', fieldNames);
        Test.stopTest();
        
        Assert.isTrue(result.objectExists, 'Object should exist');
        Assert.isTrue(result.validFields.contains('Id'), 'Id should be valid');
        Assert.isTrue(result.validFields.contains('Name'), 'Name should be valid');
        Assert.isTrue(result.invalidFields.contains('InvalidField__c'), 'InvalidField__c should be invalid');
    }
    
    @isTest
    static void testValidateFieldsInvalidObject() {
        List<String> fieldNames = new List<String>{'Name'};
        
        Test.startTest();
        AISchemaHelper.FieldValidationResult result = AISchemaHelper.validateFields('InvalidObject__c', fieldNames);
        Test.stopTest();
        
        Assert.isFalse(result.objectExists, 'Object should not exist');
        Assert.isTrue(result.invalidFields.contains('Name'), 'All fields should be invalid');
    }
    
    @isTest
    static void testGetChildRelationshipsForObjects() {
        List<String> objectNames = new List<String>{'Account', 'Contact'};
        
        Test.startTest();
        Map<String, List<AISchemaHelper.ChildRelationship>> result = 
            AISchemaHelper.getChildRelationshipsForObjects(objectNames);
        Test.stopTest();
        
        Assert.isTrue(result.containsKey('Account'), 'Should contain Account');
        Assert.isTrue(result.containsKey('Contact'), 'Should contain Contact');
        Assert.isTrue(result.get('Account').size() > 0, 'Account should have children');
    }
    
    @isTest
    static void testDiscoverGrandchildRelationships() {
        List<String> childObjects = new List<String>{'Contact', 'Opportunity'};
        
        Test.startTest();
        Map<String, List<AISchemaHelper.ChildRelationship>> result = 
            AISchemaHelper.discoverGrandchildRelationships('Account', childObjects);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testGetEnvironmentInfo() {
        Test.startTest();
        AISchemaHelper.EnvironmentInfo info = AISchemaHelper.getEnvironmentInfo();
        Test.stopTest();
        
        Assert.isNotNull(info, 'Environment info should not be null');
        Assert.isNotNull(info.sandboxType, 'Sandbox type should not be null');
        Assert.isTrue(info.fieldDensityThreshold >= 0, 'Threshold should be non-negative');
    }
    
    @isTest
    static void testFieldMetadataComparable() {
        AISchemaHelper.FieldMetadata field1 = new AISchemaHelper.FieldMetadata('Name', 'Name', 'STRING', true, true, false);
        AISchemaHelper.FieldMetadata field2 = new AISchemaHelper.FieldMetadata('Id', 'Record ID', 'ID', true, false, false);
        
        Test.startTest();
        Integer comparison = field1.compareTo(field2);
        Test.stopTest();
        
        Assert.isTrue(comparison > 0, 'Name should come after Id alphabetically');
    }
    
    @isTest
    static void testChildRelationshipComparable() {
        AISchemaHelper.ChildRelationship child1 = new AISchemaHelper.ChildRelationship('Contact', 'Contacts', 'AccountId');
        AISchemaHelper.ChildRelationship child2 = new AISchemaHelper.ChildRelationship('Opportunity', 'Opportunities', 'AccountId');
        
        Test.startTest();
        Integer comparison = child1.compareTo(child2);
        Test.stopTest();
        
        Assert.isTrue(comparison < 0, 'Contact should come before Opportunity alphabetically');
    }
    
    @isTest
    static void testFieldValidationResultMethods() {
        AISchemaHelper.FieldValidationResult result = new AISchemaHelper.FieldValidationResult();
        result.validFields.add('Name');
        result.invalidFields.add('BadField__c');
        
        Test.startTest();
        Boolean isValid = result.isValid();
        Boolean hasIssues = result.hasIssues();
        Test.stopTest();
        
        Assert.isFalse(isValid, 'Should not be valid with invalid fields');
        Assert.isTrue(hasIssues, 'Should have issues');
    }
}