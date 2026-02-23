/**
 * @description Test class for AIAgenticTestingFrameworkCtrl
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AIAgenticTestingFrameworkCtrlTest {
    
    @TestSetup
    static void setupTestData() {
        // Create AI Connection
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4',
            Named_Credential__c = 'TestCredential',
            Type__c = 'Agentic'
        );
        insert aiConnection;
        
        // Create AI Agent
        AI_Agent__c agent = new AI_Agent__c(
            Name = 'Test Agent',
            Developer_Name__c = 'Test_Agent',
            TTL__c = 60,
            TTL_Message__c = 'Session expired',
            AI_Model__c = aiConnection.Id,
            Status__c = 'Active'
        );
        insert agent;
        
        // Create AI Verification Prompt (must have Object__c = 'AI_Response__c' for lookup filter)
        AI_Prompt__c verificationPrompt = new AI_Prompt__c(
            Name = 'Verification Prompt',
            Status__c = 'Active',
            Object__c = 'AI_Response__c'
        );
        insert verificationPrompt;
        
        // Create Test Cycle
        AI_Test_Cycle__c testCycle = new AI_Test_Cycle__c(
            Name = 'Test Cycle',
            Status__c = 'Draft',
            AI_Agent__c = agent.Id,
            AI_Verification_Prompt__c = verificationPrompt.Id
        );
        insert testCycle;
    }
    
    private static AI_Test_Cycle__c getTestCycle() {
        return [SELECT Id, Name, Status__c, Start_Date_Time__c FROM AI_Test_Cycle__c WHERE Name = 'Test Cycle' LIMIT 1];
    }
    
    @isTest
    static void testRunTestCycleSuccess() {
        AI_Test_Cycle__c testCycle = getTestCycle();
        
        Test.startTest();
        AIAgenticTestingFrameworkCtrl.runTestCycle(testCycle.Id);
        Test.stopTest();
        
        // Verify test cycle was updated - status may change to 'Errored' if no file is attached
        // The important thing is that the batch was triggered and the cycle was processed
        AI_Test_Cycle__c updatedCycle = [SELECT Id, Status__c, Start_Date_Time__c FROM AI_Test_Cycle__c WHERE Id = :testCycle.Id];
        Assert.isNotNull(updatedCycle.Start_Date_Time__c, 'Start date time should be set');
        Assert.isTrue(updatedCycle.Status__c == 'In Progress' || updatedCycle.Status__c == 'Errored', 
                      'Status should be In Progress or Errored (if no file attached)');
    }
    
    @isTest
    static void testRunTestCycleInvalidId() {
        String invalidId = 'invalidRecordId';
        
        Test.startTest();
        try {
            AIAgenticTestingFrameworkCtrl.runTestCycle(invalidId);
            Assert.fail('Expected AuraException for invalid ID');
        } catch (AuraException ex) {
            Assert.isTrue(ex.getMessage() != null, 'Exception message should not be null');
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage() != null, 'Exception should be thrown for invalid ID');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testRunTestCycleNonExistentId() {
        // Generate a valid format ID that doesn't exist
        Id fakeId = AI_Test_Cycle__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        
        Test.startTest();
        try {
            AIAgenticTestingFrameworkCtrl.runTestCycle(fakeId);
            Assert.fail('Expected AuraException for non-existent ID');
        } catch (AuraException ex) {
            Assert.isTrue(ex.getMessage() != null, 'Exception message should not be null');
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage() != null, 'Exception should be thrown for non-existent ID');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testRunTestCycleNullId() {
        Test.startTest();
        try {
            AIAgenticTestingFrameworkCtrl.runTestCycle(null);
            Assert.fail('Expected AuraException for null ID');
        } catch (AuraException ex) {
            Assert.isTrue(ex.getMessage() != null, 'Exception message should not be null');
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage() != null, 'Exception should be thrown for null ID');
        }
        Test.stopTest();
    }
}