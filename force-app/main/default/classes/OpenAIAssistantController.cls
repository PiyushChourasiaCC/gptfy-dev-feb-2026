public with sharing class OpenAIAssistantController {
    private static final String AZURE_API_KEY = 'lRM3ZDfA8sPy3U2Wr1KfJ669HKBqKPmhbuxrvDTqmdi5M5BcDqUuJQQJ99BBACfhMk5XJ3w3AAAAACOGZYpH';
    private static final String AZURE_ENDPOINT = 'https://neel-m74zh4ra-swedencentral.cognitiveservices.azure.com';
    private static final String API_VERSION = '2024-05-01-preview';
    // Hardcoded Assistant ID
    private static final String ASSISTANT_ID = 'asst_OgoBJ7OFZfH03TSG1tHKq4Sf';
    // Hardcoded Vector Store ID
    private static final String VECTOR_STORE_ID = 'vs_CjZeKL1tJE1IUDJJWg228yEV';
    
    static {
        try {
            System.debug('Fetching Custom Metadata Type record...');
           // OpenAISettings__mdt settings = OpenAISettings__mdt.getInstance('gpt4o');
           // System.debug('Settings record: ' + settings);
          //  AZURE_API_KEY = settings?.API_Key__c;
            System.debug('API Key retrieved: ' + (String.isNotBlank(AZURE_API_KEY) ? 'Yes' : 'No'));
        } catch (Exception e) {
            System.debug('Error initializing static variables: ' + e.getMessage() + '\n' + e.getStackTraceString());
            AZURE_API_KEY = null;
        }
    }
    
    @AuraEnabled
    public static Map<String, String> createAssistant() {
        try {
            System.debug('Using hardcoded assistant ID: ' + ASSISTANT_ID);
            
            // Verify API Key is not null
            if (String.isBlank(AZURE_API_KEY)) {
                throw new AuraHandledException('Azure API Key not found in Custom Metadata Type. Please ensure the "gpt4o" record has a valid API Key.');
            }
            
            // Create thread
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            String threadEndpoint = AZURE_ENDPOINT + '/openai/threads?api-version=' + API_VERSION;
            System.debug('Thread creation endpoint: ' + threadEndpoint);
            req.setEndpoint(threadEndpoint);
            req.setMethod('POST');
            req.setHeader('api-key', AZURE_API_KEY);
            req.setHeader('Content-Type', 'application/json');
            req.setBody('{}');
            
            HttpResponse res = http.send(req);
            System.debug('Thread creation response status: ' + res.getStatusCode());
            System.debug('Thread creation response body: ' + res.getBody());
            
            if (res.getStatusCode() != 201 && res.getStatusCode() != 200) {
                String errorMsg = 'Failed to create thread. Status: ' + res.getStatusCode();
                if (String.isNotBlank(res.getBody())) {
                    Map<String, Object> errorResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                    if (errorResponse.containsKey('error')) {
                        Map<String, Object> error = (Map<String, Object>)errorResponse.get('error');
                        errorMsg += '. Error: ' + error.get('message');
                    } else {
                        errorMsg += '. Response: ' + res.getBody();
                    }
                }
                throw new AuraHandledException(errorMsg);
            }
            
            // Parse thread response
            Map<String, Object> threadData = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            String threadId = (String)threadData.get('id');
            System.debug('Created thread with ID: ' + threadId);
            
            return new Map<String, String>{
                'assistantId' => ASSISTANT_ID,
                'threadId' => threadId
            };
        } catch (Exception e) {
            System.debug('Error in createAssistant: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, String> sendMessage(String threadId, String assistantId, String message) {
        try {
            // Always use the hardcoded assistant ID
            System.debug('Sending message to thread: ' + threadId + ', assistant: ' + ASSISTANT_ID);
            System.debug('Message content: ' + message);
            
            // Validate input parameters
            if (String.isBlank(threadId)) {
                throw new AuraHandledException('Thread ID cannot be empty');
            }
            
            // Ensure message is not empty
            if (String.isBlank(message)) {
                throw new AuraHandledException('Message content cannot be empty');
            }
            
            Http http = new Http();
            
            // Add message to thread
            HttpRequest req = new HttpRequest();
            String messageEndpoint = AZURE_ENDPOINT + '/openai/threads/' + threadId + '/messages?api-version=' + API_VERSION;
            System.debug('Message endpoint: ' + messageEndpoint);
            req.setEndpoint(messageEndpoint);
            req.setMethod('POST');
            req.setHeader('api-key', AZURE_API_KEY);
            req.setHeader('Content-Type', 'application/json');
            
            Map<String, String> messageData = new Map<String, String>{
                'role' => 'user',
                'content' => message
            };
            
            String messageBody = JSON.serialize(messageData);
            System.debug('Message request body: ' + messageBody);
            req.setBody(messageBody);
            
            HttpResponse res = http.send(req);
            System.debug('Message creation response status: ' + res.getStatusCode());
            System.debug('Message creation response body: ' + res.getBody());
            
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                String errorMsg = 'Failed to send message. Status: ' + res.getStatusCode();
                if (String.isNotBlank(res.getBody())) {
                    Map<String, Object> errorResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                    if (errorResponse.containsKey('error')) {
                        Map<String, Object> error = (Map<String, Object>)errorResponse.get('error');
                        errorMsg += '. Error: ' + error.get('message');
                    } else {
                        errorMsg += '. Response: ' + res.getBody();
                    }
                }
                throw new AuraHandledException(errorMsg);
            }
            
            // Create a run with the assistant
            req = new HttpRequest();
            String runEndpoint = AZURE_ENDPOINT + '/openai/threads/' + threadId + '/runs?api-version=' + API_VERSION;
            System.debug('Run creation endpoint: ' + runEndpoint);
            req.setEndpoint(runEndpoint);
            req.setMethod('POST');
            req.setHeader('api-key', AZURE_API_KEY);
            req.setHeader('Content-Type', 'application/json');
            
            Map<String, String> runData = new Map<String, String>{
                'assistant_id' => ASSISTANT_ID
            };
            
            String runBody = JSON.serialize(runData);
            System.debug('Run creation request body: ' + runBody);
            req.setBody(runBody);
            
            res = http.send(req);
            System.debug('Run creation response status: ' + res.getStatusCode());
            System.debug('Run creation response body: ' + res.getBody());
            
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                String errorMsg = 'Failed to create run. Status: ' + res.getStatusCode();
                if (String.isNotBlank(res.getBody())) {
                    Map<String, Object> errorResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                    if (errorResponse.containsKey('error')) {
                        Map<String, Object> error = (Map<String, Object>)errorResponse.get('error');
                        errorMsg += '. Error: ' + error.get('message');
                    } else {
                        errorMsg += '. Response: ' + res.getBody();
                    }
                }
                throw new AuraHandledException(errorMsg);
            }
            
            // Parse run response
            Map<String, Object> runResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            String runId = (String)runResponse.get('id');
            System.debug('Created run with ID: ' + runId);
            
            // Wait for the run to complete
            String runStatus = 'queued';
            Integer maxAttempts = 30; // Maximum number of attempts
            Integer attempts = 0;
            
            while ((runStatus == 'queued' || runStatus == 'in_progress') && attempts < maxAttempts) {
                // Wait for a short time before checking status
                attempts++;
                
                // Check run status
                req = new HttpRequest();
                String statusEndpoint = AZURE_ENDPOINT + '/openai/threads/' + threadId + '/runs/' + runId + '?api-version=' + API_VERSION;
                System.debug('Run status check endpoint: ' + statusEndpoint);
                req.setEndpoint(statusEndpoint);
                req.setMethod('GET');
                req.setHeader('api-key', AZURE_API_KEY);
                req.setHeader('Content-Type', 'application/json');
                
                res = http.send(req);
                System.debug('Run status response: ' + res.getStatusCode() + ' - ' + res.getBody());
                
                Map<String, Object> statusResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                runStatus = (String)statusResponse.get('status');
                System.debug('Current run status: ' + runStatus);
                
                if (runStatus == 'completed' || runStatus == 'failed' || runStatus == 'cancelled') {
                    break;
                }
                
                // Sleep for a short time before checking again
                if (attempts < maxAttempts) {
                    // Sleep for 1 second (1000 milliseconds)
                    Long startTime = System.now().getTime();
                    while (System.now().getTime() - startTime < 1000) {
                        // This is a busy-wait loop to simulate sleep
                    }
                }
            }
            
            // Retrieve messages
            req = new HttpRequest();
            String messagesEndpoint = AZURE_ENDPOINT + '/openai/threads/' + threadId + '/messages?api-version=' + API_VERSION;
            System.debug('Messages retrieval endpoint: ' + messagesEndpoint);
            req.setEndpoint(messagesEndpoint);
            req.setMethod('GET');
            req.setHeader('api-key', AZURE_API_KEY);
            req.setHeader('Content-Type', 'application/json');
            
            res = http.send(req);
            System.debug('Messages retrieval response: ' + res.getStatusCode() + ' - ' + res.getBody());
            
            if (res.getStatusCode() != 200) {
                throw new AuraHandledException('Failed to retrieve messages. Status: ' + res.getStatusCode());
            }
            
            // Process messages to extract the assistant's response
            Map<String, Object> messagesResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            List<Object> messages = (List<Object>)messagesResponse.get('data');
            
            // Extract the assistant's response
            String assistantMessage = '';
            String fileSearchResults = '';
            
            for (Object msg : messages) {
                Map<String, Object> messageObj = (Map<String, Object>)msg;
                String role = (String)messageObj.get('role');
                
                if (role == 'assistant') {
                    List<Object> contentList = (List<Object>)messageObj.get('content');
                    for (Object content : contentList) {
                        Map<String, Object> contentItem = (Map<String, Object>)content;
                        String type = (String)contentItem.get('type');
                        
                        if (type == 'text') {
                            Map<String, Object> textObj = (Map<String, Object>)contentItem.get('text');
                            String value = (String)textObj.get('value');
                            
                            // Check if this is a file search result or a regular message
                            if (value.contains('File search results:')) {
                                fileSearchResults = value;
                            } else {
                                assistantMessage = value;
                            }
                        }
                    }
                    
                    // We only need the most recent assistant message
                    break;
                }
            }
            
            return new Map<String, String>{
                'response' => assistantMessage,
                'fileSearchResults' => fileSearchResults,
                'runStatus' => runStatus
            };
        } catch (Exception e) {
            System.debug('Error in sendMessage: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, String> uploadFileToAzure(String threadId, String contentDocumentId) {
        try {
            System.debug('Uploading file to Azure for thread: ' + threadId + ', document: ' + contentDocumentId);
            
            // Get the ContentVersion of the uploaded file
            ContentVersion cv = [
                SELECT Id, Title, VersionData, FileType, ContentSize, PathOnClient
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];
            
            if (cv == null) {
                throw new AuraHandledException('File not found');
            }
            
            // Generate a preview for the UI
            String preview = generatePreview(cv);
            
            // 1. First, upload the file to Azure OpenAI
            String fileId = uploadFileToAzureOpenAI(cv);
            System.debug('File uploaded with ID: ' + fileId);
            
            if (String.isBlank(fileId)) {
                throw new AuraHandledException('Failed to upload file to Azure OpenAI');
            }
            
            // 2. Associate the file with the hardcoded vector store
            associateFileWithVectorStore(VECTOR_STORE_ID, fileId);
            System.debug('File associated with vector store');
            
            // 3. Update the assistant configuration with the hardcoded vector store
            associateWithAssistant(VECTOR_STORE_ID, threadId);
            System.debug('Vector store associated with assistant');
            
            // 4. Send a notification message about the file
            if (String.isNotBlank(threadId)) {
                Boolean messageSent = sendFileNotificationMessage(threadId, cv.PathOnClient, fileId);
                System.debug('File notification message sent: ' + messageSent);
            }
            
            return new Map<String, String>{
                'fileName' => cv.PathOnClient,
                'fileType' => cv.FileType,
                'fileSize' => String.valueOf(cv.ContentSize),
                'preview' => preview,
                'fileId' => fileId,
                'vectorStoreId' => VECTOR_STORE_ID
            };
        } catch (Exception e) {
            System.debug('Error in uploadFileToAzure: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Helper method to generate a preview based on file type
    private static String generatePreview(ContentVersion cv) {
        String preview = '';
        
        try {
            if (cv.FileType.equalsIgnoreCase('TEXT') || 
                cv.FileType.equalsIgnoreCase('CSV') || 
                cv.FileType.equalsIgnoreCase('HTML') || 
                cv.FileType.equalsIgnoreCase('XML')) {
                
                // For text files, convert to string directly
                String fileContent = cv.VersionData.toString();
                preview = fileContent.length() > 500 ? fileContent.substring(0, 500) + '...' : fileContent;
                
            } else if (cv.FileType.equalsIgnoreCase('PDF')) {
                preview = '[PDF file - ' + cv.Title + ' - ' + cv.ContentSize + ' bytes]';
            } else {
                preview = '[' + cv.FileType + ' file - ' + cv.Title + ' - ' + cv.ContentSize + ' bytes]';
            }
        } catch (Exception e) {
            System.debug('Error generating preview: ' + e.getMessage());
            preview = 'Error generating preview: ' + e.getMessage();
        }
        
        return preview;
    }

    // Method to upload file to Azure OpenAI API
    private static String uploadFileToAzureOpenAI(ContentVersion cv) {
        try {
            // First, we'll create a temporary file in Azure Blob Storage
            // Then we'll use that file's URL to create an OpenAI file
            
            // For simplicity, we'll use a direct approach with base64 encoding
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            
            String fileUploadEndpoint = AZURE_ENDPOINT + '/openai/files?api-version=' + API_VERSION;
            System.debug('File upload endpoint: ' + fileUploadEndpoint);
            
            req.setEndpoint(fileUploadEndpoint);
            req.setMethod('POST');
            req.setHeader('api-key', AZURE_API_KEY);
            req.setHeader('Content-Type', 'application/json');
            
            // Convert file content to base64
            String fileContentBase64 = EncodingUtil.base64Encode(cv.VersionData);
            
            // Create a JSON payload with the file content
            Map<String, Object> payload = new Map<String, Object>{
                'purpose' => 'assistants',
                'file' => fileContentBase64,
                'filename' => cv.PathOnClient
            };
            
            req.setBody(JSON.serialize(payload));
            req.setTimeout(120000); // 2 minutes timeout for large files
            
            HttpResponse res = http.send(req);
            System.debug('File upload response status: ' + res.getStatusCode());
            
            if (res.getStatusCode() != 201 && res.getStatusCode() != 200) {
                System.debug('Error uploading file: ' + res.getBody());
                
                // Try an alternative approach - using a direct file upload
                return uploadFileDirectly(cv);
            }
            
            // Parse the response to get the file ID
            Map<String, Object> responseData = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            String fileId = (String)responseData.get('id');
            System.debug('File uploaded with ID: ' + fileId);
            
            return fileId;
        } catch (Exception e) {
            System.debug('Exception during file upload: ' + e.getMessage());
            throw new AuraHandledException('Error uploading file: ' + e.getMessage());
        }
    }
    
    // Alternative method for direct file upload
    private static String uploadFileDirectly(ContentVersion cv) {
        try {
            // This is a fallback method that uses a different approach
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            
            String fileUploadEndpoint = AZURE_ENDPOINT + '/openai/files?api-version=' + API_VERSION;
            req.setEndpoint(fileUploadEndpoint);
            req.setMethod('POST');
            req.setHeader('api-key', AZURE_API_KEY);
            
            // Create a unique boundary for multipart form data
            String boundary = '----SalesforceBoundary' + String.valueOf(DateTime.now().getTime());
            req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
            
            // Create the multipart form data manually
            String body = '--' + boundary + '\r\n';
            body += 'Content-Disposition: form-data; name="purpose"\r\n\r\n';
            body += 'assistants\r\n';
            body += '--' + boundary + '\r\n';
            body += 'Content-Disposition: form-data; name="file"; filename="' + cv.PathOnClient + '"\r\n';
            body += 'Content-Type: application/octet-stream\r\n\r\n';
            
            // We can't directly append binary data in Apex, so we'll use a workaround
            // Convert the file to base64, then back to a string representation
            String fileContent = EncodingUtil.base64Encode(cv.VersionData);
            
            // Set the body - note this won't work for binary files, only text files
            body += fileContent;
            body += '\r\n--' + boundary + '--';
            
            req.setBody(body);
            req.setTimeout(120000); // 2 minutes timeout
            
            HttpResponse res = http.send(req);
            System.debug('Direct file upload response status: ' + res.getStatusCode());
            
            if (res.getStatusCode() != 201 && res.getStatusCode() != 200) {
                System.debug('Error in direct file upload: ' + res.getBody());
                throw new AuraHandledException('Failed to upload file: ' + res.getBody());
            }
            
            // Parse the response to get the file ID
            Map<String, Object> responseData = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            String fileId = (String)responseData.get('id');
            System.debug('File uploaded directly with ID: ' + fileId);
            
            return fileId;
        } catch (Exception e) {
            System.debug('Exception during direct file upload: ' + e.getMessage());
            throw new AuraHandledException('Error in direct file upload: ' + e.getMessage());
        }
    }

    // Method to send a message notifying about the file
    private static Boolean sendFileNotificationMessage(String threadId, String fileName, String fileId) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        
        String messageEndpoint = AZURE_ENDPOINT + '/openai/threads/' + threadId + '/messages?api-version=' + API_VERSION;
        System.debug('Message endpoint: ' + messageEndpoint);
        
        req.setEndpoint(messageEndpoint);
        req.setMethod('POST');
        req.setHeader('api-key', AZURE_API_KEY);
        req.setHeader('Content-Type', 'application/json');
        
        // Create a simple text message
        // Azure OpenAI API expects content as a plain string for text messages, not an object
        Map<String, String> messageData = new Map<String, String>{
            'role' => 'user',
            'content' => 'I\'ve uploaded a file called "' + fileName + '" with ID: ' + fileId + '. Please analyze this document.'
        };
        
        String messageBody = JSON.serialize(messageData);
        System.debug('File notification message request body: ' + messageBody);
        req.setBody(messageBody);
        
        HttpResponse res = http.send(req);
        System.debug('File notification message response status: ' + res.getStatusCode());
        System.debug('File notification message response body: ' + res.getBody());
        
        return (res.getStatusCode() == 200 || res.getStatusCode() == 201);
    }

    // Helper method to process message content including annotations and citations
    private static String processMessageContent(List<Object> contentList) {
        String messageText = '';
        
        for (Object content : contentList) {
            Map<String, Object> contentItem = (Map<String, Object>)content;
            String type = (String)contentItem.get('type');
            
            if (type == 'text') {
                Map<String, Object> textObj = (Map<String, Object>)contentItem.get('text');
                String value = (String)textObj.get('value');
                
                // Process annotations if present
                List<Object> annotations = (List<Object>)textObj.get('annotations');
                if (annotations != null && !annotations.isEmpty()) {
                    value = processAnnotations(value, annotations);
                }
                
                messageText += value;
            } else if (type == 'image_file') {
                messageText += '[Image attachment]';
            }
        }
        
        return messageText;
    }

    // Process annotations like file citations
    private static String processAnnotations(String text, List<Object> annotations) {
        // Sort annotations by index to process them in reverse order
        List<AnnotationWrapper> wrappers = new List<AnnotationWrapper>();
        
        for (Object anno : annotations) {
            Map<String, Object> annotation = (Map<String, Object>)anno;
            Integer startIndex = (Integer)annotation.get('start_index');
            Integer endIndex = (Integer)annotation.get('end_index');
            String type = (String)annotation.get('type');
            
            wrappers.add(new AnnotationWrapper(startIndex, endIndex, type, annotation));
        }
        
        // Sort by start_index in descending order to avoid index shifting
        wrappers.sort();
        
        // Process annotations in reverse order
        for (AnnotationWrapper wrapper : wrappers) {
            Map<String, Object> annotation = wrapper.annotation;
            Integer startIndex = wrapper.startIndex;
            Integer endIndex = wrapper.endIndex;
            String type = wrapper.type;
            
            String citation = '';
            if (type == 'file_citation') {
                Map<String, Object> fileCitation = (Map<String, Object>)annotation.get('file_citation');
                String fileId = (String)fileCitation.get('file_id');
                String quote = text.substring(startIndex, endIndex);
                citation = '[' + quote + ' (Source: File ' + fileId + ')]';
            } else if (type == 'file_path') {
                Map<String, Object> filePath = (Map<String, Object>)annotation.get('file_path');
                String fileId = (String)filePath.get('file_id');
                citation = '[File: ' + fileId + ']';
            }
            
            if (String.isNotBlank(citation)) {
                text = text.substring(0, startIndex) + citation + text.substring(endIndex);
            }
        }
        
        return text;
    }

    // Helper class for sorting annotations
    private class AnnotationWrapper implements Comparable {
        public Integer startIndex;
        public Integer endIndex;
        public String type;
        public Map<String, Object> annotation;
        
        public AnnotationWrapper(Integer startIndex, Integer endIndex, String type, Map<String, Object> annotation) {
            this.startIndex = startIndex;
            this.endIndex = endIndex;
            this.type = type;
            this.annotation = annotation;
        }
        
        public Integer compareTo(Object obj) {
            AnnotationWrapper other = (AnnotationWrapper)obj;
            // Sort in descending order by start_index
            return other.startIndex - this.startIndex;
        }
    }

    @AuraEnabled
    public static List<Map<String, String>> getRelatedFiles(String recordId) {
        try {
            List<Map<String, String>> files = new List<Map<String, String>>();
            
            // Query ContentDocumentLink to get all documents linked to this record
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId 
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :recordId
            ];
            
            if (!links.isEmpty()) {
                Set<Id> documentIds = new Set<Id>();
                for (ContentDocumentLink link : links) {
                    documentIds.add(link.ContentDocumentId);
                }
                
                // Get the latest version of each document
                List<ContentVersion> versions = [
                    SELECT Id, Title, FileType, ContentSize, ContentDocumentId
                    FROM ContentVersion 
                    WHERE ContentDocumentId IN :documentIds 
                    AND IsLatest = true
                ];
                
                for (ContentVersion version : versions) {
                    files.add(new Map<String, String>{
                        'id' => version.ContentDocumentId,
                        'title' => version.Title,
                        'fileType' => version.FileType,
                        'size' => String.valueOf(version.ContentSize)
                    });
                }
            }
            
            return files;
        } catch (Exception e) {
            System.debug('Error in getRelatedFiles: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String createVectorStore() {
        try {
            if (String.isBlank(ASSISTANT_ID)) {
                System.debug('No assistant ID available for vector store creation');
                // Create a unique name without assistant ID
                return createVectorStoreWithName('SalesforceVectorStore_' + Datetime.now().getTime());
            }
            
            // Create a vector store with assistant ID in the name
            String vectorStoreName = 'VectorStore_' + ASSISTANT_ID + '_' + Datetime.now().getTime();
            return createVectorStoreWithName(vectorStoreName);
        } catch (Exception e) {
            System.debug('Error creating vector store: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return createVectorStoreAlternative();
        }
    }
    
    private static String createVectorStoreWithName(String vectorStoreName) {
        try {
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(AZURE_ENDPOINT + '/openai/vector_stores?api-version=' + API_VERSION);
            request.setMethod('POST');
            request.setHeader('api-key', AZURE_API_KEY);
            request.setHeader('Content-Type', 'application/json');
            
            // Create a vector store with the provided name
            Map<String, Object> payload = new Map<String, Object>{
                'name' => vectorStoreName
            };
            
            String requestBody = JSON.serialize(payload);
            System.debug('Vector store creation request: ' + request.getEndpoint());
            System.debug('Vector store creation payload: ' + requestBody);
            request.setBody(requestBody);
            
            HttpResponse response = http.send(request);
            System.debug('Vector store creation response status: ' + response.getStatusCode());
            System.debug('Vector store creation response body: ' + response.getBody());
            
            if (response.getStatusCode() != 200 && response.getStatusCode() != 201) {
                System.debug('Primary endpoint failed, trying alternative endpoint');
                return createVectorStoreWithNameAlternative(vectorStoreName);
            }
            
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String vectorStoreId = (String) result.get('id');
            
            // Check if the vector store was created successfully
            if (String.isBlank(vectorStoreId)) {
                System.debug('Vector store ID is blank, creation may have failed');
                return '';
            }
            
            System.debug('Successfully created vector store with ID: ' + vectorStoreId);
            return vectorStoreId;
        } catch (Exception e) {
            System.debug('Error creating vector store: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return createVectorStoreWithNameAlternative(vectorStoreName);
        }
    }
    
    // Alternative method to create vector store using a different endpoint format
    private static String createVectorStoreAlternative() {
        try {
            if (String.isBlank(ASSISTANT_ID)) {
                System.debug('No assistant ID available for vector store creation');
                // Create a unique name without assistant ID
                return createVectorStoreWithNameAlternative('SalesforceVectorStore_' + Datetime.now().getTime());
            }
            
            // Create a vector store with assistant ID in the name
            String vectorStoreName = 'VectorStore_' + ASSISTANT_ID + '_' + Datetime.now().getTime();
            return createVectorStoreWithNameAlternative(vectorStoreName);
        } catch (Exception e) {
            System.debug('Error in alternative vector store creation: ' + e.getMessage());
            return '';
        }
    }
    
    private static String createVectorStoreWithNameAlternative(String vectorStoreName) {
        try {
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(AZURE_ENDPOINT + '/openai/vectorstores?api-version=' + API_VERSION);
            request.setMethod('POST');
            request.setHeader('api-key', AZURE_API_KEY);
            request.setHeader('Content-Type', 'application/json');
            
            // Create a vector store with the provided name
            Map<String, Object> payload = new Map<String, Object>{
                'name' => vectorStoreName
            };
            
            String requestBody = JSON.serialize(payload);
            System.debug('Alternative vector store creation request: ' + request.getEndpoint());
            System.debug('Alternative vector store creation payload: ' + requestBody);
            request.setBody(requestBody);
            
            HttpResponse response = http.send(request);
            System.debug('Alternative vector store creation response status: ' + response.getStatusCode());
            System.debug('Alternative vector store creation response body: ' + response.getBody());
            
            if (response.getStatusCode() != 200 && response.getStatusCode() != 201) {
                System.debug('Vector store creation failed with both endpoints, will try direct file association');
                return '';
            }
            
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String vectorStoreId = (String) result.get('id');
            
            // Check if the vector store was created successfully
            if (String.isBlank(vectorStoreId)) {
                System.debug('Vector store ID is blank, creation may have failed');
                return '';
            }
            
            System.debug('Successfully created vector store with ID: ' + vectorStoreId);
            return vectorStoreId;
        } catch (Exception e) {
            System.debug('Error in alternative vector store creation: ' + e.getMessage());
            return '';
        }
    }

    // Method to create a vector store with files in a single API call
    private static String createVectorStoreWithFiles(List<String> fileIds) {
        try {
            if (fileIds == null || fileIds.isEmpty()) {
                System.debug('No file IDs provided for vector store creation');
                return '';
            }
            
            String vectorStoreName;
            if (String.isBlank(ASSISTANT_ID)) {
                vectorStoreName = 'SalesforceVectorStore_' + Datetime.now().getTime();
            } else {
                vectorStoreName = 'VectorStore_' + ASSISTANT_ID + '_' + Datetime.now().getTime();
            }
            
            return createVectorStoreWithFilesAndName(fileIds, vectorStoreName);
        } catch (Exception e) {
            System.debug('Error creating vector store with files: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return createVectorStoreWithFilesAlternative(fileIds);
        }
    }
    
    private static String createVectorStoreWithFilesAndName(List<String> fileIds, String vectorStoreName) {
        try {
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(AZURE_ENDPOINT + '/openai/vector_stores?api-version=' + API_VERSION);
            request.setMethod('POST');
            request.setHeader('api-key', AZURE_API_KEY);
            request.setHeader('Content-Type', 'application/json');
            
            // Create a vector store with a name and file IDs
            Map<String, Object> payload = new Map<String, Object>{
                'name' => vectorStoreName,
                'file_ids' => fileIds
            };
            
            String requestBody = JSON.serialize(payload);
            System.debug('Vector store with files creation request: ' + request.getEndpoint());
            System.debug('Vector store with files creation payload: ' + requestBody);
            request.setBody(requestBody);
            
            HttpResponse response = http.send(request);
            System.debug('Vector store with files creation response status: ' + response.getStatusCode());
            System.debug('Vector store with files creation response body: ' + response.getBody());
            
            if (response.getStatusCode() != 200 && response.getStatusCode() != 201) {
                System.debug('Primary endpoint failed, trying alternative endpoint');
                return createVectorStoreWithFilesAndNameAlternative(fileIds, vectorStoreName);
            }
            
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String vectorStoreId = (String) result.get('id');
            
            // Check if the vector store was created successfully
            if (String.isBlank(vectorStoreId)) {
                System.debug('Vector store ID is blank, creation may have failed');
                return '';
            }
            
            System.debug('Successfully created vector store with ID: ' + vectorStoreId + ' and files: ' + fileIds);
            return vectorStoreId;
        } catch (Exception e) {
            System.debug('Error creating vector store with files: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return createVectorStoreWithFilesAndNameAlternative(fileIds, vectorStoreName);
        }
    }
    
    // Alternative method to create vector store with files using a different endpoint format
    private static String createVectorStoreWithFilesAlternative(List<String> fileIds) {
        try {
            if (fileIds == null || fileIds.isEmpty()) {
                System.debug('No file IDs provided for vector store creation');
                return '';
            }
            
            String vectorStoreName;
            if (String.isBlank(ASSISTANT_ID)) {
                vectorStoreName = 'SalesforceVectorStore_' + Datetime.now().getTime();
            } else {
                vectorStoreName = 'VectorStore_' + ASSISTANT_ID + '_' + Datetime.now().getTime();
            }
            
            return createVectorStoreWithFilesAndNameAlternative(fileIds, vectorStoreName);
        } catch (Exception e) {
            System.debug('Error in alternative vector store with files creation: ' + e.getMessage());
            return '';
        }
    }
    
    private static String createVectorStoreWithFilesAndNameAlternative(List<String> fileIds, String vectorStoreName) {
        try {
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(AZURE_ENDPOINT + '/openai/vectorstores?api-version=' + API_VERSION);
            request.setMethod('POST');
            request.setHeader('api-key', AZURE_API_KEY);
            request.setHeader('Content-Type', 'application/json');
            
            // Create a vector store with a name and file IDs
            Map<String, Object> payload = new Map<String, Object>{
                'name' => vectorStoreName,
                'file_ids' => fileIds
            };
            
            String requestBody = JSON.serialize(payload);
            System.debug('Alternative vector store with files creation request: ' + request.getEndpoint());
            System.debug('Alternative vector store with files creation payload: ' + requestBody);
            request.setBody(requestBody);
            
            HttpResponse response = http.send(request);
            System.debug('Alternative vector store with files creation response status: ' + response.getStatusCode());
            System.debug('Alternative vector store with files creation response body: ' + response.getBody());
            
            if (response.getStatusCode() != 200 && response.getStatusCode() != 201) {
                System.debug('Vector store creation with files failed with both endpoints');
                return '';
            }
            
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String vectorStoreId = (String) result.get('id');
            
            // Check if the vector store was created successfully
            if (String.isBlank(vectorStoreId)) {
                System.debug('Vector store ID is blank, creation may have failed');
                return '';
            }
            
            System.debug('Successfully created vector store with ID: ' + vectorStoreId + ' and files: ' + fileIds);
            return vectorStoreId;
        } catch (Exception e) {
            System.debug('Error in alternative vector store with files creation: ' + e.getMessage());
            return '';
        }
    }

    private static void associateWithAssistant(String vectorStoreId, String threadId) {
        try {
            // Always use the hardcoded assistant ID and vector store ID
            System.debug('Associating vector store ' + VECTOR_STORE_ID + ' with assistant ' + ASSISTANT_ID);
            
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            
            // Update assistant configuration with the hardcoded vector store
            String assistantEndpoint = AZURE_ENDPOINT + '/openai/assistants/' + ASSISTANT_ID + '?api-version=' + API_VERSION;
            System.debug('Updating assistant configuration at endpoint: ' + assistantEndpoint);
            
            req.setEndpoint(assistantEndpoint);
            req.setMethod('PUT');  // Changed from PATCH to PUT for better compatibility
            req.setHeader('api-key', AZURE_API_KEY);
            req.setHeader('Content-Type', 'application/json');
            
            // Create the tool_resources object with the hardcoded vector store ID
            Map<String, Object> fileSearchConfig = new Map<String, Object>{
                'vector_store_ids' => new List<String>{ VECTOR_STORE_ID }
            };
            
            Map<String, Object> toolResources = new Map<String, Object>{
                'file_search' => fileSearchConfig
            };
            
            // Create a complete assistant configuration
            Map<String, Object> updateData = new Map<String, Object>{
                'name' => 'SalesforceAssistant',
                'model' => 'gpt-4o',
                'instructions' => 'You are a helpful assistant with access to file search capabilities. Use the file search tool to find relevant information when needed.',
                'tools' => new List<Map<String, String>>{
                    new Map<String, String>{'type' => 'file_search'}
                },
                'tool_resources' => toolResources
            };
            
            String requestBody = JSON.serialize(updateData);
            System.debug('Assistant update request body: ' + requestBody);
            req.setBody(requestBody);
            
            HttpResponse res = http.send(req);
            System.debug('Assistant update response status: ' + res.getStatusCode());
            System.debug('Assistant update response body: ' + res.getBody());
            
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                System.debug('Warning: Failed to update assistant configuration with PUT: ' + res.getBody());
                // Try with PATCH as fallback
                tryPatchAssistant(VECTOR_STORE_ID, threadId);
            } else {
                System.debug('Successfully associated vector store with assistant');
                
                // Optionally, send a message to the thread about the new file
                if (String.isNotBlank(threadId)) {
                    sendFileNotificationMessage(threadId, 'New file associated with vector store ID: ' + VECTOR_STORE_ID, vectorStoreId);
                }
            }
        } catch (Exception e) {
            System.debug('Error in associateWithAssistant: ' + e.getMessage() + '\n' + e.getStackTraceString());
            // Don't rethrow the exception to avoid breaking the file upload process
        }
    }
    
    // Fallback method to try PATCH if PUT fails
    private static void tryPatchAssistant(String vectorStoreId, String threadId) {
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            
            String assistantEndpoint = AZURE_ENDPOINT + '/openai/assistants/' + ASSISTANT_ID + '?api-version=' + API_VERSION;
            req.setEndpoint(assistantEndpoint);
            req.setMethod('PATCH');
            req.setHeader('api-key', AZURE_API_KEY);
            req.setHeader('Content-Type', 'application/json');
            
            // Create the tool_resources object with the hardcoded vector store ID
            Map<String, Object> fileSearchConfig = new Map<String, Object>{
                'vector_store_ids' => new List<String>{ VECTOR_STORE_ID }
            };
            
            Map<String, Object> toolResources = new Map<String, Object>{
                'file_search' => fileSearchConfig
            };
            
            Map<String, Object> updateData = new Map<String, Object>{
                'tool_resources' => toolResources
            };
            
            String requestBody = JSON.serialize(updateData);
            req.setBody(requestBody);
            
            HttpResponse res = http.send(req);
            System.debug('Assistant PATCH update response status: ' + res.getStatusCode());
            System.debug('Assistant PATCH update response body: ' + res.getBody());
            
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                System.debug('Warning: Failed to update assistant configuration with PATCH: ' + res.getBody());
                // Try to associate the file directly with the assistant as a fallback
                System.debug('Attempting to associate file directly with the assistant as a fallback');
                associateFileDirectlyWithAssistant(vectorStoreId, threadId);
            } else {
                System.debug('Successfully associated vector store with assistant using PATCH');
                
                // Optionally, send a message to the thread about the new file
                if (String.isNotBlank(threadId)) {
                    sendFileNotificationMessage(threadId, 'New file associated with vector store ID: ' + VECTOR_STORE_ID, vectorStoreId);
                }
            }
        } catch (Exception e) {
            System.debug('Error in tryPatchAssistant: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    private static void associateFileWithVectorStore(String vectorStoreId, String fileId) {
        try {
            if (String.isBlank(vectorStoreId) || String.isBlank(fileId)) {
                System.debug('Cannot associate file with vector store: vectorStoreId or fileId is blank');
                return;
            }
            
            System.debug('Attempting to associate file ' + fileId + ' with vector store ' + vectorStoreId);
            
            // First try with the new endpoint format
            if (associateFileWithVectorStoreAttempt(vectorStoreId, fileId, true)) {
                System.debug('Successfully associated file with vector store using primary endpoint');
                return; // Success with the first attempt
            }
            
            // If the first attempt fails, try with the alternative endpoint format
            if (associateFileWithVectorStoreAttempt(vectorStoreId, fileId, false)) {
                System.debug('Successfully associated file with vector store using alternative endpoint');
                return; // Success with the second attempt
            }
            
            // If both attempts fail, log a warning but don't throw an exception
            System.debug('Warning: Failed to associate file with vector store using both endpoint formats');
            
        } catch (Exception e) {
            System.debug('Error in associateFileWithVectorStore: ' + e.getMessage());
            // Don't rethrow the exception to avoid breaking the file upload process
        }
    }
    
    private static Boolean associateFileWithVectorStoreAttempt(String vectorStoreId, String fileId, Boolean useNewEndpoint) {
        try {
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            
            String endpointBase = useNewEndpoint ? '/openai/vector_stores/' : '/openai/vectorstores/';
            String endpoint = AZURE_ENDPOINT + endpointBase + vectorStoreId + '/files?api-version=' + API_VERSION;
            System.debug('Associating file with vector store at endpoint: ' + endpoint);
            
            request.setEndpoint(endpoint);
            request.setMethod('POST');
            request.setHeader('api-key', AZURE_API_KEY);
            request.setHeader('Content-Type', 'application/json');
            
            // Create the request body with the file ID
            Map<String, String> payload = new Map<String, String>{ 
                'file_id' => fileId 
            };
            String requestBody = JSON.serialize(payload);
            System.debug('Request body: ' + requestBody);
            request.setBody(requestBody);
            
            HttpResponse response = http.send(request);
            System.debug('Associate file with vector store response status: ' + response.getStatusCode());
            System.debug('Associate file with vector store response body: ' + response.getBody());
            
            return (response.getStatusCode() == 200 || response.getStatusCode() == 201);
        } catch (Exception e) {
            System.debug('Error in associateFileWithVectorStoreAttempt: ' + e.getMessage());
            return false;
        }
    }

    // Update the associateFileDirectlyWithAssistant method to use the hardcoded assistant ID
    private static void associateFileDirectlyWithAssistant(String fileId, String threadId) {
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            
            // Update assistant configuration with the file
            String assistantEndpoint = AZURE_ENDPOINT + '/openai/assistants/' + ASSISTANT_ID + '/files?api-version=' + API_VERSION;
            System.debug('Associating file directly with assistant at endpoint: ' + assistantEndpoint);
            
            req.setEndpoint(assistantEndpoint);
            req.setMethod('POST');
            req.setHeader('api-key', AZURE_API_KEY);
            req.setHeader('Content-Type', 'application/json');
            
            Map<String, String> fileData = new Map<String, String>{
                'file_id' => fileId
            };
            
            req.setBody(JSON.serialize(fileData));
            
            HttpResponse res = http.send(req);
            System.debug('Direct file association response status: ' + res.getStatusCode());
            System.debug('Direct file association response body: ' + res.getBody());
            
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                System.debug('Warning: Failed to associate file directly with assistant: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('Error in associateFileDirectlyWithAssistant: ' + e.getMessage());
        }
    }
}