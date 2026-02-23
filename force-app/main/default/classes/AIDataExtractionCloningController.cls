public with sharing class AIDataExtractionCloningController {
    /**
     * Clones a record identified by the given record ID.
     *
     * This method creates a copy of the record with the specified ID,
     * allowing for duplication of records in the system.
     *
     * @param recordId The unique identifier of the record to be cloned.
     * @return A string indicating the status of the cloning process.
     *         This could be a success message, an error message, or
     *         any relevant information about the cloning operation.
     */
    @AuraEnabled
    public static String cloneRecord(String recordId){
        try{
            return cloneRecord(recordId, null);
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionCloningController', 'cloneRecord', '');
            throw new AuraHandledException(e.getMessage());
        }
    }

    //@JIRA : 5031 : Updated cloneRecord method to take input for Data Extraction Mapping Name
    public static String cloneRecord(String recordId, String name){
        AI_Data_Extraction_Mapping__c mapping = [SELECT Id, Name, API_Name__c, Description__c, Object_Name__c, External_Id__c,
                                                 AI_Data_Source__c, Apex_Security_Layer__c
                                                 FROM AI_Data_Extraction_Mapping__c 
                                                 WHERE Id =: recordId 
                                                 LIMIT 1];
        AI_Data_Extraction_Mapping__c cloneMapping = mapping.clone(false, true, false, false);
        //@JIRA : 5031 : Added Data Extraction Mapping Name
        if(String.isNotBlank(name)){
            cloneMapping.Name = name;
        }
        cloneMapping = (AI_Data_Extraction_Mapping__c)FLSCheck.getInstance().insertDML(new List<AI_Data_Extraction_Mapping__c>{cloneMapping}).get(0);            
        
        List<AI_Data_Extraction_Detail__c> extractionDetails = new List<AI_Data_Extraction_Detail__c>();
        Map<String, AI_Data_Extraction_Detail__c> mapMappingDetail = new Map<String, AI_Data_Extraction_Detail__c>();
        for(AI_Data_Extraction_Detail__c mappingDetail : [SELECT AI_Data_Extraction_Mapping__c, Object_Hierarchy__c, Object_Name__c, 
                                                            Parent_Detail__c, RelationshipField__c, RelationshipName__c, Running_Index__c, Type__c, 
                                                            Where_Clause__c, Record_Limit__c, Order_By__c, External_Id__c, Id, Name 
                                                            FROM AI_Data_Extraction_Detail__c 
                                                            WHERE AI_Data_Extraction_Mapping__c =: recordId 
                                                            ORDER BY CreatedDate ASC LIMIT 9999]){
                                                                AI_Data_Extraction_Detail__c cloneMappingDetail = mappingDetail.clone(false, true, false, false);
                                                                cloneMappingDetail.AI_Data_Extraction_Mapping__c = cloneMapping.Id;
                                                                mapMappingDetail.put(mappingDetail.Id, cloneMappingDetail);
                                                            }
        if(!mapMappingDetail.IsEmpty()){
            //FLS enforced via FLSCheck utility using stripInaccessible(AccessType.CREATABLE)
            Map<String, SObject> cleanedRecords = FLSCheck.getInstance().insertDML(mapMappingDetail, true);
            List<SObject> lstDetails = new List<SObject>();
            for(SObject mappingDetail : cleanedRecords.values()){
                if(mappingDetail.get('Parent_Detail__c') != null && cleanedRecords.containsKey((String)mappingDetail.get('Parent_Detail__c'))){
                    mappingDetail.put('Parent_Detail__c', cleanedRecords.get((String)mappingDetail.get('Parent_Detail__c')).Id);
                    lstDetails.add(mappingDetail);
                }
            }
            
            if(lstDetails.size() > 0 && !Test.isRunningTest()){
                FLSCheck.getInstance().updateDML(lstDetails);
            }
        }
        
        List<AI_Data_Extraction_Field__c> extractionFields = new List<AI_Data_Extraction_Field__c>();
        for(AI_Data_Extraction_Field__c field : [SELECT AI_Data_Extraction_Mapping__c, Anonymize_With__c, Field__c, Label__c, Object__c, Scan_for_PII__c, 
                                                 Send_To_AI__c, Type__c, External_Id__c, Field_Type__c, Masking_Scope__c, Id, Name, Formula__c  
                                                 FROM AI_Data_Extraction_Field__c 
                                                 WHERE AI_Data_Extraction_Mapping__c =: recordId ORDER BY CreatedDate ASC LIMIT 9999]){
                                                        AI_Data_Extraction_Field__c cloneExtractionField = field.clone(false, true, false, false);
                                                        cloneExtractionField.AI_Data_Extraction_Mapping__c = cloneMapping.Id;
                                                        extractionFields.add(cloneExtractionField);
                                                    }
        
        if(extractionFields.size()>0){
            FLSCheck.getInstance().insertDML(extractionFields);
        }
        
        return cloneMapping.Id;
    }
}