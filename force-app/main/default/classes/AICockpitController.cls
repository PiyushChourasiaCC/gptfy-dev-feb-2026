/**
 * @description Controller for Cockpit Lightning Web Component
 * Provides metrics for Time Saved, Money Saved, Active Prompts, and dashboard data
 * @author GPTfy
 * @date 2024
 */
public with sharing class AICockpitController {
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    private static final String CARD_TYPE_APIDS = 'APIDS';
    private static final String CARD_TYPE_AMODL = 'AMODL';
    
    /**
     * @description Wrapper class for Cockpit data
     */
    public class CockpitData {
        @AuraEnabled public Boolean incompleteSetup;
        @AuraEnabled public Decimal timeSavedSeconds;
        @AuraEnabled public Decimal moneySaved;
        @AuraEnabled public Integer activePrompts;
        @AuraEnabled public Integer noOfPrompts;
        @AuraEnabled public String totalSavings;
        @AuraEnabled public String usageDetail;
        @AuraEnabled public Integer noOfFeedbacks;
        @AuraEnabled public Integer noOfModels;
        @AuraEnabled public Integer noOfDataSources;
        @AuraEnabled public Integer noOfMappings;
        @AuraEnabled public Integer noOfResponses;
        @AuraEnabled public Integer scheduledPrompts;
        @AuraEnabled public Integer noOfAgents;
        @AuraEnabled public Integer noOfRAGSyncs;
        @AuraEnabled public Integer retentionDays;
        @AuraEnabled public String retentionMetric;
        @AuraEnabled public String namespace;
        
        public CockpitData() {
            this.incompleteSetup = false;
            this.timeSavedSeconds = 0;
            this.moneySaved = 0;
            this.activePrompts = 0;
            this.noOfPrompts = 0;
            this.totalSavings = '';
            this.usageDetail = '';
            this.noOfFeedbacks = 0;
            this.noOfModels = 0;
            this.noOfDataSources = 0;
            this.noOfMappings = 0;
            this.noOfResponses = 0;
            this.scheduledPrompts = 0;
            this.noOfAgents = 0;
            this.noOfRAGSyncs = 0;
            this.retentionDays = 90;
            this.retentionMetric = '';
            this.namespace = '';
        }
    }
    
    /**
     * @description Retrieves cockpit metrics including time saved, money saved, active prompts, and card metrics
     * @return CockpitData wrapper containing all metrics for the Cockpit component
     */
    @AuraEnabled
    public static CockpitData getDetails(){
        try{
            CockpitData data = new CockpitData();
            
            // Check for incomplete setup
            Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
            if(settings.Record_Pages__c == null || settings.Selected_Prompts__c == null || settings.Candidates_1__c == null){
                data.incompleteSetup = true;
            }
            
            // Query total time saved in seconds from AI_Usage_Tracking__c
            List<AggregateResult> lstOfTimeSavings = [
                SELECT SUM(Lifetime_Saving_Seconds__c) totalSeconds 
                FROM AI_Usage_Tracking__c 
                WHERE Lifetime_Saving_Seconds__c != NULL
                    AND RecordType.DeveloperName = :AIConstants.UT_RECTYPE_OBJECT
            ];
            if(lstOfTimeSavings != null && !lstOfTimeSavings.isEmpty()){
                Object totalSecondsObj = lstOfTimeSavings.get(0).get('totalSeconds');
                if(totalSecondsObj != null && String.isNotBlank(String.valueOf(totalSecondsObj))){
                    data.timeSavedSeconds = Decimal.valueOf(String.valueOf(totalSecondsObj));
                }
            }
            
            // Query total money saved from AI_Usage_Tracking__c (with RecordType filter)
            List<AggregateResult> lstOfMoneySavings = [
                SELECT SUM(Money_Saved__c) totalMoney 
                FROM AI_Usage_Tracking__c 
                WHERE RecordTypeId != NULL 
                AND RecordType.DeveloperName = :AIConstants.UT_RECTYPE_OBJECT
            ];
            if(lstOfMoneySavings != null && !lstOfMoneySavings.isEmpty()){
                Object totalMoneyObj = lstOfMoneySavings.get(0).get('totalMoney');
                if(totalMoneyObj != null && String.isNotBlank(String.valueOf(totalMoneyObj))){
                    data.moneySaved = Decimal.valueOf(String.valueOf(totalMoneyObj));
                }
            }
            
            // Query count of active prompts
            data.noOfPrompts = [
                SELECT COUNT() 
                FROM AI_Prompt__c 
                WHERE Status__c = :AIConstants.PMT_STATUS_ACTIVE
            ];
            data.activePrompts = data.noOfPrompts;
            
            // Get usage detail (active users)
            data.usageDetail = '100% Active Users';
            String prefix = '';
            if(String.isNotBlank(NAMESPACE)){
                prefix = NAMESPACE.removeEnd('__');
            }
            List<PackageLicense> lstOfLicenses = [
                SELECT AllowedLicenses, UsedLicenses 
                FROM PackageLicense 
                WHERE NamespacePrefix = :prefix AND AllowedLicenses > 0
            ];
            if(lstOfLicenses != null && !lstOfLicenses.isEmpty()){
                data.usageDetail = ((Integer)lstOfLicenses.get(0).UsedLicenses) + ' Active Users';
            }
            
            // Get other metrics
            data.noOfFeedbacks = [SELECT COUNT() FROM AI_Feedback__c WHERE Id != NULL];
            data.noOfModels = getCountActiveDataSource(CARD_TYPE_AMODL);
            data.noOfDataSources = getCountActiveDataSource(CARD_TYPE_APIDS);
            data.noOfMappings = [SELECT COUNT() FROM AI_Data_Extraction_Mapping__c WHERE Id != NULL];
            data.noOfResponses = [SELECT COUNT() FROM AI_Response__c WHERE Id != NULL];
            data.scheduledPrompts = [SELECT COUNT() FROM AI_Scheduler__c WHERE Status__c = :AIConstants.SCH_STATUS_SCHEDULED];
            
            // Get AI Agents count (Active)
            data.noOfAgents = [SELECT COUNT() FROM AI_Agent__c WHERE Status__c = :AIConstants.PMT_STATUS_ACTIVE];
            
            // Get RAG & Knowledge Base count
            data.noOfRAGSyncs = [SELECT COUNT() FROM AI_RAG_Sync__c WHERE Id != NULL];
            
            // Get retention days and active status
            data.retentionDays = 90; // Default
            data.retentionMetric = 'Setup Retention';
            
            if(Retention_Preference__c.getOrgDefaults() != null && 
               Retention_Preference__c.getOrgDefaults().Id != null){
                Retention_Preference__c retentionPref = Retention_Preference__c.getOrgDefaults();
                Boolean retentionActive = retentionPref.Active__c != null ? retentionPref.Active__c : false;
                
                if(retentionActive && retentionPref.Delete_Records_After_Days__c != null){
                    data.retentionDays = (Integer)retentionPref.Delete_Records_After_Days__c;
                    data.retentionMetric = data.retentionDays + ' Days Retention Enforced';
                }
            }
            
            // Set namespace and total savings
            data.namespace = NAMESPACE;
            data.totalSavings = data.moneySaved + ' ' + UserInfo.getDefaultCurrency();
            
            return data;
            
        }catch(Exception ex){
            GPTfyException.log(ex, 'GPTfy', '', 'AICockpitController', 'getDetails', '');
            throw new AuraHandledException(ex.getMessage());
        }
    }
    
    /**
     * @description Helper method to get count of active data sources
     * @param cardType The type of card (APIDS or AMODL)
     * @return Integer count of active data sources
     */
    private static Integer getCountActiveDataSource(String cardType){
        Set<String> activeCardConfigSet = new Set<String>();
        for(AI_Card_Configuration__c aiCardConfig : [
            SELECT Id, Name 
            FROM AI_Card_Configuration__c 
            WHERE Feature__c = :cardType AND Enabled__c = TRUE
        ]){
            activeCardConfigSet.add(aiCardConfig.Name);
        }
        
        if(activeCardConfigSet != null && !activeCardConfigSet.isEmpty()){
            if(cardType == CARD_TYPE_APIDS){
                return [SELECT COUNT() FROM AI_Data_Source__c WHERE Name IN :activeCardConfigSet];
            } else if(cardType == CARD_TYPE_AMODL){
                return [SELECT COUNT() FROM AI_Connection__c WHERE Name IN :activeCardConfigSet];
            } else{
                return 0;
            }
        } else{
            return 0;
        }
    }
}