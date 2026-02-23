public without sharing class GPTfyGCPCallout {
    
    @InvocableMethod(label='GPTfy GCP Callout' callout=true)
    public static List<ResponseWrapper> doAIResponse(List<RequestWrapper> endUserInput) {
        
        String MessagingSessionId;
        String question;
        String botConfigurationId;
        if(!endUserInput.isEmpty()){ 
            RequestWrapper wrapper = endUserInput[0];
            MessagingSessionId = wrapper.MessagingSessionId;
            question = wrapper.question;
            botConfigurationId = wrapper.botConfigurationId;
        }
        
        String keyword;
        String response;
        try{
            GPTfyGCPExtraction.aiParsedResponse combinedResponse = GPTfyGCPExtraction.doCallout(messagingSessionId, question);
            if(combinedResponse != null){
                keyword = combinedResponse.keyword;
                response = combinedResponse.responseText;
                if (response != null && response.startsWith('"') && response.endsWith('"')) {
                    // Remove the double quotes from the start and end of the string
                    response = response.substring(1, response.length() - 1);
                }
            }
            // Fetch Timeout and Timeout message from bot configuration
            Bot_Configuration__c configuration = [SELECT Id, Timeout__c, Timeout_Message__c FROM Bot_Configuration__c WHERE Id = :botConfigurationId LIMIT 1];
            
            if(configuration.Timeout__c != null && configuration.Timeout_Message__c != null) {
                // Fetch Created date from Messaging Session
                MessagingSession msg = [SELECT Id, CreatedDate FROM MessagingSession WHERE Id = :MessagingSessionId LIMIT 1];
                
                // Calculate the difference in minutes between the current time and the CreatedDate of the messaging session
                Decimal timeDifferenceInMinutes = (Datetime.now().getTime() - msg.CreatedDate.getTime()) / (1000 * 60);
                System.debug('timeDifferenceInMinutes: ' + timeDifferenceInMinutes);
                if ((timeDifferenceInMinutes > configuration.Timeout__c)) {
                    response = configuration.Timeout_Message__c;
                }
                
            }
            
        }catch(Exception e){
            System.debug('Error: '+e.getMessage());
        } 
        
        
        
        ResponseWrapper respWrap = new ResponseWrapper();
        respWrap.transferToAgent = false;
        
        List<Bot_Configuration__c> lstOfConfigs = [SELECT Id, Flag_Field__c, 
                                                   (SELECT Id, Name, Canned_Response__c, Flag_Keyword__c, Invoke_Agent__c, Default_Action__c
                                                    FROM Bot_Actions__r ORDER BY Invoke_Agent__c DESC) 
                                                   FROM Bot_Configuration__c 
                                                   WHERE Id =:botConfigurationId];  
        
        Bot_Configuration__c config = lstOfConfigs.get(0);
        Bot_Action__c defaultAction;
        
        if(!lstOfConfigs.isEmpty() && config.Bot_Actions__r != null && config.Bot_Actions__r.size() > 0){
            //config = lstOfConfigs.get(0);
            //if(config.Bot_Actions__r.size() > 0) {
            for(Bot_Action__c ba : config.Bot_Actions__r){
                if(ba.Default_Action__c){
                    defaultAction = ba;
                    break;
                }
            }  
            //}
            
            
            if(String.isNotBlank(response)){
                response = response.trim();
            }
            
            String flagKeyword;
            for(Bot_Action__c ba : config.Bot_Actions__r){
                if(String.isNotBlank(keyword) && keyword.containsIgnoreCase(ba.Name)){
                    if(ba.Invoke_Agent__c){
                        respWrap.transferToAgent = true;
                    }if(ba.Flag_Keyword__c){
                        flagKeyword = keyword;
                    }if(String.isNotBlank(ba.Canned_Response__c)){
                        response = ba.Canned_Response__c;
                    }
                    break;
                }
            }
            
            if(String.isNotBlank(flagKeyword) && config.Flag_Field__c != null){
                String query = 'SELECT Id, '+config.Flag_Field__c+' FROM MessagingSession WHERE Id =:MessagingSessionId';
                List<MessagingSession> lstOfMs = Database.query(query);
                if(lstOfMs != null && !lstOfMs.isEmpty()){
                    MessagingSession ms = lstOfMs.get(0);
                    Set<String> setOfKeys = new Set<String>();
                    if(String.isNotBlank(ms.Flag_Keywords__c)){
                        setOfKeys.addAll(ms.Flag_Keywords__c.split(';'));
                    }
                    if(ms.get(config.Flag_Field__c) != null){
                        setOfKeys.addAll(String.valueOf(ms.get(config.Flag_Field__c)).split(';'));
                    }
                    if(flagKeyword.contains(';')){
                        for(String flag : flagKeyword.split(';')){
                            if(String.isNotBlank(flag) && flag.contains('#')){
                                String fKey = flag.substringBetween('#', '#');
                                if(String.isNotBlank(fKey)){
                                    setOfKeys.add(fKey);
                                }
                            }
                        }
                    }else{
                        setOfKeys.add(flagKeyword);
                    }
                    ms.put(config.Flag_Field__c,  String.join(new List<String>(setOfKeys), ';'));
                    update ms;
                }
            }
        }  
        
        respWrap.answer = response;
        if(defaultAction != null && String.isBlank(respWrap.answer)){
            respWrap.transferToAgent = defaultAction.Invoke_Agent__c;    
            respWrap.answer = defaultAction.Canned_Response__c; 
        } 
        System.debug('response: '+response);
        return new List<ResponseWrapper>{respWrap};
            }
    
    
    public class RequestWrapper{
        @InvocableVariable(label='MessagingSessionId')
        public String MessagingSessionId;
        @InvocableVariable(label='question')
        public String question;
        @InvocableVariable(label='botConfigurationId')
        public String botConfigurationId;
    }
    
    public class ResponseWrapper {  
        @InvocableVariable(label='answer')
        public String answer;
        @InvocableVariable(label='transferToAgent')
        public Boolean transferToAgent;
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