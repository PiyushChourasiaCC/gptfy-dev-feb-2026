/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 11-18-2025
* @last modified by  : Rishabh Goel
* @JIRA V2-7334 : File based RAG Sync
**/
public with sharing class AISyncFileUploadBatch implements Database.Batchable<ContentVersion>, Database.Stateful, Database.AllowsCallouts {
    
    public List<ContentVersion> lstOfContentVersions;
    public AI_RAG_Sync__c scheduler;
    public AI_RAG_Sync_Job__c job;   
    public List<String> additionalFileIds;
    public List<String> additionalFileNames;
    public List<String> errorMessages;
    public Boolean isGCPStorage;
    public Boolean isAzureSearchDirect;
    
    /**
     * Constructs an instance of AISyncFileUploadBatch.
     *
     * This constructor is used to create a batch job for extracting data related to RAG Sync.
     *
     * @param lstOfContentVersions Files uploaded to RAG Sync.
     * @param scheduler The specific scheduled run details, including the start time and other run-related information.
     * @param jobId The specific scheduled run RAG Sync Job details, including the start time and other run-related information.
     */
    public AISyncFileUploadBatch(List<ContentVersion> lstOfContentVersions, AI_RAG_Sync__c scheduler, String jobId){
        this.lstOfContentVersions = lstOfContentVersions;
        this.scheduler = scheduler;
        this.errorMessages = new List<String>();
        this.additionalFileIds = new List<String>();
        this.additionalFileNames = new List<String>();
        this.isGCPStorage = scheduler.AI_Model_File_Upload__c != null && 
                            scheduler.AI_Model_File_Upload__r.Model__c != null &&
                            scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.GCP_FILE_UPLOAD);
        this.isAzureSearchDirect = scheduler.AI_Model_File_Upload__c != null && 
                                   scheduler.AI_Model_File_Upload__r.Model__c != null &&
                                   scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.AZURE_AI_SEARCH_DIRECT);
        
        this.job = (AI_RAG_Sync_Job__c)FLSCheck.getInstance().insertDML(new List<AI_RAG_Sync_Job__c>{
            new AI_RAG_Sync_Job__c(
                Start_Date_Time__c = System.now(),
                AI_RAG_Sync__c = scheduler.Id,
                Apex_Job_Id__c = jobId,
                Status__c = AIConstants.SYNC_JOB_STATUS_IN_PROGRESS
            )
        }).get(0);
    }
	
    
    /**
     * The start method is called at the beginning of the batch job execution.
     * It is responsible for providing a query locator, which defines the scope
     * of records that will be processed by the batch job.
     *
     * @param BC The Database.BatchableContext parameter provides access to the
     *           execution context of the batch job.
     * @return Iterable The iterable specifying the records to
     *         be processed by the batch job.
     */
    public Iterable<ContentVersion> start(Database.BatchableContext bc) {
        return lstOfContentVersions;
    }

    /**
     * This method is part of a Salesforce Batch Apex class and is responsible for processing a batch of ContentVersion records.
     * It is called by the Salesforce platform to execute the logic defined in the batch job.
     *
     * @param BC The Database.BatchableContext parameter provides contextual information for the batch job.
     * @param scope The List<ContentVersion> parameter represents the batch of ContentVersion records to be processed.
     */
    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) { 
        ContentVersion cv = [SELECT Id, Title, FileExtension, 
                             VersionData, ContentDocumentId, PathOnClient
                             FROM ContentVersion
                             WHERE Id =:scope.get(0).Id];
        try{     
            // V2-7480: For GCP Storage, skip datastore import in individual uploads - we'll do it in batch at the end
            // For Azure Search Direct, each upload goes directly to the index, so no separate datastore import needed
            Boolean skipDatastoreImport = isGCPStorage || isAzureSearchDirect;
            Map<String, Object> responseMap = AISyncSchedulable.pushToAI(
                EncodingUtil.base64Encode(cv.VersionData), 
                cv.PathOnClient, 
                scheduler,
                !skipDatastoreImport
            );
            
            if(responseMap != null && !responseMap.isEmpty()){
                if(responseMap.containsKey('fileId')){
                    additionalFileIds.add(String.valueOf(responseMap.get('fileId')));
                }
                if(responseMap.containsKey('fileName')){
                    additionalFileNames.add(String.valueOf(responseMap.get('fileName')));
                }
                // For non-GCP (OpenAI and Azure Search Direct), update external ID immediately
                if(!isGCPStorage && String.isBlank(scheduler.External_Id__c) && responseMap.containsKey('externalId')){
                    scheduler.External_Id__c = String.valueOf(responseMap.get('externalId'));
                    FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync__c>{scheduler});
                }
            }
        }catch (Exception e) {
            errorMessages.add('File: '+cv.PathOnClient+' - '+e.getMessage()+' \n\n '+e.getStackTraceString());
        } 
    }

    /**
     * This method is called when a batch execution finishes.
     * It provides an implementation of the finish method in the Database.Batchable interface.
     *
     * @param BC The Database.BatchableContext parameter provides context information
     *           for the batch job, such as the jobId and jobInstanceId.
     */
    public void finish(Database.BatchableContext bc) {
        try {
            // If Object is specified, chain to AISyncSObjectUploadBatch to handle large data volumes
            if(String.isNotBlank(scheduler.Object__c) && String.isNotBlank(scheduler.Fields__c)){
                // Chain to sObject upload batch - it will handle file generation, pushing, and job status update
                Integer batchSize = scheduler.Batch_Size__c != null ? Integer.valueOf(scheduler.Batch_Size__c) : 200;
                Database.executeBatch(
                    new AISyncSObjectUploadBatch(scheduler, job, additionalFileIds, additionalFileNames, errorMessages), 
                    batchSize
                );
                return;
            }
            
            // No Object specified - just finalize the job with ContentVersion uploads only
            finalizeJob();
        } catch (Exception e) {
            // If chaining fails or finalizeJob fails, ensure job status is updated
            try {
                job.Status__c = AIConstants.SYNC_JOB_STATUS_ERRORED;
                job.Message__c = 'Finish error: ' + e.getMessage() + ' \n\n ' + e.getStackTraceString();
                job.End_Date_Time__c = System.now();
                FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync_Job__c>{job});
            } catch (Exception statusEx) {
                System.debug('CRITICAL: Failed to update job status: ' + statusEx.getMessage());
            }
        }
    }
    
    /**
     * @description Finalizes the job when no sObject records need to be processed
     */
    private void finalizeJob() {
        Map<String, Object> responseMap = new Map<String, Object>();
        
        // V2-7480: For GCP Storage, perform batch datastore import with all uploaded files
        if(isGCPStorage && additionalFileNames != null && !additionalFileNames.isEmpty()){
            try{
                Boolean isGCPDiscovery = scheduler.AI_Model_Datastore_Import__c != null && 
                                         scheduler.AI_Model_Datastore_Import__r.Model__c != null &&
                                         scheduler.AI_Model_Datastore_Import__r.Model__c.containsIgnoreCase(AIConstants.GCP_DISCOVERY_ENGINE);
                
                if(isGCPDiscovery){
                    // V2-7480: Import all files in a single batch operation (supports up to 10000 files)
                    Map<String, Object> importResponse = AISyncSchedulable.importFilesToGCPDatastore(additionalFileNames, scheduler);
                    if(importResponse != null && importResponse.containsKey('externalId')){
                        responseMap.put('externalId', importResponse.get('externalId'));
                    }
                }
            }catch (Exception e) {
                errorMessages.add('Batch datastore import - '+e.getMessage()+' \n\n '+e.getStackTraceString());
            }
        }
        
        // Store file information in response
        // For GCP: fileId contains the GCS object name (e.g., "myfile.pdf")
        // For OpenAI: fileId contains the OpenAI file ID (e.g., "file-abc123")
        if(additionalFileIds != null && additionalFileIds.size() > 0){
            responseMap.put('additionalFileIds', additionalFileIds); 
        }
        
        // additionalFileNames is used internally for GCP batch import
        // Store it only if different from fileIds (for debugging/reference)
        if(isGCPStorage && additionalFileNames != null && additionalFileNames.size() > 0){
            // For GCP, fileNames are the same as fileIds, but we store them for the import URI construction
            // Only store in response for reference
            responseMap.put('additionalFileNames', additionalFileNames); 
        }
        
        if(responseMap != NULL){
            job.Response__c = JSON.serialize(responseMap); 
        }
        
        // Update job status
        if(errorMessages != null && !errorMessages.isEmpty()){
            job.Status__c = AIConstants.SYNC_JOB_STATUS_ERRORED;
            job.Message__c = String.join(errorMessages, '\n\n');
        }else{
            job.Status__c = AIConstants.SYNC_JOB_STATUS_COMPLETE;
        }
        
        job.End_Date_Time__c = System.Now();
        FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync_Job__c>{job});
        
        // Update External_Id on scheduler if not already set
        if(responseMap != NULL && responseMap.containsKey('externalId')){
            scheduler.External_Id__c = String.valueOf(responseMap.get('externalId'));
            FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync__c>{scheduler});
        }
    }
    
}