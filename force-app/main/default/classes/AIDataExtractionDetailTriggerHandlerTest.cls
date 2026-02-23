/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class AIDataExtractionDetailTriggerHandlerTest {
	
    @isTest
    static void createObjectHierarchyTest(){
        Test.startTest();
        TestUtility.insertDataExtraction();
        Test.stopTest();
        List<AI_Data_Extraction_Detail__c> lst = [SELECT Id FROM AI_Data_Extraction_Detail__c];
        System.Assert(lst != null);
    }
    
}