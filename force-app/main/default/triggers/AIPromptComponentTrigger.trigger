trigger AIPromptComponentTrigger on AI_Prompt_Component__c (before insert, before update, after insert, after update, after delete) {
    if(Trigger.isBefore && Trigger.isInsert){
        AIPromptComponentTriggerHandler.onBeforeInsert(Trigger.New);
    }if(Trigger.isBefore && Trigger.isUpdate){
        AIPromptComponentTriggerHandler.onBeforeUpdate(Trigger.New, Trigger.oldMap);
    }if(Trigger.isAfter && Trigger.isInsert){ 
        AIPromptComponentTriggerHandler.onAfterInsert(Trigger.New);
    }if(Trigger.isAfter && Trigger.isUpdate){
        AIPromptComponentTriggerHandler.onAfterUpdate(Trigger.New, Trigger.oldMap);
    }if(Trigger.isAfter && Trigger.isDelete){
        AIPromptComponentTriggerHandler.onAfterDelete(Trigger.Old);
    }
}