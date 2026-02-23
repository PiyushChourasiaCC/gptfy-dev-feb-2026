global with sharing class AIPromptResponseProcessingInvokable {
	/**
     * Processes a list of requests and returns a list of response wrappers.
     *
     * This method takes a list of RequestWrapper objects as input, performs some processing
     * on each request, and generates a corresponding ResponseWrapper for each request. The
     * ResponseWrapper objects are then collected into a List and returned.
     *
     * @param requests A list of RequestWrapper objects containing the requests to be processed.
     * @return A list of ResponseWrapper objects containing the processed responses.
     * @throws SomeException If there is an error during the processing, an appropriate exception
     *                       is thrown to indicate the failure.
     */
    @InvocableMethod(label='processResponse' description='This is a apex invocable method which is used to process the JSON response retured by GPTfy executePrompt action.' category='GPTfy')
    global static List<ResponseWrapper> processRequest(List<RequestWrapper> requests){
        ResponseWrapper response = new ResponseWrapper();
        
        List<AI_Response__c> lstOfResponse = [SELECT Id, AI_Processed_Data_PII_Added__c 
                                              FROM AI_Response__c 
                                              WHERE Id =:requests.get(0).responseId];
        if(lstOfResponse != null && !lstOfResponse.isEmpty()){
            if(String.isNotBlank(lstOfResponse.get(0).AI_Processed_Data_PII_Added__c)){
                String str = lstOfResponse.get(0).AI_Processed_Data_PII_Added__c;
                try{
                    Map<String, Object> m = (Map<String, Object>)JSON.deserializeUntyped(str);
                    String key = requests.get(0).key;
                    String value = '';
                    if(m != null && m.containsKey(key) && m.get(key) != null){
                        value = String.valueOf(m.get(key));
                    }
                    response.value = value;
                }catch(Exception e){
                    response.message = 'Malformed JSON! Please check the response.';
                }
            }else{
                response.message = 'Response does not have any data to process.';
            }
        }else{
            response.message = 'Response with Id not found.';
        }
        
        return new List<ResponseWrapper>{response}; 
    }
    
    global class RequestWrapper {
    	@InvocableVariable(label='responseId' required=true description='Id of the AI Response record.')
    	global String responseId;
        @InvocableVariable(label='key' required=true description='Key of the response JSON.')
    	global String key;
        @InvocableVariable(label='keys' required=false description='Do not use in Flows')
    	global List<String> keys;
  	}
    
    global class ResponseWrapper{
        @InvocableVariable(label='value')
        global String value;
        @InvocableVariable(label='error message')
        global String message;
        @InvocableVariable(label='Do not use in Flows')
        global List<ResponseKey> response;
    }
    
    global class ResponseKey{
        @InvocableVariable(label='Do not use in Flows')
        global String key;
        @InvocableVariable(label='Do not use in Flows')
        global String value;
    }
    
}