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
        systemInstructions += '\n\n' + System.Label.AI_Agentic_Mandatory_Response_Format + '\n\n';
        
        if (agentIntents != null && !agentIntents.isEmpty()) {
            System.debug('AgentIntents: Adding Agent Intents format to instructions');
            systemInstructions += System.Label.AI_Agentic_Intent_Detection_Header + '\n'
                + JSON.serialize(agentIntents) + '\nEND_AVAILABLE_INTENTS_JSON\n\n'
                + System.Label.AI_Agentic_Intent_Matching + '\n\n'
                + System.Label.AI_Agentic_Update_Field_Instructions + '\n\n'
                + System.Label.AI_Agentic_Create_Record_Instructions + '\n\n'
                + System.Label.AI_Agentic_Field_Mapping_Param_Rules + '\n\n'
                + System.Label.AI_Agentic_Examples_Basic + '\n\n'
                + System.Label.AI_Agentic_Example_Update_Context + '\n\n'
                + System.Label.AI_Agentic_Example_Update_And_Create + '\n\n';
            System.debug('AgentIntents: Agent Intents format ADDED to instructions');
        } else {
            System.debug('AgentIntents: No intents available, but mandatory response format still enforced');
            systemInstructions += System.Label.AI_Agentic_No_Intents_Example + '\n\n';
        }
        
        // Add critical reminders that apply to ALL responses
        systemInstructions += System.Label.AI_Agentic_Critical_Rules;
        
        System.debug('@System Prompt' + systemInstructions);
        return systemInstructions;
    }
}