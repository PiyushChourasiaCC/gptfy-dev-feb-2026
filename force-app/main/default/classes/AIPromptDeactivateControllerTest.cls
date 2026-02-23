/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 12-14-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public class AIPromptDeactivateControllerTest {
	
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
    static void deactivatePromptTest(){
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String data = AIPromptDeactivateController.deactivatePrompt(pmt.Id);
        Test.stopTest();
        System.assert(String.isBlank(data));
    }
    
    @isTest
    static void deactivatePromptExceptionTest(){
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        try{
        String data = AIPromptDeactivateController.deactivatePrompt(null);
        }catch(Exception e){
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }
    
}