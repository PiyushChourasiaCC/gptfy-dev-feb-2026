/**
 * @description:
 *   AIAgenticWebService is a RESTful web service responsible for handling agentic requests.
 *   It processes incoming JSON payloads, validates them, and invokes appropriate utility methods.
 * 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 29-07-2025
 * @last modified by  : Rishabh Goel
 **/
@RestResource(urlMapping='/v1/agentic/*')
global with sharing class AIAgenticWebService {
    
    /**
     * @description:
     *   Handles HTTP POST requests to process agentic operations.
     *
     * @return ResponseWrapper containing the status and message of the operation.
     */
    @HttpPost
    global static ResponseWrapper runRequest(){
    	ResponseWrapper response = new ResponseWrapper();
        response.status = 'Error';
        response.statusCode = 400;
		response.message = AIConstants.REQUEST_FAILED;
        
        RequestWrapper request = new RequestWrapper();
        RestRequest req = RestContext.request;
        Map<String,String> headers = req.headers;
        
        try{
            String jsonBody = req.requestBody.toString();
            if(String.isNotBlank(jsonBody)){
                request = (RequestWrapper)JSON.deserializeStrict(jsonBody, RequestWrapper.class);
                if(!headers.isEmpty() && headers.containsKey('X-Microsoft-AI-ConversationId')){
            		request.userContextId = headers.get('X-Microsoft-AI-ConversationId');
        		}
            }
        }catch(Exception e){
            response.message = AIConstants.INCORRECT_JSON;
            GPTfyException.log(e, 'GPTfy', '', 'AIAgenticWebService', 'runRequest', '');
            return response;
        }

        if(request != null){
            response = AIAgenticUtility.invokeAgent(request);
        }
        
        return response;
    }
    /**
     * @description:
     *   Wrapper class for incoming agentic request payloads.
     *
     * @property agentName - Developer name for agentic configuration.
     * @property agenticConfigId - ID of the agentic configuration.
     * @property userIdentificationField - Field used for user identification.
     * @property userIdentificationValue - Value used for user identification.
     * @property promptRequestId - ID of the prompt request.
     * @property recordId - ID of the record being processed.
     * @property userMessage - Message from the user.
     * @property threadId - ID of the thread for the operation.
     */
    global class RequestWrapper{
        global String agentName{get;set;}
        global String agenticConfigId{get;set;}
        global String userIdentificationField{get;set;}
        global String userIdentificationValue{get;set;}
        global String promptRequestId{get;set;}
        global String recordId{get;set;}
        global String relatedToId{get;set;}
        global String userMessage{get;set;}
        global String userContextId{get;set;}
        global List<Object> promptFunctions{get;set;}
        global String namedCredentials{get;set;}
        global String model{get;set;}
        global String type{get;set;}
        global AI_Agent__c config{get;set;}
        global String previousResponseId{get;set;}
        global List<Object> conversation{get;set;}
        global String developerInstructions{get;set;}
        global Set<String> setOfVectorStoreIds{get;set;}
        global String locale{get;set;}
        global String language{get;set;}
        global String format{get;set;}
        global String userAgent{get;set;}
        global Map<String, Object> additionalInformation{get;set;}
        global Set<String> imageFileIds{get;set;}
        global List<String> vectorStoreIds{get;set;}
        global Map<String, Object> agentIntents{get;set;}
    }
    
    /**
     * @description:
     *   Wrapper class for outgoing agentic response payloads.
     *
     * @property threadId - ID of the thread for the operation.
     * @property responseId - ID of the response.
     * @property responseBody - Body of the response.
     * @property status - Status of the operation.
     * @property statusCode - HTTP status code of the operation.
     * @property message - Message describing the operation result.
     */
    global class ResponseWrapper{
        global String userContextId{get;set;}
        global String responseId{get;set;}
        global String responseBody{get;set;}
        global String status{get;set;}
        global Integer statusCode{get;set;}
        global String message{get;set;}
        global AI_Agent__c config{get;set;}
        global List<String> intents{get;set;}
        global String detectedLanguage{get;set;}
    }
}