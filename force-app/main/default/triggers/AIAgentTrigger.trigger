trigger AIAgentTrigger on AI_Agent__c (before insert) {
    if(Trigger.isBefore && Trigger.isInsert){
        AIAgentTriggerHandler.onBeforeInsert(Trigger.New);
    }
}