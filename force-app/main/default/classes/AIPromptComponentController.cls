/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptComponentController {
	
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    
    /**
     * Retrieves component data for a prompt based on the provided record ID.
     *
     * @param recordId The unique identifier of the record for which the prompt component data is requested.
     * @return A Map<String, Object> containing the details of the prompt component data.
     *         The keys represent different properties, and the values are the corresponding data.
     *         Returns an empty map if no data is available or an error occurs during retrieval.
     */
    @AuraEnabled
    public static Map<String, Object> getPromptComponentData(String recordId){
        try{
            List<Schema.FieldSetMember> fieldSetMembers = SObjectType.AI_Prompt_Component__c.FieldSets.Prompt_Related_Fields.getFields();
        
            List<Object> fields = new List<Object>();
            List<String> fieldApiNames = new List<String>();
            for(Schema.FieldSetMember fmObj : fieldSetMembers){
                String fieldName = fmObj.getFieldPath();
                String fieldLabel = fmObj.getLabel();
                String fieldType = String.valueOf(fmObj.getType());  
                
                fieldApiNames.add(fieldName);
                String jsType = 'text';
                if(fieldType.equalsIgnoreCase('DateTime')){
                    jsType = 'date-local';
                }
                
                fields.add(new Map<String, Object>{
                    'label' => fieldLabel, 'fieldName' => fieldName, 'type' => jsType
                });
            }
            
            String objName = NAMESPACE+'AI_Prompt_Component__c';
            String parentFieldApi = NAMESPACE+'AI_Prompt__c';
            String query = 'SELECT Id, '+String.join(fieldApiNames, ', ')+' FROM '+objName+' WHERE '+parentFieldApi+' =:recordId ORDER BY CreatedDate ASC';
            List<sObject> records = Database.query(query);
            
            return new Map<String, Object>{
                'fields' => fields, 'records' => records
            };
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptComponentController', 'getPromptComponentData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves a list of component objects based on the provided parent ID.
     *
     * This method takes a parent ID as a parameter and returns a list of associated
     * component objects. The specific details of the implementation may vary based on
     * the application's requirements.
     *
     * @param parentId The identifier of the parent component for which associated
     *                 objects are to be retrieved.
     * @return A list of Object representing the component objects associated with
     *         the specified parent ID. The list may be empty if no objects are found.
     */
    @AuraEnabled
    public static List<Object> getComponentObjects(String parentId){
        try{
            AI_Prompt__c pmt = [SELECT Id, AI_Data_Extraction_Mapping__c, AI_Data_Extraction_Mapping__r.Object_Name__c FROM AI_Prompt__c WHERE Id =:parentId];  
            List<Object> options = new List<Object>();
            if(pmt.AI_Data_Extraction_Mapping__c != null){
                options.add(new Map<String, Object>{
                    'label' => pmt.AI_Data_Extraction_Mapping__r.Object_Name__c, 
                    'value' => pmt.AI_Data_Extraction_Mapping__c, 
                    'description' => pmt.AI_Data_Extraction_Mapping__r.Object_Name__c
                });
                for(AI_Data_Extraction_Detail__c detail : [SELECT Id, Object_Name__c, Object_Hierarchy__c FROM AI_Data_Extraction_Detail__c WHERE 
                                                        AI_Data_Extraction_Mapping__c =:pmt.AI_Data_Extraction_Mapping__c
                                                        ORDER BY Running_Index__c]){
                    options.add(new Map<String, Object>{
                        'label' => detail.Object_Name__c, 
                        'value' => detail.Id, 
                        'description' => detail.Object_Hierarchy__c
                    });
                }
            }
            return options;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptComponentController', 'getComponentObjects', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves processing data for a specific record identified by the given record ID.
     *
     * @param recordId The unique identifier of the record for which processing data is requested.
     * @return A Map<String, Object> containing details related to the processing of the specified record.
     *         The keys in the map represent different aspects of the processing, and the corresponding values
     *         are objects containing the relevant data.
     */
    @AuraEnabled
    public static Map<String, Object> getPromptProcessingData(String recordId){
        try{
            List<Schema.FieldSetMember> fieldSetMembers = SObjectType.AI_Response_Processing__c.FieldSets.Prompt_Related_Fields.getFields();
        
            List<Object> fields = new List<Object>();
            List<String> fieldApiNames = new List<String>();
            for(Schema.FieldSetMember fmObj : fieldSetMembers){
                String fieldName = fmObj.getFieldPath();
                String fieldLabel = fmObj.getLabel();
                String fieldType = String.valueOf(fmObj.getType());  
                
                fieldApiNames.add(fieldName);
                String jsType = 'text';
                if(fieldType.equalsIgnoreCase('DateTime')){
                    jsType = 'date-local';
                }
                
                fields.add(new Map<String, Object>{
                    'label' => fieldLabel, 'fieldName' => fieldName, 'type' => jsType
                });
            }
            
            String objName = NAMESPACE+'AI_Response_Processing__c';
            String parentFieldApi = NAMESPACE+'AI_Prompt_Component__c';
            String query = 'SELECT Id, '+String.join(fieldApiNames, ', ')+' FROM '+String.escapeSingleQuotes(objName)+' WHERE '+String.escapeSingleQuotes(parentFieldApi)+' =:recordId';
            List<sObject> records = Database.query(query);
            
            return new Map<String, Object>{
                'fields' => fields, 'records' => records
            };
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptComponentController', 'getPromptProcessingData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves response processing data based on the provided record ID and parent ID.
     *
     * @param recordId The unique identifier for the record.
     * @param parentId The identifier of the parent record, if applicable.
     * @return A ResponseProcessingWrapper containing the relevant data for processing the response.
     */
    @AuraEnabled
    public static ResponseProcessingWrapper getResponseProcessingData(String recordId, String parentId){
        try{
            ResponseProcessingWrapper wrap = new ResponseProcessingWrapper();
            if(String.isNotBlank(recordId)){
                List<AI_Response_Processing__c> lstOfProcessing = [SELECT Id, Destination_Field__c, Description__c, Action__c
                                                                FROM AI_Response_Processing__c WHERE Id =:recordId LIMIT 1];
                if(lstOfProcessing != null && !lstOfProcessing.isEmpty()){
                    wrap.action = lstOfProcessing.get(0).Action__c;
                    wrap.description = lstOfProcessing.get(0).Description__c;
                    wrap.destinationFieldApi = lstOfProcessing.get(0).Destination_Field__c;
                }
            }
            
            List<AI_Prompt_Component__c> lstOfComponents = [SELECT Id, AI_Prompt__r.Object__c FROM AI_Prompt_Component__c WHERE Id =:parentId LIMIT 1];
            if(lstOfComponents != null && !lstOfComponents.isEmpty()){
                String objName = lstOfComponents.get(0).AI_Prompt__r.Object__c;
                
                List<AIDataExtractionController.PicklistWrapper> fieldOptions = new List<AIDataExtractionController.PicklistWrapper>();
                Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
                Map<String, Schema.SObjectField> fieldMap = schemaMap.get(objName).getDescribe().fields.getMap();
                for(Schema.SObjectField sfield : fieldMap.Values()){
                    Schema.describeFieldResult dfield = sfield.getDescribe();
                    if(dfield.isAccessible() && dfield.isUpdateable()){
                        AIDataExtractionController.PicklistWrapper fw = new AIDataExtractionController.PicklistWrapper();
                        fw.label = dfield.getLabel();
                        fw.description = dfield.getname();
                        fw.value = dfield.getname();
                        fw.fieldType = String.valueOf(dfield.getType());
                        fieldOptions.add(fw);
                    }
                } 
                wrap.fieldOptions = fieldOptions;
            }
            return wrap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptComponentController', 'getResponseProcessingData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    public class ResponseProcessingWrapper{
        @AuraEnabled public String action{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String destinationFieldApi{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> fieldOptions{get;set;}
    }
    
}