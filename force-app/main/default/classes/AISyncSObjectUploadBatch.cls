/**
 * @description Batch class for uploading sObject records to AI in chunks based on heap size limits
 * @author Plumcloud Labs
 * @group GPTfy
 */
public with sharing class AISyncSObjectUploadBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    
    public AI_RAG_Sync__c scheduler;
    public AI_RAG_Sync_Job__c job;
    public String accumulatedContent;
    public Integer filePartCounter;
    public List<String> additionalFileIds;
    public List<String> additionalFileNames;
    public List<String> errorMessages;
    public Boolean csvHeaderAdded;
    public Boolean isGCPStorage;
    public Boolean isAzureSearchDirect;
    public Map<String, Object> fieldMap;
    public Integer totalCount; // Total records processed
    public Integer maxContentSize; // Configurable max content size in bytes
    public Integer stringLimit; // V2-7438, V2-7599: Dynamic string limit based on platform
    
    // V2-7438, V2-7599: Azure Search Direct uses smaller limits to avoid CPU/heap issues
    private static final Integer AZURE_DEFAULT_MAX_FILE_SIZE_MB = 1;
    private static final Integer AZURE_MAX_ALLOWED_FILE_SIZE_MB = 2;
    private static final Integer AZURE_STRING_LIMIT = 2 * 1024 * 1024; // 2MB
    
    // GCP and OpenAI Responses API use larger limits
    private static final Integer DEFAULT_MAX_FILE_SIZE_MB = 3;
    private static final Integer MAX_ALLOWED_FILE_SIZE_MB = 5;
    private static final Integer SALESFORCE_STRING_LIMIT = 5 * 1024 * 1024; // 5MB
    
    // Pending file for finish() - only stores last file to avoid batch size limit
    private String pendingFileName;
    private String pendingFileContent;
    
    /**
     * @description Constructs an instance of AISyncSObjectUploadBatch
     * @param scheduler The AI_RAG_Sync__c record containing configuration
     * @param job The AI_RAG_Sync_Job__c record for tracking job status
     */
    public AISyncSObjectUploadBatch(AI_RAG_Sync__c scheduler, AI_RAG_Sync_Job__c job) {
        this(scheduler, job, new List<String>(), new List<String>(), new List<String>());
    }
    
    /**
     * @description Constructs an instance of AISyncSObjectUploadBatch with existing file data from previous batch
     * @param scheduler The AI_RAG_Sync__c record containing configuration
     * @param job The AI_RAG_Sync_Job__c record for tracking job status
     * @param existingFileIds List of file IDs already uploaded by previous batch (e.g., ContentVersion uploads)
     * @param existingFileNames List of file names already uploaded by previous batch
     * @param existingErrors List of error messages from previous batch
     */
    public AISyncSObjectUploadBatch(AI_RAG_Sync__c scheduler, AI_RAG_Sync_Job__c job, 
                                    List<String> existingFileIds, List<String> existingFileNames, 
                                    List<String> existingErrors) {
        this.scheduler = scheduler;
        this.job = job;
        this.accumulatedContent = '';
        this.filePartCounter = 1;
        this.additionalFileIds = existingFileIds != null ? existingFileIds : new List<String>();
        this.additionalFileNames = existingFileNames != null ? existingFileNames : new List<String>();
        this.errorMessages = existingErrors != null ? existingErrors : new List<String>();
        this.csvHeaderAdded = false;
        this.totalCount = 0;
        this.pendingFileName = null;
        this.pendingFileContent = null;
        this.isGCPStorage = scheduler.AI_Model_File_Upload__c != null && 
                           scheduler.AI_Model_File_Upload__r.Model__c != null &&
                           scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.GCP_FILE_UPLOAD);
        this.isAzureSearchDirect = scheduler.AI_Model_File_Upload__c != null && 
                                   scheduler.AI_Model_File_Upload__r.Model__c != null &&
                                   scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.AZURE_AI_SEARCH_DIRECT);
        
        // V2-7438, V2-7599: Use different limits based on platform
        Integer defaultSize;
        Integer maxAllowed;
        if (this.isAzureSearchDirect) {
            defaultSize = AZURE_DEFAULT_MAX_FILE_SIZE_MB;
            maxAllowed = AZURE_MAX_ALLOWED_FILE_SIZE_MB;
            this.stringLimit = AZURE_STRING_LIMIT;
        } else {
            defaultSize = DEFAULT_MAX_FILE_SIZE_MB;
            maxAllowed = MAX_ALLOWED_FILE_SIZE_MB;
            this.stringLimit = SALESFORCE_STRING_LIMIT;
        }
        
        // Set max content size from scheduler or use default, capped at max allowed
        Integer maxFileSizeMB = scheduler.Max_File_Size__c != null ? Integer.valueOf(scheduler.Max_File_Size__c) : defaultSize;
        if (maxFileSizeMB > maxAllowed) {
            maxFileSizeMB = maxAllowed;
        }
        this.maxContentSize = maxFileSizeMB * 1024 * 1024;
        
        // Parse field map once for reuse
        if (String.isNotBlank(scheduler.Fields__c)) {
            this.fieldMap = (Map<String, Object>) JSON.deserializeUntyped(scheduler.Fields__c);
        } else {
            this.fieldMap = new Map<String, Object>();
        }
    }
    
    /**
     * @description Start method to provide query locator for batch processing
     * @param bc The batch context
     * @return Database.QueryLocator for the sObject records to process
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT ' + getFieldAPIs() + ' FROM ' + String.escapeSingleQuotes(scheduler.Object__c);
        // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
        System.debug('query : '+query);
        query+=String.escapeSingleQuotes(AIUtility.getFormattedWhereClause(scheduler.Where_Clause__c,NULL,NULL,false));
        System.debug('after query : '+query);
        return Database.getQueryLocator(query);
    }
    
    /**
     * @description Execute method to process each batch of records
     * @param bc The batch context
     * @param scope The list of sObject records to process
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            // Check heap usage before processing - if over 80% (9.6MB of 12MB), push first
            Integer heapLimit = Limits.getLimitHeapSize();
            Integer heapUsed = Limits.getHeapSize();
            Integer heapThreshold = (heapLimit * 80) / 100; // 80% of heap limit
            
            if (heapUsed > heapThreshold && String.isNotBlank(accumulatedContent)) {
                pushAccumulatedContent(true);
            }
            
            String batchContent = generateContent(scope);
            
            if (String.isBlank(batchContent)) {
                return;
            }
            
            // Check if adding this batch would exceed limit - push first if needed
            Integer currentSize = String.isNotBlank(accumulatedContent) ? accumulatedContent.length() : 0;
            Integer projectedSize = currentSize + batchContent.length();
            
            // Push if exceeds configured limit OR if approaching string limit
            if (projectedSize >= maxContentSize || projectedSize >= stringLimit) {
                // Push accumulated content to AI before adding more
                if (String.isNotBlank(accumulatedContent)) {
                    pushAccumulatedContent(true);
                }
            }
            
            // Combine the content based on file format
            // V2-7438, V2-7599: Azure Search Direct always uses JSONL format (extracted from JSON field)
            if (isAzureSearchDirect) {
                appendJSONLContent(batchContent);
            } else if (isCSVFormat()) {
                appendCSVContent(batchContent);
            } else if (isJSONLFormat()) {
                appendJSONLContent(batchContent);
            } else {
                appendJSONContent(batchContent);
            }
            
            // Safety check: if content exceeds limit after append OR heap is critical, push immediately
            heapUsed = Limits.getHeapSize();
            if (String.isNotBlank(accumulatedContent) && 
                (accumulatedContent.length() >= maxContentSize || 
                 accumulatedContent.length() >= stringLimit ||
                 heapUsed > heapThreshold)) {
                pushAccumulatedContent(true);
            }
            totalCount += scope.size();
        } catch (Exception e) {
            errorMessages.add('Execute error: ' + e.getMessage() + ' \n\n ' + e.getStackTraceString());
        }
    }
    
    /**
     * @description Finish method called after all batches are processed
     * @param bc The batch context
     */
    public void finish(Database.BatchableContext bc) {
        try {
            // Push any remaining accumulated content (defer save to avoid callout-after-DML)
            if (String.isNotBlank(accumulatedContent)) {
                pushAccumulatedContent(false);
            }
            
            // Handle GCP batch datastore import if applicable
            if (isGCPStorage && additionalFileNames != null && !additionalFileNames.isEmpty()) {
                handleGCPDatastoreImport();
            }
        } catch (Exception e) {
            errorMessages.add('Finish error: ' + e.getMessage() + ' \n\n ' + e.getStackTraceString());
        } finally {
            // Always update job status, even if an exception occurred
            try {
                updateJobStatus();
            } catch (Exception statusEx) {
                // Last resort: try to update job status with minimal info
                try {
                    job.Status__c = AIConstants.SYNC_JOB_STATUS_ERRORED;
                    job.Message__c = 'Critical error updating job status: ' + statusEx.getMessage();
                    job.End_Date_Time__c = System.now();
                    FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync_Job__c>{job});
                } catch (Exception finalEx) {
                    System.debug('CRITICAL: Failed to update job status: ' + finalEx.getMessage());
                }
            }
        }
    }
    
    /**
     * @description Get field API names from the scheduler configuration
     * @return Comma-separated field API names
     */
    private String getFieldAPIs() {
        return String.join(new List<String>(fieldMap.keySet()), ',');
    }
    
    /**
     * @description Check if the file format is CSV
     * @return True if CSV format, false otherwise
     */
    private Boolean isCSVFormat() {
        return String.isNotBlank(scheduler.File_Format__c) && 
               scheduler.File_Format__c.equalsIgnoreCase('csv');
    }
    
    /**
     * @description Check if the file format is JSONL
     * @return True if JSONL format, false otherwise
     */
    private Boolean isJSONLFormat() {
        return String.isNotBlank(scheduler.File_Format__c) && 
               scheduler.File_Format__c.equalsIgnoreCase('jsonl');
    }
    
    /**
     * @description Generate file content for the given records
     * @param records The sObject records to convert
     * @return The generated file content string (CSV, JSON, or JSONL based on scheduler configuration)
     */
    private String generateContent(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return null;
        }
        
        // V2-7438, V2-7599: For Azure Search Direct - Extract JSON from single field and generate JSONL
        if (isAzureSearchDirect) {
            return AISyncSchedulable.generateJSONLForAzureSearchDirect(records, fieldMap);
        }
        
        if (isCSVFormat()) {
            return AISyncSchedulable.generateCSV(records, fieldMap);
        } else if (isJSONLFormat()) {
            return AISyncSchedulable.generateJSONL(records, fieldMap);
        } else {
            return AISyncSchedulable.generateJSON(records, fieldMap);
        }
    }
    
    /**
     * @description Append CSV content, handling headers appropriately
     * @param batchContent The CSV content from current batch
     */
    private void appendCSVContent(String batchContent) {
        if (String.isBlank(batchContent)) {
            return;
        }
        
        if (!csvHeaderAdded) {
            // First batch - include header
            accumulatedContent = batchContent;
            csvHeaderAdded = true;
        } else {
            // Subsequent batches - skip header row
            Integer firstNewlineIndex = batchContent.indexOf('\n');
            if (firstNewlineIndex > 0 && firstNewlineIndex < batchContent.length() - 1) {
                String rowsOnly = batchContent.substring(firstNewlineIndex + 1);
                if (String.isNotBlank(rowsOnly)) {
                    accumulatedContent += '\n' + rowsOnly;
                }
            }
        }
    }
    
    /**
     * @description Append JSON content
     * @param batchContent The JSON content from current batch
     */
    private void appendJSONContent(String batchContent) {
        if (String.isBlank(batchContent)) {
            return;
        }
        
        if (String.isBlank(accumulatedContent)) {
            accumulatedContent = batchContent;
        } else {
            // Merge JSON arrays: remove closing ] from accumulated and opening [ from new
            // accumulatedContent: [...] + batchContent: [...]  => [..., ...]
            String trimmedAccumulated = accumulatedContent.trim();
            String trimmedBatch = batchContent.trim();
            
            if (trimmedAccumulated.endsWith(']') && trimmedBatch.startsWith('[')) {
                accumulatedContent = trimmedAccumulated.substring(0, trimmedAccumulated.length() - 1) + 
                                    ',' + 
                                    trimmedBatch.substring(1);
            } else {
                // Fallback: just append
                accumulatedContent += batchContent;
            }
        }
    }
    
    /**
     * @description Append JSONL content (newline-delimited JSON objects)
     * @param batchContent The JSONL content from current batch
     */
    private void appendJSONLContent(String batchContent) {
        if (String.isBlank(batchContent)) {
            return;
        }
        
        if (String.isBlank(accumulatedContent)) {
            accumulatedContent = batchContent;
        } else {
            // JSONL is newline-delimited, simply append with newline separator
            accumulatedContent += '\n' + batchContent;
        }
    }
    
    /**
     * @description Push accumulated content to AI and reset for next chunk
     * @param saveImmediately If true, saves file immediately (for execute). If false, defers to finish (to avoid callout-after-DML)
     */
    private void pushAccumulatedContent(Boolean saveImmediately) {
        if (String.isBlank(accumulatedContent)) {
            return;
        }
        
        String fileName = generatePartFileName();
        String contentToSave = accumulatedContent;
        
        try {
            // Skip datastore import for GCP - handled in batch at the end
            // For Azure Search Direct, each upload goes directly to the index
            Boolean skipDatastoreImport = isGCPStorage || isAzureSearchDirect;
            
            Map<String, Object> responseMap = AISyncSchedulable.pushToAI(
                accumulatedContent, 
                fileName, 
                scheduler, 
                !skipDatastoreImport
            );
            
            if (responseMap != null && !responseMap.isEmpty()) {
                if (responseMap.containsKey('fileId')) {
                    additionalFileIds.add(String.valueOf(responseMap.get('fileId')));
                }
                if (responseMap.containsKey('fileName')) {
                    additionalFileNames.add(String.valueOf(responseMap.get('fileName')));
                } else {
                    additionalFileNames.add(fileName);
                }
                
                // Track external ID for later update (deferred to avoid callout-after-DML)
                // Skip for GCP as they handle external ID in batch import
                if (!isGCPStorage && String.isBlank(scheduler.External_Id__c) && responseMap.containsKey('externalId')) {
                    scheduler.External_Id__c = String.valueOf(responseMap.get('externalId'));
                }
            }
            
            // Save file to job record
            if (saveImmediately) {
                // Save immediately - safe in execute() since each execute is a separate transaction
                AISyncSchedulable.saveFile(job.Id, fileName, contentToSave);
            } else {
                // Defer save for finish() - store only the last file to avoid batch size limit
                pendingFileName = fileName;
                pendingFileContent = contentToSave;
            }          
            filePartCounter++;
        } catch (Exception e) {
            errorMessages.add('Push error for part ' + filePartCounter + ': ' + e.getMessage() + ' \n\n ' + e.getStackTraceString());
        }
        
        // Reset accumulated content
        accumulatedContent = '';
        
        // Reset CSV header flag if we pushed content (next chunk needs new header)
        if (isCSVFormat()) {
            csvHeaderAdded = false;
        }
    }
    
    /**
     * @description Generate file name with part number
     * @return File name with part suffix
     */
    private String generatePartFileName() {
        String baseName = scheduler.File_Name__c;
        String extension = getFileExtension();
        
        // Remove existing extension if present
        if (baseName.toLowerCase().endsWith('.csv') || 
            baseName.toLowerCase().endsWith('.json') || 
            baseName.toLowerCase().endsWith('.jsonl')) {
            baseName = baseName.substringBeforeLast('.');
        }
        
        return baseName + '_part' + filePartCounter + extension;
    }
    
    /**
     * @description Get file extension based on scheduler file format
     * @return File extension including the dot (e.g., '.csv', '.json', '.jsonl')
     */
    private String getFileExtension() {
        if (isCSVFormat()) {
            return '.csv';
        } else if (isJSONLFormat()) {
            return '.jsonl';
        }
        return '.json';
    }
    
    /**
     * @description Handle GCP Discovery Engine batch import
     * Note: Scheduler update is deferred to updateJobStatus() to avoid callout-after-DML errors
     */
    private void handleGCPDatastoreImport() {
        try {
            Boolean isGCPDiscovery = scheduler.AI_Model_Datastore_Import__c != null && 
                                     scheduler.AI_Model_Datastore_Import__r.Model__c != null &&
                                     scheduler.AI_Model_Datastore_Import__r.Model__c.containsIgnoreCase(AIConstants.GCP_DISCOVERY_ENGINE);
            
            if (isGCPDiscovery) {
                Map<String, Object> importResponse = AISyncSchedulable.importFilesToGCPDatastore(additionalFileNames, scheduler);
                if (importResponse != null && importResponse.containsKey('externalId')) {
                    // Track external ID for later update (deferred to avoid callout-after-DML)
                    scheduler.External_Id__c = String.valueOf(importResponse.get('externalId'));
                }
            }
        } catch (Exception e) {
            errorMessages.add('GCP Datastore import error: ' + e.getMessage() + ' \n\n ' + e.getStackTraceString());
        }
    }
    
    /**
     * @description Update job status after batch completion
     * Also saves pending file from finish() and updates scheduler
     */
    private void updateJobStatus() {
        // Save pending file from finish() (DML after all callouts complete)
        if (String.isNotBlank(pendingFileName) && String.isNotBlank(pendingFileContent)) {
            try {
                AISyncSchedulable.saveFile(job.Id, pendingFileName, pendingFileContent);
            } catch (Exception e) {
                errorMessages.add('File save error: ' + pendingFileName + ' - ' + e.getMessage());
            }
        }
        
        // Update scheduler External_Id if it was set during callouts
        if (String.isNotBlank(scheduler.External_Id__c)) {
            FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync__c>{scheduler});
        }
        
        Map<String, Object> responseMap = new Map<String, Object>();
        
        if (additionalFileIds != null && !additionalFileIds.isEmpty()) {
            responseMap.put('additionalFileIds', additionalFileIds);
        }
        
        if (additionalFileNames != null && !additionalFileNames.isEmpty()) {
            responseMap.put('additionalFileNames', additionalFileNames);
        }
        
        responseMap.put('totalParts', filePartCounter - 1);
        
        if (!responseMap.isEmpty()) {
            job.Response__c = JSON.serialize(responseMap);
        }
        
        if (errorMessages != null && !errorMessages.isEmpty()) {
            job.Status__c = AIConstants.SYNC_JOB_STATUS_ERRORED;
            job.Message__c = String.join(errorMessages, '\n\n');
        } else {
            job.Status__c = AIConstants.SYNC_JOB_STATUS_COMPLETE;
        }
        
        job.End_Date_Time__c = System.now();
        FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync_Job__c>{job});
    }
}