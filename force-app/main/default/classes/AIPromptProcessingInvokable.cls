global with sharing class AIPromptProcessingInvokable {
	/**
     * Processes a list of requests and returns a list of response wrappers.
     *
     * This method takes a list of RequestWrapper objects as input and performs some
     * processing to generate a list of ResponseWrapper objects. The implementation
     * details of the processing logic may vary based on the specific requirements.
     *
     * @param requests A list of RequestWrapper objects containing input data.
     * @return A list of ResponseWrapper objects representing the processed results.
     *
     * Example usage:
     * List<RequestWrapper> inputRequests = // Populate with request data
     * List<ResponseWrapper> processedResponses = processRequest(inputRequests);
     * // Use the processed responses as needed
     */
    @InvocableMethod(label='executePrompt' description='This is a apex invocable method which is used to run GPTfy over a record using a prompt.' category='GPTfy')
    global static List<ResponseWrapper> processRequest(List<RequestWrapper> requests){
        ResponseWrapper response = new ResponseWrapper();
        if(requests != null && !requests.isEmpty()){
            RequestWrapper request = requests.get(0);
            response.status = 'Error';
            response.message = AIConstants.REQUEST_FAILED;
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
                        }catch(Exception e){}
                        if(String.isNotBlank(objName)){
                            String recId = request.recordId;
                            String query = 'SELECT Id FROM '+String.escapeSingleQuotes(objName)+' WHERE Id =:recId LIMIT 1 ';
                            List<sObject> lst = Database.query(query);
                            if(lst != null && !lst.isEmpty()){
                                response = invokeCallout(request, response, pmt.Id);
                                //System.debug('response' + response);
                                if(response != null && String.isNotBlank(response.responseBody)){
                                    ExecutePrompt__e event = new ExecutePrompt__e();
                                    event.Executed__c = true;
                                    event.EventUUID__c = request.eventUUID;
                                    EventBus.publish(event);
                                }
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
        }
        return new List<ResponseWrapper>{response};
    }
    
    global static ResponseWrapper invokeCallout(RequestWrapper request, ResponseWrapper response, String promptId){
        try{
            AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
            if(!Test.isRunningTest()){
            	if(!ChatGPTUtills.checkLicensePlanActive(System.Label.LICENSES_STARTER_PLAN)){
            		throw new ChatGPTUtills.ApplicationException(String.format(System.Label.LICENESES_PLAN_ERROR_MESSAGE,new List<String> { System.Label.LICENSES_PRO_PLAN }));
            	}
            }
            AI_Response__c resp;
             if(aiPrompt.Include_Files__c == true && AIConstants.RESPONSES_API_MODEL.contains(aiPrompt.AI_Model_File_Processing__r.Model__c)){
                resp = ChatGPTUtills.processResponsesFileRequest(promptId, request.recordId, request.customPromptCommand,new AI_Response__c());
            }else{
                resp = ChatGPTUtills.initiateGPT(request.recordId, promptId, request.customPromptCommand, null, false);
            }
            if(resp != null){
                response.responseId = resp.Id;
                response.responseBody = resp.AI_Processed_Data_PII_Added__c;
                //Jira 7221:  Issues/Feedbacks from 1.12 Testing
                response.status = resp.Status__c;
                response.message = '';
            }
        }catch(Exception e){
            System.debug(e.getMessage());
            System.debug(e.getStackTraceString());
            response.message = e.getMessage(); 
        }
        return response;
    }
    
    global class RequestWrapper {
    	@InvocableVariable(label='promptRequestId' required=true)
    	global String promptRequestId;
        @InvocableVariable(label='recordId' required=true)
    	global String recordId;
        @InvocableVariable(label='EventUUID' required=true)
    	global String eventUUID;
        @InvocableVariable(label='customPromptCommand')
    	global String customPromptCommand;
  	}
    
    global class ResponseWrapper{
        @InvocableVariable(label='responseId')
        global String responseId;
        @InvocableVariable(label='responseBody')
        global String responseBody;
        @InvocableVariable(label='status')
        global String status;
        @InvocableVariable(label='message')
        global String message;
    }
    
}