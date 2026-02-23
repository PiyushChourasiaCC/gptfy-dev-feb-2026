@isTest
private class AIAgentTriggerHandlerTest {

    @isTest static void testOnBeforeInsertPopulatesDeveloperName() {
         // Create test AI Connection record
         AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4.1',
            Named_Credential__c = 'Test_Credential',
            Type__c = 'Agentic'
        );
        INSERT aiConnection;
        AI_Agent__c cfg = new AI_Agent__c(
            Name = 'My Test Config 1',
            Developer_Name__c = 'My_Test_Config_1',
            TTL__c = 10,
            TTL_Message__c = 'This session has expired.',
            AI_Model__c = aiConnection.Id
        );

        Test.startTest();
        insert cfg; // should trigger before insert
        Test.stopTest();

        AI_Agent__c insertedCfg = [
            SELECT Id, Name, Developer_Name__c FROM AI_Agent__c WHERE Id = :cfg.Id
        ];
        Assert.isNotNull(insertedCfg.Developer_Name__c);
    }

    @isTest static void testGenerateUniqueKeyWithSpecialCharacters() {
        // Create test AI Connection record
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4.1',
            Named_Credential__c = 'Test_Credential',
            Type__c = 'Agentic'
        );
        INSERT aiConnection;

        AI_Agent__c cfg = new AI_Agent__c(
            Name = 'Config@# With$% Special!!',
            Developer_Name__c = 'My_Test_Config_1',
            TTL__c = 10,
            TTL_Message__c = 'This session has expired.',
            AI_Model__c = aiConnection.Id
        );

        Test.startTest();
        insert cfg; // should trigger before insert
        Test.stopTest();

        AI_Agent__c insertedCfg = [
            SELECT Developer_Name__c FROM AI_Agent__c WHERE Id = :cfg.Id
        ];

        // Special characters should be stripped, spaces replaced with underscores
        Assert.isNotNull(insertedCfg.Developer_Name__c);
    }

    @isTest static void testConvertToDeveloperNameVariety() {
        Test.startTest();
        // 1. Blank string => should return null
        String blankResult = AIAgentTriggerHandler.convertToDeveloperName('');
        Assert.isNull(blankResult, 'Blank name should return null');

        // 2. Null string => should return null
        String nullResult = AIAgentTriggerHandler.convertToDeveloperName(null);
        Assert.isNull(nullResult, 'Null name should return null');

        // 3. Leading/trailing spaces => should trim and replace spaces
        String trimmedResult = AIAgentTriggerHandler.convertToDeveloperName('   Config With Spaces   ');
        Assert.areEqual('Config_With_Spaces', trimmedResult, 'Whitespace trimming failed');

        // 4. Alphanumeric + underscore preserved
        String alphanumeric = AIAgentTriggerHandler.convertToDeveloperName('Valid_Name123');
        Assert.areEqual('Valid_Name123', alphanumeric, 'Alphanumeric with underscore should remain unchanged');
        Test.stopTest();
    }

    @isTest static void testMultipleRecordsBulkInsert() {
         // Create test AI Connection record
         AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4.1',
            Named_Credential__c = 'Test_Credential',
            Type__c = 'Agentic'
        );
        INSERT aiConnection;
        List<AI_Agent__c> cfgs = new List<AI_Agent__c>{
            new AI_Agent__c(Name = 'First Config',AI_Model__c = aiConnection.Id),
            new AI_Agent__c(Name = 'Second-Config##',AI_Model__c = aiConnection.Id),
            new AI_Agent__c(Name = '   Third   Config   ',AI_Model__c = aiConnection.Id)
        };

        Test.startTest();
        insert cfgs;
        Test.stopTest();

        Map<String, AI_Agent__c> results =
            new Map<String, AI_Agent__c>([
                SELECT Name, Developer_Name__c FROM AI_Agent__c WHERE Id IN :cfgs
            ]);

        Assert.isNotNull(results.get(cfgs[0].Id).Developer_Name__c);
        Assert.isNotNull(results.get(cfgs[1].Id).Developer_Name__c);
        Assert.isNotNull(results.get(cfgs[2].Id).Developer_Name__c);
    }
}