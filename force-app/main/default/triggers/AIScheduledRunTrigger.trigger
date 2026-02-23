/**
 * @description Trigger for AI_Scheduled_Run__c object that handles after update events
 *              to process completed scheduled runs and consolidate responses.
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 12-02-2024
 * @last modified by Piyush Chourasia
 */
trigger AIScheduledRunTrigger on AI_Scheduled_Run__c (after update) {
    if(Trigger.isAfter && Trigger.isUpdate){
        AIScheduledRunTriggerHandler.onAfterUpdate(Trigger.New, Trigger.oldMap);
    }
}