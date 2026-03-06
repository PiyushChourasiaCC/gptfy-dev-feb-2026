/**
 * @description Controller for AI Prompt Factory component
 *              Handles prompt generation with proper FLS checks and exception logging
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 02-26-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
public with sharing class AIPromptFactoryController {
    
    /**
     * Wrapper class for object options
     */
    public class ObjectOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        
        public ObjectOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
        
        public Integer compareTo(Object compareTo) {
            ObjectOption compareToOption = (ObjectOption)compareTo;
            if (label == compareToOption.label) return 0;
            if (label > compareToOption.label) return 1;
            return -1;
        }
    }
    
    /**
     * Wrapper class for record options
     */
    public class RecordOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        
        public RecordOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    /**
     * Wrapper class for AI Model options
     */
    public class AIModelOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        
        public AIModelOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    /**
     * Wrapper class for prompt generation request
     */
    public class PromptGenerationRequest {
        @AuraEnabled public String targetObject { get; set; }
        @AuraEnabled public String sampleRecordId { get; set; }
        @AuraEnabled public String businessContext { get; set; }
        @AuraEnabled public String aiModelId { get; set; }
        @AuraEnabled public List<String> detectedObjects { get; set; }
    }
    
    /**
     * Wrapper class for prompt deployment request
     */
    public class PromptDeploymentRequest {
        @AuraEnabled public String goldenPromptText { get; set; }
        @AuraEnabled public String promptName { get; set; }
        @AuraEnabled public String targetObject { get; set; }
        @AuraEnabled public String aiModelId { get; set; }
        @AuraEnabled public String existingPromptId { get; set; }
        @AuraEnabled public Map<String, Object> schemaInfo { get; set; }
        @AuraEnabled public String businessContext { get; set; }
        @AuraEnabled public List<String> priorityChildObjects { get; set; }
    }
    
    /**
     * Retrieves all queryable Salesforce objects using AIDataExtractionController
     * @return List of ObjectOption containing object labels and API names
     * @jira V2-7823
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAllSalesforceObjects() {
        try {
            List<ObjectOption> objectOptions = new List<ObjectOption>();
            
            // Use AIDataExtractionController.getSObjects() to get filtered objects
            List<AIDataExtractionController.PicklistWrapper> sObjects = AIDataExtractionController.getSObjects();
            
            for (AIDataExtractionController.PicklistWrapper obj : sObjects) {
                objectOptions.add(new ObjectOption(obj.label, obj.value));
            }
            
            return objectOptions;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Salesforce objects: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves records from the specified object for the sample record dropdown
     * @param objectApiName API name of the object
     * @param searchTerm Search term for filtering records
     * @return List of RecordOption containing record names and IDs
     * @jira V2-7823
     */
    @AuraEnabled
    public static List<RecordOption> getObjectRecords(String objectApiName, String searchTerm) {
        try {
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('Object API name is required');
            }
            
            List<RecordOption> recordOptions = new List<RecordOption>();
            
            // Validate object accessibility
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            if (objType == null) {
                throw new AuraHandledException('Invalid object API name: ' + objectApiName);
            }
            
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            
            // Check object accessibility
            if (!objDescribe.isAccessible()) {
                throw new AuraHandledException('You do not have access to this object');
            }
            
            // Check if Name field exists, otherwise use Id
            String nameField = 'Name';
            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
            if (!fieldMap.containsKey('Name')) {
                nameField = 'Id';
            }
            
            // Build dynamic SOQL query with USER_MODE for FLS enforcement
            String query = 'SELECT Id, ' + nameField + ' FROM ' + objectApiName;
            
            if (String.isNotBlank(searchTerm)) {
                String searchKey = '%' + String.escapeSingleQuotes(searchTerm) + '%';
                query += ' WHERE ' + nameField + ' LIKE :searchKey';
            }
            
            query += ' WITH USER_MODE ORDER BY ' + nameField + ' ASC LIMIT 50';
            
            List<SObject> records = Database.query(query);
            
            for (SObject record : records) {
                String recordName = nameField == 'Id' ? String.valueOf(record.get('Id')) : String.valueOf(record.get(nameField));
                recordOptions.add(new RecordOption(recordName, String.valueOf(record.get('Id'))));
            }
            System.debug('recordOptions: ' + recordOptions);
            return recordOptions;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching records: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves all AI Models where Type is Chat
     * @return List of AIModelOption containing model names and IDs
     * @jira V2-7823
     */
    @AuraEnabled(cacheable=true)
    public static List<AIModelOption> getChatAIModels() {
        try {
            List<AIModelOption> modelOptions = new List<AIModelOption>();
            
            List<AI_Connection__c> chatModels = [
                SELECT Id, Name
                FROM AI_Connection__c
                WHERE Type__c = :AIConstants.AI_MODEL_TYPE_CHAT
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT 1000
            ];
            
            for (AI_Connection__c model : chatModels) {
                modelOptions.add(new AIModelOption(model.Name, model.Id));
            }
            
            return modelOptions;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching AI Models: ' + e.getMessage());
        }
    }
    
    /**
     * Discover schema for a given object.
     * Returns field count, child object count, and top child objects.
     * @param objectName Salesforce object API name
     * @return Map with fieldCount, childCount, customFieldCount, topChildren
     * @jira V2-7823
     */
    @AuraEnabled
    public static Map<String, Object> discoverSchema(String objectName) {
        try {
            if (String.isBlank(objectName)) {
                throw new AuraHandledException('Object name is required.');
            }

            if (!AISchemaHelper.isObjectAccessible(objectName)) {
                throw new AuraHandledException('Object "' + objectName + '" is not accessible.');
            }

            List<AISchemaHelper.FieldMetadata> fields = AISchemaHelper.getFields(objectName);
            List<AISchemaHelper.ChildRelationship> children = AISchemaHelper.getChildRelationships(objectName);

            Integer customFieldCount = 0;
            for (AISchemaHelper.FieldMetadata f : fields) {
                if (f.isCustom) {
                    customFieldCount++;
                }
            }

            List<String> topChildren = new List<String>();
            for (AISchemaHelper.ChildRelationship child : children) {
                if (topChildren.size() >= 10) break;
                if (String.isBlank(child.relationshipName)) continue;
                topChildren.add(child.relationshipName + ' (' + child.childObject + ')');
            }

            Map<String, Object> result = new Map<String, Object>{
                'fieldCount' => fields.size(),
                'childCount' => children.size(),
                'customFieldCount' => customFieldCount,
                'topChildren' => topChildren,
                'objectName' => objectName
            };

            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Schema discovery failed: ' + e.getMessage());
        }
    }
    
    /**
     * Generates a golden prompt using AI-powered context assembly and meta-prompt service
     * @param request PromptGenerationRequest wrapper with targetObject, businessContext, sampleRecordId, aiModelId
     * @return String containing the generated golden prompt
     * @jira V2-7823
     */
    @AuraEnabled
    public static String generatePromptWithConnection(PromptGenerationRequest request) {
        try {
            if (request == null) {
                throw new AuraHandledException('Request cannot be null');
            }
            
            if (String.isBlank(request.targetObject)) {
                throw new AuraHandledException('Target object is required');
            }
            
            if (String.isBlank(request.businessContext)) {
                throw new AuraHandledException('Business context is required');
            }
            
            if (String.isBlank(request.aiModelId)) {
                throw new AuraHandledException('AI Model is required');
            }

            // === CALLOUT PHASE (no DML before callouts) ===
            
            // 1. Assemble context using AIContextAssembler
            String contextPackage = AIContextAssembler.assembleContext(
                request.targetObject,
                request.sampleRecordId,
                request.businessContext
            );
            
            // 2. Generate golden prompt via LLM using AIMetaPromptService
            String goldenPrompt = AIMetaPromptService.generateGoldenPrompt(
                contextPackage,
                request.aiModelId
            );
            
            return goldenPrompt;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Prompt generation failed: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves the namespace prefix for the current org
     * @return String - The namespace prefix or empty string
     */
    @AuraEnabled(cacheable=true)
    public static String getNamespace() {
        try {
            String namespace = AIConstants.NAMESPACE;
            return String.isNotBlank(namespace) ? namespace : '';
        } catch (Exception e) {
            return '';
        }
    }
    
    /**
     * Deploy or update a prompt record with Data Context Mapping
     * @param request PromptDeploymentRequest wrapper with all deployment parameters
     * @return Map with promptId, promptName, mappingId, and status (deployed/updated)
     * @jira V2-7823
     */
    @AuraEnabled
    public static Map<String, Object> deployPrompt(PromptDeploymentRequest request) {
        try {
            if (request == null) {
                throw new AuraHandledException('Request cannot be null');
            }
            
            if (String.isBlank(request.goldenPromptText)) {
                throw new AuraHandledException('Golden prompt text is required.');
            }
            
            if (String.isBlank(request.promptName)) {
                request.promptName = request.targetObject + ' 360 Prompt';
            }
            
            Id promptId;
            Id mappingId;
            String status;
            
            // Check if we have a valid existing prompt ID to update
            Boolean shouldUpdate = false;
            if (String.isNotBlank(request.existingPromptId)) {
                try {
                    // Validate the ID format
                    Id testId = Id.valueOf(request.existingPromptId);
                    shouldUpdate = true;
                } catch (Exception idEx) {
                    // Invalid ID format, treat as new prompt
                    shouldUpdate = false;
                }
            }
            
            if (shouldUpdate) {
                // Update existing prompt
                List<AI_Prompt__c> existingPrompts = [
                    SELECT Id, Name, AI_Data_Extraction_Mapping__c
                    FROM AI_Prompt__c
                    WHERE Id = :request.existingPromptId
                    WITH USER_MODE
                    LIMIT 1
                ];
                
                if (existingPrompts.isEmpty()) {
                    throw new AuraHandledException('Prompt not found with ID: ' + request.existingPromptId);
                }
                
                AI_Prompt__c existingPrompt = existingPrompts[0];
                existingPrompt.Prompt_Command__c = request.goldenPromptText;
                if (String.isNotBlank(request.aiModelId)) {
                    existingPrompt.AI_Connection__c = request.aiModelId;
                }
                
                // Use FLSCheck for update
                List<AI_Prompt__c> promptsToUpdate = new List<AI_Prompt__c>{ existingPrompt };
                FLSCheck.getInstance().updateDML(promptsToUpdate);
                
                promptId = existingPrompt.Id;
                mappingId = existingPrompt.AI_Data_Extraction_Mapping__c;
                status = 'updated';
            } else {
                // Step 1: Create Data Context Mapping with fields and child objects
                mappingId = createDataContextMapping(
                    request.promptName,
                    request.targetObject,
                    request.goldenPromptText,
                    request.schemaInfo,
                    request.businessContext,
                    request.priorityChildObjects
                );
                
                // Step 2: Create new prompt with AI Connection and Data Context Mapping reference
                AI_Prompt__c newPrompt = new AI_Prompt__c(
                    Name = request.promptName,
                    Prompt_Command__c = request.goldenPromptText,
                    Status__c = 'Active',
                    Type__c = 'Text',
                    Object__c = request.targetObject,
                    Description__c = 'Generated by AI Prompt Factory',
                    AI_Data_Extraction_Mapping__c = mappingId
                );
                
                // Set AI Connection if provided
                if (String.isNotBlank(request.aiModelId)) {
                    newPrompt.AI_Connection__c = request.aiModelId;
                }
                
                // Use FLSCheck for insert and capture returned records
                List<AI_Prompt__c> promptsToInsert = new List<AI_Prompt__c>{ newPrompt };
                List<SObject> insertedPrompts = FLSCheck.getInstance().insertDML(promptsToInsert);
                
                // Get the ID from the inserted record
                if (insertedPrompts != null && !insertedPrompts.isEmpty()) {
                    promptId = insertedPrompts[0].Id;
                }
                
                status = 'deployed';
            }
            
            return new Map<String, Object>{
                'promptId' => String.valueOf(promptId),
                'promptName' => request.promptName,
                'mappingId' => String.valueOf(mappingId),
                'status' => status
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Deployment failed: ' + e.getMessage());
        }
    }
    
    /**
     * Execute a deployed prompt against a specific record using Data Context Mapping
     * @param promptId ID of the deployed AI_Prompt__c record
     * @param recordId ID of the Salesforce record to execute against
     * @param targetObject The target Salesforce object
     * @param aiModelId The AI Connection ID to use
     * @return The HTML output from the LLM
     * @jira V2-7823
     */
    @AuraEnabled
    public static String executePrompt(String promptId, String recordId, String targetObject, String aiModelId) {
        try {
            if (String.isBlank(promptId) || String.isBlank(recordId)) {
                throw new AuraHandledException('Prompt ID and Record ID are required.');
            }
            
            if (String.isBlank(aiModelId)) {
                throw new AuraHandledException('AI Model is required.');
            }
            
            // Get the prompt with Data Context Mapping
            AI_Prompt__c prompt = [
                SELECT Id, Name, Prompt_Command__c, AI_Connection__c, AI_Data_Extraction_Mapping__c,
                       AI_Connection__r.Id, AI_Connection__r.Name, AI_Connection__r.Type__c, 
                       AI_Connection__r.AI_Technology__c, AI_Connection__r.Named_Credential__c
                FROM AI_Prompt__c
                WHERE Id = :promptId
                WITH USER_MODE
                LIMIT 1
            ];
            
            // Use the prompt's AI Connection
            if (prompt.AI_Connection__c == null) {
                throw new AuraHandledException('Prompt does not have an AI Connection configured.');
            }
            
            // Build record data using Data Context Mapping
            String recordDataJson = buildRecordDataFromMapping(prompt.AI_Data_Extraction_Mapping__c, recordId);
            
            // Build the final prompt with record data
            String finalPrompt = prompt.Prompt_Command__c + '\n\n' + recordDataJson;
            
            // Create a temporary AI_Prompt__c object for the callout
            AI_Prompt__c tempPrompt = new AI_Prompt__c(
                Id = prompt.Id,
                Prompt_Command__c = finalPrompt,
                AI_Connection__c = prompt.AI_Connection__c
            );
            tempPrompt.AI_Connection__r = prompt.AI_Connection__r;
            
            // Execute via AIGPTfyCalloutController
            String response = AIGPTfyCalloutController.processRequest(finalPrompt, recordDataJson, tempPrompt);
            
            // Parse the response with graceful fallback
            String htmlOutput;
            try {
                htmlOutput = parseAIResponse(response);
            } catch (Exception parseEx) {
                System.debug('Parse error: ' + parseEx.getMessage());
                System.debug('Raw response: ' + response);
                // Return raw response if parsing fails
                htmlOutput = response;
            }
            
            return htmlOutput;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Prompt execution failed: ' + e.getMessage());
        }
    }
    
    /**
     * Generates intelligent data context mapping using AI based on business context AND generated prompt
     * Includes child object schema so AI can pick correct fields
     * @param targetObject The Salesforce object
     * @param businessContext User's business context description
     * @param goldenPrompt The generated golden prompt text (contains detailed requirements)
     * @param schemaInfo Schema information with child relationships
     * @return JSON string with data context mapping structure
     */
    private static String generateDataContextMappingWithAI(String targetObject, String businessContext, String goldenPrompt, Map<String, Object> schemaInfo) {
        try {
            // Get GPTfy connection
            List<AI_Connection__c> connections = [
                SELECT Id, Name, AI_Technology__c, Model__c, EndPoint_URL__c,
                       Named_Credential__c, Temperature__c, Max_Tokens__c, Top_P__c,
                       Max_Total_Tokens__c, Processing_Class__c, Connector_Class__c,
                       Additional_Parameters__c, Version__c, Type__c
                FROM AI_Connection__c
                WHERE Name = 'GPTfy (OpenAI)'
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            if (connections.isEmpty()) {
                System.debug('No GPTfy connection found, falling back to manual detection');
                return null;
            }
            
            AI_Connection__c connection = connections[0];
            
            // Build schema context with child objects and their fields
            String schemaContext = buildSchemaContext(targetObject, schemaInfo);
            
            // Build system prompt for data context detection
            String systemPrompt = 'You are a Salesforce data expert. Based on the user\'s business context and available schema, determine which fields and child relationships are needed. ' +
                'Return ONLY a JSON object with this exact structure:\n' +
                '{\n' +
                '  "mainObjectFields": ["Name", "Industry", "BillingCity"],\n' +
                '  "childRelationships": [\n' +
                '    {\n' +
                '      "objectName": "Opportunity",\n' +
                '      "relationshipName": "Opportunities",\n' +
                '      "fields": ["Name", "Amount", "StageName"]\n' +
                '    }\n' +
                '  ]\n' +
                '}\n' +
                'CRITICAL Rules:\n' +
                '- ALWAYS include at least 5-10 relevant fields for the main object (Name, Id, and other key fields)\n' +
                '- ALWAYS include the child relationships mentioned in the business context\n' +
                '- For each child relationship, include at least 3-5 relevant fields\n' +
                '- Use ONLY fields that exist in the provided schema\n' +
                '- Use ONLY child objects that exist in the provided schema\n' +
                '- Use exact Salesforce API names from the schema (no __c unless it\'s in the schema)\n' +
                '- If business context mentions "opportunities", include the Opportunities relationship\n' +
                '- If business context mentions "opportunity roles" or "contact roles", include OpportunityContactRoles relationship\n' +
                '- Maximum 3 child relationships\n' +
                '- Return ONLY the JSON, no explanations or markdown';
            
            // Truncate golden prompt if too long (keep first 3000 chars to avoid token limits)
            String promptSample = goldenPrompt;
            if (promptSample.length() > 3000) {
                promptSample = promptSample.substring(0, 3000) + '...[truncated]';
            }
            
            // Build user prompt with schema context AND golden prompt
            String userPrompt = 'Target Object: ' + targetObject + '\n\n' +
                'Business Context: ' + businessContext + '\n\n' +
                'Generated Prompt Command (READ THIS CAREFULLY - it tells you exactly what data is needed):\n' +
                '---\n' + promptSample + '\n---\n\n' +
                'Available Schema:\n' + schemaContext + '\n\n' +
                'CRITICAL TASK: Read the "Generated Prompt Command" above. It explicitly tells you:\n' +
                '- Which child objects to query (e.g., "Query related Opportunities", "Include OpportunityContactRoles")\n' +
                '- Which fields to include (e.g., "Display Account Name, Industry", "Show Opportunity Amount, Stage")\n\n' +
                'Extract this information and return a JSON with:\n' +
                '1. mainObjectFields: ALL field names mentioned for the main object in the prompt\n' +
                '2. childRelationships: ALL child objects mentioned in the prompt, with their fields\n\n' +
                'Example - If prompt says "Query related Opportunities with Name, Amount and their Contact Roles":\n' +
                '{\n' +
                '  "mainObjectFields": ["Id", "Name", "Industry"],\n' +
                '  "childRelationships": [\n' +
                '    {"objectName": "Opportunity", "relationshipName": "Opportunities", "fields": ["Name", "Amount", "StageName"]},\n' +
                '    {"objectName": "OpportunityContactRole", "relationshipName": "OpportunityContactRoles", "fields": ["Role", "IsPrimary", "ContactId"]}\n' +
                '  ]\n' +
                '}\n\n' +
                'IMPORTANT: Look for phrases like "Query related...", "Include...", "Display...", "Show..." in the prompt command.\n' +
                'Return ONLY the JSON, no explanations:';
            
            // Create temp prompt for callout
            AI_Prompt__c tempPrompt = new AI_Prompt__c();
            tempPrompt.Prompt_Command__c = systemPrompt;
            tempPrompt.AI_Connection__c = connection.Id;
            tempPrompt.AI_Connection__r = connection;
            tempPrompt.Max_Output_Tokens__c = 3000;
            tempPrompt.Temperature__c = 0.3;
            tempPrompt.Type__c = AIConstants.AI_MODEL_TYPE_CHAT;
            
            System.debug('Calling AI with schema context (' + schemaContext.length() + ' chars)');
            
            // Make callout
            String response = AIGPTfyCalloutController.processRequest(
                systemPrompt,
                userPrompt,
                tempPrompt
            );
            
            if (String.isBlank(response)) {
                return null;
            }
            
            // Parse response
            String parsedResponse;
            if (connection.AI_Technology__c == AIConstants.PRODUCT_NAME) {
                parsedResponse = ChatGPTUtills.parseGPTfyResponse(response);
            } else {
                parsedResponse = ChatGPTUtills.parseOtherResponse(response);
            }
            
            System.debug('AI-generated data context: ' + parsedResponse);
            return parsedResponse;
        } catch (Exception e) {
            System.debug('AI data context generation failed: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Builds schema context string with child objects and their fields
     */
    private static String buildSchemaContext(String targetObject, Map<String, Object> schemaInfo) {
        List<String> contextParts = new List<String>();
        
        // Add main object fields
        contextParts.add('Main Object (' + targetObject + ') Fields:');
        Set<String> mainFields = AISchemaHelper.getSafeQueryableFields(targetObject);
        List<String> mainFieldsList = new List<String>(mainFields);
        if (mainFieldsList.size() > 20) {
            mainFieldsList = new List<String>();
            Integer count = 0;
            for (String field : mainFields) {
                mainFieldsList.add(field);
                count++;
                if (count >= 20) break;
            }
        }
        contextParts.add(String.join(mainFieldsList, ', '));
        contextParts.add('\n');
        
        // Add child relationships with their fields
        if (schemaInfo != null && schemaInfo.containsKey('childRelationships')) {
            List<Object> childRels = (List<Object>) schemaInfo.get('childRelationships');
            if (childRels != null && !childRels.isEmpty()) {
                contextParts.add('Available Child Relationships:');
                Integer childCount = 0;
                for (Object childRelObj : childRels) {
                    if (childCount >= 10) break; // Limit to 10 child objects to keep context manageable
                    
                    Map<String, Object> childRel = (Map<String, Object>) childRelObj;
                    String childObject = (String) childRel.get('childObject');
                    String relationshipName = (String) childRel.get('relationshipName');
                    
                    if (String.isNotBlank(childObject) && String.isNotBlank(relationshipName)) {
                        contextParts.add('\n- ' + relationshipName + ' (' + childObject + '):');
                        contextParts.add('  Fields: ');
                        
                        // Get fields for this child object
                        Set<String> childFields = AISchemaHelper.getSafeQueryableFields(childObject);
                        List<String> childFieldsList = new List<String>(childFields);
                        if (childFieldsList.size() > 10) {
                            childFieldsList = new List<String>();
                            Integer fieldCount = 0;
                            for (String field : childFields) {
                                childFieldsList.add(field);
                                fieldCount++;
                                if (fieldCount >= 10) break;
                            }
                        }
                        contextParts.add(String.join(childFieldsList, ', '));
                        childCount++;
                    }
                }
            }
        }
        
        return String.join(contextParts, '\n');
    }

    /**
     * Builds record data JSON using the Data Context Mapping
     * @param mappingId ID of the AI_Data_Extraction_Mapping__c
     * @param recordId ID of the record to query
     * @return JSON string with record data
     */
    private static String buildRecordDataFromMapping(String mappingId, String recordId) {
        try {
            if (String.isBlank(mappingId)) {
                throw new AuraHandledException('Data Context Mapping is required.');
            }
            
            // Get the mapping
            AI_Data_Extraction_Mapping__c mapping = [
                SELECT Id, Object_Name__c
                FROM AI_Data_Extraction_Mapping__c
                WHERE Id = :mappingId
                WITH USER_MODE
                LIMIT 1
            ];
            
            // Get fields for the main object
            List<AI_Data_Extraction_Field__c> fields = [
                SELECT Field__c, Object__c, Type__c
                FROM AI_Data_Extraction_Field__c
                WHERE AI_Data_Extraction_Mapping__c = :mappingId
                AND Object__c = :mapping.Object_Name__c
                AND Type__c = 'FIELD'
                WITH USER_MODE
            ];
            
            List<String> fieldNames = new List<String>{'Id'};
            for (AI_Data_Extraction_Field__c field : fields) {
                fieldNames.add(field.Field__c);
            }
            
            // Query the main record
            String query = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + mapping.Object_Name__c + ' WHERE Id = :recordId WITH USER_MODE LIMIT 1';
            List<SObject> records = Database.query(query);
            
            if (records.isEmpty()) {
                throw new AuraHandledException('Record not found: ' + recordId);
            }
            
            Map<String, Object> recordData = new Map<String, Object>();
            recordData.put(mapping.Object_Name__c, records[0]);
            
            // Get child relationships
            List<AI_Data_Extraction_Detail__c> childDetails = [
                SELECT Object_Name__c, RelationshipName__c, RelationshipField__c, Record_Limit__c
                FROM AI_Data_Extraction_Detail__c
                WHERE AI_Data_Extraction_Mapping__c = :mappingId
                WITH USER_MODE
                LIMIT 3
            ];
            
            // Query child records
            for (AI_Data_Extraction_Detail__c detail : childDetails) {
                try {
                    // Get fields for child object
                    List<AI_Data_Extraction_Field__c> childFields = [
                        SELECT Field__c
                        FROM AI_Data_Extraction_Field__c
                        WHERE AI_Data_Extraction_Mapping__c = :mappingId
                        AND Object__c = :detail.Object_Name__c
                        AND Type__c = 'FIELD'
                        WITH USER_MODE
                    ];
                    
                    List<String> childFieldNames = new List<String>{'Id'};
                    for (AI_Data_Extraction_Field__c childField : childFields) {
                        childFieldNames.add(childField.Field__c);
                    }
                    
                    Integer recordLimit = detail.Record_Limit__c != null ? Integer.valueOf(detail.Record_Limit__c) : 10;
                    String childQuery = 'SELECT ' + String.join(childFieldNames, ', ') + 
                                       ' FROM ' + detail.Object_Name__c + 
                                       ' WHERE ' + detail.RelationshipField__c + ' = :recordId' +
                                       ' WITH USER_MODE LIMIT ' + recordLimit;
                    
                    List<SObject> childRecords = Database.query(childQuery);
                    if (!childRecords.isEmpty()) {
                        recordData.put(detail.RelationshipName__c, childRecords);
                    }
                } catch (Exception childEx) {
                    System.debug('Error querying child relationship ' + detail.RelationshipName__c + ': ' + childEx.getMessage());
                }
            }
            
            return JSON.serializePretty(recordData);
            
        } catch (Exception e) {
            System.debug('Error building record data from mapping: ' + e.getMessage());
            throw new AuraHandledException('Failed to build record data: ' + e.getMessage());
        }
    }
    
    /**
     * Refine a golden prompt with user instructions
     * @param currentPrompt The current prompt text
     * @param refinementInstruction User's refinement instruction
     * @param aiModelId The AI Connection ID to use
     * @return Map with refined prompt text and character count
     * @jira V2-7823
     */
    @AuraEnabled
    public static Map<String, Object> refinePrompt(String currentPrompt, String refinementInstruction, String aiModelId) {
        try {
            if (String.isBlank(currentPrompt)) {
                throw new AuraHandledException('Current prompt is required.');
            }
            
            if (String.isBlank(refinementInstruction)) {
                throw new AuraHandledException('Refinement instruction is required.');
            }
            
            if (String.isBlank(aiModelId)) {
                throw new AuraHandledException('AI Model is required.');
            }
            
            // Use AIMetaPromptService for refinement (same pattern as generation)
            String refinedPrompt = AIMetaPromptService.refineGoldenPrompt(
                currentPrompt,
                refinementInstruction,
                aiModelId
            );
            
            return new Map<String, Object>{
                'goldenPrompt' => refinedPrompt,
                'charCount' => refinedPrompt.length()
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Refinement error: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Refinement failed: ' + e.getMessage());
        }
    }
    
    /**
     * Helper method to get record data as JSON
     * @param objectName The Salesforce object API name
     * @param recordId The record ID
     * @return JSON string with record data
     */
    private static String getRecordDataAsJson(String objectName, String recordId) {
        try {
            // Get all accessible and queryable fields for the object
            Set<String> safeFieldsSet = AISchemaHelper.getSafeQueryableFields(objectName);
            List<String> safeFields = new List<String>(safeFieldsSet);
            
            if (safeFields.isEmpty()) {
                safeFields.add('Id');
            }
            
            // Build and execute query
            String query = 'SELECT ' + String.join(safeFields, ', ') + ' FROM ' + objectName + ' WHERE Id = :recordId WITH USER_MODE LIMIT 1';
            List<SObject> records = Database.query(query);
            
            if (records.isEmpty()) {
                throw new AuraHandledException('Record not found: ' + recordId);
            }
            
            return JSON.serializePretty(records[0]);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching record data: ' + e.getMessage());
        }
    }
    
    /**
     * Helper method to parse AI response
     * @param response The raw AI response
     * @return Parsed HTML output
     */
    private static String parseAIResponse(String response) {
        try {
            // Check for errors first
            String errorMsg = ChatGPTUtills.getErrorMessage(response);
            if (String.isNotBlank(errorMsg)) {
                return 'AI Error: ' + errorMsg;
            }

            // Try parsing as GPTfy response
            try {
                String gptfyResponse = ChatGPTUtills.parseGPTfyResponse(response);
                if (String.isNotBlank(gptfyResponse)) {
                    return gptfyResponse;
                }
            } catch (Exception e) {
                System.debug('GPTfy parse failed: ' + e.getMessage());
            }

            // Try parsing as ChatGPT response (with empty model parameter)
            try {
                String chatGptResponse = ChatGPTUtills.parseChatGptResponse(response, '');
                if (String.isNotBlank(chatGptResponse)) {
                    return chatGptResponse;
                }
            } catch (Exception e) {
                System.debug('ChatGPT parse failed: ' + e.getMessage());
            }

            // Try parsing as other response
            try {
                String otherResponse = ChatGPTUtills.parseOtherResponse(response);
                if (String.isNotBlank(otherResponse)) {
                    return otherResponse;
                }
            } catch (Exception e) {
                System.debug('Other parse failed: ' + e.getMessage());
            }

            // If all parsing fails, return raw response
            return response;
        } catch (Exception e) {
            System.debug('Parse error: ' + e.getMessage());
            // Return raw response on any error
            return response;
        }
    }
    
    /**
     * Creates a complete Data Context Mapping with fields and child objects
     * Uses intelligent object detection based on business context AND generated prompt
     * @param mappingName Name for the mapping
     * @param targetObject Target Salesforce object
     * @param goldenPrompt The generated golden prompt text
     * @param schemaInfo Schema information from discoverSchema method
     * @param businessContext User's business context for intelligent object detection
     * @param priorityChildObjects Pre-analyzed priority child objects (optional)
     * @return ID of the created mapping
     */
    private static String createDataContextMapping(String mappingName, String targetObject,
                                                   String goldenPrompt,
                                                   Map<String, Object> schemaInfo,
                                                   String businessContext,
                                                   List<String> priorityChildObjects) {
        try {
            // Step 1: Try to use AI to determine data context (like AIAdvancePromptBuilder)
            // Pass BOTH business context AND golden prompt for better field selection
            String aiGeneratedContext = null;
            if (String.isNotBlank(businessContext) && String.isNotBlank(goldenPrompt)) {
                System.debug('Generating data context mapping with AI using golden prompt');
                aiGeneratedContext = generateDataContextMappingWithAI(targetObject, businessContext, goldenPrompt, schemaInfo);
            }
            
            // Step 2: Parse AI-generated context or fall back to manual analysis
            Map<String, Object> dataContextMap = null;
            if (String.isNotBlank(aiGeneratedContext)) {
                try {
                    dataContextMap = (Map<String, Object>) JSON.deserializeUntyped(aiGeneratedContext);
                    System.debug('AI-generated data context: ' + JSON.serializePretty(dataContextMap));
                    System.debug('Using AI-generated data context mapping');
                } catch (Exception parseEx) {
                    System.debug('Failed to parse AI-generated context: ' + parseEx.getMessage());
                    System.debug('Raw AI response: ' + aiGeneratedContext);
                }
            }
            
            // Step 3: Fall back to manual analysis if AI failed OR if AI returned empty data
            Boolean useManualAnalysis = false;
            if (dataContextMap == null) {
                System.debug('AI generation failed, falling back to manual business context analysis');
                useManualAnalysis = true;
            } else {
                // Check if AI returned empty or invalid data
                List<Object> mainFields = (List<Object>) dataContextMap.get('mainObjectFields');
                List<Object> childRels = (List<Object>) dataContextMap.get('childRelationships');
                
                if ((mainFields == null || mainFields.isEmpty()) && (childRels == null || childRels.isEmpty())) {
                    System.debug('AI returned empty data, falling back to manual analysis');
                    useManualAnalysis = true;
                    dataContextMap = null;
                }
            }
            
            if (useManualAnalysis) {
                if (priorityChildObjects == null || priorityChildObjects.isEmpty()) {
                    AIBusinessContextAnalyzer.AnalysisResult analysis =
                        AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, targetObject);
                    priorityChildObjects = analysis.priorityChildObjects;
                    System.debug('Intelligent object detection: ' + analysis.analysisNotes);
                }
            }

            // Step 4: Create the main mapping record
            AI_Data_Extraction_Mapping__c mapping = new AI_Data_Extraction_Mapping__c(
                Name = mappingName + ' Mapping',
                Object_Name__c = targetObject,
                Description__c = 'Auto-generated mapping for AI Prompt Factory',
                Status__c = 'Active'
            );

            List<AI_Data_Extraction_Mapping__c> mappingsToInsert = new List<AI_Data_Extraction_Mapping__c>{ mapping };
            List<SObject> insertedMappings = FLSCheck.getInstance().insertDML(mappingsToInsert);

            if (insertedMappings == null || insertedMappings.isEmpty()) {
                return null;
            }

            String mappingId = String.valueOf(insertedMappings[0].Id);

            // Step 5: Create fields and relationships based on AI or manual analysis
            if (dataContextMap != null) {
                System.debug('Creating mapping from AI-generated data context');
                
                // Use AI-generated data context (like AIAdvancePromptBuilder)
                List<Object> mainObjectFieldsObj = (List<Object>) dataContextMap.get('mainObjectFields');
                if (mainObjectFieldsObj != null && !mainObjectFieldsObj.isEmpty()) {
                    List<String> mainObjectFields = new List<String>();
                    for (Object fieldObj : mainObjectFieldsObj) {
                        String fieldName = (String) fieldObj;
                        if (String.isNotBlank(fieldName)) {
                            mainObjectFields.add(fieldName);
                        }
                    }
                    System.debug('Creating ' + mainObjectFields.size() + ' main object fields: ' + mainObjectFields);
                    if (!mainObjectFields.isEmpty()) {
                        createDataExtractionFields(mappingId, targetObject, mainObjectFields);
                    }
                } else {
                    System.debug('WARNING: No main object fields in AI response, using all accessible fields');
                    // Fall back to all accessible fields if AI didn't provide any
                    Set<String> safeFields = AISchemaHelper.getSafeQueryableFields(targetObject);
                    List<String> mainObjectFields = new List<String>(safeFields);
                    if (!mainObjectFields.isEmpty()) {
                        createDataExtractionFields(mappingId, targetObject, mainObjectFields);
                    }
                }
                
                List<Object> childRelationships = (List<Object>) dataContextMap.get('childRelationships');
                if (childRelationships != null && !childRelationships.isEmpty()) {
                    System.debug('Creating ' + childRelationships.size() + ' child relationships from AI data');
                    createDataExtractionDetailsFromAI(mappingId, targetObject, childRelationships);
                } else {
                    System.debug('WARNING: No child relationships in AI response');
                }
            } else {
                // Use manual analysis approach
                Set<String> safeFields = AISchemaHelper.getSafeQueryableFields(targetObject);
                List<String> mainObjectFields = new List<String>(safeFields);
                
                if (!mainObjectFields.isEmpty()) {
                    createDataExtractionFields(mappingId, targetObject, mainObjectFields);
                }
                
                List<AISchemaHelper.ChildRelationship> allChildRelationships =
                    AISchemaHelper.getChildRelationships(targetObject);
                
                List<AISchemaHelper.ChildRelationship> filteredChildren =
                    AIBusinessContextAnalyzer.filterChildRelationships(allChildRelationships, priorityChildObjects);
                
                System.debug('Creating data context mapping with ' + filteredChildren.size() +
                            ' child relationships based on business context');
                
                if (filteredChildren != null && !filteredChildren.isEmpty()) {
                    createDataExtractionDetails(mappingId, targetObject, filteredChildren);
                }
            }

            return mappingId;

        } catch (Exception e) {
            System.debug('Error creating data context mapping: ' + e.getMessage());
            throw new AuraHandledException('Failed to create data context mapping: ' + e.getMessage());
        }
    }
    
    /**
     * Creates AI_Data_Extraction_Field__c records for the main object
     */
    private static void createDataExtractionFields(String mappingId, String objectName, List<String> fields) {
        try {
            List<AI_Data_Extraction_Field__c> fieldRecords = new List<AI_Data_Extraction_Field__c>();
            
            // Create OBJECT type record
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
            
            // Create FIELD type records
            for (String fieldApi : fields) {
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
            System.debug('Error creating extraction fields: ' + e.getMessage());
        }
    }
    
    /**
     * Creates AI_Data_Extraction_Detail__c records from AI-generated child relationships
     * Similar to AIAdvancePromptBuilderController.createDataExtractionDetails
     */
    private static void createDataExtractionDetailsFromAI(String mappingId, String parentObject, List<Object> childRelationships) {
        try {
            final Integer MAX_CHILD_RELATIONSHIPS = 3;
            List<AI_Data_Extraction_Detail__c> details = new List<AI_Data_Extraction_Detail__c>();
            Integer processedCount = 0;
            
            for (Object childRelObj : childRelationships) {
                if (processedCount >= MAX_CHILD_RELATIONSHIPS) break;
                
                Map<String, Object> childRel = (Map<String, Object>) childRelObj;
                String childObjectName = (String) childRel.get('objectName');
                String relationshipName = (String) childRel.get('relationshipName');
                
                if (String.isBlank(childObjectName) || String.isBlank(relationshipName)) {
                    continue;
                }
                
                AI_Data_Extraction_Detail__c detail = new AI_Data_Extraction_Detail__c(
                    AI_Data_Extraction_Mapping__c = mappingId,
                    Object_Name__c = childObjectName,
                    RelationshipName__c = relationshipName,
                    Record_Limit__c = 10,
                    Order_By__c = 'CreatedDate DESC',
                    Type__c = 'CHILD'
                );
                details.add(detail);
                processedCount++;
            }
            
            if (!details.isEmpty()) {
                List<SObject> insertedDetails = FLSCheck.getInstance().insertDML(details);
                
                // Create fields for each child object
                for (Object childRelObj : childRelationships) {
                    Map<String, Object> childRel = (Map<String, Object>) childRelObj;
                    List<Object> fieldsObj = (List<Object>) childRel.get('fields');
                    
                    if (fieldsObj != null && !fieldsObj.isEmpty()) {
                        List<String> fields = new List<String>();
                        for (Object fieldObj : fieldsObj) {
                            fields.add((String) fieldObj);
                        }
                        
                        String childObjectName = (String) childRel.get('objectName');
                        createDataExtractionFieldsForDetail(mappingId, childObjectName, fields);
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error creating extraction details from AI: ' + e.getMessage());
        }
    }
    
    /**
     * Creates AI_Data_Extraction_Field__c records for a child object
     * Note: Fields go to the mapping, not the detail
     */
    private static void createDataExtractionFieldsForDetail(String mappingId, String objectName, List<String> fields) {
        try {
            List<AI_Data_Extraction_Field__c> fieldRecords = new List<AI_Data_Extraction_Field__c>();
            
            // Add OBJECT type record
            AI_Data_Extraction_Field__c objectField = new AI_Data_Extraction_Field__c(
                AI_Data_Extraction_Mapping__c = mappingId,
                Object__c = objectName,
                Field__c = objectName,
                Label__c = objectName,
                Type__c = 'OBJECT',
                Send_To_AI__c = false
            );
            fieldRecords.add(objectField);
            
            // Add FIELD type records
            for (String fieldApi : fields) {
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
            System.debug('Error creating extraction fields for child: ' + e.getMessage());
        }
    }

    /**
     * Creates AI_Data_Extraction_Detail__c records for child objects
     * Note: Child relationships are already filtered by business context analyzer
     * Also creates level 2 (grandchildren) relationships for at least one child
     */
    private static void createDataExtractionDetails(String mappingId, String parentObject, List<AISchemaHelper.ChildRelationship> childRelationships) {
        try {
            List<AI_Data_Extraction_Detail__c> details = new List<AI_Data_Extraction_Detail__c>();
            Integer processedCount = 0;
            
            for (AISchemaHelper.ChildRelationship childRel : childRelationships) {
                if (String.isBlank(childRel.relationshipName)) {
                    continue;
                }
                
                AI_Data_Extraction_Detail__c detail = new AI_Data_Extraction_Detail__c(
                    AI_Data_Extraction_Mapping__c = mappingId,
                    Object_Name__c = childRel.childObject,
                    RelationshipName__c = childRel.relationshipName,
                    RelationshipField__c = childRel.field,
                    Record_Limit__c = 10
                );
                details.add(detail);
                processedCount++;
            }
            
            if (!details.isEmpty()) {
                List<SObject> insertedDetails = FLSCheck.getInstance().insertDML(details);
                
                // Track which child objects we've processed for level 2
                Map<String, String> childObjectToDetailId = new Map<String, String>();
                
                // Create fields for each child object
                if (insertedDetails != null && !insertedDetails.isEmpty()) {
                    List<AI_Data_Extraction_Field__c> childFields = new List<AI_Data_Extraction_Field__c>();
                    
                    for (Integer i = 0; i < insertedDetails.size(); i++) {
                        AISchemaHelper.ChildRelationship childRel = childRelationships[i];
                        String detailId = String.valueOf(insertedDetails[i].Id);
                        
                        // Store mapping for level 2 processing
                        childObjectToDetailId.put(childRel.childObject, detailId);
                        
                        // Get fields for child object
                        List<AISchemaHelper.FieldMetadata> childObjFields = AISchemaHelper.getFields(childRel.childObject);
                        List<String> selectedFields = new List<String>();
                        
                        for (AISchemaHelper.FieldMetadata field : childObjFields) {
                            if (field.isAccessible) {
                                selectedFields.add(field.name);
                                if (selectedFields.size() >= 10) {
                                    break;
                                }
                            }
                        }
                        
                        // Create OBJECT type field
                        Schema.DescribeSObjectResult childObjDescribe = Schema.getGlobalDescribe().get(childRel.childObject).getDescribe();
                        AI_Data_Extraction_Field__c objectField = new AI_Data_Extraction_Field__c(
                            AI_Data_Extraction_Mapping__c = mappingId,
                            Object__c = childRel.childObject,
                            Field__c = childRel.childObject,
                            Label__c = childObjDescribe.getLabel(),
                            Type__c = 'OBJECT',
                            Send_To_AI__c = false
                        );
                        childFields.add(objectField);
                        
                        // Create FIELD type records
                        for (String fieldApi : selectedFields) {
                            AI_Data_Extraction_Field__c field = new AI_Data_Extraction_Field__c(
                                AI_Data_Extraction_Mapping__c = mappingId,
                                Object__c = childRel.childObject,
                                Field__c = fieldApi,
                                Label__c = fieldApi,
                                Send_To_AI__c = true,
                                Type__c = 'FIELD'
                            );
                            childFields.add(field);
                        }
                    }
                    
                    if (!childFields.isEmpty()) {
                        FLSCheck.getInstance().insertDML(childFields);
                    }
                    
                    // === CREATE LEVEL 2 RELATIONSHIPS (GRANDCHILDREN) ===
                    // Create at least one level 2 relationship for the first child object
                    createLevel2Relationships(mappingId, childRelationships, childObjectToDetailId);
                }
            }
            
        } catch (Exception e) {
            System.debug('Error creating extraction details: ' + e.getMessage());
        }
    }
    
    /**
     * Creates level 2 (grandchildren) relationships for child objects
     * Creates at least one level 2 relationship for better data context
     */
    private static void createLevel2Relationships(
        String mappingId, 
        List<AISchemaHelper.ChildRelationship> childRelationships,
        Map<String, String> childObjectToDetailId) {
        
        try {
            List<AI_Data_Extraction_Detail__c> level2Details = new List<AI_Data_Extraction_Detail__c>();
            Integer level2Count = 0;
            
            // Create level 2 for the first child object (at minimum)
            for (AISchemaHelper.ChildRelationship childRel : childRelationships) {
                if (level2Count >= 1) {
                    break; // Only create level 2 for first child
                }
                
                // Get level 2 relationship for this child
                AISchemaHelper.ChildRelationship grandchild = 
                    AIBusinessContextAnalyzer.getLevel2Relationship(childRel.childObject, '');
                
                if (grandchild != null && String.isNotBlank(grandchild.relationshipName)) {
                    String parentDetailId = childObjectToDetailId.get(childRel.childObject);
                    
                    AI_Data_Extraction_Detail__c level2Detail = new AI_Data_Extraction_Detail__c(
                        AI_Data_Extraction_Mapping__c = mappingId,
                        Object_Name__c = grandchild.childObject,
                        RelationshipName__c = grandchild.relationshipName,
                        RelationshipField__c = grandchild.field,
                        Record_Limit__c = 5,
                        Parent_Detail__c = parentDetailId
                    );
                    level2Details.add(level2Detail);
                    level2Count++;
                    
                    System.debug('Created level 2 relationship: ' + childRel.childObject + 
                               ' -> ' + grandchild.childObject);
                }
            }
            
            // Insert level 2 details
            if (!level2Details.isEmpty()) {
                List<SObject> insertedLevel2 = FLSCheck.getInstance().insertDML(level2Details);
                
                // Create fields for level 2 objects
                if (insertedLevel2 != null && !insertedLevel2.isEmpty()) {
                    List<AI_Data_Extraction_Field__c> level2Fields = new List<AI_Data_Extraction_Field__c>();
                    
                    for (Integer i = 0; i < insertedLevel2.size(); i++) {
                        String grandchildObject = level2Details[i].Object_Name__c;
                        
                        // Get fields for grandchild object (limit to 5 fields)
                        List<AISchemaHelper.FieldMetadata> grandchildFields = 
                            AISchemaHelper.getFields(grandchildObject);
                        List<String> selectedFields = new List<String>();
                        
                        for (AISchemaHelper.FieldMetadata field : grandchildFields) {
                            if (field.isAccessible) {
                                selectedFields.add(field.name);
                                if (selectedFields.size() >= 5) {
                                    break;
                                }
                            }
                        }
                        
                        // Create OBJECT type field
                        Schema.DescribeSObjectResult objDescribe = 
                            Schema.getGlobalDescribe().get(grandchildObject).getDescribe();
                        AI_Data_Extraction_Field__c objectField = new AI_Data_Extraction_Field__c(
                            AI_Data_Extraction_Mapping__c = mappingId,
                            Object__c = grandchildObject,
                            Field__c = grandchildObject,
                            Label__c = objDescribe.getLabel(),
                            Type__c = 'OBJECT',
                            Send_To_AI__c = false
                        );
                        level2Fields.add(objectField);
                        
                        // Create FIELD type records
                        for (String fieldApi : selectedFields) {
                            AI_Data_Extraction_Field__c field = new AI_Data_Extraction_Field__c(
                                AI_Data_Extraction_Mapping__c = mappingId,
                                Object__c = grandchildObject,
                                Field__c = fieldApi,
                                Label__c = fieldApi,
                                Send_To_AI__c = true,
                                Type__c = 'FIELD'
                            );
                            level2Fields.add(field);
                        }
                    }
                    
                    if (!level2Fields.isEmpty()) {
                        FLSCheck.getInstance().insertDML(level2Fields);
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('Error creating level 2 relationships: ' + e.getMessage());
            // Don't throw - level 2 is optional
        }
    }
}