/**
 * @description       : 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 06-08-2023
 * @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class AIPromptImportControllerTest {
	
    @testSetup
    static void makeData(){
        TestUtility.insertDataExtraction();
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
        
        AI_Connection__c conn = TestUtility.getConnection('AnyAI_AnyPlatform', true);
        
        prompt.AI_Connection__c = conn.Id;
        AI_Data_Source__c dataSource = TestUtility.getAIDataSource(true);
        
        AI_Data_Extraction_Mapping__c master = [SELECT Id, AI_Data_Source__c FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        master.AI_Data_Source__c = dataSource.Id;
        update master;
        
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{ 
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
        });
        
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        
        insert prompt;
        
        AI_Prompt_Action__c promptAction = TestUtility.getAIPromptAction(prompt.Id, 'Update Field', true);
        AI_Prompt_Action_Detail__c promptActionDetail = TestUtility.getAIPromptActionDetail(promptAction.Id, 'Name', 'Hardcoded', true);
        AI_Prompt_Element__c Prompt_Element = TestUtility.getAIPromptElement(prompt.Id,prompt.Id,prompt.Id,1,'3/3 Column',250,'custom2',false,true);
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmtId, master.Id, 'Account', false);
        cmp1.AI_Prompt__c = prompt.Id;
        
        insert cmp1;
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(pmtId, cDetail.Id, 'Contact', true);
        
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(pmtId, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(pmtId);
        
        AI_Response_Processing__c rp = TestUtility.getResponseProcessing(cmp1.Id, 'Description', true);
        
        AI_Security_Filters__c sf = TestUtility.getAISecurityFilter('Post Code', AIDataExtractionService.RT_REGEX, true);
        AI_Security_Filters__c sf2 = TestUtility.getAISecurityFilter('Accounts', AIDataExtractionService.RT_BLOCKLIST, true);
    }
    
    @isTest
    static void exportImportTest(){  
        Test.startTest();        
    	ExportMappingWrapper wrap;
        try{
            AIPromptImportController.readFileData(JSON.serialize(wrap));
        }catch(Exception ex){}
        wrap = new ExportMappingWrapper();
        try{
            AIPromptImportController.readFileData(JSON.serialize(wrap));
        }catch(Exception ex){}
        try{
            AIPromptImportController.readFileData('[]');
        }catch(Exception ex){}
        wrap = AIPromptExportController.getMappings();
        Map<String, ExportMappingWrapper.ConnectionWrapper> mapConnection = wrap.connections;
        Integer i = 0;
        for(String k : mapConnection.keySet()){
            ExportMappingWrapper.ConnectionWrapper mapConn = mapconnection.get(k);
            mapConn.connectionName = mapConn.connectionName+i;
            mapconnection.put(k,mapConn);
        }
        AIPromptImportController.readFileData(JSON.serialize(wrap));
        try{
            AIPromptImportController.saveMappings(null, null, null, null, null, false);
        }catch(Exception ex){}
        AIPromptImportController.saveMappings(wrap.prompts, wrap.connections.values(), wrap.dataExtractionMappings.values(), !wrap.securityFilters.isEmpty() ? wrap.securityFilters.values()[0] : new List<ExportMappingWrapper.ExtractionSecurityFilterWrapper>(), wrap.dataSources, false);
        Test.stopTest();
        System.assert(wrap != null);
    }
    
}