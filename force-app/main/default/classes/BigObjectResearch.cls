public class BigObjectResearch {
    public static void createRecord(String accountId){
        Account_Config__b obj = new Account_Config__b();
        obj.Account_Name__c = 'Test Inserted';
        obj.Account__c = accountId;
        System.debug(database.insertImmediate(obj));
        System.debug([SELECT Id FROM Account_Config__b].size());
        System.debug([SELECT Account_Name__c FROM Account_Config__b]);
    }
    public static void updateRecord(String accountId){
        Account_Config__b obj = new Account_Config__b();
        obj.Account_Name__c = 'Test Updated';
        obj.Account__c = accountId;
        System.debug(database.insertImmediate(obj));
        System.debug([SELECT Id FROM Account_Config__b].size());
        System.debug([SELECT Account_Name__c FROM Account_Config__b]);
    }
    public static void deleteRecord(String accountId){
       	database.deleteImmediate([SELECT Account__c FROM Account_Config__b WHERE Account__c = :accountId]);
        System.debug([SELECT Id FROM Account_Config__b].size());
        System.debug([SELECT Account_Name__c FROM Account_Config__b]);
    }
}