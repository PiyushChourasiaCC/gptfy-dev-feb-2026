/**
 * @description Test class for AIAgenticChatAPIService
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AIAgenticChatAPIServiceTest {
    
    private static final String NAMED_CREDENTIAL = 'TestOpenAI';
    
    /**
     * Mock class for successful file upload response
     */
    private class MockFileUploadSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody('{"id": "file-abc123", "object": "file", "purpose": "assistants"}');
            return resp;
        }
    }
    
    /**
     * Mock class for successful vector store creation
     */
    private class MockVectorStoreSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            resp.setStatus('Created');
            
            if (req.getEndpoint().contains('/v1/files')) {
                resp.setBody('{"id": "file-abc123", "object": "file"}');
            } else if (req.getEndpoint().contains('/v1/vector_stores')) {
                resp.setBody('{"id": "vs-xyz789", "object": "vector_store"}');
            }
            return resp;
        }
    }
    
    /**
     * Mock class for error response
     */
    private class MockErrorResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setStatus('Bad Request');
            resp.setBody('{"error": {"message": "Invalid request"}}');
            return resp;
        }
    }
    
    /**
     * Multi-request mock to handle different endpoints
     */
    private class MockMultiRequestSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            
            String endpoint = req.getEndpoint();
            if (endpoint.contains('/v1/files')) {
                resp.setBody('{"id": "file-test123", "object": "file"}');
            } else if (endpoint.contains('/v1/vector_stores') && req.getMethod() == 'DELETE') {
                resp.setBody('{"id": "vs-deleted", "deleted": true}');
            } else if (endpoint.contains('/v1/vector_stores') && endpoint.contains('/files')) {
                resp.setBody('{"id": "vsf-123", "object": "vector_store.file"}');
            } else if (endpoint.contains('/v1/vector_stores')) {
                resp.setBody('{"id": "vs-newstore", "object": "vector_store"}');
            }
            return resp;
        }
    }
    
    private static AIAgenticChatController.FileWrapper createTestFile(String fileName, String mimeType) {
        AIAgenticChatController.FileWrapper fw = new AIAgenticChatController.FileWrapper();
        fw.fileName = fileName;
        fw.mimeType = mimeType;
        fw.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Test file content'));
        fw.fileSize = 100;
        return fw;
    }
    
    @isTest
    static void testUploadSingleFileSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockFileUploadSuccess());
        AIAgenticChatController.FileWrapper file = createTestFile('test.pdf', 'application/pdf');
        
        Test.startTest();
        String fileId = AIAgenticChatAPIService.uploadSingleFile(file, NAMED_CREDENTIAL, 'assistants');
        Test.stopTest();
        
        Assert.areEqual('file-abc123', fileId, 'File ID should match');
    }
    
    @isTest
    static void testUploadSingleFileError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());
        AIAgenticChatController.FileWrapper file = createTestFile('test.pdf', 'application/pdf');
        
        Test.startTest();
        try {
            AIAgenticChatAPIService.uploadSingleFile(file, NAMED_CREDENTIAL, 'assistants');
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreateVectorStoreSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockVectorStoreSuccess());
        List<String> fileIds = new List<String>{'file-123', 'file-456'};
        
        Test.startTest();
        String vectorStoreId = AIAgenticChatAPIService.createVectorStore(fileIds, NAMED_CREDENTIAL);
        Test.stopTest();
        
        Assert.areEqual('vs-xyz789', vectorStoreId, 'Vector store ID should match');
    }
    
    @isTest
    static void testCreateVectorStoreEmptyFileIds() {
        Test.startTest();
        try {
            AIAgenticChatAPIService.createVectorStore(new List<String>(), NAMED_CREDENTIAL);
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isTrue(e.getMessage().contains('No uploaded file IDs'), 'Should contain correct error');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreateVectorStoreNullFileIds() {
        Test.startTest();
        try {
            AIAgenticChatAPIService.createVectorStore(null, NAMED_CREDENTIAL);
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isTrue(e.getMessage().contains('No uploaded file IDs'), 'Should contain correct error');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreateVectorStoreError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());
        List<String> fileIds = new List<String>{'file-123'};
        
        Test.startTest();
        try {
            AIAgenticChatAPIService.createVectorStore(fileIds, NAMED_CREDENTIAL);
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testAddFileToVectorStoreSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockMultiRequestSuccess());
        List<String> fileIds = new List<String>{'file-123', 'file-456'};
        
        Test.startTest();
        AIAgenticChatAPIService.addFileToVectorStore(fileIds, NAMED_CREDENTIAL, 'vs-existing');
        Test.stopTest();
        
        // No exception means success
        Assert.isTrue(true, 'Method should complete without exception');
    }
    
    @isTest
    static void testAddFileToVectorStoreEmptyFileIds() {
        Test.startTest();
        try {
            AIAgenticChatAPIService.addFileToVectorStore(new List<String>(), NAMED_CREDENTIAL, 'vs-123');
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isTrue(e.getMessage().contains('No uploaded file IDs'), 'Should contain correct error');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testAddFileToVectorStoreError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());
        List<String> fileIds = new List<String>{'file-123'};
        
        Test.startTest();
        try {
            AIAgenticChatAPIService.addFileToVectorStore(fileIds, NAMED_CREDENTIAL, 'vs-123');
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteVectorStoreSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockMultiRequestSuccess());
        
        Test.startTest();
        AIAgenticChatAPIService.deleteVectorStore(NAMED_CREDENTIAL, 'vs-todelete');
        Test.stopTest();
        
        // No exception means success
        Assert.isTrue(true, 'Method should complete without exception');
    }
    
    @isTest
    static void testDeleteVectorStoreError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());
        
        Test.startTest();
        try {
            AIAgenticChatAPIService.deleteVectorStore(NAMED_CREDENTIAL, 'vs-123');
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testUploadFilesAndCreateVectorStoreSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockMultiRequestSuccess());
        List<AIAgenticChatController.FileWrapper> files = new List<AIAgenticChatController.FileWrapper>{
            createTestFile('doc.pdf', 'application/pdf'),
            createTestFile('image.png', 'image/png')
        };
        
        Test.startTest();
        AIAgenticChatController.ResponseWrapper result = 
            AIAgenticChatAPIService.uploadFilesAndCreateVectorStore(files, NAMED_CREDENTIAL);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.vectorStroreId, 'Vector store ID should not be null');
        Assert.isTrue(result.uploadedFileIds.size() > 0, 'Should have uploaded file IDs');
    }
    
    @isTest
    static void testUploadFilesToVectorStoreSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockMultiRequestSuccess());
        List<AIAgenticChatController.FileWrapper> files = new List<AIAgenticChatController.FileWrapper>{
            createTestFile('doc.pdf', 'application/pdf')
        };
        
        Test.startTest();
        AIAgenticChatController.ResponseWrapper result = 
            AIAgenticChatAPIService.uploadFilesToVectorStore(files, NAMED_CREDENTIAL, 'vs-existing');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual('vs-existing', result.vectorStroreId, 'Vector store ID should match');
    }
    
    @isTest
    static void testUploadFilesWithImageFiles() {
        Test.setMock(HttpCalloutMock.class, new MockMultiRequestSuccess());
        List<AIAgenticChatController.FileWrapper> files = new List<AIAgenticChatController.FileWrapper>{
            createTestFile('photo.jpg', 'image/jpeg'),
            createTestFile('screenshot.png', 'image/png'),
            createTestFile('animation.gif', 'image/gif'),
            createTestFile('modern.webp', 'image/webp')
        };
        
        Test.startTest();
        AIAgenticChatController.ResponseWrapper result = 
            AIAgenticChatAPIService.uploadFilesAndCreateVectorStore(files, NAMED_CREDENTIAL);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.imageFileIds.size() > 0, 'Should have image file IDs');
    }
    
    @isTest
    static void testUploadFilesAndCreateVectorStoreError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());
        List<AIAgenticChatController.FileWrapper> files = new List<AIAgenticChatController.FileWrapper>{
            createTestFile('doc.pdf', 'application/pdf')
        };
        
        Test.startTest();
        try {
            AIAgenticChatAPIService.uploadFilesAndCreateVectorStore(files, NAMED_CREDENTIAL);
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testUploadFilesToVectorStoreError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());
        List<AIAgenticChatController.FileWrapper> files = new List<AIAgenticChatController.FileWrapper>{
            createTestFile('doc.pdf', 'application/pdf')
        };
        
        Test.startTest();
        try {
            AIAgenticChatAPIService.uploadFilesToVectorStore(files, NAMED_CREDENTIAL, 'vs-123');
            Assert.fail('Should throw exception');
        } catch (AIAgenticChatController.AIAgenticChatControllerException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
}