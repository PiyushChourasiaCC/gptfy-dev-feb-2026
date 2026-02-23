/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 12-08-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AICrossObjectFilterTriggerHandler {
	
    public static void onBeforeInsert(List<AI_Cross_Object_Filter__c> newList){
		checkDuplicateSequence(newList);
        updateFilterQuery(newList, null);
    }
    
    public static void onBeforeUpdate(List<AI_Cross_Object_Filter__c> newList, Map<Id, AI_Cross_Object_Filter__c> oldMap){
		updateFilterQuery(newList, oldMap);
    }
    
    public static void onAfterInsert(List<AI_Cross_Object_Filter__c> newList){
        //deactivateMapping(newList, null);
    }
    
    public static void onAfterUpdate(List<AI_Cross_Object_Filter__c> newList, Map<Id, AI_Cross_Object_Filter__c> oldMap){
		//deactivateMapping(newList, oldMap);
    }
    
    public static void onAfterDelete(List<AI_Cross_Object_Filter__c> oldList){
		//deactivateMapping(oldList, null);
    }
    
    public static void checkDuplicateSequence(List<AI_Cross_Object_Filter__c> newList){
        Set<String> setOfUniqueIds = new Set<String>();
        Set<String> masterIds = new Set<String>();
        for(AI_Cross_Object_Filter__c filter : newList){
            masterIds.add(filter.AI_Prompt_Scheduler__c);
        }
        if(!masterIds.isEmpty()){
            for(AI_Cross_Object_Filter__c filter : [SELECT Id, AI_Prompt_Scheduler__c, Sequence__c FROM AI_Cross_Object_Filter__c WHERE AI_Prompt_Scheduler__c IN :masterIds]){
                String key = filter.AI_Prompt_Scheduler__c+'~'+filter.Sequence__c;
                setOfUniqueIds.add(key);
            }
        }
        
        for(AI_Cross_Object_Filter__c filter : newList){
            String key = filter.AI_Prompt_Scheduler__c+'~'+filter.Sequence__c;
            if(!setOfUniqueIds.contains(key)){
                setOfUniqueIds.add(key);
            }else{
                filter.addError('Sequence cannot be same for 2 filters with same Prompt.');
            }
        }
    }
    
    public static void updateFilterQuery(List<AI_Cross_Object_Filter__c> newList, Map<Id, AI_Cross_Object_Filter__c> oldMap){
        List<AI_Cross_Object_Filter__c> listOfFilter = new List<AI_Cross_Object_Filter__c>();
        Boolean isNew = oldMap != null ? false : true;
        for(AI_Cross_Object_Filter__c co : newList){
            if(isNew || (oldMap.containsKey(co.Id) && (co.Relationship_Field__c != oldMap.get(co.Id).Relationship_Field__c || co.Where_Clause__c != oldMap.get(co.Id).Where_Clause__c || co.Value__c != oldMap.get(co.Id).Value__c))){
                listOfFilter.add(co);
            }
        }
        
        for(AI_Cross_Object_Filter__c co : listOfFilter){
            String query = 'SELECT COUNT(Id), '+co.Relationship_Field__c+' FROM '+co.Object_API__c+' WHERE '+co.Relationship_Field__c+' IN ()';
            if(String.isNotBlank(co.Where_Clause__c)){
                query += ' AND ('+co.Where_Clause__c+')';
            }
            query += ' GROUP BY '+co.Relationship_Field__c;
            String operator = '';
            if(co.Operator__c.equalsIgnoreCase('Equals')){
        		operator = '=';
            }else if(co.Operator__c.equalsIgnoreCase('Not Equals')){
                operator = '!=';
            }else if(co.Operator__c.equalsIgnoreCase('Less than')){
                operator = '<';
            }else if(co.Operator__c.equalsIgnoreCase('Less than or Equals')){
                operator = '<=';
            }else if(co.Operator__c.equalsIgnoreCase('Greater than')){
                operator = '>';
            }else if(co.Operator__c.equalsIgnoreCase('Greater than or Equals')){
                operator = '>=';
            }
            query += ' HAVING COUNT(Id) '+operator+' '+co.Value__c;
            co.Filter_Query__c = query;
        }
    }
    
}