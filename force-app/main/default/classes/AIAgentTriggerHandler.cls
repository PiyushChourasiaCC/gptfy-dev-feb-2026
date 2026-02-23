public with sharing class AIAgentTriggerHandler {
    public static void onBeforeInsert(List<AI_Agent__c> newList){
        generateUniqueKey(newList);
    }
    
    public static void generateUniqueKey(List<AI_Agent__c> newList){
        for(AI_Agent__c ac : newList){
            ac.Developer_Name__c = convertToDeveloperName(ac.Name)+DateTime.now().format();
        }
    }
    
     public static String convertToDeveloperName(String name) {
        if (String.isBlank(name)) return null;
        
        // Step 1: Trim leading/trailing whitespace
        String cleaned = name.trim();
        
        // Step 2: Replace any non-alphanumeric characters (except underscore and space) with nothing
        cleaned = cleaned.replaceAll('[^A-Za-z0-9 _]', '');

        // Step 3: Replace spaces with underscores
        cleaned = cleaned.replaceAll('[\\s]+', '_');

        return cleaned;
    }
}