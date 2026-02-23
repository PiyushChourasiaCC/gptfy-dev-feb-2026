/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class CatalogControllerTest {
	
     @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy (OpenAI)', false);
        conn.AI_Technology__c = 'GPTfy';
        insert conn;
        TestUtility.createCardConfiguration('GPTfy (OpenAI)','AMODL',true);
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
        });
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmtId, master.Id, 'Account', true);
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(pmtId, cDetail.Id, 'Contact', true);
        
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(pmtId, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(pmtId);
        
        AI_Response_Processing__c rp = TestUtility.getResponseProcessing(cmp1.Id, 'Description', true);
        TestUtility.getAIPrompt('testpromptAccount','Account','Active', true);
    }
    
    @isTest
    static void getCatalogOptionsTest(){
    	List<Object> catOptions = CatalogController.getCatalogOptions();
        
        Test.startTest();
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        pmt.Purpose__c = 'Boost Sales';
        update pmt;
        Map<String, Object> purpOptions = CatalogController.getPurposeOptions(AIConstants.GPTFY_CARD_CONFIGURATION_MDT_CTLOG);
        
        CatalogController.PromptWrapper wrap = new CatalogController.PromptWrapper();
        wrap.pmtId = pmt.Id;
        CatalogController.updatePromptData(new List<CatalogController.PromptWrapper>{wrap});
        Test.stopTest();
        
        AI_Prompt__c upmt = [SELECT Id, Record_Type__c FROM AI_Prompt__c LIMIT 1];
        System.Assert(String.isBlank(upmt.Record_Type__c));
    }
    
    @isTest
    static void updatePromptTest(){
        AI_Connection__c aiConnection = [Select Id from AI_Connection__c LIMIT 1];
    	AI_Prompt__c aiPrompt = [Select Id from AI_Prompt__c LIMIT 1];
    	Map<String,Object> promptMap = new Map<String,Object>();
        promptMap.put('pmtId',aiPrompt.Id);
        promptMap.put('name','testpromptUpdate');
        promptMap.put('aiConnection',aiConnection.Id);
        promptMap.put('description','test description');
        List<Object> promptRecords = new List<Object>();
        promptRecords.add(promptMap);
        String jsondata = JSON.serialize(promptRecords);
        Test.startTest();
        	CatalogController.updatePrompts(jsondata);
            List<FieldSetWrappper> wrap = CatalogController.getFields();
        Test.stopTest();
         System.assert(wrap != null);
    }
    
}