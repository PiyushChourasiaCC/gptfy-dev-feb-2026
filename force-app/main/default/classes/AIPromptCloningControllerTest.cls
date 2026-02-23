/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 11-01-2023
* @last modified by  : Adarsh Sharma
**/
@isTest
public with sharing class AIPromptCloningControllerTest {
   
    @testSetup
    public static void createTestData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.'
        });
        
        AI_Prompt_Action__c actionInvokeApex = TestUtility.getAIPromptAction(pmtId,AIConstants.ACTION_TYPE_INVOKE_APEX, false);
        actionInvokeApex.Apex_Class_Name__c = 'TestApexClass';
        actionInvokeApex.Sequence__c = 1;
        insert actionInvokeApex;
        
        AI_Prompt_Action_Detail__c actionDetailHardcoded = TestUtility.getAIPromptActionDetail(actionInvokeApex.Id,'Field_B','Hardcoded', false);
        actionDetailHardcoded.Value__c = 'Hardcoded Value';
        insert actionDetailHardcoded;
        
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(pmtId, master.Id, 'Account', true);
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(pmtId, cDetail.Id, 'Contact', true);
        
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(pmtId, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(pmtId);
        
        AI_Response_Processing__c rp = TestUtility.getResponseProcessing(cmp1.Id, 'Description', true);
    }

    @isTest
    public static void cloneRecordTest(){
        AI_Prompt__c prompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String cloneRecordId = AIPromptCloningController.cloneRecord(prompt.Id, 'Cloned Name', 'Cloned Description', true);
        String mapStr = AIPromptCloningController.getAIPromptData(prompt.Id);
        Test.stopTest();
        System.assertEquals(true, prompt.Id != cloneRecordId);
        System.assertEquals(true, mapStr != NULL);
    }
    @isTest
    public static void cloneRecordTestWithPromptElements(){
        // Create AI Prompts with different configurations
        List<AI_Prompt__c> prompts = new List<AI_Prompt__c>();
        
        // Active Canvas prompt with profile restriction
        prompts.add(new AI_Prompt__c(
            Name = 'Active Canvas Prompt',
            Object__c = 'Account',
            Type__c = 'Canvas',
            Status__c = 'Active',
            Profiles__c = 'System Administrator',
            Auto_Refresh_Duration__c = 30,
            Prompt_Request_Id__c = 'active-prompt-123',
            Visibility_Condition__c = 'Industry = \'Technology\'',
            Visibility_Exception_Message__c = 'Account must be in Technology industry'
        ));
        
        // Summary prompt
        prompts.add(new AI_Prompt__c(
            Name = 'Summary Prompt',
            Object__c = 'Account',
            Type__c = 'Text',
            Status__c = 'Active',
            Auto_Refresh_Duration__c = 20,
            Prompt_Request_Id__c = 'summary-prompt-101'
        ));
        
        insert prompts;
        
        // Create AI Prompt Elements
        AI_Prompt_Element__c promptElement = new AI_Prompt_Element__c(
            AI_Parent_Prompt__c = prompts[0].Id,
            AI_Prompt__c = prompts[1].Id,
            AI_Summary_Prompt__c = prompts[1].Id,
            Sequence__c = 1,
            Width__c = '3/3 Column',
            Height__c = 250,
            Icon__c = 'custom2',
            Inherit_Prompt_Security__c = false
        );
        insert promptElement;

        Test.startTest();
        String cloneRecordId = AIPromptCloningController.cloneRecord(prompts[0].Id, 'Cloned Name', 'Cloned Description', true);
        Test.stopTest();
        
        // Query the cloned prompt
        List<AI_Prompt__c> clonedPrompts = [
            SELECT Id, Name, Object__c, Type__c, Status__c, Profiles__c, 
                Auto_Refresh_Duration__c, Prompt_Request_Id__c, 
                Visibility_Condition__c, Visibility_Exception_Message__c
            FROM AI_Prompt__c
            WHERE Name = 'Cloned Name'
        ];

        // Assert that exactly one cloned record exists
        Assert.areEqual(1, clonedPrompts.size(), 'There should be exactly one cloned prompt with the name "Cloned Name".');
        // Get the cloned record
        AI_Prompt__c cloned = clonedPrompts[0];

        // Assert that the cloned record has a different Id from the original
        Assert.areNotEqual(prompts[0].Id, cloned.Id, 'The cloned prompt should have a different Id from the original.');

        // Assert that important fields were copied correctly
        Assert.areEqual('Cloned Name', cloned.Name, 'Name should be "Cloned Name".');
        Assert.areEqual(prompts[0].Object__c, cloned.Object__c, 'Object__c should match the original.');
        Assert.areEqual(prompts[0].Type__c, cloned.Type__c, 'Type__c should match the original.');
        Assert.areNotEqual(prompts[0].Status__c, cloned.Status__c, 'Status__c should match the original.');
        Assert.areEqual(prompts[0].Profiles__c, cloned.Profiles__c, 'Profiles__c should match the original.');
        Assert.areEqual(prompts[0].Auto_Refresh_Duration__c, cloned.Auto_Refresh_Duration__c, 'Auto_Refresh_Duration__c should match the original.');
        Assert.areNotEqual(prompts[0].Prompt_Request_Id__c, cloned.Prompt_Request_Id__c, 'Prompt_Request_Id__c should match the original.');
        Assert.areEqual(prompts[0].Visibility_Condition__c, cloned.Visibility_Condition__c, 'Visibility_Condition__c should match the original.');
        Assert.areEqual(prompts[0].Visibility_Exception_Message__c, cloned.Visibility_Exception_Message__c, 'Visibility_Exception_Message__c should match the original.');

        // Query the prompt element related to the cloned prompt
        List<AI_Prompt_Element__c> clonedElements = [
            SELECT Id, AI_Parent_Prompt__c, AI_Prompt__c, AI_Summary_Prompt__c, Sequence__c, Width__c, Height__c, Icon__c, Inherit_Prompt_Security__c
            FROM AI_Prompt_Element__c
            WHERE AI_Parent_Prompt__c = :cloned.Id
        ];

        // Assert that there is at least one prompt element for the cloned prompt
        Assert.areEqual(1, clonedElements.size(), 'There should be exactly one prompt element for the cloned prompt.');

        // Get the cloned element
        AI_Prompt_Element__c clonedElement = clonedElements[0];

        // Assert important fields were copied or set correctly
        Assert.areEqual(cloned.Id, clonedElement.AI_Parent_Prompt__c, 'AI_Parent_Prompt__c should match the cloned prompt Id.');
        Assert.areEqual(prompts[1].Id, clonedElement.AI_Prompt__c, 'AI_Prompt__c should match the expected prompt.');
        Assert.areEqual(prompts[1].Id, clonedElement.AI_Summary_Prompt__c, 'AI_Summary_Prompt__c should match the expected summary prompt.');
        Assert.areEqual(1, clonedElement.Sequence__c, 'Sequence__c should be 1.');
        Assert.areEqual('3/3 Column', clonedElement.Width__c, 'Width__c should be "3/3 Column".');
        Assert.areEqual(250, clonedElement.Height__c, 'Height__c should be 250.');
        Assert.areEqual('custom2', clonedElement.Icon__c, 'Icon__c should be "custom2".');
        Assert.areEqual(false, clonedElement.Inherit_Prompt_Security__c, 'Inherit_Prompt_Security__c should be false.');
    }
}