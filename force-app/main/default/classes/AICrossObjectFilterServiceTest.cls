/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 12-13-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public class AICrossObjectFilterServiceTest {
	
    @testSetup
    public static void makeData(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        Contact con = new Contact(LastName = 'Test');
        con.AccountId = acc.Id;
        insert con;
        
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', true);
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        AI_Cross_Object_Filter__c cofi = TestUtility.createCrossObjectFilter(promptScheduler.Id, 'Contact', true);
        AI_Cross_Object_Filter__c c_cofi = TestUtility.createCrossObjectFilter(promptScheduler.Id, 'Contact', false);
        c_cofi.Operator__c = 'Not Equals';
		c_cofi.Sequence__c = 2;
        insert c_cofi;
    }
    
    @isTest
    static void serviceTest(){
        AI_Prompt_Scheduler__c sch = [SELECT Id FROM AI_Prompt_Scheduler__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<AI_Cross_Object_Filter__c> lstOfFilters = AICrossObjectFilterService.getCrossObjectFilters(sch.Id);
        Set<String> recIds = AICrossObjectFilterService.init('(1 OR 2)', lstOfFilters, new Set<String>{acc.Id});
        Test.stopTest();
        System.assert(lstOfFilters != null);
    }
    
}