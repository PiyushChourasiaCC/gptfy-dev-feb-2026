public with sharing class AISyncScheduleController {
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
	
    @AuraEnabled
    public static String scheduleJob(String recordId){
		try{
            List<AI_RAG_Sync__c> lst = [SELECT Id, 
                                             Cron_Expression__c 
                                             FROM AI_RAG_Sync__c 
                                             WHERE Id =:recordId LIMIT 1];
            if(lst != null && !lst.isEmpty()){
                AI_RAG_Sync__c sch = lst.get(0);
                
                String jobName = 'AI_Sync-'+recordId;
                AISyncSchedulable job = new AISyncSchedulable(recordId);
                System.schedule(jobName, sch.Cron_Expression__c, job);

                TimeZone tz = UserInfo.getTimeZone();
                String displayName = tz.getDisplayName();
                sch.Scheduled_Timezone__c = (String.isNotBlank(displayName) && displayName.containsIgnoreCase(' ')) ? displayName.substringAfter(' ') : displayName;
                sch.Status__c = AIConstants.SCH_STATUS_SCHEDULED;
                
                FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync__c>{sch});
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISyncScheduleController', 'scheduleJob', '');
            throw new AuraHandledException(e.getMessage());
        }        
        return null;
    }
    
    @AuraEnabled
    public static void unscheduleJob(String recordId){
        try{
            List<AI_RAG_Sync__c> lst = [SELECT Id 
                                              FROM AI_RAG_Sync__c 
                                              WHERE Id =:recordId 
                                              LIMIT 1];
            if(lst != null && !lst.isEmpty()){
                AI_RAG_Sync__c sch = lst.get(0);
                String jobName = 'AI_Sync-'+recordId;
                List<CronTrigger> crTrigger =  [SELECT Id, CronJobDetailId,CronJobDetail.Name 
                                                FROM CronTrigger 
                                                WHERE CronJobDetail.Name=:jobName];
                if(!crTrigger.isEmpty()){
                    system.abortJob(crTrigger.get(0).Id);
                }
                sch.Scheduled_Timezone__c = '';
                sch.Status__c = AIConstants.SCH_STATUS_NOT_SCHEDULED;
                
                FLSCheck.getInstance().updateDML(new List<AI_RAG_Sync__c>{sch});
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISyncScheduleController', 'unscheduleJob', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void runNow(String recordId){
        try{
            // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
            List<AI_RAG_Sync__c> lst = [SELECT Id, Object__c, Where_Clause__c 
                                              FROM AI_RAG_Sync__c 
                                              WHERE Id =:recordId 
                                              LIMIT 1];
            if(lst != null && !lst.isEmpty()){
                AI_RAG_Sync__c sch = lst.get(0);
                if(AIPromptValidationController.isValidVisibilityCondition(sch.Object__c,sch.Where_Clause__c)){
                    AISyncSchedulable job = new AISyncSchedulable(recordId);
					job.execute(null);
                }else{
                    String errorMsg = 'Where Clause is invalid. Please check and try again.';
                    throw AIUtility.getMessageAuraHandledException(errorMsg);
                }
            }
           
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISyncScheduleController', 'runNow', '');
            throw AIUtility.getMessageAuraHandledException(e.getMessage());
        } 
    }
    
    @AuraEnabled
    public static AISyncWrapper getInitData(String recordId){
        AISyncWrapper wrap = new AISyncWrapper();
        wrap.modelOptions = getConnectionOptions();
        wrap.fileFormatOptions = AIPromptController.getPickListValues(NAMESPACE+'AI_RAG_Sync__c', NAMESPACE+'File_Format__c');
        wrap.objectOptions = AIDataExtractionController.getSObjects();
        
        if(String.isNotBlank(recordId)){
            List<AI_RAG_Sync__c> lstOfScheduler = [SELECT Id, Name, Cron_Expression__c, Description__c, Fields__c, 
                                                         File_Format__c, File_Name__c, Object__c, Where_Clause__c, 
                                                         AI_Model_File_Upload__c, AI_Model_Datastore_Import__c 
                                                         FROM AI_RAG_Sync__c 
                                                         WHERE Id =:recordId 
                                                         LIMIT 1];
            if(lstOfScheduler != null && !lstOfScheduler.isEmpty()){
                AI_RAG_Sync__c sch = lstOfScheduler.get(0);
                wrap.name = sch.Name;
                wrap.cronExp = sch.Cron_Expression__c;
                wrap.description = sch.Description__c;
                wrap.fileFormat = sch.File_Format__c;
                wrap.fileName = sch.File_Name__c;
                wrap.objectName = sch.Object__c;
                wrap.whereClause = sch.Where_Clause__c;
                wrap.fileUploadModelId = sch.AI_Model_File_Upload__c;
                wrap.datastoreImportModelId = sch.AI_Model_Datastore_Import__c; 
                if(String.isNotBlank(sch.Fields__c)){
                    Map<String, Object> fieldMap = (Map<String, Object>)JSON.deserializeUntyped(sch.Fields__c);
                    if(fieldMap != null && !fieldMap.isEmpty()){
                        List<FieldOptionWrapper> fields = new List<FieldOptionWrapper>();
                        for(String fieldApi : fieldMap.keySet()){
                            FieldOptionWrapper opt = new FieldOptionWrapper();
                            opt.fieldApi = fieldApi;
                            opt.nodeName = String.valueOf(fieldMap.get(fieldApi));
                            fields.add(opt);
                        }
                        wrap.fields = fields;
                    }
                }
                if(String.isNotBlank(wrap.objectName)){
                    wrap.fieldOptions = AIPromptActionController.getFieldOptions(wrap.objectName, false);
                }
            }
        }
        
        return wrap;
    }
    
    public class AISyncWrapper{
        @AuraEnabled public String name{get;set;}
        @AuraEnabled public String cronExp{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String fileFormat{get;set;}
        @AuraEnabled public String fileName{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String whereClause{get;set;}
        @AuraEnabled public String fileUploadModelId{get;set;}
        @AuraEnabled public String datastoreImportModelId{get;set;}
        @AuraEnabled public List<FieldOptionWrapper> fields{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> modelOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> fileFormatOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> objectOptions{get;set;}
        @AuraEnabled public List<AIPromptActionController.PicklistAttributeWrapper> fieldOptions{get;set;}
    }
    
    public class FieldOptionWrapper{
        @AuraEnabled public String fieldApi{get;set;}
        @AuraEnabled public String nodeName{get;set;}
    }
    
    @AuraEnabled
    public static List<AIDataExtractionController.PicklistWrapper> getConnectionOptions(){
        try{
            List<AIDataExtractionController.PicklistWrapper> typeOptions = new List<AIDataExtractionController.PicklistWrapper>();
            List<String> activeAIModal = new List<String>();
            for(AI_Card_Configuration__c cc : [SELECT Id, Name 
                                               FROM AI_Card_Configuration__c 
                                               WHERE Enabled__c = true 
                                               AND Feature__c =:AIConstants.GPTfy_Card_Configuration_MDT_AMODL]){
                activeAIModal.add(cc.Name.toLowercase());
            }
            
            for(AI_Connection__c p : [SELECT Id, Name 
                                      FROM AI_Connection__c 
                                      WHERE Type__c =:AIConstants.AI_MODEL_TYPE_AI_SYNC
                                      ORDER BY Name 
                                      LIMIT 50000]){
                if(activeAIModal.contains(p.Name.toLowercase())){
                    AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                    wrap.label = p.Name;
                    wrap.value = p.Id;
                    typeOptions.add(wrap);
                }
                
            }
            return typeOptions;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISyncScheduleController', 'getConnectionOptions', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String updateSyncScheduler(String data, String recordId){
        try{
            AISyncWrapper wrap = (AISyncWrapper)System.JSON.deserialize(data, AISyncWrapper.class);
            
            AI_RAG_Sync__c sch = new AI_RAG_Sync__c();
            sch.Name = wrap.name; 
            sch.Cron_Expression__c = wrap.cronExp;
            sch.Description__c = wrap.description;
            sch.File_Format__c = wrap.fileFormat;
            sch.File_Name__c = wrap.fileName; 
            sch.Object__c = wrap.objectName;
            sch.Where_Clause__c = wrap.whereClause;
            sch.AI_Model_File_Upload__c = wrap.fileUploadModelId;
            sch.AI_Model_Datastore_Import__c = wrap.datastoreImportModelId; 
            sch.Fields__c = '';
            if(wrap.fields != null && !wrap.fields.isEmpty()){
                Map<String, Object> fieldMap = new Map<String, Object>();
                for(FieldOptionWrapper opt : wrap.fields){
                    fieldMap.put(opt.fieldApi, opt.nodeName);
                }
                sch.Fields__c = JSON.serialize(fieldMap);
            }
            if(String.isNotBlank(recordId)){
                sch.Id = recordId;
            }
            List<Sobject> records = FLSCheck.getInstance().upsertDML(new List<AI_RAG_Sync__c>{sch});
            if(records != null && !records.isEmpty()){
                return String.valueOf(records.get(0).get('Id'));
            }
            return null;
        }catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
    }
    
}