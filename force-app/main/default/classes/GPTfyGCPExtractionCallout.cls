public without sharing class GPTfyGCPExtractionCallout {
    
    @InvocableMethod(label='GPTfy GCP Extraction Callout' callout=true)
    public static void doInitialAIResponse(List<RequestWrapper> endUserInput) {
        
        String MessagingSessionId;
        List<String> responseIds; 
        if(!endUserInput.isEmpty()){
            RequestWrapper wrapper = endUserInput[0];
            responseIds = String.isNotBlank(wrapper.responseIds) ? wrapper.responseIds.split(';') : new List<String>();
            MessagingSessionId = wrapper.MessagingSessionId;
        }
        
        if(responseIds != null && !responseIds.isEmpty()){
            List<AI_Response__c> audits = V2GoogleDialogFlowInitialInvocable.getAiResponse(responseIds);
            
            // Collect all prompt IDs and original data
            Set<Id> promptIds = new Set<Id>();
            Map<Id, AI_Response__c> responseMap = new Map<Id, AI_Response__c>();
            Map<Id, Map<String, Object>> promptDataMap = new Map<Id, Map<String, Object>>();

            for (AI_Response__c audit : audits) {
                promptIds.add(audit.AI_Prompt__c);
                responseMap.put(audit.Id, audit);
                promptDataMap.put(audit.Id, (Map<String, Object>)JSON.deserializeUntyped(audit.Data_Original__c));
            }

            // Query all related Command_Snippet__c records in one go
            Map<Id, List<Command_Snippet__c>> promptToSnippetsMap = new Map<Id, List<Command_Snippet__c>>();
            for (Command_Snippet__c snippet : [SELECT Id, Prompt__c, Command_Snippet__c, Matching_Node__c, Sequence__c 
                                               FROM Command_Snippet__c 
                                               WHERE Prompt__c IN :promptIds 
                                               ORDER BY Sequence__c ASC]) {
                if (!promptToSnippetsMap.containsKey(snippet.Prompt__c)) {
                    promptToSnippetsMap.put(snippet.Prompt__c, new List<Command_Snippet__c>());
                }
                promptToSnippetsMap.get(snippet.Prompt__c).add(snippet);
            }

            Map<String, Object> data = new Map<String, Object>();
            for (AI_Response__c aiResponse : audits) {
                System.debug('aiResponse: ' + aiResponse);

                String promptCommand = buildPromptCommand(aiResponse, promptToSnippetsMap, promptDataMap.get(aiResponse.Id));
				System.debug('promptCommand@@@' + promptCommand);
                if (String.isNotBlank(promptCommand) && String.isNotBlank(aiResponse.Bot_Configuration_Detail__r.Prompt_Command_Variable_Name__c)) {
                    data.put(aiResponse.Bot_Configuration_Detail__r.Prompt_Command_Variable_Name__c, promptCommand);
                }

                Map<String, Object> promptData = promptDataMap.get(aiResponse.Id);
                if (promptData != null && !promptData.isEmpty() && String.isNotBlank(aiResponse.Bot_Configuration_Detail__r.Prompt_Data_Variable_Name__c)) {
                    data.put(aiResponse.Bot_Configuration_Detail__r.Prompt_Data_Variable_Name__c, promptData);
                }
            }

            try {
                V2GoogleDialogFlowInitialInvocable.doCalloutFirst(MessagingSessionId, data);
            } catch (Exception e) {
                System.debug('Error: ' + e.getMessage());
            }
        }
    }
    
    private static String buildPromptCommand(AI_Response__c aiResponse, Map<Id, List<Command_Snippet__c>> promptToSnippetsMap, Map<String, Object> promptData) {
        String promptCommand = '';

        List<Command_Snippet__c> snippets = promptToSnippetsMap.get(aiResponse.AI_Prompt__c);
        if (snippets != null) {
            for (Command_Snippet__c snippet : snippets) {
                if (snippet.Matching_Node__c == null || findNodeValue(JSON.serialize(promptData), snippet.Matching_Node__c) != null) {
                    promptCommand += snippet.Command_Snippet__c;
                }
            }
        }

        return promptCommand;
    }
    
    public static Object findNodeValue(String jsonString, String nodeName) {
        if (String.isBlank(jsonString) || String.isBlank(nodeName)) {
            return null;
        }
        
        try {
            // Parse the JSON string into a Map
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
            return findNodeValueRecursive(jsonMap, nodeName);
        } catch (JSONException e) {
            // Handle JSON parsing errors
            System.debug('JSON Parsing Error: ' + e.getMessage());
            return null;
        }
    }
    
    private static Object findNodeValueRecursive(Map<String, Object> jsonMap, String nodeName) {
        for (String key : jsonMap.keySet()) {
            Object value = jsonMap.get(key);
            if (key.equals(nodeName)) {
                return value;
            } else if (value instanceof Map<String, Object>) {
                // Recursively search nested maps
                Object nestedValue = findNodeValueRecursive((Map<String, Object>) value, nodeName);
                if (nestedValue != null) {
                    return nestedValue;
                }
            } else if (value instanceof List<Object>) {
                // Recursively search lists of maps
                for (Object item : (List<Object>) value) {
                    if (item instanceof Map<String, Object>) {
                        Object nestedValue = findNodeValueRecursive((Map<String, Object>) item, nodeName);
                        if (nestedValue != null) {
                            return nestedValue;
                        }
                    }
                }
            }
        }
        return null;
    }
    
    public class RequestWrapper {  
        @InvocableVariable(label='MessagingSessionId')
        public String MessagingSessionId;
        @InvocableVariable(label='responseIds')
        public String responseIds;
    }
}