@isTest
public class AIAssistantApiCalloutUtilityTest {

    @TestSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        Account testAccount = TestUtility.getAccount(true);
        Contentversion cv = TestUtility.getContentversion('Test', 'Test', 'Test', true);
    }

@IsTest
    static void testProcessFileRequest() {
        AI_Connection__c conn = [SELECT Id, Name, Version__c, Named_Credential__c,Temperature__c,Top_p__c FROM AI_Connection__c WHERE Name = 'GPTfy' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        ContentVersion cv = [SELECT Id,ContentDocumentId FROM ContentVersion WHERE Title = 'Test' LIMIT 1];
        AIAssistantApiCalloutUtility.AssistantWrapper wrap = new AIAssistantApiCalloutUtility.AssistantWrapper();
        wrap.recordId = testAccount.Id;
        wrap.aiModel = conn;
        wrap.extractedData = 'test';
        wrap.cdIds = new List<String>{cv.ContentDocumentId};
        String responseBody = '{"id": "vcId", "status": "succeeded"}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(responseBody));
        Test.startTest();
        wrap = AIAssistantApiCalloutUtility.processFileRequest(wrap);
        Test.stopTest();
        System.Assert(wrap != NULL);
    }


@IsTest
    static void testGetAnalyzeResult() {
        AI_Connection__c conn = [SELECT Id, Name, Version__c, Named_Credential__c,Temperature__c,Top_p__c FROM AI_Connection__c WHERE Name = 'GPTfy' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = [SELECT Id,ContentDocumentId FROM ContentVersion WHERE Title = 'Test' LIMIT 1];
        AIAssistantApiCalloutUtility.AssistantWrapper wrap = new AIAssistantApiCalloutUtility.AssistantWrapper();
        wrap.recordId = testAccount.Id;
        wrap.aiModel = conn;
        wrap.extractedData = 'test';
        wrap.threadId = 'test';
        wrap.promptCommand = 'test';
        wrap.vectorStoreId = 'test';
        wrap.uploadedFileId = 'test';
        wrap.assistantId = 'test';
        wrap.messageId = 'test';
        wrap.cdIds = new List<String>{cv.ContentDocumentId};
        String responseBody = '{"data": [{ "content" : [{ "text" : { "value": "This is test result" }}] }], "status": "completed"}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(responseBody));
        Test.startTest();
        wrap = AIAssistantApiCalloutUtility.getAnalyzeResult(wrap);
        Test.stopTest();
        System.Assert(wrap != NULL);
    }
}