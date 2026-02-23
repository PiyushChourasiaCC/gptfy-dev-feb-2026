public with sharing class AIAssistantApiCalloutUtility {

    public static AssistantWrapper processFileRequest(AssistantWrapper wrap){
        if(wrap.vectorStoreId == NULL || wrap.vectorStoreId == ''){
            wrap = AIAssistantApiCalloutUtility.createVectorStore(wrap);
            wrap = AIAssistantApiCalloutUtility.fileUpload(wrap);
            wrap = AIAssistantApiCalloutUtility.addFileToVectorStore(wrap);
        }
       if(wrap.runStatus == NULL || wrap.runStatus == ''){
        	wrap = AIAssistantApiCalloutUtility.createAssistant(wrap);
            wrap = AIAssistantApiCalloutUtility.createThread(wrap);
            wrap = AIAssistantApiCalloutUtility.createMessage(wrap);
            wrap = AIAssistantApiCalloutUtility.createRun(wrap);
        }
        if(wrap.runStatus != NULL || wrap.runStatus != ''){
            wrap = AIAssistantApiCalloutUtility.getRunStatus(wrap);
        }
        return wrap;
    }
    
    public static AssistantWrapper getAnalyzeResult(AssistantWrapper wrap){
        wrap = AIAssistantApiCalloutUtility.getRunStatus(wrap);
        wrap = AIAssistantApiCalloutUtility.getChatResponse(wrap);
        return wrap;
    }

    public static AssistantWrapper createVectorStore(AssistantWrapper wrap){
        String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/vector_stores?api-version='+wrap.aiModel.Version__c;
        String body = JSON.serialize(new Map<String, Object>{'name' => wrap.recordId});
        
        Http http = new Http();
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'application/json');
        request.setBody(body);
        
        HttpResponse response = http.send(request);
        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());
        
        String respBody = response.getBody();
        if(String.isNotBlank(respBody)){
            Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
            if(dataMap != null && dataMap.containsKey('id')){
                wrap.vectorStoreId = String.valueOf(dataMap.get('id'));
            }
        }

        return wrap;
    }
    
    public static AssistantWrapper fileUpload(AssistantWrapper wrap){
        String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/files?api-version='+wrap.aiModel.Version__c;
        String boundary = '----SalesforceBoundary' + String.valueOf(DateTime.now().getTime());
        String body = '--' + boundary + '\r\n';
        body += 'Content-Disposition: form-data; name="purpose"\r\n\r\n';
        body += 'assistants\r\n';
        body += '--' + boundary + '\r\n';
        body += 'Content-Disposition: form-data; name="file"; filename="' + [SELECT PathOnClient FROM ContentVersion WHERE ContentDocumentId IN :wrap.cdIds AND IsLatest = True LIMIT 1].PathOnClient + '"\r\n';
        body += 'Content-Type: application/octet-stream\r\n\r\n'+EncodingUtil.base64Encode([SELECT VersionData FROM ContentVersion WHERE ContentDocumentId IN :wrap.cdIds AND IsLatest = True LIMIT 1].VersionData)+'\r\n--' + boundary + '--';
        Http http = new Http();
        
        HttpRequest request = new HttpRequest();
        request.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setBody(body);
        HttpResponse response = http.send(request);
        
        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());
        
        String respBody = response.getBody();
        if(String.isNotBlank(respBody)){
            Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
            if(dataMap != null && dataMap.containsKey('id')){
                wrap.uploadedFileId = String.valueOf(dataMap.get('id'));
            }
        }
        
        return wrap;
    }
    
    public static AssistantWrapper addFileToVectorStore(AssistantWrapper wrap){
        String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/vector_stores/'+wrap.vectorStoreId+'/files?api-version='+wrap.aiModel.Version__c;
        //String body = JSON.serialize(new Map<String, Object>{'file_id' => wrap.uploadedFileId, 'chunk_size' => 1000, 'overlap' => 100});
        String body = JSON.serialize(new Map<String, Object>{'file_id' => wrap.uploadedFileId});
        
        Http http = new Http();
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'application/json');
        request.setBody(body);
        
        HttpResponse response = http.send(request);
        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());

        return wrap;
    }
    
    public static AssistantWrapper createAssistant(AssistantWrapper wrap){
        String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/assistants?api-version='+wrap.aiModel.Version__c;
        //String instructions = 'You are an AI assistant that can write code to help answer math questions.';
        String instructions = 'You are an intelligent assistant designed to retrieve and provide accurate information from files uploaded via the file search tool. When a user asks questions related to these files, ensure your responses are based on the content within the uploaded files. Always prioritize the most relevant and precise information from the files to answer the user\'s queries.\nIf a user asks some details from the files uploaded like " provide the details from this topic", then search in the document and give full response from that topic inside that document.';
        //String instructions = wrap.promptCommand;
        if(String.isNotBlank(wrap.extractedData)){
            instructions += '\n\nAdditional Information:\n'+wrap.extractedData;
        }
        
        String body = JSON.serialize(
            new Map<String, Object>{
                'instructions' => instructions,
               	'name' => wrap.recordId,
                'tools' => new List<Object>{new Map<String, Object>{'type' => 'file_search'}},
                'model' => 'gpt-4o',
                'tool_resources' => new Map<String, Object>{'file_search' => new Map<String, Object>{'vector_store_ids' => new List<String>{wrap.vectorStoreId}}},
                'temperature' => wrap.aiModel.Temperature__c,
                'top_p' => wrap.aiModel.Top_p__c 
        	}
       	);
        
        Http http = new Http();
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'application/json');
        request.setBody(body);
        
        HttpResponse response = http.send(request);
        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());
        
        String respBody = response.getBody();
        if(String.isNotBlank(respBody)){
            Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
            if(dataMap != null && dataMap.containsKey('id')){
                wrap.assistantId = String.valueOf(dataMap.get('id'));
            }
        }

        return wrap;
    }
    
    public static AssistantWrapper createThread(AssistantWrapper wrap){
        String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/threads?api-version='+wrap.aiModel.Version__c;
        
        Http http = new Http();
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Content-Length', '0');
        
        HttpResponse response = http.send(request);
        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());
        
        String respBody = response.getBody();
        if(String.isNotBlank(respBody)){
            Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
            if(dataMap != null && dataMap.containsKey('id')){
                wrap.threadId = String.valueOf(dataMap.get('id'));
            }
        }

        return wrap;
    }
    
    public static AssistantWrapper createMessage(AssistantWrapper wrap){
        String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/threads/'+wrap.threadId+'/messages?api-version='+wrap.aiModel.Version__c;
        String body = JSON.serialize(new Map<String, Object>{'role' => 'user', 'content' => wrap.promptCommand});
        
        Http http = new Http();
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'application/json');
        request.setBody(body);
        
        HttpResponse response = http.send(request);
        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());
        
        String respBody = response.getBody();
        if(String.isNotBlank(respBody)){
            Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
            if(dataMap != null && dataMap.containsKey('id')){
                wrap.messageId = String.valueOf(dataMap.get('id'));
            }
        }

        return wrap;
    }
    
    public static AssistantWrapper createRun(AssistantWrapper wrap){
        String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/threads/'+wrap.threadId+'/runs?api-version='+wrap.aiModel.Version__c;
        String body = JSON.serialize(new Map<String, Object>{'assistant_id' => wrap.assistantId});
        
        Http http = new Http();
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'application/json');
        request.setBody(body);
        
        HttpResponse response = http.send(request);
        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());
        
        String respBody = response.getBody();
        if(String.isNotBlank(respBody)){
            Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
            if(dataMap != null && dataMap.containsKey('id')){
                wrap.runId = String.valueOf(dataMap.get('id'));
            }
        }

        return wrap;
    }
    
    public static AssistantWrapper getRunStatus(AssistantWrapper wrap){
        String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/threads/'+wrap.threadId+'/runs/'+wrap.runId+'?api-version='+wrap.aiModel.Version__c;
        
        Http http = new Http();
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'application/json');
        
        HttpResponse response = http.send(request);
        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());

        String respBody = response.getBody();
        if(String.isNotBlank(respBody)){
            Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
            if(dataMap != null && dataMap.containsKey('status')){
                wrap.runStatus = String.valueOf(dataMap.get('status'));
            }
        }

        return wrap;
    }
    
    public static AssistantWrapper getChatResponse(AssistantWrapper wrap){
        if(wrap.runStatus == 'completed'){
            String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/openai/threads/'+wrap.threadId+'/messages?api-version='+wrap.aiModel.Version__c;
            
            Http http = new Http();
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            
            HttpResponse response = http.send(request);
            //System.debug('body: '+response.getBody());
            //System.debug('status: '+response.getStatus());
            //System.debug('statusCode: '+response.getStatusCode());
            
            String respBody = response.getBody();
            if(String.isNotBlank(respBody)){
                Map<String, Object> mainMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                if(mainMap != null && mainMap.containsKey('data')){
                    List<Object> dataList = (List<Object>)mainMap.get('data');
                    if(dataList != null && !dataList.isEmpty()){
                        Map<String, Object> dataMap = (Map<String, Object>)dataList.get(0);
                        if(dataMap != null && dataMap.containsKey('content')){
                            List<Object> contentList = (List<Object>)dataMap.get('content');
                            if(contentList != null && !contentList.isEmpty()){
                                Map<String, Object> contentMap = (Map<String, Object>)contentList.get(0);
                                if(contentMap != null && contentMap.containsKey('text')){
                                    Map<String, Object> textMap = (Map<String, Object>)contentMap.get('text');
                                    if(textMap != null && textMap.containsKey('value')){
                                        wrap.assistantResponse = String.valueOf(textMap.get('value'));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return wrap;
    }
    
    public class AssistantWrapper{
        public String recordId{get;set;}
        public AI_Connection__c aiModel{get;set;}
        public List<String> cdIds{get;set;}
        public String extractedData{get;set;}
        public String promptCommand{get;set;}
        
        public String vectorStoreId{get;set;}
        public String uploadedFileId{get;set;}
        public String assistantId{get;set;}
        public String threadId{get;set;}
        public String messageId{get;set;}
        public String runId{get;set;}
        public String assistantResponse{get;set;}
        
        public String runStatus{get;set;}
    }
    
}