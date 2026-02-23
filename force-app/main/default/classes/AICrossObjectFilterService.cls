/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-03-2025
* @last modified by  : Rishabh Goel
**/
public with sharing class AICrossObjectFilterService {
    
    public static List<AI_Cross_Object_Filter__c> getCrossObjectFilters(String mappingId){
        List<AI_Cross_Object_Filter__c> lstOfFilters = [SELECT Id, Name, Object_API__c, Object_Label__c, 
                                                        Operator__c, Parent_Filter__c, Relationship_Field__c, 
                                                        Relationship_Name__c, Sequence__c, Value__c, Where_Clause__c 
                                                        FROM AI_Cross_Object_Filter__c 
                                                        WHERE Object_API__c != NULL 
                                                        AND Operator__c != NULL 
                                                        AND Relationship_Field__c != NULL 
                                                        AND Sequence__c > 0
                                                        AND Value__c >= 0 
                                                        AND AI_Prompt_Scheduler__c =:mappingId  
                                                        ORDER BY Sequence__c ASC];
        if(lstOfFilters != null && !lstOfFilters.isEmpty()){
            return lstOfFilters;
        }
        return null;
    }
    
    public static Set<String> init(String filterConditions, List<AI_Cross_Object_Filter__c> lstOfFilters, Set<String> recordIds){
        
        Map<String, Map<String, Boolean>> mapOfRecordIdToMapOfSequenceToValid = new Map<String, Map<String, Boolean>>();

        for(AI_Cross_Object_Filter__c filter : lstOfFilters){
            
            String query = 'SELECT Count(Id) cnt, '+filter.Relationship_Field__c+' FROM '+filter.Object_API__c + ' WHERE '+filter.Relationship_Field__c+' IN :recordIds';
            if(String.isNotBlank(filter.Where_Clause__c)){
                query += ' AND ( '+filter.Where_Clause__c+' ) ';
            }
            query += ' GROUP BY '+filter.Relationship_Field__c;
            
            List<AggregateResult> listOfResults = Database.query(query);
            
            Map<String, Integer> mapOfRecordIdToCount = new Map<String, Integer>();
            if(listOfResults != null && !listOfResults.isEmpty()){
                for(AggregateResult ar : listOfResults){
                	String recId = String.valueOf(ar.get(filter.Relationship_Field__c));
                    Integer count = Integer.valueOf(ar.get('cnt'));
                    if(!mapOfRecordIdToCount.containsKey(recId)){
                        mapOfRecordIdToCount.put(recId, count);
                    }
            	}
            }

            for(String recId : recordIds){
                Integer count = 0;
                if(!mapOfRecordIdToCount.isEmpty() && mapOfRecordIdToCount.containsKey(recId)){
                    count = mapOfRecordIdToCount.get(recId);
                }
                Boolean isValid = checkValidity(filter, count);
                Integer sequence = Integer.valueOf(filter.Sequence__c);
                if(!mapOfRecordIdToMapOfSequenceToValid.containsKey(recId)){
                    mapOfRecordIdToMapOfSequenceToValid.put(recId, new Map<String, Boolean>());
                }
                mapOfRecordIdToMapOfSequenceToValid.get(recId).put(String.valueOf(sequence), isValid);
            }
        }

        if(!mapOfRecordIdToMapOfSequenceToValid.isEmpty()){
			return evaluateFinalResult(mapOfRecordIdToMapOfSequenceToValid, filterConditions, recordIds);         
        }
		
        return null;
        
    }
    
    public static Boolean checkValidity(AI_Cross_Object_Filter__c filter, Integer count){
        String operator = filter.Operator__c;
        Integer value = Integer.valueOf(filter.Value__c);
        if(operator.equalsIgnoreCase('Equals') && value == count){
        	return true;
        }else if(operator.equalsIgnoreCase('Not Equals') && value != count){
            return true;
        }else if(operator.equalsIgnoreCase('Less than') && count < value){
            return true;
        }else if(operator.equalsIgnoreCase('Less than or Equals') && count <= value){
            return true;
        }else if(operator.equalsIgnoreCase('Greater than') && count > value){
            return true;
        }else if(operator.equalsIgnoreCase('Greater than or Equals') && count >= value){
            return true;
        }
        return false;
    }
    
    public static Set<String> evaluateFinalResult(Map<String, Map<String, Boolean>> mapOfRecordIdToMapOfSequenceToValid, String filterConditions, Set<String> recordIds){
        Set<String> qualifiedRecordIds = new Set<String>();
        for(String recId : recordIds){
            if(mapOfRecordIdToMapOfSequenceToValid.containsKey(recId)){
                Map<String, Boolean> mapOfSequenceToValid = mapOfRecordIdToMapOfSequenceToValid.get(recId);
                
                List<String> sequenceList = new List<String>();
                List<Integer> integerSequences = new List<Integer>();
                for(String sequence : mapOfSequenceToValid.keySet()){
                    integerSequences.add(Integer.valueOf(sequence));
                }
                integerSequences.sort();
                for(Integer i = integerSequences.size() - 1; i >= 0; i--){
                    sequenceList.add(String.valueOf(integerSequences.get(i)));
                }
                
                String condition = filterConditions;
                for(String sequence : sequenceList){
                    String val = mapOfSequenceToValid.get(sequence) ? 'true' : 'false';
                    while(condition.contains(sequence)){
                        condition = condition.replaceFirst(sequence, String.valueOf(val));
                    }
                }
                Boolean isValid = evaluate(condition);
                if(isValid && !qualifiedRecordIds.contains(recId)){
                    qualifiedRecordIds.add(recId);
                }
            }
        }  
        if(!qualifiedRecordIds.isEmpty()){
            return qualifiedRecordIds;
        }
        return null;
    }
    
    public static Boolean evaluate(String x){
        x = simplify(x);
        if(!isSimpleExpression(x)){
            if (x.contains('AND')) return andJoin(x.split('AND', 2));
            if (x.contains('OR')) return orJoin(x.split('OR', 2));
            if (x.startsWith('!')) return !evaluate(x.substring(1));
        }
        return Boolean.valueOf(x);
    }

    public static String simplify(String x){
        x = x.trim();
        while (x.contains('(')){
            String sub = x.substringAfterLast('(').substringBefore(')');
            x = x.replace('(' + sub + ')', String.valueOf(evaluate(sub)));
        }
        return x;
    }
    
    public static Boolean orJoin(List<String> lst){
        return evaluate(lst.get(0)) || evaluate(lst.get(1)); 
    }
    
    public static Boolean andJoin(List<String> lst){
        return evaluate(lst.get(0)) && evaluate(lst.get(1)); 
    }
    
    public static Boolean isSimpleExpression(String x){
        return x == 'true' || x == 'false'; 
    }
    
}