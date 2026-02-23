public with sharing class AIOrgWideSetupController {
	
    /**
     * Retrieves details as a key-value map.
     *
     * This method returns a Map<String, Object> containing various details.
     * The keys in the map are strings, and the corresponding values can be of any Object type.
     *
     * @return A Map<String, Object> containing details.
     */
    @AuraEnabled
    public static Map<String, Object> getDetails(){
        try{
            Map<String, Object> returnMap = new Map<String, Object>();
            List<AsyncApexJob> lst = [SELECT CronTrigger.NextFireTime 
                                    FROM AsyncApexJob 
                                    WHERE ApexClass.Name LIKE '%AIRetentionScheduler%' 
                                    AND Status = 'Queued' 
                                    AND CronTriggerId != NULL
                                    ORDER BY CronTrigger.NextFireTime ASC];
            if(lst != null && !lst.isEmpty()){
                returnMap.put('nextFireTime', lst.get(0).CronTrigger.NextFireTime);
            }
            
            returnMap.put('status', false);
            returnMap.put('recordsPurged', 0);
            returnMap.put('noOfDays', null);
            returnMap.put('whereClause',null);
            if(Retention_Preference__c.getOrgDefaults() != null && Retention_Preference__c.getOrgDefaults().Id != null){
                Retention_Preference__c pref = Retention_Preference__c.getOrgDefaults();
                returnMap.put('recordsPurged', (pref.Records_Purged__c != null ? (Integer)pref.Records_Purged__c : 0));
                returnMap.put('lastRunDateTime', (pref.Last_Ran_Date_Time__c != null ? pref.Last_Ran_Date_Time__c : null));
                returnMap.put('status', pref.Active__c != null && pref.Active__c ? true : false);
                returnMap.put('noOfDays', pref.Delete_Records_After_Days__c != null && pref.Delete_Records_After_Days__c > 0 ? (Integer)pref.Delete_Records_After_Days__c : null);
            	returnMap.put('whereClause', pref.Where_Clause__c != null ? pref.Where_Clause__c : null);
            }
            if(returnMap.get('lastRunDateTime') == null){
                returnMap.put('lastRunDateTime', 'NONE');
            }
            
            Map<String, Object> settings = AIUtility.getCustomSettings();
            returnMap.putAll(settings);
            return returnMap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIOrgWideSetupController', 'getDetails', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Updates the status based on the provided parameters.
     * 
     * @param isActive A boolean indicating whether the status should be set to active or inactive.
     * @param noOfDays An integer representing the number of days for which the status is valid.
     */
    @AuraEnabled
    public static void updateStatus(Boolean isActive, Integer noOfDays){
        try{
            Retention_Preference__c pref = Retention_Preference__c.getOrgDefaults();
            pref.Active__c = isActive != null && isActive ? true : false;
            pref.Delete_Records_After_Days__c = noOfDays != null ? (Integer)noOfDays : null;
            FLSCheck.getInstance().upsertDML(new List<Retention_Preference__c>{pref});
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIOrgWideSetupController', 'updateStatus', '');
            throw new AurahandledException(e.getMessage());
        }
    }
    
    /*
    @AuraEnabled
    public static boolean updateCustomLabel(String labelName, String newValue) {
        String NAMESPACE = AIExtractionFieldMappingController.NAMESPACE;
        boolean hasUpdated = false;
        
        MetadataService.MetadataPort service = createService();
        MetadataService.CustomLabel customLabel;
        if(!Test.isRunningTest()){
            customLabel = (MetadataService.CustomLabel) service.readMetadata('CustomLabel', new String[] {NAMESPACE+labelName}).getRecords()[0];
        }else{
            customLabel = new MetadataService.CustomLabel();
        }
        
        customLabel.value = newValue;
        
        MetadataService.SaveResult[] result = service.updateMetadata(new MetadataService.Metadata[] { customLabel });
        
        if(Test.isRunningTest() || (!Test.isRunningTest() && result[0].success)){
            hasUpdated = true;
        }
        
        return hasUpdated;
    }
    
    public static MetadataService.MetadataPort createService() {
        MetadataService.MetadataPort service = new MetadataService.MetadataPort();
        service.timeout_x = 120000;
        service.SessionHeader = new MetadataService.SessionHeader_element();
        service.SessionHeader.sessionId = fetchUserSessionIdUsingVF(); 
        
        return service;
    }
    
    public static String fetchUserSessionIdUsingVF(){
        try{
            PageReference reportPage = Page.MetadataServiceSession;
            String vfContent = reportPage.getContent().toString();
            Integer startP = vfContent.indexOf('Start_Of_Session_Id') + 'Start_Of_Session_Id'.length();
            Integer endP = vfContent.indexOf('End_Of_Session_Id');
            return vfContent.substring(startP, endP);
        }catch(Exception ex){
            System.debug('Unable to generate a session Id.');
        }
        return null;
    }
	*/
    
    @AuraEnabled
    public static String scheduleJob(String cronExpr) {
        // Use your actual Schedulable class name
        AIRetentionScheduler job = new AIRetentionScheduler();
        //String jobName = 'AI Retention Scheduler';
        return System.schedule(AIConstants.RETENTION_JOB_NAME, cronExpr, job);
    }

    @AuraEnabled
    public static void abortJob() {
        // Retrieve the job by its name and abort it
        CronTrigger ct = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name =: AIConstants.RETENTION_JOB_NAME LIMIT 1];
        if (ct != null) {
            System.abortJob(ct.Id);
        }
    }
    
     @AuraEnabled
    public static void updateRetentionPreference(String fieldName, Object value){
        Retention_Preference__c settings = Retention_Preference__c.getOrgDefaults();
        settings.put(fieldName,value);
        FLSCheck.getInstance().upsertDML(new List<Retention_Preference__c>{settings});
    }
}