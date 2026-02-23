@isTest
public class AIDyanmicFieldRendringControllerTest {

    @testSetup
    static void makeData(){
        Account acc = new Account(Name = 'Test Account22');
        insert acc;
        
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
        List<AI_Data_Extraction_Mapping__c> master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master[0].Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.', 'groundingContent' => 'Only answer what has been asked for.', 
            'groundingEthical' => 'Do not hallucinate.'
        });
        
    }
    
    @isTest
    static void getExtractedDataTest(){
        List<Account> a = [SELECT Id FROM Account LIMIT 1];
        List<AI_Prompt__c> pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        AI_Response__c resp = AIGlobalUtility.getExtractedData(a[0].Id, pmt[0].Id);
        insert resp;
        Contentversion cv = TestUtility.getContentversion('Name', 'Test', 'Test', false);
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion where Id = :cv.Id]; 
        ContentDocumentLink cdl = TestUtility.getContentDocumentLink(resp.Id, cv.ContentDocumentId, false);
        insert cdl;
        Test.startTest();
        
        Map<String, Object> m = AIDyanmicFieldRendringController.getFieldData(new List<String>{'Name'}, resp.Id);
        Test.stopTest();
        System.assert(m != NULL);
    }
}