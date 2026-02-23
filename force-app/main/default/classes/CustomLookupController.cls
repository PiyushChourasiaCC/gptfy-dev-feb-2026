/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 11-27-2023
* @last modified by  : Adarsh Sharma
**/
public with sharing class CustomLookupController {
    @AuraEnabled
    public static List<sObject> getRecords(String objectName, String field, String searchTerm){
        try{
            List<SObject> lstResults = new List<SObject>();
            if(String.isBlank(searchTerm)){
                String soqlQuery = 'SELECT Id, Name, Type, LastViewedDate FROM RecentlyViewed WHERE Type =\''+objectName+'\' ORDER BY LastViewedDate DESC LIMIT 5';
                if(objectName.endsWith('__mdt')){
                    soqlQuery = 'SELECT Id, MasterLabel, DeveloperName FROM '+objectName+' ORDER BY MasterLabel ASC LIMIT 100';
                }
                soqlQuery = soqlQuery.replace('\\\'', '\'');
                lstResults = Database.query(String.escapeSingleQuotes(soqlQuery).replace('\\\'', '\''));
            }else{
                String searchKeyword = '\'' + String.escapeSingleQuotes(searchTerm) + '%\'';
                String soqlQuery  = ('SELECT Id, '+field+' FROM '+objectName+' WHERE '+field+' LIKE '+ searchKeyword+' LIMIT 999').replace('\\\'', '\'');
                lstResults = Database.Query(String.escapeSingleQuotes(soqlQuery).replace('\\\'', '\''));
            }
            return lstResults;
        }catch(Exception ex){
            GPTfyException.log(ex, 'GPTfy', '', 'CustomLookupController', 'getRecords', '');
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static map<String, String> getPicklistValues(String objectName, String fieldName){
        map<String, String> mapPicklistValues = new map<String,String>();
        for( Schema.PicklistEntry pickListVal : Schema.getGlobalDescribe().get(NAMESPACE+objectName).getDescribe().fields.getMap().get(NAMESPACE+fieldName).getDescribe().getPicklistValues()){
            mapPicklistValues.put(pickListVal.getValue(), pickListVal.getLabel());
        }
        return mapPicklistValues;
    }

    public static final String NAMESPACE = AIExtractionFieldMappingController.NAMESPACE;

    @AuraEnabled
    public static String createResponseMapping(List<String> METADATA_FIELDS, Map<String, Object> params, Map<String,String> responseMappingParams){
        try {
            String responseMappingName = (String)params.get('name');
            Boolean isExistResponseMapping = false;
            for(AI_Response_Mapping__c rm : [SELECT Id FROM AI_Response_Mapping__c WHERE Name=:responseMappingName LIMIT 1]){
                isExistResponseMapping = true;
            }
            if(!isExistResponseMapping){
                AI_Response_Mapping__c reMapping = new AI_Response_Mapping__c();
                reMapping.Name = (String)params.get('name');
                for(String field : METADATA_FIELDS){
                    if(String.isNotBlank(field) && !field.equalsIgnoreCase('name')){
                        reMapping.put(NAMESPACE + field, params.get(field));
                    }
                }
                reMapping = (AI_Response_Mapping__c)FLSCheck.getInstance().insertDML(new List<sObject>{reMapping}).get(0);

                List<AI_Response_Mapping_Line__c> lstResponseMappingLine = new List<AI_Response_Mapping_Line__c>();
                AI_Response_Mapping_Line__c oResponseMappingLine;
                for(String field : responseMappingParams.keyset()){
                    oResponseMappingLine = new AI_Response_Mapping_Line__c();
                    oResponseMappingLine.AI_Response_Mapping__c = reMapping.Id;
                    oResponseMappingLine.Security_Audit_Field_Name__c = field;
                    oResponseMappingLine.Mapping_Field_Name__c = responseMappingParams.get(field);
                    lstResponseMappingLine.add(oResponseMappingLine);
                }
                if(lstResponseMappingLine.size()>0){
                    FLSCheck.getInstance().insertDML(lstResponseMappingLine);
                }
                return reMapping.Id;
            }else{
                throw new AuraHandledException('There is already exist a Response Mapping with '+responseMappingName+' Name');
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static map<String, String> getsobjectMappingFields(String objectName, String fieldSetName){
        set<String> setFields = new set<String>();
        map<String, String> mapMappingFields = new map<String, String>();
        Schema.DescribeSObjectResult describeSObjectResultObj = Schema.getGlobalDescribe().get(NAMESPACE+objectName).getDescribe();
        for(Schema.FieldSetMember fsm : DescribeSObjectResultObj.FieldSets.getMap().get(NAMESPACE+fieldSetName).getFields()){
            setFields.add(fsm.getFieldPath());
        }
        for(Schema.SObjectField field : describeSObjectResultObj.fields.getMap().values()){
            Schema.DescribeFieldResult fieldResult = field.getDescribe();
            if(fieldResult.isAccessible() && !fieldResult.isAutoNumber() && fieldResult.isCreateable() && fieldResult.isUpdateable() && fieldResult.getType() != Schema.DisplayType.Reference && !setFields.contains(fieldResult.getName())){
                mapMappingFields.put(fieldResult.getName(), fieldResult.getLabel()+' ('+fieldResult.getName()+')');
            }
        }
        return mapMappingFields;
    }
}