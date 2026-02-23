/**
 * @description Controller for AI Prompts Table Component
 * @author      Salesforce Development Team
 * @date        2025-11-10
 */
public with sharing class P_PromptsTableController {
    
    /**
     * @description Wrapper class for AI Prompt data
     */
    public class PromptWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String promptName;
        @AuraEnabled public String primaryObject;
        @AuraEnabled public String connection;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public List<String> profileNames;
        @AuraEnabled public List<String> recordTypes;
        @AuraEnabled public String visibilityCondition;
        
        /**
         * @description Constructor to initialize the wrapper
         */
        public PromptWrapper(AI_Prompt__c prompt) {
            this.id = prompt.Id;
            this.promptName = prompt.Name;
            this.primaryObject = prompt.Object__c != null ? prompt.Object__c : '';
            this.connection = prompt.AI_Connection__r != null ? prompt.AI_Connection__r.Name : '';
            this.description = prompt.Description__c != null ? prompt.Description__c : '';
            this.status = prompt.Status__c != null ? prompt.Status__c : '';
            this.profileNames = prompt.Profiles__c != null ? prompt.Profiles__c.split(';') : new List<String>();
            this.recordTypes = prompt.Record_Type__c != null ? prompt.Record_Type__c.split(';') : new List<String>();
            this.visibilityCondition = prompt.Visibility_Condition__c != null ? prompt.Visibility_Condition__c : '';
        }
    }
    
    /**
     * @description Get AI Prompts filtered by Purpose (Card Name)
     * @param cardName The name of the card/purpose to filter by
     * @return List of PromptWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<PromptWrapper> getPromptsByPurpose(String cardName) {
        try {
            List<AI_Prompt__c> prompts = [
                SELECT 
                    Id,
                    Name,
                    Object__c,
                    AI_Connection__c,
                    AI_Connection__r.Name,
                    Description__c,
                    Status__c,
                    Purpose__c,
                    Profiles__c,
                    Record_Type__c,
                    Visibility_Condition__c
                FROM AI_Prompt__c
                WHERE Purpose__c = :cardName
                  AND Status__c IN ('Active', 'Draft')
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT 1000
            ];
            
            // Convert to wrapper
            List<PromptWrapper> wrapperList = new List<PromptWrapper>();
            for (AI_Prompt__c prompt : prompts) {
                wrapperList.add(new PromptWrapper(prompt));
            }
            
            return wrapperList;
            
        } catch (System.QueryException qe) {
            throw new AuraHandledException('Query Exception: ' + qe.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('An unexpected error occurred: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get all AI Prompts without filter
     * @return List of AI_Prompt__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<AI_Prompt__c> getAllPrompts() {
        try {
            List<AI_Prompt__c> prompts = [
                SELECT 
                    Id,
                    Name,
                    Object__c,
                    AI_Connection__c,
                    AI_Connection__r.Name,
                    Description__c,
                    Status__c,
                    Purpose__c
                FROM AI_Prompt__c
                WHERE Status__c IN ('Active', 'Draft')
                WITH USER_MODE
                ORDER BY Purpose__c ASC, Name ASC
                LIMIT 1000
            ];
            
            return prompts;
            
        } catch (System.QueryException qe) {
            throw new AuraHandledException('Query Exception: ' + qe.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('An unexpected error occurred: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get unique purposes for the tabs
     * @return List of unique purpose values
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getUniquePurposes() {
        try {
            List<String> purposes = new List<String>();
            
            // Query distinct purposes
            List<AggregateResult> results = [
                SELECT Purpose__c
                FROM AI_Prompt__c
                WHERE Purpose__c != null
                  AND Status__c IN ('Active', 'Draft')
                WITH USER_MODE
                GROUP BY Purpose__c
                ORDER BY Purpose__c ASC
            ];
            
            for (AggregateResult ar : results) {
                String purpose = (String)ar.get('Purpose__c');
                if (String.isNotBlank(purpose)) {
                    purposes.add(purpose);
                }
            }
            
            return purposes;
            
        } catch (Exception e) {
            throw new AuraHandledException('An unexpected error occurred: ' + e.getMessage());
        }
    }
}