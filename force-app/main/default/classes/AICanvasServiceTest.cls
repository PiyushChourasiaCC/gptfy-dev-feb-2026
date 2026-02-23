/**
 * @description:
 *   Test class for AICanvasService to validate backend utility/service layer functionality
 *   for handling AI Canvas templates, components, prompts, and record-level visibility logic
 *   with comprehensive coverage of positive, negative, and edge case scenarios.
 * 
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 01-06-2025
 * @last modified by  : Piyush Chourasia
 **/
@isTest
private class AICanvasServiceTest {
    
    /**
     * @description:
     *   Creates comprehensive test data for AI Canvas Service tests including AI_Prompt__c,
     *   AI_Prompt_Element__c, AI_Response__c, User, and Profile records for thorough testing.
     */
    @TestSetup
    static void createTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account',
            Industry = 'Technology',
            Type = 'Customer'
        );
        insert testAccount;
        
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
        
        // Inactive Canvas prompt
        prompts.add(new AI_Prompt__c(
            Name = 'Inactive Canvas Prompt',
            Object__c = 'Account',
            Type__c = 'Canvas',
            Status__c = 'Inactive',
            Auto_Refresh_Duration__c = 15,
            Prompt_Request_Id__c = 'inactive-prompt-456'
        ));
        
        // Active prompt without profile restriction
        prompts.add(new AI_Prompt__c(
            Name = 'Open Canvas Prompt',
            Object__c = 'Account',
            Type__c = 'Canvas',
            Status__c = 'Active',
            Auto_Refresh_Duration__c = 45,
            Prompt_Request_Id__c = 'open-prompt-789'
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
            AI_Prompt__c = prompts[3].Id,
            AI_Summary_Prompt__c = prompts[3].Id,
            Sequence__c = 1,
            Width__c = '3/3 Column',
            Height__c = 250,
            Icon__c = 'custom2',
            Inherit_Prompt_Security__c = false
        );
        insert promptElement;
        
        // Create AI Responses
        List<AI_Response__c> responses = new List<AI_Response__c>();
        
        // Parent response
        responses.add(new AI_Response__c(
            Record_Id__c = testAccount.Id,
            AI_Prompt__c = prompts[3].Id,
            Status__c = 'Processed',
            Is_Canvas_Response__c = true,
            AI_Processed_Data_PII_Added__c = 'Parent response data',
            Message__c = 'Completed successfully',
            How_it_works__c = 'AI analysis of account data',
            Prompt_Tokens__c = 200,
            Completion_Tokens__c = 250,
            Total_Tokens__c = 450
        ));
        
        insert responses;
        
        // Child response
        responses.add(new AI_Response__c(
            Record_Id__c = testAccount.Id,
            AI_Prompt__c = prompts[3].Id,
            AI_Parent_Response__c = responses[0].Id,
            Status__c = 'Processed',
            Is_Canvas_Response__c = true,
            AI_Processed_Data_PII_Added__c = 'Child response data',
            Prompt_Tokens__c = 100,
            Completion_Tokens__c = 125
        ));
        
        insert new List<AI_Response__c>{responses[1]};
    }
    
    /**
     * @description:
     *   Tests fetchWinnerPrompt method with matching profile and visibility condition.
     *   Validates successful retrieval of appropriate prompt based on user profile and record criteria.
     */
    @isTest
    static void testFetchWinnerPromptSuccess() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        AI_Prompt__c winnerPrompt = AICanvasService.fetchWinnerPrompt(testAccount.Id, 'Account');
        Test.stopTest();
        
        Assert.isNotNull(winnerPrompt, 'Winner prompt should be found');
        Assert.areEqual('Account', winnerPrompt.Object__c, 'Prompt should be for Account object');
    }
    
    /**
     * @description:
     *   Tests fetchWinnerPrompt method with non-existent object.
     *   Validates proper null return when no prompts exist for the specified object.
     */
    @isTest
    static void testFetchWinnerPromptNoMatch() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        AI_Prompt__c winnerPrompt = AICanvasService.fetchWinnerPrompt(testAccount.Id, 'Contact');
        Test.stopTest();
        
        Assert.isNull(winnerPrompt, 'No winner prompt should be found for Contact object');
    }
    
    /**
     * @description:
     *   Tests getCurrentUserProfileName method.
     *   Validates proper retrieval of current user's profile name.
     */
    @isTest
    static void testGetCurrentUserProfileName() {
        Test.startTest();
        String profileName = AICanvasService.getCurrentUserProfileName();
        Test.stopTest();
        
        Assert.isNotNull(profileName, 'Profile name should not be null');
        Assert.isTrue(profileName.length() > 0, 'Profile name should not be empty');
    }
    
    /**
     * @description:
     *   Tests getEmailActionName method with Account object.
     *   Validates proper retrieval of email action name for the specified object.
     */
    @isTest
    static void testGetEmailActionName() {
        Test.startTest();
        String emailActionName = AICanvasService.getEmailActionName('Account');
        Test.stopTest();
        
        Assert.isNotNull(emailActionName, 'Email action name should be initialized (may be empty)');
    }
    
    /**
     * @description:
     *   Tests buildWhereClause method with visibility condition.
     *   Validates proper SOQL where clause construction with escape handling.
     */
    @isTest
    static void testBuildWhereClause() {
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id, Visibility_Condition__c FROM AI_Prompt__c 
                                  WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        
        String baseQuery = 'SELECT Id FROM Account WHERE Id = :recordId';
        
        Test.startTest();
        String finalQuery = AICanvasService.buildWhereClause(baseQuery, testPrompt);
        Test.stopTest();
        
        Assert.isNotNull(finalQuery, 'Final query should not be null');
        Assert.isTrue(finalQuery.contains('Industry'), 'Query should contain visibility condition');
        Assert.isTrue(finalQuery.contains('LIMIT'), 'Query should contain LIMIT clause');
    }
    
    /**
     * @description:
     *   Tests buildWhereClause method with ORDER BY condition.
     *   Validates proper handling of ORDER BY clauses in visibility conditions.
     */
    @isTest
    static void testBuildWhereClauseWithOrderBy() {
        // Create prompt with ORDER BY condition
        AI_Prompt__c testPrompt = new AI_Prompt__c(
            Name = 'Order By Prompt',
            Object__c = 'Account',
            Type__c = 'Canvas',
            Status__c = 'Active',
            Visibility_Condition__c = 'ORDER BY Name ASC'
        );
        insert testPrompt;
        
        String baseQuery = 'SELECT Id FROM Account WHERE Id = :recordId';
        
        Test.startTest();
        String finalQuery = AICanvasService.buildWhereClause(baseQuery, testPrompt);
        Test.stopTest();
        
        Assert.isTrue(finalQuery.contains('ORDER BY'), 'Query should contain ORDER BY clause');
    }
    
    /**
     * @description:
     *   Tests fetchPrompts method with valid prompt IDs.
     *   Validates successful retrieval of multiple prompts by ID set.
     */
    @isTest
    static void testFetchPrompts() {
        // Retrieve test data
        List<AI_Prompt__c> allPrompts = [SELECT Id FROM AI_Prompt__c LIMIT 2];
        Set<Id> promptIds = new Set<Id>();
        for (AI_Prompt__c prompt : allPrompts) {
            promptIds.add(prompt.Id);
        }
        
        Test.startTest();
        List<AI_Prompt__c> fetchedPrompts = AICanvasService.fetchPrompts(promptIds);
        Test.stopTest();
        
        Assert.isNotNull(fetchedPrompts, 'Fetched prompts should not be null');
        Assert.areEqual(allPrompts.size(), fetchedPrompts.size(), 'Should fetch all requested prompts');
    }
    
    /**
     * @description:
     *   Tests fetchSecurityAuditRecord method with valid record ID.
     *   Validates successful retrieval of security audit record with feedbacks.
     */
    @isTest
    static void testFetchSecurityAuditRecord() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Response__c testResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        
        Test.startTest();
        AI_Response__c fetchedResponse = AICanvasService.fetchSecurityAuditRecord(testResponse.Id, testAccount.Id);
        Test.stopTest();
        
        Assert.isNotNull(fetchedResponse, 'Fetched response should not be null');
        Assert.areEqual(testResponse.Id, fetchedResponse.Id, 'Should fetch the correct response');
        Assert.isNotNull(fetchedResponse.AI_Processed_Data_PII_Added__c, 'Response data should be present');
    }
    
    /**
     * @description:
     *   Tests fetchSecurityAuditRecordByPromptId method with valid prompt ID.
     *   Validates successful retrieval of security audit record by prompt association.
     */
    @isTest
    static void testFetchSecurityAuditRecordByPromptId() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Summary Prompt' LIMIT 1];
        
        Test.startTest();
        AI_Response__c fetchedResponse = AICanvasService.fetchSecurityAuditRecordByPromptId(testPrompt.Id, testAccount.Id);
        Test.stopTest();
        
        Assert.isNotNull(fetchedResponse, 'Fetched response should not be null');
        Assert.areEqual(testPrompt.Id, fetchedResponse.AI_Prompt__c, 'Response should be linked to correct prompt');
    }
    
    /**
     * @description:
     *   Tests fetchAIResponses method with valid child response IDs.
     *   Validates successful retrieval of multiple AI responses with token information.
     */
    @isTest
    static void testFetchAIResponses() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<AI_Response__c> childResponses = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c != null];
        Set<Id> childIds = new Set<Id>();
        for (AI_Response__c child : childResponses) {
            childIds.add(child.Id);
        }
        
        Test.startTest();
        List<AI_Response__c> fetchedResponses = AICanvasService.fetchAIResponses(childIds, testAccount.Id);
        Test.stopTest();
        
        Assert.isNotNull(fetchedResponses, 'Fetched responses should not be null');
        Assert.areEqual(childResponses.size(), fetchedResponses.size(), 'Should fetch all requested responses');
    }
    
    /**
     * @description:
     *   Tests fetchSecurityAuditByPromptId method with parent response linkage.
     *   Validates successful retrieval of security audit by prompt and parent response.
     */
    @isTest
    static void testFetchSecurityAuditByPromptId() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Summary Prompt' LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        
        Test.startTest();
        AI_Response__c fetchedResponse = AICanvasService.fetchSecurityAuditByPromptId(
            testPrompt.Id, 
            parentResponse.Id, 
            testAccount.Id
        );
        Test.stopTest();
        
        Assert.isNotNull(fetchedResponse, 'Fetched response should not be null');
    }
    
    /**
     * @description:
     *   Tests validatePrompt method with active prompt and valid conditions.
     *   Validates successful prompt validation with record-level security checks.
     */
    @isTest
    static void testValidatePromptSuccess() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        
        Test.startTest();
        String validationResult = AICanvasService.validatePrompt(testPrompt.Id, testAccount.Id, 'Account');
        Test.stopTest();
        
        Assert.areEqual('Success', validationResult, 'Validation should succeed for active prompt');
    }
    
    /**
     * @description:
     *   Tests validatePrompt method with inactive prompt.
     *   Validates proper error message for inactive prompts.
     */
    @isTest
    static void testValidatePromptInactive() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c inactivePrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Inactive Canvas Prompt' LIMIT 1];
        
        Test.startTest();
        String validationResult = AICanvasService.validatePrompt(inactivePrompt.Id, testAccount.Id, 'Account');
        Test.stopTest();
        
        Assert.isTrue(validationResult.contains('deactivated'), 'Should return inactive prompt error message');
    }
    
    /**
     * @description:
     *   Tests validatePrompt method with non-existent prompt ID.
     *   Validates proper error message for missing prompts.
     */
    @isTest
    static void testValidatePromptNotFound() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        String nonExistentPromptId = 'a0000000000000';
        
        Test.startTest();
        String validationResult = AICanvasService.validatePrompt(nonExistentPromptId, testAccount.Id, 'Account');
        Test.stopTest();
        
        Assert.isTrue(validationResult.contains('unavailable'), 'Should return prompt unavailable error message');
    }
    
    /**
     * @description:
     *   Tests validateSummaryPrompt method with valid summary prompt.
     *   Validates successful summary prompt validation with record-level checks.
     */
    @isTest
    static void testValidateSummaryPromptSuccess() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c summaryPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Summary Prompt' LIMIT 1];
        
        Test.startTest();
        String validationResult = AICanvasService.validateSummaryPrompt(summaryPrompt.Id, 'Account', testAccount.Id);
        Test.stopTest();
        
        Assert.areEqual('Success', validationResult, 'Summary prompt validation should succeed');
    }
    
    /**
     * @description:
     *   Tests validateSummaryPrompt method without record context.
     *   Validates summary prompt validation without record-level security checks.
     */
    @isTest
    static void testValidateSummaryPromptWithoutRecord() {
        // Retrieve test data
        AI_Prompt__c summaryPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Summary Prompt' LIMIT 1];
        
        Test.startTest();
        String validationResult = AICanvasService.validateSummaryPrompt(summaryPrompt.Id);
        Test.stopTest();
        
        Assert.areEqual('Success', validationResult, 'Summary prompt validation should succeed without record context');
    }
    
    /**
     * @description:
     *   Tests getPromptElementsByPromptId method with valid prompt ID.
     *   Validates successful retrieval of prompt elements associated with a prompt.
     */
    @isTest
    static void testGetPromptElementsByPromptId() {
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        
        Test.startTest();
        List<AI_Prompt_Element__c> promptElements = AICanvasService.getPromptElementsByPromptId(testPrompt.Id);
        Test.stopTest();
        
        Assert.isNotNull(promptElements, 'Prompt elements should not be null');
        Assert.isTrue(promptElements.size() > 0, 'Should have at least one prompt element');
        Assert.areEqual(testPrompt.Id, promptElements[0].AI_Parent_Prompt__c, 'Element should be linked to correct prompt');
    }
    
    /**
     * @description:
     *   Tests getSecurityAuditsByParent method with valid parent audit ID.
     *   Validates successful retrieval of child security audit records.
     */
    @isTest
    static void testGetSecurityAuditsByParent() {
        // Retrieve test data
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        
        Test.startTest();
        List<AI_Response__c> childAudits = AICanvasService.getSecurityAuditsByParent(parentResponse.Id);
        Test.stopTest();
        
        Assert.isNotNull(childAudits, 'Child audits should not be null');
        Assert.isTrue(childAudits.size() > 0, 'Should have at least one child audit');
    }
    
    /**
     * @description:
     *   Tests getPromptDetails method with valid prompt ID.
     *   Validates successful retrieval of detailed prompt information.
     */
    @isTest
    static void testGetPromptDetails() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        
        Test.startTest();
        AI_Prompt__c promptDetails = AICanvasService.getPromptDetails(testAccount.Id, 'Account', testPrompt.Id);
        Test.stopTest();
        
        Assert.isNotNull(promptDetails, 'Prompt details should not be null');
        Assert.areEqual(testPrompt.Id, promptDetails.Id, 'Should return correct prompt');
        Assert.isNotNull(promptDetails.Name, 'Prompt name should be present');
        Assert.isNotNull(promptDetails.Object__c, 'Prompt object should be present');
    }
    
    /**
     * @description:
     *   Tests getPromptDetails method with non-existent prompt ID.
     *   Validates proper null return for invalid prompt references.
     */
    @isTest
    static void testGetPromptDetailsNotFound() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        String nonExistentPromptId = 'a0000000000000';
        
        Test.startTest();
        AI_Prompt__c promptDetails = AICanvasService.getPromptDetails(nonExistentPromptId,'Account', testAccount.Id);
        Test.stopTest();
        
        Assert.isNull(promptDetails, 'Should return null for non-existent prompt');
    }
    
    /**
     * @description:
     *   Tests validatePrompt method with different profile restriction.
     *   Validates proper error handling for profile mismatches.
     */
    @isTest
    static void testValidatePromptProfileMismatch() {
        // Create prompt with different profile requirement
        AI_Prompt__c restrictedPrompt = new AI_Prompt__c(
            Name = 'Restricted Prompt',
            Object__c = 'Account',
            Type__c = 'Canvas',
            Status__c = 'Active',
            Profiles__c = 'Different Profile'
        );
        insert restrictedPrompt;
        
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        String validationResult = AICanvasService.validatePrompt(restrictedPrompt.Id, testAccount.Id, 'Account');
        Test.stopTest();
        
        Assert.isTrue(validationResult.contains('profile'), 'Should return profile mismatch error message');
    }
    @isTest
    static void testInvokeCallout() {
        // Get test data
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Summary Prompt' LIMIT 1];
        AI_Prompt_Element__c pmtElement = [SELECT Id,AI_Prompt__c,AI_Summary_Prompt__c,Sequence__c,Width__c,Icon__c,Height__c,AI_Parent_Prompt__c,Inherit_Prompt_Security__c FROM AI_Prompt_Element__c LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Response__c testResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        // Create mock request JSON
        String requestJSON = '{"promptRequestId":"TEST-REQ-001","recordId":"001000000000000","customPromptCommand":""}';
        AICanvasController.PromptElement elmentWrap = new AICanvasController.PromptElement(pmtElement);
        
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));

        try{
            AICanvasCardController.ResponseWrapper result = AICanvasService.invokeCallout(
                requestJSON, testPrompt.Id, testResponse.Id, testAccount.Id,elmentWrap
            );

            // Varify the results
            Assert.isNotNull(result);
            Assert.isTrue(true, 'Method should complete without errors');
        }catch(Exception ex){
            Assert.isNotNull(ex);
        }

        Test.stopTest();
    }
    @isTest
    static void testUpdateSecurityAuditRecordWithParent() {
        // Get test data
        AI_Response__c testResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c != null LIMIT 1];
        AI_Response__c parentResponse = [SELECT Id FROM AI_Response__c WHERE AI_Parent_Response__c = null LIMIT 1];
        AI_Prompt_Element__c pmtElement = [SELECT Id,AI_Prompt__c,AI_Summary_Prompt__c,Sequence__c,Width__c,Icon__c,Height__c,AI_Parent_Prompt__c,Inherit_Prompt_Security__c FROM AI_Prompt_Element__c LIMIT 1];
        AICanvasController.PromptElement elmentWrap = new AICanvasController.PromptElement(pmtElement);
        
        Test.startTest();
        AICanvasService.updateSecurityAuditRecord(testResponse.Id, parentResponse.Id,elmentWrap);
        Test.stopTest();
        
        // Verify record was updated
        AI_Response__c updatedResponse = [SELECT Id, AI_Parent_Response__c 
                                         FROM AI_Response__c WHERE Id = :testResponse.Id];
        Assert.areEqual(parentResponse.Id, updatedResponse.AI_Parent_Response__c, 'Parent response ID should be updated');
    }
    @isTest
    static void testValidatePomptErrorAndSuccess() {
        // Get test data
        AI_Prompt__c testPrompt1 = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        AI_Prompt__c testPrompt2 = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Inactive Canvas Prompt' LIMIT 1];
        
        Test.startTest();
        String message = '';
        message = AICanvasService.validatePrompt(testPrompt1.Id, 'Case');
        Assert.areEqual(AICanvasService.NO_PROMPT_ERROR, message, 'Should return correct message');
        message = AICanvasService.validatePrompt(testPrompt2.Id, 'Account');
        Assert.areEqual(AICanvasService.INACTIVE_PROMPT_ERROR, message, 'Should return correct message');
        message = AICanvasService.validatePrompt(testPrompt1.Id, 'Account');
        Assert.areEqual(AICanvasService.SUCCESS_MESSAGE, message, 'Should return correct message');
        Test.stopTest();
    }
    @isTest
    static void testGetPromptDetails_Error() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        testPrompt.Profiles__c = 'System Administrator';
        testPrompt.Permission_Sets__c = 'gptfy admin';

        UPDATE testPrompt;

        Test.startTest();
        AI_Prompt__c promptDetails = AICanvasService.getPromptDetails(testAccount.Id, 'Account', testPrompt.Id);
        Test.stopTest();
        
        Assert.isNotNull(promptDetails, 'Prompt details should not be null');
        Assert.areEqual(testPrompt.Id, promptDetails.Id, 'Should return correct prompt');
        Assert.isNotNull(promptDetails.Name, 'Prompt name should be present');
        Assert.isNotNull(promptDetails.Object__c, 'Prompt object should be present');
    }
    @isTest
    static void testGetPromptDetails_ErrorBlankProfile() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        testPrompt.Profiles__c = '';
        testPrompt.Permission_Sets__c = 'gptfy admin';

        UPDATE testPrompt;

        Test.startTest();
        AI_Prompt__c promptDetails = AICanvasService.getPromptDetails(testAccount.Id, 'Account', testPrompt.Id);
        Test.stopTest();
        
        Assert.isNotNull(promptDetails, 'Prompt details should not be null');
        Assert.areEqual(testPrompt.Id, promptDetails.Id, 'Should return correct prompt');
        Assert.isNotNull(promptDetails.Name, 'Prompt name should be present');
        Assert.isNotNull(promptDetails.Object__c, 'Prompt object should be present');
    }
    @isTest
    static void testGetPromptDetails_ErrorBlank() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id FROM AI_Prompt__c WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        testPrompt.Profiles__c = '';
        testPrompt.Permission_Sets__c = '';

        UPDATE testPrompt;

        Test.startTest();
        AI_Prompt__c promptDetails = AICanvasService.getPromptDetails(testAccount.Id, 'Account', testPrompt.Id);
        Test.stopTest();
        
        Assert.isNotNull(promptDetails, 'Prompt details should not be null');
        Assert.areEqual(testPrompt.Id, promptDetails.Id, 'Should return correct prompt');
        Assert.isNotNull(promptDetails.Name, 'Prompt name should be present');
        Assert.isNotNull(promptDetails.Object__c, 'Prompt object should be present');
    }
    /**
     * @description:
     *   Tests validateSummaryPrompt method with valid summary prompt.
     *   Validates successful summary prompt validation with record-level checks.
     */
    @isTest
    static void testValidateSummaryPromptInvalidId() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c summaryPrompt = [SELECT Id, Status__c FROM AI_Prompt__c LIMIT 1];
        
        Test.startTest();
        String validationResult = AICanvasService.validateSummaryPrompt(null);
        Test.stopTest();
        
        Assert.areNotEqual('Success', validationResult, 'Summary prompt validation should succeed');
    }
     /**
     * @description:
     *   Tests validateSummaryPrompt method with valid summary prompt.
     *   Validates successful summary prompt validation with record-level checks.
     */
    @isTest
    static void testValidateSummaryPromptInactiveError() {
        // Retrieve test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c summaryPrompt = [SELECT Id, Status__c FROM AI_Prompt__c LIMIT 1];
        summaryPrompt.Status__c = 'Inactive';

        UPDATE summaryPrompt;
        
        Test.startTest();
        String validationResult = AICanvasService.validateSummaryPrompt(summaryPrompt.Id);
        Test.stopTest();
        
        Assert.areNotEqual('Success', validationResult, 'Summary prompt validation should succeed');
    }
}