public with sharing class AIPromptActionController {
	
    @AuraEnabled
    public static DataWrapper getPromptActions(String recordId){
        DataWrapper d_wrap = new DataWrapper();
        d_wrap.typeOptions = AIPromptController.getPickListValues(AIConstants.NAMESPACE+'AI_Prompt_Action__c', AIConstants.NAMESPACE+'Action__c');
        d_wrap.fieldActionTypeOptions = AIPromptController.getPickListValues(AIConstants.NAMESPACE+'AI_Prompt_Action_Detail__c', AIConstants.NAMESPACE+'Type__c');
        d_wrap.objectOptions = getSObjects();
        
        AI_Prompt__c pmt = [SELECT Id, Object__c, Type__c, Status__c 
                            FROM AI_Prompt__c 
                            WHERE Id =:recordId];
        
        if(pmt != null && pmt.Object__c != null){
            d_wrap.objectName = pmt.Object__c;
            d_wrap.targetObjectFieldOptions = getFieldOptions(pmt.Object__c, false);
            d_wrap.jsonNodeOptions = getJsonPromptNodeOptions(pmt.Id);
            d_wrap.showActions = true;
            if(pmt.Status__c == AIConstants.PMT_STATUS_ACTIVE){
                d_wrap.showActions = false;
            }
        }
        
        List<AI_Prompt_Action__c> lstOfActions = [SELECT Id, Action__c, Name, Action_Label__c, Apex_Class_Name__c, 
                                                 Field_API_Name__c, Flow_API_Name__c, Sequence__c, Description__c,
                                                 Prompt_Component__c, Object_Name__c, Append_Timestamp__c,
                                                 (SELECT Id, Field_API_Name__c, Type__c, Value__c 
                                                  FROM Prompt_Action_Details__r)
                                                 FROM AI_Prompt_Action__c
                                                 WHERE AI_Prompt__c =:recordId
                                                 ORDER BY Sequence__c];
        
        List<ActionWrapper> lstOfWrapper = new List<ActionWrapper>();
        if(lstOfActions != null && !lstOfActions.isEmpty()){
            for(AI_Prompt_Action__c pa : lstOfActions){
                ActionWrapper wrap = new ActionWrapper();
            	wrap.id = pa.Id;
                wrap.name = pa.Name;
                wrap.actionType = pa.Action__c;
                wrap.actionName = '';
                wrap.actionLabel = pa.Action_Label__c;
                wrap.description = pa.Description__c;
                wrap.appendTimestamp = pa.Append_Timestamp__c;
                if(wrap.actionType == AIConstants.ACTION_TYPE_UPDATE_FIELD){
                    wrap.fieldApiName = pa.Field_API_Name__c;
                    wrap.actionName = pa.Field_API_Name__c;
                    wrap.promptComponent = pa.Prompt_Component__c != null ? pa.Prompt_Component__c : '#N/A#';
                }else if(wrap.actionType == AIConstants.ACTION_TYPE_INVOKE_APEX){
                    wrap.apexClassName = pa.Apex_Class_Name__c;
                    wrap.actionName = pa.Apex_Class_Name__c;
                }else if(wrap.actionType == AIConstants.ACTION_TYPE_INVOKE_FLOW){
                    wrap.flowApiName = pa.Flow_API_Name__c;
                    wrap.actionName = pa.Flow_API_Name__c;
                }else if(wrap.actionType == AIConstants.ACTION_TYPE_CREATE_RECORD || wrap.actionType == AIConstants.ACTION_TYPE_OPEN_FORM){
                    wrap.objectName = pa.Object_Name__c;
                    wrap.fieldOptions = getFieldOptions(pa.Object_Name__c, true);
                }
                wrap.sequence = pa.Sequence__c != null ? (Integer)pa.Sequence__c : null;              
                
                if(pa.Prompt_Action_Details__r != null && !pa.Prompt_Action_Details__r.isEmpty()){
                    List<ActionDetailWrapper> details = new List<ActionDetailWrapper>();
                    for(AI_Prompt_Action_Detail__c detail : pa.Prompt_Action_Details__r){
                        ActionDetailWrapper d = new ActionDetailWrapper();
                        d.id = detail.Id;
                        d.fieldName = detail.Field_API_Name__c;
                        d.type = detail.Type__c;
                        d.value = detail.Value__c;
                        d.isReference = false;
                        d.jsonNode = false;
                        d.isHardcoded = false;
                        if(d.type == 'Reference Field'){
                            d.isReference = true;
                        }else if(d.type == 'AI Response'){
                            d.jsonNode = true;
                            if(String.isBlank(d.value)){
                                d.value = '#N/A#';
                            }
                        }else{
                            d.isHardcoded = true;
                        }
                        details.add(d);
                    }
                    wrap.fieldMappings = details;
                }
                
                lstOfWrapper.add(wrap);
            }
            d_wrap.actions = lstOfWrapper;
        }
        return d_wrap;
    }
    
    @AuraEnabled
    public static List<PicklistAttributeWrapper> getParentFields(String objName){  
        List<PicklistAttributeWrapper> lst = new List<PicklistAttributeWrapper>();
        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        Map<String, Schema.SObjectField> fieldMap = schemaMap.get(objName).getDescribe().fields.getMap();
        
        for(Schema.SObjectField sfield : fieldMap.Values()){
            Schema.describeFieldResult dfield = sfield.getDescribe();
            if(dfield.isUpdateable()){
                PicklistAttributeWrapper pv = new PicklistAttributeWrapper();
                List<Schema.sObjectType> types = dfield.getReferenceTo();
                
                pv.label = dfield.getLabel();
                pv.value = dfield.getName();
                pv.description = dfield.getName();
                pv.relationshipName = dfield.getRelationshipName();  
                pv.parentName = types != null && !types.isEmpty() ? String.valueOf(types.get(0)) : '';
                if(String.isNotBlank(pv.parentName)){
                    pv.label += ' >';
                }else{
                    pv.fieldType = String.valueOf(dfield.getType());
                }
                if(types == null || types.isEmpty() || types.size() <= 1){
                    if((String.isNotBlank(pv.parentName) && String.isNotBlank(pv.relationshipName)) || String.isBlank(pv.parentName)){
                        lst.add(pv);
                    }                    
                }
            }
        } 
        if(!lst.isEmpty()){
            lst.sort();
        }
        return lst;
    }
    
    public static List<PicklistAttributeWrapper> getJsonPromptNodeOptions(String recordId){  
    	List<PicklistAttributeWrapper> lst = new List<PicklistAttributeWrapper>();
        PicklistAttributeWrapper i_wrap = new PicklistAttributeWrapper();
        i_wrap.label = 'Entire JSON';
        i_wrap.value = '#N/A#';
        lst.add(i_wrap);                    
        
        for(AI_Prompt_Component__c obj : [SELECT Id, Name, Object_Name__c 
                                          FROM AI_Prompt_Component__c
                                          WHERE AI_Prompt__c =:recordId]){
            PicklistAttributeWrapper wrap = new PicklistAttributeWrapper();
            wrap.label = obj.Name;
            wrap.value = obj.Name;
            wrap.description = obj.Object_Name__c; 
            lst.add(wrap);                                  
        }
        return lst;
    }
    
    public static List<PicklistAttributeWrapper> getSObjects(){
        try{
            List<PicklistAttributeWrapper> objects = new List<PicklistAttributeWrapper>();
            for(Schema.SObjectType o : Schema.getGlobalDescribe().values()){
                Schema.DescribeSObjectResult objResult = o.getDescribe();
                if(objResult.isCreateable() && objResult.isUpdateable() && objResult.isAccessible()){
                    PicklistAttributeWrapper wrap = new PicklistAttributeWrapper();
                    wrap.label = objResult.getLabel()+' ('+objResult.getName()+')';
                    wrap.value = objResult.getName();
                    objects.add(wrap);
                }
            }
            objects.sort();
            return objects;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptActionController', 'getSObjects', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<PicklistAttributeWrapper> getFieldOptions(String objectName, Boolean isCreatable){
        isCreatable = isCreatable != null && isCreatable ? true : false;
        List<PicklistAttributeWrapper> fields = new List<PicklistAttributeWrapper>();
        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
    	Map<String, Schema.SObjectField> fieldMap = schemaMap.get(objectName).getDescribe().fields.getMap();
        for(Schema.SObjectField sfield : fieldMap.Values()){
            Schema.describeFieldResult dfield = sfield.getDescribe();
            if(dfield.isAccessible()){
                if((isCreatable && dfield.isCreateable()) || !isCreatable){
                    PicklistAttributeWrapper wrap = new PicklistAttributeWrapper();
                    wrap.label = dfield.getLabel();
                    wrap.value = dfield.getname();
                    wrap.description = dfield.getname();
                    fields.add(wrap);
                } 
            }
        } 
        return fields;
    }
    
    @AuraEnabled
    public static void upsertPromptActions(String data, String recordId){
        try{
            ActionWrapper wrap = (ActionWrapper)System.JSON.deserialize(data, ActionWrapper.class);
            AI_Prompt_Action__c pa = new AI_Prompt_Action__c();
            pa.Action__c = wrap.actionType;
            pa.Description__c = wrap.description;
			pa.Sequence__c = wrap.sequence != null ? (Integer)wrap.sequence : null; 
            pa.Append_Timestamp__c = false;
            if(wrap.actionType == AIConstants.ACTION_TYPE_UPDATE_FIELD){
                pa.Field_API_Name__c = wrap.fieldApiName;
                pa.Prompt_Component__c = wrap.promptComponent != null && !wrap.promptComponent.equalsIgnoreCase('#N/A#') ? wrap.promptComponent : null ;
                pa.Append_Timestamp__c = wrap.appendTimestamp != null && wrap.appendTimestamp ? true : false;
            }else if(wrap.actionType == AIConstants.ACTION_TYPE_INVOKE_APEX){
                pa.Apex_Class_Name__c = wrap.apexClassName;
            }else if(wrap.actionType == AIConstants.ACTION_TYPE_INVOKE_FLOW){
                pa.Flow_API_Name__c = wrap.flowApiName;
            }else if(wrap.actionType == AIConstants.ACTION_TYPE_CREATE_RECORD || wrap.actionType == AIConstants.ACTION_TYPE_OPEN_FORM){
                pa.Object_Name__c = wrap.objectName;
            }

            if(String.isNotBlank(wrap.id)){
                pa.Id = wrap.id;
                pa = (AI_Prompt_Action__c)FLSCheck.getInstance().updateDML(new List<AI_Prompt_Action__c>{pa}).get(0);
            }else{
                pa.AI_Prompt__c = recordId;
                pa = (AI_Prompt_Action__c)FLSCheck.getInstance().insertDML(new List<AI_Prompt_Action__c>{pa}).get(0);
            }
            
            if(wrap.fieldMappings != null && !wrap.fieldMappings.isEmpty()){
                List<AI_Prompt_Action_Detail__c> lstToUpdate = new List<AI_Prompt_Action_Detail__c>();
                List<AI_Prompt_Action_Detail__c> lstToInsert = new List<AI_Prompt_Action_Detail__c>();
                Set<String> setOfDetailIds = new Set<String>();
                for(ActionDetailWrapper d_wrap : wrap.fieldMappings){
                	AI_Prompt_Action_Detail__c detail = new AI_Prompt_Action_Detail__c();
                    detail.Field_API_Name__c = d_wrap.fieldName;
                    detail.Type__c = d_wrap.type;
                    detail.Value__c = d_wrap.value;
                    if(String.isNotBlank(d_wrap.id)){
                        detail.Id = d_wrap.id;
                        setOfDetailIds.add(d_wrap.id);
                        lstToUpdate.add(detail);
                    }else{
                        detail.AI_Prompt_Action__c = pa.Id;
                        lstToInsert.add(detail);
                    }
            	}
                List<AI_Prompt_Action_Detail__c> lstToDelete = [SELECT Id 
                                                                FROM AI_Prompt_Action_Detail__c 
                                                                WHERE AI_Prompt_Action__c =:pa.Id 
                                                                AND Id NOT IN :setOfDetailIds];
                if(!lstToDelete.isEmpty()){
                    FLSCheck.getInstance().deleteDML(lstToDelete);
                }
                if(!lstToUpdate.isEmpty()){
                    FLSCheck.getInstance().updateDML(lstToUpdate);
                }
                if(!lstToInsert.isEmpty()){
                    FLSCheck.getInstance().insertDML(lstToInsert);
                }
            }
            
        }catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
        
    }
    
    public class PicklistAttributeWrapper implements Comparable{
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String relationshipName{get;set;}
        @AuraEnabled public String parentName{get;set;}
        @AuraEnabled public String fieldType{get;set;}
        
        public Integer compareTo(Object objToCompare) {
        	return label.compareTo(((PicklistAttributeWrapper)objToCompare).label);
        }
    }
    
    public class DataWrapper{
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public Boolean showActions{get;set;}
        @AuraEnabled public List<PicklistAttributeWrapper> objectOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> typeOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> fieldActionTypeOptions{get;set;}
        @AuraEnabled public List<PicklistAttributeWrapper> jsonNodeOptions{get;set;}
        @AuraEnabled public List<ActionWrapper> actions{get;set;}
        @AuraEnabled public List<Object> targetObjectFieldOptions{get;set;}
    }
    
    public class ActionWrapper{
        @AuraEnabled public String id{get;set;}
        @AuraEnabled public String name{get;set;}
        @AuraEnabled public String actionLabel{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public Boolean appendTimestamp{get;set;}
        @AuraEnabled public String actionType{get;set;}
        @AuraEnabled public String actionName{get;set;}
        @AuraEnabled public String flowApiName{get;set;}
        @AuraEnabled public String apexClassName{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String fieldApiName{get;set;}
        @AuraEnabled public String promptComponent{get;set;}
        @AuraEnabled public Integer sequence{get;set;}
        @AuraEnabled public List<ActionDetailWrapper> fieldMappings{get;set;}
        @AuraEnabled public List<PicklistAttributeWrapper> fieldOptions{get;set;}
    }

    public class ActionDetailWrapper{
        @AuraEnabled public String id{get;set;}
        @AuraEnabled public String fieldName{get;set;}
        @AuraEnabled public String type{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public Boolean isReference{get;set;}
        @AuraEnabled public Boolean jsonNode{get;set;}
        @AuraEnabled public Boolean isHardcoded{get;set;}
    }
    
}