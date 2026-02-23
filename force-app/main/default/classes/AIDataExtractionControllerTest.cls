/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class AIDataExtractionControllerTest {
	
    @testSetup
    static void makeData(){
        TestUtility.insertDataExtraction();
        ContentVersion cv = TestUtility.createContentVersion('test',false);
        String body = '-----BEGIN PRIVATE KEY-----'+
                    'MIIEpAIBAAKCAQEAxVyXPhg0y99JNO7ATSNckoIKW4xM32745ZeHQ0ZaN28r+eCS'+
                    'ce3VSKcHCX4W2mITgp3rZvaBB4IzIA9SYSOMZVFekjGR6X8YZf14gu/LLeS1jWfE'+
                    'vbR6H2wuL1vKgQhqtLho6VTPqXf1XDYssNE77r3+YLQKgE1sSxuKLcrmWlK8nrIZ'+
                    'C6m9O5eSplztIVRVY1M1HIt7mazHxUyVakLB55Jbkp8CNqNiPgM3sZz0Vmwx1cJw'+
                    '0HJ3//7OIW1VkE0/iKnXlZIn9dWLnYCURW8pSJ2MASHCfVck0vEgvdN8e/lH/H6s'+
                    'YclHf07toMWL1azL2riMUU0nzCmQhSkOCMgamQIDAQABAoIBAQCMkx7HA8bXT/t8'+
                    '0HH4f694S1fFTXGT1B9EqWGW8Y1g3racDPFCZPz9+rpwcHcmpaTv7Du34uyUxJBV'+
                    'zZQHzKI7qHGL//LGNdjTDG/CE7rMvZLzXW4tEVfK+esLoH3k2nHmt1NCnz4qn18M'+
                    'hynd56qgqoN9rb+tE3iHJt6NL3BT9EjuV/RxsMv8uHZNQl5E/bzsmP47c+xVKW44'+
                    '0TD9eprHusCdvNge1wbgdBk+r31pOtPP2Z3PVu09IElXMsXVPReiCDCeQ3uQ78av'+
                    '0+PHN8Ls2VwkUKdSOUKmrLozPdQKhpVMvGv81JzMWvlO2dZ7+1yCYCGXTdamGoMC'+
                    'EbLrJFnhAoGBAPcqD/kFkF6DLPsEfJaiB5HZmXSRbG/lkLUdDnWynCXG1Q7SS2I8'+
                    'ixWUbInmeGzRuJ0PJ0u5/DKi5OBG73C1yeDRjYKmLhJGNHOYN4Cf7A8ndNMzLVJ8'+
                    'TNUSoQO7HXEgF4DF14F1MWuTHM3xHMf63CyARIhQsivtCXKi+jziFMjfAoGBAMxq'+
                    'wclHC+nmU8L91LEvx5kkyOquYixAYm1Jb5pZp54W4as1IYiSg9hbhZpXqhnJn/xu'+
                    '9iaS/fIR9ck44mE75USozxm2/c5pafKC4Vc88WMya+4fiFuhka1rupa3B5vJmCjx'+
                    '2bSinqaGD27SyM6dmgqiuxGEte7oSeC+OZUbKnOHAoGAM+qr7DzU9GVNX3Szztg+'+
                    'Cs7QQwIA6wgne0OdM+/OiMjZHAHkP8BD3saMffLhPMpYovT55hgs913sAYgk52Ho'+
                    'A8dAmD7b0o7YmadRkT0GUrCRA4PuczMU2HTPSX9WUdrR1QS5ncHGHbiLBl8tEnyJ'+
                    'HvfabV+17TAfGetN8Nf0UbUCgYAff/f6v0L7uS2BJ8JFx5oXZE69sz+XmBhSxPU4'+
                    'sMYem2INEvPm6sT8ayYMYaPps2M+8A5oZVBSpCfe6TAhUayDxwua59L2otHbuAVn'+
                    'fxGnepadLCjEDgK32Zj4Lp4yiH81GAe3STPvb0sjhcHB7RFWwDrZeTzb4tm3kzim'+
                    'XHhPMwKBgQCDpcC0qAZBYx4FLLdrn1+ig2aifnNod4NUJXPrglWhAQDDhK3ALQ/M'+
                    'I90Wo4J0NgzaC15KF0/g1dcNN8IJt2J3ViHQS1kVwA9ytj1+/ZBL+Co9dA5IEoib'+
                    'euCvSuA5bOa1YP0fkuNi6Vb2kjdJpkFeQb+80rpT1+UbQU3AQYZgtw=='+
                    '-----END PRIVATE KEY-----';        
        Blob data = Blob.valueOf(body);
        cv.versiondata = data;
        insert cv;
    }
    
    @isTest
    static void getMasterDataTest(){
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        Test.startTest(); 
        AIDataExtractionController.MasterWrapper wrap = AIDataExtractionController.getMasterData(master.Id);
        AIDataExtractionController.modifyMaster(new Map<String, String>{'recordId' => master.Id, 'mappingName' => 'Test Mapping', 'targetObject' => 'Account', 'description' => 'Test Desc', 'objLabel' => 'Account', 'aiDataSource' => null});
        Test.stopTest();
        AI_Data_Extraction_Mapping__c umaster = [SELECT Id, Description__c FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        System.Assert(umaster.Description__c == 'Test Desc');
    }
    
    @isTest
    static void fetchDetailHierarchyTest(){
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        Test.startTest();
        AIDataExtractionController.DataWrapper wrap = AIDataExtractionController.fetchDetailHierarchy(master.Id);
        AI_Data_Extraction_Detail__c detail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        List<AIDataExtractionController.PicklistWrapper> relatedObjects = AIDataExtractionController.getRelatedObjects(master.Id, 'Contact', detail.Id);
		AIDataExtractionController.deleteRelatedObjectMapping(master.Id, detail.Id, 'Account');
        Test.stopTest();
        List<AI_Data_Extraction_Detail__c> lst = [SELECT Id FROM AI_Data_Extraction_Detail__c];
        System.Assert(lst == null || lst.isEmpty());
    }
    
    @isTest
    static void dataCloudTest(){
        List<ContentVersion> lstOfVersions = [SELECT Id,ContentDocumentId FROM ContentVersion LIMIT 1];
		GPTfy_Settings__c gptfySetting = new GPTfy_Settings__c(Enable_for_Data_Cloud__c=true,Salesforce_Client_Id__c='clientId',
                                                        Salesforce_Admin_Email__c='adminEmail',Salesforce_Domain_URL__c='domain',
                                                        Salesforce_Auth_Named_Credential__c='namedTest',Salesforce_Private_Key_File_Id__c=lstOfVersions[0].ContentDocumentId);
        insert gptfySetting;
        //Map<String, String> mapOfEndpointUrls = new Map<String,String>();
        Map<String, String> response = new Map<String,String>();
       // mapOfEndpointUrls.put('cdId','google.com');
        String responseBody = '{ "access_token":"token",  "metadata": [{ "name": "Contact__dlm", "fields": [{"name": "fieldName"}] , "relationships" : [{ "fromEntity": "Account__dlm", "fromEntityAttribute": "testField" }] , "primaryKeys": [{ "name": "testName", "displayName": "testDisplay" }] }] }';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(responseBody)); 
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        AIDataExtractionController.upsertRelatedObjectMapping(new Map<String, String>{
            'selectedObject' => 'Contact__dlm', 'selectedObjectLabel' => 'Contact__dlm', 'masterId' => master.Id, 'parentId' => '', 'detailId' => '',
            'parentObject' => 'Account', 'relationshipField' => 'AccountId', 'relationshipName' => 'Contacts'       
        });
        
        List<Object> relationshipList = new List<Object>();

        Map<String, Object> rel1 = new Map<String, Object>();
        rel1.put('fromEntity', 'Account__dlm');
        rel1.put('fromEntityAttribute', 'testfield');
        relationshipList.add(rel1);

        List<Object> primaryKeys = new List<Object>();

        Map<String, Object> pkeys = new Map<String, Object>();
        pkeys.put('name', 'testName');
        pkeys.put('displayName', 'testDisplayName');
        primaryKeys.add(pkeys);
        
        
        AIDataExtractionController.DataCloudWrapper dcwrap = new AIDataExtractionController.DataCloudWrapper();
        dcwrap.label = 'Test Label';
        dcwrap.fieldCount = 5;
        dcwrap.apiName = 'Test_Api_Name__c';
        dcwrap.primaryFields = primaryKeys;
        dcwrap.relationshipFields = relationshipList;
        
        Map<String,AIDataExtractionController.DataCloudWrapper> mapDCWrap = new Map<String, AIDataExtractionController.DataCloudWrapper>();
        mapDCWrap.put('Account__dlm',dcwrap);
        
        Test.startTest();
        AI_Data_Extraction_Detail__c detail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact__dlm' LIMIT 1];
        List<AIDataExtractionController.PicklistWrapper> relatedObjects = AIDataExtractionController.getRelatedObjects(master.Id, 'Contact', detail.Id);
		relatedObjects = AIDataExtractionController.getRelatedObjects(master.Id, 'Contact__dlm', detail.Id);
		AIDataExtractionController.getTargetFields('Contact__dlm','Account__dlm',mapDCWrap,true);
        AIDataExtractionController.getTargetFields('Contact','Account__dlm',mapDCWrap,true);
        AIDataExtractionController.getTargetFields('Contact','Account__dlm',mapDCWrap,false);
        mapDCWrap = AIDataExtractionController.getObjectsWithFieldCountFromDataCloud();
        Test.stopTest();
        Assert.isNotNull(mapDCWrap.get('Contact__dlm'));
    }
    
}