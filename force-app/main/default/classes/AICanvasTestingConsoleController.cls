/**
 * @description:
 *   AICanvasTestingConsoleController is a controller class that provides functionality
 *   for the AI Canvas Testing Console. It handles the retrieval of AI Canvas templates
 *   based on user profile and visibility conditions for testing purposes.
 * 
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 05-14-2025
 * @last modified by  : Piyush Chourasia
 **/
public with sharing class AICanvasTestingConsoleController {
    
    /**
     * @description:
     *   Retrieves an AI Canvas Template based on the provided record ID and validates
     *   if the current user's profile has access to it.
     *
     * @param recordId - ID of the AI Canvas Template record to retrieve
     * @return CanvasTemplate wrapper containing template details or error message
     */
    @AuraEnabled(cacheable=true)
    public static CanvasTemplate getCanvasTemplate(String recordId){
        try {
            String profileName = AICanvasService.getCurrentUserProfileName();
            AI_Canvas_Template__c winnerTemplate = AICanvasService.fetchCanvasTemplate(recordId);
            if(winnerTemplate != null && !String.isBlank(winnerTemplate.Profiles__c) && winnerTemplate.Profiles__c.containsIgnoreCase(profileName)){
                return new CanvasTemplate(winnerTemplate);
            }else{
                return new CanvasTemplate('No Canvas template is visible to your profile!');
            }
        } catch (Exception e) {
            return new CanvasTemplate(e.getMessage());
        }
    }
    
    /**
     * @description:
     *   Inner wrapper class to encapsulate AI Canvas Template data for the UI component.
     *   Provides structured access to template properties or error messages.
     */
    public class CanvasTemplate{
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String visibilityCondition;
        @AuraEnabled public String errorMessage;

        /**
         * @description:
         *   Constructor that initializes the wrapper with data from an AI Canvas Template record
         *
         * @param canvasTemplate - AI_Canvas_Template__c record to wrap
         */
        public CanvasTemplate(AI_Canvas_Template__c canvasTemplate){
            this.objectApiName = canvasTemplate.Object__c;
            this.visibilityCondition = canvasTemplate.Visibility_Condition__c;
        }
        
        /**
         * @description:
         *   Constructor that initializes the wrapper with an error message
         *
         * @param errorMessage - Error message to be displayed
         */
        public CanvasTemplate(String errorMessage){
            this.errorMessage = errorMessage;
        }
    }
}