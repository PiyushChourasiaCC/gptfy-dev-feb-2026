/**
 * @description       : 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 06-08-2023
 * @last modified by  : Rishabh Goel
**/
@isTest
public class AICockpitControllerTest {
	
    @testSetup
    static void makeData(){
        TestUtility.insertDataExtraction();
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.createCardConfiguration('DnB','APIDS',true);
        TestUtility.createCardConfiguration('GPTfy (OpenAI)','AMODL',true);
        
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
    static void getDetailsTest(){
        Test.startTest();
        AICockpitController.CockpitData data = AICockpitController.getDetails();
        Test.stopTest();
        System.Assert(data != null);
    }
    
}