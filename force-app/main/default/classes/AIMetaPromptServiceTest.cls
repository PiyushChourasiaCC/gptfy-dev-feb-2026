/**
 * @description Test class for AIMetaPromptService
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 03-02-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
@isTest
private class AIMetaPromptServiceTest {
    
    @testSetup
    static void setupTestData() {
        // Create Meta Prompt record
        AI_GPTfy_Warehouse__c metaPrompt = new AI_GPTfy_Warehouse__c(
            Type__c = 'Prompt Factory',
            Sub_Type__c = 'Meta Prompt',
            Value__c = 'You are an expert prompt engineer. Generate a golden prompt based on the following context:\n\n{CONTEXT}'
        );
        insert metaPrompt;
        
        // Create Company Context record
        AI_GPTfy_Warehouse__c companyContext = new AI_GPTfy_Warehouse__c(
            Type__c = 'Prompt Factory',
            Sub_Type__c = 'Company Context',
            Value__c = 'Company: Acme Corp\nIndustry: Technology\nFocus: Customer Success'
        );
        insert companyContext;
        
        // Create AI Connection
        AI_Connection__c connection = new AI_Connection__c(
            Name = 'Test Chat Model',
            Type__c = AIConstants.AI_MODEL_TYPE_CHAT,
            AI_Technology__c = 'OpenAI_ChatGPT',
            Model__c = 'gpt-4',
            EndPoint_URL__c = 'https://api.openai.com/v1/chat/completions',
            Temperature__c = 0.7,
            Max_Tokens__c = 4000
        );
        insert connection;
    }
    
    @isTest
    static void testLoadMetaPrompt() {
        Test.startTest();
        String metaPrompt = AIMetaPromptService.loadMetaPrompt();
        Test.stopTest();
        
        Assert.isNotNull(metaPrompt, 'Meta prompt should not be null');
        Assert.isTrue(metaPrompt.contains('expert prompt engineer'), 'Should contain meta prompt text');
    }
    
    @isTest
    static void testLoadMetaPromptNotFound() {
        // Delete all meta prompts
        delete [SELECT Id FROM AI_GPTfy_Warehouse__c WHERE Sub_Type__c = 'Meta Prompt'];
        
        Test.startTest();
        Exception caughtException;
        try {
            AIMetaPromptService.loadMetaPrompt();
        } catch (Exception e) {
            caughtException = e;
        }
        Test.stopTest();
        
        Assert.isNotNull(caughtException, 'Should throw exception when meta prompt not found');
        Assert.isTrue(caughtException.getMessage().contains('No Meta Prompt found'), 
                      'Should have appropriate error message');
    }
    
    @isTest
    static void testLoadCompanyContext() {
        Test.startTest();
        String companyContext = AIMetaPromptService.loadCompanyContext();
        Test.stopTest();
        
        Assert.isNotNull(companyContext, 'Company context should not be null');
        Assert.isTrue(companyContext.contains('Acme Corp'), 'Should contain company context text');
    }
    
    @isTest
    static void testLoadCompanyContextNotFound() {
        // Delete all company context records
        delete [SELECT Id FROM AI_GPTfy_Warehouse__c WHERE Sub_Type__c = 'Company Context'];
        
        Test.startTest();
        String companyContext = AIMetaPromptService.loadCompanyContext();
        Test.stopTest();
        
        Assert.isNull(companyContext, 'Should return null when company context not found');
    }
    
    @isTest
    static void testGenerateGoldenPromptSuccess() {
        AI_Connection__c connection = [SELECT Id FROM AI_Connection__c LIMIT 1];
        String contextPackage = '# Account 360 Context Package\n\nTest context for Account object.';
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Test.startTest();
        String goldenPrompt = AIMetaPromptService.generateGoldenPrompt(contextPackage, connection.Id);
        Test.stopTest();
        
        Assert.isNotNull(goldenPrompt, 'Golden prompt should not be null');
        Assert.isTrue(goldenPrompt.length() > 0, 'Golden prompt should not be empty');
    }
    
    @isTest
    static void testGenerateGoldenPromptEmptyContext() {
        AI_Connection__c connection = [SELECT Id FROM AI_Connection__c LIMIT 1];
        
        Test.startTest();
        Exception caughtException;
        try {
            AIMetaPromptService.generateGoldenPrompt('', connection.Id);
        } catch (Exception e) {
            caughtException = e;
        }
        Test.stopTest();
        
        Assert.isNotNull(caughtException, 'Should throw exception for empty context');
        Assert.isTrue(caughtException.getMessage().contains('Context package cannot be empty'), 
                      'Should have appropriate error message');
    }
    
    @isTest
    static void testGenerateGoldenPromptNullConnection() {
        String contextPackage = '# Account 360 Context Package\n\nTest context.';
        
        Test.startTest();
        Exception caughtException;
        try {
            AIMetaPromptService.generateGoldenPrompt(contextPackage, null);
        } catch (Exception e) {
            caughtException = e;
        }
        Test.stopTest();
        
        Assert.isNotNull(caughtException, 'Should throw exception for null connection');
        Assert.isTrue(caughtException.getMessage().contains('AI Connection ID is required'), 
                      'Should have appropriate error message');
    }
    
    @isTest
    static void testGenerateGoldenPromptConnectionNotFound() {
        String contextPackage = '# Account 360 Context Package\n\nTest context.';
        
        // Create a valid ID format but for a non-existent record
        String prefix = Schema.SObjectType.AI_Connection__c.getKeyPrefix();
        Id fakeConnectionId = Id.valueOf(prefix + '000000000AAA');
        
        Test.startTest();
        Exception caughtException;
        try {
            AIMetaPromptService.generateGoldenPrompt(contextPackage, fakeConnectionId);
        } catch (Exception e) {
            caughtException = e;
        }
        Test.stopTest();
        
        Assert.isNotNull(caughtException, 'Should throw exception for connection not found');
    }
    
    /**
     * Mock HTTP callout class for testing
     */
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            Map<String, Object> responseBody = new Map<String, Object>{
                'choices' => new List<Object>{
                    new Map<String, Object>{
                        'message' => new Map<String, Object>{
                            'content' => 'This is a generated golden prompt for Account 360 intelligence report. It includes comprehensive instructions for data analysis and presentation.'
                        }
                    }
                }
            };
            
            res.setBody(JSON.serialize(responseBody));
            return res;
        }
    }
}
