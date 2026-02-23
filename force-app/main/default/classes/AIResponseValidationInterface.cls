/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-03-2025
* @last modified by  : Rishabh Goel
**/
global interface AIResponseValidationInterface {
	Boolean invokeApex(String response, AI_Prompt_Response_Validation__c responseValidation);  
}