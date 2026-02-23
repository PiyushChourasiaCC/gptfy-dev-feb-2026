@isTest
public class AIGlobalUtilityTest {
	
    @testSetup
    static void makeData(){
        Account acc = new Account(Name = 'Test Account22');
        insert acc;
        
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.', 'groundingContent' => 'Only answer what has been asked for.', 
            'groundingEthical' => 'Do not hallucinate.'
        });
    }
    
    @isTest
    static void getExtractedDataTest(){
        Account a = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        Test.startTest();
        AI_Response__c resp = AIGlobalUtility.getExtractedData(a.Id, pmt.Id);
        Test.stopTest();
        System.assert(resp != NULL);
    }
    
    @isTest
    static void aiUtilityTest(){
        Test.startTest();
        AIUtility.updateGPTfySettings(AIConstants.NAMESPACE+'Blank_Replacement_Value__c', 'Test2');
        AIUtility.updateCustomSettings(AIConstants.NAMESPACE+'Typewriter_Effect__c', true);
        Test.stopTest();
        GPTfy_Settings__c settings = [Select id,Blank_Replacement_Value__c from GPTfy_Settings__c where Blank_Replacement_Value__c='Test2'];
        System.assert(settings != NULL);
    }
    
}