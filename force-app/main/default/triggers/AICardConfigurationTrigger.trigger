trigger AICardConfigurationTrigger on AI_Card_Configuration__c (before insert, before update) {
	if(Trigger.isBefore && Trigger.isInsert){
        AICardConfigurationTriggerHandler.onBeforeInsert(Trigger.New);
    }if(Trigger.isBefore && Trigger.isUpdate){
        AICardConfigurationTriggerHandler.onBeforeUpdate(Trigger.New, Trigger.oldMap);
    }
}