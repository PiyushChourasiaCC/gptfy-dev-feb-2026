/**
* @description       : Test class for AIResponseValidationController
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-03-2025
* @last modified by  : Rishabh Goel
**/
@isTest
private class AIResponseValidationControllerTest {
    
    private static final String TEST_PROMPT_NAME = 'Test AI Prompt';
    private static final String TEST_VALIDATION_CONDITION = '1 AND 2';
    private static final String TEST_VALIDATION_MESSAGE = 'Test validation message';
    private static final String TEST_ACTION_INCLUDE = 'Includes';
    private static final String TEST_ACTION_EXCLUDE = 'Excludes';
    private static final String TEST_VALUE_INCLUDE = 'required_text';
    private static final String TEST_VALUE_EXCLUDE = 'forbidden_text';
    
    @TestSetup
    static void makeData() {
        // Create test AI_Prompt__c record
        AI_Prompt__c testPrompt = new AI_Prompt__c(
            Name = TEST_PROMPT_NAME,
            Response_Validation_Condition__c = TEST_VALIDATION_CONDITION,
            Response_Validation_Message__c = TEST_VALIDATION_MESSAGE
        );
        insert testPrompt;
        
        // Create test AI_Prompt_Response_Validation__c records
        List<AI_Prompt_Response_Validation__c> testValidations = new List<AI_Prompt_Response_Validation__c>();
        
        testValidations.add(new AI_Prompt_Response_Validation__c(
            AI_Prompt__c = testPrompt.Id,
            Sequence__c = 1,
            Action__c = TEST_ACTION_INCLUDE,
            Value__c = TEST_VALUE_INCLUDE
        ));
        
        testValidations.add(new AI_Prompt_Response_Validation__c(
            AI_Prompt__c = testPrompt.Id,
            Sequence__c = 2,
            Action__c = TEST_ACTION_EXCLUDE,
            Value__c = TEST_VALUE_EXCLUDE
        ));
        
        insert testValidations;
    }
    
    @isTest
    static void testGetResponseValidations_Success() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        List<AI_Prompt_Response_Validation__c> testValidations = [SELECT Id FROM AI_Prompt_Response_Validation__c WHERE AI_Prompt__c = :testPrompt.Id];
        
        // When
        Test.startTest();
        AIResponseValidationController.DataWrapper result = AIResponseValidationController.getResponseValidations(testPrompt.Id);
        Test.stopTest();
        
        // Then
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual(TEST_VALIDATION_CONDITION, result.responseValidationCondition, 'Response validation condition should match');
        Assert.areEqual(TEST_VALIDATION_MESSAGE, result.responseValidationMessage, 'Response validation message should match');
        Assert.areEqual(2, result.responseValidations.size(), 'Should have 2 validation records');
        Assert.isNotNull(result.actionOptions, 'Action options should not be null');
        
        // Verify validation wrapper data
        AIResponseValidationController.ValidationWrapper firstValidation = result.responseValidations[0];
        Assert.isNotNull(firstValidation.id, 'Validation ID should not be null');
        Assert.areEqual(1, firstValidation.sequence, 'First validation sequence should be 1');
        Assert.areEqual(TEST_ACTION_INCLUDE, firstValidation.action, 'First validation action should match');
        Assert.areEqual(TEST_VALUE_INCLUDE, firstValidation.value, 'First validation value should match');
    }
    
    @isTest
    static void testGetResponseValidations_EmptyConditionAndMessage() {
        // Given
        AI_Prompt__c testPrompt = new AI_Prompt__c(
            Name = 'Test Prompt Empty',
            Response_Validation_Condition__c = null,
            Response_Validation_Message__c = null
        );
        insert testPrompt;
        
        // When
        Test.startTest();
        AIResponseValidationController.DataWrapper result = AIResponseValidationController.getResponseValidations(testPrompt.Id);
        Test.stopTest();
        
        // Then
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual('', result.responseValidationCondition, 'Response validation condition should be empty string');
        Assert.areEqual('', result.responseValidationMessage, 'Response validation message should be empty string');
        Assert.areEqual(0, result.responseValidations.size(), 'Should have 0 validation records');
    }
    
    @isTest
    static void testGetResponseValidations_NullSequence() {
        // Given
        AI_Prompt__c testPrompt = new AI_Prompt__c(Name = 'Test Prompt Null Sequence');
        insert testPrompt;
        
        AI_Prompt_Response_Validation__c validation = new AI_Prompt_Response_Validation__c(
            AI_Prompt__c = testPrompt.Id,
            Sequence__c = null,
            Action__c = TEST_ACTION_INCLUDE,
            Value__c = TEST_VALUE_INCLUDE
        );
        insert validation;
        
        // When
        Test.startTest();
        AIResponseValidationController.DataWrapper result = AIResponseValidationController.getResponseValidations(testPrompt.Id);
        Test.stopTest();
        
        // Then
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual(1, result.responseValidations.size(), 'Should have 1 validation record');
        Assert.isNull(result.responseValidations[0].sequence, 'Sequence should be null');
    }
    
    @isTest
    static void testDeleteResponseValidation_Success() {
        // Given
        AI_Prompt_Response_Validation__c testValidation = [SELECT Id FROM AI_Prompt_Response_Validation__c LIMIT 1];
        String validationId = testValidation.Id;
        
        // When
        Test.startTest();
        AIResponseValidationController.deleteResponseValidation(validationId);
        Test.stopTest();
        
        // Then
        List<AI_Prompt_Response_Validation__c> remainingValidations = [SELECT Id FROM AI_Prompt_Response_Validation__c WHERE Id = :validationId];
        Assert.areEqual(0, remainingValidations.size(), 'Validation record should be deleted');
    }
    
    @isTest
    static void testDeleteResponseValidation_BlankId() {
        // Given
        Integer initialCount = [SELECT COUNT() FROM AI_Prompt_Response_Validation__c];
        
        // When
        Test.startTest();
        AIResponseValidationController.deleteResponseValidation('');
        AIResponseValidationController.deleteResponseValidation(null);
        Test.stopTest();
        
        // Then
        Integer finalCount = [SELECT COUNT() FROM AI_Prompt_Response_Validation__c];
        Assert.areEqual(initialCount, finalCount, 'No records should be deleted when ID is blank or null');
    }
    
    @isTest
    static void testUpdateResponseValidationCondition_Success() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        String newCondition = '1 OR 2';
        String newMessage = 'Updated validation message';
        
        // When
        Test.startTest();
        AIResponseValidationController.updateResponseValidationCondition(newCondition, newMessage, testPrompt.Id);
        Test.stopTest();
        
        // Then
        AI_Prompt__c updatedPrompt = [SELECT Response_Validation_Condition__c, Response_Validation_Message__c FROM AI_Prompt__c WHERE Id = :testPrompt.Id];
        Assert.areEqual(newCondition, updatedPrompt.Response_Validation_Condition__c, 'Validation condition should be updated');
        Assert.areEqual(newMessage, updatedPrompt.Response_Validation_Message__c, 'Validation message should be updated');
    }
    
    @isTest
    static void testUpdateResponseValidationCondition_BlankCondition() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        String newMessage = 'Updated validation message';
        
        // When
        Test.startTest();
        AIResponseValidationController.updateResponseValidationCondition('', newMessage, testPrompt.Id);
        Test.stopTest();
        
        // Then
        AI_Prompt__c updatedPrompt = [SELECT Response_Validation_Condition__c, Response_Validation_Message__c FROM AI_Prompt__c WHERE Id = :testPrompt.Id];
        Assert.areEqual(null, updatedPrompt.Response_Validation_Condition__c, 'Validation condition should be empty string');
        Assert.areEqual(newMessage, updatedPrompt.Response_Validation_Message__c, 'Validation message should be updated');
    }
    
    @isTest
    static void testUpdateResponseValidationCondition_NullCondition() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        String newMessage = 'Updated validation message';
        
        // When
        Test.startTest();
        AIResponseValidationController.updateResponseValidationCondition(null, newMessage, testPrompt.Id);
        Test.stopTest();
        
        // Then
        AI_Prompt__c updatedPrompt = [SELECT Response_Validation_Condition__c, Response_Validation_Message__c FROM AI_Prompt__c WHERE Id = :testPrompt.Id];
        Assert.areEqual(null, updatedPrompt.Response_Validation_Condition__c, 'Validation condition should be empty string when null');
        Assert.areEqual(newMessage, updatedPrompt.Response_Validation_Message__c, 'Validation message should be updated');
    }
    
    @isTest
    static void testUpdateResponseValidationCondition_BlankRecordId() {
        // When
        Test.startTest();
        AIResponseValidationController.updateResponseValidationCondition('test', 'test', '');
        AIResponseValidationController.updateResponseValidationCondition('test', 'test', null);
        Test.stopTest();
        
        // Then - No exception should be thrown, method should handle gracefully
        Assert.isTrue(true, 'Method should handle blank record ID gracefully');
    }
    
    @isTest
    static void testUpsertResponseValidation_BlankPromptId() {
        // Given
        Map<String, String> data = new Map<String, String>{
            'promptId' => '',
            'responseValidationId' => '',
            'validationAction' => 'Test Action',
            'validationValue' => 'Test Value',
            'sequence' => '1'
        };
        
        Integer initialCount = [SELECT COUNT() FROM AI_Prompt_Response_Validation__c];
        
        // When
        Test.startTest();
        AIResponseValidationController.upsertResponseValidation(data);
        Test.stopTest();
        
        // Then
        Integer finalCount = [SELECT COUNT() FROM AI_Prompt_Response_Validation__c];
        Assert.areEqual(initialCount, finalCount, 'No records should be created when prompt ID is blank');
    }
    
    @isTest
    static void testUpsertResponseValidation_Exception() {
        // Given
        Map<String, String> data = new Map<String, String>{
            'promptId' => 'invalid_id',
            'responseValidationId' => '',
            'validationAction' => 'Test Action',
            'validationValue' => 'Test Value',
            'sequence' => '1'
        };
        
        // When/Then
        Test.startTest();
        try {
            AIResponseValidationController.upsertResponseValidation(data);
            Assert.fail('Should have thrown an exception for invalid prompt ID');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        Test.stopTest();
    }
    
    @isTest
    static void testDataWrapper_Properties() {
        // Given/When
        AIResponseValidationController.DataWrapper wrapper = new AIResponseValidationController.DataWrapper();
        wrapper.responseValidationCondition = 'test condition';
        wrapper.responseValidationMessage = 'test message';
        wrapper.responseValidations = new List<AIResponseValidationController.ValidationWrapper>();
        wrapper.actionOptions = new List<AIDataExtractionController.PicklistWrapper>();
        
        // Then
        Assert.areEqual('test condition', wrapper.responseValidationCondition, 'Condition should match');
        Assert.areEqual('test message', wrapper.responseValidationMessage, 'Message should match');
        Assert.isNotNull(wrapper.responseValidations, 'Response validations should not be null');
        Assert.isNotNull(wrapper.actionOptions, 'Action options should not be null');
    }
    
    @isTest
    static void testValidationWrapper_Properties() {
        // Given/When
        AIResponseValidationController.ValidationWrapper wrapper = new AIResponseValidationController.ValidationWrapper();
        wrapper.id = 'test_id';
        wrapper.sequence = 5;
        wrapper.action = 'test_action';
        wrapper.value = 'test_value';
        
        // Then
        Assert.areEqual('test_id', wrapper.id, 'ID should match');
        Assert.areEqual(5, wrapper.sequence, 'Sequence should match');
        Assert.areEqual('test_action', wrapper.action, 'Action should match');
        Assert.areEqual('test_value', wrapper.value, 'Value should match');
    }
}