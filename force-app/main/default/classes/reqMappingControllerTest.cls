/**
* @description       : 
* @author            : Sohit Sharma
* @group             : Plumcloud Labs
* @last modified on  : 11-03-2024
* @last modified by  : Sohit Sharma
**/
@isTest
public with sharing class reqMappingControllerTest {
    
    @testSetup
    static void makeData(){
        TestUtility.createRequestMapping('test',true);
    }
    
	@isTest
    public static void getRecords(){
        Request_Mapping__c reqMapping = [Select Id,Name from Request_Mapping__c where Name='test'];
        Test.startTest();
        List<sObject> recList1 = reqMappingController.getRecords(NULL);
        List<sObject> recList2 = reqMappingController.getRecords(reqMapping.Name);
        Test.stopTest();
        System.Assert(recList1 != null);
        System.Assert(recList2 != null);
    }
    
    @isTest
    public static void getFields(){
        String NAMESPACE = reqMappingController.NAMESPACE;
        Test.startTest();
        Map<String, String> mapRec = reqMappingController.getFields(NAMESPACE+'AI_Prompt_Scheduler__c',NAMESPACE+'Scheduler_Related_Fields');
        Test.stopTest();
        System.Assert(mapRec != null); 
    }
    
    @isTest
    public static void createRequestMapping(){
        String NAMESPACE = reqMappingController.NAMESPACE;
      Map<String, Object> reqParams = new Map<String, Object>();
        reqParams.put(NAMESPACE+'Name', 'test2');
        reqParams.put(NAMESPACE+'AI_Model__c', 'OpenAi 3.5-Turbo16K');
        reqParams.put(NAMESPACE+'Description__c', 'test description');
        List<Map<String, Object>> reqLinesList = new List<Map<String, Object>>();
        Map<String, Object> reqLineParams = new Map<String, Object>();
        reqLineParams.put('dataSource', 'Prompt');
        reqLineParams.put('sequence', '1');
        reqLineParams.put('annotation', 'testannotation');
        reqLinesList.add(reqLineParams);
        Test.startTest();
        List<Request_Mapping_Line__c> reqLine = reqMappingController.createRequestMapping(reqParams,reqLinesList);
        Test.stopTest();
        System.Assert(reqLine != null);
    }
}