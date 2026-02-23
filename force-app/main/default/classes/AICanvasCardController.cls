/**
 * @description:
 *   AICanvasCardController is a utility Apex class used for invoking AI prompt REST API callouts
 *   and processing their responses.
 * 
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 04-09-2025
 * @last modified by  : Piyush Chourasia
 **/
public with sharing class AICanvasCardController {
    /**
     * @description:
     *  
     * 
     * @param requestJSON  - JSON string representing the AI prompt request wrapper
     * @param promptId     - The ID of the AI prompt to be processed
     * @return ResponseWrapper object containing the callout result or error message
     */
    @AuraEnabled
    public static ResponseWrapper getPromptResponse(String requestJSON, String promptId, String recordId,String parentAIResponseId, Boolean notInitialLoad, String objectApiName, Boolean inheritPromptSecurity, String promptElementDetails) {
        try{
            AICanvasController.PromptElement elementWrap = (AICanvasController.PromptElement)JSON.deserialize(promptElementDetails, AICanvasController.PromptElement.class);
            if(inheritPromptSecurity == false){
                String message = AICanvasService.validatePrompt(promptId,recordId, objectApiName);
                if(message != 'Success'){
                    return new ResponseWrapper(message);
                }
            }else{
                String message = AICanvasService.validatePrompt(promptId, objectApiName);
                if(message != 'Success'){
                    return new ResponseWrapper(message);
                }
            }
            if(!notInitialLoad){
                AI_Response__c response = AICanvasService.fetchSecurityAuditByPromptId(promptId, parentAIResponseId,recordId);
                if(response != null){
                    return new ResponseWrapper(response);
                }else{
                    return invokeCallout(requestJSON,promptId,parentAIResponseId,recordId,elementWrap);
                }
            }else{
                return invokeCallout(requestJSON,promptId,parentAIResponseId,recordId,elementWrap);
            }
        }catch(Exception ex){
            // Return a controlled error for front-end handling
            throw new AuraHandledException(ex.getMessage());
        }
    }
    /**
     * @description:
     *  Makes a REST API callout using the provided request JSON and prompt ID.
     *  Captures any exceptions and returns a wrapped response with the error message if applicable.
     * 
     * @param requestJSON  - JSON string representing the AI prompt request wrapper
     * @param promptId     - The ID of the AI prompt to be processed
     * @return ResponseWrapper object containing the callout result or error message
     */
    private static ResponseWrapper invokeCallout(String requestJSON, String promptId, String parentAIResponseId, String recordId,AICanvasController.PromptElement elementWrap ) {
        //Calling service to handle all the business logics
        return AICanvasService.invokeCallout(requestJSON,promptId,parentAIResponseId,recordId,elementWrap);
    }

    /**
     * @description:
     *  Makes a REST API callout and optionally updates a parent Security Audit record
     *  with the returned AI response details if successful.
     * 
     * @param requestJSON         - JSON string representing the AI prompt request wrapper
     * @param promptId            - The ID of the AI prompt to be processed
     * @param parentAuditRecordId       - The ID of the parent Security Audit record 
     * @param templateComponentId - The ID of the canvas template component (optional linkage)
     * @return ResponseWrapper object containing the callout result or error message
     */
    @AuraEnabled
    public static ResponseWrapper getSummaryPromptResponse(
            String requestJSON, 
            String promptId, 
            String recordId,
            String parentAIResponseId, 
            Boolean notInitialLoad, 
            String objectApiName, 
            Boolean inheritPromptSecurity,
            String auditRecordId) {
        try{
            if(inheritPromptSecurity == false){
                String message = AICanvasService.validateSummaryPrompt(promptId,objectApiName,recordId);
                if(message != 'Success'){
                    return new ResponseWrapper(message);
                }
            }else{
                String message = AICanvasService.validateSummaryPrompt(promptId);
                if(message != 'Success'){
                    return new ResponseWrapper(message);
                }
            }
            if(!notInitialLoad){
                AI_Response__c response = AICanvasService.fetchSecurityAuditByPromptId(promptId, parentAIResponseId,auditRecordId);
                if(response != null){
                    return new ResponseWrapper(response);
                }else{
                    return invokeCallout(requestJSON,promptId,parentAIResponseId,auditRecordId, null);
                }
            }else{
                return invokeCallout(requestJSON,promptId,parentAIResponseId,auditRecordId, null);
            }
        }catch(Exception ex){
            System.debug(ex.getMessage());
            // Return a controlled error for front-end handling
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description:
     *  Inner class to standardize the response returned to the client layer
     */
    public class ResponseWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String name;
        @AuraEnabled public String responseBody;
        @AuraEnabled public String feedbackType;
        @AuraEnabled public String message;
        @AuraEnabled public String howItWorks;
        @AuraEnabled public Double timeSaved;

        /**
         * @description:
         *  Constructor to convert and populate fields from the internal response structure.
         */
        public ResponseWrapper(AI_Response__c aIResponse) {
            this.Id = aIResponse.Id;
            this.responseBody = aIResponse.AI_Processed_Data_PII_Added__c;
            this.name = aIResponse.Name;
            this.feedbackType = (aIResponse.Feedbacks__r != null && aIResponse.Feedbacks__r.size() > 0) ? aIResponse.Feedbacks__r[0].Type__c : '';
            this.message = aIResponse.Message__c;
            this.howItWorks = aIResponse.How_it_works__c;
            this.timeSaved = aIResponse.Time_Saved_Seconds__c;
        }
        /**
         * @description:
         *  Constructor to give the error message if any
         * 
         */
        public ResponseWrapper(String message) {
            this.message = message;
        }
    }

}