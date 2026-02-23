public with sharing class AIResponsesApiCalloutUtility {
    
    private static String FILE_FAILURE_PREFIX = 'File Upload Failed: ';
    private static String VECTOR_STORE_FAILURE_PREFIX = 'Vector Store Failed: ';
    private static String FILE_STATUS_FAILURE_PREFIX = 'File Status Check Failed: ';
    private static String RESPONSE_FAILURE_PREFIX = 'Response Failed: ';

    public static ResponseApiWrapper processFileRequest(ResponseApiWrapper wrap){
        try{
            wrap = AIResponsesApiCalloutUtility.uploadFiles(wrap);
            wrap = AIResponsesApiCalloutUtility.createVectorStore(wrap);
            wrap = AIResponsesApiCalloutUtility.addFileToVectorStore(wrap);
            return wrap;
        }catch(Exception ex){
            System.debug(ex.getStackTraceString());
            System.debug(ex.getMessage());
            throw new AIResponsesApiCalloutUtilityException(ex.getMessage());
        }
    }
     /**
     * Custom exception class for errors
     */
    public class AIResponsesApiCalloutUtilityException extends Exception {}
    
     /**
     * Upload multiple files sequentially
     */
    public static ResponseApiWrapper uploadFiles(ResponseApiWrapper wrap) {
        List<String> uploadedFileIds = new List<String>();
        for(String contentVersionId : wrap.cdIds){
            wrap = uploadSingleFile(wrap, contentVersionId);
        }

        return wrap;
    }
    
    public static ResponseApiWrapper addFileToVectorStore(ResponseApiWrapper wrap){

        for(String fileId : wrap.uploadedFileIds){
            String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/v1/vector_stores/'+wrap.vectorStoreId+'/files';

            String body = JSON.serialize(new Map<String, Object>{'file_id' => fileId});
            
            Http http = new Http();
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('POST');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('OpenAI-Beta', 'assistants=v2');
            
            request.setBody(body);
            HttpResponse response = http.send(request);
            if(response.getStatusCode() != 200 &&  response.getStatusCode() != 201) {
                throw new AIResponsesApiCalloutUtilityException(handleResponseError(wrap,response.getBody(),FILE_FAILURE_PREFIX));
            }
        }
        return wrap;
    }
    
   /**
     * Build multipart form data body -
     */
    private static String buildMultipartBodyBlob(String contentVersionId, String boundary) {
        // Get file information
        ContentVersion cv = [SELECT Title, FileExtension, PathOnClient 
                                FROM ContentVersion 
                                WHERE Id = :contentVersionId 
                                LIMIT 1];
        String fileName = String.isNotBlank(cv.PathOnClient) ? cv.PathOnClient : 
            (cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : ''));

        // Clean filename
        fileName = fileName.replaceAll('[^a-zA-Z0-9._-]', '_');

        // Build multipart sections with proper spacing
        String purposeSection = '--' + boundary + '\r\n' +
                'Content-Disposition: form-data; name="purpose"\r\n\r\n' +
                'assistants\r\n';

        String fileHeaderSection = '--' + boundary + '\r\n' +
                    'Content-Disposition: form-data; name="file"; filename="' + fileName + '"\r\n' +
                    'Content-Type: application/octet-stream\r\n\r\n';


        // Convert to hex to avoid base64
        String purposeHex = EncodingUtil.convertToHex(Blob.valueOf(purposeSection));
        String fileHeaderHex = EncodingUtil.convertToHex(Blob.valueOf(fileHeaderSection));

        // Combine all hex parts and convert back to blob
        String combinedHex = purposeHex + fileHeaderHex;
        return combinedHex;
        //return EncodingUtil.convertFromHex(combinedHex);
    }

    /**
     * Upload a single file to OpenAI - WORKING VERSION
     */
    private static ResponseApiWrapper uploadSingleFile(ResponseApiWrapper wrap, String contentVersionId) {
        try {
            String boundary = 'boundary_' + DateTime.now().getTime();
            String bodyBlob = buildMultipartBodyBlob(contentVersionId, boundary);
            String footerSection = '\r\n--' + boundary + '--\r\n';
            String footerHex = EncodingUtil.convertToHex(Blob.valueOf(footerSection));
            Blob bodyData = EncodingUtil.convertFromHex(bodyBlob + EncodingUtil.convertToHex([SELECT VersionData FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1][0].VersionData) + footerHex);
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:'+wrap.aiModel.Named_Credential__c+'/v1/files');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
            //System.debug('Heap Size: ' + Limits.getHeapSize() + ' bytes');
            //System.debug('Heap Size Limit: ' + Limits.getLimitHeapSize() + ' bytes');
            req.setBodyAsBlob(bodyData);
            bodyData = null;
            req.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            //System.debug(response.getBody());
            // Check for successful response codes
            if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                String respBody = response.getBody();
                if (String.isNotBlank(respBody)) {
                    try {
                        Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                        if (dataMap != null && dataMap.containsKey('id')) {
                            if (wrap.uploadedFileIds == null) {
                                wrap.uploadedFileIds = new List<String>();
                            }
                            wrap.uploadedFileIds.add(String.valueOf(dataMap.get('id')));
                        }
                    } catch (Exception jsonEx) {
                        throw new AIResponsesApiCalloutUtilityException(FILE_FAILURE_PREFIX + jsonEx.getMessage());
                    }
                }
            } else {
                throw new AIResponsesApiCalloutUtilityException(handleResponseError(wrap,response.getBody(),FILE_FAILURE_PREFIX));
            }
            
        } catch (Exception ex) {
            throw new AIResponsesApiCalloutUtilityException(FILE_FAILURE_PREFIX + ex.getMessage());
        }
        
        return wrap;
    }

    public static ResponseApiWrapper createVectorStore(ResponseApiWrapper wrap) {
        try {
            // Ensure we have uploaded file IDs
            if (wrap.uploadedFileIds == null || wrap.uploadedFileIds.isEmpty()) {
                throw new AIResponsesApiCalloutUtilityException('No uploaded file IDs available for vector store creation');
            }
            
            Map<String, Object> requestBody = new Map<String, Object>{
                'name' => wrap.recordId
            };
            
            String body = JSON.serialize(requestBody);
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:'+wrap.aiModel.Named_Credential__c+'/v1/vector_stores');
            request.setMethod('POST');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('OpenAI-Beta', 'assistants=v2');
            request.setBody(body);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                String respBody = response.getBody();
                if (String.isNotBlank(respBody)) {
                    try {
                        Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                        if (dataMap != null && dataMap.containsKey('id')) {
                            wrap.vectorStoreId = String.valueOf(dataMap.get('id'));
                        }
                    } catch (Exception jsonEx) {
                        throw new AIResponsesApiCalloutUtilityException( VECTOR_STORE_FAILURE_PREFIX + jsonEx.getMessage());
                    }
                }
            } else {
                throw new AIResponsesApiCalloutUtilityException(handleResponseError(wrap,response.getBody(),VECTOR_STORE_FAILURE_PREFIX));
            }
            
        } catch (Exception ex) {
            throw new AIResponsesApiCalloutUtilityException( VECTOR_STORE_FAILURE_PREFIX + ex.getMessage());
        }
        
        return wrap;
    }
    public static ResponseApiWrapper getFileStatus(ResponseApiWrapper wrap){
        try{
            // Initialize retry count if not set
            if(wrap.fileStatusRetryCount == null){
                wrap.fileStatusRetryCount = 0;
            }
            
            String endpoint = 'callout:'+wrap.aiModel.Named_Credential__c+'/v1/vector_stores/'+wrap.vectorStoreId+'/files/'+wrap.fileId;

            Http http = new Http();
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            
            HttpResponse response = http.send(request);
            System.debug(response.getBody());
            if(response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                String respBody = response.getBody();
                if (String.isNotBlank(respBody)) {
                    try {
                        Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                        if (dataMap != null && dataMap.containsKey('status')) {
                            wrap.fileStatus = String.valueOf(dataMap.get('status'));
                            if(wrap.fileStatus == 'in_progress')  {
                                // Check if retry limit has been reached
                                if(wrap.fileStatusRetryCount < 90){
                                    wrap.fileStatusRetryCount++;
                                    getFileStatus(wrap);
                                } else {
                                    return wrap;
                                }
                            }
                        }
                    } catch (Exception jsonEx) {
                        throw new AIResponsesApiCalloutUtilityException( FILE_STATUS_FAILURE_PREFIX + jsonEx.getMessage());
                    }
                }
            }else{
                throw new AIResponsesApiCalloutUtilityException(handleResponseError(wrap,response.getBody(),FILE_STATUS_FAILURE_PREFIX));
            }
        }catch(Exception ex){
            throw new AIResponsesApiCalloutUtilityException( FILE_STATUS_FAILURE_PREFIX + ex.getMessage());
        }
        return wrap;
    }
    public static ResponseApiWrapper createResponses(ResponseApiWrapper wrap) {
        try {
            Map<String, Object> tools = new Map<String, Object>{
                'type' => 'file_search',
                'vector_store_ids' => new List<String> {wrap.vectorStoreId},
                'max_num_results' => 20
            };

            String instructions = 'You are a helpful assistant. Retrieve the relevant answer from the vector store files based on the user query. Always prioritize the content of your most recent assistant response. When the user asks to “summarize it” or uses similar pronouns, assume they refer to that response first. Consult the uploaded records only if no prior answer exists or the user explicitly requests a fresh analysis of the records. If the records conflict with the last response, keep the response’s view and note the conflict.';

            if(String.isNotBlank(wrap.extractedData)){
                instructions += '\n\nAdditional Information:\n'+wrap.extractedData;
            }
            
            Map<String, Object> requestBody = new Map<String, Object>{
                'model' => wrap.aiModel.Model__c, 
                'tools' => new List<Object>{tools},
                'instructions' => instructions,
                'input' => wrap.promptCommand,
                'max_output_tokens' => Integer.valueOf(wrap.aiModel.Max_Tokens__c)
            };
            
            // Add reasoning_effort and text (verbosity) for GPT-5 and higher models
            if(isGpt5OrHigher(wrap.aiModel.Model__c)){
                try{
                    if(String.isNotBlank(wrap.aiModel.Additional_Parameters__c)){
                        Map<String, Object> additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(wrap.aiModel.Additional_Parameters__c);
                        
                        // Add reasoning_effort if present in Additional_Parameters__c
                        if(additionalParamMap != null && additionalParamMap.containsKey('reasoning')){
                            requestBody.put('reasoning', new Map<String, Object>{'effort' => String.valueOf(additionalParamMap.get('reasoning'))});
                        }else{
                            requestBody.put('reasoning', new Map<String, Object>{'effort' => 'low'});
                        }
                        
                        // Add text (verbosity) if present in Additional_Parameters__c
                        if(additionalParamMap != null && additionalParamMap.containsKey('verbosity')){
                            requestBody.put('text', new Map<String, Object>{'verbosity' => String.valueOf(additionalParamMap.get('verbosity'))});
                        }else{
                            requestBody.put('text', new Map<String, Object>{'verbosity' => 'low'});
                        }
                    }else{
                        requestBody.put('reasoning', new Map<String, Object>{'effort' => 'low'});
                        requestBody.put('text', new Map<String, Object>{'verbosity' => 'low'});
                    }
                }catch(Exception e){
                    System.debug('Error parsing Additional_Parameters__c: ' + e.getMessage());
                }
            }else{
                requestBody.put('temperature', wrap.aiModel.Temperature__c);
                requestBody.put('top_p', wrap.aiModel.Top_p__c);
            }
            
            String body = JSON.serialize(requestBody);
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:'+wrap.aiModel.Named_Credential__c+'/v1/responses');
            request.setMethod('POST');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            request.setBody(body);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            System.debug(response.getBody());
            
            //System.debug('Responses API Body: ' + response.getBody());
            
            if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                String respBody = response.getBody();
                wrap.response = respBody;
                try {
                    Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                    if (dataMap != null && dataMap.containsKey('id')) {
                        wrap.previousResponseId = String.valueOf(dataMap.get('id'));
                    }
                } catch (Exception jsonEx) {
                    throw new AIResponsesApiCalloutUtilityException( RESPONSE_FAILURE_PREFIX + jsonEx.getMessage());
                }
            } else {
                throw new AIResponsesApiCalloutUtilityException(handleResponseError(wrap,response.getBody(),RESPONSE_FAILURE_PREFIX));
            }
            
        } catch (Exception ex) {
            throw new AIResponsesApiCalloutUtilityException( RESPONSE_FAILURE_PREFIX + ex.getMessage());
        }
        
        return wrap;
    }
    private static String handleResponseError(ResponseApiWrapper wrap, String body, String context){
        try {
            Map<String, Object> errorMap = (Map<String, Object>)JSON.deserializeUntyped(body);
            if (errorMap.containsKey('error')) {
                Map<String, Object> errorDetails = (Map<String, Object>)errorMap.get('error');
                if(errorDetails.containsKey('message')){
                    return context + String.valueOf(errorDetails.get('message'));
                }else{
                    return context + ' Unexpected error received.';
                }
            }
        } catch (Exception ex) {
           return context + ex.getMessage();
        }
        return '';
    }
    public static ResponseApiWrapper deleteFileFromVectorStore(ResponseApiWrapper wrap) {
        try {
            // Ensure we have uploaded file IDs
            if (wrap.fileId == null || wrap.vectorStoreId == null) {
                throw new AIResponsesApiCalloutUtilityException('No file found to upload in vector store');
            }
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:'+wrap.aiModel.Named_Credential__c+'/v1/vector_stores/'+ wrap.vectorStoreId + '/files/'+ wrap.fileId);
            request.setMethod('DELETE');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                String respBody = response.getBody();
                wrap.response = respBody;
            } else {
                throw new AIResponsesApiCalloutUtilityException(handleResponseError(wrap,response.getBody(),VECTOR_STORE_FAILURE_PREFIX));
            }
            
        } catch (Exception ex) {
            throw new AIResponsesApiCalloutUtilityException( VECTOR_STORE_FAILURE_PREFIX + ex.getMessage());
        }
        
        return wrap;
    }
    
    /**
     * Checks if the model is GPT-5 or higher version.
     * Supports versions like: gpt-5, gpt-5.1, gpt-6, etc.
     * 
     * @param modelName The name of the AI model
     * @return Boolean True if model is GPT-5 or higher, false otherwise
     */
    private static Boolean isGpt5OrHigher(String modelName){
        if(String.isBlank(modelName)){
            return false;
        }
        
        // Convert to lowercase for case-insensitive comparison
        String model = modelName.toLowerCase().trim();
        
        // Check if it starts with 'gpt-' followed by a number
        if(model.startsWith('gpt-')){
            try{
                // Extract the major version number (e.g., '5' from 'gpt-5.1')
                String versionPart = model.substring(4); // Remove 'gpt-' prefix
                
                // Handle versions like 'gpt-5' or 'gpt-5.1'
                Integer majorVersion;
                if(versionPart.contains('.')){
                    majorVersion = Integer.valueOf(versionPart.split('\\.')[0]);
                }else{
                    majorVersion = Integer.valueOf(versionPart);
                }
                
                // Return true if version is 5 or higher
                return majorVersion >= 5;
            }catch(Exception e){
                // If parsing fails, return false
                System.debug('Error parsing model version: ' + e.getMessage());
                return false;
            }
        }
        
        return false;
    }
    
    public class ResponseApiWrapper{
        public String recordId{get;set;}
        public AI_Connection__c aiModel{get;set;}
        public String extractedData{get;set;}
        public String promptCommand{get;set;}
        public Set<String> cdIds{get;set;}
        public AI_Response__c aiResponse{get;set;}

        public List<String> uploadedFileIds{get;set;}
        public String vectorStoreId{get;set;}
        public String vectorFileCheckStatus{get;set;}
        public String responseId{get;set;}
        public String previousResponseId{get;set;}
        public String response{get;set;}
        public Set<String> errors{get;set;}
        public String fileId{get;set;}
        public String fileStatus{get;set;}
        public Integer fileStatusRetryCount{get;set;}
    }

}