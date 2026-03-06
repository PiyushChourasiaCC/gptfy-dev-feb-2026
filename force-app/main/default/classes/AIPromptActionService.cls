public with sharing class AIPromptActionService {
    
    public static Map<String, Schema.SObjectType> schemaMap;
    public static Map<String, Map<String, Schema.SObjectField>> globalFieldMap;
    static{
        schemaMap = Schema.getGlobalDescribe();
    }
	
    public static List<AI_Security_Audit_Detail__c> managePromptActions(AI_Response__c response){
        Integer existingDetails = [SELECT COUNT()
                                   FROM AI_Security_Audit_Detail__c 
                                   WHERE AI_Security_Audit__c =:response.Id];
        
        if(existingDetails != null && existingDetails > 0){
            return null;
        }
        
        List<AI_Prompt_Action__c> lstOfActions = [SELECT Id, Action__c, Apex_Class_Name__c, Append_Timestamp__c, 
                                                  Description__c, Field_API_Name__c, Flow_API_Name__c, 
                                                  Object_Name__c, Prompt_Component__c, Sequence__c,
                                                  (SELECT Id, Field_API_Name__c, Type__c, Value__c FROM Prompt_Action_Details__r)
                                                  FROM AI_Prompt_Action__c
                                                  WHERE AI_Prompt__c =:response.AI_Prompt__c
                                                  ORDER BY Sequence__c ASC NULLS LAST];
        
        if(lstOfActions != null && !lstOfActions.isEmpty()){
            String formattedDateTime = getFormattedDateTime();
            AI_Prompt__c pmt = [SELECT Id, Object__c 
                                FROM AI_Prompt__c 
                                WHERE Id =:response.AI_Prompt__c];
            
            String currentRecordId = response.Record_Id__c;
            Map<String, QueriedFieldWrapper> mapOfQueriedFieldToValue = getQueriedFieldValues(lstOfActions, pmt, currentRecordId);
            
            Map<String, List<SObject>> mapToCreate = new Map<String, List<SObject>>();
            Map<String, Map<String, SObject>> mapToUpdate = new Map<String, Map<String, SObject>>();

            List<AI_Security_Audit_Detail__c> lstOfAuditDetailsToInsert = new List<AI_Security_Audit_Detail__c>();
            
            for(AI_Prompt_Action__c pa : lstOfActions){
                if(pa.Action__c == AIConstants.ACTION_TYPE_UPDATE_FIELD){
                    String fieldName = pa.Field_API_Name__c.toLowerCase();
                    if(mapOfQueriedFieldToValue != null && mapOfQueriedFieldToValue.containsKey(fieldName)){
                        QueriedFieldWrapper wrap = mapOfQueriedFieldToValue.get(fieldName);
                        if(!mapToUpdate.containsKey(wrap.objectName)){
                            mapToUpdate.put(wrap.objectName, new Map<String, sObject>());
                        }
                        if(!mapToUpdate.get(wrap.objectName).containsKey(wrap.recordId)){
                            Schema.SObjectType targetType = schemaMap.get(wrap.objectName);
							SObject obj = targetType.newSObject();
                            obj.put('Id', wrap.recordId);
                            mapToUpdate.get(wrap.objectName).put(wrap.recordId, obj);
                        }
                        Object fieldVal = getResponseValue(pa.Prompt_Component__c, response.AI_Processed_Data_PII_Added__c, pa.Append_Timestamp__c, formattedDateTime);
                        Object fieldValObj = getFieldTypeBasedValue(wrap.objectName, wrap.fieldName, String.valueOf(fieldVal));
                        mapToUpdate.get(wrap.objectName).get(wrap.recordId).put(wrap.fieldName, fieldValObj);
                    }
                }else if(pa.Action__c == AIConstants.ACTION_TYPE_CREATE_RECORD){
                    if(!mapToCreate.containsKey(pa.Object_Name__c)){
                        mapToCreate.put(pa.Object_Name__c, new List<sObject>());
                    }
                    Schema.SObjectType targetType = schemaMap.get(pa.Object_Name__c);
					SObject obj = targetType.newSObject();
                    obj = getMappedSObjectForCreateRecord(obj, pa, mapOfQueriedFieldToValue, response);
                    mapToCreate.get(pa.Object_Name__c).add(obj);
                }else if(pa.Action__c == AIConstants.ACTION_TYPE_INVOKE_FLOW){
                    String errorMessage = '';
                    Boolean isError = false;
                    try{
                        Flow.Interview flow_obj = Flow.Interview.createInterview(pa.Flow_API_Name__c, new Map<String, Object>{'securityAudit' => response});
						flow_obj.start();
                    }catch(Exception e){
                        isError = true;
                        errorMessage = e.getMessage();
                    }
                    lstOfAuditDetailsToInsert.add(getSecurityAuditDetail(AIConstants.ACTION_TYPE_INVOKE_FLOW, ('Flow: '+pa.Flow_API_Name__c), response.Id, isError, errorMessage));
                }else if(pa.Action__c == AIConstants.ACTION_TYPE_INVOKE_APEX){
                    String errorMessage = '';
                    Boolean isError = false;
                    try{
                        Type impl = Type.forName('', pa.Apex_Class_Name__c);
                        AIPromptActionInterface obj = (AIPromptActionInterface)impl.newInstance();
                        obj.invokeApex(response);
                    }catch(Exception e){
                        isError = true;
                        errorMessage = e.getMessage();
                    }
                    lstOfAuditDetailsToInsert.add(getSecurityAuditDetail(AIConstants.ACTION_TYPE_INVOKE_APEX, ('Apex Class: '+pa.Apex_Class_Name__c), response.Id, isError, errorMessage));
                }
            }
            if(!mapToUpdate.isEmpty()){
                for(String objName : mapToUpdate.keySet()){
                    List<String> messages = new List<String>();
                    messages.add('Object: '+objName);
                    messages.add('Total Records: '+mapToUpdate.get(objName).size());
                    for(String soId : mapToUpdate.get(objName).keySet()){
                        SObject so = mapToUpdate.get(objName).get(soId);
                        Map<String, Object> mapOfFieldToValue = so.getPopulatedFieldsAsMap();
                        messages.add(soId+': '+String.join(new List<String>(mapOfFieldToValue.keySet()), ', '));
                    }
                    String errorMessage = '';
                    Boolean isError = false;
                    try{
                        FLSCheck.getInstance().updateDML(mapToUpdate.get(objName).values());
                    }catch(Exception e){
                        isError = true;
                        errorMessage = e.getMessage();
                    }
                    lstOfAuditDetailsToInsert.add(getSecurityAuditDetail(AIConstants.ACTION_TYPE_UPDATE_FIELD, String.join(messages, '\n'), response.Id, isError, errorMessage));
                }
            }
            if(!mapToCreate.isEmpty()){
                for(String objName : mapToCreate.keySet()){
                    List<String> messages = new List<String>();
                    messages.add('Object: '+objName);
                    messages.add('Total Records: '+mapToCreate.get(objName).size());
                    String errorMessage = '';
                    Boolean isError = false;
                    try{
                        List<sObject> insertedRecords = FLSCheck.getInstance().insertDML(mapToCreate.get(objName));
                        Map<String, sObject> mapOfInsertedRecords = new Map<String, sObject>(insertedRecords);
                    	messages.add('Record IDs: '+String.join(new List<String>(mapOfInsertedRecords.keySet()), ', '));
                    }catch(Exception e){
                        isError = true;
                        errorMessage = e.getMessage();
                    }
                    lstOfAuditDetailsToInsert.add(getSecurityAuditDetail(AIConstants.ACTION_TYPE_CREATE_RECORD, String.join(messages, '\n'), response.Id, isError, errorMessage));
                }
            }
            if(!lstOfAuditDetailsToInsert.isEmpty()){
                lstOfAuditDetailsToInsert = (List<AI_Security_Audit_Detail__c>)FLSCheck.getInstance().insertDML(lstOfAuditDetailsToInsert);
                return lstOfAuditDetailsToInsert;
            }
        }
        return null;
    }
    
    public static AI_Security_Audit_Detail__c getSecurityAuditDetail(String actionType, String data, String responseId, Boolean isError, String errorMessage){
        AI_Security_Audit_Detail__c detail = new AI_Security_Audit_Detail__c();
        detail.Prompt_Action_Details__c = data;
        detail.Prompt_Action_Type__c = actionType;
        detail.AI_Security_Audit__c = responseId;
        detail.Type__c = AIConstants.SECURITY_AUDIT_DETAIL_TYPE_PROMPT_ACTION;
        detail.Status__c = AIConstants.SECURITY_AUDIT_DETAIL_STATUS_COMPLETED;
        if(isError != null && isError){
            detail.Status__c = AIConstants.SECURITY_AUDIT_DETAIL_STATUS_ERRORED;
            detail.Message__c = errorMessage;
        }
        return detail;
    }
    
    public static SObject getMappedSObjectForCreateRecord(SObject obj, AI_Prompt_Action__c action, Map<String, QueriedFieldWrapper> mapOfQueriedFieldToValue, AI_Response__c response){
        String objName = String.valueOf(obj.getSobjectType());
        if(action.Prompt_Action_Details__r != null && !action.Prompt_Action_Details__r.isEmpty()){
            for(AI_Prompt_Action_Detail__c detail : action.Prompt_Action_Details__r){
                if(detail.Type__c == AIConstants.ACTION_DETAIL_TYPE_REF_FIELD){ 
                    String sourceFieldName = detail.Value__c.toLowerCase();
                    if(mapOfQueriedFieldToValue != null && mapOfQueriedFieldToValue.containsKey(sourceFieldName)){
                        QueriedFieldWrapper wrap = mapOfQueriedFieldToValue.get(sourceFieldName);
                        obj.put(detail.Field_API_Name__c, wrap.fieldValue);
                    }
                }else if(detail.Type__c == AIConstants.ACTION_DETAIL_TYPE_HARDCODED){
                    if(String.isNotBlank(detail.Value__c) && detail.Value__c.equalsIgnoreCase('{TODAY}')){
                        obj.put(detail.Field_API_Name__c, (Object)System.today());
                    }else if(String.isNotBlank(detail.Value__c) && detail.Value__c.equalsIgnoreCase('{UserId}')){
                        obj.put(detail.Field_API_Name__c, (Object)UserInfo.getUserId());
                    }else if(String.isNotBlank(detail.Value__c) && detail.Value__c.equalsIgnoreCase('{NOW}')){
                        obj.put(detail.Field_API_Name__c, (Object)System.Now());
                    }else{ 
                        Object fieldVal = getFieldTypeBasedValue(objName, detail.Field_API_Name__c, detail.Value__c);
                        obj.put(detail.Field_API_Name__c, fieldVal);
                    }   
                }else if(detail.Type__c == AIConstants.ACTION_DETAIL_TYPE_AI_RESP){
                    Object fieldVal = getResponseValue(detail.Value__c, response.AI_Processed_Data_PII_Added__c, false, '');
                    Object fieldValObj = getFieldTypeBasedValue(objName, detail.Field_API_Name__c, String.valueOf(fieldVal));
                    obj.put(detail.Field_API_Name__c, fieldValObj);
                }
            }
        }
        return obj;
    }
    
    
    public static Object getResponseValue(String promptComponentName, String aiResponse, Boolean appendTimestamp, String formattedDateTime){
        Object response = aiResponse;
        if(String.isNotBlank(promptComponentName)){
            Map<String, Object> mapOfData;
            try{
                mapOfData = (Map<String,Object>)JSON.deserializeUntyped(aiResponse);
            }catch(Exception e){
                gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIPromptActionService', 'getResponseValue', '');
            }
            if(mapOfData != null && mapOfData.containsKey(promptComponentName)){
                response = mapOfData.get(promptComponentName);
            }
        }
        if(appendTimestamp != null && appendTimestamp){
            response = 'Generated On: '+formattedDateTime + ': '+response;
        }
        return response;
    }
    
    public static Map<String, QueriedFieldWrapper> getQueriedFieldValues(List<AI_Prompt_Action__c> lstOfActions, AI_Prompt__c pmt, String currentRecordId){
        Set<String> setOfFieldNames = new Set<String>();
        for(AI_Prompt_Action__c pa : lstOfActions){
            if(pa.Action__c == AIConstants.ACTION_TYPE_UPDATE_FIELD){
                setOfFieldNames.add(pa.Field_API_Name__c);
                if(pa.Field_API_Name__c.contains('.')){
                    setOfFieldNames.add(pa.Field_API_Name__c.substringBeforeLast('.')+'.Id');
                }
            }else if(pa.Action__c == AIConstants.ACTION_TYPE_CREATE_RECORD || pa.Action__c == AIConstants.ACTION_TYPE_OPEN_FORM){
                if(pa.Prompt_Action_Details__r != null && !pa.Prompt_Action_Details__r.isEmpty()){
                    for(AI_Prompt_Action_Detail__c detail : pa.Prompt_Action_Details__r){
                        if(detail.Type__c == AIConstants.ACTION_DETAIL_TYPE_REF_FIELD){
                            setOfFieldNames.add(detail.Value__c);
                            if(detail.Value__c.contains('.')){
                                setOfFieldNames.add(detail.Value__c.substringBeforeLast('.')+'.Id');
                            }
                        }
                    }
                }
            }else if(pa.Action__c == AIConstants.ACTION_TYPE_INVOKE_FLOW){
                //do-nothing
            }else if(pa.Action__c == AIConstants.ACTION_TYPE_INVOKE_APEX){
                //do-nothing
            }
        }  

        Map<String, QueriedFieldWrapper> mapOfQueriedFieldToWrapper = new Map<String, QueriedFieldWrapper>();
        if(!setOfFieldNames.isEmpty()){
            setOfFieldNames.add('Id');
            String query = 'SELECT '+String.join(new List<String>(setOfFieldNames), ', ')+' FROM '+String.escapeSingleQuotes(pmt.Object__c)+' WHERE Id =:currentRecordId LIMIT 1';
            List<sObject> lstOfRecords = Database.query(query);
            if(lstOfRecords != null && !lstOfRecords.isEmpty()){
                sObject so = lstOfRecords.get(0);
                for(String fieldName : setOfFieldNames){
                    if(fieldName.contains('.')){
                        List<String> fNames = fieldName.split('\\.');
                        sObject rObj;
                        for(Integer i = 0; i < fNames.size(); i++){
                            String fName = fNames.get(i);
                            if((fNames.size() - 1) == i){
                                if(rObj != null){
                                    Id r_id = Id.valueOf(String.valueOf(rObj.get('Id')));
                                    mapOfQueriedFieldToWrapper.put(fieldName.toLowerCase(), new QueriedFieldWrapper(String.valueOf(r_id.getsobjecttype()), fName, String.valueOf(r_id), rObj.get(fName)));
                                }
                            }else{
                                rObj = so.getSObject(fName);
                            }
                        }
                    }else{
                        mapOfQueriedFieldToWrapper.put(fieldName.toLowerCase(), new QueriedFieldWrapper(pmt.Object__c, fieldName, currentRecordId, so.get(fieldName)));
                    }
                }
            }
        }
        return mapOfQueriedFieldToWrapper;
    }
    
    public static Object getFieldTypeBasedValue(String objName, String fName, String fValue){
        if(globalFieldMap == null){
            globalFieldMap = new Map<String, Map<String, Schema.SObjectField>>();
        }
        if(!globalFieldMap.containsKey(objName)){
            globalFieldMap.put(objName, schemaMap.get(objName).getDescribe().fields.getMap());
        }
        
        String fType = String.valueOf(globalFieldMap.get(objName).get(fName).getDescribe().getType());  
        if(ftype == 'INTEGER' || ftype == 'DOUBLE' || ftype == 'CURRENCY' || ftype == 'DECIMAL' || ftype == 'PERCENT'){
            if(ftype == 'CURRENCY'){
                fValue = fValue.replaceAll('\\p{Sc}','');
            }else if(ftype == 'PERCENT'){
                fValue = fValue.replaceAll('%','');
            }
            Decimal val = Decimal.valueOf(fValue);
            if(ftype == 'INTEGER'){
                return (Integer)val;
            }else{
                return val;
            }
        }else if(ftype == 'BOOLEAN' || ftype == 'CHECKBOX'){
            return Boolean.valueOf(fValue);
        }else if(ftype == 'DATE'){
            return (Date) JSON.deserialize('"'+fValue+'"', Date.class);
        }else if(ftype == 'DATETIME'){
            return (Datetime) JSON.deserialize('"'+fValue+'"', Datetime.class);
        }else if(ftype == 'TIME'){
            return (Time) JSON.deserialize('"'+fValue+'"', Time.class);
        }

        if(fType == 'STRING' || fType == 'TEXTAREA'){
            Integer length = Integer.valueOf(globalFieldMap.get(objName).get(fName).getDescribe().getLength());
            if(length > 0 && String.isNotBlank(String.valueOf(fValue)) && String.valueOf(fValue).length() > length){
                return String.valueOf(fValue).substring(0, length);
            }
        }
        return fValue;
    }
    
    public class QueriedFieldWrapper{
        public String objectName{get;set;}
        public String recordId{get;set;}
        public String fieldName{get;set;}
        public Object fieldValue{get;set;}
        public QueriedFieldWrapper(String objectName, String fieldName, String recordId, Object fieldValue){
            this.objectName = objectName;
            this.fieldName = fieldName;
            this.recordId = recordId;
            this.fieldValue = fieldValue;
        }
    }
    
    public static String getFormattedDateTime(){
        // Query the Organization object to get the default time zone
        Organization orgInfo = [SELECT Id, TimeZoneSidKey FROM Organization LIMIT 1];
        
        // Get the current date and time in the default time zone
        Datetime currentDateTime = Datetime.now();
        String defaultTimeZoneId = orgInfo.TimeZoneSidKey;
        String formattedDateTime = currentDateTime.format('dd-MMM-yyyy HH:mm:ss zzz', defaultTimeZoneId);
        return formattedDateTime;
    }
    
}