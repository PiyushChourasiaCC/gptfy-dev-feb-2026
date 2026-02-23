/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 01-31-2024
* @last modified by  : Rishabh Goel
**/
public with sharing class AISetupAssistantController {
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    public static Map<String, Schema.SObjectType> schemaMap;
    static{
        schemaMap = Schema.getGlobalDescribe();
    }
    
    @AuraEnabled
    public static Boolean checkPermissionSet(){
        String adminPS = 'SGPT_Admin';
        String l_namespace = NAMESPACE;
        if(String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')){
            l_namespace = l_namespace.removeEndIgnoreCase('__');
        }
        List<PermissionSetAssignment> psas = [SELECT Id FROM PermissionSetAssignment 
                                              WHERE PermissionSet.Name =:adminPS 
                                              AND AssigneeId = :UserInfo.getUserId()
                                              AND PermissionSet.NamespacePrefix =:l_namespace];
        
        Boolean permSetAssigned = false;
        if(psas != null && !psas.isEmpty()){
            permSetAssigned = true;
        }
        return permSetAssigned;
    }
	
    @AuraEnabled
    public static List<Object> getPromptOptions(){  
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        Set<String> selectedPromptIds = new Set<String>();
        if(settings.Selected_Prompts__c != null && String.isNotBlank(settings.Selected_Prompts__c)){
            selectedPromptIds = new Set<String>(settings.Selected_Prompts__c.split(','));
        }
        
        List<AI_Prompt__c> lstOfPrompts = [SELECT Id, Name, Description__c, Object__c 
                                           FROM AI_Prompt__c 
                                           WHERE Status__c =:AIConstants.PMT_STATUS_ACTIVE
                                           AND Pre_Packaged__c = True
                                           ORDER BY Object__c, Name];
        
        List<Object> data = new List<Object>();
        if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
            for(AI_Prompt__c pmt : lstOfPrompts){
                Schema.DescribeSObjectResult describeObj = schemaMap.get(pmt.Object__c).getDescribe();
                Boolean selected = false;
                if(!selectedPromptIds.isEmpty() && selectedPromptIds.contains(pmt.Id)){
                    selected = true;
                }
                data.add(new Map<String, Object>{
                    'id' => pmt.Id,
                    'name' => pmt.Name,
                    'description' => pmt.Description__c,
                    'objectName' => pmt.Object__c,
                    'objectLabel' => describeObj.getLabel(),
                    'iconName' => 'standard:'+pmt.Object__c.toLowerCase(),
                    'selected' => selected
                });
            }
        }
        return data;
    }
    
    @AuraEnabled
    public static List<String> getSelectedRecordPages(){
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        if(settings.Record_Pages__c != null && String.isNotBlank(settings.Record_Pages__c)){
            return settings.Record_Pages__c.split(',');
        }
        return null;
    }
    
    @AuraEnabled
    public static void updateSelectedPromptSettings(List<String> promptIds){
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        settings.Selected_Prompts__c = promptIds != null && promptIds.size() > 0 ? String.join(promptIds, ',') : '';
        FLSCheck.getInstance().upsertDML(new List<Setup_Settings__c>{settings});
    }
    
    @AuraEnabled
    public static void updateRecordPageSettings(List<String> objNames){
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        settings.Record_Pages__c = objNames != null && objNames.size() > 0 ? String.join(objNames, ',') : '';
        FLSCheck.getInstance().upsertDML(new List<Setup_Settings__c>{settings});
    }
    
    @AuraEnabled
    public static void startDataReview(List<String> promptIds){
        updateCandidateSettings(null);
        
        Integer batchSize = 50;
        AICandidateIdentificationBatch job = new AICandidateIdentificationBatch();
        job.promptIds = promptIds;
        job.BATCH_SIZE = batchSize;
        Database.executeBatch(job, batchSize);
    }
    
    @AuraEnabled
    public static void completeDataReview(List<String> promptIds){
        Map<String, Object> mapOfCandidates = new Map<String, Object>();
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        if(settings.Candidates_1__c != null){
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(settings.Candidates_1__c);
            if(m != null && !m.isEmpty()){
                mapOfCandidates.putAll(m);
            }
        }if(settings.Candidates_2__c != null){
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(settings.Candidates_2__c);
            if(m != null && !m.isEmpty()){
                mapOfCandidates.putAll(m);
            }
        }if(settings.Candidates_3__c != null){
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(settings.Candidates_3__c);
            if(m != null && !m.isEmpty()){
                mapOfCandidates.putAll(m);
            }
        }if(settings.Candidates_4__c != null){
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(settings.Candidates_4__c);
            if(m != null && !m.isEmpty()){
                mapOfCandidates.putAll(m);
            }
        }
        
        for(String pmtId : promptIds){
            if(!mapOfCandidates.containsKey(pmtId)){
                mapOfCandidates.put(pmtId, 'NO_RECORD_FOUND');
            }
        }
        
        if(!mapOfCandidates.isEmpty()){
            Map<String, String> tempMap = new Map<String, String>();
            for(String key : mapOfCandidates.keySet()){
                tempMap.put(key, String.valueOf(mapOfCandidates.get(key)));
            }
            updateCandidateSettings(tempMap);
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> checkDataReviewStatus(){
        Map<String, Object> data = new Map<String, Object>();
        String namespace = AIPromptController.NAMESPACE;
        if(String.isNotBlank(namespace) && namespace.endsWithIgnoreCase('__')){
            namespace = namespace.removeEnd('__');
        }
        List<AsyncApexJob> lstOfJobs = [SELECT Id 
                                        FROM AsyncApexJob 
                                        WHERE Status IN ('Holding', 'Preparing', 'Processing', 'Queued')
                                       	AND ApexClass.NamespacePrefix =:namespace
                                        AND ApexClass.Name = 'AICandidateIdentificationBatch'];
        if(lstOfJobs != null && !lstOfJobs.isEmpty()){
            data.put('isReviewRunning', true);
        }else{
            data.put('isReviewRunning', false);
        }
        
        Map<String, Object> mapOfCandidates = new Map<String, Object>();
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        if(settings.Candidates_1__c != null){
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(settings.Candidates_1__c);
            if(m != null && !m.isEmpty()){
                mapOfCandidates.putAll(m);
            }
        }if(settings.Candidates_2__c != null){
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(settings.Candidates_2__c);
            if(m != null && !m.isEmpty()){
                mapOfCandidates.putAll(m);
            }
        }if(settings.Candidates_3__c != null){
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(settings.Candidates_3__c);
            if(m != null && !m.isEmpty()){
                mapOfCandidates.putAll(m);
            }
        }if(settings.Candidates_4__c != null){
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(settings.Candidates_4__c);
            if(m != null && !m.isEmpty()){
                mapOfCandidates.putAll(m);
            }
        }
        
        data.put('mapOfCandidates', mapOfCandidates);
        
        return data;
    }
    
    @AuraEnabled
    public static void updateCandidateSettings(Map<String, String> mapOfCandidates){
        Setup_Settings__c settings = Setup_Settings__c.getOrgDefaults();
        if(mapOfCandidates == null || mapOfCandidates.isEmpty()){
            settings.Candidates_1__c = null;
            settings.Candidates_2__c = null;
            settings.Candidates_3__c = null;
            settings.Candidates_4__c = null;
        }else{
            Integer fieldCount = 1;
            Integer totalCount = 0;
            Integer recCount = 0;
            Map<String, String> tempCandidates = new Map<String, String>();
            for(String key : mapOfCandidates.keySet()){
                if(recCount < 5){
                    tempCandidates.put(key, mapOfCandidates.get(key));
                    recCount++;
                }
                totalCount++;
                if(recCount == 5 || mapOfCandidates.size() == totalCount){
                    String fName = AIPromptController.NAMESPACE+'Candidates_'+fieldCount+'__c';
                    settings.put(fName, JSON.serialize(tempCandidates));
                    recCount = 0;
                    fieldCount++;
                    tempCandidates = new Map<String, String>();
                }
            }
        }
        FLSCheck.getInstance().upsertDML(new List<Setup_Settings__c>{settings});
    }
    
}