public class AudioRecorderKenshoController {

    @AuraEnabled
    public static String generatetoken(){
        
		String endpoint = 'callout:kenshoTokenAPI';
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(endpoint);
        
        Http http = new Http();
        HttpResponse response = http.send(req);

        //System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
       // System.debug('statusCode: '+response.getStatusCode());
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        return String.valueOf(m.get('access_token'));
    }
    
    
    @AuraEnabled
    public static String createContentDocumentLinkWithKenshoPooling(String cdId, String recordId,String transcriptId,String token){
         List<ContentVersion> lstOfVersions = [SELECT Id, VersionData, ContentDocumentId 
                                              FROM ContentVersion
                                              WHERE Id =:cdId];

        if(lstOfVersions != null && lstOfVersions.size() > 0){
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            request.setTimeout(120000);

            String endpoint;
            List<AI_Voice_Configuration__c> lstOfConfigs = [SELECT Id, AI_Model__c, AI_Model__r.Named_Credential__c, 
                                                            AI_Model__r.EndPoint_URL__c, AI_Model__r.Model__c 
                                                            FROM AI_Voice_Configuration__c 
                                                            WHERE AI_Model__c != NULL
                                                            LIMIT 1];
            if(lstOfConfigs != null && !lstOfConfigs.isEmpty()){
                    request.setHeader('Content-Type', 'application/json');
                  	endPoint = 'callout:Kensho/api/v2/transcription/'+transcriptId;
            }
            
            request.setEndpoint(endPoint);
            request.setHeader('Authorization', 'Bearer ' + token);
            HttpResponse response = http.send(request);
            System.debug('body: '+response.getBody());
			System.debug('status: '+response.getStatus());
            System.debug('statusCode: '+response.getStatusCode());
            
            if(String.isNotBlank(response.getBody()) && response.getStatusCode() == 200){
                Map<String,Object> dataMap = (Map<String,Object>)JSON.deserializeUntyped(response.getBody());
                if(dataMap.containsKey('transcript') && dataMap.get('transcript') != null){
                     lstOfVersions[0].Transcript__c = String.valueOf(dataMap.get('transcript'));
                    FLSCheck.getInstance().updateDML(lstOfVersions);
                }
            }else{
                return String.valueOf(response.getStatusCode());
            }
            
            ContentDocumentLink contentlink = new ContentDocumentLink();
            contentlink.LinkedEntityId = recordId;
            contentlink.ShareType = 'V';
            contentlink.ContentDocumentId = lstOfVersions[0].ContentDocumentId;
            contentlink.Visibility = 'AllUsers'; 
            FLSCheck.getInstance().insertDML(new List<ContentDocumentLink>{contentlink});
            
            return String.valueOf(response.getStatusCode());
        }else{
            return 'Not found Audio';
        }
    }
}