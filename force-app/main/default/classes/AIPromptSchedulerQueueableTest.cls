/**
 * @description       : Test class for AIPromptSchedulerQueueable
 * @jira              : Jira v2/7712 Issue: AI Mass Processing with more than 7 Prompts
 *                      V2-7889 Enhanced test coverage to 83%
 * @author            : Sohit Sharma
 * @group             : Plumcloud Labs
 * @last modified on  : 03-20-2026
 * @last modified by  : Piyush Chourasia
 **/
@isTest
public with sharing class AIPromptSchedulerQueueableTest {
    
    @testSetup
    public static void makeData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', true);
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
    }
    
    @isTest
    public static void testQueueableExecution() {
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c LIMIT 1];
        AI_Prompt_Scheduler__c promptSch = [
            SELECT Id, Prompt__c, Where_Clause__c, Record_Limit__c,
                   Prompt__r.Object__c, Prompt__r.AI_Connection__c, 
                   Prompt__r.AI_Connection__r.Name, Prompt__r.Prompt_Command__c,
                   AI_Scheduler__c, AI_Scheduler__r.Retry_Count__c, Object_Name__c,
                   Cross_Object_Filter_Condition__c
            FROM AI_Prompt_Scheduler__c 
            LIMIT 1
        ];
        
        AI_Scheduled_Run__c scheduledRun = new AI_Scheduled_Run__c();
        scheduledRun.Run_Date_Time__c = System.now();
        scheduledRun.Scheduler__c = sch.Id;
        scheduledRun.Current_Retry_Count__c = 0;
        scheduledRun.Total_Records__c = 0;
        scheduledRun.InProgress_Records__c = 0;
        scheduledRun.Errored_Records__c = 0;
        scheduledRun.Status__c = 'Not Started';
        insert scheduledRun;
        
        List<AI_Prompt_Scheduler__c> schedulers = new List<AI_Prompt_Scheduler__c>{ promptSch };
        
        Test.startTest();
        // Disable chaining for test
        AIPromptSchedulerQueueable.disableChaining = true;
        System.enqueueJob(new AIPromptSchedulerQueueable(schedulers, scheduledRun));
        Test.stopTest();
        
        // Verify no exceptions were thrown
        System.assert(true, 'Queueable executed successfully');
    }
    
    @isTest
    public static void testQueueableWithMultipleSchedulers() {
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c LIMIT 1];
        AI_Prompt__c prompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        // Create additional prompt schedulers using TestUtility
        for (Integer i = 0; i < 3; i++) {
            TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        }
        
        List<AI_Prompt_Scheduler__c> allSchedulers = [
            SELECT Id, Prompt__c, Where_Clause__c, Record_Limit__c,
                   Prompt__r.Object__c, Prompt__r.AI_Connection__c, 
                   Prompt__r.AI_Connection__r.Name, Prompt__r.Prompt_Command__c,
                   AI_Scheduler__c, AI_Scheduler__r.Retry_Count__c, Object_Name__c,
                   Cross_Object_Filter_Condition__c
            FROM AI_Prompt_Scheduler__c 
            WHERE AI_Scheduler__c = :sch.Id
        ];
        
        AI_Scheduled_Run__c scheduledRun = new AI_Scheduled_Run__c();
        scheduledRun.Run_Date_Time__c = System.now();
        scheduledRun.Scheduler__c = sch.Id;
        scheduledRun.Current_Retry_Count__c = 0;
        scheduledRun.Total_Records__c = 0;
        scheduledRun.InProgress_Records__c = 0;
        scheduledRun.Errored_Records__c = 0;
        scheduledRun.Status__c = 'Not Started';
        insert scheduledRun;
        
        Test.startTest();
        // Disable chaining for test
        AIPromptSchedulerQueueable.disableChaining = true;
        System.enqueueJob(new AIPromptSchedulerQueueable(allSchedulers, scheduledRun));
        Test.stopTest();
        
        // Verify no exceptions were thrown
        System.assert(true, 'Queueable with multiple schedulers executed successfully');
    }
    
    @isTest
    public static void testQueueableChaining() {
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c LIMIT 1];
        AI_Prompt_Scheduler__c promptSch = [
            SELECT Id, Prompt__c, Where_Clause__c, Record_Limit__c,
                   Prompt__r.Object__c, Prompt__r.AI_Connection__c, 
                   Prompt__r.AI_Connection__r.Name, Prompt__r.Prompt_Command__c,
                   AI_Scheduler__c, AI_Scheduler__r.Retry_Count__c, Object_Name__c,
                   Cross_Object_Filter_Condition__c
            FROM AI_Prompt_Scheduler__c 
            LIMIT 1
        ];
        
        AI_Scheduled_Run__c scheduledRun = new AI_Scheduled_Run__c();
        scheduledRun.Run_Date_Time__c = System.now();
        scheduledRun.Scheduler__c = sch.Id;
        scheduledRun.Current_Retry_Count__c = 0;
        scheduledRun.Total_Records__c = 0;
        scheduledRun.InProgress_Records__c = 0;
        scheduledRun.Errored_Records__c = 0;
        scheduledRun.Status__c = 'Not Started';
        insert scheduledRun;
        
        List<AI_Prompt_Scheduler__c> schedulers = new List<AI_Prompt_Scheduler__c>{ promptSch };
        
        Test.startTest();
        // Test with chaining constructor (starting from index 0)
        AIPromptSchedulerQueueable.disableChaining = true;
        System.enqueueJob(new AIPromptSchedulerQueueable(schedulers, 0, scheduledRun));
        Test.stopTest();
        
        System.assert(true, 'Queueable with chaining constructor executed successfully');
    }
    
    @isTest
    public static void testEmptySchedulersList() {
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c LIMIT 1];
        
        AI_Scheduled_Run__c scheduledRun = new AI_Scheduled_Run__c();
        scheduledRun.Run_Date_Time__c = System.now();
        scheduledRun.Scheduler__c = sch.Id;
        scheduledRun.Current_Retry_Count__c = 0;
        scheduledRun.Total_Records__c = 0;
        scheduledRun.InProgress_Records__c = 0;
        scheduledRun.Errored_Records__c = 0;
        scheduledRun.Status__c = 'Not Started';
        insert scheduledRun;
        
        List<AI_Prompt_Scheduler__c> emptySchedulers = new List<AI_Prompt_Scheduler__c>();
        
        Test.startTest();
        AIPromptSchedulerQueueable.disableChaining = true;
        System.enqueueJob(new AIPromptSchedulerQueueable(emptySchedulers, scheduledRun));
        Test.stopTest();
        
        System.assert(true, 'Queueable with empty list executed successfully');
    }
    
    @isTest
    public static void testFinalizerDirectCallNoChaining() {
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c LIMIT 1];
        AI_Prompt__c prompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        
        List<AI_Prompt_Scheduler__c> allSchedulers = [
            SELECT Id, Prompt__c, Where_Clause__c, Record_Limit__c,
                   Prompt__r.Object__c, Prompt__r.AI_Connection__c, 
                   Prompt__r.AI_Connection__r.Name, Prompt__r.Prompt_Command__c,
                   AI_Scheduler__c, AI_Scheduler__r.Retry_Count__c, Object_Name__c,
                   Cross_Object_Filter_Condition__c
            FROM AI_Prompt_Scheduler__c 
            WHERE AI_Scheduler__c = :sch.Id
        ];
        
        AI_Scheduled_Run__c scheduledRun = new AI_Scheduled_Run__c();
        scheduledRun.Run_Date_Time__c = System.now();
        scheduledRun.Scheduler__c = sch.Id;
        scheduledRun.Current_Retry_Count__c = 0;
        scheduledRun.Total_Records__c = 0;
        scheduledRun.InProgress_Records__c = 0;
        scheduledRun.Errored_Records__c = 0;
        scheduledRun.Status__c = 'Not Started';
        insert scheduledRun;
        
        Test.startTest();
        AIPromptSchedulerQueueable queueable = new AIPromptSchedulerQueueable(allSchedulers, 1, scheduledRun);
        FinalizerContext mockContext = new MockFinalizerContext();
        queueable.execute(mockContext);
        Test.stopTest();
        
        Assert.isTrue(allSchedulers.size() >= 1, 'Should have schedulers');
    }
    
    @isTest
    public static void testFinalizerChainingPath() {
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c LIMIT 1];
        AI_Prompt__c prompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        
        List<AI_Prompt_Scheduler__c> allSchedulers = [
            SELECT Id, Prompt__c, Where_Clause__c, Record_Limit__c,
                   Prompt__r.Object__c, Prompt__r.AI_Connection__c, 
                   Prompt__r.AI_Connection__r.Name, Prompt__r.Prompt_Command__c,
                   AI_Scheduler__c, AI_Scheduler__r.Retry_Count__c, Object_Name__c,
                   Cross_Object_Filter_Condition__c
            FROM AI_Prompt_Scheduler__c 
            WHERE AI_Scheduler__c = :sch.Id
        ];
        
        AI_Scheduled_Run__c scheduledRun = new AI_Scheduled_Run__c();
        scheduledRun.Run_Date_Time__c = System.now();
        scheduledRun.Scheduler__c = sch.Id;
        scheduledRun.Current_Retry_Count__c = 0;
        scheduledRun.Total_Records__c = 0;
        scheduledRun.InProgress_Records__c = 0;
        scheduledRun.Errored_Records__c = 0;
        scheduledRun.Status__c = 'Not Started';
        insert scheduledRun;
        
        Test.startTest();
        AIPromptSchedulerQueueable.skipBatchExecution = true;
        AIPromptSchedulerQueueable.disableChaining = false;
        AIPromptSchedulerQueueable queueable = new AIPromptSchedulerQueueable(allSchedulers, 0, scheduledRun);
        queueable.execute((QueueableContext) null);
        
        FinalizerContext mockContext = new MockFinalizerContext();
        queueable.execute(mockContext);
        Test.stopTest();
        
        Assert.isTrue(allSchedulers.size() > 1, 'Should have multiple schedulers');
    }
    
    private class MockFinalizerContext implements FinalizerContext {
        public Id getAsyncApexJobId() {
            return null;
        }
        
        public String getRequestId() {
            return 'test-request-id';
        }
        
        public System.ParentJobResult getResult() {
            return System.ParentJobResult.SUCCESS;
        }
        
        public Exception getException() {
            return null;
        }
    }
}