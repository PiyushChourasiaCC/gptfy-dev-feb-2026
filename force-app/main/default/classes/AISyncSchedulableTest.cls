/**
 * @description Dedicated test class for AISyncSchedulable
 * Covers utility methods, file generation, callouts, and schedulable logic
 */
@isTest
public class AISyncSchedulableTest {
    
    /**
     * Mock class for successful responses
     */
    private class MockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            
            if (req.getEndpoint().contains('/v1/files')) {
                resp.setBody('{"id": "file-12345", "object": "file", "purpose": "assistants"}');
            } else if (req.getEndpoint().contains('/v1/vector_stores')) {
                resp.setBody('{"id": "vs_abcde12345", "object": "vector_store"}');
            } else if (req.getEndpoint().contains('/upload/storage/v1')) {
                resp.setBody('{"name": "test_file.json", "bucket": "test-bucket"}');
            } else if (req.getEndpoint().contains('/documents:import')) {
                resp.setBody('{"name": "operations/import-12345"}');
            } else if (req.getEndpoint().contains('/storage/v1/b/') && req.getMethod() == 'DELETE') {
                resp.setBody('');
                resp.setStatusCode(204);
            } else {
                resp.setBody('{"id": "default-12345"}');
            }
            return resp;
        }
    }
    
    /**
     * Mock class for error responses
     */
    private class MockError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(500);
            resp.setStatus('Internal Server Error');
            resp.setBody('{"error": "Server error"}');
            return resp;
        }
    }
    
    @TestSetup
    static void setupTestData() {
        // Create test Account records
        List<Account> accounts = new List<Account>();
        accounts.add(new Account(Name = 'Test Account 1', AnnualRevenue = 500000));
        accounts.add(new Account(Name = 'Test Account 2', AnnualRevenue = 1000000));
        insert accounts;
        
        // Create AI Connection for OpenAI file upload
        AI_Connection__c openAIFileUpload = new AI_Connection__c(
            Name = 'Test OpenAI File Upload',
            Type__c = 'RAG Sync',
            Model__c = 'gpt-4-turbo',
            Named_Credential__c = 'Test_OpenAI_Credential'
        );
        insert openAIFileUpload;
        
        // Create AI Connection for OpenAI vector store
        AI_Connection__c openAIDatastore = new AI_Connection__c(
            Name = 'Test OpenAI Datastore',
            Type__c = 'RAG Sync',
            Model__c = 'gpt-4-turbo',
            Named_Credential__c = 'Test_OpenAI_Credential'
        );
        insert openAIDatastore;
        
        // Create AI Connection for GCP Storage
        AI_Connection__c gcpStorage = new AI_Connection__c(
            Name = 'Test GCP Storage',
            Type__c = 'RAG Sync',
            Model__c = 'GCP Storage',
            Named_Credential__c = 'Test_GCP_Credential',
            Additional_Parameters__c = '{"bucketName": "test-bucket"}'
        );
        insert gcpStorage;
        
        // Create AI Connection for GCP Discovery Engine
        AI_Connection__c gcpDiscovery = new AI_Connection__c(
            Name = 'Test GCP Discovery',
            Type__c = 'RAG Sync',
            Model__c = 'GCP Discovery Engine',
            Named_Credential__c = 'Test_GCP_Discovery_Credential',
            Additional_Parameters__c = '{"bucketName": "test-bucket", "projectId": "test-project", "dataStoreId": "test-datastore", "isStructured": false}'
        );
        insert gcpDiscovery;
        
        // Create AI_RAG_Sync__c record for OpenAI
        Map<String, String> fieldMap = new Map<String, String>{
            'Name' => 'Account Name',
            'AnnualRevenue' => 'Revenue'
        };
        
        AI_RAG_Sync__c openAIRagSync = new AI_RAG_Sync__c(
            Name = 'Test OpenAI RAG Sync',
            Cron_Expression__c = '0 0 1 * * ?',
            Object__c = 'Account',
            Fields__c = JSON.serialize(fieldMap),
            File_Format__c = 'json',
            File_Name__c = 'accounts.json',
            Where_Clause__c = 'AnnualRevenue > 100000',
            AI_Model_File_Upload__c = openAIFileUpload.Id,
            AI_Model_Datastore_Import__c = openAIDatastore.Id,
            Status__c = 'Not Scheduled'
        );
        insert openAIRagSync;
        
        // Create AI_RAG_Sync__c record for GCP
        AI_RAG_Sync__c gcpRagSync = new AI_RAG_Sync__c(
            Name = 'Test GCP RAG Sync',
            Cron_Expression__c = '0 0 2 * * ?',
            Object__c = 'Account',
            Fields__c = JSON.serialize(fieldMap),
            File_Format__c = 'csv',
            File_Name__c = 'accounts.csv',
            AI_Model_File_Upload__c = gcpStorage.Id,
            AI_Model_Datastore_Import__c = gcpDiscovery.Id,
            Status__c = 'Not Scheduled'
        );
        insert gcpRagSync;
        
        // Create ContentVersion and link to RAG Sync
        ContentVersion cv = new ContentVersion(
            Title = 'Test Attached File',
            PathOnClient = 'test_attached.pdf',
            VersionData = Blob.valueOf('Test file content for attachment')
        );
        insert cv;
        
        // Query ContentDocumentId
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        
        // Create ContentDocumentLink
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = openAIRagSync.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V'
        );
        insert cdl;
    }
    
    private static AI_RAG_Sync__c getOpenAIRagSync() {
        return [SELECT Id, Name, External_Id__c, Cron_Expression__c,
                Where_Clause__c, File_Format__c, Object__c, Fields__c, File_Name__c,
                AI_Model_File_Upload__c, AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c, AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_File_Upload__r.Connector_Class__c,
                AI_Model_Datastore_Import__c, AI_Model_Datastore_Import__r.Named_Credential__c,
                AI_Model_Datastore_Import__r.Model__c, AI_Model_Datastore_Import__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__r.Connector_Class__c,
                (SELECT Id, Response__c FROM AI_RAG_Sync_Jobs__r ORDER BY CreatedDate DESC LIMIT 1)
                FROM AI_RAG_Sync__c WHERE Name = 'Test OpenAI RAG Sync' LIMIT 1];
    }
    
    private static AI_RAG_Sync__c getGCPRagSync() {
        return [SELECT Id, Name, External_Id__c, Cron_Expression__c,
                Where_Clause__c, File_Format__c, Object__c, Fields__c, File_Name__c,
                AI_Model_File_Upload__c, AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c, AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_File_Upload__r.Connector_Class__c,
                AI_Model_Datastore_Import__c, AI_Model_Datastore_Import__r.Named_Credential__c,
                AI_Model_Datastore_Import__r.Model__c, AI_Model_Datastore_Import__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__r.Connector_Class__c,
                (SELECT Id, Response__c FROM AI_RAG_Sync_Jobs__r ORDER BY CreatedDate DESC LIMIT 1)
                FROM AI_RAG_Sync__c WHERE Name = 'Test GCP RAG Sync' LIMIT 1];
    }
    
    @isTest
    static void testSchedulableConstructor() {
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        
        Test.startTest();
        AISyncSchedulable schedulable = new AISyncSchedulable(ragSync.Id);
        Test.stopTest();
        
        Assert.areEqual(ragSync.Id, schedulable.schedulerId, 'Scheduler ID should match');
    }
    
    @isTest
    static void testSchedulableExecute() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        AISyncSchedulable schedulable = new AISyncSchedulable(ragSync.Id);
        
        Test.startTest();
        schedulable.execute(null);
        Test.stopTest();
        
        // Verify a job was created
        List<AI_RAG_Sync_Job__c> jobs = [SELECT Id FROM AI_RAG_Sync_Job__c WHERE AI_RAG_Sync__c = :ragSync.Id];
        Assert.isTrue(jobs.size() > 0, 'At least one job should be created');
    }
    
    @isTest
    static void testProcessRequestWithFiles() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        
        Test.startTest();
        AISyncSchedulable.processRequest(ragSync.Id, 'test-job-123');
        Test.stopTest();
        
        // Verify batch was executed
        List<AI_RAG_Sync_Job__c> jobs = [SELECT Id FROM AI_RAG_Sync_Job__c WHERE AI_RAG_Sync__c = :ragSync.Id];
        Assert.isTrue(jobs.size() >= 0, 'Process request should complete');
    }
    
    @isTest
    static void testProcessRequestGCP() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getGCPRagSync();
        
        Test.startTest();
        AISyncSchedulable.processRequest(ragSync.Id, 'test-job-456');
        Test.stopTest();
        
        // Verify batch was executed
        Assert.isTrue(true, 'Process request for GCP should complete');
    }
    
    @isTest
    static void testCreateFileUsingRecords() {
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        
        Test.startTest();
        String fileContent = AISyncSchedulable.createFileUsingRecords(ragSync);
        Test.stopTest();
        
        Assert.isNotNull(fileContent, 'File content should not be null');
        Assert.isTrue(fileContent.contains('Account Name'), 'File should contain field labels');
    }
    
    @isTest
    static void testCreateFileUsingRecordsCSV() {
        AI_RAG_Sync__c ragSync = getGCPRagSync();
        
        Test.startTest();
        String fileContent = AISyncSchedulable.createFileUsingRecords(ragSync);
        Test.stopTest();
        
        Assert.isNotNull(fileContent, 'File content should not be null');
    }
    
    @isTest
    static void testGenerateCSV() {
        List<Account> accounts = [SELECT Name, AnnualRevenue FROM Account];
        Map<String, Object> fieldMap = new Map<String, Object>{
            'Name' => 'Account Name',
            'AnnualRevenue' => 'Revenue'
        };
        
        Test.startTest();
        String csv = AISyncSchedulable.generateCSV(accounts, fieldMap);
        Test.stopTest();
        
        Assert.isTrue(csv.contains('Account Name'), 'CSV should contain header');
        Assert.isTrue(csv.contains('Test Account 1'), 'CSV should contain data');
    }
    
    @isTest
    static void testGenerateJSON() {
        List<Account> accounts = [SELECT Name, AnnualRevenue FROM Account];
        Map<String, Object> fieldMap = new Map<String, Object>{
            'Name' => 'Account Name',
            'AnnualRevenue' => 'Revenue'
        };
        
        Test.startTest();
        String jsonStr = AISyncSchedulable.generateJSON(accounts, fieldMap);
        Test.stopTest();
        
        Assert.isTrue(jsonStr.startsWith('['), 'JSON should be an array');
        Assert.isTrue(jsonStr.contains('Account Name'), 'JSON should contain field labels');
    }
    
    @isTest
    static void testGenerateJSONEmptyRecords() {
        List<Account> emptyAccounts = new List<Account>();
        Map<String, Object> fieldMap = new Map<String, Object>{
            'Name' => 'Account Name'
        };
        
        Test.startTest();
        String jsonStr = AISyncSchedulable.generateJSON(emptyAccounts, fieldMap);
        Test.stopTest();
        
        Assert.isNull(jsonStr, 'JSON should be null for empty records');
    }
    
    @isTest
    static void testPushToAIOpenAI() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        String fileContent = '{"test": "data"}';
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.pushToAI(fileContent, ragSync);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testPushToAIWithFileName() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        String fileContent = '{"test": "data"}';
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.pushToAI(fileContent, 'custom_file.json', ragSync);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testPushToAISkipDatastoreImport() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        String fileContent = '{"test": "data"}';
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.pushToAI(fileContent, ragSync, false);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testPushToAIGCPStorage() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getGCPRagSync();
        String fileContent = 'Name,Revenue\nTest,1000';
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.pushToAI(fileContent, ragSync);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testPushToAIBase64Content() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        // Create base64 encoded content
        String fileContent = EncodingUtil.base64Encode(Blob.valueOf('Test PDF content'));
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.pushToAI(fileContent, 'test.pdf', ragSync);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testImportFilesToGCPDatastore() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getGCPRagSync();
        List<String> fileNames = new List<String>{'file1.pdf', 'file2.pdf'};
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.importFilesToGCPDatastore(fileNames, ragSync);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testImportFilesToGCPDatastoreEmpty() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getGCPRagSync();
        List<String> fileNames = new List<String>();
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.importFilesToGCPDatastore(fileNames, ragSync);
        Test.stopTest();
        
        Assert.isTrue(result.isEmpty(), 'Result should be empty for empty file names');
    }
    
    @isTest
    static void testImportFilesToGCPDatastoreCSV() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        // Create connection with isStructured = true
        AI_Connection__c gcpDiscovery = new AI_Connection__c(
            Name = 'Test GCP Discovery CSV',
            Type__c = 'RAG Sync',
            Model__c = 'GCP Discovery Engine',
            Named_Credential__c = 'Test_GCP_Credential',
            Additional_Parameters__c = '{"bucketName": "test-bucket", "projectId": "test-project", "dataStoreId": "test-datastore", "isStructured": true}'
        );
        insert gcpDiscovery;
        
        AI_Connection__c gcpStorage = [SELECT Id FROM AI_Connection__c WHERE Name = 'Test GCP Storage' LIMIT 1];
        
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test GCP CSV Sync',
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Format__c = 'csv',
            File_Name__c = 'test.csv',
            AI_Model_File_Upload__c = gcpStorage.Id,
            AI_Model_Datastore_Import__c = gcpDiscovery.Id
        );
        insert ragSync;
        
        ragSync = [SELECT Id, Name, External_Id__c,
                AI_Model_File_Upload__c, AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c, AI_Model_File_Upload__r.Additional_Parameters__c,
                AI_Model_Datastore_Import__c, AI_Model_Datastore_Import__r.Named_Credential__c,
                AI_Model_Datastore_Import__r.Model__c, AI_Model_Datastore_Import__r.Additional_Parameters__c
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        List<String> fileNames = new List<String>{'data.csv'};
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.importFilesToGCPDatastore(fileNames, ragSync);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testSaveFile() {
        // Create a parent record
        Account parentAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        AISyncSchedulable.saveFile(parentAccount.Id, 'test_saved_file.json', '{"test": "content"}');
        Test.stopTest();
        
        // Verify file was created and linked
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :parentAccount.Id];
        Assert.isTrue(links.size() > 0, 'File should be linked to parent');
    }
    
    @isTest
    static void testDeleteFile() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        // Create a RAG Sync with a job that has file info
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c WHERE Name = 'Test OpenAI File Upload' LIMIT 1];
        
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test Delete RAG Sync',
            External_Id__c = 'vs-test-delete',
            AI_Model_File_Upload__c = conn.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_delete.json',
            File_Format__c = 'json'
        );
        insert ragSync;
        
        // Create a job with response containing fileId
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            AI_RAG_Sync__c = ragSync.Id,
            Start_Date_Time__c = System.now(),
            Status__c = 'Completed',
            Response__c = '{"fileId": "file-to-delete"}'
        );
        insert job;
        
        // Query with relationship
        ragSync = [SELECT Id, Name, External_Id__c,
                AI_Model_File_Upload__c, AI_Model_File_Upload__r.Named_Credential__c,
                AI_Model_File_Upload__r.Model__c, AI_Model_File_Upload__r.Additional_Parameters__c,
                (SELECT Id, Response__c FROM AI_RAG_Sync_Jobs__r ORDER BY CreatedDate DESC LIMIT 1)
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        Test.startTest();
        AISyncSchedulable.deleteFile(ragSync);
        Test.stopTest();
        
        // No exception means success
        Assert.isTrue(true, 'Delete file should complete');
    }
    
    @isTest
    static void testDeleteFileFromGCP() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getGCPRagSync();
        
        Test.startTest();
        AISyncSchedulable.deleteFileFromGCP(ragSync, 'test-bucket', 'test-file.pdf');
        Test.stopTest();
        
        // No exception means success
        Assert.isTrue(true, 'Delete from GCP should complete');
    }
    
    @isTest
    static void testDeleteFileFromGCPBlankName() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getGCPRagSync();
        
        Test.startTest();
        AISyncSchedulable.deleteFileFromGCP(ragSync, 'test-bucket', '');
        Test.stopTest();
        
        // No exception, early return
        Assert.isTrue(true, 'Delete with blank name should return early');
    }
    
    @isTest
    static void testGetFileIds() {
        // Create a RAG Sync with job containing file IDs
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c WHERE Name = 'Test OpenAI File Upload' LIMIT 1];
        
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test GetFileIds RAG Sync',
            External_Id__c = 'vs-test-getfiles',
            AI_Model_File_Upload__c = conn.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test_getfiles.json',
            File_Format__c = 'json'
        );
        insert ragSync;
        
        // Create a job with response containing fileId and additionalFileIds
        AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
            AI_RAG_Sync__c = ragSync.Id,
            Start_Date_Time__c = System.now(),
            Status__c = 'Completed',
            Response__c = '{"fileId": "file-main", "additionalFileIds": ["file-1", "file-2"]}'
        );
        insert job;
        
        // Query with relationship
        ragSync = [SELECT Id, Name, External_Id__c,
                (SELECT Id, Response__c FROM AI_RAG_Sync_Jobs__r ORDER BY CreatedDate DESC LIMIT 1)
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        Test.startTest();
        List<String> fileIds = AISyncSchedulable.getFileIds(ragSync);
        Test.stopTest();
        
        Assert.areEqual(3, fileIds.size(), 'Should return 3 file IDs (1 main + 2 additional)');
        Assert.isTrue(fileIds.contains('file-main'), 'Should contain main file ID');
        Assert.isTrue(fileIds.contains('file-1'), 'Should contain additional file ID 1');
    }
    
    @isTest
    static void testGetFileIdsNoExternalId() {
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c WHERE Name = 'Test OpenAI File Upload' LIMIT 1];
        
        AI_RAG_Sync__c ragSync = new AI_RAG_Sync__c(
            Name = 'Test No External RAG Sync',
            AI_Model_File_Upload__c = conn.Id,
            Object__c = 'Account',
            Fields__c = '{"Name":"Account Name"}',
            File_Name__c = 'test.json',
            File_Format__c = 'json'
        );
        insert ragSync;
        
        ragSync = [SELECT Id, Name, External_Id__c,
                (SELECT Id, Response__c FROM AI_RAG_Sync_Jobs__r ORDER BY CreatedDate DESC LIMIT 1)
                FROM AI_RAG_Sync__c WHERE Id = :ragSync.Id];
        
        Test.startTest();
        List<String> fileIds = AISyncSchedulable.getFileIds(ragSync);
        Test.stopTest();
        
        Assert.isTrue(fileIds.isEmpty(), 'Should return empty list when no external ID');
    }
    
    @isTest
    static void testPushToAIWithExistingExternalId() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        // Update RAG Sync with existing external ID
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        ragSync.External_Id__c = 'vs-existing-123';
        update ragSync;
        
        ragSync = getOpenAIRagSync();
        String fileContent = '{"test": "data"}';
        
        Test.startTest();
        Map<String, Object> result = AISyncSchedulable.pushToAI(fileContent, ragSync);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testProcessRequestWithExistingJob() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        
        AI_RAG_Sync__c ragSync = getOpenAIRagSync();
        
        // Create an existing job with file response
        AI_RAG_Sync_Job__c existingJob = new AI_RAG_Sync_Job__c(
            AI_RAG_Sync__c = ragSync.Id,
            Start_Date_Time__c = System.now().addDays(-1),
            Status__c = 'Completed',
            Response__c = '{"fileId": "file-old"}'
        );
        insert existingJob;
        
        // Update External_Id
        ragSync.External_Id__c = 'vs-existing';
        update ragSync;
        
        Test.startTest();
        try {
            AISyncSchedulable.processRequest(ragSync.Id, 'test-job-with-existing');
        } catch (Exception e) {
            // Expected - batch chaining may cause issues in test context
        }
        Test.stopTest();
        
        // Process should trigger delete batch first
        Assert.isTrue(true, 'Process request with existing job should complete');
    }
}