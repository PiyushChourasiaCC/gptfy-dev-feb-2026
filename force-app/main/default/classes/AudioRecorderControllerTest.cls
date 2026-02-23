@isTest
public class AudioRecorderControllerTest {
	
    @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        conn.Type__c = AIConstants.AI_MODEL_TYPE_VOICE;
        conn.Model__c = 'Chirp';
        insert conn;
        
        Map<String, String> data = new Map<String, String>();
        data.put('recordId', null);
        data.put('mappingName', 'Test Mapping');
        data.put('targetObject', 'ContentVersion');
        data.put('description', 'test desc');
        data.put('objLabel', 'Content Version');
        data.put('aiDataSource', null);
        String masterId = AIDataExtractionController.modifyMaster(data);
        
        AIExtractionFieldMappingController.FieldWrapper cvField = new AIExtractionFieldMappingController.FieldWrapper();
        cvField.fieldName = 'Name';
        cvField.label = 'Name';
        cvField.sendToAI = true;
        cvField.scanForPII = false;
        cvField.fieldType = 'String';
        AIExtractionFieldMappingController.saveFieldMappings(masterId, 'ContentVersion', new List<AIExtractionFieldMappingController.FieldWrapper>{cvField});
        
        //TestUtility.insertDataExtraction();
        //List<AIExtractionFieldMappingController.PicklistAttributeWrapper> formula = AIExtractionFieldMappingController.validateFormula('Account','STRING','Name');
        List<AI_Data_Extraction_Field__c> dataExtractionFields = [SELECT id, formula__c FROM AI_Data_Extraction_Field__c where object__c = 'ContentVersion' AND Type__c ='FIELD'];
        dataExtractionFields[0].formula__c = 'Title';
        dataExtractionFields[0].Field_Type__c = 'STRING';
        update dataExtractionFields;
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'ContentVersion', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
        }); 
        
        AI_Prompt__c pmt = new AI_Prompt__c();
        pmt.Id = pmtId;
        pmt.Status__c = AIConstants.PMT_STATUS_ACTIVE;
        pmt.Prompt_Command__c = 'Give a sample response.';
        update pmt;
        
        AIVoiceConfigurationController.ConfigurationWrapper wrap = AIVoiceConfigurationController.getConfigurationDetails();
        wrap.duration = 1;
        wrap.aiModelId = conn.Id;
        AIVoiceConfigurationController.updateConfiguration(JSON.serialize(wrap));
        
        
        TestUtility.getAccount(true);
        ContentVersion cv = new ContentVersion(
            Title = 'Penguins',
            PathOnClient = 'Penguins.jpg',
            VersionData = Blob.valueOf('Test Content'),
            IsMajorVersion = false
        );
        insert cv;  
    }
    
    @isTest
    static void createContentDocumentLinkTest(){
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
        Account a = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        List<AI_Voice_Configuration__c> lstOfConfigs = [SELECT Id, Async_Request__c,AI_Model__c,AI_Model_File_Upload__c,Maximum_Polling_Counter__c FROM AI_Voice_Configuration__c where AI_Model__c != NULL];
        AI_Voice_Configuration_Detail__c voiceDetail = new AI_Voice_Configuration_Detail__c(Related_To_Object__c='Account',
                                                                                           AI_Prompt__c=pmt.Id,
                                                                                           AI_Voice_Configuration__c=lstOfConfigs.get(0).Id);
        insert voiceDetail;
        Test.startTest();
       // String respBody = '{"results": [{"alternatives" : [{"transcript" : "Test"}]}]}';
        String respBody = '{ "response" : { "results": [{ "channelTag": 1, "alternatives" : [{"transcript" : "Test" }] }] } }';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        AudioRecorderController.createContentDocumentLink(cv.Id, a.Id, false);
        AudioRecorderController.isUserAuthorized();
        Test.stopTest();
        
        ContentDocumentLink contentlink = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId =:cv.ContentDocumentId LIMIT 1];
        System.assertNotEquals(null, contentlink, 'ContentDocumentLink should be created.');
    }
    
    @isTest
    static void testSyncIOSTest(){
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
       // String respBody = '{"results": [{"alternatives" : [{"transcript" : "Test"}]}]}';
        String respBody = '{ "transcript" : "Test" }';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        AudioRecorderController.createContentDocumentLink(cv.Id, a.Id, true);
        Test.stopTest();
        
        ContentDocumentLink contentlink = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId =:cv.ContentDocumentId LIMIT 1];
        System.assertNotEquals(null, contentlink, 'ContentDocumentLink should be created.');
    }
    
     @isTest
    static void audioProcessAsyncTest(){
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
        Account a = [SELECT Id FROM Account LIMIT 1];
        AI_Connection__c con = [SELECT Id, Name, Type__c, Additional_Parameters__c, Model__c FROM AI_Connection__c];
        con.Additional_Parameters__c = ' { "privateKeyFileId" : "'+cv.ContentDocumentId+'", "clientId": "testclientId", "authUrl": "https//www.gptfy.ai" ,"tokenUrl": "tokenUrl" } ';
        update con;
        List<AI_Voice_Configuration__c> lstOfConfigs = [SELECT Id, Async_Request__c,AI_Model__c,AI_Model_File_Upload__c FROM AI_Voice_Configuration__c where AI_Model__c != NULL];
        lstOfConfigs.get(0).Async_Request__c = true;
        lstOfConfigs.get(0).AI_Model_File_Upload__c = con.Id;
        lstOfConfigs.get(0).AI_Model_Polling__c = con.Id;
        update lstOfConfigs;
        Test.startTest();
        String respBody = '{ "name":"JobIdName", "mediaLink":"test.com", "response" : { "results": [{ "alternatives" : [{"transcript" : "Test" }] }] } }';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        AudioRecorderController.createContentDocumentLink(cv.Id, a.Id, false);
        Test.stopTest();
        
        ContentDocumentLink contentlink = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId =:cv.ContentDocumentId LIMIT 1];
        System.assertNotEquals(null, contentlink, 'ContentDocumentLink should be created.');
    }
    
    @isTest
    static void audioProcessAsyncCounterTest(){
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Account a = [SELECT Id FROM Account LIMIT 1];
        AI_Connection__c con = [SELECT Id, Name, Type__c, Additional_Parameters__c, Model__c FROM AI_Connection__c];
        con.Additional_Parameters__c = ' { "privateKeyFileId" : "'+cv.ContentDocumentId+'", "clientId": "testclientId", "authUrl": "https//www.gptfy.ai" ,"tokenUrl": "tokenUrl" } ';
        con.Model__c = AIConstants.KENSHO_VOICE_MODEL;
        
        update con;
        List<AI_Voice_Configuration__c> lstOfConfigs = [SELECT Id, Async_Request__c,AI_Model__c,AI_Model_File_Upload__c,Maximum_Polling_Counter__c FROM AI_Voice_Configuration__c where AI_Model__c != NULL];
        lstOfConfigs.get(0).Async_Request__c = true;
        lstOfConfigs.get(0).AI_Model_Polling__c = con.Id;
        lstOfConfigs.get(0).Maximum_Polling_Counter__c = 2;
        lstOfConfigs.get(0).AI_Model_File_Upload__c = con.Id;
        lstOfConfigs.get(0).Polling_Timeframe__c = 1;
        update lstOfConfigs;
        AI_Voice_Configuration_Detail__c voiceDetail = new AI_Voice_Configuration_Detail__c(Related_To_Object__c='Account',
                                                                                           AI_Prompt__c=pmt.Id,
                                                                                           AI_Voice_Configuration__c=lstOfConfigs.get(0).Id);
        insert voiceDetail;
        String respBody = '{ "fileUrl": "testurl", "name":"JobIdName", "mediaLink":"test.com", "results": [{ "channelTag": 1,"alternatives" : [{"transcript" : "" }] }]  }';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        AudioRecorderController.createContentDocumentLink(cv.Id, a.Id, false);
        Test.stopTest();
        
        ContentDocumentLink contentlink = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId =:cv.ContentDocumentId LIMIT 1];
        System.assertNotEquals(null, contentlink, 'ContentDocumentLink should be created.');
    }
    
}