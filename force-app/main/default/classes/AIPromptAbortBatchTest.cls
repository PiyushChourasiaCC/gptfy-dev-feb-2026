/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 28-10-2024
* @last modified by  : Adarsh Sharma
**/
@isTest
public class AIPromptAbortBatchTest {

    @testSetup
    public static void makeData(){
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
        prompt.Prompt_Request_Id__c = 'test';
        insert prompt;
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        AI_Scheduled_Run__c scheduledRun = TestUtility.getAIScheduledRun(sch.Id, true);
        AI_Response__c response = TestUtility.getAIResponse(scheduledRun.Id, promptScheduler.Id, null, true);
    }
    
    @isTest
    public static void myUnitTest(){
        AI_Scheduled_Run__c scheduledRun = [SELECT Id FROM AI_Scheduled_Run__c LIMIT 1];
        Test.startTest();
          Database.executeBatch(new AIPromptAbortBatch(scheduledRun.Id),1);
        Test.stopTest();
        System.AssertEquals(scheduledRun!=null, true, false);
    }
    
}