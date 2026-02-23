@isTest
public class AIPromptSchedulerControllerTest {

    @testSetup
    static void makeData() {
        // Setup test data with utility methods
        Account testAccount = TestUtility.getAccount(true);
        Contact testContact = TestUtility.getContact(testAccount.Id, true);
        Case testCase = TestUtility.getCase(testAccount.Id, testContact.Id, true);
        AI_Connection__c testConnection = TestUtility.getConnection('GPTfy', true);
        AI_Prompt__c testPrompt = TestUtility.getAIPrompt('Sample Prompt', 'Account', 'Active', true);
        AI_Scheduler__c testScheduler = TestUtility.getScheduler('Test Scheduler', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt_Scheduler__c testPromptScheduler = TestUtility.getAIPromptScheduler(testPrompt.Id, testScheduler.Id, true);
    }

    @isTest
    static void testGetPromptObjectWithInvalidId() {
        String invalidId = 'Invalid Id'; // Use a realistic but non-existing ID
        String result = AIPromptSchedulerController.getPromptObject(invalidId);
        System.assertEquals(null, result, 'Result should be null for a non-existing ID.');
    }

    @isTest
    static void testGetPromptSchedulerData() {
        String promptSchedulerId = [SELECT Id FROM AI_Prompt_Scheduler__c LIMIT 1].Id;
        Test.startTest();
        Map<String, Object> schedulerData = AIPromptSchedulerController.getPromptSchedulerData(promptSchedulerId);
        Test.stopTest();
        
        System.assertNotEquals(null, schedulerData, 'Scheduler data should not be null.');
        System.assertEquals(true, schedulerData.containsKey('fields'), 'Fields key should be present.');
        System.assertEquals(true, schedulerData.containsKey('records'), 'Records key should be present.');
    }


    @isTest
    static void testGetPromptSchedulerDetail() {
        String promptSchedulerId = [SELECT Id FROM AI_Prompt_Scheduler__c LIMIT 1].Id;
        Test.startTest();
        Map<String, Object> detail = AIPromptSchedulerController.getPromptSchedulerDetail(promptSchedulerId);
        Test.stopTest();
        
        System.assertNotEquals(null, detail, 'Detail should not be null.');
        System.assertEquals('Sample Prompt', detail.get('promptName'), 'Prompt name should match.');
    }

    @isTest
    static void testGetPromptOptions() {
        Test.startTest();
        List<Object> options = AIPromptSchedulerController.getPromptOptions();
        Test.stopTest();
        
        System.assertNotEquals(null, options, 'Options should not be null.');
        System.assertEquals(true, options.isEmpty(), 'Options list should not be empty.');
    }

    @isTest
    static void testGetPromptObject() {
        String promptId = [SELECT Id FROM AI_Prompt__c LIMIT 1].Id;
        Test.startTest();
        String objectName = AIPromptSchedulerController.getPromptObject(promptId);
        Test.stopTest();
        
        System.assertEquals('Account', objectName, 'Object name should be Account.');
    }
}