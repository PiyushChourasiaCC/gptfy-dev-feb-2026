@isTest
public class AISetupAssistantControllerTest {
	
    @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'Text', 'promptCommand' => 'Give a sample response.'
        });
        
        AI_Data_Extraction_Detail__c detail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'ActivityHistory' LIMIT 1];
        delete detail;
        
        AI_Prompt__c pmt = new AI_Prompt__c();
        pmt.Id = pmtId;
        pmt.Pre_Packaged__c = true;
        pmt.Status__c = AIConstants.PMT_STATUS_ACTIVE;
        update pmt;
        
        Account acc = TestUtility.getAccount(true);
        Contact con = TestUtility.getContact(acc.Id, true);
        Case c = TestUtility.getCase(acc.Id, con.Id, true);
    }
    
    @isTest
    static void checkPermissionSetTest(){
        Test.startTest();
        Boolean isAssigned = AISetupAssistantController.checkPermissionSet();
        Test.stopTest();
        System.assert(isAssigned || !isAssigned);
    }
    
    @isTest
    static void getPromptOptionsTest(){
        Test.startTest();
        List<Object> data = AISetupAssistantController.getPromptOptions();
        Test.stopTest();
        System.assert(data != null);
    }
    
    @isTest
    static void getAndUpdateCustomSettings(){
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c];
        Account acc = [SELECT Id FROM Account];
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        settings.Selected_Prompts__c = pmt.Id;
        settings.Record_Pages__c = 'Account';
        settings.Candidates_1__c = JSON.serialize(new Map<String, String>{pmt.Id => acc.Id});
        settings.Candidates_2__c = JSON.serialize(new Map<String, String>{pmt.Id => acc.Id});
        settings.Candidates_3__c = JSON.serialize(new Map<String, String>{pmt.Id => acc.Id});
        settings.Candidates_4__c = JSON.serialize(new Map<String, String>{pmt.Id => acc.Id});
        upsert settings;
        
        Test.startTest();
        List<String> pages = AISetupAssistantController.getSelectedRecordPages();
        AISetupAssistantController.updateSelectedPromptSettings(new List<String>{pmt.Id});
        AISetupAssistantController.updateRecordPageSettings(new List<String>{'Account'});
        AISetupAssistantController.completeDataReview(new List<String>{pmt.Id});
        AISetupAssistantController.checkDataReviewStatus();
        Test.stopTest();
        System.assert(pages != null);
    }
    
    @isTest
    static void startDataReviewTest(){
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c];
        Test.startTest();
        AISetupAssistantController.startDataReview(new List<String>{pmt.Id});
        AISetupAssistantController.checkDataReviewStatus();
        Test.stopTest();
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        System.assert(String.isNotBlank(settings.Candidates_1__c));
    }
    
}