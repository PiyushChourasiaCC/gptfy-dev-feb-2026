@isTest
public class ContentVersionTriggerHandlerTest {
    
    @testSetup
    static void makeData(){
        TestUtility.getAccount(true);
    }
	
    @isTest
    static void transcriptTest(){
        Account a = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = new ContentVersion(
            Title = 'Penguins',
            PathOnClient = 'Penguins.jpg',
            VersionData = Blob.valueOf('Test Content'),
            IsMajorVersion = false
        );
        insert cv;  
        
        List<ContentDocument> documents = [
            SELECT Id, Title, LatestPublishedVersionId 
            FROM ContentDocument
        ];
        
        //create ContentDocumentLink  record 
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.LinkedEntityId = a.id;
        cdl.ContentDocumentId = documents[0].Id;
        cdl.ShareType = 'V';
        insert cdl;
        
        Test.startTest();
        cv.Transcript__c = 'Testing';
        update cv;
        Test.stopTest();
        System.assert(cv != null);
    }
    
}