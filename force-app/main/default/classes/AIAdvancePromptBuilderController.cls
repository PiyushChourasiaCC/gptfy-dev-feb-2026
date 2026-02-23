/**
 * @description:
 *   AIAdvancePromptBuilderController serves as the server-side controller for the AI-powered
 *   Prompt Builder component. It leverages AI services to automatically generate prompt configurations,
 *   create data extraction mappings, and manage Salesforce metadata for intelligent prompt creation.
 *   This controller enables users to describe their needs in natural language and receive
 *   production-ready AI prompt configurations with proper data context and field mappings.
 *
 * @author             : Piyush Chourasia
 * @group              : Plumcloud Labs
 * @last modified on   : 19-11-2024
 * @last modified by   : Piyush Chourasia
 * @jira               : V2-7442
 */
public with sharing class AIAdvancePromptBuilderController {
    
    /**
     * Generates AI prompt configuration details based on natural language user input.
     * This method orchestrates the entire prompt generation process by:
     * 1. Validating user input
     * 2. Retrieving the appropriate AI connection configuration
     * 3. Building system and user prompts with context from existing prompts
     * 4. Making a callout to the AI service (GPTfy/OpenAI)
     * 5. Parsing the AI response using standardized parsing utilities
     * 
     * The AI service analyzes the user's request and generates a complete prompt configuration
     * including name, description, target object, prompt command, and data context mapping.
     *
     * @param userInput           - Natural language description of the desired prompt functionality.
     * @param existingPromptsJson - JSON string containing examples of existing prompts to guide AI generation.
     * @return String             - JSON string containing the generated prompt configuration with structure:
     *                              {
     *                                "name": "Prompt Name",
     *                                "description": "Prompt Description",
     *                                "targetObject": "Account",
     *                                "promptCommand": "Detailed AI instruction...",
     *                                "dataContext": {
     *                                  "mainObjectFields": ["Name", "Industry"],
     *                                  "childRelationships": [...]
     *                                }
     *                              }
     * @throws AuraHandledException - For validation errors, AI service failures, or parsing errors.
     * @jira V2-7442
     */
    @AuraEnabled
    public static String generatePromptDetails(String userInput, String existingPromptsJson) {
        try {
            if (String.isBlank(userInput)) {
                throw new AuraHandledException('User input cannot be empty');
            }
            
            AI_Connection__c connection = getGPTfyConnection();
            String systemPrompt = buildSystemPrompt();
            String userPrompt = buildUserPrompt(userInput, existingPromptsJson);
            
            Integer maxOutputToken = connection.Max_Tokens__c != null ? Integer.valueOf(connection.Max_Tokens__c) : 3000;
            Decimal temperature = 0.7;
            Decimal topP = connection.Top_P__c != null ? connection.Top_P__c : 1.0;
            
            HttpResponse response = AIGPTfyCalloutController.processGptfyRequest(
                systemPrompt,
                userPrompt,
                connection,
                maxOutputToken,
                temperature,
                topP
            );
            
            if (response != null && response.getStatusCode() == 200) {
                String responseBody = response.getBody();
                
                // Check if response is empty or just whitespace
                if (String.isBlank(responseBody)) {
                    throw new AuraHandledException('AI service returned an empty response');
                }
                
                // Use the existing ChatGPTUtills.parseGPTfyResponse method
                // This method handles all GPTfy response formats including data.value.choices
                String parsedContent = ChatGPTUtills.parseGPTfyResponse(responseBody);
                
                if (String.isNotBlank(parsedContent)) {
                    return parsedContent;
                }
                
                // If parsing returned null or empty, throw an error
                throw new AuraHandledException('Failed to parse AI response. Response may be in an unexpected format.');
            } else {
                String errorMsg = 'HTTP ' + (response != null ? String.valueOf(response.getStatusCode()) + ' - ' + response.getStatus() : 'No response');
                String detailedError = 'AI Service Error: ' + errorMsg + 
                                      '. Connection: ' + connection.Name + 
                                      ', Named Credential: ' + connection.Named_Credential__c;
                
                if (response != null && String.isNotBlank(response.getBody())) {
                    detailedError += '. Response: ' + response.getBody().abbreviate(200);
                }
                
                throw new AuraHandledException(detailedError);
            }
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIAdvancePromptBuilderController', 'generatePromptDetails','');
            throw new AuraHandledException('Error generating prompt details: ' + e.getMessage());
        }
    }
    
    /**
     * Creates a complete AI_Prompt__c record with associated data extraction mappings.
     * This method handles the full prompt creation workflow:
     * 1. Validates required parameters (name, object, command)
     * 2. Retrieves the GPTfy AI connection configuration
     * 3. Creates data extraction mapping if context is provided
     * 4. Creates the AI_Prompt__c record with proper field-level security checks
     * 5. Links the prompt to the data extraction mapping
     * 
     * The data extraction mapping enables the prompt to automatically pull relevant
     * Salesforce data (fields and child relationships) when executed.
     *
     * @param promptName         - The name of the prompt to be created.
     * @param targetObject       - The Salesforce object API name this prompt targets (e.g., 'Account', 'Contact').
     * @param description        - Detailed description of the prompt's purpose and functionality.
     * @param promptCommand      - The actual AI instruction/command text that will be sent to the AI service.
     * @param dataContextMapping - JSON string containing field and relationship mappings for data extraction.
     * @return String            - The ID of the created AI_Prompt__c record.
     * @throws AuraHandledException - For validation errors, missing AI connection, or DML failures.
     * @jira V2-7442
     */
    @AuraEnabled
    public static String createPromptWithMapping(String promptName, String targetObject, 
                                                String description, String promptCommand, 
                                                String dataContextMapping) {
        try {
            if (String.isBlank(promptName) || String.isBlank(targetObject) || String.isBlank(promptCommand)) {
                throw new AuraHandledException('Required fields cannot be empty');
            }
            
            AI_Connection__c connection = getGPTfyConnection();
            
            String extractionMappingId = null;
            if (String.isNotBlank(dataContextMapping) && dataContextMapping != 'undefined' && dataContextMapping != 'null') {
                extractionMappingId = createDataExtractionMapping(
                    promptName, 
                    targetObject, 
                    description, 
                    dataContextMapping
                );
            }
            
            String truncatedDescription = String.isNotBlank(description) ? 
                                         description.abbreviate(255) : '';
            
            AI_Prompt__c prompt = new AI_Prompt__c(
                Name = promptName,
                Description__c = truncatedDescription,
                Object__c = targetObject,
                Prompt_Command__c = promptCommand,
                Type__c = 'Text',
                Status__c = 'Draft',
                AI_Connection__c = connection.Id,
                AI_Data_Extraction_Mapping__c = extractionMappingId
            );
            
            List<SObject> insertedRecords = FLSCheck.getInstance().insertDML(new List<AI_Prompt__c>{prompt});
            
            if (insertedRecords != null && !insertedRecords.isEmpty()) {
                return String.valueOf(insertedRecords.get(0).get('Id'));
            }
            
            throw new AuraHandledException('Failed to create prompt record');
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIAdvancePromptBuilderController', 'createPromptWithMapping','');
            throw new AuraHandledException('Error creating prompt: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves comprehensive metadata for all accessible Salesforce objects.
     * This method provides the AI with context about available Salesforce objects,
     * their labels, and child relationships to generate accurate prompt configurations.
     * 
     * Only objects that are createable, updateable, and not custom settings are included
     * to ensure the AI suggests valid targets for prompt creation.
     *
     * @return List<Map<String, Object>> - List of object metadata maps containing:
     *                                      - name: API name of the object
     *                                      - label: User-friendly label
     *                                      - isCustom: Whether it's a custom object
     *                                      - childRelationships: List of child relationship names
     * @throws AuraHandledException      - On schema describe failures or permission issues.
     * @jira V2-7442
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getSalesforceObjectsMetadata() {
        try {
            List<Map<String, Object>> objectsList = new List<Map<String, Object>>();
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            
            for (String objName : globalDescribe.keySet()) {
                Schema.SObjectType objType = globalDescribe.get(objName);
                Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
                
                if (objDescribe.isCreateable() && objDescribe.isUpdateable() && 
                    !objDescribe.isCustomSetting()) {
                    
                    Map<String, Object> objInfo = new Map<String, Object>();
                    objInfo.put('name', objDescribe.getName());
                    objInfo.put('label', objDescribe.getLabel());
                    objInfo.put('isCustom', objDescribe.isCustom());
                    
                    List<String> childRelationships = new List<String>();
                    for (Schema.ChildRelationship childRel : objDescribe.getChildRelationships()) {
                        if (childRel.getRelationshipName() != null) {
                            childRelationships.add(childRel.getRelationshipName() + ' (' + 
                                                 childRel.getChildSObject().getDescribe().getLabel() + ')');
                        }
                    }
                    objInfo.put('childRelationships', childRelationships);
                    
                    objectsList.add(objInfo);
                }
            }
            
            return objectsList;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Salesforce objects: ' + e.getMessage());
        }
    }
    
    /**
     * Fetches a sample of existing active prompts to provide pattern examples for AI generation.
     * The AI analyzes these examples to understand the organization's prompt structure,
     * naming conventions, and style preferences, ensuring generated prompts align with
     * existing patterns and maintain consistency across the organization.
     * 
     * Returns up to 10 most recently created active text prompts with truncated commands
     * to keep the context size manageable for AI processing.
     *
     * @return List<Map<String, String>> - List of prompt metadata maps containing:
     *                                      - name: Prompt name
     *                                      - object: Target Salesforce object
     *                                      - description: Prompt description
     *                                      - command: Truncated prompt command (first 200 chars)
     * @throws AuraHandledException      - On query failures or permission issues.
     * @jira V2-7442
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getExistingPrompts() {
        try {
            List<Map<String, String>> promptsList = new List<Map<String, String>>();
            
            List<AI_Prompt__c> prompts = [
                SELECT Id, Name, Description__c, Object__c, Prompt_Command__c, Type__c
                FROM AI_Prompt__c
                WHERE Status__c = 'Active' AND Type__c = 'Text'
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];
            
            for (AI_Prompt__c prompt : prompts) {
                Map<String, String> promptInfo = new Map<String, String>();
                promptInfo.put('name', prompt.Name);
                promptInfo.put('object', prompt.Object__c);
                promptInfo.put('description', prompt.Description__c != null ? prompt.Description__c : '');
                promptInfo.put('command', prompt.Prompt_Command__c != null ? 
                             prompt.Prompt_Command__c.substring(0, Math.min(200, prompt.Prompt_Command__c.length())) : '');
                promptsList.add(promptInfo);
            }
            
            return promptsList;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching existing prompts: ' + e.getMessage());
        }
    }
    
    /**
     * @description Retrieves the namespace prefix for the current org
     *              Uses AIConstants.NAMESPACE to get the namespace dynamically
     *              Returns empty string for non-namespaced orgs
     * @return String - The namespace prefix (without trailing underscore) or empty string
     * @jira V2-7442
     */
    @AuraEnabled(cacheable=true)
    public static String getNamespace() {
        try {
            String namespace = AIConstants.NAMESPACE;
            return String.isNotBlank(namespace) ? namespace : '';
        } catch (Exception e) {
            // Return empty string if any error occurs
            return '';
        }
    }
    
    // ==================== PRIVATE HELPER METHODS ====================
    
    /**
     * Constructs the system prompt that instructs the AI on how to generate prompt configurations.
     * The system prompt is assembled from multiple custom labels to maintain:
     * - Ease of maintenance and updates without code deployment
     * - Potential for future localization
     * - Separation of concerns between code logic and prompt instructions
     * 
     * The system prompt defines the JSON structure, field requirements, and rules
     * that the AI must follow when generating prompt configurations.
     *
     * @return String - Complete system prompt with instructions for AI prompt generation.
     * @jira V2-7442
     */
    private static String buildSystemPrompt() {
        return Label.AI_Prompt_Builder_System_Prompt_Intro + '\n\n' +
               Label.AI_Prompt_Builder_JSON_Structure + '\n\n' +
               Label.AI_Prompt_Builder_Command_Instructions + '\n' +
               Label.AI_Prompt_Builder_Command_Example + '\n\n' +
               Label.AI_Prompt_Builder_Data_Context_Instructions + '\n' +
               Label.AI_Prompt_Builder_Additional_Rules;
    }
    
    /**
     * Constructs the user-specific prompt by combining the user's natural language request
     * with examples from existing prompts to provide context and pattern guidance.
     * 
     * This method enhances the AI's understanding by:
     * - Including the user's exact requirements
     * - Providing real-world examples from the organization's existing prompts
     * - Instructing the AI to follow established patterns and conventions
     *
     * @param userInput           - The user's natural language description of desired prompt functionality.
     * @param existingPromptsJson - JSON string containing examples of existing prompts for pattern matching.
     * @return String             - Complete user prompt with context and instructions.
     * @jira V2-7442
     */
    private static String buildUserPrompt(String userInput, String existingPromptsJson) {
        String userPrompt = 'User Request: ' + userInput + '\n\n';
        
        if (String.isNotBlank(existingPromptsJson)) {
            userPrompt += 'Here are examples of existing prompts for reference (study their structure and style):\n' +
                         existingPromptsJson + '\n\n';
        }
        
        userPrompt += 'Based on the user\'s request and the pattern from existing prompts, ' +
                     'generate a complete prompt configuration following the exact JSON structure specified. ' +
                     'Make the prompt command detailed, professional, and production-ready.';
        
        return userPrompt;
    }
    
    /**
     * Creates a complete data extraction mapping hierarchy from AI-generated context.
     * This method orchestrates the creation of:
     * 1. AI_Data_Extraction_Mapping__c (parent record)
     * 2. AI_Data_Extraction_Detail__c (child relationship configurations)
     * 3. AI_Data_Extraction_Field__c (field selections for main and child objects)
     * 
     * The data extraction mapping enables prompts to automatically retrieve relevant
     * Salesforce data when executed, eliminating the need for manual field selection.
     *
     * @param mappingName     - Name for the data extraction mapping record.
     * @param targetObject    - Salesforce object API name this mapping targets.
     * @param description     - Description of the mapping's purpose.
     * @param dataContextJson - JSON string containing field and relationship specifications from AI.
     * @return String         - ID of the created AI_Data_Extraction_Mapping__c record, or null on failure.
     * @jira V2-7442
     */
    private static String createDataExtractionMapping(String mappingName, String targetObject, 
                                                     String description, String dataContextJson) {
        try {
            Map<String, Object> contextMap = (Map<String, Object>) JSON.deserializeUntyped(dataContextJson);
            
            AI_Data_Extraction_Mapping__c mapping = new AI_Data_Extraction_Mapping__c(
                Name = mappingName,
                Object_Name__c = targetObject,
                Description__c = description,
                Status__c = 'Active'
            );
            
            List<SObject> insertedMappings = FLSCheck.getInstance().insertDML(
                new List<AI_Data_Extraction_Mapping__c>{mapping}
            );
            
            if (insertedMappings == null || insertedMappings.isEmpty()) {
                return null;
            }
            
            String mappingId = String.valueOf(insertedMappings.get(0).get('Id'));
            
            List<Object> childRelationships = (List<Object>) contextMap.get('childRelationships');
            if (childRelationships != null && !childRelationships.isEmpty()) {
                createDataExtractionDetails(mappingId, childRelationships);
            }
            
            List<Object> mainObjectFieldsObj = (List<Object>) contextMap.get('mainObjectFields');
            if (mainObjectFieldsObj != null && !mainObjectFieldsObj.isEmpty()) {
                List<String> mainObjectFields = new List<String>();
                for (Object fieldObj : mainObjectFieldsObj) {
                    mainObjectFields.add((String) fieldObj);
                }
                createDataExtractionFields(mappingId, targetObject, mainObjectFields);
            }
            
            return mappingId;
            
        } catch (Exception e) {
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIAdvancePromptBuilderController', 'createDataExtractionMapping','');
            return null;
        }
    }
    
    /**
     * Creates AI_Data_Extraction_Detail__c records for child object relationships.
     * This method processes AI-generated child relationship specifications and:
     * 1. Validates each child object exists in Salesforce schema
     * 2. Identifies the correct relationship field between parent and child
     * 3. Creates detail records with proper configuration (WHERE clauses, limits, etc.)
     * 4. Creates associated field records for each child object
     * 
     * Maximum of 3 child relationships are processed to maintain reasonable query complexity
     * and avoid governor limit issues during prompt execution.
     *
     * @param mappingId          - ID of the parent AI_Data_Extraction_Mapping__c record.
     * @param childRelationships - List of child relationship specifications from AI containing:
     *                             objectName, relationshipName, fields, whereClause
     * @jira V2-7442
     */
    private static void createDataExtractionDetails(String mappingId, List<Object> childRelationships) {
        try {
            final Integer MAX_CHILD_RELATIONSHIPS = 3;
            
            List<AI_Data_Extraction_Mapping__c> mappings = [
                SELECT Object_Name__c FROM AI_Data_Extraction_Mapping__c WHERE Id = :mappingId LIMIT 1
            ];
            String parentObjectName = mappings.isEmpty() ? null : mappings[0].Object_Name__c;
            
            List<AI_Data_Extraction_Detail__c> details = new List<AI_Data_Extraction_Detail__c>();
            List<AI_Data_Extraction_Field__c> childFields = new List<AI_Data_Extraction_Field__c>();
            List<Map<String, Object>> validChildRelationships = new List<Map<String, Object>>();
            Integer runningIndex = 0;
            Integer processedCount = 0;
            
            for (Object childRelObj : childRelationships) {
                if (processedCount >= MAX_CHILD_RELATIONSHIPS) {
                    break;
                }
                
                Map<String, Object> childRel = (Map<String, Object>) childRelObj;
                
                String objectName = (String) childRel.get('objectName');
                String relationshipName = (String) childRel.get('relationshipName');
                String whereClause = (String) childRel.get('whereClause');
                
                // Validate child object exists in Salesforce
                if (!isValidSalesforceObject(objectName)) {
                    continue;
                }
                
                String relationshipField = getRelationshipFieldName(parentObjectName, objectName);
                
                if (String.isBlank(relationshipField)) {
                    continue;
                }
                
                AI_Data_Extraction_Detail__c detail = new AI_Data_Extraction_Detail__c(
                    AI_Data_Extraction_Mapping__c = mappingId,
                    Object_Name__c = objectName,
                    RelationshipName__c = relationshipName,
                    Type__c = 'CHILD',
                    Running_Index__c = runningIndex,
                    Where_Clause__c = String.isNotBlank(whereClause) ? whereClause : null,
                    Order_By__c = null,
                    Record_Limit__c = null,
                    RelationshipField__c = relationshipField
                );
                
                details.add(detail);
                validChildRelationships.add(childRel);
                runningIndex += 100;
                processedCount++;
            }
            
            if (!details.isEmpty()) {
                List<SObject> insertedDetails = FLSCheck.getInstance().insertDML(details);
                
                if (insertedDetails != null && !insertedDetails.isEmpty()) {
                    List<AI_Data_Extraction_Field__c> objectLabelFields = new List<AI_Data_Extraction_Field__c>();
                    
                    Integer detailIndex = 0;
                    for (Map<String, Object> childRel : validChildRelationships) {
                        String objectName = (String) childRel.get('objectName');
                        String relationshipName = (String) childRel.get('relationshipName');
                        
                        AI_Data_Extraction_Field__c objectField = new AI_Data_Extraction_Field__c(
                            AI_Data_Extraction_Mapping__c = mappingId,
                            Object__c = objectName,
                            Field__c = objectName,
                            Label__c = relationshipName != null ? relationshipName : objectName,
                            Type__c = 'OBJECT',
                            Send_To_AI__c = false
                        );
                        objectLabelFields.add(objectField);
                        
                        List<Object> fieldsObj = (List<Object>) childRel.get('fields');
                        
                        if (fieldsObj != null && !fieldsObj.isEmpty() && detailIndex < insertedDetails.size()) {
                            // Convert List<Object> to List<String> for validation
                            List<String> fieldNames = new List<String>();
                            for (Object fieldObj : fieldsObj) {
                                fieldNames.add((String) fieldObj);
                            }
                            
                            // Validate fields against Salesforce schema
                            List<String> validFields = getValidFields(objectName, fieldNames);
                            
                            for (String fieldApi : validFields) {
                                AI_Data_Extraction_Field__c field = new AI_Data_Extraction_Field__c(
                                    AI_Data_Extraction_Mapping__c = mappingId,
                                    Object__c = objectName,
                                    Field__c = fieldApi,
                                    Label__c = fieldApi,
                                    Send_To_AI__c = true,
                                    Type__c = 'FIELD'
                                );
                                
                                childFields.add(field);
                            }
                        }
                        detailIndex++;
                    }
                    
                    if (!objectLabelFields.isEmpty()) {
                        FLSCheck.getInstance().insertDML(objectLabelFields);
                    }
                    
                    if (!childFields.isEmpty()) {
                        FLSCheck.getInstance().insertDML(childFields);
                    }
                }
            }
            
        } catch (Exception e) {
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIAdvancePromptBuilderController', 'createDataExtractionDetails','');
        }
    }
    
    /**
     * Creates AI_Data_Extraction_Field__c records for the main target object.
     * This method:
     * 1. Validates the target object exists in Salesforce
     * 2. Creates an OBJECT-type field record for the object label
     * 3. Validates each field against the Salesforce schema
     * 4. Creates FIELD-type records only for valid, accessible fields
     * 
     * Field validation ensures prompts don't fail at runtime due to invalid field references
     * or insufficient permissions.
     *
     * @param mappingId  - ID of the parent AI_Data_Extraction_Mapping__c record.
     * @param objectName - Salesforce object API name to create field records for.
     * @param fields     - List of field API names from AI-generated configuration.
     * @jira V2-7442
     */
    private static void createDataExtractionFields(String mappingId, String objectName, List<String> fields) {
        try {
            // Validate object exists
            if (!isValidSalesforceObject(objectName)) {
                return;
            }
            
            List<AI_Data_Extraction_Field__c> fieldRecords = new List<AI_Data_Extraction_Field__c>();
            
            Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objectName).getDescribe();
            AI_Data_Extraction_Field__c objectField = new AI_Data_Extraction_Field__c(
                AI_Data_Extraction_Mapping__c = mappingId,
                Object__c = objectName,
                Field__c = objectName,
                Label__c = objDescribe.getLabel(),
                Type__c = 'OBJECT',
                Send_To_AI__c = false
            );
            fieldRecords.add(objectField);
            
            // Validate and filter fields
            List<String> validFields = getValidFields(objectName, fields);
            
            for (String fieldApi : validFields) {
                AI_Data_Extraction_Field__c field = new AI_Data_Extraction_Field__c(
                    AI_Data_Extraction_Mapping__c = mappingId,
                    Object__c = objectName,
                    Field__c = fieldApi,
                    Label__c = fieldApi,
                    Send_To_AI__c = true,
                    Type__c = 'FIELD'
                );
                
                fieldRecords.add(field);
            }
            
            if (!fieldRecords.isEmpty()) {
                FLSCheck.getInstance().insertDML(fieldRecords);
            }
            
        } catch (Exception e) {
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIAdvancePromptBuilderController', 'createDataExtractionFields','');
        }
    }
    
    /**
     * Executes a direct HTTP callout to the AI Responses API endpoint.
     * This method constructs and sends an HTTP POST request with:
     * - Model configuration (GPT-4, etc.)
     * - Combined system and user prompts
     * - Generation parameters (tokens, temperature, top_p)
     * 
     * Uses Named Credentials for secure authentication and endpoint management.
     * Note: This method is currently not actively used but maintained for potential
     * future direct API integration scenarios.
     *
     * @param systemPrompt - System-level instructions for the AI model.
     * @param userPrompt   - User-specific request and context.
     * @param connection   - AI_Connection__c record containing endpoint and credential details.
     * @param maxTokens    - Maximum number of tokens in the AI response.
     * @param temperature  - Controls randomness in AI generation (0.0-1.0).
     * @param topP         - Controls diversity via nucleus sampling (0.0-1.0).
     * @return HttpResponse - Raw HTTP response from the AI service.
     * @throws Exception    - On HTTP failures, timeout, or connection issues.
     * @jira V2-7442
     */
    private static HttpResponse callResponsesAPI(String systemPrompt, String userPrompt, 
                                                AI_Connection__c connection, Integer maxTokens, 
                                                Decimal temperature, Decimal topP) {
        try {
            Map<String, Object> requestBody = new Map<String, Object>();
            
            String model = connection.Model__c != null ? connection.Model__c : 'gpt-4';
            requestBody.put('model', model);
            
            String combinedInput = systemPrompt + '\n\n' + userPrompt;
            requestBody.put('input', combinedInput);
            
            requestBody.put('max_output_tokens', maxTokens);
            requestBody.put('temperature', temperature);
            requestBody.put('top_p', topP);
            
            String jsonBody = JSON.serialize(requestBody);
            
            HttpRequest request = new HttpRequest();
            
            String endpoint = 'callout:' + connection.Named_Credential__c;
            
            if (String.isNotBlank(connection.EndPoint_URL__c)) {
                endpoint += connection.EndPoint_URL__c;
            } else {
                endpoint += '/v1/responses';
            }
            
            request.setEndpoint(endpoint);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setBody(jsonBody);
            request.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            return response;
            
        } catch (Exception e) {
            throw e;
        }
    }
    
    /**
     * Retrieves the GPTfy (OpenAI) AI connection configuration.
     * This method queries for the most recent AI_Connection__c record configured
     * for GPTfy/OpenAI integration, which contains:
     * - Named Credential for authentication
     * - Model configuration (GPT-4, GPT-3.5, etc.)
     * - Default generation parameters
     * - Endpoint URL configuration
     * 
     * Throws a user-friendly error if no connection is configured, guiding
     * administrators on the required setup.
     *
     * @return AI_Connection__c - The GPTfy connection configuration record.
     * @throws AuraHandledException - If no GPTfy connection is configured in the org.
     * @jira V2-7442
     */
    private static AI_Connection__c getGPTfyConnection() {
        List<AI_Connection__c> connections = [
            SELECT Id, Name, Named_Credential__c, Model__c, Max_Tokens__c, 
                   Temperature__c, Top_P__c, EndPoint_URL__c, AI_Technology__c,
                   Connector_Class__c, Processing_Class__c, Version__c, 
                   Additional_Parameters__c
            FROM AI_Connection__c
            WHERE Name = 'GPTfy (OpenAI)'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (connections.isEmpty()) {
            throw new AuraHandledException('No AI Connection found. Please configure an AI Connection record with Name = "Response API". ' +
                                         'Ensure the Named_Credential__c field is set to your Named Credential name (without "callout:" prefix) and EndPoint_URL__c is configured correctly.');
        }
        
        return connections[0];
    }
    
    /**
     * Identifies the relationship field API name that connects a parent object to a child object.
     * This method uses Salesforce schema metadata to:
     * 1. Retrieve all child relationships of the parent object
     * 2. Find the relationship where the child object matches the specified child
     * 3. Extract the field API name that establishes the relationship
     * 
     * This is essential for constructing proper SOQL queries with child relationship queries.
     * Example: For Account (parent) and Contact (child), returns 'AccountId'
     *
     * @param parentObjectName - API name of the parent Salesforce object.
     * @param childObjectName  - API name of the child Salesforce object.
     * @return String          - The field API name on the child object that references the parent,
     *                           or null if no relationship exists or objects are invalid.
     * @jira V2-7442
     */
    private static String getRelationshipFieldName(String parentObjectName, String childObjectName) {
        try {
            if (String.isBlank(parentObjectName) || String.isBlank(childObjectName)) {
                return null;
            }
            
            Schema.DescribeSObjectResult parentDescribe = Schema.getGlobalDescribe().get(parentObjectName).getDescribe();
            
            for (Schema.ChildRelationship childRel : parentDescribe.getChildRelationships()) {
                if (String.valueOf(childRel.getChildSObject()) == childObjectName) {
                    String fieldName = String.valueOf(childRel.getField());
                    return fieldName;
                }
            }
            
            return null;
            
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Validates whether a specified object exists in the Salesforce schema.
     * This validation prevents runtime errors by ensuring AI-generated object references
     * are valid before creating data extraction configurations.
     * 
     * Uses global describe to check object existence in a case-insensitive manner.
     *
     * @param objectName - The API name of the Salesforce object to validate.
     * @return Boolean   - True if the object exists in the org's schema, false otherwise.
     * @jira V2-7442
     */
    private static Boolean isValidSalesforceObject(String objectName) {
        try {
            if (String.isBlank(objectName)) {
                return false;
            }
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            return globalDescribe.containsKey(objectName.toLowerCase());
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * Validates whether a specified field exists on a Salesforce object.
     * This validation ensures AI-generated field references are valid and accessible,
     * preventing SOQL errors during prompt execution.
     * 
     * Performs case-insensitive field name matching against the object's field map.
     *
     * @param objectName - The API name of the Salesforce object.
     * @param fieldName  - The API name of the field to validate.
     * @return Boolean   - True if the field exists on the object, false otherwise.
     * @jira V2-7442
     */
    private static Boolean isValidField(String objectName, String fieldName) {
        try {
            if (String.isBlank(objectName) || String.isBlank(fieldName)) {
                return false;
            }
            
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType == null) {
                return false;
            }
            
            Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
            return fieldMap.containsKey(fieldName.toLowerCase());
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * Validates and filters a list of field names against a Salesforce object's schema.
     * This method ensures only valid, existing fields are included in data extraction
     * configurations, preventing runtime SOQL errors and improving prompt reliability.
     * 
     * Performs bulk validation by:
     * 1. Retrieving the object's complete field map once
     * 2. Checking each field name against the map (case-insensitive)
     * 3. Returning only the fields that exist on the object
     *
     * @param objectName - The API name of the Salesforce object.
     * @param fields     - List of field API names to validate (potentially from AI generation).
     * @return List<String> - Filtered list containing only valid field API names.
     * @jira V2-7442
     */
    private static List<String> getValidFields(String objectName, List<String> fields) {
        List<String> validFields = new List<String>();
        
        if (String.isBlank(objectName) || fields == null || fields.isEmpty()) {
            return validFields;
        }
        
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType == null) {
                return validFields;
            }
            
            Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
            
            for (String fieldName : fields) {
                if (String.isNotBlank(fieldName) && fieldMap.containsKey(fieldName.toLowerCase())) {
                    validFields.add(fieldName);
                }
            }
        } catch (Exception e) {
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIAdvancePromptBuilderController', 'getValidFields','');
        }
        
        return validFields;
    }
}