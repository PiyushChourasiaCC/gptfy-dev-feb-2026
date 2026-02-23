/**
 * @description       : 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 06-08-2023
 * @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptExportController {
    
    public static String NAMESPACE_PREFIX = AIPromptController.getNameSpace();
    
    /**
     * Retrieves the name of the current package, providing information about the package context within Salesforce.
     * 
     * @return String The name of the current package, indicating the package in which the method is being executed.
     */
    public String getCurrentPackageName() {
        return NAMESPACE_PREFIX;
    }
    
    public static String requestType{get;set;}
    public AIPromptExportController() {
        requestType = ApexPages.currentPage().getParameters().get('type');
    }
    
    /**
     * Navigates to the designated list view, providing a PageReference object for redirecting to the specified list view within the Salesforce platform.
     * 
     * @return PageReference A PageReference object representing the navigation to the designated list view.
     */
    public PageReference navigateToListView(){
        Schema.DescribeSObjectResult result = AI_Prompt__c.SObjectType.getDescribe(); 
        PageReference pageRef = new PageReference('/' + result.getKeyPrefix()); 
  		pageRef.setRedirect(true); 
        return pageRef;
    }
	
    /**
     * Retrieves the mapping information for exporting data, providing an ExportMappingWrapper object containing the necessary mappings for the export process.
     * 
     * @return ExportMappingWrapper An ExportMappingWrapper object representing the mapping information for data export, ready for further processing or analysis.
     */
    @AuraEnabled
    public static ExportMappingWrapper getMappings(){
        try{
            ExportMappingWrapper wrap = new ExportMappingWrapper();
            wrap.exportedOn = System.today();
            wrap.orgId = UserInfo.getOrganizationId();
            wrap.exportedBy = UserInfo.getName();
            wrap = getPromptDetails(wrap);
            return wrap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptExportController', 'getMappings', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
	
    /**
     * Retrieves the prompt details for the provided ExportMappingWrapper, enhancing the wrapper object with additional information and data for prompt processing.
     * 
     * @param wrap The ExportMappingWrapper object containing the necessary data for retrieving prompt details.
     * @return ExportMappingWrapper An updated ExportMappingWrapper object with enhanced prompt details for further processing or analysis.
     */
    public static ExportMappingWrapper getPromptDetails(ExportMappingWrapper wrap){
        return getPromptDetailsService(wrap, null);
    }
	
    /**
     * Retrieves the prompt details service for the provided ExportMappingWrapper and prompt ID, updating the wrapper with the relevant details.
     * 
     * @param wrap The ExportMappingWrapper containing the necessary details for the prompt details service.
     * @param promptId The ID of the prompt associated with the prompt details service.
     * @return ExportMappingWrapper The updated ExportMappingWrapper containing the retrieved prompt details service information for further processing or analysis.
     *  @Jira V2-7132
     */
    public static ExportMappingWrapper getPromptDetailsService(ExportMappingWrapper wrap, String promptId){
        Map<String, ExportMappingWrapper.PromptWrapper> prompts = new Map<String, ExportMappingWrapper.PromptWrapper>();
        
        String activeStatus = AIConstants.PMT_STATUS_ACTIVE;
        
        String sSOQL = 'SELECT Id, Name, Description__c, Object__c, Profiles__c, Prompt_Command__c, Purpose__c, Record_Type__c, Status__c, Type__c,Auto_Refresh_Duration__c, '; //Target_Field__c,Append_Timestamp__c,/*#JIRA-4986:Prompt Action Framework*/
        sSOQL += 'Custom_Prompt__c, Grounding_Ethical__c, Grounding_Content__c, Include_Files__c, Enable_Loopback__c, Loopback_Message__c, Response_Validation_Condition__c, Response_Validation_Message__c, ';
        sSOQL += 'AI_Connection__c, Top_P__c, Max_Output_Tokens__c, Temperature__c, How_It_Works__c, AI_Connection__r.Name, AI_Connection__r.AI_Technology__c, AI_Connection__r.Connector_Class__c, ';
        sSOQL += 'AI_Connection__r.Processing_Class__c, AI_Connection__r.EndPoint_URL__c, AI_Connection__r.Key__c, AI_Connection__r.Max_Tokens__c, AI_Connection__r.Model__c, AI_Connection__r.Type__c, ';
        sSOQL += 'AI_Connection__r.Named_Credential__c, AI_Connection__r.Infrastructure__c, AI_Connection__r.Security_Layer__c, ';
        sSOQL += 'AI_Connection__r.Temperature__c, AI_Connection__r.Top_P__c, AI_Connection__r.Version__c, Prompt_Request_Id__c, ';
        sSOQL += 'AI_Data_Extraction_Mapping__c, AI_Data_Extraction_Mapping__r.Name, AI_Data_Extraction_Mapping__r.Description__c, ';
        sSOQL += 'AI_Data_Extraction_Mapping__r.Object_Name__c, Prompt_Version__c, Visibility_Condition__c, AI_Data_Extraction_Mapping__r.AI_Data_Source__c, ';
        sSOQL += 'AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Name, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Connector_Class__c,';
        sSOQL += 'AI_Data_Extraction_Mapping__r.AI_Data_Source__r.EndPoint_URL__c, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Named_Credential__c, Time_Saved_Coefficient__c, ';
        sSOQL += 'AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Source__c, AI_Locale_Automation__c, AI_Locale_GPTfy_Console__c, Permission_Sets__c, Agentic_Function_Class__c, AI_Model_File_Processing__c ';
        sSOQL += 'FROM AI_Prompt__c ';
        sSOQL += 'WHERE Status__c =:activeStatus AND AI_Connection__c != NULL AND AI_Data_Extraction_Mapping__c != NULL ';
        if(String.isNotBlank(promptId)){
            sSOQL += 'AND Id=:promptId ';
        }
        sSOQL += 'ORDER BY Name, Object__c';

        List<AI_Prompt__c> lstOfPrompts = new List<AI_Prompt__c>();
        for(AI_Prompt__c prompt : database.query(sSOQL)){
            lstOfPrompts.add(prompt);
        }
        
        Map<String, ExportMappingWrapper.ConnectionWrapper> mapOfConnections = new Map<String, ExportMappingWrapper.ConnectionWrapper>();
        Map<String, ExportMappingWrapper.ExtractionWrapper> mapOfMappings = new Map<String, ExportMappingWrapper.ExtractionWrapper>();
        Map<String, ExportMappingWrapper.DataSourceWrapper> mapOfDataSources = new Map<String, ExportMappingWrapper.DataSourceWrapper>();

        Set<String> setOfCardNames = new Set<String>();
        
        for(AI_Prompt__c obj : lstOfPrompts){
            if(!mapOfConnections.containsKey(obj.AI_Connection__c)){
                mapOfConnections.put(obj.AI_Connection__c, getMappedConnection(obj.AI_Connection__r));
            } 
            
            if(obj.AI_Data_Extraction_Mapping__c != null && obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__c != null){
                if(!mapOfDataSources.containskey(obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__c)){
                    mapOfDataSources.put(obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__c, getDataSource(obj.AI_Data_Extraction_Mapping__r.AI_Data_Source__r));
                }
            }
            
            if(!mapOfMappings.containsKey(obj.AI_Data_Extraction_Mapping__c)){
                mapOfMappings.put(obj.AI_Data_Extraction_Mapping__c, getMappedExtractionMapping(obj.AI_Data_Extraction_Mapping__r));
            }
            prompts.put(obj.Id, getMappedPrompt(obj));
        }
         //@Jira V2-7132
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
            List<AI_Prompt_Element__c> lstOfPromptElements = [SELECT Id, Name, Inherit_Prompt_Security__c, Height__c, Icon__c, AI_Parent_Prompt__c,
                                                                    AI_Prompt__c, Sequence__c, AI_Summary_Prompt__c, Width__c, AI_Parent_Prompt__r.Prompt_Request_Id__c,
                                                                    AI_Prompt__r.Prompt_Request_Id__c, AI_Summary_Prompt__r.Prompt_Request_Id__c
                                                                FROM AI_Prompt_Element__c 
                                                                WHERE AI_Parent_Prompt__c IN :prompts.KeySet()];
            if(lstOfPromptElements != null && !lstOfPromptElements.isEmpty()){
                for(AI_Prompt_Element__c obj : lstOfPromptElements){
                    prompts.get(obj.AI_Parent_Prompt__c).promptElements.add(getMappedPromptElement(obj));
                }
            }
            
            List<AI_Prompt_Action__c> lstOfActions = [SELECT Id, Action__c, Field_API_Name__c, Apex_Class_Name__c, Flow_API_Name__c, 
                                                      Sequence__c, Object_Name__c, Prompt_Component__c, Action_Label__c, Description__c, 
                                                      Append_Timestamp__c, AI_Prompt__c, 
                                                      (SELECT Id, Field_API_Name__c, Type__c, Value__c FROM Prompt_Action_Details__r) 
                                                      FROM AI_Prompt_Action__c WHERE AI_Prompt__c IN :prompts.keySet()];
            if(lstOfActions != null && !lstOfActions.isEmpty()){
                for(AI_Prompt_Action__c obj : lstOfActions){
                    prompts.get(obj.AI_Prompt__c).promptActions.add(getMappedPromptAction(obj));
                }
            }
            // Jira 7221:  Issues/Feedbacks from 1.12 Testing
            List<AI_Prompt_Response_Validation__c> lstOfRespValidation = [SELECT Id, AI_Prompt__c, Action__c, Value__c, Sequence__c 
                                                                            FROM AI_Prompt_Response_Validation__c 
                                                                                WHERE AI_Prompt__c IN :prompts.keySet()];
            if(lstOfRespValidation != null && !lstOfRespValidation.isEmpty()){
                for(AI_Prompt_Response_Validation__c obj : lstOfRespValidation){
                    prompts.get(obj.AI_Prompt__c).promptResponseValidations.add(getMappedPromptResponseValidation(obj));
                }
            }
            
            List<AI_Data_Extraction_Field__c> lstOfExtractionFields = [SELECT Id, AI_Data_Extraction_Mapping__c, Anonymize_With__c, Field__c, Name, Label__c, Object__c, 
                                                                       Type__c, Field_Type__c, Masking_Scope__c, Formula__c, Send_To_AI__c FROM AI_Data_Extraction_Field__c 
                                                                       WHERE AI_Data_Extraction_Mapping__c IN :mapOfMappings.KeySet()];
            if(lstOfExtractionFields != null && !lstOfExtractionFields.isEmpty()){
                for(AI_Data_Extraction_Field__c obj : lstOfExtractionFields){
                    mapOfMappings.get(obj.AI_Data_Extraction_Mapping__c).fields.add(getMappedField(obj));
                }
            }
            
            List<AI_Data_Extraction_Detail__c> lstOfExtractionDetails = [SELECT Id, Name, AI_Data_Extraction_Mapping__c, Object_Hierarchy__c, Object_Name__c, Order_By__c,
                                                                        Parent_Detail__c, Record_Limit__c, RelationshipField__c, RelationshipName__c, Running_Index__c,
                                                                        Type__c, Where_Clause__c FROM AI_Data_Extraction_Detail__c 
                                                                       	WHERE AI_Data_Extraction_Mapping__c IN :mapOfMappings.KeySet()];
            if(lstOfExtractionDetails != null && !lstOfExtractionDetails.isEmpty()){
                for(AI_Data_Extraction_Detail__c obj : lstOfExtractionDetails){
                    mapOfMappings.get(obj.AI_Data_Extraction_Mapping__c).details.add(getMappedDetail(obj));
                }
            }
            Map<String, List<ExportMappingWrapper.ExtractionSecurityFilterWrapper>> mapSecurityFilters = new Map<String, List<ExportMappingWrapper.ExtractionSecurityFilterWrapper>>();
            for(AI_Security_Filters__c sf : [SELECT Id, Name, RecordTypeId, RecordType.Name, Blocklist__c, 
                                             Comment__c, Replacement_Value__c, Search_Pattern__c, Status__c, Type__c 
                                             FROM AI_Security_Filters__c WHERE Status__c = 'Active']){
                if(!mapSecurityFilters.containsKey(sf.RecordType.Name)){
                    mapSecurityFilters.put(sf.RecordType.Name, new List<ExportMappingWrapper.ExtractionSecurityFilterWrapper>());
                }
                mapSecurityFilters.get(sf.RecordType.Name).add(getSecurityFilters(sf));
            }
            wrap.prompts = prompts.values();
            wrap.connections = mapOfConnections;
            wrap.dataExtractionMappings = mapOfMappings;
            if(mapOfDataSources != null && !mapOfDataSources.isEmpty()){
                wrap.dataSources = mapOfDataSources.values();
            }
            wrap.securityFilters = mapSecurityFilters;
        }
        return wrap;
    }
    
    /**
     * Retrieves the mapped extraction detail for the specified AI data extraction detail object, providing an ExtractionDetailWrapper within the ExportMappingWrapper for processing or analysis.
     * 
     * @param obj The AI data extraction detail object containing the details to be mapped and processed.
     * @return ExportMappingWrapper.ExtractionDetailWrapper An ExtractionDetailWrapper within the ExportMappingWrapper, representing the mapped extraction detail for further processing or analysis.
     */
    public static ExportMappingWrapper.ExtractionDetailWrapper getMappedDetail(AI_Data_Extraction_Detail__c obj){
        ExportMappingWrapper.ExtractionDetailWrapper wrap = new ExportMappingWrapper.ExtractionDetailWrapper();
        wrap.salesforceId = obj.Id;
        wrap.detailName = obj.Name;
        wrap.objectHierarchy = obj.Object_Hierarchy__c;
        wrap.objectName = obj.Object_Name__c;
        wrap.orderBy = obj.Order_By__c;
        wrap.parentDetailId = obj.Parent_Detail__c;
        wrap.relationshipField = obj.RelationshipField__c;
        wrap.relationshipName = obj.RelationshipName__c;
        wrap.type = obj.Type__c;
        wrap.whereClause = obj.Where_Clause__c;
        wrap.recordLimit = obj.Record_Limit__c;
        wrap.runningIndex = obj.Running_Index__c;
        return wrap;
    }
    
    /**
     * Retrieves the mapped field from the AI Data Extraction Field object, providing an ExtractionFieldWrapper object within the ExportMappingWrapper for further processing or analysis.
     * 
     * @param obj The AI Data Extraction Field object containing the field information to be mapped.
     * @return ExportMappingWrapper.ExtractionFieldWrapper An ExtractionFieldWrapper object within the ExportMappingWrapper, representing the mapped field for the provided AI Data Extraction Field, ready for further processing or analysis.
     */
    public static ExportMappingWrapper.ExtractionFieldWrapper getMappedField(AI_Data_Extraction_Field__c obj){
        ExportMappingWrapper.ExtractionFieldWrapper wrap = new ExportMappingWrapper.ExtractionFieldWrapper();
        wrap.salesforceId = obj.Id;
        wrap.fieldName = obj.Label__c;
        wrap.fieldApi = obj.Field__c;
        wrap.objectName = obj.Object__c;
        wrap.type = obj.Type__c;
        wrap.anonymizeWith = obj.Anonymize_With__c;
        wrap.formula = obj.Formula__c;
        wrap.fieldType = String.isNotBlank(obj.Field_Type__c) ? obj.Field_Type__c : '';
        wrap.maskingScope = String.isNotBlank(obj.Masking_Scope__c) ? obj.Masking_Scope__c : '';
        wrap.sendToAi = obj.Send_To_AI__c;
        return wrap;
    }
    
    /**
     * Retrieves the mapped connection for the provided AI_Connection__c object, providing a connection wrapper within the ExportMappingWrapper for further data processing or analysis.
     * 
     * @param obj The AI_Connection__c object for which the mapped connection is being retrieved.
     * @return ExportMappingWrapper.ConnectionWrapper A connection wrapper within the ExportMappingWrapper representing the mapped connection for the provided AI_Connection__c object.
     */
    public static ExportMappingWrapper.ConnectionWrapper getMappedConnection(AI_Connection__c obj){
        ExportMappingWrapper.ConnectionWrapper wrap = new ExportMappingWrapper.ConnectionWrapper();
        wrap.salesforceId = obj.Id;
        wrap.connectionName = obj.Name;
        wrap.aiTechnology = obj.AI_Technology__c;
        wrap.connectorClass = obj.Connector_Class__c;
        wrap.processingClass = obj.Processing_Class__c;
        wrap.endpointUrl = obj.EndPoint_URL__c;
        wrap.key = obj.Key__c;
        wrap.maxTokens = obj.Max_Tokens__c;
        wrap.model = obj.Model__c;
        wrap.namedCredential = obj.Named_Credential__c;
        wrap.infrastructure = obj.Infrastructure__c;
        wrap.securityLayer = obj.Security_Layer__c;
        wrap.temperature = obj.Temperature__c;
        wrap.topP = obj.Top_P__c;
        wrap.version = obj.Version__c;
        // @Jira 7317: Global Import/Export Feedbacks
        //@Jira V2-7132
        wrap.type = obj.Type__c;
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
        wrap.details = new List<ExportMappingWrapper.ExtractionDetailWrapper>();
        wrap.fields = new List<ExportMappingWrapper.ExtractionFieldWrapper>();
        return wrap;
    }
    
    /**
     * Retrieves the mapped prompt component based on the provided AI_Prompt_Component__c object, returning an ExportMappingWrapper.PromptComponentWrapper containing the necessary data and details for the mapped prompt component.
     * 
     * @param obj The AI_Prompt_Component__c object representing the mapped prompt component to be retrieved.
     * @return ExportMappingWrapper.PromptComponentWrapper A wrapper object containing the mapped prompt component data, ready for further processing or analysis.
     */
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
    
    /**
     * Retrieves the mapped prompt action based on the provided AI_Prompt_Action__c object, returning an ExportMappingWrapper.PromptActionWrapper containing the necessary data and details for the mapped prompt action.
     * 
     * @param obj The AI_Prompt_Action__c object representing the mapped prompt action to be retrieved.
     * @return ExportMappingWrapper.PromptActionWrapper A wrapper object containing the mapped prompt action data, ready for further processing or analysis.
     */
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

    /**
     * Jira 7221:  Issues/Feedbacks from 1.12 Testing
     * Retrieves the mapped prompt response validation based on the provided AI_Response_Validation object, returning an ExportMappingWrapper.PromptResponseValidationWrapper containing the necessary data and details for the mapped prompt response validation.
     * 
     * @param obj The AI_Prompt_Response_Validation__c object representing the mapped prompt action to be retrieved.
     * @return ExportMappingWrapper.PromptResponseValidationWrapper A wrapper object containing the mapped prompt action data, ready for further processing or analysis.
     *  @Jira V2-7132
     */
    public static ExportMappingWrapper.PromptResponseValidationWrapper getMappedPromptResponseValidation(AI_Prompt_Response_Validation__c obj){
        ExportMappingWrapper.PromptResponseValidationWrapper wrap = new ExportMappingWrapper.PromptResponseValidationWrapper();
        wrap.salesforceId = obj.Id;
        wrap.action = obj.Action__c;
        wrap.promptId = obj.AI_Prompt__c;
        wrap.sequence = obj.Sequence__c;
        wrap.value = obj.Value__c;
        return wrap;
    }
    
    /**
     * Retrieves the mapped prompt action detail based on the provided AI_Prompt_Action_Detail__c object, returning an ExportMappingWrapper.PromptActionDetailWrapper containing the necessary data and details for the mapped prompt action detail.
     * 
     * @param obj The AI_Prompt_Action_Detail__c object representing the mapped prompt action detail to be retrieved.
     * @return ExportMappingWrapper.PromptActionDetailWrapper A wrapper object containing the mapped prompt action detail data, ready for further processing or analysis.
     */
    public static ExportMappingWrapper.PromptActionDetailWrapper getMappedPromptActionDetail(AI_Prompt_Action_Detail__c obj){
        ExportMappingWrapper.PromptActionDetailWrapper wrap = new ExportMappingWrapper.PromptActionDetailWrapper();
        wrap.salesforceId = obj.Id;
        wrap.fieldAPIName = obj.Field_API_Name__c;
        wrap.actionType = obj.Type__c;
        wrap.value = obj.Value__c;
        return wrap;
    }
    
    /**
     * Retrieves the mapped prompt from the provided AI_Prompt__c object, returning an ExportMappingWrapper.PromptWrapper object containing the relevant prompt details and mappings.
     * 
     * @param obj The AI_Prompt__c object from which the mapped prompt is being retrieved.
     * @return ExportMappingWrapper.PromptWrapper An ExportMappingWrapper.PromptWrapper object representing the mapped prompt with associated details and mappings, ready for further processing or analysis.
     *  @Jira V2-7132
     */
    public static ExportMappingWrapper.PromptWrapper getMappedPrompt(AI_Prompt__c obj){
        ExportMappingWrapper.PromptWrapper wrap = new ExportMappingWrapper.PromptWrapper();
        wrap.salesforceId = obj.Id;
        //if(String.isNotBlank(obj.Prompt_Request_Id__c)){
            //wrap.salesforceId = obj.Prompt_Request_Id__c;
        //}
        wrap.connectionId = obj.AI_Connection__c;
        wrap.extractionMappingId = obj.AI_Data_Extraction_Mapping__c;
        wrap.promptName = obj.Name;
        wrap.description = obj.Description__c;
        wrap.objectName = obj.Object__c;
        wrap.profiles = obj.Profiles__c;
        wrap.permissionSets = obj.Permission_Sets__c;
        // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
        wrap.timeSavedCoefficient = obj.Time_Saved_Coefficient__c;
        wrap.groundingContent = obj.Grounding_Content__c;
        wrap.groundingEthical = obj.Grounding_Ethical__c;
        wrap.localeAutomation = obj.AI_Locale_Automation__c;
        wrap.localeGPTfyConsole = obj.AI_Locale_GPTfy_Console__c;
        wrap.promptCommand = obj.Prompt_Command__c;
        wrap.purpose = obj.Purpose__c;
        //wrap.targetField = obj.Target_Field__c;/*#JIRA-4986:Prompt Action Framework*/
        //wrap.appendTimestamp = obj.Append_Timestamp__c;/*#JIRA-4986:Prompt Action Framework*/
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
        wrap.enableLoopback = obj.Enable_Loopback__c;
        wrap.loopbackMessage = obj.Loopback_Message__c;
        wrap.responseValidationCondition = obj.Response_Validation_Condition__c;
        wrap.responseValidationMessage = obj.Response_Validation_Message__c;
        wrap.agenticFunctionClass = obj.Agentic_Function_Class__c;
        wrap.aIModelFileProcessing = obj.AI_Model_File_Processing__c;
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
        return wrap;
    }
    
    public static ExportMappingWrapper.DataSourceWrapper getDataSource(AI_Data_Source__c obj){
        ExportMappingWrapper.DataSourceWrapper wrap = new ExportMappingWrapper.DataSourceWrapper();
        wrap.salesforceId = obj.Id;
        wrap.connectorClass = obj.Connector_Class__c;
        wrap.name = obj.name;
        wrap.endpointUrl = obj.EndPoint_URL__c;
        wrap.namedCredential = obj.Named_Credential__c;
        wrap.source = obj.Source__c;
        return wrap;
    }

    public static ExportMappingWrapper.PromptElementWrapper getMappedPromptElement(AI_Prompt_Element__c obj){
        ExportMappingWrapper.PromptElementWrapper wrap = new ExportMappingWrapper.PromptElementWrapper();
        wrap.salesforceId = obj.Id;
        wrap.parentPromptId = obj.AI_Parent_Prompt__c;
        wrap.parentPromptrequestId = obj.AI_Parent_Prompt__r.Prompt_Request_Id__c;
        wrap.promptId = obj.AI_Prompt__c;
        wrap.promptRequestId = obj.AI_Prompt__r.Prompt_Request_Id__c;
        wrap.summaryPromptId = obj.AI_Summary_Prompt__c;
        wrap.summaryPromptRequestId = obj.AI_Summary_Prompt__r.Prompt_Request_Id__c;
        wrap.width = obj.Width__c;
        wrap.icon = obj.Icon__c;
        wrap.height = obj.Height__c;
        wrap.sequence = Integer.valueOf(obj.Sequence__c);
        wrap.inheritPromptSecurity = obj.Inherit_Prompt_Security__c;
        return wrap;
    }
}