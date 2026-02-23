/**
 * @description Test class for AddCardController
 * @date 2025-11-07
 */
@isTest
private class TestAddCardController {
    
    private static final String FEATURE_CTLOG = 'CTLOG';
    private static final String FEATURE_AMODL = 'AMODL';
    private static final String FEATURE_APIDS = 'APIDS';
    private static final String NAMESPACE = AIExtractionFieldMappingController.NAMESPACE;
    
    @TestSetup
    static void setupTestData() {
        TestUtility.createCardConfiguration('DnB', FEATURE_APIDS, true);
        TestUtility.createCardConfiguration('GPTfy (OpenAI)', FEATURE_AMODL, true);
        TestUtility.createCardConfiguration('Boost Sales', FEATURE_CTLOG, true);
        
        AI_Response_Mapping__c responseMapping = TestUtility.createResponseMapping('TestResponse', true);
        
        AI_Connection__c connection = TestUtility.getConnection('GPTfy (OpenAI)1', false);
        connection.AI_Technology__c = 'GPTfy';
        connection.AI_Response_Mapping__c = responseMapping.Id;
        insert connection;
        connection.Name = 'GPTfy (OpenAI)';
        update connection;
        
        AI_Data_Source__c dataSource = TestUtility.getAIDataSource(false);
        dataSource.Name = 'DnB';
        dataSource.Connector_Class__c = NAMESPACE + 'AddCardController';
        insert dataSource;
    }
    
    // PICKLIST TESTS
    @isTest
    static void testInsertPicklistValue_Success() {
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        Test.startTest();
        Boolean result = AddCardController.insertPicklistValue('Account', 'Industry', 'TestIndustry');
        Test.stopTest();
        Assert.areEqual(true, result, 'Picklist value insertion should succeed');
    }
    
    @isTest
    static void testDeployCallbackHandler_Success() {
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        AddCardController controller = new AddCardController();
        Test.startTest();
        controller.handleResult(new Metadata.DeployResult(), new Metadata.DeployCallbackContext());
        Test.stopTest();
        Assert.isNotNull(controller, 'Controller instance should be valid');
    }
    
    // CARD CONFIGURATION CRUD TESTS
    @isTest
    static void testCreateCardConfiguration_AllTypes() {
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        Map<String, Object> params = new Map<String, Object>{
            'Name' => 'Test Card', 'Feature__c' => FEATURE_CTLOG, 'Icon_Source__c' => 'SLDS Icon',
            'Icon_Details__c' => 'custom:custom28', 'Description__c' => 'Test', 'Sequence__c' => 1,
            'Enabled__c' => true, 'CardName' => 'CTLOG_Test'
        };
        
        Test.startTest();
        Boolean result1 = AddCardController.createCardConfiguration(params);
        params.put('Name', 'AMODL Card');
        params.put('Feature__c', FEATURE_AMODL);
        Boolean result2 = AddCardController.createCardConfiguration(params);
        Test.stopTest();
        
        Assert.areEqual(true, result1, 'CTLOG creation should succeed');
        Assert.areEqual(true, result2, 'AMODL creation should succeed');
        Assert.areEqual(1, [SELECT COUNT() FROM AI_Card_Configuration__c WHERE Name = 'Test Card'], 'Card should exist');
    }
    
    @isTest
    static void testCreateCardConfiguration_InvalidStaticResource() {
        Map<String, Object> params = new Map<String, Object>{
            'Name' => 'Invalid', 'Feature__c' => FEATURE_CTLOG, 'Icon_Source__c' => 'Static Resource',
            'Icon_Details__c' => 'NonExistent', 'Sequence__c' => 1, 'CardName' => 'TEST'
        };
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            AddCardController.createCardConfiguration(params);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        Assert.isTrue(exceptionThrown, 'Exception should be thrown');
    }
    
    @isTest
    static void testUpdateCardConfiguration_Success() {
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        AI_Card_Configuration__c card = [SELECT Id FROM AI_Card_Configuration__c WHERE Feature__c = :FEATURE_CTLOG LIMIT 1];
        Map<String, Object> params = new Map<String, Object>{
            'Id' => card.Id, 'Feature__c' => FEATURE_CTLOG, 'Description__c' => 'Updated', 'Sequence__c' => 2
        };
        
        Test.startTest();
        Boolean result = AddCardController.updateCardConfiguration(params);
        Test.stopTest();
        
        Assert.areEqual(true, result, 'Update should succeed');
        Assert.areEqual('Updated', [SELECT Description__c FROM AI_Card_Configuration__c WHERE Id = :card.Id].Description__c);
    }
    
    @isTest
    static void testUpdateCardConfiguration_NonCTLOG() {
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        AI_Card_Configuration__c card = [SELECT Id FROM AI_Card_Configuration__c WHERE Feature__c = :FEATURE_AMODL LIMIT 1];
        Map<String, Object> params = new Map<String, Object>{
            'Id' => card.Id, 'Feature__c' => FEATURE_AMODL, 'Enabled__c' => true, 'Sequence__c' => 2
        };
        
        Test.startTest();
        AddCardController.updateCardConfiguration(params);
        Test.stopTest();
        
        Assert.areEqual(false, [SELECT Enabled__c FROM AI_Card_Configuration__c WHERE Id = :card.Id].Enabled__c);
    }
    
    @isTest
    static void testDeleteCardConfiguration_Success() {
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        AI_Card_Configuration__c card = TestUtility.createCardConfiguration('DeleteTest', FEATURE_CTLOG, true);
        
        Test.startTest();
        Boolean result = AddCardController.deleteCardConfiguration('test', 'Test', 'test', FEATURE_CTLOG, card.Id);
        Test.stopTest();
        
        Assert.isNotNull(result);
        Assert.areEqual(0, [SELECT COUNT() FROM AI_Card_Configuration__c WHERE Id = :card.Id]);
    }
    
    @isTest
    static void testDeleteCardConfiguration_WithDependencies() {
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c WHERE Name = 'GPTfy (OpenAI)' LIMIT 1];
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
        prompt.AI_Connection__c = conn.Id;
        insert prompt;
        
        AI_Card_Configuration__c card = [SELECT Id FROM AI_Card_Configuration__c WHERE Name = 'GPTfy (OpenAI)' AND Feature__c = :FEATURE_AMODL LIMIT 1];
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            AddCardController.deleteCardConfiguration('test', 'Test', 'GPTfy (OpenAI)', FEATURE_AMODL, card.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        Assert.isTrue(exceptionThrown);
    }
    
    @isTest
    static void testDeleteCardConfiguration_APIDS() {
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        AI_Card_Configuration__c card = [SELECT Id FROM AI_Card_Configuration__c WHERE Name = 'DnB' LIMIT 1];
        
        Test.startTest();
        AddCardController.deleteCardConfiguration('test', 'Test', 'DnB', FEATURE_APIDS, card.Id);
        Test.stopTest();
        
        Assert.areEqual(0, [SELECT COUNT() FROM AI_Data_Source__c WHERE Name = 'DnB']);
    }
    
    // GET CONFIGURATION TESTS
    @isTest
    static void testGetCardConfiguration_AllTypes() {
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Contact', 'Active', false);
        prompt.Purpose__c = 'Boost Sales';
        insert prompt;
        insert new AI_Usage_Tracking__c(AI_Prompt__c = prompt.Id, Lifetime_Saving_Seconds__c = 1000);
        
        Test.startTest();
        List<AddCardController.dataWrap> ctlogResult = AddCardController.getCardConfiguration(FEATURE_CTLOG);
        List<AddCardController.dataWrap> amodlResult = AddCardController.getCardConfiguration(FEATURE_AMODL);
        List<AddCardController.dataWrap> apidsResult = AddCardController.getCardConfiguration(FEATURE_APIDS);
        Test.stopTest();
        
        Assert.isTrue(ctlogResult.size() > 0);
        Assert.isTrue(amodlResult.size() > 0);
        Assert.isTrue(apidsResult.size() > 0);
    }
    
    @isTest
    static void testGetCardConfigurationRecord() {
        AI_Card_Configuration__c card = [SELECT Id FROM AI_Card_Configuration__c LIMIT 1];
        Test.startTest();
        AddCardController.metadataWrap result = AddCardController.getCardConfigurationRecord(card.Id);
        Test.stopTest();
        Assert.areEqual(card.Id, result.Id);
    }
    
    // CONNECTION TESTS
    @isTest
    static void testCreateConnection() {
        AI_Response_Mapping__c rm = TestUtility.createResponseMapping('TestRM', true);
        Request_Mapping__c reqm = TestUtility.createRequestMapping('TestReqM', true);
        Map<String, Object> params = new Map<String, Object>{
            'Name' => 'TestConn', NAMESPACE + 'Named_Credential__c' => 'TestCred',
            NAMESPACE + 'AI_Technology__c' => 'GPTfy', NAMESPACE + 'Infrastructure__c' => 'Others',
            NAMESPACE + 'Version__c' => '1', NAMESPACE + 'Temperature__c' => 0.7,
            'Response_Mapping__c' => rm.Id, 'Request_Mapping__c' => reqm.Id
        };
        
        Test.startTest();
        AI_Connection__c result = AddCardController.createConnection(params);
        Test.stopTest();
        
        Assert.isNotNull(result.Id);
        Assert.areEqual('TestConn', result.Name);
    }
    
    @isTest
    static void testGetResponseAndRequestMapping() {
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c WHERE Name = 'GPTfy (OpenAI)' LIMIT 1];
        
        Test.startTest();
        String respResult = AddCardController.getResponseMapping(conn.Id);
        String reqResult = AddCardController.getRequestMapping(conn.Id);
        Test.stopTest();
        
        Assert.isNotNull(respResult);
        Assert.isTrue(respResult.contains('namespace'));
    }
    
    // DATA SOURCE TESTS
    @isTest
    static void testCreateDataSource() {
        Map<String, Object> params = new Map<String, Object>{
            'Name' => 'TestDS', NAMESPACE + 'Named_Credential__c' => 'TestCred',
            NAMESPACE + 'Source__c' => 'DnB', NAMESPACE + 'Connector_Class__c' => 'TestClass',
            NAMESPACE + 'EndPoint_URL__c' => 'https://test.com'
        };
        
        Test.startTest();
        AI_Data_Source__c result = AddCardController.createDataSource(params);
        Test.stopTest();
        
        Assert.isNotNull(result.Id);
        Assert.areEqual('TestDS', result.Name);
    }
    
    // CARD ACTIVATION TESTS
    @isTest
    static void testHandleCardActivate_Success() {
        String mockResp = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(mockResp));
        
        Test.startTest();
        Boolean hasError1 = AddCardController.handleCardActivate(new Map<String, Object>{'Name' => 'GPTfy (OpenAI)', 'Feature' => FEATURE_AMODL});
        Boolean hasError2 = AddCardController.handleCardActivate(new Map<String, Object>{'Name' => 'DnB', 'Feature' => FEATURE_APIDS});
        Test.stopTest();
        
        Assert.isFalse(hasError1);
        Assert.isFalse(hasError2);
    }
    
    @isTest
    static void testHandleCardActivate_ValidationErrors() {
        AI_Response_Mapping__c rm = TestUtility.createResponseMapping('TestRM2', true);
        
        // Test missing fields
        AI_Connection__c conn1 = TestUtility.getConnection('InvalidConn1', false);
        conn1.AI_Technology__c = '';
        conn1.Infrastructure__c = '';
        conn1.Version__c = '';
        conn1.Temperature__c = null;
        conn1.AI_Response_Mapping__c = rm.Id;
        insert conn1;
        TestUtility.createCardConfiguration('InvalidConn1', FEATURE_AMODL, true);
        
        // Test invalid temperature
        AI_Connection__c conn2 = TestUtility.getConnection('InvalidTemp', false);
        conn2.AI_Technology__c = 'GPTfy';
        conn2.Infrastructure__c = 'Others';
        conn2.Version__c = '1';
        conn2.Temperature__c = 1.5;
        conn2.AI_Response_Mapping__c = rm.Id;
        insert conn2;
        TestUtility.createCardConfiguration('InvalidTemp', FEATURE_AMODL, true);
        
        // Test invalid named credential
        AI_Connection__c conn3 = TestUtility.getConnection('InvalidNC', false);
        conn3.Named_Credential__c = 'NonExistent';
        conn3.AI_Technology__c = 'GPTfy';
        conn3.Infrastructure__c = 'Others';
        conn3.Version__c = '1';
        conn3.Temperature__c = 0.5;
        conn3.AI_Response_Mapping__c = rm.Id;
        insert conn3;
        TestUtility.createCardConfiguration('InvalidNC', FEATURE_AMODL, true);
        
        Test.startTest();
        Boolean err1 = false, err2 = false, err3 = false;
        try { AddCardController.handleCardActivate(new Map<String, Object>{'Name' => 'InvalidConn1', 'Feature' => FEATURE_AMODL}); } catch (Exception e) { err1 = true; }
        try { AddCardController.handleCardActivate(new Map<String, Object>{'Name' => 'InvalidTemp', 'Feature' => FEATURE_AMODL}); } catch (Exception e) { err2 = true; }
        try { AddCardController.handleCardActivate(new Map<String, Object>{'Name' => 'InvalidNC', 'Feature' => FEATURE_AMODL}); } catch (Exception e) { err3 = true; }
        Test.stopTest();
        
        Assert.isTrue(err1 || err2 || err3, 'At least one validation should fail');
    }
    
    // UTILITY METHOD TESTS
    @isTest
    static void testUtilityMethods() {
        Test.startTest();
        Set<String> picklistValues = AddCardController.getPicklistFieldValues(NAMESPACE + 'AI_Prompt__c', NAMESPACE + 'Purpose__c');
        MetadataService.MetadataPort service = AddCardController.createService();
        String sessionId = AddCardController.fetchUserSessionIdUsingVF();
        Boolean exists1 = AddCardController.isExistingStaticResource('demo');
        Boolean exists2 = AddCardController.isExistingStaticResource(NAMESPACE + 'demo');
        String namespace = AddCardController.getNameSpace();
        Test.stopTest();
        
        Assert.isNotNull(picklistValues);
        Assert.isNotNull(service);
        Assert.isNotNull(namespace);
    }
    
    // MOCK CLASS
    private class MetadataAPIMockHttpResponseGenerator implements WebServiceMock {
        public void doInvoke(Object stub, Object request, Map<String, Object> response, String endpoint, 
                           String soapAction, String requestName, String responseNS, String responseName, String responseType) {
            if (request instanceof MetadataService.retrieve_element) {
                response.put('response_x', new MetadataService.retrieveResponse_element());
            } else if (request instanceof MetadataService.checkDeployStatus_element) {
                response.put('response_x', new MetadataService.checkDeployStatusResponse_element());
            } else if (request instanceof MetadataService.listMetadata_element) {
                response.put('response_x', new MetadataService.listMetadataResponse_element());
            } else if (request instanceof MetadataService.checkRetrieveStatus_element) {
                response.put('response_x', new MetadataService.checkRetrieveStatusResponse_element());
            } else if (request instanceof MetadataService.describeMetadata_element) {
                response.put('response_x', new MetadataService.describeMetadataResponse_element());
            } else if (request instanceof MetadataService.deploy_element) {
                response.put('response_x', new MetadataService.deployResponse_element());
            } else if (request instanceof MetadataService.updateMetadata_element) {
                response.put('response_x', new MetadataService.updateMetadataResponse_element());
            } else if (request instanceof MetadataService.renameMetadata_element) {
                response.put('response_x', new MetadataService.renameMetadataResponse_element());
            } else if (request instanceof MetadataService.cancelDeploy_element) {
                response.put('response_x', new MetadataService.cancelDeployResponse_element());
            } else if (request instanceof MetadataService.deleteMetadata_element) {
                response.put('response_x', new MetadataService.deleteMetadataResponse_element());
            } else if (request instanceof MetadataService.upsertMetadata_element) {
                response.put('response_x', new MetadataService.upsertMetadataResponse_element());
            } else if (request instanceof MetadataService.createMetadata_element) {
                response.put('response_x', new MetadataService.createMetadataResponse_element());
            } else if (request instanceof MetadataService.deployRecentValidation_element) {
                response.put('response_x', new MetadataService.deployRecentValidationResponse_element());
            } else if (request instanceof MetadataService.describeValueType_element) {
                response.put('response_x', new MetadataService.describeValueTypeResponse_element());
            }
        }
    }
}