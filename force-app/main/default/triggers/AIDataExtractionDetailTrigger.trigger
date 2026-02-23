trigger AIDataExtractionDetailTrigger on AI_Data_Extraction_Detail__c (before insert) {
    if(Trigger.isBefore && Trigger.isInsert){
        AIDataExtractionDetailTriggerHandler.onBeforeInsert(Trigger.New);
    }
}