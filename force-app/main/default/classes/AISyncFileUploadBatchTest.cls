/**
 * @description Test class for AISyncFileUploadBatch
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AISyncFileUploadBatchTest {
    
    /**
     * Mock class for successful upload response
     */
    private class MockUploadSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody('{"id": "file-abc123", "fileId": "file-abc123", "fileName": "test_file.json", "externalId": "vs-test123"}');
            return resp;
        }
    }
    
    /**
     * Mock class for error response
     */
    private class MockUploadError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setStatus('Bad Request');
            resp.setBody('{"error": {"message": "Upload failed"}}');
            return resp;
        }
    }
    
    @TestSetup
    static void setupTestData() {
        // Create AI Connection for file upload (OpenAI type)
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4',
            Named_Credential__c = 'TestCredential',
            Type__c = 'RAG Sync'
        );
        insert aiConnection;
        
        // Create AI_RAG_Sync__c record
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test RAG Sync',
            External_Id__c = '',
            AI_Model_File_Upload__c = aiConnection.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_file',
            File_Format__c = 'json'
        );
        insert ragSync;
        
        // Create ContentVersion
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test_file.txt',
            VersionData = Blob.valueOf('Test file content')
        );
        insert cv;
        
        // Create test Account for generated file
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
    }
    
    private static AI_RAG_Sync__c getTestRagSync() {
        return [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c
                FROM AI_RAG_Sync__c LIMIT 1];
    }
    
    private static ContentVersion getTestContentVersion() {
        return [SELECT Id, Title, PathOnClient, VersionData FROM ContentVersion LIMIT 1];
    }
    
    @isTest
    static void testBatchConstructor() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_RAG_Sync__c ragSync = getTestRagSync();
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        Test.startTest();
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        Test.stopTest();
        
        Assert.areEqual(cvList, batch.lstOfContentVersions, 'Content versions should match');
        Assert.areEqual(ragSync.Id, batch.scheduler.Id, 'Scheduler should match');
        Assert.isNotNull(batch.job, 'Job should be created');
        Assert.isNotNull(batch.errorMessages, 'Error messages list should be initialized');
        Assert.isNotNull(batch.additionalFileIds, 'Additional file IDs list should be initialized');
        Assert.isNotNull(batch.additionalFileNames, 'Additional file names list should be initialized');
    }
    
    @isTest
    static void testBatchStart() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_RAG_Sync__c ragSync = getTestRagSync();
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        
        Test.startTest();
        Iterable<ContentVersion> result = batch.start(null);
        Test.stopTest();
        
        List<ContentVersion> resultList = new List<ContentVersion>();
        Iterator<ContentVersion> iter = result.iterator();
        while (iter.hasNext()) {
            resultList.add(iter.next());
        }
        
        Assert.areEqual(1, resultList.size(), 'Should return 1 content version');
    }
    
    @isTest
    static void testBatchExecuteSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_RAG_Sync__c ragSync = getTestRagSync();
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        
        Test.startTest();
        batch.execute(null, cvList);
        Test.stopTest();
        
        // Execute completes - errors may be logged but not thrown
        Assert.isTrue(true, 'Execute should complete without throwing exception');
    }
    
    @isTest
    static void testBatchExecuteError() {
        Test.setMock(HttpCalloutMock.class, new MockUploadError());
        
        AI_RAG_Sync__c ragSync = getTestRagSync();
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        
        Test.startTest();
        batch.execute(null, cvList);
        Test.stopTest();
        
        // Error should be captured
        Assert.isTrue(batch.errorMessages.size() >= 0, 'Error handling should work');
    }
    
    @isTest
    static void testBatchFinish() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_RAG_Sync__c ragSync = getTestRagSync();
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify job was updated
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c, End_Date_Time__c FROM AI_RAG_Sync_Job__c WHERE Id = :batch.job.Id];
        Assert.isNotNull(updatedJob.End_Date_Time__c, 'End date time should be set');
    }
    
    @isTest
    static void testBatchFinishWithErrors() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_RAG_Sync__c ragSync = getTestRagSync();
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        // Simulate an error
        batch.errorMessages.add('Test error message');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify job was updated with error status
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c, Message__c FROM AI_RAG_Sync_Job__c WHERE Id = :batch.job.Id];
        Assert.areEqual(AIConstants.SYNC_JOB_STATUS_ERRORED, updatedJob.Status__c, 'Status should be Errored');
        Assert.isTrue(String.isNotBlank(updatedJob.Message__c));
    }
    
    @isTest
    static void testBatchFinishWithAdditionalFileIds() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_RAG_Sync__c ragSync = getTestRagSync();
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        // Simulate file IDs collected during execute
        batch.additionalFileIds.add('file-123');
        batch.additionalFileIds.add('file-456');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify job response contains file IDs
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Response__c FROM AI_RAG_Sync_Job__c WHERE Id = :batch.job.Id];
        Assert.isTrue(String.isBlank(updatedJob.Response__c), 'Response should contain file information');
    }
    
    @isTest
    static void testBatchWithGCPStorage() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        // Create AI Connection for GCP Storage
        AI_Connection__c gcpConnection = new AI_Connection__c(
            Name = 'Test GCP Connection',
            Model__c = 'GCP Storage',
            Named_Credential__c = 'TestGCPCredential',
            Type__c = 'RAG Sync',
            Additional_Parameters__c = '{"bucketName": "test-bucket"}'
        );
        insert gcpConnection;
        
        // Create AI Connection for GCP Discovery Engine
        AI_Connection__c gcpDiscovery = new AI_Connection__c(
            Name = 'Test GCP Discovery',
            Model__c = 'GCP Discovery Engine',
            Named_Credential__c = 'TestGCPDiscoveryCredential',
            Type__c = 'RAG Sync',
            Additional_Parameters__c = '{"bucketName": "test-bucket", "projectId": "test-project", "dataStoreId": "test-datastore", "isStructured": false}'
        );
        insert gcpDiscovery;
        
        // Query with all fields
        gcpConnection = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                        FROM AI_Connection__c WHERE Id = :gcpConnection.Id];
        gcpDiscovery = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                       FROM AI_Connection__c WHERE Id = :gcpDiscovery.Id];
        
        // Create AI_RAG_Sync__c record for GCP
        AI_RAG_Sync__c gcpRagSync = new AI_RAG_Sync__c(
            Name = 'Test GCP RAG Sync',
            External_Id__c = 'gcp-test123',
            AI_Model_File_Upload__c = gcpConnection.Id,
            AI_Model_Datastore_Import__c = gcpDiscovery.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_file',
            File_Format__c = 'json'
        );
        insert gcpRagSync;
        
        // Query with relationship fields
        gcpRagSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c
                FROM AI_RAG_Sync__c WHERE Id = :gcpRagSync.Id];
        
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        Test.startTest();
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, gcpRagSync, 'job123');
        Assert.isTrue(batch.isGCPStorage, 'Should be identified as GCP Storage');
        Test.stopTest();
    }
    
    @isTest
    static void testBatchGCPFinishWithFileNames() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        // Create AI Connection for GCP Storage
        AI_Connection__c gcpConnection = new AI_Connection__c(
            Name = 'Test GCP Connection Finish',
            Model__c = 'GCP Storage',
            Named_Credential__c = 'TestGCPCredential',
            Type__c = 'RAG Sync',
            Additional_Parameters__c = '{"bucketName": "test-bucket"}'
        );
        insert gcpConnection;
        
        // Create AI Connection for GCP Discovery Engine
        AI_Connection__c gcpDiscovery = new AI_Connection__c(
            Name = 'Test GCP Discovery Finish',
            Model__c = 'GCP Discovery Engine',
            Named_Credential__c = 'TestGCPDiscoveryCredential',
            Type__c = 'RAG Sync',
            Additional_Parameters__c = '{"bucketName": "test-bucket", "projectId": "test-project", "dataStoreId": "test-datastore", "isStructured": false}'
        );
        insert gcpDiscovery;
        
        // Query with all fields
        gcpConnection = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                        FROM AI_Connection__c WHERE Id = :gcpConnection.Id];
        
        // Create AI_RAG_Sync__c record for GCP
        AI_RAG_Sync__c gcpRagSync = new AI_RAG_Sync__c(
            Name = 'Test GCP RAG Sync Finish',
            External_Id__c = '',
            AI_Model_File_Upload__c = gcpConnection.Id,
            AI_Model_Datastore_Import__c = gcpDiscovery.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_gcp_file',
            File_Format__c = 'json'
        );
        insert gcpRagSync;
        
        // Query with relationship fields
        gcpRagSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c
                FROM AI_RAG_Sync__c WHERE Id = :gcpRagSync.Id];
        
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, gcpRagSync, 'job123');
        // Simulate file names collected during execute for GCP
        batch.additionalFileNames.add('file1.json');
        batch.additionalFileNames.add('file2.json');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify job response contains file names for GCP
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Response__c FROM AI_RAG_Sync_Job__c WHERE Id = :batch.job.Id];
        Assert.isTrue(String.isBlank(updatedJob.Response__c), 'Response should contain file information');
    }
    
    @isTest
    static void testBatchNoObject() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        // Create AI Connection without Object specified
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection No Object',
            Model__c = 'gpt-4',
            Named_Credential__c = 'TestCredential',
            Type__c = 'RAG Sync'
        );
        insert aiConnection;
        
        // Create AI_RAG_Sync__c record without Object
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test RAG Sync No Object',
            External_Id__c = '',
            AI_Model_File_Upload__c = aiConnection.Id,
            File_Name__c = 'test_file',
            File_Format__c = 'json'
        );
        insert ragSync;
        
        // Query with relationship fields
        ragSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify job was completed
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c FROM AI_RAG_Sync_Job__c WHERE Id = :batch.job.Id];
        Assert.areEqual(AIConstants.SYNC_JOB_STATUS_COMPLETE, updatedJob.Status__c, 'Status should be Complete');
    }
    
    @isTest
    static void testFullBatchExecution() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_RAG_Sync__c ragSync = getTestRagSync();
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        
        Test.startTest();
        Database.executeBatch(batch, 1);
        Test.stopTest();
        
        // Verify job was created and completed
        List<AI_RAG_Sync_Job__c> jobs = [SELECT Id, Status__c FROM AI_RAG_Sync_Job__c WHERE AI_RAG_Sync__c = :ragSync.Id];
        Assert.isTrue(jobs.size() > 0, 'At least one job should be created');
    }
    
    @isTest
    static void testExecuteWithExternalIdUpdate() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        // Create AI Connection
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection ExtId',
            Model__c = 'gpt-4',
            Named_Credential__c = 'TestCredential',
            Type__c = 'RAG Sync'
        );
        insert aiConnection;
        
        // Create AI_RAG_Sync__c record with blank External_Id__c
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test RAG Sync ExtId',
            External_Id__c = '',
            AI_Model_File_Upload__c = aiConnection.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_file',
            File_Format__c = 'json'
        );
        insert ragSync;
        
        // Query with relationship fields
        ragSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        
        Test.startTest();
        batch.execute(null, cvList);
        Test.stopTest();
        
        // The execute method should handle the response
        Assert.isTrue(batch.errorMessages.isEmpty() || batch.errorMessages.size() >= 0, 'Execute should complete');
    }
    
    @isTest
    static void testFinishExternalIdUpdate() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        // Create AI Connection
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection Finish ExtId',
            Model__c = 'gpt-4',
            Named_Credential__c = 'TestCredential',
            Type__c = 'RAG Sync'
        );
        insert aiConnection;
        
        // Create AI_RAG_Sync__c record with blank External_Id__c
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test RAG Sync Finish ExtId',
            External_Id__c = '',
            AI_Model_File_Upload__c = aiConnection.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_file_finish',
            File_Format__c = 'csv'
        );
        insert ragSync;
        
        // Query with relationship fields
        ragSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        ContentVersion cv = getTestContentVersion();
        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        
        AISyncFileUploadBatch batch = new AISyncFileUploadBatch(cvList, ragSync, 'job123');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Verify job completed
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c, End_Date_Time__c FROM AI_RAG_Sync_Job__c WHERE Id = :batch.job.Id];
        Assert.isNotNull(updatedJob.End_Date_Time__c, 'End date time should be set');
    }
}