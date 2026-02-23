@IsTest
private class AISFPublicURLGeneratorServiceTest {
    
    @TestSetup
    static void setupData() {
        // Create a ContentVersion record as prerequisite data
        ContentVersion cv = new ContentVersion(
            Title = 'Sample File',
            PathOnClient = 'samplefile.txt',
            VersionData = Blob.valueOf('Sample content')
        );
        insert cv;
        
        // Create FLSCheck records or other dependencies if required by FLSCheck.getInstance()
    }
    
    @IsTest
    static void testRunRequestWithValidData() {
        // Get the ContentVersion record inserted in @TestSetup
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];
        
        // Set up a request body with valid cvId
        AISalesforcePublicURLGeneratorService.RequestWrapper reqWrap = new AISalesforcePublicURLGeneratorService.RequestWrapper();
        reqWrap.cvId = cv.Id;
        
        // Set the mock request body
        RestContext.request = new RestRequest();
        RestContext.request.requestBody = Blob.valueOf(JSON.serialize(reqWrap));
        
        // Call the method
        AISalesforcePublicURLGeneratorService.ResponseWrapper response = AISalesforcePublicURLGeneratorService.runRequest();
        
        // Assert that a URL is generated and is not null
        System.assertNotEquals(null, response.fileUrl, 'File URL should not be null for a valid ContentVersion');
    }
    
    @IsTest
    static void testRunRequestWithInvalidData() {
        // Set up a request body with an invalid cvId
        AISalesforcePublicURLGeneratorService.RequestWrapper reqWrap = new AISalesforcePublicURLGeneratorService.RequestWrapper();
        reqWrap.cvId = 'InvalidId';
        
        // Set the mock request body
        RestContext.request = new RestRequest();
        RestContext.request.requestBody = Blob.valueOf(JSON.serialize(reqWrap));
        
        // Call the method and handle exceptions if any
        Test.startTest();
        AISalesforcePublicURLGeneratorService.ResponseWrapper response = AISalesforcePublicURLGeneratorService.runRequest();
        Test.stopTest();
        
        // Assert that the file URL is null when an invalid cvId is provided
        System.assertEquals(null, response.fileUrl, 'File URL should be null for an invalid ContentVersion');
    }
    
    @IsTest
    static void testRunRequestWithEmptyRequestBody() {
        // Set up an empty request body
        RestContext.request = new RestRequest();
        RestContext.request.requestBody = Blob.valueOf('');
        
        // Call the method
        Test.startTest();
        AISalesforcePublicURLGeneratorService.ResponseWrapper response = AISalesforcePublicURLGeneratorService.runRequest();
        Test.stopTest();
        
        // Assert that the file URL is null when no request body is provided
        System.assertEquals(null, response.fileUrl, 'File URL should be null for an empty request body');
    }
}