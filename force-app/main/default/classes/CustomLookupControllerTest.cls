/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 12-14-2023
* @last modified by  : Adarsh Sharma
**/
@isTest
public class CustomLookupControllerTest {
   
    @testSetup
    public static void makeData(){
        Account acc = TestUtility.getAccount(true);
        AI_Response_Mapping__c responseMapping = TestUtility.createResponseMapping('TestResponse',true);
    }

    @isTest
    public static void testGetRecords(){
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Test.startTest();
        List<sObject> records = CustomLookupController.getRecords('Account', 'Name', acc.Name);
        Test.stopTest();
        System.Assert(records != null);
    }

    @isTest
    public static void testGetRecordsWithoutSearchKey(){
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Test.startTest();
        List<sObject> records = CustomLookupController.getRecords('Account', 'Name', null);
        Test.stopTest();
        System.Assert(records != null);
    }

    @isTest
    public static void testGetPicklistValues(){
        Test.startTest();
        map<String, String> picklistValues = CustomLookupController.getPicklistValues('Account', 'Industry');
        Test.stopTest();
        System.Assert(picklistValues != null);
    }

    @isTest
    public static void testGetsobjectMappingFields(){
        Test.startTest();
        map<String, String> mapsobjectMappingFields = CustomLookupController.getsobjectMappingFields(CustomLookupController.NAMESPACE+'AI_Response__c', CustomLookupController.NAMESPACE+'Response_Mapping');
        Test.stopTest();
        System.Assert(mapsobjectMappingFields != null);
    }

    @isTest
    public static void testCreateMetadataRecords(){
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        MetadataService metaDataService = new MetadataService();
        Test.startTest(); 
        Map<String, Object> mapParams = new Map<String, Object>();
        mapParams.put('name','Test');
        mapParams.put('Description__c', 'test');
        List<String> metadataFields = new List<String>();
        metadataFields.add('Name');
       // metadataFields.add('Sequence__c');
        Map<String,String> mapResponseLineMap = new Map<String,String>();
        mapResponseLineMap.put('Sequence__c', '1');
        CustomLookupController.createResponseMapping(metadataFields, mapParams, mapResponseLineMap);
        Test.stopTest();
        System.Assert(metaDataService != null);
    }
    
    @isTest
    public static void testExistsMetadataRecord(){
        Test.setMock(WebServiceMock.class, new MetadataAPIMockHttpResponseGenerator());
        MetadataService metaDataService = new MetadataService();
        Boolean isError = false;
        Test.startTest(); 
        try{
            Map<String, Object> mapParams = new Map<String, Object>();
        	mapParams.put('name','TestResponse');
        	mapParams.put('Description__c', 'test');
            
            CustomLookupController.createResponseMapping(new List<String>(mapParams.keyset()), mapParams,new Map<String,String>());
        }catch(Exception e){
            isError = true;
        }
        Test.stopTest();
        System.assert(isError);
    }

}