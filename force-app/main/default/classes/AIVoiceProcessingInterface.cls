/**
* @description       : 
* @author            : Sohit Sharma
* @group             : Plumcloud Labs
* @last modified on  : 05-11-2025
* @last modified by  : Sohit Sharma
* @Jira 			 : v2/7290 : GPTfy Voice Enhancements
**/
global interface AIVoiceProcessingInterface {
	HttpResponse getProcessedResponse(VoiceProcessingWrapper voiceWrap);
}