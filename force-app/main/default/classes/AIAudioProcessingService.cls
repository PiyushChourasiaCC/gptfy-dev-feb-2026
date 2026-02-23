public with sharing class AIAudioProcessingService {
	
    public static void processFile(ProcessAudioWrapper wrap){
        //try{
            wrap.formattedFileName = wrap.cv.Id;
            wrap.max_pollingCounter = 5;
            if(wrap.audioConfig.Maximum_Polling_Counter__c != null && wrap.audioConfig.Maximum_Polling_Counter__c >= 0){
                wrap.max_pollingCounter = (Integer)wrap.audioConfig.Maximum_Polling_Counter__c;
            }
            
            wrap.pollingCounter = 0;
            if(wrap.audioConfig.Async_Request__c){
                processAsyncRequest(wrap);
            }else{
                processSyncRequest(wrap);
            }
        //}catch(Exception e){
          //  throw new ChatGPTUtills.ApplicationException('Error in processing audio file: '+e.getMessage());
        //}
    }
    
    public static void processSyncRequest(ProcessAudioWrapper wrap){
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        // v2/7290 : GPTfy Voice Enhancements
        if(String.isNotBlank(wrap.audioConfig.AI_Model__r.Connector_Class__c)){
                Type impl = Type.forName('', wrap.audioConfig.AI_Model__r.Connector_Class__c);
                AIAuthenticationInterface obj = (AIAuthenticationInterface)impl.newInstance();
                request = obj.getAuthenticatedRequest(wrap.audioConfig.AI_Model__r);
        }else if(String.isNotBlank(wrap.audioConfig.AI_Model__r.Named_Credential__c)){
            String endPoint = 'callout:'+wrap.audioConfig.AI_Model__r.Named_Credential__c+wrap.audioConfig.AI_Model__r.EndPoint_URL__c;
            request.setEndpoint(endPoint);
        }
        
        request.setMethod('POST');
        request.setTimeout(120000);
        HttpResponse response;
        if(String.isNotBlank(wrap.audioConfig.AI_Model__r.Processing_Class__c)){
                Type impl = Type.forName('', wrap.audioConfig.AI_Model__r.Processing_Class__c);
                AIVoiceProcessingInterface obj = (AIVoiceProcessingInterface)impl.newInstance();
            	VoiceProcessingWrapper vWrap = new VoiceProcessingWrapper(request,wrap.audioConfig.AI_Model__r,wrap.cv,wrap.isIOS);
                response = obj.getProcessedResponse(vWrap);
        }else{
            if(String.isNotBlank(wrap.audioConfig.AI_Model__r.Model__c) && wrap.audioConfig.AI_Model__r.Model__c.containsIgnoreCase(AIConstants.GCP_CHIP_MODEL)){
                request.setHeader('Content-Type', 'application/json');
                Map<String, Object> requestBody;
                if(wrap.isIOS){
                    requestBody = new Map<String, Object>{
                        'config' => new Map<String, Object>{
                            'languageCode' => 'en-US', 'model' => 'default','enableAutomaticPunctuation' => true, 'encoding' => 'WEBM_OPUS', 'sampleRateHertz' => 48000,
                            'enableSeparateRecognitionPerChannel' => true, 'audioChannelCount' => 2
                        },
                        'audio' => new Map<String, Object>{'content' => EncodingUtil.base64Encode(wrap.cv.VersionData)}
                    };
                }else{
                    requestBody = new Map<String, Object>{
                        'config' => new Map<String, Object>{
                            'languageCode' => 'en-US', 'model' => 'default', 'encoding' => 'WEBM_OPUS','enableAutomaticPunctuation' => true, 'sampleRateHertz' => 48000
                        },
                        'audio' => new Map<String, Object>{'content' => EncodingUtil.base64Encode(wrap.cv.VersionData)}
                    };  
                }
                //System.debug(requestBody);
                request.setBody(JSON.serialize(requestBody));
                
            }else if(String.isNotBlank(wrap.audioConfig.AI_Model__r.Model__c) && wrap.audioConfig.AI_Model__r.Model__c.containsIgnoreCase(AIConstants.WHISPER_VOICE_MODEL)){
                String boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
                Blob combinedBlob = generateMultipartBody(wrap, boundary);
                request.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
                request.setBodyAsBlob(combinedBlob);
            }
            response = http.send(request);
        }
        
        //System.debug(response.getBody());
        if(String.isNotBlank(response.getBody())){
            wrap.transcript = parseResponse(response.getBody());
            createContentDocumentLink(wrap);
            updateContentVersion(wrap);
            insertAIResponse(wrap);
        }
    }
    
    public static void processAsyncRequest(ProcessAudioWrapper wrap){
        Map<String, Object> authDetails = JWTAuthenticationService.getAuthenticationDetails(wrap.audioConfig.AI_Model__r);
        if(authDetails != null && authDetails.containsKey('accessToken')){
            wrap.authToken = String.valueOf(authDetails.get('accessToken'));
        }
        wrap = generateFileUrl(wrap);
        
        if(String.isNotBlank(wrap.fileUrl)){
            wrap = submitFileForProcessing(wrap);
            if(String.isNotBlank(wrap.asyncJobId)){
                performPolling(wrap);
            }
        }
    }
    
    public static ProcessAudioWrapper generateFileUrl(ProcessAudioWrapper wrap){
        if(wrap.audioConfig.AI_Model_File_Upload__c != null && String.isNotBlank(wrap.audioConfig.AI_Model_File_Upload__r.Model__c) && wrap.audioConfig.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.GCP_CHIP_MODEL)){
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setMethod('POST');
            request.setTimeout(120000);
            
            Map<String, Object> additionalParamMap;
            if(String.isNotBlank(wrap.audioConfig.AI_Model_File_Upload__r.Additional_Parameters__c)){
                try{
                    additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(wrap.audioConfig.AI_Model_File_Upload__r.Additional_Parameters__c);
                }catch(Exception e){}
            }
            
            String bucketName = additionalParamMap != null && additionalParamMap.containsKey('bucketName') ? String.valueOf(additionalParamMap.get('bucketName')) : '';
            String endpoint = 'callout:'+wrap.audioConfig.AI_Model_File_Upload__r.Named_Credential__c+wrap.audioConfig.AI_Model_File_Upload__r.EndPoint_URL__c+bucketName+'/o?uploadType=media&name='+wrap.formattedFileName;

            request.setHeader('Content-Type', 'application/octet-stream');
            request.setHeader('Content-Length', String.valueOf(wrap.cv.VersionData.size()));
            request.setBodyAsBlob(wrap.cv.VersionData);
            request.setEndpoint(endpoint);
       
            HttpResponse res = http.send(request);
            //System.debug('body: '+res.getBody());
            //System.debug('status: '+res.getStatus());
            //System.debug('statusCode: '+res.getStatusCode());
            if(res.getStatusCode() >= 200 && res.getStatusCode() <= 205){
                if(String.isNotBlank(res.getBody())){
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    if(responseMap != null && !responseMap.isEmpty()){
                        if(responseMap.containsKey('mediaLink')){
                            wrap.fileUrl = String.valueOf(responseMap.containsKey('mediaLink'));
                        }
                    }
                }
            }else{
                throw new ChatGPTUtills.ApplicationException(res.getBody());
            }
        }else if(wrap.audioConfig.AI_Model_File_Upload__c != null && String.isNotBlank(wrap.audioConfig.AI_Model_File_Upload__r.Model__c) && wrap.audioConfig.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.KENSHO_VOICE_MODEL)){
            wrap.fileUrl = generateSalesforcePublicUrl(wrap);
        }
        return wrap;
    }
    
    public static ProcessAudioWrapper submitFileForProcessing(ProcessAudioWrapper wrap){
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        
        String endpoint;
        String requestBody;
        if(String.isNotBlank(wrap.audioConfig.AI_Model__r.Model__c) && wrap.audioConfig.AI_Model__r.Model__c.containsIgnoreCase(AIConstants.GCP_CHIP_MODEL)){
            Map<String, Object> additionalParamMap;
            if(String.isNotBlank(wrap.audioConfig.AI_Model__r.Additional_Parameters__c)){
                try{
                    additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(wrap.audioConfig.AI_Model__r.Additional_Parameters__c);
                }catch(Exception e){}
            }
            
            String bucketName = additionalParamMap != null && additionalParamMap.containsKey('bucketName') ? String.valueOf(additionalParamMap.get('bucketName')) : '';
            endpoint = 'callout:'+wrap.audioConfig.AI_Model__r.Named_Credential__c+wrap.audioConfig.AI_Model__r.EndPoint_URL__c;
            
            Map<String, Object> requestBodyMap = new Map<String, Object>{
                'config' => new Map<String, Object>{'encoding' => 'MP3', 'languageCode' => 'en-US', 'sampleRateHertz' => 48000},
                'audio' => new Map<String, Object>{'uri' => 'gs://'+bucketName+'/'+wrap.formattedFileName}
            };
            requestBody = JSON.serialize(requestBodyMap);   
        }else if(String.isNotBlank(wrap.audioConfig.AI_Model__r.Model__c) && wrap.audioConfig.AI_Model__r.Model__c.containsIgnoreCase(AIConstants.KENSHO_VOICE_MODEL)){
            endpoint = 'callout:'+wrap.audioConfig.AI_Model__r.Named_Credential__c+wrap.audioConfig.AI_Model__r.EndPoint_URL__c;
            req.setHeader('Authorization', 'Bearer '+wrap.authToken);
            req.setHeader('Content-Type', 'application/json'); 
            Map<String, Object> requestBodyMap = new Map<String, Object>{
                'media_url' => wrap.fileUrl
            };
            requestBody = JSON.serialize(requestBodyMap);   
        }
        //System.debug('endpoint: '+endpoint);
        //System.debug('requestBody: '+requestBody);
        req.setBody(requestBody);
        req.setEndpoint(endpoint); 
        
        Http http = new Http();
        HttpResponse res = http.send(req); 
        
        //System.debug('body: '+res.getBody());
        //System.debug('status: '+res.getStatus());
        //System.debug('statusCode: '+res.getStatusCode());
        if(res.getStatusCode() >= 200 && res.getStatusCode() <= 205){
            if(String.isNotBlank(res.getBody())){
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                if(responseMap != null && !responseMap.isEmpty()){
                    if(responseMap.containsKey('name')){
                        wrap.asyncJobId = String.valueOf(responseMap.get('name'));
                    }else if(responseMap.containsKey('transcription_id')){
                        wrap.asyncJobId = String.valueOf(responseMap.get('transcription_id'));
                    }
                }
            }
        }else{
            throw new ChatGPTUtills.ApplicationException(res.getBody());
        }
        return wrap;
    }

    public static ProcessAudioWrapper performPolling(ProcessAudioWrapper wrap){
        if(wrap.pollingCounter == null){
            wrap.pollingCounter = 0;
        }
        
        AI_Security_Audit_Detail__c detail = new AI_Security_Audit_Detail__c();
        detail.Type__c = AIConstants.SECURITY_AUDIT_DETAIL_TYPE_POLLING;
        try{
            wrap = performPollingCallout(wrap);
            detail.Status__c = AIConstants.SECURITY_AUDIT_DETAIL_STATUS_COMPLETED;
            detail.Message__c = wrap.pollingResponse;
        }catch(Exception e){
            detail.Status__c = AIConstants.SECURITY_AUDIT_DETAIL_STATUS_ERRORED;
            detail.Message__c = e.getMessage();
        }
        wrap.detail = detail;
        
        if(wrap.pollingCounter == 0){
            createContentDocumentLink(wrap);
            insertAIResponse(wrap);
        }
        insertAIResponseDetail(wrap);
        
        wrap.pollingCounter += 1;
        
        if(String.isNotBlank(wrap.transcript)){
            updateContentVersion(wrap);
            updateAIResponse(wrap);
        }else{
        	if(wrap.pollingCounter < wrap.max_pollingCounter){
                Integer delay = 1;
                if(wrap.audioConfig != null && wrap.audioConfig.Polling_Timeframe__c != null){
                    delay = (Integer)wrap.audioConfig.Polling_Timeframe__c;
                }
                
                if(wrap.pollingCounter == 1){
                    AsyncOptions asyncOptions = new AsyncOptions();
                    asyncOptions.MaximumQueueableStackDepth = wrap.max_pollingCounter + 1;
                    asyncOptions.MinimumQueueableDelayInMinutes = delay;
                    AIPollingService sch = new AIPollingService(wrap);
                    Id enqueueJobId = System.enqueueJob(sch, asyncOptions); 
                }else{
                    AsyncOptions asyncOptions = new AsyncOptions();
                    asyncOptions.MinimumQueueableDelayInMinutes = delay;
                    AIPollingService sch = new AIPollingService(wrap);
                    Id enqueueJobId = System.enqueueJob(sch, asyncOptions); 
                }
            }else{
                updateContentVersion(wrap);
                updateAIResponse(wrap);
            }
        }
        return wrap;
    }
    
    public static ProcessAudioWrapper performPollingCallout(ProcessAudioWrapper wrap){
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setTimeout(120000);
        String endpoint;
        if(wrap.audioConfig.AI_Model_Polling__c != null && String.isNotBlank(wrap.audioConfig.AI_Model_Polling__r.Model__c) && wrap.audioConfig.AI_Model_Polling__r.Model__c.containsIgnoreCase(AIConstants.GCP_CHIP_MODEL)){
            endpoint = 'callout:'+wrap.audioConfig.AI_Model_Polling__r.Named_Credential__c+wrap.audioConfig.AI_Model_Polling__r.EndPoint_URL__c+wrap.asyncJobId;
        }else if(wrap.audioConfig.AI_Model_Polling__c != null && String.isNotBlank(wrap.audioConfig.AI_Model_Polling__r.Model__c) && wrap.audioConfig.AI_Model_Polling__r.Model__c.containsIgnoreCase(AIConstants.KENSHO_VOICE_MODEL)){
            endpoint = 'callout:'+wrap.audioConfig.AI_Model_Polling__r.Named_Credential__c+wrap.audioConfig.AI_Model_Polling__r.EndPoint_URL__c+wrap.asyncJobId;
            request.setHeader('Authorization', 'Bearer '+wrap.authToken);
        }
        request.setEndpoint(endPoint);
        HttpResponse res = http.send(request);
        //System.debug('body: '+res.getBody());
        //System.debug('status: '+res.getStatus());
        //System.debug('statusCode: '+res.getStatusCode());
        
        wrap.pollingResponse = '';
        if(res.getStatusCode() >= 200 && res.getStatusCode() <= 205){
            wrap.transcript = parseResponse(res.getBody());
            wrap.pollingResponse = res.getBody();
        }else{
            throw new ChatGPTUtills.ApplicationException(res.getBody());
        }
        return wrap;
    }
    
    public static void createContentDocumentLink(ProcessAudioWrapper wrap){
        ContentDocumentLink contentlink = new ContentDocumentLink();
        contentlink.LinkedEntityId = wrap.recordId;
        contentlink.ShareType = 'V';
        contentlink.ContentDocumentId = wrap.cv.ContentDocumentId;
        contentlink.Visibility = 'AllUsers'; 
        FLSCheck.getInstance().insertDML(new List<ContentDocumentLink>{contentlink});
    }
    
    public static void updateContentVersion(ProcessAudioWrapper wrap){
        wrap.cv.Transcript__c = wrap.transcript;
        FLSCheck.getInstance().updateDML(new List<ContentVersion>{wrap.cv});
        
        if(String.isNotBlank(wrap.transcript)){
            AsyncOptions asyncOptions = new AsyncOptions();
            asyncOptions.MinimumQueueableDelayInMinutes = 1;
            AIVoicePromptCalloutService sch = new AIVoicePromptCalloutService(wrap);
            Id enqueueJobId = System.enqueueJob(sch, asyncOptions); 
        }
    }
    
    public static void insertAIResponse(ProcessAudioWrapper wrap){
        AI_Response__c aiResponse = new AI_Response__c();
        aiResponse.Record_Id__c = wrap.cv.Id;
        aiResponse.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
        if(!wrap.audioConfig.Async_Request__c){
            if(String.isNotBlank(wrap.transcript)){
                aiResponse.AI_Processed_Data_No_PII__c = wrap.transcript;
                aiResponse.AI_Processed_Data_PII_Added__c = wrap.transcript;
                aiResponse.Status__c = AIConstants.RESP_STATUS_PROCESSED;
            }else{
                aiResponse.Status__c = AIConstants.RESP_STATUS_ERROR;
                aiResponse.Message__c = 'Response was not generated, please try again.';
            }
        }else{
            if(String.isNotBlank(wrap.transcript)){
            	aiResponse.Status__c = AIConstants.RESP_STATUS_PROCESSED;
            }
        }
        wrap.aiResponse = (AI_Response__c)FLSCheck.getInstance().insertDML(new List<AI_Response__c>{aiResponse}).get(0);
    }
    
    public static void insertAIResponseDetail(ProcessAudioWrapper wrap){
        if(wrap.detail != null){
            wrap.detail.AI_Security_Audit__c = wrap.aiResponse.Id;
            FLSCheck.getInstance().insertDML(new List<AI_Security_Audit_Detail__c>{wrap.detail});
        }
    }
    
    public static void updateAIResponse(ProcessAudioWrapper wrap){
        wrap.aiResponse.AI_Processed_Data_No_PII__c = wrap.transcript;
        wrap.aiResponse.AI_Processed_Data_PII_Added__c = wrap.transcript;
        if(String.isNotBlank(wrap.transcript)){
            wrap.aiResponse.Status__c = AIConstants.RESP_STATUS_PROCESSED;
        }else{
            wrap.aiResponse.Status__c = AIConstants.RESP_STATUS_ERROR;
            wrap.aiResponse.Message__c = 'Response was not generated, please try again.';
        }
        wrap.aiResponse = (AI_Response__c)FLSCheck.getInstance().updateDML(new List<AI_Response__c>{wrap.aiResponse}).get(0);
    }
    
    public static String parseResponse(String responseBody){
        String descp = '';
        Map<String, Object> mainMap = (Map<String,Object>)JSON.deserializeUntyped(responseBody);
        if(mainMap.containsKey('response') && mainMap.get('response') != null){
            Map<String, Object> dataMap = (Map<String, Object>)mainMap.get('response');
            if(dataMap.containsKey('results') && dataMap.get('results') != null){
                List<Object> resultList = (List<Object>)dataMap.get('results');
                if(resultList != null && !resultList.isEmpty()){
                    for(Object result : resultList){
                        Map<String, Object> resultMap = (Map<String, Object>) result;
                        if(resultMap != null && resultMap.containsKey('alternatives')){
                            List<Object> altList = (List<Object>)resultMap.get('alternatives');
                             if(resultMap.containsKey('channelTag') && resultMap.get('channelTag') != NULL){
                                Integer channelTag = (Integer)resultMap.get('channelTag');
                                if(channelTag != null && channelTag == 1){
                                		if(altList != null && !altList.isEmpty()){
                                            Map<String, Object> altMap = (Map<String, Object>)altList.get(0);
                                            if(altMap != null && altMap.containsKey('transcript')){
                                                descp += String.valueOf(altMap.get('transcript'));
                                            }
                                        }
                            	}
                            }else{
                                if(altList != null && !altList.isEmpty()){
                                    Map<String, Object> altMap = (Map<String, Object>)altList.get(0);
                                    if(altMap != null && altMap.containsKey('transcript')){
                                        descp += String.valueOf(altMap.get('transcript'));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }else if(mainMap.containsKey('results') && mainMap.get('results') != null){
            List<Object> resultList = (List<Object>)mainMap.get('results');
            if(resultList != null && !resultList.isEmpty()){
                for(Object result : resultList){
                    Map<String, Object> resultMap = (Map<String, Object>) result;
                    if(resultMap != null && resultMap.containsKey('alternatives')){
                        List<Object> altList = (List<Object>)resultMap.get('alternatives');
                        if(resultMap.containsKey('channelTag') && resultMap.get('channelTag') != NULL){
                            Integer channelTag = (Integer)resultMap.get('channelTag');
                            if(channelTag != null && channelTag == 1){
                                if(altList != null && !altList.isEmpty()){
                                    Map<String, Object> altMap = (Map<String, Object>)altList.get(0);
                                    if(altMap != null && altMap.containsKey('transcript')){
                                        descp += String.valueOf(altMap.get('transcript'));
                                    }
                                }
                            }
                        }else{
                            if(altList != null && !altList.isEmpty()){
                                Map<String, Object> altMap = (Map<String, Object>)altList.get(0);
                                if(altMap != null && altMap.containsKey('transcript')){
                                    descp += String.valueOf(altMap.get('transcript'));
                                }
                            }
                        }
                    }
                }
            }
        }else if(mainMap.containsKey('transcript') && mainMap.get('transcript') != null){
            descp = String.valueOf(mainMap.get('transcript'));
        }else if(mainMap.containsKey('text') && mainMap.get('text') != null){
            descp = String.valueOf(mainMap.get('text'));
        }
        return descp;
    }
    
    public static String generateSalesforcePublicUrl(ProcessAudioWrapper wrap){
        HttpRequest req = new HttpRequest();
        
        String namespace = AIConstants.NAMESPACE;
        if(String.isNotBlank(namespace) && namespace.endsWithIgnoreCase('__')){
            namespace = namespace.removeEndIgnoreCase('__');
        }
        
        String endpoint = 'callout:'+wrap.audioConfig.AI_Model_File_Upload__r.Named_Credential__c+'/services/apexrest/';
        if(String.isNotBlank(namespace)){
            endpoint += namespace+'/';
        }
        endpoint += 'v1/generatePublicURL';
        
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        
        AISalesforcePublicURLGeneratorService.RequestWrapper req_wrap = new AISalesforcePublicURLGeneratorService.RequestWrapper();
        req_wrap.cvId = wrap.cv.Id;
        
        req.setBody(JSON.serialize(req_wrap));
        Http http = new Http();
        HttpResponse res = http.send(req);

        //System.debug('p_body: '+res.getBody());
        //System.debug('p_status: '+res.getStatus());
        //System.debug('p_statusCode: '+res.getStatusCode());

        if(res.getStatusCode() == 200 && String.isNotBlank(res.getBody())){
            Map<String, Object> mainMap = (Map<String,Object>)JSON.deserializeUntyped(res.getBody());
            if(mainMap != null && mainMap.containsKey('fileUrl')){
                return String.valueOf(mainMap.get('fileUrl'));
            }
        }
        return null;
    }
    
    public class ProcessAudioWrapper{
        @AuraEnabled public AI_Voice_Configuration__c audioConfig{get;set;}
        @AuraEnabled public ContentVersion cv{get;set;}
        @AuraEnabled public AI_Response__c aiResponse{get;set;}
        @AuraEnabled public AI_Security_Audit_Detail__c detail{get;set;}
        @AuraEnabled public String recordId{get;set;}
        @AuraEnabled public String formattedFileName{get;set;}
        @AuraEnabled public String authToken{get;set;}
        @AuraEnabled public String fileUrl{get;set;}
        @AuraEnabled public String asyncJobId{get;set;}
        @AuraEnabled public String transcript{get;set;}
        @AuraEnabled public String pollingResponse{get;set;}
        @AuraEnabled public Boolean isIOS{get;set;}
        @AuraEnabled public Integer pollingCounter{get;set;}
        @AuraEnabled public Integer max_pollingCounter{get;set;}
    }
    
    public static Blob generateMultipartBody(ProcessAudioWrapper wrap, String boundary){
        String body = '';
        body += '--' + boundary + '\r\n';
        body += 'Content-Disposition: form-data; name="model"\r\n\r\n';
        body += wrap.audioConfig.AI_Model__r.Model__c+'\r\n';
        body += '--' + boundary + '\r\n';
        body += 'Content-Disposition: form-data; name="file"; filename="' + wrap.cv.Title + '.mp3' + '"\r\n';
        body += 'Content-Type: application/octet-stream\r\n\r\n';
        Blob headerBlob = Blob.valueOf(body);
        Blob footerBlob = Blob.valueOf('\r\n--' + boundary + '--');
        
        Blob combinedBlob = concatenateBlobs(new List<Blob>{
            headerBlob,
            wrap.cv.VersionData,
            footerBlob
        });
        return combinedBlob;
    }
    
    private static Blob concatenateBlobs(List<Blob> blobs) {
        List<String> hexStrings = new List<String>();
        for(Blob b : blobs){
            hexStrings.add(EncodingUtil.convertToHex(b));
        }
        String combinedHex = String.join(hexStrings, '');
        return EncodingUtil.convertFromHex(combinedHex);
    }

}