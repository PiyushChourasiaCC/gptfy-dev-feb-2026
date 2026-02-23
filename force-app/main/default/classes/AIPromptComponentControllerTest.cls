/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class AIPromptComponentControllerTest {
	
    @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
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
    }
    
    @isTest
    static void getPromptComponentDataTest(){
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        Test.startTest();
        Map<String, Object> data = AIPromptComponentController.getPromptComponentData(pmt.Id);
        System.assert(data != null);
        
        List<Object> componentObjects = AIPromptComponentController.getComponentObjects(pmt.Id);
        System.assert(componentObjects != null);
        
        AI_Response_Processing__c pro = [SELECT Id, AI_Prompt_Component__c FROM AI_Response_Processing__c LIMIT 1];
        Map<String, Object> processingData = AIPromptComponentController.getPromptProcessingData(pro.AI_Prompt_Component__c);
        System.assert(processingData != null);
        
        AIPromptComponentController.ResponseProcessingWrapper respWrap = AIPromptComponentController.getResponseProcessingData(pro.Id, pro.AI_Prompt_Component__c);
        System.assert(respWrap != null);
        Test.stopTest();
    }
    
}