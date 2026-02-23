/**
 * @description:
 *   Test class for AICanvasCardController to validate AI prompt REST API callouts
 *   and response processing functionality with comprehensive coverage of positive,
 *   negative, and edge case scenarios.
 * 
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 02-06-2025
 * @last modified by  : Piyush Chourasia
 **/
@isTest
private class AICanvasCardControllerTest {
    
    /**
     * @description:
     *   Creates test data for AI Canvas Card Controller tests including AI_Prompt__c,
     *   AI_Response__c, and related records needed for comprehensive testing.
     */
    @TestSetup
    static void createTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account',
            Industry = 'Technology'
        );
        insert testAccount;
        
        // Create test AI Prompt
        AI_Prompt__c testPrompt = new AI_Prompt__c(
            Name = 'Test Canvas Prompt',
            Object__c = 'Account',
            Type__c = 'Canvas',
            Status__c = 'Active',
            Profiles__c = 'System Administrator',
            Auto_Refresh_Duration__c = 30,
            Prompt_Request_Id__c = 'test-prompt-123'
        );
        insert testPrompt;

        // Create test AI Prompt
        AI_Prompt__c testSummary = new AI_Prompt__c(
            Name = 'Test Summary Prompt',
            Object__c = 'AI_Response__c',
            Type__c = 'Text',
            Status__c = 'Active',
            Profiles__c = 'System Administrator',
            Auto_Refresh_Duration__c = 30,
            Prompt_Request_Id__c = 'test-prompt-1234'
        );
        insert testSummary;
        
        // Create test AI Response (parent) with Feedbacks relationship
        AI_Response__c parentResponse = new AI_Response__c(
            Record_Id__c = testAccount.Id,
            AI_Prompt__c = testPrompt.Id,
            Status__c = 'Processed',
            Is_Canvas_Response__c = true,
            AI_Processed_Data_PII_Added__c = 'Test response data',
            Message__c = 'Test message',
            How_it_works__c = 'Test explanation'
        );
        insert parentResponse;
        
        // Create test AI Response (child)
        AI_Response__c childResponse = new AI_Response__c(
            Record_Id__c = testAccount.Id,
            AI_Prompt__c = testPrompt.Id,
            AI_Parent_Response__c = parentResponse.Id,
            Status__c = 'Processed',
            Is_Canvas_Response__c = true,
            AI_Processed_Data_PII_Added__c = 'Child response data'
        );
        insert childResponse;
        
        // Create feedback record to test feedbackType mapping
        AI_Feedback__c feedback = new AI_Feedback__c(
            Security_Audit__c = parentResponse.Id,
            Type__c = 'Dislike',
            User__c = UserInfo.getUserId()
        );
        insert feedback;
        
        AI_Prompt_Element__c pmtElement = new AI_Prompt_Element__c(
             AI_Prompt__c= testSummary.Id,
             AI_Summary_Prompt__c= testSummary.Id,
             AI_Parent_Prompt__c = testSummary.Id,
             Sequence__c = 2
        );
        insert pmtElement;
    }
    
    /**
     * @description:
     *   Tests getPromptResponse method with valid parameters and inheritPromptSecurity false.
     *   Validates successful prompt validation and response retrieval.
     */
    @isTest
    static void testGetPromptResponseSuccess() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Prompt_Element__c pmtElement = [SELECT Id,AI_Prompt__c,AI_Summary_Prompt__c,Sequence__c,Width__c,Icon__c,Height__c,AI_Parent_Prompt__c,Inherit_Prompt_Security__c FROM AI_Prompt_Element__c LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + testPrompt.Id + '"}';
        AICanvasController.PromptElement elmentWrap = new AICanvasController.PromptElement(pmtElement);
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getPromptResponse(
            requestJSON,
            testPrompt.Id,
            testAccount.Id,
            parentResponse.Id,
            false,
            'Account',
            false,
            JSON.serialize(elmentWrap)
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
        Assert.isNotNull(result.Id, 'Response ID should not be null');
        Assert.areEqual('Child response data', result.responseBody, 'Response body should match expected value');
    }
    
    /**
     * @description:
     *   Tests getPromptResponse method with inheritPromptSecurity true.
     *   Validates prompt validation without record-level security checks.
     */
    @isTest
    static void testGetPromptResponseWithInheritSecurity() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Prompt_Element__c pmtElement = [SELECT Id,AI_Prompt__c,AI_Summary_Prompt__c,Sequence__c,Width__c,Icon__c,Height__c,AI_Parent_Prompt__c,Inherit_Prompt_Security__c FROM AI_Prompt_Element__c LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + testPrompt.Id + '"}';
        AICanvasController.PromptElement elmentWrap = new AICanvasController.PromptElement(pmtElement);
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getPromptResponse(
            requestJSON,
            testPrompt.Id,
            testAccount.Id,
            parentResponse.Id,
            false,
            'Account',
            true,
            JSON.serialize(elmentWrap)
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
    }
    
    /**
     * @description:
     *   Tests getPromptResponse method with notInitialLoad true to force new callout.
     *   Validates callout invocation for fresh responses.
     */
    @isTest
    static void testGetPromptResponseNotInitialLoad() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Prompt_Element__c pmtElement = [SELECT Id,AI_Prompt__c,AI_Summary_Prompt__c,Sequence__c,Width__c,Icon__c,Height__c,AI_Parent_Prompt__c,Inherit_Prompt_Security__c FROM AI_Prompt_Element__c LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + testPrompt.Id + '"}';
        AICanvasController.PromptElement elmentWrap = new AICanvasController.PromptElement(pmtElement);
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getPromptResponse(
            requestJSON,
            testPrompt.Id,
            testAccount.Id,
            parentResponse.Id,
            true,
            'Account',
            false,
            JSON.serialize(elmentWrap)
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
    }
    
    /**
     * @description:
     *   Tests getPromptResponse method with invalid prompt ID.
     *   Validates proper error handling for non-existent prompts.
     */
    @isTest
    static void testGetPromptResponseInvalidPrompt() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        AI_Prompt_Element__c pmtElement = [SELECT Id,AI_Prompt__c,AI_Summary_Prompt__c,Sequence__c,Width__c,Icon__c,Height__c,AI_Parent_Prompt__c,Inherit_Prompt_Security__c FROM AI_Prompt_Element__c LIMIT 1];
        
        String invalidPromptId = 'a0000000000000';
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + invalidPromptId + '"}';
        
        AICanvasController.PromptElement elmentWrap = new AICanvasController.PromptElement(pmtElement);
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getPromptResponse(
            requestJSON,
            invalidPromptId,
            testAccount.Id,
            parentResponse.Id,
            false,
            'Account',
            false,
            JSON.serialize(elmentWrap)
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
        Assert.isNotNull(result.message, 'Error message should be present');
        Assert.isTrue(result.message.contains('unavailable'), 'Error message should indicate prompt unavailability');
    }
    
    /**
     * @description:
     *   Tests getPromptResponse method when validation fails with inheritPromptSecurity true.
     *   Validates error message handling for validation failures.
     */
    @isTest
    static void testGetPromptResponseValidationFailureInheritSecurity() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt_Element__c pmtElement = [SELECT Id,AI_Prompt__c,AI_Summary_Prompt__c,Sequence__c,Width__c,Icon__c,Height__c,AI_Parent_Prompt__c,Inherit_Prompt_Security__c FROM AI_Prompt_Element__c LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        
        String invalidPromptId = 'a0000000000000';
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + invalidPromptId + '"}';
        
        AICanvasController.PromptElement elmentWrap = new AICanvasController.PromptElement(pmtElement);
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getPromptResponse(
            requestJSON,
            invalidPromptId,
            testAccount.Id,
            parentResponse.Id,
            false,
            'Account',
            true,
            JSON.serialize(elmentWrap)
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
        Assert.isNotNull(result.message, 'Error message should be present for validation failure');
    }
    
    /**
     * @description:
     *   Tests getPromptResponse method when fetchSecurityAuditByPromptId returns null.
     *   Validates fallback to invokeCallout when no existing response is found.
     */
    @isTest
    static void testGetPromptResponseNoExistingResponse() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt_Element__c pmtElement = [SELECT Id,AI_Prompt__c,AI_Summary_Prompt__c,Sequence__c,Width__c,Icon__c,Height__c,AI_Parent_Prompt__c,Inherit_Prompt_Security__c FROM AI_Prompt_Element__c LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + testPrompt.Id + '"}';
        
        AICanvasController.PromptElement elmentWrap = new AICanvasController.PromptElement(pmtElement);
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getPromptResponse(
            requestJSON,
            testPrompt.Id,
            testAccount.Id,
            'nonexistent-parent-id',
            false,
            'Account',
            false,
            JSON.serialize(elmentWrap)
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null when no existing response found');
    }
    
    /**
     * @description:
     *   Tests getSummaryPromptResponse method with valid parameters and inheritPromptSecurity false.
     *   Validates successful summary prompt validation and response retrieval.
     */
    @isTest
    static void testGetSummaryPromptResponseSuccess() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Test Summary Prompt' LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        AI_Response__c childResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c != null LIMIT 1];
        
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + testPrompt.Id + '"}';
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getSummaryPromptResponse(
            requestJSON,
            testPrompt.Id,
            testAccount.Id,
            parentResponse.Id,
            false,
            'Account',
            false,
            childResponse.Id
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
    }
    
    /**
     * @description:
     *   Tests getSummaryPromptResponse method with inheritPromptSecurity true.
     *   Validates summary prompt validation without record-level security checks.
     */
    @isTest
    static void testGetSummaryPromptResponseWithInheritSecurity() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        AI_Response__c childResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c != null LIMIT 1];
        
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + testPrompt.Id + '"}';
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getSummaryPromptResponse(
            requestJSON,
            testPrompt.Id,
            testAccount.Id,
            parentResponse.Id,
            false,
            'Account',
            true,
            childResponse.Id
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
    }
    
    /**
     * @description:
     *   Tests getSummaryPromptResponse method with notInitialLoad true.
     *   Validates callout invocation for fresh summary responses.
     */
    @isTest
    static void testGetSummaryPromptResponseNotInitialLoad() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        AI_Response__c childResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c != null LIMIT 1];
        
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + testPrompt.Id + '"}';
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getSummaryPromptResponse(
            requestJSON,
            testPrompt.Id,
            testAccount.Id,
            parentResponse.Id,
            true,
            'Account',
            false,
            childResponse.Id
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
    }
    
    /**
     * @description:
     *   Tests getSummaryPromptResponse method with validation failure and inheritPromptSecurity false.
     *   Validates error handling for summary prompt validation failures.
     */
    @isTest
    static void testGetSummaryPromptResponseValidationFailure() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        AI_Response__c childResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c != null LIMIT 1];
        
        String invalidPromptId = 'a0000000000000';
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + invalidPromptId + '"}';
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getSummaryPromptResponse(
            requestJSON,
            invalidPromptId,
            testAccount.Id,
            parentResponse.Id,
            false,
            'Account',
            false,
            childResponse.Id
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
        Assert.isNotNull(result.message, 'Error message should be present for validation failure');
    }
    
    /**
     * @description:
     *   Tests getSummaryPromptResponse method with validation failure and inheritPromptSecurity true.
     *   Validates error handling for summary prompt validation failures with inherited security.
     */
    @isTest
    static void testGetSummaryPromptResponseValidationFailureInheritSecurity() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        AI_Response__c childResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c != null LIMIT 1];
        
        String invalidPromptId = 'a0000000000000';
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + invalidPromptId + '"}';
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getSummaryPromptResponse(
            requestJSON,
            invalidPromptId,
            testAccount.Id,
            parentResponse.Id,
            false,
            'Account',
            true,
            childResponse.Id
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null');
        Assert.isNotNull(result.message, 'Error message should be present for validation failure');
    }
    
    /**
     * @description:
     *   Tests getSummaryPromptResponse method when no existing response is found.
     *   Validates fallback to invokeCallout for summary prompts.
     */
    @isTest
    static void testGetSummaryPromptResponseNoExistingResponse() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        String requestJSON = '{"recordId":"' + testAccount.Id + '","promptId":"' + testPrompt.Id + '"}';
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper result = AICanvasCardController.getSummaryPromptResponse(
            requestJSON,
            testPrompt.Id,
            testAccount.Id,
            'nonexistent-parent-id',
            false,
            'Account',
            false,
            'nonexistent-audit-id'
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Response wrapper should not be null when no existing response found');
    }
    
    /**
     * @description:
     *   Tests ResponseWrapper constructor with AI_Response__c parameter including feedback relationship.
     *   Validates proper field mapping and data conversion with feedback data.
     */
    @isTest
    static void testResponseWrapperWithAIResponse() {
        // Retrieve test data with feedback relationship
        AI_Response__c testResponse = [SELECT Id, Name, AI_Processed_Data_PII_Added__c, Message__c, 
                                      How_it_works__c, Time_Saved_Seconds__c,
                                      (SELECT Type__c FROM Feedbacks__r LIMIT 1)
                                      FROM AI_Response__c 
                                      WHERE AI_Parent_Response__c = null LIMIT 1];
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper wrapper = new AICanvasCardController.ResponseWrapper(testResponse);
        Test.stopTest();
        
        Assert.areEqual(testResponse.Id, wrapper.Id, 'Response ID should match');
        Assert.areEqual(testResponse.Name, wrapper.name, 'Response name should match');
        Assert.areEqual(testResponse.AI_Processed_Data_PII_Added__c, wrapper.responseBody, 'Response body should match');
        Assert.areEqual(testResponse.Message__c, wrapper.message, 'Message should match');
        Assert.areEqual(testResponse.How_it_works__c, wrapper.howItWorks, 'How it works should match');
        Assert.areEqual(testResponse.Time_Saved_Seconds__c, wrapper.timeSaved, 'Time saved should match');
        Assert.areEqual('Dislike', wrapper.feedbackType, 'Feedback type should match');
    }
    
    /**
     * @description:
     *   Tests ResponseWrapper constructor with AI_Response__c parameter without feedback relationship.
     *   Validates proper field mapping when no feedback is present.
     */
    @isTest
    static void testResponseWrapperWithAIResponseNoFeedback() {
        // Retrieve child response without feedback
        AI_Response__c testResponse = [SELECT Id, Name, AI_Processed_Data_PII_Added__c, Message__c, 
                                      How_it_works__c, Time_Saved_Seconds__c,
                                      (SELECT Type__c FROM Feedbacks__r LIMIT 1)
                                      FROM AI_Response__c 
                                      WHERE AI_Parent_Response__c != null LIMIT 1];
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper wrapper = new AICanvasCardController.ResponseWrapper(testResponse);
        Test.stopTest();
        
        Assert.areEqual(testResponse.Id, wrapper.Id, 'Response ID should match');
        Assert.areEqual('', wrapper.feedbackType, 'Feedback type should be empty when no feedback exists');
    }
    
    /**
     * @description:
     *   Tests ResponseWrapper constructor with String message parameter.
     *   Validates proper error message handling.
     */
    @isTest
    static void testResponseWrapperWithMessage() {
        String testMessage = 'Test error message';
        
        Test.startTest();
        AICanvasCardController.ResponseWrapper wrapper = new AICanvasCardController.ResponseWrapper(testMessage);
        Test.stopTest();
        
        Assert.areEqual(testMessage, wrapper.message, 'Error message should match');
        Assert.isNull(wrapper.Id, 'ID should be null for error response');
        Assert.isNull(wrapper.responseBody, 'Response body should be null for error response');
    }
}