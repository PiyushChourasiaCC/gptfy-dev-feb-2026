/**
* @description       : Test class for AIResponseValidationUtility
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-03-2025
* @last modified by  : Rishabh Goel
**/
@isTest
private class AIResponseValidationUtilityTest {
    
    private static final String TEST_PROMPT_NAME = 'Test AI Prompt';
    private static final String TEST_RESPONSE_VALID = 'This response contains required_text and does not contain forbidden content';
    private static final String TEST_RESPONSE_INVALID = 'This response contains forbidden_text';
    private static final String TEST_RESPONSE_MISSING = 'This response is missing required content';
    
    @TestSetup
    static void makeData() {
        // Create test AI_Prompt__c record
        AI_Prompt__c testPrompt = new AI_Prompt__c(
            Name = TEST_PROMPT_NAME,
            Response_Validation_Condition__c = '1 AND 2',
            Response_Validation_Message__c = 'Test validation message'
        );
        insert testPrompt;
        
        // Create test AI_Prompt_Response_Validation__c records
        List<AI_Prompt_Response_Validation__c> testValidations = new List<AI_Prompt_Response_Validation__c>();
        
        testValidations.add(new AI_Prompt_Response_Validation__c(
            AI_Prompt__c = testPrompt.Id,
            Sequence__c = 1,
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE,
            Value__c = 'required_text'
        ));
        
        testValidations.add(new AI_Prompt_Response_Validation__c(
            AI_Prompt__c = testPrompt.Id,
            Sequence__c = 2,
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_EXCLUDE,
            Value__c = 'forbidden_text'
        ));
        
        insert testValidations;
    }
    
    @isTest
    static void testValidateResponse_ValidResponse() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id, Response_Validation_Condition__c, Response_Validation_Message__c FROM AI_Prompt__c LIMIT 1];
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.validateResponse(testPrompt, TEST_RESPONSE_VALID);
        Test.stopTest();
        
        // Then
        Assert.isTrue(result, 'Response should be valid');
    }
    
    @isTest
    static void testValidateResponse_InvalidResponse_ForbiddenText() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id, Response_Validation_Condition__c, Response_Validation_Message__c FROM AI_Prompt__c LIMIT 1];
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.validateResponse(testPrompt, TEST_RESPONSE_INVALID);
        Test.stopTest();
        
        // Then
        Assert.isFalse(result, 'Response should be invalid due to forbidden text');
    }
    
    @isTest
    static void testValidateResponse_InvalidResponse_MissingRequiredText() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id, Response_Validation_Condition__c, Response_Validation_Message__c FROM AI_Prompt__c LIMIT 1];
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.validateResponse(testPrompt, TEST_RESPONSE_MISSING);
        Test.stopTest();
        
        // Then
        Assert.isFalse(result, 'Response should be invalid due to missing required text');
    }
    
    @isTest
    static void testValidateResponse_BlankResponse() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id, Response_Validation_Condition__c, Response_Validation_Message__c FROM AI_Prompt__c LIMIT 1];
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.validateResponse(testPrompt, '');
        Test.stopTest();
        
        // Then
        Assert.isTrue(result, 'Blank response should be considered valid (no validation performed)');
    }
    
    @isTest
    static void testValidateResponse_NullResponse() {
        // Given
        AI_Prompt__c testPrompt = [SELECT Id, Response_Validation_Condition__c, Response_Validation_Message__c FROM AI_Prompt__c LIMIT 1];
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.validateResponse(testPrompt, null);
        Test.stopTest();
        
        // Then
        Assert.isTrue(result, 'Null response should be considered valid (no validation performed)');
    }
    
    @isTest
    static void testValidateResponse_NoValidations() {
        // Given
        AI_Prompt__c testPrompt = new AI_Prompt__c(
            Name = 'Test Prompt No Validations',
            Response_Validation_Condition__c = null,
            Response_Validation_Message__c = null
        );
        insert testPrompt;
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.validateResponse(testPrompt, TEST_RESPONSE_VALID);
        Test.stopTest();
        
        // Then
        Assert.isTrue(result, 'Response should be valid when no validations exist');
    }
    
    @isTest
    static void testValidateResponse_BlankValidationCondition() {
        // Given
        AI_Prompt__c testPrompt = new AI_Prompt__c(
            Name = 'Test Prompt Blank Condition',
            Response_Validation_Condition__c = '',
            Response_Validation_Message__c = 'Test message'
        );
        insert testPrompt;
        
        AI_Prompt_Response_Validation__c validation = new AI_Prompt_Response_Validation__c(
            AI_Prompt__c = testPrompt.Id,
            Sequence__c = 1,
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE,
            Value__c = 'required_text'
        );
        insert validation;
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.validateResponse(testPrompt, TEST_RESPONSE_VALID);
        Test.stopTest();
        
        // Then
        Assert.isTrue(result, 'Response should be valid when validation condition is blank');
    }
    
    @isTest
    static void testValidateResponse_OrCondition() {
        // Given
        AI_Prompt__c testPrompt = new AI_Prompt__c(
            Name = 'Test Prompt OR Condition',
            Response_Validation_Condition__c = '1 OR 2',
            Response_Validation_Message__c = 'Test message'
        );
        insert testPrompt;
        
        List<AI_Prompt_Response_Validation__c> validations = new List<AI_Prompt_Response_Validation__c>();
        validations.add(new AI_Prompt_Response_Validation__c(
            AI_Prompt__c = testPrompt.Id,
            Sequence__c = 1,
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE,
            Value__c = 'option1'
        ));
        validations.add(new AI_Prompt_Response_Validation__c(
            AI_Prompt__c = testPrompt.Id,
            Sequence__c = 2,
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE,
            Value__c = 'option2'
        ));
        insert validations;
        
        // When
        Test.startTest();
        Boolean result1 = AIResponseValidationUtility.validateResponse(testPrompt, 'This contains option1');
        Boolean result2 = AIResponseValidationUtility.validateResponse(testPrompt, 'This contains option2');
        Boolean result3 = AIResponseValidationUtility.validateResponse(testPrompt, 'This contains neither');
        Test.stopTest();
        
        // Then
        Assert.isTrue(result1, 'Response with option1 should be valid');
        Assert.isTrue(result2, 'Response with option2 should be valid');
        Assert.isFalse(result3, 'Response with neither option should be invalid');
    }
    
    @isTest
    static void testCheckValidityBasedOnAction_Include_Valid() {
        // Given
        AI_Prompt_Response_Validation__c validation = new AI_Prompt_Response_Validation__c(
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE,
            Value__c = 'required_text'
        );
        String response = 'This response contains required_text';
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.checkValidityBasedOnAction(response, validation);
        Test.stopTest();
        
        // Then
        Assert.isTrue(result, 'Response should be valid when it contains required text');
    }
    
    @isTest
    static void testCheckValidityBasedOnAction_Include_Invalid() {
        // Given
        AI_Prompt_Response_Validation__c validation = new AI_Prompt_Response_Validation__c(
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE,
            Value__c = 'required_text'
        );
        String response = 'This response does not contain the required content';
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.checkValidityBasedOnAction(response, validation);
        Test.stopTest();
        
        // Then
        Assert.isFalse(result, 'Response should be invalid when it does not contain required text');
    }
    
    @isTest
    static void testCheckValidityBasedOnAction_Exclude_Valid() {
        // Given
        AI_Prompt_Response_Validation__c validation = new AI_Prompt_Response_Validation__c(
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_EXCLUDE,
            Value__c = 'forbidden_text'
        );
        String response = 'This response does not contain forbidden content';
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.checkValidityBasedOnAction(response, validation);
        Test.stopTest();
        
        // Then
        Assert.isTrue(result, 'Response should be valid when it does not contain forbidden text');
    }
    
    @isTest
    static void testCheckValidityBasedOnAction_Exclude_Invalid() {
        // Given
        AI_Prompt_Response_Validation__c validation = new AI_Prompt_Response_Validation__c(
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_EXCLUDE,
            Value__c = 'forbidden_text'
        );
        String response = 'This response contains forbidden_text';
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.checkValidityBasedOnAction(response, validation);
        Test.stopTest();
        
        // Then
        Assert.isFalse(result, 'Response should be invalid when it contains forbidden text');
    }
    
    @isTest
    static void testCheckValidityBasedOnAction_CaseInsensitive() {
        // Given
        AI_Prompt_Response_Validation__c includeValidation = new AI_Prompt_Response_Validation__c(
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE,
            Value__c = 'REQUIRED_TEXT'
        );
        AI_Prompt_Response_Validation__c excludeValidation = new AI_Prompt_Response_Validation__c(
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_EXCLUDE,
            Value__c = 'FORBIDDEN_TEXT'
        );
        
        // When
        Test.startTest();
        Boolean includeResult = AIResponseValidationUtility.checkValidityBasedOnAction('This contains required_text', includeValidation);
        Boolean excludeResult = AIResponseValidationUtility.checkValidityBasedOnAction('This contains forbidden_text', excludeValidation);
        Test.stopTest();
        
        // Then
        Assert.isTrue(includeResult, 'Include validation should be case insensitive');
        Assert.isFalse(excludeResult, 'Exclude validation should be case insensitive');
    }
    @isTest
    static void testCheckValidityBasedOnAction_UnknownAction() {
        // Given
        AI_Prompt_Response_Validation__c validation = new AI_Prompt_Response_Validation__c(
            Action__c = 'Unknown_Action',
            Value__c = 'test_value'
        );
        String response = 'Test response';
        
        // When
        Test.startTest();
        Boolean result = AIResponseValidationUtility.checkValidityBasedOnAction(response, validation);
        Test.stopTest();
        
        // Then
        Assert.isTrue(result, 'Unknown action should return true by default');
    }
    
    @isTest
    static void testCheckValidityBasedOnAction_EmptyResponse() {
        // Given
        AI_Prompt_Response_Validation__c includeValidation = new AI_Prompt_Response_Validation__c(
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE,
            Value__c = 'required_text'
        );
        AI_Prompt_Response_Validation__c excludeValidation = new AI_Prompt_Response_Validation__c(
            Action__c = AIConstants.PROMPT_VALIDATION_ACTION_EXCLUDE,
            Value__c = 'forbidden_text'
        );
        
        // When
        Test.startTest();
        Boolean includeResult = AIResponseValidationUtility.checkValidityBasedOnAction('', includeValidation);
        Boolean excludeResult = AIResponseValidationUtility.checkValidityBasedOnAction('', excludeValidation);
        Test.stopTest();
        
        // Then
        Assert.isFalse(includeResult, 'Empty response should fail include validation');
        Assert.isTrue(excludeResult, 'Empty response should pass exclude validation');
    }
}