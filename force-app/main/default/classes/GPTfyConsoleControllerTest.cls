/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class GPTfyConsoleControllerTest {
	
    @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
        });
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmtId, master.Id, 'Account', false);
        cmp1.Key__c = 'Sentiment';
        insert cmp1;
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(pmtId, cDetail.Id, 'Contact', true);
        
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(pmtId, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(pmtId);
        AI_Prompt_Action__c action = TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_UPDATE_FIELD, false);
        action.Field_API_Name__c = 'Name';
        action.Object_Name__c = 'Account';
        insert action;
        AI_Prompt_Action__c actionCreateRecord = TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_CREATE_RECORD, false);
        actionCreateRecord.Object_Name__c = 'Account';
        insert actionCreateRecord;
        AI_Prompt_Action_Detail__c actionDetails = TestUtility.getAIPromptActionDetail(actionCreateRecord.Id,'Name',AIConstants.ACTION_DETAIL_TYPE_HARDCODED, false);
        actionDetails.Value__c = 'TestValue';
        insert actionDetails;
    }
    
    @isTest
    static void getPromptOptionsTest(){
        Account acc = new Account(name = 'test account');
        insert acc;
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c limit 1];
        AI_Prompt_Action__c action = new AI_Prompt_Action__c(Object_Name__c= 'Account',Description__c='test',
                                                            Action__c=AIConstants.ACTION_TYPE_OPEN_FORM,AI_Prompt__c=aiPrompt.Id);
        insert action;
        Test.startTest();
        Boolean hasPortalUser = GPTfyConsoleController.isPortalUser();
        Boolean isAdminUser = GPTfyConsoleController.isAdminUser();
        GPTfyConsoleController.getPromptActionOptionsOpenForm(aiPrompt.Id);
        System.Assert(hasPortalUser != true);
        Map<String, Object> data = GPTfyConsoleController.getPromptOptions(acc.Id, NULL);
        GPTfyConsoleController.getLatestRecordOfSecurityAudit(aiPrompt.Id);
        Test.stopTest();
        System.Assert(data != null);
    }
    
    @isTest
    static void checkValidationVisibilityCondition(){
        AI_Security_Filters__c secfilter = new AI_Security_Filters__c(name = 'test security filters');
        secfilter.RecordTypeId = Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByDeveloperName().get('Regex').getRecordTypeId();
        secfilter.Search_Pattern__c = 'abc';
        insert secfilter;
        Test.startTest();
        Boolean isValid = GPTfyConsoleController.isValidVisibilityCondition(null,secfilter.Id, 'Name = \'test security filters\' LIMIT 1',new List<String> {'Regex'});
        System.Assert(isValid == true);
        Test.stopTest();
    }
    
    @isTest
    static void checkForContentVersionsTest(){
        Account acc = new Account(name = 'test account');
        insert acc;
         
        Contentversion cv = TestUtility.getContentversion('Test', 'Test', 'Test', false);
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion where Id = :cv.Id]; 
        
        ContentDocumentLink cdl = TestUtility.getContentDocumentLink(acc.Id, cv.ContentDocumentId, false);
        insert cdl;
        
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c limit 1];
        Test.startTest();
        List<GPTfyConsoleController.RecordWrapper> data = GPTfyConsoleController.checkForContentVersions(acc.Id, aiPrompt.Id);
        Test.stopTest();
        System.Assert(data != null);
    }
    
    @isTest
    static void saveFeedbackTest(){
        Account acc = new Account(name = 'test account');
        insert acc;
        List<AI_Prompt_Action__c> pActions = [Select Id,Field_API_Name__c from AI_Prompt_Action__c];
        AI_Response__c resp = new AI_Response__c();
        resp.AI_Prompt__c = [SELECT Id FROM AI_Prompt__c limit 1].Id;
        resp.AI_Processed_Data_PII_Added__c = 'test';
        resp.Status__c = AIConstants.RESP_STATUS_PROCESSED;
        resp.Record_Id__c = acc.Id;
        insert resp;
        
        List<AI_Response__c> respList = GPTfyConsoleController.getAllResponses(acc.Id);
        List<AI_Response__c> respSecurityAuditList = GPTfyConsoleController.getSecurityAudit(resp.Id);
        
        Test.startTest();
        GPTfyConsoleController.saveFeedback(respSecurityAuditList[0].Id, 'Dislike', '', '');
        for(AI_Prompt_Action__c a : pActions){
             GPTfyConsoleController.getDefaultFieldsString(a.Id,resp.Id);
        }
        Test.stopTest();
        System.assert(respSecurityAuditList != null);
    }
    
}