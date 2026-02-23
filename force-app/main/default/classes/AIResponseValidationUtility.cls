public with sharing class AIResponseValidationUtility {
	
    public static Boolean validateResponse(AI_Prompt__c pmt, String response){
        Boolean isValid = true;
        
        String responseCondition = '';
        if(String.isNotBlank(pmt.Response_Validation_Condition__c)){
            responseCondition = pmt.Response_Validation_Condition__c;
        }
        
        if(String.isNotBlank(response)){
            List<AI_Prompt_Response_Validation__c> lstOfValidations = [SELECT Id, Sequence__c, Action__c, Value__c 
                                                                       FROM AI_Prompt_Response_Validation__c
                                                                       WHERE AI_Prompt__c =:pmt.Id
                                                                       ORDER BY Sequence__c DESC];
            
            Map<String, Boolean> mapOfSequenceToValid = new Map<String, Boolean>();
            if(lstOfValidations != null && !lstOfValidations.isEmpty()){
                for(AI_Prompt_Response_Validation__c val : lstOfValidations){
                    Boolean iValid = checkValidityBasedOnAction(response, val);
                    String sequence = val.Sequence__c != null ? String.valueOf((Integer)val.Sequence__c) : '';
                    mapOfSequenceToValid.put(sequence, iValid);                                             
            	}

                List<Integer> integerSequences = new List<Integer>();
                for(String sequence : mapOfSequenceToValid.keySet()){
                    integerSequences.add(Integer.valueOf(sequence));
                }
                integerSequences.sort();
    
                if(String.isBlank(responseCondition)){
                    responseCondition = String.join(new List<String>(mapOfSequenceToValid.keySet()), ' AND ');
                }
    
                for(Integer i = integerSequences.size() - 1; i >= 0; i--){
                    String sequence = String.valueOf(integerSequences.get(i));
                    String val = mapOfSequenceToValid.get(sequence) ? 'true' : 'false';
                    while(responseCondition.contains(sequence)){
                        responseCondition = responseCondition.replaceFirst(sequence, String.valueOf(val));
                    }
                }            
                isValid = AICrossObjectFilterService.evaluate(responseCondition);
            }  
        }
        return isValid;
    }
    
    public static Boolean checkValidityBasedOnAction(String response, AI_Prompt_Response_Validation__c respVal){
        if(respVal.Action__c.equalsIgnoreCase(AIConstants.PROMPT_VALIDATION_ACTION_INCLUDE)){
            if(!response.containsIgnoreCase(respVal.Value__c)){
                return false;
            }
        }else if(respVal.Action__c.equalsIgnoreCase(AIConstants.PROMPT_VALIDATION_ACTION_EXCLUDE)){
            if(response.containsIgnoreCase(respVal.Value__c)){
                return false;
            }
        }else if(respVal.Action__c.equalsIgnoreCase(AIConstants.PROMPT_VALIDATION_ACTION_APEX)){
            Type impl = Type.forName('', respVal.Value__c);
            AIResponseValidationInterface obj = (AIResponseValidationInterface)impl.newInstance();
            return obj.invokeApex(response, respVal);
        }
        return true;
    }
    
}