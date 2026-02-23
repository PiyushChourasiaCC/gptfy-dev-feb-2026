public with sharing class AIPromptTriggerHandler {
	
    public static void onBeforeInsert(List<AI_Prompt__c> newList){
        generateUniqueKey(newList);
        
    }
    
    public static void generateUniqueKey(List<AI_Prompt__c> newList){
        for(AI_Prompt__c pmt : newList){
            if(String.isBlank(pmt.Prompt_Request_Id__c)){
                pmt.Prompt_Request_Id__c = generateRandomUniqueId()+''+getRandomString(5);
            } 
        }
    }
    
    public static String generateRandomUniqueId(){
        String hashString = UserInfo.getUserId()  + '__' + UserInfo.getOrganizationId() + String.valueOf(Datetime.now().formatGmt('YYYYMMddHHmmss'));
        Blob hash = Crypto.generateDigest('MD5', Blob.valueOf(hashString));
        String hexDigest = EncodingUtil.convertToHex(hash);
        return hexDigest;
    }
    
    public static string getRandomString(Integer size){
        if(size == 0){
            size = 8;
        }
        Blob blobKey = crypto.generateAesKey(128);
        String key   = EncodingUtil.convertToHex(blobKey);
        if(key.length() > size)
            key = key.substring(0,size); 
        return key;
    }
    
}