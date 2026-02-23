/**
 * @description Test class for AIResponsesApiCalloutUtility
 * This test class validates the functionality of AI API callout operations including file uploads,
 * vector store management, and AI response generation while ensuring proper error handling.
 * 
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 11-07-2025
 * @last modified by Piyush Chourasia
 */
@isTest
private class AIResponsesApiCalloutUtilityTest {
    
    /**
     * Test setup method to create necessary test data
     */
    @TestSetup
    static void makeData() {
        // Create test AI Connection record
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4',
            Named_Credential__c = 'Test_Credential'
        );
        insert aiConnection;
        
        // Create test AI Response record
        AI_Response__c aiResponse = new AI_Response__c(
            Vector_Store_Id__c = null,
            Thread_Id__c = null,
            Data_PII_Removed__c = 'Test extracted data'
        );
        insert aiResponse;
        
        // Create test ContentVersion for file upload testing
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test_file.txt',
            VersionData = Blob.valueOf('Test file content for upload')
        );
        insert cv;
    }
    
    /**
     * Mock HTTP callout class for successful API responses
     */
    private class MockHttpResponseSuccess implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;
        private String endpoint;
        
        public MockHttpResponseSuccess(Integer statusCode, String responseBody, String endpoint) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
            this.endpoint = endpoint;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * Mock HTTP callout class for error responses
     */
    private class MockHttpResponseError implements HttpCalloutMock {
        private Integer statusCode;
        private String errorMessage;
        
        public MockHttpResponseError(Integer statusCode, String errorMessage) {
            this.statusCode = statusCode;
            this.errorMessage = errorMessage;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error": {"message": "' + errorMessage + '"}}');
            return res;
        }
    }
    
    /**
     * Test successful file upload process
     */
    @isTest
    static void testUploadFiles_Success() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];
        
        // Setup mock response for successful file upload
        String mockResponse = '{"id": "file-123", "object": "file", "filename": "test_file.txt"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(200, mockResponse, 'files'));
        
        // Create wrapper with test data
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.cdIds = new Set<String>{cv.Id};
        wrapper.uploadedFileIds = new List<String>();
        
        Test.startTest();
        AIResponsesApiCalloutUtility.ResponseApiWrapper result = AIResponsesApiCalloutUtility.uploadFiles(wrapper);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result wrapper should not be null');
        Assert.isNotNull(result.uploadedFileIds, 'Uploaded file IDs should not be null');
        Assert.areEqual(1, result.uploadedFileIds.size(), 'Should have one uploaded file ID');
        Assert.areEqual('file-123', result.uploadedFileIds[0], 'File ID should match mock response');
    }
    
    /**
     * Test file upload with HTTP error response
     */
    @isTest
    static void testUploadFiles_HttpError() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];
        
        // Setup mock response for failed file upload
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseError(400, 'Invalid file format'));
        
        // Create wrapper with test data
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.cdIds = new Set<String>{cv.Id};
        
        Test.startTest();
        try {
            AIResponsesApiCalloutUtility.uploadFiles(wrapper);
            Assert.fail('Expected AIResponsesApiCalloutUtilityException to be thrown');
        } catch (AIResponsesApiCalloutUtility.AIResponsesApiCalloutUtilityException ex) {
            Assert.isTrue(ex.getMessage().contains('File Upload Failed'), 'Error message should contain file upload failure prefix');
            Assert.isTrue(ex.getMessage().contains('Invalid file format'), 'Error message should contain API error message');
        }
        Test.stopTest();
    }
    
    /**
     * Test successful vector store creation
     */
    @isTest
    static void testCreateVectorStore_Success() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        
        // Setup mock response for successful vector store creation
        String mockResponse = '{"id": "vs_123", "object": "vector_store", "name": "test_record_id"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(201, mockResponse, 'vector_stores'));
        
        // Create wrapper with test data
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.recordId = 'test_record_id';
        wrapper.uploadedFileIds = new List<String>{'file-123', 'file-456'};
        
        Test.startTest();
        AIResponsesApiCalloutUtility.ResponseApiWrapper result = AIResponsesApiCalloutUtility.createVectorStore(wrapper);
        wrapper.vectorStoreId = 'vs_123';
        wrapper.fileId = 'fileId';
        AIResponsesApiCalloutUtility.deleteFileFromVectorStore(wrapper);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result wrapper should not be null');
        Assert.areEqual('vs_123', result.vectorStoreId, 'Vector store ID should match mock response');
    }
    
    /**
     * Test vector store creation with no uploaded files
     */
    @isTest
    static void testCreateVectorStore_NoFiles() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        
        // Create wrapper with no uploaded files
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.recordId = 'test_record_id';
        wrapper.uploadedFileIds = new List<String>();
        
        Test.startTest();
        try {
            AIResponsesApiCalloutUtility.createVectorStore(wrapper);
            Assert.fail('Expected AIResponsesApiCalloutUtilityException to be thrown');
        } catch (AIResponsesApiCalloutUtility.AIResponsesApiCalloutUtilityException ex) {
            Assert.isTrue(ex.getMessage().contains('No uploaded file IDs available'), 'Error message should indicate no files available');
        }
        Test.stopTest();
    }
    
    /**
     * Test successful file addition to vector store
     */
    @isTest
    static void testAddFileToVectorStore_Success() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        
        // Setup mock response for successful file addition
        String mockResponse = '{"id": "vfile_123", "object": "vector_store.file", "vector_store_id": "vs_123"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(200, mockResponse, 'vector_stores'));
        
        // Create wrapper with test data
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.vectorStoreId = 'vs_123';
        wrapper.uploadedFileIds = new List<String>{'file-123'};
        AIResponsesApiCalloutUtility.ResponseApiWrapper result;
        Test.startTest();
        result = AIResponsesApiCalloutUtility.addFileToVectorStore(wrapper);
        
        Test.stopTest();
        System.assertNotEquals(result,NULL,'result is null');
    }
    
    /**
     * Test file status retrieval success
     */
    @isTest
    static void testGetFileStatus_Success() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        
        // Setup mock response for successful file status check
        String mockResponse = '{"id": "vfile_123", "status": "completed", "vector_store_id": "vs_123"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(200, mockResponse, 'vector_stores'));
        
        // Create wrapper with test data
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.vectorStoreId = 'vs_123';
        wrapper.fileId = 'vfile_123';
        
        Test.startTest();
        AIResponsesApiCalloutUtility.ResponseApiWrapper result = AIResponsesApiCalloutUtility.getFileStatus(wrapper);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result wrapper should not be null');
        Assert.areEqual('completed', result.fileStatus, 'File status should match mock response');
    }
    
    /**
     * Test successful AI response creation
     */
    @isTest
    static void testCreateResponses_Success() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c,Max_Tokens__c,Temperature__c,Additional_Parameters__c,Top_p__c FROM AI_Connection__c LIMIT 1];
        
        // Setup mock response for successful AI response creation
        String mockResponse = '{"id": "response_123", "object": "response", "content": "Test AI response"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(201, mockResponse, 'responses'));
        
        // Create wrapper with test data
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.vectorStoreId = 'vs_123';
        wrapper.promptCommand = 'Test prompt';
        wrapper.extractedData = 'Test extracted data';
        wrapper.previousResponseId = 'prev_response_123';
        
        Test.startTest();
        AIResponsesApiCalloutUtility.ResponseApiWrapper result = AIResponsesApiCalloutUtility.createResponses(wrapper);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result wrapper should not be null');
        Assert.areEqual(mockResponse, result.response, 'Response should match mock response');
        Assert.areEqual('response_123', result.previousResponseId, 'Previous response ID should be updated');
    }
    
    /**
     * Test successful file processing workflow
     */
    @isTest
    static void testProcessFileRequest_Success() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];
        
        // Setup mock responses for the complete workflow
        String fileUploadResponse = '{"id": "file-123", "object": "file", "filename": "test_file.txt"}';
        String vectorStoreResponse = '{"id": "vs_123", "object": "vector_store", "name": "test_record"}';
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(200, fileUploadResponse, 'files'));
        
        // Create wrapper with test data
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.recordId = 'test_record_id';
        wrapper.cdIds = new Set<String>{cv.Id};
        
        Test.startTest();
        AIResponsesApiCalloutUtility.ResponseApiWrapper result = AIResponsesApiCalloutUtility.processFileRequest(wrapper);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result wrapper should not be null');
        Assert.isNotNull(result.uploadedFileIds, 'Uploaded file IDs should not be null');
    }
    
    /**
     * Test file processing with exception handling
     */
    @isTest
    static void testProcessFileRequest_Exception() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];
        
        // Setup mock response for failed file upload
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseError(500, 'Internal server error'));
        
        // Create wrapper with test data
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.recordId = 'test_record_id';
        wrapper.cdIds = new Set<String>{cv.Id};
        
        Test.startTest();
        try {
            AIResponsesApiCalloutUtility.processFileRequest(wrapper);
            Assert.fail('Expected AIResponsesApiCalloutUtilityException to be thrown');
        } catch (AIResponsesApiCalloutUtility.AIResponsesApiCalloutUtilityException ex) {
            Assert.isTrue(ex.getMessage().contains('File Upload Failed'), 'Error message should contain appropriate failure prefix');
        }
        Test.stopTest();
    }
    
    /**
     * Test ResponseApiWrapper constructor and properties
     */
    @isTest
    static void testResponseApiWrapper_Properties() {
        Test.startTest();
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        
        // Test property setters and getters
        wrapper.recordId = 'test_record_id';
        wrapper.extractedData = 'test_extracted_data';
        wrapper.promptCommand = 'test_prompt';
        wrapper.cdIds = new Set<String>{'cv_123'};
        wrapper.uploadedFileIds = new List<String>{'file_123'};
        wrapper.vectorStoreId = 'vs_123';
        wrapper.responseId = 'response_123';
        wrapper.previousResponseId = 'prev_response_123';
        wrapper.response = 'test_response';
        wrapper.errors = new Set<String>{'error1'};
        wrapper.fileId = 'file_123';
        wrapper.fileStatus = 'completed';
        
        Test.stopTest();
        
        // Assertions
        Assert.areEqual('test_record_id', wrapper.recordId, 'Record ID should be set correctly');
        Assert.areEqual('test_extracted_data', wrapper.extractedData, 'Extracted data should be set correctly');
        Assert.areEqual('test_prompt', wrapper.promptCommand, 'Prompt command should be set correctly');
        Assert.areEqual(1, wrapper.cdIds.size(), 'CD IDs should be set correctly');
        Assert.areEqual(1, wrapper.uploadedFileIds.size(), 'Uploaded file IDs should be set correctly');
        Assert.areEqual('vs_123', wrapper.vectorStoreId, 'Vector store ID should be set correctly');
        Assert.areEqual('response_123', wrapper.responseId, 'Response ID should be set correctly');
        Assert.areEqual('prev_response_123', wrapper.previousResponseId, 'Previous response ID should be set correctly');
        Assert.areEqual('test_response', wrapper.response, 'Response should be set correctly');
        Assert.areEqual(1, wrapper.errors.size(), 'Errors should be set correctly');
        Assert.areEqual('file_123', wrapper.fileId, 'File ID should be set correctly');
        Assert.areEqual('completed', wrapper.fileStatus, 'File status should be set correctly');
    }
    
    /**
     * Test edge case with null values
     */
    @isTest
    static void testCreateVectorStore_NullFileIds() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        
        // Create wrapper with null uploaded file IDs
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.recordId = 'test_record_id';
        wrapper.uploadedFileIds = null;
        
        Test.startTest();
        try {
            AIResponsesApiCalloutUtility.createVectorStore(wrapper);
            Assert.fail('Expected AIResponsesApiCalloutUtilityException to be thrown');
        } catch (AIResponsesApiCalloutUtility.AIResponsesApiCalloutUtilityException ex) {
            Assert.isTrue(ex.getMessage().contains('No uploaded file IDs available'), 'Error message should indicate no files available');
        }
        Test.stopTest();
    }
    
    /**
     * Test bulk file upload scenario
     */
    @isTest
    static void testUploadFiles_BulkProcessing() {
        // Get test data
        AI_Connection__c aiConnection = [SELECT Id, Model__c, Named_Credential__c FROM AI_Connection__c LIMIT 1];
        
        // Create multiple ContentVersion records
        List<ContentVersion> cvList = new List<ContentVersion>();
        for (Integer i = 0; i < 3; i++) {
            cvList.add(new ContentVersion(
                Title = 'Test File ' + i,
                PathOnClient = 'test_file_' + i + '.txt',
                VersionData = Blob.valueOf('Test file content ' + i)
            ));
        }
        insert cvList;
        
        // Setup mock response for successful file uploads
        String mockResponse = '{"id": "file-123", "object": "file", "filename": "test_file.txt"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(200, mockResponse, 'files'));
        
        // Create wrapper with multiple file IDs
        Set<String> fileIds = new Set<String>();
        for (ContentVersion cv : cvList) {
            fileIds.add(cv.Id);
        }
        
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrapper = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrapper.aiModel = aiConnection;
        wrapper.cdIds = fileIds;
        wrapper.uploadedFileIds = new List<String>();
        
        Test.startTest();
        AIResponsesApiCalloutUtility.ResponseApiWrapper result = AIResponsesApiCalloutUtility.uploadFiles(wrapper);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result wrapper should not be null');
        Assert.areEqual(3, result.uploadedFileIds.size(), 'Should have three uploaded file IDs');
    }
}