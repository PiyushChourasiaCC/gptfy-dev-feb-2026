public with sharing class AIRealTimeVoiceController {
	/*
    @AuraEnabled
    public static InitWrapper getInitDetails(){
        InitWrapper i_wrap = new InitWrapper();
        List<AI_Voice_Configuration__c> configs = [SELECT Id, AI_Model_Agentic__c
                                                   FROM AI_Voice_Configuration__c
                                                   LIMIT 1];
        if(configs != null && !configs.isEmpty() && configs.get(0).AI_Model_Agentic__c != null){
            //i_wrap.endpoint = configs.get(0).AI_Model_Agentic__c;
            
            Set<String> promptNames = new Set<String>();
            Set<String> objectTypes = new Set<String>();
            List<PromptWrapper> lstOfPrompts = new List<PromptWrapper>();
            String profileName = [SELECT Id, Name 
                                  FROM Profile 
                                  WHERE Id =:UserInfo.getProfileId() 
                                  LIMIT 1].Name;
            
            for(AI_Prompt__c pmt : [SELECT Id, Name, Object__c, Profiles__c, Description__c, How_It_Works__c, 
                                    Grounding_Ethical__c, Grounding_Content__c, Prompt_Command__c
                                    FROM AI_Prompt__c 
                                    WHERE Status__c =:AIConstants.PMT_STATUS_ACTIVE
                                    AND Available_for_Agentic__c = True]){
                if((String.isBlank(pmt.Profiles__c) || pmt.Profiles__c.containsIgnoreCase(profileName))){
                    promptNames.add(pmt.Name);
                	objectTypes.add(pmt.Object__c);
                    
                    PromptWrapper p_wrap = new PromptWrapper();
                    p_wrap.promptId = pmt.Id;
                    p_wrap.promptName = pmt.Name;
                    p_wrap.objectType = pmt.Object__c;
                    p_wrap.description = pmt.Description__c;
                    p_wrap.howItWorks = pmt.How_It_Works__c;
                    p_wrap.groundingEthical = pmt.Grounding_Ethical__c;
                    p_wrap.groundingContent = pmt.Grounding_Content__c;
                    p_wrap.promptCommand = pmt.Prompt_Command__c;
                    lstOfPrompts.add(p_wrap);
                }
            }
            
            if(!promptNames.isEmpty()){
                i_wrap.promptNames = new List<String>(promptNames);
                i_wrap.objectTypes = new List<String>(objectTypes);
                i_wrap.prompts = lstOfPrompts;
            }
        }
        return i_wrap;
    }
    
    public class InitWrapper{
        @AuraEnabled public String endpoint{get;set;}
        @AuraEnabled public List<String> promptNames{get;set;}
        @AuraEnabled public List<String> objectTypes{get;set;}
        @AuraEnabled public List<PromptWrapper> prompts{get;set;}
    }
    
    public class PromptWrapper{
        @AuraEnabled public String promptId{get;set;}
        @AuraEnabled public String promptName{get;set;}
        @AuraEnabled public String objectType{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String howItWorks{get;set;}
        @AuraEnabled public String groundingEthical{get;set;}
        @AuraEnabled public String groundingContent{get;set;}
        @AuraEnabled public String promptCommand{get;set;}
    }
    
    
    @AuraEnabled
    public static List<Object> findRecordsUsingSearchKey(String promptName, String searchKey){
        List<Object> data = new List<Object>();
        promptName = '%'+promptName+'%';
        searchKey = '%'+searchKey+'%';
        List<AI_Prompt__c> lstOfPrompts = [SELECT Id, Name, Object__c, Prompt_Request_Id__c, 
                                           Record_Finder_Filter__c, Record_Finder_Fields__c
                                           FROM AI_Prompt__c
                                           WHERE Name LIKE :promptName 
                                           AND Status__c =:AIConstants.PMT_STATUS_ACTIVE
                                           LIMIT 1];
        
        if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
            AI_Prompt__c pmt = lstOfPrompts.get(0);
            String objName = pmt.Object__c;
            if(String.isNotBlank(pmt.Record_Finder_Filter__c)){
                String query = ' SELECT Id ';
                if(String.isNotBlank(pmt.Record_Finder_Fields__c)){
                    query += ', '+String.escapeSingleQuotes(pmt.Record_Finder_Fields__c);
                }
                query += ' FROM '+String.escapeSingleQuotes(objName);
                query += ' WHERE '+pmt.Record_Finder_Filter__c;
                
                Map<String, Object> bindMap = new Map<String, Object>{'searchKey' => searchKey};
				List<sObject> records =  Database.queryWithBinds(query, bindMap, AccessLevel.USER_MODE);
                
                if(records != null && !records.isEmpty()){
                    Map<String, Schema.SObjectField> initialFieldMap = AIDataExtractionService.schemaMap.get(objName).getDescribe().fields.getMap();
                    Map<String, Schema.SObjectField> fieldMap = new Map<String, Schema.SObjectField>();
                    for(String fName : initialFieldMap.keySet()){
                        fieldMap.put(fName.toLowerCase(), initialFieldMap.get(fName));
                    }
                    
                    for(sObject so : records){
                       	Map<String, Object> sObjMap = new Map<String, Object>();
                        sObjMap.put('Id', so.get('Id'));
                        if(String.isNotBlank(pmt.Record_Finder_Fields__c)){
                            List<String> finderFields = pmt.Record_Finder_Fields__c.split(',');
                            for(String fName : finderFields){
                                String fieldName = fName.toLowerCase().trim();
                                if(fieldMap != null && fieldMap.containsKey(fieldName)){
                                   	DescribeFieldResult fDesc = fieldMap.get(fieldName).getDescribe();
                                    String fieldLabel = fDesc.getLabel();
                                    sObjMap.put(fieldLabel, so.get(fName.trim()));
                                }
                            }
                        }
                        data.add(sObjMap);
                    }
                }
            }
        }
        
        return data;
    } 
    
    @AuraEnabled
    public static String getExtractedData(String promptName, String recordId){
        String promptSearchKey = '%'+promptName+'%';
        List<AI_Prompt__c> lstOfPrompts = [SELECT Id, Name, Object__c, Prompt_Request_Id__c, 
                                           Record_Finder_Filter__c, Record_Finder_Fields__c
                                           FROM AI_Prompt__c
                                           WHERE Name LIKE :promptSearchKey 
                                           AND Status__c =:AIConstants.PMT_STATUS_ACTIVE
                                           LIMIT 1];
        
        if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
            AI_Prompt__c pmt = lstOfPrompts.get(0);
            AI_Response__c resp = AIGlobalUtility.getExtractedData(recordId, pmt.Id);
            return resp.AI_Processed_Data_PII_Added__c;
        }
        return null;
    }
    
    @AuraEnabled
    public static String sendMessageToAzureChatBot(List<Map<String, String>> messages) {
        List<AI_Voice_Configuration__c> configs = [SELECT Id, AI_Model_Agentic__c
                                                   FROM AI_Voice_Configuration__c
                                                   LIMIT 1];
        if(configs != null && !configs.isEmpty() && configs.get(0).AI_Model_Agentic__c != null){
            List<AI_Connection__c> agenticModel = [SELECT Id,EndPoint_URL__c, Named_Credential__c,Temperature__c,Max_Total_Tokens__c 
                                                   FROM AI_Connection__c 
                                                   WHERE Id=:configs.get(0).AI_Model_Agentic__c 
                                                   LIMIT 1];
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:'+agenticModel[0].Named_Credential__c+agenticModel[0].EndPoint_URL__c);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
           // req.setHeader('api-key', '9FzRxq2nMHNzlduqmGEozrwJ5o9Ittb57A0SGOPTzwVvS7Otjb6NJQQJ99ALACHYHv6XJ3w3AAAAACOGIjot');
            
            Map<String, Object> body = new Map<String, Object>{
                'messages' => messages,
                //'max_tokens' => 150,
                'temperature' => agenticModel[0].Temperature__c,
                    'max_completion_tokens' => agenticModel[0].Max_Total_Tokens__c
            };
            
            req.setBody(JSON.serialize(body));
            
            // Return streaming response
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                // Handle streaming response
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> choices = (List<Object>) responseMap.get('choices');
                Map<String, Object> choiceObj = (Map<String, Object>) choices[0];
                Map<String, Object> message = (Map<String, Object>) choiceObj.get('message');
                return (String) message.get('content');
            } else {
                return 'Error from OpenAI: ' + res.getBody();
            }
        }else {
                return 'AI Model Agentic not define in Voice Configuration.';
        }
        
        
    }*/
    
    /*
    @AuraEnabled
    public static List<SObject> getObjectByName(String objectName, String name) {
        System.debug('Object Name: ' + objectName +', Name: ' + name);
        name = '%'+name+'%';
        // Construct the dynamic query string
        String query = 'SELECT Id, Name FROM ' + objectName + ' WHERE Name LIKE :name LIMIT 1';
    
        try {
            // Execute the dynamic query
            return Database.query(query);
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to fetch records. Please check your inputs.');
        }
    }

    
    @AuraEnabled
    public static List<AI_Prompt__c> getPromptByName(String promptName) {
        System.debug('prompt name: '+promptName);
        String nm = '%' + promptName + '%';
        return [
            SELECT Id, Name, Prompt_Request_Id__c
            FROM AI_Prompt__c
            WHERE Name LIKE :nm LIMIT 1
        ];
    }
    */
    
}