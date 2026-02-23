@isTest
public class AIPromptActionServiceTest {

    @testSetup
    static void setupData() {
        // Step 1: Create necessary connections and extraction mappings
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
        
        // Fetch the Data Extraction Mapping created in `insertDataExtraction`
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        // Step 2: Create an AI Prompt with required data
        String promptId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account',
            'aiConnection' => conn.Id,
            'promptName' => 'Test Prompt',
            'extractionMappingId' => master.Id,
            'selectedType' => 'JSON',
            'promptCommand' => 'Give a sample response.'
        });
        
        // Step 3: Create prompt components linked to different objects for testing
        AI_Prompt_Component__c componentAccount = TestUtility.getPromptComponent(promptId, master.Id, 'Account', true);
        AI_Data_Extraction_Detail__c contactDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        AI_Prompt_Component__c componentContact = TestUtility.getPromptComponent(promptId, contactDetail.Id, 'Contact', true);
        
        // Step 4: Create an Account record for testing the update action
        Account testAccount = TestUtility.getAccount(true);

        // Step 5: Create a Response record associated with the AI Prompt
        AI_Response__c response = new AI_Response__c(
            AI_Prompt__c = promptId,
            Record_Id__c = testAccount.Id,
            AI_Processed_Data_PII_Added__c = '{"SampleKey":"SampleValue"}'
        );
        insert response;

        // Step 6: Create various prompt actions (Update Field, Create Record, Invoke Flow, Invoke Apex)
        AI_Prompt_Action__c actionUpdateField = new AI_Prompt_Action__c(
            AI_Prompt__c = promptId,
            Action__c = AIConstants.ACTION_TYPE_UPDATE_FIELD,
            Field_API_Name__c = 'Name',
            Sequence__c = 1,
            Append_Timestamp__c = true,
            Prompt_Component__c = componentContact.Id
        );
        insert actionUpdateField;

        AI_Prompt_Action__c actionCreateRecord = new AI_Prompt_Action__c(
            AI_Prompt__c = promptId,
            Action__c = AIConstants.ACTION_TYPE_CREATE_RECORD,
            Object_Name__c = 'Contact',
            Sequence__c = 2
        );
        insert actionCreateRecord;

        // Add necessary field mappings for the "Create Record" action, e.g., LastName on Contact
        AI_Prompt_Action_Detail__c actionDetailLastName = new AI_Prompt_Action_Detail__c(
            AI_Prompt_Action__c = actionCreateRecord.Id,
            Field_API_Name__c = 'LastName',
            Type__c = AIConstants.ACTION_DETAIL_TYPE_HARDCODED,
            Value__c = 'Test Last Name'
        );
        insert actionDetailLastName;

        AI_Prompt_Action__c actionInvokeFlow = new AI_Prompt_Action__c(
            AI_Prompt__c = promptId,
            Action__c = AIConstants.ACTION_TYPE_INVOKE_FLOW,
            Flow_API_Name__c = 'Test_Flow',
            Sequence__c = 3
        );
        insert actionInvokeFlow;

        AI_Prompt_Action__c actionInvokeApex = new AI_Prompt_Action__c(
            AI_Prompt__c = promptId,
            Action__c = AIConstants.ACTION_TYPE_INVOKE_APEX,
            Apex_Class_Name__c = 'TestApexClass',
            Sequence__c = 4
        );
        insert actionInvokeApex;
    }

    @isTest
    static void testManagePromptActions_UpdateField() {
        // Retrieve the response and validate that required fields are available
        AI_Response__c response = [SELECT Id, AI_Prompt__c, Record_Id__c, AI_Processed_Data_PII_Added__c FROM AI_Response__c LIMIT 1];
        List<AI_Prompt_Action__c> lstOfActions = [SELECT Id, Action__c, Apex_Class_Name__c, Append_Timestamp__c, 
                                                  Description__c, Field_API_Name__c, Flow_API_Name__c, 
                                                  Object_Name__c, Prompt_Component__c, Sequence__c,
                                                  (SELECT Id, Field_API_Name__c, Type__c, Value__c FROM Prompt_Action_Details__r)
                                                  FROM AI_Prompt_Action__c
                                                  WHERE AI_Prompt__c =:response.AI_Prompt__c
                                                  ORDER BY Sequence__c ASC NULLS LAST];
        
        Test.startTest();
        List<AI_Security_Audit_Detail__c> auditDetails = AIPromptActionService.managePromptActions(response);
        Test.stopTest();

        // Assert that audit details were created and check for the "Update Field" action type
        System.assertNotEquals(null, auditDetails, 'Expected audit details to be returned');
        Boolean foundUpdate = false;
        for (AI_Security_Audit_Detail__c detail : auditDetails) {
            if (detail.Prompt_Action_Type__c == AIConstants.ACTION_TYPE_UPDATE_FIELD) {
                foundUpdate = true;
                break;
            }
        }
        System.assertEquals(true, foundUpdate, 'Expected an update field action in audit details');
    }

    @isTest
    static void testManagePromptActions_CreateRecord() {
        AI_Response__c response = [SELECT Id, AI_Prompt__c, Record_Id__c, AI_Processed_Data_PII_Added__c FROM AI_Response__c LIMIT 1];
        
        Test.startTest();
        List<AI_Security_Audit_Detail__c> auditDetails = AIPromptActionService.managePromptActions(response);
        Test.stopTest();

        Boolean foundCreate = false;
        for (AI_Security_Audit_Detail__c detail : auditDetails) {
            if (detail.Prompt_Action_Type__c == AIConstants.ACTION_TYPE_CREATE_RECORD) {
                foundCreate = true;
                break;
            }
        }
        System.assertEquals(true, foundCreate, 'Expected a create record action in audit details');
    }

    @isTest
    static void testManagePromptActions_InvokeFlow() {
        AI_Response__c response = [SELECT Id, AI_Prompt__c, Record_Id__c, AI_Processed_Data_PII_Added__c FROM AI_Response__c LIMIT 1];
        
        Test.startTest();
        List<AI_Security_Audit_Detail__c> auditDetails = AIPromptActionService.managePromptActions(response);
        Test.stopTest();

        Boolean foundFlow = false;
        for (AI_Security_Audit_Detail__c detail : auditDetails) {
            if (detail.Prompt_Action_Type__c == AIConstants.ACTION_TYPE_INVOKE_FLOW) {
                foundFlow = true;
                break;
            }
        }
        System.assertEquals(true, foundFlow, 'Expected an invoke flow action in audit details');
    }

    @isTest
    static void testManagePromptActions_InvokeApex() {
        AI_Response__c response = [SELECT Id, AI_Prompt__c, Record_Id__c, AI_Processed_Data_PII_Added__c FROM AI_Response__c LIMIT 1];
        
        Test.startTest();
        List<AI_Security_Audit_Detail__c> auditDetails = AIPromptActionService.managePromptActions(response);
        Test.stopTest();

        Boolean foundApex = false;
        for (AI_Security_Audit_Detail__c detail : auditDetails) {
            if (detail.Prompt_Action_Type__c == AIConstants.ACTION_TYPE_INVOKE_APEX) {
                foundApex = true;
                break;
            }
        }
        System.assertEquals(true, foundApex, 'Expected an invoke apex action in audit details');
    }
}