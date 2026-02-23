@isTest
public class AIVoiceConfigurationControllerTest {
	
    @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        conn.Type__c = AIConstants.AI_MODEL_TYPE_VOICE;
        insert conn;
        
        TestUtility.insertDataExtraction();
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
    }
    
    @isTest
    static void getConfigurationDetailsTest(){
        Test.startTest();
        AIVoiceConfigurationController.ConfigurationWrapper wrap = AIVoiceConfigurationController.getConfigurationDetails();
        AIVoiceConfigurationController.updateConfiguration(JSON.serialize(wrap)); 
        
        AI_Voice_Configuration__c obj = [SELECT ID FROM AI_Voice_Configuration__c LIMIT 1];
        AIVoiceConfigurationController.ConfigurationDetailWrapper detail_wrap = new AIVoiceConfigurationController.ConfigurationDetailWrapper();
        AIVoiceConfigurationController.updateConfigurationDetail(JSON.serialize(detail_wrap), obj.Id);
        wrap = AIVoiceConfigurationController.getConfigurationDetails();
        Test.stopTest();
        System.assert(wrap != null);
    }
    
}