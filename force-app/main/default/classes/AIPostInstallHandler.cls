/**
 * @description       : 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 06-14-2023
 * @last modified by  : Rishabh Goel
**/
global without sharing class AIPostInstallHandler implements InstallHandler{
	
    /**
     * This method is called when the application is installed.
     *
     * @param context The installation context, providing information about the installation process.
     */
    global void onInstall(InstallContext context){
        if(!context.isUpgrade()){
            manageCards(); 
        	managePrompts(); 
            createDefaultSettings();
        }else{
            manageDataExtractionOrderByAndRecordLimits();
            managePromptSchedulerRecordLimits();
            managePromptProcessingActions();
            //manageVoiceConfigDetail();
        }
    }
    
    /**
     * This method is responsible for managing cards in a global context.
     * It performs actions related to handling and controlling cards.
     * Note: The method is declared as 'global' and 'static', implying it can be
     * accessed globally without requiring an instance of the class.
     */
    global static void manageCards(){
        try{
            String resName = 'PostInstallCards';
            List<StaticResource> lst = [SELECT Id, Body FROM StaticResource WHERE Name =:resName LIMIT 1];
            if(lst != null && !lst.isEmpty() && lst.get(0).Body != null){
                String fileData = lst.get(0).Body.toString();
                if(String.isNotBlank(fileData)){
                    ExportMappingWrapper wrap = (ExportMappingWrapper)System.JSON.deserialize(fileData, ExportMappingWrapper.class);
                    if(wrap != null && wrap.cardConfigs != null && !wrap.cardConfigs.isEmpty()){
                        AICardConfigurationExportController.saveCards(wrap.cardConfigs, true);
                    }
                }
            } 
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPostInstallHandler', 'manageCards', '');
        }
    }
    
    /**
     * This method is responsible for managing prompts in a global context.
     * It performs actions related to handling and controlling prompts.
     * Note: The method is declared as 'global' and 'static', implying it can be
     * accessed globally without requiring an instance of the class.
     */
    global static void managePrompts(){
        try{
            String resName = 'PostInstallPrompts';
            List<StaticResource> lst = [SELECT Id, Body FROM StaticResource WHERE Name =:resName LIMIT 1];
            if(lst != null && !lst.isEmpty() && lst.get(0).Body != null){
                String fileData = lst.get(0).Body.toString();
                if(String.isNotBlank(fileData)){
                    ExportMappingWrapper wrap = (ExportMappingWrapper)System.JSON.deserialize(fileData, ExportMappingWrapper.class);
                    if(wrap != null && wrap.prompts != null && !wrap.prompts.isEmpty()){
                        
                        List<ExportMappingWrapper.ExtractionSecurityFilterWrapper> filters = new List<ExportMappingWrapper.ExtractionSecurityFilterWrapper>();
                        if(wrap.securityFilters != null && !wrap.securityFilters.isEmpty()){
                            for(String key : wrap.securityFilters.keySet()){
                                if(wrap.securityFilters.get(key) != null && !wrap.securityFilters.get(key).isEmpty()){
                                    filters.addAll(wrap.securityFilters.get(key));
                                } 
                            }
                        }
                        
                        AIPromptImportController.saveMappings(wrap.prompts, wrap.connections.values(), wrap.dataExtractionMappings.values(), filters, wrap.dataSources, true);
                    }
                }
            } 
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPostInstallHandler', 'managePrompts', '');
        }
    }

	/**
     * This method is responsible for updating custom settings during upgrade.
    **/    
    public static void createDefaultSettings(){
        GPTfy_Settings__c settings = GPTfy_Settings__c.getOrgDefaults();
        settings.Exception_Log__c = false;
        settings.File_Processing__c = false;
        settings.Prefix_Suffix__c = false;
        settings.Prompt_Versioning__c = false;
        settings.Typewriter_Effect__c = false;
        settings.File_Type__c = 'pdf,jpg';
        settings.Max_File_Count__c = 3;
        settings.Max_File_Size__c = 3;
        settings.Reporting_Period__c = 1;
        settings.Hourly_Cost__c = 100;
        FLSCheck.getInstance().upsertDML(new List<GPTfy_Settings__c>{settings});
    }
    
    public static void manageDataExtractionOrderByAndRecordLimits(){
        List<AI_Data_Extraction_Detail__c> lstToProcess = [SELECT Id, Where_Clause__c, Order_By__c, Record_Limit__c, Object_Name__c, RelationshipName__c
                                                           FROM AI_Data_Extraction_Detail__c 
                                                           WHERE Order_By__c != NULL
                                                           OR Record_Limit__c != NULL];
        if(lstToProcess != null && !lstToProcess.isEmpty()){
            List<AI_Data_Extraction_Detail__c> lstToUpdate = new List<AI_Data_Extraction_Detail__c>();
            for(AI_Data_Extraction_Detail__c d : lstToProcess){
                String whereClause = '';
                if(String.isNotBlank(d.Where_Clause__c)){
                    whereClause += d.Where_Clause__c;
                }
                if(String.isNotBlank(d.Order_By__c) && (String.isBlank(whereClause) || !whereClause.containsIgnoreCase('ORDER BY '))){
                    String orderby = ' ORDER BY CreatedDate ';
                    if(d.Object_Name__c.endsWithIgnoreCase('__x')){ //this check is for external objects
                        orderby = ' ORDER BY CreatedDate__c ';
                    }else if(String.isNotBlank(d.RelationshipName__c) && d.RelationshipName__c == 'ActivityHistories'){
                        orderby = ' ORDER BY LastModifiedDate ';
                    }
                    whereClause += orderby+' '+d.Order_By__c;
                }
                if(d.Record_Limit__c != NULL && (String.isBlank(whereClause) || !whereClause.containsIgnoreCase('LIMIT '))){
                    whereClause += ' LIMIT '+d.Record_Limit__c;
                }
                d.Where_Clause__c = whereClause;
                d.Order_By__c = null;
                d.Record_Limit__c = null;
                lstToUpdate.add(d);
            }
            if(!lstToUpdate.isEmpty()){
                FLSCheck.getInstance().updateDML(lstToUpdate);
            }
        }
    }
    
    public static void managePromptSchedulerRecordLimits(){
        List<AI_Prompt_Scheduler__c> lstToProcess = [SELECT Id, Where_Clause__c, Record_Limit__c 
                                                     FROM AI_Prompt_Scheduler__c 
                                                     WHERE Record_Limit__c != NULL];
        if(lstToProcess != null && !lstToProcess.isEmpty()){
            List<AI_Prompt_Scheduler__c> lstToUpdate = new List<AI_Prompt_Scheduler__c>();
            for(AI_Prompt_Scheduler__c d : lstToProcess){
                String whereClause = '';
                if(String.isNotBlank(d.Where_Clause__c)){
                    whereClause += d.Where_Clause__c;
                }
                if(d.Record_Limit__c != NULL && (String.isBlank(whereClause) || !whereClause.containsIgnoreCase('LIMIT '))){
                    whereClause += ' LIMIT '+d.Record_Limit__c;
                }
                d.Where_Clause__c = whereClause;
                d.Record_Limit__c = null;
                lstToUpdate.add(d);
            }
            if(!lstToUpdate.isEmpty()){
                //List<sObject> lstToBeUpdated = (List<sObject>)lstToUpdate;
                //lstToBeUpdated = FLSCheck.getInstance().updateCheck(lstToBeUpdated);
                //if(lstToUpdate != null && !lstToUpdate.isEmpty()){
                    FLSCheck.getInstance().updateDML(lstToUpdate, false);
                    //Database.update(lstToBeUpdated, false, AccessLevel.USER_MODE);
                //}
            }
        }
    }
    
    //JIRA-V2-4986 : Prompt Action Framework
    public static void managePromptProcessingActions(){
        //Script to convert Target Field & Append Timestamp as records of Prompt Action.
        Set<String> setPromptId = new Set<String>();
        Set<String> setFieldAPIName = new Set<String>();
        List<AI_Prompt__c> lstAIPromptToUpdate = new List<AI_Prompt__c>();
        List<AI_Response_Processing__c> lstAIResponseProcessing = new List<AI_Response_Processing__c>();
        List<AI_Prompt_Action__c> lstAIPromptActionsToInsert = new List<AI_Prompt_Action__c>();
        Map<Id, AI_Prompt_Action__c> aIPromptActionsToUpdate = new Map<Id, AI_Prompt_Action__c>();
        Map<String, AI_Prompt_Action__c> mapExistingPromptAction = new Map<String, AI_Prompt_Action__c>();
        
        for(AI_Prompt__c prompt : [SELECT Id, Target_Field__c, Append_Timestamp__c FROM AI_Prompt__c WHERE Target_Field__c != null]){
            setPromptId.add(prompt.Id);
            setFieldAPIName.add(prompt.Target_Field__c);
            lstAIPromptToUpdate.add(prompt);
        }
        for(AI_Response_Processing__c responseProcessing : [SELECT Id, AI_Prompt_Component__r.AI_Prompt__c, Destination_Field__c,  Append_Timestamp__c FROM AI_Response_Processing__c WHERE Action__c = :AIConstants.ACTION_TYPE_UPDATE_FIELD]){
            setPromptId.add(responseProcessing.AI_Prompt_Component__r.AI_Prompt__c);
            setFieldAPIName.add(responseProcessing.Destination_Field__c);
            lstAIResponseProcessing.add(responseProcessing);
        }
        if(setPromptId.size()>0 && setFieldAPIName.size()>0){
            for(AI_Prompt_Action__c promptAction : [SELECT Id, AI_Prompt__c, Field_API_Name__c, Action__c, Append_Timestamp__c FROM AI_Prompt_Action__c WHERE AI_Prompt__c IN:setPromptId AND Field_API_Name__c IN:setFieldAPIName AND Action__c=:AIConstants.ACTION_TYPE_UPDATE_FIELD]){
                mapExistingPromptAction.put(promptAction.AI_Prompt__c+'_'+promptAction.Field_API_Name__c+'_'+promptAction.Action__c, promptAction);
            }
        }
        if(lstAIPromptToUpdate.size()>0){
            for(AI_Prompt__c prompt : lstAIPromptToUpdate){
                if(mapExistingPromptAction.containsKey(prompt.Id+'_'+prompt.Target_Field__c+'_'+AIConstants.ACTION_TYPE_UPDATE_FIELD)){
                    AI_Prompt_Action__c promptAction = mapExistingPromptAction.get(prompt.Id+'_'+prompt.Target_Field__c+'_'+AIConstants.ACTION_TYPE_UPDATE_FIELD);
                    promptAction.Append_Timestamp__c = prompt.Append_Timestamp__c;
                    aIPromptActionsToUpdate.put(promptAction.Id, promptAction); 
                }else{
                    AI_Prompt_Action__c promptAction = new AI_Prompt_Action__c();
                    promptAction.AI_Prompt__c = prompt.Id;
                    PromptAction.Action__c = AIConstants.ACTION_TYPE_UPDATE_FIELD;
                    promptAction.Field_API_Name__c = prompt.Target_Field__c;
                    promptAction.Append_Timestamp__c = prompt.Append_Timestamp__c;
                    lstAIPromptActionsToInsert.add(promptAction);
                }
                
                prompt.Target_Field__c = null;
                prompt.Append_Timestamp__c = false;
            }
        }
        if(lstAIResponseProcessing.size()>0){
            for(AI_Response_Processing__c responseProcessing : lstAIResponseProcessing){
                if(mapExistingPromptAction.containsKey(responseProcessing.AI_Prompt_Component__r.AI_Prompt__c+'_'+responseProcessing.Destination_Field__c+'_'+AIConstants.ACTION_TYPE_UPDATE_FIELD)){
                    AI_Prompt_Action__c promptAction = mapExistingPromptAction.get(responseProcessing.AI_Prompt_Component__r.AI_Prompt__c+'_'+responseProcessing.Destination_Field__c+'_'+AIConstants.ACTION_TYPE_UPDATE_FIELD);
                    promptAction.Append_Timestamp__c = responseProcessing.Append_Timestamp__c;
                    aIPromptActionsToUpdate.put(promptAction.Id, promptAction); 
                }else{
                    AI_Prompt_Action__c promptAction = new AI_Prompt_Action__c();
                    promptAction.AI_Prompt__c = responseProcessing.AI_Prompt_Component__r.AI_Prompt__c;
                    PromptAction.Action__c = AIConstants.ACTION_TYPE_UPDATE_FIELD;
                    promptAction.Field_API_Name__c = responseProcessing.Destination_Field__c;
                    promptAction.Append_Timestamp__c = responseProcessing.Append_Timestamp__c;
                    lstAIPromptActionsToInsert.add(promptAction);
                }
            }
        }
        if(lstAIPromptToUpdate.size()>0){
            FLSCheck.getInstance().updateDML(lstAIPromptToUpdate, false);
            //List<sObject> lstToBeUpdated = (List<sObject>)lstAIPromptToUpdate;
            //lstToBeUpdated = FLSCheck.getInstance().updateCheck(lstToBeUpdated);
            //if(lstToBeUpdated != null && !lstToBeUpdated.isEmpty()){
                //Database.update(lstToBeUpdated, false);
            //}
        }
        if(lstAIResponseProcessing.size() > 0){
            FLSCheck.getInstance().deleteDML(lstAIResponseProcessing);
        }
        if(lstAIPromptActionsToInsert.size()>0){
            FLSCheck.getInstance().insertDML(lstAIPromptActionsToInsert, false);
            //List<sObject> lstToBeInsert = (List<sObject>)lstAIPromptActionsToInsert;
            //lstToBeInsert = FLSCheck.getInstance().insertCheck(lstToBeInsert);
            //if(lstToBeInsert != null && !lstToBeInsert.isEmpty()){
                //Database.insert(lstToBeInsert, false);
            //}
        }
        if(!aIPromptActionsToUpdate.IsEmpty()){
            FLSCheck.getInstance().updateDML(aIPromptActionsToUpdate.values(), false);
            //List<sObject> lstToBeUpdate = (List<sObject>)aIPromptActionsToUpdate.values();
            //lstToBeUpdate = FLSCheck.getInstance().updateCheck(lstToBeUpdate);
            //if(lstToBeUpdate != null && !lstToBeUpdate.isEmpty()){
                //Database.update(lstToBeUpdate, false, AccessLevel.USER_MODE);
            //}
        }
    }
    
    /*
    public static void manageVoiceConfigDetail(){
        List<AI_Voice_Configuration_Detail__c> lstOfDetails = [SELECT Id, Profile__c, Profiles__c 
                                                               FROM AI_Voice_Configuration_Detail__c 
                                                               WHERE Profile__c != NULL];
        if(lstOfDetails != null && !lstOfDetails.isEmpty()){
            for(AI_Voice_Configuration_Detail__c detail : lstOfDetails){
            	detail.Profiles__c = detail.Profile__c;
        	}
            FLSCheck.getInstance().updateDML(lstOfDetails);
        }
    }
	*/
}