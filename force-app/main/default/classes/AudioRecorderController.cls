global with sharing class AudioRecorderController {
    public static final String NAMESPACE = AIPromptController.getNameSpace();
	
    /*
    This method will be called on click submit audio to google chrip for transcript
    params : isIOS is true if the request is for IOS, false for Android
    params : cdId is the content document Id
    params : recordId is the record Id
    */
    @AuraEnabled
    global static void createContentDocumentLink(String cdId, String recordId, Boolean isIOS){
        List<ContentVersion> lstOfVersions = [SELECT Id, VersionData, ContentDocumentId, Title 
                                              FROM ContentVersion
                                              WHERE Id =:cdId];
        if(lstOfVersions != null && lstOfVersions.size() > 0){
            // v2/7290 : GPTfy Voice Enhancements : Added  AI_Model__r.Connector_Class__c,  AI_Model__r.Processing_Class__c
            List<AI_Voice_Configuration__c> lstOfConfigs = [SELECT Id, Async_Request__c, Polling_Timeframe__c, Maximum_Polling_Counter__c,
                                                            AI_Model__c, AI_Model__r.Connector_Class__c, AI_Model__r.Named_Credential__c, AI_Model__r.EndPoint_URL__c, 
                                                            AI_Model__r.Model__c, AI_Model__r.Additional_Parameters__c, AI_Model__r.Processing_Class__c,
                                                            AI_Model_File_Upload__c, AI_Model_File_Upload__r.Named_Credential__c, AI_Model_File_Upload__r.EndPoint_URL__c, 
                                                            AI_Model_File_Upload__r.Model__c, AI_Model_File_Upload__r.Additional_Parameters__c,
                                                            AI_Model_Polling__c, AI_Model_Polling__r.Named_Credential__c, AI_Model_Polling__r.EndPoint_URL__c, 
                                                            AI_Model_Polling__r.Model__c, AI_Model_Polling__r.Additional_Parameters__c
                                                            FROM AI_Voice_Configuration__c 
                                                            WHERE AI_Model__c != NULL
                                                            LIMIT 1];
            if(lstOfConfigs != null && !lstOfConfigs.isEmpty()){
                AIAudioProcessingService.ProcessAudioWrapper wrap = new AIAudioProcessingService.ProcessAudioWrapper();
                wrap.audioConfig = lstOfConfigs.get(0);
                wrap.cv = lstOfVersions.get(0);
                wrap.recordId = recordId;
                wrap.isIOS = isIOS;
                AIAudioProcessingService.processFile(wrap);
            }
        }
    }
    
    /*
    This method will be called on initialize Audio Controller for check User Authorized with Permission Set Admin, User, Portal.
    */
    @AuraEnabled
    public static Boolean isUserAuthorized(){
    	String l_namespace = NAMESPACE;
        if(String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')){
            l_namespace = l_namespace.removeEndIgnoreCase('__');
        }
        
        List<PermissionSetAssignment> permSetAssignments = [SELECT Id FROM PermissionSetAssignment 
                                                            WHERE AssigneeId =:UserInfo.getUserId()
                                                            AND (PermissionSet.Name =:AIConstants.GPTFY_ADMIN_PERM_SET
                                                            OR PermissionSet.Name =:AIConstants.GPTFY_VOICE_PERM_SET)
                                                            AND PermissionSet.NamespacePrefix =:l_namespace];
        if(permSetAssignments == null || permSetAssignments.isEmpty()){
            return false;
        }
        return true;
    }
}