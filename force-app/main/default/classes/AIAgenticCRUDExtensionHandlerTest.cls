/**
 * @description Test class for AIAgenticCRUDExtensionHandler
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AIAgenticCRUDExtensionHandlerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account',
            Industry = 'Technology',
            Phone = '1234567890',
            Website = 'www.test.com'
        );
        insert testAccount;
    }
    
    private static Account getTestAccount() {
        return [SELECT Id, Name, Industry, Phone, Website FROM Account WHERE Name = 'Test Account' LIMIT 1];
    }
    
    @isTest
    static void testUpdateAccountById() {
        Account testAccount = getTestAccount();
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'recordId' => testAccount.Id,
            'Industry' => 'Healthcare',
            'Phone' => '9876543210'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Id', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) response.get('success'), 'Update should be successful');
        Assert.areEqual(testAccount.Id, response.get('recordId'), 'Record ID should match');
        
        // Verify the update
        Account updatedAccount = [SELECT Id, Industry, Phone FROM Account WHERE Id = :testAccount.Id];
        Assert.areEqual('Healthcare', updatedAccount.Industry, 'Industry should be updated');
        Assert.areEqual('9876543210', updatedAccount.Phone, 'Phone should be updated');
    }
    
    @isTest
    static void testUpdateAccountByIdMissingRecordId() {
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'Industry' => 'Healthcare'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Id', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) response.get('success'), 'Update should fail without recordId');
        Assert.isTrue(((String) response.get('message')).contains('recordId'), 'Error message should mention recordId');
    }
    
    @isTest
    static void testUpdateAccountByName() {
        Account testAccount = getTestAccount();
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'Name' => 'Test Account',
            'Industry' => 'Finance',
            'Website' => 'www.updated.com'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Name', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) response.get('success'), 'Update should be successful');
        Assert.areEqual(testAccount.Id, response.get('recordId'), 'Record ID should match');
        Assert.areEqual('Test Account', response.get('accountName'), 'Account name should match');
        
        // Verify the update
        Account updatedAccount = [SELECT Id, Industry, Website FROM Account WHERE Id = :testAccount.Id];
        Assert.areEqual('Finance', updatedAccount.Industry, 'Industry should be updated');
        Assert.areEqual('www.updated.com', updatedAccount.Website, 'Website should be updated');
    }
    
    @isTest
    static void testUpdateAccountByNameMissingName() {
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'Industry' => 'Healthcare'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Name', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) response.get('success'), 'Update should fail without Name');
        Assert.isTrue(((String) response.get('message')).contains('Name'), 'Error message should mention Name');
    }
    
    @isTest
    static void testUpdateAccountByNameNotFound() {
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'Name' => 'Non Existent Account',
            'Industry' => 'Healthcare'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Name', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) response.get('success'), 'Update should fail for non-existent account');
        Assert.isTrue(((String) response.get('message')).contains('No Account found'), 'Error message should indicate account not found');
    }
    
    @isTest
    static void testExecuteMethodUnknownMethod() {
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'recordId' => 'testId'
        };
        
        Test.startTest();
        String result = handler.executeMethod('unknown_method', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) response.get('success'), 'Unknown method should return failure');
        Assert.isTrue(((String) response.get('message')).contains('Method is not defined'), 'Error message should indicate undefined method');
    }
    
    @isTest
    static void testUpdateAccountByIdWithException() {
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        // Use invalid record ID to trigger exception
        Map<String, Object> parameters = new Map<String, Object>{
            'recordId' => 'invalidId',
            'Industry' => 'Healthcare'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Id', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) response.get('success'), 'Update should fail with invalid ID');
    }
    
    @isTest
    static void testUpdateAccountByNameWithInvalidField() {
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'Name' => 'Test Account',
            'InvalidField__c' => 'test value'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Name', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean) response.get('success'), 'Update should fail with invalid field');
        Assert.isNotNull(response.get('stackTrace'), 'Stack trace should be present');
    }
    
    @isTest
    static void testUpdateAccountByIdNoFieldsToUpdate() {
        Account testAccount = getTestAccount();
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        // Only provide recordId, no other fields
        Map<String, Object> parameters = new Map<String, Object>{
            'recordId' => testAccount.Id
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Id', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) response.get('success'), 'Update should succeed even with no fields');
        Assert.areEqual(0, response.get('updatedFields'), 'Updated fields count should be 0');
    }
    
    @isTest
    static void testUpdateAccountByNameNoFieldsToUpdate() {
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        // Only provide Name, no other fields
        Map<String, Object> parameters = new Map<String, Object>{
            'Name' => 'Test Account'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Name', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) response.get('success'), 'Update should succeed even with no fields');
        Assert.areEqual(0, response.get('updatedFields'), 'Updated fields count should be 0');
    }
    
    @isTest
    static void testUpdateAccountDirectMethod() {
        Account testAccount = getTestAccount();
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'recordId' => testAccount.Id,
            'Description' => 'Updated Description'
        };
        
        Test.startTest();
        String result = handler.updateAccount(parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) response.get('success'), 'Direct method call should be successful');
    }
    
    @isTest
    static void testUpdateAccountByNameDirectMethod() {
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'Name' => 'Test Account',
            'Description' => 'Updated via direct method'
        };
        
        Test.startTest();
        String result = handler.updateAccountByName(parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) response.get('success'), 'Direct method call should be successful');
    }
    
    @isTest
    static void testUpdateAccountMultipleFields() {
        Account testAccount = getTestAccount();
        AIAgenticCRUDExtensionHandler handler = new AIAgenticCRUDExtensionHandler();
        
        Map<String, Object> parameters = new Map<String, Object>{
            'recordId' => testAccount.Id,
            'Industry' => 'Manufacturing',
            'Phone' => '5551234567',
            'Website' => 'www.manufacturing.com',
            'Description' => 'Manufacturing company'
        };
        
        Test.startTest();
        String result = handler.executeMethod('update_Account_by_Id', parameters);
        Test.stopTest();
        
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean) response.get('success'), 'Update should be successful');
        Assert.areEqual(4, response.get('updatedFields'), 'Should update 4 fields');
    }
}