/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 11-18-2025
* @last modified by  : Rishabh Goel
* @JIRA V2-7334 : File based RAG Sync
**/
public class AISyncSchedulable implements Schedulable, Database.AllowsCallouts {
    
    
    public String schedulerId;
    /**
     * Constructs an instance of AISyncSchedulable.
     *
     * This constructor is used to create a batch job for extracting data related to RAG Sync.
     *
     * @param schedulerId The specific scheduled run details, including the start time and other run-related information.
     */
    public AISyncSchedulable(String schedulerId){
        this.schedulerId = schedulerId;
    }
    
    /**
     * This method is part of a Salesforce Scheduler Apex class and is responsible for processing a batch of records.
     * It is called by the Salesforce platform to execute the logic defined in the batch job.
     *
     * @param BC The Database.SchedulableContext parameter provides contextual information for the Scheduler job.
     */
    public void execute(SchedulableContext sc) {
        String jobId = sc != null ? sc.getTriggerId() : null;
        processRequest(schedulerId, jobId);
    }
    
    
    /**
     * Process the RAG Sync Jobs
     *
     * This method takes a Scheduler ID and Schedule Job ID as a parameter 
     *
     * @param schedulerId The unique identifier of the record for which RAG Sync data is requested.
     * @param jobId The unique identifier of the record for RAG Sync Job is requested.
     * @return none
     */
    public static void processRequest(String schedulerId, String jobId){
        List<AI_RAG_Sync__c> lst = [SELECT Id, Name, Cron_Expression__c,
                                          Where_Clause__c, File_Format__c, Batch_Size__c, Max_File_Size__c,
                                          Object__c, Fields__c, File_Name__c,
                                          AI_Model_File_Upload__c, External_Id__c,
                                          AI_Model_File_Upload__r.Additional_Parameters__c, 
                                          AI_Model_File_Upload__r.Named_Credential__c, 
                                          AI_Model_File_Upload__r.Model__c,
                                          AI_Model_File_Upload__r.Connector_Class__c,
                                          AI_Model_Datastore_Import__c, 
                                          AI_Model_Datastore_Import__r.Additional_Parameters__c, 
                                          AI_Model_Datastore_Import__r.Named_Credential__c, 
                                          AI_Model_Datastore_Import__r.Model__c,
                                          AI_Model_Datastore_Import__r.Connector_Class__c,
                                          (SELECT Id, Response__c FROM AI_RAG_Sync_Jobs__r 
                                           ORDER BY CreatedDate DESC LIMIT 1)
                                          FROM AI_RAG_Sync__c 
                                          WHERE Id =:schedulerId
                                          AND AI_Model_File_Upload__c != NULL
                                          LIMIT 1];
        
        if(lst != null && !lst.isEmpty()){
            AI_RAG_Sync__c scheduler = lst.get(0);
            
            
            List<ContentVersion> lstOfFiles = new List<ContentVersion>();
            List<ContentDocumentLink> lstOfDocumentLinks = [SELECT Id, ContentDocumentId
                                                            FROM ContentDocumentLink 
                                                            WHERE LinkedEntityId =:scheduler.Id];

            if(lstOfDocumentLinks != null && !lstOfDocumentLinks.isEmpty()){
                Set<String> setOfContentDocumentIds = new Set<String>();
                for(ContentDocumentLink cdl : lstOfDocumentLinks){
					setOfContentDocumentIds.add(cdl.ContentDocumentId);           
                }
                
                lstOfFiles = [SELECT Id
                              FROM ContentVersion
                              WHERE ContentDocumentId IN :setOfContentDocumentIds
                              AND IsLatest = true];

            }
			List<String> fileIds = getFileIds(scheduler);
            
            // Check if this is Azure AI Search Direct - needs to clear index before upload
            Boolean isAzureSearchDirect = scheduler.AI_Model_File_Upload__c != null && 
                                          scheduler.AI_Model_File_Upload__r.Model__c != null &&
                                          scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.AZURE_AI_SEARCH_DIRECT);
            
            if(isAzureSearchDirect){
                // Azure Search Direct: Clear index before uploading new data
                // Use batch size of 1000 to match Azure's max batch size
                Database.executeBatch(new AISyncAzureSearchDeleteBatch(lstOfFiles, scheduler, jobId), 1000);
            }else if(fileIds != null && !fileIds.isEmpty()){
                Database.executeBatch(new AISyncFileDeleteBatch(lstOfFiles, scheduler, jobId, fileIds), 1);
            }else{
                Database.executeBatch(new AISyncFileUploadBatch(lstOfFiles, scheduler, jobId), 1);
            }
        }
    }
    
    /**
     *
     * This method takes a Scheduler as a parameter 
     * @param scheduler The unique identifier of the record for which RAG Sync data is requested.
     * @return File Data as String
     */
    public static String createFileUsingRecords(AI_RAG_Sync__c scheduler){
        String query = 'SELECT ' + AISyncSchedulable.getFieldAPIs(scheduler)+' FROM '+String.escapeSingleQuotes(scheduler.Object__c);
        if(String.isNotBlank(scheduler.Where_Clause__c)){
            query += ' WHERE '+scheduler.Where_Clause__c;
        }
        
        Map<String, Object> responseMap;
        List<SObject> records = Database.query(query);

        if(records != null && !records.isEmpty()){
            String fileContent = AISyncSchedulable.generateFile(records, scheduler);
            return fileContent;
        }
        
        return null;
    }
    
    /**
     *
     * This method takes a Scheduler as a parameter 
     * @param scheduler The unique identifier of the record for which RAG Sync data is requested.
     * @return Field Name as String
     */
    private static String getFieldAPIs(AI_RAG_Sync__c scheduler) {
        Map<String, Object> fieldMap = (Map<String, Object>) JSON.deserializeUntyped(scheduler.Fields__c);
        return String.join(new List<String>(fieldMap.keySet()), ',');
    }
    
    /**
	* @description Generates file content from sObject records based on the specified file format
    * @param records List of sObject records to process
	* @param scheduler The RAG Sync record containing file format configuration
	* @return String Data formatted as CSV, JSON, or JSONL based on scheduler configuration
	*/
    private static String generateFile(List<SObject> records, AI_RAG_Sync__c scheduler) {
        Map<String, Object> fieldMap = (Map<String, Object>) JSON.deserializeUntyped(scheduler.Fields__c);
        
        // V2-7438, V2-7599: For Azure Search Direct - Extract JSON from single field and generate JSONL
        Boolean isAzureSearchDirect = scheduler.AI_Model_File_Upload__c != null && 
                                      scheduler.AI_Model_File_Upload__r.Model__c != null &&
                                      scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.AZURE_AI_SEARCH_DIRECT);
        if(isAzureSearchDirect){
            return generateJSONLForAzureSearchDirect(records, fieldMap);
        }
        
        if(String.isBlank(scheduler.File_Format__c)){
            return generateJSON(records, fieldMap);
        }
        
        String fileFormat = scheduler.File_Format__c.toLowerCase();
        if(fileFormat == 'csv'){
            return generateCSV(records, fieldMap);
        }else if(fileFormat == 'jsonl'){
            return generateJSONL(records, fieldMap);
        }
        return generateJSON(records, fieldMap);
    }
    
    /**
	*
    * @param records The unique identifier of the sObject record
	* @param fieldMap sObject field details.
	* @return Data as CSV
	*/
    public static String generateCSV(List<SObject> records, Map<String, Object> fieldMap){
        List<String> headers = new List<String>();
        for(Object header : fieldMap.values()){
            headers.add('"' + String.valueOf(header).replaceAll('"', '""') + '"');
        }
        String csvContentBuilder = String.join(headers, ',') + '\n';
        for(SObject record : records){
            List<String> values = new List<String>();
            for (String fieldAPI : fieldMap.keySet()) {
                String value = record.get(fieldAPI) != null ? String.valueOf(record.get(fieldAPI)) : '';
                if(String.isNotBlank(value)) {
                    value = value.unescapeHtml3().unescapeHtml4();
                    value = '"' + value.replaceAll('"', '""') + '"';
                }
                values.add(value);
            }
            csvContentBuilder += String.join(values, ',') + '\n';
        }
        return csvContentBuilder.removeEnd('\n');
    }
    
    /**
	* @description Generates JSON array format from sObject records
    * @param records List of sObject records to process
	* @param fieldMap Map of field API names to display labels
	* @return String Data formatted as JSON array
	*/
    public static String generateJSON(List<SObject> records, Map<String, Object> fieldMap){
        List<Object> returnList = new List<Object>();
        for(SObject record : records){
            Map<String, Object> recordMap = new Map<String, Object>();
            for(String fieldAPI : fieldMap.keySet()){
                String fieldLabel = String.valueOf(fieldMap.get(fieldAPI));
                String value = record.get(fieldAPI) != null ? String.valueOf(record.get(fieldAPI)) : '';
                if(String.isNotBlank(value)) {
                    value = value.unescapeHtml3().unescapeHtml4();
                    value = '"' + value.replaceAll('"', '""') + '"';
                }
                recordMap.put(fieldLabel, value);
            }
            returnList.add(recordMap);
        }
        if(!returnList.isEmpty()){
            return JSON.serialize(returnList);
        }
        return null;
    }
    
    /**
	* @description Generates JSONL (JSON Lines) format from sObject records where each record is a separate JSON object on its own line
    * @param records List of sObject records to process
	* @param fieldMap Map of field API names to display labels
	* @return String Data formatted as JSONL (newline-delimited JSON objects)
	*/
    public static String generateJSONL(List<SObject> records, Map<String, Object> fieldMap){
        List<String> jsonLines = new List<String>();
        for(SObject record : records){
            Map<String, Object> recordMap = new Map<String, Object>();
            for(String fieldAPI : fieldMap.keySet()){
                String fieldLabel = String.valueOf(fieldMap.get(fieldAPI));
                String value = record.get(fieldAPI) != null ? String.valueOf(record.get(fieldAPI)) : '';
                if(String.isNotBlank(value)) {
                    value = value.unescapeHtml3().unescapeHtml4();
                    value = '"' + value.replaceAll('"', '""') + '"';
                }
                recordMap.put(fieldLabel, value);
            }
            jsonLines.add(JSON.serialize(recordMap));
        }
        if(!jsonLines.isEmpty()){
            return String.join(jsonLines, '\n');
        }
        return null;
    }
    
    /**
	* @description Generates JSONL for Azure Search Direct - extracts JSON from a single field in each record
    * Each record is expected to have one field containing JSON data. This method extracts that JSON
    * and outputs it as JSONL format (one JSON object per line).
    * V2-7438, V2-7599: Azure AI Search Direct integration
    * @param records List of sObject records to process
	* @param fieldMap Map containing the single field API name that holds JSON data
	* @return String Data formatted as JSONL (newline-delimited JSON objects)
	*/
    public static String generateJSONLForAzureSearchDirect(List<SObject> records, Map<String, Object> fieldMap){
        if(records == null || records.isEmpty() || fieldMap == null || fieldMap.isEmpty()){
            return null;
        }
        
        List<String> jsonLines = new List<String>();
        
        // Get the first (and expected only) field API name that contains JSON data
        String jsonFieldAPI = new List<String>(fieldMap.keySet())[0];
        
        for(SObject record : records){
            Object fieldValue = record.get(jsonFieldAPI);
            if(fieldValue == null){
                continue;
            }
            
            String jsonContent = String.valueOf(fieldValue);
            if(String.isBlank(jsonContent)){
                continue;
            }
            
            // Parse the JSON and convert to JSONL (one object per line)
            try {
                Object parsed = JSON.deserializeUntyped(jsonContent);
                
                if(parsed instanceof List<Object>){
                    // JSON array - each item becomes a separate line
                    List<Object> jsonArray = (List<Object>)parsed;
                    for(Object item : jsonArray){
                        if(item != null){
                            jsonLines.add(JSON.serialize(item));
                        }
                    }
                } else if(parsed != null){
                    // Single JSON object - add as one line
                    jsonLines.add(JSON.serialize(parsed));
                }
            } catch(Exception ex){
                // Skip records with invalid JSON
            }
        }
        
        if(!jsonLines.isEmpty()){
            return String.join(jsonLines, '\n');
        }
        return null;
    }
    
    /**
	* @description Uploads file content to AI service (OpenAI or GCP)
    * @param fileContent File data as String (text content like CSV/JSON) or base64-encoded String (binary files like PDF, images)
	* @param scheduler RAG Sync record details
	* @return Map<String, Object> file Id information
	*/
    public static Map<String, Object> pushToAI(String fileContent, AI_RAG_Sync__c scheduler) {
        return pushToAI(fileContent, scheduler.File_Name__c, scheduler, true);
    }
    
    /**
	* @description Uploads file content to AI service (OpenAI or GCP) with option to skip datastore import
    * @param fileContent File data as String (text content like CSV/JSON) or base64-encoded String (binary files like PDF, images)
	* @param scheduler RAG Sync record details
    * @param includeDatastoreImport Whether to perform datastore import (false for batch operations)
	* @return Map<String, Object> file Id information
	*/
    public static Map<String, Object> pushToAI(String fileContent, AI_RAG_Sync__c scheduler, Boolean includeDatastoreImport) {
        return pushToAI(fileContent, scheduler.File_Name__c, scheduler, includeDatastoreImport);
    }
    
    /**
	* @description Uploads file content to AI service (OpenAI or GCP) with custom filename
    * @param fileContent File data as String (text content like CSV/JSON) or base64-encoded String (binary files like PDF, images)
    * @param fileName Custom filename to use for the upload
	* @param scheduler RAG Sync record details
	* @return Map<String, Object> file Id information containing 'fileId' and 'externalId' (vector store ID)
	*/
    public static Map<String, Object> pushToAI(String fileContent, String fileName, AI_RAG_Sync__c scheduler) {
        return pushToAI(fileContent, fileName, scheduler, true);
    }
    
    /**
	* @description Uploads file content to AI service (OpenAI or GCP) with custom filename and option to skip datastore import
    * @param fileContent File data as String (text content like CSV/JSON) or base64-encoded String (binary files like PDF, images)
    * @param fileName Custom filename to use for the upload
	* @param scheduler RAG Sync record details
    * @param includeDatastoreImport Whether to perform datastore import (false for batch operations)
	* @return Map<String, Object> file Id information containing 'fileId' and 'externalId' (vector store ID)
	*/
    public static Map<String, Object> pushToAI(String fileContent, String fileName, AI_RAG_Sync__c scheduler, Boolean includeDatastoreImport) {     
        String fileUploadAddParams = scheduler.AI_Model_File_Upload__c != null ? scheduler.AI_Model_File_Upload__r.Additional_Parameters__c : null;
        String datastoreImportAddParams = scheduler.AI_Model_Datastore_Import__c != null ? scheduler.AI_Model_Datastore_Import__r.Additional_Parameters__c : null;
        Map<String, Object> mapOfFileUploadAdditionalParams;
        if(String.isNotBlank(fileUploadAddParams)){
            mapOfFileUploadAdditionalParams = (Map<String, Object>)JSON.deserializeUntyped(fileUploadAddParams);
        }
        
        Map<String, Object> mapOfStoreImportAdditionalParams;
        if(String.isNotBlank(datastoreImportAddParams)){
            mapOfStoreImportAdditionalParams = (Map<String, Object>)JSON.deserializeUntyped(datastoreImportAddParams);
        }
        
        Map<String, Object> responseMap = new Map<String, Object>();
        
        String fileFormat = 'application/json';
        if(String.isNotBlank(scheduler.File_Format__c) && scheduler.File_Format__c.equalsIgnoreCase('csv')){
            fileFormat = 'text/csv';
        }

        HttpResponse resp;
        Boolean isGCPStorage = scheduler.AI_Model_File_Upload__c != null && scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.GCP_FILE_UPLOAD);
        
        if(isGCPStorage){
            // V2-7480: Fixed GCP Storage upload - decode base64 to binary and use correct Content-Type
            String bucketName = String.valueOf(mapOfFileUploadAdditionalParams.get('bucketName'));
            
            // Determine Content-Type based on file extension
            String contentType = getContentType(fileName);
            if(contentType == null){
                contentType = fileFormat;
            }
            
            // For GCP Storage, decode base64 content back to binary
            Blob fileBlob;
            try {
                // Try to decode as base64 (for binary files like PDF, images, etc.)
                fileBlob = EncodingUtil.base64Decode(fileContent);
            } catch (Exception ex) {
                // If base64 decode fails, treat as text content (CSV/JSON)
                fileBlob = Blob.valueOf(fileContent);
            }
            
            // V2-7480: Use urlEncodeForGCP to encode with %20 instead of + for spaces
            resp = doCallout(
                null,
                fileBlob,
                new Map<String, String>{'Content-Type' => contentType}, 
                'callout:'+scheduler.AI_Model_File_Upload__r.Named_Credential__c+'/upload/storage/v1/b/'+urlEncodeForGCP(bucketName)+'/o?name='+urlEncodeForGCP(fileName),
                'POST'
            );
            fileBlob = null; // Clear memory
        }else if(isAzureSearchDirect(scheduler)){
            // Azure AI Search direct upload - no blob storage needed
            Map<String, Object> azureResponse = uploadToAzureSearchDirect(fileContent, fileName, scheduler, mapOfFileUploadAdditionalParams);
            responseMap.putAll(azureResponse);
            // For direct upload, skip datastore import as it's already in the index
            includeDatastoreImport = false;
        }else{
            String boundary = 'boundary_' + DateTime.now().getTime(); 
            String bodyBlob = buildMultipartBodyBlob(fileName, boundary);
            String footerSection = '\r\n--' + boundary + '--\r\n';
            String footerHex = EncodingUtil.convertToHex(Blob.valueOf(footerSection));
            
            // Determine if this is binary data (base64-encoded) or text data
            Blob fileBlob;
            try {
                // Try to decode as base64 (for binary files like PDF, images, etc.)
                fileBlob = EncodingUtil.base64Decode(fileContent);
            } catch (Exception ex) {
                // If base64 decode fails, treat as text content (CSV/JSON)
                fileBlob = Blob.valueOf(fileContent);
            }
            
            Blob bodyData = EncodingUtil.convertFromHex(bodyBlob + EncodingUtil.convertToHex(fileBlob) + footerHex);
            fileBlob = null; // Clear memory
            
            resp = doCallout(
                null,
                bodyData,
                new Map<String, String>{'Content-Type' => 'multipart/form-data; boundary=' + boundary}, 
                'callout:'+scheduler.AI_Model_File_Upload__r.Named_Credential__c+'/v1/files',
                'POST'
            );
            bodyData = null; // Clear memory
        }
        
        // Azure upload is handled by dedicated method and populates responseMap directly
        // For GCP and OpenAI, process the HTTP response
        if(resp != null){
            if(resp.getStatusCode() > 210){
                throw new ChatGPTUtills.ApplicationException('Failed to upload file: '+resp.getBody());
            }else{
                String respBody = resp.getBody();
                System.debug('respBody: '+respBody);
                if (String.isNotBlank(respBody)) {
                    try{
                        Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                        if(isGCPStorage){
                            // V2-7480: GCP Storage returns 'name' field with the object name
                            if(dataMap != null && dataMap.containsKey('name')) {
                                responseMap.put('fileId', dataMap.get('name'));
                                responseMap.put('fileName', dataMap.get('name'));
                            }
                        }else{
                            // OpenAI and other services return 'id' field
                            if(dataMap != null && dataMap.containsKey('id')) {
                                responseMap.put('fileId', dataMap.get('id'));
                            }
                        }
                    }catch (Exception jsonEx){
                        throw new ChatGPTUtills.ApplicationException('Failed to upload file: '+jsonEx.getMessage());
                    }
                }
            }
        }
        
        // V2-7480: Import file to datastore (skip for GCP/Azure batch operations, handled separately)
        if(includeDatastoreImport && scheduler.AI_Model_Datastore_Import__c != null){
            if(scheduler.AI_Model_Datastore_Import__r.Model__c.containsIgnoreCase(AIConstants.GCP_DISCOVERY_ENGINE)){
                // GCP Discovery Engine import
                String bucketName = String.valueOf(mapOfStoreImportAdditionalParams.get('bucketName'));
                String projectId = String.valueOf(mapOfStoreImportAdditionalParams.get('projectId'));
                String dataStoreId = String.valueOf(mapOfStoreImportAdditionalParams.get('dataStoreId'));
                Boolean isStructured = Boolean.valueOf(mapOfStoreImportAdditionalParams.get('isStructured'));
            
                List<String> inputUris = new List<String>{'gs://'+bucketName+'/'+fileName};
                
                // V2-7480: Determine the appropriate data schema based on file type
                String dataSchemaFormat = determineDataSchema(new List<String>{fileName}, isStructured);
                
                // Build request body
                Map<String, Object> gcsSource = new Map<String, Object>{
                    'inputUris' => inputUris,
                    'dataSchema' => dataSchemaFormat
                };
                
                Map<String, Object> reqBody = new Map<String, Object>{
                    'reconciliationMode' => 'FULL',
                    'gcsSource' => gcsSource
                };
                
                // V2-7480: Only add autoGenerateIds for CSV schema (not compatible with 'content' schema)
                if(dataSchemaFormat == 'csv'){
                    reqBody.put('autoGenerateIds', true);
                }
                
                System.debug('reqBody: '+JSON.serialize(reqBody));
                
                resp = doCallout(
                    JSON.serialize(reqBody), 
                    null,
                    new Map<String, String>{'Content-Type' => 'application/json'}, 
                    'callout:'+scheduler.AI_Model_Datastore_Import__r.Named_Credential__c+'/v1/projects/'+ EncodingUtil.urlEncode(projectId, 'UTF-8')+'/locations/global/dataStores/' + EncodingUtil.urlEncode(dataStoreId, 'UTF-8') + '/branches/default_branch/documents:import',
                    'POST'
                );
            }else if(String.isNotBlank(scheduler.AI_Model_Datastore_Import__r.Model__c)){
                // OpenAI vector store import
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
            }
        }

        // Azure import is handled by dedicated method and populates responseMap directly
        // For GCP and OpenAI, process the HTTP response
        if(resp != null){
            if(resp.getStatusCode() > 210){
                throw new ChatGPTUtills.ApplicationException('Failed to import file: '+resp.getBody());
            }else{
                String respBody = resp.getBody();
                System.debug('respBody: '+respBody);
                if(String.isNotBlank(respBody)){
                    try{
                        Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                        if(scheduler.External_Id__c == null && dataMap != null && dataMap.containsKey('id')) {
                            responseMap.put('externalId', dataMap.get('id'));  
                        }else{
                            responseMap.put('externalId', scheduler.External_Id__c);
                        }
                        if(scheduler.AI_Model_Datastore_Import__r.Model__c.containsIgnoreCase(AIConstants.GCP_DISCOVERY_ENGINE)){
                            responseMap.put('externalId', dataMap.get('name'));
                        }
                    }catch (Exception jsonEx) {
                        throw new ChatGPTUtills.ApplicationException('Failed to import file: '+jsonEx.getMessage());
                    }
                }
            }
        }
        return responseMap;
    }
    
    /**
	* @description URL encode for GCP Storage API (uses %20 for spaces instead of +)
    * @param value String to encode
	* @return String URL-encoded string compatible with GCP Storage API
    * @JIRA V2-7480 : Fixed URL encoding for GCP Storage - use %20 instead of + for spaces
	*/
    private static String urlEncodeForGCP(String value) {
        if(String.isBlank(value)){
            return value;
        }
        
        // V2-7480: EncodingUtil.urlEncode uses '+' for spaces, but GCP Storage API requires '%20'
        // So we use urlEncode and then replace '+' with '%20'
        String encoded = EncodingUtil.urlEncode(value, 'UTF-8');
        return encoded.replace('+', '%20');
    }
    
    /**
	* @description Get the appropriate Content-Type header based on file extension
    * @param fileName File name with extension
	* @return String Content-Type header value
    * @JIRA V2-7480 : Added proper Content-Type detection for binary files (PDF, DOCX, etc.)
	*/
    private static String getContentType(String fileName) {
        if(String.isBlank(fileName) || !fileName.contains('.')){
            return 'application/octet-stream';
        }
        
        String extension = fileName.substringAfterLast('.').toLowerCase();
        
        // Map of file extensions to MIME types
        Map<String, String> mimeTypes = new Map<String, String>{
            'pdf' => 'application/pdf',
            'doc' => 'application/msword',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls' => 'application/vnd.ms-excel',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'ppt' => 'application/vnd.ms-powerpoint',
            'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'txt' => 'text/plain',
            'html' => 'text/html',
            'htm' => 'text/html',
            'csv' => 'text/csv',
            'json' => 'application/json',
            'jsonl' => 'application/jsonl',
            'xml' => 'application/xml',
            'jpg' => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png' => 'image/png',
            'gif' => 'image/gif'
        };
        
        if(mimeTypes.containsKey(extension)){
            return mimeTypes.get(extension);
        }
        
        return 'application/octet-stream';
    }
    
    /**
	* @description Determine the appropriate data schema for GCP Discovery Engine based on file types
    * @param fileNames List of file names
    * @param isStructured Whether the data is structured (from config)
	* @return String data schema format
    * @JIRA V2-7480 : Smart schema detection for GCP Discovery Engine (content for PDFs, csv for structured data)
	*/
    private static String determineDataSchema(List<String> fileNames, Boolean isStructured) {
        if(fileNames == null || fileNames.isEmpty()){
            return isStructured ? 'csv' : 'content-with-faq-csv';
        }
        
        // Check file extensions to determine file types
        Set<String> documentExtensions = new Set<String>{
            'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'
        };
        
        Boolean hasDocuments = false;
        Boolean hasTextFiles = false;
        Boolean hasStructuredFiles = false;
        
        for(String fileName : fileNames){
            String extension = '';
            if(fileName.contains('.')){
                extension = fileName.substringAfterLast('.').toLowerCase();
            }
            
            if(documentExtensions.contains(extension)){
                hasDocuments = true;
            }else if(extension == 'txt' || extension == 'html' || extension == 'htm'){
                hasTextFiles = true;
            }else if(extension == 'csv' || extension == 'json' || extension == 'jsonl'){
                hasStructuredFiles = true;
            }
        }
        
        // GCP Discovery Engine schema selection:
        // - For PDF/DOCX/PPT/XLS: use 'content' (unstructured documents)
        // - For CSV with structured data: use 'csv'
        // - For text/html: use 'content'
        // - For JSON: use 'content'
        
        if(hasDocuments || hasTextFiles){
            // Use 'content' schema for unstructured documents
            return 'content-with-faq-csv';
        }
        
        if(hasStructuredFiles && isStructured){
            return 'csv';
        }
        
        // Default based on isStructured flag
        return isStructured ? 'csv' : 'content-with-faq-csv';
    }
    
    /**
	* @description Import multiple files to GCP Discovery Engine datastore in a single operation
    * @param fileNames List of file names that were uploaded to GCP Storage
	* @param scheduler RAG Sync record details
	* @return Map<String, Object> operation information containing 'externalId'
    * @JIRA V2-7480 : Batch import to GCP Discovery Engine (supports up to 10000 files in single request)
	*/
    public static Map<String, Object> importFilesToGCPDatastore(List<String> fileNames, AI_RAG_Sync__c scheduler) {
        Map<String, Object> responseMap = new Map<String, Object>();
        
        if(fileNames == null || fileNames.isEmpty()){
            return responseMap;
        }
        
        String datastoreImportAddParams = scheduler.AI_Model_Datastore_Import__c != null ? scheduler.AI_Model_Datastore_Import__r.Additional_Parameters__c : null;
        Map<String, Object> mapOfStoreImportAdditionalParams;
        if(String.isNotBlank(datastoreImportAddParams)){
            mapOfStoreImportAdditionalParams = (Map<String, Object>)JSON.deserializeUntyped(datastoreImportAddParams);
        }
        
        String bucketName = String.valueOf(mapOfStoreImportAdditionalParams.get('bucketName'));
        String projectId = String.valueOf(mapOfStoreImportAdditionalParams.get('projectId'));
        String dataStoreId = String.valueOf(mapOfStoreImportAdditionalParams.get('dataStoreId'));
        Boolean isStructured = Boolean.valueOf(mapOfStoreImportAdditionalParams.get('isStructured'));
        
        // V2-7480: Build GCS URIs for all uploaded files
        List<String> inputUris = new List<String>();
        for(String fileName : fileNames){
            inputUris.add('gs://'+bucketName+'/'+fileName);
        }
        
        // V2-7480: Determine the appropriate data schema based on file types
        String dataSchemaFormat = determineDataSchema(fileNames, isStructured);
        
        // Build request body
        Map<String, Object> gcsSource = new Map<String, Object>{
            'inputUris' => inputUris,
            'dataSchema' => dataSchemaFormat
        };
        
        Map<String, Object> reqBody = new Map<String, Object>{
            'reconciliationMode' => 'FULL',
            'gcsSource' => gcsSource
        };
            
            System.debug('reqBody: '+JSON.serialize(reqBody));
        
        // V2-7480: Only add autoGenerateIds for CSV schema (not compatible with 'content' schema)
        if(dataSchemaFormat == 'csv'){
            reqBody.put('autoGenerateIds', true);
        }
        
        HttpResponse resp = doCallout(
            JSON.serialize(reqBody), 
            null,
            new Map<String, String>{'Content-Type' => 'application/json'}, 
            'callout:'+scheduler.AI_Model_Datastore_Import__r.Named_Credential__c+'/v1/projects/'+ EncodingUtil.urlEncode(projectId, 'UTF-8')+'/locations/global/dataStores/' + EncodingUtil.urlEncode(dataStoreId, 'UTF-8') + '/branches/default_branch/documents:import',
            'POST'
        );
        
        System.debug('respBody: '+resp.getBody());
        System.debug('status: '+resp.getStatus());
        System.debug('statusCode: '+resp.getStatusCode());
        
        if(resp.getStatusCode() > 210){
            throw new ChatGPTUtills.ApplicationException('Failed to import files to datastore: '+resp.getBody());
        }else{
            String respBody = resp.getBody();
            System.debug('respBody: '+respBody);
            if(String.isNotBlank(respBody)){
                try{
                    Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(respBody);
                    if(dataMap != null && dataMap.containsKey('name')) {
                        responseMap.put('externalId', dataMap.get('name'));
                    }
                }catch (Exception jsonEx) {
                    throw new ChatGPTUtills.ApplicationException('Failed to import files: '+jsonEx.getMessage());
                }
            }
        }
        
        return responseMap;
    }
    
    // ============================================================================
    // AZURE AI SEARCH DIRECT METHODS
    // V2-7438, V2-7599: Azure AI Search Direct integration
    // ============================================================================
    
    /**
     * @description Check if the file upload model is Azure AI Search Direct (no blob storage)
     * @param scheduler RAG Sync record
     * @return Boolean true if Azure AI Search Direct
     */
    private static Boolean isAzureSearchDirect(AI_RAG_Sync__c scheduler) {
        return scheduler.AI_Model_File_Upload__c != null && 
               scheduler.AI_Model_File_Upload__r.Model__c != null &&
               scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.AZURE_AI_SEARCH_DIRECT);
    }
    
    // Cache for sanitized field names to avoid repeated processing
    private static Map<String, String> fieldNameCache = new Map<String, String>();
    
    /**
     * @description Sanitize string for Azure Search document ID (allows alphanumeric, underscore, hyphen)
     * File names are short, so regex is safe here
     * @param input String to sanitize
     * @return String sanitized for use as Azure document ID
     */
    private static String sanitizeForAzureId(String input) {
        if(String.isBlank(input)) {
            return '';
        }
        // File names are typically short (< 255 chars), regex is safe
        return input.replaceAll('[^a-zA-Z0-9_-]', '_');
    }
    
    /**
     * @description Sanitize string for Azure Search field name (allows alphanumeric and underscore only)
     * Uses caching to avoid repeated sanitization of the same field names
     * @param input String to sanitize
     * @return String sanitized for use as Azure field name
     */
    private static String sanitizeForAzureField(String input) {
        if(String.isBlank(input)) {
            return '';
        }
        // Check cache first - field names repeat across all documents
        if(fieldNameCache.containsKey(input)) {
            return fieldNameCache.get(input);
        }
        // Field names are typically short (< 100 chars), regex is safe
        String result = input.replaceAll('[^a-zA-Z0-9_]', '_');
        fieldNameCache.put(input, result);
        return result;
    }
    
    /**
     * @description Upload documents directly to Azure AI Search index
     * This method uploads content directly to the search index without needing blob storage
     * Supports JSON array, single JSON object, and JSONL (newline-delimited JSON) formats
     * @param fileContent File data as String (JSON/JSONL content)
     * @param fileName File name for reference
     * @param scheduler RAG Sync record with Azure Search configuration
     * @param additionalParams Map of Azure Search parameters (indexName, apiKey via Named Credential)
     * @return Map<String, Object> containing 'fileId' and 'externalId'
     */
    private static Map<String, Object> uploadToAzureSearchDirect(
        String fileContent, 
        String fileName, 
        AI_RAG_Sync__c scheduler,
        Map<String, Object> additionalParams
    ) {
        Map<String, Object> responseMap = new Map<String, Object>();
        
        if(additionalParams == null){
            throw new ChatGPTUtills.ApplicationException('Azure AI Search configuration is missing');
        }
        
        String indexName = String.valueOf(additionalParams.get('indexName'));
        String apiVersion = additionalParams.containsKey('apiVersion') ? 
                           String.valueOf(additionalParams.get('apiVersion')) : '2024-07-01';
        
        if(String.isBlank(indexName)){
            throw new ChatGPTUtills.ApplicationException('Azure AI Search indexName is required');
        }
        
        // Note: Index clearing is handled by AISyncAzureSearchDeleteBatch before this method is called
        // This ensures proper batch processing for large indexes (100,000+ documents)
        
        // Parse the content and build Azure Search documents
        // Supports: JSON array, single JSON object, and JSONL (newline-delimited JSON)
        List<Object> documents = new List<Object>();
        String baseDocumentId = sanitizeForAzureId(fileName) + '_' + DateTime.now().getTime();
        
        // First, detect if content is JSONL format (multiple newline-separated JSON objects)
        // JSONL: each line is a valid JSON object, content starts with { not [
        Boolean isJSONL = false;
        String trimmedContent = fileContent.trim();
        
        if(trimmedContent.startsWith('{') && !trimmedContent.startsWith('[')) {
            // Check if content contains newlines (potential JSONL)
            if(trimmedContent.contains('\n')) {
                isJSONL = true;
            }
        }
        
        if(isJSONL) {
            // Parse JSONL format - each line is a separate JSON object
            // Optimized: Build JSON string directly instead of parsing and rebuilding
            Integer docIndex = 0;
            Integer startPos = 0;
            Integer newlinePos = fileContent.indexOf('\n', startPos);
            
            while(startPos < fileContent.length()) {
                String line;
                if(newlinePos == -1) {
                    line = fileContent.substring(startPos);
                    startPos = fileContent.length();
                } else {
                    line = fileContent.substring(startPos, newlinePos);
                    startPos = newlinePos + 1;
                    newlinePos = fileContent.indexOf('\n', startPos);
                }
                
                String trimmedLine = line.trim();
                if(String.isBlank(trimmedLine) || !trimmedLine.startsWith('{')) {
                    continue;
                }
                
                // Optimized: Insert @search.action and id directly into the JSON string
                // This avoids parsing and rebuilding each object
                String docId = baseDocumentId + '_' + docIndex;
                String modifiedJson = '{"@search.action":"upload","id":"' + docId + '",' + trimmedLine.substring(1);
                
                try {
                    // Parse once to get the final document
                    Object doc = JSON.deserializeUntyped(modifiedJson);
                    documents.add(doc);
                    docIndex++;
                } catch(Exception lineEx) {
                    // If modified JSON fails, try parsing original and rebuilding
                    try {
                        Map<String, Object> parsedLine = (Map<String, Object>)JSON.deserializeUntyped(trimmedLine);
                        parsedLine.put('@search.action', 'upload');
                        parsedLine.put('id', docId);
                        documents.add(parsedLine);
                        docIndex++;
                    } catch(Exception e) {
                        // Skip invalid lines
                    }
                }
            }
        } else {
            // Try parsing as regular JSON (array or single object)
            try {
                Object parsedContent = JSON.deserializeUntyped(fileContent);
                if(parsedContent instanceof List<Object>){
                    // JSON array - each item becomes a document
                    // Optimized: directly modify the parsed maps instead of creating new ones
                    List<Object> items = (List<Object>)parsedContent;
                    Integer docIndex = 0;
                    for(Object item : items){
                        if(item instanceof Map<String, Object>){
                            Map<String, Object> itemMap = (Map<String, Object>)item;
                            // Add required Azure Search fields directly to existing map
                            itemMap.put('@search.action', 'upload');
                            itemMap.put('id', baseDocumentId + '_' + docIndex);
                            documents.add(itemMap);
                            docIndex++;
                        }
                    }
                } else if(parsedContent instanceof Map<String, Object>){
                    // Single JSON object - add required fields directly
                    Map<String, Object> itemMap = (Map<String, Object>)parsedContent;
                    itemMap.put('@search.action', 'upload');
                    itemMap.put('id', baseDocumentId);
                    documents.add(itemMap);
                }
            } catch(Exception jsonEx){
                throw new ChatGPTUtills.ApplicationException('Failed to parse file content as JSON for Azure AI Search: ' + jsonEx.getMessage());
            }
        }
        
        // Validate we have documents to upload
        if(documents.isEmpty()) {
            throw new ChatGPTUtills.ApplicationException('No valid documents found in file content to upload to Azure AI Search');
        }
        
        // Build request body
        Map<String, Object> reqBody = new Map<String, Object>{
            'value' => documents
        };
        
        // Build Azure AI Search index upload endpoint
        // POST https://{search-service}.search.windows.net/indexes/{index-name}/docs/index?api-version={api-version}
        String endpoint = 'callout:' + scheduler.AI_Model_File_Upload__r.Named_Credential__c + 
                         '/indexes/' + EncodingUtil.urlEncode(indexName, 'UTF-8') + 
                         '/docs/index?api-version=' + apiVersion;
        
        Map<String, String> headers = new Map<String, String>{
            'Content-Type' => 'application/json'
        };
        
        HttpResponse resp = doCallout(JSON.serialize(reqBody), null, headers, endpoint, 'POST');
        
        if(resp.getStatusCode() > 210){
            throw new ChatGPTUtills.ApplicationException('Failed to upload to Azure AI Search: ' + resp.getBody());
        }
        
        // Parse response to get document count
        responseMap.put('fileId', baseDocumentId);
        responseMap.put('fileName', fileName);
        responseMap.put('externalId', indexName);
        responseMap.put('documentsUploaded', documents.size());
        
        return responseMap;
    }
    
    // ============================================================================
    // END AZURE METHODS
    // ============================================================================
    
    /**
	*
    * @param requestBody data as Striing
	* @param requestBody_blob data as Blob
    * @param headers data which send in headers
    * @param endpoint API endpoint where the Data need to share
    * @param method HTTP method Type
	* @return HttpResponse response details after the callout
	*/
    public static HttpResponse doCallout(String requestBody, Blob requestBody_blob, Map<String, String> headers, String endpoint, String method){
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
        
        return resp;
    }
    
     /**
	*
    * @param parentId recordId file should be created
	* @param fileName file name to store as file
    * @param fileContent csv/json data
	* @return none
	*/
    public static void saveFile(Id parentId, String fileName, String fileContent) {
        Blob bodyBlob = Blob.valueOf('\uFEFF'+fileContent);     
        ContentVersion cv = new ContentVersion(
            Title = fileName, 
            PathOnClient = fileName,
            VersionData = bodyBlob, 
            origin = 'H'
        );
        cv = (ContentVersion)FLSCheck.getInstance().insertDML(new List<ContentVersion>{cv}).get(0);
        
        cv = [SELECT Id, Title, ContentDocumentId 
              FROM ContentVersion 
              WHERE Id =:cv.Id 
              LIMIT 1];
        
        ContentDocumentLink link = new ContentDocumentLink();
        link.LinkedEntityId = parentId;
        link.contentdocumentid = cv.ContentDocumentId;
        link.ShareType = 'V';
        FLSCheck.getInstance().insertDML(new List<ContentDocumentLink>{link});
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
    
    /**
	*
    * @param sch RAG Sync record details
	* @return none
	*/
    public static void deleteFile(AI_RAG_Sync__c sch){	
        String externalId = sch.External_Id__c;
        if(String.isNotBlank(externalId)){
            if(sch.AI_RAG_Sync_Jobs__r != null && !sch.AI_RAG_Sync_Jobs__r.isEmpty()){
                String response = sch.AI_RAG_Sync_Jobs__r.get(0).Response__c;
                if(String.isNotBlank(response)){
                    Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response);
                    if(responseMap != null && responseMap.containsKey('fileId')){
                        String fileId = String.valueOf(responseMap.get('fileId'));
                        
                        AIResponsesApiCalloutUtility.ResponseApiWrapper wrap = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
                        wrap.aiModel = sch.AI_Model_File_Upload__r;
                        wrap.vectorStoreId = externalId;
                        wrap.fileId = fileId;
                        wrap = AIResponsesApiCalloutUtility.deleteFileFromVectorStore(wrap);
                    }
                }
            }
        }
    }
    
    /**
	* @description Delete a file from GCP Storage bucket
    * @param scheduler RAG Sync record details
    * @param bucketName GCS bucket name
    * @param objectName GCS object name (file name) to delete
	* @return none
    * @JIRA V2-7480 : Fixed GCP file deletion with proper URL encoding (%20 for spaces)
	*/
    public static void deleteFileFromGCP(AI_RAG_Sync__c scheduler, String bucketName, String objectName){
        if(String.isBlank(objectName)){
            return;
        }
        
        // V2-7480: objectName should be just the file name (e.g., "myfile.pdf" or "Technical Review - a0eQH000005EyZJYA0.pdf")
        // IMPORTANT: Object name must be URL-encoded for the DELETE request using %20 for spaces (not +)
        // GCP Storage DELETE endpoint: DELETE /storage/v1/b/{bucket}/o/{object}
        String endpoint = 'callout:'+scheduler.AI_Model_File_Upload__r.Named_Credential__c+
                         '/storage/v1/b/'+urlEncodeForGCP(bucketName)+
                         '/o/'+urlEncodeForGCP(objectName);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('DELETE');
        req.setTimeout(120000);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if(res.getStatusCode() > 210){
            System.debug('ERROR - Failed to delete GCP file: ' + objectName + 
                        ', Status: ' + res.getStatusCode() + 
                        ', Body: ' + res.getBody());
        }
    }
    
    /**
	*
    * @param sch RAG Sync record details
	* @return return file Id as String
	*/
    public static List<String> getFileIds(AI_RAG_Sync__c sch){	
        List<String> fileIds = new List<String>();
        String externalId = sch.External_Id__c;
        if(String.isNotBlank(externalId)){
            if(sch.AI_RAG_Sync_Jobs__r != null && !sch.AI_RAG_Sync_Jobs__r.isEmpty()){
                String response = sch.AI_RAG_Sync_Jobs__r.get(0).Response__c;
                if(String.isNotBlank(response)){
                    Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response);
                    if(responseMap != null && responseMap.containsKey('fileId')){
                        fileIds.add(String.valueOf(responseMap.get('fileId')));
                    }
                    if(responseMap != null && responseMap.containsKey('additionalFileIds')){
                        List<object> lstOfAdditionalFileIds = (List<Object>)responseMap.get('additionalFileIds');
                        if(lstOfAdditionalFileIds != null && !lstOfAdditionalFileIds.isEmpty()){
                            for(Object obj : lstOfAdditionalFileIds){
                                fileIds.add(String.valueOf(obj));
                            }
                        }
                    }
                }
            }
        }
        return fileIds;
    }
    
    
}