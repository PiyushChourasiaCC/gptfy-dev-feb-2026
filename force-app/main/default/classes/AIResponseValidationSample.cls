global class AIResponseValidationSample implements AIResponseValidationInterface {
	
    global static Boolean invokeApex(String response, AI_Prompt_Response_Validation__c responseValidation){
        if(response.containsIgnoreCase('Error') || response.containsIgnoreCase('Exception')){
            return false;
        }
        return true;
    }
    
}