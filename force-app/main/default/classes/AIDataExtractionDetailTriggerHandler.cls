/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIDataExtractionDetailTriggerHandler {
	
    /**
     * This method is called before inserting records of the custom object AI_Data_Extraction_Detail__c.
     * It provides an opportunity to perform any necessary actions or validations
     * before the records are actually inserted into the database.
     *
     * @param newList A list of AI_Data_Extraction_Detail__c objects that are about to be inserted.
     */
    public static void onBeforeInsert(List<AI_Data_Extraction_Detail__c> newList){    
        createObjectHierarchy(newList);
    }
    
    /**
     * This method is called before inserting records of the custom object AI_Data_Extraction_Detail__c.
     * It provides an opportunity to perform any necessary actions or validations
     * before the records are actually inserted into the database.
     *
     * @param newList A list of AI_Data_Extraction_Detail__c objects that are about to be inserted.
     */
    public static void createObjectHierarchy(List<AI_Data_Extraction_Detail__c> newList){
        Set<String> setOfMasterIds = new Set<String>();
        for(AI_Data_Extraction_Detail__c detail : newList){
            setOfMasterIds.add(detail.AI_Data_Extraction_Mapping__c);
        }
        Map<String, AI_Data_Extraction_Mapping__c> mapOfMaster = new Map<String, AI_Data_Extraction_Mapping__c>([
            SELECT Id, Object_Name__c, (SELECT Id, Object_Hierarchy__c FROM AI_Data_Extraction_Details__r) 
            FROM AI_Data_Extraction_Mapping__c WHERE Id IN :setOfMasterIds
        ]);
        Map<String, AI_Data_Extraction_Detail__c> mapOfDetail = new Map<String, AI_Data_Extraction_Detail__c>();
        for(AI_Data_Extraction_Mapping__c master : mapOfMaster.values()){ 
            if(master.AI_Data_Extraction_Details__r != null){
                mapOfDetail.putAll(new Map<String, AI_Data_Extraction_Detail__c>(master.AI_Data_Extraction_Details__r));
            }            
        }
       	
        for(AI_Data_Extraction_Detail__c detail : newList){
            if(detail.Parent_Detail__c == null){
                detail.Object_Hierarchy__c = mapOfMaster.get(detail.AI_Data_Extraction_Mapping__c).Object_Name__c+' > '+detail.Object_Name__c;
            }else if(!mapOfDetail.isEmpty() && mapOfDetail.containsKey(detail.Parent_Detail__c)){
                detail.Object_Hierarchy__c = mapOfDetail.get(detail.Parent_Detail__c).Object_Hierarchy__c+' > '+detail.Object_Name__c;
            }
        }
    }
    
}