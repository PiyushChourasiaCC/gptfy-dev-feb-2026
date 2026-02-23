/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-03-2025
* @last modified by  : Rishabh Goel
**/
public with sharing class AIResponseValidationController {
	
    @AuraEnabled
    public static DataWrapper getResponseValidations(String promptId){
        DataWrapper wrap = new DataWrapper();
        
        List<ValidationWrapper> lstOfValidations = new List<ValidationWrapper>();
        for(AI_Prompt_Response_Validation__c resp : [SELECT Id, Sequence__c, Action__c, Value__c 
                                                     FROM AI_Prompt_Response_Validation__c
                                                     WHERE AI_Prompt__c =:promptId]){
            ValidationWrapper v_wrap = new ValidationWrapper();
            v_wrap.id = resp.Id;
            v_wrap.sequence = resp.Sequence__c != null ? Integer.valueOf(resp.Sequence__c) : null;
            v_wrap.action = resp.Action__c;
            v_wrap.value = resp.Value__c;                                             
            lstOfValidations.add(v_wrap);                                             
        }
        
        AI_Prompt__c pmt = [SELECT Id, Response_Validation_Condition__c, Response_Validation_Message__c, Status__c 
                            FROM AI_Prompt__c 
                            WHERE Id =:promptId LIMIT 1];
        //Jira 7221:  Issues/Feedbacks from 1.12 Testing
        wrap.isPromptActive = (pmt.Status__c == AIConstants.PMT_STATUS_ACTIVE)? true : false;
        wrap.responseValidationCondition = String.isNotBlank(pmt.Response_Validation_Condition__c) ? pmt.Response_Validation_Condition__c : '';
        wrap.responseValidationMessage = String.isNotBlank(pmt.Response_Validation_Message__c) ? pmt.Response_Validation_Message__c : '';
        wrap.responseValidations = lstOfValidations;
        wrap.actionOptions = AIPromptController.getPickListValues(AIConstants.NAMESPACE+'AI_Prompt_Response_Validation__c', AIConstants.NAMESPACE+'Action__c');
        return wrap;
    }
    
    @AuraEnabled
    public static void deleteResponseValidation(String responseValidationId){
        if(String.isNotBlank(responseValidationId)){
            try{
                List<AI_Prompt_Response_Validation__c> lstToDelete = [SELECT Id, Sequence__c, Action__c, Value__c 
                                                                     FROM AI_Prompt_Response_Validation__c
                                                                     WHERE Id =:responseValidationId
                                                                     LIMIT 1];
                FLSCheck.getInstance().deleteDML(lstToDelete);
            }catch(Exception e){
                throw new AuraHandledException(e.getMessage());
            }
        }
    }
    
    @AuraEnabled
    public static void updateResponseValidationCondition(String condition, String message, String recordId){
        condition = String.isNotBlank(condition) ? condition : '';
        if(String.isNotBlank(recordId)){
            AI_Prompt__c pmt = new AI_Prompt__c(
                Id = recordId, 
                Response_Validation_Condition__c = condition,
                Response_Validation_Message__c = message
            );
            FLSCheck.getInstance().updateDML(new List<AI_Prompt__c>{pmt});
        }
    }
    
    @AuraEnabled
    public static void upsertResponseValidation(Map<String, String> data){
        try{
            String promptId = data.get('promptId');
            String responseValidationId = data.get('responseValidationId');
            String validationAction = data.get('validationAction');
            String validationValue = data.get('validationValue');
            String sequence = data.get('sequence');
    
            if(String.isNotBlank(promptId)){
                AI_Prompt_Response_Validation__c resp = new AI_Prompt_Response_Validation__c();
                resp.Action__c = validationAction;
                resp.Sequence__c = String.isNotBlank(sequence) ? Integer.valueOf(sequence) : 1;
                resp.Value__c = validationValue;
                if(String.isNotBlank(responseValidationId)){
                    resp.Id = responseValidationId;
                    FLSCheck.getInstance().updateDML(new List<AI_Prompt_Response_Validation__c>{resp});
                }else{
                    resp.AI_Prompt__c = promptId;
                    FLSCheck.getInstance().insertDML(new List<AI_Prompt_Response_Validation__c>{resp});
                }
            }
        }catch(Exception e){
        	throw new AuraHandledException(e.getMessage());
        }
    }
    
    public class DataWrapper{
        @AuraEnabled public String responseValidationCondition{get;set;}
        @AuraEnabled public String responseValidationMessage{get;set;}
        @AuraEnabled public List<ValidationWrapper> responseValidations{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> actionOptions{get;set;}
        @AuraEnabled public Boolean isPromptActive{get;set;}
    }
    
    public class ValidationWrapper{
        @AuraEnabled public String id{get;set;}
        @AuraEnabled public Integer sequence{get;set;}
        @AuraEnabled public String action{get;set;}
        @AuraEnabled public String value{get;set;}
    }
    
}