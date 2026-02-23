/**
 * @description       : 
 * @author            : Adarsh Sharma
 * @group             : Plumcloud Labs
 * @last modified on  : 10-31-2023
 * @last modified by  : Adarsh Sharma
**/
public with sharing class AIPromptCloningController {
    
    /**
     * Get a Prompt record identified by the provided record ID.
     *
     * This method takes a unique record ID as a parameter and performs the
     * necessary operations to get a Prompt of the corresponding record.
     * The cloned record is then returned as a String representation.
     *
     * @param recordId The unique identifier of the record.
     * @return A String representing the Prompt record.
     * @JIRA : 5031 : Added getAIPromptData method to pull the Prompt Name and it's description
     */
    @AuraEnabled
    public static String getAIPromptData(String recordId){
        Map<String, Object> mapPromptData = new Map<String, Object>();
        for(AI_Prompt__c prompt :[SELECT Id, Name, Description__c FROM AI_Prompt__c WHERE Id=:recordId]){
            mapPromptData.put('Name', prompt.Name);
            mapPromptData.put('Description', prompt.Description__c);
        }
        return JSON.serialize(mapPromptData);
    }

    /**
     * Clones a record identified by the provided record ID.
     *
     * This method takes a unique record ID as a parameter and performs the
     * necessary operations to create a clone or duplicate of the corresponding
     * record. The cloned record is then returned as a String representation.
     *
     * @param recordId The unique identifier of the record to be cloned.
     * @param name The prompt name of the record to be cloned.
     * @param description The prompt desciption of the record to be cloned.
     * @param isDuplicateContextMapping The unique identifier is used to clone the Data Extraction Mapping.
     * @return A String representing the cloned record.
     * @JIRA : 5031 : Updated this method to take input for Prompt Name, Desciption and create duplicate data extraction mapping
     */
    @AuraEnabled
    public static String cloneRecord(String recordId, String name, String description, Boolean isDuplicateContextMapping){
        try{
            AI_Prompt__c prompt = [SELECT Id, Name, AI_Connection__c, AI_Data_Extraction_Mapping__c, Custom_Prompt__c, 
                                   Description__c, Object__c, Profiles__c, Prompt_Command__c, Purpose__c, 
                                   Record_Type__c, Status__c, Type__c, External_Id__c, Include_Files__c, 
                                   Max_Output_Tokens__c, Top_P__c, Temperature__c, Message__c, Auto_Refresh_Duration__c,
                                   //Target_Field__c, Append_Timestamp__c,/*#JIRA-4986:Prompt Action Framework*/
                                   Grounding_Ethical__c, Grounding_Content__c,AI_Locale_GPTfy_Console__c,AI_Locale_Automation__c,
                                   How_it_works__c,Visibility_Condition__c,AI_Model_File_Processing__c,Visibility_Exception_Message__c,
                                   Enable_Loopback__c, Loopback_Message__c, Response_Validation_Condition__c , Response_Validation_Message__c , Permission_Sets__c,Agentic_Function_Class__c
                                   FROM AI_Prompt__c WHERE Id=:recordId LIMIT 1];
            AI_Prompt__c clonePrompt = prompt.clone(false, true, false, false);
            clonePrompt.Name = name;
            clonePrompt.Description__c = description;
            clonePrompt.Status__c = 'Draft';
            //@JIRA : 5031 : Check and clone the AI Data Extraction Mapping with Prompt 
            if(isDuplicateContextMapping && prompt.AI_Data_Extraction_Mapping__c != null){
                clonePrompt.AI_Data_Extraction_Mapping__c = AIDataExtractionCloningController.cloneRecord(prompt.AI_Data_Extraction_Mapping__c, name);
            }
            clonePrompt = (AI_Prompt__c)FLSCheck.getInstance().insertDML(new List<AI_Prompt__c>{clonePrompt}).get(0);
            
            Map<String, AI_Prompt_Component__c> promptComponents = new Map<String, AI_Prompt_Component__c>();
            for(AI_Prompt_Component__c promptComponent : [SELECT Id, Name, AI_Prompt__c, Additional_Instructions__c, 
                                                        Constraint_Value__c, Data_Extraction_Id__c, Format__c, 
                                                        GPTfy_Sentence__c, Key__c, Language__c, Length__c, 
                                                        Object_Name__c, Phrase_After_Action__c, 
                                                        Phrase_After_Contraints__c, Phrase_After_Format__c, 
                                                        Phrase_After_Language__c, Phrase_After_Length__c, 
                                                        Phrase_After_Object__c, Phrase_After_Tone__c, 
                                                        Phrase_Before_Action__c, Phrase_Before_Contraints__c, 
                                                        Phrase_Before_Format__c, Phrase_Before_Language__c, 
                                                        Phrase_Before_Length__c, Phrase_Before_Object__c, 
                                                        Phrase_Before_Tone__c, Tone__c, User_Customizable__c, External_Id__c 
                                                        FROM AI_Prompt_Component__c WHERE AI_Prompt__c=:recordId ORDER BY CreatedDate ASC LIMIT 999]){
                AI_Prompt_Component__c clonePromptComponent = promptComponent.clone(false, true, false, false);
                clonePromptComponent.AI_Prompt__c = clonePrompt.Id;
                clonePromptComponent.Phrase_Before_Action__c = promptComponent.Phrase_Before_Action__c;
                clonePromptComponent.Phrase_Before_Contraints__c = promptComponent.Phrase_Before_Contraints__c;
                clonePromptComponent.Phrase_Before_Format__c = promptComponent.Phrase_Before_Format__c;
                clonePromptComponent.Phrase_Before_Language__c = promptComponent.Phrase_Before_Language__c;
                clonePromptComponent.Phrase_Before_Length__c = promptComponent.Phrase_Before_Length__c;
                clonePromptComponent.Phrase_Before_Object__c = promptComponent.Phrase_Before_Object__c;
                clonePromptComponent.Phrase_Before_Tone__c = promptComponent.Phrase_Before_Tone__c;

                clonePromptComponent.Phrase_After_Action__c = promptComponent.Phrase_After_Action__c;
                clonePromptComponent.Phrase_After_Contraints__c = promptComponent.Phrase_After_Contraints__c;
                clonePromptComponent.Phrase_After_Format__c = promptComponent.Phrase_After_Format__c;
                clonePromptComponent.Phrase_After_Language__c = promptComponent.Phrase_After_Language__c;
                clonePromptComponent.Phrase_After_Length__c = promptComponent.Phrase_After_Length__c;
                clonePromptComponent.Phrase_After_Object__c = promptComponent.Phrase_After_Object__c;
                clonePromptComponent.Phrase_After_Tone__c = promptComponent.Phrase_After_Tone__c;

                clonePromptComponent.Data_Extraction_Id__c = clonePrompt.AI_Data_Extraction_Mapping__c;
                promptComponents.put(promptComponent.Id, clonePromptComponent);
            }

            if(!promptComponents.IsEmpty()){
                FLSCheck.getInstance().insertDML(promptComponents.values(), true);
            }
            
            /*#JIRA-5327:Prompt Action Framework - Catchup*/
            Map<String, AI_Prompt_Action__c> promptActions = new Map<String, AI_Prompt_Action__c>();
            for(AI_Prompt_Action__c pa : [SELECT Id, Action__c, Apex_Class_Name__c, Append_Timestamp__c, 
                                          Description__c, Field_API_Name__c, Flow_API_Name__c, Object_Name__c,
                                          AI_Prompt__c, Prompt_Component__c, Sequence__c
                                          FROM AI_Prompt_Action__c 
                                          WHERE AI_Prompt__c =:prompt.Id]){
                AI_Prompt_Action__c clone_pa = pa.clone(false, true, false, false);
                clone_pa.AI_Prompt__c = clonePrompt.Id;
                promptActions.put(pa.Id, clone_pa);                              
            }
            if(!promptActions.IsEmpty()){
                Map<String, SObject> cleanedRecords = FLSCheck.getInstance().insertDML(promptActions, true);
                //Map<String, SObject> cleanedRecords = (Map<String, SObject>)promptActions;
                //cleanedRecords = (Map<String, SObject>)FLSCheck.getInstance().insertCheck(promptActions);
                //Database.insert(cleanedRecords.values(), true);
                
                
                List<AI_Prompt_Action_Detail__c> lstOfDetails = new List<AI_Prompt_Action_Detail__c>();
                for(AI_Prompt_Action_Detail__c detail : [SELECT Id, Field_API_Name__c, AI_Prompt_Action__c, Type__c, Value__c
                                                        FROM AI_Prompt_Action_Detail__c
                                                        WHERE AI_Prompt_Action__c IN :cleanedRecords.keySet()]){
                    AI_Prompt_Action_Detail__c clone_detail = detail.clone(false, true, false, false);
                    clone_detail.AI_Prompt_Action__c = cleanedRecords != null && cleanedRecords.containsKey(detail.AI_Prompt_Action__c) ? String.valueOf(cleanedRecords.get(detail.AI_Prompt_Action__c).get('Id')) : null;
                    lstOfDetails.add(clone_detail);        
                }
                if(!lstOfDetails.isEmpty()){
                    FLSCheck.getInstance().insertDML(lstOfDetails);
                }
            }

            /*#JIRA-V2-6162:Canvas enhancement*/
            Map<String, AI_Prompt_Element__c> promptElements = new Map<String, AI_Prompt_Element__c>();
            for(AI_Prompt_Element__c promptElement : [SELECT Id,AI_Prompt__c, AI_Parent_Prompt__c, AI_Summary_Prompt__c, Icon__c, Height__c,
                                                    Width__c, Sequence__c, Inherit_Prompt_Security__c
                                          FROM AI_Prompt_Element__c 
                                          WHERE AI_Parent_Prompt__c =:prompt.Id]){
                AI_Prompt_Element__c clonedPromptElement = promptElement.clone(false, true, false, false);
                clonedPromptElement.AI_Parent_Prompt__c = clonePrompt.Id;
                promptElements.put(promptElement.Id, clonedPromptElement);                              
            }
            if(!promptElements.IsEmpty()){
                FLSCheck.getInstance().insertDML(promptElements, true);
            }

            // Jira 7221: Issues/Feedbacks from 1.12 Testing
            Map<String, AI_Prompt_Response_Validation__c> promptResponseValidations = new Map<String, AI_Prompt_Response_Validation__c>();
            for(AI_Prompt_Response_Validation__c resp : [SELECT Id, Sequence__c, Action__c, Value__c 
                                                            FROM AI_Prompt_Response_Validation__c
                                                            WHERE AI_Prompt__c =:prompt.Id]){
                    AI_Prompt_Response_Validation__c clonedResponseValidation = resp.clone(false, true, false, false);
                    clonedResponseValidation.AI_Prompt__c = clonePrompt.Id;
                    promptResponseValidations.put(resp.Id, clonedResponseValidation);
            }

            if(!promptResponseValidations.IsEmpty()){
                FLSCheck.getInstance().insertDML(promptResponseValidations, true);
            }


            return clonePrompt.Id;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptCloningController', 'cloneRecord', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
}