@isTest
public with sharing class JWTAuthenticationServiceTest implements HttpCalloutMock {
    
    public HttpResponse respond(HTTPRequest req) {
        System.assertEquals('POST', req.getMethod());

        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody('{"access_token":"TOKEN", "instance_url":"https://spoke-domain.my.salesforce.com", "error":"", "error_description":""}');
        res.setStatusCode(200);
        return res;
    }
    
    @testSetup
    private static void makeData(){
        ContentVersion cv = TestUtility.createContentVersion('spoke-key', true);
        ContentVersion u_cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
        AI_Connection__c aiModel = TestUtility.getConnection('GPTfy', false);
        aiModel.Additional_Parameters__c = JSON.serialize(new Map<String, Object>{
            'privateKeyFileId' => u_cv.ContentDocumentId, 'clientId' => 'SAMPLE_ID', 'authUrl' => 'https://spoke-domain.my.salesforce.com', 'tokenUrl' => 'https://spoke-domain.my.salesforce.com'           
        });
        insert aiModel;
    }
    
    @isTest
    private static void getAuthenticationDetailsTest(){
        AI_Connection__c aiModel = [SELECT Id, Additional_Parameters__c FROM AI_Connection__c LIMIT 1];
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new JWTAuthenticationServiceTest());
        Map<String, Object> results = JWTAuthenticationService.getAuthenticationDetails(aiModel);
        Test.stopTest();
        System.assert(results != null && !results.isEmpty());
    }
    
}