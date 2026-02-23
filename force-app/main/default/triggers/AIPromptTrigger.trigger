trigger AIPromptTrigger on AI_Prompt__c (before insert) {
	if(Trigger.isBefore && Trigger.isInsert){
        AIPromptTriggerHandler.onBeforeInsert(Trigger.New);
    }
}