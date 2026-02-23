global with sharing class AIRetentionScheduler implements Database.Batchable<sObject>, Schedulable, Database.Stateful {
    
    public static final String NAMESPACE = AIPromptController.NAMESPACE;
    public Integer recordCount = 0;
    
    /**
     * This method is the entry point for the scheduled job execution.
     * It is called by the system scheduler when the scheduled job is triggered.
     *
     * @param SC The SchedulableContext parameter provides context information
     *           and allows interaction with the scheduler during execution.
     *           It can be used to access job-related information and control
     *           certain aspects of the scheduled job.
     */
    global void execute(SchedulableContext SC) {
        Database.executeBatch(new AIRetentionScheduler(), 2000);
    }
    
    /**
     * The start method is used to initialize and provide the initial set of records
     * for processing in a batch job. It returns a QueryLocator, which defines the
     * scope of records to be processed.
     *
     * @param BC The batchable context containing information about the batch job.
     * @return Database.QueryLocator representing the initial set of records to process.
     */
     global Database.QueryLocator start(Database.BatchableContext BC){
        Integer noOfDays;
        String whereClause = '';
        this.recordCount = 0;
        
        if(Retention_Preference__c.getOrgDefaults() != null && Retention_Preference__c.getOrgDefaults().Id != null && Retention_Preference__c.getOrgDefaults().Active__c && Retention_Preference__c.getOrgDefaults().Delete_Records_After_Days__c != null){
            Retention_Preference__c rp = Retention_Preference__c.getOrgDefaults();
            noOfDays = (Integer) rp.Delete_Records_After_Days__c;
            if(String.isNotBlank(rp.Where_Clause__c)){
            	whereClause = rp.Where_Clause__c.trim();
        	}
        }
        DateTime currentTime = System.Now();
        if(noOfDays > 0){
			currentTime = currentTime.addDays((-1) * noOfDays);            
        }
        String query = ' SELECT Id FROM '+NAMESPACE+'AI_Response__c ';
        // @jira : 4662 Handle ORDER BY in Where Clause of Data Extraction
        Boolean isLimit0 = false;
        if(noOfDays != null && noOfDays > 0){
            // nothing
        }else{
			isLimit0 = true;
        }
         
        whereClause = AIUtility.getFormattedWhereClause(whereClause,NULL,NULL,isLimit0);
        if(!isLimit0 && whereClause.containsIgnoreCase(' WHERE Id != NULL ')){
               whereClause = whereClause.replace(' WHERE Id != NULL ',' WHERE CreatedDate < :currentTime ');
        } 
        
        query += whereClause;
        return Database.getQueryLocator(query);
    }
    
    /**
     * Implements the execute method required for a Salesforce Batch Apex class.
     * This method is invoked to process a batch of AI_Response__c records.
     *
     * @param BC The Database.BatchableContext parameter provides information about the execution context.
     * @param scope A List of AI_Response__c records representing the batch of data to be processed.
     */
    global void execute(Database.BatchableContext BC, List<AI_Response__c> scope){
        if(scope != null && !scope.isEmpty()){
            this.recordCount += scope.size();
            FLSCheck.getInstance().deleteDML(scope);
        }
    }
    
    /**
     * The finish method is called after all batches of records have been processed
     * by the execute method. It provides an opportunity to perform any final 
     * operations or cleanup tasks. This method is part of the Database.Batchable 
     * interface in Salesforce Apex.
     * 
     * @param BC The Database.BatchableContext parameter provides information about 
     * the context in which the batch job is running. It can be used to obtain 
     * information about the job or to perform certain operations.
     */
    global void finish(Database.BatchableContext BC){
        if(Retention_Preference__c.getOrgDefaults() != null && Retention_Preference__c.getOrgDefaults().Id != null && Retention_Preference__c.getOrgDefaults().Active__c && Retention_Preference__c.getOrgDefaults().Delete_Records_After_Days__c != null){
            Retention_Preference__c pref = Retention_Preference__c.getOrgDefaults();
            Integer initCount = pref.Records_Purged__c != null ? (Integer)pref.Records_Purged__c : 0;
            pref.Records_Purged__c = initCount + this.recordCount;
            pref.Last_Ran_Date_Time__c = System.Now();
            FLSCheck.getInstance().updateDML(new List<Retention_Preference__c>{pref});
        }
    }
    
}