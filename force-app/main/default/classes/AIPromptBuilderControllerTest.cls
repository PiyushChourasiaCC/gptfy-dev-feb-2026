@isTest
public class AIPromptBuilderControllerTest {

	@testSetup
    public static void setupData(){
        TestUtility.insertDataExtraction();
            AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
            
            AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
            
            prompt.AI_Connection__c = conn.Id;
            
            List<AI_Data_Extraction_Mapping__c> master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
            
            String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{ 
                'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master[0].Id,
                'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
            });
            
            prompt.AI_Data_Extraction_Mapping__c = master[0].Id;
            
            insert prompt;
            
            AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmtId, master[0].Id, 'Account', false);
            cmp1.AI_Prompt__c = prompt.Id;
            
            insert cmp1;
            
    }
    
    @isTest
    public static void getTabfieldsTest(){
        List<AI_Prompt__c> pmtList = [Select id from AI_Prompt__c where Name='Test' limit 1];
        Map<String,Object> pmtParams = new Map<String,Object>();
        pmtParams.put('Id',pmtList[0].Id);
        pmtParams.put(AIConstants.NAMESPACE+'Visibility_Condition__c','test');
        Test.startTest();
            AIPromptBuilderController.ReturnWrapper retWrap = AIPromptBuilderController.getTabFields(pmtList[0].Id);
        	AIPromptBuilderController.getProfileOptions();
        	AIPromptBuilderController.getTargetFieldOptions('Account');
            AIPromptBuilderController.updatePrompt(pmtParams);
        	Test.stopTest();
        System.assert(retWrap != null);
    }
}