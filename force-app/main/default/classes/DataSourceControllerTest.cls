@isTest
public with sharing class DataSourceControllerTest {
    @testSetup
    static void makeData(){
        AI_Data_Source__c ds = TestUtility.getAIDataSource(true);
    }
    
    @isTest
    static void dataSourceTest(){
        Test.startTest();
        List<Object> lstObj = DataSourceController.getDataSourceOptions();
        system.assert(lstObj != null);
        Test.stopTest();
    }
}