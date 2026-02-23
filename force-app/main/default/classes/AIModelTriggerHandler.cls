public with sharing class AIModelTriggerHandler {
	
    public static void onBeforeInsert(List<AI_Connection__c> newList){
        validateModelName(newList, null);        
    }
    
    public static void onBeforeUpdate(List<AI_Connection__c> newList, Map<Id, AI_Connection__c> oldMap){
		validateModelName(newList, oldMap);        
    }

    public static void validateModelName(List<AI_Connection__c> newList, Map<Id, AI_Connection__c> oldMap){
        Boolean isNew = oldMap != null ? false : true;
        
        Set<String> connectionIds = new Set<String>();
        Map<String, Integer> mapOfModelNameToCount = new Map<String, Integer>();
        List<AI_Connection__c> lstOfConnections = new List<AI_Connection__c>();
        for(AI_Connection__c conn : newList){
            if(isNew || conn.Name != oldMap.get(conn.Id).Name){
                String connName = conn.Name.toLowerCase();
                if(!mapOfModelNameToCount.containsKey(connName)){
                    mapOfModelNameToCount.put(connName, 1);
                }else{
                    mapOfModelNameToCount.put(connName, 1 + mapOfModelNameToCount.get(connName));
                }
                if(conn.Id != null){
                    connectionIds.add(conn.Id);
                }
                lstOfConnections.add(conn);
            }
        }
        
        if(!mapOfModelNameToCount.isEmpty() && !lstOfConnections.isEmpty()){
            for(AggregateResult ar : [SELECT Count(Id) cnt, Name 
                                      FROM AI_Connection__c 
                                      WHERE Id NOT IN :connectionIds 
                                      AND Name IN :mapOfModelNameToCount.keySet() 
                                      GROUP BY Name]){
                String connName = String.valueOf(ar.get('Name')).toLowerCase();
                Integer count = Integer.valueOf(ar.get('cnt'));        
                mapOfModelNameToCount.put(connName, count + mapOfModelNameToCount.get(connName));                         
            }
            
            for(AI_Connection__c conn : lstOfConnections){
                String connName = conn.Name.toLowerCase();
                if(mapOfModelNameToCount.containsKey(connName) && mapOfModelNameToCount.get(connName) > 1){
                    conn.addError('Cannot add models with duplicate Name.');
                }
            }
        }
    }
    
}