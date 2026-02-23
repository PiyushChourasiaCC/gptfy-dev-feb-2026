public with sharing class AIVoicePromptCalloutService implements Queueable, Database.AllowsCallouts {
	
    public AIAudioProcessingService.ProcessAudioWrapper wrap;
    
    public AIVoicePromptCalloutService(AIAudioProcessingService.ProcessAudioWrapper wrap){
        this.wrap = wrap;
    }
    
    public void execute(QueueableContext context) {
        String profileId = UserInfo.getProfileId();
        List<Profile> lstOfProfile = [SELECT Id, Name 
                                      FROM Profile 
                                      WHERE Id =:profileId 
                                      LIMIT 1];
        String profileName;
        if(lstOfProfile != null && !lstOfProfile.isEmpty()){
            profileName = lstOfProfile.get(0).Name;
        }
        
        Id recId = (Id)wrap.recordId;
        String objName = recId.getSObjectType().getDescribe().getName();
        List<AI_Voice_Configuration_Detail__c> lstOfDetails = [SELECT Id, Related_To_Object__c, Profile__c, AI_Prompt__c
                                                               FROM AI_Voice_Configuration_Detail__c
                                                               WHERE (Profile__c =:profileName 
                                                               OR Profile__c = NULL)
                                                               AND Related_To_Object__c =:objName
                                                               ORDER BY Profile__c NULLS LAST, CreatedDate DESC
                                                               LIMIT 1];
        if(lstOfDetails != null && !lstOfDetails.isEmpty()){
            AI_Voice_Configuration_Detail__c detail = lstOfDetails.get(0);
            if(detail.AI_Prompt__c != null){
                ChatGPTUtills.initiateGPT(wrap.cv.Id, detail.AI_Prompt__c, null, null, false);
            }
        }
    }
    
}