@isTest
public with sharing class AddCardControllerTest {

    @testSetup
    public static void makeData(){
        TestUtility.createCardConfiguration('DnB','APIDS',true);
        TestUtility.createCardConfiguration('GPTfy (OpenAI)','AMODL',true);
        TestUtility.createCardConfiguration('Boost Sales','CTLOG',true);
        AI_Response_Mapping__c responseMapping = TestUtility.createResponseMapping('TestResponse',true);
        AI_Connection__c ac = TestUtility.getConnection('GPTfy (OpenAI)1', false);
        ac.AI_Technology__c = 'GPTfy';
        ac.AI_Response_Mapping__c = responseMapping.Id;
        insert ac;
        ac.Name = 'GPTfy (OpenAI)';
        update ac;
        AI_Data_Source__c ds = TestUtility.getAIDataSource(false);
        ds.Name = 'DnB';
        ds.Connector_Class__c = AIExtractionFieldMappingController.NAMESPACE+'AddCardController';
        insert ds;
    }

     @isTest
    public static void insertPicklistValueTest(){ 
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        MetadataService metaDataService = new MetadataService();
        Test.startTest(); 
        	boolean hasSuccess = AddCardController.insertPicklistValue('Account', 'Industry','demom');
        	AddCardController ctrl = new AddCardController();
        	ctrl.handleResult(new Metadata.DeployResult(), new Metadata.DeployCallbackContext());
        Test.stopTest();
        System.Assert(hasSuccess == true);
    }
	    
    @isTest
    public static void createCardConfigurationCTLOGTest(){ 
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        MetadataService metaDataService = new MetadataService();
        Test.startTest();        
        Map<String, Object> mapParams = new Map<String, Object>();
        mapParams.put('Name','Test1');
        mapParams.put('Feature__c','CTLOG');
        mapParams.put('Icon_Source__c','SLDS Icon');
        mapParams.put('Icon_Details__c','custom:custom28');
        mapParams.put('Description__c', 'test');
        mapParams.put('Sequence__c', 1);
        mapParams.put('Enabled__c', true);
        mapParams.put('CardName', 'CTLOG_Test');
        
        boolean hasSuccess = AddCardController.createCardConfiguration(mapParams);
        Test.stopTest();
        
        System.Assert(hasSuccess == true);
        
    }
    
    @isTest
    public static void createCardConfigurationAMODLTest(){ 
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        MetadataService metaDataService = new MetadataService();
        Test.startTest();        
        Map<String, Object> mapParams = new Map<String, Object>();
        mapParams.put('Name','GPTfy (OpenAI)2');
        mapParams.put('Feature__c','AMODL');
        mapParams.put('Icon_Source__c','SLDS Icon');
        mapParams.put('Icon_Details__c','custom:custom28');
        mapParams.put('Description__c', 'test');
        mapParams.put('Sequence__c', 1);
        mapParams.put('Enabled__c', true);
        mapParams.put('CardName', 'AMODL_1');
        
        boolean hasSuccess = AddCardController.createCardConfiguration(mapParams);
        Test.stopTest();
        
        System.Assert(hasSuccess == true);
    }
    
    @isTest
    public static void createCardConfigurationAPIDSTest(){ 
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        MetadataService metaDataService = new MetadataService();
        Test.startTest();        
        Map<String, Object> mapParams = new Map<String, Object>();
        mapParams.put('Name','Boost Sales 2');
        mapParams.put('Feature__c','APIDS');
        mapParams.put('Icon_Source__c','SLDS Icon');
        mapParams.put('Icon_Details__c','custom:custom28');
        mapParams.put('Description__c', 'test');
        mapParams.put('Sequence__c', 1);
        mapParams.put('Enabled__c', true);
        mapParams.put('CardName', 'APIDS_Test');
        
        boolean hasSuccess = AddCardController.createCardConfiguration(mapParams);
        Test.stopTest();
        
        System.Assert(hasSuccess == true);
    }
    
    @isTest
    public static void updateCardConfigurationTest(){        
        Test.startTest();
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        AI_Card_Configuration__c config = [Select id from AI_Card_Configuration__c where Name='Boost Sales' AND Feature__c='CTLOG'];
        Map<String, Object> mapParams = new Map<String, Object>();
        mapParams.put('Id',config.id);
        mapParams.put('Name','Boost Sales');
        mapParams.put('Feature__c','CTLOG');
        mapParams.put('Icon_Source__c','SLDS Icon');
        mapParams.put('Icon_Details__c','custom:custom28');
        mapParams.put('Description__c', 'test update');
        mapParams.put('Sequence__c', 1);
        mapParams.put('Enabled__c', true);
        mapParams.put('CardName', 'CTLOG_Test');
        
        boolean hasSuccess = AddCardController.updateCardConfiguration(mapParams);
        Test.stopTest();
        
        System.Assert(hasSuccess == true);
        
    }
    
    @isTest
    public static void deleteCardConfigurationTest(){        
        Test.startTest();
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());

        AI_Card_Configuration__c card = TestUtility.createCardConfiguration('TestCard123','AMODL',true);
        boolean hasSuccess = AddCardController.deleteCardConfiguration('test', 'GPTfy_Card_Configuration.Test', 'test', 'CTLOG',card.Id);
        Test.stopTest();
        
        System.Assert(hasSuccess!=null);
        
    }
    
    @isTest
    public static void getCardConfigurationCTLOGTest(){        
        Test.startTest();
		AI_Prompt__c ap = TestUtility.getAIPrompt('Test', 'Contact', 'Active', false);
		ap.Purpose__c = 'Improve Services;Boost Sales'; 
        insert ap;
        
        AI_Usage_Tracking__c ut = new AI_Usage_Tracking__c();
        ut.AI_Prompt__c = ap.Id;
        ut.Lifetime_Saving_Seconds__c = 1000;
		insert ut;
        
        List<AddCardController.dataWrap> lst = AddCardController.getCardConfiguration('CTLOG');
        Test.stopTest();   
        System.assert(lst != null);
    }
    
    @isTest
    public static void getCardConfigurationAMODLTest(){        
        Test.startTest();        
        List<AddCardController.dataWrap> lst = AddCardController.getCardConfiguration('AMODL');
        Test.stopTest();        
        System.assert(lst != null);
    }
    
    @isTest
    public static void checkDuplicateConnection(){        
        Test.startTest();        
        List<AddCardController.dataWrap> lst = AddCardController.getCardConfiguration('AMODL');
        try{
            AI_Connection__c ac = TestUtility.getConnection('GPTfy (OpenAI)', false);
            ac.AI_Technology__c = 'GPTfy';
            insert ac;
        }catch(Exception ex){}
        Test.stopTest();        
        System.assert(lst != null);
    }
    
    @isTest
    public static void getCardConfigurationAPIDSTest(){        
        Test.startTest();        
        List<AddCardController.dataWrap> lst = AddCardController.getCardConfiguration('APIDS');
        Test.stopTest();     
        System.assert(lst != null);
    }
    
    @isTest
    public static void createConnectionTest(){
        String NAMESPACE = AIExtractionFieldMappingController.NAMESPACE;
        AI_Response_Mapping__c responseMapping = TestUtility.createResponseMapping('TestResponse2',true);
        Request_Mapping__c reqMapping = TestUtility.createRequestMapping('TestRequest2',true);
        Map<String, Object> params = new Map<String, Object>();
        params.put('Name', 'GPTfy (OpenAI)');
        params.put(NAMESPACE + 'Named_Credential__c', 'Test');
        params.put(NAMESPACE + 'AI_Technology__c', 'GPTfy');
        params.put(NAMESPACE + 'Connector_Class__c', 'GPTfy');
        params.put(NAMESPACE + 'Infrastructure__c', 'Others');
        params.put(NAMESPACE + 'Security_Layer__c', 'GPTfy');
        params.put(NAMESPACE + 'Version__c', '1');
        params.put(NAMESPACE + 'Enable_in_Sandbox__c', false);
        params.put(NAMESPACE + 'Model__c', 'Test');
        params.put(NAMESPACE + 'Max_Tokens__c', 2000);
        params.put(NAMESPACE + 'Temperature__c', .01);
        params.put(NAMESPACE + 'EndPoint_URL__c', 'test');
        params.put(NAMESPACE + 'Top_P__c', 1);
        params.put(NAMESPACE + 'Response_Mapping__c',responseMapping.Id);
        params.put(NAMESPACE + 'Request_Mapping__c',reqMapping.Id);
        Test.startTest();
        AI_Connection__c conn = AddCardController.createConnection(params);
        String responseMappingData = AddCardController.getResponseMapping(conn.Id);
        AddCardController.getRequestMapping(conn.Id);
        Test.stopTest();
        System.assert(conn != null);
        System.assert(responseMappingData != null);
    }
    
    @isTest
    public static void createDataSourceTest(){
        String NAMESPACE = AIExtractionFieldMappingController.NAMESPACE; 
        Map<String, Object> params = new Map<String, Object>();
        params.put('Name', 'Test');
        params.put(NAMESPACE + 'Named_Credential__c', 'Test');
        params.put(NAMESPACE + 'Source__c', 'DnB');
        params.put(NAMESPACE + 'Connector_Class__c', 'GPTfy');
		params.put(NAMESPACE + 'EndPoint_URL__c', 'test');
        
        Test.startTest();
        AI_Data_Source__c ds = AddCardController.createDataSource(params);
        Test.stopTest();
        System.assert(ds != null);
    }
    
    @isTest
    public static void cardActivateTest(){
        
        
        Map<String, Object> params = new Map<String, Object>();
        params.put('Name', 'GPTfy (OpenAI)');
        params.put('Feature','AMODL');

        Map<String, Object> paramsDataSource = new Map<String, Object>();
        paramsDataSource.put('Name', 'DnB');
        paramsDataSource.put('Feature', 'APIDS');
        

        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        boolean act = AddCardController.handleCardActivate(params);
        boolean act2 = AddCardController.handleCardActivate(paramsDataSource);
        AI_Card_Configuration__c metadata = [SELECT Id FROM AI_Card_Configuration__c LIMIT 1];
        AddCardController.getCardConfigurationRecord(metadata.Id);
        Test.stopTest();
        System.assert(!act);
    }
    
    @isTest
    public static void cardActivateFailTest(){
        Boolean isError = false;
        Test.startTest();
        try{
            AI_Connection__c ac = TestUtility.getConnection('OpenAI / Azure', false);
            ac.Named_Credential__c = '';
            ac.AI_Technology__c = '';
            ac.Infrastructure__c = '';
            ac.Version__c = '';
            ac.Temperature__c = NULL;
            insert ac;
            TestUtility.createCardConfiguration('OpenAI / Azure','AMODL',true);
            Map<String, Object> params = new Map<String, Object>();
            params.put('Name', 'OpenAI / Azure');
            params.put('Feature', 'AMODL');
            AddCardController.handleCardActivate(params);
            
        }catch(Exception ex){
            isError = true;
        }
        Test.stopTest();
        System.assert(isError);
    }
    
    @isTest
    public static void getPicklistFieldValues(){
        String NAMESPACE = AIExtractionFieldMappingController.NAMESPACE; 
        
        Test.startTest();
        Set<String> setOfValues = AddCardController.getPicklistFieldValues(NAMESPACE + 'AI_Prompt__c', NAMESPACE + 'Purpose__c');
        Test.stopTest();
        System.assert(setOfValues != null);
    }
    
    @isTest
    public static void callGeneralMethods(){
        MetadataService.MetadataPort mdp = AddCardController.createService();
        AddCardController.fetchUserSessionIdUsingVF();
        AddCardController.getNameSpace();
        AddCardController.isExistingStaticResource('demo');
        System.assert(mdp != null);
    }
    
    public class MetadataAPIMockHttpResponseGenerators implements WebServiceMock {
        public void doInvoke(
			Object stub, Object request, Map<String, Object> response,
			String endpoint, String soapAction, String requestName,
			String responseNS, String responseName, String responseType) 
		{
			if(request instanceof MetadataService.retrieve_element)
				response.put('response_x', new MetadataService.retrieveResponse_element());
			else if(request instanceof MetadataService.checkDeployStatus_element)
				response.put('response_x', new MetadataService.checkDeployStatusResponse_element());
			else if(request instanceof MetadataService.listMetadata_element)
				response.put('response_x', new MetadataService.listMetadataResponse_element());
			else if(request instanceof MetadataService.checkRetrieveStatus_element)
				response.put('response_x', new MetadataService.checkRetrieveStatusResponse_element());
			else if(request instanceof MetadataService.describeMetadata_element)
				response.put('response_x', new MetadataService.describeMetadataResponse_element());
			else if(request instanceof MetadataService.deploy_element)
				response.put('response_x', new MetadataService.deployResponse_element());
            else if(request instanceof MetadataService.updateMetadata_element)
                response.put('response_x', new MetadataService.updateMetadataResponse_element());
            else if(request instanceof MetadataService.renameMetadata_element)
                response.put('response_x', new MetadataService.renameMetadataResponse_element());
            else if(request instanceof  MetadataService.cancelDeploy_element)
                response.put('response_x', new MetadataService.cancelDeployResponse_element());
            else if(request instanceof  MetadataService.deleteMetadata_element)
                response.put('response_x', new MetadataService.deleteMetadataResponse_element());
            else if(request instanceof  MetadataService.upsertMetadata_element)
                response.put('response_x', new MetadataService.upsertMetadataResponse_element());
            else if(request instanceof  MetadataService.createMetadata_element)
                response.put('response_x', new MetadataService.createMetadataResponse_element());
            else if(request instanceof  MetadataService.deployRecentValidation_element)
                response.put('response_x', new MetadataService.deployRecentValidationResponse_element());
            else if(request instanceof MetadataService.describeValueType_element)
                response.put('response_x', new MetadataService.describeValueTypeResponse_element());
            else if(request instanceof MetadataService.checkRetrieveStatus_element)
                response.put('response_x', new MetadataService.checkRetrieveStatusResponse_element());
			return; 
		}
    }
}