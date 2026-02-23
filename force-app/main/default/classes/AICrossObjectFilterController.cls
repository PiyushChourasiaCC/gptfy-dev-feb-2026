/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 12-08-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AICrossObjectFilterController {
    
    public static Map<String, Schema.SObjectType> schemaMap;
    static{
        schemaMap = Schema.getGlobalDescribe();
    }
	
    @AuraEnabled
    public static DataWrapper fetchHierarchy(String masterId){
        DataWrapper wrap = new DataWrapper();
        
        List<AI_Cross_Object_Filter__c> parentList = new List<AI_Cross_Object_Filter__c>();
        List<AI_Cross_Object_Filter__c> childList = new List<AI_Cross_Object_Filter__c>();
        List<String> filterIds = new List<String>();
        for(AI_Cross_Object_Filter__c detail : [SELECT Id, Object_API__c, Object_Label__c, Parent_Filter__c, Parent_Filter__r.Object_Api__c, 
                                                Relationship_Field__c, Relationship_Name__c, Sequence__c, Where_Clause__c, AI_Prompt_Scheduler__c, 
                                                AI_Prompt_Scheduler__r.Object_Name__c, Operator__c, Value__c 
                                                FROM AI_Cross_Object_Filter__c
                                             	WHERE AI_Prompt_Scheduler__c =:masterId 
                                                ORDER BY Parent_Filter__c ASC NULLS FIRST, Sequence__c]){
            if(detail.Parent_Filter__c != null){
                childList.add(detail);
            }else{
                parentList.add(detail);
            }  
            filterIds.add(detail.Id);                                    
        }
        
        List<HierarchyWrapper> listWrap = new List<HierarchyWrapper>();
            
        if(!parentList.isEmpty()){
            for(AI_Cross_Object_Filter__c f : parentList){
                HierarchyWrapper hWrap = getMappedHierarchyWrapper(f);
                if(!childList.isEmpty()){ 
                    hWrap.children = findRelations(childList, f.Id);
                }
                listWrap.add(hWrap);
            }
        }
        
        String NAMESPACE = AIPromptController.NAMESPACE;
        wrap.filters = listWrap;
        wrap.filterIds = filterIds;
        wrap.operatorOptions = AIPromptController.getPickListValues(NAMESPACE+'AI_Cross_Object_Filter__c', NAMESPACE+'Operator__c');
        return wrap;
    }

    public static List<HierarchyWrapper> findRelations(List<AI_Cross_Object_Filter__c> listOfDetails, Id rootId) {
    	List<HierarchyWrapper> listWrap = new List<HierarchyWrapper>();
        for(AI_Cross_Object_Filter__c f : listOfDetails){
            if(f.Parent_Filter__c == rootId){
                HierarchyWrapper wrap = getMappedHierarchyWrapper(f);
                wrap.children = findRelations(listOfDetails, f.Id);
                listWrap.add(wrap);
            }
        }

        if(!listWrap.isEmpty()){
            return listWrap;
        } 
        return null;
    }
    
    public static HierarchyWrapper getMappedHierarchyWrapper(AI_Cross_Object_Filter__c f){
        HierarchyWrapper wrap = new HierarchyWrapper();
        wrap.filterId = f.Id;
        wrap.parentId = f.Parent_Filter__c;
        wrap.objectName = f.Object_API__c ;
        wrap.objectLabel = f.Object_Label__c;
        wrap.operator = f.Operator__c;
        wrap.filterValue = Integer.valueOf(f.Value__c);
        wrap.sequence = Integer.valueOf(f.Sequence__c);
        wrap.whereClause = f.Where_Clause__c;
        wrap.relationshipField = f.Relationship_Field__c;
        wrap.relationshipLabel = f.Relationship_Name__c;
        if(f.Parent_Filter__c != null){
        wrap.relationshipOptions = AIDataExtractionController.getTargetFields(f.Parent_Filter__r.Object_API__c, f.Object_API__c, null, false);
        }else{
            wrap.relationshipOptions = AIDataExtractionController.getTargetFields(f.AI_Prompt_Scheduler__r.Object_Name__c, f.Object_API__c, null, false);
        }                                         
        return wrap;
    }
    
    @AuraEnabled
    public static void deleteFilters(String masterId, String filterId){
        if(String.isNotBlank(filterId)){
            try{
                List<AI_Cross_Object_Filter__c> listOfDetails = [SELECT Id, Object_API__c, Object_Label__c, Parent_Filter__c, 
                                                                 Parent_Filter__r.Object_Api__c, Relationship_Field__c, 
                                                                 Relationship_Name__c, Sequence__c, Where_Clause__c, AI_Prompt_Scheduler__c, 
                                                                 AI_Prompt_Scheduler__r.Object_Name__c, Operator__c, Value__c 
                                                                 FROM AI_Cross_Object_Filter__c
                                                                 WHERE AI_Prompt_Scheduler__c =:masterId 
                                                                 ORDER BY Parent_Filter__c ASC NULLS FIRST, Object_API__c];
                List<AI_Cross_Object_Filter__c> filteredList = findChildMappings(listOfDetails, filterId);
                filteredList.add(new AI_Cross_Object_Filter__c(Id = filterId));
                FLSCheck.getInstance().deleteDML(filteredList);
            }catch(Exception e){
                throw new AuraHandledException(e.getMessage());
            }
        }
    }
    
    public static List<AI_Cross_Object_Filter__c> findChildMappings(List<AI_Cross_Object_Filter__c> listOfDetails, Id rootId) {
    	List<AI_Cross_Object_Filter__c> lstOfMapping = new List<AI_Cross_Object_Filter__c>();
        for(AI_Cross_Object_Filter__c detail : listOfDetails) {
            if (detail.Parent_Filter__c == rootId) {
                lstOfMapping.add(detail);
                lstOfMapping.addAll(findChildMappings(listOfDetails, detail.Id));
            }
        }
        return lstOfMapping;
    }
    
    @AuraEnabled
    public static List<AIDataExtractionController.PicklistWrapper> getRelatedObjects(String masterId, String parentId, String parentObject){
        List<AIDataExtractionController.PicklistWrapper> lstOfWrapper = new List<AIDataExtractionController.PicklistWrapper>();
        
        Set<String> alreadySet= new Set<String>();
        Schema.DescribeSObjectResult describeObj = schemaMap.get(parentObject).getDescribe();
        if(describeObj.isCustom()){
            String str = describeObj.getName();
            str = str.removeEndIgnoreCase('c');
            alreadySet.add(str+'History');
            alreadySet.add(str+'Feed');
        }else{
            alreadySet.add(describeObj.getName()+'History');
            alreadySet.add(describeObj.getName()+'Feed');
        }
        
        for(Schema.ChildRelationship cr: describeObj.getChildRelationships()){
            if(schemaMap.containsKey(String.valueOf(cr.getChildSObject()))){
                String fieldName = String.valueOf(cr.getField());
                if(String.isNotBlank(fieldName) && !fieldName.equalsIgnoreCase('CreatedById') && !fieldName.equalsIgnoreCase('LastModifiedById')){
                    Schema.DescribeSObjectResult describeChildObj = schemaMap.get(String.valueOf(cr.getChildSObject())).getDescribe();
                    DescribeSObjectResult objResult = schemaMap.get(String.valueOf(cr.getChildSObject())).getDescribe();
                    if(objResult != null && objResult.fields.getMap() != null && objResult.fields.getMap().containsKey(fieldName)){
                        DescribeFieldResult fieldResult = objResult.fields.getMap().get(fieldName).getDescribe();
                        if(!alreadySet.contains(describeChildObj.getName()) && fieldResult != null){
                            AIDataExtractionController.PicklistWrapper pv = new AIDataExtractionController.PicklistWrapper();
                            pv.value = String.valueOf(describeChildObj.getName());
                            pv.label = String.valueOf(describeChildObj.getLabel()) + ' ('+pv.value+')';
                            lstOfWrapper.add(pv);
                            alreadySet.add(String.valueOf(describeChildObj.getName()));
                        }
                    }
                }
            }  
        }
        
        return lstOfWrapper;
    }
    
    @AuraEnabled
    public static void upsertRelatedFilter(Map<String, String> filterData){
        try{
            String selectedObject = filterData.get('selectedObject');
            String masterId = filterData.get('masterId');
            String parentId = filterData.get('parentId');
            String filterId = filterData.get('filterId');
            String parentObject = filterData.get('parentObject');
            String operator = filterData.get('operator');
            String filterValue = filterData.get('filterValue');
            String whereClause = filterData.get('whereClause');
            String sequence = filterData.get('sequence');
            String relationshipField = filterData.get('relationshipField');
            String relationshipName = filterData.get('relationshipName');
    
            if(String.isNotBlank(masterId)){
                
                Schema.DescribeSObjectResult descObj = schemaMap.get(selectedObject).getDescribe(); 
                
                AI_Cross_Object_Filter__c filter = new AI_Cross_Object_Filter__c();
                filter.operator__c = operator;
                filter.Object_API__c = selectedObject;
                filter.Object_Label__c = descObj.getLabel();
                if(String.isNotBlank(parentId)){
                    filter.Parent_Filter__c = parentId;
                }
                filter.Relationship_Field__c = relationshipField;
                filter.Relationship_Name__c = relationshipName;
                filter.Sequence__c = String.isNotBlank(sequence) ? Integer.valueOf(sequence) : 1;
                filter.Value__c = String.isNotBlank(filterValue) ? Integer.valueOf(filterValue) : 0;
                filter.Where_Clause__c = whereClause;
                if(String.isNotBlank(filterId)){
                    filter.Id = filterId;
                    FLSCheck.getInstance().updateDML(new List<AI_Cross_Object_Filter__c>{filter});
                }else{
                    filter.AI_Prompt_Scheduler__c = masterId;
                    FLSCheck.getInstance().insertDML(new List<AI_Cross_Object_Filter__c>{filter});
                }
            }
        
        }catch(Exception e){
        	throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void updateCofiCondition(String condition, String recordId){
        condition = String.isNotBlank(condition) ? condition : '';
        if(String.isNotBlank(recordId)){
            AI_Prompt_Scheduler__c dm = new AI_Prompt_Scheduler__c(Id = recordId, Cross_Object_Filter_Condition__c = condition);
            FLSCheck.getInstance().updateDML(new List<AI_Prompt_Scheduler__c>{dm});
        }
    }
        
    public class DataWrapper{
        @AuraEnabled public Boolean hasError{get;set;}
        @AuraEnabled public List<HierarchyWrapper> filters{get;set;}
        @AuraEnabled public List<String> filterIds{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> operatorOptions{get;set;}
    }
    
    public class HierarchyWrapper {
        @AuraEnabled public String filterId{get;set;}
        @AuraEnabled public String parentId{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String objectLabel{get;set;}
        @AuraEnabled public String operator{get;set;}
        @AuraEnabled public Integer filterValue{get;set;}
        @AuraEnabled public Integer sequence{get;set;}
        @AuraEnabled public String whereClause{get;set;}
        @AuraEnabled public String relationshipField{get;set;}
        @AuraEnabled public String relationshipLabel{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> relationshipOptions{get;set;}
        
        @AuraEnabled public List<HierarchyWrapper> children{get;set;}
    }
    
}