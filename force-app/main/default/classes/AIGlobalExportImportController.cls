/**
 * @description       : 
 * @author            : Adarsh Sharma
 * @group             : Plumcloud Labs
 * @last modified on  : 30-05-2025
 * @last modified by  : Adarsh Sharma
**/
public with sharing class AIGlobalExportImportController {
	
    public STATIC String RT_REGEX = (String)Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Regex').getRecordTypeId();
    public STATIC String RT_APEX = (String)Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Apex').getRecordTypeId();
    public STATIC String RT_BLOCKLIST = (String)Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Blocklist').getRecordTypeId();
    
    
    @AuraEnabled
    public static ExportMappingWrapper getInitData(){
        ExportMappingWrapper wrap = new ExportMappingWrapper();
        wrap.exportedOn = System.today();
        wrap.orgId = UserInfo.getOrganizationId();
        wrap.exportedBy = UserInfo.getName();
        wrap = getExport(wrap);
        return wrap;
    }
    
    @AuraEnabled
    public static map<string, object> readFileData(String fileData){
        map<string, object> mapOfData = new map<string, object>();
        try{
            ImportMappingWrapper wrap = (ImportMappingWrapper)System.JSON.deserialize(fileData, ImportMappingWrapper.class);
            if(wrap != null){
                mapOfData.put('hasError', false);
                	mapOfData.put('data', wrap);
            }else{
                mapOfData.put('hasError', true);
                mapOfData.put('message', 'Empty Export File.');
            }
            return mapOfData;
        }catch(Exception e){
            mapOfData.put('hasError', true);
            mapOfData.put('message', e.getMessage());
            GPTfyException.log(e, 'GPTfy', '', 'AIGlobalExportImportController', 'readFileData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void saveMappings(List<ImportMappingWrapper.PromptWrapper> prompts, List<ImportMappingWrapper.ConnectionWrapper> connections, List<ImportMappingWrapper.ExtractionWrapper> mappings, List<ImportMappingWrapper.ExtractionSecurityFilterWrapper> filters, List<ImportMappingWrapper.DataSourceWrapper> dataSources, List<ImportMappingWrapper.CardConfigurationWrapper> catalogCards, Boolean isPostInstall){
       	try{
        	insertPrompts(prompts, connections, mappings, filters, dataSources, catalogCards, isPostInstall);
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptImportController', 'saveMappings', '');
            if(isPostInstall != null && !isPostInstall){
                throw new AuraHandledException(e.getMessage());
            }
        } 
    }
    
    //@Jira V2-7132
    public static void insertPrompts(List<ImportMappingWrapper.PromptWrapper> prompts, List<ImportMappingWrapper.ConnectionWrapper> connections, List<ImportMappingWrapper.ExtractionWrapper> mappings, List<ImportMappingWrapper.ExtractionSecurityFilterWrapper> filters, List<ImportMappingWrapper.DataSourceWrapper> dataSources, List<ImportMappingWrapper.CardConfigurationWrapper> catalogCards, Boolean isPostInstall){
        Map<String, AI_Data_Extraction_Mapping__c> mapOfExternalIdToDataExtraction = new Map<String, AI_Data_Extraction_Mapping__c>();
        Map<String, AI_Data_Extraction_Detail__c> mapOfExtIdToDetailToUpsert = new Map<String, AI_Data_Extraction_Detail__c>();
        Map<String, AI_Connection__c> mapOfExternalIdToConnection = new Map<String, AI_Connection__c>();
        Map<String, AI_Data_Source__c> mapOfExternalIdToDataSource = new Map<String, AI_Data_Source__c>();
        Map<String, AI_Card_Configuration__c> mapOfExternalIdToCatalogCards = new Map<String, AI_Card_Configuration__c>();
        
        //inserting connection records
        for(ImportMappingWrapper.ConnectionWrapper wrap : connections){
             mapOfExternalIdToConnection.put(wrap.salesforceId, getMappedConnection(wrap));
            if(wrap.cardDetails != null){
                mapOfExternalIdToCatalogCards.put(wrap.cardDetails.salesforceId, getCardConfiguration(wrap.cardDetails, false));
            }
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
            for(ImportMappingWrapper.DataSourceWrapper wrap : dataSources){
                mapOfExternalIdToDataSource.put(wrap.salesforceId, getDataSource(wrap));
                if(wrap.cardDetails != null){
                    mapOfExternalIdToCatalogCards.put(wrap.cardDetails.salesforceId, getCardConfiguration(wrap.cardDetails, false));
                }
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
        
        //Security Filters
        Set<String> setOfUniqueFilters = new Set<String>();
        Map<String, AI_Security_Filters__c> mapOfExternalIdToFilters = new Map<String, AI_Security_Filters__c>();
        Map<String, AI_Security_Filters__c> mapOfNameToExistingFilters = new Map<String, AI_Security_Filters__c>();
        for(AI_Security_Filters__c sf : [SELECT Id, Name, Search_Pattern__c, External_Id__c FROM AI_Security_Filters__c LIMIT 9999]){
            setOfUniqueFilters.add(sf.Name);
            mapOfNameToExistingFilters.put(sf.Name, sf);
        }
        
        for(ImportMappingWrapper.ExtractionSecurityFilterWrapper wrap : filters){
            if(setOfUniqueFilters.size() == 0 || !setOfUniqueFilters.contains(wrap.filterName) || test.isRunningTest()){
                mapOfExternalIdToFilters.put(wrap.salesforceId, getMappedFilters(wrap));
            }
            if(mapOfNameToExistingFilters != null && mapOfNameToExistingFilters.containsKey(wrap.filterName)){
                mapOfExternalIdToFilters.put(wrap.salesforceId, mapOfNameToExistingFilters.get(wrap.filterName));
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
            for(String key : cleanedRecords.keySet()){
                mapOfExternalIdToFilters.put(key, (AI_Security_Filters__c)cleanedRecords.get(key));
            }
        }
        
        //inserting data extraction mapping records
        for(ImportMappingWrapper.ExtractionWrapper wrap : mappings){
        	AI_Data_Extraction_Mapping__c em = getMappedDataExtractionMapping(wrap, isPostInstall);
            if(wrap.dataSourceId != null && mapOfExternalIdToDataSource != null && mapOfExternalIdToDataSource.containsKey(wrap.dataSourceId)){
               em.AI_Data_Source__c = mapOfExternalIdToDataSource.get(wrap.dataSourceId).Id;
            }
            if(wrap.apexSecurityLayerId != null && mapOfExternalIdToFilters != null && mapOfExternalIdToFilters.containsKey(wrap.apexSecurityLayerId)){
               em.Apex_Security_Layer__c = mapOfExternalIdToFilters.get(wrap.apexSecurityLayerId).Id;
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
            List<ImportMappingWrapper.ExtractionDetailWrapper> lstOfParentDetailWrappers = new List<ImportMappingWrapper.ExtractionDetailWrapper>();
                
            for(ImportMappingWrapper.ExtractionWrapper wrap : mappings){
                if(mapOfExternalIdToDataExtraction.containsKey(wrap.salesforceId)){
                    String dataExtMappingId = mapOfExternalIdToDataExtraction.get(wrap.salesforceId).Id;
                    if(wrap.details != null && !wrap.details.isEmpty()){
                        for(ImportMappingWrapper.ExtractionDetailWrapper d_wrap : wrap.details){
                        	mapOfExtIdToDetailToUpsert.put(d_wrap.salesforceId, getMappedDetail(d_wrap, dataExtMappingId));
                            
                            if(String.isNotBlank(d_wrap.parentDetailId)){
                                lstOfParentDetailWrappers.add(d_wrap);
                            }
                    	}
                    }
                    if(wrap.fields != null && !wrap.fields.isEmpty()){
                        for(ImportMappingWrapper.ExtractionFieldWrapper f_wrap : wrap.fields){
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
                    for(ImportMappingWrapper.ExtractionDetailWrapper d_wrap : lstOfParentDetailWrappers){
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
        List<ExportMappingWrapper.PromptResponseValidationWrapper> listOfPromptResponseValidations = new List<ExportMappingWrapper.PromptResponseValidationWrapper>();
        
        Map<String, String> mapOfRespProIdToParentId = new Map<String, String>();
        Map<String, String> mapOfCmpIdToParentId = new Map<String, String>();
        Map<String, String> mapOfPromActionDetailProIdToParentId = new Map<String, String>();
        
        for(ImportMappingWrapper.PromptWrapper wrap : prompts){
            mapOfExternalIdToPrompt.put(wrap.salesforceId, getMappedPrompt(wrap, mapOfExternalIdToDataExtraction, mapOfExternalIdToConnection, isPostInstall));
            
            if(wrap.promptComponents != null && !wrap.promptComponents.isEmpty()){
                for(ImportMappingWrapper.PromptComponentWrapper c_wrap : wrap.promptComponents){
                    mapOfExternalIdToPromptComponent.put(c_wrap.salesforceId, getMappedPromptComponent(c_wrap, mapOfExtIdToDetailToUpsert, mapOfExternalIdToDataExtraction));
                    mapOfCmpIdToParentId.put(c_wrap.salesforceId, wrap.salesforceId);
                    
                    if(c_wrap.responseProcessings != null && !c_wrap.responseProcessings.isEmpty()){
                        for(ImportMappingWrapper.ResponseProcessingWrapper rp_wrap : c_wrap.responseProcessings){
                            mapOfExternalIdToRespProcessing.put(rp_wrap.salesforceId, getMappedResponseProcessing(rp_wrap));
                            mapOfRespProIdToParentId.put(rp_wrap.salesforceId, c_wrap.salesforceId);
                        }
                    }
                }
            }
            
            if(wrap.promptActions != null && !wrap.promptActions.isEmpty()){
                for(ImportMappingWrapper.PromptActionWrapper pa_wrap : wrap.promptActions){
                    mapOfExternalIdToPromptAction.put(pa_wrap.salesforceId, getMappedPromptAction(pa_wrap));
                    mapOfCmpIdToParentId.put(pa_wrap.salesforceId, wrap.salesforceId);
                    
                    if(pa_wrap.promptActionDetails != null && !pa_wrap.promptActionDetails.isEmpty()){
                        for(ImportMappingWrapper.PromptActionDetailWrapper pad_wrap : pa_wrap.promptActionDetails){
                            mapOfExternalIdToPromptActionDetail.put(pad_wrap.salesforceId, getMappedPromptActionDetail(pad_wrap));
                            mapOfPromActionDetailProIdToParentId.put(pad_wrap.salesforceId, pa_wrap.salesforceId);
                        }
                    }
                    
                }
            }
            if(wrap.promptElements != null && !wrap.promptElements.isEmpty()){
                listOfPromptElements.addAll(
                    (List<ExportMappingWrapper.PromptElementWrapper>)JSON.deserialize(JSON.serialize(wrap.promptElements), List<ExportMappingWrapper.PromptElementWrapper>.class));
            }
            //Jira 7221:  Issues/Feedbacks from 1.12 Testing
            if(wrap.promptResponseValidations != null && !wrap.promptResponseValidations.isEmpty()){
                listOfPromptResponseValidations.addAll(
                    (List<ExportMappingWrapper.PromptResponseValidationWrapper>)JSON.deserialize(JSON.serialize(wrap.promptResponseValidations), List<ExportMappingWrapper.PromptResponseValidationWrapper>.class));
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
                    mapOfExternalIdToPromptElements.put(pe_wrap.salesforceId, getMappedPromptElementRecord(pe_wrap, mapOfExternalIdToPrompt));
                }
                Map<String, SObject> cleanedPromptElementRecords = (Map<String, SObject>)mapOfExternalIdToPromptElements;
                if(isPostInstall){
                    cleanedPromptElementRecords = FLSCheck.getInstance().upsertDML(cleanedPromptElementRecords, true);
                }else{
                    cleanedPromptElementRecords = FLSCheck.getInstance().upsertDML(cleanedPromptElementRecords, AI_Prompt_Element__c.Fields.External_Id__c, true);
                }
            }
            //Jira 7221:  Issues/Feedbacks from 1.12 Testing
            //@Jira V2-7132
            if(!listOfPromptResponseValidations.isEmpty()){
                Map<String, AI_Prompt_Response_Validation__c> mapOfExternalIdToPromptResponseValidations = new Map<String, AI_Prompt_Response_Validation__c>();

                for(ExportMappingWrapper.PromptResponseValidationWrapper pe_wrap : listOfPromptResponseValidations){
                    mapOfExternalIdToPromptResponseValidations.put(pe_wrap.salesforceId, getMappedPromptResponseValidationRecord(pe_wrap, mapOfExternalIdToPrompt));
                }
                Map<String, SObject> cleanedPromptRespValidationRecords = (Map<String, SObject>)mapOfExternalIdToPromptResponseValidations;
                if(isPostInstall){
                    cleanedPromptRespValidationRecords = FLSCheck.getInstance().upsertDML(cleanedPromptRespValidationRecords, true);
                }else{
                    cleanedPromptRespValidationRecords = FLSCheck.getInstance().upsertDML(cleanedPromptRespValidationRecords, AI_Prompt_Response_Validation__c.Fields.External_Id__c, true);
                }
            }
        }

        if(catalogCards != null && catalogCards.size()>0){
            for(ImportMappingWrapper.CardConfigurationWrapper wrap : catalogCards){
                mapOfExternalIdToCatalogCards.put(wrap.salesforceId, getCardConfiguration(wrap, true));
            }
        }
        if(!mapOfExternalIdToCatalogCards.isEmpty()){
            Map<String, SObject> cleanedRecords = (Map<String, SObject>)mapOfExternalIdToCatalogCards;
            //cleanedRecords = FLSCheck.getInstance().upsertCheck(cleanedRecords);
            if(isPostInstall){
                cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, true);
            }else{
                cleanedRecords = FLSCheck.getInstance().upsertDML(cleanedRecords, AI_Card_Configuration__c.Fields.External_Id__c,  true);
            }
        }
    }
    
    public static ExportMappingWrapper getExport(ExportMappingWrapper wrap){
        Map<String, ExportMappingWrapper.PromptWrapper> prompts = new Map<String, ExportMappingWrapper.PromptWrapper>();
        Map<String, ExportMappingWrapper.ConnectionWrapper> mapOfConnections = new Map<String, ExportMappingWrapper.ConnectionWrapper>();
        Map<String, ExportMappingWrapper.ExtractionWrapper> mapOfMappings = new Map<String, ExportMappingWrapper.ExtractionWrapper>();
        Map<String, ExportMappingWrapper.DataSourceWrapper> mapOfDataSources = new Map<String, ExportMappingWrapper.DataSourceWrapper>();
        Map<String, AI_Card_Configuration__c> mapOfDataSourcesCard = new Map<String, AI_Card_Configuration__c>();

        Set<String> setOfCardNames = new Set<String>();
        
        String activeStatus = AIConstants.PMT_STATUS_ACTIVE;
        
        String sSOQL = 'SELECT Id, Name, Description__c, Object__c, Profiles__c, Prompt_Command__c, Purpose__c, Record_Type__c, Status__c, Type__c, '; //Target_Field__c,Append_Timestamp__c,/*#JIRA-4986:Prompt Action Framework*/
        sSOQL += 'Custom_Prompt__c, Grounding_Ethical__c, Grounding_Content__c, Include_Files__c,Auto_Refresh_Duration__c, AI_Model_File_Processing__c, ';
        sSOQL += 'AI_Connection__c, Top_P__c, Max_Output_Tokens__c, Temperature__c, How_It_Works__c, AI_Connection__r.Name, AI_Connection__r.AI_Technology__c, AI_Connection__r.Connector_Class__c, ';
        sSOQL += 'AI_Connection__r.Processing_Class__c, AI_Connection__r.EndPoint_URL__c, AI_Connection__r.Key__c, AI_Connection__r.Max_Tokens__c, AI_Connection__r.Model__c, ';
        sSOQL += 'AI_Connection__r.Named_Credential__c, AI_Connection__r.Infrastructure__c, AI_Connection__r.Security_Layer__c, ';
        sSOQL += 'AI_Connection__r.Temperature__c, AI_Connection__r.Top_P__c, AI_Connection__r.Version__c, Prompt_Request_Id__c, ';
        sSOQL += 'AI_Data_Extraction_Mapping__c, AI_Data_Extraction_Mapping__r.Name, AI_Data_Extraction_Mapping__r.Description__c, AI_Data_Extraction_Mapping__r.Apex_Security_Layer__c, ';
        sSOQL += 'AI_Data_Extraction_Mapping__r.Object_Name__c, Prompt_Version__c, Visibility_Condition__c, AI_Data_Extraction_Mapping__r.AI_Data_Source__c, ';
        sSOQL += 'AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Name, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Connector_Class__c,';
        sSOQL += 'AI_Data_Extraction_Mapping__r.AI_Data_Source__r.EndPoint_URL__c, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Named_Credential__c, ';
        sSOQL += 'AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Source__c, AI_Locale_Automation__c, AI_Locale_GPTfy_Console__c, Permission_Sets__c, Enable_Loopback__c, Loopback_Message__c, Agentic_Function_Class__c, ';
        sSOQL += 'Response_Validation_Condition__c, Response_Validation_Message__c, Time_Saved_Coefficient__c ';
        sSOQL += 'FROM AI_Prompt__c ';
        sSOQL += 'WHERE Status__c =:activeStatus AND AI_Connection__c != NULL AND AI_Data_Extraction_Mapping__c != NULL ';
        sSOQL += 'ORDER BY Name, Object__c';
        
        for(AI_Prompt__c obj : database.query(sSOQL)){
            /*if(!mapOfConnections.containsKey(obj.AI_Connection__c)){
                mapOfConnections.put(obj.AI_Connection__c, AIPromptExportController.getMappedConnection(obj.AI_Connection__r));
            } */
            
            if(obj.AI_Data_Extraction_Mapping__c != null && obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__c != null){
                if(!mapOfDataSources.containskey(obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__c)){
                    mapOfDataSourcesCard.put(obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Name, null);
                    mapOfDataSources.put(obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__c, AIPromptExportController.getDataSource(obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__r));
                }
            }
            
            if(!mapOfMappings.containsKey(obj.AI_Data_Extraction_Mapping__c)){
                mapOfMappings.put(obj.AI_Data_Extraction_Mapping__c, getMappedExtractionMapping(obj.AI_Data_Extraction_Mapping__r));
            }
            prompts.put(obj.Id, getMappedPrompt(obj));
        }
        
        for(AI_Card_Configuration__c cardConfiguration : [SELECT Id, Name, Description__c, Icon_Details__c, Icon_Source__c, Sequence__c, Feature__c, Enabled__c FROM AI_Card_Configuration__c
                                                          WHERE Feature__c='APIDS' AND Icon_Details__c != NULL AND Enabled__c=true 
                                                          ORDER BY Sequence__c LIMIT 50000]){
             mapOfDataSourcesCard.put(cardConfiguration.Name, cardConfiguration);
        }

        if(!mapOfDataSourcesCard.IsEmpty()){
            for(ExportMappingWrapper.DataSourceWrapper datawrap : mapOfDataSources.values()){
                if(mapOfDataSourcesCard.containsKey(datawrap.name) && mapOfDataSourcesCard.get(datawrap.name) != null){
                    datawrap.cardDetails = AICardConfigurationExportController.getMappedWrapper(mapOfDataSourcesCard.get(datawrap.name));
                }
            }
            for(AI_Data_Source__c dataSource : [SELECT Id, Name, Named_Credential__c, Source__c, EndPoint_URL__c, Connector_Class__c, External_Id__c 
                                                FROM AI_Data_Source__c WHERE Name IN:mapOfDataSourcesCard.keyset()]){
                if(mapOfDataSourcesCard.get(dataSource.Name) != null){
                    ExportMappingWrapper.DataSourceWrapper datawrap = AIPromptExportController.getDataSource(dataSource);
                    datawrap.cardDetails = AICardConfigurationExportController.getMappedWrapper(mapOfDataSourcesCard.get(dataSource.Name));                                    
                    mapOfDataSources.put(dataSource.Id, datawrap);
                }
            }

            
        }
        
        Map<String, AI_Card_Configuration__c> mapCardNames = new Map<String, AI_Card_Configuration__c>();
        for(AI_Card_Configuration__c cardConfiguration : [SELECT Id, Name, Description__c, Icon_Details__c, Icon_Source__c, Sequence__c, Feature__c, Enabled__c FROM AI_Card_Configuration__c
                                                          WHERE Feature__c='AMODL' AND Icon_Details__c != NULL
                                                          ORDER BY Sequence__c LIMIT 50000]){
            mapCardNames.put(cardConfiguration.Name, cardConfiguration);
        }
        
        for(AI_Connection__c connection : [SELECT Id, Name, AI_Technology__c, Connector_Class__c, Processing_Class__c, EndPoint_URL__c, Key__c, 
                                           Max_Tokens__c, Model__c, Named_Credential__c, Infrastructure__c, Security_Layer__c, 
                                           Temperature__c, Top_P__c, Version__c, Type__c FROM AI_Connection__c
                                          WHERE Name IN: mapCardNames.keyset() LIMIT 50000]){
            if(!mapOfConnections.containsKey(connection.Id) && mapCardNames.containskey(connection.Name)){
                ExportMappingWrapper.ConnectionWrapper connwrap = AIPromptExportController.getMappedConnection(connection);
                AI_Card_Configuration__c cardConfiguration = mapCardNames.get(connection.Name);
                connwrap.active = cardConfiguration.Enabled__c;
                connwrap.cardDetails = AICardConfigurationExportController.getMappedWrapper(cardConfiguration);
                mapOfConnections.put(connection.Id, connwrap);
            } 
        }
        
        if(!prompts.isEmpty()){
            List<AI_Prompt_Component__c> lstOfComponents = [SELECT Id, Key__c, Additional_Instructions__c, AI_Prompt__c, Name, Constraint_Value__c, Data_Extraction_Id__c,
                                                            Format__c, Language__c, Length__c, Object_Name__c, Tone__c, User_Customizable__c,
                                                            Phrase_Before_Action__c, Phrase_After_Action__c, Phrase_Before_Contraints__c, Phrase_After_Contraints__c,
                                                            Phrase_Before_Format__c, Phrase_After_Format__c, Phrase_Before_Language__c, Phrase_After_Language__c,
                                                            Phrase_Before_Length__c, Phrase_After_Length__c, Phrase_Before_Object__c, Phrase_After_Object__c,
                                                            Phrase_Before_Tone__c, Phrase_After_Tone__c, 
                                                            (SELECT Id, Action__c, Description__c, Destination_Field__c, Append_Timestamp__c FROM AI_Response_Processing__r)
                                                            FROM AI_Prompt_Component__c WHERE AI_Prompt__c IN :prompts.keySet()];
            if(lstOfComponents != null && !lstOfComponents.isEmpty()){
                for(AI_Prompt_Component__c obj : lstOfComponents){
                    prompts.get(obj.AI_Prompt__c).promptComponents.add(getMappedPromptComponent(obj));
                }
            }
            
            List<AI_Prompt_Action__c> lstOfActions = [SELECT Id, Action__c, Field_API_Name__c, Apex_Class_Name__c, Flow_API_Name__c, 
                                                      Sequence__c, Object_Name__c, Prompt_Component__c, Action_Label__c, Description__c, 
                                                      Append_Timestamp__c, AI_Prompt__c, 
                                                      (SELECT Id, Field_API_Name__c, Type__c, Value__c FROM Prompt_Action_Details__r) 
                                                      FROM AI_Prompt_Action__c WHERE AI_Prompt__c IN :prompts.keySet()];
            if(lstOfActions != null && !lstOfActions.isEmpty()){
                for(AI_Prompt_Action__c obj : lstOfActions){
                    prompts.get(obj.AI_Prompt__c).promptActions.add(AIPromptExportController.getMappedPromptAction(obj));
                }
            }
            List<AI_Data_Extraction_Field__c> lstOfExtractionFields = [SELECT Id, AI_Data_Extraction_Mapping__c, Anonymize_With__c, Field__c, Name, Label__c, Object__c, 
                                                                       Type__c, Field_Type__c, Masking_Scope__c, Formula__c, Send_To_AI__c FROM AI_Data_Extraction_Field__c 
                                                                       WHERE AI_Data_Extraction_Mapping__c IN :mapOfMappings.KeySet()];
            if(lstOfExtractionFields != null && !lstOfExtractionFields.isEmpty()){
                for(AI_Data_Extraction_Field__c obj : lstOfExtractionFields){
                    mapOfMappings.get(obj.AI_Data_Extraction_Mapping__c).fields.add(AIPromptExportController.getMappedField(obj));
                }
            }
            
            List<AI_Data_Extraction_Detail__c> lstOfExtractionDetails = [SELECT Id, Name, AI_Data_Extraction_Mapping__c, Object_Hierarchy__c, Object_Name__c, Order_By__c,
                                                                        Parent_Detail__c, Record_Limit__c, RelationshipField__c, RelationshipName__c, Running_Index__c,
                                                                        Type__c, Where_Clause__c FROM AI_Data_Extraction_Detail__c 
                                                                       	WHERE AI_Data_Extraction_Mapping__c IN :mapOfMappings.KeySet()];
            if(lstOfExtractionDetails != null && !lstOfExtractionDetails.isEmpty()){
                for(AI_Data_Extraction_Detail__c obj : lstOfExtractionDetails){
                    mapOfMappings.get(obj.AI_Data_Extraction_Mapping__c).details.add(AIPromptExportController.getMappedDetail(obj));
                }
            }
            List<AI_Prompt_Element__c> lstOfPromptElements = [SELECT Id, Name, Inherit_Prompt_Security__c, Height__c, Icon__c, AI_Parent_Prompt__c,
                                                                    AI_Prompt__c, Sequence__c, AI_Summary_Prompt__c, Width__c, AI_Parent_Prompt__r.Prompt_Request_Id__c,
                                                                    AI_Prompt__r.Prompt_Request_Id__c, AI_Summary_Prompt__r.Prompt_Request_Id__c
                                                                FROM AI_Prompt_Element__c 
                                                                WHERE AI_Parent_Prompt__c IN :prompts.KeySet()];
            if(lstOfPromptElements != null && !lstOfPromptElements.isEmpty()){
                for(AI_Prompt_Element__c obj : lstOfPromptElements){
                    prompts.get(obj.AI_Parent_Prompt__c).promptElements.add(AIPromptExportController.getMappedPromptElement(obj));
                }
            }

            // Jira 7221:  Issues/Feedbacks from 1.12 Testing
            List<AI_Prompt_Response_Validation__c> lstOfRespValidation = [SELECT Id, AI_Prompt__c, Action__c, Value__c, Sequence__c 
                                                                            FROM AI_Prompt_Response_Validation__c 
                                                                                WHERE AI_Prompt__c IN :prompts.keySet()];
            if(lstOfRespValidation != null && !lstOfRespValidation.isEmpty()){
                for(AI_Prompt_Response_Validation__c obj : lstOfRespValidation){
                    prompts.get(obj.AI_Prompt__c).promptResponseValidations.add(AIPromptExportController.getMappedPromptResponseValidation(obj));
                }
            }
        }
        Map<String, List<ExportMappingWrapper.ExtractionSecurityFilterWrapper>> mapSecurityFilters = new Map<String, List<ExportMappingWrapper.ExtractionSecurityFilterWrapper>>();
        for(AI_Security_Filters__c sf : [SELECT Id, Name, RecordTypeId, RecordType.Name, Blocklist__c, 
                                         Comment__c, Replacement_Value__c, Search_Pattern__c, Status__c, Type__c, Apex_Class_Name__c  
                                         FROM AI_Security_Filters__c WHERE Status__c = 'Active' LIMIT 50000]){
            if(!mapSecurityFilters.containsKey(sf.RecordType.Name)){
               mapSecurityFilters.put(sf.RecordType.Name, new List<ExportMappingWrapper.ExtractionSecurityFilterWrapper>());
            }
            mapSecurityFilters.get(sf.RecordType.Name).add(getSecurityFilters(sf));
       }
        
        List<ExportMappingWrapper.CardConfigurationWrapper> lstOfWrapper = new List<ExportMappingWrapper.CardConfigurationWrapper>();
        List<AI_Card_Configuration__c> lst = [SELECT Id, Name, Description__c, Icon_Details__c, Icon_Source__c, Sequence__c, Feature__c, Enabled__c
                                              FROM AI_Card_Configuration__c WHERE Feature__c =  'CTLOG'
                                              ORDER BY Feature__c, Sequence__c, Name LIMIT 50000];
        if(lst != null && !lst.isEmpty()){
            for(AI_Card_Configuration__c cc : lst){
                ExportMappingWrapper.CardConfigurationWrapper ccwrap = AICardConfigurationExportController.getMappedWrapper(cc);
                lstOfWrapper.add(ccwrap);
            }
        }
        
        wrap.prompts = prompts.values();
        wrap.connections = mapOfConnections;
        wrap.dataExtractionMappings = mapOfMappings;
        if(mapOfDataSources != null && !mapOfDataSources.isEmpty()){
            wrap.dataSources = mapOfDataSources.values();
        }
        wrap.securityFilters = mapSecurityFilters;
        wrap.cardConfigs = lstOfWrapper;
        return wrap;
    }
    //@Jira V2-7132
    public static ExportMappingWrapper.PromptWrapper getMappedPrompt(AI_Prompt__c obj){
        ExportMappingWrapper.PromptWrapper wrap = new ExportMappingWrapper.PromptWrapper();
        wrap.salesforceId = obj.Id;
        wrap.connectionId = obj.AI_Connection__c;
        wrap.extractionMappingId = obj.AI_Data_Extraction_Mapping__c;
        wrap.promptName = obj.Name;
        wrap.description = obj.Description__c;
        wrap.objectName = obj.Object__c;
        wrap.profiles = obj.Profiles__c;
        // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
        wrap.permissionSets = obj.Permission_Sets__c;
        wrap.timeSavedCoefficient = obj.Time_Saved_Coefficient__c;
        wrap.groundingContent = obj.Grounding_Content__c;
        wrap.groundingEthical = obj.Grounding_Ethical__c;
        wrap.localeAutomation = obj.AI_Locale_Automation__c;
        wrap.localeGPTfyConsole = obj.AI_Locale_GPTfy_Console__c;
        wrap.promptCommand = obj.Prompt_Command__c;
        wrap.purpose = obj.Purpose__c;
        wrap.recordTypes = obj.Record_Type__c;
        wrap.type = obj.Type__c;
        wrap.topP = obj.Top_P__c;
        wrap.temperature = obj.Temperature__c;
        wrap.maxTokens = obj.Max_Output_Tokens__c;
        wrap.connectionName = obj.AI_Connection__r.Name;
        wrap.extractionMappingName = obj.AI_Data_Extraction_Mapping__r.Name;
        wrap.promptComponents = new List<ExportMappingWrapper.PromptComponentWrapper>();
        wrap.promptActions = new List<ExportMappingWrapper.PromptActionWrapper>();
        wrap.promptElements = new List<ExportMappingWrapper.PromptElementWrapper>();
        wrap.promptResponseValidations = new List<ExportMappingWrapper.PromptResponseValidationWrapper>();
        wrap.promptRequestId = obj.Prompt_Request_Id__c;
        wrap.visibilityCondition = obj.Visibility_Condition__c;
        wrap.allowUserInput = obj.Custom_Prompt__c;
        wrap.howItWorks = obj.How_it_works__c;
        wrap.includeFiles = obj.Include_Files__c;
        wrap.autoRefreshDuration = Integer.valueOf(obj.Auto_Refresh_Duration__c);
        wrap.enableLoopback = obj.Enable_Loopback__c != null && obj.Enable_Loopback__c ? true : false;
        wrap.loopbackMessage = obj.Loopback_Message__c ;
        wrap.responseValidationCondition = obj.Response_Validation_Condition__c;
        wrap.responseValidationMessage = obj.Response_Validation_Message__c;
        wrap.agenticFunctionClass = obj.Agentic_Function_Class__c;
        wrap.aIModelFileProcessing = obj.AI_Model_File_Processing__c;
        return wrap;
    }
    
    public static ExportMappingWrapper.PromptComponentWrapper getMappedPromptComponent(AI_Prompt_Component__c obj){
        ExportMappingWrapper.PromptComponentWrapper wrap = new ExportMappingWrapper.PromptComponentWrapper();
        wrap.salesforceId = obj.Id;
        wrap.componentName = obj.Name;
        wrap.actionName = obj.Key__c;
        wrap.additionalInstructions = obj.Additional_Instructions__c;
        wrap.constraintValue = obj.Constraint_Value__c;
        wrap.dataExtractionId = obj.Data_Extraction_Id__c;
        wrap.format = obj.Format__c;
        wrap.language = obj.Language__c;
        wrap.length = obj.Length__c;
        wrap.objectName = obj.Object_Name__c;
        wrap.tone = obj.Tone__c;
        wrap.userCustomizable = obj.User_Customizable__c;
        wrap.phraseBeforeAction = obj.Phrase_Before_Action__c;
        wrap.phraseAfterAction = obj.Language__c;
        wrap.phraseBeforeContraints = obj.Phrase_Before_Contraints__c;
        wrap.phraseAfterContraints = obj.Phrase_After_Contraints__c;
        wrap.phraseBeforeFormat = obj.Phrase_Before_Format__c;
        wrap.phraseAfterFormat = obj.Phrase_After_Format__c;
        wrap.phraseBeforeLanguage = obj.Phrase_Before_Language__c;
        wrap.phraseAfterLanguage = obj.Phrase_After_Language__c;
        wrap.phraseBeforeLength = obj.Phrase_Before_Length__c;
        wrap.phraseAfterLength = obj.Phrase_After_Length__c;
        wrap.phraseBeforeObject = obj.Phrase_Before_Object__c;
        wrap.phraseAfterObject = obj.Phrase_After_Object__c;
        wrap.phraseBeforeTone = obj.Phrase_Before_Tone__c;
        wrap.phraseAfterTone = obj.Phrase_After_Tone__c;
        wrap.responseProcessings = new List<ExportMappingWrapper.ResponseProcessingWrapper>();
        if(obj.AI_Response_Processing__r != null && !obj.AI_Response_Processing__r.isEmpty()){
            for(AI_Response_Processing__c p : obj.AI_Response_Processing__r){
                ExportMappingWrapper.ResponseProcessingWrapper p_wrap = new ExportMappingWrapper.ResponseProcessingWrapper();
                p_wrap.salesforceId = p.Id;
                p_wrap.actionName = p.Action__c;
                p_wrap.description = p.Description__c;
                p_wrap.destinationField = p.Destination_Field__c;
                p_wrap.appendTimestamp = p.Append_Timestamp__c;
                wrap.responseProcessings.add(p_wrap);
            }
        }
        return wrap;
    }

    public static ExportMappingWrapper.PromptActionWrapper getMappedPromptAction(AI_Prompt_Action__c obj){
        ExportMappingWrapper.PromptActionWrapper wrap = new ExportMappingWrapper.PromptActionWrapper();
        wrap.salesforceId = obj.Id;
        wrap.actionType = obj.Action__c;
        wrap.description = obj.Description__c;
        wrap.sequence = obj.Sequence__c;
        wrap.objectName = obj.Object_Name__c;
        wrap.fieldAPIName = obj.Field_API_Name__c;
        wrap.flowAPIName = obj.Flow_API_Name__c;
        wrap.apexClassName = obj.Apex_Class_Name__c;
        wrap.appendTimestamp = obj.Append_Timestamp__c;
        wrap.promptComponent = obj.Prompt_Component__c;
        wrap.promptActionDetails = new List<ExportMappingWrapper.PromptActionDetailWrapper>();
        if(obj.Prompt_Action_Details__r != null && obj.Prompt_Action_Details__r.size()>0){
            for(AI_Prompt_Action_Detail__c detail : obj.Prompt_Action_Details__r){
                wrap.promptActionDetails.add(getMappedPromptActionDetail(detail));
            }
        }
        return wrap;
    }
    
    public static ExportMappingWrapper.PromptActionDetailWrapper getMappedPromptActionDetail(AI_Prompt_Action_Detail__c obj){
        ExportMappingWrapper.PromptActionDetailWrapper wrap = new ExportMappingWrapper.PromptActionDetailWrapper();
        wrap.salesforceId = obj.Id;
        wrap.fieldAPIName = obj.Field_API_Name__c;
        wrap.actionType = obj.Type__c;
        wrap.value = obj.Value__c;
        return wrap;
    }

    /**
     * Retrieves the security filters for the extraction based on the provided AI_Security_Filters__c object, returning an ExportMappingWrapper.ExtractionSecurityFilterWrapper object containing the security filter details.
     * 
     * @param obj The AI_Security_Filters__c object providing the security filter information for the extraction process.
     * @return ExportMappingWrapper.ExtractionSecurityFilterWrapper An ExportMappingWrapper.ExtractionSecurityFilterWrapper object representing the security filters for the extraction, ready for further processing or analysis.
     */
    public static ExportMappingWrapper.ExtractionSecurityFilterWrapper getSecurityFilters(AI_Security_Filters__c obj){
        ExportMappingWrapper.ExtractionSecurityFilterWrapper wrap = new ExportMappingWrapper.ExtractionSecurityFilterWrapper();
        wrap.salesforceId = obj.Id;
        wrap.filterName = obj.Name;
        wrap.recordTypeName = obj.RecordType.Name;
        wrap.searchPattern = obj.Search_Pattern__c;
        wrap.status = obj.Status__c;
        wrap.type = obj.Type__c;
        wrap.blocklist = obj.Blocklist__c;
        wrap.comment = obj.Comment__c;
        wrap.apexClassName = obj.Apex_Class_Name__c ;
        return wrap;
    }

    /**
     * Retrieves the mapped extraction mapping for the provided AI_Data_Extraction_Mapping__c object, returning an ExportMappingWrapper.ExtractionWrapper object containing the necessary mapping details.
     * 
     * @param obj The AI_Data_Extraction_Mapping__c object for which the mapped extraction mapping is being retrieved.
     * @return ExportMappingWrapper.ExtractionWrapper An ExportMappingWrapper.ExtractionWrapper object representing the mapped extraction mapping for the specified object, ready for further processing or analysis.
     */
    public static ExportMappingWrapper.ExtractionWrapper getMappedExtractionMapping(AI_Data_Extraction_Mapping__c obj){
        ExportMappingWrapper.ExtractionWrapper wrap = new ExportMappingWrapper.ExtractionWrapper();
        wrap.salesforceId = obj.Id;
        wrap.mappingName = obj.Name;
        wrap.description = obj.Description__c;
        wrap.objectName = obj.Object_Name__c;
        wrap.dataSourceId = obj.AI_Data_Source__c;
        wrap.apexSecurityLayerId = obj.Apex_Security_Layer__c;
        wrap.details = new List<ExportMappingWrapper.ExtractionDetailWrapper>();
        wrap.fields = new List<ExportMappingWrapper.ExtractionFieldWrapper>();
        return wrap;
    }
    
    public static AI_Prompt_Component__c getMappedPromptComponent(ImportMappingWrapper.PromptComponentWrapper wrap, Map<String, AI_Data_Extraction_Detail__c> mapOfExtIdToDetail, Map<String, AI_Data_Extraction_Mapping__c> mapOfExtIdToMapping){
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
    
    public static AI_Prompt_Action__c getMappedPromptAction(ImportMappingWrapper.PromptActionWrapper wrap){
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
    
    public static AI_Prompt_Action_Detail__c getMappedPromptActionDetail(ImportMappingWrapper.PromptActionDetailWrapper wrap){
        AI_Prompt_Action_Detail__c obj = new AI_Prompt_Action_Detail__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Field_API_Name__c = wrap.fieldAPIName;
        obj.Type__c = wrap.actionType;
        obj.Value__c = wrap.value;
        return obj;
    }
    
    /**
     * Retrieves the mapped AI response processing data based on the provided ImportMappingWrapper.ResponseProcessingWrapper object, facilitating the processing of AI response data accordingly.
     * 
     * @param wrap The ResponseProcessingWrapper object containing the necessary details for retrieving the mapped AI response processing data.
     * @return AI_Response_Processing__c An AI response processing record containing the mapped data for the AI response, ready for processing operations.
     */
    public static AI_Response_Processing__c getMappedResponseProcessing(ImportMappingWrapper.ResponseProcessingWrapper wrap){
        AI_Response_Processing__c obj = new AI_Response_Processing__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Action__c = wrap.actionName;
        obj.Description__c = wrap.description;
        obj.Destination_Field__c = wrap.destinationField;
        obj.Append_Timestamp__c = wrap.appendTimestamp;
        return obj;
    }
    
    /**
     * Retrieves the mapped field based on the provided ImportMappingWrapper.ExtractionFieldWrapper and mapping ID, providing the corresponding AI Data Extraction Field object.
     * 
     * @param wrap The ImportMappingWrapper.ExtractionFieldWrapper containing information about the mapped field.
     * @param mappingId The ID of the mapping associated with the field to be retrieved.
     * @return AI_Data_Extraction_Field__c The AI Data Extraction Field object representing the mapped field, ready for further processing or analysis.
     */
    public static AI_Data_Extraction_Field__c getMappedField(ImportMappingWrapper.ExtractionFieldWrapper wrap, String mappingId){
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
     * Retrieves the mapped data extraction detail based on the provided ImportMappingWrapper.ExtractionDetailWrapper object and mapping ID, allowing access to the corresponding AI data extraction detail.
     * 
     * @param wrap The ImportMappingWrapper.ExtractionDetailWrapper object containing information necessary for retrieving the mapped detail.
     * @param mappingId The ID of the mapping associated with the data extraction detail to be retrieved.
     * @return AI_Data_Extraction_Detail__c The AI data extraction detail record retrieved based on the provided wrapper object and mapping ID, ready for further processing or analysis.
     */
    public static AI_Data_Extraction_Detail__c getMappedDetail(ImportMappingWrapper.ExtractionDetailWrapper wrap, String mappingId){
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
     * Retrieves the data extraction mapping based on the provided ImportMappingWrapper.ExtractionWrapper object, providing the relevant AI data extraction mapping.
     * 
     * @param wrap The ImportMappingWrapper.ExtractionWrapper object containing information necessary for retrieving the data extraction mapping.
     * @return AI_Data_Extraction_Mapping__c The AI data extraction mapping corresponding to the provided ExtractionWrapper, ready for further processing or analysis.
     */

    public static AI_Data_Extraction_Mapping__c getMappedDataExtractionMapping(ImportMappingWrapper.ExtractionWrapper wrap, Boolean isPostInstall){
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
     * Retrieves the mapped AI connection based on the provided ImportMappingWrapper.ConnectionWrapper object, facilitating the retrieval and processing of the mapped connection.
     * 
     * @param wrap The ConnectionWrapper object containing the necessary information and details for the mapped AI connection.
     * @return AI_Connection__c The AI connection record mapped based on the provided ConnectionWrapper, ready for further processing or analysis.
     */
	public static AI_Connection__c getMappedConnection(ImportMappingWrapper.ConnectionWrapper wrap){
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
        obj.Type__c = wrap.type;
        return obj;
    }                                          
    
    /**
    * Retrieves the mapped AI prompt based on the provided ImportMappingWrapper.PromptWrapper object, map of external ID to data extraction, and map of external ID to AI connection.
    * 
    * @param wrap The ImportMappingWrapper.PromptWrapper object containing information for the mapped AI prompt.
    * @param mapOfExternalIdToDataExtraction A map where the keys represent external IDs, and the values contain the corresponding data extraction mappings.
    * @param mapOfExternalIdToConnection A map where the keys represent external IDs, and the values contain the corresponding AI connections.
    * @return AI_Prompt__c The AI prompt object retrieved based on the provided parameters and mappings, ready for further processing or analysis.
    * @Jira V2-7132
    */
    public static AI_Prompt__c getMappedPrompt(ImportMappingWrapper.PromptWrapper wrap, Map<String, AI_Data_Extraction_Mapping__c> mapOfExternalIdToDataExtraction, Map<String, AI_Connection__c> mapOfExternalIdToConnection, Boolean isPostInstall){
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
        if(wrap.aIModelFileProcessing != '' && mapOfExternalIdToConnection.containsKey(wrap.aIModelFileProcessing)){
            obj.AI_Model_File_Processing__c = mapOfExternalIdToConnection.get(wrap.aIModelFileProcessing).Id;
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
        obj.Permission_Sets__c = wrap.permissionSets;
        obj.Time_Saved_Coefficient__c = wrap.timeSavedCoefficient;
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
        obj.Auto_Refresh_Duration__c = wrap.autoRefreshDuration;
        obj.Enable_Loopback__c = wrap.enableLoopback != null && wrap.enableLoopback ? true : false;
        obj.Loopback_Message__c = wrap.loopbackMessage;
        obj.Response_Validation_Condition__c = wrap.responseValidationCondition;
        obj.Response_Validation_Message__c = wrap.responseValidationMessage;
        obj.Agentic_Function_Class__c = wrap.agenticFunctionClass;
        //obj.AI_Model_File_Processing__c = wrap.aIModelFileProcessing;

        
        if(isPostInstall){
            obj.Status__c = AIConstants.PMT_STATUS_ACTIVE;
            obj.Pre_Packaged__c = true;
        }else{
            obj.Status__c = AIConstants.PMT_STATUS_DRAFT;
        }
        return obj;
    }
    
    public static AI_Security_Filters__c getMappedFilters(ImportMappingWrapper.ExtractionSecurityFilterWrapper wrap){
        AI_Security_Filters__c obj = new AI_Security_Filters__c();
        obj.Name =  wrap.filterName;
        obj.Search_Pattern__c = wrap.searchPattern;
        obj.Status__c = wrap.status;
        obj.Type__c = wrap.type;
        obj.Blocklist__c = wrap.blocklist;
        obj.Comment__c = wrap.comment;
        obj.External_Id__c = wrap.salesforceId;
        obj.Apex_Class_Name__c = wrap.apexClassName;
        if(wrap.recordTypeName == 'Regex'){
            obj.RecordTypeId = RT_REGEX;
        }else if(wrap.recordTypeName == 'Blocklist'){
            obj.RecordTypeId = RT_BLOCKLIST;
        }else if(wrap.recordTypeName == 'Apex'){
            obj.RecordTypeId = RT_APEX;
        }
        return obj;
    }
    
    public static AI_Data_Source__c getDataSource(ImportMappingWrapper.DataSourceWrapper wrap){
        AI_Data_Source__c obj = new AI_Data_Source__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Connector_Class__c = wrap.connectorClass;
        obj.name = wrap.name;
        obj.EndPoint_URL__c = wrap.endpointUrl;
        obj.Named_Credential__c = wrap.namedCredential;
        obj.Source__c = wrap.source;
        return obj;
    }
    
    public static AI_Card_Configuration__c getCardConfiguration(ImportMappingWrapper.CardConfigurationWrapper wrap, boolean enabled){
        AI_Card_Configuration__c cc = new AI_Card_Configuration__c();
        cc.External_Id__c = wrap.salesforceId;
        cc.Name = wrap.configName;
        cc.Description__c = wrap.description;
        cc.Icon_Details__c = wrap.iconDetails;
        cc.Icon_Source__c = wrap.iconSource;
        cc.Sequence__c = wrap.sequence;
        cc.Feature__c = wrap.feature;  
        cc.Enabled__c = enabled;
        return cc;
    }
    public static AI_Prompt_Element__c getMappedPromptElementRecord(ExportMappingWrapper.PromptElementWrapper wrap, Map<String, AI_Prompt__c> mapOfExternalIdToPrompt) {
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
    
    public static AI_Prompt_Response_Validation__c getMappedPromptResponseValidationRecord(ExportMappingWrapper.PromptResponseValidationWrapper wrap, Map<String, AI_Prompt__c> mapOfExternalIdToPrompt) {
        AI_Prompt_Response_Validation__c obj = new AI_Prompt_Response_Validation__c();
        obj.External_Id__c = wrap.salesforceId;
        obj.Sequence__c = wrap.sequence;
        obj.Action__c = wrap.action;
        obj.Value__c = wrap.value;
    
        
        if(String.isNotBlank(wrap.promptId) && mapOfExternalIdToPrompt.containsKey(wrap.promptId)) {
            obj.AI_Prompt__c = mapOfExternalIdToPrompt.get(wrap.promptId).Id;
        }
        
        // Add any additional fields as needed
        return obj;
    }
    
}