/**
* @description       : 
* @author            : Sohit Sharma
* @group             : Plumcloud Labs
* @last modified on  : 11-03-2024
* @last modified by  : Sohit Sharma
**/
@isTest
public with sharing class AISecurityFilterTriggerHandlerTest {
    @isTest
    public static void createSecurityLayer(){
        Test.startTest();
        String regexRecordTypeId = AIDataExtractionService.RT_REGEX;
        AI_Security_Filters__c rec = TestUtility.getAISecurityFilter('Email',regexRecordTypeId,false);
        rec.Status__c = 'InActive';
        insert rec;
        rec.Status__c = 'Active';
        update rec;
        Test.stopTest();
        System.Assert(rec != null); 
    }
    
    @isTest
    public static void createUpdateApexSecurityLayer(){
        
        String apexRecordTypeId = Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Apex').getRecordTypeId();
        AI_Security_Filters__c rec = TestUtility.getAISecurityFilter('Driver License',apexRecordTypeId,false);
        rec.Apex_Class_Name__c = 'AISecurityFilterTriggerHandlerTest';
        rec.Status__c = 'InActive';
        Test.startTest();
        insert rec;
        rec.Status__c = 'Active';
        rec.Apex_Class_Name__c = 'AISecurityFilterTriggerHandlerTest1';
        Boolean errorOccur = false;
        try {
            update rec;
        }catch(Exception e){
            errorOccur = true;
        }
        Test.stopTest();
        System.Assert(rec != null); 
        System.Assert(errorOccur); 
    }

}