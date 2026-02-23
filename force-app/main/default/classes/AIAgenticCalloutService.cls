/**
 * @description:
 *   AIAgenticCalloutService handles communication between the agenting framework and external AI services.
 *   It provides utility methods for constructing HTTP callouts, serializing request payloads,
 *   invoking external endpoints, and managing response handling and error propagation.
 *   The service ensures robust integration for AI-powered conversational flows.
 *
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 30-07-2025
 * @last modified by  : Rishabh Goel
 **/
public class AIAgenticCalloutService {

    /**
     * Calls an external AI service to fetch a qualified prompt, given a request object.
     *
     * @param request      RequestWrapper containing configuration, conversation input, and prompt parameters.
     * @return             ResponseWrapper with the raw response body or an error message.
     *
     * The method builds and serializes the HTTP request body based on input,
     * sets the endpoint using the Named Credential and model in configuration,
     * sends a synchronous HTTP POST request, and handles the response.
     * Handles exceptions gracefully by returning the exception message in the wrapper.
     */
    public static AIAgenticWebService.ResponseWrapper fetchQualifiedPrompt(AIAgenticWebService.RequestWrapper request) {
        AIAgenticWebService.ResponseWrapper respWrap = new AIAgenticWebService.ResponseWrapper();
        try {
            HttpRequest httpRequestObj = new HttpRequest();
            String body = '';
            // Only proceed if the model is supported for API callouts
            if(AIConstants.RESPONSES_API_MODEL.contains(request.config.AI_Model__r.Model__c)){
                httpRequestObj.setEndpoint('callout:' + request.config.AI_Model__r.Named_Credential__c + '/v1/responses');
                Map<String, Object> requestBody;

                // Build complete instructions with Agent Intents (V2-7338)
                String systemInstructions = buildSystemInstructions(request.config.System_Prompt__c, request.agentIntents);

                // Include prompt functions if present, otherwise build the minimal required payload
                if(request.promptFunctions != null && request.promptFunctions.size() > 0){
                    requestBody = new Map<String, Object>{
                        'model' => request.config.AI_Model__r.Model__c, 
                        'input' => request.conversation,
                        'tools' => request.promptFunctions,
                        'instructions' => systemInstructions,
                        'previous_response_id' => request.previousResponseId,
                        'tool_choice' => 'auto'
                    };
                } else {
                    requestBody = new Map<String, Object>{
                        'model' => request.config.AI_Model__r.Model__c, 
                        'input' => request.conversation,
                        'instructions' => systemInstructions,
                        'previous_response_id' => request.previousResponseId
                    };
                }
                
                // Add max_output_tokens if available
                if(request.config.AI_Model__r.Max_Tokens__c != null){
                    requestBody.put('max_output_tokens', Integer.valueOf(request.config.AI_Model__r.Max_Tokens__c));
                }
                
                // Add reasoning_effort and text (verbosity) for GPT-5 and higher models
                if(isGpt5OrHigher(request.config.AI_Model__r.Model__c)){
                    if(String.isNotBlank(request.config.AI_Model__r.Additional_Parameters__c)){
                        Map<String, Object> additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(request.config.AI_Model__r.Additional_Parameters__c);
                        
                        // Add reasoning_effort if present in Additional_Parameters__c
                        if(additionalParamMap != null && additionalParamMap.containsKey('reasoning')){
                            requestBody.put('reasoning', new Map<String, Object>{'effort' => String.valueOf(additionalParamMap.get('reasoning'))});
                        }else{
                            requestBody.put('reasoning', new Map<String, Object>{'effort' => 'low'});
                        }
                        
                        // Add text (verbosity) if present in Additional_Parameters__c
                        if(additionalParamMap != null && additionalParamMap.containsKey('verbosity')){
                            requestBody.put('text', new Map<String, Object>{'verbosity' => String.valueOf(additionalParamMap.get('verbosity'))});
                        }else{
                            requestBody.put('text', new Map<String, Object>{'verbosity' => 'low'});
                        }
                    }else{
                        requestBody.put('reasoning', new Map<String, Object>{'effort' => 'low'});
                        requestBody.put('text', new Map<String, Object>{'verbosity' => 'low'});
                    }
                }else{
                    // For GPT-4 and below, use temperature and top_p
                    if(request.config.AI_Model__r.Temperature__c != null){
                        requestBody.put('temperature', request.config.AI_Model__r.Temperature__c);
                    }
                    if(request.config.AI_Model__r.Top_p__c != null){
                        requestBody.put('top_p', request.config.AI_Model__r.Top_p__c);
                    }
                }
                
                // Serialize payload to JSON
                body = JSON.serialize(requestBody);
            }
            
            // Execute external callout and check for success
            HttpResponse response = responseGenerator(httpRequestObj, body);
            System.debug(response.getBody());
            if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                respWrap.responseBody = response.getBody();
            } else {
                // Set error response body as a message for debugging
                respWrap.message = response.getBody();
            }
        } catch (Exception ex) {
            // Catch and return any errors encountered during callout
            respWrap.message = ex.getMessage();
        }
        return respWrap;
    }

    /**
     * Interacts with the AI assistant service, sending user messages and receiving assistant replies.
     *
     * @param request    RequestWrapper holding agent config and conversation context.
     * @param messages   List of user and assistant messages to be sent for context.
     * @return           Map<String, String> containing assistant 'response' and underlying 'threadId',
     *                   or error details if the callout fails.
     *
     * This method constructs the request payload, invokes the AI response endpoint,
     * parses the response body, and extracts a clean reply and thread ID,
     * assisting with stateful multi-turn conversations.
     */
    public static Map<String,String> getAssistantReply(AIAgenticWebService.RequestWrapper request, List<Object> messages) {
        HttpRequest httpRequestObj = new HttpRequest();
        String body = '';

        // Compose request and endpoint only for supported models
        if(AIConstants.RESPONSES_API_MODEL.contains(request.config.AI_Model__r.Model__c)){
            httpRequestObj.setEndpoint('callout:' + request.config.AI_Model__r.Named_Credential__c + '/v1/responses');
            
            // Build complete instructions with Agent Intents (V2-7338)
            String systemInstructions = buildSystemInstructions(request.config.System_Prompt__c, request.agentIntents);
            
            Map<String, Object> payload = new Map<String, Object>{
                'model' => request.config.AI_Model__r.Model__c,
                'input' => messages,
                'instructions' => systemInstructions,
                'previous_response_id' => request.previousResponseId
            };
            
            // Add max_output_tokens if available
            if(request.config.AI_Model__r.Max_Tokens__c != null){
                payload.put('max_output_tokens', Integer.valueOf(request.config.AI_Model__r.Max_Tokens__c));
            }
            
            // Add reasoning_effort and text (verbosity) for GPT-5 and higher models
            if(isGpt5OrHigher(request.config.AI_Model__r.Model__c)){
                if(String.isNotBlank(request.config.AI_Model__r.Additional_Parameters__c)){
                    Map<String, Object> additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(request.config.AI_Model__r.Additional_Parameters__c);
                    
                    // Add reasoning_effort if present in Additional_Parameters__c
                    if(additionalParamMap != null && additionalParamMap.containsKey('reasoning')){
                        payload.put('reasoning', new Map<String, Object>{'effort' => String.valueOf(additionalParamMap.get('reasoning'))});
                    }else{
                        payload.put('reasoning', new Map<String, Object>{'effort' => 'low'});
                    }
                    
                    // Add text (verbosity) if present in Additional_Parameters__c
                    if(additionalParamMap != null && additionalParamMap.containsKey('verbosity')){
                        payload.put('text', new Map<String, Object>{'verbosity' => String.valueOf(additionalParamMap.get('verbosity'))});
                    }else{
                        payload.put('text', new Map<String, Object>{'verbosity' => 'low'});
                    }
                }else{
                    payload.put('reasoning', new Map<String, Object>{'effort' => 'low'});
                    payload.put('text', new Map<String, Object>{'verbosity' => 'low'});
                }
            }else{
                // For GPT-4 and below, use temperature and top_p
                if(request.config.AI_Model__r.Temperature__c != null){
                    payload.put('temperature', request.config.AI_Model__r.Temperature__c);
                }
                if(request.config.AI_Model__r.Top_p__c != null){
                    payload.put('top_p', request.config.AI_Model__r.Top_p__c);
                }
            }
            
            body = JSON.serialize(payload);
        }
        
        HttpResponse response = responseGenerator(httpRequestObj, body);
        System.debug(response.getBody());
        // Handle and transform successful or failed responses
        if(response.getStatusCode() == 200 || response.getStatusCode() == 201){
            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            return new Map<String,String> {
                'response' => ChatGPTUtills.parseGPTfyResponse(response.getBody()), // Clean AI assistant text
                'threadId' => String.valueOf(dataMap.get('id')) // Reference for multi-turn threading
            };
        } else {
            // Return a generic error mapping if callout fails
            return new Map<String,String>{'error' => 'The callout failed to process'};
        }
    }

    /**
     * Generates and executes a POST HttpRequest for a given body and returns the response.
     *
     * @param httpRequestObj   The base HttpRequest with endpoint and headers set.
     * @param body             Serialized JSON string to send as the request body.
     * @return                 HttpResponse object as returned by the HTTP callout.
     *
     * Sets method, timeout, headers, and attaches the body before sending the callout.
     * Intended for internal use to standardize outgoing call behavior.
     */
    public static HttpResponse responseGenerator(HttpRequest httpRequestObj, String body){
        httpRequestObj.setMethod('POST');
        httpRequestObj.setTimeout(120000); // 120 seconds
        httpRequestObj.setHeader('Content-Type', 'application/json');
        httpRequestObj.setBody(body);
        
        Http http = new Http();
        HttpResponse response = http.send(httpRequestObj);
        return response;
    }

    /**
     * Checks if the model is GPT-5 or higher version.
     * Supports versions like: gpt-5, gpt-5.1, gpt-6, etc.
     * 
     * @param modelName The name of the AI model
     * @return Boolean True if model is GPT-5 or higher, false otherwise
     */
    private static Boolean isGpt5OrHigher(String modelName){
        if(String.isBlank(modelName)){
            return false;
        }
        
        // Convert to lowercase for case-insensitive comparison
        String model = modelName.toLowerCase().trim();
        
        // Check if it starts with 'gpt-' followed by a number
        if(model.startsWith('gpt-')){
            try{
                // Extract the major version number (e.g., '5' from 'gpt-5.1')
                String versionPart = model.substring(4); // Remove 'gpt-' prefix
                
                // Handle versions like 'gpt-5' or 'gpt-5.1'
                Integer majorVersion;
                if(versionPart.contains('.')){
                    majorVersion = Integer.valueOf(versionPart.split('\\.')[0]);
                }else{
                    majorVersion = Integer.valueOf(versionPart);
                }
                
                // Return true if version is 5 or higher
                return majorVersion >= 5;
            }catch(Exception e){
                // If parsing fails, return false
                return false;
            }
        }
        
        return false;
    }

    /**
     * Builds the complete system instructions including Agent Intents format (V2-7338).
     * 
     * @param baseInstructions The base system prompt from AI Agent configuration
     * @param agentIntents Map of agent intents keyed by intent name to include in instructions
     * @return String Complete system instructions with Agent Intents format if applicable
     */
        private static String buildSystemInstructions(String baseInstructions, Map<String, Object> agentIntents) {
        System.debug('@AgentIntentInPrompt' + agentIntents);
          
        String systemInstructions = baseInstructions != null ? baseInstructions : '';

        // ALWAYS add mandatory response format - this applies regardless of whether intents exist
        // IMPORTANT: Do NOT include markdown code fences in these instructions; the model may echo them.
        systemInstructions += '\n\n## MANDATORY RESPONSE FORMAT\n\n' +
            'You MUST ALWAYS respond with ONLY a valid JSON object. No text, markdown, or code fences before or after it.\n\n' +
            '{"message": "your response", "intents": [], "language": "en", "additionalParameters": {}}\n\n' +
            'Fields:\n' +
            '- **message**: Your helpful response (ALL conversational text goes here).\n' +
            '- **intents**: Array of matched intent NAME strings ([] if none). Names must exactly match top-level intent keys below.\n' +
            '- **language**: ISO 639-1 code.\n' +
            '- **additionalParameters**: Object keyed by intent name. {} if no intents triggered.\n\n';
        
        if (agentIntents != null && !agentIntents.isEmpty()) {
            System.debug('AgentIntents: Adding Agent Intents format to instructions');
            systemInstructions += '## Agent Intent Detection System\n\n' +
                '### Available Intents\n' +
                'BEGIN_AVAILABLE_INTENTS_JSON\n' + JSON.serialize(agentIntents) + '\nEND_AVAILABLE_INTENTS_JSON\n\n' +
                '### How It Works\n\n' +
                '**Matching:** Each intent has a "description" field. An intent matches when the user\'s message semantically aligns with that description. ' +
                'Intents may also have an "actions" array -- each action has a "type" (Update Field or Create Record), an "object", a "description", and field information.\n\n' +
                '**Update Field actions** have a single "field" key and an "object" key (e.g., Case, Account, Contact). You must extract the field value AND determine the target recordId:\n' +
                '- The action\'s "object" tells you WHICH type of record to look for. Search the ENTIRE conversation thread for a recordId or record number matching that object type.\n' +
                '- CRITICAL: If a matching recordId appeared ANYWHERE earlier in this thread (in your own previous responses OR in user messages), and the user now says "this record", "this case", "this account", "it", or similar, you MUST reuse that recordId and TRIGGER the intent. Do NOT ask again for a recordId that already exists in the thread.\n' +
                '- Only ask the user for a recordId if NO matching record has been mentioned ANYWHERE in the entire conversation thread.\n' +
                '- Return: additionalParameters.INTENT_NAME = { "recordId": "id", "FieldApiName": "value" }\n\n' +
                '**Create Record actions** have a "fields" array. Each field has a "field" (API name) and "description" (what to extract).\n' +
                '- ALWAYS trigger immediately when the intent description matches -- do NOT ask follow-up questions.\n' +
                '- Extract a value for EVERY field in the array using each field\'s "description" as guidance.\n' +
                '- No recordId is needed -- a new record will be created. Do NOT include recordId.\n' +
                '- NEVER return an empty {} for a Create Record intent. You MUST populate all fields.\n' +
                '- Return: additionalParameters.INTENT_NAME = { "Field1": "value1", "Field2": "value2" } (include ALL fields)\n\n' +
                '**Field value mapping:** Map user language intelligently (urgent/critical/asap -> High, normal/standard -> Medium, not urgent/whenever -> Low). ' +
                'If a field description specifies valid values, only use those values. Keys MUST be exact Salesforce Field API Names.\n\n' +
                '### additionalParameters Rules\n' +
                '- Intent WITHOUT actions -> additionalParameters.INTENT_NAME = {}\n' +
                '- Intent with Update Field action -> { "recordId": "id_if_known", "FieldApiName": "extracted_value" }\n' +
                '- Intent with Create Record action -> { "Field1": "value1", "Field2": "value2" } (ALL fields, NEVER empty)\n\n' +
                '### Examples\n\n' +
                '**No intent match (general conversation):**\n' +
                '{"message": "I can help with that. What would you like to know?", "intents": [], "language": "en", "additionalParameters": {}}\n\n' +
                '**Intent without actions (e.g., EMERGENCY):**\n' +
                '{"message": "I am flagging this as an emergency.", "intents": ["EMERGENCY"], "language": "en", "additionalParameters": {"EMERGENCY": {}}}\n\n' +
                '**Update Field (recordId from thread context -- "this record" reference):**\n' +
                'Previous assistant response: Here are the details: Record ID: 500J700000LjY85IAF\n' +
                'User: I want to update this record\'s priority to High\n' +
                '{"message": "I have updated the priority to High.", "intents": ["UPDATE_PRIORITY"], "language": "en", "additionalParameters": {"UPDATE_PRIORITY": {"recordId": "500J700000LjY85IAF", "Priority": "High"}}}\n\n' +
                '**Update Field (no record mentioned ANYWHERE in thread -- DO NOT trigger):**\n' +
                'This is the very first message in a brand new conversation with no prior context.\n' +
                'User: Update the priority to high\n' +
                '{"message": "Could you please provide the record ID you would like me to update?", "intents": [], "language": "en", "additionalParameters": {}}\n\n' +
                '**Create Record (trigger immediately, populate ALL fields):**\n' +
                'User: Create a case for my broken laptop, it is urgent\n' +
                '{"message": "I have created a support case for your broken laptop.", "intents": ["CREATE_CASE"], "language": "en", "additionalParameters": {"CREATE_CASE": {"Subject": "Broken laptop", "Priority": "High", "Description": "User reports a broken laptop and requests urgent assistance."}}}\n\n';
            System.debug('AgentIntents: Agent Intents format ADDED to instructions');
        } else {
            System.debug('AgentIntents: No intents available, but mandatory response format still enforced');
            systemInstructions += '### Example Response\n' +
                '{"message": "Hello! How can I assist you today?", "intents": [], "language": "en", "additionalParameters": {}}\n\n';
        }
        
        // Add critical reminders that apply to ALL responses
        systemInstructions += '### CRITICAL RULES\n' +
            '1. Return ONLY valid JSON -- no text, markdown, or code fences outside the JSON object.\n' +
            '2. ALL four fields (message, intents, language, additionalParameters) are required in every response.\n' +
            '3. For Create Record intents: ALWAYS populate ALL field values. NEVER return an empty {} -- extract values from the conversation.\n' +
            '4. For Update Field intents: if a recordId exists ANYWHERE in the conversation thread (in user messages OR your own previous responses), reuse it. Only ask for a recordId when no record has ever been mentioned in the entire thread.\n' +
            '5. Map user expressions to valid field values (urgent -> High, medium -> Medium, not urgent -> Low).\n' +
            '6. If you cannot produce valid JSON, return: {"message": "I encountered an error processing your request.", "intents": [], "language": "en", "additionalParameters": {}}';
        
        System.debug('@System Prompt' + systemInstructions);
        return systemInstructions;
    }
}