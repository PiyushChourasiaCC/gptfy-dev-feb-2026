global class SampleRAGSyncFilesCreateVector implements Database.Batchable<SObject>, Database.AllowsCallouts{

    // Pass the ID of the file to process
    global Id contentDocumentId;
	global AI_RAG_Sync__c scheduler;
    // Constructor
    global SampleRAGSyncFilesCreateVector(Id contentDocumentId) {
        this.contentDocumentId = contentDocumentId;
    }

    // Start method: returns a single file to process
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Only the latest ContentVersion for this file
        return Database.getQueryLocator([
            SELECT Id, Title, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
        ]);
    }

    // Execute method: process the file, upload, store vector
    global void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        for(ContentVersion cv : scope) {
            try {
                // Set up the HTTP request for the vector API
                Map<String, Object> responseMap;
                String boundary = 'boundary_' + DateTime.now().getTime();
                String bodyBlob = buildMultipartBodyBlob(cv.Title, boundary);
                String footerHex = EncodingUtil.convertToHex(Blob.valueOf('\r\n--' + boundary + '--\r\n'));
                Blob bodyData = EncodingUtil.convertFromHex(bodyBlob + EncodingUtil.convertToHex(Blob.valueOf(String.valueOf(cv.VersionData))) + footerHex);
                
                HttpResponse resp = doCallout(
                    null,
                    bodyData,
                    new Map<String, String>{'Content-Type' => 'multipart/form-data; boundary=' + boundary}, 
                    'callout:'+scheduler.AI_Model_File_Upload__r.Named_Credential__c+'/v1/files',
                    'POST'
                );
                
                if(resp.getStatusCode() > 210){
                    throw new ChatGPTUtills.ApplicationException('Failed to upload file: '+resp.getBody());
                }else{
                    String respBody = resp.getBody();
                    if (String.isNotBlank(respBody)) {
                        try{
                            Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                            if(dataMap != null && dataMap.containsKey('id')) {
                                responseMap.put('fileId', dataMap.get('id'));
                            }
                        }catch (Exception jsonEx){
                            throw new ChatGPTUtills.ApplicationException('Failed to upload file: '+jsonEx.getMessage());
                        }
                    }
                }
                
                if(responseMap == null || !responseMap.containsKey('fileId')){
               		 throw new ChatGPTUtills.ApplicationException('No uploaded file IDs available for vector store creation');
            	}
                
                Map<String, Object> reqBody = new Map<String, Object>{
                'name' => String.valueOf(DateTime.now().getTime()),
                'file_ids' => new List<String>{String.valueOf(responseMap.get('fileId'))}
                };
                    
                String endPoint = 'callout:'+scheduler.AI_Model_Datastore_Import__r.Named_Credential__c+'/v1/vector_stores';
                if(String.isNotBlank(scheduler.External_Id__c)){
                    endPoint += '/'+scheduler.External_Id__c+'/files';
                    reqBody = new Map<String, Object>{'file_id' => String.valueOf(responseMap.get('fileId'))};
                }
                
                resp = doCallout(
                    JSON.serialize(reqBody), 
                    null,
                    new Map<String, String>{'Content-Type' => 'application/json', 'OpenAI-Beta' => 'assistants=v2'}, 
                    endPoint,
                    'POST'
                );

                // Optionally handle the API response, e.g., save vector to custom object
                // String vectorResult = res.getBody();
                // Handle/store the result as needed
            }
            catch(Exception ex) {
                System.debug('Error uploading file ' + cv.Id + ': ' + ex.getMessage());
                // Error handling, logging, etc.
            }
        }
    }
    
    
    private static HttpResponse doCallout(String requestBody, Blob requestBody_blob, Map<String, String> headers, String endpoint, String method){
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endPoint);
        req.setMethod(method);
        req.setTimeout(120000);
        for(String key : headers.keySet()){
            req.setHeader(key, headers.get(key));
        }
        if(String.isNotBlank(requestBody)){
            req.setBody(requestBody);
        }else if(requestBody_blob != null){
            req.setBodyAsBlob(requestBody_blob);
        }
        
        HttpResponse resp = http.send(req);
        
        //System.debug('status: '+resp.getStatus());
        //System.debug('statusCode: '+resp.getStatusCode());
        //System.debug('body: '+resp.getBody());
        
        return resp;
    }
    
    private static String buildMultipartBodyBlob(String fileName, String boundary) {
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

        String combinedHex = purposeHex + fileHeaderHex;
        return combinedHex;
    }

    // Finish method: post-processing if required
    global void finish(Database.BatchableContext bc) {
        // Notification, summary logging, or other tasks after batch completes
        System.debug('Finished processing file for ContentDocumentId: ' + contentDocumentId);
    }
    
    
}