public with sharing class AICardConfigurationTriggerHandler {
	
    public static void onBeforeInsert(List<AI_Card_Configuration__c> newList){
        validateCardConfigName(newList, null);        
    }
    
    public static void onBeforeUpdate(List<AI_Card_Configuration__c> newList, Map<Id, AI_Card_Configuration__c> oldMap){
		validateCardConfigName(newList, oldMap);        
    }

    public static void validateCardConfigName(List<AI_Card_Configuration__c> newList, Map<Id, AI_Card_Configuration__c> oldMap){
        Boolean isNew = oldMap != null ? false : true;
        
        Set<String> configIds = new Set<String>();
        Map<String, Integer> mapOfNameToCount = new Map<String, Integer>();
        List<AI_Card_Configuration__c> lstOfConfigs = new List<AI_Card_Configuration__c>();
        for(AI_Card_Configuration__c conn : newList){
            if(isNew || conn.Name != oldMap.get(conn.Id).Name){
                String connName = conn.Name.toLowerCase();
                if(!mapOfNameToCount.containsKey(connName)){
                    mapOfNameToCount.put(connName, 1);
                }else{
                    mapOfNameToCount.put(connName, 1 + mapOfNameToCount.get(connName));
                }
                if(conn.Id != null){
                    configIds.add(conn.Id);
                }
                lstOfConfigs.add(conn);
            }
        }
        
        if(!mapOfNameToCount.isEmpty() && !lstOfConfigs.isEmpty()){
            for(AggregateResult ar : [SELECT Count(Id) cnt, Name 
                                      FROM AI_Card_Configuration__c 
                                      WHERE Id NOT IN :configIds 
                                      AND Name IN :mapOfNameToCount.keySet() 
                                      GROUP BY Name]){
                String connName = String.valueOf(ar.get('Name')).toLowerCase();
                Integer count = Integer.valueOf(ar.get('cnt'));        
                mapOfNameToCount.put(connName, count + mapOfNameToCount.get(connName));                         
            }
            
            for(AI_Card_Configuration__c conn : lstOfConfigs){
                String connName = conn.Name.toLowerCase();
                if(mapOfNameToCount.containsKey(connName) && mapOfNameToCount.get(connName) > 1){
                    conn.addError('Cannot add Configuration with duplicate Name.');
                }
            }
        }
    }
    
}