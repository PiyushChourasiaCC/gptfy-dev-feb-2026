/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 10-30-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIUsageTrackingController {
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    
    public static AI_Response__c getTokensFromResponse(AI_Response__c resp){
        
        resp.Completion_Tokens__c = 0;
        resp.Prompt_Tokens__c = 0;
        resp.Total_Tokens__c = 0;
        
        if(String.isNotBlank(resp.AI_Processed_Data_No_PII__c)){
            Map<String, Object> gptMap = (Map<String, Object>)JSON.deserializeUntyped(resp.AI_Processed_Data_No_PII__c);
            Map<String, Object> usageMap;
            Integer completionTokens = 0;
            Integer promptTokens = 0;
            Integer totalTokens = 0;
            
            if(gptMap != null && gptMap.containsKey('usage') && gptMap.get('usage') != null){
                usageMap = (Map<String, Object>)gptMap.get('usage'); 
                completionTokens = usageMap.containsKey('completion_tokens') ? Integer.valueOf(usageMap.get('completion_tokens')) : 
                                    usageMap.containsKey('output_tokens') ? Integer.valueOf(usageMap.get('output_tokens')) : null;
                promptTokens = usageMap.containsKey('prompt_tokens') ? Integer.valueOf(usageMap.get('prompt_tokens')) : 
                                    usageMap.containsKey('input_tokens') ? Integer.valueOf(usageMap.get('input_tokens')) : null;
                totalTokens = Integer.valueOf(usageMap.get('total_tokens'));
            }else if(gptMap != null && gptMap.containsKey('data')){
                try{
                    Map<String, Object> dataMap = (Map<String, Object>)gptMap.get('data');
                    if(dataMap != null && dataMap.containsKey('value')){
                        Map<String, Object> valueMap = (Map<String, Object>)dataMap.get('value');
                        if(valueMap != null && valueMap.containsKey('usage')){
                            usageMap = (Map<String, Object>)valueMap.get('usage');
                            completionTokens = Integer.valueOf(usageMap.get('completionTokens'));
                            promptTokens = Integer.valueOf(usageMap.get('promptTokens'));
                            totalTokens = Integer.valueOf(usageMap.get('totalTokens'));
                        }
                    }
                }catch(Exception e){
                    //do-nothing
                }
            }else if(gptMap != null && gptMap.containsKey('metadata')){
                Map<String, Object> dataMap = (Map<String, Object>)gptMap.get('metadata');
                if(dataMap != null && dataMap.containsKey('tokenMetadata')){
                    Map<String, Object> valueMap = (Map<String, Object>)dataMap.get('tokenMetadata');
                    if(valueMap != null && valueMap.containsKey('inputTokenCount')){
                        usageMap = (Map<String, Object>)valueMap.get('inputTokenCount');
                        completionTokens = Integer.valueOf(usageMap.get('totalTokens'));
                        promptTokens = Integer.valueOf(usageMap.get('promptTokens'));
                        totalTokens = Integer.valueOf(usageMap.get('totalTokens'));
                    }if(valueMap != null && valueMap.containsKey('outputTokenCount')){
                        usageMap = (Map<String, Object>)valueMap.get('outputTokenCount');
                        promptTokens = Integer.valueOf(usageMap.get('totalTokens'));
                    }
                    totalTokens = promptTokens + completionTokens;
                }
            }
            
            if(usageMap != null && !usageMap.isEmpty()){
                resp.Completion_Tokens__c = completionTokens;
                resp.Prompt_Tokens__c = promptTokens;
                resp.Total_Tokens__c = totalTokens;
            }
        }
        
        return resp;
    }
	
    public static List<AI_Usage_Tracking__c> getUsageTrackings(AI_Response__c resp){
        User u = [SELECT Id, ProfileId, Profile.Name, UserRoleId, UserRole.Name, Department 
                 FROM User WHERE Id =:UserInfo.getUserId()];
        
        String objApiName = NAMESPACE+'AI_Usage_Tracking__c';
        List<RecordType> lstOfTypes = [SELECT Id, DeveloperName FROM RecordType WHERE SObjectType =:objApiName];
        
        String promptId = resp.AI_Prompt__c;
        String objName = resp.Record_Id__c != null ? Id.valueOf(resp.Record_Id__c).getSobjectType().getDescribe().getName() : '';
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
        String query = 'SELECT Id, '+NAMESPACE+'Lifetime_Calls__c, '+NAMESPACE+'Lifetime_Saving_Seconds__c, RecordTypeId FROM '+NAMESPACE+'AI_Usage_Tracking__c WHERE ';
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
       
        Map<String, AI_Usage_Tracking__c> mapOfRecordTypeUsageTracking = new Map<String, AI_Usage_Tracking__c>();
        if(filterQueries != null && !filterQueries.isEmpty()){
			query += ' ('+String.join(filterQueries, ' OR ')+') ';
            List<AI_Usage_Tracking__c> usageTrackings = Database.query(query);

            for(AI_Usage_Tracking__c ut : usageTrackings){
                if(ut.RecordTypeId != null && !mapOfRecordTypeUsageTracking.containsKey(ut.RecordTypeId)){
                    mapOfRecordTypeUsageTracking.put(ut.RecordTypeId, ut);
                }
            }
        }
        
        List<AI_Usage_Tracking__c> lstOfTrackings = new List<AI_Usage_Tracking__c>();
        
        for(RecordType rt : lstOfTypes){
            String rtName = rt.DeveloperName;
            AI_Usage_Tracking__c ut = new AI_Usage_Tracking__c();
            
            if(mapOfRecordTypeUsageTracking != null && mapOfRecordTypeUsageTracking.containsKey(rt.Id)){
                ut = mapOfRecordTypeUsageTracking.get(rt.Id);
                ut.Lifetime_Calls__c = ut.Lifetime_Calls__c == null ? 1 : ut.Lifetime_Calls__c + 1;
            	ut.Lifetime_Saving_Seconds__c = ut.Lifetime_Saving_Seconds__c == null ? 0 : ut.Lifetime_Saving_Seconds__c;
                lstOfTrackings.add(ut);
                 
            }else{
                ut.recordTypeId = rt.Id;
                ut.Lifetime_Calls__c = 1;
                ut.Lifetime_Saving_Seconds__c = 0;
                
                if(rtName.equalsIgnoreCase(AIConstants.UT_RECTYPE_USER)){
                    ut.User__c = userId; 
                    lstOfTrackings.add(ut);
                }else if(rtName.equalsIgnoreCase(AIConstants.UT_RECTYPE_PROFILE)){
                    ut.Profile__c = profileName;
                    lstOfTrackings.add(ut);
                }else if(rtName.equalsIgnoreCase(AIConstants.UT_RECTYPE_PROMPT)){
                    ut.AI_Prompt__c = promptId;
                    lstOfTrackings.add(ut);
                }else if(rtName.equalsIgnoreCase(AIConstants.UT_RECTYPE_OBJECT)){
                    ut.Object_Name__c = objName;
                    lstOfTrackings.add(ut);
                }else if(rtName.equalsIgnoreCase(AIConstants.UT_RECTYPE_USER_ROLE) && String.isNotBlank(department)){
                    ut.Department__c = department;
                    lstOfTrackings.add(ut);
                }else if(rtName.equalsIgnoreCase(AIConstants.UT_RECTYPE_DEPT) && String.isNotBlank(userRoleName)){
                    ut.User_Role__c = userRoleName;
                    lstOfTrackings.add(ut);
                }
            }
            
        }
        return lstOfTrackings;
    }
    
    public static void upsertUsageTrackingDetails(List<AI_Usage_Tracking__c> usageTrackingList,Decimal timeSavedSeconds){
        Date todayDate = Date.today();
        GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
        Integer reportingPeriod = gptfySetting.Reporting_Period__c != null ? Integer.valueOf(gptfySetting.Reporting_Period__c) : 1;
		List<AI_Usage_Tracking_Detail__c> usageTrackingDetailList = [SELECT Id, AI_Calls_Count__c, AI_Start_Date__c, AI_End_Date__c,AI_Time_Saved__c, Usage_Tracking__c 
                                                                     FROM AI_Usage_Tracking_Detail__c 
                                                                 	 WHERE Usage_Tracking__c IN :usageTrackingList 
                                                                     AND AI_Start_Date__c <= :todayDate 
                                                                     AND AI_End_Date__c >= :todayDate ORDER BY CreatedDate DESC];
        
        Map<String,AI_Usage_Tracking_Detail__c> mapUTidUsageTrackingDetails = new Map<String,AI_Usage_Tracking_Detail__c>();
        for(AI_Usage_Tracking_Detail__c utd : usageTrackingDetailList){
             if(!mapUTidUsageTrackingDetails.containsKey(utd.Usage_Tracking__c)){
                    mapUTidUsageTrackingDetails.put(utd.Usage_Tracking__c,utd);
             }
            
        }
        List<AI_Usage_Tracking_Detail__c> lstOfTrackingsDetails = new List<AI_Usage_Tracking_Detail__c>();
        for(AI_Usage_Tracking__c ut : usageTrackingList){
              	AI_Usage_Tracking_Detail__c utd = new AI_Usage_Tracking_Detail__c();
             	if(mapUTidUsageTrackingDetails != null && mapUTidUsageTrackingDetails.containsKey(ut.Id)){
                    utd = mapUTidUsageTrackingDetails.get(ut.Id);
                    utd.AI_Calls_Count__c = utd.AI_Calls_Count__c != null? utd.AI_Calls_Count__c + 1 : 1;
                     if(timeSavedSeconds != null){
                         utd.AI_Time_Saved__c = utd.AI_Time_Saved__c != null? utd.AI_Time_Saved__c + timeSavedSeconds: timeSavedSeconds;
                     }
                }else{
                    Date firstDayOfMonth = Date.today().toStartOfMonth();
                    Date lastDayOfMonth = firstDayOfMonth;
                    if(reportingPeriod > 1){
                        lastDayOfMonth = firstDayOfMonth.addMonths(reportingPeriod-1);
                    }
                    lastDayOfMonth  =  lastDayOfMonth.addDays(Date.daysInMonth(lastDayOfMonth.year(), lastDayOfMonth.month()) - 1);
                    utd.AI_Start_Date__c = firstDayOfMonth;
                    utd.AI_End_Date__c = lastDayOfMonth;
                    utd.AI_Calls_Count__c = 1;
                    if(timeSavedSeconds != null){
                         utd.AI_Time_Saved__c = timeSavedSeconds != null? timeSavedSeconds: 0;
                    }
                    utd.Usage_Tracking__c =  ut.Id;
                }
                lstOfTrackingsDetails.add(utd); 
        }
        if(lstOfTrackingsDetails != null && !lstOfTrackingsDetails.isEmpty()){
            FLSCheck.getInstance().upsertDML(lstOfTrackingsDetails);
        }
    }
    
}