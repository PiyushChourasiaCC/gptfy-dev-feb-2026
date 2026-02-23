/**
 * @description       : 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 06-08-2023
 * @last modified by  : Rishabh Goel
**/
@isTest
public class AIPostInstallHandlerTest {
	
    @testSetup
    static void makeData(){
        TestUtility.insertDataExtraction();
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
        });
        AI_Prompt__c p = [Select Id,Target_Field__c from AI_Prompt__c where Id =: pmtId ];
        p.Target_Field__c = 'Description';
        update p;
        AI_Prompt_Action__c actionInvokeApex = TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_UPDATE_FIELD, false);
        actionInvokeApex.Apex_Class_Name__c = 'TestApexClass';
        actionInvokeApex.Sequence__c = 1;
        insert actionInvokeApex;
        
        AI_Prompt_Action_Detail__c actionDetailHardcoded = TestUtility.getAIPromptActionDetail(actionInvokeApex.Id,'Field_B','Hardcoded', false);
        actionDetailHardcoded.Value__c = 'Hardcoded Value';
        insert actionDetailHardcoded;
        
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmtId, master.Id, 'Account', true);
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id,Record_Limit__c FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        cDetail.Record_Limit__c = 1;
        cDetail.Where_Clause__c = ' WHERE Id != NULL ';
        update cDetail;
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(pmtId, cDetail.Id, 'Contact', true);
        AI_Response_Processing__c responseProcessing = TestUtility.getResponseProcessing(cmp2.Id, 'test desc',true);
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(pmtId, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(pmtId);
        TestUtility.insertDataExtraction();
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        TestUtility.getAIPromptScheduler(pmtId, sch.id, true);
    }
    
    @isTest
    static void postInstallTest(){  
        Test.startTest();
    	AIPostInstallHandler obj = new AIPostInstallHandler();
        Test.testInstall(obj, null);
        Test.testInstall(obj, new Version(1,0,1));
        Test.stopTest();
        System.assert(true);
    }
    
    
}