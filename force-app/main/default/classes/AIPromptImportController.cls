/**
 * @description       : 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 06-08-2023
 * @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptImportController {
    
    public STATIC String RT_REGEX = (String)Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Regex').getRecordTypeId();
    public STATIC String RT_BLOCKLIST = (String)Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Blocklist').getRecordTypeId();
    
    /**
     * Reads and processes the file data provided as a string, extracting relevant information and organizing it into a map for further manipulation or analysis.
     * 
     * @param fileData The string representation of the file data to be processed and organized into a map.
     * @return Map<String, Object> A map where the keys represent data attributes, and the values contain the corresponding extracted information from the file data for further processing or analysis.
     */
    @AuraEnabled
    public static map<string, object> readFileData(String fileData){
        map<string, object> mapOfData = new map<string, object>();
        try{
            ExportMappingWrapper wrap = (ExportMappingWrapper)System.JSON.deserialize(fileData, ExportMappingWrapper.class);
            if(wrap != null){
                if(wrap.prompts != null && !wrap.prompts.isEmpty()){ 
                    mapOfData.put('hasError', false);
                	mapOfData.put('data', wrap);
                }else{
                    mapOfData.put('hasError', true);
                	mapOfData.put('message', 'No Prompts in the File to Import.');
                }
            }else{
                mapOfData.put('hasError', true);
                mapOfData.put('message', 'Empty Export File.');
            }

            return mapOfData;
        }catch(Exception e){
            mapOfData.put('hasError', true);
            mapOfData.put('message', e.getMessage());
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptImportController', 'readFileData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Saves the mappings, prompts, connections, extraction mappings, extraction security filters, and relevant data, with consideration for post-install operations if specified.
     * 
     * @param prompts A list of ExportMappingWrapper.PromptWrapper objects containing the prompts to be saved.
     * @param connections A list of ExportMappingWrapper.ConnectionWrapper objects containing the connections to be saved.
     * @param mappings A list of ExportMappingWrapper.ExtractionWrapper objects containing the extraction mappings to be saved.
     * @param filters A list of ExportMappingWrapper.ExtractionSecurityFilterWrapper objects containing the extraction security filters to be saved.
     * @param isPostInstall A boolean value indicating whether the save operation is being performed post-installation.
     */
    @AuraEnabled
    public static void saveMappings(List<ExportMappingWrapper.PromptWrapper> prompts, List<ExportMappingWrapper.ConnectionWrapper> connections, List<ExportMappingWrapper.ExtractionWrapper> mappings, List<ExportMappingWrapper.ExtractionSecurityFilterWrapper> filters, List<ExportMappingWrapper.DataSourceWrapper> dataSources, Boolean isPostInstall){
       	try{
        	insertPrompts(prompts, connections, mappings, filters, dataSources, isPostInstall);
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptImportController', 'saveMappings', '');
            if(isPostInstall != null && !isPostInstall){
                throw new AuraHandledException(e.getMessage());
            }
        }
    }
    
   /**
     * Inserts prompts, connections, mappings, and extraction security filters into the Salesforce environment based on the provided lists, considering the specified post-installation status.
     * 
     * @param prompts A list of ExportMappingWrapper.PromptWrapper objects containing the prompts to be inserted.
     * @param connections A list of ExportMappingWrapper.ConnectionWrapper objects containing the connections to be inserted.
     * @param mappings A list of ExportMappingWrapper.ExtractionWrapper objects containing the mappings to be inserted.
     * @param filters A list of ExportMappingWrapper.ExtractionSecurityFilterWrapper objects containing the extraction security filters to be inserted.
     * @param isPostInstall A boolean value indicating whether the insertion is occurring during the post-installation process.
     */
    public static void insertPrompts(List<ExportMappingWrapper.PromptWrapper> prompts, List<ExportMappingWrapper.ConnectionWrapper> connections, List<ExportMappingWrapper.ExtractionWrapper> mappings, List<ExportMappingWrapper.ExtractionSecurityFilterWrapper> filters, List<ExportMappingWrapper.DataSourceWrapper> dataSources, Boolean isPostInstall){
        Map<String, AI_Data_Extraction_Mapping__c> mapOfExternalIdToDataExtraction = new Map<String, AI_Data_Extraction_Mapping__c>();
        Map<String, AI_Data_Extraction_Detail__c> mapOfExtIdToDetailToUpsert = new Map<String, AI_Data_Extraction_Detail__c>();
        Map<String, AI_Connection__c> mapOfExternalIdToConnection = new Map<String, AI_Connection__c>();
        Map<String, AI_Data_Source__c> mapOfExternalIdToDataSource = new Map<String, AI_Data_Source__c>();
        
        //inserting connection records
        for(ExportMappingWrapper.ConnectionWrapper wrap : connections){
            mapOfExternalIdToConnection.put(wrap.salesforceId, getMappedConnection(wrap));
        }
        if(!mapOfExternalIdToConnection.isEmpty()){
            Map<String, SObject> cleanedRecords = (Map<String, SObject>)mapOfExternalIdToConnection;
            //cleanedRecords = FLSCheck.getInstance().upsertCheck(cleanedRecords);
            if(isPostInstall){
                cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, true);
            }else{
                cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, AI_Connection__c.Fields.External_Id__c, true);
            }
            
            for(String key : cleanedRecords.keySet()){
                mapOfExternalIdToConnection.put(key, (AI_Connection__c)cleanedRecords.get(key));
            }
        }
        
        //inserting datasource records
        if(dataSources != null && !dataSources.isEmpty()){
            for(ExportMappingWrapper.DataSourceWrapper wrap : dataSources){
                mapOfExternalIdToDataSource.put(wrap.salesforceId, getDataSource(wrap));
            }
            if(!mapOfExternalIdToDataSource.isEmpty()){
                Map<String, SObject> cleanedRecords = (Map<String, SObject>)mapOfExternalIdToDataSource;
                //cleanedRecords = FLSCheck.getInstance().upsertCheck(cleanedRecords);
                if(isPostInstall){
                    cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, true);
                }else{
                    cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, AI_Data_Source__c.Fields.External_Id__c, true);
                }
                
                for(String key : cleanedRecords.keySet()){
                    mapOfExternalIdToDataSource.put(key, (AI_Data_Source__c)cleanedRecords.get(key));
                }
            }
        }
        
        
        //inserting data extraction mapping records
        for(ExportMappingWrapper.ExtractionWrapper wrap : mappings){
            AI_Data_Extraction_Mapping__c em = getMappedDataExtractionMapping(wrap, isPostInstall);
            if(wrap.dataSourceId != null && mapOfExternalIdToDataSource != null && mapOfExternalIdToDataSource.containsKey(wrap.dataSourceId)){
                em.AI_Data_Source__c = mapOfExternalIdToDataSource.get(wrap.dataSourceId).Id;
            }
            mapOfExternalIdToDataExtraction.put(wrap.salesforceId, em);
        }
        if(!mapOfExternalIdToDataExtraction.isEmpty()){
            Map<String, SObject> cleanedRecords = (Map<String, SObject>)mapOfExternalIdToDataExtraction;
            //cleanedRecords = FLSCheck.getInstance().upsertCheck(cleanedRecords);
            if(isPostInstall){
                cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, true);
            }else{
                cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, AI_Data_Extraction_Mapping__c.Fields.External_Id__c, true);
            }
            for(String key : cleanedRecords.keySet()){
                mapOfExternalIdToDataExtraction.put(key, (AI_Data_Extraction_Mapping__c)cleanedRecords.get(key));
            }
            
            List<AI_Data_Extraction_Field__c> lstOfFieldToUpsert = new List<AI_Data_Extraction_Field__c>();
            List<ExportMappingWrapper.ExtractionDetailWrapper> lstOfParentDetailWrappers = new List<ExportMappingWrapper.ExtractionDetailWrapper>();
            
            for(ExportMappingWrapper.ExtractionWrapper wrap : mappings){
                if(mapOfExternalIdToDataExtraction.containsKey(wrap.salesforceId)){
                    String dataExtMappingId = mapOfExternalIdToDataExtraction.get(wrap.salesforceId).Id;
                    if(wrap.details != null && !wrap.details.isEmpty()){
                        for(ExportMappingWrapper.ExtractionDetailWrapper d_wrap : wrap.details){
                            mapOfExtIdToDetailToUpsert.put(d_wrap.salesforceId, getMappedDetail(d_wrap, dataExtMappingId));
                            
                            if(String.isNotBlank(d_wrap.parentDetailId)){
                                lstOfParentDetailWrappers.add(d_wrap);
                            }
                        }
                    }
                    if(wrap.fields != null && !wrap.fields.isEmpty()){
                        for(ExportMappingWrapper.ExtractionFieldWrapper f_wrap : wrap.fields){
                            lstOfFieldToUpsert.add(getMappedField(f_wrap, dataExtMappingId));
                        }
                    }
                }
            }
            
            //inserting detail records
            if(!mapOfExtIdToDetailToUpsert.isEmpty()){
                Map<String, SObject> cleanedDetailRecords = (Map<String, SObject>)mapOfExtIdToDetailToUpsert;
                //cleanedDetailRecords = FLSCheck.getInstance().upsertCheck(cleanedDetailRecords);
                if(isPostInstall){
                    cleanedDetailRecords = FLSCheck.getInstance().upsertDML(cleanedDetailRecords, true);
                }else{
                    cleanedDetailRecords = FLSCheck.getInstance().upsertDML(cleanedDetailRecords, AI_Data_Extraction_Detail__c.Fields.External_Id__c, true);
                }
                for(String key : cleanedDetailRecords.keySet()){
                    mapOfExtIdToDetailToUpsert.put(key, (AI_Data_Extraction_Detail__c)cleanedDetailRecords.get(key));
                }
                
                //updating detail records with parent id
                List<AI_Data_Extraction_Detail__c> lstToUpdate = new List<AI_Data_Extraction_Detail__c>();
                if(lstOfParentDetailWrappers != null && !lstOfParentDetailWrappers.isEmpty()){
                    for(ExportMappingWrapper.ExtractionDetailWrapper d_wrap : lstOfParentDetailWrappers){
                        if(mapOfExtIdToDetailToUpsert.containsKey(d_wrap.salesforceId) && mapOfExtIdToDetailToUpsert.containsKey(d_wrap.parentDetailId)){
                            lstToUpdate.add(new AI_Data_Extraction_Detail__c(
                                Id = mapOfExtIdToDetailToUpsert.get(d_wrap.salesforceId).Id,
                                Parent_Detail__c = mapOfExtIdToDetailToUpsert.get(d_wrap.parentDetailId).Id
                            ));
                        }
                    }
                }
                if(!lstToUpdate.isEmpty()){
                    FLSCheck.getInstance().updateDML(lstToUpdate);
                }
            }
            
            //inserting field records
            if(!lstOfFieldToUpsert.isEmpty()){
                List<sObject> cleanedFieldRecords = (List<sObject>)lstOfFieldToUpsert;
                //cleanedFieldRecords = FLSCheck.getInstance().upsertCheck(cleanedFieldRecords);
                if(cleanedFieldRecords != null && !cleanedFieldRecords.isEmpty()){
                    if(isPostInstall){
                        cleanedFieldRecords = (List<sObject>)FLSCheck.getInstance().upsertDML(cleanedFieldRecords, true);
                    }else{
                        cleanedFieldRecords = (List<sObject>)FLSCheck.getInstance().upsertDML(cleanedFieldRecords, AI_Data_Extraction_Field__c.Fields.External_Id__c, true);
                    }
                }
            }
        }
        
        //inserting prompt records
        Map<String, AI_Prompt__c> mapOfExternalIdToPrompt = new Map<String, AI_Prompt__c>();
        Map<String, AI_Prompt_Component__c> mapOfExternalIdToPromptComponent = new Map<String, AI_Prompt_Component__c>();
        Map<String, AI_Prompt_Action__c> mapOfExternalIdToPromptAction = new Map<String, AI_Prompt_Action__c>();
        Map<String, AI_Prompt_Action_Detail__c> mapOfExternalIdToPromptActionDetail = new Map<String, AI_Prompt_Action_Detail__c>();
        Map<String, AI_Response_Processing__c> mapOfExternalIdToRespProcessing = new Map<String, AI_Response_Processing__c>();
        List<ExportMappingWrapper.PromptElementWrapper> listOfPromptElements = new List<ExportMappingWrapper.PromptElementWrapper>();
        
        Map<String, String> mapOfRespProIdToParentId = new Map<String, String>();
        Map<String, String> mapOfCmpIdToParentId = new Map<String, String>();
        Map<String, String> mapOfPromActionDetailProIdToParentId = new Map<String, String>();
        
        for(ExportMappingWrapper.PromptWrapper wrap : prompts){
            mapOfExternalIdToPrompt.put(wrap.salesforceId, getMappedPrompt(wrap, mapOfExternalIdToDataExtraction, mapOfExternalIdToConnection, isPostInstall));
            
            if(wrap.promptComponents != null && !wrap.promptComponents.isEmpty()){
                for(ExportMappingWrapper.PromptComponentWrapper c_wrap : wrap.promptComponents){
                    mapOfExternalIdToPromptComponent.put(c_wrap.salesforceId, getMappedPromptComponent(c_wrap, mapOfExtIdToDetailToUpsert, mapOfExternalIdToDataExtraction));
                    mapOfCmpIdToParentId.put(c_wrap.salesforceId, wrap.salesforceId);
                    
                    if(c_wrap.responseProcessings != null && !c_wrap.responseProcessings.isEmpty()){
                        for(ExportMappingWrapper.ResponseProcessingWrapper rp_wrap : c_wrap.responseProcessings){
                            mapOfExternalIdToRespProcessing.put(rp_wrap.salesforceId, getMappedResponseProcessing(rp_wrap));
                            mapOfRespProIdToParentId.put(rp_wrap.salesforceId, c_wrap.salesforceId);
                        }
                    }
                }
            }
            
            if(wrap.promptActions != null && !wrap.promptActions.isEmpty()){
                for(ExportMappingWrapper.PromptActionWrapper pa_wrap : wrap.promptActions){
                    mapOfExternalIdToPromptAction.put(pa_wrap.salesforceId, getMappedPromptAction(pa_wrap));
                    mapOfCmpIdToParentId.put(pa_wrap.salesforceId, wrap.salesforceId);
                    
                    if(pa_wrap.promptActionDetails != null && !pa_wrap.promptActionDetails.isEmpty()){
                        for(ExportMappingWrapper.PromptActionDetailWrapper pad_wrap : pa_wrap.promptActionDetails){
                            mapOfExternalIdToPromptActionDetail.put(pad_wrap.salesforceId, getMappedPromptActionDetail(pad_wrap));
                            mapOfPromActionDetailProIdToParentId.put(pad_wrap.salesforceId, pa_wrap.salesforceId);
                        }
                    }
                }
            }
            
            if(wrap.promptElements != null && !wrap.promptElements.isEmpty()){
                listOfPromptElements.addAll(wrap.promptElements);
            }
        }
        if(!mapOfExternalIdToPrompt.isEmpty()){
            Map<String, SObject> cleanedRecords;
            if(isPostInstall){
                cleanedRecords = FLSCheck.getInstance().upsertDML(mapOfExternalIdToPrompt, true);
            }else{
                cleanedRecords = FLSCheck.getInstance().upsertDML(mapOfExternalIdToPrompt, AI_Prompt__c.Fields.External_Id__c, true);
            }
            
            for(String key : cleanedRecords.keySet()){
                mapOfExternalIdToPrompt.put(key, (AI_Prompt__c)cleanedRecords.get(key));
            }
            
            if(!mapOfExternalIdToPromptComponent.isEmpty()){
                for(AI_Prompt_Component__c cmp : mapOfExternalIdToPromptComponent.values()){
                    if(mapOfCmpIdToParentId.containsKey(cmp.External_Id__c)){
                        String parentExtId = mapOfCmpIdToParentId.get(cmp.External_Id__c);
                        if(mapOfExternalIdToPrompt.containsKey(parentExtId)){
                            cmp.AI_Prompt__c = mapOfExternalIdToPrompt.get(parentExtId).Id;
                        }
                    }
                }
                Map<String, SObject> cleanedCmpRecords;
                if(isPostInstall){
                    cleanedCmpRecords = FLSCheck.getInstance().upsertDML(mapOfExternalIdToPromptComponent, true);
                }else{
                    cleanedCmpRecords = FLSCheck.getInstance().upsertDML(mapOfExternalIdToPromptComponent, AI_Prompt_Component__c.Fields.External_Id__c,  true);
                }
                
                for(String key : cleanedCmpRecords.keySet()){
                    mapOfExternalIdToPromptComponent.put(key, (AI_Prompt_Component__c)cleanedCmpRecords.get(key));
                }
                
                if(!mapOfExternalIdToRespProcessing.isEmpty()){
                    for(AI_Response_Processing__c rp : mapOfExternalIdToRespProcessing.values()){
                        if(mapOfRespProIdToParentId.containsKey(rp.External_Id__c)){
                            String parentExtId = mapOfRespProIdToParentId.get(rp.External_Id__c);
                            if(mapOfExternalIdToPromptComponent.containsKey(parentExtId)){
                                rp.AI_Prompt_Component__c = mapOfExternalIdToPromptComponent.get(parentExtId).Id;
                            }
                        }
                    }
                    Map<String, SObject> cleanedRespRecords;
                    if(isPostInstall){
                        cleanedRespRecords = FLSCheck.getInstance().upsertDML(mapOfExternalIdToRespProcessing, true);
                    }else{
                        cleanedRespRecords = FLSCheck.getInstance().upsertDML(mapOfExternalIdToRespProcessing, AI_Response_Processing__c.Fields.External_Id__c,  true);
                    }
                }
            }
            
            if(!mapOfExternalIdToPromptAction.isEmpty()){
                for(AI_Prompt_Action__c pa : mapOfExternalIdToPromptAction.values()){
                    if(mapOfCmpIdToParentId.containsKey(pa.External_Id__c)){
                        String parentExtId = mapOfCmpIdToParentId.get(pa.External_Id__c);
                        if(mapOfExternalIdToPrompt.containsKey(parentExtId)){
                            pa.AI_Prompt__c = mapOfExternalIdToPrompt.get(parentExtId).Id;
                        }
                    }
                }
                Map<String, SObject> cleanedActionRecords = (Map<String, SObject>)mapOfExternalIdToPromptAction;
                //cleanedActionRecords = FLSCheck.getInstance().upsertCheck(cleanedActionRecords);
                if(isPostInstall){
                    cleanedActionRecords = FLSCheck.getInstance().upsertDML(cleanedActionRecords, true);
                }else{
                    cleanedActionRecords = FLSCheck.getInstance().upsertDML(cleanedActionRecords, AI_Prompt_Action__c.Fields.External_Id__c,  true);
                }
                
                for(String key : cleanedActionRecords.keySet()){
                    mapOfExternalIdToPromptAction.put(key, (AI_Prompt_Action__c)cleanedActionRecords.get(key));
                }
                if(!mapOfExternalIdToPromptActionDetail.isEmpty()){
                    for(AI_Prompt_Action_Detail__c rp : mapOfExternalIdToPromptActionDetail.values()){
                        if(mapOfPromActionDetailProIdToParentId.containsKey(rp.External_Id__c)){
                            String parentExtId = mapOfPromActionDetailProIdToParentId.get(rp.External_Id__c);
                            if(mapOfExternalIdToPromptAction.containsKey(parentExtId)){
                                rp.AI_Prompt_Action__c = mapOfExternalIdToPromptAction.get(parentExtId).Id;
                            }
                        }
                    }
                    Map<String, SObject> cleanedPromptActionDetailRecords = (Map<String, SObject>)mapOfExternalIdToPromptActionDetail;
                    //cleanedPromptActionDetailRecords = FLSCheck.getInstance().upsertCheck(cleanedPromptActionDetailRecords);
                    if(isPostInstall){
                        cleanedPromptActionDetailRecords = FLSCheck.getInstance().upsertDML(cleanedPromptActionDetailRecords, true);
                    }else{
                        cleanedPromptActionDetailRecords = FLSCheck.getInstance().upsertDML(cleanedPromptActionDetailRecords, AI_Prompt_Action_Detail__c.Fields.External_Id__c, true);
                    }
                }
            }
            
            if(!listOfPromptElements.isEmpty()){
                Map<String, AI_Prompt_Element__c> mapOfExternalIdToPromptElements = new Map<String, AI_Prompt_Element__c>();

                for(ExportMappingWrapper.PromptElementWrapper pe_wrap : listOfPromptElements){
                    mapOfExternalIdToPromptElements.put(pe_wrap.salesforceId, getMappedPromptElement(pe_wrap, mapOfExternalIdToPrompt));
                }
                Map<String, SObject> cleanedPromptElementRecords = (Map<String, SObject>)mapOfExternalIdToPromptElements;
                if(isPostInstall){
                    cleanedPromptElementRecords = FLSCheck.getInstance().upsertDML(cleanedPromptElementRecords, true);
                }else{
                    cleanedPromptElementRecords = FLSCheck.getInstance().upsertDML(cleanedPromptElementRecords, AI_Prompt_Element__c.Fields.External_Id__c, true);
                }
            }
        }
        
        //Security Filters
        Set<String> setOfUniqueFilters = new Set<String>();
        Map<String, AI_Security_Filters__c> mapOfExternalIdToFilters = new Map<String, AI_Security_Filters__c>();
        for(AI_Security_Filters__c sf : [SELECT Id, Name, Search_Pattern__c FROM AI_Security_Filters__c LIMIT 9999]){
            setOfUniqueFilters.add(sf.Name);
        }
        for(ExportMappingWrapper.ExtractionSecurityFilterWrapper wrap : filters){
            if(setOfUniqueFilters.size() == 0 || !setOfUniqueFilters.contains(wrap.filterName) || test.isRunningTest()){
                mapOfExternalIdToFilters.put(wrap.salesforceId, getMappedFilters(wrap));
            }
        }
        if(!mapOfExternalIdToFilters.isEmpty()){
            Map<String, SObject> cleanedRecords = (Map<String, SObject>)mapOfExternalIdToFilters;
            //cleanedRecords = FLSCheck.getInstance().upsertCheck(cleanedRecords);
            if(isPostInstall){
                cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, true);
            }else{
                cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, AI_Security_Filters__c.Fields.External_Id__c,  true);
            }
        }
    }
    
    public static AI_Prompt_Element__c getMappedPromptElement(ExportMappingWrapper.PromptElementWrapper wrap, Map<String, AI_Prompt__c> mapOfExternalIdToPrompt) {
        AI_Prompt_Element__c obj = new AI_Prompt_Element__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Sequence__c = wrap.sequence;
        obj.Width__c = wrap.width;
        obj.Height__c = wrap.height;
        obj.Icon__c = wrap.icon;
        obj.Inherit_Prompt_Security__c = wrap.inheritPromptSecurity;
        // Map parent, prompt, and summary prompt references
        if(String.isNotBlank(wrap.parentPromptId) && mapOfExternalIdToPrompt.containsKey(wrap.parentPromptId)) {
            obj.AI_Parent_Prompt__c = mapOfExternalIdToPrompt.get(wrap.parentPromptId).Id;
        }
        if(String.isNotBlank(wrap.promptId) && mapOfExternalIdToPrompt.containsKey(wrap.promptId)) {
            obj.AI_Prompt__c = mapOfExternalIdToPrompt.get(wrap.promptId).Id;
        }
        if(String.isNotBlank(wrap.summaryPromptId) && mapOfExternalIdToPrompt.containsKey(wrap.summaryPromptId)) {
            obj.AI_Summary_Prompt__c = mapOfExternalIdToPrompt.get(wrap.summaryPromptId).Id;
        }
        // Add any additional fields as needed
        return obj;
    }
    
    /**
     * Retrieves the mapped AI prompt component based on the provided PromptComponentWrapper object, map of external ID to AI data extraction details, and map of external ID to AI data extraction mappings.
     * 
     * @param wrap The PromptComponentWrapper object containing the necessary data and details for retrieving the mapped AI prompt component.
     * @param mapOfExtIdToDetail A map where the keys represent external IDs, and the values contain the corresponding AI data extraction details.
     * @param mapOfExtIdToMapping A map where the keys represent external IDs, and the values contain the corresponding AI data extraction mappings.
     * @return AI_Prompt_Component__c The AI prompt component object mapped based on the provided parameters, ready for further processing or analysis.
     */
    public static AI_Prompt_Component__c getMappedPromptComponent(ExportMappingWrapper.PromptComponentWrapper wrap, Map<String, AI_Data_Extraction_Detail__c> mapOfExtIdToDetail, Map<String, AI_Data_Extraction_Mapping__c> mapOfExtIdToMapping){
        AI_Prompt_Component__c obj = new AI_Prompt_Component__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Name = wrap.componentName;
        obj.Key__c = wrap.actionName;
        obj.Additional_Instructions__c = wrap.additionalInstructions;
        obj.Constraint_Value__c = wrap.constraintValue;
        String extId = wrap.dataExtractionId;

        if(mapOfExtIdToDetail != null && mapOfExtIdToDetail.containsKey(extId)){
            extId = mapOfExtIdToDetail.get(extId).Id;
        }else if(mapOfExtIdToMapping != null && mapOfExtIdToMapping.containsKey(extId)){
            extId = mapOfExtIdToMapping.get(extId).Id;
        }

        obj.Data_Extraction_Id__c = extId;
        obj.Format__c = wrap.format;
        obj.Language__c = wrap.language;
        obj.Length__c = wrap.length;
        obj.Object_Name__c = wrap.objectName;
        obj.Tone__c = wrap.tone;
        obj.User_Customizable__c = wrap.userCustomizable;
        obj.Phrase_Before_Action__c = wrap.phraseBeforeAction;
        obj.Language__c = wrap.phraseAfterAction;
        obj.Phrase_Before_Contraints__c = wrap.phraseBeforeContraints;
        obj.Phrase_After_Contraints__c = wrap.phraseAfterContraints;
        obj.Phrase_Before_Format__c = wrap.phraseBeforeFormat;
        obj.Phrase_After_Format__c = wrap.phraseAfterFormat;
        obj.Phrase_Before_Language__c = wrap.phraseBeforeLanguage;
        obj.Phrase_After_Language__c = wrap.phraseAfterLanguage;
        obj.Phrase_Before_Length__c = wrap.phraseBeforeLength;
        obj.Phrase_After_Length__c = wrap.phraseAfterLength;
        obj.Phrase_Before_Object__c = wrap.phraseBeforeObject;
        obj.Phrase_After_Object__c = wrap.phraseAfterObject;
        obj.Phrase_Before_Tone__c = wrap.phraseBeforeTone;
        obj.Phrase_After_Tone__c = wrap.phraseAfterTone;
        return obj;
    }
    
    public static AI_Prompt_Action__c getMappedPromptAction(ExportMappingWrapper.PromptActionWrapper wrap){
        AI_Prompt_Action__c obj = new AI_Prompt_Action__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Action__c = wrap.actionType;
        obj.Description__c = wrap.description ;
        obj.Sequence__c = wrap.sequence;
        obj.Object_Name__c = wrap.objectName;
        obj.Field_API_Name__c = wrap.fieldAPIName;
        obj.Flow_API_Name__c = wrap.flowAPIName ;
        obj.Apex_Class_Name__c = wrap.apexClassName;
        obj.Append_Timestamp__c = wrap.appendTimestamp;
        obj.Prompt_Component__c = wrap.promptComponent;
        return obj;
    }
    
    public static AI_Prompt_Action_Detail__c getMappedPromptActionDetail(ExportMappingWrapper.PromptActionDetailWrapper wrap){
        AI_Prompt_Action_Detail__c obj = new AI_Prompt_Action_Detail__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Field_API_Name__c = wrap.fieldAPIName;
        obj.Type__c = wrap.actionType;
        obj.Value__c = wrap.value;
        return obj;
    }
    
    /**
     * Retrieves the mapped AI response processing data based on the provided ExportMappingWrapper.ResponseProcessingWrapper object, facilitating the processing of AI response data accordingly.
     * 
     * @param wrap The ResponseProcessingWrapper object containing the necessary details for retrieving the mapped AI response processing data.
     * @return AI_Response_Processing__c An AI response processing record containing the mapped data for the AI response, ready for processing operations.
     */
    public static AI_Response_Processing__c getMappedResponseProcessing(ExportMappingWrapper.ResponseProcessingWrapper wrap){
        AI_Response_Processing__c obj = new AI_Response_Processing__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Action__c = wrap.actionName;
        obj.Description__c = wrap.description;
        obj.Destination_Field__c = wrap.destinationField;
        obj.Append_Timestamp__c = wrap.appendTimestamp;
        return obj;
    }
    
    /**
     * Retrieves the mapped field based on the provided ExportMappingWrapper.ExtractionFieldWrapper and mapping ID, providing the corresponding AI Data Extraction Field object.
     * 
     * @param wrap The ExportMappingWrapper.ExtractionFieldWrapper containing information about the mapped field.
     * @param mappingId The ID of the mapping associated with the field to be retrieved.
     * @return AI_Data_Extraction_Field__c The AI Data Extraction Field object representing the mapped field, ready for further processing or analysis.
     */
    public static AI_Data_Extraction_Field__c getMappedField(ExportMappingWrapper.ExtractionFieldWrapper wrap, String mappingId){
        AI_Data_Extraction_Field__c obj = new AI_Data_Extraction_Field__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Label__c = wrap.fieldName;
        obj.Field__c = wrap.fieldApi;
        obj.Object__c = wrap.objectName;
        obj.Type__c = wrap.type;
        obj.Anonymize_With__c = (String.isNotBlank(wrap.maskingScope) ? (wrap.maskingScope == 'Entire Value' ? wrap.anonymizeWith : '') : '');
        obj.Formula__c = wrap.formula; 
        obj.Field_Type__c = wrap.fieldType;
        obj.Masking_Scope__c = wrap.maskingScope;
        obj.Send_To_AI__c = wrap.sendToAi != null && wrap.sendToAi ? true : false;
        obj.AI_Data_Extraction_Mapping__c = mappingId;
        return obj;
    }
    
    /**
     * Retrieves the mapped data extraction detail based on the provided ExportMappingWrapper.ExtractionDetailWrapper object and mapping ID, allowing access to the corresponding AI data extraction detail.
     * 
     * @param wrap The ExportMappingWrapper.ExtractionDetailWrapper object containing information necessary for retrieving the mapped detail.
     * @param mappingId The ID of the mapping associated with the data extraction detail to be retrieved.
     * @return AI_Data_Extraction_Detail__c The AI data extraction detail record retrieved based on the provided wrapper object and mapping ID, ready for further processing or analysis.
     */
    public static AI_Data_Extraction_Detail__c getMappedDetail(ExportMappingWrapper.ExtractionDetailWrapper wrap, String mappingId){
        AI_Data_Extraction_Detail__c obj = new AI_Data_Extraction_Detail__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Name = wrap.detailName;
        obj.Object_Hierarchy__c = wrap.objectHierarchy;
        obj.Object_Name__c = wrap.objectName;
        obj.Order_By__c = wrap.orderBy;
        obj.RelationshipField__c = wrap.relationshipField;
        obj.RelationshipName__c = wrap.relationshipName;
        obj.Type__c = wrap.type;
        obj.Where_Clause__c = wrap.whereClause;
        obj.Record_Limit__c = wrap.recordLimit;
        obj.Running_Index__c = wrap.runningIndex;
        obj.AI_Data_Extraction_Mapping__c = mappingId;
        return obj;
    }
    
    /**
     * Retrieves the data extraction mapping based on the provided ExportMappingWrapper.ExtractionWrapper object, providing the relevant AI data extraction mapping.
     * 
     * @param wrap The ExportMappingWrapper.ExtractionWrapper object containing information necessary for retrieving the data extraction mapping.
     * @return AI_Data_Extraction_Mapping__c The AI data extraction mapping corresponding to the provided ExtractionWrapper, ready for further processing or analysis.
     */

    public static AI_Data_Extraction_Mapping__c getMappedDataExtractionMapping(ExportMappingWrapper.ExtractionWrapper wrap, Boolean isPostInstall){
        AI_Data_Extraction_Mapping__c obj = new AI_Data_Extraction_Mapping__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Name = wrap.mappingName;
        obj.Description__c = wrap.description;
        obj.Object_Name__c = wrap.objectName;
        if(isPostInstall){
            obj.Status__c = AIConstants.DATA_CONTEXT_STATUS_ACTIVE;
        }else{
            obj.Status__c = AIConstants.DATA_CONTEXT_STATUS_DRAFT;
        }
        return obj;
    }
    
    /**
     * Retrieves the mapped AI connection based on the provided ExportMappingWrapper.ConnectionWrapper object, facilitating the retrieval and processing of the mapped connection.
     * 
     * @param wrap The ConnectionWrapper object containing the necessary information and details for the mapped AI connection.
     * @return AI_Connection__c The AI connection record mapped based on the provided ConnectionWrapper, ready for further processing or analysis.
     */
	public static AI_Connection__c getMappedConnection(ExportMappingWrapper.ConnectionWrapper wrap){
        AI_Connection__c obj = new AI_Connection__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Name = wrap.connectionName;
        obj.AI_Technology__c = wrap.aiTechnology;
        obj.Connector_Class__c = wrap.connectorClass;
        obj.Processing_Class__c = wrap.processingClass;
        obj.EndPoint_URL__c = wrap.endpointUrl;
        obj.Key__c = wrap.key;
        obj.Max_Tokens__c = wrap.maxTokens;
        obj.Model__c = wrap.model;
        obj.Named_Credential__c = wrap.namedCredential;
        obj.Infrastructure__c = wrap.infrastructure;
        obj.Security_Layer__c = wrap.securityLayer;
        obj.Temperature__c = wrap.temperature;
        obj.Top_P__c = wrap.topP;
        obj.Version__c = wrap.version;
        return obj;
    }                                          
    
    /**
    * Retrieves the mapped AI prompt based on the provided ExportMappingWrapper.PromptWrapper object, map of external ID to data extraction, and map of external ID to AI connection.
    * 
    * @param wrap The ExportMappingWrapper.PromptWrapper object containing information for the mapped AI prompt.
    * @param mapOfExternalIdToDataExtraction A map where the keys represent external IDs, and the values contain the corresponding data extraction mappings.
    * @param mapOfExternalIdToConnection A map where the keys represent external IDs, and the values contain the corresponding AI connections.
    * @return AI_Prompt__c The AI prompt object retrieved based on the provided parameters and mappings, ready for further processing or analysis.
    */
    public static AI_Prompt__c getMappedPrompt(ExportMappingWrapper.PromptWrapper wrap, Map<String, AI_Data_Extraction_Mapping__c> mapOfExternalIdToDataExtraction, Map<String, AI_Connection__c> mapOfExternalIdToConnection, Boolean isPostInstall){
        AI_Prompt__c obj = new AI_Prompt__c();
        if(String.isNotBlank(wrap.promptRequestId)){
            obj.Prompt_Request_Id__c = wrap.promptRequestId;
        }

        if(String.isNotBlank(wrap.salesforceId)){
            obj.External_Id__c = wrap.salesforceId;
        }else if(String.isNotBlank(wrap.promptRequestId)){
            obj.External_Id__c = wrap.promptRequestId;
        }
        
        if(mapOfExternalIdToConnection.containsKey(wrap.connectionId)){
            obj.AI_Connection__c = mapOfExternalIdToConnection.get(wrap.connectionId).Id;
        }
        if(mapOfExternalIdToDataExtraction.containsKey(wrap.extractionMappingId)){
            obj.AI_Data_Extraction_Mapping__c = mapOfExternalIdToDataExtraction.get(wrap.extractionMappingId).Id;
        }
        obj.Name = wrap.promptName;
        obj.Description__c = wrap.description;
        obj.Object__c = wrap.objectName;
        //obj.Target_Field__c = wrap.targetField;/*#JIRA-4986:Prompt Action Framework*/
        //obj.Append_Timestamp__c = wrap.appendTimestamp;/*#JIRA-4986:Prompt Action Framework*/
        obj.Custom_Prompt__c = wrap.allowUserInput != null && wrap.allowUserInput ? true : false;
        obj.Profiles__c = wrap.profiles;
        obj.Grounding_Content__c = wrap.groundingContent;
        obj.Grounding_Ethical__c = wrap.groundingEthical;
        obj.Prompt_Command__c = wrap.promptCommand;
        obj.Purpose__c = wrap.purpose;
        obj.Record_Type__c = wrap.recordTypes;
        obj.Type__c = wrap.type;
        obj.Top_P__c = wrap.topP;
        obj.Temperature__c = wrap.temperature;
        obj.Max_Output_Tokens__c = wrap.maxTokens; 
        obj.Visibility_Condition__c = wrap.visibilityCondition;
        obj.How_It_Works__c = wrap.howItWorks;
        obj.AI_Locale_Automation__c = wrap.localeAutomation;
        obj.AI_Locale_GPTfy_Console__c = wrap.localeGPTfyConsole;
        obj.Include_Files__c = wrap.includeFiles != null && wrap.includeFiles ? true : false;
        
        if(isPostInstall){
            obj.Status__c = AIConstants.PMT_STATUS_ACTIVE;
            obj.Pre_Packaged__c = true;
        }else{
            obj.Status__c = AIConstants.PMT_STATUS_DRAFT;
        }

        if(wrap.autoRefreshDuration != null){
            obj.Auto_Refresh_Duration__c = wrap.autoRefreshDuration;
        }
        return obj;
    }
    
    /**
     * Retrieves the mapped AI security filters based on the provided ExportMappingWrapper.ExtractionSecurityFilterWrapper, facilitating the extraction and application of security filters for data export operations.
     * 
     * @param wrap The ExportMappingWrapper.ExtractionSecurityFilterWrapper containing the necessary details for retrieving and mapping the AI security filters.
     * @return AI_Security_Filters__c The AI security filters mapped and retrieved based on the provided wrapper, ready for application during the data export process.
     */
    public static AI_Security_Filters__c getMappedFilters(ExportMappingWrapper.ExtractionSecurityFilterWrapper wrap){
        AI_Security_Filters__c obj = new AI_Security_Filters__c();
        obj.Name =  wrap.filterName;
        obj.Search_Pattern__c = wrap.searchPattern;
        obj.Status__c = wrap.status;
        obj.Type__c = wrap.type;
        obj.Blocklist__c = wrap.blocklist;
        obj.Comment__c = wrap.comment;
        obj.External_Id__c = wrap.salesforceId;
        if(wrap.recordTypeName == 'Regex'){
            obj.RecordTypeId = RT_REGEX;
        }else if(wrap.recordTypeName == 'Blocklist'){
            obj.RecordTypeId = RT_BLOCKLIST;
        }
        return obj;
    }
    
    public static AI_Data_Source__c getDataSource(ExportMappingWrapper.DataSourceWrapper wrap){
        AI_Data_Source__c obj = new AI_Data_Source__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Connector_Class__c = wrap.connectorClass;
        obj.name = wrap.name;
        obj.EndPoint_URL__c = wrap.endpointUrl;
        obj.Named_Credential__c = wrap.namedCredential;
        obj.Source__c = wrap.source;
        return obj;
    }
    
}