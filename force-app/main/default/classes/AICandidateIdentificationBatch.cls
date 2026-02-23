public with sharing class AICandidateIdentificationBatch implements Database.Batchable<sObject>, Database.Stateful{
    
    public static final Integer RECORD_LIMIT = 2000;
     
    public Integer BATCH_SIZE = 200;
    public List<String> promptIds;
    public Map<String, String> mapOfPromptToCandidateId;
    public Map<String, Map<String, Integer>> mapOfPromptToCandidateIdToGrade;
    public String currentPromptId;
    public List<AI_Prompt__c> promptList;
    public Boolean bestRecordFound = false;
    
    public Database.QueryLocator start(Database.BatchableContext BC){
        if(mapOfPromptToCandidateId == null || mapOfPromptToCandidateId.isEmpty()){
            AISetupAssistantController.updateCandidateSettings(null);
            mapOfPromptToCandidateId = new Map<String, String>();
        }
		mapOfPromptToCandidateIdToGrade = new Map<String, Map<String, Integer>>();	
        promptList = null;
        
        if(String.isBlank(currentPromptId)){
            currentPromptId = promptIds.get(0);
        }

        if(String.isNotBlank(currentPromptId)){
            promptList = [SELECT Id, Object__c, AI_Data_Extraction_Mapping__c 
                                               FROM AI_Prompt__c
                                               WHERE Id =:currentPromptId];
            mapOfPromptToCandidateIdToGrade.put(currentPromptId, new Map<String, Integer>());
        }
        
        String query = 'SELECT Id FROM '+String.escapeSingleQuotes(promptList.get(0).Object__c)+ ' ORDER BY CreatedDate DESC LIMIT '+RECORD_LIMIT;
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext BC, List<sObject> scope){
        
        if(bestRecordFound){
			throw new ApplicationException('Skipping the chunk as the Best record is found.');            
        }
        
        Set<String> setOfRecordIds = new Set<String>();
        Map<String, Integer> mapOfRecordIdToGrade = new Map<String, Integer>();
        for(sObject so : scope){
            String recId = String.valueOf(so.get('Id'));
            mapOfRecordIdToGrade.put(recId, 0);
            setOfRecordIds.add(recId);
        }
        
        AI_Prompt__c pmt = promptList.get(0);
        
        List<AI_Data_Extraction_Detail__c> extractionDetails = AIDataExtractionSelector.getAIDataExtractionDetailByMappingId(pmt.AI_Data_Extraction_Mapping__c);
        for(AI_Data_Extraction_Detail__c extractionDetail : extractionDetails){
        
            // @jira : 4662 Handle ORDER BY in Where Clause of Data Extraction
            String defaultOrderByClause = ' ORDER BY CreatedDate DESC ';
            if(String.isNotBlank(extractionDetail.RelationshipName__c) && extractionDetail.RelationshipName__c == 'ActivityHistories'){
                defaultOrderByClause = ' ORDER BY ActivityDate DESC, LastModifiedDate DESC ';
            }
            String whereClause = AIUtility.getFormattedWhereClause(extractionDetail.Where_Clause__c,defaultOrderByClause,NULL,false);
            
            String parentObject = extractionDetail.Parent_Detail__c != null ? extractionDetail.Parent_Detail__r.Object_Name__c : extractionDetail.AI_Data_Extraction_Mapping__r.Object_Name__c;
            
            String rName = extractionDetail.RelationshipName__c;
            Map<String,String> mapObjNames = new Map<String,String>{
                'Task' => 'Tasks',
                'Event' => 'Events'
            };
            if(String.isNotBlank(rName) && mapObjNames.containsKey(rName) && String.isNotBlank(extractionDetail.RelationshipField__c) && !extractionDetail.RelationshipField__c.equalsIgnoreCase('WhatId') && !extractionDetail.RelationshipField__c.endsWithIgnoreCase('__r')){
                rName = mapObjNames.get(rName);
            }
            
            String query = 'SELECT Id, (SELECT Id FROM '+rName+''+whereClause+') FROM '+parentObject+' WHERE ';
    
            Map<String, String> mapOfChildIdToRecId = new Map<String, String>();
            Set<String> idsSet = new Set<String>();
            
            if(extractionDetail.Type__c == 'CHILD'){
                query += 'Id IN :setOfRecordIds';
            }else if(extractionDetail.Type__c == 'GRANDCHILD'){ 
                String field = extractionDetail.Parent_Detail__r.relationShipField__c;
                for(sObject sobj :database.query('SELECT Id,'+field+' from '+extractionDetail.Parent_Detail__r.Object_Name__c+' where '+field+' IN :setOfRecordIds ')){
                    String p_id = String.valueOf(sobj.get('Id'));
                    String r_id = String.valueOf(sobj.get(field));
                    mapOfChildIdToRecId.put(p_id, r_id);
                    idsSet.add(p_id);
                }
                query += ' Id IN:idsSet ';
            }
            
            List<sObject> lstOfRecords = Database.query(query);
            Set<String> setOfProcessedRecIds = new Set<String>();
            if(lstOfRecords != null && !lstOfRecords.isEmpty()){
                for(sObject so : lstOfRecords){
                    String p_id = String.valueOf(so.get('Id'));
                    Integer rec_count = so.getSobjects(rName) != null ? so.getSobjects(rName).size() : 0;
                    if(rec_count > 0){
                        if(extractionDetail.Type__c == 'CHILD'){
                            Integer count = mapOfRecordIdToGrade.get(p_id);
                            mapOfRecordIdToGrade.put(p_id, (count+1));
                        }else if(extractionDetail.Type__c == 'GRANDCHILD'){
                            if(mapOfChildIdToRecId != null && mapOfChildIdToRecId.containsKey(p_id)){
                                String r_id = mapOfChildIdToRecId.get(p_id);
                                if(!setOfProcessedRecIds.contains(r_id)){
                                    Integer count = mapOfRecordIdToGrade.get(r_id);
                                    mapOfRecordIdToGrade.put(r_id, (count+1));
                                    setOfProcessedRecIds.add(r_id);
                                }
                            }
                        }
                    } 
                }
            }        
        }
        
        Integer max = 0;
        String bestRecordIdInChunk;
        for(String recId : mapOfRecordIdToGrade.keySet()){
            if(max < mapOfRecordIdToGrade.get(recId)){
                max = mapOfRecordIdToGrade.get(recId);
                bestRecordIdInChunk = recId;
            }
        }
        
        mapOfPromptToCandidateIdToGrade.get(currentPromptId).put(bestRecordIdInChunk, max);
        if(max == extractionDetails.size()){
            mapOfPromptToCandidateIdToGrade.put(currentPromptId, new Map<String, Integer>{bestRecordIdInChunk => max});
            bestRecordFound = true;
        }
    }
    
    public void finish(Database.BatchableContext BC){
        if(mapOfPromptToCandidateIdToGrade != null && mapOfPromptToCandidateIdToGrade.containsKey(currentPromptId)){
            Integer max = 0;
            String bestRecordId;
            Map<String, Integer> mapOfRecordIdToGrade = mapOfPromptToCandidateIdToGrade.get(currentPromptId);
            for(String recId :  mapOfRecordIdToGrade.keySet()){
                if(max < mapOfRecordIdToGrade.get(recId)){
                    max = mapOfRecordIdToGrade.get(recId);
                    bestRecordId = recId;
                }
            }
            
            if(String.isBlank(bestRecordId)){
                bestRecordId = 'NO_RECORD_FOUND';
            }
            mapOfPromptToCandidateId.put(currentPromptId, bestRecordId);
            AISetupAssistantController.updateCandidateSettings(mapOfPromptToCandidateId);
        }
        
        Integer index = promptIds.indexOf(currentPromptId);
        if((index+1) < promptIds.size()){
            AICandidateIdentificationBatch job = new AICandidateIdentificationBatch();
            job.promptIds = promptIds;
            job.mapOfPromptToCandidateId = mapOfPromptToCandidateId;
            job.currentPromptId = promptIds.get(index+1);
            Integer batchSize = 50;
            if(BATCH_SIZE != null && BATCH_SIZE > 0){
                batchSize = BATCH_SIZE;
            }
            Database.executeBatch(job, batchSize);
        }
    }
    
    public class ApplicationException extends Exception {}
    
}