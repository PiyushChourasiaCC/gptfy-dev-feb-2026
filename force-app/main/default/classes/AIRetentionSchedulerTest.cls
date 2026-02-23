/**
 * @description       : 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 03-10-2023
 * @last modified by  : Rishabh Goel
**/
@isTest
public class AIRetentionSchedulerTest {
	
    @testSetup
    static void makeData(){
        AI_Response__c resp = new AI_Response__c();
        insert resp;
        Test.setCreatedDate(resp.Id, Date.today().addDays(-12));
    }
    
    @isTest
    static void scheduleTest(){
        Test.startTest();
        AIOrgWideSetupController.updateStatus(true, 10);
        AIRetentionScheduler job = new AIRetentionScheduler();
        job.execute(null);
        Test.stopTest();
        
        List<AI_Response__c> lstOfResponses = [SELECT Id FROM AI_Response__c LIMIT 1];
        System.Assert(lstOfResponses == null || lstOfResponses.isEmpty());
    }
    
}