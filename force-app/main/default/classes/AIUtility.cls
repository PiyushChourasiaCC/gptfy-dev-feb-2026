public with sharing class AIUtility {
    
	
    @AuraEnabled
    public static Map<String, Object> getCustomSettings(){
        Map<String, Object> returnMap = new Map<String, Object>();
        GPTfy_Settings__c settings = GPTfy_Settings__c.getOrgDefaults();
        returnMap.put('typeEffect', settings.Typewriter_Effect__c != null ? settings.Typewriter_Effect__c : false); 
        returnMap.put('fileProcessing', settings.File_Processing__c != null ? settings.File_Processing__c : false);
        returnMap.put('prefixSuffix', settings.Prefix_Suffix__c != null ? settings.Prefix_Suffix__c : false);
        returnMap.put('enableExceptionLog', settings.Exception_Log__c != null ? settings.Exception_Log__c : false);
        returnMap.put('enablePromptVersion', settings.Prompt_Versioning__c != null ? settings.Prompt_Versioning__c : false);
        returnMap.put('fileType', settings.File_Type__c != null ? settings.File_Type__c : NULL);
        returnMap.put('maxFileSize', settings.Max_File_Size__c != null ? settings.Max_File_Size__c : NULL);
        returnMap.put('maxFileCount', settings.Max_File_Count__c != null ? settings.Max_File_Count__c : NULL);
        returnMap.put('reportingPeriod', settings.Reporting_Period__c != null ? settings.Reporting_Period__c : NULL);
        returnMap.put('hourlyCost', settings.Hourly_Cost__c != null ? settings.Hourly_Cost__c : NULL);
        returnMap.put('additionalInstructions', settings.Additional_Input_Separator__c != null ? settings.Additional_Input_Separator__c : null);
        // @Jira 4487 : Data Context Mapping with Data Cloud Integration
        returnMap.put('enableForDataCloud', settings.Enable_for_Data_Cloud__c != null ? settings.Enable_for_Data_Cloud__c : null);
        returnMap.put('salesforceDomainUrl', settings.Salesforce_Domain_URL__c != null ? settings.Salesforce_Domain_URL__c : null);
        returnMap.put('salesforceClientId', settings.Salesforce_Client_Id__c != null ? settings.Salesforce_Client_Id__c : null);
        returnMap.put('salesforceAdminEmail', settings.Salesforce_Admin_Email__c != null ? settings.Salesforce_Admin_Email__c : null);
        returnMap.put('salesforcePrivateKeyFileId', settings.Salesforce_Private_Key_File_Id__c != null ? settings.Salesforce_Private_Key_File_Id__c : null);
        returnMap.put('salesforceAuthNamedCredential', settings.Salesforce_Auth_Named_Credential__c != null ? settings.Salesforce_Auth_Named_Credential__c : null);
        returnMap.put('dataCloudNamedCredential', settings.Data_Cloud_Named_Credentials__c != null ? settings.Data_Cloud_Named_Credentials__c : null);
        return returnMap;
    } 
    
    @AuraEnabled
    public static void updateCustomSettings(String fieldName, Boolean value){
        GPTfy_Settings__c settings = GPTfy_Settings__c.getOrgDefaults();
        settings.put(fieldName, value);
        FLSCheck.getInstance().upsertDML(new List<GPTfy_Settings__c>{settings});
    }
    
    @AuraEnabled
    public static void updateGPTfySettings(String fieldName, Object value){
        GPTfy_Settings__c settings = GPTfy_Settings__c.getOrgDefaults();
        settings.put(fieldName,value);
        FLSCheck.getInstance().upsertDML(new List<GPTfy_Settings__c>{settings});
    }
    
    /**
     * Checks if a given model name is in the RESPONSES_API_MODEL set.
     * This method is AuraEnabled to allow calls from Lightning Web Components.
     * 
     * @param modelName The name of the model to check
     * @return Boolean True if the model is in RESPONSES_API_MODEL set, false otherwise
     */
    @AuraEnabled(cacheable=true)
    public static Boolean checkIfResponsesApiModel(String modelName){
        if(String.isBlank(modelName)){
            return false;
        }
        return AIConstants.RESPONSES_API_MODEL.contains(modelName);
    }
    
    /*
     * This method is use for handle where clause condition.
     * @params: 
     * whereClause : use for user input whereclause on record.
     * defaultOrderBy : set default order by field on whereClause.
     * defaultLimit : set default limit on whereClause.
     * isValidating : use for where clause validating with limit 0.
     * @return : The correct where clause condition.
     */
    public static String getFormattedWhereClause(String whereClause, String defaultOrderBy, Integer defaultLimit, Boolean isValidating){
        String formattedWhereClause = ' WHERE Id != NULL ';
        if(String.isBlank(whereClause)){
            formattedWhereClause = '';
        }
        
        if(String.isNotBlank(whereClause)){
            whereClause = whereClause.trim();
            if(whereClause.startsWithIgnoreCase('ORDER BY ') || whereClause.startsWithIgnoreCase('LIMIT ')){
            	formattedWhereClause += whereClause;
            }else{
                formattedWhereClause += ' AND '+whereClause;
            }
        }

        if(formattedWhereClause.indexOf('ORDER BY') != -1){
            //do-nothing
        }else{
            if(String.isNotBlank(defaultOrderBy)){
                if(formattedWhereClause.indexOfIgnoreCase('LIMIT ') != -1){
                    Integer index = formattedWhereClause.indexOfIgnoreCase('LIMIT ');
                    if(index > -1){
                        String temp1 = formattedWhereClause.substring(0, index);
                        String temp2 = formattedWhereClause.substring(index);
                        formattedWhereClause = temp1+defaultOrderBy+temp2;
                    }
                }else{
                    formattedWhereClause += defaultOrderBy;
                }
            }
        }
        
        if(formattedWhereClause.indexOfIgnoreCase('LIMIT ') != -1){
            //do-nothing
        }else{
            if(defaultLimit != null){
            	formattedWhereClause += ' LIMIT '+defaultLimit;
            }
        }
        
        if(isValidating){
            if(formattedWhereClause.indexOfIgnoreCase('LIMIT ') != -1){
                Integer index = formattedWhereClause.lastIndexOfIgnoreCase('LIMIT ');
                if(index > -1){
                    formattedWhereClause = formattedWhereClause.substring(0, index);
                }
            }
            formattedWhereClause += ' LIMIT 0 ';
        }  
        if(!String.isBlank(formattedWhereClause)){
            formattedWhereClause = formattedWhereClause.replace('\\\'', '\'');                                                         
            Pattern regex = Pattern.compile('\\b\\w*\'\\w*\\b'); 
            Matcher matcher = regex.matcher(formattedWhereClause);
            while (matcher.find()) {
                formattedWhereClause = formattedWhereClause.replace(matcher.group(0), matcher.group(0).replace('\'', '\\\''));
            }
        }
        return formattedWhereClause;
    }
    
    /**
     * 
     * This method is create a AuraHandledException with message
     * Jira v2/7550 : Issues/Feedbacks Reported in 1.13
     * @param message The message of the Exception
     * @return AuraHandledException instance.
     */
    public static AuraHandledException getMessageAuraHandledException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
    
}