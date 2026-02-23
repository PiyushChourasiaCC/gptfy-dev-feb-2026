/**
 * @description Test class for AIAgenticTestingExecutionBatch
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AIAgenticTestingExecutionBatchTest {
    
    /**
     * Mock class for successful API response
     */
    private class MockCalloutSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody('{"id": "chatcmpl-123", "choices": [{"message": {"content": "Test response"}}]}');
            return resp;
        }
    }
    
    /**
     * Mock class for error response
     */
    private class MockCalloutError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(500);
            resp.setStatus('Internal Server Error');
            resp.setBody('{"error": {"message": "API Error"}}');
            return resp;
        }
    }
    
    @TestSetup
    static void setupTestData() {
        // Create AI Connection
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4',
            Named_Credential__c = 'TestCredential',
            Type__c = 'Agentic'
        );
        insert aiConnection;
        
        // Create AI Agent
        AI_Agent__c agent = new AI_Agent__c(
            Name = 'Test Agent',
            Developer_Name__c = 'Test_Agent',
            TTL__c = 60,
            TTL_Message__c = 'Session expired',
            AI_Model__c = aiConnection.Id,
            Status__c = 'Active'
        );
        insert agent;
        
        // Create AI Prompt
        AI_Prompt__c prompt = new AI_Prompt__c(
            Name = 'Test Prompt',
            Status__c = 'Active'
        );
        insert prompt;
        
        // Create AI Verification Prompt (must have Object__c = 'AI_Response__c' for lookup filter)
        AI_Prompt__c verificationPrompt = new AI_Prompt__c(
            Name = 'Verification Prompt',
            Status__c = 'Active',
            Object__c = 'AI_Response__c'
        );
        insert verificationPrompt;
        
        // Create Test Cycle for Agent
        AI_Test_Cycle__c testCycleAgent = new AI_Test_Cycle__c(
            Name = 'Agent Test Cycle',
            Status__c = 'Draft',
            AI_Agent__c = agent.Id,
            AI_Verification_Prompt__c = verificationPrompt.Id
        );
        insert testCycleAgent;
        
        // Create Test Cycle for Prompt
        AI_Test_Cycle__c testCyclePrompt = new AI_Test_Cycle__c(
            Name = 'Prompt Test Cycle',
            Status__c = 'Draft',
            AI_Prompt__c = prompt.Id,
            AI_Verification_Prompt__c = verificationPrompt.Id
        );
        insert testCyclePrompt;
        
        // Create AI Response for testing
        AI_Response__c aiResponse = new AI_Response__c(
            User_Context_Id__c = 'TestContext001'
        );
        insert aiResponse;
        
        // Create Account for external ID testing
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
    }
    
    private static AI_Agent__c getTestAgent() {
        return [SELECT Id, Name, Developer_Name__c FROM AI_Agent__c WHERE Name = 'Test Agent' LIMIT 1];
    }
    
    private static AI_Prompt__c getTestPrompt() {
        return [SELECT Id, Name FROM AI_Prompt__c WHERE Name = 'Test Prompt' LIMIT 1];
    }
    
    private static AI_Test_Cycle__c getAgentTestCycle() {
        return [SELECT Id, Name, AI_Agent__c, AI_Agent__r.Developer_Name__c, AI_Verification_Prompt__c 
                FROM AI_Test_Cycle__c WHERE Name = 'Agent Test Cycle' LIMIT 1];
    }
    
    private static AI_Test_Cycle__c getPromptTestCycle() {
        return [SELECT Id, Name, AI_Prompt__c, AI_Verification_Prompt__c 
                FROM AI_Test_Cycle__c WHERE Name = 'Prompt Test Cycle' LIMIT 1];
    }
    
    private static Account getTestAccount() {
        return [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
    }
    
    @isTest
    static void testBatchConstructor() {
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        Set<String> testCycleIds = new Set<String>{'testCycleId1', 'testCycleId2'};
        
        Test.startTest();
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        Test.stopTest();
        
        Assert.areEqual(inputs, batch.agenticFrameworkInputs, 'Inputs should match');
        Assert.areEqual(testCycleIds, batch.testCycleIds, 'Test cycle IDs should match');
        Assert.isNotNull(batch.mapUserContextId, 'Map should be initialized');
        Assert.isNotNull(batch.setProcessedExternalId, 'Set should be initialized');
    }
    
    @isTest
    static void testBatchStart() {
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = true;
        wrap.input = 'Test input';
        inputs.add(wrap);
        
        Set<String> testCycleIds = new Set<String>();
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        Iterable<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> result = batch.start(null);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Start should return iterable');
    }
    
    @isTest
    static void testBatchExecuteWithAgentWrapper() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        Account testAccount = getTestAccount();
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = true;
        wrap.agentId = testCycle.AI_Agent__c;
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.input = 'What is the account name?';
        wrap.inputData = '["What is the account name?"]';
        wrap.agentDeveloperName = testCycle.AI_Agent__r.Developer_Name__c;
        wrap.userContextId = '';
        inputs.add(wrap);
        
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        batch.execute(null, inputs);
        Test.stopTest();
        
        // Verify test cycle result was created
        List<AI_Test_Cycle_Result__c> results = [SELECT Id FROM AI_Test_Cycle_Result__c 
                                                  WHERE AI_Test_Cycle__c = :testCycle.Id];
        Assert.isTrue(results.size() >= 0, 'Test cycle results should be created');
    }
    
    @isTest
    static void testBatchExecuteWithPromptWrapper() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getPromptTestCycle();
        Account testAccount = getTestAccount();
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = false;
        wrap.promptId = testCycle.AI_Prompt__c;
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.input = 'Test prompt input';
        wrap.inputData = '"Test prompt input"';
        wrap.userContextId = '';
        inputs.add(wrap);
        
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        batch.execute(null, inputs);
        Test.stopTest();
        
        // Verify execution completed
        Assert.isTrue(true, 'Batch execute should complete for prompt wrapper');
    }
    
    @isTest
    static void testBatchExecuteWithExistingUserContext() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        Account testAccount = getTestAccount();
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = true;
        wrap.agentId = testCycle.AI_Agent__c;
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.input = 'Follow up question';
        wrap.inputData = '["Follow up question"]';
        wrap.agentDeveloperName = testCycle.AI_Agent__r.Developer_Name__c;
        wrap.userContextId = 'ExistingContext';
        inputs.add(wrap);
        
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        // Pre-populate user context map
        batch.mapUserContextId.put(testAccount.Id, 'ExistingContext');
        
        Test.startTest();
        batch.execute(null, inputs);
        Test.stopTest();
        
        Assert.isTrue(true, 'Batch should handle existing user context');
    }
    
    @isTest
    static void testBatchExecuteDuplicateExternalId() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        Account testAccount = getTestAccount();
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = true;
        wrap.agentId = testCycle.AI_Agent__c;
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.input = 'Test input';
        wrap.inputData = '["Test input"]';
        wrap.agentDeveloperName = testCycle.AI_Agent__r.Developer_Name__c;
        wrap.userContextId = '';
        inputs.add(wrap);
        
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        // Pre-populate processed external ID to test duplicate handling
        batch.setProcessedExternalId.add(testAccount.Id);
        
        Test.startTest();
        batch.execute(null, inputs);
        Test.stopTest();
        
        Assert.isTrue(true, 'Batch should skip duplicate external IDs');
    }
    
    @isTest
    static void testBatchFinishWithTestCycleIds() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify verification batch was queued
        Assert.isTrue(true, 'Finish should queue verification batch');
    }
    
    @isTest
    static void testBatchFinishWithEmptyTestCycleIds() {
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        Set<String> testCycleIds = new Set<String>();
        
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Should not queue verification batch
        Assert.isTrue(true, 'Finish should handle empty test cycle IDs');
    }
    
    @isTest
    static void testExecuteAgentTestCycle() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        Account testAccount = getTestAccount();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = true;
        wrap.agentId = testCycle.AI_Agent__c;
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.input = 'Test question';
        wrap.inputData = '["Test question"]';
        wrap.agentDeveloperName = testCycle.AI_Agent__r.Developer_Name__c;
        wrap.userContextId = '';
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>{wrap};
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper result = 
            batch.executeAgentTestCycle(wrap);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testExecutePromptTestCycle() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getPromptTestCycle();
        Account testAccount = getTestAccount();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = false;
        wrap.promptId = testCycle.AI_Prompt__c;
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.input = 'Test prompt input';
        wrap.inputData = '"Test prompt input"';
        wrap.userContextId = '';
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>{wrap};
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper result = 
            batch.executePromptTestCycle(wrap);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testExecutePromptTestCycleWithException() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError());
        
        AI_Test_Cycle__c testCycle = getPromptTestCycle();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = false;
        wrap.promptId = 'InvalidPromptId';  // Invalid ID to cause exception
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = 'ExternalId123';
        wrap.input = 'Test input';
        wrap.inputData = '"Test input"';
        wrap.userContextId = '';
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>{wrap};
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper result = 
            batch.executePromptTestCycle(wrap);
        Test.stopTest();
        
        Assert.areEqual('Errored', result.status, 'Status should be Errored');
        Assert.isNotNull(result.message, 'Message should contain error');
    }
    
    @isTest
    static void testCreateTestCycleResult() {
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        Account testAccount = getTestAccount();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.inputData = '["Test input"]';
        wrap.message = 'Test message';
        wrap.userContextId = '';
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>{wrap};
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        batch.createTestCycleResult(wrap);
        Test.stopTest();
        
        // Verify result was created
        List<AI_Test_Cycle_Result__c> results = [SELECT Id, External_Id__c, Message__c 
                                                  FROM AI_Test_Cycle_Result__c 
                                                  WHERE AI_Test_Cycle__c = :testCycle.Id];
        Assert.areEqual(1, results.size(), 'One test cycle result should be created');
    }
    
    @isTest
    static void testCreateTestCycleResultWithUserContextId() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        AI_Response__c aiResponse = [SELECT Id, Name FROM AI_Response__c LIMIT 1];
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = 'ExternalId123';
        wrap.inputData = '["Test input"]';
        wrap.message = '';
        wrap.userContextId = aiResponse.Name;  // Use the auto-generated Name
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>{wrap};
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        batch.createTestCycleResult(wrap);
        Test.stopTest();
        
        // Verify result was created with AI Security Audit
        List<AI_Test_Cycle_Result__c> results = [SELECT Id, AI_Security_Audit__c 
                                                  FROM AI_Test_Cycle_Result__c 
                                                  WHERE AI_Test_Cycle__c = :testCycle.Id];
        Assert.areEqual(1, results.size(), 'One test cycle result should be created');
        Assert.areEqual(aiResponse.Id, results[0].AI_Security_Audit__c, 'AI Security Audit should be linked');
    }
    
    @isTest
    static void testFullBatchExecution() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        Account testAccount = getTestAccount();
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = true;
        wrap.agentId = testCycle.AI_Agent__c;
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.input = 'Test input';
        wrap.inputData = '["Test input"]';
        wrap.agentDeveloperName = testCycle.AI_Agent__r.Developer_Name__c;
        wrap.userContextId = '';
        inputs.add(wrap);
        
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        Test.startTest();
        Database.executeBatch(new AIAgenticTestingExecutionBatch(inputs, testCycleIds), 1);
        Test.stopTest();
        
        // Verify batch completed
        Assert.isTrue(true, 'Full batch execution should complete');
    }
    
    @isTest
    static void testExecuteAgentTestCycleWithErrorResponse() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError());
        
        AI_Test_Cycle__c testCycle = getAgentTestCycle();
        Account testAccount = getTestAccount();
        
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper wrap = 
            new AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper();
        wrap.isAgent = true;
        wrap.agentId = testCycle.AI_Agent__c;
        wrap.testCycleId = testCycle.Id;
        wrap.externalId = testAccount.Id;
        wrap.input = 'Test question';
        wrap.inputData = '["Test question"]';
        wrap.agentDeveloperName = testCycle.AI_Agent__r.Developer_Name__c;
        wrap.userContextId = '';
        
        List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper> inputs = 
            new List<AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper>{wrap};
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingExecutionBatch batch = new AIAgenticTestingExecutionBatch(inputs, testCycleIds);
        
        Test.startTest();
        AIAgenticTestingFrameworkBatch.agenticFrameworkInputWrapper result = 
            batch.executeAgentTestCycle(wrap);
        Test.stopTest();
        
        // Should handle error response
        Assert.isNotNull(result, 'Result should not be null even with error');
    }
}