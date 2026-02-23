trigger AICrossObjectFilterTrigger on AI_Cross_Object_Filter__c (before insert, before update, after insert, after update, after delete) {
    
    if(Trigger.isBefore && Trigger.isInsert){
		AICrossObjectFilterTriggerHandler.onBeforeInsert(Trigger.New);
    }if(Trigger.isBefore && Trigger.isUpdate){
		AICrossObjectFilterTriggerHandler.onBeforeUpdate(Trigger.New, Trigger.oldMap);
    }if(Trigger.isAfter && Trigger.isInsert){
		AICrossObjectFilterTriggerHandler.onAfterInsert(Trigger.New);
    }if(Trigger.isAfter && Trigger.isUpdate){
		AICrossObjectFilterTriggerHandler.onAfterUpdate(Trigger.New, Trigger.oldMap);
    }if(Trigger.isAfter && Trigger.isDelete){
		AICrossObjectFilterTriggerHandler.onAfterDelete(Trigger.old);
    }
    
}