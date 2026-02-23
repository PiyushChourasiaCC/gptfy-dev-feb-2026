public with sharing class AISchedulerTriggerHandler {
	
    /**
     * This method is triggered before inserting records of the custom object AI_Scheduler__c.
     * It allows performing custom logic or validations before the records are actually inserted
     * into the database.
     *
     * @param newList A List of AI_Scheduler__c records that are about to be inserted.
     */
    public static void onBeforeInsert(List<AI_Scheduler__c> newList){
        manageCronExpression(newList, null);
    }
    
    /**
     * This method is called before records of the AI_Scheduler__c object are updated.
     * It is intended to perform any necessary actions or validations prior to the update operation.
     *
     * @param newList The list of AI_Scheduler__c records that are about to be updated.
     * @param oldMap  A map containing the old versions of the AI_Scheduler__c records, with their Ids as keys.
     *                This can be used to compare changes made during the update.
     */
    public static void onBeforeUpdate(List<AI_Scheduler__c> newList, Map<Id, AI_Scheduler__c> oldMap){
        manageCronExpression(newList, oldMap);
        unscheduleJob(newList, oldMap);
    }
    
    /**
     * Unschedules jobs based on a list of new AI_Scheduler__c records and a map of old AI_Scheduler__c records.
     *
     * This method is responsible for unscheduling jobs by comparing the changes between the new list of AI_Scheduler__c records
     * and the old map of AI_Scheduler__c records. It performs the necessary actions to unschedule jobs as needed.
     *
     * @param newList The list of new AI_Scheduler__c records that may have changes.
     * @param oldMap The map of old AI_Scheduler__c records where the key is the record Id.
     */
    public static void unscheduleJob(List<AI_Scheduler__c> newList, Map<Id, AI_Scheduler__c> oldMap){
        Set<String> setOfJobNames = new Set<String>();
        List<AI_Scheduler__c> lst = new List<AI_Scheduler__c>();
        for(AI_Scheduler__c sch : newList){
            if(sch.Cron_Expression__c != oldMap.get(sch.Id).Cron_Expression__c){
                setOfJobNames.add('GPTfy-'+sch.Id);
                sch.Status__c = AIConstants.SCH_STATUS_NOT_SCHEDULED;
                sch.Scheduled_Timezone__c = '';
            }
        }
        if(!setOfJobNames.isEmpty()){
            List<CronTrigger> crTrigger =  [SELECT Id, CronJobDetailId,CronJobDetail.Name FROM CronTrigger where CronJobDetail.Name IN :setOfJobNames];
            if(!crTrigger.isEmpty()){
                for(CronTrigger job : crTrigger){
                    system.abortJob(job.Id);
                } 
            }
        }
    }
    
    /**
     * This method is responsible for managing the Cron expressions of AI_Scheduler__c records.
     *
     * @param newList The list of AI_Scheduler__c records representing the updated records.
     * @param oldMap The map of AI_Scheduler__c records from the previous state, with record Ids as keys.
     */
    public static void manageCronExpression(List<AI_Scheduler__c> newList, Map<Id, AI_Scheduler__c> oldMap){
        Boolean isNew = oldMap != null ? false : true;
        for(AI_Scheduler__c sch : newList){
            if(sch.Scheduling_Frequency__c != AIConstants.SCH_FREQ_CUSTOM && 
               (isNew || 
                sch.Schedule_Detail__c != oldMap.get(sch.Id).Schedule_Detail__c || 
                sch.Scheduling_Frequency__c != oldMap.get(sch.Id).Scheduling_Frequency__c || 
                sch.Schedule_time__c != oldMap.get(sch.Id).Schedule_time__c)){
                sch.Cron_Expression__c = getCronExpression(sch);
            }
        }
    }
    
    /**
     * Generates a cron expression based on the properties of the provided AI_Scheduler__c object.
     *
     * @param sch The AI_Scheduler__c object containing scheduling properties.
     * @return A String representing the cron expression for scheduling tasks.
     */
    public static String getCronExpression(AI_Scheduler__c sch){
        List<String> schedulerDetail = String.isNotBlank(sch.Schedule_Detail__c) ? sch.Schedule_Detail__c.split(';') : null;
        String schedularType = sch.Scheduling_Frequency__c;
        
        String CRON = '';
        List<String> detailList = new List<String>();
        if(schedulerDetail != null && !schedulerDetail.isEmpty()){
            for(String str : schedulerDetail){
                if(schedularType == AIConstants.SCH_FREQ_WEEKLY){
                    detailList.add(str.substring(0,3).toUpperCase());
                }else{
                    detailList.add(str);
                }
            }
        }
        
        String schedularTime = sch.Schedule_time__c != null ? String.valueOf(sch.Schedule_time__c) : '';
        
        String SelectedList1 = String.join(detailList, ',');
        List<String> tList = schedularTime.split(':');
        if(schedularType == AIConstants.SCH_FREQ_HOURLY){
            CRON = '0 0 '+SelectedList1+' * * ? *';
        }else if(schedularType == AIConstants.SCH_FREQ_DAILY){
            CRON = '0 '+tList[1]+' '+tList[0]+' ? * * *';
        }else if(schedularType == AIConstants.SCH_FREQ_WEEKLY){
            CRON = '0 '+tList[1]+' '+tList[0]+' ? * '+SelectedList1+' *';
        }else if(schedularType == AIConstants.SCH_FREQ_MONTHLY){
            CRON = '0 '+tList[1]+' '+tList[0]+' '+SelectedList1+' * ? *';
        }
        
        return CRON;
    }
    
}