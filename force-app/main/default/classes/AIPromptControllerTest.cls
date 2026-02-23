/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class AIPromptControllerTest {
	
    @testSetup
    static void makeData(){
        Account a = TestUtility.getAccount(true);
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.createCardConfiguration('GPTfy',AIConstants.GPTfy_Card_Configuration_MDT_AMODL,true);
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => 'ADD_MAPPING',
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
    static void getPromptDataTest(){
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        Test.startTest();
        AIPromptController.PromptWrapper wrap1 = AIPromptController.getPromptData(pmt.Id);
        System.Assert(wrap1 != null);
        AIPromptController.PromptWrapper wrap2 = AIPromptController.getObjectBasedOptions('Account');
        System.Assert(wrap2 != null);
        AIPromptController.ObjectFieldsListWrapper wrap3 = AIPromptController.getObjectFields('Account');
        System.Assert(wrap3 != null);
        List<AIDataExtractionController.PicklistWrapper> wrap4 = AIPromptController.getRecordTypeOptions(AIPromptController.NAMESPACE+'AI_Security_Filters__c');
        System.Assert(wrap4.size() > 0);
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id, AI_Data_Extraction_Mapping__c FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        List<AIDataExtractionController.PicklistWrapper> mergeOptions = AIPromptController.getMergeFields(cDetail.Id, cDetail.AI_Data_Extraction_Mapping__c, 'Contact');
        System.Assert(mergeOptions != null);
        
        Account a = [SELECT Id FROM Account LIMIT 1];
        List<AI_Prompt__c> pmts = AIPromptSelector.getAIPromptByObjectId(a.Id);
        AIPromptController.getMergeObjects(cDetail.AI_Data_Extraction_Mapping__c);
        AIPromptController.getProfileOptions();
        wrap2.targetField = 'Test';
        wrap2.description = 'Test';
        wrap2.promptCommand = 'Test';
        wrap2.visibilityCondition = 'Test';
        wrap2.howItWorks = 'Test';
        wrap2.includeFiles = true;
        wrap2.allowUserInput = true;
        wrap2.temprature = 0.5;
        wrap2.topP = 0.5;
        wrap2.maxOutputTokens = 5;
        wrap2.profileIds = new List<String>{UserInfo.getProfileId()};
        wrap2.groundingEthical = new List<String>{'Test'};
        wrap2.groundingContent = new List<String>{'Test'};
        wrap2.localeAutomation = 'Test';
        wrap2.localeGptfyConsole = 'Test';
        wrap2.recordTypeIds = new List<String>{'Test'};
        wrap2.selectedPurpose = new List<String>{'Test'};
        wrap2.appendTimestamp = true;
        wrap2.mergeFieldObjectOptions = new List<Object>{'Test'};
        wrap2.selectedUsage = new List<String>{'Test'};
        wrap2.selectedSites = new List<String>{'Test'};
        List<AIDataExtractionController.PicklistWrapper> extractOptions = AIPromptController.getTargetFieldOptions('Account');
        Test.stopTest();
        System.Assert(pmts != null);
        System.Assert(extractOptions.size() > 0);
    }
    
    @isTest
    static void exceptionBlockCoverage(){
        AIPromptController.ObjectFieldsListWrapper wraplist = null;
        try{
              wraplist = AIPromptController.getObjectFields('');
        }catch(Exception e){
            wraplist = null;
        }
       System.Assert(wraplist == null);
    }
    
}