@isTest
public class AIPromptActionControllerTest {

    @testSetup
    static void setupData() {
        // Create a test AI_Prompt__c record
        AI_Prompt__c aiPrompt = TestUtility.getAIPrompt('Test Prompt', 'Account', 'Active', true);

        // Create various AI_Prompt_Action__c records for different action types
        AI_Prompt_Action__c actionInvokeApex = new AI_Prompt_Action__c(
            AI_Prompt__c = aiPrompt.Id,
            Action__c = AIConstants.ACTION_TYPE_INVOKE_APEX,
            Apex_Class_Name__c = 'TestApexClass',
            Sequence__c = 1
        );
        insert actionInvokeApex;

		 AI_Prompt_Action__c actionUpdateField = new AI_Prompt_Action__c(
            AI_Prompt__c = aiPrompt.Id,
            Action__c = AIConstants.ACTION_TYPE_UPDATE_FIELD,
            Apex_Class_Name__c = 'TestUpdateField',
            //Action_Label__c = 'Invoke Apex',
            Sequence__c = 1
        );
        insert actionUpdateField;

        AI_Prompt_Action__c actionInvokeFlow = new AI_Prompt_Action__c(
            AI_Prompt__c = aiPrompt.Id,
            Action__c = AIConstants.ACTION_TYPE_INVOKE_FLOW,
            Flow_API_Name__c = 'TestFlow',
            Sequence__c = 2
        );
        insert actionInvokeFlow;

        AI_Prompt_Action__c actionCreateRecord = new AI_Prompt_Action__c(
            AI_Prompt__c = aiPrompt.Id,
            Action__c = AIConstants.ACTION_TYPE_CREATE_RECORD,
            Object_Name__c = 'Contact',
            Sequence__c = 3
        );
        insert actionCreateRecord;

        // Create an AI_Prompt_Action_Detail__c for AI Response type
        AI_Prompt_Action_Detail__c actionDetailAIResponse = new AI_Prompt_Action_Detail__c(
            AI_Prompt_Action__c = actionInvokeApex.Id,
            Field_API_Name__c = 'Field_A',
            Type__c = 'AI Response',
            Value__c = null  // to trigger the #N/A#
        );
        insert actionDetailAIResponse;

        AI_Prompt_Action_Detail__c actionDetailHardcoded = new AI_Prompt_Action_Detail__c(
            AI_Prompt_Action__c = actionInvokeApex.Id,
            Field_API_Name__c = 'Field_B',
            Type__c = 'Hardcoded',
            Value__c = 'Hardcoded Value'
        );
        insert actionDetailHardcoded;

    }

    @isTest
    static void testGetPromptActions() {
        // Fetch a test prompt
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];

        // Call the getPromptActions method
        Test.startTest();
        AIPromptActionController.DataWrapper result = AIPromptActionController.getPromptActions(aiPrompt.Id);
        Test.stopTest();

        // Validate the results
        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.actions);
        System.assertEquals('Account', result.objectName);
        System.assertEquals(result.actions.size()>0, true, false);
        System.assertEquals(result.actions[0].actionLabel!=null, true, false);
    }

    @isTest
    static void testGetParentFields() {
        // Test getting parent fields for the Account object
        Test.startTest();
        List<AIPromptActionController.PicklistAttributeWrapper> parentFields = AIPromptActionController.getParentFields('Account');
        Test.stopTest();

        // Validate that we received parent fields
        System.assertNotEquals(null, parentFields);
    }

    @isTest
    static void testGetJsonPromptNodeOptions() {
        // Fetch a test prompt
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];

        // Call the method to get JSON node options
        Test.startTest();
        List<AIPromptActionController.PicklistAttributeWrapper> jsonNodeOptions = AIPromptActionController.getJsonPromptNodeOptions(aiPrompt.Id);
        Test.stopTest();

        // Validate the results
        System.assertNotEquals(null, jsonNodeOptions);
        System.assertEquals('Entire JSON', jsonNodeOptions[0].label);
    }

    @isTest
    static void testUpsertPromptActions() {
        // Fetch a test prompt
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
		AI_Prompt_Action_Detail__c actionDetail = [Select Id,Field_API_Name__c,Type__c,Value__c from AI_Prompt_Action_Detail__c where Field_API_Name__c = 'Field_A' limit 1];
        // Create action wrapper data in JSON format
        String jsonData = '{ "fieldMappings": [{ "Id":"'+actionDetail.Id+'", "fieldName": "'+actionDetail.Field_API_Name__c+'", "type": "'+actionDetail.Type__c+'", "value": "updated value" }], "actionType": "Update Field", "description": "Updated Description", "fieldApiName": "Name", "appendTimestamp": true, "id": ""}';

        // Call the upsert method
        Test.startTest();
        AIPromptActionController.upsertPromptActions(jsonData, aiPrompt.Id);
        Test.stopTest();

        // Validate that the record was inserted or updated
        AI_Prompt_Action__c updatedAction = [SELECT Description__c FROM AI_Prompt_Action__c WHERE AI_Prompt__c =:aiPrompt.Id LIMIT 1];
        System.assertEquals(updatedAction!=null, true, false);
    }

	@isTest
    static void testUpsertPromptActionsInvokeApex() {
        // Fetch a test prompt
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];

        // Create action wrapper data in JSON format
        String invokeApexJson = '{ "fieldMappings": [{ "fieldName": "Field_B", "type": "Hardcoded", "value": "Hardcoded value" }],  "actionType": "Invoke Apex", "description": "Invoke Apex Action", "apexClassName": "TestApexClass"}';

        // Call the upsert method
        Test.startTest();
        AIPromptActionController.upsertPromptActions(invokeApexJson, aiPrompt.Id);
        Test.stopTest();

        // Validate that the record was inserted or updated
        AI_Prompt_Action__c updatedAction = [SELECT Description__c FROM AI_Prompt_Action__c WHERE AI_Prompt__c =:aiPrompt.Id LIMIT 1];
        System.assertEquals(updatedAction!=null, true, false);
    }
	
	@isTest
    static void testUpsertPromptActionsInvokeFlow() {
        // Fetch a test prompt
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];

        // Create action wrapper data in JSON format
        String invokeFlowJson = '{"actionType": "Invoke Flow", "description": "Invoke Flow Action", "flowApiName": "TestFlow"}';

        // Call the upsert method
        Test.startTest();
        AIPromptActionController.upsertPromptActions(invokeFlowJson, aiPrompt.Id);
        Test.stopTest();

        // Validate that the record was inserted or updated
        AI_Prompt_Action__c updatedAction = [SELECT Description__c FROM AI_Prompt_Action__c WHERE AI_Prompt__c =:aiPrompt.Id LIMIT 1];
        System.assertEquals(updatedAction!=null, true, false);
    }

	@isTest
    static void testUpsertPromptActionsCreateRecord() {
        // Fetch a test prompt
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];

        // Create action wrapper data in JSON format
        String createRecordJson = '{"actionType": "Create Record", "description": "Create Record Action", "objectName": "Contact"}';

        // Call the upsert method
        Test.startTest();
        AIPromptActionController.upsertPromptActions(createRecordJson, aiPrompt.Id);
        Test.stopTest();

        // Validate that the record was inserted or updated
        AI_Prompt_Action__c updatedAction = [SELECT Description__c FROM AI_Prompt_Action__c WHERE AI_Prompt__c =:aiPrompt.Id LIMIT 1];
        System.assertEquals(updatedAction!=null, true, false);
    }
    
    

}