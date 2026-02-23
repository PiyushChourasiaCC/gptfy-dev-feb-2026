/**
 * @description               : Test class for AIPromptElementController class.
 * @author                    : Piyush Chourasia
 * @group                     : Plumcloud Labs
 * @last modified on          : 04-09-2025
 * @last modified by          : Piyush Chourasia
 **/
@isTest
public class AIPromptElementControllerTest {

    /**
     * @description:
     *   Creates comprehensive test data for AI Canvas Service tests including AI_Prompt__c,
     *   AI_Prompt_Element__c, AI_Response__c, User, and Profile records for thorough testing.
     */
    @TestSetup
    static void createTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account',
            Industry = 'Technology',
            Type = 'Customer'
        );
        insert testAccount;
        
        // Create AI Prompts with different configurations
        List<AI_Prompt__c> prompts = new List<AI_Prompt__c>();
        
        // Active Canvas prompt with profile restriction
        prompts.add(new AI_Prompt__c(
            Name = 'Active Canvas Prompt',
            Object__c = 'Account',
            Type__c = 'Canvas',
            Status__c = 'Active',
            Profiles__c = 'System Administrator',
            Auto_Refresh_Duration__c = 30,
            Prompt_Request_Id__c = 'active-prompt-123',
            Visibility_Condition__c = 'Industry = \'Technology\'',
            Visibility_Exception_Message__c = 'Account must be in Technology industry'
        ));
        
        // Summary prompt
        prompts.add(new AI_Prompt__c(
            Name = 'Summary Prompt',
            Object__c = 'Account',
            Type__c = 'Text',
            Status__c = 'Active',
            Auto_Refresh_Duration__c = 20,
            Prompt_Request_Id__c = 'summary-prompt-101'
        ));
        
        insert prompts;
        
        // Create AI Prompt Elements
        AI_Prompt_Element__c promptElement = new AI_Prompt_Element__c(
            AI_Parent_Prompt__c = prompts[0].Id,
            AI_Prompt__c = prompts[1].Id,
            AI_Summary_Prompt__c = prompts[1].Id,
            Sequence__c = 1,
            Width__c = '3/3 Column',
            Height__c = 250,
            Icon__c = 'custom2',
            Inherit_Prompt_Security__c = false
        );
        insert promptElement;
    }
    
    @isTest
    static void testGetInitialDetails() {
       // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id, Visibility_Condition__c FROM AI_Prompt__c 
                                 WHERE Name = 'Active Canvas Prompt' LIMIT 1];

        Test.startTest();
        AIPromptElementController.DetailsWrapper details = AIPromptElementController.getInitialDetails(testPrompt.Id);
        Test.stopTest();

        Assert.isTrue(details != null, 'DetailsWrapper should not be null');
        Assert.isTrue(details.promptDetails != null, 'PromptDetails should not be null');
        Assert.areEqual(testPrompt.Id, details.promptDetails.id, 'PromptDetails id should match');
        Assert.isTrue(details.widthOptions != null, 'Width picklist options should not be null');
        Assert.isTrue(details.iconOptions != null, 'Icon picklist options should not be null');
        Assert.isTrue(details.promptElements != null, 'PromptElements list should not be null');
        Assert.isTrue(details.promptElements.size() > 0, 'PromptElements should contain at least one element');
    }

    @isTest
    static void testCreatePromptElement() {
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id, Visibility_Condition__c FROM AI_Prompt__c 
                                WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        // Retrieve test data
        AI_Prompt__c testPrompt2 = [SELECT Id, Visibility_Condition__c FROM AI_Prompt__c 
                                WHERE Name = 'Summary Prompt' LIMIT 1];

        // Prepare wrapper for serialization
        AIPromptElementController.PromptElementWrapper wrapper = new AIPromptElementController.PromptElementWrapper(
            new AI_Prompt_Element__c(
                AI_Parent_Prompt__c = testPrompt.Id,
                AI_Prompt__c = testPrompt2.Id,
                Height__c = 123,
                Width__c = '3/3 Column',
                Icon__c = 'custom2',
                Sequence__c = 5,
                Inherit_Prompt_Security__c = true
            )
        );
        String jsonString = JSON.serialize(wrapper);

        Test.startTest();
        AIPromptElementController.createPromptElement(jsonString);
        Test.stopTest();

        List<AI_Prompt_Element__c> created = [SELECT Id, AI_Parent_Prompt__c, AI_Prompt__c, AI_Summary_Prompt__c, 
                                                Height__c, Width__c, Icon__c, Sequence__c, Inherit_Prompt_Security__c 
                                            FROM AI_Prompt_Element__c 
                                            WHERE AI_Parent_Prompt__c = :testPrompt.Id 
                                                AND Sequence__c = 5];

        Assert.areEqual(1, created.size(), 'Should create one Prompt Element');
        Assert.areEqual('3/3 Column', created[0].Width__c, 'Width should match');
        Assert.areEqual('custom2', created[0].Icon__c, 'Icon should match');
        Assert.areEqual(true, created[0].Inherit_Prompt_Security__c, 'Inherit_Prompt_Security__c should match');
    }

    @isTest
    static void testUpdatePromptElement() {
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id, Visibility_Condition__c FROM AI_Prompt__c 
                                WHERE Name = 'Active Canvas Prompt' LIMIT 1];
        // Retrieve test data
        AI_Prompt__c testPrompt2 = [SELECT Id, Visibility_Condition__c FROM AI_Prompt__c 
                                WHERE Name = 'Summary Prompt' LIMIT 1];

        // Prepare wrapper for serialization
        AIPromptElementController.PromptElementWrapper wrapper = new AIPromptElementController.PromptElementWrapper(
            new AI_Prompt_Element__c(
                AI_Parent_Prompt__c = testPrompt.Id,
                AI_Prompt__c = testPrompt2.Id,
                Height__c = 123,
                Width__c = '3/3 Column',
                Icon__c = 'custom2',
                Sequence__c = 5,
                Inherit_Prompt_Security__c = true
            )
        );
        String jsonString = JSON.serialize(wrapper);

        Test.startTest();
        AIPromptElementController.createPromptElement(jsonString);

        List<AI_Prompt_Element__c> created = [SELECT Id, AI_Parent_Prompt__c, AI_Prompt__c, AI_Summary_Prompt__c, 
                                                Height__c, Width__c, Icon__c, Sequence__c, Inherit_Prompt_Security__c 
                                                FROM AI_Prompt_Element__c
                                                WHERE AI_Parent_Prompt__c = :testPrompt.Id 
                                                    AND Sequence__c = 5];
        Assert.areEqual(1, created.size(), 'Should create one Prompt Element');
        Assert.areEqual('3/3 Column', created[0].Width__c, 'Width should match');
        Assert.areEqual('custom2', created[0].Icon__c, 'Icon should match');
        Assert.areEqual(true, created[0].Inherit_Prompt_Security__c, 'Inherit_Prompt_Security__c should match');

        wrapper.sequence = 99;
        wrapper.id = created[0].Id;
        wrapper.height = 222;
        wrapper.icon = 'custom1';

        jsonString = JSON.serialize(wrapper);
        AIPromptElementController.updatePromptElement(jsonString);
        Test.stopTest();

        AI_Prompt_Element__c updated = [SELECT Width__c, Icon__c, Height__c, Sequence__c, Inherit_Prompt_Security__c 
                                            FROM AI_Prompt_Element__c 
                                            WHERE Id = :created[0].Id 
                                            LIMIT 1];
        Assert.areEqual('custom1', updated.Icon__c, 'Icon should be updated');
        Assert.areEqual(222, updated.Height__c, 'Height should be updated');
        Assert.areEqual(99, updated.Sequence__c, 'Sequence should be updated');
    }

    @isTest
    static void testDeletePromptElement() {
        // Retrieve test data
        AI_Prompt__c testPrompt = [SELECT Id, Visibility_Condition__c FROM AI_Prompt__c 
                                    WHERE Name = 'Active Canvas Prompt' LIMIT 1];

        AI_Prompt_Element__c toBeDeleted = [SELECT Id FROM AI_Prompt_Element__c WHERE AI_Parent_Prompt__c = :testPrompt.Id LIMIT 1];

        Test.startTest();
        AIPromptElementController.deletePromptElement(toBeDeleted.Id);
        Test.stopTest();

        List<AI_Prompt_Element__c> deleted = [SELECT Id FROM AI_Prompt_Element__c WHERE AI_Parent_Prompt__c = :testPrompt.Id];
        Assert.areEqual(0, deleted.size(), 'Prompt Element should be deleted');
    }

    @isTest
    static void testGetInitialDetailsException() {
        // Pass invalid Id, expect AuraHandledException
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIPromptElementController.getInitialDetails('invalidId');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        Assert.isTrue(exceptionThrown, 'AuraHandledException should be thrown for invalid Id');
    }

    @isTest
    static void testCreatePromptElementException() {
        // Pass invalid JSON, expect AuraHandledException
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIPromptElementController.createPromptElement('invalidJson');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        Assert.isTrue(exceptionThrown, 'AuraHandledException should be thrown for invalid JSON');
    }

    @isTest
    static void testUpdatePromptElementException() {
        // Pass invalid JSON, expect AuraHandledException
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            AIPromptElementController.updatePromptElement('invalidJson');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        Assert.isTrue(exceptionThrown, 'AuraHandledException should be thrown for invalid JSON');
    }
}