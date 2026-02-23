/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 07-21-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AISchedulerOverrideController {
    /**
     * Schedules a job for processing a record identified by the provided recordId.
     *
     * @param recordId The unique identifier of the record to be processed by the scheduled job.
     */
    @AuraEnabled
    public static String scheduleJob(String recordId){
		try{
            
            List<AI_Scheduler__c> lst = [SELECT Id, Cron_Expression__c 
                                         FROM AI_Scheduler__c WHERE Id =:recordId LIMIT 1];
            if(lst != null && !lst.isEmpty()){
                AI_Scheduler__c sch = lst.get(0);
                
                Integer noOfPrompts = [SELECT Count() FROM AI_Prompt_Scheduler__c WHERE AI_Scheduler__c =:sch.Id];
                if(noOfPrompts > 0){
                    String jobName = 'GPTfy-'+recordId;
                    AIPromptScheduler job = new AIPromptScheduler(recordId);
                    System.schedule(jobName, sch.Cron_Expression__c, job);
                    
                    sch.Status__c = AIConstants.SCH_STATUS_SCHEDULED;
                    TimeZone tz = UserInfo.getTimeZone();
                    String displayName = tz.getDisplayName();
                    sch.Scheduled_Timezone__c = (String.isNotBlank(displayName) && displayName.containsIgnoreCase(' ')) ? displayName.substringAfter(' ') : displayName;
                    
                    FLSCheck.getInstance().updateDML(new List<AI_Scheduler__c>{sch});
                }else{
                    return 'Please make sure that prompts are added before scheduling.';
                }
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISchedulerOverrideController', 'scheduleJob', '');
            throw new AuraHandledException(e.getMessage());
        }        
        return null;
    }
    
    /**
     * Unschedules a job associated with the given record ID.
     * This method is responsible for canceling or removing a scheduled job
     * that corresponds to a specific record identified by the provided record ID.
     *
     * @param recordId The unique identifier of the record associated with the scheduled job.
     *                 This ID is used to locate and unschedule the corresponding job.
     */
    @AuraEnabled
    public static void unscheduleJob(String recordId){
        try{
            List<AI_Scheduler__c> lst = [SELECT Id FROM AI_Scheduler__c WHERE Id =:recordId LIMIT 1];
            if(lst != null && !lst.isEmpty()){
                AI_Scheduler__c sch = lst.get(0);
                String jobName = 'GPTfy-'+recordId;
                List<CronTrigger> crTrigger =  [SELECT Id, CronJobDetailId,CronJobDetail.Name FROM CronTrigger where CronJobDetail.Name=:jobName];
                if(!crTrigger.isEmpty()){
                    system.abortJob(crTrigger.get(0).Id);
                }
                sch.Status__c = AIConstants.SCH_STATUS_NOT_SCHEDULED;
                sch.Scheduled_Timezone__c = '';
                FLSCheck.getInstance().updateDML(new List<AI_Scheduler__c>{sch});
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISchedulerOverrideController', 'unscheduleJob', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves scheduling information for a given record.
     *
     * This method takes a record ID as a parameter and returns a Map containing scheduling details.
     *
     * @param recordId The unique identifier of the record for which scheduling information is requested.
     * @return A Map<String, Object> containing scheduling information. The keys represent different aspects
     *         of the scheduling information, and the corresponding values are of type Object.
     *         Example keys might include "startTime", "endTime", "location", etc.
     *         Returns an empty map if no scheduling information is found for the given record ID.
     */
    @AuraEnabled
    public static Map<String, Object> getSchedulingInformation(String recordId){
        try{
            Map<String, Object> data = new Map<String, Object>();
            List<AI_Scheduler__c> lst = [SELECT Id, Name, Schedule_time__c, Scheduling_Frequency__c, Schedule_Detail__c, Cron_Expression__c, Retry_Count__c
                                        FROM AI_Scheduler__c WHERE Id =:recordId];
            if(lst != null && !lst.isEmpty()){
                Time t = lst.get(0).Schedule_time__c;
                if(t != null){
                    data.put('time', t+'');
                }
                data.put('schedulerName', lst.get(0).Name);
                data.put('cronExp', lst.get(0).Cron_Expression__c);
                data.put('selectedScheduleOption', lst.get(0).Scheduling_Frequency__c);
                data.put('retryCount', lst.get(0).Retry_Count__c);
                List<String> selectedOptions;
                if(String.isNotBlank(lst.get(0).Schedule_Detail__c)){
                    selectedOptions = lst.get(0).Schedule_Detail__c.split(';');
                }
                data.put('scheduleDetail', selectedOptions);
            }
            return data;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISchedulerOverrideController', 'getSchedulingInformation', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Saves scheduling information for a specific record.
     *
     * @param recordId       The unique identifier of the record.
     * @param schedulerName  The name of the scheduler.
     * @param schedulerType  The type of the scheduler (e.g., daily, weekly).
     * @param schedulerTime  The time at which the scheduler is set to run.
     * @param schedulerDetail Additional details about the scheduler.
     * @param cronExp        The cron expression for scheduling (if applicable).
     * @param retryCount     The number of times the scheduling should be retried in case of failure.
     */
    @AuraEnabled
    public static void saveSchedulingInformation(String recordId, String schedulerName, String schedularType, String schedularTime, List<String> schedulerDetail, String cronExp, Decimal retryCount){
        try{
            AI_Scheduler__c sch = new AI_Scheduler__c();
            sch.Name = schedulerName;
            sch.Scheduling_Frequency__c = schedularType;
            sch.Schedule_Detail__c = schedulerDetail != null && schedulerDetail.size() > 0 ? String.join(schedulerDetail, ';') : '';
            sch.Cron_Expression__c = cronExp;
            sch.Schedule_time__c = null;
            sch.Retry_Count__c = retryCount != null && retryCount > 0 ? (Integer)retryCount : 0;
            if(String.isNotBlank(schedularTime)){
                List<String> tList = schedularTime.split(':');
                sch.Schedule_time__c = Time.newInstance(Integer.valueOf(tList[0]), Integer.valueOf(tList[1]), 0, 0); 
            }
            if(String.isNotBlank(recordId)){
                sch.Id = recordId;
            }
            FLSCheck.getInstance().upsertDML(new List<AI_Scheduler__c>{sch});
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISchedulerOverrideController', 'saveSchedulingInformation', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
	
    /**
     * Executes a process immediately for the specified record.
     *
     * @param recordId The unique identifier of the record for which the process should run.
     *                 This method performs an operation associated with the provided record identifier.
     *                 The exact nature of the operation should be documented in the method implementation.
     *                 If the recordId is null or invalid, the method might handle it gracefully or
     *                 log an appropriate message.
     *                 Note: This method does not return any value; it triggers a process or action.
     */
    @AuraEnabled
    public static void runNow(String recordId){
        try{
            AIPromptScheduler job = new AIPromptScheduler(recordId);
			job.execute(null);
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISchedulerOverrideController', 'runNow', '');
            throw new AuraHandledException(e.getMessage());
        } 
    }

    /**
     * Abort all job associated with the given record ID.
     * This method is responsible for canceling or removing a scheduled job
     * that corresponds to a specific record identified by the provided record ID.
     *
     * @param recordId The unique identifier of the record associated with the scheduled job.
     *                 This ID is used to locate and unschedule the corresponding job.
     */
    @AuraEnabled
    public static void abortJobs(String recordId){
        try{
            List<AI_Scheduled_Run__c> lst = [SELECT Id, Scheduler__c FROM AI_Scheduled_Run__c WHERE Id =:recordId LIMIT 1];
            if(lst != null && !lst.isEmpty()){
                AI_Scheduled_Run__c schRun = lst.get(0);
                String jobName = 'GPTfy-'+schRun.Scheduler__c;
                List<CronTrigger> crTrigger =  [SELECT Id, CronJobDetailId,CronJobDetail.Name FROM CronTrigger where CronJobDetail.Name=:jobName];
                if(!crTrigger.isEmpty()){
                    system.abortJob(crTrigger.get(0).Id);
                }
                for(AsyncApexJob asyncJob : [SELECT Id, CronTriggerId FROM AsyncApexJob WHERE ApexClass.Name IN:AIConstants.SCH_BATCH_CLASSES AND Status!=:AIConstants.SCH_STATUS_ABORTED AND Status!=:AIConstants.SCH_STATUS_COMPLETED]){
                    system.abortJob((asyncJob.CronTriggerId!=null?asyncJob.CronTriggerId:asyncJob.Id));
                }
                datetime start = system.now();
                while(system.now() < start.addseconds(5)){}
                System.enqueueJob(new AIPromptAbortQueueable(schRun.Id));
                start = system.now();
                while(system.now() < start.addseconds(5)){}
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AISchedulerOverrideController', 'abortJobs', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
}