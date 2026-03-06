/**
 * @description Test class for AIContextAssembler
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 03-02-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
@isTest
private class AIContextAssemblerTest {
    
    @testSetup
    static void setupTestData() {
        Account testAccount = new Account(
            Name = 'Test Account',
            Industry = 'Technology',
            AnnualRevenue = 1000000
        );
        insert testAccount;
        
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = testAccount.Id,
            Email = 'test@example.com'
        );
        insert testContact;
    }
    
    @isTest
    static void testAssembleContextWithSampleRecord() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        String context = AIContextAssembler.assembleContext(
            'Account',
            acc.Id,
            'Generate a comprehensive account intelligence report'
        );
        Test.stopTest();
        
        Assert.isNotNull(context, 'Context should not be null');
        Assert.isTrue(context.contains('Account 360 Context Package'), 'Should contain header');
        Assert.isTrue(context.contains('OBJECT TYPE'), 'Should contain object type section');
        Assert.isTrue(context.contains('REPORT PURPOSE'), 'Should contain report purpose');
        Assert.isTrue(context.contains('DATA CONTRACT'), 'Should contain data contract');
        Assert.isTrue(context.contains('Generate a comprehensive account intelligence report'), 
                      'Should include business context');
    }
    
    @isTest
    static void testAssembleContextWithoutSampleRecord() {
        Test.startTest();
        String context = AIContextAssembler.assembleContext(
            'Account',
            null,
            'Generate account intelligence'
        );
        Test.stopTest();
        
        Assert.isNotNull(context, 'Context should not be null');
        Assert.isTrue(context.contains('Account 360 Context Package'), 'Should contain header');
        Assert.isTrue(context.contains('Generate account intelligence'), 'Should include business context');
    }
    
    @isTest
    static void testAssembleContextWithoutBusinessContext() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        String context = AIContextAssembler.assembleContext(
            'Account',
            acc.Id,
            null
        );
        Test.stopTest();
        
        Assert.isNotNull(context, 'Context should not be null');
        Assert.isTrue(context.contains('Account Intelligence'), 'Should have default purpose');
    }
    
    @isTest
    static void testBuildDataContract() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        Map<String, Object> contract = AIContextAssembler.buildDataContract('Account', acc.Id);
        Test.stopTest();
        
        Assert.isNotNull(contract, 'Contract should not be null');
        Assert.isTrue(contract.containsKey('fields'), 'Should contain fields');
        Assert.isTrue(contract.containsKey('children'), 'Should contain children');
        Assert.isTrue(contract.containsKey('objectName'), 'Should contain objectName');
        Assert.areEqual('Account', contract.get('objectName'), 'Object name should be Account');
        
        List<AISchemaHelper.FieldMetadata> fields = 
            (List<AISchemaHelper.FieldMetadata>) contract.get('fields');
        Assert.isTrue(fields.size() > 0, 'Should have fields');
    }
    
    @isTest
    static void testBuildDataContractWithoutSampleRecord() {
        Test.startTest();
        Map<String, Object> contract = AIContextAssembler.buildDataContract('Contact', null);
        Test.stopTest();
        
        Assert.isNotNull(contract, 'Contract should not be null');
        Assert.isTrue(contract.containsKey('fields'), 'Should contain fields');
        Assert.isFalse(contract.containsKey('sampleRecord'), 'Should not contain sample record');
    }
    
    @isTest
    static void testBuildRootFieldsTable() {
        List<AISchemaHelper.FieldMetadata> fields = AISchemaHelper.getFields('Account');
        Map<String, Object> sampleRecord = new Map<String, Object>{
            'Id' => '001000000000001',
            'Name' => 'Test Account',
            'Industry' => 'Technology'
        };
        
        Test.startTest();
        String table = AIContextAssembler.buildRootFieldsTable(fields, sampleRecord);
        Test.stopTest();
        
        Assert.isNotNull(table, 'Table should not be null');
        Assert.isTrue(table.contains('| Field | Type | Notes |'), 'Should have table header');
        Assert.isTrue(table.contains('Name'), 'Should contain Name field');
    }
    
    @isTest
    static void testBuildRootFieldsTableWithoutSample() {
        List<AISchemaHelper.FieldMetadata> fields = AISchemaHelper.getFields('Account');
        
        Test.startTest();
        String table = AIContextAssembler.buildRootFieldsTable(fields, null);
        Test.stopTest();
        
        Assert.isNotNull(table, 'Table should not be null');
        Assert.isTrue(table.contains('| Field | Type | Notes |'), 'Should have table header');
    }
    
    @isTest
    static void testBuildChildArraysSection() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        List<AISchemaHelper.ChildRelationship> children = AISchemaHelper.getChildRelationships('Account');
        
        Map<String, Object> childData = new Map<String, Object>();
        Map<String, Object> contactInfo = new Map<String, Object>();
        contactInfo.put('objectName', 'Contact');
        contactInfo.put('records', new List<Object>{
            new Map<String, Object>{'FirstName' => 'Test', 'LastName' => 'Contact'}
        });
        contactInfo.put('count', 1);
        childData.put('Contacts', contactInfo);
        
        Test.startTest();
        String section = AIContextAssembler.buildChildArraysSection(children, childData);
        Test.stopTest();
        
        Assert.isNotNull(section, 'Section should not be null');
    }
    
    @isTest
    static void testDetectDataQuirks() {
        List<AISchemaHelper.FieldMetadata> fields = AISchemaHelper.getFields('Account');
        Map<String, Object> sampleRecord = new Map<String, Object>{
            'Id' => '001000000000001',
            'Name' => 'Test Account',
            'IsDeleted' => 'false',
            'AnnualRevenue' => '1000000.00'
        };
        Map<String, Object> childData = new Map<String, Object>();
        
        Test.startTest();
        List<String> quirks = AIContextAssembler.detectDataQuirks(fields, sampleRecord, childData);
        Test.stopTest();
        
        Assert.isNotNull(quirks, 'Quirks should not be null');
    }
    
    @isTest
    static void testDetectDataQuirksWithoutSample() {
        List<AISchemaHelper.FieldMetadata> fields = AISchemaHelper.getFields('Account');
        
        Test.startTest();
        List<String> quirks = AIContextAssembler.detectDataQuirks(fields, null, null);
        Test.stopTest();
        
        Assert.areEqual(0, quirks.size(), 'Should return empty list without sample');
    }
    
    @isTest
    static void testBuildSampleJson() {
        Map<String, Object> sampleRecord = new Map<String, Object>{
            'Id' => '001000000000001',
            'Name' => 'Test Account',
            'Industry' => 'Technology'
        };
        Map<String, Object> childData = new Map<String, Object>();
        
        Test.startTest();
        String json = AIContextAssembler.buildSampleJson(sampleRecord, childData);
        Test.stopTest();
        
        Assert.isNotNull(json, 'JSON should not be null');
        Assert.isTrue(json.contains('Name'), 'Should contain Name field');
    }
    
    @isTest
    static void testBuildSampleJsonWithoutSample() {
        Test.startTest();
        String json = AIContextAssembler.buildSampleJson(null, null);
        Test.stopTest();
        
        Assert.areEqual('No sample data available.', json, 'Should return no data message');
    }
    
    @isTest
    static void testAssembleContextForContact() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        String context = AIContextAssembler.assembleContext(
            'Contact',
            con.Id,
            'Generate contact intelligence report'
        );
        Test.stopTest();
        
        Assert.isNotNull(context, 'Context should not be null');
        Assert.isTrue(context.contains('Contact 360 Context Package'), 'Should contain Contact header');
    }
    
    @isTest
    static void testAssembleContextForCustomObject() {
        Test.startTest();
        String context = AIContextAssembler.assembleContext(
            'AI_GPTfy_Warehouse__c',
            null,
            'Generate warehouse intelligence'
        );
        Test.stopTest();
        
        Assert.isNotNull(context, 'Context should not be null');
        Assert.isTrue(context.contains('AI_GPTfy_Warehouse__c 360 Context Package'), 
                      'Should contain custom object header');
    }
}