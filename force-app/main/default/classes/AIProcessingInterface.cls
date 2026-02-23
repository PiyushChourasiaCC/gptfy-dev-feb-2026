/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 12-12-2023
* @last modified by  : Rishabh Goel
**/
global interface AIProcessingInterface {
	HttpResponse getProcessedResponse(AI_Connection__c aiModel, AI_Prompt__c aiPrompt, String promptCommand, String extractedData);  
}