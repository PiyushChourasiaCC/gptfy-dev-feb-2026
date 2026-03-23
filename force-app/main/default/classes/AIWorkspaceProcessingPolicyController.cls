/**
 * @description       : Controller for AI Workspace Processing Policy Component
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 03-12-2026
 * @last modified by  : Rishabh Goel
 **/
public with sharing class AIWorkspaceProcessingPolicyController {
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    
    /**
     * Retrieves a list of active standard users ordered by Name.
     * 
     * @return List<FieldWrapper> A list of FieldWrapper objects containing user Username and Name
     */
    @AuraEnabled
    public static List<FieldWrapper> getUsers(){
        try{
            List<FieldWrapper> userOptions = new List<FieldWrapper>();
            for(User u : [SELECT Id, Name, Username FROM User WHERE IsActive = true AND UserType = 'Standard' ORDER BY Name LIMIT 50000]){
                FieldWrapper wrap = new FieldWrapper();
                wrap.label = u.Name;
                wrap.value = u.Username;
                userOptions.add(wrap);
            }
            return userOptions;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIWorkspaceProcessingPolicyController', 'getUsers', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the policy data for the specified record ID.
     * 
     * @param recordId The ID of the policy record to retrieve
     * @return PolicyWrapper A PolicyWrapper object containing the policy data
     */
    @AuraEnabled
    public static PolicyWrapper getPolicyData(String recordId){
        try{
            PolicyWrapper wrap = new PolicyWrapper();
            
            if(String.isNotBlank(recordId)){
                List<AI_Workspace_Processing_Policy__c> policies = [SELECT Id, Name, Prompt__c, Users__c, Profiles__c FROM AI_Workspace_Processing_Policy__c WHERE Id = :recordId LIMIT 1];
                
                if(!policies.isEmpty()){
                    AI_Workspace_Processing_Policy__c policy = policies.get(0);
                    wrap.policyName = String.valueOf(policy.Name);
                    wrap.promptId = String.valueOf(policy.Prompt__c);
                    wrap.userIds = String.valueOf(policy.Users__c);
                    wrap.profileIds = String.valueOf(policy.Profiles__c);
                }
            }
            
            return wrap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIWorkspaceProcessingPolicyController', 'getPolicyData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Saves or updates a workspace processing policy record.
     * 
     * @param data Map containing the policy field values
     * @return String The ID of the saved policy record
     */
    @AuraEnabled
    public static String savePolicy(Map<String, Object> data){
        String recordId = String.valueOf(data.get('recordId'));
        AI_Workspace_Processing_Policy__c policy = new AI_Workspace_Processing_Policy__c();
        if(String.isNotBlank(recordId)){
            policy.Id = recordId;
        }
        if(data.containsKey('policyName') && data.get('policyName') != null){
            policy.Name = String.valueOf(data.get('policyName'));
        }
        if(data.containsKey('promptId') && data.get('promptId') != null){
            policy.Prompt__c = String.valueOf(data.get('promptId'));
        }
        if(data.containsKey('userIds')){
            policy.Users__c = String.valueOf(data.get('userIds'));
        }
        if(data.containsKey('profileIds')){
            policy.Profiles__c = String.valueOf(data.get('profileIds'));
        }
        policy = (AI_Workspace_Processing_Policy__c)FLSCheck.getInstance().upsertDML(new List<AI_Workspace_Processing_Policy__c>{policy}).get(0);
        
        return String.valueOf(policy.get('Id'));
    }
    
    public class PolicyWrapper{
        @AuraEnabled public String policyName{get;set;}
        @AuraEnabled public String promptId{get;set;}
        @AuraEnabled public String userIds{get;set;}
        @AuraEnabled public String profileIds{get;set;}
    }
    
    public class FieldWrapper implements Comparable{
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public String value{get;set;}
        
        public Integer compareTo(Object objToCompare) {
            return label.compareTo(((FieldWrapper)objToCompare).label);
        }
    }
}