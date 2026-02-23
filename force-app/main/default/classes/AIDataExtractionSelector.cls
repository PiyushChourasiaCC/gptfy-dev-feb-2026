/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIDataExtractionSelector {
    
    STATIC FINAL String STATUS_ACTIVE = 'Active';
    
    static Set<String> getDefaultMappingFields(){
        return new Set<String>{
            'Id',
            'Object_Name__c'
        };
    }

    static Set<String> getDefaultDetailFields(){
        return new Set<String>{
            'Id',
            'AI_Data_Extraction_Mapping__c',
            'Type__c',
            'Running_Index__c',
            'Object_Name__c',
            'Parent_Detail__c',
            'Where_Clause__c',
            'Record_Limit__c',
            'Order_By__c',    
            'RelationshipField__c',
            'RelationshipName__c',
            'Parent_Detail__c',
            'Parent_Detail__r.Object_Name__c',
            'Parent_Detail__r.Where_Clause__c',
            'AI_Data_Extraction_Mapping__r.Object_Name__c',
            'Parent_Detail__r.relationShipField__c'
        };
    }

    static Set<String> getDefaultFields(){
        return new Set<String>{
            'Id',
            'AI_Data_Extraction_Mapping__c',
            'Anonymize_With__c',
            'Field__c',
            'Object__c',
            'Formula__c',
            'Field_Type__c', 
            'Masking_Scope__c',
            'Send_To_AI__c',
            'Type__c',
            'Label__c'
        };
    }
    
    static Set<String> getDefaultSecurityFilterFields(){
        return new Set<String>{
            'Id',
            'Name',
            'Type__c',
            'Search_Pattern__c',
            'Replacement_Value__c',
            'Status__c', 
            'Comment__c',
            'Blocklist__c',
            'RecordTypeId',
            'AI_Ignore_Special_Characters__c',
            'AI_Match_Complete_Word__c',
            'AI_Optimized_Search_Pattern__c'
        };
    }

    public static AI_Data_Extraction_Mapping__c getAIDataExtractionMappingById(Id mappingId){
        List<String> queryFieldList = new List<String>(getDefaultMappingFields());
        String query = 'SELECT ' +String.join(queryFieldList,',') + ' FROM AI_Data_Extraction_Mapping__c WHERE Id=:mappingId LIMIT 1';
        List<AI_Data_Extraction_Mapping__c> extractionMappings = Database.query(query);
        return extractionMappings.isEmpty() ? null : extractionMappings[0];
    }

    public static List<AI_Data_Extraction_Detail__c> getAIDataExtractionDetailByMappingId(Id mappingId){
        List<String> queryFieldList = new List<String>(getDefaultDetailFields());
        String query = 'SELECT ' + String.join(queryFieldList,',') + ' FROM AI_Data_Extraction_Detail__c WHERE AI_Data_Extraction_Mapping__c=:mappingId ORDER BY Running_Index__c ASC';
        return Database.query(query);
    }


    public static List<AI_Data_Extraction_Field__c> getAIDataExtractionFieldsByMappingId(Id mappingId){
        List<String> queryFieldList = new List<String>(getDefaultFields());
        String typeField = 'FIELD';
        // Jira 5988: Security Layer 1 and 2 is conflict
        String query = 'SELECT ' + String.join(queryFieldList,',') + ' FROM AI_Data_Extraction_Field__c WHERE AI_Data_Extraction_Mapping__c=:mappingId AND Type__c =:typeField ORDER BY Anonymize_With__c DESC';
        return Database.query(query);
    }
    
    public static List<AI_Security_Filters__c> getAISecurityFilters(){
        List<String> queryFieldList = new List<String>(getDefaultSecurityFilterFields());
        String query = 'SELECT ' + String.join(queryFieldList,',') + ' FROM AI_Security_Filters__c WHERE Status__c =: STATUS_ACTIVE AND Replacement_Value__c != NULL ';
        return Database.query(query);
    }


}