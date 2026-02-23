/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class AIExtractionFieldMappingControllerTest {
	
    @testSetup
    static void makeData(){
        TestUtility.insertDataExtraction();
    }
    
    @isTest
    static void getFieldMappingsTest(){
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        Test.startTest();
        Map<String, Object> data = AIExtractionFieldMappingController.getFieldMappings(master.Id, 'Account');
        Test.stopTest();
        System.Assert(data != null);
    }
    
    @isTest
    static void getParentFieldsTest(){
        Test.startTest();
        List<AIExtractionFieldMappingController.PicklistAttributeWrapper> options = AIExtractionFieldMappingController.getParentFields('Contact', false);
        Test.stopTest();
        System.Assert(options != null);
    }
    
    @isTest
    static void formulaBuilderTest(){
        Test.startTest();
        List<AIExtractionFieldMappingController.PicklistAttributeWrapper> formula = AIExtractionFieldMappingController.validateFormula('Account','STRING','Name');
        Test.stopTest();
        System.Assert(formula != null);
    }
    
}