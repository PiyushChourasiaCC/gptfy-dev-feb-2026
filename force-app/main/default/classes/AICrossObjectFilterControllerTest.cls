/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 12-13-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public class AICrossObjectFilterControllerTest {
	
    @testSetup
    public static void makeData(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test', 'Account', 'Active', true);
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt.Id, sch.Id, true);
        AI_Cross_Object_Filter__c cofi = TestUtility.createCrossObjectFilter(promptScheduler.Id, 'Contact', true);
        AI_Cross_Object_Filter__c c_cofi = TestUtility.createCrossObjectFilter(promptScheduler.Id, 'Contact', false);
        c_cofi.Parent_Filter__c = cofi.Id;
		c_cofi.Sequence__c = 2;
        insert c_cofi;
    }
    
    @isTest
    public static void controllerTest(){
        AI_Prompt_Scheduler__c pmtSch = [SELECT Id FROM AI_Prompt_Scheduler__c limit 1];
        Test.startTest();
        
        AICrossObjectFilterController.DataWrapper dw = AICrossObjectFilterController.fetchHierarchy(pmtSch.Id);
        List<AIDataExtractionController.PicklistWrapper> lstOfObjects = AICrossObjectFilterController.getRelatedObjects(pmtSch.Id, pmtSch.Id, 'Account');
        AICrossObjectFilterController.upsertRelatedFilter(new Map<String, String>{
            'selectedObject' => 'Contact', 'masterId' => pmtSch.Id, 'parentId' => null, 'filterId' => null, 'parentObject' => 'Account', 'operator' => 'Equals', 
           	'filterValue' => '0', 'whereClause' => null,  'sequence' => '3', 'relationshipField' => 'AccountId', 'relationshipName' => 'Contacts'
        });
        AICrossObjectFilterController.updateCofiCondition('1 AND 2 AND 3', pmtSch.Id);
        
        AI_Cross_Object_Filter__c cofi = [SELECT Id FROM AI_Cross_Object_Filter__c WHERE Sequence__c = 1];
        
        cofi.Where_Clause__c = ' Id != NULL ';
        update cofi;
        
        AICrossObjectFilterController.deleteFilters(pmtSch.Id, cofi.Id);
        
        Test.stopTest();
        System.Assert(dw != null);
    }
    
}