/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class AIJsonGenerationTest {
	
    @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        AI_Data_Source__c ds = TestUtility.getAIDataSource(true);
        master.AI_Data_Source__c = ds.Id;
        update master;
        
        AI_Card_Configuration__c card = TestUtility.createCardConfiguration(ds.name, AIConstants.GPTFY_CARD_CONFIGURATION_MDT_APIDS, true);

        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.', 'visibilityCondition' => ' Id != NULL '
        });
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmtId, master.Id, 'Account', true);
        AI_Response_Processing__c rp = TestUtility.getResponseProcessing(cmp1.Id, 'Description', true);
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        cDetail.Where_Clause__c = 'LastName != NULL';
        update cDetail;
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(pmtId, cDetail.Id, 'Contact', true);
        
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(pmtId, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(pmtId);
        
        TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_UPDATE_FIELD,true);
        AI_Prompt_Action__c pAction = TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_CREATE_RECORD,false);
        pAction.Object_Name__c = 'Account';
        insert pAction;
        
        AI_Prompt_Action_Detail__c pActionDetail = TestUtility.getAIPromptActionDetail(pAction.Id,'Name',AIConstants.ACTION_DETAIL_TYPE_AI_RESP,false);
        pActionDetail.Value__c = 'TestName';
        insert pActionDetail;
        
        pAction = TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_CREATE_RECORD,false);
        pAction.Object_Name__c = 'Account';
        insert pAction;
        
        TestUtility.getAIPromptActionDetail(pAction.Id,'Name',AIConstants.ACTION_DETAIL_TYPE_REF_FIELD,true);
        TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_OPEN_FORM,true);
        
        pAction = TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_INVOKE_FLOW,false);
        pAction.Flow_API_Name__c = 'Test';
        insert pAction;
        
        pAction = TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_INVOKE_APEX,false);
        pAction.Apex_Class_Name__c = 'TestClass';
        insert pAction;
    }
    
    @isTest
    static void generateJSONPromptCommandTest(){
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        AIJsonGeneration.generatePromptCommand(pmt.Id);
        Test.stopTest();
        AI_Prompt__c upmt = [SELECT Id, Prompt_Command__c FROM AI_Prompt__c LIMIT 1];
        System.Assert(String.isNotBlank(upmt.Prompt_Command__c));
    }
    
    @isTest
    static void generateTextPromptCommandTest(){
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        pmt.Type__c = 'Text';
        pmt.Prompt_Command__c = '{{{Name}}}';
        update pmt;
        Test.startTest();
        AIJsonGeneration.generatePromptCommand(pmt.Id);
        Test.stopTest();
        AI_Prompt__c upmt = [SELECT Id, Prompt_Command__c FROM AI_Prompt__c LIMIT 1];
        System.Assert(String.isNotBlank(upmt.Prompt_Command__c));
    }
    
    @isTest
    static void checkValidationPromptCommandTest(){
        AI_Prompt__c pmt = [SELECT Id, AI_Data_Extraction_Mapping__c, Visibility_Condition__c FROM AI_Prompt__c LIMIT 1];
        pmt.Type__c = 'Text';
        pmt.Prompt_Command__c = '{{{Name1}}}';
        pmt.Visibility_Condition__c = ' Id != NULL ';
        update pmt;
        
        Test.startTest();
        AIJsonGeneration.checkValidationPromptCommand(pmt.Id);
        AIJsonGeneration.validateDataContextMapping(pmt.AI_Data_Extraction_Mapping__c);
        Test.stopTest();
        AI_Prompt__c upmt = [SELECT Id, Status__c FROM AI_Prompt__c LIMIT 1];
        System.Assert(String.isNotBlank(upmt.Status__c));
    }
    
    @isTest
    static void generateTextPromptCommandWithDataSourceTest(){
        AI_Prompt__c pmt = [SELECT Id, AI_Data_Extraction_Mapping__c FROM AI_Prompt__c LIMIT 1];
        pmt.Type__c = 'Text';
        pmt.Prompt_Command__c = '{{{Name}}}';
        update pmt;
        
        AI_Data_Source__c ds = TestUtility.getAIDataSource(false);
        ds.Named_Credential__c = 'SAMPLE_CRED';
        ds.Connector_Class__c = 'SAMPLE_CLASS';
        insert ds;
        
        AI_Data_Extraction_Mapping__c master = new AI_Data_Extraction_Mapping__c();
        master.Id = pmt.AI_Data_Extraction_Mapping__c;
        master.AI_Data_Source__c = ds.Id;
        update master;
        
        Test.startTest();
        AIJsonGeneration.generatePromptCommand(pmt.Id);
        Test.stopTest();
        AI_Prompt__c upmt = [SELECT Id, Prompt_Command__c FROM AI_Prompt__c LIMIT 1];
        System.Assert(String.isNotBlank(upmt.Prompt_Command__c));
    }
    
    @isTest
    static void updateWhatNeeded(){
        AI_Prompt__c pmt = [SELECT Id, Name FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        
        ContentVersion contentVersion = new ContentVersion(
            Title = pmt.Id,
            PathOnClient = pmt.Id+'.json',
            VersionData = Blob.valueOf('{"prompts" : [{"promptActions":[{"sequence" : 35,"salesforceId" : "a0fJ700000110X4IAI","promptActionDetails" : [ {"value" : "Id","salesforceId" : "a0gJ7000000HDLYIA4","fieldAPIName" : "ParentId","actionType" : "Reference Field"}, {"value" : "Child Account","salesforceId" : "a0gJ7000000HDLXIA4","fieldAPIName" : "Name","actionType" : "Hardcoded"} ],"objectName" : "Account","flowAPIName" : null,"fieldAPIName" : null,"description" : "This action is for creating a child account","appendTimestamp" : false,"apexClassName" : null,"actionType" : "Open a Form"}], "promptComponents":[{"actionName":"Identify Language","componentName":"Identify Language","dataExtractionId":"a038d00000AuyhDAAR","objectName":"Case","phraseAfterContraints":"only","phraseAfterFormat":".","phraseAfterLanguage":".","phraseAfterLength":"only.","phraseAfterObject":".","phraseAfterTone":".","phraseBeforeContraints":"with values constrained to","phraseBeforeFormat":"Format in","phraseBeforeLanguage":"Keep it in","phraseBeforeLength":"Limit it to","phraseBeforeObject":"of this","phraseBeforeTone":"Keep tone","responseProcessings":[{"actionName":"Update Field","appendTimestamp":false,"destinationField":"GPTfy_Language__c","salesforceId":"a068d00000DpsgYAAR"}],"salesforceId":"a048d00000E3aYRAAZ"}]}]}'),
            IsMajorVersion = true
        );
        insert contentVersion;    
        List<ContentDocument> documents = [SELECT Id, Title, LatestPublishedVersionId FROM ContentDocument];
        AIJsonGeneration.isPromptVersionEmpty(pmt.Id);
        
        /*
        ContentDocumentLink cdl = New ContentDocumentLink();
        cdl.LinkedEntityId = pmt.id;
        cdl.ContentDocumentId = documents[0].Id;
        cdl.shareType = 'V';
        insert cdl;
		*/
		
        //try{
            AIJsonGeneration.updateWhatNeeded(pmt.Id, 'test comment');
        //}catch(Exception e){}        
        
        Boolean val = AIJsonGeneration.isEnablePromptVersioning();
        
        String docId = AIJsonGeneration.getPromptContentDocumentId(pmt.Id);
        List<ContentVersion> versions = AIJsonGeneration.getPromptContentVersion(docId);
        
        AIJsonGeneration.importReinstateVersion(pmt.Id, contentVersion.Id);
        Test.stopTest();
        System.assert(docId != null);
    }
    
}