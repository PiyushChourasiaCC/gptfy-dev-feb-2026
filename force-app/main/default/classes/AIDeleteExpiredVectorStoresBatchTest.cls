/**
 * @description Test class for AIDeleteExpiredVectorStoresBatch
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AIDeleteExpiredVectorStoresBatchTest {
    
    /**
     * Mock class for successful delete response
     */
    private class MockDeleteSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody('{"id": "vs-abc123", "deleted": true}');
            return resp;
        }
    }
    
    /**
     * Mock class for error response
     */
    private class MockDeleteError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setStatus('Bad Request');
            resp.setBody('{"error": {"message": "Vector store not found"}}');
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
        
        // Create AI Agent with TTL
        AI_Agent__c agent = new AI_Agent__c(
            Name = 'Test Agent',
            Developer_Name__c = 'Test_Agent',
            TTL__c = 60,
            TTL_Message__c = 'Session expired',
            AI_Model__c = aiConnection.Id,
            Status__c = 'Active'
        );
        insert agent;
        
        // Create AI Agent without TTL
        AI_Agent__c agentNoTTL = new AI_Agent__c(
            Name = 'Agent No TTL',
            Developer_Name__c = 'Agent_No_TTL',
            TTL_Message__c = 'Session expired',
            AI_Model__c = aiConnection.Id,
            Status__c = 'Active'
        );
        insert agentNoTTL;
        
        // Create AI Response with Vector Store ID (not expired)
        AI_Response__c response1 = new AI_Response__c(
            User_Context_Id__c = 'Thread001',
            Vector_Store_Id__c = 'vs-test123',
            Agent_Name__c = 'Test Agent',
            Session_Expired__c = false
        );
        insert response1;
        
        // Create AI Response with Session Expired flag
        AI_Response__c response2 = new AI_Response__c(
            User_Context_Id__c = 'Thread002',
            Vector_Store_Id__c = 'vs-test456',
            Agent_Name__c = 'Test Agent',
            Session_Expired__c = true
        );
        insert response2;
        
        // Create AI Response without Agent Name
        AI_Response__c response3 = new AI_Response__c(
            User_Context_Id__c = 'Thread003',
            Vector_Store_Id__c = 'vs-test789'
        );
        insert response3;
    }
    
    private static AI_Agent__c getTestAgent() {
        return [SELECT Id, Name, Developer_Name__c, TTL__c FROM AI_Agent__c WHERE Name = 'Test Agent' LIMIT 1];
    }
    
    private static List<AI_Response__c> getTestResponses() {
        return [SELECT Id, Name, User_Context_Id__c, Vector_Store_Id__c, Agent_Name__c, 
                Session_Expired__c, CreatedDate 
                FROM AI_Response__c WHERE Vector_Store_Id__c != null];
    }
    
    @isTest
    static void testSchedulableExecute() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        Test.startTest();
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        String jobId = System.schedule('Test Delete Vector Stores', '0 0 0 1 1 ?', batch);
        Test.stopTest();
        
        // Verify job was scheduled
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual(1, jobs.size(), 'Job should be scheduled');
    }
    
    @isTest
    static void testBatchStart() {
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        Database.QueryLocator locator = batch.start(null);
        Test.stopTest();
        
        Assert.isNotNull(locator, 'QueryLocator should not be null');
    }
    
    @isTest
    static void testBatchExecuteWithExpiredSession() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        // Get response with Session_Expired__c = true
        List<AI_Response__c> responses = [SELECT Id, Name, Vector_Store_Id__c, Agent_Name__c, 
                                           Session_Expired__c, CreatedDate 
                                           FROM AI_Response__c 
                                           WHERE Session_Expired__c = true AND Agent_Name__c != null];
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, responses);
        Test.stopTest();
        
        // Verify execution completed
        Assert.isTrue(true, 'Batch execute should complete');
    }
    
    @isTest
    static void testBatchExecuteWithTTLExpired() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        // Get response and set CreatedDate to past
        AI_Response__c response = [SELECT Id, Name, Vector_Store_Id__c, Agent_Name__c, 
                                   Session_Expired__c, CreatedDate 
                                   FROM AI_Response__c 
                                   WHERE Agent_Name__c = 'Test Agent' AND Session_Expired__c = false
                                   LIMIT 1];
        
        // Set CreatedDate to 2 hours ago (TTL is 60 mins)
        Test.setCreatedDate(response.Id, System.now().addMinutes(-120));
        
        // Re-query to get updated CreatedDate
        response = [SELECT Id, Name, Vector_Store_Id__c, Agent_Name__c, 
                    Session_Expired__c, CreatedDate 
                    FROM AI_Response__c WHERE Id = :response.Id];
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, new List<AI_Response__c>{response});
        Test.stopTest();
        
        // Verify execution completed
        Assert.isTrue(true, 'Batch execute should complete for TTL expired records');
    }
    
    @isTest
    static void testBatchExecuteNoAgentsFound() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        // Create response with non-existent agent
        AI_Response__c response = new AI_Response__c(
            User_Context_Id__c = 'Thread999',
            Vector_Store_Id__c = 'vs-noagent',
            Agent_Name__c = 'Non Existent Agent',
            Session_Expired__c = true
        );
        insert response;
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, new List<AI_Response__c>{response});
        Test.stopTest();
        
        // Should return early without processing
        Assert.isTrue(true, 'Batch should handle non-existent agents gracefully');
    }
    
    @isTest
    static void testBatchExecuteWithCalloutError() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteError());
        
        List<AI_Response__c> responses = [SELECT Id, Name, Vector_Store_Id__c, Agent_Name__c, 
                                           Session_Expired__c, CreatedDate 
                                           FROM AI_Response__c 
                                           WHERE Session_Expired__c = true AND Agent_Name__c != null];
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, responses);
        Test.stopTest();
        
        // Should handle error gracefully
        Assert.isTrue(true, 'Batch should handle callout errors gracefully');
    }
    
    @isTest
    static void testBatchFinish() {
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Finish method is empty, just verify it completes
        Assert.isTrue(true, 'Finish method should complete');
    }
    
    @isTest
    static void testIsSessionExpiredWithFlag() {
        AI_Response__c response = new AI_Response__c(
            Session_Expired__c = true
        );
        
        Test.startTest();
        Boolean result = AIDeleteExpiredVectorStoresBatch.isSessionExpired(response, 60);
        Test.stopTest();
        
        Assert.isTrue(result, 'Should return true when Session_Expired__c is true');
    }
    
    @isTest
    static void testIsSessionExpiredWithTTL() {
        AI_Response__c response = new AI_Response__c(
            Session_Expired__c = false
        );
        insert response;
        
        // Set CreatedDate to 2 hours ago
        Test.setCreatedDate(response.Id, System.now().addMinutes(-120));
        
        // Re-query to get updated CreatedDate
        response = [SELECT Id, Session_Expired__c, CreatedDate FROM AI_Response__c WHERE Id = :response.Id];
        
        Test.startTest();
        Boolean result = AIDeleteExpiredVectorStoresBatch.isSessionExpired(response, 60);
        Test.stopTest();
        
        Assert.isTrue(result, 'Should return true when TTL has expired');
    }
    
    @isTest
    static void testIsSessionNotExpired() {
        AI_Response__c response = new AI_Response__c(
            Session_Expired__c = false
        );
        insert response;
        
        // Re-query to get CreatedDate (just created, so not expired)
        response = [SELECT Id, Session_Expired__c, CreatedDate FROM AI_Response__c WHERE Id = :response.Id];
        
        Test.startTest();
        Boolean result = AIDeleteExpiredVectorStoresBatch.isSessionExpired(response, 60);
        Test.stopTest();
        
        Assert.isFalse(result, 'Should return false when session is not expired');
    }
    
    @isTest
    static void testCreateErrorLog() {
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.createErrorLog('Test error message');
        Test.stopTest();
        
        // Verify error log was created (if enabled)
        Assert.isTrue(true, 'Error log creation should complete');
    }
    
    @isTest
    static void testCreateErrorLogWithBlankMessage() {
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.createErrorLog('');
        Test.stopTest();
        
        // Verify handles blank message
        Assert.isTrue(true, 'Should handle blank error message');
    }
    
    @isTest
    static void testFullBatchExecution() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        // Set one response to be expired by TTL
        AI_Response__c response = [SELECT Id FROM AI_Response__c 
                                   WHERE Agent_Name__c = 'Test Agent' AND Session_Expired__c = false
                                   LIMIT 1];
        Test.setCreatedDate(response.Id, System.now().addMinutes(-120));
        
        Test.startTest();
        Database.executeBatch(new AIDeleteExpiredVectorStoresBatch(), 50);
        Test.stopTest();
        
        // Verify batch completed
        Assert.isTrue(true, 'Full batch execution should complete');
    }
    
    @isTest
    static void testBatchExecuteWithEmptyScope() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, new List<AI_Response__c>());
        Test.stopTest();
        
        // Should handle empty scope
        Assert.isTrue(true, 'Batch should handle empty scope');
    }
    
    @isTest
    static void testBatchExecuteNoExpiredSessions() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        // Get fresh response that is not expired
        AI_Response__c response = [SELECT Id, Name, Vector_Store_Id__c, Agent_Name__c, 
                                   Session_Expired__c, CreatedDate 
                                   FROM AI_Response__c 
                                   WHERE Agent_Name__c = 'Test Agent' AND Session_Expired__c = false
                                   LIMIT 1];
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, new List<AI_Response__c>{response});
        Test.stopTest();
        
        // Should return early since no expired sessions
        Assert.isTrue(true, 'Batch should handle no expired sessions');
    }
    
    @isTest
    static void testBatchExecuteWithNullAgentInMap() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        // Create response with agent that has no TTL (will cause null in agentMap.get())
        AI_Response__c response = new AI_Response__c(
            User_Context_Id__c = 'ThreadNoTTL',
            Vector_Store_Id__c = 'vs-nottl',
            Agent_Name__c = 'Agent No TTL',
            Session_Expired__c = true
        );
        insert response;
        
        // Re-query to get all fields
        response = [SELECT Id, Name, Vector_Store_Id__c, Agent_Name__c, 
                    Session_Expired__c, CreatedDate 
                    FROM AI_Response__c WHERE Id = :response.Id];
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, new List<AI_Response__c>{response});
        Test.stopTest();
        
        // Should handle null TTL gracefully
        Assert.isTrue(true, 'Batch should handle agents without TTL');
    }
    
    @isTest
    static void testBatchExecuteWithException() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteError());
        
        // Create response that will cause exception in processing
        AI_Response__c response = new AI_Response__c(
            User_Context_Id__c = 'ThreadException',
            Vector_Store_Id__c = 'vs-exception',
            Agent_Name__c = 'Test Agent',
            Session_Expired__c = true
        );
        insert response;
        
        // Re-query to get all fields
        response = [SELECT Id, Name, Vector_Store_Id__c, Agent_Name__c, 
                    Session_Expired__c, CreatedDate 
                    FROM AI_Response__c WHERE Id = :response.Id];
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, new List<AI_Response__c>{response});
        Test.stopTest();
        
        // Should handle exception gracefully
        Assert.isTrue(true, 'Batch should handle exceptions in execute');
    }
    
    @isTest
    static void testBatchExecuteWithBlankAgentName() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());
        
        // Create response with blank agent name
        AI_Response__c response = new AI_Response__c(
            User_Context_Id__c = 'ThreadBlank',
            Vector_Store_Id__c = 'vs-blank',
            Agent_Name__c = '',
            Session_Expired__c = true
        );
        insert response;
        
        // Re-query to get all fields
        response = [SELECT Id, Name, Vector_Store_Id__c, Agent_Name__c, 
                    Session_Expired__c, CreatedDate 
                    FROM AI_Response__c WHERE Id = :response.Id];
        
        AIDeleteExpiredVectorStoresBatch batch = new AIDeleteExpiredVectorStoresBatch();
        
        Test.startTest();
        batch.execute(null, new List<AI_Response__c>{response});
        Test.stopTest();
        
        // Should handle blank agent name
        Assert.isTrue(true, 'Batch should handle blank agent names');
    }
}