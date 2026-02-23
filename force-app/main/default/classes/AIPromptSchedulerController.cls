/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 01-08-2024
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptSchedulerController {
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();

    /**
     * Retrieves data for a specific record identified by the given record ID.
     *
     * @param recordId The unique identifier of the record for which data is requested.
     * @return A Map<String, Object> containing details related to the processing of the specified record.
     *         The keys in the map represent different aspects of the processing, and the corresponding values
     *         are objects containing the relevant data.
     */
    @AuraEnabled
    public static Map<String, Object> getPromptSchedulerData(String recordId){
        try{
            List<Schema.FieldSetMember> fieldSetMembers = SObjectType.AI_Prompt_Scheduler__c.FieldSets.Scheduler_Related_Fields.getFields();
        
            List<Object> fields = new List<Object>();
            List<String> fieldApiNames = new List<String>();
            for(Schema.FieldSetMember fmObj : fieldSetMembers){
                String fieldName = fmObj.getFieldPath();
                String fieldLabel = fmObj.getLabel();
                String fieldType = String.valueOf(fmObj.getType());  
                
                fieldApiNames.add(fieldName);
                
                Boolean isReference = false;
                if(String.isNotBlank(fieldType) && fieldType.equalsIgnoreCase('reference')){
                    isReference = true;
                    
                    String lookupNameField = fieldName;
                    if(lookupNameField.endsWithIgnoreCase('__c')){
                        lookupNameField = lookupNameField.removeEndIgnoreCase('__c')+'__r.Name';
                    }else if(lookupNameField.endsWithIgnoreCase('Id')){
                        lookupNameField = lookupNameField.removeEndIgnoreCase('Id')+'.Name';
                    }
                    fieldApiNames.add(lookupNameField);
                }
                String jsType = 'text';
                if(fieldType.equalsIgnoreCase('DateTime')){
                    jsType = 'date-local';
                }
                
                fields.add(new Map<String, Object>{
                    'label' => fieldLabel, 'fieldName' => fieldName, 'type' => jsType, 'isReference' => isReference
                });
            }
            
            String objName = NAMESPACE+'AI_Prompt_Scheduler__c';
            String parentFieldApi = NAMESPACE+'AI_Scheduler__c';
            String query = 'SELECT Id, '+String.join(fieldApiNames, ', ')+' FROM '+String.escapeSingleQuotes(objName)+' WHERE '+String.escapeSingleQuotes(parentFieldApi)+' =:recordId';
            List<sObject> records = Database.query(query);
            
            return new Map<String, Object>{
                'fields' => fields, 'records' => records
            };
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptSchedulerController', 'getPromptSchedulerData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> getPromptSchedulerDetail(String recordId){
        List<AI_Prompt_Scheduler__c> lstOfPromptSchs = [SELECT Id, Object_Name__c, Prompt__c, Prompt__r.Name, Where_Clause__c, Record_Limit__c 
                                                        FROM AI_Prompt_Scheduler__c WHERE Id =:recordId LIMIT 1];
        if(lstOfPromptSchs != null && !lstOfPromptSchs.isEmpty()){
            AI_Prompt_Scheduler__c ps = lstOfPromptSchs.get(0);
            return new Map<String, Object>{
                'id' => ps.Id, 'objectName' => ps.Object_Name__c, 'promptId' => ps.Prompt__c,
                'promptName' => ps.Prompt__r.Name, 'whereClause' => ps.Where_Clause__c, 'recordLimit' => ps.Record_Limit__c 
            };
        }
        return null;
    }
    
    @AuraEnabled
    public static List<Object> getPromptOptions(){
        List<Object> lst = new List<Object>();
        List<AI_Prompt__c> lstOfPrompts = [SELECT Id, Name, Object__c, Prompt_Command__c
                                           FROM AI_Prompt__c 
                                           WHERE Status__c =:AIConstants.PMT_STATUS_ACTIVE];
        if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
            for(AI_Prompt__c pmt : lstOfPrompts){
                if(String.isNotBlank(pmt.Prompt_Command__c)){
                    lst.add(new Map<String, Object>{
                    	'value' => pmt.Id, 'label' => pmt.Name, 'description' => pmt.Object__c
               		});
                } 
            }
        }
        return lst;
    }
    
    @AuraEnabled
    public static String getPromptObject(String recordId){
        List<AI_Prompt__c> lstOfPrompts = [SELECT Id, Object__c FROM AI_Prompt__c WHERE Id =:recordId LIMIT 1];
        if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
            return lstOfPrompts.get(0).Object__c;
        }else{
            List<AI_Prompt_Scheduler__c> lstOfPromptSchs = [SELECT Id, Object_Name__c FROM AI_Prompt_Scheduler__c WHERE Id =:recordId LIMIT 1];
            if(lstOfPromptSchs != null && !lstOfPromptSchs.isEmpty()){
                return lstOfPromptSchs.get(0).Object_Name__c;
            }
        }
        return null;
    }

}