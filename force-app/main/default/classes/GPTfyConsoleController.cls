/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class GPTfyConsoleController {
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    
    /*
    * This method is used for get open form action of prompt
    * param : promptId - prompt record id
    * return : Map<String, Object>
    */
    @AuraEnabled
    public static Map<String,Object> getPromptActionOptionsOpenForm(String promptId){
        
        String profileName = [SELECT Id, Name 
                              FROM Profile 
                              WHERE Id =:UserInfo.getProfileId() 
                              LIMIT 1].Name;
        
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        OptionWrapper options = new OptionWrapper();
        Map<String, AI_Prompt__c> mapOfPrompt = new Map<String, AI_Prompt__c>();
        AI_Prompt__c pmt = [SELECT Id,
                            (SELECT Id, Name, Object_Name__c, Description__c 
                             FROM Prompt_Actions__r 
                             WHERE Action__c =:AIConstants.ACTION_TYPE_OPEN_FORM 
                             ORDER BY Sequence__c)
                            FROM AI_Prompt__c 
                            WHERE Id =:promptId 
                            AND AI_Data_Extraction_Mapping__c != NULL];
        List<ActionWrapper> actions = new List<ActionWrapper>();
       if(pmt.Prompt_Actions__r != null && !pmt.Prompt_Actions__r.isEmpty()){
           for(AI_Prompt_Action__c pa : pmt.Prompt_Actions__r){
               ActionWrapper act = new ActionWrapper();
               act.actionId = pa.Id;
               act.objectName = pa.Object_Name__c;
               act.objectLabel = (String)gd.get(pa.Object_Name__c).getDescribe().getLabel();
               act.description = pa.Description__c;
               actions.add(act);
           }
        }
        Map<String, Object> data = new Map<String, Object>();
        data.put('actions', actions);
        return data;
    }
    
    
    
    @AuraEnabled
    public static Boolean isAdminUser(){
        List<String> validPermSets = new List<String>{'SGPT_Admin'};
        String l_namespace = NAMESPACE;
        if(String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')){
            l_namespace = l_namespace.removeEndIgnoreCase('__');
        }
        List<PermissionSetAssignment> psas = [SELECT Id FROM PermissionSetAssignment 
                                              WHERE PermissionSet.Name IN :validPermSets 
                                              AND AssigneeId = :UserInfo.getUserId()
                                              AND PermissionSet.NamespacePrefix =:l_namespace];
        if(psas != null && !psas.isEmpty()){
            return true;
        }
        return false;
    }

    @AuraEnabled
    public static Boolean isPortalUser(){
        List<String> validPermSets = new List<String>{'SGPT_Admin', 'SGPT_User'};
        String l_namespace = NAMESPACE;
        if(String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')){
            l_namespace = l_namespace.removeEndIgnoreCase('__');
        }
        List<PermissionSetAssignment> psas = [SELECT Id FROM PermissionSetAssignment 
                                              WHERE PermissionSet.Name IN :validPermSets 
                                              AND AssigneeId = :UserInfo.getUserId()
                                              AND PermissionSet.NamespacePrefix =:l_namespace];
        if(psas != null && !psas.isEmpty()){
            return false;
        }
        return true;
    }
    
    @AuraEnabled
    public static Map<String, Object> getPromptOptions(String recordId, String objectApiName){  
        
        String l_namespace = NAMESPACE;
        if(String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')){
            l_namespace = l_namespace.removeEndIgnoreCase('__');
        }
        
        List<PermissionSetAssignment> gptfyPermSetAssignments = [SELECT Id FROM PermissionSetAssignment 
                                                                WHERE AssigneeId =:UserInfo.getUserId()
                                                                AND (PermissionSet.Name =:AIConstants.GPTFY_ADMIN_PERM_SET
                                                                OR PermissionSet.Name =:AIConstants.GPTFY_USER_PERM_SET
                                                                OR PermissionSet.Name =:AIConstants.GPTFY_PORTAL_PERM_SET)
                                                                AND PermissionSet.NamespacePrefix =:l_namespace];
        if(gptfyPermSetAssignments == null || gptfyPermSetAssignments.isEmpty()){
            return null;
        }
		// Jira 6566: Security - Permission Set Dependency
		Set<String> assignedPermissionSets = new Set<String>();        
        for(PermissionSetAssignment psa : [SELECT Id, PermissionSet.Label 
                                           FROM PermissionSetAssignment
                                           WHERE AssigneeId =:UserInfo.getUserId()]){
            assignedPermissionSets.add(psa.PermissionSet.Label.toLowerCase());
        }
        
        if(String.isBlank(objectApiName) && String.isNotBlank(recordId)){
            objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
        }
        
        String profileName = [SELECT Id, Name FROM Profile WHERE Id =:UserInfo.getProfileId() LIMIT 1].Name;
        
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        List<OptionWrapper> options = new List<OptionWrapper>();
        Map<String, AI_Prompt__c> mapOfPrompt = new Map<String, AI_Prompt__c>();
        for(AI_Prompt__c pmt : [SELECT Id, Name, Profiles__c, Record_Type__c, Custom_Prompt__c, Description__c,
                                AI_Data_Extraction_Mapping__c, Type__c, Include_Files__c, Visibility_Condition__c, Visibility_Exception_Message__c,
                                Permission_Sets__c,AI_Model_File_Processing__r.Model__c,
                                (SELECT Id, Name, Object_Name__c, Description__c FROM Prompt_Actions__r WHERE Action__c =:AIConstants.ACTION_TYPE_OPEN_FORM ORDER BY Sequence__c)
                                FROM AI_Prompt__c 
                                WHERE Status__c =:AIConstants.PMT_STATUS_ACTIVE 
                                AND Object__c =:objectApiName 
                                AND AI_Data_Extraction_Mapping__c != NULL
                                AND (AI_Connection__r.Type__c = '' OR AI_Connection__r.Type__c =:AIConstants.AI_MODEL_TYPE_CHAT)]){
          // Jira 6566: Security - Permission Set Dependency  
          if((String.isBlank(pmt.Profiles__c) && String.isBlank(pmt.Permission_Sets__c)) ||
              (String.isNotBlank(pmt.Profiles__c) && pmt.Profiles__c.containsIgnoreCase(profileName)) ||
              (String.isNotBlank(pmt.Permission_Sets__c) && checkMatchingSets(assignedPermissionSets, pmt.Permission_Sets__c.toLowerCase().split(';')))){                     
                mapOfPrompt.put(pmt.Id, pmt);
                OptionWrapper opt = new OptionWrapper();
                opt.label = pmt.Name;
                opt.value = pmt.Id;
                opt.allowUserInput = pmt.Custom_Prompt__c;
                opt.includeFiles = pmt.Include_Files__c;
                opt.visibilityCondition = pmt.Visibility_Condition__c;
                opt.promptDescription = pmt.Description__c;
                opt.recordTypes = String.isNotBlank(pmt.Record_Type__c) ? pmt.Record_Type__c.split(';') : new List<String>();
                opt.visibilityExceptionMessage = pmt.Visibility_Exception_Message__c;
                opt.type = pmt.Type__c;
                opt.connectionModel = pmt?.AI_Model_File_Processing__r?.Model__c;
                if(pmt.Prompt_Actions__r != null && !pmt.Prompt_Actions__r.isEmpty()){
                    List<ActionWrapper> actions = new List<ActionWrapper>();
                    for(AI_Prompt_Action__c pa : pmt.Prompt_Actions__r){
                        ActionWrapper act = new ActionWrapper();
                        act.actionId = pa.Id;
                        act.objectName = pa.Object_Name__c;
                        String objLabel = pa.Object_Name__c;
                        if(gd.containsKey(pa.Object_Name__c) && gd.get(pa.Object_Name__c) != null){
                            objLabel = (String)gd.get(pa.Object_Name__c).getDescribe().getLabel();
                        }
                        act.objectLabel = objLabel;
                        act.description = pa.Description__c;
                        actions.add(act);
                    }
                    opt.actions = actions;
                }
                options.add(opt);
            }
        }
        
        Map<String, Object> data = new Map<String, Object>();
        
        if(options != null && !options.isEmpty()){
            options.sort();
        }
        data.put('options', options);
        
        List<AI_Prompt_Component__c> lstOfComponent = [SELECT Id, Data_Extraction_Id__c, Object_Name__c, Name, AI_Prompt__c FROM AI_Prompt_Component__c 
                                                       WHERE AI_Prompt__c IN :mapOfPrompt.keySet() AND Data_Extraction_Id__c != Null
                                                       AND Key__c = 'Sentiment'];
        Map<String, String> mapOfPromptIdToSentimentKey = new Map<String, String>();
        if(lstOfComponent != null && !lstOfComponent.isEmpty()){
            for(AI_Prompt_Component__c pc : lstOfComponent){
                if(mapOfPrompt.get(pc.AI_Prompt__c).AI_Data_Extraction_Mapping__c == pc.Data_Extraction_Id__c){
                    mapOfPromptIdToSentimentKey.put(pc.AI_Prompt__c, pc.Name);
                }
            }
        }
        
        if(!mapOfPromptIdToSentimentKey.isEmpty()){
            data.put('mapOfSentimentKey', mapOfPromptIdToSentimentKey);
        }
        
        List<AI_Response__c> lstOfResponses = getAllResponses(recordId);
        if(lstOfResponses != null && !lstOfResponses.isEmpty()){
            data.put('lstOfResponses', lstOfResponses);
        }
        data.put('options', options);
        
        List<User> lstOfUser = [SELECT Id, Signature FROM User WHERE Id =:UserInfo.getUserId() LIMIT 1];
        if(lstOfUser != null && !lstOfUser.isEmpty()){
            data.put('userSign', lstOfUser.get(0).Signature);
        }
        
        data.put('feedbackCategoryOptions', AIPromptController.getPickListValues(NAMESPACE+'AI_Feedback__c', NAMESPACE+'Category__c'));
        data.put('namespace', NAMESPACE);
        
        List<QuickAction.DescribeAvailableQuickActionResult> lstOfQuickActions = QuickAction.DescribeAvailableQuickActions(objectApiName);
        if(lstOfQuickActions != null && !lstOfQuickActions.isEmpty()){
            for(QuickAction.DescribeAvailableQuickActionResult qa : lstOfQuickActions){
                if(qa.getType() == 'SendEmail'){
                    String actionName = qa.getName();
                    if(actionName.startsWithIgnoreCase(objectApiName)){
                        data.put('emailActionName', actionName);
                        break;
                    }else if(!actionName.startsWithIgnoreCase(objectApiName)){
                        data.put('emailActionName', 'Global.'+actionName);
                    }
                }
            }
        }
        return data;
    }
    // Jira 6566: Security - Permission Set Dependency
    public static Boolean checkMatchingSets(Set<String> mainSet, List<String> subSet){
        Boolean isMatch = false;
        for(String sub1 : subSet){
            if(mainSet.contains(sub1)){
                isMatch = true;
                break;
            }
        }
        return isMatch;
    }
    
    @AuraEnabled
    public static Boolean isValidVisibilityCondition(String objectApiName, String recordId, String whereClause, List<String> selectedRecordTypes){
        try {
            if(String.isBlank(objectApiName) && String.isNotBlank(recordId)){
            	objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
            }
            String query = 'SELECT Id FROM '+String.escapeSingleQuotes(objectApiName)+' WHERE Id =:recordId ';
			
            if(selectedRecordTypes != null && !selectedRecordTypes.isEmpty()){
                query += 'AND RecordTypeId != NULL AND RecordType.DeveloperName IN :selectedRecordTypes ';
            }
            if(String.isNotBlank(whereClause)){
                whereClause = whereClause.trim();
                if(whereClause.startsWithIgnoreCase('ORDER BY ') || whereClause.startsWithIgnoreCase('LIMIT ')){
                    query += ' '+String.escapeSingleQuotes(whereClause);
                }else{
                    query += ' AND '+String.escapeSingleQuotes(whereClause);
                }
            }
            if(query.containsIgnoreCase(' LIMIT ')){
                Integer index = query.lastIndexOfIgnoreCase(' LIMIT ');
                if(index > -1){
                    query = query.substring(0, index);
                }
            }
            query += ' LIMIT 1 ';

            query = query.replace('\\\'', '\'');
            List<sobject> objList = Database.query(query);
        	return objList.size() > 0;
        }catch(Exception e){
            return false;
        }
    }

    // v2/7427 Slow GPTfy User Console
    @AuraEnabled
    public static List<AI_Response__c> getAllResponses(String recordId){
        List<AI_Response__c> lst = new List<AI_Response__c>();
        
        String profileName = [SELECT Id, Name FROM Profile WHERE Id =:UserInfo.getProfileId() LIMIT 1].Name;
        
        for(AI_Response__c resp : [SELECT Id, Name, Record_Id__c, CreatedDate,Vector_Store_Id__c, Thread_Id__c,AI_Prompt__c,
                                        AI_Processed_Data_PII_Added__c,Prompt_Tokens__c, Total_Tokens__c,
                                        Is_Canvas_Response__c, Profiles__c,Time_Saved_Seconds__c, Time_Estimate_Seconds__c,How_It_Works__c, 
                                        (SELECT Id, Type__c FROM Feedbacks__r WHERE User__c =:UserInfo.getUserId() LIMIT 1)
                                FROM AI_Response__c WHERE Record_Id__c =:recordId 
                                AND (CreatedById =:UserInfo.getUserId() OR Scheduled_Run__c != NULL)
                                AND Status__c =:AIConstants.RESP_STATUS_PROCESSED
                                AND AI_Parent_Response__c = NULL
                                ORDER BY CreatedDate DESC LIMIT 49999]){
            if((String.isNotBlank(resp.AI_Processed_Data_PII_Added__c) || resp.Is_Canvas_Response__c == true) && (String.isBlank(resp.Profiles__c) || resp.Profiles__c.containsIgnoreCase(profileName))){
                lst.add(resp);
            }
        }
        return lst;
    }


    // v2/7427 Slow GPTfy User Console
    @AuraEnabled(cacheable=true)
    public static AI_Response__c getCurrentResponse(String responseId){
        AI_Response__c resp = [SELECT Id, Name, Record_Id__c, Data_Original__c, CreatedDate, AI_Prompt__c, Data_PII_Key__c,
                                Data_PII_Removed__c, AI_Processed_Data_No_PII__c, AI_Processed_Data_PII_Added__c, Completion_Tokens__c,
                                Is_Canvas_Response__c,Vector_Store_Id__c, Thread_Id__c,
                                Prompt_Tokens__c, Total_Tokens__c, Time_Saved_Seconds__c, Time_Estimate_Seconds__c, Profiles__c, How_It_Works__c,
                                (SELECT Id, Type__c FROM Feedbacks__r WHERE User__c =:UserInfo.getUserId() LIMIT 1)
                                FROM AI_Response__c WHERE Id =:responseId LIMIT 1];
       if(resp != null){
        return resp;
       }
       return null;
    }

    // v2/7427 Slow GPTfy User Console
    /*@AuraEnabled
    public static List<AI_Response__c> getAllResponses(String recordId){
        List<AI_Response__c> lst = new List<AI_Response__c>();
        
        String profileName = [SELECT Id, Name FROM Profile WHERE Id =:UserInfo.getProfileId() LIMIT 1].Name;
        
        for(AI_Response__c resp : [SELECT Id, Name, Record_Id__c, Data_Original__c, CreatedDate, AI_Prompt__c, Data_PII_Key__c,
                                Data_PII_Removed__c, AI_Processed_Data_No_PII__c, AI_Processed_Data_PII_Added__c, Completion_Tokens__c,
                                Is_Canvas_Response__c,Vector_Store_Id__c, Thread_Id__c,
                                Prompt_Tokens__c, Total_Tokens__c, Time_Saved_Seconds__c, Time_Estimate_Seconds__c, Profiles__c, How_It_Works__c,
                                (SELECT Id, Type__c FROM Feedbacks__r WHERE User__c =:UserInfo.getUserId() LIMIT 1)
                                FROM AI_Response__c WHERE Record_Id__c =:recordId 
                                AND (CreatedById =:UserInfo.getUserId() OR Scheduled_Run__c != NULL)
                                AND Status__c =:AIConstants.RESP_STATUS_PROCESSED
                                AND AI_Parent_Response__c = NULL
                                ORDER BY CreatedDate DESC]){
            if((String.isNotBlank(resp.AI_Processed_Data_PII_Added__c) || resp.Is_Canvas_Response__c == true) && (String.isBlank(resp.Profiles__c) || resp.Profiles__c.containsIgnoreCase(profileName))){
                lst.add(resp);
            }
        }
        return lst;
    }*/


    
    @AuraEnabled
    public static List<AI_Response__c> getSecurityAudit(String responseId){
        return [SELECT Id, Name, Record_Id__c, Data_Original__c, CreatedDate, AI_Prompt__c, Data_PII_Key__c,
                Data_PII_Removed__c, AI_Processed_Data_No_PII__c, AI_Processed_Data_PII_Added__c, Completion_Tokens__c,
                Prompt_Tokens__c, Total_Tokens__c, Time_Saved_Seconds__c, Time_Estimate_Seconds__c,Vector_Store_Id__c,User_Context_Id__c
                FROM AI_Response__c WHERE Id =:responseId LIMIT 1];
    }

    //Jira 7125 : Enhance Security Audit Response Viewer to handle Chat Experience
    @AuraEnabled
    public static List<ChatMessageWrapper> getChatMessageSecurityAuditDetails(String responseId){
       List<AI_Security_Audit_Detail__c> securityAuditDetailsList = [SELECT Id,Message__c FROM AI_Security_Audit_Detail__c 
                                                                        WHERE AI_Security_Audit__c =:responseId LIMIT 49999];
        List<ChatMessageWrapper> chatMessages = new List<ChatMessageWrapper>();
        Integer sequence = 1;
        for(AI_Security_Audit_Detail__c detail : securityAuditDetailsList){
            	if(detail.Message__c != null){
                    List<ChatMessageWrapper> messages = (List<ChatMessageWrapper>)JSON.deserialize(detail.Message__c, List<ChatMessageWrapper>.class);
                    for(ChatMessageWrapper msg : messages){
                        if (msg.role == 'user') {
                            msg.question = msg.content;
                        } else if (msg.role == 'assistant') {
                            msg.answer = msg.content;
                        }
                        if(msg.question != null || msg.answer != null){
                            msg.sequence = sequence++;
                            chatMessages.add(msg);
                        }
                    }
                }
        }
        return chatMessages;
    }
    
    @AuraEnabled
    public static List<RecordWrapper> checkForContentVersions(String recordId, String promptId){
        AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
        
        AI_Data_Extraction_Mapping__c extractionMapping = AIDataExtractionSelector.getAIDataExtractionMappingById(aiPrompt.AI_Data_Extraction_Mapping__c);
        List<AI_Data_Extraction_Detail__c> extractionDetails = AIDataExtractionSelector.getAIDataExtractionDetailByMappingId(extractionMapping.Id);
        
        Set<String> setOfObjectNames = new Set<String>();
        setOfObjectNames.add(extractionMapping.Object_Name__c);
        for(AI_Data_Extraction_Detail__c det : extractionDetails){
            setOfObjectNames.add(det.Object_Name__c);
        }
       
        Map<String, String> mapOfObjToNameField = new Map<String, String>();
        Set<String> setOfQueryableObjects = new Set<String>();
        for(FieldDefinition fd : [SELECT QualifiedApiName, EntityDefinition.QualifiedApiName, EntityDefinition.IsQueryable FROM FieldDefinition 
                                  WHERE EntityDefinition.QualifiedApiName IN :setOfObjectNames AND IsNameField = True LIMIT 200]){
            mapOfObjToNameField.put(fd.EntityDefinition.QualifiedApiName.toLowerCase(), fd.QualifiedApiName);
            if(fd.EntityDefinition.IsQueryable){
                setOfQueryableObjects.add(fd.EntityDefinition.QualifiedApiName.toLowerCase());
            }                          
        }
        
        String query = 'SELECT Id, '+mapOfObjToNameField.get(extractionMapping.Object_Name__c.toLowerCase())+' FROM '+extractionMapping.Object_Name__c+' WHERE Id=:recordId WITH SECURITY_ENFORCED LIMIT 1';    
        Sobject parentSobject = Database.query(query);
        
        Map<String, String> mapOfIdToName = new Map<String, String>();
        mapOfIdToName.put(String.valueOf(parentSobject.get('Id')), String.valueOf(parentSobject.get(mapOfObjToNameField.get(extractionMapping.Object_Name__c.toLowerCase()))));

        
        for(AI_Data_Extraction_Detail__c extractionDetail : extractionDetails){
            Set<String> setOfFieldApis = new Set<String>{'Id'};
            //List<SObject> sobjs = new List<SObject>();
            
            if(String.isNotBlank(extractionDetail.Object_Name__c) && mapOfObjToNameField.containsKey(extractionDetail.Object_Name__c.toLowerCase())){
                String nameFieldApi = mapOfObjToNameField.get(extractionDetail.Object_Name__c.toLowerCase());
                if(String.isNotBlank(nameFieldApi) && !setOfFieldApis.contains(nameFieldApi)){
                    setOfFieldApis.add(nameFieldApi);
                }
            }
            
            //adding relationship field to the queryfields as well
            if(String.isNotBlank(extractionDetail.RelationshipField__c) && !setOfFieldApis.contains(extractionDetail.RelationshipField__c)){
                setOfFieldApis.add(extractionDetail.RelationshipField__c);
            }
            
            //if(setOfQueryableObjects == null || !setOfQueryableObjects.contains(extractionDetail.Object_Name__c.toLowerCase())){
            List<SObject> sobjs = AIDataExtractionService.queryRecordsForChildQueryable(recordId, extractionDetail, String.join(new List<String>(setOfFieldApis), ','),null);
            //}else{
                //sobjs = AIDataExtractionService.queryRecords(recordId, extractionDetail, String.join(new List<String>(setOfFieldApis), ','));
            //}
            
            for(Sobject sobj : sobjs){
                if(String.isNotBlank(extractionDetail.Object_Name__c) && mapOfObjToNameField.containsKey(extractionDetail.Object_Name__c.toLowerCase())){
                    String nameFieldApi = mapOfObjToNameField.get(extractionDetail.Object_Name__c.toLowerCase());
                    if(String.isNotBlank(nameFieldApi)){
                        mapOfIdToName.put(String.valueOf(sobj.get('Id')), String.valueOf(sobj.get(nameFieldApi)));
                    }
                }
            }
        }
        
        if(!mapOfIdToName.isEmpty()){
            Map<String, String> mapOfCdIdToRecId = new Map<String, String>();
            for(ContentDocumentLink cdl : [SELECT LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :mapOfIdToName.keySet()]){
                mapOfCdIdToRecId.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            }
            if(!mapOfCdIdToRecId.isEmpty()){
                GPTfy_Settings__c settings = GPTfy_Settings__c.getOrgDefaults();
                Map<String, RecordWrapper> mapOfRecordWrapper = new Map<String, RecordWrapper>();
                for(ContentVersion cv : [SELECT FileExtension,VersionData, ContentDocumentId, Title, FileType, ContentSize FROM ContentVersion 
                                         WHERE ContentDocumentId IN :mapOfCdIdToRecId.keySet() AND IsLatest = true]){
                    if(cv.ContentSize != null){
                            if(settings.Max_File_Size__c != NULL){
                                 Double s = (cv.ContentSize/1024);
                                 s= (s/1024);
                                if(s > settings.Max_File_Size__c){
                                    continue;
                                }
                    		}                     
                     }
                    if(String.isNotBlank(settings.File_Type__c)){
                                String ftype = cv.FileExtension.toLowerCase();
                                List<String> fileTypesSetting = settings.File_Type__c.split(',');
                                Boolean isFileMatch = false;
                                     for(String f : fileTypesSetting){
                                         if(ftype.contains(f.toLowerCase())){
                                    		isFileMatch = true;
                                		}
                                     }
                         if(!isFileMatch){
                             continue;
                         }
                         		
                     }
                    
                    String recId = mapOfCdIdToRecId.get(cv.ContentDocumentId);                         
                    if(!mapOfRecordWrapper.containsKey(recId)){
                        RecordWrapper rw = new RecordWrapper();
                        rw.recId = recId;
                        rw.name = mapOfIdToName.get(recId);
                        rw.files = new List<FileWrapper>();
                        mapOfRecordWrapper.put(recId, rw);
                    }
                                             
                    FileWrapper fw = new FileWrapper();
                    fw.docId = cv.ContentDocumentId;
                    fw.title = cv.Title;
                    fw.recId = recId;
                    fw.fileType = cv.FileExtension;  
                    fw.fileSize = (cv.ContentSize != null && cv.ContentSize > 0 ? cv.ContentSize : 0)+' bytes';                           
                    mapOfRecordWrapper.get(recId).files.add(fw);                         
                }
                if(!mapOfRecordWrapper.isEmpty()){
                    return mapOfRecordWrapper.values();
                }
            }
        }
        return null;
    }
    
    @AuraEnabled
    public static void saveFeedback(String responseId, String feedback, String feedbackCategory, String feebackDetail){
        AI_Feedback__c fb = new AI_Feedback__c();
        fb.Security_Audit__c = responseId;
        fb.Type__c = feedback;
        fb.Category__c = feedbackCategory;
        fb.Comments__c = feebackDetail;
        fb.User__c = UserInfo.getUserId();
        fb = (AI_Feedback__c)FLSCheck.getInstance().insertDML(new List<AI_Feedback__c>{fb}).get(0);
        
        AI_Response__c resp = [SELECT Id, AI_Prompt__c, Record_Id__c FROM AI_Response__c WHERE Id =:responseId LIMIT 1];
        
        User u = [SELECT Id, ProfileId, Profile.Name, UserRoleId, UserRole.Name, Department 
                 FROM User WHERE Id =:UserInfo.getUserId()];
        
        String objApiName = NAMESPACE+'AI_Usage_Tracking__c';
        List<RecordType> lstOfTypes = [SELECT Id, DeveloperName FROM RecordType WHERE SObjectType =:objApiName];
        
        String promptId = resp.AI_Prompt__c;
        String objName = Id.valueOf(resp.Record_Id__c).getSobjectType().getDescribe().getName();
        String profileName;
        String userRoleName;
        String department = u.Department;
        String userId = u.Id;
        if(u.UserRoleId != null){
            userRoleName = u.UserRole.Name;
        }if(u.ProfileId != null){
            profileName = u.Profile.Name;
        }
        
        List<String> filterQueries = new List<String>();
        String query = 'SELECT Id FROM '+NAMESPACE+'AI_Usage_Tracking__c WHERE ';
        if(String.isNotBlank(profileName)){
            filterQueries.add(' '+NAMESPACE+'Profile__c =:profileName ');
        }if(String.isNotBlank(userRoleName)){
            filterQueries.add(' '+NAMESPACE+'User_Role__c =:userRoleName ');
        }if(String.isNotBlank(promptId)){
            filterQueries.add(' '+NAMESPACE+'AI_Prompt__c =:promptId ');
        }if(String.isNotBlank(objName)){
            filterQueries.add(' '+NAMESPACE+'Object_Name__c =:objName ');
        }if(String.isNotBlank(department)){
            filterQueries.add(' '+NAMESPACE+'Department__c =:department ');
        }if(String.isNotBlank(userId)){
            filterQueries.add(' '+NAMESPACE+'User__c =:userId ');
        }
        
		List<AI_Related_Feedback__c> lstOfRelatedFeedbacks = new List<AI_Related_Feedback__c>();
        if(filterQueries != null && !filterQueries.isEmpty()){
			query += ' ('+String.join(filterQueries, ' OR ')+') ';
            List<AI_Usage_Tracking__c> usageTrackings = Database.query(query);
			
            for(AI_Usage_Tracking__c ut : usageTrackings){
                AI_Related_Feedback__c rf = new AI_Related_Feedback__c();
                rf.AI_Feedback__c = fb.Id;
                rf.AI_Usage_Tracking__c = ut.Id;
                lstOfRelatedFeedbacks.add(rf);
            }
        }
        if(!lstOfRelatedFeedbacks.isEmpty()){
            FLSCheck.getInstance().insertDML(lstOfRelatedFeedbacks);
        }
    }
    
    @AuraEnabled
    public static SObject getDefaultFields(String actionId, String responseId){
    	AI_Prompt_Action__c action = [SELECT Id,Field_API_Name__c, Object_Name__c, Action__c, AI_Prompt__c, AI_Prompt__r.Id, AI_Prompt__r.Object__c,
                                      (SELECT Id, Field_API_Name__c, Type__c, Value__c FROM Prompt_Action_Details__r)
                                      FROM AI_Prompt_Action__c
                                      WHERE Id =:actionId];
        AI_Response__c response = ChatGPTUtills.getQueriedAIResponse(responseId);
        
        Map<String, AIPromptActionService.QueriedFieldWrapper> mapOfQueriedFieldToValue = AIPromptActionService.getQueriedFieldValues(new List<AI_Prompt_Action__c>{action}, action.AI_Prompt__r, response.Record_Id__c);
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get(action.Object_Name__c);
        SObject obj = targetType.newSObject();
        obj = AIPromptActionService.getMappedSObjectForCreateRecord(obj, action, mapOfQueriedFieldToValue, response);
        return obj;
    }
    
    @AuraEnabled
    public static String getDefaultFieldsString(String actionId, String responseId){
        SObject obj = getDefaultFields(actionId, responseId);
        return JSON.serialize(obj);
    }
    
    /*
    * This method is used for get record id of latest security audit with provided prompt id
    * param : promptId - prompt record id
    * return : List<AI_Response__c> is a list of Security Audit Record.
    */
    @AuraEnabled
    public static List<AI_Response__c> getLatestRecordOfSecurityAudit(String promptId){
        String userId = UserInfo.getUserId();
        List<AI_Response__c> aiResponseList = [SELECT Id,Record_Id__c FROM AI_Response__c 
                                                 WHERE CreatedById =:userId
                                                 AND AI_Prompt__c =:promptId 
                                                 ORDER BY CreatedDate DESC 
                                                 LIMIT 1];
        return aiResponseList;
    }

    
    public class OptionWrapper implements Comparable{
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public Boolean includeFiles{get;set;}
        @AuraEnabled public String howItWorks{get;set;}
        @AuraEnabled public Boolean allowUserInput{get;set;}
        @AuraEnabled public String visibilityCondition {get;set;}
        @AuraEnabled public String promptDescription {get;set;}
        @AuraEnabled public List<String> recordTypes {get;set;}
        @AuraEnabled public String visibilityExceptionMessage{get;set;}
        @AuraEnabled public List<ActionWrapper> actions{get;set;}
        @AuraEnabled public String type{get;set;}
        @AuraEnabled public String connectionModel{get;set;}
        
        public Integer compareTo(Object objToCompare) {
        	return label.compareTo(((OptionWrapper)objToCompare).label);
        }
    }
    
    public class ActionWrapper{
        @AuraEnabled public String actionId{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String objectLabel{get;set;}
        @AuraEnabled public String description{get;set;}
    }
    
    public class RecordWrapper{
        @AuraEnabled public String recId{get;set;}
        @AuraEnabled public String name{get;set;}
        @AuraEnabled public List<FileWrapper> files{get;set;}
    }
    
    public class FileWrapper{
        @AuraEnabled public String recId{get;set;}
        @AuraEnabled public String docId{get;set;}
        @AuraEnabled public String title{get;set;}
        @AuraEnabled public String fileType{get;set;}
        @AuraEnabled public String fileSize{get;set;}
    }

    public class ChatMessageWrapper{
        @AuraEnabled public String role{get;set;}
        @AuraEnabled public String content{get;set;}
        @AuraEnabled public String question{get;set;}
        @AuraEnabled public String answer{get;set;}
        @AuraEnabled public Integer sequence{get;set;}
    }
    
}