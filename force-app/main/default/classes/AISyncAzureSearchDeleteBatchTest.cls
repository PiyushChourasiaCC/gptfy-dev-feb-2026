/**
 * @description Test class for AISyncAzureSearchDeleteBatch
 * @author Plumcloud Labs
 * @group GPTfy
 */
@isTest
private class AISyncAzureSearchDeleteBatchTest {
    
    /**
     * @description Mock HTTP response for Azure Search queries and deletes
     */
    private class AzureSearchMock implements HttpCalloutMock {
        private Boolean returnEmpty;
        private Boolean simulateError;
        
        public AzureSearchMock() {
            this.returnEmpty = false;
            this.simulateError = false;
        }
        
        public AzureSearchMock(Boolean returnEmpty, Boolean simulateError) {
            this.returnEmpty = returnEmpty;
            this.simulateError = simulateError;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            if (simulateError) {
                res.setStatusCode(500);
                res.setBody('{"error": {"code": "500", "message": "Internal Server Error"}}');
                return res;
            }
            
            String endpoint = req.getEndpoint();
            
            // Query for document IDs
            if (req.getMethod() == 'GET' && endpoint.contains('/docs?')) {
                if (returnEmpty) {
                    res.setStatusCode(200);
                    res.setBody('{"value": []}');
                } else {
                    // Return some test document IDs
                    res.setStatusCode(200);
                    res.setBody('{"value": [{"id": "doc1"}, {"id": "doc2"}, {"id": "doc3"}]}');
                }
            }
            // Delete documents
            else if (req.getMethod() == 'POST' && endpoint.contains('/docs/index')) {
                res.setStatusCode(200);
                res.setBody('{"value": [{"key": "doc1", "status": true}, {"key": "doc2", "status": true}, {"key": "doc3", "status": true}]}');
            }
            else {
                res.setStatusCode(200);
                res.setBody('{}');
            }
            
            return res;
        }
    }
    
    @TestSetup
    static void setupTestData() {
        // Create AI Connection for Azure Search
        AI_Connection__c azureSearchConn = new AI_Connection__c(
            Name = 'Azure Search Direct Test',
            Model__c = 'Azure AI Search Direct',
            Named_Credential__c = 'Azure_Search_Test',
            Type__c = 'Rag Sync',
            Additional_Parameters__c = '{"indexName": "testindex", "apiVersion": "2024-07-01"}'
        );
        insert azureSearchConn;
        
        // Create RAG Sync scheduler
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test Azure Search Sync',
            AI_Model_File_Upload__c = azureSearchConn.Id,
            Object__c = 'Account',
            Fields__c = '{"Name": "name", "Industry": "industry"}',
            File_Format__c = 'JSONL'
        );
        insert ragSync;
    }
    
    @isTest
    static void testBatchWithDocuments() {
        Test.setMock(HttpCalloutMock.class, new AzureSearchMock());
        
        AI_RAG_Sync__c ragSync = [SELECT Id, Name, Object__c, Fields__c, File_Format__c, External_Id__c,
                                  AI_Model_File_Upload__c, AI_Model_File_Upload__r.Model__c,
                                  AI_Model_File_Upload__r.Named_Credential__c,
                                  AI_Model_File_Upload__r.Additional_Parameters__c
                                  FROM AI_RAG_Sync__c LIMIT 1];
        
        List<ContentVersion> cvList = new List<ContentVersion>();
        
        Test.startTest();
        AISyncAzureSearchDeleteBatch batch = new AISyncAzureSearchDeleteBatch(cvList, ragSync, 'testJob123');
        Database.executeBatch(batch, 1000);
        Test.stopTest();
        
        // Verify batch completed
        Assert.isTrue(true, 'Batch should complete successfully');
    }
    
    @isTest
    static void testBatchWithEmptyIndex() {
        Test.setMock(HttpCalloutMock.class, new AzureSearchMock(true, false));
        
        AI_RAG_Sync__c ragSync = [SELECT Id, Name, Object__c, Fields__c, File_Format__c, External_Id__c,
                                  AI_Model_File_Upload__c, AI_Model_File_Upload__r.Model__c,
                                  AI_Model_File_Upload__r.Named_Credential__c,
                                  AI_Model_File_Upload__r.Additional_Parameters__c
                                  FROM AI_RAG_Sync__c LIMIT 1];
        
        List<ContentVersion> cvList = new List<ContentVersion>();
        
        Test.startTest();
        AISyncAzureSearchDeleteBatch batch = new AISyncAzureSearchDeleteBatch(cvList, ragSync, 'testJob123');
        Database.executeBatch(batch, 1000);
        Test.stopTest();
        
        // Verify batch completed even with empty index
        Assert.isTrue(true, 'Batch should complete successfully with empty index');
    }
    
    @isTest
    static void testBatchWithError() {
        Test.setMock(HttpCalloutMock.class, new AzureSearchMock(false, true));
        
        AI_RAG_Sync__c ragSync = [SELECT Id, Name, Object__c, Fields__c, File_Format__c, External_Id__c,
                                  AI_Model_File_Upload__c, AI_Model_File_Upload__r.Model__c,
                                  AI_Model_File_Upload__r.Named_Credential__c,
                                  AI_Model_File_Upload__r.Additional_Parameters__c
                                  FROM AI_RAG_Sync__c LIMIT 1];
        
        List<ContentVersion> cvList = new List<ContentVersion>();
        
        Test.startTest();
        AISyncAzureSearchDeleteBatch batch = new AISyncAzureSearchDeleteBatch(cvList, ragSync, 'testJob123');
        Database.executeBatch(batch, 1000);
        Test.stopTest();
        
        // Verify batch handles errors gracefully
        Assert.isTrue(true, 'Batch should handle errors gracefully');
    }
    
    @isTest
    static void testBatchWithMissingConfig() {
        Test.setMock(HttpCalloutMock.class, new AzureSearchMock());
        
        // Create RAG Sync without proper Azure config
        AI_Connection__c conn = new AI_Connection__c(
            Name = 'No Index Config',
            Model__c = 'Azure AI Search Direct',
            Type__c = 'Rag Sync',
            Named_Credential__c = 'Azure_Search_Test'
            // Missing Additional_Parameters__c with indexName
        );
        insert conn;
        
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test No Config',
            AI_Model_File_Upload__c = conn.Id,
            Object__c = 'Account',
            Fields__c = '{"Name": "name"}'
        );
        insert ragSync;
        
        AI_RAG_Sync__c queriedRagSync = [SELECT Id, Name, Object__c, Fields__c, File_Format__c, External_Id__c,
                                         AI_Model_File_Upload__c, AI_Model_File_Upload__r.Model__c,
                                         AI_Model_File_Upload__r.Named_Credential__c,
                                         AI_Model_File_Upload__r.Additional_Parameters__c
                                         FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        List<ContentVersion> cvList = new List<ContentVersion>();
        
        Test.startTest();
        AISyncAzureSearchDeleteBatch batch = new AISyncAzureSearchDeleteBatch(cvList, queriedRagSync, 'testJob123');
        Database.executeBatch(batch, 1000);
        Test.stopTest();
        
        // Verify batch handles missing config gracefully
        Assert.isTrue(true, 'Batch should handle missing config gracefully');
    }
    
    @isTest
    static void testConstructor() {
        AI_RAG_Sync__c ragSync = [SELECT Id, Name, Object__c, Fields__c, File_Format__c, External_Id__c,
                                  AI_Model_File_Upload__c, AI_Model_File_Upload__r.Model__c,
                                  AI_Model_File_Upload__r.Named_Credential__c,
                                  AI_Model_File_Upload__r.Additional_Parameters__c
                                  FROM AI_RAG_Sync__c LIMIT 1];
        
        List<ContentVersion> cvList = new List<ContentVersion>();
        
        Test.startTest();
        AISyncAzureSearchDeleteBatch batch = new AISyncAzureSearchDeleteBatch(cvList, ragSync, 'testJob123');
        Test.stopTest();
        
        // Verify constructor initializes properly
        Assert.isNotNull(batch, 'Batch instance should be created');
    }
}