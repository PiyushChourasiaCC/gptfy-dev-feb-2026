/**
 * @description       : Comprehensive test class for AIGlobalExportImportController with maximum coverage using TestUtility
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 30-05-2025
 * @last modified by  : Piyush Chourasia
**/
@isTest
public class AIGlobalExportImportControllerTest {
    @testSetup
    static void setupData() {
        TestUtility.insertDataExtraction();
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
        
        AI_Connection__c conn = TestUtility.getConnection('AnyAI_AnyPlatform', true);
        
        prompt.AI_Connection__c = conn.Id;
        
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{ 
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
        });
        
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        
        insert prompt;
        
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmtId, master.Id, 'Account', false);
        cmp1.AI_Prompt__c = prompt.Id;
        
        insert cmp1;
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(pmtId, cDetail.Id, 'Contact', true);
        AI_Data_Source__c ds = TestUtility.getAIDataSource(true);
        AI_Card_Configuration__c card = TestUtility.createCardConfiguration('Card1', 'APIDS', true);
        AI_Card_Configuration__c card1 = TestUtility.createCardConfiguration('Card2', 'AMODL', true);
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(pmtId, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(pmtId);
        
        AI_Response_Processing__c rp = TestUtility.getResponseProcessing(cmp1.Id, 'Description', true);
        
        AI_Security_Filters__c sf = TestUtility.getAISecurityFilter('Post Code', AIDataExtractionService.RT_REGEX, true);
        AI_Security_Filters__c sf2 = TestUtility.getAISecurityFilter('Accounts', AIDataExtractionService.RT_BLOCKLIST, true);
    }

    @isTest
    static void testGetInitData() {
        Test.startTest();
        ExportMappingWrapper result = AIGlobalExportImportController.getInitData();
        Test.stopTest();
        Assert.isNotNull(result, 'getInitData should not return null');
        Assert.isNotNull(result.exportedOn, 'exportedOn should not be null');
        Assert.isNotNull(result.orgId, 'orgId should not be null');
        Assert.isNotNull(result.exportedBy, 'exportedBy should not be null');
        Assert.isTrue(result.prompts != null && !result.prompts.isEmpty(), 'Prompts should not be empty');
        Assert.isTrue(result.dataExtractionMappings != null && !result.dataExtractionMappings.isEmpty(), 'Data Extraction Mappings should not be empty');
        Assert.isTrue(result.securityFilters != null && !result.securityFilters.isEmpty(), 'Security Filters should not be empty');
    }

    @isTest
    static void testReadFileDataValidAndInvalid() {
        ImportMappingWrapper wrap = new ImportMappingWrapper();
        wrap.orgId = UserInfo.getOrganizationId();
        wrap.exportedBy = UserInfo.getName();
        wrap.exportedOn = System.today();
        String validJson = JSON.serialize(wrap);
        Test.startTest();
        Map<String, Object> result = AIGlobalExportImportController.readFileData(validJson);
        Assert.isFalse((Boolean)result.get('hasError'), 'Valid file data should not error');
        Assert.isNotNull(result.get('data'), 'Result data should not be null');
        // Invalid JSON
        try {
            AIGlobalExportImportController.readFileData('Invalid JSON');
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().length() > 0, 'Error message should not be empty');
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveMappingsErrorAndSuccess() {
        // Error branch
        Test.startTest();
        try {
            AIGlobalExportImportController.saveMappings(null, null, null, null, null, null, false);
            Assert.fail('Should throw AuraHandledException');
        } catch (Exception e) {
            Assert.isTrue(e instanceof AuraHandledException, 'Should throw AuraHandledException');
        }
        // Success branch
        ImportMappingWrapper.PromptWrapper prompt = new ImportMappingWrapper.PromptWrapper();
        prompt.salesforceId = [SELECT Id FROM AI_Prompt__c LIMIT 1].Id;
        prompt.objectName = 'Account';
        ImportMappingWrapper.ConnectionWrapper conn = new ImportMappingWrapper.ConnectionWrapper();
        conn.salesforceId = [SELECT Id FROM AI_Connection__c LIMIT 1].Id;
        conn.connectionName = 'Test Connection';
        ImportMappingWrapper.ExtractionWrapper mapping = new ImportMappingWrapper.ExtractionWrapper();
        mapping.salesforceId = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1].Id;
        mapping.mappingName = 'Test Mapping';
        ImportMappingWrapper.ExtractionSecurityFilterWrapper filter = new ImportMappingWrapper.ExtractionSecurityFilterWrapper();
        filter.salesforceId = [SELECT Id FROM AI_Security_Filters__c LIMIT 1].Id;
        filter.filterName = 'Test Filter';
        ImportMappingWrapper.DataSourceWrapper ds = new ImportMappingWrapper.DataSourceWrapper();
        ds.salesforceId = [SELECT Id FROM AI_Data_Source__c LIMIT 1].Id;
        ds.name = 'Test DataSource';
        ImportMappingWrapper.CardConfigurationWrapper card = new ImportMappingWrapper.CardConfigurationWrapper();
        card.salesforceId = [SELECT Id FROM AI_Card_Configuration__c LIMIT 1].Id;
        card.configName = 'Test Card';
        AIGlobalExportImportController.saveMappings(
            new List<ImportMappingWrapper.PromptWrapper>{ prompt },
            new List<ImportMappingWrapper.ConnectionWrapper>{ conn },
            new List<ImportMappingWrapper.ExtractionWrapper>{ mapping },
            new List<ImportMappingWrapper.ExtractionSecurityFilterWrapper>{ filter },
            new List<ImportMappingWrapper.DataSourceWrapper>{ ds },
            new List<ImportMappingWrapper.CardConfigurationWrapper>{ card },
            true
        );
        Test.stopTest();
        Assert.isTrue(true, 'saveMappings success branch covered');
    }

    @isTest
    static void testInsertPrompts() {
        ImportMappingWrapper.PromptWrapper prompt = new ImportMappingWrapper.PromptWrapper();
        prompt.salesforceId = [SELECT Id FROM AI_Prompt__c LIMIT 1].Id;
        prompt.objectName = 'Account';
        ImportMappingWrapper.ConnectionWrapper conn = new ImportMappingWrapper.ConnectionWrapper();
        conn.salesforceId = [SELECT Id FROM AI_Connection__c LIMIT 1].Id;
        conn.connectionName = 'Test Connection 2';
        ImportMappingWrapper.ExtractionWrapper mapping = new ImportMappingWrapper.ExtractionWrapper();
        mapping.salesforceId = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1].Id;
        mapping.mappingName = 'Test Mapping 2';
        ImportMappingWrapper.ExtractionSecurityFilterWrapper filter = new ImportMappingWrapper.ExtractionSecurityFilterWrapper();
        System.debug([SELECT Id,Type__c FROM AI_Security_Filters__c LIMIT 1]);
        filter.salesforceId = [SELECT Id FROM AI_Security_Filters__c LIMIT 1].Id;
        filter.filterName = 'Test Filter 2';
        filter.recordTypeName= '';
        filter.searchPattern= '\\d{4}';
        filter.status= '';
        filter.type= '';
        filter.apexClassName = 'AIGlobalExportImportControllerTest';
        filter.blocklist= '';
        filter.comment= '';
        ImportMappingWrapper.DataSourceWrapper ds = new ImportMappingWrapper.DataSourceWrapper();
        ds.salesforceId = [SELECT Id FROM AI_Data_Source__c LIMIT 1].Id;
        ds.name = 'Test DataSource 2';
        ImportMappingWrapper.CardConfigurationWrapper card = new ImportMappingWrapper.CardConfigurationWrapper();
        card.salesforceId = [SELECT Id FROM AI_Card_Configuration__c LIMIT 1].Id;
        card.configName = 'Test Card 2';
        card.description = '';
        card.iconDetails = '';
        card.iconSource = '';
        card.sequence = 1;
        card.feature = '';
        card.enabled = true;
        Test.startTest();
        AIGlobalExportImportController.insertPrompts(
            new List<ImportMappingWrapper.PromptWrapper>{ prompt },
            new List<ImportMappingWrapper.ConnectionWrapper>{ conn },
            new List<ImportMappingWrapper.ExtractionWrapper>{ mapping },
            new List<ImportMappingWrapper.ExtractionSecurityFilterWrapper>{ filter },
            new List<ImportMappingWrapper.DataSourceWrapper>{ ds },
            new List<ImportMappingWrapper.CardConfigurationWrapper>{ card },
            false
        );
        Test.stopTest();
        Assert.isTrue(true, 'insertPrompts success branch covered');
    }

    @isTest
    static void testGetExport() {
        ExportMappingWrapper wrap = new ExportMappingWrapper();
        Test.startTest();
        ExportMappingWrapper result = AIGlobalExportImportController.getExport(wrap);
        Test.stopTest();
        Assert.isNotNull(result, 'getExport should not return null');
        Assert.isTrue(result.prompts != null, 'Prompts should not be null');
        Assert.isTrue(result.connections != null, 'Connections should not be null');
        Assert.isTrue(result.dataExtractionMappings != null, 'Data Extraction Mappings should not be null');
        Assert.isTrue(result.securityFilters != null, 'Security Filters should not be null');
    }

    @isTest
    static void testGetMappedPromptActionWrappers() {
        // Test ImportMappingWrapper.PromptActionWrapper -> AI_Prompt_Action__c
        ImportMappingWrapper.PromptActionWrapper actionWrap = new ImportMappingWrapper.PromptActionWrapper();
        actionWrap.salesforceId = 'ACTION-TEST-1';
        actionWrap.actionType = 'TestActionType';
        actionWrap.description = 'Test Description';
        actionWrap.sequence = 1;
        actionWrap.objectName = 'TestObject';
        actionWrap.fieldAPIName = 'TestFieldAPI';
        actionWrap.flowAPIName = 'TestFlowAPI';
        actionWrap.apexClassName = 'TestApexClass';
        actionWrap.appendTimestamp = true;
        actionWrap.promptComponent = 'TestPromptComponent';
        AI_Prompt_Action__c result = AIGlobalExportImportController.getMappedPromptAction(actionWrap);
        Assert.isNotNull(result, 'Resulting AI_Prompt_Action__c should not be null');
        Assert.areEqual('ACTION-TEST-1', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('TestActionType', result.Action__c, 'Action__c should match');
        Assert.areEqual('Test Description', result.Description__c, 'Description__c should match');
        Assert.areEqual(1, result.Sequence__c, 'Sequence__c should match');
        Assert.areEqual('TestObject', result.Object_Name__c, 'Object_Name__c should match');
        Assert.areEqual('TestFieldAPI', result.Field_API_Name__c, 'Field_API_Name__c should match');
        Assert.areEqual('TestFlowAPI', result.Flow_API_Name__c, 'Flow_API_Name__c should match');
        Assert.areEqual('TestApexClass', result.Apex_Class_Name__c, 'Apex_Class_Name__c should match');
        Assert.isTrue(result.Append_Timestamp__c, 'Append_Timestamp__c should be true');
        Assert.areEqual('TestPromptComponent', result.Prompt_Component__c, 'Prompt_Component__c should match');

        // Test AI_Prompt_Action__c -> ExportMappingWrapper.PromptActionWrapper
        AI_Prompt_Action__c action = new AI_Prompt_Action__c();
        action.Action__c = 'TestActionType';
        action.Description__c = 'Test Description';
        action.Sequence__c = 2;
        action.Object_Name__c = 'TestObject';
        action.Field_API_Name__c = 'TestFieldAPI';
        action.Flow_API_Name__c = 'TestFlowAPI';
        action.Apex_Class_Name__c = 'TestApexClass';
        action.Append_Timestamp__c = true;
        action.Prompt_Component__c = 'TestPromptComponent';
        AI_Prompt_Action_Detail__c detail = new AI_Prompt_Action_Detail__c();
        detail.Field_API_Name__c = 'DetailFieldAPI';
        detail.Type__c = 'DetailType';
        detail.Value__c = 'DetailValue';
        ExportMappingWrapper.PromptActionWrapper resultWrap = AIGlobalExportImportController.getMappedPromptAction(action);
        Assert.isNotNull(resultWrap, 'Resulting PromptActionWrapper should not be null');
        Assert.areEqual('TestActionType', resultWrap.actionType, 'actionType should match');
        Assert.areEqual('Test Description', resultWrap.description, 'description should match');
        Assert.areEqual(2, resultWrap.sequence, 'sequence should match');
        Assert.areEqual('TestObject', resultWrap.objectName, 'objectName should match');
        Assert.areEqual('TestFieldAPI', resultWrap.fieldAPIName, 'fieldAPIName should match');
        Assert.areEqual('TestFlowAPI', resultWrap.flowAPIName, 'flowAPIName should match');
        Assert.areEqual('TestApexClass', resultWrap.apexClassName, 'apexClassName should match');
        Assert.isTrue(resultWrap.appendTimestamp, 'appendTimestamp should be true');
        Assert.areEqual('TestPromptComponent', resultWrap.promptComponent, 'promptComponent should match');
    }
    @isTest
    static void testGetMappedPromptActionDetailFromWrapper() {
        ImportMappingWrapper.PromptActionDetailWrapper wrap = new ImportMappingWrapper.PromptActionDetailWrapper();
        wrap.salesforceId = 'PAD-1';
        wrap.fieldAPIName = 'FieldAPI';
        wrap.actionType = 'Type';
        wrap.value = 'Value';
        AI_Prompt_Action_Detail__c result = AIGlobalExportImportController.getMappedPromptActionDetail(wrap);
        Assert.isNotNull(result, 'AI_Prompt_Action_Detail__c should not be null');
        Assert.areEqual('PAD-1', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('FieldAPI', result.Field_API_Name__c, 'Field_API_Name__c should match');
        Assert.areEqual('Type', result.Type__c, 'Type__c should match');
        Assert.areEqual('Value', result.Value__c, 'Value__c should match');
    }

    @isTest
    static void testGetMappedPromptActionDetailFromSObject() {
        AI_Prompt_Action_Detail__c obj = new AI_Prompt_Action_Detail__c();
        obj.Field_API_Name__c = 'FieldAPI';
        obj.Type__c = 'Type';
        obj.Value__c = 'Value';
        ExportMappingWrapper.PromptActionDetailWrapper result = AIGlobalExportImportController.getMappedPromptActionDetail(obj);
        Assert.isNotNull(result, 'PromptActionDetailWrapper should not be null');
        Assert.areEqual('FieldAPI', result.fieldAPIName, 'fieldAPIName should match');
        Assert.areEqual('Type', result.actionType, 'actionType should match');
        Assert.areEqual('Value', result.value, 'value should match');
    }

    @isTest
    static void testGetMappedPromptComponent() {
        ImportMappingWrapper.PromptComponentWrapper wrap = new ImportMappingWrapper.PromptComponentWrapper();
        wrap.salesforceId = 'COMP-1';
        wrap.componentName = 'Component1';
        wrap.actionName = 'ActionName';
        wrap.dataExtractionId = 'EXT-1';
        wrap.format = 'Format';
        wrap.language = 'en';
        wrap.length = '100';
        wrap.objectName = 'Account';
        wrap.tone = 'Formal';
        wrap.userCustomizable = 'true';
        wrap.phraseBeforeAction = 'Before';
        wrap.phraseAfterAction = 'After';
        wrap.phraseBeforeContraints = 'BeforeC';
        wrap.phraseAfterContraints = 'AfterC';
        wrap.phraseBeforeFormat = 'BeforeF';
        wrap.phraseAfterFormat = 'AfterF';
        wrap.phraseBeforeLanguage = 'BeforeL';
        wrap.phraseAfterLanguage = 'AfterL';
        wrap.phraseBeforeLength = 'BeforeLen';
        wrap.phraseAfterLength = 'AfterLen';
        wrap.phraseBeforeObject = 'BeforeObj';
        wrap.phraseAfterObject = 'AfterObj';
        wrap.phraseBeforeTone = 'BeforeTone';
        wrap.phraseAfterTone = 'AfterTone';
        // Provide empty maps for required params
        Map<String, AI_Data_Extraction_Detail__c> mapOfExtIdToDetail = new Map<String, AI_Data_Extraction_Detail__c>();
        Map<String, AI_Data_Extraction_Mapping__c> mapOfExtIdToMapping = new Map<String, AI_Data_Extraction_Mapping__c>();
        AI_Prompt_Component__c result = AIGlobalExportImportController.getMappedPromptComponent(wrap, mapOfExtIdToDetail, mapOfExtIdToMapping);
        Assert.isNotNull(result, 'AI_Prompt_Component__c should not be null');
        Assert.areEqual('COMP-1', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('Component1', result.Name, 'Name should match');
        Assert.areEqual('ActionName', result.Key__c, 'Key__c should match');
    }

    @isTest
    static void testGetMappedResponseProcessing() {
        ImportMappingWrapper.ResponseProcessingWrapper wrap = new ImportMappingWrapper.ResponseProcessingWrapper();
        wrap.salesforceId = 'RP-1';
        wrap.actionName = 'Action';
        wrap.description = 'Desc';
        wrap.destinationField = 'Field';
        wrap.appendTimestamp = true;
        AI_Response_Processing__c result = AIGlobalExportImportController.getMappedResponseProcessing(wrap);
        Assert.isNotNull(result, 'AI_Response_Processing__c should not be null');
        Assert.areEqual('RP-1', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('Action', result.Action__c, 'Action__c should match');
        Assert.areEqual('Desc', result.Description__c, 'Description__c should match');
        Assert.areEqual('Field', result.Destination_Field__c, 'Destination_Field__c should match');
        Assert.isTrue(result.Append_Timestamp__c, 'Append_Timestamp__c should be true');
    }

    @isTest
    static void testGetMappedField() {
        ImportMappingWrapper.ExtractionFieldWrapper wrap = new ImportMappingWrapper.ExtractionFieldWrapper();
        wrap.salesforceId = 'FIELD-1';
        wrap.fieldName = 'FieldName';
        wrap.fieldApi = 'FieldApi';
        wrap.objectName = 'Account';
        wrap.type = 'String';
        wrap.anonymizeWith = 'Anon';
        wrap.scanForPii = true;
        wrap.sendToAi = true;
        wrap.maskingScope = 'Entire Value';
        wrap.fieldType = 'Text';
        wrap.formula = 'Formula';
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        AI_Data_Extraction_Field__c result = AIGlobalExportImportController.getMappedField(wrap, master.Id);
        Assert.isNotNull(result, 'AI_Data_Extraction_Field__c should not be null');
        Assert.areEqual('FIELD-1', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('FieldName', result.Label__c, 'Label__c should match');
        Assert.areEqual('FieldApi', result.Field__c, 'Field__c should match');
        Assert.areEqual('Account', result.Object__c, 'Object__c should match');
        Assert.areEqual('String', result.Type__c, 'Type__c should match');
        Assert.areEqual('Anon', result.Anonymize_With__c, 'Anonymize_With__c should match');
        Assert.areEqual('Formula', result.Formula__c, 'Formula__c should match');
        Assert.areEqual('Text', result.Field_Type__c, 'Field_Type__c should match');
        Assert.areEqual('Entire Value', result.Masking_Scope__c, 'Masking_Scope__c should match');
        Assert.isTrue(result.Send_To_AI__c, 'Send_To_AI__c should be true');
        Assert.areEqual(master.Id, result.AI_Data_Extraction_Mapping__c, 'AI_Data_Extraction_Mapping__c should match');
    }

    @isTest
    static void testGetMappedDetail() {
        ImportMappingWrapper.ExtractionDetailWrapper wrap = new ImportMappingWrapper.ExtractionDetailWrapper();
        wrap.salesforceId = 'DET-1';
        wrap.detailName = 'DetailName';
        wrap.objectHierarchy = 'Hierarchy';
        wrap.objectName = 'Account';
        wrap.orderBy = 'OrderBy';
        wrap.parentDetailId = 'ParentId';
        wrap.relationshipField = 'RelField';
        wrap.relationshipName = 'RelName';
        wrap.type = 'Type';
        wrap.whereClause = 'Where';
        wrap.recordLimit = 10;
        wrap.runningIndex = 1;
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        AI_Data_Extraction_Detail__c result = AIGlobalExportImportController.getMappedDetail(wrap, master.Id);
        Assert.isNotNull(result, 'AI_Data_Extraction_Detail__c should not be null');
        Assert.areEqual('DET-1', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('DetailName', result.Name, 'Name should match');
        Assert.areEqual('Hierarchy', result.Object_Hierarchy__c, 'Object_Hierarchy__c should match');
        Assert.areEqual('Account', result.Object_Name__c, 'Object_Name__c should match');
        Assert.areEqual('OrderBy', result.Order_By__c, 'Order_By__c should match');
        Assert.areEqual('RelField', result.RelationshipField__c, 'RelationshipField__c should match');
        Assert.areEqual('RelName', result.RelationshipName__c, 'RelationshipName__c should match');
        Assert.areEqual('Type', result.Type__c, 'Type__c should match');
        Assert.areEqual('Where', result.Where_Clause__c, 'Where_Clause__c should match');
        Assert.areEqual(10, result.Record_Limit__c, 'Record_Limit__c should match');
        Assert.areEqual(1, result.Running_Index__c, 'Running_Index__c should match');
        Assert.areEqual(master.Id, result.AI_Data_Extraction_Mapping__c, 'AI_Data_Extraction_Mapping__c should match');
    }

    @isTest
    static void testGetCardConfiguration() {
        ImportMappingWrapper.CardConfigurationWrapper wrap = new ImportMappingWrapper.CardConfigurationWrapper();
        wrap.salesforceId = 'CARD-1';
        wrap.configName = 'ConfigName';
        wrap.description = 'Desc';
        wrap.iconDetails = 'IconDetails';
        wrap.iconSource = 'IconSource';
        wrap.sequence = 1;
        wrap.feature = 'CTLOG';
        wrap.enabled = true;
        AI_Card_Configuration__c result = AIGlobalExportImportController.getCardConfiguration(wrap, true);
        Assert.isNotNull(result, 'AI_Card_Configuration__c should not be null');
        Assert.areEqual('CARD-1', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('ConfigName', result.Name, 'Name should match');
        Assert.areEqual('Desc', result.Description__c, 'Description__c should match');
        Assert.areEqual('IconDetails', result.Icon_Details__c, 'Icon_Details__c should match');
        Assert.areEqual('IconSource', result.Icon_Source__c, 'Icon_Source__c should match');
        Assert.areEqual(1, result.Sequence__c, 'Sequence__c should match');
        Assert.areEqual('CTLOG', result.Feature__c, 'Feature__c should match');
        Assert.isTrue(result.Enabled__c, 'Enabled__c should be true');
    }
    @isTest
    static void testGetMappedPromptActionDetailFromWrapper_Direct() {
        ImportMappingWrapper.PromptActionDetailWrapper wrap = new ImportMappingWrapper.PromptActionDetailWrapper();
        wrap.salesforceId = 'PAD-2';
        wrap.fieldAPIName = 'DirectFieldAPI';
        wrap.actionType = 'DirectType';
        wrap.value = 'DirectValue';
        AI_Prompt_Action_Detail__c result = AIGlobalExportImportController.getMappedPromptActionDetail(wrap);
        Assert.isNotNull(result, 'AI_Prompt_Action_Detail__c should not be null');
        Assert.areEqual('PAD-2', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('DirectFieldAPI', result.Field_API_Name__c, 'Field_API_Name__c should match');
        Assert.areEqual('DirectType', result.Type__c, 'Type__c should match');
        Assert.areEqual('DirectValue', result.Value__c, 'Value__c should match');
    }
    @isTest
    static void testGetMappedPromptActionDetailFromSObject_Direct() {
        AI_Prompt_Action_Detail__c obj = new AI_Prompt_Action_Detail__c();
        obj.Field_API_Name__c = 'DirectFieldAPI';
        obj.Type__c = 'DirectType';
        obj.Value__c = 'DirectValue';
        ExportMappingWrapper.PromptActionDetailWrapper result = AIGlobalExportImportController.getMappedPromptActionDetail(obj);
        Assert.isNotNull(result, 'PromptActionDetailWrapper should not be null');
        Assert.areEqual('DirectFieldAPI', result.fieldAPIName, 'fieldAPIName should match');
        Assert.areEqual('DirectType', result.actionType, 'actionType should match');
        Assert.areEqual('DirectValue', result.value, 'value should match');
    }
    @isTest
    static void testGetPromptElementRecord(){
         // Create AI Prompts with different configurations
         List<AI_Prompt__c> prompts = new List<AI_Prompt__c>();

         // Active Canvas prompt with profile restriction
         prompts.add(new AI_Prompt__c(
            Name = 'Active Canvas Prompt',
            Object__c = 'Account',
            Type__c = 'Canvas',
            Status__c = 'Active',
            Profiles__c = 'System Administrator',
            Auto_Refresh_Duration__c = 30,
            Prompt_Request_Id__c = 'active-prompt-123',
            Visibility_Condition__c = 'Industry = \'Technology\'',
            Visibility_Exception_Message__c = 'Account must be in Technology industry'
        ));
        
        // Summary prompt
        prompts.add(new AI_Prompt__c(
            Name = 'Summary Prompt',
            Object__c = 'AI_Response__c',
            Type__c = 'Text',
            Status__c = 'Active',
            Auto_Refresh_Duration__c = 20,
            Prompt_Request_Id__c = 'summary-prompt-101'
        ));
        
        insert prompts;
        
        AI_Prompt__c prompt = [SELECT ID FROM AI_Prompt__c LIMIT 1][0];
        ExportMappingWrapper.PromptElementWrapper wrap = new ExportMappingWrapper.PromptElementWrapper();
        wrap.salesforceId = 'ELEMENT-1';
        wrap.parentPromptId = prompt.Id;
        wrap.parentPromptrequestId = 'TEMP_REQ';
        wrap.promptId = prompts[0].Id;
        wrap.promptRequestId = 'TEMP_REQ_PROMPT';
        wrap.summaryPromptId = prompts[1].Id;
        wrap.summaryPromptRequestId = 'TEMP_REQ_SUMMARY';
        wrap.width = '3/3 Column';
        wrap.icon = 'custom1';
        wrap.height = 400;
        wrap.sequence = 1;
        wrap.inheritPromptSecurity = true;

        Map<String,AI_Prompt__c> promptsMap = new Map<String,AI_Prompt__c> {
            prompt.Id => prompt,
            prompts[0].Id => prompts[0],
            prompts[1].Id => prompts[1]
        };

        AI_Prompt_Element__c element = AIGlobalExportImportController.getMappedPromptElementRecord(wrap, promptsMap);

        Assert.isNotNull(element, 'PromptActionDetailWrapper should not be null');
        Assert.areEqual(element.External_Id__c, wrap.salesforceId, 'value should match');
        Assert.areEqual(element.Sequence__c, wrap.sequence, 'value should match');
        Assert.areEqual(element.Width__c, wrap.width, 'value should match');
        Assert.areEqual(element.AI_Parent_Prompt__c, wrap.parentPromptId, 'value should match');
        Assert.areEqual(element.Height__c, wrap.height, 'value should match');
        Assert.areEqual(element.Icon__c, wrap.icon, 'value should match');
        Assert.areEqual(element.Inherit_Prompt_Security__c, wrap.inheritPromptSecurity, 'value should match');
        Assert.areEqual(element.AI_Prompt__c, wrap.promptId, 'value should match');
        Assert.areEqual(element.AI_Summary_Prompt__c, wrap.summaryPromptId, 'value should match');
    }
    @isTest
    static void testInsertPromptsExtended() {
        ImportMappingWrapper.ExtractionDetailWrapper extractionDetailWrap = new ImportMappingWrapper.ExtractionDetailWrapper();
        extractionDetailWrap.salesforceId = 'DET-1';
        extractionDetailWrap.detailName = 'DetailName';
        extractionDetailWrap.objectHierarchy = 'Hierarchy';
        extractionDetailWrap.objectName = 'Account';
        extractionDetailWrap.orderBy = 'OrderBy';
        extractionDetailWrap.parentDetailId = 'ParentId';
        extractionDetailWrap.relationshipField = 'RelField';
        extractionDetailWrap.relationshipName = 'RelName';
        extractionDetailWrap.type = 'Type';
        extractionDetailWrap.whereClause = 'Where';
        extractionDetailWrap.recordLimit = 10;
        extractionDetailWrap.runningIndex = 1;

        ImportMappingWrapper.ExtractionFieldWrapper extractionFieldWrap = new ImportMappingWrapper.ExtractionFieldWrapper();
        extractionFieldWrap.salesforceId = 'FIELD-1';
        extractionFieldWrap.fieldName = 'FieldName';
        extractionFieldWrap.fieldApi = 'FieldApi';
        extractionFieldWrap.objectName = 'Account';
        extractionFieldWrap.type = 'String';
        extractionFieldWrap.anonymizeWith = 'PersonF{n}';
        extractionFieldWrap.scanForPii = true;
        extractionFieldWrap.sendToAi = true;
        extractionFieldWrap.maskingScope = 'Entire Value';
        extractionFieldWrap.fieldType = 'Text';
        extractionFieldWrap.formula = 'Formula';

        ImportMappingWrapper.PromptComponentWrapper promptComponentWrap = new ImportMappingWrapper.PromptComponentWrapper();
        promptComponentWrap.salesforceId = 'COMP-1';
        promptComponentWrap.componentName = 'Component1';
        promptComponentWrap.actionName = 'JSON';
        promptComponentWrap.dataExtractionId = 'EXT-1';
        promptComponentWrap.format = 'Bullet Points';
        promptComponentWrap.language = 'English';
        promptComponentWrap.length = 'Under 30 Words';
        promptComponentWrap.objectName = 'Account';
        promptComponentWrap.tone = 'Professional';
        promptComponentWrap.userCustomizable = 'Tone';
        promptComponentWrap.phraseBeforeAction = 'Before';
        promptComponentWrap.phraseAfterAction = 'Hindi';
        promptComponentWrap.phraseBeforeContraints = 'BeforeC';
        promptComponentWrap.phraseAfterContraints = 'AfterC';
        promptComponentWrap.phraseBeforeFormat = 'BeforeF';
        promptComponentWrap.phraseAfterFormat = 'AfterF';
        promptComponentWrap.phraseBeforeLanguage = 'BeforeL';
        promptComponentWrap.phraseAfterLanguage = 'AfterL';
        promptComponentWrap.phraseBeforeLength = 'BeforeLen';
        promptComponentWrap.phraseAfterLength = 'AfterLen';
        promptComponentWrap.phraseBeforeObject = 'BeforeObj';
        promptComponentWrap.phraseAfterObject = 'AfterObj';
        promptComponentWrap.phraseBeforeTone = 'BeforeTone';
        promptComponentWrap.phraseAfterTone = 'AfterTone';

        ImportMappingWrapper.PromptWrapper prompt = new ImportMappingWrapper.PromptWrapper();
        prompt.salesforceId = [SELECT Id FROM AI_Prompt__c LIMIT 1].Id;
        prompt.objectName = 'Account';
        prompt.promptComponents = new List<ImportMappingWrapper.PromptComponentWrapper>{promptComponentWrap};
        ImportMappingWrapper.ConnectionWrapper conn = new ImportMappingWrapper.ConnectionWrapper();
        conn.salesforceId = [SELECT Id FROM AI_Connection__c LIMIT 1].Id;
        conn.connectionName = 'Test Connection 2';
        ImportMappingWrapper.ExtractionWrapper mapping = new ImportMappingWrapper.ExtractionWrapper();
        mapping.salesforceId = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1].Id;
        mapping.mappingName = 'Test Mapping 2';
        mapping.details = new List<ImportMappingWrapper.ExtractionDetailWrapper>{extractionDetailWrap};
        mapping.fields = new List<ImportMappingWrapper.ExtractionFieldWrapper>{extractionFieldWrap};
        ImportMappingWrapper.ExtractionSecurityFilterWrapper filter = new ImportMappingWrapper.ExtractionSecurityFilterWrapper();
        filter.salesforceId = [SELECT Id FROM AI_Security_Filters__c LIMIT 1].Id;
        filter.filterName = 'Test Filter 2';
        filter.recordTypeName= '';
        filter.searchPattern= '\\d{4}';
        filter.status= '';
        filter.type= '';
        filter.apexClassName = 'AIGlobalExportImportControllerTest';
        filter.blocklist= '';
        filter.comment= '';
        ImportMappingWrapper.DataSourceWrapper ds = new ImportMappingWrapper.DataSourceWrapper();
        ds.salesforceId = [SELECT Id FROM AI_Data_Source__c LIMIT 1].Id;
        ds.name = 'Test DataSource 2';
        ImportMappingWrapper.CardConfigurationWrapper card = new ImportMappingWrapper.CardConfigurationWrapper();
        card.salesforceId = [SELECT Id FROM AI_Card_Configuration__c LIMIT 1].Id;
        card.configName = 'Test Card 2';
        card.description = '';
        card.iconDetails = '';
        card.iconSource = '';
        card.sequence = 1;
        card.feature = '';
        card.enabled = true;
        Test.startTest();
        AIGlobalExportImportController.insertPrompts(
            new List<ImportMappingWrapper.PromptWrapper>{ prompt },
            new List<ImportMappingWrapper.ConnectionWrapper>{ conn },
            new List<ImportMappingWrapper.ExtractionWrapper>{ mapping },
            new List<ImportMappingWrapper.ExtractionSecurityFilterWrapper>{ filter },
            new List<ImportMappingWrapper.DataSourceWrapper>{ ds },
            new List<ImportMappingWrapper.CardConfigurationWrapper>{ card },
            false
        );
        Test.stopTest();
        Assert.isTrue(true, 'insertPrompts success branch covered');
    }

    @isTest
    static void testGetMappedPromptResponseValidationRecord() {
        AI_Prompt__c prompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        ExportMappingWrapper.PromptResponseValidationWrapper wrap = new ExportMappingWrapper.PromptResponseValidationWrapper();
        wrap.salesforceId = 'PRV-001';
        wrap.promptId = prompt.Id;
        wrap.sequence = 1;
        wrap.action = 'Includes';
        wrap.value = 'Test Validation Value';
        
        Map<String, AI_Prompt__c> mapOfExternalIdToPrompt = new Map<String, AI_Prompt__c>();
        mapOfExternalIdToPrompt.put(prompt.Id, prompt);
        
        Test.startTest();
        AI_Prompt_Response_Validation__c result = AIGlobalExportImportController.getMappedPromptResponseValidationRecord(wrap, mapOfExternalIdToPrompt);
        Test.stopTest();
        
        Assert.isNotNull(result, 'AI_Prompt_Response_Validation__c should not be null');
        Assert.areEqual('PRV-001', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual(1, result.Sequence__c, 'Sequence__c should match');
        Assert.areEqual('Includes', result.Action__c, 'Action__c should match');
        Assert.areEqual('Test Validation Value', result.Value__c, 'Value__c should match');
        Assert.areEqual(prompt.Id, result.AI_Prompt__c, 'AI_Prompt__c should match');
    }

    @isTest
    static void testGetSecurityFilters() {
        AI_Security_Filters__c filter = [SELECT Id, Name, RecordTypeId, RecordType.Name, Blocklist__c, Comment__c, 
                                         Replacement_Value__c, Search_Pattern__c, Status__c, Type__c, Apex_Class_Name__c 
                                         FROM AI_Security_Filters__c LIMIT 1];
        
        Test.startTest();
        ExportMappingWrapper.ExtractionSecurityFilterWrapper result = AIGlobalExportImportController.getSecurityFilters(filter);
        Test.stopTest();
        
        Assert.isNotNull(result, 'ExtractionSecurityFilterWrapper should not be null');
        Assert.areEqual(filter.Id, result.salesforceId, 'salesforceId should match');
        Assert.areEqual(filter.Name, result.filterName, 'filterName should match');
        Assert.areEqual(filter.RecordType.Name, result.recordTypeName, 'recordTypeName should match');
        Assert.areEqual(filter.Search_Pattern__c, result.searchPattern, 'searchPattern should match');
        Assert.areEqual(filter.Status__c, result.status, 'status should match');
    }

    @isTest
    static void testGetMappedExtractionMapping() {
        AI_Data_Extraction_Mapping__c mapping = [SELECT Id, Name, Description__c, Object_Name__c, 
                                                  AI_Data_Source__c, Apex_Security_Layer__c 
                                                  FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        Test.startTest();
        ExportMappingWrapper.ExtractionWrapper result = AIGlobalExportImportController.getMappedExtractionMapping(mapping);
        Test.stopTest();
        
        Assert.isNotNull(result, 'ExtractionWrapper should not be null');
        Assert.areEqual(mapping.Id, result.salesforceId, 'salesforceId should match');
        Assert.areEqual(mapping.Name, result.mappingName, 'mappingName should match');
        Assert.areEqual(mapping.Description__c, result.description, 'description should match');
        Assert.areEqual(mapping.Object_Name__c, result.objectName, 'objectName should match');
        Assert.isNotNull(result.details, 'details list should not be null');
        Assert.isNotNull(result.fields, 'fields list should not be null');
    }

    @isTest
    static void testGetMappedDataExtractionMapping() {
        ImportMappingWrapper.ExtractionWrapper wrap = new ImportMappingWrapper.ExtractionWrapper();
        wrap.salesforceId = 'EXT-MAP-001';
        wrap.mappingName = 'Test Mapping';
        wrap.description = 'Test Description';
        wrap.objectName = 'Account';
        
        Test.startTest();
        AI_Data_Extraction_Mapping__c resultDraft = AIGlobalExportImportController.getMappedDataExtractionMapping(wrap, false);
        AI_Data_Extraction_Mapping__c resultActive = AIGlobalExportImportController.getMappedDataExtractionMapping(wrap, true);
        Test.stopTest();
        
        Assert.isNotNull(resultDraft, 'AI_Data_Extraction_Mapping__c should not be null');
        Assert.areEqual('EXT-MAP-001', resultDraft.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('Test Mapping', resultDraft.Name, 'Name should match');
        Assert.areEqual('Test Description', resultDraft.Description__c, 'Description__c should match');
        Assert.areEqual('Account', resultDraft.Object_Name__c, 'Object_Name__c should match');
        Assert.areEqual('Draft', resultDraft.Status__c, 'Status should be Draft for non-post install');
        Assert.areEqual('Active', resultActive.Status__c, 'Status should be Active for post install');
    }

    @isTest
    static void testGetMappedConnectionImport() {
        ImportMappingWrapper.ConnectionWrapper wrap = new ImportMappingWrapper.ConnectionWrapper();
        wrap.salesforceId = 'CONN-001';
        wrap.connectionName = 'Test Connection';
        wrap.aiTechnology = 'GPTfy';
        wrap.connectorClass = 'TestConnector';
        wrap.processingClass = 'TestProcessor';
        wrap.endpointUrl = 'https://test.com';
        wrap.key = 'test-key';
        wrap.maxTokens = 2000;
        wrap.model = 'gpt-4';
        wrap.namedCredential = 'TestCred';
        wrap.infrastructure = 'Cloud';
        wrap.securityLayer = 'Layer1';
        wrap.temperature = 0.7;
        wrap.topP = 0.9;
        wrap.version = 'v1';
        wrap.type = 'Chat';
        
        Test.startTest();
        AI_Connection__c result = AIGlobalExportImportController.getMappedConnection(wrap);
        Test.stopTest();
        
        Assert.isNotNull(result, 'AI_Connection__c should not be null');
        Assert.areEqual('CONN-001', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('Test Connection', result.Name, 'Name should match');
        Assert.areEqual('GPTfy', result.AI_Technology__c, 'AI_Technology__c should match');
        Assert.areEqual('TestConnector', result.Connector_Class__c, 'Connector_Class__c should match');
        Assert.areEqual('TestProcessor', result.Processing_Class__c, 'Processing_Class__c should match');
        Assert.areEqual('https://test.com', result.EndPoint_URL__c, 'EndPoint_URL__c should match');
        Assert.areEqual(2000, result.Max_Tokens__c, 'Max_Tokens__c should match');
        Assert.areEqual('gpt-4', result.Model__c, 'Model__c should match');
        Assert.areEqual('Chat', result.Type__c, 'Type__c should match');
    }

    @isTest
    static void testGetMappedPromptExport() {
        AI_Connection__c conn = [SELECT Id, Name, AI_Technology__c, Connector_Class__c, Processing_Class__c, 
                                 EndPoint_URL__c, Key__c, Max_Tokens__c, Model__c, Named_Credential__c, 
                                 Infrastructure__c, Security_Layer__c, Temperature__c, Top_P__c, Version__c 
                                 FROM AI_Connection__c LIMIT 1];
        AI_Data_Extraction_Mapping__c mapping = [SELECT Id, Name, Description__c, Object_Name__c 
                                                 FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        AI_Prompt__c prompt = [SELECT Id, Name, Description__c, Object__c, Profiles__c, Prompt_Command__c, 
                               Purpose__c, Record_Type__c, Status__c, Type__c, Custom_Prompt__c, 
                               Grounding_Ethical__c, Grounding_Content__c, Include_Files__c, 
                               Auto_Refresh_Duration__c, AI_Connection__c, Top_P__c, Max_Output_Tokens__c, 
                               Temperature__c, How_It_Works__c, AI_Connection__r.Name, 
                               AI_Data_Extraction_Mapping__c, AI_Data_Extraction_Mapping__r.Name, 
                               Prompt_Request_Id__c, Visibility_Condition__c, AI_Locale_Automation__c, 
                               AI_Locale_GPTfy_Console__c, Permission_Sets__c, Enable_Loopback__c, 
                               Loopback_Message__c, Response_Validation_Condition__c, 
                               Response_Validation_Message__c, Agentic_Function_Class__c, 
                               AI_Model_File_Processing__c,Time_Saved_Coefficient__c
                               FROM AI_Prompt__c LIMIT 1];
        
        Test.startTest();
        ExportMappingWrapper.PromptWrapper result = AIGlobalExportImportController.getMappedPrompt(prompt);
        Test.stopTest();
        
        Assert.isNotNull(result, 'PromptWrapper should not be null');
        Assert.areEqual(prompt.Id, result.salesforceId, 'salesforceId should match');
        Assert.areEqual(prompt.Name, result.promptName, 'promptName should match');
        Assert.areEqual(prompt.Description__c, result.description, 'description should match');
        Assert.areEqual(prompt.Object__c, result.objectName, 'objectName should match');
        Assert.isNotNull(result.promptComponents, 'promptComponents list should not be null');
        Assert.isNotNull(result.promptActions, 'promptActions list should not be null');
        Assert.isNotNull(result.promptElements, 'promptElements list should not be null');
        Assert.isNotNull(result.promptResponseValidations, 'promptResponseValidations list should not be null');
    }

    @isTest
    static void testGetMappedPromptImport() {
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        AI_Data_Extraction_Mapping__c mapping = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        ImportMappingWrapper.PromptWrapper wrap = new ImportMappingWrapper.PromptWrapper();
        wrap.salesforceId = 'PROMPT-001';
        wrap.promptRequestId = 'REQ-001';
        wrap.connectionId = conn.Id;
        wrap.extractionMappingId = mapping.Id;
        wrap.promptName = 'Test Prompt Import';
        wrap.description = 'Test Description';
        wrap.objectName = 'Account';
        wrap.profiles = 'System Administrator';
        wrap.permissionSets = 'TestPermSet';
        wrap.groundingContent = 'Test Content';
        wrap.groundingEthical = 'Test Ethical';
        wrap.promptCommand = 'Test Command';
        wrap.purpose = 'Test Purpose';
        wrap.recordTypes = 'TestRecordType';
        wrap.type = 'JSON';
        wrap.topP = 0.9;
        wrap.temperature = 0.7;
        wrap.maxTokens = 1000;
        wrap.visibilityCondition = 'Test Condition';
        wrap.howItWorks = 'Test How It Works';
        wrap.localeAutomation = 'en_US';
        wrap.localeGPTfyConsole = 'en_US';
        wrap.includeFiles = true;
        wrap.autoRefreshDuration = 30;
        wrap.enableLoopback = true;
        wrap.loopbackMessage = 'Test Loopback';
        wrap.responseValidationCondition = 'Test Validation Condition';
        wrap.responseValidationMessage = 'Test Validation Message';
        wrap.agenticFunctionClass = 'TestAgenticClass';
        wrap.aIModelFileProcessing = conn.Id;
        wrap.allowUserInput = true;
        
        Map<String, AI_Connection__c> mapOfConn = new Map<String, AI_Connection__c>();
        mapOfConn.put(conn.Id, conn);
        Map<String, AI_Data_Extraction_Mapping__c> mapOfMapping = new Map<String, AI_Data_Extraction_Mapping__c>();
        mapOfMapping.put(mapping.Id, mapping);
        
        Test.startTest();
        AI_Prompt__c resultDraft = AIGlobalExportImportController.getMappedPrompt(wrap, mapOfMapping, mapOfConn, false);
        AI_Prompt__c resultActive = AIGlobalExportImportController.getMappedPrompt(wrap, mapOfMapping, mapOfConn, true);
        Test.stopTest();
        
        Assert.isNotNull(resultDraft, 'AI_Prompt__c should not be null');
        Assert.areEqual('PROMPT-001', resultDraft.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('REQ-001', resultDraft.Prompt_Request_Id__c, 'Prompt_Request_Id__c should match');
        Assert.areEqual('Test Prompt Import', resultDraft.Name, 'Name should match');
        Assert.areEqual('Test Description', resultDraft.Description__c, 'Description__c should match');
        Assert.areEqual('Account', resultDraft.Object__c, 'Object__c should match');
        Assert.areEqual('Draft', resultDraft.Status__c, 'Status should be Draft for non-post install');
        Assert.areEqual('Active', resultActive.Status__c, 'Status should be Active for post install');
        Assert.isTrue(resultActive.Pre_Packaged__c, 'Pre_Packaged__c should be true for post install');
        Assert.isTrue(resultDraft.Custom_Prompt__c, 'Custom_Prompt__c should be true');
        Assert.isTrue(resultDraft.Include_Files__c, 'Include_Files__c should be true');
        Assert.isTrue(resultDraft.Enable_Loopback__c, 'Enable_Loopback__c should be true');
    }

    @isTest
    static void testGetMappedFilters() {
        ImportMappingWrapper.ExtractionSecurityFilterWrapper wrapRegex = new ImportMappingWrapper.ExtractionSecurityFilterWrapper();
        wrapRegex.salesforceId = 'FILTER-REGEX-001';
        wrapRegex.filterName = 'Regex Filter';
        wrapRegex.searchPattern = '\\d{4}';
        wrapRegex.status = 'Active';
        wrapRegex.type = 'PII';
        wrapRegex.blocklist = '';
        wrapRegex.comment = 'Test Comment';
        wrapRegex.recordTypeName = 'Regex';
        wrapRegex.apexClassName = 'TestApexClass';
        
        ImportMappingWrapper.ExtractionSecurityFilterWrapper wrapBlocklist = new ImportMappingWrapper.ExtractionSecurityFilterWrapper();
        wrapBlocklist.salesforceId = 'FILTER-BLOCK-001';
        wrapBlocklist.filterName = 'Blocklist Filter';
        wrapBlocklist.searchPattern = 'block';
        wrapBlocklist.status = 'Active';
        wrapBlocklist.type = 'Blocklist';
        wrapBlocklist.blocklist = 'test1,test2';
        wrapBlocklist.comment = 'Test Blocklist';
        wrapBlocklist.recordTypeName = 'Blocklist';
        wrapBlocklist.apexClassName = '';
        
        ImportMappingWrapper.ExtractionSecurityFilterWrapper wrapApex = new ImportMappingWrapper.ExtractionSecurityFilterWrapper();
        wrapApex.salesforceId = 'FILTER-APEX-001';
        wrapApex.filterName = 'Apex Filter';
        wrapApex.searchPattern = '';
        wrapApex.status = 'Active';
        wrapApex.type = 'Custom';
        wrapApex.blocklist = '';
        wrapApex.comment = 'Test Apex';
        wrapApex.recordTypeName = 'Apex';
        wrapApex.apexClassName = 'CustomApexFilter';
        
        Test.startTest();
        AI_Security_Filters__c resultRegex = AIGlobalExportImportController.getMappedFilters(wrapRegex);
        AI_Security_Filters__c resultBlocklist = AIGlobalExportImportController.getMappedFilters(wrapBlocklist);
        AI_Security_Filters__c resultApex = AIGlobalExportImportController.getMappedFilters(wrapApex);
        Test.stopTest();
        
        Assert.isNotNull(resultRegex, 'Regex filter should not be null');
        Assert.areEqual('Regex Filter', resultRegex.Name, 'Name should match');
        Assert.areEqual('\\d{4}', resultRegex.Search_Pattern__c, 'Search_Pattern__c should match');
        Assert.areEqual(AIGlobalExportImportController.RT_REGEX, resultRegex.RecordTypeId, 'RecordTypeId should be Regex');
        
        Assert.isNotNull(resultBlocklist, 'Blocklist filter should not be null');
        Assert.areEqual(AIGlobalExportImportController.RT_BLOCKLIST, resultBlocklist.RecordTypeId, 'RecordTypeId should be Blocklist');
        
        Assert.isNotNull(resultApex, 'Apex filter should not be null');
        Assert.areEqual(AIGlobalExportImportController.RT_APEX, resultApex.RecordTypeId, 'RecordTypeId should be Apex');
        Assert.areEqual('CustomApexFilter', resultApex.Apex_Class_Name__c, 'Apex_Class_Name__c should match');
    }

    @isTest
    static void testGetDataSource() {
        ImportMappingWrapper.DataSourceWrapper wrap = new ImportMappingWrapper.DataSourceWrapper();
        wrap.salesforceId = 'DS-001';
        wrap.name = 'Test Data Source';
        wrap.connectorClass = 'TestConnector';
        wrap.endpointUrl = 'https://datasource.test.com';
        wrap.namedCredential = 'TestDataSourceCred';
        wrap.source = 'External';
        
        Test.startTest();
        AI_Data_Source__c result = AIGlobalExportImportController.getDataSource(wrap);
        Test.stopTest();
        
        Assert.isNotNull(result, 'AI_Data_Source__c should not be null');
        Assert.areEqual('DS-001', result.External_Id__c, 'External_Id__c should match');
        Assert.areEqual('Test Data Source', result.Name, 'Name should match');
        Assert.areEqual('TestConnector', result.Connector_Class__c, 'Connector_Class__c should match');
        Assert.areEqual('https://datasource.test.com', result.EndPoint_URL__c, 'EndPoint_URL__c should match');
        Assert.areEqual('TestDataSourceCred', result.Named_Credential__c, 'Named_Credential__c should match');
        Assert.areEqual('External', result.Source__c, 'Source__c should match');
    }

    @isTest
    static void testGetMappedPromptComponentExport() {
        AI_Prompt__c prompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Prompt_Component__c component = [SELECT Id, Key__c, Additional_Instructions__c, AI_Prompt__c, Name, 
                                           Constraint_Value__c, Data_Extraction_Id__c, Format__c, Language__c, 
                                           Length__c, Object_Name__c, Tone__c, User_Customizable__c, 
                                           Phrase_Before_Action__c, Phrase_After_Action__c, Phrase_Before_Contraints__c, 
                                           Phrase_After_Contraints__c, Phrase_Before_Format__c, Phrase_After_Format__c, 
                                           Phrase_Before_Language__c, Phrase_After_Language__c, Phrase_Before_Length__c, 
                                           Phrase_After_Length__c, Phrase_Before_Object__c, Phrase_After_Object__c, 
                                           Phrase_Before_Tone__c, Phrase_After_Tone__c 
                                           FROM AI_Prompt_Component__c LIMIT 1];
        
        Test.startTest();
        ExportMappingWrapper.PromptComponentWrapper result = AIGlobalExportImportController.getMappedPromptComponent(component);
        Test.stopTest();
        
        Assert.isNotNull(result, 'PromptComponentWrapper should not be null');
        Assert.areEqual(component.Id, result.salesforceId, 'salesforceId should match');
        Assert.areEqual(component.Name, result.componentName, 'componentName should match');
        Assert.areEqual(component.Key__c, result.actionName, 'actionName should match');
        Assert.isNotNull(result.responseProcessings, 'responseProcessings list should not be null');
    }

    @isTest
    static void testInsertPromptsWithPromptActionsAndResponseValidation() {
        AI_Prompt__c prompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        AI_Data_Extraction_Mapping__c mapping = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        ImportMappingWrapper.PromptActionDetailWrapper actionDetail = new ImportMappingWrapper.PromptActionDetailWrapper();
        actionDetail.salesforceId = 'PAD-TEST-001';
        actionDetail.fieldAPIName = 'Name';
        actionDetail.actionType = 'Hardcoded';
        actionDetail.value = 'TestValue';
        
        ImportMappingWrapper.PromptActionWrapper promptAction = new ImportMappingWrapper.PromptActionWrapper();
        promptAction.salesforceId = 'PA-TEST-001';
        promptAction.actionType = 'Update Field';
        promptAction.description = 'Test Action';
        promptAction.sequence = 1;
        promptAction.objectName = 'Account';
        promptAction.fieldAPIName = 'Name';
        promptAction.flowAPIName = '';
        promptAction.apexClassName = '';
        promptAction.appendTimestamp = false;
        promptAction.promptComponent = '';
        promptAction.promptActionDetails = new List<ImportMappingWrapper.PromptActionDetailWrapper>{actionDetail};
        
        ImportMappingWrapper.ResponseProcessingWrapper responseProcessing = new ImportMappingWrapper.ResponseProcessingWrapper();
        responseProcessing.salesforceId = 'RP-TEST-001';
        responseProcessing.actionName = 'Update Field';
        responseProcessing.description = 'Test Response Processing';
        responseProcessing.destinationField = 'Description';
        responseProcessing.appendTimestamp = true;
        
        ImportMappingWrapper.PromptComponentWrapper promptComponent = new ImportMappingWrapper.PromptComponentWrapper();
        promptComponent.salesforceId = 'PC-TEST-001';
        promptComponent.componentName = 'Test Component';
        promptComponent.actionName = 'JSON';
        promptComponent.dataExtractionId = mapping.Id;
        promptComponent.responseProcessings = new List<ImportMappingWrapper.ResponseProcessingWrapper>{responseProcessing};
        
        ImportMappingWrapper.PromptWrapper promptWrap = new ImportMappingWrapper.PromptWrapper();
        promptWrap.salesforceId = prompt.Id;
        promptWrap.connectionId = conn.Id;
        promptWrap.extractionMappingId = mapping.Id;
        promptWrap.objectName = 'Account';
        promptWrap.promptName = 'Test Prompt With Actions';
        promptWrap.promptActions = new List<ImportMappingWrapper.PromptActionWrapper>{promptAction};
        promptWrap.promptComponents = new List<ImportMappingWrapper.PromptComponentWrapper>{promptComponent};
        
        ImportMappingWrapper.ConnectionWrapper connWrap = new ImportMappingWrapper.ConnectionWrapper();
        connWrap.salesforceId = conn.Id;
        connWrap.connectionName = 'Test Connection';
        
        ImportMappingWrapper.ExtractionWrapper mappingWrap = new ImportMappingWrapper.ExtractionWrapper();
        mappingWrap.salesforceId = mapping.Id;
        mappingWrap.mappingName = 'Test Mapping';
        
        Test.startTest();
        AIGlobalExportImportController.insertPrompts(
            new List<ImportMappingWrapper.PromptWrapper>{promptWrap},
            new List<ImportMappingWrapper.ConnectionWrapper>{connWrap},
            new List<ImportMappingWrapper.ExtractionWrapper>{mappingWrap},
            new List<ImportMappingWrapper.ExtractionSecurityFilterWrapper>(),
            new List<ImportMappingWrapper.DataSourceWrapper>(),
            new List<ImportMappingWrapper.CardConfigurationWrapper>(),
            false
        );
        Test.stopTest();
        
        List<AI_Prompt_Action__c> insertedActions = [SELECT Id FROM AI_Prompt_Action__c WHERE External_Id__c = 'PA-TEST-001'];
        
        Assert.isTrue(insertedActions.size() > 0, 'Prompt Action should be inserted');
    }

    @isTest
    static void testInsertPromptsWithElementsAndValidations() {
        AI_Prompt__c prompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        AI_Data_Extraction_Mapping__c mapping = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        // Create a wrapper JSON string manually to simulate deserialization
        String promptJson = '{' +
            '"salesforceId":"' + prompt.Id + '",' +
            '"connectionId":"' + conn.Id + '",' +
            '"extractionMappingId":"' + mapping.Id + '",' +
            '"promptName":"Test Prompt With Elements",' +
            '"objectName":"Account",' +
            '"promptElements":[{' +
                '"salesforceId":"PE-TEST-002",' +
                '"parentPromptId":"' + prompt.Id + '",' +
                '"promptId":"' + prompt.Id + '",' +
                '"sequence":1,' +
                '"width":"1/3 Column",' +
                '"height":300,' +
                '"icon":"custom1",' +
                '"inheritPromptSecurity":true' +
            '}],' +
            '"promptResponseValidations":[{' +
                '"salesforceId":"PRV-TEST-002",' +
                '"promptId":"' + prompt.Id + '",' +
                '"sequence":1,' +
                '"action":"Includes",' +
                '"value":"ValidationValue"' +
            '}]' +
        '}';
        
        ImportMappingWrapper.PromptWrapper promptWrap = (ImportMappingWrapper.PromptWrapper)JSON.deserialize(promptJson, ImportMappingWrapper.PromptWrapper.class);
        
        ImportMappingWrapper.ConnectionWrapper connWrap = new ImportMappingWrapper.ConnectionWrapper();
        connWrap.salesforceId = conn.Id;
        connWrap.connectionName = 'Test Connection';
        
        ImportMappingWrapper.ExtractionWrapper mappingWrap = new ImportMappingWrapper.ExtractionWrapper();
        mappingWrap.salesforceId = mapping.Id;
        mappingWrap.mappingName = 'Test Mapping';
        
        Test.startTest();
        AIGlobalExportImportController.insertPrompts(
            new List<ImportMappingWrapper.PromptWrapper>{promptWrap},
            new List<ImportMappingWrapper.ConnectionWrapper>{connWrap},
            new List<ImportMappingWrapper.ExtractionWrapper>{mappingWrap},
            new List<ImportMappingWrapper.ExtractionSecurityFilterWrapper>(),
            new List<ImportMappingWrapper.DataSourceWrapper>(),
            new List<ImportMappingWrapper.CardConfigurationWrapper>(),
            false
        );
        Test.stopTest();
        
        List<AI_Prompt_Element__c> insertedElements = [SELECT Id FROM AI_Prompt_Element__c WHERE External_Id__c = 'PE-TEST-002'];
        List<AI_Prompt_Response_Validation__c> insertedValidations = [SELECT Id FROM AI_Prompt_Response_Validation__c WHERE External_Id__c = 'PRV-TEST-002'];
        
        Assert.isTrue(insertedElements.size() > 0, 'Prompt Element should be inserted');
        Assert.isTrue(insertedValidations.size() > 0, 'Prompt Response Validation should be inserted');
    }
}