trigger AISecurityFilterTrigger on AI_Security_Filters__c (before insert, before update) {
    if(Trigger.isBefore && Trigger.isInsert){
        AISecurityFilterTriggerHandler.onBeforeInsert(Trigger.New);
    }
    if(Trigger.isBefore && Trigger.isUpdate){
        AISecurityFilterTriggerHandler.onBeforeUpdate(Trigger.New, Trigger.oldMap);
    }
}