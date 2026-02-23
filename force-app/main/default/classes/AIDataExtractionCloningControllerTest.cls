@isTest
private class AIDataExtractionCloningControllerTest {
    
    @testSetup
    static void makeData(){
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', true);
        TestUtility.insertDataExtraction();
    }
    
    @isTest 
    private static void testcloneRecord(){     
        AI_Data_Extraction_Mapping__c master = [SELECT Id, Name, API_Name__c, Description__c, Object_Name__c, External_Id__c FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        String cloneRecordId = AIDataExtractionCloningController.cloneRecord(master.Id);
        system.assertEquals(String.isNotBlank(cloneRecordId), true);
    }
}