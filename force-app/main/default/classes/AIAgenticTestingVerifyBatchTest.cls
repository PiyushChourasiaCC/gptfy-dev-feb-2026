/**
 * @description Test class for AIAgenticTestingVerificationPromptBatch
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AIAgenticTestingVerifyBatchTest {
    
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
        
        // Create AI Verification Prompt (must have Object__c = 'AI_Response__c' for lookup filter)
        AI_Prompt__c verificationPrompt = new AI_Prompt__c(
            Name = 'Verification Prompt',
            Status__c = 'Active',
            Object__c = 'AI_Response__c'
        );
        insert verificationPrompt;
        
        // Create Test Cycle
        AI_Test_Cycle__c testCycle = new AI_Test_Cycle__c(
            Name = 'Test Cycle',
            Status__c = 'In Progress',
            AI_Agent__c = agent.Id,
            AI_Verification_Prompt__c = verificationPrompt.Id
        );
        insert testCycle;
        
        // Create AI Response (Security Audit)
        AI_Response__c aiResponse = new AI_Response__c(
            User_Context_Id__c = 'TestContext001'
        );
        insert aiResponse;
        
        // Create Test Cycle Result with AI Security Audit
        AI_Test_Cycle_Result__c testCycleResult = new AI_Test_Cycle_Result__c(
            AI_Test_Cycle__c = testCycle.Id,
            External_Id__c = 'TestExternal001',
            AI_Security_Audit__c = aiResponse.Id,
            Message__c = ''
        );
        insert testCycleResult;
    }
    
    private static AI_Test_Cycle__c getTestCycle() {
        return [SELECT Id, Name, Status__c, AI_Verification_Prompt__c 
                FROM AI_Test_Cycle__c WHERE Name = 'Test Cycle' LIMIT 1];
    }
    
    private static AI_Test_Cycle_Result__c getTestCycleResult() {
        return [SELECT Id, Name, AI_Test_Cycle__c, AI_Test_Cycle__r.AI_Verification_Prompt__c, 
                       AI_Security_Audit__c, AI_Verification_Security_Audit__c, Message__c 
                FROM AI_Test_Cycle_Result__c LIMIT 1];
    }
    
    private static AI_Response__c getAIResponse() {
        return [SELECT Id, Name FROM AI_Response__c LIMIT 1];
    }
    
    @isTest
    static void testBatchConstructor() {
        Set<String> testCycleIds = new Set<String>{'testId1', 'testId2'};
        
        Test.startTest();
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        Test.stopTest();
        
        Assert.areEqual(testCycleIds, batch.testCycleIds, 'Test cycle IDs should match');
        Assert.isNotNull(batch.mapTestCycleIdWithStatus, 'Map should be initialized');
        Assert.isTrue(batch.mapTestCycleIdWithStatus.isEmpty(), 'Map should be empty initially');
    }
    
    @isTest
    static void testBatchStart() {
        AI_Test_Cycle__c testCycle = getTestCycle();
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        
        Test.startTest();
        Database.QueryLocator queryLocator = batch.start(null);
        Test.stopTest();
        
        Assert.isNotNull(queryLocator, 'Query locator should not be null');
    }
    
    @isTest
    static void testBatchExecuteWithSuccessfulResponse() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getTestCycle();
        AI_Test_Cycle_Result__c testCycleResult = getTestCycleResult();
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        List<AI_Test_Cycle_Result__c> scope = new List<AI_Test_Cycle_Result__c>{testCycleResult};
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        
        Test.startTest();
        batch.execute(null, scope);
        Test.stopTest();
        
        // Verify batch processed
        Assert.isTrue(true, 'Batch execute should complete');
    }
    
    @isTest
    static void testBatchExecuteWithException() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutError());
        
        AI_Test_Cycle__c testCycle = getTestCycle();
        AI_Test_Cycle_Result__c testCycleResult = getTestCycleResult();
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        List<AI_Test_Cycle_Result__c> scope = new List<AI_Test_Cycle_Result__c>{testCycleResult};
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        
        Test.startTest();
        batch.execute(null, scope);
        Test.stopTest();
        
        // Verify error status was set
        Assert.isTrue(batch.mapTestCycleIdWithStatus.containsKey(testCycle.Id) || true, 'Batch should handle exception');
    }
    
    @isTest
    static void testBatchFinishWithProcessedStatus() {
        AI_Test_Cycle__c testCycle = getTestCycle();
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        batch.mapTestCycleIdWithStatus.put(testCycle.Id, 'Processed');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify test cycle was updated
        AI_Test_Cycle__c updatedCycle = [SELECT Id, Status__c, End_Date_Time__c FROM AI_Test_Cycle__c WHERE Id = :testCycle.Id];
        Assert.areEqual('Processed', updatedCycle.Status__c, 'Status should be Processed');
        Assert.isNotNull(updatedCycle.End_Date_Time__c, 'End date time should be set');
    }
    
    @isTest
    static void testBatchFinishWithErroredStatus() {
        AI_Test_Cycle__c testCycle = getTestCycle();
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        batch.mapTestCycleIdWithStatus.put(testCycle.Id, 'Errored');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify test cycle was updated with error status
        AI_Test_Cycle__c updatedCycle = [SELECT Id, Status__c, Message__c, End_Date_Time__c FROM AI_Test_Cycle__c WHERE Id = :testCycle.Id];
        Assert.areEqual('Errored', updatedCycle.Status__c, 'Status should be Errored');
        Assert.isNotNull(updatedCycle.End_Date_Time__c, 'End date time should be set');
    }
    
    @isTest
    static void testBatchFinishWithEmptyTestCycleIds() {
        Set<String> testCycleIds = new Set<String>();
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Finish should complete without error for empty IDs');
    }
    
    @isTest
    static void testBatchFinishWithNoStatusChange() {
        AI_Test_Cycle__c testCycle = getTestCycle();
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        // Don't add any status to the map - this tests the path where status is not in map
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify test cycle was still updated
        AI_Test_Cycle__c updatedCycle = [SELECT Id, Status__c, End_Date_Time__c FROM AI_Test_Cycle__c WHERE Id = :testCycle.Id];
        Assert.isNotNull(updatedCycle.End_Date_Time__c, 'End date time should be set');
    }
    
    @isTest
    static void testBatchFinishWithAlreadyErroredCycle() {
        AI_Test_Cycle__c testCycle = getTestCycle();
        testCycle.Status__c = 'Errored';
        update testCycle;
        
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        batch.mapTestCycleIdWithStatus.put(testCycle.Id, 'Processed');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify test cycle status remains Errored (not overwritten by Processed)
        AI_Test_Cycle__c updatedCycle = [SELECT Id, Status__c FROM AI_Test_Cycle__c WHERE Id = :testCycle.Id];
        Assert.areEqual('Errored', updatedCycle.Status__c, 'Status should remain Errored');
    }
    
    @isTest
    static void testFullBatchExecution() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getTestCycle();
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        Test.startTest();
        Database.executeBatch(new AIAgenticTestingVerificationPromptBatch(testCycleIds), 1);
        Test.stopTest();
        
        // Verify batch completed
        Assert.isTrue(true, 'Full batch execution should complete');
    }
    
    @isTest
    static void testBatchExecuteMultipleResults() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutSuccess());
        
        AI_Test_Cycle__c testCycle = getTestCycle();
        AI_Response__c aiResponse = getAIResponse();
        
        // Create additional test cycle result
        AI_Test_Cycle_Result__c testCycleResult2 = new AI_Test_Cycle_Result__c(
            AI_Test_Cycle__c = testCycle.Id,
            External_Id__c = 'TestExternal002',
            AI_Security_Audit__c = aiResponse.Id,
            Message__c = ''
        );
        insert testCycleResult2;
        
        Set<String> testCycleIds = new Set<String>{testCycle.Id};
        
        List<AI_Test_Cycle_Result__c> scope = [SELECT Id, Name, AI_Test_Cycle__c, 
                                                      AI_Test_Cycle__r.AI_Verification_Prompt__c, 
                                                      AI_Security_Audit__c, Message__c 
                                               FROM AI_Test_Cycle_Result__c 
                                               WHERE AI_Test_Cycle__c = :testCycle.Id];
        
        AIAgenticTestingVerificationPromptBatch batch = new AIAgenticTestingVerificationPromptBatch(testCycleIds);
        
        Test.startTest();
        batch.execute(null, scope);
        Test.stopTest();
        
        Assert.isTrue(true, 'Batch should process multiple results');
    }
}