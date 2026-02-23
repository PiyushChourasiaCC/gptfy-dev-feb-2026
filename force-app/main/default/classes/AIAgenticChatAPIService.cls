/**
 * @description:
 *   AIAgenticChatAPIService handles all external API interactions for the AI Agentic Chat feature.
 *   This service manages file uploads to OpenAI, vector store creation and management, and file-to-vector
 *   store associations. It processes both image and document files, handles multipart form data uploads,
 *   and provides comprehensive error handling for all API operations. All methods interact with OpenAI's
 *   API v1 endpoints using Named Credentials for secure authentication.
 *
 * @author             : Piyush Chourasia
 * @group              : Plumcloud Labs
 * @last modified on   : 05-11-2025
 * @last modified by   : Piyush Chourasia
 * @jira               : V2-7341
 */
public with sharing class AIAgenticChatAPIService {

    /**
     * @description: Uploads files to OpenAI and creates a new vector store with the uploaded files.
     *               This is a two-step operation: first uploads files, then creates a vector store
     *               and associates the uploaded files with it. Image files are separated from document
     *               files during the upload process.
     * @param files List of FileWrapper objects containing file data to upload
     * @param namedCredential Named Credential name for OpenAI API authentication
     * @return AIAgenticChatController.ResponseWrapper containing uploaded file IDs, image file IDs, and vector store ID
     * @throws AIAgenticChatController.AIAgenticChatControllerException if upload or vector store creation fails
     * @jira: [V2-7341]
     */
    public static AIAgenticChatController.ResponseWrapper uploadFilesAndCreateVectorStore(List<AIAgenticChatController.FileWrapper> files, String namedCredential) {
        try {
            AIAgenticChatController.ResponseWrapper wrap = uploadFiles(files, namedCredential);
            if(!wrap.uploadedFileIds.isEmpty()){
                wrap.vectorStroreId = createVectorStore(wrap.uploadedFileIds,namedCredential);
            }
            
            return wrap;
        } catch (Exception ex) {
            throw new AIAgenticChatController.AIAgenticChatControllerException(ex.getMessage());
        }
    }
     /**
     * @description: Uploads files to OpenAI and adds them to an existing vector store.
     *               This method is used when a vector store already exists and new files need
     *               to be associated with it. Separates image files from document files during upload.
     * @param files List of FileWrapper objects containing file data to upload
     * @param namedCredential Named Credential name for OpenAI API authentication
     * @param vectorStoreId Existing vector store ID to which files will be added
     * @return AIAgenticChatController.ResponseWrapper containing uploaded file IDs, image file IDs, and vector store ID
     * @throws AIAgenticChatController.AIAgenticChatControllerException if upload or file association fails
     * @jira: [V2-7341]
     */
    public static AIAgenticChatController.ResponseWrapper uploadFilesToVectorStore(List<AIAgenticChatController.FileWrapper> files, String namedCredential, String vectorStoreId) {
        try {
            // Upload files and get their IDs
            AIAgenticChatController.ResponseWrapper wrap = uploadFiles(files, namedCredential);
            if(!wrap.uploadedFileIds.isEmpty()){
                addFileToVectorStore(wrap.uploadedFileIds,namedCredential,vectorStoreId);
            }
            wrap.vectorStroreId = vectorStoreId;
            return wrap;
        } catch (Exception ex) {
            throw new AIAgenticChatController.AIAgenticChatControllerException(ex.getMessage());
        }
    }
    /**
     * @description: Internal method to upload multiple files to OpenAI and categorize them by type.
     *               Separates image files (for vision purposes) from document files (for assistants).
     *               Each file is uploaded with the appropriate purpose parameter based on its MIME type.
     * @param files List of FileWrapper objects containing file data to upload
     * @param namedCredential Named Credential name for OpenAI API authentication
     * @return AIAgenticChatController.ResponseWrapper with populated uploadedFileIds (documents) and imageFileIds (images)
     * @throws AIAgenticChatController.AIAgenticChatControllerException if any file upload fails
     * @jira: [V2-7341]
     */
    private static AIAgenticChatController.ResponseWrapper uploadFiles(List<AIAgenticChatController.FileWrapper> files, String namedCredential){
        AIAgenticChatController.ResponseWrapper wrap = new AIAgenticChatController.ResponseWrapper();
       
        List<String> uploadedFileIds = new List<String>();
        for(AIAgenticChatController.FileWrapper fileWrapper : files){
            if(isImageFile(fileWrapper.mimeType)  == true){
                String fileId = uploadSingleFile(fileWrapper, namedCredential,'vision');
                wrap.imageFileIds.add(fileId);
                wrap.uploadedFileIds.add(fileId);
            }else{
                wrap.uploadedFileIds.add(uploadSingleFile(fileWrapper, namedCredential,'assistants'));
            }
        }
        return wrap;
    }
    /**
     * @description: Determines if a file is an image based on its MIME type.
     *               Checks for standard image MIME types and common image format indicators.
     * @param mimeType The MIME type string of the file
     * @return Boolean true if the file is an image, false otherwise
     * @jira: [V2-7341]
     */
    private static Boolean isImageFile(String mimeType) {
        return mimeType != null && (
            mimeType.startsWith('image/') ||
            mimeType.contains('png') ||
            mimeType.contains('jpg') ||
            mimeType.contains('jpeg') ||
            mimeType.contains('gif') ||
            mimeType.contains('webp')
        );
    }
     /**
     * @description: Uploads a single file to OpenAI using multipart/form-data encoding.
     *               Constructs the HTTP request with proper headers and boundary markers,
     *               encodes the file data, and sends it to OpenAI's file upload endpoint.
     * @param fileWrapper FileWrapper object containing file name, MIME type, and base64-encoded data
     * @param namedCredential Named Credential name for OpenAI API authentication
     * @param purpose Purpose of the file upload ('vision' for images, 'assistants' for documents)
     * @return String The file ID returned by OpenAI API
     * @throws AIAgenticChatController.AIAgenticChatControllerException if upload fails or response is invalid
     * @jira: [V2-7341]
     */
    public static String uploadSingleFile(AIAgenticChatController.FileWrapper fileWrapper, String namedCredential, String purpose) { 
        String fileId = '';
        try {
            String boundary = 'boundary_' + DateTime.now().getTime();
            String bodyBlob = buildMultipartBodyBlob(fileWrapper, boundary, purpose);
            String footerSection = '\r\n--' + boundary + '--\r\n';
            String footerHex = EncodingUtil.convertToHex(Blob.valueOf(footerSection));
            Blob fileBlob = EncodingUtil.base64Decode(fileWrapper.base64Data);
            Blob bodyData = EncodingUtil.convertFromHex(bodyBlob + EncodingUtil.convertToHex(fileBlob) + footerHex);
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:'+namedCredential+'/v1/files');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
            req.setBodyAsBlob(bodyData);
            bodyData = null;
            req.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            System.debug('File Upload Response: ' + response.getBody());
            if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                String respBody = response.getBody();
                if (String.isNotBlank(respBody)) {
                    Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                    if (dataMap != null && dataMap.containsKey('id')) {
                        fileId =  String.valueOf(dataMap.get('id'));
                        System.debug('Uploaded File ID: ' + fileId);
                    }
                }
            } else {
                throw new AIAgenticChatController.AIAgenticChatControllerException(response.getBody());
            }
            
        } catch (Exception ex) {
            throw new AIAgenticChatController.AIAgenticChatControllerException(ex.getMessage());
        }
        
        return fileId;
    }
     
    /**
     * @description: Builds the multipart/form-data body for file upload in hex format.
     *               Creates properly formatted sections for the 'purpose' field and file header,
     *               following RFC 2388 multipart/form-data specification. Returns hex-encoded
     *               string to avoid base64 encoding issues.
     * @param fileWrapper FileWrapper object containing file name and metadata
     * @param boundary Unique boundary string to separate multipart sections
     * @param purpose Purpose of the file ('vision' or 'assistants')
     * @return String Hex-encoded multipart body sections (purpose + file header)
     * @jira: [V2-7341]
     */
    private static String buildMultipartBodyBlob(AIAgenticChatController.FileWrapper fileWrapper, String boundary, String purpose) {
        // Build multipart sections with proper spacing
        String purposeSection = '--' + boundary + '\r\n' +
                'Content-Disposition: form-data; name="purpose"\r\n\r\n' +
                purpose + '\r\n';

        String fileHeaderSection = '--' + boundary + '\r\n' +
                    'Content-Disposition: form-data; name="file"; filename="' + fileWrapper.fileName + '"\r\n' +
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
     * @description: Builds the multipart/form-data body for file upload in hex format.
     *               Creates properly formatted sections for the 'purpose' field and file header,
     *               following RFC 2388 multipart/form-data specification. Returns hex-encoded
     *               string to avoid base64 encoding issues.
     * @param fileWrapper FileWrapper object containing file name and metadata
     * @param boundary Unique boundary string to separate multipart sections
     * @param purpose Purpose of the file ('vision' or 'assistants')
     * @return String Hex-encoded multipart body sections (purpose + file header)
     * @jira: [V2-7341]
     */
    public static String createVectorStore(List<String> uploadedFileIds, String namedCredential) {
        String vectorStoreId = '';
        try {
            // Ensure we have uploaded file IDs
            if (uploadedFileIds == null || uploadedFileIds.isEmpty()) {
                throw new AIAgenticChatController.AIAgenticChatControllerException('No uploaded file IDs available for vector store creation');
            }
            
            Map<String, Object> requestBody = new Map<String, Object>{
                'name' => 'Additional Files',
                'file_ids' => uploadedFileIds
            };
            
            String body = JSON.serialize(requestBody);
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:'+namedCredential+'/v1/vector_stores');
            request.setMethod('POST');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('OpenAI-Beta', 'assistants=v2');
            request.setBody(body);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            System.debug('Vector Store Creation Response: ' + response.getBody());
            if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                String respBody = response.getBody();
                if (String.isNotBlank(respBody)) {
                    Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                    if (dataMap != null && dataMap.containsKey('id')) {
                        vectorStoreId = String.valueOf(dataMap.get('id'));
                    }
                }
            } else {
                throw new AIAgenticChatController.AIAgenticChatControllerException(response.getBody());
            }
            
        } catch (Exception ex) {
            throw new AIAgenticChatController.AIAgenticChatControllerException(ex.getMessage());
        }
        
        return vectorStoreId;
    }
    /**
     * @description: Adds uploaded files to an existing vector store.
     *               Iterates through each file ID and creates an association with the vector store.
     *               This enables the AI assistant to search and retrieve information from these files.
     *               Uses OpenAI's Assistants API v2.
     * @param uploadedFileIds List of file IDs that were previously uploaded to OpenAI
     * @param namedCredential Named Credential name for OpenAI API authentication
     * @param vectorStoreId Existing vector store ID to which files will be added
     * @throws AIAgenticChatController.AIAgenticChatControllerException if no file IDs provided or association fails
     * @jira: [V2-7341]
     */
    public static void addFileToVectorStore(List<String> uploadedFileIds, String namedCredential, String vectorStoreId) {
        try {
            // Ensure we have uploaded file IDs
            if (uploadedFileIds == null || uploadedFileIds.isEmpty()) {
                throw new AIAgenticChatController.AIAgenticChatControllerException('No uploaded file IDs available for vector store creation');
            }
            
            for(String fileId : uploadedFileIds){
                String endpoint = 'callout:'+namedCredential+'/v1/vector_stores/'+vectorStoreId+'/files';
    
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
                System.debug('Add File to Vector Store Response: ' + response.getBody());
                if(response.getStatusCode() != 200 &&  response.getStatusCode() != 201) {
                    throw new AIAgenticChatController.AIAgenticChatControllerException(response.getBody());
                }
            }
        } catch (Exception ex) {
            throw new AIAgenticChatController.AIAgenticChatControllerException(ex.getMessage());
        }
    }
    /**
     * @description: Deletes a vector store from OpenAI.
     *               This permanently removes the vector store and all its file associations.
     *               Note: This does not delete the actual files from OpenAI, only the vector store container.
     *               Uses OpenAI's Assistants API v2.
     * @param namedCredential Named Credential name for OpenAI API authentication
     * @param vectorStoreId Vector store ID to be deleted
     * @throws AIAgenticChatController.AIAgenticChatControllerException if deletion fails
     * @jira: [V2-7341]
     */
    public static void deleteVectorStore(String namedCredential, String vectorStoreId) {
        try {
            String endpoint = 'callout:'+namedCredential+'/v1/vector_stores/'+vectorStoreId;
            
            Http http = new Http();
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('DELETE');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('OpenAI-Beta', 'assistants=v2');
            
            HttpResponse response = http.send(request);
            System.debug('Delete Vector Store Response: ' + response.getBody());
            if(response.getStatusCode() != 200 &&  response.getStatusCode() != 201) {
                throw new AIAgenticChatController.AIAgenticChatControllerException(response.getBody());
            }
        } catch (Exception ex) {
            throw new AIAgenticChatController.AIAgenticChatControllerException(ex.getMessage());
        }
    }
}