public with sharing class AISecurityFilterTriggerHandler {
    
    public static String sampleInputOfRegex = '123-456-789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    
	/**
     * This method is a trigger handler that is invoked before inserting records
     * of the AI_Security_Filters__c object. It allows custom logic to be executed
     * prior to the records being inserted into the database.
     *
     * @param newList The list of AI_Security_Filters__c records that are about
     *                to be inserted.
     */
    public static void onBeforeInsert(List<AI_Security_Filters__c> newList){
        checkIsRegexValidAndUpdatePattern(newList,null);
        checkIsApexClassValid(newList,null);
    }
    
    /**
     * This method is called before updating records of the AI_Security_Filters__c object.
     * It allows for custom logic to be executed before the update operation.
     *
     * @param newList The list of AI_Security_Filters__c records that are being updated.
     * @param oldMap  A map containing the old versions of AI_Security_Filters__c records,
     *                where the keys are record IDs.
     */
    public static void onBeforeUpdate(List<AI_Security_Filters__c> newList, Map<Id, AI_Security_Filters__c> oldMap){
        checkIsRegexValidAndUpdatePattern(newList,oldMap);
        checkIsApexClassValid(newList,oldMap);
    }
    
    /*
	 * Checks whether the Apex class is valid or not.
	 */
    //Jira: 6007
    public static void checkIsApexClassValid(List<AI_Security_Filters__c> newList,Map<Id, AI_Security_Filters__c> oldMap){
        String recTypeId = Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get(AIConstants.SEC_LAYER_REC_TYPE_APEX).getRecordTypeId();
        Set<String> setDupRecOfApexName = new Set<String>();
        Set<String> setApexClassName = new Set<String>();
        Set<String> setValidApexClassName = new Set<String>();
        List<AI_Security_Filters__c> lstOfFilters = new List<AI_Security_Filters__c>();
        
        Boolean isNew = oldMap != null ? false : true;
        for(AI_Security_Filters__c sf : newList){
            if(recTypeId == sf.RecordTypeId){
                //if((isNew || oldMap.get(sf.Id).Status__c != sf.Status__c || sf.Apex_Class_Name__c != oldMap.get(sf.Id).Apex_Class_Name__c) && sf.Status__c == AIConstants.SEC_LAYER_STATUS_ACTIVE){
                //Jira 7221: Issues/Feedbacks from 1.12 Testing
                if( ( isNew || ( oldMap.get(sf.Id).Status__c != sf.Status__c && sf.Status__c == AIConstants.SEC_LAYER_STATUS_ACTIVE ) )
					                || ( sf.Apex_Class_Name__c != oldMap.get(sf.Id).Apex_Class_Name__c ) ) {
                    if(String.isNotBlank(sf.Apex_Class_Name__c)){
                        lstOfFilters.add(sf);
                        setApexClassName.add(sf.Apex_Class_Name__c);
                    }else{
                        sf.addError('Invalid Apex Class Name.');
                    }
                }
            }
        }
        
        if(!lstOfFilters.isEmpty()){
            if(setApexClassName.size() > 0){
                for(ApexClass ac : [SELECT Id, Name FROM ApexClass 
                                    WHERE Name IN: setApexClassName 
                                    AND Status = 'Active']){
                    setValidApexClassName.add(ac.Name);
                }
                //Jira 7221: Issues/Feedbacks from 1.12 Testing
                List<AI_Security_Filters__c> secfilterApexDuplicate = [SELECT Id,RecordTypeId,Apex_Class_Name__c FROM AI_Security_Filters__c 
                                                                            WHERE RecordTypeId = :recTypeId
                                                                       		AND Id NOT IN :lstOfFilters
                                                                            AND Apex_Class_Name__c in :setApexClassName];
                if(!secfilterApexDuplicate.isEmpty()){
                    for(AI_Security_Filters__c sf : secfilterApexDuplicate){
                        setDupRecOfApexName.add(sf.Apex_Class_Name__c);
                    }
                }
            }
            
            for(AI_Security_Filters__c sf : lstOfFilters){
                if(setValidApexClassName.isEmpty() || !setValidApexClassName.contains(sf.Apex_Class_Name__c)){
                    sf.addError('Invalid Apex Class Name.');
                }
                //Jira 7221:  Issues/Feedbacks from 1.12 Testing
                if(setDupRecOfApexName.contains(sf.Apex_Class_Name__c)){
                    sf.addError('This Apex Class Name is already exists with Other Security Layer Records.');
                }
        	}
        }
    }
    
    /*
	 * Checks whether the regex pattern is valid or not.
	 */
	public static void checkIsRegexValidAndUpdatePattern(List<AI_Security_Filters__c> newList,Map<Id, AI_Security_Filters__c> oldMap){
        Boolean isNew = oldMap!= null ? false : true;
        String recTypeId = Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Regex').getRecordTypeId();
        for(AI_Security_Filters__c sf : newList){
            if(recTypeId == sf.RecordTypeId){
                try{
                    if(sf.Search_Pattern__c != null){
                            Pattern.matches(sf.Search_Pattern__c, sampleInputOfRegex);
                    }else{
                            sf.addError('Invalid Search Pattern');
                    }
                }catch(Exception e){
                    sf.addError('Invalid Search Pattern');
                }
            }
        }
	}
}