public with sharing class AITeamsBotsController {
    public static final String NAMESPACE = AIPromptController.getNameSpace();

    @AuraEnabled
    public static Map<String, Object> getPromptOptions(String recordId, String objectApiName){  
        
        String l_namespace = NAMESPACE;
        if(String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')){
            l_namespace = l_namespace.removeEndIgnoreCase('__');
        }
        
        List<PermissionSetAssignment> permSetAssignments = [SELECT Id FROM PermissionSetAssignment 
                                                            WHERE AssigneeId =:UserInfo.getUserId()
                                                            AND (PermissionSet.Name =:AIConstants.GPTFY_ADMIN_PERM_SET
                                                            OR PermissionSet.Name =:AIConstants.GPTFY_USER_PERM_SET
                                                            OR PermissionSet.Name =:AIConstants.GPTFY_PORTAL_PERM_SET)
                                                            AND PermissionSet.NamespacePrefix =:l_namespace];
        if(permSetAssignments == null || permSetAssignments.isEmpty()){
            return null;
        }
        
        if(String.isBlank(objectApiName) && String.isNotBlank(recordId)){
            objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
        }
        
        String profileName = [SELECT Id, Name FROM Profile WHERE Id =:UserInfo.getProfileId() LIMIT 1].Name;
        String status = 'Active';
        
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        List<OptionWrapper> options = new List<OptionWrapper>();
        Map<String, AI_Prompt__c> mapOfPrompt = new Map<String, AI_Prompt__c>();
        for(AI_Prompt__c pmt : [SELECT Id, Name, Description__c,Prompt_Request_Id__c,Profiles__c
                                FROM AI_Prompt__c 
                                WHERE Status__c =:status AND Object__c =:objectApiName AND AI_Data_Extraction_Mapping__c != NULL]){
            if((String.isBlank(pmt.Profiles__c) || pmt.Profiles__c.containsIgnoreCase(profileName))){
                mapOfPrompt.put(pmt.Id, pmt);
                OptionWrapper opt = new OptionWrapper();
                opt.label = pmt.Name;
                opt.value = pmt.Id;
                opt.promptDescription = pmt.Description__c;
                opt.promptRequestedId = pmt.Prompt_Request_Id__c;
                options.add(opt);
            }
        }
        
        Map<String, Object> data = new Map<String, Object>();
        
        if(options != null && !options.isEmpty()){
            options.sort();
        }
        data.put('options', options);

        return data;
    }

    public class OptionWrapper implements Comparable{
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public String promptDescription {get;set;}
        @AuraEnabled public String promptRequestedId {get;set;}
        
        public Integer compareTo(Object objToCompare) {
        	return label.compareTo(((OptionWrapper)objToCompare).label);
        }
    }
}