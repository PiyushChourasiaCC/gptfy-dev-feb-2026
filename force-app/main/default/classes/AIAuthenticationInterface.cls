/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 11-15-2023
* @last modified by  : Rishabh Goel
**/
global interface AIAuthenticationInterface {	
    HttpRequest getAuthenticatedRequest(AI_Connection__c aiModel);  
}