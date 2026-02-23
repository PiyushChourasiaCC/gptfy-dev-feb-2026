/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 09-19-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptValidationController {
	
    public static Map<String, Schema.SObjectType> schemaMap;
    List<String> messages;
    static {
        schemaMap = Schema.getGlobalDescribe();
    }
    
    public AIPromptValidationController(){
        messages = new List<String>();
    }
    
    /**
     * Validates the given AI prompt and its associated components.
     *
     * @param pmt The AI prompt to be validated.
     * @param lstOfComponents The list of AI prompt components associated with the prompt.
     * @return A list of error messages indicating validation issues, or an empty list if the prompt is valid.
     * @Jira V2-7132
     */
    public List<String> validatePrompts(AI_Prompt__c pmt, List<AI_Prompt_Component__c> lstOfComponents){
        try{
            validatePrompt(pmt);
            validateDataExtraction(pmt.AI_Data_Extraction_Mapping__c, pmt.Object__c);
            List<AI_Data_Extraction_Detail__c> detailList = validateDataExtractionDetails(pmt.AI_Data_Extraction_Mapping__c);
            validateDataExtractionFields(pmt.AI_Data_Extraction_Mapping__c);
            Map<String, String> mapOfExtractionIdToObjName = validatePromptComponents(pmt, lstOfComponents, detailList);
            validatePromptActions(pmt);
            validateResponseValidation(pmt);
            return messages;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptValidationController', 'validatePrompts', '');
            return null;
        }
    }

    /**
     * Validates the given Data Extraction Mapping and its associated fields.
     *
     * @param deMappingId The AI prompt to be validated.
     * @return A list of error messages indicating validation issues, or an empty list if the Data Extraction Mapping is valid.
     */
    public List<String> validateDataExtractionMapping(String deMappingId){
        try{
            validateDataExtraction(deMappingId, null);
            List<AI_Data_Extraction_Detail__c> detailList = validateDataExtractionDetails(deMappingId);
            validateDataExtractionFields(deMappingId);
            return messages;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptValidationController', 'validateDataExtractionMapping', '');
            return null;
        }
    }
    
    /**
     * Validates an AI prompt object.
     * This method checks the properties of the given AI_Prompt__c object to ensure
     * it meets certain criteria or conditions. If the prompt is invalid, appropriate
     * actions or error handling should be implemented.
     *
     * @param pmt The AI_Prompt__c object to be validated.
     *            This object represents a prompt in an AI system and contains
     *            relevant information that needs to be validated.
     * @Jira V2-7132
     */
    public void validatePrompt(AI_Prompt__c pmt){
        if(!schemaMap.containsKey(pmt.Object__c)){
            addMessage('The selected object on prompt ('+pmt.Object__c+') does not exist.');
        }if(pmt.AI_Data_Extraction_Mapping__c == null){
            addMessage('Data Extraction Mapping cannot be blank on the prompt.');
        }if(pmt.AI_Connection__c == null){
            addMessage('Connection cannot be blank on the prompt.');
        }if(pmt.AI_Model_File_Processing__c == null && pmt.Include_Files__c){
            addMessage('"AI Model - File Procesing" cannot be blank when "Include Files" is checked.');
        }
        // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
        if(pmt.Agentic_Function_Class__c == null && pmt.Type__c == AIConstants.AI_PMT_TYPE_AGENTIC){
            addMessage('"Agentic Function Class" cannot be blank on the prompt.');
        }else if(String.isNotBlank(pmt.Agentic_Function_Class__c) && pmt.Type__c == AIConstants.AI_PMT_TYPE_AGENTIC && (Type.forName('',pmt.Agentic_Function_Class__c) == null || String.valueOf(Type.forName('',pmt.Agentic_Function_Class__c)) == 'System.Test')){
            addMessage('"Agentic Function Class" is invalid class name on the prompt. Please check the "'+pmt.Agentic_Function_Class__c+'" class name and try again.');
        }
        /*#JIRA-4986:Prompt Action Framework*/
        /*if(String.isNotBlank(pmt.Target_Field__c) && !isFieldExists(pmt.Object__c, pmt.Target_Field__c)){
            addMessage('Selected Target field does not exist on the Object.');
        }*/
        checkFieldBindings(pmt);
        if(String.isNotBlank(pmt.Visibility_Condition__c) && !isValidVisibilityCondition(pmt.Object__c,pmt.Visibility_Condition__c)){
            addMessage('Visibility Condition specified on the Prompt is incorrect.');
        }
    }
    
    public void validateDataSource(AI_Data_Extraction_Mapping__c ext){
        List<AI_Data_Source__c> lst = [SELECT Id, Name, Connector_Class__c 
                                       FROM AI_Data_Source__c 
                                       WHERE Id =:ext.AI_Data_Source__c];
        if(lst != null && !lst.isEmpty()){
            AI_Data_Source__c ds = lst.get(0);
            if(String.isNotBlank(ds.Connector_Class__c)){
                List<AI_Card_Configuration__c> mdt = [SELECT Id 
                                                      FROM AI_Card_Configuration__c 
                                                      WHERE Enabled__c = true 
                                                      AND Name =:ds.Name
                                                      AND Feature__c =:AIConstants.GPTFY_CARD_CONFIGURATION_MDT_APIDS];
                if(mdt != null && !mdt.isEmpty()){
                    //do-nothing
                }else{
                    addMessage('Selected API Data Connection is not Active.');
                }	
            }else{
                addMessage('Selected API Data Connection does not have a Connector Class.');
            }
        }else{
            addMessage('Selected API Data Connection does not exist.');
        }
    }
    
     /**
     * Validate the where clause condition.
     *
     * @param objName              The Object Name to validate.
     * @param whereClause  The whereclause of objName to validate.
     * @return              The boolean value is valid or not.
     */
    @AuraEnabled
    public static Boolean isValidVisibilityCondition(String objName, String whereClause){
        try {
            whereClause = AIUtility.getFormattedWhereClause(whereClause,NULL,NULL,true);
            String query = 'SELECT Id FROM '+String.escapeSingleQuotes(objName)+String.escapeSingleQuotes(whereClause);
            query = query.replace('\\\'','\'');
            Database.query(query.replace('\\\'','\''));
        	return true;
        }catch(QueryException e){
            return false;
        }catch(Exception e){
            return false;
        }
    }
    
    
    /**
     * Validates the components of a prompt and associated data extraction details.
     *
     * @param pmt              The AI Prompt to validate.
     * @param lstOfComponents  The list of AI Prompt Components to validate.
     * @param detailList       The list of AI Data Extraction Details to validate.
     * @return                 A map containing validation results for each component. 
     *                         The key is the component's ID, and the value is a validation message.
     */
    public Map<String, String> validatePromptComponents(AI_Prompt__c pmt, List<AI_Prompt_Component__c> lstOfComponents, List<AI_Data_Extraction_Detail__c> detailList){
        Map<String, String> mapOfExtractionIdToObjName = new Map<String, String>();
        mapOfExtractionIdToObjName.put(pmt.AI_Data_Extraction_Mapping__c, pmt.Object__c);
        if(detailList != null && !detailList.isEmpty()){
            for(AI_Data_Extraction_Detail__c detail : detailList){
            	mapOfExtractionIdToObjName.put(detail.Id, detail.Object_Name__c);
        	}
        }
        if(pmt.Type__c == 'JSON' && (lstOfComponents == null || lstOfComponents.isEmpty())){
            addMessage('Prompt components are required for JSON type prompts.');
        }
        for(AI_Prompt_Component__c pc : lstOfComponents){
            if(String.isBlank(pc.Data_Extraction_Id__c) || !mapOfExtractionIdToObjName.containsKey(pc.Data_Extraction_Id__c)){
                addMessage('Prompt component '+pc.Name+' does not have correct Data Extraction Id. Please delete the component and add again.');
            }
        }
        return mapOfExtractionIdToObjName;
    }
    
    /**
     * Validates the data extraction for an AI Prompt.
     * 
     * This method takes an AI_Prompt__c object as a parameter and performs
     * validation checks on the data extraction. It ensures that the provided
     * AI Prompt contains valid data or meets specific criteria.
     * 
     * @param pmt The AI_Prompt__c object representing the AI Prompt to be validated.
     * 
     * Note: Add specific details about the validation criteria and any
     *       additional considerations related to the data extraction process.
     */
    public void validateDataExtraction(String deMappingId, String promptObject){
        AI_Data_Extraction_Mapping__c deMapping = [SELECT Id, Object_Name__c, AI_Data_Source__c, 
                                                   Apex_Security_Layer__c, Apex_Security_Layer__r.Status__c
                                                   FROM AI_Data_Extraction_Mapping__c 
                                                   WHERE Id =:deMappingId LIMIT 1];
        if(deMapping != null){
            if(String.isBlank(deMapping.Object_Name__c)){
                addMessage('The object on Data Extraction Mapping cannot be blank.');
            }else{
                if(!schemaMap.containsKey(deMapping.Object_Name__c)){
            		addMessage('The selected object on Data Extraction Mapping ('+deMapping.Object_Name__c+') does not exist.');
                }if(String.isNotBlank(promptObject) && !deMapping.Object_Name__c.equalsIgnoreCase(promptObject)){
                    addMessage('The selected object on Prompt and Data Extraction Mapping cannot be different.');
                }
        	}
            if(deMapping.AI_Data_Source__c != null){
                validateDataSource(deMapping);
            }
            if(deMapping.Apex_Security_Layer__c != null && deMapping.Apex_Security_Layer__r.Status__c != AIConstants.SEC_LAYER_STATUS_ACTIVE){
                addMessage('The selected Apex Security Layer is not Active.');
            }
        }
    }
    
    /**
     * Validates the data extraction details for a given AI Prompt.
     *
     * @param pmt The AI Prompt for which data extraction details are to be validated.
     * @return A list of AI_Data_Extraction_Detail__c objects representing the validated details.
     */
    public List<AI_Data_Extraction_Detail__c> validateDataExtractionDetails(String deMappingId){
        if(deMappingId != null){
            List<AI_Data_Extraction_Detail__c> detailList = [SELECT Object_Name__c, Where_Clause__c, RelationshipField__c, RelationshipName__c, Type__c 
                                                             FROM AI_Data_Extraction_Detail__c 
                                                             WHERE AI_Data_Extraction_Mapping__c =:deMappingId];
            for(AI_Data_Extraction_Detail__c detail : detailList){
                if(detail.Type__c == 'GRANDCHILD' && detail.Object_Name__c == 'ActivityHistory'){
                    addMessage(detail.Object_Name__c+' is not supported at third level.');
                }
                if(String.isNotBlank(detail.Object_Name__c) && !schemaMap.containsKey(detail.Object_Name__c) && !detail.Object_Name__c.endsWithIgnoreCase('__dlm')){
                    addMessage('The mapping object ' + detail.Object_Name__c + ' does not exist.');
                }else{
                    if(!isFieldExists(detail.Object_Name__c, detail.RelationshipField__c)){
                        addMessage('The field ' + detail.RelationshipField__c + ' does not exists on ' + detail.Object_Name__c + ' object or you might not have permission to it.');
                    }
                }
                if(String.isNotBlank(detail.Where_Clause__c)){
                    if(detail.Object_Name__c == 'ActivityHistory'){
                        addMessage('WHERE CLAUSE is not supported on ' + detail.Object_Name__c + ' object.');
                    }else{
                        try{
                            // @jira : 4662 Handle ORDER BY in Where Clause of Data Extraction
                            String whereClause = AIUtility.getFormattedWhereClause(detail.Where_Clause__c,NULL,NULL,true);
                            String query = 'SELECT Id FROM '+String.escapeSingleQuotes(detail.Object_Name__c)+whereClause;
                            Database.query(query);
                        }catch(Exception e){
                            addMessage('Incorrect WHERE CLAUSE on ' + detail.Object_Name__c + ' object.');
                        } 
                    }               
                }
                
            }
            return detailList;
        }
        return null;
    }
    
    /**
     * Validates data extraction fields for an AI prompt.
     * This method performs validation on the specified AI prompt object,
     * ensuring that the required fields for data extraction are present
     * and meet the necessary criteria.
     *
     * @param pmt The AI prompt object to be validated.
     */
    public void validateDataExtractionFields(String deMappingId){
        if(deMappingId != null){
            Boolean areFieldMappingsValid = true;
            Map<String, List<AI_Data_Extraction_Field__c>> mapOfObjectNameToFields = new Map<String, List<AI_Data_Extraction_Field__c>>();
            List<AI_Data_Extraction_Field__c> lstOfObjects = new List<AI_Data_Extraction_Field__c>();
            for(AI_Data_Extraction_Field__c fm : [SELECT Id, Name, AI_Data_Extraction_Mapping__c, 
                                                  Type__c, Field__c, Object__c, Formula__c 
                                                  FROM AI_Data_Extraction_Field__c 
                                                  WHERE AI_Data_Extraction_Mapping__c =:deMappingId
                                                  AND Type__c != NULL 
                                                  AND Object__c != NULL 
                                                  AND Field__c != NULL]){
                String objName = fm.Object__c.toLowerCase();
                if(String.isNotBlank(fm.Type__c) && fm.Type__c.equalsIgnoreCase('OBJECT')){
                    lstOfObjects.add(fm);
                }else{
                    if(!mapOfObjectNameToFields.containsKey(objName)){
                        mapOfObjectNameToFields.put(objName, new List<AI_Data_Extraction_Field__c>());
                    }
                    mapOfObjectNameToFields.get(objName).add(fm);
                }
            }
            
            if(!lstOfObjects.isEmpty()){
                for(AI_Data_Extraction_Field__c objFm : lstOfObjects) {
                    String objName = objFm.Object__c.toLowerCase();
                    if(!mapOfObjectNameToFields.isEmpty() && mapOfObjectNameToFields.containsKey(objName)){
                        for(AI_Data_Extraction_Field__c fieldFm : mapOfObjectNameToFields.get(objName)){
                            if(String.isBlank(fieldFm.Formula__c) && !isFieldExists(fieldFm.Object__c, fieldFm.Field__c) && fieldFm.Object__c != fieldFm.Field__c && !fieldFm.Field__c.contains('.')){
                                addMessage('The field '+fieldFm.Field__c+' is not present on '+fieldFm.Object__c+' object or you might not have permission to it');
                            }
                            if(String.isNotBlank(fieldFm.Formula__c) && isFieldExists(fieldFm.Object__c, fieldFm.Field__c)){
                                addMessage('The formula field '+fieldFm.Field__c+' API name is duplicate.');
                            }
                        }
                    }else{
                        addMessage('There are no field mappings defined for '+objFm.Object__c+'.');
                    }
                }
            }
        }
    }
    
    /**
     * Adds a message to the collection.
     *
     * This method takes a message as input and adds it to the underlying collection
     * or data structure. The purpose is to store messages for further processing,
     * display, or any other relevant use case.
     *
     * @param msg The message to be added to the collection.
     */
    public void addMessage(String msg){
        Integer count = (messages != null ? messages.size() : 0) + 1;
        msg = '('+count+') '+msg;
        messages.add(msg);
    }
    
    /**
     * Checks if a given field exists for a specified object in an API.
     *
     * @param objectApiName The API name of the object to which the field belongs.
     * @param fieldApiName The API name of the field to check for existence.
     * @return True if the field exists for the specified object, false otherwise.
     * @Jira V2-7132
     */
    public boolean isFieldExists(String objectApiName, String fieldApiName) {
        if(schemaMap != null && schemaMap.containsKey(objectApiName) && schemaMap.get(objectApiName) != null && schemaMap.get(objectApiName).getDescribe() != null){
            Schema.DescribeSObjectResult gdesc = schemaMap.get(objectApiName).getDescribe();
            if(gdesc.fields != null && gdesc.fields.getMap().containsKey(fieldApiName)){
                Schema.describeFieldResult dfield = gdesc.fields.getMap().get(fieldApiName).getDescribe();
                if(dfield != null && dfield.isAccessible()){
                    return true;
                }
            }
        }else if(objectApiName.endsWithIgnoreCase('__dlm')){
            //do-nothing
            return true;
        }
        return false;
    }
    
    /**
     * Checks the field bindings for an AI_Prompt__c object.
     *
     * @param pmt The AI_Prompt__c object for which field bindings are checked.
     */
    public void checkFieldBindings(AI_Prompt__c pmt){
        if(String.isBlank(pmt.Prompt_Command__c) && !pmt.Custom_Prompt__c && pmt.Type__c != 'Canvas' && pmt.Type__c != 'JSON'){
            addMessage('Prompt command is blank.');
        }else if(pmt.Type__c == 'Text' && String.isNotBlank(pmt.Prompt_Command__c)){
            List<String> mergeFields = AIPromptValidationController.getMatchedFields(pmt.Prompt_Command__c);
            if(mergeFields != null && !mergeFields.isEmpty()){
                Set<String> setOfMergeFields = getMergedFields(pmt.AI_Data_Extraction_Mapping__r);
                for(String mergeField : mergeFields){
                    if(setOfMergeFields.isEmpty() || !setOfMergeFields.contains(mergeField.toLowerCase())){
                        addMessage('Merge Field '+mergeField+' added in Prompt Command does not exist in the Field Mapping.');
                    }
                }
            }
        }
    }
    
    /**
     * Retrieves a list of matched fields based on the provided PMT command.
     *
     * @param pmtCommand The PMT command for which matched fields are to be retrieved.
     * @return A list of strings representing the matched fields.
     */
    public static List<String> getMatchedFields(String pmtCommand){
        Pattern regex = Pattern.compile('\\{\\{\\{(.*?)\\}\\}\\}');
        Matcher matcher = regex.matcher(pmtCommand);
        List<String> matches = new List<String>();
        while(matcher.find()){
            String match = matcher.group(1);
            matches.add(match);
        }
        return matches;
    }
    
    /**
     * Retrieves the merged fields from the given AI_Data_Extraction_Mapping__c object.
     *
     * This method takes an AI_Data_Extraction_Mapping__c object as a parameter and
     * extracts the merged fields from it. Merged fields are represented as a Set of strings.
     *
     * @param ext The AI_Data_Extraction_Mapping__c object from which merged fields are extracted.
     * @return A Set<String> containing the merged fields.
     */
    public Set<String> getMergedFields(AI_Data_Extraction_Mapping__c ext){
        
        Map<String, List<AI_Data_Extraction_Detail__c>> mapOfObjNameToDetails = new Map<String, List<AI_Data_Extraction_Detail__c>>();
        Map<String, AI_Data_Extraction_Detail__c> mapOfDetail = new Map<String, AI_Data_Extraction_Detail__c>();
        for(AI_Data_Extraction_Detail__c detail : [SELECT Id, Object_Name__c, RelationshipName__c, Parent_Detail__c 
                                                   FROM AI_Data_Extraction_Detail__c 
                                                   WHERE AI_Data_Extraction_Mapping__c =:ext.Id]){
            if(!mapOfObjNameToDetails.containsKey(detail.Object_Name__c)){
                mapOfObjNameToDetails.put(detail.Object_Name__c, new List<AI_Data_Extraction_Detail__c>());
            }
            mapOfObjNameToDetails.get(detail.Object_Name__c).add(detail);   
            mapOfDetail.put(detail.Id, detail);                                           
        }

        Map<String, String> mapOfDetailIdToPrefix = new Map<String, String>();
        if(mapOfDetail != null && !mapOfDetail.isEmpty()){
            for(String detailId : mapOfDetail.keySet()){
            	String rName = '';
                String currentDetailId = detailId;
                while(String.isNotBlank(currentDetailId) && mapOfDetail.containsKey(currentDetailId)){
                    rName = mapOfDetail.get(currentDetailId).RelationshipName__c + (String.isNotBlank(rName) ? ('.'+ rName) : '');
                    currentDetailId = mapOfDetail.get(currentDetailId).Parent_Detail__c;
                }
                mapOfDetailIdToPrefix.put(detailId, rName);
        	}
        }
        Set<String> setOfMergeFields = new Set<String>();
        for(AI_Data_Extraction_Field__c field : [SELECT Id, Label__c, Object__c, Field__c
                                                 FROM AI_Data_Extraction_Field__c 
                                                 WHERE Type__c = 'FIELD'
                                                 AND AI_Data_Extraction_Mapping__c =:ext.Id
                                                 AND Field__c != NULL]){
            if(!mapOfObjNameToDetails.isEmpty() && mapOfObjNameToDetails.containsKey(field.Object__c)){
                for(AI_Data_Extraction_Detail__c detail : mapOfObjNameToDetails.get(field.Object__c)){
                    if(!mapOfDetailIdToPrefix.isEmpty() && mapOfDetailIdToPrefix.containsKey(detail.Id)){
                        String rName = mapOfDetailIdToPrefix.get(detail.Id);
                        setOfMergeFields.add((rName+'.'+field.Field__c).toLowerCase());
                        setOfMergeFields.add((field.Field__c).toLowerCase());
                    }
                }
            }else{
                setOfMergeFields.add((field.Field__c).toLowerCase());
            }
        }
        return setOfMergeFields;
    }
    //@Jira V2-7132
    public void validatePromptActions(AI_Prompt__c pmt){
        Map<String, AI_Prompt_Action__c> mapOfActions = new Map<String, AI_Prompt_Action__c>([
            SELECT Id, Action__c, Action_Label__c, Apex_Class_Name__c, Field_API_Name__c,
            Flow_API_Name__c, Object_Name__c, Prompt_Component__c, AI_Prompt__r.Object__c,
            (SELECT Id, Field_API_Name__c, Type__c, Value__c FROM Prompt_Action_Details__r)
            FROM AI_Prompt_Action__c
            WHERE AI_Prompt__c =:pmt.Id
        ]);
        
        if(mapOfActions != null && !mapOfActions.isEmpty()){
            
            Map<String, String> mapOfFlowApiNames = new Map<String, String>();
            Map<String, String> mapOfApexClassApiNames = new Map<String, String>();
            Set<String> setOfUpdateFieldApiNames = new Set<String>();
            
            Set<String> setOfValidPromptComponents = new Set<String>();
            for(AI_Prompt_Component__c pc : [SELECT Id, Name 
                                             FROM AI_Prompt_Component__c 
                                             WHERE AI_Prompt__c =:pmt.Id]){
                setOfValidPromptComponents.add(pc.Name.toLowerCase());
            }
            
            for(AI_Prompt_Action__c pa : mapOfActions.values()){
                if(pa.Action__c == AIConstants.ACTION_TYPE_UPDATE_FIELD){
                    setOfUpdateFieldApiNames.add(pa.Field_API_Name__c);
                    if(String.isNotBlank(pa.Prompt_Component__c) && (setOfValidPromptComponents.isEmpty() || !setOfValidPromptComponents.contains(pa.Prompt_Component__c.toLowerCase()))){
                        addMessage('Prompt Component "'+pa.Prompt_Component__c+'" is missing on Prompt: '+pa.Action_Label__c);
                    }
                }else if(pa.Action__c == AIConstants.ACTION_TYPE_CREATE_RECORD || pa.Action__c == AIConstants.ACTION_TYPE_OPEN_FORM){
                    if(String.isNotBlank(pa.Object_Name__c)){
                        if(!schemaMap.containsKey(pa.Object_Name__c)){
                            addMessage('Object Name "'+pa.Object_Name__c+'" is missing on Prompt Action: '+pa.Action_Label__c);
                        }else{
                            if(pa.Prompt_Action_Details__r != null && !pa.Prompt_Action_Details__r.isEmpty()){
                                for(AI_Prompt_Action_Detail__c detail : pa.Prompt_Action_Details__r){
                                    if(detail.Type__c == AIConstants.ACTION_DETAIL_TYPE_AI_RESP && String.isNotBlank(detail.Value__c) && detail.Value__c != '#N/A#' && (setOfValidPromptComponents.isEmpty() || !setOfValidPromptComponents.contains(detail.Value__c.toLowerCase()))){
                                        addMessage('One of the Prompt Component "'+detail.Value__c+'" selected in "'+pa.Action_Label__c+'" is missing on Prompt.');
                                    }else if(detail.Type__c == AIConstants.ACTION_DETAIL_TYPE_REF_FIELD){
                                        if(String.isBlank(detail.Value__c) || !isFieldExists(pmt.Object__c, detail.Value__c)){
                                            addMessage('One of the Field "'+detail.Value__c+'" selected in "'+pa.Action_Label__c+'" either does exists or you do not have permission to it.');
                                        }
                                    }
                                }
                            }else{
                                addMessage('Fields is missing on Prompt Action: '+pa.Action_Label__c);
                            }
                        }
                    }else{
                        addMessage('Object Name is missing on Prompt Action: '+pa.Action_Label__c);
                    }
                }else if(pa.Action__c == AIConstants.ACTION_TYPE_INVOKE_FLOW){
                    if(String.isBlank(pa.Flow_API_Name__c)){
                        addMessage('Flow API Name is missing on Prompt Action: '+pa.Action_Label__c);
                    }else{
                        mapOfFlowApiNames.put(pa.Id, pa.Flow_API_Name__c);
                    }
                }else if(pa.Action__c == AIConstants.ACTION_TYPE_INVOKE_APEX){
                    if(String.isBlank(pa.Apex_Class_Name__c)){
                        addMessage('Apex Class Name is missing on Prompt Action: '+pa.Action_Label__c);
                    }
                    else if(Type.forName('',pa.Apex_Class_Name__c) == null || String.valueOf(Type.forName('',pa.Apex_Class_Name__c)) == 'System.Test'){
                        addMessage('Apex Class Name is invalid on Prompt Action: '+pa.Action_Label__c);
                    }
                else{
                        mapOfApexClassApiNames.put(pa.Id, pa.Apex_Class_Name__c.toLowerCase());
                    }
                }
            }
            
            if(!setOfUpdateFieldApiNames.isEmpty()){
                String query = 'SELECT '+String.join(new List<String>(setOfUpdateFieldApiNames), ', ')+' FROM '+pmt.Object__c+' LIMIT 0 ';
                try{
                    Database.query(query);
                }catch(Exception e){
                    addMessage('One or more Update Field actions has incorrect field references, please check the error message for more details: '+e.getMessage());
                }
            }
            
            if(!mapOfFlowApiNames.isEmpty()){
                Set<String> activeFlowApiNames = new Set<String>();
                for(FlowDefinitionView fd : [SELECT Id, ApiName 
                                             FROM FlowDefinitionView 
                     						 WHERE IsActive = True 
                                             AND ProcessType = 'AutoLaunchedFlow' 
                                             AND ApiName IN :mapOfFlowApiNames.values()]){
                    activeFlowApiNames.add(fd.ApiName);
                }

                for(String paId : mapOfFlowApiNames.keySet()){
                    AI_Prompt_Action__c pa = mapOfActions.get(paId);
                    String flowApiName = mapOfFlowApiNames.get(paId);
                    if(activeFlowApiNames == null || !activeFlowApiNames.contains(flowApiName)){
                        addMessage('Either the Flow "'+pa.Flow_API_Name__c+'" does not exists, or is Inactive, or is not of Type Autolaunched on Prompt Action: '+pa.Action_Label__c);
                    }
                }
            }
            
            if(!mapOfApexClassApiNames.isEmpty()){
                Set<String> activeApexClassNames = new Set<String>();
                for(ApexClass ac : [SELECT Id, Name 
                                    FROM ApexClass 
                                    WHERE Status = 'Active' 
                                    AND Name IN :mapOfApexClassApiNames.values()]){
                    activeApexClassNames.add(ac.Name.toLowerCase());
                }
                
                for(String paId : mapOfApexClassApiNames.keySet()){
                    AI_Prompt_Action__c pa = mapOfActions.get(paId);
                    String apexClassName = mapOfApexClassApiNames.get(paId);
                    if(activeApexClassNames == null || !activeApexClassNames.contains(apexClassName)){
                        addMessage('The Apex Class "'+pa.Apex_Class_Name__c+'" does not exists on Prompt Action: '+pa.Action_Label__c);
                    }
                }
            }
        }
    }

    //Jira 7221:  Issues/Feedbacks from 1.12 Testing
    //@Jira V2-7132
    public void validateResponseValidation(AI_Prompt__c pmt){
        for(AI_Prompt_Response_Validation__c resp : [SELECT Id, Sequence__c, Action__c, Value__c 
                                                     FROM AI_Prompt_Response_Validation__c
                                                     WHERE AI_Prompt__c =:pmt.Id]){
            if(String.isBlank(resp.Value__c) || resp.Value__c == null){
                addMessage('The Response Validation value is invalid of '+resp.Action__c+' action.');
            }
            else if(resp.Action__c == 'Apex' && (Type.forName('',resp.Value__c) == null || String.valueOf(Type.forName('',resp.Value__c)) == 'System.Test')){
                addMessage('The Response Validation Apex Class Name is invalid of '+resp.Action__c+' action.');
            }
        }
    }
    
}