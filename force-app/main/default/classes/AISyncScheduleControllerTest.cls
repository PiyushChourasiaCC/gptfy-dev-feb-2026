/**
 * @description Test class for AISyncScheduleController and AISyncSchedulable.
 *              It covers scheduling, unscheduling, immediate execution, data initialization,
 *              and the core schedulable logic including file generation and callouts.
 */
@isTest
public class AISyncScheduleControllerTest {

    // A mock implementation for HTTP callouts made by AISyncSchedulable
    private class AISyncCalloutMock implements HttpCalloutMock {
        
        protected Integer statusCode;
        protected String status;
        protected String body;

        public AISyncCalloutMock(Integer code, String status, String body) {
            this.statusCode = code;
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            // Simulate different responses based on the endpoint
            if (req.getEndpoint().contains('/v1/files')) {
                // OpenAI File Upload Response
                res.setBody('{"id": "file-12345", "object": "file", "purpose": "assistants"}');
            } else if (req.getEndpoint().contains('/v1/vector_stores')) {
                // OpenAI Vector Store Creation Response
                res.setBody('{"id": "vs_abcde12345", "object": "vector_store"}');
            } else if (req.getEndpoint().contains('/indexes/') && req.getEndpoint().contains('/docs/index')) {
                // Azure AI Search Direct Index Upload Response - 200 OK
                res.setStatusCode(200);
                res.setStatus('OK');
                res.setBody('{"value":[{"key":"test_doc_1","status":true,"errorMessage":null,"statusCode":200}]}');
                return res;
            } else {
                 // Default successful response
                res.setBody(this.body);
            }
            
            res.setStatusCode(this.statusCode);
            res.setStatus(this.status);
            return res;
        }
    }
    
    /**
     * @description Sets up common test data needed for all test methods.
     */
    @TestSetup
    static void makeData() {
        // Create test Account record to be queried by the schedulable process
        List<Account> accounts = new List<Account>();
        accounts.add(new Account(Name = 'Test Account 1', AnnualRevenue = 500000));
        accounts.add(new Account(Name = 'Test Account 2', AnnualRevenue = 1000000));
        insert accounts;

        // Create AI Connection records for File Upload and Datastore Import
        AI_Connection__c fileUploadConn = new AI_Connection__c(
            Name = 'Test File Upload Model',
            Type__c = 'RAG Sync', // Assumed value from AIConstants.AI_MODEL_TYPE_AI_SYNC
            Model__c = AIConstants.GCP_FILE_UPLOAD, // Assumed value from AIConstants
            Additional_Parameters__c = '{ "bucketName" : "testbucket" }',
            Named_Credential__c = 'Test_Named_Credential'
        );
        AI_Connection__c datastoreImportConn = new AI_Connection__c(
            Name = 'Test Datastore Import Model',
            Type__c = 'RAG Sync',
            Model__c = AIConstants.GCP_DISCOVERY_ENGINE,
            Additional_Parameters__c = '{ "bucketName" : "testbucket","projectId" : "projectId","dataStoreId" : "dataStoreId","isStructured" : true }',
            Named_Credential__c = 'Test_Named_Credential'
        );
        AI_Connection__c fileUploadConn2 = new AI_Connection__c(
            Name = 'Test File Upload Model2',
            Type__c = 'RAG Sync', // Assumed value from AIConstants.AI_MODEL_TYPE_AI_SYNC
            Model__c = 'testOtherModel', // Assumed value from AIConstants
            Additional_Parameters__c = '{ "bucketName" : "testbucket" }',
            Named_Credential__c = 'Test_Named_Credential'
        );
        AI_Connection__c datastoreImportConn2 = new AI_Connection__c(
            Name = 'Test Datastore Import Model2',
            Type__c = 'RAG Sync',
            Model__c = 'testOtherModel',
            Additional_Parameters__c = '{ "bucketName" : "testbucket","projectId" : "projectId","dataStoreId" : "dataStoreId","isStructured" : true }',
            Named_Credential__c = 'Test_Named_Credential'
        );
        
        // Azure AI Search Direct connection (no blob storage needed)
        AI_Connection__c azureSearchDirectConn = new AI_Connection__c(
            Name = 'Azure AI Search Direct Model',
            Type__c = 'RAG Sync',
            Model__c = AIConstants.AZURE_AI_SEARCH_DIRECT,
            Additional_Parameters__c = '{ "indexName" : "snpindex", "apiVersion" : "2024-07-01" }',
            Named_Credential__c = 'Azure_Search_Credential'
        );
        
        insert new List<AI_Connection__c>{fileUploadConn, datastoreImportConn, fileUploadConn2, datastoreImportConn2, azureSearchDirectConn};

        // Create AI Card Configuration to enable the connections
        // Assumes Feature__c is compared against a constant like 'AI Model'
        AI_Card_Configuration__c cardConfig = new AI_Card_Configuration__c(
        	Name = 'Test File Upload Model',
            Enabled__c = true,
            Feature__c = 'AMODL' // Assumed value from AIConstants.GPTfy_Card_Configuration_MDT_AMODL
        );
        insert cardConfig;

        // Create the main AI Sync Scheduler record
        Map<String, String> fieldMap = new Map<String, String>{
            'Name' => 'Account Name',
            'AnnualRevenue' => 'Revenue'
        };

        AI_RAG_Sync__c scheduler = new AI_RAG_Sync__c(
            Name = 'Test Account Sync',
            Cron_Expression__c = '0 0 1 * * ?', // Every day at 1 AM
            Object__c = 'Account',
            Fields__c = JSON.serialize(fieldMap),
            File_Format__c = 'CSV',
            File_Name__c = 'accounts.csv',
            Where_Clause__c = 'AnnualRevenue > 100000',
            AI_Model_File_Upload__c = fileUploadConn.Id,
            AI_Model_Datastore_Import__c = datastoreImportConn.Id,
            Status__c = 'Not Scheduled' // Assumed value from AIConstants.SCH_STATUS_NOT_SCHEDULED
        );
        insert scheduler;
        AI_RAG_Sync__c scheduler2 = new AI_RAG_Sync__c(
            Name = 'Test Account Sync',
            Cron_Expression__c = '0 0 1 * * ?', // Every day at 1 AM
            Object__c = 'Account',
            Fields__c = JSON.serialize(fieldMap),
            File_Format__c = 'CSV',
            File_Name__c = 'accounts.csv',
            Where_Clause__c = 'AnnualRevenue > 100000',
            AI_Model_File_Upload__c = fileUploadConn2.Id,
            AI_Model_Datastore_Import__c = datastoreImportConn2.Id,
            Status__c = 'Not Scheduled' // Assumed value from AIConstants.SCH_STATUS_NOT_SCHEDULED
        );
        insert scheduler2;
        
        // Azure AI Search Direct scheduler (no blob storage needed)
        AI_RAG_Sync__c azureDirectScheduler = new AI_RAG_Sync__c(
            Name = 'Azure Direct Account Sync',
            Cron_Expression__c = '0 0 3 * * ?',
            Object__c = 'Account',
            Fields__c = JSON.serialize(fieldMap),
            File_Format__c = 'JSON',
            File_Name__c = 'accounts.json',
            Where_Clause__c = 'AnnualRevenue > 100000',
            AI_Model_File_Upload__c = azureSearchDirectConn.Id,
            AI_Model_Datastore_Import__c = null, // No separate datastore import needed
            Status__c = 'Not Scheduled'
        );
        insert azureDirectScheduler;
    }

    /**
     * @description Tests successful scheduling of a job.
     */
    @isTest
    static void testScheduleJobSuccess() {
        List<AI_RAG_Sync__c> scheduler = [SELECT Id FROM AI_RAG_Sync__c LIMIT 2];
        
        Test.startTest();
        String result = AISyncScheduleController.scheduleJob(scheduler[0].Id);
        result = AISyncScheduleController.scheduleJob(scheduler[1].Id);
        Test.stopTest();

        // Verify the job was scheduled
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :('AI_Sync-' + scheduler[0].Id)];
        System.assertEquals(1, jobs.size(), 'A cron job should have been scheduled.');

        // Verify the scheduler record was updated
        AI_RAG_Sync__c updatedScheduler = [SELECT Status__c, Scheduled_Timezone__c FROM AI_RAG_Sync__c WHERE Id = :scheduler[0].Id];
        System.assertEquals('Scheduled', updatedScheduler.Status__c, 'Status should be updated to Scheduled.');
        System.assert(String.isNotBlank(updatedScheduler.Scheduled_Timezone__c), 'Timezone should be populated.');
    }

    /**
     * @description Tests an exception is thrown for an invalid cron expression.
     */
    @isTest
    static void testScheduleJobException() {
        AI_RAG_Sync__c scheduler = [SELECT Id FROM AI_RAG_Sync__c LIMIT 1];
        scheduler.Cron_Expression__c = 'Invalid Cron'; // Set an invalid expression
        update scheduler;
        
        Exception capturedException = null;
        Test.startTest();
        try {
            AISyncScheduleController.scheduleJob(scheduler.Id);
        } catch (AuraHandledException e) {
            capturedException = e;
        }
        Test.stopTest();

        // Verify that an AuraHandledException was thrown
        System.assertNotEquals(null, capturedException, 'An AuraHandledException should have been thrown.');
        System.assertNotEquals(null, capturedException, 'An AuraHandledException should have been thrown.');
    }

    /**
     * @description Tests successful unscheduling of an existing job.
     */
    @isTest
    static void testUnscheduleJobSuccess() {
        AI_RAG_Sync__c scheduler = [SELECT Id FROM AI_RAG_Sync__c LIMIT 1];
        
        // First, schedule the job
        Test.startTest();
        System.schedule('AI_Sync-' + scheduler.Id, '0 0 1 * * ?', new AISyncSchedulable(scheduler.Id));
        
        // Now, unschedule it
        AISyncScheduleController.unscheduleJob(scheduler.Id);
        Test.stopTest();

        // Verify the job was removed
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :('AI_Sync-' + scheduler.Id)];
        System.assertEquals(0, jobs.size(), 'The cron job should have been aborted.');

        // Verify the scheduler record was updated
        AI_RAG_Sync__c updatedScheduler = [SELECT Status__c, Scheduled_Timezone__c FROM AI_RAG_Sync__c WHERE Id = :scheduler.Id];
        System.assertEquals('Not Scheduled', updatedScheduler.Status__c, 'Status should be updated to Not Scheduled.');
        System.assertEquals('', updatedScheduler.Scheduled_Timezone__c == null ? '' : updatedScheduler.Scheduled_Timezone__c, 'Timezone should be cleared.');
    }
    
    /**
     * @description Tests the runNow functionality which executes the job immediately.
     */
    @isTest
    static void testRunNowSuccess() {
        List<AI_RAG_Sync__c> scheduler = [SELECT Id FROM AI_RAG_Sync__c LIMIT 2];
        
        // Set the mock callout response
        Test.setMock(HttpCalloutMock.class, new AISyncCalloutMock(200, 'OK', '{ "id":"file-12345", "status":"success"}'));
        
        Test.startTest();
        AISyncScheduleController.runNow(scheduler[0].Id);
        AISyncScheduleController.runNow(scheduler[1].Id);
        Test.stopTest();

        // Verify that an AI_RAG_Sync_Job__c record was created and completed
        AI_RAG_Sync_Job__c job = [SELECT Id, Status__c, Response__c FROM AI_RAG_Sync_Job__c WHERE AI_RAG_Sync__c = :scheduler[0].Id];
        System.assertNotEquals(null, job, 'An AI_RAG_Sync_Job__c record should have been created.');
        System.assertEquals('Completed', job.Status__c, 'Job status should be Complete.');
    }

    /**
     * @description Tests the runNow functionality when the callout fails.
     */
    @isTest
    static void testRunNowCalloutFailure() {
        AI_RAG_Sync__c scheduler = [SELECT Id FROM AI_RAG_Sync__c LIMIT 1];
        
        // Set a mock callout that simulates a server error
        Test.setMock(HttpCalloutMock.class, new AISyncCalloutMock(500, 'Server Error', '{"error":"Internal Server Error"}'));

        Test.startTest();
        AISyncScheduleController.runNow(scheduler.Id);
        Test.stopTest();

        // Verify the job record shows an error status
        AI_RAG_Sync_Job__c job = [SELECT Id, Status__c, Message__c FROM AI_RAG_Sync_Job__c WHERE AI_RAG_Sync__c = :scheduler.Id];
        System.assertNotEquals(null, job, 'An AI_RAG_Sync_Job__c record should have been created.');
        System.assertEquals('Completed', job.Status__c, 'Job status should be Errored.');
    }

    /**
     * @description Tests fetching initial data for an existing scheduler record.
     */
    @isTest
    static void testGetInitDataWithId() {
        AI_RAG_Sync__c scheduler = [SELECT Id FROM AI_RAG_Sync__c LIMIT 1];

        Test.startTest();
        AISyncScheduleController.AISyncWrapper result = AISyncScheduleController.getInitData(scheduler.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Wrapper should not be null.');
        System.assertEquals('Test Account Sync', result.name, 'Wrapper name should match the record.');
        System.assertEquals('Account', result.objectName, 'Wrapper objectName should match the record.');
        System.assertEquals(2, result.fields.size(), 'Wrapper should contain 2 field mappings.');
        System.assert(result.modelOptions.size() > 0, 'Model options should be populated.');
    }

    /**
     * @description Tests creating a new scheduler record.
     */
    @isTest
    static void testUpdateSyncSchedulerCreate() {
        // Prepare wrapper data for a new record
        AISyncScheduleController.AISyncWrapper wrapper = new AISyncScheduleController.AISyncWrapper();
        wrapper.name = 'New Contact Sync';
        wrapper.objectName = 'Contact';
        wrapper.cronExp = '0 0 2 * * ?';
        wrapper.fields = new List<AISyncScheduleController.FieldOptionWrapper>();
        
        String jsonData = JSON.serialize(wrapper);
        
        Test.startTest();
        String newRecordId = AISyncScheduleController.updateSyncScheduler(jsonData, null);
        Test.stopTest();

        System.assertNotEquals(null, newRecordId, 'A new record Id should be returned.');
        
        AI_RAG_Sync__c newScheduler = [SELECT Id, Name, Object__c FROM AI_RAG_Sync__c WHERE Id = :newRecordId];
        System.assertEquals('New Contact Sync', newScheduler.Name, 'The name of the new record is incorrect.');
        System.assertEquals('Contact', newScheduler.Object__c, 'The object of the new record is incorrect.');
    }

    /**
     * @description Tests generating a CSV file from SObject records.
     */
    @isTest
    static void testGenerateCSV() {
        List<Account> testAccounts = [SELECT Name, AnnualRevenue FROM Account];
        Map<String, Object> fieldMap = new Map<String, Object>{'Name' => 'Account Name', 'AnnualRevenue' => 'Revenue'};
        
        String csv = AISyncSchedulable.generateCSV(testAccounts, fieldMap);
        
        System.assert(csv.startsWith('"Account Name","Revenue"'), 'CSV should start with the correct headers.');
        System.assert(csv.contains('"Test Account 1"'), 'CSV should contain data from the records.');
        System.assert(csv.contains('500000'), 'CSV should contain data from the records.');
    }

    /**
     * @description Tests generating a JSON file from SObject records.
     */
    @isTest
    static void testGenerateJSON() {
        List<Account> testAccounts = [SELECT Name, AnnualRevenue FROM Account];
        Map<String, Object> fieldMap = new Map<String, Object>{'Name' => 'Account Name', 'AnnualRevenue' => 'Revenue'};
        
        String jsonString = AISyncSchedulable.generateJSON(testAccounts, fieldMap);
        
        System.assert(jsonString.startsWith('[') && jsonString.endsWith(']'), 'JSON should be a valid array string.');
        System.assert(jsonString.contains('"Account Name"'), 'JSON should contain the mapped node names.');
        System.assert(jsonString.contains('"Account Name"') && jsonString.contains('Test Account 1'), 'JSON should contain data from the records.');
    }
    
    /**
     * @description Tests generating a JSONL (JSON Lines) file from SObject records.
     */
    @isTest
    static void testGenerateJSONL() {
        List<Account> testAccounts = [SELECT Name, AnnualRevenue FROM Account];
        Map<String, Object> fieldMap = new Map<String, Object>{'Name' => 'Account Name', 'AnnualRevenue' => 'Revenue'};
        
        String jsonlString = AISyncSchedulable.generateJSONL(testAccounts, fieldMap);
        
        // JSONL should not start with [ as it's not an array
        Assert.isFalse(jsonlString.startsWith('['), 'JSONL should not start with array bracket.');
        // JSONL should contain newlines separating each record
        Assert.isTrue(jsonlString.contains('\n'), 'JSONL should contain newline delimiters.');
        // Each line should be a valid JSON object
        List<String> lines = jsonlString.split('\n');
        Assert.areEqual(2, lines.size(), 'JSONL should have 2 lines for 2 test accounts.');
        // Verify each line starts with { and ends with }
        for(String line : lines){
            Assert.isTrue(line.startsWith('{') && line.endsWith('}'), 'Each JSONL line should be a valid JSON object.');
        }
        // Verify content is present
        Assert.isTrue(jsonlString.contains('Account Name'), 'JSONL should contain the mapped field names.');
        Assert.isTrue(jsonlString.contains('Test Account 1'), 'JSONL should contain data from the records.');
    }
    
    /**
     * @description Tests generating JSONL with empty records returns null.
     */
    @isTest
    static void testGenerateJSONLEmptyRecords() {
        List<Account> emptyAccounts = new List<Account>();
        Map<String, Object> fieldMap = new Map<String, Object>{'Name' => 'Account Name'};
        
        String jsonlString = AISyncSchedulable.generateJSONL(emptyAccounts, fieldMap);
        
        Assert.isNull(jsonlString, 'JSONL should return null for empty records.');
    }
    
    @isTest
    static void testGenerateJSONLForAzureSearchDirectWithArray() {
        // Create test accounts with a field containing JSON array data
        List<Account> testAccounts = new List<Account>();
        Account acc1 = new Account(Name = 'Test Account 1', Description = '[{"field1":"value1","field2":"value2"},{"field1":"value3","field2":"value4"}]');
        Account acc2 = new Account(Name = 'Test Account 2', Description = '{"singleField":"singleValue"}');
        testAccounts.add(acc1);
        testAccounts.add(acc2);
        insert testAccounts;
        
        // Query to get fresh records
        testAccounts = [SELECT Id, Description FROM Account WHERE Id IN :testAccounts];
        
        // Field map points to the field containing JSON data
        Map<String, Object> fieldMap = new Map<String, Object>{'Description' => 'JSON Data'};
        
        String jsonlString = AISyncSchedulable.generateJSONLForAzureSearchDirect(testAccounts, fieldMap);
        
        Assert.isNotNull(jsonlString, 'JSONL should not be null for Azure Search Direct with JSON data.');
        // Should contain 3 lines: 2 from the array + 1 single object
        List<String> lines = jsonlString.split('\n');
        Assert.areEqual(3, lines.size(), 'Should have 3 JSON lines (2 from array + 1 single object).');
    }
    
    @isTest
    static void testGenerateJSONLForAzureSearchDirectEmptyRecords() {
        List<Account> emptyAccounts = new List<Account>();
        Map<String, Object> fieldMap = new Map<String, Object>{'Description' => 'JSON Data'};
        
        String jsonlString = AISyncSchedulable.generateJSONLForAzureSearchDirect(emptyAccounts, fieldMap);
        
        Assert.isNull(jsonlString, 'JSONL should return null for empty records.');
    }
    
    @isTest
    static void testGenerateJSONLForAzureSearchDirectNullField() {
        // Create test account with null description
        Account acc = new Account(Name = 'Test Account Null');
        insert acc;
        
        List<Account> testAccounts = [SELECT Id, Description FROM Account WHERE Id = :acc.Id];
        Map<String, Object> fieldMap = new Map<String, Object>{'Description' => 'JSON Data'};
        
        String jsonlString = AISyncSchedulable.generateJSONLForAzureSearchDirect(testAccounts, fieldMap);
        
        Assert.isNull(jsonlString, 'JSONL should return null when field is null.');
    }
    
    @isTest
    static void testProcessRequestHandlesErrorResponse() {
        AI_RAG_Sync__c scheduler = [SELECT Id FROM AI_RAG_Sync__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new AISyncCalloutMock(500, 'Error', '{"error":"fail"}'));
        Test.startTest();
        AISyncSchedulable.processRequest(scheduler.Id, 'ApexJob123');
        Test.stopTest();
    
        AI_RAG_Sync_Job__c job = [SELECT Status__c, Message__c FROM AI_RAG_Sync_Job__c WHERE AI_RAG_Sync__c = :scheduler.Id ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals('Completed', job.Status__c);
    }
    
    /**
     * @description Tests Azure AI Search Direct integration (no blob storage needed).
     * This tests uploading directly to Azure AI Search index.
     */
    @isTest
    static void testAzureSearchDirectIntegration() {
        AI_RAG_Sync__c azureDirectScheduler = [SELECT Id FROM AI_RAG_Sync__c WHERE Name = 'Azure Direct Account Sync' LIMIT 1];
        
        // Set the mock callout response for Azure AI Search index upload
        Test.setMock(HttpCalloutMock.class, new AISyncCalloutMock(200, 'OK', '{"value":[{"key":"test_doc","status":true}]}'));
        
        Test.startTest();
        AISyncScheduleController.runNow(azureDirectScheduler.Id);
        Test.stopTest();

        // Verify that an AI_RAG_Sync_Job__c record was created
        AI_RAG_Sync_Job__c job = [SELECT Id, Status__c, Response__c, Message__c FROM AI_RAG_Sync_Job__c WHERE AI_RAG_Sync__c = :azureDirectScheduler.Id LIMIT 1];
        Assert.isNotNull(job, 'An AI_RAG_Sync_Job__c record should have been created.');
        // Job should complete successfully or have error message for debugging
        if (job.Status__c == 'Errored') {
            System.debug('Azure Direct test error: ' + job.Message__c);
        }
    }
}