/**
* @description       : This class used as a controller to invoke the Agentic Testing Framework Batchs
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 23-10-2025
* @last modified by  : Adarsh Sharma
* @JIRA V2-7163 : Agentic Testing Framework
**/
public with sharing class AIAgenticTestingFrameworkCtrl {
    
     /**
     * This method is used as controller to invoke the Agentic Testing Framework Batchs
     * @param recordId The Test Cycle recordId as variable for the batch job execution.
     * @return none
     */
    @AuraEnabled
    public static void runTestCycle(String recordId){
        try{
            AI_Test_Cycle__c testCycle = [SELECT Id, Start_Date_Time__c, Status__c FROM AI_Test_Cycle__c WHERE Id=:recordId];
            testCycle.Status__c = 'In Progress';
            testCycle.Start_Date_Time__c = DateTime.now();
            FLSCheck.getInstance().updateDML(new List<AI_Test_Cycle__c>{testCycle});
            
            Database.executeBatch(new AIAgenticTestingFrameworkBatch(recordId), 1);
        }catch(Exception ex){
            throw new AuraException(ex.getMessage());
        }
    }

}