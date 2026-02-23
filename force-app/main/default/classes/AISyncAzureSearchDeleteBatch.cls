/**
 * @description Batch class to delete all documents from Azure AI Search index before uploading new data
 *              This batch queries document IDs from the index and deletes them in batches to handle
 *              large indexes (100,000+ documents) while respecting Salesforce governor limits
 * V2-7438, V2-7599: Azure AI Search Direct integration
 * @author Plumcloud Labs
 * @group GPTfy
 */
public class AISyncAzureSearchDeleteBatch implements Database.Batchable<String>, Database.Stateful, Database.AllowsCallouts {
    
    private AI_RAG_Sync__c scheduler;
    private List<ContentVersion> lstOfContentVersions;
    private String jobId;
    private List<String> documentIdsToDelete;
    private Integer totalDeleted;
    private String indexName;
    private String apiVersion;
    private Boolean hasMoreDocuments;
    private List<String> errorMessages;
    
    /**
     * @description Constructor for AISyncAzureSearchDeleteBatch
     * @param lstOfContentVersions Files to be uploaded after deletion
     * @param scheduler The AI_RAG_Sync__c record containing configuration
     * @param jobId The job ID for tracking
     */
    public AISyncAzureSearchDeleteBatch(List<ContentVersion> lstOfContentVersions, AI_RAG_Sync__c scheduler, String jobId) {
        this.lstOfContentVersions = lstOfContentVersions;
        this.scheduler = scheduler;
        this.jobId = jobId;
        this.documentIdsToDelete = new List<String>();
        this.totalDeleted = 0;
        this.hasMoreDocuments = true;
        this.errorMessages = new List<String>();
        
        // Parse additional parameters for Azure Search configuration
        String fileUploadAddParams = scheduler.AI_Model_File_Upload__c != null ? 
                                     scheduler.AI_Model_File_Upload__r.Additional_Parameters__c : null;
        if (String.isNotBlank(fileUploadAddParams)) {
            Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(fileUploadAddParams);
            this.indexName = String.valueOf(params.get('indexName'));
            this.apiVersion = params.containsKey('apiVersion') ? 
                             String.valueOf(params.get('apiVersion')) : '2024-07-01';
        }
    }
    
    /**
     * @description Start method - fetches document IDs from Azure Search index
     * @param bc The batch context
     * @return Iterable<String> List of document IDs to delete
     */
    public Iterable<String> start(Database.BatchableContext bc) {
        // Fetch document IDs from Azure Search index
        // We fetch in the start method to get all IDs before processing
        if (String.isBlank(indexName)) {
            return new List<String>();
        }
        
        try {
            fetchDocumentIds();
        } catch (Exception e) {
            errorMessages.add('Failed to fetch document IDs: ' + e.getMessage());
        }
        
        return documentIdsToDelete;
    }
    
    /**
     * @description Fetches all document IDs from the Azure Search index using pagination
     */
    private void fetchDocumentIds() {
        String namedCredential = scheduler.AI_Model_File_Upload__r.Named_Credential__c;
        Integer batchCount = 0;
        Integer maxBatches = 100; // Safety limit: 100 batches * 1000 docs = 100,000 max
        
        while (hasMoreDocuments && batchCount < maxBatches) {
            String searchEndpoint = 'callout:' + namedCredential + 
                                   '/indexes/' + EncodingUtil.urlEncode(indexName, 'UTF-8') + 
                                   '/docs?api-version=' + apiVersion + 
                                   '&$select=id&$top=1000';
            
            // Add skip for pagination (after first batch)
            if (batchCount > 0) {
                searchEndpoint += '&$skip=' + (batchCount * 1000);
            }
            
            Map<String, String> headers = new Map<String, String>{
                'Content-Type' => 'application/json'
            };
            
            HttpResponse resp = AISyncSchedulable.doCallout(null, null, headers, searchEndpoint, 'GET');
            
            if (resp.getStatusCode() > 210) {
                errorMessages.add('Failed to query Azure Search: ' + resp.getBody());
                break;
            }
            
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            List<Object> documents = (List<Object>) result.get('value');
            
            if (documents == null || documents.isEmpty()) {
                hasMoreDocuments = false;
                break;
            }
            
            for (Object doc : documents) {
                Map<String, Object> docMap = (Map<String, Object>) doc;
                String docId = String.valueOf(docMap.get('id'));
                if (String.isNotBlank(docId)) {
                    documentIdsToDelete.add(docId);
                }
            }
            
            // Check if we got less than 1000 documents (end of index)
            if (documents.size() < 1000) {
                hasMoreDocuments = false;
            }
            
            batchCount++;
        }
        
        System.debug('Fetched ' + documentIdsToDelete.size() + ' document IDs for deletion from Azure Search index: ' + indexName);
    }
    
    /**
     * @description Execute method - deletes documents in batches
     * @param bc The batch context
     * @param scope List of document IDs to delete in this batch
     */
    public void execute(Database.BatchableContext bc, List<String> scope) {
        if (scope == null || scope.isEmpty() || String.isBlank(indexName)) {
            return;
        }
        
        try {
            String namedCredential = scheduler.AI_Model_File_Upload__r.Named_Credential__c;
            
            // Build delete actions for all documents in scope
            List<Object> deleteActions = new List<Object>();
            for (String docId : scope) {
                Map<String, Object> deleteAction = new Map<String, Object>{
                    '@search.action' => 'delete',
                    'id' => docId
                };
                deleteActions.add(deleteAction);
            }
            
            // Send batch delete request
            Map<String, Object> deleteReqBody = new Map<String, Object>{
                'value' => deleteActions
            };
            
            String deleteEndpoint = 'callout:' + namedCredential + 
                                   '/indexes/' + EncodingUtil.urlEncode(indexName, 'UTF-8') + 
                                   '/docs/index?api-version=' + apiVersion;
            
            Map<String, String> headers = new Map<String, String>{
                'Content-Type' => 'application/json'
            };
            
            HttpResponse resp = AISyncSchedulable.doCallout(JSON.serialize(deleteReqBody), null, headers, deleteEndpoint, 'POST');
            
            if (resp.getStatusCode() <= 210) {
                totalDeleted += scope.size();
            } else {
                errorMessages.add('Failed to delete batch: ' + resp.getBody());
            }
        } catch (Exception e) {
            errorMessages.add('Delete batch error: ' + e.getMessage());
        }
    }
    
    /**
     * @description Finish method - chains to AISyncFileUploadBatch after deletion completes
     * @param bc The batch context
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('Azure Search delete completed. Total deleted: ' + totalDeleted + ' documents from index: ' + indexName);
        
        if (!errorMessages.isEmpty()) {
            System.debug('Azure Search delete errors: ' + String.join(errorMessages, '; '));
        }
        
        try {
            // Chain to the file upload batch, passing any error messages
            AISyncFileUploadBatch uploadBatch = new AISyncFileUploadBatch(lstOfContentVersions, scheduler, jobId);
            // Pass error messages to the next batch so they are included in job status
            if (!errorMessages.isEmpty()) {
                uploadBatch.errorMessages.addAll(errorMessages);
            }
            Database.executeBatch(uploadBatch, 1);
        } catch (Exception e) {
            // If chaining fails, create job record and mark as errored
            try {
                AI_RAG_Sync_Job__c job = new AI_RAG_Sync_Job__c(
                    Start_Date_Time__c = System.now(),
                    End_Date_Time__c = System.now(),
                    AI_RAG_Sync__c = scheduler.Id,
                    Apex_Job_Id__c = jobId,
                    Status__c = AIConstants.SYNC_JOB_STATUS_ERRORED,
                    Message__c = 'Azure Search Delete batch failed to chain: ' + e.getMessage() + 
                                (errorMessages.isEmpty() ? '' : '\n\nPrevious errors:\n' + String.join(errorMessages, '\n'))
                );
                FLSCheck.getInstance().insertDML(new List<AI_RAG_Sync_Job__c>{job});
            } catch (Exception jobEx) {
                System.debug('CRITICAL: Failed to create error job record: ' + jobEx.getMessage());
            }
        }
    }
}