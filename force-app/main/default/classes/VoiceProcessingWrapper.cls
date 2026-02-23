/**
* @description       : 
* @author            : Sohit Sharma
* @group             : Plumcloud Labs
* @last modified on  : 05-11-2025
* @last modified by  : Sohit Sharma
* @Jira 			 : v2/7290 : GPTfy Voice Enhancements
**/
global class VoiceProcessingWrapper {
    global AI_Connection__c aiModel { get; set; }
    global ContentVersion cv { get; set; }
    global Boolean isIOS { get; set; }
    global HttpRequest request { get; set; }

    // Optional: Constructor for initializing fields
    global VoiceProcessingWrapper(HttpRequest request,AI_Connection__c aiModel, ContentVersion cv, Boolean isIOS) {
        this.request = request;
        this.aiModel = aiModel;
        this.cv = cv;
        this.isIOS = isIOS;
    }
}