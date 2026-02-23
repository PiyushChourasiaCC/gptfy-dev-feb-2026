/**
 * @description:
 *   AIDeleteExpiredVectorStoresBatch is a schedulable batch Apex class responsible for cleaning up
 *   expired vector stores from OpenAI. It queries AI_Response__c records with vector store IDs,
 *   checks if sessions have expired based on TTL (Time To Live) configuration, and deletes the
 *   associated vector stores from OpenAI to prevent unnecessary storage costs. The batch processes
 *   records in chunks of 50 to stay within Salesforce callout limits. Implements Database.Batchable,
 *   Database.AllowsCallouts for API interactions, and Schedulable for automated execution.
 *
 * @author             : Piyush Chourasia
 * @group              : Plumcloud Labs
 * @last modified on   : 05-11-2025
 * @last modified by   : Piyush Chourasia
 * @jira               : [V2-7341]
 */
global class AIDeleteExpiredVectorStoresBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    
   /**
     * @description: Schedulable execute method that initiates the batch job.
     *               This method is called by the Salesforce scheduler and kicks off the batch
     *               processing with a batch size of 50 to ensure we stay within the governor limit
     *               of 100 callouts per transaction (each batch can make up to 50 DELETE callouts).
     * @param sc SchedulableContext provided by the Salesforce scheduler
     * @jira: [V2-7341]
     */
    global void execute(SchedulableContext sc) {
        // Execute the batch with batch size of 50 to stay within callout limits (max 100 per transaction)
        Database.executeBatch(this, 50);
    }
    
    /**
     * @description: Batch start method that builds the query for AI_Response__c records to process.
     *               Queries all records that have a Vector_Store_Id__c and Agent_Name__c populated,
     *               ordered by CreatedDate ascending to process oldest records first. Uses SOQL
     *               QueryLocator for optimal memory usage when processing large data volumes.
     * @param bc BatchableContext provided by the batch framework
     * @return Database.QueryLocator containing the query for AI_Response__c records with vector stores
     * @jira: [V2-7341]
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Query all AI_Response__c records where Session_Expired__c is true or Vector_Store_Id__c is not null
        return Database.getQueryLocator([
            SELECT Id, 
                   Name, 
                   Vector_Store_Id__c, 
                   Session_Expired__c,
                   Agent_Name__c,
                   CreatedDate
            FROM AI_Response__c 
            WHERE Vector_Store_Id__c != null
                AND Agent_Name__c != null
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ]);
    }
    
    /**
     * @description: Batch execute method that processes each batch of AI_Response__c records.
     *               For each record, retrieves the associated AI Agent configuration to get TTL settings,
     *               checks if the session has expired based on Session_Expired__c flag or TTL calculation,
     *               and delegates the vector store deletion to AIGlobalUtility. Includes error handling
     *               to ensure one failed deletion doesn't break the entire batch.
     * @param bc BatchableContext provided by the batch framework
     * @param scope List of AI_Response__c records in the current batch (max 50 records)
     * @jira: [V2-7341]
     */
    global void execute(Database.BatchableContext bc, List<AI_Response__c> scope) {
        try {
            List<AI_Response__c> aiResponses = new List<AI_Response__c>();
            Set<String> agentNames = new Set<String>();
            Map<String, AI_Agent__c> agentMap = new Map<String, AI_Agent__c>(); 
    
            for(AI_Response__c aiResp : scope) {
                if(String.isNotBlank(aiResp.Agent_Name__c)) {
                    agentNames.add(aiResp.Agent_Name__c);
                }
            }
    
            List<AI_Agent__c> agents = [    
                SELECT Developer_Name__c, AI_Model__r.Named_Credential__c, TTL__c, Name
                FROM AI_Agent__c 
                WHERE Name IN :agentNames 
                    AND TTL__c != null
                WITH SECURITY_ENFORCED
                LIMIT 100
            ];
    
            if(agents.isEmpty()) {
                return; // No agents found, nothing to process
            }
    
            for(AI_Agent__c agent : agents) {
                agentMap.put(agent.Name, agent);
            }
          
            for (AI_Response__c aiResponse : scope) {
                try {
                    if(isSessionExpired(aiResponse, agentMap.get(aiResponse.Agent_Name__c).TTL__c)) {
                        aiResponses.add(aiResponse);
                    }
                } catch (Exception e) {
                    // do not update the record if deletion fails
                }
            }
            if(aiResponses.isEmpty()) {
                return; // No expired sessions to process
            }   
            AIGlobalUtility.deleteExpiredVectorStores(aiResponses);
        } catch(Exception ex) {
            createErrorLog('Batch execution failed: ' + ex.getMessage());
        }
    }
    
    /**
     * @description Batch finish method - performs cleanup and sends notification
     * @param bc BatchableContext
     */
    global void finish(Database.BatchableContext bc) {
    }
     /**
     * @description: Determines if an AI Response record's session has expired based on two criteria:
     *               1. Session_Expired__c flag is explicitly set to true, OR
     *               2. Current time exceeds CreatedDate + TTL minutes (TTL from agent configuration)
     *               This dual check ensures both manual expiration flags and automatic TTL-based
     *               expiration are handled correctly.
     * @param record AI_Response__c record to check for expiration
     * @param ttlMinutes Time To Live in minutes from the AI Agent configuration
     * @return Boolean true if the session has expired, false otherwise
     * @jira: [V2-7341]
     */
    global static Boolean isSessionExpired(AI_Response__c record, Decimal ttlMinutes){
        if(record.Session_Expired__c == true){
            return true;
        }
        if(DateTime.now() > record.CreatedDate.addMinutes(Integer.valueOf(ttlMinutes))){
            return true;
        }
        return false;
    }
     /**
     * @description: Creates an Exception_Log__c record to track batch processing failures.
     *               Captures error details including message, exception type, application context,
     *               module information, and the running user. Only creates logs if exception logging
     *               is enabled via AIConstants.enableExceptionLog flag. Uses FLSCheck for
     *               field-level security compliance during DML operations.
     * @param errorMessage The error message to log
     * @jira: [V2-7341](https://cloudcompliance.atlassian.net/browse/V2-7341)
     */
    global void createErrorLog(String errorMessage) {
        //Create exception record
        Exception_Log__c exc = new Exception_Log__c();
        if(String.isNotBlank(errorMessage)){
            exc.Error_Message__c = errorMessage;
            exc.Exception_Type__c = 'Batch Processing Exception';
        }
        exc.Application_Name__c = 'AI Integration';
        exc.Module_Name__c = 'AIDeleteExpiredVectorStoresBatch';
        exc.Class_Name__c  = 'AIDeleteExpiredVectorStoresBatch';
        exc.Method_Name__c = 'execute';
        exc.Exception_Running_User__c = UserInfo.getUserId();
        if(AIConstants.enableExceptionLog){
            FLSCheck.getInstance().insertDML(new List<Exception_Log__c>{exc});
        }
    }
}