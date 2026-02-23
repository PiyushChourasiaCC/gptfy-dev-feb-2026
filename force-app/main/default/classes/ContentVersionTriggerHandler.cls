public with sharing class ContentVersionTriggerHandler {
	
    public static void onAfterUpdate(List<ContentVersion> newList, Map<Id, ContentVersion> oldMap){
        try{
        	publishEvents(newList, oldMap);
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'ContentVersionTriggerHandler', 'onAfterUpdate', '');
        }
    }
    
    public static void publishEvents(List<ContentVersion> newList, Map<Id, ContentVersion> oldMap){
        Map<String, ContentVersion> mapOfDocIdToVersion = new Map<String, ContentVersion>();
        for(ContentVersion cv : newList){
            if(String.isNotBlank(cv.Transcript__c) && cv.Transcript__c != oldMap.get(cv.Id).Transcript__c){
                mapOfDocIdToVersion.put(cv.ContentDocumentId, cv);
            }
        }
        
        if(!mapOfDocIdToVersion.isEmpty()){
            Map<String, String> mapOfDocIdToRecordId = new Map<String, String>();
            for(ContentDocumentLink cdl : [SELECT Id, ContentDocumentId, LinkedEntityId 
                                           FROM ContentDocumentLink 
                                           WHERE ContentDocumentId IN :mapOfDocIdToVersion.KeySet()]){
                String recId = cdl.LinkedEntityId;
                if(String.isNotBlank(recId) && !recId.startsWith('005')){
                    mapOfDocIdToRecordId.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                }                                  
            }
            List<Audio_Transcript__e> events = new List<Audio_Transcript__e>();
            for(String docId : mapOfDocIdToVersion.keySet()){
                ContentVersion cv = mapOfDocIdToVersion.get(docId);
                String parentId = mapOfDocIdToRecordId != null && mapOfDocIdToRecordId.containsKey(docId) ? mapOfDocIdToRecordId.get(docId) : null;
                if(String.isNotBlank(parentId)){
                    Id recId = (Id)parentId;
                    String objName = recId.getSObjectType().getDescribe().getName();
                    
                    events.add(new Audio_Transcript__e(
                        Content_Document_Id__c = docId, 
                        Content_Version_Id__c = cv.Id, 
                        Record_Id__c = parentId,
                        Transcript__c = cv.Transcript__c,
                        Related_To_Object__c = objName,
                        Running_User_Id__c = UserInfo.getUserId()
                    ));
                }
            }
            if(!events.isEmpty()){
            	EventBus.publish(events);
            }
        }
    }
    
}