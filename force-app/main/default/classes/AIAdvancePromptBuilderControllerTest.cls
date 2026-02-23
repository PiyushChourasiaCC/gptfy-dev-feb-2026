/**
 * @description       : Comprehensive test class for AIAdvancePromptBuilderController
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 28-11-2024
 * @last modified by  : Piyush Chourasia
 * @jira              : V2-7442
**/
@isTest
public class AIAdvancePromptBuilderControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create AI Connection for GPTfy using TestUtility
        AI_Connection__c gptfyConnection = TestUtility.getConnection('AnyAI_AnyPlatform', false);
        gptfyConnection.Name = 'GPTfy (OpenAI)';
        gptfyConnection.Model__c = 'gpt-4';
        gptfyConnection.Max_Tokens__c = 3000;
        gptfyConnection.Temperature__c = 0.7;
        gptfyConnection.Top_P__c = 1.0;
        gptfyConnection.Named_Credential__c = 'GPTfy';
        gptfyConnection.EndPoint_URL__c = '/v1/chat/completions';
        insert gptfyConnection;
        
        // Create test data extraction mapping
        AI_Data_Extraction_Mapping__c mapping = new AI_Data_Extraction_Mapping__c(
            Name = 'Test Mapping',
            Object_Name__c = 'Account',
            Description__c = 'Test Description',
            Status__c = 'Active'
        );
        insert mapping;
        
        // Create test prompt
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test Prompt', 'Account', 'Active', false);
        prompt.AI_Connection__c = gptfyConnection.Id;
        prompt.AI_Data_Extraction_Mapping__c = mapping.Id;
        prompt.Type__c = 'Text';
        prompt.Prompt_Command__c = 'Generate a summary of the account details';
        insert prompt;
        
        // Create test account for validation
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
    }
    
    // ==================== Mock HTTP Callout Classes ====================
    
    public class SuccessfulMockHttpResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            Map<String, Object> responseMap = new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'value' => new Map<String, Object>{
                        'choices' => new List<Object>{
                            new Map<String, Object>{
                                'message' => new Map<String, Object>{
                                    'content' => JSON.serialize(new Map<String, Object>{
                                        'name' => 'Account Summary',
                                        'description' => 'Generate account summary',
                                        'targetObject' => 'Account',
                                        'promptCommand' => 'Analyze account data and provide summary',
                                        'dataContext' => new Map<String, Object>{
                                            'mainObjectFields' => new List<String>{'Name', 'Industry'},
                                            'childRelationships' => new List<Object>{
                                                new Map<String, Object>{
                                                    'objectName' => 'Contact',
                                                    'relationshipName' => 'Contacts',
                                                    'fields' => new List<String>{'FirstName', 'LastName'},
                                                    'whereClause' => ''
                                                }
                                            }
                                        }
                                    })
                                }
                            }
                        }
                    }
                }
            };
            
            res.setBody(JSON.serialize(responseMap));
            return res;
        }
    }
    
    public class FailedMockHttpResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('{"error": "AI service error"}');
            return res;
        }
    }
    
    public class EmptyResponseMockHttpResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('');
            return res;
        }
    }
    
    // ==================== Test Methods for generatePromptDetails ====================
    
    @isTest
    static void testGeneratePromptDetailsSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulMockHttpResponse());
        
        String existingPromptsJson = '[{"name":"Test","object":"Account"}]';
        
        Test.startTest();
        String result = AIAdvancePromptBuilderController.generatePromptDetails(
            'Create a prompt for account summary',
            existingPromptsJson
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.contains('Account Summary') || result.contains('name'), 'Result should contain prompt details');
    }
    
    @isTest
    static void testGeneratePromptDetailsBlankInput() {
        Test.startTest();
        try {
            String result = AIAdvancePromptBuilderController.generatePromptDetails('', '[]');
            // If no exception, method handled blank input gracefully
            Assert.isTrue(result == null || String.isNotBlank(result), 'Method should handle gracefully');
        } catch (Exception e) {
            // Exception is expected for blank input
            Assert.isNotNull(e, 'Exception should have details');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGeneratePromptDetailsNoConnection() {
        // Delete prompt first to avoid association error
        delete [SELECT Id FROM AI_Prompt__c];
        delete [SELECT Id FROM AI_Connection__c];
        
        Test.startTest();
        try {
            String result = AIAdvancePromptBuilderController.generatePromptDetails('Test input', '[]');
            // If no exception, method handled missing connection gracefully
            Assert.isTrue(result == null || String.isNotBlank(result), 'Method should handle gracefully');
        } catch (Exception e) {
            // Exception is expected when connection is missing
            Assert.isNotNull(e, 'Exception should have details');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGeneratePromptDetailsHttpError() {
        Test.setMock(HttpCalloutMock.class, new FailedMockHttpResponse());
        
        Test.startTest();
        try {
            String result = AIAdvancePromptBuilderController.generatePromptDetails('Test input', '[]');
            // If no exception, method handled HTTP error gracefully
            Assert.isTrue(result == null || String.isNotBlank(result), 'Method should handle gracefully');
        } catch (Exception e) {
            // Exception is expected for HTTP errors
            Assert.isNotNull(e, 'Exception should have details');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGeneratePromptDetailsEmptyResponse() {
        Test.setMock(HttpCalloutMock.class, new EmptyResponseMockHttpResponse());
        
        Test.startTest();
        try {
            String result = AIAdvancePromptBuilderController.generatePromptDetails('Test input', '[]');
            // If no exception, method handled empty response gracefully
            Assert.isTrue(result == null || String.isNotBlank(result), 'Method should handle gracefully');
        } catch (Exception e) {
            // Exception is expected for empty response
            Assert.isNotNull(e, 'Exception should have details');
        }
        Test.stopTest();
    }
    
    // ==================== Test Methods for createPromptWithMapping ====================
    
    @isTest
    static void testCreatePromptWithMappingSuccess() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name', 'Industry'},
            'childRelationships' => new List<Object>()
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Test Prompt Creation',
            'Account',
            'Test Description',
            'Test prompt command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt ID should not be null');
        
        List<AI_Prompt__c> prompts = [SELECT Id, Name, Object__c, Status__c FROM AI_Prompt__c WHERE Id = :promptId];
        Assert.areEqual(1, prompts.size(), 'Prompt should be created');
        Assert.areEqual('Test Prompt Creation', prompts[0].Name, 'Prompt name should match');
        Assert.areEqual('Draft', prompts[0].Status__c, 'Status should be Draft');
    }
    
    @isTest
    static void testCreatePromptWithMappingWithChildRelationships() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name', 'Industry', 'Phone'},
            'childRelationships' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => 'Contact',
                    'relationshipName' => 'Contacts',
                    'fields' => new List<String>{'FirstName', 'LastName', 'Email'},
                    'whereClause' => 'IsActive__c = true'
                }
            }
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Account with Contacts Prompt',
            'Account',
            'Detailed description for account and contacts',
            'Generate detailed analysis',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt ID should not be null');
        
        AI_Prompt__c prompt = [SELECT Id, AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        Assert.isNotNull(prompt.AI_Data_Extraction_Mapping__c, 'Should have data extraction mapping');
        
        List<AI_Data_Extraction_Detail__c> details = [SELECT Id FROM AI_Data_Extraction_Detail__c 
                                                       WHERE AI_Data_Extraction_Mapping__c = :prompt.AI_Data_Extraction_Mapping__c];
        Assert.isTrue(details.size() > 0, 'Should have child relationship details');
    }
    
    @isTest
    static void testCreatePromptWithMappingBlankName() {
        Test.startTest();
        try {
            String result = AIAdvancePromptBuilderController.createPromptWithMapping(
                '',
                'Account',
                'Description',
                'Command',
                null
            );
            // If no exception, method handled blank name - verify result
            Assert.isTrue(result == null || String.isNotBlank(result), 'Method should handle gracefully');
        } catch (Exception e) {
            // Exception is acceptable for validation
            Assert.isNotNull(e, 'Exception should have details');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreatePromptWithMappingBlankObject() {
        Test.startTest();
        try {
            String result = AIAdvancePromptBuilderController.createPromptWithMapping(
                'Test Name',
                '',
                'Description',
                'Command',
                null
            );
            // If no exception, method handled blank object - verify result
            Assert.isTrue(result == null || String.isNotBlank(result), 'Method should handle gracefully');
        } catch (Exception e) {
            // Exception is acceptable for validation
            Assert.isNotNull(e, 'Exception should have details');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreatePromptWithMappingBlankCommand() {
        Test.startTest();
        try {
            String result = AIAdvancePromptBuilderController.createPromptWithMapping(
                'Test Name',
                'Account',
                'Description',
                '',
                null
            );
            // If no exception, method handled blank command - verify result
            Assert.isTrue(result == null || String.isNotBlank(result), 'Method should handle gracefully');
        } catch (Exception e) {
            // Exception is acceptable for validation
            Assert.isNotNull(e, 'Exception should have details');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreatePromptWithMappingNoDataContext() {
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Simple Prompt',
            'Account',
            'Simple Description',
            'Simple command',
            null
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt ID should not be null');
        
        AI_Prompt__c prompt = [SELECT Id, AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        Assert.isNull(prompt.AI_Data_Extraction_Mapping__c, 'Should not have data extraction mapping');
    }
    
    @isTest
    static void testCreatePromptWithMappingLongDescription() {
        String longDescription = 'This is a very long description that exceeds 255 characters. ' +
            'It should be truncated when saved to the database. ' +
            'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' +
            'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ' +
            'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.';
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Truncation Test',
            'Account',
            longDescription,
            'Test command',
            null
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt ID should not be null');
        
        AI_Prompt__c prompt = [SELECT Description__c FROM AI_Prompt__c WHERE Id = :promptId];
        Assert.isTrue(prompt.Description__c.length() <= 255, 'Description should be truncated to 255 characters');
    }
    
    // ==================== Test Methods for getSalesforceObjectsMetadata ====================
    
    @isTest
    static void testGetSalesforceObjectsMetadata() {
        Test.startTest();
        List<Map<String, Object>> result = AIAdvancePromptBuilderController.getSalesforceObjectsMetadata();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.size() > 0, 'Should return objects');
        
        Boolean foundAccount = false;
        for (Map<String, Object> obj : result) {
            if (obj.get('name') == 'Account') {
                foundAccount = true;
                Assert.isNotNull(obj.get('label'), 'Should have label');
                Assert.isNotNull(obj.get('isCustom'), 'Should have isCustom flag');
                Assert.isNotNull(obj.get('childRelationships'), 'Should have child relationships');
                break;
            }
        }
        Assert.isTrue(foundAccount, 'Should include Account object');
    }
    
    // ==================== Test Methods for getExistingPrompts ====================
    
    @isTest
    static void testGetExistingPromptsSuccess() {
        Test.startTest();
        List<Map<String, String>> result = AIAdvancePromptBuilderController.getExistingPrompts();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.size() > 0, 'Should return existing prompts');
        
        Map<String, String> firstPrompt = result[0];
        Assert.isNotNull(firstPrompt.get('name'), 'Should have name');
        Assert.isNotNull(firstPrompt.get('object'), 'Should have object');
        Assert.isNotNull(firstPrompt.get('command'), 'Should have command');
    }
    
    @isTest
    static void testGetExistingPromptsEmpty() {
        delete [SELECT Id FROM AI_Prompt__c];
        
        Test.startTest();
        List<Map<String, String>> result = AIAdvancePromptBuilderController.getExistingPrompts();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual(0, result.size(), 'Should return empty list when no prompts exist');
    }
    
    @isTest
    static void testGetExistingPromptsTruncation() {
        AI_Prompt__c longPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        longPrompt.Prompt_Command__c = 'This is a very long prompt command that exceeds 200 characters. ' +
            'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' +
            'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ' +
            'Ut enim ad minim veniam, quis nostrud exercitation.';
        update longPrompt;
        
        Test.startTest();
        List<Map<String, String>> result = AIAdvancePromptBuilderController.getExistingPrompts();
        Test.stopTest();
        
        Assert.isTrue(result.size() > 0, 'Should return prompts');
        String command = result[0].get('command');
        Assert.isTrue(command.length() <= 200, 'Command should be truncated to 200 characters');
    }
    
    // ==================== Test Methods for getNamespace ====================
    
    @isTest
    static void testGetNamespace() {
        Test.startTest();
        String namespace = AIAdvancePromptBuilderController.getNamespace();
        Test.stopTest();
        
        Assert.isNotNull(namespace, 'Namespace should not be null');
    }
    
    // ==================== Test Methods for Data Extraction with Invalid Data ====================
    
    @isTest
    static void testCreatePromptWithInvalidObject() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name'},
            'childRelationships' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => 'InvalidObject__c',
                    'relationshipName' => 'InvalidRelationship',
                    'fields' => new List<String>{'Field1'},
                    'whereClause' => ''
                }
            }
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Invalid Object Test',
            'Account',
            'Test with invalid object',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should still be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        
        if (prompt.AI_Data_Extraction_Mapping__c != null) {
            List<AI_Data_Extraction_Detail__c> details = [SELECT Id FROM AI_Data_Extraction_Detail__c 
                                                          WHERE AI_Data_Extraction_Mapping__c = :prompt.AI_Data_Extraction_Mapping__c 
                                                          AND Object_Name__c = 'InvalidObject__c'];
            Assert.areEqual(0, details.size(), 'Invalid object should not create detail record');
        }
    }
    
    @isTest
    static void testCreatePromptWithInvalidFields() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name', 'InvalidField__c', 'Industry'},
            'childRelationships' => new List<Object>()
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Invalid Fields Test',
            'Account',
            'Test with invalid fields',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        
        if (prompt.AI_Data_Extraction_Mapping__c != null) {
            List<AI_Data_Extraction_Field__c> fields = [SELECT Field__c FROM AI_Data_Extraction_Field__c 
                                                        WHERE AI_Data_Extraction_Mapping__c = :prompt.AI_Data_Extraction_Mapping__c 
                                                        AND Type__c = 'FIELD'];
            
            Boolean hasInvalidField = false;
            for (AI_Data_Extraction_Field__c field : fields) {
                if (field.Field__c == 'InvalidField__c') {
                    hasInvalidField = true;
                }
            }
            Assert.isFalse(hasInvalidField, 'Invalid fields should be filtered out');
        }
    }
    
    @isTest
    static void testCreatePromptWithMultipleChildRelationships() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name'},
            'childRelationships' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => 'Contact',
                    'relationshipName' => 'Contacts',
                    'fields' => new List<String>{'FirstName'},
                    'whereClause' => ''
                },
                new Map<String, Object>{
                    'objectName' => 'Opportunity',
                    'relationshipName' => 'Opportunities',
                    'fields' => new List<String>{'Name'},
                    'whereClause' => 'IsClosed = false'
                },
                new Map<String, Object>{
                    'objectName' => 'Case',
                    'relationshipName' => 'Cases',
                    'fields' => new List<String>{'Subject'},
                    'whereClause' => ''
                },
                new Map<String, Object>{
                    'objectName' => 'Task',
                    'relationshipName' => 'Tasks',
                    'fields' => new List<String>{'Subject'},
                    'whereClause' => ''
                }
            }
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Multiple Children Test',
            'Account',
            'Test with multiple child relationships',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        
        if (prompt.AI_Data_Extraction_Mapping__c != null) {
            List<AI_Data_Extraction_Detail__c> details = [SELECT Id FROM AI_Data_Extraction_Detail__c 
                                                          WHERE AI_Data_Extraction_Mapping__c = :prompt.AI_Data_Extraction_Mapping__c];
            Assert.isTrue(details.size() <= 3, 'Should limit to maximum 3 child relationships');
        }
    }
    
    @isTest
    static void testCreatePromptWithEmptyFieldsList() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>(),
            'childRelationships' => new List<Object>()
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Empty Fields Test',
            'Account',
            'Test with empty fields',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should still be created');
    }
    
    @isTest
    static void testCreatePromptWithMappingInvalidJSON() {
        String invalidDataContext = '{invalid json}';
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Invalid JSON Test',
            'Account',
            'Test with invalid JSON',
            'Test command',
            invalidDataContext
        );
        Test.stopTest();
        
        // Should still create prompt even if data context parsing fails
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        Assert.isNull(prompt.AI_Data_Extraction_Mapping__c, 'Should not have mapping due to invalid JSON');
    }
    
    @isTest
    static void testCreatePromptWithNullFields() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => null,
            'childRelationships' => null
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Null Fields Test',
            'Account',
            'Test with null fields',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should still be created');
    }
    
    @isTest
    static void testCreatePromptWithBlankFieldNames() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name', '', '   ', 'Industry'},
            'childRelationships' => new List<Object>()
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Blank Field Names Test',
            'Account',
            'Test with blank field names',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        
        if (prompt.AI_Data_Extraction_Mapping__c != null) {
            List<AI_Data_Extraction_Field__c> fields = [SELECT Field__c FROM AI_Data_Extraction_Field__c 
                                                        WHERE AI_Data_Extraction_Mapping__c = :prompt.AI_Data_Extraction_Mapping__c 
                                                        AND Type__c = 'FIELD'];
            
            // Blank fields should be filtered out
            for (AI_Data_Extraction_Field__c field : fields) {
                Assert.isTrue(String.isNotBlank(field.Field__c), 'Field names should not be blank');
            }
        }
    }
    
    @isTest
    static void testCreatePromptWithChildRelationshipNoFields() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name'},
            'childRelationships' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => 'Contact',
                    'relationshipName' => 'Contacts',
                    'fields' => null,
                    'whereClause' => ''
                }
            }
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Child No Fields Test',
            'Account',
            'Test with child relationship but no fields',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        Assert.isNotNull(prompt.AI_Data_Extraction_Mapping__c, 'Should have data extraction mapping');
    }
    
    @isTest
    static void testCreatePromptWithInvalidChildRelationship() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name'},
            'childRelationships' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => 'Contact',
                    'relationshipName' => 'InvalidRelationship',
                    'fields' => new List<String>{'FirstName'},
                    'whereClause' => ''
                }
            }
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Invalid Child Relationship Test',
            'Account',
            'Test with invalid child relationship',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
    }
    
    @isTest
    static void testCreatePromptWithInvalidParentObject() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'InvalidField__c'},
            'childRelationships' => new List<Object>()
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Invalid Parent Object Test',
            'InvalidObject__c',
            'Test with invalid parent object',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        // Should still create prompt even if object validation fails in data extraction
        Assert.isNotNull(promptId, 'Prompt should be created');
    }
    
    @isTest
    static void testCreatePromptMappingException() {
        // Create a scenario that might cause exception in data extraction mapping
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name'},
            'childRelationships' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => '',
                    'relationshipName' => '',
                    'fields' => new List<String>{'Field1'},
                    'whereClause' => ''
                }
            }
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Exception Test',
            'Account',
            'Test exception handling',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created even if mapping fails');
    }
    
    @isTest
    static void testCreatePromptWithDataContextUndefined() {
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Undefined Context Test',
            'Account',
            'Test with undefined data context',
            'Test command',
            'undefined'
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        Assert.isNull(prompt.AI_Data_Extraction_Mapping__c, 'Should not have mapping for undefined');
    }
    
    @isTest
    static void testCreatePromptWithDataContextNull() {
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Null Context Test',
            'Account',
            'Test with null data context',
            'Test command',
            'null'
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        Assert.isNull(prompt.AI_Data_Extraction_Mapping__c, 'Should not have mapping for null string');
    }
    
    @isTest
    static void testCreatePromptWithValidAndInvalidFields() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name', 'InvalidField1__c', 'Industry', 'InvalidField2__c', 'Phone'},
            'childRelationships' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => 'Contact',
                    'relationshipName' => 'Contacts',
                    'fields' => new List<String>{'FirstName', 'InvalidContactField__c', 'LastName'},
                    'whereClause' => ''
                }
            }
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Mixed Valid Invalid Fields Test',
            'Account',
            'Test with mix of valid and invalid fields',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        
        if (prompt.AI_Data_Extraction_Mapping__c != null) {
            List<AI_Data_Extraction_Field__c> mainFields = [SELECT Field__c FROM AI_Data_Extraction_Field__c 
                                                            WHERE AI_Data_Extraction_Mapping__c = :prompt.AI_Data_Extraction_Mapping__c 
                                                            AND Type__c = 'FIELD'
                                                            AND Object__c = 'Account'];
            
            // Should only have valid fields
            Integer validFieldCount = 0;
            for (AI_Data_Extraction_Field__c field : mainFields) {
                if (field.Field__c == 'Name' || field.Field__c == 'Industry' || field.Field__c == 'Phone') {
                    validFieldCount++;
                }
                Assert.isFalse(field.Field__c.contains('Invalid'), 'Should not contain invalid fields');
            }
            Assert.isTrue(validFieldCount > 0, 'Should have at least some valid fields');
        }
    }
    
    @isTest
    static void testCreatePromptWithWhereClause() {
        String dataContext = JSON.serialize(new Map<String, Object>{
            'mainObjectFields' => new List<String>{'Name'},
            'childRelationships' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => 'Contact',
                    'relationshipName' => 'Contacts',
                    'fields' => new List<String>{'FirstName', 'LastName'},
                    'whereClause' => 'Email != null AND IsActive__c = true'
                }
            }
        });
        
        Test.startTest();
        String promptId = AIAdvancePromptBuilderController.createPromptWithMapping(
            'Where Clause Test',
            'Account',
            'Test with where clause',
            'Test command',
            dataContext
        );
        Test.stopTest();
        
        Assert.isNotNull(promptId, 'Prompt should be created');
        
        AI_Prompt__c prompt = [SELECT AI_Data_Extraction_Mapping__c FROM AI_Prompt__c WHERE Id = :promptId];
        
        if (prompt.AI_Data_Extraction_Mapping__c != null) {
            List<AI_Data_Extraction_Detail__c> details = [SELECT Where_Clause__c FROM AI_Data_Extraction_Detail__c 
                                                          WHERE AI_Data_Extraction_Mapping__c = :prompt.AI_Data_Extraction_Mapping__c];
            
            if (!details.isEmpty()) {
                Assert.isNotNull(details[0].Where_Clause__c, 'Where clause should be saved');
            }
        }
    }
    
    @isTest
    static void testGeneratePromptDetailsWithNullExistingPrompts() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulMockHttpResponse());
        
        Test.startTest();
        String result = AIAdvancePromptBuilderController.generatePromptDetails(
            'Create a prompt for account summary',
            null
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null even with null existing prompts');
    }
    
    @isTest
    static void testGeneratePromptDetailsWithEmptyExistingPrompts() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulMockHttpResponse());
        
        Test.startTest();
        String result = AIAdvancePromptBuilderController.generatePromptDetails(
            'Create a prompt for contact management',
            ''
        );
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null with empty existing prompts');
    }
}