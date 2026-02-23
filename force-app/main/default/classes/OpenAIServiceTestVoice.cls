public class OpenAIServiceTestVoice {
    private static final String OPENAI_ENDPOINT = 'https://api.openai.com/v1/chat/completions';
    private static final String OPENAI_REALTIME_NAMED_CREDENTIAL = 'callout:OpenAI';
    private static final String AZURE_OPENAI_REALTIME_NAMED_CREDENTIAL = 'callout:AzureRealtime';
    
    private static final String AZURE_ENDPOINT = 'saura-m51w47qu-eastus2.cognitiveservices.azure.com';
    private static final String API_VERSION = '2024-10-01-preview';
    private static final String DEPLOYMENT_NAME = 'gpt-4o-realtime-preview';
    
    /**
     * Creates an ephemeral client secret token for Azure OpenAI Realtime API
     * POST https://{resource}.openai.azure.com/openai/v1/realtime/client_secrets
     * Reference: https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/realtime-audio-webrtc
     * This token is short-lived and safe to use in client-side code
     * @param deploymentName The deployment name (e.g., 'gpt-realtime')
     * @param instructions System instructions for the AI
     * @param voice The voice to use for audio output (e.g., 'marin', 'alloy')
     * @return ClientSecretResponse containing the ephemeral token value
     */
    @AuraEnabled
    public static ClientSecretResponse createRealtimeSession(String deploymentName, String instructions, String voice) {
        try {
            HttpRequest req = new HttpRequest();
            // Azure OpenAI endpoint format: https://{resource}.openai.azure.com/openai/v1/realtime/client_secrets
            req.setEndpoint(AZURE_OPENAI_REALTIME_NAMED_CREDENTIAL + '/openai/v1/realtime/client_secrets');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            
            // Build audio output configuration
            Map<String, Object> audioOutput = new Map<String, Object>{
                'voice' => String.isNotBlank(voice) ? voice : 'alloy'
            };
            
            // Build audio configuration
            Map<String, Object> audio = new Map<String, Object>{
                'output' => audioOutput
            };
            
            // Build session configuration for Azure OpenAI
            Map<String, Object> session = new Map<String, Object>{
                'type' => 'realtime',
                'model' => String.isNotBlank(deploymentName) ? deploymentName : 'gpt-realtime',
                'instructions' => String.isNotBlank(instructions) ? instructions : 'You are a helpful assistant.',
                'audio' => audio
            };
            
            // Build request body
            Map<String, Object> requestBody = new Map<String, Object>{
                'session' => session
            };
            
            req.setBody(JSON.serialize(requestBody));
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            System.debug('Realtime Client Secret Response Status: ' + res.getStatusCode());
            System.debug('Realtime Client Secret Response Body: ' + res.getBody());
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                ClientSecretResponse secretResponse = new ClientSecretResponse();
                secretResponse.value = (String) responseMap.get('value');
                
                // Handle expires_at - could be Long or Integer
                Object expiresAtObj = responseMap.get('expires_at');
                if (expiresAtObj != null) {
                    if (expiresAtObj instanceof Long) {
                        secretResponse.expiresAt = (Long) expiresAtObj;
                    } else if (expiresAtObj instanceof Integer) {
                        secretResponse.expiresAt = (Long) expiresAtObj;
                    }
                }
                
                // Extract session info if present
                Map<String, Object> sessionInfo = (Map<String, Object>) responseMap.get('session');
                if (sessionInfo != null) {
                    secretResponse.sessionModel = (String) sessionInfo.get('model');
                    secretResponse.sessionType = (String) sessionInfo.get('type');
                }
                
                return secretResponse;
            } else {
                throw new AuraHandledException('Failed to create client secret: ' + res.getStatusCode() + ' - ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('Error creating client secret: ' + e.getMessage());
            throw new AuraHandledException('Error creating client secret: ' + e.getMessage());
        }
    }
    
    /**
     * Wrapper class for Client Secret Response from Azure OpenAI /v1/realtime/client_secrets
     */
    public class ClientSecretResponse {
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public Long expiresAt { get; set; }
        @AuraEnabled public String sessionModel { get; set; }
        @AuraEnabled public String sessionType { get; set; }
    }
    
    @AuraEnabled(cacheable=true)
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

    
    @AuraEnabled(cacheable=true)
    public static List<AI_Prompt__c> getPromptByName(String promptName) {
        System.debug('prompt name: '+promptName);
        String nm = '%' + promptName + '%';
        return [
            SELECT Id, Name, Prompt_Request_Id__c
            FROM AI_Prompt__c
            WHERE Name LIKE :nm LIMIT 1
        ];
    }
    
    
    @AuraEnabled
    public static Object getChatCompletion(List<Map<String, String>> messages) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(AZURE_ENDPOINT + '/openai/deployments/' + 
                       DEPLOYMENT_NAME + '/chat/completions?api-version=' + 
                       API_VERSION);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('api-key', '9FzRxq2nMHNzlduqmGEozrwJ5o9Ittb57A0SGOPTzwVvS7Otjb6NJQQJ99ALACHYHv6XJ3w3AAAAACOGIjot');
        
        Map<String, Object> body = new Map<String, Object>{
            'messages' => messages,
            'max_tokens' => 150,
            'temperature' => 0.7,
            'stream' => true
        };
        
        req.setBody(JSON.serialize(body));
        
        // Return streaming response
        return streamResponse(req);
    }
    
    private static Object streamResponse(HttpRequest req) {
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            // Handle streaming response
            return res.getBodyAsBlob();
        } else {
            throw new AuraHandledException('Error from OpenAI: ' + 
                                         res.getBody());
        }
    }
    
    @AuraEnabled
    public static String callOpenAI(String message) {
        try {
            String apiKey = '9FzRxq2nMHNzlduqmGEozrwJ5o9Ittb57A0SGOPTzwVvS7Otjb6NJQQJ99ALACHYHv6XJ3w3AAAAACOGIjot';
            
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(OPENAI_ENDPOINT);
            request.setMethod('POST');
            request.setHeader('Authorization', 'Bearer ' + apiKey);
            request.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> requestBody = new Map<String, Object>{
                'model' => 'gpt-4',
                'messages' => new List<Object>{
                    new Map<String, String>{
                        'role' => 'user',
                        'content' => message
                    }
                },
                'temperature' => 0.7
            };
            
            request.setBody(JSON.serialize(requestBody));
            
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                Map<String, Object> responseBody = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                List<Object> choices = (List<Object>)responseBody.get('choices');
                Map<String, Object> choice = (Map<String, Object>)choices[0];
                Map<String, Object> messageobj = (Map<String, Object>)choice.get('message');
                return (String)messageobj.get('content');
            } else {
                throw new AuraHandledException('OpenAI API error: ' + response.getStatusCode() + ' ' + response.getStatus());
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
  
}