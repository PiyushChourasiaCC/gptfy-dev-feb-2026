/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIGPTfyCalloutController {
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    
    /**
     * Processes the request based on the provided prompt command, prompt body, and AI prompt, performing necessary operations accordingly.
     * 
     * @param promptCommand The command associated with the prompt, specifying the type of request being processed.
     * @param promptBody The body of the prompt containing additional information or data for processing.
     * @param aiPrompt The AI prompt object providing context and details for the request processing.
     * @return String The result of the request processing, which may include data, messages, or notifications based on the provided parameters.
    */
    public static String processRequest(String promptCommand, String promptBody, AI_Prompt__c aiPrompt){
        String supportData;
        try{
            AI_Connection__c connection = aiPrompt.AI_Connection__r;

            Integer maxOuputToken = connection.Max_Tokens__c != null ? (Integer)connection.Max_Tokens__c : null;
            if(aiPrompt.Max_Output_Tokens__c != null){
                maxOuputToken = (Integer)aiPrompt.Max_Output_Tokens__c;
            }
            
            Decimal temprature = connection.Temperature__c != null ? (Decimal)connection.Temperature__c : null;
            if(aiPrompt.Temperature__c != null){
                temprature = (Integer)aiPrompt.Temperature__c;
            }
            
            Decimal topP = connection.Top_P__c != null ? (Decimal)connection.Top_P__c : null;
            if(aiPrompt.Top_P__c != null){
                temprature = (Integer)aiPrompt.Top_P__c;
            }
            
            if(aiPrompt.AI_Connection__c != null && aiPrompt.AI_Connection__r.Max_Total_Tokens__c != null && aiPrompt.AI_Connection__r.Max_Total_Tokens__c > 0){
                String message = promptCommand + ' : ' + promptBody;
                if(String.isNotBlank(message) && (message.length() / 6) > aiPrompt.AI_Connection__r.Max_Total_Tokens__c){
                    throw new ChatGPTUtills.ApplicationException('Data sent to AI is more than the Max Total Token. Please review your mapping to set Record Limits or increase the Max Total Token for the Model.');
                }
            }
            
            HttpResponse response = doCallout(promptCommand, promptBody, connection, aiPrompt, maxOuputToken, temprature, topP); 
            if(response != null){
                //System.debug('body: '+response.getBody());
                //System.debug('status: '+response.getStatus());
                //System.debug('statusCode: '+response.getStatusCode());
                if(String.isBlank(response.getBody()) && response.getStatusCode() > 210 && String.isNotBlank(response.getStatus())){
                    return JSON.serializePretty(new Map<String, Object>{'errorCode' => response.getStatusCode(), 'errorText' => response.getStatus()});
                }
                supportData = response.getBody();
                return JSON.serializePretty((Map<String, Object>)JSON.deserializeUntyped(response.getBody()));
            }
            return null;
        }catch(Exception e){
            String exceptionType = e.getTypeName();
            String message = AIConstants.AI_GENERAL_ERROR;
            if(String.isNotBlank(exceptionType) && exceptionType.endsWithIgnoreCase('ApplicationException')){
                message = e.getMessage();
            }
            if(String.isNotBlank(supportData) && supportData.length() > 131072){
                supportData = supportData.substring(0, 131072); 
            }
            GPTfyException.log(e, 'GPTfy', '', 'AIGPTfyCalloutController', 'validateRequest', supportData);
            return '{"error" : {"message" : "'+message+'"}}';
        }
    }
    
    /**
     * Validates a request based on the provided parameters.
     *
     * @param promptCommand The command associated with the request.
     * @param promptBody The body of the request.
     * @param connection An instance of the AI_Connection__c class representing the connection.
     * @return A String indicating the result of the validation.
     *         - If validation is successful, a success message is returned.
     *         - If validation fails, an error message describing the failure is returned.
     */
    public static String validateRequest(String promptCommand, String promptBody, AI_Connection__c connection){
        try{
            Integer maxOuputToken = connection.Max_Tokens__c != null ? (Integer)connection.Max_Tokens__c : null;
            Decimal temprature = connection.Temperature__c != null ? (Decimal)connection.Temperature__c : null;
            Decimal topP = connection.Top_P__c != null ? (Decimal)connection.Top_P__c : null;
            HttpResponse response = doCallout(promptCommand, promptBody, connection, null, maxOuputToken, temprature, topP);  
            //System.debug('body: '+response.getBody());
            //System.debug('status: '+response.getStatus());
            //System.debug('statusCode: '+response.getStatusCode());
            if(response != null && response.getStatusCode() > 210){
                if(String.isNotBlank(response.getBody())){
                    try{
                        Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                        if(dataMap != null && dataMap.containsKey('message')){
                            return String.valueOf(dataMap.get('message'));
                        }else if(dataMap != null && dataMap.containsKey('error')){
                            Map<String, Object> errorMap = (Map<String, Object>)dataMap.get('error');
                            if(errorMap != null && errorMap.containsKey('message')){
                                return String.valueOf(errorMap.get('message'));
                            }
                        }
                    }catch(Exception e){}  
                    return response.getBody();
                }else if(String.isNotBlank(response.getStatus())){
                    return response.getStatus();
                }
            }
            return null;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIGPTfyCalloutController', 'validateRequest', '');
            return e.getMessage();
        }
    }
    
    /**
     * Generic method to do a callout based on certain type of requests.
     *
     * @param promptCommand The command associated with the request.
     * @param promptBody The body of the request.
     * @param connection An instance of the AI_Connection__c object representing the connection.
     * @param aiPrompt An instance of the AI_Prompt__c object representing the prompt.
     * @param maxOuputToken The maximum number of output tokens allowed for the GPTfy response.
     * @param temprature The temperature value to be used during the GPTfy response generation, affecting the diversity of the output.
     * @param topP The top P value representing the nucleus sampling for the GPTfy response generation, controlling the probability distribution of the generated tokens.
     * @return A HttpResponse indicating the result.
    */
    public static HttpResponse doCallout(String promptCommand, String promptBody, AI_Connection__c connection, AI_Prompt__c aiPrompt, Integer maxOuputToken, Decimal temprature, Decimal topP){
        HttpResponse response;  
        System.debug('connection: '+connection.Name);
        System.debug('promptCommand: '+connection.AI_Technology__c);
        if(connection.AI_Technology__c == AIConstants.PRODUCT_NAME){
            response = processGptfyRequest(promptCommand, promptBody, connection, maxOuputToken, temprature, topP);
        }else{
            if(String.isNotBlank(connection.Processing_Class__c)){
                response = processCustomRequest(connection, aiPrompt, promptCommand, promptBody);
            }else{
                response = submitGPTRequest(promptCommand, promptBody, connection, maxOuputToken, temprature, topP);
            }
        }
        return response;
    }
    
    public static String getGPTfyEncryptedToken(){
        Organization orgInstance = [SELECT Id, IsSandbox FROM Organization LIMIT 1];
        
        Map<String, String> keyBodyMap = new Map<String, String>();
        keyBodyMap.put('org_id', UserInfo.getOrganizationId());
        keyBodyMap.put('org_type', orgInstance.IsSandbox ? AIConstants.ORG_TYPE_SB : AIConstants.ORG_TYPE_PROD);
        keyBodyMap.put('company', UserInfo.getOrganizationName());
        keyBodyMap.put('product', AIConstants.PRODUCT_NAME);
        keyBodyMap.put('email', UserInfo.getUserEmail());

        Blob key = Blob.valueOf('GPTfyallCustomer');
        Blob data = Blob.valueOf(JSON.serialize(keyBodyMap));
        Blob encrypted = Crypto.encrypt('AES128', key, key, data);
        String encString = EncodingUtil.base64Encode(encrypted);
        
        return encString;
    }
	
    /**
     * Processes the GPTfy request based on the provided prompt command, prompt body, AI connection, maximum output tokens, temperature, and top P value, performing necessary GPT-related operations accordingly.
     * 
     * @param promptCommand The command associated with the GPTfy prompt, specifying the type of GPT-related request being processed.
     * @param promptBody The body of the GPTfy prompt containing additional information or data for processing.
     * @param connection The AI connection object providing necessary details for the GPTfy request processing.
     * @param maxOuputToken The maximum number of output tokens allowed for the GPTfy response.
     * @param temprature The temperature value to be used during the GPTfy response generation, affecting the diversity of the output.
     * @param topP The top P value representing the nucleus sampling for the GPTfy response generation, controlling the probability distribution of the generated tokens.
     * @return HttpResponse The result of the GPTfy request processing, which may include generated text, messages, or notifications based on the provided parameters and AI connection.
     */
    public static HttpResponse processGptfyRequest(String promptCommand, String promptBody, AI_Connection__c connection, Integer maxOuputToken, Decimal temprature, Decimal topP){
        //Map<String, Object> mapObject = (Map<String, Object>) JSON.deserializeUntyped(promptBody);
        String userContext = '';
        String systemContext = '';
        
        Organization orgInstance = [SELECT Id, IsSandbox FROM Organization LIMIT 1];
        
        String strBody = '';
        String modelName; //= AIConstants.TURBO_16K_MODEL;
        if(String.isNotBlank(connection.Model__c)){
            modelName = connection.Model__c;
        }
        
        if(String.isNotBlank(modelName) && modelName.equalsIgnoreCase(AIConstants.DAVINCI_MODEL)){
            String message = promptCommand+' : '+promptBody;
            Map<String, Object> body = new Map<String, Object>();
            body.put('temperature', temprature);
            body.put('max_tokens', maxOuputToken);
            body.put('prompt', message);
            strBody = JSON.serialize(body);
        }else if(String.isNotBlank(modelName) && modelName.equalsIgnoreCase(AIConstants.TEXT_BISON_001_MODEL)){
            String message = promptCommand+' : '+promptBody;
            Map<String, Object> body = new Map<String, Object>();
            body.put('instances', new List<Map<String, Object>>{new Map<String, Object>{'content' => message}});
            body.put('parameters', new Map<String, Object>{
                'candidateCount' => 1, 
                'maxOutputTokens' => maxOuputToken, 
                'temperature' => temprature, 
                'topP' => topP
            });
            strBody = JSON.serialize(body); 
        }else if(String.isNotBlank(modelName) && modelName.equalsIgnoreCase(AIConstants.AWS_BEDROCK_MODEL)){
            String message = 'Human: '+promptCommand+' '+promptBody+' \nAssistant:';
            Map<String, Object> reqBodymap = new Map<String, Object>{
                'prompt' => message,
                'max_tokens_to_sample' => maxOuputToken,
                'temperature' => temprature,
                'top_p' => topP,
                'anthropic_version' => connection.Version__c
            };
            strBody = JSON.serialize(reqBodymap); 
        }else if(String.isNotBlank(connection.Model__c) && String.isNotBlank(connection.EndPoint_URL__c) && connection.EndPoint_URL__c.containsIgnoreCase('/chat/completions') && 
            String.isNotBlank(connection.Additional_Parameters__c) && connection.Additional_Parameters__c.containsIgnoreCase('gpt-5')){
                Map<String, Object> additionalParamMap;
                if(String.isNotBlank(connection.Additional_Parameters__c)){
                    try{
                        additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(connection.Additional_Parameters__c);
                    }catch(Exception e){}
                }
                Map<String, String> systemContentMap = new  Map<String, String>();
                systemContentMap.put('role', 'system');
                systemContentMap.put('content', promptCommand);
                
                Map<String, String> userContentMap = new  Map<String, String>();
                userContentMap.put('role', 'user');
                userContentMap.put('content', promptBody);
                
                Map<String, Object> reqBodymap = new Map<String, Object>{
                    'model' => connection.Model__c,
                    'messages' => new List<Map<String, String>>{systemContentMap, userContentMap},
                    'max_completion_tokens' => maxOuputToken,
                    'reasoning_effort' => String.valueOf(additionalParamMap.get('reasoning')),
                    'verbosity' => String.valueOf(additionalParamMap.get('verbosity'))
                };
                strBody = JSON.serialize(reqBodymap);   
        }
        //@Jira V2-7425
        else if(String.isNotBlank(connection.Model__c) && String.isNotBlank(connection.EndPoint_URL__c) && connection.EndPoint_URL__c.containsIgnoreCase('/v1/responses') && 
            String.isNotBlank(connection.Additional_Parameters__c) && connection.Additional_Parameters__c.containsIgnoreCase('gpt-5')){
                Map<String, Object> additionalParamMap;
                if(String.isNotBlank(connection.Additional_Parameters__c)){
                    try{
                        additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(connection.Additional_Parameters__c);
                    }catch(Exception e){}
                }
                Map<String, String> systemContentMap = new  Map<String, String>();
                systemContentMap.put('role', 'system');
                systemContentMap.put('content', promptCommand);
                
                Map<String, String> userContentMap = new  Map<String, String>();
                userContentMap.put('role', 'user');
                userContentMap.put('content', promptBody);
                
                Map<String, Object> reqBodymap = new Map<String, Object>{
                    'model' => connection.Model__c,
                    'input' => new List<Map<String, String>>{systemContentMap, userContentMap},
                    'max_output_tokens' => maxOuputToken,
                    'reasoning' =>  new Map<String, String>{ 'effort' => String.valueOf(additionalParamMap.get('reasoning')) },
                    'text' =>  new Map<String, String>{'verbosity' => String.valueOf(additionalParamMap.get('verbosity')) }
                };
                strBody = JSON.serialize(reqBodymap);    
        }
        //@Jira V2-7425 
        else if(String.isNotBlank(connection.Model__c) && String.isNotBlank(connection.EndPoint_URL__c) && connection.EndPoint_URL__c.containsIgnoreCase('/v1/responses')){
            Map<String, String> systemContentMap = new  Map<String, String>();
            systemContentMap.put('role', 'system');
            systemContentMap.put('content', promptCommand);
            
            Map<String, String> userContentMap = new  Map<String, String>();
            userContentMap.put('role', 'user');
            userContentMap.put('content', promptBody);
            
            Map<String, Object> reqBodymap = new Map<String, Object>{
                'model' => connection.Model__c,
                'input' => new List<Map<String, String>>{systemContentMap, userContentMap},
                'max_output_tokens' => maxOuputToken
            };
            strBody = JSON.serialize(reqBodymap);    
        }else{
            Map<String, String> systemContentMap = new  Map<String, String>();
            systemContentMap.put('role', 'system');
            systemContentMap.put('content', promptCommand);
            
            Map<String, String> userContentMap = new  Map<String, String>();
            userContentMap.put('role', 'user');
            userContentMap.put('content', promptBody);
            
            Map<String, Object> reqBodymap = new Map<String, Object>{
                'messages' => new List<Map<String, String>>{systemContentMap, userContentMap},
                'max_tokens' => maxOuputToken
            };
            strBody = JSON.serialize(reqBodymap);    
        }
        
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        if(String.isNotBlank(connection.Connector_Class__c)){
            Type impl = Type.forName('', connection.Connector_Class__c);
                AIAuthenticationInterface obj = (AIAuthenticationInterface)impl.newInstance();
                request = obj.getAuthenticatedRequest(connection);
                String endPointUrl = request.getEndPoint();
                request.setEndPoint(endPointUrl+AIConstants.PRODUCT_UNIQ_ENDPOINT);
        }else{
            String endPoint = 'callout:'+NAMESPACE+connection.Named_Credential__c;
        	if(String.isNotBlank(connection.EndPoint_URL__c)){
            	endPoint += connection.EndPoint_URL__c;
        	}
        	endPoint += AIConstants.PRODUCT_UNIQ_ENDPOINT;
            request.setEndpoint(endPoint);
        }
        
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('token', getGPTfyEncryptedToken());
        request.setHeader('Content-Type', 'application/json;charset=UTF-8');
        if(String.isNotBlank(modelName)){
            request.setHeader('model', modelName);
        }
        request.setBody(strBody);
        HttpResponse response = http.send(request);
        System.debug('response: '+response.getBody());
        return response;
    }
    
    /**
     * Submits the GPT request based on the provided prompt command, prompt body, AI connection, maximum output tokens, temperature, and top P value, initiating the GPT-related request processing.
     * 
     * @param promptCommand The command associated with the GPT request, specifying the type of GPT-related request being submitted.
     * @param promptBody The body of the prompt containing additional information or data for the GPT request processing.
     * @param connection The AI connection object providing necessary details for the GPT request submission.
     * @param maxOuputToken The maximum number of output tokens allowed for the GPT response.
     * @param temprature The temperature value to be used during the GPT response generation, affecting the diversity of the output.
     * @param topP The top P value representing the nucleus sampling for the GPT response generation, controlling the probability distribution of the generated tokens.
     * @return String The result of the GPT request submission, which may include generated text, messages, or notifications based on the provided parameters and AI connection.
     */
    public static HttpResponse submitGPTRequest(String promptCommand, String promptBody, AI_Connection__c connection, Integer maxOuputToken, Decimal temprature, Decimal topP){             
        
        String userContext = '';
        String systemContext = '';
        
        String contentType = 'application/json;charset=UTF-8';
            String acceptType = '';
            
            String additionalParams = '';
            String body = '';
            if(String.isNotBlank(connection.Model__c) && connection.Model__c.equalsIgnoreCase(AIConstants.DAVINCI_MODEL)){
                String message = promptCommand +' : '+promptBody;
                Map<String, Object> reqBodymap = new Map<String, Object>{
                    'model' => connection.Model__c,
                    'prompt' => message,
                    'temperature' => temprature,
                    'max_tokens' => maxOuputToken
                };
                body = JSON.serialize(reqBodymap);
            }else if(String.isNotBlank(connection.Model__c) && connection.Model__c.equalsIgnoreCase(AIConstants.X_LARGE_MODEL)){
                String message = promptCommand +' : '+promptBody;
                Map<String, Object> reqBodymap = new Map<String, Object>{
                    'model' => 'command-xlarge-nightly',
                    'prompt' => message,
                    'return_likelihoods' => 'NONE',
                    'truncate' => 'END',
                    'max_tokens' => maxOuputToken
                };
                body = JSON.serialize(reqBodymap);
            }else if(String.isNotBlank(connection.Model__c) && connection.Model__c.equalsIgnoreCase(AIConstants.GCP_CHAT_BISON_MODEL)){
                
                Map<String, Object> instancesMap = new Map<String, Object>{
                    'context' => promptCommand,
                    'messages' => new List<Map<String, Object>>{new Map<String, Object>{
                        'author' => 'user',
                        'content' => promptBody   
                    }} 
                };
                
                Map<String, Object> paramMap = new Map<String, Object>{
                    'maxOutputTokens' => maxOuputToken,
                    'temperature' => temprature,
                    'topP' => topP
                };
                    
                Map<String, Object> reqBodymap = new Map<String, Object>{
                    'instances' => new List<Map<String, Object>>{instancesMap},
                    'parameters' => paramMap   
                };
                    
                body = JSON.serialize(reqBodymap);    
                    
            }
            else if(String.isNotBlank(connection.Model__c) && connection.Model__c.equalsIgnoreCase(AIConstants.GCP_DIALOGFLOW_MODEL)){
                String contextId = AIPromptTriggerHandler.getRandomString(20);
                additionalParams += '/sessions/'+contextId+':detectIntent';
                String message = promptCommand;
                if(String.isNotBlank(promptBody)){
                    message += ' : '+promptBody;
                }
                Map<String, Object> reqBodymap = new Map<String, Object>{
                    'queryInput' => new Map<String, Object>{'text' => new Map<String, Object>{'text' => message}, 'languageCode' => 'en'},
                    'queryParams' => new Map<String, Object>{'timeZone' => 'America/Los_Angeles'}                   
                };
                body = JSON.serialize(reqBodymap);    
            }
            else if(String.isNotBlank(connection.Model__c) && connection.Model__c.equalsIgnoreCase(AIConstants.AWS_BEDROCK_MODEL)){
                if(String.isNotBlank(connection.EndPoint_URL__c) && connection.EndPoint_URL__c.endsWithIgnoreCase('retrieveAndGenerate')){
                    String message = promptCommand +' : '+promptBody;
                    
                    Map<String, Object> additionalParamMap;
                    if(String.isNotBlank(connection.Additional_Parameters__c)){
                        try{
                            additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(connection.Additional_Parameters__c);
                        }catch(Exception e){}
                    }
                    
                    Map<String, Object> reqBodymap = new Map<String, Object>{
                        'input' => new Map<String, Object>{'text' => message},
                        'retrieveAndGenerateConfiguration' => new Map<String, Object>{
                        	'knowledgeBaseConfiguration' => new Map<String, Object>{
                                'knowledgeBaseId' => additionalParamMap != null && additionalParamMap.containsKey('knowledgeBaseId') ? String.valueOf(additionalParamMap.get('knowledgeBaseId')) : '',
                                'modelArn' => additionalParamMap != null && additionalParamMap.containsKey('modelArn') ? String.valueOf(additionalParamMap.get('modelArn')) : ''
                             },
                            'type' => 'KNOWLEDGE_BASE'
                        }
                    };
                    body = JSON.serialize(reqBodymap); 
                }else{
                    String message = 'Human: '+promptCommand+' '+promptBody+' \nAssistant:';
                    Map<String, Object> reqBodymap = new Map<String, Object>{
                        'prompt' => message,
                        'max_tokens_to_sample' => maxOuputToken,
                        'temperature' => temprature,
                        'top_p' => topP
                    };
                    body = JSON.serialize(reqBodymap); 
                }
                contentType = 'application/json';
                acceptType = 'application/json';
            }else if(String.isNotBlank(connection.Model__c) && connection.Model__c.containsIgnoreCase('llama')){
                String message = promptCommand +' : '+promptBody;
                Map<String,Object> reqBodymap = new Map<String,Object>{
                    'additionalModelRequestFields' => new Map<String, Object>{},
                        'inferenceConfig' => new Map<String, Object>{
                            'maxTokens' => maxOuputToken,
                            'temperature' => temprature,
                            'topP' => topP    
                        },
                        'messages' => new List<Object>{new Map<String, Object>{'content' => new List<Object>{new Map<String, Object>{'text' => message}}, 'role' => 'user'}}
                };
                body = JSON.serialize(reqBodymap);
                contentType = 'application/json';
                acceptType = 'application/json';
            }else if(String.isNotBlank(connection.Model__c) && connection.Model__c.equalsIgnoreCase(AIConstants.AZURE_RAG_GPT_35_TURBO_MODEL)){   
                Map<String, String> systemContentMap = new  Map<String, String>();
                systemContentMap.put('role', 'system');
                systemContentMap.put('content', promptCommand);
                
                Map<String, String> userContentMap = new  Map<String, String>();
                userContentMap.put('role', 'user');
                userContentMap.put('content', promptBody);
                
                Map<String, Object> additionalParamMap;
                if(String.isNotBlank(connection.Additional_Parameters__c)){
                    try{
                        additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(connection.Additional_Parameters__c);
                    }catch(Exception e){}
                }

                Map<String,Object> reqBodymap = new Map<String,Object>{
                    'messages' => new List<Map<String,String>>{systemContentMap, userContentMap},
                    'dataSources' => new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'type' => 'AzureCognitiveSearch',
                        	'parameters' => new Map<String, Object>{ 
                                'endpoint' => additionalParamMap != null && additionalParamMap.containsKey('endpoint') ? String.valueOf(additionalParamMap.get('endpoint')) : '',
                                'key' => additionalParamMap != null && additionalParamMap.containsKey('key') ? String.valueOf(additionalParamMap.get('key')) : '',
                                'indexName' => additionalParamMap != null && additionalParamMap.containsKey('indexName') ? String.valueOf(additionalParamMap.get('indexName')) : '' 
                             }
                                                          
                 		}
                    },
                   'temperature' => temprature,
                    'top_p' => topP,
                    'max_tokens' => maxOuputToken
                };
                body = JSON.serialize(reqBodymap);
            }/*else if(String.isNotBlank(connection.Model__c) && String.isNotBlank(connection.EndPoint_URL__c) && connection.EndPoint_URL__c.containsIgnoreCase('/assistants')){
                String message = promptCommand +' : '+promptBody;
                Map<String, Object> reqBodymap = new Map<String, Object>{
                    'instructions' => message,
                    'name' => 'Assistant',
                    'tools' => new List<Map<String, String>>{new Map<String, String>{'type' => 'retrieval'}},
                    'model' => connection.Model__c
                };
                body = JSON.serialize(reqBodymap);    
            }*/
            //@Jira V2-7425
            else if(String.isNotBlank(connection.Model__c) && String.isNotBlank(connection.EndPoint_URL__c) && connection.EndPoint_URL__c.containsIgnoreCase('/chat/completions') && 
                String.isNotBlank(connection.Additional_Parameters__c) && connection.Additional_Parameters__c.containsIgnoreCase('gpt-5')){
                    Map<String, Object> additionalParamMap;
                    if(String.isNotBlank(connection.Additional_Parameters__c)){
                        try{
                            System.debug('connection.Additional_Parameters__c: '+connection.Additional_Parameters__c);
                            additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(connection.Additional_Parameters__c);
                        }catch(Exception e){
                            System.debug('error: '+e.getMessage());
                            System.debug('error: '+e.getStackTraceString());
                        }
                    }
                    Map<String, String> systemContentMap = new  Map<String, String>();
                    systemContentMap.put('role', 'system');
                    systemContentMap.put('content', promptCommand);
                    
                    Map<String, String> userContentMap = new  Map<String, String>();
                    userContentMap.put('role', 'user');
                    userContentMap.put('content', promptBody);
                    
                    System.debug('additionalParamMap: '+additionalParamMap);
                    System.debug('maxOuputToken: '+maxOuputToken);
                    System.debug('verbosity: '+additionalParamMap.get('verbosity'));
                    System.debug('reasoning: '+additionalParamMap.get('reasoning'));
                    Map<String, Object> reqBodymap = new Map<String, Object>{
                        'model' => connection.Model__c,
                        'messages' => new List<Map<String, String>>{systemContentMap, userContentMap},
                        'max_completion_tokens' => maxOuputToken,
                        'verbosity' => String.valueOf(additionalParamMap.get('verbosity')),
                        'reasoning_effort' => String.valueOf(additionalParamMap.get('reasoning')) 
                    };
                    body = JSON.serialize(reqBodymap);   
                    System.debug('body: '+body);
            }
            //@Jira V2-7425
            else if(String.isNotBlank(connection.Model__c) && String.isNotBlank(connection.EndPoint_URL__c) && connection.EndPoint_URL__c.containsIgnoreCase('/v1/responses') && 
                String.isNotBlank(connection.Additional_Parameters__c) && connection.Additional_Parameters__c.containsIgnoreCase('gpt-5')){
                    Map<String, Object> additionalParamMap;
                    if(String.isNotBlank(connection.Additional_Parameters__c)){
                        try{
                            additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(connection.Additional_Parameters__c);
                        }catch(Exception e){}
                    }
                    Map<String, String> systemContentMap = new  Map<String, String>();
                    systemContentMap.put('role', 'system');
                    systemContentMap.put('content', promptCommand);
                    
                    Map<String, String> userContentMap = new  Map<String, String>();
                    userContentMap.put('role', 'user');
                    userContentMap.put('content', promptBody);
                    
                    Map<String, Object> reqBodymap = new Map<String, Object>{
                        'model' => connection.Model__c,
                        'input' => new List<Map<String, String>>{systemContentMap, userContentMap},
                        'max_output_tokens' => maxOuputToken,
                        'reasoning' =>  new Map<String, String>{ 'effort' => String.valueOf(additionalParamMap.get('reasoning')) },
                        'text' =>  new Map<String, String>{'verbosity' => String.valueOf(additionalParamMap.get('verbosity')) }
                    };
                    body = JSON.serialize(reqBodymap);    
            }
            //@Jira V2-7425 
            else if(String.isNotBlank(connection.Model__c) && String.isNotBlank(connection.EndPoint_URL__c) && connection.EndPoint_URL__c.containsIgnoreCase('/v1/responses')){
                Map<String, String> systemContentMap = new  Map<String, String>();
                systemContentMap.put('role', 'system');
                systemContentMap.put('content', promptCommand);
                
                Map<String, String> userContentMap = new  Map<String, String>();
                userContentMap.put('role', 'user');
                userContentMap.put('content', promptBody);
                
                Map<String, Object> reqBodymap = new Map<String, Object>{
                    'model' => connection.Model__c,
                    'input' => new List<Map<String, String>>{systemContentMap, userContentMap},
                    'max_output_tokens' => maxOuputToken
                };
                body = JSON.serialize(reqBodymap);    
            }else{   
                Map<String, String> systemContentMap = new  Map<String, String>();
                systemContentMap.put('role', 'system');
                systemContentMap.put('content', promptCommand);
                
                Map<String, String> userContentMap = new  Map<String, String>();
                userContentMap.put('role', 'user');
                userContentMap.put('content', promptBody);
                
                Map<String,Object> reqBodymap = new Map<String,Object>{
                    'messages' => new List<Map<String,String>>{systemContentMap, userContentMap},
                    'model' => connection.Model__c,
                    'max_tokens' => maxOuputToken
                };
                body = JSON.serialize(reqBodymap);
            }
            
            HttpRequest req; 
            if(String.isNotBlank(connection.Connector_Class__c)){
                Type impl = Type.forName('', connection.Connector_Class__c);
                AIAuthenticationInterface obj = (AIAuthenticationInterface)impl.newInstance();
                req = obj.getAuthenticatedRequest(connection);
            }else{
                req = new HttpRequest();
                String endPoint = 'callout:'+connection.Named_Credential__c+connection.EndPoint_URL__c+additionalParams;
                req.setEndpoint(endPoint);
                System.debug('endPoint: '+endPoint);
            }
            req.setMethod('POST');
            req.setTimeout(120000);
            req.setHeader('Content-Type', contentType);
            if(String.isNotBlank(acceptType)){
                req.setHeader('Accept', acceptType);
            }
            req.setBody(body);

            Http api = new Http();
            HttpResponse response = api.send(req);
            System.debug('response: '+response.getBody());
            return response;
    }
    
    public static HttpResponse processCustomRequest(AI_Connection__c aiModel, AI_Prompt__c aiPrompt, String promptCommand, String extractedData){
        Type impl = Type.forName('', aiModel.Processing_Class__c);
        AIProcessingInterface obj = (AIProcessingInterface)impl.newInstance();
        HttpResponse response = obj.getProcessedResponse(aiModel, aiPrompt, promptCommand, extractedData);
        return response;
    }
    
    /**
     * fetching the result of the analysis of the document
     * @param mapOfEndpointUrls The map is contains document Id and url of request endpoint.
     * @return Return map data anlysis of the document.
     */
    public static Map<String, String> getGPTfyAnalyzeResult(Map<String, String> mapOfEndpointUrls){
        Map<String, String> mapOfData = new Map<String, String>();
        for(String cdId : mapOfEndpointUrls.keySet()){     
            
            String endPoint = 'callout:'+AIGPTfyCalloutController.NAMESPACE+'GPTfy/api/GetAnalysisResults';
            endPoint += AIConstants.PRODUCT_UNIQ_ENDPOINT;
            endpoint += '&url=analyzeResults/'+mapOfEndpointUrls.get(cdId);
            
            String token = AIGPTfyCalloutController.getGPTfyEncryptedToken();

            Http http = new Http();
            HttpRequest request = new HttpRequest();
            
            request.setEndpoint(endPoint);
            request.setMethod('GET');
            request.setTimeout(120000);
            request.setHeader('token', token);
            
            HttpResponse response = http.send(request);
            //System.debug('body: '+response.getBody());
            //System.debug('status: '+response.getStatus());
            //System.debug('statusCode: '+response.getStatusCode());
            
            if(String.isNotBlank(response.getBody())){
                Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                if(dataMap != null && !dataMap.isEmpty() && dataMap.containsKey('Result')){
                    Object resultMapStr = (Object)dataMap.get('Result');
                    mapOfData.put(cdId, String.valueOf(resultMapStr));
                }
            }
        }
        return mapOfData;
    }
    
    /*
     * Request to AI for Analysis documentation
     * @param cdIds The list is contains document id of attached file.
     * @return Return The map is contains document id and url of anlysis of the document.
     */
    public static Map<String, String> processGPTfyFileRequest(List<String> cdIds){

		Map<String, ContentVersion> data = new Map<String, ContentVersion>();      
        for(ContentVersion cv : [SELECT Id, ContentDocumentId, VersionData FROM ContentVersion 
                                 WHERE ContentDocumentId IN :cdIds AND IsLatest = True]){
            data.put(cv.ContentDocumentId, cv);
        }
        
        Map<String, String> mapOfEndpointUrls = new Map<String, String>();
        for(String cdId : data.keySet()){
            ContentVersion cv = data.get(cdId);
            
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            
            String endPoint = 'callout:'+AIGPTfyCalloutController.NAMESPACE+'GPTfy/api/AnalyzeDocument';
            endPoint += AIConstants.PRODUCT_UNIQ_ENDPOINT;
            String token = AIGPTfyCalloutController.getGPTfyEncryptedToken();

            request.setEndpoint(endPoint);
            request.setMethod('POST');
            request.setTimeout(120000);
            request.setHeader('token', token);
            request.setHeader('Content-Type', 'text/plain');
            request.setBody(EncodingUtil.base64Encode(cv.VersionData));

            HttpResponse response = http.send(request);
            //System.debug('body: '+response.getBody());
            //System.debug('status: '+response.getStatus());
            //System.debug('statusCode: '+response.getStatusCode());
            
           String respUrl;
            if(String.isNotBlank(response.getBody())){
                Map<String,Object> dataMap = (Map<String,Object>)JSON.deserializeUntyped(response.getBody());
				if(dataMap != null && dataMap.containsKey('headers')){
                	List<object> headersList = (List<object>)dataMap.get('headers');
                    //System.debug('headers : '+headersList);
                    if(headersList != null && !headersList.isEmpty()){
                        for(Object obj : headersList){
                            Map<String, object> keyValueMap = (Map<String, object>)obj;
                            if(keyValueMap != null && keyValueMap.containsKey('key') && keyValueMap.get('key') == 'Operation-Location' && keyValueMap.containsKey('value') && keyValueMap.get('value') != null){
                                List<Object> urls = (List<Object>)keyValueMap.get('value');
                                if(urls != null && !urls.isEmpty()){
                                    respUrl = String.valueOf(urls.get(0)).substringAfter('/analyzeResults/');
                                }
                                break;
                            }
                        }
                    }
            	}                
            }
                       
            //handling errors
            if(String.isBlank(respUrl) && response.getBody() != null){
                Map<String, Object> respMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                if(respMap.containsKey('error')){
                    Map<String, Object> errorMap = (Map<String,Object>)respMap.get('error');
                    if(errorMap.containsKey('innererror')){
                        Map<String, Object> innerErrorMap = (Map<String,Object>)errorMap.get('innererror');
                        if(innerErrorMap.containsKey('message') && innerErrorMap.get('message') != null){
                            throw new ChatGPTUtills.ApplicationException(String.valueOf(innerErrorMap.get('message')));
                        }
                	}
                }
            }
            mapOfEndpointUrls.put(cdId, respUrl);
        }
        return mapOfEndpointUrls;  
    }
    
     /**
     * fetching the result of the analysis of the document
     * @param mapOfEndpointUrls The map is contains document Id and url of request endpoint.
     * @return Return map data anlysis of the document.
     */
    public static Map<String, String> getAnalyzeResult(AI_Connection__c aiModel, Map<String, String> mapOfEndpointUrls){
        Map<String, String> mapOfData = new Map<String, String>();
        
        for(String cdId : mapOfEndpointUrls.keySet()){     
            String endPoint = mapOfEndpointUrls.get(cdId);
            Integer index = endPoint.indexOf('.com/');
            if (index != -1) {
                // Extract the relative path after ".com/"
                String relativePath = endPoint.substring(index + 5); // to skip ".com/"
                // Construct the new URL with Named Credential
                endPoint = 'callout:'+aiModel.Named_Credential__c + '/' + relativePath;
            }
            
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            
            request.setEndpoint(endPoint);
            request.setMethod('GET');
            request.setTimeout(120000);
            HttpResponse response = http.send(request);
            
            if(String.isNotBlank(response.getBody())){
                mapOfData.put(cdId, String.valueOf(response.getBody()));
            } 
        }
        
        return mapOfData;
    }
    
    /**
     * Request to AI for Analysis documentation File.
     * @param cdIds The list is contains document id of attached file.
     * @return Return The map is contains document id and url of anlysis of the document.
     */
    public static Map<String, String> processFileRequest(AI_Connection__c aiModel, List<String> cdIds){
        Map<String, ContentVersion> data = new Map<String, ContentVersion>();      
        for(ContentVersion cv : [SELECT Id, ContentDocumentId, VersionData FROM ContentVersion 
                                 WHERE ContentDocumentId IN :cdIds AND IsLatest = True]){
            data.put(cv.ContentDocumentId, cv);
        }
        
        Map<String, String> mapOfEndpointUrls = new Map<String, String>();
        for(String cdId : data.keySet()){
            ContentVersion cv = data.get(cdId);
            
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            String endPoint = 'callout:'+aiModel.Named_Credential__c+aiModel.EndPoint_URL__c;
            request.setEndpoint(endPoint);
            request.setMethod('POST');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            Map<String, String> keyBodyMap = new Map<String, String>();
            keyBodyMap.put('base64Source', EncodingUtil.base64Encode(cv.VersionData));
            request.setBody(JSON.serialize(keyBodyMap));
            
            HttpResponse response = http.send(request);

            String respUrl;
            if(response.getHeader('Operation-Location') != Null){
                respUrl = response.getHeader('Operation-Location');
                mapOfEndpointUrls.put(cv.ContentDocumentId, respUrl);
            } 
        }
           
        return mapOfEndpointUrls;
    }
    
    /**
     * JIRA V2-7410 : Enhance Validation/Handshake process for Agentic
     * Validate the configuration for Agentic
     * @param connection The AI Model details which going to create
     */
    public static String validateVoiceRequest(AI_Connection__c connection){
        try{
            HttpRequest httpRequestObj = new HttpRequest();
            httpRequestObj.setEndpoint('callout:' + connection.Named_Credential__c + '/v1/responses');
            String body = getVoiceRequestBody(connection.Model__c);
            System.debug(body);
            HttpResponse response = AIAgenticCalloutService.responseGenerator(httpRequestObj, body);
            System.debug(response.getBody());
            if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                return null;
            } else {
                return response.getBody();
            }
            
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIGPTfyCalloutController', 'validateRequest', '');
            return e.getMessage();
        }
    }
    
    /**
     * JIRA V2-7410 : Enhance Validation/Handshake process for Agentic
     * Sample payload for Agentic
     * @param model The model name which selected for AI Model
     */
    public static String getVoiceRequestBody(String model){
        String body = '';
        Map<String, Object> requestBody= new Map<String, Object>{
            'model' => model, 
                'input' => (Object)JSON.deserializeUntyped('[{"content":[{"text":"IMPORTANT: For EACH provided RECORD, IF record ID is PRESENT and NOT NULL, REPLACE \\u003CRecordId\\u003E with the actual record ID. ONLY generate this LINK when a valid record ID EXISTS in the RESPONSE. The LINK must open the record in VIEW-ONLY (READ-ONLY) MODE. Do NOT show the link if the record ID is missing. The record ID should be embedded in the URL, NOT displayed elsewhere on the UI.\\n\\nIF user query CONTAINS (\\"this\\" OR \\"current\\" OR \\"selected\\" OR explicit reference to CURRENT RECORD) THEN USE current record details ELSE SEARCH across records; DO NOT USE current record details when query does NOT explicitly reference it.\\n\\nCURRENT RECORD CONTEXT: User is viewing Account record:\\n- ID:  0018d00000looahAAA\\nName: Cloud Compliance / GPTfy Test Account\\n\\n\\nIMPORTANT: All RESPONSES must be in English LANGUAGE ONLY, using English (United Kingdom)  LOCALE conventions for all formatting (dates, numbers, etc.).  ALL RESPONSES must be structured and OUTPUT as VALID HTML.. DO NOT use any HTML <table>, <thead>, <tbody>, <tfoot>, <tr>, <th>, or <td> tags—tables in any format are STRICTLY PROHIBITED. DO NOT use Markdown, code fences, or any code block delimiters (such as ``````) in the output. The response must be pure HTML. without code wrappers.\\n\\n User: can you please Let me know 1 Account Name?","type":"input_text"}],"role":"user"}]'),
                'tools' => (Object)JSON.deserializeUntyped('[{"parameters":{"required":["Subject","AccountId"],"properties":{"AccountId":{"description":"Id of the Acccount","type":"string"},"Subject":{"description":"Subject of the Case","type":"string"}},"type":"object"},"description":"Create a Case For an Account","name":"create_Case_for_Account","type":"function"},{"parameters":{"required":["LastName"],"properties":{"AccountId":{"description":"Id of the Parent Account","type":"string"},"FirstName":{"description":"FirstName of the contact","type":"string"},"LastName":{"description":"LastName of the contact","type":"string"}},"type":"object"},"description":"Create a new contact with the specified details","name":"create_Contact_by_Name","type":"function"},{"parameters":{"required":["Subject","ContactId"],"properties":{"ContactId":{"description":"Id of the Contact","type":"string"},"Subject":{"description":"Subject of the Case","type":"string"}},"type":"object"},"description":"Create a Case with Subject and ContactId","name":"create_Case","type":"function"},{"parameters":{"required":["Id"],"properties":{"Id":{"description":"Record Id Of the Account","type":"string"}},"type":"object"},"description":"This function fetches all the contacts, Opportunities and tasks for the Account by Id","name":"get_Account_details_by_Id","type":"function"},{"parameters":{"required":["Name"],"properties":{"Name":{"description":"Name Of the Account","type":"string"}},"type":"object"},"description":"This function fetches all the contacts, Opportunities and tasks for the Account by Name","name":"get_Account_details_by_name","type":"function"},{"max_num_results":20,"vector_store_ids":["vs_68abe6c890c081919584d0ef4c950c8e","vs_68ad2ea99b8881918fa7e266da5a7fcd"],"type":"file_search"}]'),
                'instructions' => 'You are a Sales Assistant Agent whose primary role is to facilitate the sales process by managing leads, tracking opportunities, qualifying prospects, and providing timely product information. Your core responsibilities include:<br><ul><li>Understanding and navigating the sales pipeline effectively.</li><li>Following up on opportunities and tracking customer interactions.</li><li>Generating quotes and answering pricing questions.</li><li>Guiding customers through the sales process to help close deals.</li></ul><br>When interacting with customers, maintain a professional and friendly tone. Your communication style should be clear, concise, and informative. Always format your responses using HTML tags for better readability. For example:<br><h3>Product Information</h3><p>Here are the details about our latest product:</p><ul><li><strong>Feature 1:</strong> Description</li><li><strong>Feature 2:</strong> Description</li></ul><br>In common scenarios, such as when a customer asks for a quote, you should respond with:<br><h3>Quote Request</h3><p>Thank you for your interest! Here is the quote for your requested product:</p><ul><li><strong>Product Name:</strong> XYZ</li><li><strong>Price:</strong> $100</li></ul><br>Always ensure that you provide accurate and timely information. If you encounter a situation where you do not have the answer, inform the customer that you will follow up with the necessary information as soon as possible. Your limitations include not providing personal opinions or making decisions outside of the sales process. Always prioritize customer satisfaction and strive to assist them in making informed decisions.</p>',
                'previous_response_id' => null,
                'tool_choice' => 'auto'
                };
        body = JSON.serialize(requestBody);
        return body;
    }
    
}