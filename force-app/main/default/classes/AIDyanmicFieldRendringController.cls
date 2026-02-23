public with sharing class AIDyanmicFieldRendringController {
	
    @AuraEnabled
    public static Map<String, Object> getFieldData(List<String> fieldNames, String recordId){
    
        Map<String, Object> data = new Map<String, Object>();
        String query = 'SELECT Id, '+String.escapeSingleQuotes(String.join(fieldNames, ', '))+' FROM '+String.escapeSingleQuotes(AIConstants.NAMESPACE)+'AI_Response__c WHERE Id =:recordId LIMIT 1';
        query = query.replace('\\\'', '\'');

        AI_Response__c aiResp = (AI_Response__c)Database.query(query);
        if(aiResp != null){
            for(String fName : fieldNames){
                String fieldVal = '';
                if(String.isNotBlank(String.valueOf(aiResp.get(fName)))){
                    fieldVal = String.valueOf(aiResp.get(fName));
                }
                data.put(fName, fieldVal);
            }
        }
        
        Set<String> setOfDocIds = new Set<String>();
        for(ContentDocumentLink cdl : [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId =:recordId]){
            setOfDocIds.add(cdl.ContentDocumentId);
        } 
        
        if(!setOfDocIds.isEmpty()){
            for(ContentVersion cv : [SELECT Id, VersionData, Title FROM ContentVersion WHERE ContentDocumentId IN :setOfDocIds]){
                if(String.isNotBlank(cv.Title) && fieldNames.contains(cv.Title)){
                    String fieldVal = '';
                    if(cv.VersionData != NULL){
                        fieldVal = cv.VersionData.toString();  
                    }
                    data.put(cv.Title, fieldVal);
                }
            }
        }
        
        return data;
    }
    
}