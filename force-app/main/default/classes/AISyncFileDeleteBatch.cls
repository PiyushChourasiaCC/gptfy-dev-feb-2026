/**
* @description       : 
* @author            : Adarsh Sharma
* @group             : Plumcloud Labs
* @last modified on  : 11-18-2025
* @last modified by  : Adarsh Sharma
* @JIRA V2-7334 : File based RAG Sync
**/
public class AISyncFileDeleteBatch implements Database.Batchable<String>, Database.Stateful, Database.AllowsCallouts {
    
 	public List<ContentVersion> lstOfContentVersions;
    public AI_RAG_Sync__c scheduler;
    public String jobId;
    public List<String> fileIds;
    
    /**
     * Constructs an instance of AISyncFileDeleteBatch.
     *
     * This constructor is used to create a batch job for extracting data related to RAG Sync.
     *
     * @param lstOfContentVersions Files uploaded to RAG Sync.
     * @param scheduler The specific scheduled run details, including the start time and other run-related information.
     * @param jobId The specific scheduled run RAG Sync Job details, including the start time and other run-related information.
     * @param fileId Vector Source file Id.
     */
    public AISyncFileDeleteBatch(List<ContentVersion> lstOfContentVersions, AI_RAG_Sync__c scheduler, String jobId, List<String> fileIds){
        this.lstOfContentVersions = lstOfContentVersions;
        this.scheduler = scheduler;
        this.jobId = jobId;
        this.fileIds = fileIds;
    }
    
    /**
     * The start method is called at the beginning of the batch job execution.
     * It is responsible for providing a query locator, which defines the scope
     * of records that will be processed by the batch job.
     *
     * @param BC The Database.BatchableContext parameter provides access to the
     *           execution context of the batch job.
     * @return Database.QueryLocator The query locator specifying the records to
     *         be processed by the batch job.
     */
    public Iterable<String> start(Database.BatchableContext bc){
        return fileIds;
    }
    
    /**
     * This method is part of a Salesforce Batch Apex class and is responsible for processing a batch of AI_RAG_Sync__c records.
     * It is called by the Salesforce platform to execute the logic defined in the batch job.
     *
     * @param BC The Database.BatchableContext parameter provides contextual information for the batch job.
     * @param scope The List<AI_RAG_Sync__c> parameter represents the batch of AI_RAG_Sync__c records to be processed.
     */
    public void execute(Database.BatchableContext BC, List<String> scope){
        try{
            String fileIdToDelete = scope.get(0);
            
            if(scheduler.AI_Model_File_Upload__c != null && scheduler.AI_Model_File_Upload__r.Model__c.containsIgnoreCase(AIConstants.GCP_FILE_UPLOAD)){
                String fileUploadAddParams = scheduler.AI_Model_File_Upload__c != null ? scheduler.AI_Model_File_Upload__r.Additional_Parameters__c : null;
                Map<String, Object> mapOfFileUploadAdditionalParams;
                if(String.isNotBlank(fileUploadAddParams)){
                    mapOfFileUploadAdditionalParams = (Map<String, Object>)JSON.deserializeUntyped(fileUploadAddParams);
                }
                String bucketName = String.valueOf(mapOfFileUploadAdditionalParams.get('bucketName'));
                AISyncSchedulable.deleteFileFromGCP(scheduler, bucketName, fileIdToDelete);
            }else{
                AIResponsesApiCalloutUtility.ResponseApiWrapper wrap = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
                wrap.aiModel = scheduler.AI_Model_File_Upload__r;
                wrap.vectorStoreId = scheduler.External_Id__c;
                wrap.fileId = fileIdToDelete;
                wrap = AIResponsesApiCalloutUtility.deleteFileFromVectorStore(wrap);
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISyncFileDeleteBatch', 'execute', '{"fileId":"'+fileIds.get(0)+'", "vectorStoreId":"'+scheduler.External_Id__c+'"}');
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
        Database.executeBatch(new AISyncFileUploadBatch(lstOfContentVersions, scheduler, jobId), 1);
    }
}