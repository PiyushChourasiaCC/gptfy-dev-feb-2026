trigger ContentVersionTrigger on ContentVersion (after update) {
    if(!Trigger_Bypass__c.getInstance().Content_Version__c) {
        if(Trigger.isAfter && Trigger.isUpdate){
            ContentVersionTriggerHandler.onAfterUpdate(Trigger.New, Trigger.oldMap);
        }
    }  
}