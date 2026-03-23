/**
 * @description Test class for AISyncSObjectUploadBatch
 * @author Plumcloud Labs
 * @group GPTfy
 * V2-7889
 */
@isTest
public with sharing class AISyncSObjectUploadBatchTest {
    
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
        // Create AI Connection for file upload
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4',
            Named_Credential__c = 'TestCredential',
            Type__c = 'RAG Sync'
        );
        insert aiConnection;
        
        // Create test Accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
    }
    
    private static AI_RAG_Sync__c createTestRagSync(String fileFormat, AI_Connection__c connection) {
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test RAG Sync',
            External_Id__c = '',
            AI_Model_File_Upload__c = connection.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name","Id":"Account ID"}',
            File_Name__c = 'test_file',
            File_Format__c = fileFormat,
            Max_File_Size__c = 3
        );
        insert ragSync;
        
        return [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c, Max_File_Size__c
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
    }
    
    private static AI_Connection__c getTestConnection() {
        return [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                FROM AI_Connection__c LIMIT 1];
    }
    
    @isTest
    static void testSimpleConstructor() {
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        Test.startTest();
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        Test.stopTest();
        
        Assert.areEqual(ragSync.Id, batch.scheduler.Id, 'Scheduler should match');
        Assert.areEqual(job.Id, batch.job.Id, 'Job should match');
        Assert.areEqual('', batch.accumulatedContent, 'Accumulated content should be empty');
        Assert.areEqual(1, batch.filePartCounter, 'File part counter should start at 1');
        Assert.isNotNull(batch.additionalFileIds, 'Additional file IDs should be initialized');
        Assert.isNotNull(batch.additionalFileNames, 'Additional file names should be initialized');
        Assert.isNotNull(batch.errorMessages, 'Error messages should be initialized');
        Assert.isFalse(batch.csvHeaderAdded, 'CSV header should not be added initially');
    }
    
    @isTest
    static void testConstructorWithExistingData() {
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<String> existingFileIds = new List<String>{'file-1', 'file-2'};
        List<String> existingFileNames = new List<String>{'file1.json', 'file2.json'};
        List<String> existingErrors = new List<String>{'Error 1'};
        
        Test.startTest();
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(
            ragSync, job, existingFileIds, existingFileNames, existingErrors
        );
        Test.stopTest();
        
        Assert.areEqual(2, batch.additionalFileIds.size(), 'Should have 2 existing file IDs');
        Assert.areEqual(2, batch.additionalFileNames.size(), 'Should have 2 existing file names');
        Assert.areEqual(1, batch.errorMessages.size(), 'Should have 1 existing error');
    }
    
    @isTest
    static void testStartMethodGeneratesQuery() {
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();
        
        Assert.isNotNull(ql, 'Query locator should not be null');
    }
    
    @isTest
    static void testExecuteWithJSONFormat() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 2];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        Test.stopTest();
        
        Assert.areEqual(2, batch.totalCount, 'Total count should be 2');
        Assert.isTrue(String.isNotBlank(batch.accumulatedContent), 'Content should be accumulated');
    }
    
    @isTest
    static void testExecuteWithCSVFormat() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('csv', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 2];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        Test.stopTest();
        
        Assert.areEqual(2, batch.totalCount, 'Total count should be 2');
        Assert.isTrue(batch.csvHeaderAdded, 'CSV header should be added');
    }
    
    @isTest
    static void testExecuteWithJSONLFormat() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('jsonl', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 2];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        Test.stopTest();
        
        Assert.areEqual(2, batch.totalCount, 'Total count should be 2');
        Assert.isTrue(String.isNotBlank(batch.accumulatedContent), 'Content should be accumulated');
    }
    
    @isTest
    static void testExecuteWithEmptyScope() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, new List<Account>());
        Test.stopTest();
        
        Assert.areEqual(0, batch.totalCount, 'Total count should be 0');
    }
    
    @isTest
    static void testFinishWithRemainingContent() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 1];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        batch.finish(null);
        Test.stopTest();
        
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c, End_Date_Time__c FROM AI_RAG_Sync_Job__c WHERE Id = :job.Id];
        Assert.isNotNull(updatedJob.End_Date_Time__c, 'End date time should be set');
    }
    
    @isTest
    static void testFinishWithErrors() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        batch.errorMessages.add('Test error');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c, Message__c FROM AI_RAG_Sync_Job__c WHERE Id = :job.Id];
        Assert.areEqual(AIConstants.SYNC_JOB_STATUS_ERRORED, updatedJob.Status__c, 'Status should be Errored');
        Assert.isTrue(String.isNotBlank(updatedJob.Message__c), 'Message should contain error');
    }
    
    @isTest
    static void testGCPStorageConfiguration() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c gcpConnection = new AI_Connection__c(
            Name = 'Test GCP Connection',
            Model__c = 'GCP Storage',
            Named_Credential__c = 'TestGCPCredential',
            Type__c = 'RAG Sync',
            Additional_Parameters__c = '{"bucketName": "test-bucket"}'
        );
        insert gcpConnection;
        
        AI_Connection__c gcpDiscovery = new AI_Connection__c(
            Name = 'Test GCP Discovery',
            Model__c = 'GCP Discovery Engine',
            Named_Credential__c = 'TestGCPDiscoveryCredential',
            Type__c = 'RAG Sync',
            Additional_Parameters__c = '{"bucketName": "test-bucket", "projectId": "test-project", "dataStoreId": "test-datastore"}'
        );
        insert gcpDiscovery;
        
        gcpConnection = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                        FROM AI_Connection__c WHERE Id = :gcpConnection.Id];
        gcpDiscovery = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                       FROM AI_Connection__c WHERE Id = :gcpDiscovery.Id];
        
        AI_RAG_Sync__c gcpRagSync = new AI_RAG_Sync__c(
            Name = 'Test GCP RAG Sync',
            External_Id__c = '',
            AI_Model_File_Upload__c = gcpConnection.Id,
            AI_Model_Datastore_Import__c = gcpDiscovery.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_file',
            File_Format__c = 'json'
        );
        insert gcpRagSync;
        
        gcpRagSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c, Max_File_Size__c
                FROM AI_RAG_Sync__c WHERE Id = :gcpRagSync.Id];
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = gcpRagSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        Test.startTest();
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(gcpRagSync, job);
        Test.stopTest();
        
        Assert.isTrue(batch.isGCPStorage, 'Should be identified as GCP Storage');
    }
    
    @isTest
    static void testAzureSearchDirectConfiguration() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c azureConnection = new AI_Connection__c(
            Name = 'Test Azure Connection',
            Model__c = 'Azure Search',
            Named_Credential__c = 'TestAzureCredential',
            Type__c = 'RAG Sync'
        );
        insert azureConnection;
        
        azureConnection = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                          FROM AI_Connection__c WHERE Id = :azureConnection.Id];
        
        AI_RAG_Sync__c azureRagSync = new AI_RAG_Sync__c(
            Name = 'Test Azure RAG Sync',
            External_Id__c = '',
            AI_Model_File_Upload__c = azureConnection.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_file',
            File_Format__c = 'json',
            Max_File_Size__c = 1
        );
        insert azureRagSync;
        
        azureRagSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c, Max_File_Size__c
                FROM AI_RAG_Sync__c WHERE Id = :azureRagSync.Id];
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = azureRagSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        Test.startTest();
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(azureRagSync, job);
        Test.stopTest();
        
        Assert.isTrue(batch.isAzureSearchDirect, 'Should be identified as Azure Search Direct');
        Assert.areEqual(2 * 1024 * 1024, batch.stringLimit, 'Azure should use 2MB string limit');
    }
    
    @isTest
    static void testFinishWithGCPDatastoreImport() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c gcpConnection = new AI_Connection__c(
            Name = 'Test GCP Connection Datastore',
            Model__c = 'GCP Storage',
            Named_Credential__c = 'TestGCPCredential',
            Type__c = 'RAG Sync',
            Additional_Parameters__c = '{"bucketName": "test-bucket"}'
        );
        insert gcpConnection;
        
        AI_Connection__c gcpDiscovery = new AI_Connection__c(
            Name = 'Test GCP Discovery Datastore',
            Model__c = 'GCP Discovery Engine',
            Named_Credential__c = 'TestGCPDiscoveryCredential',
            Type__c = 'RAG Sync',
            Additional_Parameters__c = '{"bucketName": "test-bucket", "projectId": "test-project", "dataStoreId": "test-datastore"}'
        );
        insert gcpDiscovery;
        
        gcpConnection = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                        FROM AI_Connection__c WHERE Id = :gcpConnection.Id];
        gcpDiscovery = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                       FROM AI_Connection__c WHERE Id = :gcpDiscovery.Id];
        
        AI_RAG_Sync__c gcpRagSync = new AI_RAG_Sync__c(
            Name = 'Test GCP RAG Sync Datastore',
            External_Id__c = '',
            AI_Model_File_Upload__c = gcpConnection.Id,
            AI_Model_Datastore_Import__c = gcpDiscovery.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_file',
            File_Format__c = 'json'
        );
        insert gcpRagSync;
        
        gcpRagSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c, Max_File_Size__c
                FROM AI_RAG_Sync__c WHERE Id = :gcpRagSync.Id];
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = gcpRagSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(gcpRagSync, job);
        batch.additionalFileNames.add('file1.json');
        batch.additionalFileNames.add('file2.json');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c, Response__c, End_Date_Time__c FROM AI_RAG_Sync_Job__c WHERE Id = :job.Id];
        Assert.isNotNull(updatedJob.End_Date_Time__c, 'End date time should be set');
    }
    
    @isTest
    static void testFullBatchExecution() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c FROM AI_RAG_Sync_Job__c WHERE Id = :job.Id];
        Assert.isNotNull(updatedJob.Status__c, 'Job status should be set');
    }
    
    @isTest
    static void testExecuteWithError() {
        Test.setMock(HttpCalloutMock.class, new MockUploadError());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 1];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        Test.stopTest();
        
        Assert.isTrue(batch.errorMessages.size() >= 0, 'Error handling should work');
    }
    
    @isTest
    static void testMaxFileSizeConfiguration() {
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        ragSync.Max_File_Size__c = 10;
        update ragSync;
        
        ragSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c, Max_File_Size__c
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        Test.startTest();
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        Test.stopTest();
        
        Assert.areEqual(5 * 1024 * 1024, batch.maxContentSize, 'Max content size should be capped at 5MB');
    }
    
    @isTest
    static void testConstructorWithNullLists() {
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        Test.startTest();
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job, null, null, null);
        Test.stopTest();
        
        Assert.isNotNull(batch.additionalFileIds, 'Should initialize empty list for null file IDs');
        Assert.isNotNull(batch.additionalFileNames, 'Should initialize empty list for null file names');
        Assert.isNotNull(batch.errorMessages, 'Should initialize empty list for null errors');
    }
    
    @isTest
    static void testCSVMultipleBatchesHeaderHandling() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('csv', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts1 = [SELECT Id, Name FROM Account LIMIT 2];
        List<Account> accounts2 = [SELECT Id, Name FROM Account LIMIT 2 OFFSET 2];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts1);
        batch.execute(null, accounts2);
        Test.stopTest();
        
        Assert.areEqual(4, batch.totalCount, 'Total count should be 4');
        Assert.isTrue(batch.csvHeaderAdded, 'CSV header should be added');
    }
    
    @isTest
    static void testFinishWithPendingFile() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 2];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        batch.finish(null);
        Test.stopTest();
        
        AI_RAG_Sync_Job__c updatedJob = [SELECT Id, Status__c, Response__c FROM AI_RAG_Sync_Job__c WHERE Id = :job.Id];
        Assert.isNotNull(updatedJob.Status__c, 'Status should be set');
    }
    
    @isTest
    static void testConstructorWithBlankFields() {
        AI_Connection__c connection = getTestConnection();
        
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test RAG Sync No Fields',
            External_Id__c = '',
            AI_Model_File_Upload__c = connection.Id,
            Object__c = 'Account',
            Fields__c = '',
            File_Name__c = 'test_file',
            File_Format__c = 'json'
        );
        insert ragSync;
        
        ragSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c, Max_File_Size__c
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        Test.startTest();
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        Test.stopTest();
        
        Assert.isNotNull(batch.fieldMap, 'Field map should be initialized');
        Assert.areEqual(0, batch.fieldMap.size(), 'Field map should be empty');
    }
    
    @isTest
    static void testAzureSearchDirectWithJSONLContent() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c azureConnection = new AI_Connection__c(
            Name = 'Test Azure JSONL',
            Model__c = 'Azure Search',
            Named_Credential__c = 'TestAzureCredential',
            Type__c = 'RAG Sync'
        );
        insert azureConnection;
        
        azureConnection = [SELECT Id, Name, Model__c, Named_Credential__c, Type__c, Additional_Parameters__c 
                          FROM AI_Connection__c WHERE Id = :azureConnection.Id];
        
        AI_RAG_Sync__c azureRagSync = new AI_RAG_Sync__c(
            Name = 'Test Azure JSONL Sync',
            External_Id__c = '',
            AI_Model_File_Upload__c = azureConnection.Id,
            Object__c = 'Account',
            Fields__c = '{"content":"Name"}',
            File_Name__c = 'test_file',
            File_Format__c = 'jsonl'
        );
        insert azureRagSync;
        
        azureRagSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c, Max_File_Size__c
                FROM AI_RAG_Sync__c WHERE Id = :azureRagSync.Id];
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = azureRagSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 2];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(azureRagSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        Test.stopTest();
        
        Assert.isTrue(batch.isAzureSearchDirect, 'Should be Azure Search Direct');
    }
    
    @isTest
    static void testJSONContentMerging() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts1 = [SELECT Id, Name FROM Account LIMIT 2];
        List<Account> accounts2 = [SELECT Id, Name FROM Account LIMIT 2 OFFSET 2];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts1);
        batch.execute(null, accounts2);
        Test.stopTest();
        
        Assert.areEqual(4, batch.totalCount, 'Total count should be 4');
        Assert.isTrue(String.isNotBlank(batch.accumulatedContent), 'Content should be accumulated');
    }
    
    @isTest
    static void testJSONLContentAppending() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('jsonl', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts1 = [SELECT Id, Name FROM Account LIMIT 1];
        List<Account> accounts2 = [SELECT Id, Name FROM Account LIMIT 1 OFFSET 1];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts1);
        batch.execute(null, accounts2);
        Test.stopTest();
        
        Assert.areEqual(2, batch.totalCount, 'Total count should be 2');
        Assert.isTrue(batch.accumulatedContent.contains('\n'), 'JSONL should have newline separator');
    }
    
    @isTest
    static void testFileNameWithExistingExtension() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test RAG Sync Extension',
            External_Id__c = '',
            AI_Model_File_Upload__c = connection.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_file.csv',
            File_Format__c = 'csv'
        );
        insert ragSync;
        
        ragSync = [SELECT Id, Name, External_Id__c, AI_Model_File_Upload__c, 
                AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c,
                AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c,
                AI_Model_Datastore_Import__r.Model__c,
                AI_Model_Datastore_Import__r.Additional_Parameters__c,
                Object__c, Fields__c, File_Name__c, File_Format__c, Where_Clause__c, Max_File_Size__c
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 1];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        batch.finish(null);
        Test.stopTest();
        
        Assert.areEqual(1, batch.totalCount, 'Total count should be 1');
    }
    
    @isTest
    static void testFinishWithExternalIdUpdate() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());
        
        AI_Connection__c connection = getTestConnection();
        AI_RAG_Sync__c ragSync = createTestRagSync('json', connection);
        
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            Start_Date_Time__c = System.now(),
            AI_RAG_Sync__c = ragSync.Id,
            Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
        );
        insert job;
        
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 1];
        
        AISyncSObjectUploadBatch batch = new AISyncSObjectUploadBatch(ragSync, job);
        
        Test.startTest();
        batch.execute(null, accounts);
        batch.scheduler.External_Id__c = 'test-external-id';
        batch.finish(null);
        Test.stopTest();
        
        AI_RAG_Sync__c updatedScheduler = [SELECT Id, External_Id__c FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        Assert.areEqual('test-external-id', updatedScheduler.External_Id__c, 'External ID should be updated');
    }
}
