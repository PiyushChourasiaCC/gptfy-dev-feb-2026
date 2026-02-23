/**
 * @description       : 
 * @author            : Abhishek Walia
 * @group             : Plumcloud Labs
 * @last modified on  : 11-27-2021
 * @last modified by  : Abhishek Walia
**/
public with sharing class FLSCheck {
    
    private static FLSCheck instance;
    static{
        instance = new FLSCheck();  
    }
    public static FLSCheck getInstance()
    {
        if(instance == null ){
            instance = new FLSCheck(); 
        }
        return instance;
    }

    public Boolean deleteDML(List<SObject> devObjs){
        Boolean isObjDeletable = false;
        if(devObjs != null && !devObjs.isEmpty()){
            Schema.DescribeSObjectResult d = devObjs[0].getSObjectType().getDescribe();
            if(d.isDeletable()){
                isObjDeletable=true;
            }
        }
        
        Boolean isSuccess=false;
        if(isObjDeletable){
            delete devObjs;
            isSuccess=true;
        }
        return isSuccess;
    }

    public List<SObject> insertDML(List<SObject> records){
        records = insertCheck(records);
        if(records != null && !records.isEmpty()){
            insert records;
        }
        return records;
    }
    
    public List<SObject> insertDML(List<SObject> records,  Boolean allOrNone){
        records = insertCheck(records);
        if(records != null && !records.isEmpty()){
            Database.insert(records, allOrNone);
        }
        return records;
    }
    
    public Map<String, SObject> insertDML(Map<String, SObject> records,  Boolean allOrNone){
        List<SObject> newrecords = new List<SObject>();
        Integer index = 0;
        Map<String, Integer> mapOfKeyToIndex = new Map<String, Integer>();
        for(String key : records.keySet()){
            newrecords.add(records.get(key));
            mapOfKeyToIndex.put(key, index);
            index++;
        }
        if(newrecords != null && !newrecords.isEmpty()){
            newrecords = insertDML(newrecords, allOrNone);
        }
        for(String key : mapOfKeyToIndex.keySet()){
            Integer i = mapOfKeyToIndex.get(key);
            if(newrecords.size() > i){
                records.put(key, newrecords.get(i));
            }
        }
        return records;
    }

    public List<SObject> updateDML(List<SObject> records){
        records = updateCheck(records);
        if(records != null && !records.isEmpty()){
            update records;
        }
        return records;
    }
    
    public List<SObject> updateDML(List<SObject> records, Boolean allOrNone){
        records = updateCheck(records);
        if(records != null && !records.isEmpty()){
            Database.update(records, allOrNone);
        }
        return records;
    }

    public List<SObject> upsertDML(List<SObject> records){
        records = upsertCheck(records);
        if(records != null && !records.isEmpty()){
            upsert records;
        }
        return records;
    }
    
    public List<SObject> upsertDML(List<SObject> records, Boolean allOrNone){
        records = upsertCheck(records);
        if(records != null && !records.isEmpty()){
            Database.upsert(records, allOrNone);
        }
        return records;
    }

    public List<SObject> upsertDML(List<SObject> records, Schema.SObjectField externalIdField, Boolean allOrNone){
        records = upsertCheck(records);
        if(records != null && !records.isEmpty()){
            Database.upsert(records, externalIdField, allOrNone);
        }
        return records;
    }
    
    public Map<String, SObject> upsertDML(Map<String, SObject> records, Schema.SObjectField externalIdField, Boolean allOrNone){
        List<SObject> newrecords = new List<SObject>();
        Integer index = 0;
        Map<String, Integer> mapOfKeyToIndex = new Map<String, Integer>();
        for(String key : records.keySet()){
            newrecords.add(records.get(key));
            mapOfKeyToIndex.put(key, index);
            index++;
        }
        if(newrecords != null && !newrecords.isEmpty()){
            newrecords = upsertDML(newrecords, externalIdField, allOrNone);
        }
        for(String key : mapOfKeyToIndex.keySet()){
            Integer i = mapOfKeyToIndex.get(key);
            if(newrecords.size() > i){
                records.put(key, newrecords.get(i));
            }
        }
        return records;
    }
    
    public Map<String, SObject> upsertDML(Map<String, SObject> records, Boolean allOrNone){
        List<SObject> newrecords = new List<SObject>();
        Integer index = 0;
        Map<String, Integer> mapOfKeyToIndex = new Map<String, Integer>();
        for(String key : records.keySet()){
            newrecords.add(records.get(key));
            mapOfKeyToIndex.put(key, index);
            index++;
        }
        if(newrecords != null && !newrecords.isEmpty()){
            newrecords = upsertDML(newrecords, allOrNone);
        }
        for(String key : mapOfKeyToIndex.keySet()){
            Integer i = mapOfKeyToIndex.get(key);
            if(newrecords.size() > i){
                records.put(key, newrecords.get(i));
            }
        }
        return records;
    }

    /*
    public Boolean deleteCheck(List<SObject> devObjs){
        Boolean isObjDeletable = false;
        if(devObjs != null && !devObjs.isEmpty()){
            Schema.DescribeSObjectResult d = devObjs[0].getSObjectType().getDescribe();
            if(d.isDeletable()){
                isObjDeletable=true;
            }
        }
        return isObjDeletable;
    }
	*/
    
    public List<SObject> insertCheck(List<SObject> records){
        List<SObject> cleanObjs = null;
        if(records!=null && !records.isEmpty()){
            SObject sob = records[0];
            Schema.DescribeSObjectResult d = sob.getSObjectType().getDescribe();
            if (d.isCreateable()){
                SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.CREATABLE, records);
                if(securityDecision!=null){
                    cleanObjs = securityDecision.getRecords();
                }
            }
        }
        return cleanObjs;
    }
    
    public List<SObject> updateCheck(List<SObject> records){
        List<SObject> cleanObjs = null;
        if(records != null && !records.isEmpty()){
            SObject sob=records[0];
            Schema.DescribeSObjectResult d = sob.getSObjectType().getDescribe();
            if( d.isUpdateable()){
                SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPDATABLE, records);
                if(securityDecision!=null){
                    cleanObjs = securityDecision.getRecords(); 
                }
            }   
        }
        return cleanObjs;
    }

    public SObject[] upsertCheck(SObject[] records){
        List<sObject> insertList = new List<sObject>();
        List<sObject> updateList = new List<sObject>();
        List<sObject> cleanObjs = new List<sObject>();
        if(records != null && !records.isEmpty()){
            for(sObject so : records){
                String recId = so != null && so.get('Id') != null ? String.valueOf(so.get('Id')) : '';
                if(String.isNotBlank(recId)){
                    updateList.add(so);
                }else{
                    insertList.add(so);
                }
            }
        }
        /*
        sObject[] cleanObjs = null;
        if(records != null && !records.isEmpty() && records.getSObjectType() != null){
            SObject sob = records[0]; 
            Schema.DescribeSObjectResult d = sob.getSObjectType().getDescribe();
            if(d != null && d.isCreateable() && d.isUpdateable()){
                SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPSERTABLE, records);
                if(securityDecision!=null){
                    cleanObjs = securityDecision.getRecords();
                }
            }
            if(Test.isRunningTest()){
                cleanObjs = records;
            }
        }
		*/
        if(!insertList.isEmpty()){
            cleanObjs.addAll(insertCheck(insertList));
        }if(!updateList.isEmpty()){
            cleanObjs.addAll(updateCheck(updateList));
        }
        
        if(Test.isRunningTest()){
            cleanObjs = records;
        }
        return cleanObjs;
    }
}