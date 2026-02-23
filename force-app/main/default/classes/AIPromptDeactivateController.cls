public with sharing class AIPromptDeactivateController {
    /**
     * Deactivates a prompt associated with the specified record.
     *
     * This method takes a record ID as a parameter and performs the necessary
     * actions to deactivate the corresponding prompt. The specific implementation
     * details may include updating the database or changing the status of the prompt.
     *
     * @param recordId The unique identifier of the record for which the prompt
     *                 should be deactivated.
     * @return A String indicating the result of the deactivation process. This
     *         could be a success message, an error message, or any other relevant
     *         information.
     */
    @AuraEnabled 
    public static String deactivatePrompt(String recordId) {
        try{
            AI_Prompt__c pmt = [SELECT Id, Name, Type__c, AI_Data_Extraction_Mapping__c, AI_Connection__c, Object__c, Prompt_Command__c,
                                AI_Data_Extraction_Mapping__r.Object_Name__c, AI_Connection__r.Named_Credential__c, Prompt_Version__c
                                //,Target_Field__c /*#JIRA-4986:Prompt Action Framework*/
                                FROM AI_Prompt__c WHERE Id =:recordId];
            pmt.Status__c = 'Draft';
            FLSCheck.getInstance().updateDML(new List<AI_Prompt__c>{pmt});
            return null;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptDeactivateController', 'deactivatePrompt', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
}