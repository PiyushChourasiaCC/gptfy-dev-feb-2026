/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIJsonGeneration {
    
    /**
     * Checks whether prompt versioning is enabled.
     *
     * This method returns a Boolean value indicating whether prompt versioning
     * is currently enabled in the system. Prompt versioning may be used to manage
     * different versions or variations of prompts in a user interface or system.
     *
     * @return True if prompt versioning is enabled, False otherwise.
     */
    @Auraenabled
    public static Boolean isEnablePromptVersioning(){
        return AIConstants.enablePromptVersioning;
    }

    /**
     * Updates the necessary information for a given record identified by its unique identifier.
     *
     * @param recordId The unique identifier of the record to be updated.
     * @param comment  Additional comments or information to be associated with the record.
     */
    @AuraEnabled
    public static void updateWhatNeeded(String recordId, String comment){
        try{
            AI_Prompt__c pmt = [SELECT Id, Name FROM AI_Prompt__c WHERE Id =:recordId];
            ContentDocumentLink cdl = getContentDocumentLink(pmt.Id, pmt.Name);
            ContentVersion cv = getLatestContentVersion(cdl.ContentDocumentId);
            cv.ReasonForChange = comment;
            FLSCheck.getInstance().updateDML(new List<ContentVersion>{cv});
        }catch(DMLException dmlex){
            throw new AuraHandledException(dmlex.getDMLMessage(0));
        }catch(Exception ex){
            GPTfyException.log(ex, 'GPTfy', '', 'AIJsonGeneration', 'updateWhatNeeded', '');
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * Validate Data Context Mapping based on the provided record ID.
     *
     * @param recordId The unique identifier of the record for the Data Context Mapping.
     * @return none.
     */
    @AuraEnabled 
    public static String validateDataContextMapping(String recordId) {
        try{
            AI_Data_Extraction_Mapping__c deMapping = [SELECT Id, Message__c, Status__c FROM AI_Data_Extraction_Mapping__c WHERE Id=:recordId];
            AIPromptValidationController con = new AIPromptValidationController();
            List<String> errorMessages = con.validateDataExtractionMapping(recordId);
            if(errorMessages != null && !errorMessages.isEmpty()){
                deMapping.Message__c = String.join(errorMessages, '\n');
                deMapping.Status__c = AIConstants.PMT_STATUS_DRAFT;
            }else{
                deMapping.Status__c = AIConstants.PMT_STATUS_ACTIVE;
                deMapping.Message__c = '';
            }
            FLSCheck.getInstance().updateDML(new List<AI_Data_Extraction_Mapping__c>{deMapping});
            if(deMapping.Status__c == AIConstants.PMT_STATUS_DRAFT){
                return 'Activation Failed. Please check Message for more details.';
            }
            return null;
        }catch(DMLException dmlex){
            throw new AuraHandledException(dmlex.getDMLMessage(0));
        }catch(Exception ex){
            throw new AuraHandledException(ex.getMessage());
        }
    }
    
    /**
     * validate a prompt based on the provided record ID.
     *
     * @param recordId The unique identifier of the record for which the prompt command is generated.
     * @return A Boolean representing the prompt validation for the given record ID.
     */
    @AuraEnabled 
    public static String checkValidationPromptCommand(String recordId) {
        try{
            AI_Prompt__c pmt = AIPromptSelector.getAIPromptById(recordId);
            List<AI_Prompt_Component__c> lstOfComponents = [SELECT Id, Name, GPTfy_Sentence__c, Object_Name__c, Data_Extraction_Id__c, 
                                                            AI_Prompt__c, AI_Prompt__r.AI_Data_Extraction_Mapping__c,
                                                            AI_Prompt__r.AI_Data_Extraction_Mapping__r.Object_Name__c
                                                            FROM AI_Prompt_Component__c 
                                                            WHERE AI_Prompt__c =:recordId
                                                            ORDER BY CreatedDate DESC];
            if(lstOfComponents != null && !lstOfComponents.isEmpty() && pmt.Type__c == 'JSON'){
                pmt.Prompt_Command__c = '';
                pmt.Prompt_Command__c = generatePromptJson(lstOfComponents);
            }
            
            pmt.Message__c = '';
            AIPromptValidationController con = new AIPromptValidationController();
            List<String> errorMessages = con.validatePrompts(pmt, lstOfComponents);
            if(errorMessages != null && !errorMessages.isEmpty()){
                pmt.Message__c = String.join(errorMessages, '\n');
                pmt.Status__c = AIConstants.PMT_STATUS_DRAFT;
            }
            else{
                FLSCheck.getInstance().updateDML(new List<AI_Prompt__c>{pmt});
                return null;
            }         
            FLSCheck.getInstance().updateDML(new List<AI_Prompt__c>{pmt});   
            if(pmt.Status__c == AIConstants.PMT_STATUS_DRAFT ){
                return 'Activation Failed. Please check Message for more details.';
            }
            return null;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIJsonGeneration', 'checkValidationPromptCommand', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * check the content version based on the provided record ID.
     *
     * @param recordId The unique identifier of the record for which the prompt version check.
     * @return A Boolean representing the check is empty prompt version for the given record ID.
     */
    @AuraEnabled
    public static Boolean isPromptVersionEmpty(String recordId){
        try {
            AI_Prompt__c pmt = [SELECT Id, Name FROM AI_Prompt__c WHERE Id =:recordId];
            ContentDocumentLink cdl = getContentDocumentLink(pmt.Id, pmt.Name);
            return (cdl == null)? true :false;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIJsonGeneration', 'isPromptVersionEmpty', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    

    /**
     * Generates a prompt command based on the provided record ID.
     *
     * @param recordId The unique identifier of the record for which the prompt command is generated.
     * @return A String representing the prompt command for the given record ID.
     */
    @AuraEnabled 
    public static String generatePromptCommand(String recordId) {
        try{
            AI_Prompt__c pmt = [SELECT Id, Name,Status__c, Type__c, AI_Data_Extraction_Mapping__c, 
                                AI_Connection__c, Object__c, Prompt_Command__c, 
                                AI_Data_Extraction_Mapping__r.AI_Data_Source__c,
                            	AI_Data_Extraction_Mapping__r.Object_Name__c, 
                                AI_Connection__r.Named_Credential__c, Prompt_Version__c,
                                /*Target_Field__c,*//*#JIRA-4986:Prompt Action Framework*/
                                Visibility_Condition__c
                            	FROM AI_Prompt__c WHERE Id =:recordId];
            
            List<AI_Prompt_Component__c> lstOfComponents = [SELECT Id, Name, GPTfy_Sentence__c, Object_Name__c, Data_Extraction_Id__c, 
                                                            AI_Prompt__c, AI_Prompt__r.AI_Data_Extraction_Mapping__c,
                                                            AI_Prompt__r.AI_Data_Extraction_Mapping__r.Object_Name__c
                                                            FROM AI_Prompt_Component__c 
                                                            WHERE AI_Prompt__c =:recordId
                                                            ORDER BY CreatedDate DESC];
            if(lstOfComponents != null && !lstOfComponents.isEmpty() && pmt.Type__c == 'JSON'){
                pmt.Prompt_Command__c = '';
                pmt.Prompt_Command__c = generatePromptJson(lstOfComponents);
            }else if(pmt.Type__c == 'Custom'){
                pmt.Prompt_Command__c = '';
            }
            
            pmt.Status__c = AIConstants.PMT_STATUS_ACTIVE;
            pmt.Message__c = '';
            AI_Data_Extraction_Mapping__c deMapping = new AI_Data_Extraction_Mapping__c();
            deMapping.Id = pmt.AI_Data_Extraction_Mapping__c;
            deMapping.Status__c = 'Active';
            deMapping.Message__c = '';
            FLSCheck.getInstance().updateDML(new List<AI_Data_Extraction_Mapping__c>{deMapping});
            FLSCheck.getInstance().updateDML(new List<AI_Prompt__c>{pmt});
            if(AIConstants.enablePromptVersioning || Test.isRunningTest()){
                generatePromptVersioning(pmt.Id, pmt.Name);
            }
            return null;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIJsonGeneration', 'generatePromptCommand', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    

    /**
     * Retrieves the document ID associated with the prompt content for a given record.
     * 
     * @param recordId The ID of the record for which the prompt content document ID is needed.
     * @return A String representing the document ID associated with the prompt content.
     */
    @AuraEnabled
    public static String getPromptContentDocumentId(String recordId){
        try{
        	List<AI_Prompt__c> lstOfPrompts = [SELECT Id, Name, Prompt_Version__c FROM AI_Prompt__c WHERE Id =:recordId];
        	if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
                AI_Prompt__c pmt = lstOfPrompts.get(0);
                ContentDocumentLink cdl = getContentDocumentLink(pmt.Id, pmt.Name);
                return (cdl!=null?cdl.ContentDocumentId+'_'+pmt.Prompt_Version__c:null);
            }
            return null;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIJsonGeneration', 'getPromptContentDocumentId', '');
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Retrieves a list of ContentVersion objects associated with a given content document ID.
     *
     * @param contentDocumentId The unique identifier for the content document.
     * @return A List of ContentVersion objects representing different versions of the content.
     */
    @AuraEnabled
    public static List<ContentVersion> getPromptContentVersion(String contentDocumentId){
        try{
            return [SELECT Id, VersionNumber, LastModifiedById, LastModifiedBy.Name, LastModifiedDate, ReasonForChange, IsLatest FROM ContentVersion WHERE ContentDocumentId=:contentDocumentId ORDER BY CreatedDate DESC LIMIT 999];
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIJsonGeneration', 'getPromptContentVersion', '');
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Imports and reinstates a specific version of a record.
     *
     * @param recordId   The unique identifier of the record.
     * @param versionId  The identifier of the version to be reinstated.
     */
    @AuraEnabled
    public static void importReinstateVersion(String recordId, String versionId){
        try{
            String jsonData;
            for(ContentVersion cv : [SELECT Id, VersionData FROM ContentVersion WHERE Id=:versionId]){
                jsonData = cv.VersionData.toString();
            }
            if(String.isNotBlank(jsonData)){
                ExportMappingWrapper wrap = (ExportMappingWrapper)JSON.deserialize(jsonData, ExportMappingWrapper.class);
                if(wrap.prompts != null && wrap.prompts.size()>0){
                    reinstatePromptComponents(recordId, wrap);
                    reinstatePromptActions(recordId, wrap);
                    //Jira 7221:  Issues/Feedbacks from 1.12 Testing
                    reinstatePromptResponseValidation(recordId, wrap);
                    reinstatePromptElements(recordId, wrap);
                    AI_Prompt__c oPrompt = getReinstatePrompt(recordId, wrap);
                    FLSCheck.getInstance().updateDML(new List<AI_Prompt__c>{oPrompt});
                }
            }
        }catch(DMLException dmlex){
            throw new AuraHandledException(dmlex.getDMLMessage(0));
        }catch(Exception ex){
            GPTfyException.log(ex, 'GPTfy', '', 'AIJsonGeneration', 'importReinstateVersion', '');
            throw new AuraHandledException(ex.getMessage());
        } 
    }

    /**
     * Retrieves a reinstatement prompt for a given record ID and export mapping wrapper.
     *
     * @param recordId The ID of the record for which the reinstatement prompt is needed.
     * @param wrap     An instance of ExportMappingWrapper containing necessary information.
     * @return An instance of AI_Prompt__c representing the reinstatement prompt.
     */
    public static AI_Prompt__c getReinstatePrompt(String recordId, ExportMappingWrapper wrap){
        AI_Prompt__c oPrompt = [SELECT Id, Name, AI_Connection__c, Custom_Prompt__c,
                                                AI_Data_Extraction_Mapping__c , Description__c,
                                                External_Id__c, Include_Files__c, Max_Output_Tokens__c,
                                                Message__c, Object__c, Profiles__c, Prompt_Command__c,
                                                Prompt_Version__c, Purpose__c, Record_Type__c, Status__c,
                                                /*Target_Field__c,*//*#JIRA-4986:Prompt Action Framework*/
                                				Temperature__c,Top_P__c,Type__c,Visibility_Condition__c,
                                				AI_Locale_Automation__c, AI_Locale_GPTfy_Console__c,Time_Saved_Coefficient__c,
                                				Permission_Sets__c, Enable_Loopback__c, Loopback_Message__c,
                                				Agentic_Function_Class__c, Response_Validation_Condition__c, 
                                                Response_Validation_Message__c, AI_Model_File_Processing__c
                                                FROM AI_Prompt__c WHERE Id=:recordId];
        ExportMappingWrapper.PromptWrapper oPromptWrapper = wrap.prompts.get(0);
        oPrompt.AI_Connection__c = oPromptWrapper.connectionId;
        //oPrompt.AI_Data_Extraction_Mapping__c = oPromptWrapper.extractionMappingId;
       // 4602 : When we reinstate a prompt it is updating the name of the prompt too.
       // oPrompt.Name = oPromptWrapper.promptName; 
        oPrompt.Description__c = oPromptWrapper.description;
        oPrompt.Object__c = oPromptWrapper.objectName;
        //oPrompt.Target_Field__c = oPromptWrapper.targetField;/*#JIRA-4986:Prompt Action Framework*/
        oPrompt.Profiles__c = oPromptWrapper.profiles;
        oPrompt.Permission_Sets__c = oPromptWrapper.permissionSets;
        // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
        oPrompt.Time_Saved_Coefficient__c = oPromptWrapper.timeSavedCoefficient;
        oPrompt.Prompt_Command__c = oPromptWrapper.promptCommand;
        oPrompt.Purpose__c = oPromptWrapper.purpose;
        oPrompt.Type__c = oPromptWrapper.type;
        oPrompt.Prompt_Version__c = oPromptWrapper.promptVersion;
        oPrompt.Top_P__c = oPromptWrapper.topP;
        oPrompt.Temperature__c = oPromptWrapper.temperature;
        oPrompt.Max_Output_Tokens__c = oPromptWrapper.maxTokens;
        oPrompt.Status__c = AIConstants.PMT_STATUS_DRAFT;
        oPrompt.Visibility_Condition__c = oPromptWrapper.visibilityCondition;
        oPrompt.Record_Type__c = oPromptWrapper.recordTypes;
        oPrompt.Custom_Prompt__c = oPromptWrapper.allowUserInput != null && oPromptWrapper.allowUserInput ? true : false;
        oPrompt.How_it_works__c = oPromptWrapper.howItWorks;
        oPrompt.Grounding_Content__c = oPromptWrapper.groundingContent;
        oPrompt.Grounding_Ethical__c = oPromptWrapper.groundingEthical;
        oPrompt.AI_Locale_Automation__c = oPromptWrapper.localeAutomation;
        oPrompt.AI_Locale_GPTfy_Console__c = oPromptWrapper.localeGPTfyConsole;
        oPrompt.Enable_Loopback__c = oPromptWrapper.enableLoopback != null && oPromptWrapper.enableLoopback ? true : false;
        oPrompt.Loopback_Message__c = oPromptWrapper.loopbackMessage;
        oPrompt.Response_Validation_Condition__c = oPromptWrapper.responseValidationCondition;
        oPrompt.Response_Validation_Message__c = oPromptWrapper.responseValidationMessage;
        oPrompt.Agentic_Function_Class__c = oPromptWrapper.agenticFunctionClass;
        oPrompt.AI_Model_File_Processing__c = oPromptWrapper.aIModelFileProcessing;
        oPrompt.Include_Files__c = oPromptWrapper.includeFiles != null && oPromptWrapper.includeFiles ? true : false;
        return oPrompt;
    }
    
    /**
     * Retrieves a reinstatement prompt elements for a given prompt record ID and export mapping wrapper.
     *
     * @param recordId The ID of the record for which the reinstatement prompt is needed.
     * @param wrap     An instance of ExportMappingWrapper containing necessary information.
     * @return none
     */
    public static void reinstatePromptElements(String recordId, ExportMappingWrapper wrap){
        List<AI_Prompt_Element__c> existingPromptElements = new List<AI_Prompt_Element__c>(); 
        Map<String, AI_Prompt_Element__c> promptElements = new Map<String, AI_Prompt_Element__c>();
        
        for(AI_Prompt_Element__c pe : [SELECT Id, Name, Inherit_Prompt_Security__c, Height__c, Icon__c, AI_Parent_Prompt__c,
                                             AI_Prompt__c, Sequence__c, AI_Summary_Prompt__c, Width__c, AI_Parent_Prompt__r.Prompt_Request_Id__c,
                                             AI_Prompt__r.Prompt_Request_Id__c, AI_Summary_Prompt__r.Prompt_Request_Id__c
                                             FROM AI_Prompt_Element__c 
                                             WHERE AI_Parent_Prompt__c =:recordId]){
            existingPromptElements.add(pe);
        }
        
        
        
        if(wrap.prompts.get(0).promptElements != null && wrap.prompts.get(0).promptElements.size()>0){
            for(ExportMappingWrapper.PromptElementWrapper oWrapper : wrap.prompts.get(0).promptElements){
                AI_Prompt_Element__c obj = new AI_Prompt_Element__c();
                obj.AI_Parent_Prompt__c = oWrapper.parentPromptId;
                obj.AI_Prompt__c = oWrapper.promptId;
                obj.AI_Summary_Prompt__c = oWrapper.summaryPromptId;
                obj.Width__c = oWrapper.width;
                obj.Icon__c = oWrapper.icon;
                obj.Height__c = oWrapper.height;
                obj.Sequence__c = Integer.valueOf(oWrapper.sequence);
                obj.Inherit_Prompt_Security__c = oWrapper.inheritPromptSecurity;
                promptElements.put(oWrapper.salesforceId, obj);
            }
        }
        
        
        if(existingPromptElements.size()>0){
            FLSCheck.getInstance().deleteDML(existingPromptElements);
        }

        if(!promptElements.IsEmpty()){
            FLSCheck.getInstance().upsertDML(promptElements.values(), false);
        }
        
    }

    /**
     * Retrieves a reinstatement prompt response validation for a given prompt record ID and export mapping wrapper.
     *
     * @param recordId The ID of the record for which the reinstatement prompt is needed.
     * @param wrap     An instance of ExportMappingWrapper containing necessary information.
     * @return none
     */
    public static void reinstatePromptResponseValidation(String recordId, ExportMappingWrapper wrap){
        List<AI_Prompt_Response_Validation__c> existingPromptResponseValidation = new List<AI_Prompt_Response_Validation__c>(); 
        Map<String, AI_Prompt_Response_Validation__c> promptResponseValidation = new Map<String, AI_Prompt_Response_Validation__c>();
        
        for(AI_Prompt_Response_Validation__c pc : [SELECT Id FROM AI_Prompt_Response_Validation__c WHERE AI_Prompt__c=:recordId]){
            existingPromptResponseValidation.add(pc);
        }
        
        if(wrap.prompts.get(0).promptResponseValidations != null && wrap.prompts.get(0).promptResponseValidations.size()>0){
            for(ExportMappingWrapper.PromptResponseValidationWrapper oWrapper : wrap.prompts.get(0).promptResponseValidations){
                AI_Prompt_Response_Validation__c obj = new AI_Prompt_Response_Validation__c();
                obj.AI_Prompt__c = recordId;
                obj.Value__c = oWrapper.value;
                obj.Sequence__c = oWrapper.sequence;
                promptResponseValidation.put(oWrapper.salesforceId, obj);
                
            }
        }
        
        
        if(existingPromptResponseValidation.size()>0){
            FLSCheck.getInstance().deleteDML(existingPromptResponseValidation);
        }

        if(!promptResponseValidation.IsEmpty()){
            FLSCheck.getInstance().upsertDML(promptResponseValidation.values(), false);
        }
        
    }

    
    /**
     * Retrieves a reinstatement prompt compoent for a given prompt record ID and export mapping wrapper.
     *
     * @param recordId The ID of the record for which the reinstatement prompt is needed.
     * @param wrap     An instance of ExportMappingWrapper containing necessary information.
     * @return none
     */
    public static void reinstatePromptComponents(String recordId, ExportMappingWrapper wrap){
        List<AI_Prompt_Component__c> existingPromptCompoents = new List<AI_Prompt_Component__c>(); 
        Map<String, AI_Prompt_Component__c> promptComponents = new Map<String, AI_Prompt_Component__c>();
        for(AI_Prompt_Component__c pc : [SELECT Id FROM AI_Prompt_Component__c WHERE AI_Prompt__c=:recordId]){
            existingPromptCompoents.add(pc);
        }
        if(wrap.prompts.get(0).promptComponents != null && wrap.prompts.get(0).promptComponents.size()>0){
            for(ExportMappingWrapper.PromptComponentWrapper oWrapper : wrap.prompts.get(0).promptComponents){
                AI_Prompt_Component__c pc = new AI_Prompt_Component__c();
                pc.AI_Prompt__c = recordId;
                pc.Name = oWrapper.componentName;
                pc.Key__c = oWrapper.actionName;
                pc.Additional_Instructions__c = oWrapper.additionalInstructions;
                pc.Constraint_Value__c = oWrapper.constraintValue;
                pc.Data_Extraction_Id__c = oWrapper.dataExtractionId;
                pc.Format__c = oWrapper.format;
                pc.Language__c = oWrapper.language;
                pc.Length__c = oWrapper.length;
                pc.Object_Name__c = oWrapper.objectName;
                pc.Tone__c = oWrapper.tone;
                pc.User_Customizable__c = oWrapper.userCustomizable;
                pc.Phrase_Before_Action__c = oWrapper.phraseBeforeAction;
                pc.Phrase_After_Action__c = oWrapper.phraseAfterAction;
                pc.Phrase_Before_Contraints__c = oWrapper.phraseBeforeContraints;
                pc.Phrase_After_Contraints__c = oWrapper.phraseAfterContraints;
                pc.Phrase_Before_Format__c = oWrapper.phraseBeforeFormat;
                pc.Phrase_After_Format__c = oWrapper.phraseAfterFormat;
                pc.Phrase_Before_Language__c = oWrapper.phraseBeforeLanguage;
                pc.Phrase_After_Language__c = oWrapper.phraseAfterLanguage;
                pc.Phrase_Before_Length__c = oWrapper.phraseBeforeLength;
                pc.Phrase_After_Length__c = oWrapper.phraseAfterLength;
                pc.Phrase_Before_Object__c = oWrapper.phraseBeforeObject;
                pc.Phrase_After_Object__c = oWrapper.phraseAfterObject;
                pc.Phrase_Before_Tone__c = oWrapper.phraseBeforeTone;
                pc.Phrase_After_Tone__c = oWrapper.phraseAfterTone;
                promptComponents.put(oWrapper.salesforceId, pc);
            }
        }
        
        if(existingPromptCompoents.size()>0){
            FLSCheck.getInstance().deleteDML(existingPromptCompoents);
        }
        if(!promptComponents.IsEmpty()){
            FLSCheck.getInstance().upsertDML(promptComponents.values(), false);
        }
        
    } 
    
    /**
     * Retrieves a reinstatement prompt action and prompt action detail for a given prompt record ID and export mapping wrapper.
     *
     * @param recordId The ID of the record for which the reinstatement prompt is needed.
     * @param wrap     An instance of ExportMappingWrapper containing necessary information.
     * @return none
     */
    public static void reinstatePromptActions(String recordId, ExportMappingWrapper wrap){
        List<AI_Prompt_Action__c> existingPromptActions = new List<AI_Prompt_Action__c>(); 
        Map<String, AI_Prompt_Action__c> promptActions = new Map<String, AI_Prompt_Action__c>();
        Map<String, AI_Prompt_Action_Detail__c> mapPromptActionDetail = new Map<String, AI_Prompt_Action_Detail__c>(); 
        Map<String, String> mapOfPromActionDetailProIdToParentId = new Map<String, String>();
        
        for(AI_Prompt_Action__c pc : [SELECT Id FROM AI_Prompt_Action__c WHERE AI_Prompt__c=:recordId]){
            existingPromptActions.add(pc);
        }
        
        if(wrap.prompts.get(0).promptActions != null && wrap.prompts.get(0).promptActions.size()>0){
            Map<String, String> mapPromptComponentId = new Map<String, String>();
            for(ExportMappingWrapper.PromptActionWrapper oWrapper : wrap.prompts.get(0).promptActions){
                if(!String.isBlank(oWrapper.promptComponent)){
                    mapPromptComponentId.put(oWrapper.promptComponent, null);
                }
            }
            if(!mapPromptComponentId.IsEmpty()){
                for(AI_Prompt_Component__c pc : [SELECT Id, External_Id__c FROM AI_Prompt_Component__c WHERE External_Id__c IN: mapPromptComponentId.keyset()]){
                    mapPromptComponentId.put(pc.External_Id__c, pc.Id);
                }
            }
            for(ExportMappingWrapper.PromptActionWrapper oWrapper : wrap.prompts.get(0).promptActions){
                AI_Prompt_Action__c obj = new AI_Prompt_Action__c();
                obj.AI_Prompt__c = recordId;
                obj.External_Id__c = oWrapper.salesforceId;
                obj.Action__c = oWrapper.actionType;
                obj.Description__c = oWrapper.description ;
                obj.Sequence__c = oWrapper.sequence;
                obj.Object_Name__c = oWrapper.objectName;
                obj.Field_API_Name__c = oWrapper.fieldAPIName;
                obj.Flow_API_Name__c = oWrapper.flowAPIName ;
                obj.Apex_Class_Name__c = oWrapper.apexClassName;
                obj.Append_Timestamp__c = oWrapper.appendTimestamp;
                obj.Prompt_Component__c = oWrapper.promptComponent;
                promptActions.put(oWrapper.salesforceId, obj);
                
                if(oWrapper.promptActionDetails != null && oWrapper.promptActionDetails.size()>0){
                    for(ExportMappingWrapper.PromptActionDetailWrapper padwrap : oWrapper.promptActionDetails){
                        mapPromptActionDetail.put(padwrap.salesforceId, AIPromptImportController.getMappedPromptActionDetail(padwrap));
                        mapOfPromActionDetailProIdToParentId.put(padwrap.salesforceId, oWrapper.salesforceId);
                    }
                }
            }
        }
        
        
        if(existingPromptActions.size()>0){
            FLSCheck.getInstance().deleteDML(existingPromptActions);
        }
        
        if(!promptActions.IsEmpty()){
            Map<String, SObject> cleanedRecords = FLSCheck.getInstance().upsertDML(promptActions, AI_Prompt_Action__c.Fields.External_Id__c, false);
            for(String key : cleanedRecords.keySet()){
                promptActions.put(key, (AI_Prompt_Action__c)cleanedRecords.get(key));
            }
            if(!mapPromptActionDetail.isEmpty()){
                for(AI_Prompt_Action_Detail__c rp : mapPromptActionDetail.values()){
                    if(mapOfPromActionDetailProIdToParentId.containsKey(rp.External_Id__c)){
                        String parentExtId = mapOfPromActionDetailProIdToParentId.get(rp.External_Id__c);
                        if(promptActions.containsKey(parentExtId)){
                            rp.AI_Prompt_Action__c = promptActions.get(parentExtId).Id;
                        } 
                    }
                }
                FLSCheck.getInstance().upsertDML(mapPromptActionDetail, AI_Prompt_Action_Detail__c.Fields.External_Id__c, true);
            }
        }
    }

    /**
     * Generates a JSON representation of AI prompt components.
     *
     * @param lstOfComponents A list of AI_Prompt_Component__c objects representing components
     *                        to be included in the generated JSON.
     * @return A JSON string containing the details of the provided AI prompt components.
     */
    public static String generatePromptJson(List<AI_Prompt_Component__c> lstOfComponents){
        String masterId = lstOfComponents.get(0).AI_Prompt__r.AI_Data_Extraction_Mapping__c;
        String targetObject = lstOfComponents.get(0).AI_Prompt__r.AI_Data_Extraction_Mapping__r.Object_Name__c;
        
        Map<String, Map<String, String>> mapOfExtIdToMapOfKeyToString = new Map<String, Map<String, String>>();
        for(AI_Prompt_Component__c cmp : lstOfComponents){
            if(!mapOfExtIdToMapOfKeyToString.containsKey(cmp.Data_Extraction_Id__c)){
                mapOfExtIdToMapOfKeyToString.put(cmp.Data_Extraction_Id__c, new Map<String, String>());
            }
            mapOfExtIdToMapOfKeyToString.get(cmp.Data_Extraction_Id__c).put(cmp.Name, cmp.GPTfy_Sentence__c);
        }

        Map<String, AI_Data_Extraction_Detail__c> mapOfExtractionDetails = new Map<String, AI_Data_Extraction_Detail__c>([
            SELECT Id, Parent_Detail__c, AI_Data_Extraction_Mapping__c, Object_hierarchy__c,
            RelationshipField__c, RelationshipName__c
            FROM AI_Data_Extraction_Detail__c 
            WHERE AI_Data_Extraction_Mapping__c =:masterId 
            ORDER BY Parent_Detail__c 
            ASC NULLS FIRST, Object_Name__c
        ]);
        
        List<AI_Data_Extraction_Detail__c> parentList = new List<AI_Data_Extraction_Detail__c>();
        List<AI_Data_Extraction_Detail__c> childList = new List<AI_Data_Extraction_Detail__c>();
        
        Map<String, Object> mapOfDetail = new Map<String, Object>();
        List<String> detailIds = new List<String>();
        
        for(AI_Data_Extraction_Detail__c detail : mapOfExtractionDetails.values()){
            if(detail.Parent_Detail__c != null){
                childList.add(detail);
            }else{
                parentList.add(detail);
            }
            if(!mapOfDetail.containsKey(detail.Id)){
                mapOfDetail.put(detail.Id, mapOfExtIdToMapOfKeyToString.get(detail.Id));
            }                                         
        }
            
        List<Object> listWrap = new List<Object>();
        
        if(!parentList.isEmpty()){
            for(AI_Data_Extraction_Detail__c detail : parentList){
                if(mapOfDetail.containsKey(detail.Id)){
                    Object obj = mapOfDetail.get(detail.Id);
                    Map<String, Object> objMap = new Map<String, Object>();
                    if(!childList.isEmpty()){ 
                        List<Object> children = findRelations(childList, detail.Id, mapOfExtIdToMapOfKeyToString);
                        if(children != null && !children.isEmpty()){
                            objMap.put('children', children);
                        }
                    }
                    if(obj != null){
                        objMap.putAll((Map<String, Object>)obj);
                    }
                    if(!objMap.isEmpty()){
                        listWrap.add(objMap);
                    }
                } 
            }
        }
        
        Map<String, Object> t_wrap = new Map<String, Object>();
        if(listWrap != null && !listWrap.isEmpty()){
            t_wrap.put('children', listWrap);
        }
        if(mapOfExtIdToMapOfKeyToString.containsKey(masterId)){
            t_wrap.putAll(mapOfExtIdToMapOfKeyToString.get(masterId));
        }                                  

        String BASE_BODY = 'Return response in following parsable JSON format';
        return BASE_BODY+'\n'+JSON.serializePretty(t_wrap);
    }
    
    /**
     * Finds relations based on the provided parameters.
     *
     * @param listOfDetails               List of AI_Data_Extraction_Detail__c objects representing details to search.
     * @param rootId                      The root identifier to start the search for relations.
     * @param mapOfExtIdToMapOfKeyToString A mapping of external identifiers to maps of key-value pairs for efficient lookup.
     * @return                             A List of Object representing the found relations.
     */
    public static List<Object> findRelations(List<AI_Data_Extraction_Detail__c> listOfDetails, Id rootId, Map<String, Map<String, String>> mapOfExtIdToMapOfKeyToString){
        List<Object> listWrap = new List<Object>();
        for (AI_Data_Extraction_Detail__c detail : listOfDetails) {
            if (detail.Parent_Detail__c == rootId) {
                List<Object> children = findRelations(listOfDetails, detail.Id, mapOfExtIdToMapOfKeyToString);
                Map<String, Object> data = new Map<String, Object>();
                
                if(children != null && !children.isEmpty()){
                    data.put('children', children);
                }
                if(mapOfExtIdToMapOfKeyToString.containsKey(detail.Id)){
                    data.putAll(mapOfExtIdToMapOfKeyToString.get(detail.Id));
                }
                if(!data.isEmpty()){
                    listWrap.add(data);
                }
            }
        }

        if(!listWrap.isEmpty()){
            return listWrap;
        } 
        return null;
    }

    /**
     * Generates a prompt versioning based on the provided prompt ID and prompt name.
     *
     * @param promptId   The unique identifier for the prompt.
     * @param promptName The name of the prompt.
     */
    public static void generatePromptVersioning(String promptId, String promptName){
        ContentDocumentLink cdl = getContentDocumentLink(promptId, promptName);
        updatePromptVersion(promptId, (cdl!=null?cdl.ContentDocumentId:null));
        ExportMappingWrapper wrap = getExportMappingWrapper(cdl, promptId);
        ContentVersion cv = new ContentVersion();
        cv.VersionData = Blob.valueOf(JSON.serializePretty(wrap));
        cv.Title = promptId;
        cv.PathOnClient = promptId+'.json';
        if(cdl != null){
            cv.ContentDocumentId = cdl.ContentDocumentId;
        }
        cv = (ContentVersion)FLSCheck.getInstance().insertDML(new List<ContentVersion>{cv}).get(0);
        cv = [SELECT Id, ContentDocumentId, VersionNumber FROM ContentVersion WHERE Id =: cv.Id];
        if(cdl == null){
            ContentDocumentLink newcdl = new ContentDocumentLink();
            newcdl.ContentDocumentId = cv.ContentDocumentId;
            newcdl.LinkedEntityId = promptId;
            newcdl.ShareType = 'V';
            FLSCheck.getInstance().insertDML(new List<ContentDocumentLink>{newcdl});
        }
        
    }

    /**
     * Updates the version of a prompt identified by its ID.
     *
     * This method takes a prompt ID and a content document ID as parameters.
     * It is responsible for performing the necessary actions to update the version
     * of the specified prompt. The details of the update process may vary based
     * on the specific requirements of the application.
     *
     * @param promptId           The unique identifier of the prompt to be updated.
     * @param contentDocumentId  The unique identifier of the content document associated
     *                           with the prompt. This is used to identify the specific
     *                           version of the content to be associated with the prompt.
     */
    public static void updatePromptVersion(String promptId, String contentDocumentId){
        Decimal versionNumber = 0;
        if(String.isNotBlank(contentDocumentId)){
            for(ContentVersion cv : [SELECT Id, VersionNumber FROM ContentVersion WHERE ContentDocumentId =: contentDocumentId AND IsLatest=true LIMIT 1]){
                versionNumber = Decimal.valueOf(cv.VersionNumber);
            }
        }
        AI_Prompt__c prompt = new AI_Prompt__c(Id=promptId, Prompt_Version__c=versionNumber+1);
        FLSCheck.getInstance().updateDML(new List<sObject>{prompt});
    }

    /**
     * Retrieves a ContentDocumentLink based on the provided parameters.
     *
     * @param parentId The identifier of the parent record to which the ContentDocumentLink is associated.
     * @param title The title of the ContentDocumentLink to be retrieved.
     * @return A ContentDocumentLink object matching the specified parentId and title, or null if not found.
     */
    public static ContentDocumentLink getContentDocumentLink(String parnetId, String title){
        ContentDocumentLink cdl;
        for(ContentDocumentLink contentDocumentLink : [SELECT Id, ContentDocument.LatestPublishedVersion.VersionData, ContentDocumentId
                                        FROM ContentDocumentLink
                                        WHERE LinkedEntityId=:parnetId AND ContentDocument.Title=:parnetId LIMIT 1]){
            cdl = contentDocumentLink;
        }
        return cdl;
    }

    /**
     * Retrieves the latest ContentVersion associated with the specified ContentDocumentId.
     *
     * @param contentDocumentId The ID of the ContentDocument for which the latest ContentVersion is to be fetched.
     * @return The latest ContentVersion associated with the given ContentDocumentId, or null if not found.
     */
    public static ContentVersion getLatestContentVersion(String contentDocumentId){
        return [SELECT Id, ReasonForChange FROM ContentVersion WHERE ContentDocumentId=:contentDocumentId AND IsLatest=true];
    }

    /**
     * Retrieves an ExportMappingWrapper based on the provided ContentDocumentLink and promptId.
     *
     * @param cdl      The ContentDocumentLink containing information about the document.
     * @param promptId The identifier for the prompt associated with the export mapping.
     * @return An ExportMappingWrapper containing the export mapping details.
     */
    public static ExportMappingWrapper getExportMappingWrapper(ContentDocumentLink cdl, String promptId){
        ExportMappingWrapper wrap = getExistingExportMappingWrapper(cdl);
        ExportMappingWrapper newWrap = getNewExportMappingWrapper(promptId);
        if(wrap == null){
            wrap = newWrap;
            wrap.promptsVersion = wrap.prompts;
        }else{
            wrap.prompts = newWrap.prompts;
            if(wrap.promptsVersion == null){
                wrap.promptsVersion = new List<ExportMappingWrapper.PromptWrapper>();
            }
            wrap.promptsVersion.addAll(newWrap.prompts);
        }
        return wrap;
    }

    /**
     * Retrieves a new ExportMappingWrapper based on the provided prompt ID.
     *
     * @param promptId The ID of the prompt for which the ExportMappingWrapper is created.
     * @return A new ExportMappingWrapper instance.
     */
    public static ExportMappingWrapper getNewExportMappingWrapper(String promptId){
        ExportMappingWrapper newWrap = new ExportMappingWrapper();
        newWrap.exportedOn = System.today();
        newWrap.orgId = UserInfo.getOrganizationId();
        newWrap.exportedBy = UserInfo.getName();
        newWrap = AIPromptExportController.getPromptDetailsService(newWrap, promptId);
        return newWrap;
    } 

    /**
     * Retrieves an existing ExportMappingWrapper based on the provided ContentDocumentLink.
     *
     * @param cdl The ContentDocumentLink used to identify the ExportMappingWrapper.
     * @return An instance of ExportMappingWrapper if found, or null if not found.
     */
    public static ExportMappingWrapper getExistingExportMappingWrapper(ContentDocumentLink cdl){
        ExportMappingWrapper wrap;
        if(cdl != null){
            wrap = (ExportMappingWrapper)JSON.deserialize(cdl.ContentDocument.LatestPublishedVersion.VersionData.toString(), ExportMappingWrapper.class);
        }
        return wrap;
    }
    
}