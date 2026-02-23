/**
 * @description:
 *   AICanvasTemplateStatusManager is responsible for handling the activation and deactivation 
 *   of AI Canvas templates. It uses a builder pattern to update the status of templates
 *   and provides AuraEnabled methods for Lightning components to interact with.
 * 
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 13-05-2025
 * @last modified by  : Piyush Chourasia
 **/
public with sharing class AICanvasTemplateStatusManager {
    /**
     * @description Activates an AI Canvas Template by setting its status to 'Active'
     * @param recordId The Id of the AI Canvas Template to activate
     */
    @AuraEnabled
    public static void activateCanvasTemplate(String recordId){
        try {
            CanvasTemplateStatusBuilder builder = new CanvasTemplateStatusBuilder(recordId)
                                                        .setStatus('Active')
                                                        .build();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * @description Deactivates an AI Canvas Template by setting its status to 'Draft'
     * @param recordId The Id of the AI Canvas Template to deactivate
     */
    @AuraEnabled
    public static void deActivateCanvasTemplate(String recordId){
        try {
            CanvasTemplateStatusBuilder builder = new CanvasTemplateStatusBuilder(recordId)
                                                        .setStatus('Draft')
                                                        .build();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * @description Builder class for updating AI Canvas Template status
     * Implements the builder pattern for fluent API design
     */
    public class CanvasTemplateStatusBuilder{
        private List<AI_Canvas_Template__c> templates;
        
        /**
         * @description Constructor that fetches the template by Id
         * @param recordId The Id of the AI Canvas Template
         */
        public CanvasTemplateStatusBuilder(String recordId) {
            this.templates = [SELECT Id, Status__c 
                            FROM AI_Canvas_Template__c 
                            WHERE Id = :recordId LIMIT 1];
        }
        
        /**
         * @description Sets the status of the template
         * @param status The new status value
         * @return The builder instance for method chaining
         */
        public CanvasTemplateStatusBuilder setStatus(String status) {
            this.templates[0].Status__c = status;
            return this;
        }
    
        /**
         * @description Updates the template in the database with FLS checks
         * @return The builder instance for method chaining
         */
        public CanvasTemplateStatusBuilder build() {
            FLSCheck.getInstance().updateDML(new List<AI_Canvas_Template__c>{this.templates[0]});
            return this;
        }
    }
}