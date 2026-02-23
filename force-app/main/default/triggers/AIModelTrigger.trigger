trigger AIModelTrigger on AI_Connection__c (before insert, before update) {
    if(Trigger.isBefore && Trigger.isInsert){
        AIModelTriggerHandler.onBeforeInsert(Trigger.New);
    }if(Trigger.isBefore && Trigger.isUpdate){
        AIModelTriggerHandler.onBeforeUpdate(Trigger.New, Trigger.oldMap);
    }
}