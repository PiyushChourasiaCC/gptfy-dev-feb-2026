public without sharing class V2GoogleDialogFlowInitialInvocable {

    @InvocableMethod(label='GPTfy GCP Callout (Initial)' callout=true)
    public static List<ResponseWrapper> doInitialAIResponse(List<RequestWrapper> endUserInput) { 
        
        ResponseWrapper respWrap = new ResponseWrapper();

        String messagingId;
        if(!endUserInput.isEmpty()){ 
            RequestWrapper wrapper = endUserInput[0];
            messagingId = wrapper.messagingSessionId;
        }
        
        List<String> lstOfResponseIds = new List<String>();
        
        List<MessagingSession> lstOfSessions = [SELECT Id, ChannelName FROM MessagingSession WHERE Id =:messagingId];
        if(lstOfSessions != null && !lstOfSessions.isEmpty() && String.isNotBlank(lstOfSessions.get(0).ChannelName)){
            String channelName = lstOfSessions.get(0).ChannelName;
            List<Bot_Configuration__c> lstOfConfigs = [SELECT Id, Matching_Criteria__c,
                                                       (SELECT Id, Name, Prompt__c, Prompt__r.Prompt_Command__c, Messaging_Session_Field__c, Record_Id__c FROM Bot_Configuration_Details__r WHERE Prompt__c != NULL)
                                                       FROM Bot_Configuration__c 
                                                       WHERE Messaging_Channel_Name__c =:channelName];       
            if(lstOfConfigs != null && !lstOfConfigs.isEmpty()){
                for(Bot_Configuration__c bo : lstOfConfigs){
                    Set<String> fieldApis = new Set<String>();
                    if(bo.Bot_Configuration_Details__r != null && !bo.Bot_Configuration_Details__r.isEmpty()){
                        for(Bot_Configuration_Detail__c detail : bo.Bot_Configuration_Details__r){
                            if(String.isNotBlank(detail.Messaging_Session_Field__c)){
                                fieldApis.add(detail.Messaging_Session_Field__c);
                            }
                        }
                    }

                    String query = ' SELECT Id ';
                    if(fieldApis != null && !fieldApis.isEmpty()){
                        query += ', '+String.join(new List<String>(fieldApis), ', ');
                    }
                    
                    query += ' FROM MessagingSession WHERE Id =:messagingId ';
                    if(String.isNotBlank(bo.Matching_Criteria__c)){
                        query += ' AND '+bo.Matching_Criteria__c;
                    }
                    System.debug('query: ' + query);
                    List<MessagingSession> lstOfValidSessions = Database.query(query);
                    if(lstOfValidSessions != null && !lstOfValidSessions.isEmpty()){
                        MessagingSession ms = lstOfValidSessions.get(0);
                        respWrap.botConfigurationId = bo.Id;
                        if(bo.Bot_Configuration_Details__r != null && !bo.Bot_Configuration_Details__r.isEmpty()){
                            for(Bot_Configuration_Detail__c detail : bo.Bot_Configuration_Details__r){
                                String recId = detail.Record_Id__c;
                                if(String.isNotBlank(detail.Messaging_Session_Field__c) && ms.get(detail.Messaging_Session_Field__c) != null){
                                    recId = String.valueOf(ms.get(detail.Messaging_Session_Field__c));
                                }
                                if(String.isNotBlank(recId)){
                                    AI_Response__c aiResponse = AIGlobalUtility.getExtractedData(recId, detail.Prompt__c);
                                    aiResponse.Bot_Configuration_Detail__c = detail.Id;
                                    aiResponse.Status__c = 'Processed';
                                    aiResponse.AI_Prompt__c = detail.Prompt__c;
                                    aiResponse.End_Date_Time__c = System.now();
                                    aiResponse.Prompt_Command__c = detail.Prompt__r.Prompt_Command__c;
                                    aiResponse.Record_Id__c = recId;
                                    insert aiResponse;
                                    lstOfResponseIds.add(aiResponse.Id);  
                                }
                            }
                        }
                        break;
                    } 
                }
            }
        } 
        
        respWrap.responseIds = lstOfResponseIds != null ? String.join(lstOfResponseIds, ';') : '';
        respWrap.assistMore = 'Is there anything else I can help you with?';
        
        if(String.isNotBlank(respWrap.botConfigurationId)){
            MessagingSession ms = new MessagingSession();
            ms.Id = messagingId;
            ms.Bot_Configuration__c = respWrap.botConfigurationId;
            update ms;
        }
        
        return new List<ResponseWrapper>{respWrap};
    }
    
    /*
    public static String getExtractedData(ccai__AI_Prompt__c pmt, String sourceId, String botDetailId){
        ccai.AIPromptProcessingInvokable.RequestWrapper reqWrapper = new ccai.AIPromptProcessingInvokable.RequestWrapper();
        reqWrapper.recordId = sourceId;
        reqWrapper.customPromptCommand = null;
        
        ccai.AIPromptProcessingInvokable.ResponseWrapper resWrapper = new ccai.AIPromptProcessingInvokable.ResponseWrapper();
        
        resWrapper = ccai.AIPromptProcessingInvokable.invokeCallout(reqWrapper, resWrapper, pmt.Id);
        
        if(String.isNotBlank(resWrapper.responseId)){
            if(botDetailId != null){
                ccai__AI_Response__c resp = new ccai__AI_Response__c();
                resp.Bot_Configuration_Detail__c = botDetailId;
                resp.Id = resWrapper.responseId;
                update resp;
            }
            return resWrapper.responseId;
        }
        return null;
    }
	*/
    
    public static List<AI_Response__c> getAiResponse(List<String> responseIds){
        List<AI_Response__c> audits = [SELECT Id, Data_Original__c, Prompt_Command__c, 
                                             Bot_Configuration_Detail__c,
                                             Bot_Configuration_Detail__r.Bot_Configuration__c, 
                                             Bot_Configuration_Detail__r.Messaging_Session_Field__c,
                                             Bot_Configuration_Detail__r.Prompt_Data_Variable_Name__c,
                                             Bot_Configuration_Detail__r.Prompt_Command_Variable_Name__c
                                             FROM AI_Response__c 
                                             WHERE Id IN :responseIds];
        return audits;
    }
    
    //Added to initialize Google Dialogflow Session variables. Delete if required. Testing only - Saurabh
    public static String doCalloutFirst(String chatKey, Map<String, Object> data){
 
        String endpoint = getEndpoint(chatKey);
        System.debug('ep:'+endpoint);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json;charset=UTF-8');

        // Updated request body to include the event and additional parameters
        Map<String, Object> requestBodyMap = new Map<String, Object>{
            'queryInput' => new Map<String, Object>{
                'event' => new Map<String, String>{
                    'event' => 'start'
                        },
                            'languageCode' => 'en'
                            },
                                'queryParams' => new Map<String, Object>{
                                    'timeZone' => 'America/Los_Angeles',
                                        'parameters' => data
                                }
        };
            
            String requestBody = JSON.serialize(requestBodyMap);
        System.debug('requestBody: ' + requestBody);
        
        req.setBody(requestBody);
        
        Http http = new Http();
        HTTPResponse res = http.send(req); 
        System.debug('response: '+res.getBody());
        
        aiParsedResponse responseFromAI = parseResponse(res.getBody());
        System.debug('@@responseFromAI: ' + responseFromAI);
        return '';
    }
    
    
    public static aiParsedResponse doCallout(String MessagingSessionId, String data){
        
        String endpoint = getEndpoint(MessagingSessionId);
        System.debug('ep:'+endpoint);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json;charset=UTF-8');
        //data = promptCommand + ':' + data;
        System.debug('Data: ' + data);
        
        Map<String, Object> requestBodyMap = new Map<String, Object>{
            'queryInput' => new Map<String, Object>{
                'text' => new Map<String, String>{
                    'text' => data
                        },
                            'languageCode' => 'en'
                            },
                                'queryParams' => new Map<String, Object>{
                                    'timeZone' => 'America/Los_Angeles'   
                                        }
            ,'debugMode' => true
        };
            
            String requestBody = JSON.serialize(requestBodyMap);
        req.setBody(requestBody);
        
        Http http = new Http();
        HTTPResponse res = http.send(req); 
        
        aiParsedResponse responseFromAI = parseResponse(res.getBody());
        System.debug('@@Res Body: ' + res.getBody());
        //responseFromAI.responseText
        
        return responseFromAI;
    }
    
    public static aiParsedResponse parseResponse(String body){
        System.debug('Body: '  + body);
         aiParsedResponse airesponse = new aiParsedResponse();
        
        if(String.isNotBlank(body)){
            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(body);
            if(dataMap.containsKey('queryResult') && dataMap.get('queryResult') != null){
                Map<String, Object> queryResultMap = (Map<String,Object>)dataMap.get('queryResult');
                if(queryResultMap != null && queryResultMap.containsKey('responseMessages')){
                    List<object> respMessagesList = (List<object>)queryResultMap.get('responseMessages');
                    List<String> lstOfReturnText = new List<String>();
                    for(Object respMessage : respMessagesList){
                        Map<String, Object> respMessageMap = (Map<String,Object>)respMessage;
                        if(respMessageMap != null && respMessageMap.containsKey('text')){
                            Map<String, Object> textMap = (Map<String,Object>)respMessageMap.get('text');
                            if(textMap != null && textMap.containsKey('text')){
                                List<Object> textList = (List<object>)textMap.get('text');
                                if(textList != null && !textList.isEmpty()){
                                    lstOfReturnText.add(String.valueOf(textList.get(0)));
                                }
                            } 
                        }else if(respMessageMap != null && respMessageMap.containsKey('payload')){
                            
                            Map<String, Object> payloadMap = (Map<String,Object>)respMessageMap.get('payload');
                            System.debug('payloadMap: ' + payloadMap);
                            if(payloadMap != null && payloadMap.containsKey('richContent')){
                                List<object> richContentList = (List<object>)payloadMap.get('richContent');
                                if(richContentList != null && !richContentList.isEmpty()){
                                    List<Object> richContentChildList = (List<object>)richContentList.get(0);
                                    if(richContentChildList != null && !richContentChildList.isEmpty()){
                                        Map<String, Object> richContentChildMap = (Map<String,Object>)richContentChildList.get(0);
                                        if(richContentChildMap != null && richContentChildMap.containsKey('actionLink')){
                                            String link = String.valueOf(richContentChildMap.get('actionLink'));
                                            if(string.isNotBlank(link) && link.contains('#:~:')){
                                                link = link.subStringBefore('#:~:');
                                            }
                                            lstOfReturnText.add(link);
                                        }
                                    }
                                }
                            }
                            if(payloadMap != null && payloadMap.containsKey('keyword')){
                                
                                airesponse.keyword = String.valueOf(payloadMap.get('keyword'));
                                
                            }
                        }
                    }
                    airesponse.responseText = lstOfReturnText != null && !lstOfReturnText.isEmpty() ? String.join(lstOfReturnText, '\n\n') : '';
                    System.debug('AIResponse: ' + airesponse);
                    return airesponse;
                }
            }
        }
        return null;
    }
    
    public static String getEndpoint(String sessionId){
        String endpoint = '';
        List<MessagingSession> lstOfSessions = [SELECT Id, ChannelName FROM MessagingSession WHERE Id =:sessionId];
        if(lstOfSessions != null && !lstOfSessions.isEmpty()){
            String channelName = lstOfSessions.get(0).ChannelName;
            List<GPTfy_Chatbot_Mapping__mdt> mcs = GPTfy_Chatbot_Mapping__mdt.getAll().values();
            for(GPTfy_Chatbot_Mapping__mdt mp : mcs){
                if(mp.Messaging_Channel_Name__c == channelName){
                    
                    endpoint = 'callout:' + mp.Named_Credential__c + '/v3/projects/'+mp.Project_ID__c+'/locations/'+mp.Location__c+'/agents/'+mp.Agent_ID__c;
                    if(String.isNotBlank(mp.Environment_Id__c)){
                        endpoint += '/environments/'+mp.Environment_Id__c;
                    }
                    endpoint += '/sessions/'+sessionId+':detectIntent';
                    break;
                }
            }
        }
        return endpoint;
    }
    
    public class RequestWrapper {  
        @InvocableVariable(label='MessagingSessionId')
        public String messagingSessionId;
    }
    
    public class ResponseWrapper {  
        @InvocableVariable(label='responseIds')
        public String responseIds;
        @InvocableVariable(label='botConfigurationId')
        public String botConfigurationId;
        @InvocableVariable(label='Assist More')
        public String assistMore;
        
    }
    
    public class aiParsedResponse {
        public String responseText{ get; set; }
        public String keyword{ get; set; }
        
        aiParsedResponse() {
            this.keyword = '';
            this.responseText = '';
        }
    }
    
}