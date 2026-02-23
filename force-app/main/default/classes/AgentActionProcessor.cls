/**
 * @description:
 *   AgentActionProcessor handles post-AI-response action processing.
 *   Responsible for parsing structured AI responses, processing intents,
 *   and executing action details (Canned Response, Update Field, Create Record, Flow, Apex).
 *
 * @author            : Sagar Alwani
 * @group             : GPTfy
 * @last modified on  : 30-01-2026
 * @last modified by  : Sagar Alwani
 * @jira              : V2-7338
 **/
public with sharing class AgentActionProcessor {

    /**
     * @description Result wrapper for intent processing
     */
    public class ActionResult {
        public String message;
        public List<String> intents;
        public String language;
        public Boolean success;
        public String errorMessage;
        
        public ActionResult() {
            this.intents = new List<String>();
            this.language = 'en';
            this.success = true;
        }
    }

    /**
     * @description Parsed AI response structure
     */
    public class ParsedResponse {
        public String message;
        public List<String> intents;
        public String language;
        public Map<String, Object> additionalParameters;
        
        public ParsedResponse() {
            this.intents = new List<String>();
            this.language = 'en';
            this.additionalParameters = new Map<String, Object>();
        }
    }

    /**
     * @description Request context wrapper for Update Field operations
     */
    public class RequestContext {
        public String relatedToId;
        public String recordId;
        
        public RequestContext() {}
        
        public RequestContext(String relatedToId, String recordId) {
            this.relatedToId = relatedToId;
            this.recordId = recordId;
        }
    }

    /**
     * Main entry point for processing Agent Intents from AI response.
     * Parses the structured JSON, processes each intent, and returns the final result.
     *
     * @param responseBody Raw response body from AI (OpenAI Responses API format)
     * @param agentId The AI_Agent__c Id to query related intents
     * @param context Optional RequestContext with relatedToId and recordId for Update Field actions
     * @return ActionResult with processed message, actions, and language
     */
    public static ActionResult process(String responseBody, Id agentId, RequestContext context) {
        System.debug('@@Before Process');
        System.debug('@@responseBody = ' + responseBody);
        ActionResult result = new ActionResult();
        
        // Store response body for Apex action processing
        currentResponseBody = responseBody;
        
        try {
            if (String.isBlank(responseBody)) {
                result.message = '';
                return result;
            }
            
            // Extract the AI message content from OpenAI response format
            String aiMessageContent = extractAIMessageContent(responseBody);
            
            if (String.isBlank(aiMessageContent)) {
                result.message = responseBody;
                return result;
            }
            
            // Try to parse as structured JSON
            ParsedResponse parsedResponse = parseStructuredResponse(aiMessageContent);
            
            if (parsedResponse == null) {
                // Not structured JSON, return as-is
                result.message = aiMessageContent;
                return result;
            }
            
            // Set values from parsed response
            result.message = parsedResponse.message;
            result.intents = parsedResponse.intents;
            result.language = parsedResponse.language;
            System.debug('@result after running AI' + result);
            // Process intents if any exist
            if (parsedResponse.intents != null && !parsedResponse.intents.isEmpty() && agentId != null) {
                processIntents(result, parsedResponse.intents, parsedResponse.language, agentId, parsedResponse.additionalParameters, context);
            }
            
            return result;
        } catch (Exception ex) {
            result.message = responseBody;
            result.success = false;
            result.errorMessage = ex.getMessage();
            return result;
        }
    }

    /**
     * Extracts the actual message content from OpenAI Responses API output.
     *
     * @param responseBody Raw API response
     * @return Extracted message text
     */
    private static String extractAIMessageContent(String responseBody) {
        try {
            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (dataMap != null && dataMap.containsKey('output')) {
                List<Object> outputList = (List<Object>) dataMap.get('output');
                for (Object item : outputList) {
                    Map<String, Object> itemMap = (Map<String, Object>) item;
                    if (itemMap.get('type') == 'message') {
                        List<Object> contentList = (List<Object>) itemMap.get('content');
                        if (contentList != null && !contentList.isEmpty()) {
                            Map<String, Object> contentMap = (Map<String, Object>) contentList.get(0);
                            if (contentMap.containsKey('text')) {
                                return String.valueOf(contentMap.get('text'));
                            }
                        }
                    }
                }
            }
            return responseBody;
        } catch (Exception ex) {
            return responseBody;
        }
    }

    /**
     * Parses the structured JSON response from AI.
     * Expected format: {"message": "...", "intents": [...], "language": "..."}
     *
     * @param content The message content to parse
     * @return ParsedResponse if valid JSON, null otherwise
     */
    @TestVisible
    private static ParsedResponse parseStructuredResponse(String content) {
        try {
            // Remove markdown code blocks if present
            String cleanContent = content.trim();
            if (cleanContent.startsWith('```json')) {
                cleanContent = cleanContent.substringAfter('```json').substringBeforeLast('```').trim();
            } else if (cleanContent.startsWith('```')) {
                cleanContent = cleanContent.substringAfter('```').substringBeforeLast('```').trim();
            }
            
            // Try to parse as JSON
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(cleanContent);
            
            if (!jsonMap.containsKey('message')) {
                return null; // Not our expected format
            }
            
            ParsedResponse response = new ParsedResponse();
            response.message = String.valueOf(jsonMap.get('message'));
            response.language = jsonMap.containsKey('language') ? String.valueOf(jsonMap.get('language')) : 'en';
            
            if (jsonMap.containsKey('intents')) {
                List<Object> intentsList = (List<Object>) jsonMap.get('intents');
                for (Object intent : intentsList) {
                    response.intents.add(String.valueOf(intent));
                }
            }
            
            // Extract additionalParameters if present
            if (jsonMap.containsKey('additionalParameters')) {
                response.additionalParameters = (Map<String, Object>) jsonMap.get('additionalParameters');
            }
            
            return response;
        } catch (Exception ex) {
            return null; // Not valid JSON
        }
    }

    // Store responseBody at class level for Apex action processing
    private static String currentResponseBody;

    /**
     * Processes all intents by querying Agent Intents and executing their details.
     *
     * @param result ActionResult to update with processed message
     * @param intents List of intent hashtags
     * @param language ISO 639-1 language code
     * @param agentId The AI_Agent__c Id
     * @param additionalParameters Map of parameters extracted by AI, keyed by intent name
     * @param context RequestContext with relatedToId and recordId
     */
    private static void processIntents(ActionResult result, List<String> intents, String language, Id agentId, Map<String, Object> additionalParameters, RequestContext context) {
        try {
            // Normalize intents - remove # prefix for database query
            Set<String> normalizedIntents = new Set<String>();
            for (String intent : intents) {
                // Strip # prefix if present for matching against Name field
                String normalized = intent.startsWith('#') ? intent.substring(1) : intent;
                normalizedIntents.add(normalized);
            }
            
            // Query Agent Intents and their Details
            List<AI_Agent_Intent__c> agentIntentsList = [
                SELECT Id, Name, Sequence__c,
                    (SELECT Id, Action_Type__c, Language__c, Canned_Response__c, 
                            Object_Name__c, Field_API_Name__c, Description__c, Sequence__c,
                            Apex_Class_Name__c, Apex_Return_Type__c, Flow_API_Name__c
                     FROM AI_Intent_Actions__r
                     WHERE Is_Active__c = true
                     ORDER BY Sequence__c ASC)
                FROM AI_Agent_Intent__c
                WHERE AI_Agent__c = :agentId
                  AND Name IN :normalizedIntents
                  AND Is_Active__c = true
                ORDER BY Sequence__c ASC
            ];
            
            for (AI_Agent_Intent__c agentIntent : agentIntentsList) {
                // Get additionalParameters for this specific intent
                Map<String, Object> intentParams = new Map<String, Object>();
                if (additionalParameters != null && additionalParameters.containsKey(agentIntent.Name)) {
                    intentParams = (Map<String, Object>) additionalParameters.get(agentIntent.Name);
                }
                
                if (agentIntent.AI_Intent_Actions__r != null && !agentIntent.AI_Intent_Actions__r.isEmpty()) {
                    Boolean anyActionProcessed = false;

                    for (AI_Intent_Action__c detail : agentIntent.AI_Intent_Actions__r) {
                        Boolean processed = processActionDetail(result, detail, language, intentParams, context, agentId);
                        if (processed) {
                            anyActionProcessed = true;
                        }
                    }

                    if (anyActionProcessed) {
                        return; // Return after all actions for this intent are processed
                    }
                }
            }
        } catch (Exception ex) {
            // Log error but don't fail - keep AI message
        }
    }

    /**
     * Routes an action detail to the appropriate processor based on Action Type.
     *
     * @param result ActionResult to update
     * @param detail AI_Intent_Action__c record
     * @param language ISO 639-1 language code
     * @param intentParams Map of parameters extracted by AI for this intent
     * @param context RequestContext with relatedToId and recordId
     * @param agentId The AI_Agent__c Id for Apex action processing
     * @return true if processed successfully, false otherwise
     */
    private static Boolean processActionDetail(ActionResult result, AI_Intent_Action__c detail, String language, Map<String, Object> intentParams, RequestContext context, Id agentId) {
        switch on detail.Action_Type__c {
            when 'Canned Response' {
                return processCannedResponse(result, detail, language);
            }
            when 'Update Field' {
                return processUpdateField(result, detail, intentParams, context);
            }
            when 'Create Record' {
                return processCreateRecord(result, detail, intentParams, context);
            }
            when 'Apex' {
                return processApexAction(result, detail, intentParams, context, agentId);
            }
            when 'Flow' {
                return processFlowAction(result, detail, intentParams, context);
            }
            when else {
                return false;
            }
        }
    }

    /**
     * Processes Canned Response action type.
     * Replaces the message with canned response if language matches.
     *
     * @param result ActionResult to update
     * @param detail AI_Intent_Action__c record
     * @param language ISO 639-1 language code
     * @return true if canned response was applied, false otherwise
     */
    private static Boolean processCannedResponse(ActionResult result, AI_Intent_Action__c detail, String language) {
        // Check for exact language match
        if (detail.Language__c == language && String.isNotBlank(detail.Canned_Response__c)) {
            result.message = detail.Canned_Response__c;
            return true;
        }
        
        // Check for English fallback
        if (detail.Language__c == 'en' && String.isNotBlank(detail.Canned_Response__c)) {
            result.message = detail.Canned_Response__c;
            return true;
        }
        
        return false;
    }

    /**
     * Processes Update Field action type.
     * Updates a field on a target record based on AI-extracted parameters.
     * Record ID priority: relatedToId (context) → recordId (intentParams) → recordId (context)
     *
     * @param result ActionResult to update
     * @param detail AI_Intent_Action__c record with Object_Name__c and Field_API_Name__c
     * @param intentParams Map of parameters extracted by AI (includes field value and possibly recordId)
     * @param context RequestContext with relatedToId and recordId from original request
     * @return true if processed successfully, false otherwise
     */
    private static Boolean processUpdateField(ActionResult result, AI_Intent_Action__c detail, Map<String, Object> intentParams, RequestContext context) {
        try {
            // Early validation
            if (String.isBlank(detail.Object_Name__c) || String.isBlank(detail.Field_API_Name__c) || intentParams == null) {
                return false;
            }
            
            // Get target record ID (prioritize context.relatedToId, then AI-extracted recordId)
            String targetRecordId = context?.relatedToId;
            if (String.isBlank(targetRecordId)) {
                targetRecordId = (String) intentParams.get('recordId');
            }
            
            // Get field value
            Object fieldValue = intentParams.get(detail.Field_API_Name__c);
            
            // Validate required values
            if (String.isBlank(targetRecordId) || fieldValue == null) {
                return false;
            }
            
            // Execute update
            SObject record = Schema.getGlobalDescribe().get(detail.Object_Name__c).newSObject();
            record.put('Id', targetRecordId);
            record.put(detail.Field_API_Name__c, fieldValue);
            System.debug('Before Update: ' + record);  
            update record;
            System.debug('After Update: ' + record);
            return true;
            
        } catch (Exception ex) {
            result.errorMessage = 'Update Field failed: ' + ex.getMessage();
            return false;
        }
    }

    /**
     * Processes Apex action type.
     * Invokes a custom Apex class implementing AIIntentActionInterface.
     * The class receives a Map with agentId, responseBody, intentParams, relatedToId, recordId.
     *
     * @param result ActionResult to update
     * @param detail AI_Intent_Action__c record with Apex_Class_Name__c and Apex_Return_Type__c
     * @param intentParams Map of parameters extracted by AI for this intent
     * @param context RequestContext with relatedToId and recordId
     * @param agentId The AI_Agent__c Id
     * @return true if processed successfully, false otherwise
     */
    private static Boolean processApexAction(ActionResult result, AI_Intent_Action__c detail, Map<String, Object> intentParams, RequestContext context, Id agentId) {
        try {
            // Validate Apex class name is provided
            if (String.isBlank(detail.Apex_Class_Name__c)) {
                result.errorMessage = 'Apex Action failed: Apex Class Name is required';
                return false;
            }
            
            // Dynamically instantiate the Apex class
            Type apexType = Type.forName('', detail.Apex_Class_Name__c);
            if (apexType == null) {
                result.errorMessage = 'Apex Action failed: Class not found - ' + detail.Apex_Class_Name__c;
                return false;
            }
            
            // Build request Map
            Map<String, Object> request = new Map<String, Object>{
                'agentId' => agentId,
                'responseBody' => currentResponseBody,
                'intentParams' => intentParams,
                'relatedToId' => context?.relatedToId,
                'recordId' => context?.recordId
            };
            
            // Verify it implements the interface and invoke
            AIIntentActionInterface handler = (AIIntentActionInterface) apexType.newInstance();
            Map<String, Object> apexResult = handler.invokeApex(request);
            
            // Handle null result
            if (apexResult == null) {
                return true; // Apex executed but returned no result - keep original message
            }
            
            // Get success status (default to true if not specified)
            Boolean success = apexResult.containsKey('success') ? (Boolean) apexResult.get('success') : true;
            
            // Apply result based on return type configuration
            String apexMessage = (String) apexResult.get('message');
            if (String.isNotBlank(apexMessage)) {
                String returnType = String.isNotBlank(detail.Apex_Return_Type__c) 
                    ? detail.Apex_Return_Type__c 
                    : 'Replace Message';
                
                if (returnType == 'Append to Message') {
                    result.message = result.message + '\n\n' + apexMessage;
                } else {
                    // Default: Replace Message
                    result.message = apexMessage;
                }
            }
            
            // Propagate error message if present
            String errorMsg = (String) apexResult.get('errorMessage');
            if (String.isNotBlank(errorMsg)) {
                result.errorMessage = errorMsg;
            }
            
            return success;
            
        } catch (System.TypeException tex) {
            result.errorMessage = 'Apex Action failed: Class must implement AIIntentActionInterface - ' + detail.Apex_Class_Name__c;
            return false;
        } catch (Exception ex) {
            result.errorMessage = 'Apex Action failed: ' + ex.getMessage();
            return false;
        }
    }

    /**
     * Processes Flow action type.
     * Invokes an Autolaunched Flow by its API name.
     * Passes intentParams as flow input variables.
     *
     * @param result ActionResult to update
     * @param detail AI_Intent_Action__c record with Flow_API_Name__c
     * @param intentParams Map of parameters extracted by AI for this intent
     * @param context RequestContext with relatedToId and recordId
     * @return true if flow was invoked successfully, false otherwise
     */
    private static Boolean processFlowAction(ActionResult result, AI_Intent_Action__c detail, Map<String, Object> intentParams, RequestContext context) {
        try {
            if (String.isBlank(detail.Flow_API_Name__c)) {
                result.errorMessage = 'Flow Action failed: Flow API Name is required';
                return false;
            }

            // Build candidate flow input variables
            Map<String, Object> candidateInputs = new Map<String, Object>();
            if (intentParams != null) {
                candidateInputs.putAll(intentParams);
            }
            if (context?.relatedToId != null) {
                candidateInputs.put('relatedToId', context.relatedToId);
            }
            if (context?.recordId != null) {
                candidateInputs.put('recordId', context.recordId);
            }

            // Try with all inputs first; fall back to empty inputs if flow doesn't accept them
            Flow.Interview flowInterview;
            try {
                flowInterview = Flow.Interview.createInterview(detail.Flow_API_Name__c, candidateInputs);
                flowInterview.start();
            } catch (Exception inputEx) {
                // Flow doesn't define matching input variables — retry with empty inputs
                System.debug('Flow input variable mismatch, retrying with empty inputs: ' + inputEx.getMessage());
                flowInterview = Flow.Interview.createInterview(detail.Flow_API_Name__c, new Map<String, Object>());
                flowInterview.start();
            }

            return true;

        } catch (Exception ex) {
            result.errorMessage = 'Flow Action failed: ' + ex.getMessage();
            return false;
        }
    }

    /**
     * Processes Create Record action type.
     * Queries child AI_Intent_Action_Detail__c records for field mappings,
     * resolves Hardcoded tokens and AI Extracted values, then inserts the record.
     *
     * @param result ActionResult to update
     * @param action The AI_Intent_Action__c record with Object_Name__c
     * @param intentParams Map of AI-extracted parameters keyed by field API name
     * @param context RequestContext with relatedToId and recordId
     * @return true if record was created successfully, false otherwise
     */
    private static Boolean processCreateRecord(ActionResult result, AI_Intent_Action__c action, Map<String, Object> intentParams, RequestContext context) {
        try {
            String objectName = action.Object_Name__c;
            if (String.isBlank(objectName)) {
                return false;
            }

            // Query child AI_Intent_Action_Detail__c records
            List<AI_Intent_Action_Detail__c> details = [
                SELECT Id, Field_API_Name__c, Type__c, Value__c, Sequence__c
                FROM AI_Intent_Action_Detail__c
                WHERE AI_Intent_Action__c = :action.Id
                ORDER BY Sequence__c ASC NULLS LAST
            ];

            if (details.isEmpty()) {
                return false;
            }

            // Get schema info for the target object
            Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objectName);
            if (targetType == null) {
                result.errorMessage = 'Create Record failed: Object not found - ' + objectName;
                return false;
            }

            SObject record = targetType.newSObject();
            Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe().fields.getMap();

            // Process each detail row
            for (AI_Intent_Action_Detail__c detail : details) {
                if (String.isBlank(detail.Field_API_Name__c) || String.isBlank(detail.Type__c)) {
                    continue;
                }

                // Validate field exists on the target object
                if (!fieldMap.containsKey(detail.Field_API_Name__c.toLowerCase())) {
                    continue;
                }

                Object fieldValue = resolveDetailValue(detail, objectName, intentParams, context);
                if (fieldValue != null) {
                    record.put(detail.Field_API_Name__c, fieldValue);
                }
            }

            // Insert via FLS-safe DML
            FLSCheck.getInstance().insertDML(new List<SObject>{ record });
            return true;

        } catch (Exception ex) {
            result.errorMessage = 'Create Record failed: ' + ex.getMessage();
            return false;
        }
    }

    /**
     * Resolves the value for a single AI_Intent_Action_Detail__c row.
     * - Hardcoded: resolves tokens ({UserId}, {TODAY}, {NOW}, {relatedToId}, {recordId}) or returns literal
     * - AI Extracted: reads from intentParams using Field_API_Name__c as the key
     *
     * @param detail The AI_Intent_Action_Detail__c record
     * @param objectName Target SObject API name (for type coercion)
     * @param intentParams AI-extracted parameters
     * @param context RequestContext for token resolution
     * @return Resolved and type-cast value, or null if unresolvable
     */
    private static Object resolveDetailValue(AI_Intent_Action_Detail__c detail, String objectName, Map<String, Object> intentParams, RequestContext context) {
        if (detail.Type__c == AIConstants.ACTION_DETAIL_TYPE_HARDCODED) {
            return resolveHardcodedValue(detail, objectName, context);
        } else if (detail.Type__c == AIConstants.ACTION_DETAIL_TYPE_AI_EXTRACTED) {
            return resolveAIExtractedValue(detail, objectName, intentParams);
        }
        return null;
    }

    /**
     * Resolves a Hardcoded detail value.
     * Checks for known tokens first, then falls through to literal with type coercion.
     */
    private static Object resolveHardcodedValue(AI_Intent_Action_Detail__c detail, String objectName, RequestContext context) {
        String rawValue = detail.Value__c;
        if (String.isBlank(rawValue)) {
            return null;
        }

        // Token resolution
        if (rawValue.equalsIgnoreCase('{UserId}')) {
            return UserInfo.getUserId();
        } else if (rawValue.equalsIgnoreCase('{TODAY}')) {
            return System.today();
        } else if (rawValue.equalsIgnoreCase('{NOW}')) {
            return System.now();
        } else if (rawValue.equalsIgnoreCase('{relatedToId}')) {
            return context?.relatedToId;
        } else if (rawValue.equalsIgnoreCase('{recordId}')) {
            return context?.recordId;
        }

        // Literal value — coerce to the target field's type
        return getFieldTypeBasedValue(objectName, detail.Field_API_Name__c, rawValue);
    }

    /**
     * Resolves an AI Extracted detail value.
     * Reads from intentParams using the Field API Name as the key, then coerces type.
     */
    private static Object resolveAIExtractedValue(AI_Intent_Action_Detail__c detail, String objectName, Map<String, Object> intentParams) {
        if (intentParams == null || intentParams.isEmpty()) {
            return null;
        }

        Object rawValue = intentParams.get(detail.Field_API_Name__c);
        if (rawValue == null) {
            return null;
        }

        // If already the correct type (e.g., Boolean from JSON), return as-is for non-string values
        if (!(rawValue instanceof String)) {
            return rawValue;
        }

        // String value — coerce to target field type
        return getFieldTypeBasedValue(objectName, detail.Field_API_Name__c, String.valueOf(rawValue));
    }

    /**
     * Converts a string value to the appropriate Apex type based on the target field's schema.
     * Mirrors AIPromptActionService.getFieldTypeBasedValue() to maintain consistent type handling.
     *
     * @param objName SObject API name
     * @param fieldName Field API name
     * @param fieldValue String value to convert
     * @return Type-cast value
     */
    @TestVisible
    private static Object getFieldTypeBasedValue(String objName, String fieldName, String fieldValue) {
        try {
            Schema.SObjectType sType = Schema.getGlobalDescribe().get(objName);
            if (sType == null) {
                return fieldValue;
            }
            Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();
            Schema.SObjectField sField = fieldMap.get(fieldName.toLowerCase());
            if (sField == null) {
                return fieldValue;
            }

            String fType = String.valueOf(sField.getDescribe().getType()).toUpperCase();

            if (fType == 'INTEGER' || fType == 'DOUBLE' || fType == 'CURRENCY' || fType == 'DECIMAL' || fType == 'PERCENT') {
                String cleanValue = fieldValue;
                if (fType == 'CURRENCY') {
                    cleanValue = cleanValue.replaceAll('\\p{Sc}', '');
                } else if (fType == 'PERCENT') {
                    cleanValue = cleanValue.replaceAll('%', '');
                }
                Decimal val = Decimal.valueOf(cleanValue.trim());
                if (fType == 'INTEGER') {
                    return val.intValue();
                }
                return val;
            } else if (fType == 'BOOLEAN' || fType == 'CHECKBOX') {
                return Boolean.valueOf(fieldValue);
            } else if (fType == 'DATE') {
                return (Date) JSON.deserialize('"' + fieldValue + '"', Date.class);
            } else if (fType == 'DATETIME') {
                return (Datetime) JSON.deserialize('"' + fieldValue + '"', Datetime.class);
            } else if (fType == 'TIME') {
                return (Time) JSON.deserialize('"' + fieldValue + '"', Time.class);
            }

            return fieldValue;
        } catch (Exception ex) {
            // If type coercion fails, return the raw string — Salesforce will throw on DML if incompatible
            return fieldValue;
        }
    }
}