/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 08-04-2023
* @last modified by  : Adarsh Sharma
**/
@isTest
public with sharing class AIPromptSchedulerTest {
    
    @testSetup
    public static void makeData(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', true);
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        AI_Cross_Object_Filter__c cofi = TestUtility.createCrossObjectFilter(promptScheduler.Id, 'Contact', true);
        promptScheduler.Cross_Object_Filter_Condition__c = '1';
        update promptScheduler;
    }

    @isTest
    public static void runNowTest(){
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c limit 1];
        Account acc = [SELECT Id FROM Account limit 1];
        Test.startTest();
        Boolean isError = false;
        try{
            AIPromptScheduler.runNow(sch.Id);
        }catch(Exception e){
            isError = true;
        }
        Test.stopTest();
        System.Assert(!isError);
    }
    
    @isTest
    public static void disqualifiedTest(){
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c limit 1];
        Account acc = [SELECT Id FROM Account limit 1];
        Contact con = new Contact(LastName = 'Test');
        con.AccountId = acc.Id;
        insert con;
        
        Test.startTest();
        Boolean isError = false;
        try{
            AIPromptScheduler.runNow(sch.Id);
        }catch(Exception e){
            isError = true;
        }
        Test.stopTest();
        System.Assert(!isError);
    }
    @isTest
    public static void runNowTestPromptProcessing(){
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c limit 1];
        AI_Prompt_Scheduler__c schde = [SELECT Id, Prompt__c,AI_Scheduler__c,AI_Scheduler__r.Retry_Count__c FROM AI_Prompt_Scheduler__c LIMIT 1];

        AI_Scheduled_Run__c obj = new AI_Scheduled_Run__c();
        obj.Run_Date_Time__c = System.Now();
        obj.Scheduler__c = sch.Id;
        obj.Current_Retry_Count__c = 0;
        obj.Total_Records__c = 0;
        obj.InProgress_Records__c = 0; 
        obj.Errored_Records__c = 0;
        obj.Status__c = 'Not Started';
        
        Insert obj;

        AI_Response__c resp = new AI_Response__c();
        resp.Prompt_Scheduler__c = schde.Id;
        resp.Status__c = AIConstants.RESP_STATUS_DATA_EXT;
        resp.Scheduled_Run__c = obj.Id;

        INSERT resp;

        Test.startTest();
        Boolean isError = false;
        try{
            Database.executeBatch(new AIPromptProcessingBatch(schde,obj));
        }catch(Exception e){
            isError = true;
        }
        Test.stopTest();
        System.Assert(!isError);
    }
    @isTest
    public static void runNowTestPromptProcessingResponses(){
        // Create test AI Connection records
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4',
            Named_Credential__c = 'Test_Credential'
        );
        insert aiConnection;
        
        AI_Connection__c aiConnectionFile = new AI_Connection__c(
            Name = 'Test AI Connection File',
            Model__c = 'gpt-4.1',
            Named_Credential__c = 'Test_Credential_File',
            Type__c = 'File'
        );
        insert aiConnectionFile;
        
        // Create test AI Prompt record
        AI_Prompt__c aiPrompt = new AI_Prompt__c(
            Name = 'Test AI Prompt',
            AI_Connection__c = aiConnection.Id,
            AI_Model_File_Processing__c = aiConnectionFile.Id,
            Include_Files__c = true
        );
        insert aiPrompt;
        AI_Scheduler__c sch = [SELECT Id FROM AI_Scheduler__c limit 1];
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(aiPrompt.Id, sch.Id, true);
        AI_Cross_Object_Filter__c cofi = TestUtility.createCrossObjectFilter(promptScheduler.Id, 'Contact', true);
        promptScheduler.Cross_Object_Filter_Condition__c = '1';
        update promptScheduler;

        AI_Scheduled_Run__c obj = new AI_Scheduled_Run__c();
        obj.Run_Date_Time__c = System.Now();
        obj.Scheduler__c = sch.Id;
        obj.Current_Retry_Count__c = 0;
        obj.Total_Records__c = 0;
        obj.InProgress_Records__c = 0; 
        obj.Errored_Records__c = 0;
        obj.Status__c = 'Not Started';
        
        Insert obj;

        AI_Response__c resp = new AI_Response__c();
        resp.Prompt_Scheduler__c = promptScheduler.Id;
        resp.Status__c = AIConstants.RESP_STATUS_DATA_EXT;
        resp.Scheduled_Run__c = obj.Id;

        INSERT resp;

        Test.startTest();
        Boolean isError = false;
        try{
            Database.executeBatch(new AIPromptProcessingBatch(promptScheduler,obj));
        }catch(Exception e){
            isError = true;
        }
        Test.stopTest();
        System.Assert(!isError);
    }
}