/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-21-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public class AISchedulerOverrideControllerTest {

    @testSetup
    static void makeData(){
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', true);
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
    }
    
    @isTest
    static void getSchedulingInformationTest(){
        AI_Scheduler__c sch = [SELECT Id, Name, Scheduling_Frequency__c, Schedule_Detail__c, Cron_Expression__c, Schedule_time__c, Retry_Count__c FROM AI_Scheduler__c LIMIT 1];
        sch.Cron_Expression__c = '0 00 10 ? * * *';
        update sch;

        Test.startTest();
        Map<String, Object> obj = AISchedulerOverrideController.getSchedulingInformation(sch.Id);
        AISchedulerOverrideController.saveSchedulingInformation(sch.Id, sch.Name, sch.Scheduling_Frequency__c, String.valueOf(sch.Schedule_time__c), sch.Schedule_Detail__c.split(';'), sch.Cron_Expression__c, sch.Retry_Count__c);
        AISchedulerOverrideController.scheduleJob(sch.Id);
        AISchedulerOverrideController.unscheduleJob(sch.Id);
        AISchedulerOverrideController.runNow(sch.Id);
        
        String runId = [SELECT Id FROM AI_Scheduled_Run__c WHERE Scheduler__c != NULL LIMIT 1].Id;
        AI_Response__c resp = new AI_Response__c();
        resp.Scheduled_Run__c = runId;
        insert resp;
        AISchedulerOverrideController.abortJobs(runId);
        Test.stopTest();
        
        System.Assert(obj != null);
    }
    
}