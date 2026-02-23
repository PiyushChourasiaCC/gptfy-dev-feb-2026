/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptComponentTriggerHandler {
	
    /**
     * This method is a trigger handler that is invoked before inserting records
     * of the AI_Prompt_Component__c object. It allows custom logic to be executed
     * prior to the records being inserted into the database.
     *
     * @param newList The list of AI_Prompt_Component__c records that are about
     *                to be inserted.
     */
    public static void onBeforeInsert(List<AI_Prompt_Component__c> newList){
        generateGPTfySentence(newList);
        validateComponentName(newList, null);
    }
    
    /**
     * This method is called before updating records of the AI_Prompt_Component__c object.
     * It allows for custom logic to be executed before the update operation.
     *
     * @param newList The list of AI_Prompt_Component__c records that are being updated.
     * @param oldMap  A map containing the old versions of AI_Prompt_Component__c records,
     *                where the keys are record IDs.
     */
    public static void onBeforeUpdate(List<AI_Prompt_Component__c> newList, Map<Id, AI_Prompt_Component__c> oldMap){
        generateGPTfySentence(newList);
        validateComponentName(newList, oldMap);
    }
    
    public static void onAfterInsert(List<AI_Prompt_Component__c> newList){
        generatePromptJSON(newList, null);
    }
    
    public static void onAfterUpdate(List<AI_Prompt_Component__c> newList, Map<Id, AI_Prompt_Component__c> oldMap){
        generatePromptJSON(newList, oldMap);
    }
    
    public static void onAfterDelete(List<AI_Prompt_Component__c> oldList){
        generatePromptJSON(oldList, null);
    }
    
    /**
     * Validates the component names in a list of new components against a map of old components.
     *
     * @param newList   The list of new AI_Prompt_Component__c instances to be validated.
     * @param oldMap    The map of old AI_Prompt_Component__c instances, where the key is the Id.
     */
    public static void validateComponentName(List<AI_Prompt_Component__c> newList, Map<Id, AI_Prompt_Component__c> oldMap){
        Boolean isNew = oldMap != null ? false : true;
        
        Set<String> setOfUniqueIds = new Set<String>();
        Set<String> masterIds = new Set<String>();
        for(AI_Prompt_Component__c obj : newList){
            if(isNew || obj.Name != oldMap.get(obj.Id).Name){
                masterIds.add(obj.AI_Prompt__c);
            }
        }

        if(!masterIds.isEmpty()){
            for(AI_Prompt_Component__c obj : [SELECT Id, Name, AI_Prompt__c FROM AI_Prompt_Component__c WHERE AI_Prompt__c IN :masterIds]){
                String key = obj.AI_Prompt__c+'~'+obj.Name.toLowerCase();
                setOfUniqueIds.add(key);
            }
        }
        
        for(AI_Prompt_Component__c obj : newList){
            String key = obj.AI_Prompt__c+'~'+obj.Name.toLowerCase();
            if(!setOfUniqueIds.contains(key)){
                setOfUniqueIds.add(key);
            }else{
                obj.addError('Name cannot be same for two AI Component with same Prompt.');
            }
        }
    }
    
    /**
     * Generates a GPT-ified sentence based on the provided list of AI_Prompt_Component__c objects.
     *
     * @param newList A list of AI_Prompt_Component__c objects containing components of the input prompt.
     *                Each object represents a part of the prompt to be used in generating the sentence.
     */
    public static void generateGPTfySentence(List<AI_Prompt_Component__c> newList){
        for(AI_Prompt_Component__c obj : newList){
            String str = '';
            
            str += String.isNotBlank(obj.Phrase_Before_Action__c) ? obj.Phrase_Before_Action__c+' ' : '';
            str += String.isNotBlank(obj.Key__c) ? obj.Key__c+' ' : '';
            str += String.isNotBlank(obj.Phrase_After_Action__c) ? obj.Phrase_After_Action__c+' ' : '';
            
            str += String.isNotBlank(obj.Phrase_Before_Object__c) ? obj.Phrase_Before_Object__c+' ' : '';
            str += String.isNotBlank(obj.Object_Name__c) ? obj.Object_Name__c+' ' : '';
            str += String.isNotBlank(obj.Phrase_After_Object__c) ? obj.Phrase_After_Object__c+' ' : '';
            
            if(String.isNotBlank(obj.Length__c)){
                str += String.isNotBlank(obj.Phrase_Before_Length__c) ? obj.Phrase_Before_Length__c+' ' : '';
                str += obj.Length__c+' ';
                str += String.isNotBlank(obj.Phrase_After_Length__c) ? obj.Phrase_After_Length__c+' ' : '';
            }
            
            if(String.isNotBlank(obj.Language__c)){
                str += String.isNotBlank(obj.Phrase_Before_Language__c) ? obj.Phrase_Before_Language__c+' ' : '';
                str += obj.Language__c+' ';
                str += String.isNotBlank(obj.Phrase_After_Language__c) ? obj.Phrase_After_Language__c+' ' : '';
            } 
            
            if(String.isNotBlank(obj.Tone__c)){
                str += String.isNotBlank(obj.Phrase_Before_Tone__c) ? obj.Phrase_Before_Tone__c+' ' : '';
                str += obj.Tone__c+' ';
                str += String.isNotBlank(obj.Phrase_After_Tone__c) ? obj.Phrase_After_Tone__c+' ' : '';
            }

            if(String.isNotBlank(obj.Format__c)){
                str += String.isNotBlank(obj.Phrase_Before_Format__c) ? obj.Phrase_Before_Format__c+' ' : '';
                str += obj.Format__c+' ';
                str += String.isNotBlank(obj.Phrase_After_Format__c) ? obj.Phrase_After_Format__c+' ' : '';
            }         

            if(String.isNotBlank(obj.Constraint_Value__c)){
                str += String.isNotBlank(obj.Phrase_Before_Contraints__c) ? obj.Phrase_Before_Contraints__c+' ' : '';
                str += obj.Constraint_Value__c+' ';
            	str += String.isNotBlank(obj.Phrase_After_Contraints__c) ? obj.Phrase_After_Contraints__c+' ' : '';
            }
            
            if(String.isNotBlank(obj.Additional_Instructions__c)){
                str += obj.Additional_Instructions__c+' ';
            }

            obj.GPTfy_Sentence__c = str;
        }
    }
    
    public static void generatePromptJSON(List<AI_Prompt_Component__c> newList, Map<Id, AI_Prompt_Component__c> oldMap){
        Boolean isNew = oldMap != null ? false : true;
        Set<String> setOfPromptIds = new Set<String>();
        for(AI_Prompt_Component__c pc : newList){
            if(isNew || pc.Name != oldMap.get(pc.Id).Name || pc.GPTfy_Sentence__c != oldMap.get(pc.Id).GPTfy_Sentence__c){
                setOfPromptIds.add(pc.AI_Prompt__c);
            }
        }
        
        Map<String, List<AI_Prompt_Component__c>> mapOfPromptIdToComponents = new Map<String, List<AI_Prompt_Component__c>>();
        if(!setOfPromptIds.isEmpty()){
			List<AI_Prompt_Component__c> lstOfComponents = [SELECT Id, Name, GPTfy_Sentence__c, Object_Name__c, Data_Extraction_Id__c, 
                                                            AI_Prompt__c, AI_Prompt__r.AI_Data_Extraction_Mapping__c,
                                                            AI_Prompt__r.AI_Data_Extraction_Mapping__r.Object_Name__c
                                                            FROM AI_Prompt_Component__c 
                                                            WHERE AI_Prompt__c IN :setOfPromptIds
                                                            ORDER BY CreatedDate DESC];   
            for(AI_Prompt_Component__c pc : lstOfComponents){
                if(!mapOfPromptIdToComponents.containsKey(pc.AI_Prompt__c)){
                    mapOfPromptIdToComponents.put(pc.AI_Prompt__c, new List<AI_Prompt_Component__c>());
                }
                mapOfPromptIdToComponents.get(pc.AI_Prompt__c).add(pc);
            }
        }

        if(!mapOfPromptIdToComponents.isEmpty()){
            List<AI_Prompt__c> lstToUpdate = new List<AI_Prompt__c>();
            for(String pmtId : mapOfPromptIdToComponents.keySet()){
                AI_Prompt__c pmt = new AI_Prompt__c();
                pmt.Prompt_Command__c = AIJsonGeneration.generatePromptJson(mapOfPromptIdToComponents.get(pmtId));
                pmt.Id = pmtId;
                lstToUpdate.add(pmt);
            }
            if(!lstToUpdate.isEmpty()){
                FLSCheck.getInstance().updateDML(lstToUpdate);
            }
        }
    }
    
}