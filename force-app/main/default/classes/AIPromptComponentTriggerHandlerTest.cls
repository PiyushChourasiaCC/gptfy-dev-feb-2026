@isTest
public class AIPromptComponentTriggerHandlerTest {
	
    @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
        });
    }
    
    @isTest
    static void triggerTest(){
        AI_Prompt__c pmt = [SELECT Id, AI_Data_Extraction_Mapping__c FROM AI_Prompt__c LIMIT 1];
        
        Test.startTest();
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmt.Id, pmt.AI_Data_Extraction_Mapping__c, 'Account', true);
        cmp1.Length__c = 'Under 30 Words';
        cmp1.Language__c = 'English';
        cmp1.Tone__c = 'Empathetic';
        cmp1.Format__c = 'Bullet Points';
        cmp1.Constraint_Value__c = 'test';
        cmp1.Additional_Instructions__c = 'test';
        update cmp1;
        Test.stopTest();
        System.assert(cmp1 != null);
    }
    
}