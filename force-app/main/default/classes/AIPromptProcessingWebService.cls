@RestResource(urlMapping='/v1/executePrompt/*')
global with sharing class AIPromptProcessingWebService {
    
    /**
     * Executes a request and returns a ResponseWrapper.
     * This method is designed to perform some global operation,
     * such as making an API request, and encapsulates the response
     * in a custom ResponseWrapper object.
     *
     * @return A ResponseWrapper containing the result of the request.
     *         The ResponseWrapper typically includes information such as
     *         the response status, data, and any additional details.
     */

	@HttpPost
    global static ResponseWrapper runRequest(){
        
        ResponseWrapper response = new ResponseWrapper();
        response.status = 'Error';
        response.statusCode = 400;
		response.message = AIConstants.REQUEST_FAILED;
        
        RequestWrapper request = new RequestWrapper();
        RestRequest req = RestContext.request; 
        try{
            String jsonBody = req.requestBody.toString();
            if(String.isNotBlank(jsonBody)){
                request = (RequestWrapper)JSON.deserializeStrict(jsonBody, RequestWrapper.class);
            }
        }catch(Exception e){
            response.message = AIConstants.INCORRECT_JSON;
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptProcessingWebService', 'runRequest', '');
            return response;
        }

        if(request != null){
            if(String.isBlank(request.promptRequestId)){
            	response.message = AIConstants.PMT_REQ_ID_NOT_FOUND;
            }else if(String.isBlank(request.recordId)){
                response.message = AIConstants.REC_ID_NOT_FOUND;
            }else{
                List<AI_Prompt__c> lstOfPrompts = [SELECT Id FROM AI_Prompt__c 
                                                   WHERE Prompt_Request_Id__c =:request.promptRequestId 
                                                   AND Status__c =:AIConstants.PMT_STATUS_ACTIVE
                                                   LIMIT 1];
                if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
                    AI_Prompt__c pmt = lstOfPrompts.get(0);
                    String objName;
                    try{
                        objName = Id.valueOf(request.recordId).getSObjectType().getDescribe().getName();
                    }catch(Exception e){
                        GPTfyException.log(e, 'GPTfy', '', 'AIPromptProcessingWebService', 'runRequest', '');
                    }
                    if(String.isNotBlank(objName)){
                        String recId = request.recordId;
                        String query = 'SELECT Id FROM '+String.escapeSingleQuotes(objName)+' WHERE Id =:recId LIMIT 1 ';
                        List<sObject> lst = Database.query(query);
                        if(lst != null && !lst.isEmpty()){
                            response = invokeCallout(request, response,pmt.Id);
                        }else{
                            response.message = AIConstants.REC_ID_DOES_NOT_EXISTS;
                        }
                    }else{ 
                        response.message = AIConstants.INCORRECT_REC_ID;
                    }
                }else{
                    response.message = AIConstants.NO_ACTIVE_PMT_FOUND;
                }
            }
        }else{
            response.message = AIConstants.EMPTY_REQ_BODY;
        }
        return response;
    }
    
    public static ResponseWrapper invokeCallout(RequestWrapper request, ResponseWrapper response, String promptId){
        try{
            AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
            if(!Test.isRunningTest()){
            	if(!ChatGPTUtills.checkLicensePlanActive(System.Label.LICENSES_STARTER_PLAN)){
            		throw new ChatGPTUtills.ApplicationException(String.format(System.Label.LICENESES_PLAN_ERROR_MESSAGE,new List<String> { System.Label.LICENSES_PRO_PLAN }));
            	}
            }
            AI_Response__c resp;
            if(aiPrompt.Include_Files__c == true && AIConstants.RESPONSES_API_MODEL.contains(aiPrompt.AI_Model_File_Processing__r.Model__c)){
                resp = ChatGPTUtills.processResponsesFileRequest(promptId, request.recordId,request.customPromptCommand, new AI_Response__c());
            }else{
                resp = ChatGPTUtills.initiateGPT(request.recordId, promptId, request.customPromptCommand, null, false);
            }
            if(resp != null){
                response.responseId = resp.Id;
                response.responseBody = resp.AI_Processed_Data_PII_Added__c;
                response.status = resp.Status__c;
                response.statusCode = 200;
                response.message = resp.Message__c;
            }
            
        }catch(Exception e){
            response.message = e.getMessage(); 
            response.statusCode = 500;
        }
        return response;
    }
    
    global class RequestWrapper{
        global String promptRequestId{get;set;}
        global String recordId{get;set;}
        global String customPromptCommand{get;set;}
    }
    
    global class ResponseWrapper{
        global String responseId{get;set;}
        global String responseBody{get;set;}
        global String status{get;set;}
        global Integer statusCode{get;set;}
        global String message{get;set;}
    }
    
}