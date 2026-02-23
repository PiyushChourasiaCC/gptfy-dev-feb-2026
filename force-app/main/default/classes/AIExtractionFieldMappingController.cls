/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIExtractionFieldMappingController {
    
    public static Map<String, Schema.SObjectType> schemaMap;
    static{
        schemaMap = Schema.getGlobalDescribe();
    }
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    
    /**
     * Retrieves the field mappings for the specified record ID and object name, providing a map of field names and their corresponding mapped objects or values.
     * 
     * @param recordId The ID of the record associated with the field mappings.
     * @param objectName The name of the object for which the field mappings are being retrieved.
     * @return Map<String, Object> A map where the keys represent field names, and the values contain the corresponding object mappings or values for the specified record and object.
     */
    @AuraEnabled
    public static Map<String, Object> getFieldMappings(String recordId, String objectName){
        
        System.debug('getFieldMapping : recordId: '+recordId+', '+objectName);
        try{
            List<PicklistAttributeWrapper> maskScopeOption = new List<PicklistAttributeWrapper>();
            List<PicklistAttributeWrapper> textAreaMaskScopeOption = new List<PicklistAttributeWrapper>();
            
            PicklistAttributeWrapper noneOption = new PicklistAttributeWrapper();
            noneOption.label = '-- None --';
            noneOption.value = '';
            
            maskScopeOption.add(noneOption);
            textAreaMaskScopeOption.add(noneOption);
            
            maskScopeOption.addAll(getPickListValues(NAMESPACE+'AI_Data_Extraction_Field__c', NAMESPACE+'Masking_Scope__c'));
            maskScopeOption = removeSpecifiOption(maskScopeOption, 'Specific Patterns');
            textAreaMaskScopeOption.addAll(getPickListValues(NAMESPACE+'AI_Data_Extraction_Field__c', NAMESPACE+'Masking_Scope__c'));
            textAreaMaskScopeOption = removeSpecifiOption(textAreaMaskScopeOption, 'Entire Value');
            
            List<FieldWrapper> fields = new List<FieldWrapper>();
            Map<String, Object> data = new Map<String, Object>();
            
            
            // @Jira 4487 : Data Context Mapping with Data Cloud Integration
            GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
            if(gptfySetting.Enable_for_Data_Cloud__c && objectName.contains('__dlm')){
                  Map<String, Object> metadata = AIDataExtractionController.getDMOObjectFromDataCloud(gptfySetting,objectName);
                  List<Object> dcfields = (List<Object>) metadata.get('fields');
                    for(Object f: dcfields){
                        Map<String, Object> metadataFields = (Map<String, Object>) f;
                        FieldWrapper fw = new FieldWrapper();
                        fw.fieldValue = null;
                        fw.fieldName = String.valueOf(metadataFields.get('name'));
                        fw.label = String.valueOf(metadataFields.get('displayName'));
                        fw.displayLabel = fw.label+' ('+fw.fieldName+')';
                        fw.fieldType = String.valueOf(metadataFields.get('type'));
                        fw.maskSopeOptions = maskScopeOption;
                        fw.selectedMaskingOption = '';
                        fw.sendToAI = false;
                        fw.anonymizeWith = '';
                        fields.add(fw);
                    }
            }else{
                Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
                Map<String, Schema.SObjectField> fieldMap = schemaMap.get(objectName).getDescribe().fields.getMap();
                
                for(Schema.SObjectField sfield : fieldMap.Values()){
                    Schema.describeFieldResult dfield = sfield.getDescribe();
                    if(dfield.isAccessible()){
                        FieldWrapper fw = new FieldWrapper();
                        fw.fieldValue = null;
                        fw.fieldName = dfield.getname();
                        fw.label = dfield.getLabel();
                        fw.displayLabel = fw.label+' ('+fw.fieldName+')';
                        fw.fieldType = String.valueOf(dfield.getType());
                        fw.maskSopeOptions = (fw.fieldType == 'TEXTAREA' ? textAreaMaskScopeOption : maskScopeOption);
                        fw.selectedMaskingOption = '';
                        fw.sendToAI = false;
                        fw.anonymizeWith = '';
                        fields.add(fw);
                    }
                } 
            }
            
            
            
            fields.sort();
            fields = getExistingMappings(recordId, objectName, fields);
            data.put('fields', fields);
            data.put('anonymizeWithOptions', getPickListValues(NAMESPACE+'AI_Data_Extraction_Field__c', NAMESPACE+'Anonymize_With__c'));
            return data;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIExtractionFieldMappingController', 'getFieldMappings', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Removes a specific option from the provided list of PicklistAttributeWrapper options based on the given option value.
     * 
     * @param options A list of PicklistAttributeWrapper options containing the picklist options to be processed.
     * @param optionValue The value of the option to be removed from the list.
     * @return List<PicklistAttributeWrapper> A list of PicklistAttributeWrapper options with the specified option removed, ready for further processing.
     */
    private static List<PicklistAttributeWrapper> removeSpecifiOption(List<PicklistAttributeWrapper> options, String optionValue){
        List<PicklistAttributeWrapper> newOptions = options;
        for(Integer i = 0; i < newOptions.size(); i++){
            if(newOptions[i].value == optionValue){
                newOptions.remove(i);
                break;
            }
        }
        return newOptions;
    }
    
    /**
     * Retrieves the existing field mappings for the specified record ID, object name, and list of field wrappers, providing information about the mappings.
     * 
     * @param recordId The ID of the record associated with the field mappings.
     * @param objectName The name of the object for which the field mappings are being retrieved.
     * @param fields A list of FieldWrapper objects containing information about the fields and their mappings.
     * @return List<FieldWrapper> A list of FieldWrapper objects representing the existing field mappings for the specified record and object, ready for further processing or analysis.
     */
    public static List<FieldWrapper> getExistingMappings(String recordId, String objectName, List<FieldWrapper> fields){
        
        List<PicklistAttributeWrapper> maskScopeOption = new List<PicklistAttributeWrapper>();
        List<PicklistAttributeWrapper> textAreaMaskScopeOption = new List<PicklistAttributeWrapper>();
        
        PicklistAttributeWrapper noneOption = new PicklistAttributeWrapper();
        noneOption.label = '-- None --';
        noneOption.value = '';
        
        maskScopeOption.add(noneOption);
        textAreaMaskScopeOption.add(noneOption);
        
        maskScopeOption.addAll(getPickListValues(NAMESPACE+'AI_Data_Extraction_Field__c', NAMESPACE+'Masking_Scope__c'));
        maskScopeOption = removeSpecifiOption(maskScopeOption, 'Specific Patterns');
        textAreaMaskScopeOption.addAll(getPickListValues(NAMESPACE+'AI_Data_Extraction_Field__c', NAMESPACE+'Masking_Scope__c'));
        textAreaMaskScopeOption = removeSpecifiOption(textAreaMaskScopeOption, 'Entire Value');
        
        Map<String, AI_Data_Extraction_Field__c> mapOfFieldApiToMapping = new Map<String, AI_Data_Extraction_Field__c>();
        for(AI_Data_Extraction_Field__c fm : [SELECT Id, Field__c, Object__c, Type__c, AI_Data_Extraction_Mapping__c, Label__c,
                                              Send_To_AI__c, Anonymize_With__c, Masking_Scope__c, Field_Type__c, Formula__c 
                                              FROM AI_Data_Extraction_Field__c
                                              WHERE AI_Data_Extraction_Mapping__c =:recordId
                                              AND Field__c != NULL 
                                              AND Object__c =:objectName 
                                              AND Type__c = 'FIELD']){
        	if(!mapOfFieldApiToMapping.containsKey(fm.Field__c.toLowerCase())){
            	mapOfFieldApiToMapping.put(fm.Field__c.toLowerCase(), fm);                                            
        	}
        }
        
        List<FieldWrapper> activeFields = new List<FieldWrapper>();
        List<FieldWrapper> nonActiveFields = new List<FieldWrapper>();
        
        for(FieldWrapper fw : fields){
            if(!mapOfFieldApiToMapping.isEmpty() && mapOfFieldApiToMapping.containsKey(fw.fieldName.toLowerCase())){
                AI_Data_Extraction_Field__c fm = mapOfFieldApiToMapping.get(fw.fieldName.toLowerCase());
                fw.fieldValue = fm.Id;
                fw.label = fm.Label__c;
                fw.sendToAI = fm.Send_To_AI__c;
                fw.anonymizeWith = fm.Anonymize_With__c;
                fw.fieldType = fm.Field_Type__c;
                fw.formula = fm.Formula__c;
                fw.selectedMaskingOption = String.isNotBlank(fm.Masking_Scope__c) ? fm.Masking_Scope__c : '';
                fw.maskSopeOptions = (fw.fieldType == 'TEXTAREA' ? textAreaMaskScopeOption : maskScopeOption);
                activeFields.add(fw);
                mapOfFieldApiToMapping.remove(fw.fieldName.toLowerCase());
            }else{
                nonActiveFields.add(fw);
            }
        }
        
        if(!mapOfFieldApiToMapping.isEmpty()){
            for(String fieldApi : mapOfFieldApiToMapping.keySet()){
                AI_Data_Extraction_Field__c fm = mapOfFieldApiToMapping.get(fieldApi);
                FieldWrapper fw = new FieldWrapper();
                fw.label = fm.Label__c;
                fw.fieldName = fm.Field__c;
                fw.displayLabel = fm.Label__c+' ('+fw.fieldName+')';
                fw.fieldValue = fm.Id;
                fw.sendToAI = fm.Send_To_AI__c;
                fw.formula = fm.Formula__c;
                fw.anonymizeWith = fm.Anonymize_With__c;
                fw.fieldType = fm.Field_Type__c;
                fw.selectedMaskingOption = String.isNotBlank(fm.Masking_Scope__c) ? fm.Masking_Scope__c : '';
                fw.maskSopeOptions = (fw.fieldType == 'TEXTAREA' ? textAreaMaskScopeOption : maskScopeOption);
                activeFields.add(fw);
            }
        }
        
        List<FieldWrapper> orderedFields = new List<FieldWrapper>();
        if(!activeFields.isEmpty()){
            orderedFields.addAll(activeFields);
        }if(!nonActiveFields.isEmpty()){
            orderedFields.addAll(nonActiveFields);
        }
        
        return orderedFields;
    }
    
    /**
     * Saves the field mappings for the specified record ID, object name, and list of FieldWrapper objects, updating the mappings for future reference.
     * 
     * @param recordId The ID of the record associated with the field mappings to be saved.
     * @param objectName The name of the object for which the field mappings are being saved.
     * @param fields A list of FieldWrapper objects containing the updated field mappings to be saved.
     */
    @AuraEnabled
    public static void saveFieldMappings(String recordId, String objectName, List<FieldWrapper> fields){ 
        try{
            List<AI_Data_Extraction_Field__c> fieldsToInsert = new List<AI_Data_Extraction_Field__c>();
            List<AI_Data_Extraction_Field__c> fieldsToUpdate = new List<AI_Data_Extraction_Field__c>();
            List<AI_Data_Extraction_Field__c> fieldsToDelete = new List<AI_Data_Extraction_Field__c>();
            for(FieldWrapper fw : fields){
                AI_Data_Extraction_Field__c field = new AI_Data_Extraction_Field__c(
                    Field__c = String.valueOf(fw.fieldName),
                    Label__c = String.valueOf(fw.label),
                    Type__c = 'FIELD',
                    Object__c = objectName,
                    Send_To_AI__c = (fw.sendToAI != null && fw.sendToAI ? true : false),
                    Formula__c = fw.formula,
                    Anonymize_With__c = (String.isNotBlank(fw.selectedMaskingOption) ? (fw.selectedMaskingOption == 'Entire Value' ? fw.anonymizeWith : '') : ''),
                    Masking_Scope__c = String.valueOf(fw.selectedMaskingOption),
                    Field_Type__c = String.valueOf(fw.fieldType)
                );
                if(field.Send_To_AI__c || String.isNotBlank(field.Masking_Scope__c)){
                    if(String.isNotBlank(String.valueOf(fw.fieldValue))){
                        field.Id = String.valueOf(fw.fieldValue);
                        fieldsToUpdate.add(field);
                    }else{
                        field.AI_Data_Extraction_Mapping__c = recordId;
                        fieldsToInsert.add(field);
                    }
                }else if(String.isNotBlank(String.valueOf(fw.fieldValue))){
                    field.Id = String.valueOf(fw.fieldValue);
                    fieldsToDelete.add(field);
                }
            }
            
            Boolean newFieldMappingsInserted = false;
            List<sObject> fieldsToUpsert = new List<sObject>();
            if(!fieldsToInsert.isEmpty()){
                SObject [] inList = FLSCheck.getInstance().insertCheck(fieldsToInsert);
                if(!inList.isEmpty()){
                    fieldsToUpsert.addAll(inList);
                    newFieldMappingsInserted = true;
                }
            }
            
            if(!fieldsToUpdate.isEmpty()){  
                SObject [] upList = FLSCheck.getInstance().updateCheck(fieldsToUpdate);
                if(!upList.isEmpty()){
                    fieldsToUpsert.addAll(upList);
                }
            }
    
            if(!fieldsToUpsert.isEmpty()){
                fieldsToUpsert = FLSCheck.getInstance().upsertDML(fieldsToUpsert);
            }
            
            if(!fieldsToDelete.isEmpty()){
                FLSCheck.getInstance().deleteDML(fieldsToDelete);
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIExtractionFieldMappingController', 'saveFieldMappings', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    public class FieldWrapper implements Comparable{
        @AuraEnabled public String fieldName{get;set;}
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public Object fieldValue{get;set;}
        @AuraEnabled public String displayLabel{get;set;} 
        @AuraEnabled public String formula{get;set;} 
        @AuraEnabled public String externalParameter{get;set;}
        @AuraEnabled public Integer fieldLength{get;set;}
        @AuraEnabled public String fieldType{get;set;}
        @AuraEnabled public String selectedMaskingOption{get;set;}
        @AuraEnabled public List<PicklistAttributeWrapper> maskSopeOptions{get;set;}
        
        @AuraEnabled public Boolean sendToAI{get;set;} 
        @AuraEnabled public Boolean scanForPII{get;set;} 
        @AuraEnabled public String anonymizeWith{get;set;} 
        
        public Integer compareTo(Object objToCompare) {
        	return label.compareTo(((FieldWrapper)objToCompare).label);
        }
    }
    
    public class PicklistAttributeWrapper implements Comparable{
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String relationshipName{get;set;}
        @AuraEnabled public String parentName{get;set;}
        @AuraEnabled public String fieldType{get;set;}
        @AuraEnabled public String selectedMaskingOption{get;set;}
        @AuraEnabled public List<PicklistAttributeWrapper> maskSopeOptions{get;set;}
        
        public Integer compareTo(Object objToCompare) {
        	return label.compareTo(((PicklistAttributeWrapper)objToCompare).label);
        }
    }
    
    /**
     * Retrieves the picklist values for the specified object and field name, providing a list of PicklistAttributeWrapper objects containing the picklist values.
     * 
     * @param objName The name of the Salesforce object associated with the picklist values.
     * @param fieldName The name of the field within the specified object for which the picklist values are being retrieved.
     * @return List<PicklistAttributeWrapper> A list of PicklistAttributeWrapper objects representing the picklist values for the specified object and field, ready for further processing or analysis.
     */
    @AuraEnabled
    public static List<PicklistAttributeWrapper> getPickListValues(String objName, String fieldName){
        try{
            List<PicklistAttributeWrapper> lst = new List<PicklistAttributeWrapper>();
            Schema.SObjectType objSobjectType = Schema.getGlobalDescribe().get(objName);
            Schema.DescribeSObjectResult objDescribeSobject = objSobjectType.getDescribe();
            Map<String, Schema.SObjectField> mapFields = objDescribeSobject.fields.getMap();
            
            List<Schema.PicklistEntry> lstPickListValues = mapFields.get(fieldName).getDescribe().getPickListValues();
            for(Schema.PicklistEntry objPickList : lstPickListValues){
                PicklistAttributeWrapper wrap = new PicklistAttributeWrapper();
                wrap.value = objPickList.getValue();
                wrap.label = objPickList.getLabel();
                lst.add(wrap);
            }
            return lst;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIExtractionFieldMappingController', 'getPickListValues', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the parent fields for the specified object, considering lookup fields if indicated, and provides a list of PicklistAttributeWrapper objects containing the parent fields.
     * 
     * @param objName The name of the Salesforce object associated with the parent fields.
     * @param onlyLookupFields A boolean value indicating whether to include only lookup fields in the retrieval process.
     * @return List<PicklistAttributeWrapper> A list of PicklistAttributeWrapper objects representing the parent fields for the specified object, considering the provided lookup field parameter, and ready for further processing or analysis.
     */
    @AuraEnabled
    public static List<PicklistAttributeWrapper> getParentFields(String objName, Boolean onlyLookupFields){
        try{
            List<PicklistAttributeWrapper> maskScopeOption = new List<PicklistAttributeWrapper>();
            List<PicklistAttributeWrapper> textAreaMaskScopeOption = new List<PicklistAttributeWrapper>();
            
            PicklistAttributeWrapper noneOption = new PicklistAttributeWrapper();
            noneOption.label = '-- None --';
            noneOption.value = '';
            
            maskScopeOption.add(noneOption);
            textAreaMaskScopeOption.add(noneOption);
            
            maskScopeOption.addAll(getPickListValues(NAMESPACE+'AI_Data_Extraction_Field__c', NAMESPACE+'Masking_Scope__c'));
            maskScopeOption = removeSpecifiOption(maskScopeOption, 'Specific Patterns');
            textAreaMaskScopeOption.addAll(getPickListValues(NAMESPACE+'AI_Data_Extraction_Field__c', NAMESPACE+'Masking_Scope__c'));
            textAreaMaskScopeOption = removeSpecifiOption(textAreaMaskScopeOption, 'Entire Value');
            
            List<PicklistAttributeWrapper> lst = new List<PicklistAttributeWrapper>();
            Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
            Map<String, Schema.SObjectField> fieldMap = schemaMap.get(objName).getDescribe().fields.getMap();

            for(Schema.SObjectField sfield : fieldMap.Values()){
                Schema.describeFieldResult dfield = sfield.getDescribe();
                if(dfield.isAccessible()){
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
                        pv.maskSopeOptions = (pv.fieldType == 'TEXTAREA' ? textAreaMaskScopeOption : maskScopeOption);
                        pv.selectedMaskingOption = '';
                    }
                    if(types == null || types.isEmpty() || types.size() <= 1){
                        if((String.isNotBlank(pv.parentName) && String.isNotBlank(pv.relationshipName)) || String.isBlank(pv.parentName)){
                            if(types != null && !types.isEmpty() && onlyLookupFields != null && onlyLookupFields){
                                lst.add(pv);
                            }else if(onlyLookupFields == null || !onlyLookupFields){
                                lst.add(pv);
                            }
                        }                    
                    }
                }
            } 
            if(!lst.isEmpty()){
                lst.sort();
            }
            return lst;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIExtractionFieldMappingController', 'getParentFields', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<PicklistAttributeWrapper> validateFormula(String objName, String returnType, String formulaStr){
        try{
            Schema.SObjectType objType = schemaMap.get(objName);

            if(objType == null){
                throw new AuraHandledException('Invalid object name: ' + objName);
            }

            // Get the field map for validation
            Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

            // Build the formula instance
            FormulaEval.FormulaInstance ff = Formula.builder()
                .withType(objType)
                .withReturnType(FormulaEval.FormulaReturnType.valueOf(returnType))
                .withFormula(formulaStr)
                .build();

            // Get referenced fields from the formula
            Set<String> referencedFields = ff.getReferencedFields();

            // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
            // Validate that all referenced fields exist and are accessible
            List<String> inaccessibleFields = new List<String>();
            List<String> nonExistentFields = new List<String>();

            for(String fieldName : referencedFields){
                Schema.SObjectField field = fieldMap.get(fieldName);

                if(field == null){
                    nonExistentFields.add(fieldName);
                }else{
                    Schema.DescribeFieldResult dfr = field.getDescribe();
                    if(!dfr.isAccessible()){
                        inaccessibleFields.add(fieldName);
                    }
                }
            }

            // Throw error if there are invalid fields
            if(!nonExistentFields.isEmpty()){
                String errorMsg = 'The following fields do not exist on ' + objName + ': ' + String.join(nonExistentFields, ', ');
                throw AIUtility.getMessageAuraHandledException(errorMsg);
            }

            if(!inaccessibleFields.isEmpty()){
                String errorMsg = 'The following fields are not accessible: ' + String.join(inaccessibleFields, ', ');
                throw AIUtility.getMessageAuraHandledException(errorMsg);
            }

            // Test evaluate with a new empty sObject instance
            SObject obj = objType.newSObject();
            ff.evaluate(obj);

            // Return masking scope options
            List<PicklistAttributeWrapper> maskScopeOption = new List<PicklistAttributeWrapper>();
            PicklistAttributeWrapper noneOption = new PicklistAttributeWrapper();
            noneOption.label = '-- None --';
            noneOption.value = '';
            maskScopeOption.add(noneOption);

            maskScopeOption.addAll(getPickListValues(NAMESPACE+'AI_Data_Extraction_Field__c', NAMESPACE+'Masking_Scope__c'));
            maskScopeOption = removeSpecifiOption(maskScopeOption, 'Specific Patterns');
            return maskScopeOption;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIExtractionFieldMappingController', 'validateFormula', '');
            throw AIUtility.getMessageAuraHandledException(e.getMessage());
        }
    }
    
}