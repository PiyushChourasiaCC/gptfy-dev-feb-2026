trigger AISchedulerTrigger on AI_Scheduler__c (before insert, before update) {
    if(Trigger.isBefore && Trigger.isInsert){
        AISchedulerTriggerHandler.onBeforeInsert(Trigger.New);
    }if(Trigger.isBefore && Trigger.isUpdate){
        AISchedulerTriggerHandler.onBeforeUpdate(Trigger.New, Trigger.oldMap);
    }
}