/**
 * @description Test class for AIAgenticFunctionHandler and AIAgenticInterface
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AIAgenticFunctionHandlerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account acc = new Account(Name = 'Test Account', Industry = 'Technology', Website = 'www.test.com');
        insert acc;
        
        // Create test Contact
        Contact con = new Contact(FirstName = 'John', LastName = 'Doe', Email = 'john.doe@test.com', AccountId = acc.Id);
        insert con;
        
        // Create test Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        
        // Create test Case
        Case cs = new Case(Subject = 'Test Case', AccountId = acc.Id, ContactId = con.Id, Status = 'New');
        insert cs;
        
        // Create test Task
        Task t = new Task(Subject = 'Test Task', WhatId = acc.Id, Status = 'Not Started');
        insert t;
    }
    
    private static Account getTestAccount() {
        return [SELECT Id, Name FROM Account LIMIT 1];
    }
    
    private static Contact getTestContact() {
        return [SELECT Id, LastName FROM Contact LIMIT 1];
    }
    
    private static Case getTestCase() {
        return [SELECT Id, CaseNumber FROM Case LIMIT 1];
    }
    
    @isTest
    static void testFindAccountByName() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'Test'};
        
        Test.startTest();
        String result = handler.executeMethod('find_Account_by_name', params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testFindAccountByIndustry() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Industry' => 'Technology'};
        
        Test.startTest();
        String result = handler.executeMethod('find_Account_by_industry', params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testFindAccountById() {
        Account acc = getTestAccount();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Id' => acc.Id};
        
        Test.startTest();
        String result = handler.executeMethod('find_Account_by_Id', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.areEqual(acc.Id, resultMap.get('AccountId'), 'Account ID should match');
    }
    
    @isTest
    static void testFindOpportunityByName() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'Test'};
        
        Test.startTest();
        String result = handler.executeMethod('find_Opportunity_by_name', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.isTrue((Integer)resultMap.get('count') > 0, 'Should find opportunities');
    }
    
    @isTest
    static void testFindContactByLastname() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'LastName' => 'Doe'};
        
        Test.startTest();
        String result = handler.executeMethod('find_Contact_by_lastname', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.isTrue((Integer)resultMap.get('count') > 0, 'Should find contacts');
    }
    
    @isTest
    static void testSearchCaseByCaseNumber() {
        Case cs = getTestCase();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'CaseNumber' => cs.CaseNumber};
        
        Test.startTest();
        String result = handler.executeMethod('search_Case_by_casenumber', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
    }
    
    @isTest
    static void testCreateCase() {
        Contact con = getTestContact();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'Subject' => 'New Test Case',
            'ContactId' => con.Id,
            'Status' => 'New'
        };
        
        Test.startTest();
        String result = handler.executeMethod('create_Case', params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testCreateCaseForContact() {
        Contact con = getTestContact();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'Subject' => 'Contact Case',
            'ContactId' => con.Id
        };
        
        Test.startTest();
        String result = handler.executeMethod('create_Case_for_Contact', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
    }
    
    @isTest
    static void testCreateCaseForAccount() {
        Account acc = getTestAccount();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'Subject' => 'Account Case',
            'AccountId' => acc.Id
        };
        
        Test.startTest();
        String result = handler.executeMethod('create_Case_for_Account', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
    }
    
    @isTest
    static void testAddCaseComment() {
        Case cs = getTestCase();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'ParentId' => cs.Id,
            'CommentBody' => 'Test comment'
        };
        
        Test.startTest();
        String result = handler.executeMethod('add_Case_Comment', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
    }
    
    @isTest
    static void testGetAccountDetailsByName() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'Test'};
        
        Test.startTest();
        String result = handler.executeMethod('get_Account_details_by_name', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.isNotNull(resultMap.get('account'), 'Should return account');
        Assert.isNotNull(resultMap.get('contacts'), 'Should return contacts');
        Assert.isNotNull(resultMap.get('opportunities'), 'Should return opportunities');
    }
    
    @isTest
    static void testGetAccountDetailsByNameNotFound() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'NonExistentAccount12345'};
        
        Test.startTest();
        String result = handler.executeMethod('get_Account_details_by_name', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean)resultMap.get('success'), 'Should not be successful');
        Assert.areEqual('No Account found', resultMap.get('message'), 'Should return not found message');
    }
    
    @isTest
    static void testGetAccountDetailsById() {
        Account acc = getTestAccount();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Id' => acc.Id};
        
        Test.startTest();
        String result = handler.executeMethod('get_Account_details_by_Id', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.isNotNull(resultMap.get('AccountId'), 'Should return AccountId');
    }
    
    @isTest
    static void testGetAccountDetailsByIdNotFound() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        // Use a fake but valid-format Account ID
        Map<String, Object> params = new Map<String, Object>{'Id' => '001000000000000AAA'};
        
        Test.startTest();
        String result = handler.executeMethod('get_Account_details_by_Id', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean)resultMap.get('success'), 'Should not be successful');
    }
    
    @isTest
    static void testCreateAccountByName() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'Name' => 'New Created Account'
        };
        
        Test.startTest();
        String result = handler.executeMethod('create_Account_by_Name', params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testCreateContactByName() {
        Account acc = getTestAccount();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'FirstName' => 'Jane',
            'LastName' => 'Smith',
            'AccountId' => acc.Id
        };
        
        Test.startTest();
        String result = handler.executeMethod('create_Contact_by_Name', params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testUndefinedMethod() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>();
        
        Test.startTest();
        String result = handler.executeMethod('undefined_method', params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean)resultMap.get('success'), 'Should not be successful');
        Assert.areEqual('Method is not defined.', resultMap.get('message'), 'Should return method not defined');
    }
    
    @isTest
    static void testFindAccountNoResults() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'ZZZNONEXISTENT999'};
        
        Test.startTest();
        String result = handler.findAccount(params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testFindOpportunityNoResults() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'ZZZNONEXISTENT999'};
        
        Test.startTest();
        String result = handler.findOpportunity(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.areEqual(0, resultMap.get('count'), 'Should find 0 opportunities');
    }
    
    @isTest
    static void testFindContactNoResults() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'LastName' => 'ZZZNONEXISTENT999'};
        
        Test.startTest();
        String result = handler.findContact(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.areEqual(0, resultMap.get('count'), 'Should find 0 contacts');
    }
    
    @isTest
    static void testFindCaseNoResults() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'CaseNumber' => '99999999'};
        
        Test.startTest();
        String result = handler.findCase(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.areEqual(0, resultMap.get('count'), 'Should find 0 cases');
    }
    
    @isTest
    static void testCreateAccountError() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        // Missing required Name field should cause error
        Map<String, Object> params = new Map<String, Object>{
            'Industry' => 'Technology'
        };
        
        Test.startTest();
        String result = handler.createAccount(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.areEqual('errored', resultMap.get('status'), 'Should be errored');
    }
    
    @isTest
    static void testCreateContactError() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        // Missing required LastName field should cause error
        Map<String, Object> params = new Map<String, Object>{
            'FirstName' => 'Test'
        };
        
        Test.startTest();
        String result = handler.createContact(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.areEqual('errored', resultMap.get('status'), 'Should be errored');
    }
    
    @isTest
    static void testInterfaceImplementation() {
        // Test that AIAgenticFunctionHandler implements AIAgenticInterface
        AIAgenticInterface handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'Test'};
        
        Test.startTest();
        String result = handler.executeMethod('find_Account_by_name', params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testFindAccountByIdDirect() {
        Account acc = getTestAccount();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Id' => acc.Id};
        
        Test.startTest();
        String result = handler.findAccountById(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
    }
    
    @isTest
    static void testFindAccountByIdNoResults() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Id' => '001000000000000AAA'};
        
        Test.startTest();
        String result = handler.findAccountById(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.areEqual(0, resultMap.get('count'), 'Should find 0 accounts');
    }
    
    @isTest
    static void testCreateCaseDirect() {
        Contact con = getTestContact();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'Subject' => 'Direct Case',
            'ContactId' => con.Id
        };
        
        Test.startTest();
        String result = handler.createCase(params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testAddCaseCommentDirect() {
        Case cs = getTestCase();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'ParentId' => cs.Id,
            'CommentBody' => 'Direct comment test'
        };
        
        Test.startTest();
        String result = handler.addCaseComment(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
    }
    
    @isTest
    static void testFetchAccountDetailsDirect() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'Test'};
        
        Test.startTest();
        String result = handler.fetchAccountDetails(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.isNotNull(resultMap.get('account'), 'Should return account');
    }
    
    @isTest
    static void testFetchAccountDetailsByIdDirect() {
        Account acc = getTestAccount();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Id' => acc.Id};
        
        Test.startTest();
        String result = handler.fetchAccountDetailsById(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.isNotNull(resultMap.get('tasks'), 'Should return tasks');
    }
    
    @isTest
    static void testFetchAccountDetailsNotFound() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'ZZZNONEXISTENT999'};
        
        Test.startTest();
        String result = handler.fetchAccountDetails(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean)resultMap.get('success'), 'Should not be successful');
        Assert.areEqual('No Account found', resultMap.get('message'), 'Should return not found');
    }
    
    @isTest
    static void testFetchAccountDetailsByIdNotFound() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Id' => '001000000000000AAA'};
        
        Test.startTest();
        String result = handler.fetchAccountDetailsById(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isFalse((Boolean)resultMap.get('success'), 'Should not be successful');
    }
    
    @isTest
    static void testCreateAccountDirect() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'Name' => 'Direct Created Account',
            'Industry' => 'Technology'
        };
        
        Test.startTest();
        String result = handler.createAccount(params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testCreateContactDirect() {
        Account acc = getTestAccount();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'FirstName' => 'Direct',
            'LastName' => 'Contact',
            'AccountId' => acc.Id
        };
        
        Test.startTest();
        String result = handler.createContact(params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testMultipleParametersInQuery() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{
            'Name' => 'Test',
            'Industry' => 'Technology'
        };
        
        Test.startTest();
        String result = handler.findAccount(params);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isNotNull(resultMap, 'Result map should not be null');
    }
    
    @isTest
    static void testFindOpportunityDirect() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'Name' => 'Test Opportunity'};
        
        Test.startTest();
        String result = handler.findOpportunity(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
    }
    
    @isTest
    static void testFindContactDirect() {
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'LastName' => 'Doe'};
        
        Test.startTest();
        String result = handler.findContact(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.isNotNull(resultMap.get('ContactId'), 'Should return ContactId');
    }
    
    @isTest
    static void testFindCaseDirect() {
        Case cs = getTestCase();
        AIAgenticFunctionHandler handler = new AIAgenticFunctionHandler();
        Map<String, Object> params = new Map<String, Object>{'CaseNumber' => cs.CaseNumber};
        
        Test.startTest();
        String result = handler.findCase(params);
        Test.stopTest();
        
        Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(result);
        Assert.isTrue((Boolean)resultMap.get('success'), 'Should be successful');
        Assert.isNotNull(resultMap.get('ParentId'), 'Should return ParentId');
    }
}