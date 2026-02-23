public with sharing class reqMappingController {
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    
    @AuraEnabled
    public static List<sObject> getRecords(String searchTerm){
        try{
            String objectName = NAMESPACE+'Request_Mapping__c';
            List<SObject> lstResults = new List<SObject>();
            if(String.isBlank(searchTerm)){
                String soqlQuery = 'SELECT Id, Name, Type, LastViewedDate FROM RecentlyViewed WHERE Type =\''+objectName+'\' ORDER BY LastViewedDate DESC LIMIT 5';
                if(objectName.endsWith('__mdt')){
                    soqlQuery = 'SELECT Id, MasterLabel, DeveloperName FROM '+objectName+' ORDER BY MasterLabel ASC LIMIT 100';
                }
                lstResults = Database.query( soqlQuery );
            }else{
                String searchKeyword = '\'' + String.escapeSingleQuotes(searchTerm) + '%\'';
                String soqlQuery  = 'SELECT Id, Name FROM '+objectName+' WHERE Name LIKE '+ searchKeyword+' LIMIT 999';
                lstResults = Database.Query(soqlQuery);
            }
            return lstResults;
        }catch(Exception ex){
            system.debug('============================= : '+ex.getStackTraceString());
            GPTfyException.log(ex, 'GPTfy', '', 'reqMappingController', 'getRecords', '');
            throw new AuraHandledException(ex.getMessage()+'--'+ex.getStackTraceString());
        }
    }
    
    @AuraEnabled
    public static map<String, String> getFields(String objectName, String fieldSetName){
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
    
    @AuraEnabled
    public static List<Request_Mapping_Line__c> createRequestMapping(Map<String, Object> mapReqParams, List<Map<String, Object>> mapReqLineParams){
        try{
            Request_Mapping__c reqMap = new Request_Mapping__c();
            reqMap.Name = (String)mapReqParams.get('reqName');
            reqMap.AI_Model__c = (String)mapReqParams.get('AI_Model__c'); 
            reqMap.Description__c = (String)mapReqParams.get('Description__c');
            
            reqMap = (Request_Mapping__c)FLSCheck.getInstance().insertDML(new List<Request_Mapping__c>{reqMap}).get(0);
            
            List<Request_Mapping_Line__c> lstReqLines = new List<Request_Mapping_Line__c>();
            for(Integer i = 0; i < mapReqLineParams.size(); i++){
                Request_Mapping_Line__c reqLine = new Request_Mapping_Line__c();
                reqLine.Request_Mapping__c = reqMap.Id;
                reqLine.Data_Source__c = (String)mapReqLineParams[i].get('dataSource');
                reqLine.User_Role__c = (String)mapReqLineParams[i].get('userRole');
                reqLine.Sequence__c = integer.valueOf(mapReqLineParams[i].get('sequence'));
                reqLine.Annotation__c = (String)mapReqLineParams[i].get('annotation');
                
                lstReqLines.add(reqLine);
            }
            
            if(lstReqLines.size() > 0){
                FLSCheck.getInstance().insertDML(lstReqLines);
            }
            
            return lstReqLines; 
        }catch(Exception ex){
            throw new AuraHandledException(ex.getMessage());
        }
    }
}