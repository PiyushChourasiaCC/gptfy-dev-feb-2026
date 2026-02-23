/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptController {
    
    public static final String NAMESPACE = getNameSpace();
	
    /**
     * Retrieves the prompt data for the specified record ID, providing a PromptWrapper object containing the necessary data and details for processing the prompt.
     * 
     * @param recordId The ID of the record associated with the prompt data to be retrieved.
     * @return PromptWrapper A PromptWrapper object representing the prompt data for the specified record, ready for further processing or analysis.
     */
    @AuraEnabled
    public static PromptWrapper getPromptData(String recordId){
        try{
            PromptWrapper wrap = new PromptWrapper();
            GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
            List<AIDataExtractionController.PicklistWrapper> objects = new List<AIDataExtractionController.PicklistWrapper>();
            if(gptfySetting.Enable_for_Data_Cloud__c){
                objects.addAll(AIDataExtractionController.getSObjectsFromDataCloud(gptfySetting));
            }
            objects.addAll(AIDataExtractionController.getSObjects());
            objects.sort();
            wrap.objects = objects;
            wrap.typeOptions = getPickListValues(NAMESPACE+'AI_Prompt__c', NAMESPACE+'Type__c');
            wrap.connectOptions = getConnectionOptions();
            
            if(String.isNotBlank(recordId)){
                List<AI_Prompt__c> lstOfPrompts = [SELECT Id, Name, Object__c, AI_Data_Extraction_Mapping__c, 
                                                   AI_Data_Extraction_Mapping__r.Name, AI_Connection__c, Type__c
                                                    FROM AI_Prompt__c WHERE Id =:recordId];
                if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
                    AI_Prompt__c pmt = lstOfPrompts.get(0);
                    wrap.objectName = pmt.Object__c;
                    wrap.promptName = pmt.Name;
                    wrap.aiConnection = pmt.AI_Connection__c;
                    wrap.extractionMappingId = pmt.AI_Data_Extraction_Mapping__c;
                    wrap.extractionMappingName = pmt.AI_Data_Extraction_Mapping__c != null ? pmt.AI_Data_Extraction_Mapping__r.Name : '';
                    wrap.extractOptions = getExtractOptions(pmt.Object__c);
                    wrap.selectedType = pmt.Type__c;
                }
            }
            return wrap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getPromptData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves a list of objects for the merge operation based on the provided external ID, allowing for data merging or consolidation as needed.
     * 
     * @param extId The external ID used as a reference for retrieving the objects to be merged.
     * @return List<Object> A list of objects retrieved based on the provided external ID, ready for the merge operation or data consolidation.
     */
    @AuraEnabled
    public static List<Object> getMergeObjects(String extId){
        try{
            List<AI_Data_Extraction_Mapping__c> extMaps = [SELECT Id, Object_Name__c 
                                                            FROM AI_Data_Extraction_Mapping__c 
                                                            WHERE Id =:extId LIMIT 1];  
            List<Object> options = new List<Object>();
            if(extMaps != null && !extMaps.isEmpty()){
                AI_Data_Extraction_Mapping__c extMap = extMaps.get(0);
                options.add(new Map<String, Object>{
                    'label' => extMap.Object_Name__c, 
                    'value' => extMap.Id, 
                    'description' => extMap.Object_Name__c
                });
                for(AI_Data_Extraction_Detail__c detail : [SELECT Id, Object_Name__c, Object_Hierarchy__c 
                                                        FROM AI_Data_Extraction_Detail__c 
                                                        WHERE AI_Data_Extraction_Mapping__c =:extMap.Id
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
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getMergeObjects', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves a list of merge fields for the merge operation based on the provided detail ID, external ID, and object name, enabling data field selection for merging.
     * 
     * @param detailId The ID of the detail associated with the merge fields to be retrieved.
     * @param extId The external ID used as a reference for the merge operation.
     * @param objName The name of the object associated with the merge fields.
     * @return List<AIDataExtractionController.PicklistWrapper> A list of PicklistWrapper objects containing the merge fields retrieved based on the provided parameters, ready for data field selection in the merge operation.
     */
    @AuraEnabled
    public static List<AIDataExtractionController.PicklistWrapper> getMergeFields(String detailId, String extId, String objName){
        try{
            List<AIDataExtractionController.PicklistWrapper> options = new List<AIDataExtractionController.PicklistWrapper>();
            if(String.isNotBlank(extId) && String.isNotBlank(objName)){
                List<AI_Data_Extraction_Field__c> lstOfFields =  [SELECT Id, Label__c, Object__c, Field__c 
                                                                FROM AI_Data_Extraction_Field__c 
                                                                WHERE Type__c = 'FIELD' 
                                                                AND Object__c =:objName
                                                                AND AI_Data_Extraction_Mapping__c =:extId];
                if(lstOfFields != null && !lstOfFields.isEmpty()){
                    for(AI_Data_Extraction_Field__c field : lstOfFields){
                        AIDataExtractionController.PicklistWrapper opt = new AIDataExtractionController.PicklistWrapper();
                        opt.label = field.Label__c;
                        opt.value = field.Field__c;
                        opt.description = field.Field__c;                                         
                        options.add(opt);
                    }
                }
            }
            if(options != null && !options.isEmpty() && String.isNotBlank(detailId) && extId != detailId){
                Map<String, AI_Data_Extraction_Detail__c> mapOfDetail = new Map<String, AI_Data_Extraction_Detail__c>([
                    SELECT Id, Parent_Detail__c, RelationshipName__c 
                    FROM AI_Data_Extraction_Detail__c 
                    WHERE AI_Data_Extraction_Mapping__c =:extId
                ]);

                String rName = '';
                String currentDetailId = detailId;
                while(String.isNotBlank(currentDetailId) && mapOfDetail.containsKey(currentDetailId)){
                    rName = mapOfDetail.get(currentDetailId).RelationshipName__c + (String.isNotBlank(rName) ? ('.'+ rName) : '');
                    currentDetailId = mapOfDetail.get(currentDetailId).Parent_Detail__c;
                }
                if(String.isNotBlank(rName)){
                    for(AIDataExtractionController.PicklistWrapper opt : options){
                        opt.value = rName+'.'+opt.value;
                        opt.description = rName+'.'+opt.description;
                    }                
                }
            }
            return options;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getMergeObjects', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the connection options for the AI data extraction controller, providing a list of PicklistWrapper objects containing the available connection options.
     * 
     * @return List<AIDataExtractionController.PicklistWrapper> A list of PicklistWrapper objects representing the connection options for the AI data extraction controller, ready for user selection or processing.
     */
    @AuraEnabled
    public static List<AIDataExtractionController.PicklistWrapper> getConnectionOptions(){
        try{
            List<AIDataExtractionController.PicklistWrapper> typeOptions = new List<AIDataExtractionController.PicklistWrapper>();
            List<String> activeAIModal = new List<String>();
            for(AI_Card_Configuration__c cc : [SELECT Id, Name FROM AI_Card_Configuration__c where Enabled__c = true and Feature__c = :AIConstants.GPTfy_Card_Configuration_MDT_AMODL]){
                activeAIModal.add(cc.Name.toLowercase());
            }
            
            for(AI_Connection__c p : [SELECT Id, Name FROM AI_Connection__c ORDER BY Name LIMIT 50000]){
                if(activeAIModal.contains(p.Name.toLowercase())){
                    AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                    wrap.label = p.Name;
                    wrap.value = p.Id;
                    typeOptions.add(wrap);
                }
                
            }
            return typeOptions;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getConnectionOptions', '');
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Retrieves the record type options for the specified object name, providing a list of PicklistWrapper objects containing the available record type options.
     * 
     * @param objName The name of the Salesforce object associated with the record type options.
     * @return List<AIDataExtractionController.PicklistWrapper> A list of PicklistWrapper objects representing the available record type options for the specified object, ready for further processing or analysis.
     */
    @AuraEnabled
    public static List<AIDataExtractionController.PicklistWrapper> getRecordTypeOptions(String objName){
        try{
            List<AIDataExtractionController.PicklistWrapper> typeOptions = new List<AIDataExtractionController.PicklistWrapper>();
            if(String.isNotBlank(objName)){
                for(RecordType p : [SELECT Id, Name, DeveloperName FROM RecordType WHERE SObjectType =:objName AND isActive = True ORDER BY Name]){
                    AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                    wrap.label = p.Name;
                    wrap.value = p.DeveloperName;
                    typeOptions.add(wrap);
                }
            }
            return typeOptions;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getRecordTypeOptions', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the extraction options for the specified object, providing a list of PicklistWrapper objects containing the available options for data extraction.
     * 
     * @param objName The name of the Salesforce object associated with the extraction options.
     * @return List<AIDataExtractionController.PicklistWrapper> A list of PicklistWrapper objects representing the extraction options for the specified object, ready for further processing or analysis.
     */
    @AuraEnabled
    public static List<AIDataExtractionController.PicklistWrapper> getExtractOptions(String objName){
        try{
            List<AIDataExtractionController.PicklistWrapper> extractOptions = new List<AIDataExtractionController.PicklistWrapper>();
            if(String.isNotBlank(objName)){
                for(AI_Data_Extraction_Mapping__c p : [SELECT Id, Name FROM AI_Data_Extraction_Mapping__c WHERE Object_Name__c =:objName AND Status__c=:AIConstants.PMT_STATUS_ACTIVE ORDER BY Name]){
                    AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                    wrap.label = p.Name;
                    wrap.value = p.Id;
                    extractOptions.add(wrap);
                }
            }
            return extractOptions;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getExtractOptions', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the target field options for the specified object name, providing a list of PicklistWrapper objects containing the available options for target fields.
     * 
     * @param objName The name of the Salesforce object associated with the target field options.
     * @return List<AIDataExtractionController.PicklistWrapper> A list of PicklistWrapper objects representing the available options for target fields within the specified object, ready for further processing or analysis.
     */
    public static List<AIDataExtractionController.PicklistWrapper> getTargetFieldOptions(String objName){
        List<AIDataExtractionController.PicklistWrapper> options = new List<AIDataExtractionController.PicklistWrapper>();
        
        AIDataExtractionController.PicklistWrapper i_wrap = new AIDataExtractionController.PicklistWrapper();
        i_wrap.label = '---None---';
        i_wrap.value = '';
        options.add(i_wrap);
        
        if(String.isNotBlank(objName) ){
            
           /* GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
            if(gptfySetting.Enable_for_Data_Cloud__c){
                List<object> fieldList = AIDataExtractionController.getFieldsFromDataCloud(gptfySetting,objName);
                for (Object field : fieldList) {
                    Map<String, Object> fieldMap = (Map<String, Object>) field;
                	String fieldType = String.valueOf(fieldMap.get('type'));
                    if(fieldType == 'STRING'){	
                        AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                        wrap.label = String.valueOf(fieldMap.get('displayName'));
                        wrap.value = String.valueOf(fieldMap.get('name'));
                        //wrap.description = dfield.getname();
                        wrap.fieldType = fieldType;
                        options.add(wrap);
                    }
                }*/

            Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
            Map<String, Schema.SObjectField> fieldMap = schemaMap.get(objName).getDescribe().fields.getMap();
            for(Schema.SObjectField sfield : fieldMap.Values()){
                Schema.describeFieldResult dfield = sfield.getDescribe();
                String fieldType = String.valueOf(dfield.getType());
                if(dfield.isAccessible() && (fieldType == 'TEXTAREA' || fieldType == 'STRING')){	
                    AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                    wrap.label = dfield.getLabel();
                    wrap.value = dfield.getname();
                    wrap.description = dfield.getname();
                    wrap.fieldType = String.valueOf(dfield.getType());
                    options.add(wrap);
                }
            }
               
        }
        return options;
    }
    
    /**
     * Retrieves the object-based options for the specified Salesforce object, providing a PromptWrapper object containing the available options and details for further processing.
     * 
     * @param objName The name of the Salesforce object for which the object-based options are being retrieved.
     * @return PromptWrapper A PromptWrapper object representing the object-based options for the specified Salesforce object, ready for further processing or analysis.
     */
    @AuraEnabled
    public static PromptWrapper getObjectBasedOptions(String objName){
        try{
            PromptWrapper retWrap = new PromptWrapper();
            //retWrap.recordTypeOptions = getRecordTypeOptions(objName);   // comment for not use
            retWrap.extractOptions = getExtractOptions(objName);
            //retWrap.targetFieldOptions = getTargetFieldOptions(objName);  // comment for not use
            return retWrap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getObjectBasedOptions', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the profile options for further processing, providing a list of PicklistWrapper objects containing the profile options.
     * 
     * @return List<AIDataExtractionController.PicklistWrapper> A list of PicklistWrapper objects representing the profile options, ready for further processing or analysis.
     */
    public static List<AIDataExtractionController.PicklistWrapper> getProfileOptions(){
        List<AIDataExtractionController.PicklistWrapper> profileOptions = new List<AIDataExtractionController.PicklistWrapper>();
        for(Profile p : [SELECT Id, Name FROM Profile ORDER BY Name LIMIT 50000]){
            AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
            wrap.label = p.Name;
            wrap.value = p.Name;
            profileOptions.add(wrap);
        }
        return profileOptions;
    }
    
    /**
     * Retrieves the fields options for further processing, providing a list of PromptObjectFieldsWrapper objects containing the fields options.
     * 
     * @return List<PromptObjectFieldsWrapper> A list of Fields details representing the fields options, ready for further processing or analysis.
     */
    @AuraEnabled
    public static ObjectFieldsListWrapper getObjectFields(String objectName){
        try{
            
            ObjectFieldsListWrapper objfield = new ObjectFieldsListWrapper();
            List<PromptObjectFieldsWrapper> fields = new List<PromptObjectFieldsWrapper>();
            List<PromptObjectFieldsWrapper> orderByfields = new List<PromptObjectFieldsWrapper>();
            PromptObjectFieldsWrapper wrap1 = new PromptObjectFieldsWrapper();
            wrap1.label = '-- None --';
            wrap1.value = '';
            wrap1.type = '';
            
            fields.add(wrap1);
            orderByfields.add(wrap1);
            
            
            GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
            if(gptfySetting.Enable_for_Data_Cloud__c && objectName.endsWithIgnoreCase('__dlm')){
                Map<String, Object> metaDataObj = AIDataExtractionController.getDMOObjectFromDataCloud(gptfySetting,objectName);
                List<Object> fieldList = (List<Object>) metaDataObj.get('fields');
                for(Object fieldObj : fieldList){
                            Map<String, Object> field = (Map<String, Object>) fieldObj;
						 	PromptObjectFieldsWrapper wrap = new PromptObjectFieldsWrapper();
                    		String nameValue = (String) field.get('name'); 
                            String type = (String) field.get('type');
                    		type = (type == 'DATE_TIME')? 'DATETIME' : type;
                            wrap.label = (String) field.get('displayName');
                            wrap.value = nameValue;
                            wrap.type = String.valueOf(field.get('type'));
                            wrap.description = nameValue;
                            fields.add(wrap);
                    		orderByfields.add(wrap);
                }
                
            }else{
                Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
                Map<String, Schema.SObjectField> fieldMap = schemaMap.get(objectName).getDescribe().fields.getMap();
                for(Schema.SObjectField s : fieldMap.values()){
                        Schema.describeFieldResult dfield = s.getDescribe();
                        
                        if(dfield.isAccessible() && dfield.isFilterable() && String.valueOf(dfield.getType()) != 'ADDRESS'){
                            PromptObjectFieldsWrapper wrap = new PromptObjectFieldsWrapper();
                            wrap.label = dfield.getLabel();
                            wrap.value = dfield.getName();
                            wrap.type = String.valueOf(dfield.getType());
                            wrap.description = dfield.getName();
                            fields.add(wrap);
                        }
                        
                        if( dfield.isAccessible() && dfield.isSortable() ){
                            PromptObjectFieldsWrapper wrap = new PromptObjectFieldsWrapper();
                            wrap.label = dfield.getLabel();
                            wrap.value = dfield.getName();
                            wrap.type = String.valueOf(dfield.getType());
                            wrap.description = dfield.getName();
                            orderByfields.add(wrap);
                        }
                        
                    }
            }
            
            
            
            
            
            
            objfield.fields = fields;
            objfield.orderByFields = orderByfields;
            return objfield;
        }catch(Exception e){
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIPromptController', 'getObjectFields','');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
	
    /**
     * Saves the AI prompt based on the provided map of data, facilitating the storage of AI prompt-related information in the Salesforce platform.
     * 
     * @param data A map containing key-value pairs representing the data to be saved for the AI prompt.
     * @return String A status message indicating the result of the AI prompt saving operation, providing information about the success or failure of the operation.
     */
	@AuraEnabled    
    public static String saveAIPrompt(Map<String, Object> data){
        try{
            if(data != null && !data.isEmpty()){
                String recordId = String.valueOf(data.get('recordId'));
                String targetObject = String.valueOf(data.get('targetObject'));
                String aiConnection = String.valueOf(data.get('aiConnection'));
                String description = String.valueOf(data.get('description'));
                String promptName = String.valueOf(data.get('promptName'));
                String extractionMappingId = String.valueOf(data.get('extractionMappingId'));
                String selectedPurpose = String.valueOf(data.get('selectedPurpose'));
                String selectedType = String.valueOf(data.get('selectedType'));

                AI_Prompt__c pmt = new AI_Prompt__c();
                if(String.isNotBlank(recordId)){
                    pmt.Id = recordId;
                }else{
                    pmt.Purpose__c = selectedPurpose;
                }
                pmt.AI_Connection__c = aiConnection;
                pmt.Object__c = targetObject;
                pmt.Name = promptName;
                if(String.isBlank(extractionMappingId) || extractionMappingId == 'ADD_MAPPING'){
                    pmt.AI_Data_Extraction_Mapping__c = AIDataExtractionController.modifyMaster(new Map<String, String>{
                        'recordId' => null,
                        'mappingName' => promptName,
                        'targetObject' => targetObject,
                        'description' => description,
                        'objLabel' => null
                  	});
                }else{
                    pmt.AI_Data_Extraction_Mapping__c = extractionMappingId;
                }
                pmt.Status__c = 'Draft';
                pmt.Type__c = selectedType;
                if(pmt.Type__c != 'Text'){
                    pmt.Prompt_Command__c ='';
                }
                List<SObject> records = FLSCheck.getInstance().upsertDML(new List<AI_Prompt__c>{pmt});
                if(records != null && !records.isEmpty()){
                    return String.valueOf(records.get(0).get('Id'));
                }
        	}
        }catch(Exception e){
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIPromptController', 'saveAIPrompt','');
            throw new AuraHandledException(e.getMessage());
        } 
        return null;
    } 
    
    public class ObjectFieldsListWrapper{
        @AuraEnabled public List<PromptObjectFieldsWrapper> fields{get;set;}
        @AuraEnabled public List<PromptObjectFieldsWrapper> orderByFields{get;set;}
    }
    
    public class PromptObjectFieldsWrapper{
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public String type {get;set;}
        @AuraEnabled public String description {get;set;}
    }
    
    public class PromptWrapper{
        @AuraEnabled public String promptName{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String targetField{get;set;}
        @AuraEnabled public String aiConnection{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String selectedType{get;set;}
        @AuraEnabled public String promptCommand{get;set;}
        @AuraEnabled public String visibilityCondition{get;set;}
        @AuraEnabled public String howItWorks{get;set;}
        @AuraEnabled public Boolean includeFiles{get;set;}
        @AuraEnabled public Boolean allowUserInput{get;set;}
        @AuraEnabled public Decimal maxOutputTokens{get;set;}
        @AuraEnabled public Decimal temprature{get;set;}
        @AuraEnabled public Decimal topP{get;set;}
        @AuraEnabled public List<String> profileIds{get;set;}
        @AuraEnabled public List<String> groundingEthical{get;set;}
        @AuraEnabled public List<String> groundingContent{get;set;}
        @AuraEnabled public String localeAutomation{get;set;}
        @AuraEnabled public String localeGptfyConsole{get;set;}
        @AuraEnabled public List<String> recordTypeIds{get;set;}
        @AuraEnabled public List<String> selectedPurpose{get;set;}
        @AuraEnabled public String extractionMappingId{get;set;}
        @AuraEnabled public String extractionMappingName{get;set;}
        @AuraEnabled public Boolean appendTimestamp{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> objects{get;set;}
        @AuraEnabled public List<Object> mergeFieldObjectOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> profileOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> recordTypeOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> extractOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> purposeOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> connectOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> typeOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> targetFieldOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> groundingEthicalOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> groundingContentOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> localeAutomationContentOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> localeGptfyConsoleContentOptions{get;set;}
        
        @AuraEnabled public List<String> selectedUsage{get;set;}
        @AuraEnabled public List<String> selectedSites{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> usageOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> siteOptions{get;set;}
    }
    
    /**
     * Retrieves the picklist values for the specified object and field name, providing a list of AIDataExtractionController.PicklistWrapper objects containing the picklist values.
     * 
     * @param objName The name of the Salesforce object associated with the picklist values.
     * @param fieldName The name of the field within the specified object for which the picklist values are being retrieved.
     * @return List<AIDataExtractionController.PicklistWrapper> A list of AIDataExtractionController.PicklistWrapper objects representing the picklist values for the specified object and field, ready for further processing or analysis.
     */
    @AuraEnabled
    public static List<AIDataExtractionController.PicklistWrapper> getPickListValues(String objName, String fieldName){
       try{
            List<AIDataExtractionController.PicklistWrapper> lst = new List<AIDataExtractionController.PicklistWrapper>();
            Schema.SObjectType objSobjectType = Schema.getGlobalDescribe().get(objName);
            Schema.DescribeSObjectResult objDescribeSobject = objSobjectType.getDescribe();
            Map<String, Schema.SObjectField> mapFields = objDescribeSobject.fields.getMap();
            
            List<Schema.PicklistEntry> lstPickListValues = mapFields.get(fieldName).getDescribe().getPickListValues();
            for(Schema.PicklistEntry objPickList : lstPickListValues){
                AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                wrap.value = objPickList.getValue();
                wrap.label = objPickList.getLabel();
                lst.add(wrap);
            }
            return lst;
        }catch(Exception e){
            gptfyException.log(e, AIConstants.APPLICATION_NAME, '', 'AIPromptController', 'getPickListValues','');
            throw new AuraHandledException(e.getMessage());
        }
    }
	
    /**
     * Retrieves the namespace used within the Salesforce environment, providing the namespace string for further reference or processing.
     * 
     * @return String The namespace used within the Salesforce environment, which may be utilized for identifying specific components or customizations.
     */
    public static String getNameSpace(){
        string np = '';
        try{
            String cName = 'AIPromptController' ;
            String query = 'select NamespacePrefix from ApexClass where Name =\''+cName +'\' limit 1 ';
            ApexClass  queryResult = Database.query(query);
            np= queryResult.NamespacePrefix ;
            if(np == null){
                np = '';
            }else{
                np= np+'__';
            }
        }catch(Exception ex){
        }
        return np;
    }
    
}