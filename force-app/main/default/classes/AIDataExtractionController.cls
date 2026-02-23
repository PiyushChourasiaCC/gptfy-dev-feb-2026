/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIDataExtractionController {
    
    public static Map<String, Schema.SObjectType> schemaMap;
    static{
        schemaMap = Schema.getGlobalDescribe();
    }
	
    /**
     * Retrieves master data for a given record ID.
     *
     * This method takes a record ID as a parameter and returns a MasterWrapper
     * object containing the relevant master data. If the record ID is not found
     * or if there is an error during data retrieval, this method may return null.
     *
     * @param recordId The unique identifier of the record for which master data is requested.
     * @return A MasterWrapper object containing the master data, or null if not found or an error occurs.
     */
    @AuraEnabled
    public static MasterWrapper getMasterData(String recordId){
        try{
            MasterWrapper wrap = new MasterWrapper();
            wrap.objects = getSObjects();
            wrap.dataSourceOptions = getDataSourceOptions();
            wrap.apexSecurityLayerOptions = getApexSecurityLayerOptions();
            if(String.isNotBlank(recordId)){
                List<AI_Data_Extraction_Mapping__c> lstOfMasters = [SELECT Id, Name, Object_Name__c, Description__c, 
                                                                    AI_Data_Source__c, Apex_Security_Layer__c 
                                                                   FROM AI_Data_Extraction_Mapping__c WHERE Id =:recordId];
                if(lstOfMasters != null && !lstOfMasters.isEmpty()){
                    AI_Data_Extraction_Mapping__c master = lstOfMasters.get(0);
                    wrap.objectName = master.Object_Name__c;
                    wrap.mappingName = master.Name;
                    wrap.description = master.Description__c;
                    wrap.aiDataSource = master.AI_Data_Source__c;
                    wrap.apexSecurityLayer = master.Apex_Security_Layer__c;
                    
                    List<AI_Data_Extraction_Field__c> lstOfFields = [SELECT Id, Label__c FROM AI_Data_Extraction_Field__c
                                                                     WHERE Type__c = 'OBJECT' AND Object__c =:master.Object_Name__c
                                                                     AND AI_Data_Extraction_Mapping__c =:recordId];
                    if(lstOfFields != null && !lstOfFields.isEmpty()){
                        wrap.objectLabel = lstOfFields.get(0).Label__c;
                    }
                }
            }
            return wrap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'getMasterData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the data source options for the AI data extraction controller, providing a list of PicklistWrapper objects containing the available connection options.
     * 
     * @return List<PicklistWrapper> A list of PicklistWrapper objects representing the connection options for the AI data extraction controller, ready for user selection or processing.
     */
    @AuraEnabled
    public static List<PicklistWrapper> getDataSourceOptions(){
        try{
            List<PicklistWrapper> options = new List<PicklistWrapper>();
            List<String> activeDataSource = new List<String>();
            for(AI_Card_Configuration__c mdt : [SELECT Id, Name 
                                                     FROM AI_Card_Configuration__c 
                                                     WHERE Enabled__c = true 
                                                     AND Feature__c =:AIConstants.GPTFY_CARD_CONFIGURATION_MDT_APIDS]){
                activeDataSource.add(mdt.Name.toLowercase());
            }
            
            PicklistWrapper noneOpt = new PicklistWrapper();
            noneOpt.label = '--None--';
            noneOpt.value = '';
            options.add(noneOpt);
            
            for(AI_Data_Source__c p : [SELECT Id, Name FROM AI_Data_Source__c 
                                      ORDER BY Name LIMIT 50000]){
                if(activeDataSource.contains(p.Name.toLowercase())){
                    PicklistWrapper wrap = new PicklistWrapper();
                    wrap.label = p.Name;
                    wrap.value = p.Id;
                    options.add(wrap);
                }  
            }
            return options;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getConnectionOptions', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the Security Layer options for the AI data extraction controller, providing a list of PicklistWrapper objects containing the available Security Layer options.
     * 
     * @return List<PicklistWrapper> A list of PicklistWrapper objects representing the Security Layer options for the AI data extraction controller, ready for user selection or processing.
     */
    @AuraEnabled
    public static List<PicklistWrapper> getApexSecurityLayerOptions(){
        try{
            List<PicklistWrapper> options = new List<PicklistWrapper>();
            PicklistWrapper noneOpt = new PicklistWrapper();
            noneOpt.label = '--None--';
            noneOpt.value = '';
            options.add(noneOpt);
            Set<String> setApexClassName = new Set<String>();
            for(AI_Security_Filters__c filter : [SELECT Id, Name, Apex_Class_Name__c FROM AI_Security_Filters__c 
                                            WHERE Status__c = 'Active' AND Apex_Class_Name__c != null
                                      		ORDER BY Name LIMIT 50000]){
                PicklistWrapper wrap = new PicklistWrapper();
                wrap.label = filter.Name;
                wrap.value = filter.Id;
                if(!setApexClassName.contains(filter.Apex_Class_Name__c)){
                    options.add(wrap);
                    setApexClassName.add(filter.Apex_Class_Name__c);
                }
            }
            return options;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptController', 'getApexSecurityLayerOptions', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Modifies a Data Context Mapping record based on specified parameters.
     *
     * @param recordId      The identifier of the record to be modified.
     * @return              none
     */
    @AuraEnabled
    public static void updateDataExtractionMappingAsDraft(String recordId){
        try{
            AI_Data_Extraction_Mapping__c deMapping = new AI_Data_Extraction_Mapping__c(Id=recordId);
            deMapping.Status__c = AIConstants.PMT_STATUS_DRAFT;
            FLSCheck.getInstance().updateDML(new List<AI_Data_Extraction_Mapping__c>{deMapping});
        }catch(DMLException dmlex){
            throw new AuraHandledException(dmlex.getDMLMessage(0));
        }catch(Exception ex){
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * Modifies a master record based on specified parameters.
     *
     * @param recordId      The identifier of the record to be modified.
     * @param mappingName   The name of the mapping associated with the modification.
     * @param targetObject  The target object for the modification.
     * @param description   A description or additional information about the modification.
     * @param objLabel      The label associated with the object being modified.
     * @return              A String indicating the result or status of the modification.
     */
    @AuraEnabled
    public static String modifyMaster(Map<String, String> data){
        try{
            String recordId = String.valueOf(data.get('recordId'));
            String mappingName = String.valueOf(data.get('mappingName'));
            String targetObject = String.valueOf(data.get('targetObject'));
            String description = String.valueOf(data.get('description')); 
            String objLabel = String.valueOf(data.get('objLabel'));
            String aiDataSource = String.valueOf(data.get('aiDataSource'));
            String apexSecurityLayer = String.valueOf(data.get('apexSecurityLayer'));
            
            String masterId;
            AI_Data_Extraction_Mapping__c master = new AI_Data_Extraction_Mapping__c();
            master.Name = mappingName;
            master.Description__c = description;
            master.Apex_Security_Layer__c = null;
            if(!String.isBlank(apexSecurityLayer)){
                master.Apex_Security_Layer__c = apexSecurityLayer;
            }
            master.AI_Data_Source__c = String.isNotBlank(aiDataSource) ? aiDataSource : null;
            if(String.isNotBlank(recordId)){
                master.Id = recordId;
            }else{
                master.Object_Name__c = targetObject;
            }
            
            List<sObject> records = FLSCheck.getInstance().upsertDML(new List<AI_Data_Extraction_Mapping__c>{master});
            if(records != null && !records.isEmpty()){
                masterId = records.get(0).Id;
                
                List<AI_Data_Extraction_Field__c> lstOfFields = [SELECT Id, Label__c FROM AI_Data_Extraction_Field__c
                                                                    WHERE Type__c = 'OBJECT' AND Object__c =:targetObject
                                                                    AND AI_Data_Extraction_Mapping__c =:recordId];
                
                AI_Data_Extraction_Field__c fm = new AI_Data_Extraction_Field__c();
                
                try{
					Schema.DescribeSObjectResult describeObj = Schema.getGlobalDescribe().get(targetObject).getDescribe();
					fm.Label__c = String.isNotBlank(objLabel) ? objLabel : describeObj.getLabel();                    
                }catch(Exception e){
                    fm.Label__c = objLabel;
                }
                
                if(lstOfFields != null && !lstOfFields.isEmpty()){
                    fm.Id = lstOfFields.get(0).Id;
                    FLSCheck.getInstance().updateDML(new List<AI_Data_Extraction_Field__c>{fm});
                }else{
                    fm.AI_Data_Extraction_Mapping__c = masterId;
                    fm.Object__c = targetObject;
                    fm.Type__c = 'OBJECT';
                    fm.Field__c = targetObject;
                    FLSCheck.getInstance().insertDML(new List<AI_Data_Extraction_Field__c>{fm});
                }
            }
            return masterId;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'modifyMaster', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the detail hierarchy for a given master identifier.
     *
     * This method fetches and returns a DataWrapper containing the hierarchical details
     * associated with the specified master identifier.
     *
     * @param masterId The identifier of the master record for which the detail hierarchy
     *                 needs to be fetched.
     * @return A DataWrapper object containing the hierarchical details, or null if no
     *         details are found for the given master identifier.
     */
    @AuraEnabled
    public static DataWrapper fetchDetailHierarchy(String masterId) {
        try{
            HierarchyWrapper t_wrap = new HierarchyWrapper();
            List<AI_Data_Extraction_Mapping__c> lstOfMasters = [SELECT Id, Object_Name__c FROM AI_Data_Extraction_Mapping__c WHERE Id =:masterId];
            
            Map<String, AI_Data_Extraction_Field__c> mapOfObjNameToObjMapping = new Map<String, AI_Data_Extraction_Field__c>();
            Map<String, Integer> mapOfObjNameToTotalFields = new Map<String, Integer>();
            Map<String, Integer> mapOfObjNameToFields = new Map<String, Integer>();
            Map<String, Integer> mapOfObjNameToRelatedFields = new Map<String, Integer>();
            Map<String, DataCloudWrapper> dataCloudObjectMap = new Map<String, DataCloudWrapper>();
            GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
            if(gptfySetting.Enable_for_Data_Cloud__c){
                dataCloudObjectMap = getObjectsWithFieldCountFromDataCloud();
            }
            
            for(AI_Data_Extraction_Field__c obj : [SELECT Id, Field__c, Object__c, Label__c, Type__c FROM AI_Data_Extraction_Field__c 
                                                WHERE AI_Data_Extraction_Mapping__c =:masterId
                                                ORDER BY Type__c DESC]){
                if(obj.Type__c == 'OBJECT'){
                    if(!mapOfObjNameToObjMapping.containsKey(obj.Object__c)){
                        mapOfObjNameToObjMapping.put(obj.Object__c, obj);
                    }if(!mapOfObjNameToFields.containsKey(obj.Object__c)){
                        mapOfObjNameToFields.put(obj.Object__c, 0);
                        mapOfObjNameToRelatedFields.put(obj.Object__c, 0);
                        Integer totalFields = 0;
                        if(obj.Object__c.endsWithIgnoreCase('__dlm')){
                            if(!dataCloudObjectMap.isEmpty() && dataCloudObjectMap.get(obj.Object__c) != Null){
                                DataCloudWrapper dcwrap = dataCloudObjectMap.get(obj.Object__c);
                            	totalFields = dcwrap.fieldCount;
                            }
                        }else{
                            totalFields = schemaMap.get(obj.Object__c).getDescribe().fields.getMap().size();
                        }
                        mapOfObjNameToTotalFields.put(obj.Object__c, totalFields);
                    }
                }else{
                    if(obj.Field__c.contains('.')){
                        Integer oldVal = mapOfObjNameToRelatedFields.get(obj.Object__c);
                        mapOfObjNameToRelatedFields.put(obj.Object__c, oldVal + 1);
                    }else{
                        Integer oldVal = mapOfObjNameToFields.get(obj.Object__c);
                        mapOfObjNameToFields.put(obj.Object__c, oldVal + 1);
                    }
                }                                        
            }
            
            Map<String, String> mapOfObjNameToFieldCount = new Map<String, String>();
            for(String oName : mapOfObjNameToTotalFields.keySet()){
                Integer total = mapOfObjNameToTotalFields.get(oName);
                Integer active = 0;
                if(mapOfObjNameToFields != null && mapOfObjNameToFields.containsKey(oName)){
                    active += mapOfObjNameToFields.get(oName);
                }if(mapOfObjNameToRelatedFields != null && mapOfObjNameToRelatedFields.containsKey(oName)){
                    total += mapOfObjNameToRelatedFields.get(oName);
                    active += mapOfObjNameToRelatedFields.get(oName);
                }
                mapOfObjNameToFieldCount.put(oName, (active+'/'+total));
            }
            
            Boolean hasError = false;
            Map<String, HierarchyWrapper> mapOfDetail = new Map<String, HierarchyWrapper>();
            List<String> detailIds = new List<String>();
            
            if(lstOfMasters != null && !lstOfMasters.isEmpty()){
                AI_Data_Extraction_Mapping__c master = lstOfMasters.get(0);
                
                List<AI_Data_Extraction_Detail__c> parentList = new List<AI_Data_Extraction_Detail__c>();
                List<AI_Data_Extraction_Detail__c> childList = new List<AI_Data_Extraction_Detail__c>();
                
                for(AI_Data_Extraction_Detail__c detail : [SELECT Id,Running_Index__c, Parent_Detail__c, Parent_Detail__r.Object_Name__c, RelationshipField__c, AI_Data_Extraction_Mapping__c, 
                                                        AI_Data_Extraction_Mapping__r.Object_Name__c, Object_Name__c, Where_Clause__c, Type__c, Order_By__c, Record_Limit__c 
                                                        FROM AI_Data_Extraction_Detail__c WHERE AI_Data_Extraction_Mapping__c =:masterId  
                                                        ORDER BY Parent_Detail__c ASC NULLS FIRST, Object_Name__c]){
                    if(detail.Parent_Detail__c != null){
                        childList.add(detail);
                    }else{
                        parentList.add(detail);
                    }
                    if(!mapOfDetail.containsKey(detail.Id)){
                        HierarchyWrapper wrap = getMappedHierarchyWrapper(detail, mapOfObjNameToObjMapping, mapOfObjNameToFieldCount, dataCloudObjectMap);
                        mapOfDetail.put(detail.Id, wrap);
                    }                                         
                }
                
                List<HierarchyWrapper> listWrap = new List<HierarchyWrapper>();
                
                if(!parentList.isEmpty()){
                    for(AI_Data_Extraction_Detail__c detail : parentList){
                        if(mapOfDetail.containsKey(detail.Id)){
                            HierarchyWrapper wrap = mapOfDetail.get(detail.Id);
                            if(!childList.isEmpty()){ 
                                wrap.children = findRelations(childList, detail.Id, mapOfObjNameToObjMapping, mapOfObjNameToFieldCount, dataCloudObjectMap);
                            }
                            listWrap.add(wrap);
                        } 
                    }
                }
                
                t_wrap.objectName = master.Object_Name__c ;                                        
                t_wrap.children = listWrap;
                t_wrap.detailId = 'NA';
                if(master.Object_Name__c.contains('__dlm')){
                    DataCloudWrapper dcwrap = dataCloudObjectMap.get(master.Object_Name__c);
                    t_wrap.objectLabel = dcwrap.label;
                }else{
                    t_wrap.objectLabel = schemaMap.get(t_wrap.objectName).getDescribe().getLabel();
                }
                
                if(!mapOfObjNameToObjMapping.isEmpty() && mapOfObjNameToObjMapping.containsKey(t_wrap.objectName)){
                    t_wrap.objectLabel = mapOfObjNameToObjMapping.get(t_wrap.objectName).Label__c;
                }
                Integer tFields = 0; Integer aFields = 0;
                if(mapOfObjNameToTotalFields != null && mapOfObjNameToTotalFields.containsKey(t_wrap.objectName)){
                    tFields += mapOfObjNameToTotalFields.get(t_wrap.objectName);
                }if(mapOfObjNameToFields != null && mapOfObjNameToFields.containsKey(t_wrap.objectName)){
                    aFields += mapOfObjNameToFields.get(t_wrap.objectName);
                }if(mapOfObjNameToRelatedFields != null && mapOfObjNameToRelatedFields.containsKey(t_wrap.objectName)){
                    tFields += mapOfObjNameToRelatedFields.get(t_wrap.objectName);
                    aFields += mapOfObjNameToRelatedFields.get(t_wrap.objectName);
                }
                t_wrap.fieldsCount = aFields+'/'+tFields;
                detailIds.add(t_wrap.detailId);
                mapOfDetail.put(t_wrap.detailId, t_wrap);
            }
            
            DataWrapper dw = new DataWrapper();
            dw.hasError = hasError;
            dw.details = new List<HierarchyWrapper>{t_wrap};  
            detailIds.addAll(mapOfDetail.keySet());
            dw.detailIds = detailIds;
            dw.detailMap = mapOfDetail;
        	dw.dataCloudMap = dataCloudObjectMap;
            return dw;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'fetchDetailHierarchy', '');
            throw new AuraHandledException(e.getMessage());
        } 
    }

    /**
     * Finds relations in a hierarchical structure based on provided parameters.
     *
     * @param listOfDetails             List of AI_Data_Extraction_Detail__c objects representing the details.
     * @param rootId                    The root ID to start the hierarchy traversal.
     * @param mapOfObjNameToObjMapping  Mapping of object names to corresponding AI_Data_Extraction_Field__c objects.
     * @param mapOfObjNameToFieldCount  Mapping of object names to the count of fields for each object.
     * @return                          List of HierarchyWrapper objects representing the hierarchical relations found.
     */
    public static List<HierarchyWrapper> findRelations(List<AI_Data_Extraction_Detail__c> listOfDetails, Id rootId, Map<String, AI_Data_Extraction_Field__c> mapOfObjNameToObjMapping, Map<String, String> mapOfObjNameToFieldCount,Map<String, DataCloudWrapper> dataCloudObjectMap){
    	try{
            List<HierarchyWrapper> listWrap = new List<HierarchyWrapper>();
            for (AI_Data_Extraction_Detail__c detail : listOfDetails) {
                if (detail.Parent_Detail__c == rootId) {
                    HierarchyWrapper wrap = getMappedHierarchyWrapper(detail, mapOfObjNameToObjMapping, mapOfObjNameToFieldCount,dataCloudObjectMap);
                    wrap.children = findRelations(listOfDetails, detail.Id, mapOfObjNameToObjMapping, mapOfObjNameToFieldCount,dataCloudObjectMap);
                    listWrap.add(wrap);
                }
            }
    
            //if(!listWrap.isEmpty()){
                return listWrap;
            //} 
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'findRelations', '');
            return null;
        }
    }
    
    /**
     * Retrieves a mapped hierarchy wrapper for the given AI_Data_Extraction_Detail__c,
     * using the provided mappings and field counts.
     *
     * @param detail The AI_Data_Extraction_Detail__c object for which the hierarchy wrapper is needed.
     * @param mapOfObjNameToObjMapping A map containing object names as keys and corresponding
     *        AI_Data_Extraction_Field__c objects as values, representing the mappings.
     * @param mapOfObjNameToFieldCount A map containing object names as keys and the associated field
     *        count as values, representing the field count for each object.
     * @return A HierarchyWrapper object containing the mapped hierarchy details.
     */
    public static HierarchyWrapper getMappedHierarchyWrapper(AI_Data_Extraction_Detail__c detail, Map<String, AI_Data_Extraction_Field__c> mapOfObjNameToObjMapping, Map<String, String> mapOfObjNameToFieldCount,Map<String, DataCloudWrapper> dataCloudObjectMap){
        try{
            HierarchyWrapper wrap = new HierarchyWrapper();
            wrap.detailId = detail.Id;
            wrap.parentId = detail.Parent_Detail__c;
            wrap.objectName = detail.Object_Name__c ;
            wrap.filterField = detail.Where_Clause__c == null ? '' : detail.Where_Clause__c;
            wrap.orderBy = detail.Order_By__c == null ? '' : detail.Order_By__c;
            wrap.recordLimit = detail.Record_Limit__c != null ? (Integer)detail.Record_Limit__c : null;
            if(detail.Parent_Detail__c != null){
                wrap.relationshipOptions = getTargetFields(detail.Parent_Detail__r.Object_Name__c, detail.Object_Name__c,dataCloudObjectMap,false);
            }else{
                wrap.relationshipOptions = getTargetFields(detail.AI_Data_Extraction_Mapping__r.Object_Name__c, detail.Object_Name__c,dataCloudObjectMap,false);
            }                                         
            wrap.relationshipField = detail.RelationshipField__c ;
            if(wrap.ObjectName.contains('__dlm')){
                DataCloudWrapper dcwrap = dataCloudObjectMap.get(wrap.ObjectName);
                wrap.objLabel = dcwrap.label;
            }else{
                wrap.objLabel = Schema.getGlobalDescribe().get(wrap.objectName).getDescribe().getLabel();
            }
            
            if(!mapOfObjNameToObjMapping.isEmpty() && mapOfObjNameToObjMapping.containsKey(wrap.objectName)){
                wrap.objectLabel = mapOfObjNameToObjMapping.get(wrap.objectName).Label__c;
            }
            if(mapOfObjNameToFieldCount != null && mapOfObjNameToFieldCount.containsKey(wrap.objectName)){
                wrap.fieldsCount = mapOfObjNameToFieldCount.get(wrap.objectName);
            }
            wrap.runningIndex =  detail.Running_Index__c != Null ? (Integer)detail.Running_Index__c : Null;
            return wrap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'getMappedHierarchyWrapper', '');
            return null;
        }
    }
    
    /**
     * Deletes the mapping between a master object and a related detail object in a given target object.
     *
     * @param masterId      The identifier of the master object.
     * @param detailId      The identifier of the detail object to be unmapped.
     * @param targetObject  The target object in which the mapping should be deleted.
     */
    @AuraEnabled
    public static void deleteRelatedObjectMapping(String masterId, String detailId, String targetObject){
        try{
            if(String.isNotBlank(detailId)){
            
                Map<Id, AI_Data_Extraction_Detail__c> mapOfIdToDetail = new Map<Id, AI_Data_Extraction_Detail__c>([
                    SELECT Id, Object_Name__c, Parent_Detail__c FROM AI_Data_Extraction_Detail__c
                    WHERE AI_Data_Extraction_Mapping__c =:masterId
                ]);
                if(!mapOfIdToDetail.isEmpty() && mapOfIdToDetail.containsKey(detailId)){
                    List<AI_Data_Extraction_Detail__c> lstMappingsToDelete = new List<AI_Data_Extraction_Detail__c>();
                    lstMappingsToDelete.add(mapOfIdToDetail.get(detailId));
                    
                    List<AI_Data_Extraction_Detail__c> childMappingsToDelete = findChildMappings(mapOfIdToDetail.values(), detailId);
                    if(childMappingsToDelete != null && !childMappingsToDelete.isEmpty()){
                        lstMappingsToDelete.addAll(childMappingsToDelete);
                    }
                    
                    Set<String> setofObjectNames = new Set<String>();
                    for(AI_Data_Extraction_Detail__c detail : lstMappingsToDelete){
                        if(targetObject != detail.Object_Name__c){
                            setofObjectNames.add(detail.Object_Name__c);
                        }
                    }
                    for(AggregateResult aggr : [SELECT COUNT(Id), Object_Name__c oName FROM AI_Data_Extraction_Detail__c 
                                                WHERE AI_Data_Extraction_Mapping__c =:masterId AND Object_Name__c IN :setofObjectNames  
                                                GROUP BY Object_Name__c HAVING COUNT(Id) > 1 ]){
                        String objName = String.valueOf(aggr.get('oName'));                    
                        if(String.isNotBlank(objName)){
                            setofObjectNames.remove(objName);
                        }
                    }
                    
                    FLSCheck.getInstance().deleteDML(lstMappingsToDelete);
                    if(!setofObjectNames.isEmpty()){
                        List<AI_Data_Extraction_Field__c> lstOfObjectsToBeDeleted = [SELECT Id FROM AI_Data_Extraction_Field__c 
                                                                                     WHERE AI_Data_Extraction_Mapping__c =:masterId 
                                                                                     AND Object__c IN :setofObjectNames];
                        if(lstOfObjectsToBeDeleted != null && !lstOfObjectsToBeDeleted.isEmpty()){
                            FLSCheck.getInstance().deleteDML(lstOfObjectsToBeDeleted);
                        }
                    }
                }
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'deleteRelatedObjectMapping', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Finds child mappings of AI_Data_Extraction_Detail__c objects based on a rootId.
     *
     * @param listOfDetails A list of AI_Data_Extraction_Detail__c objects to search through.
     * @param rootId        The Id used as a reference to find child mappings.
     * @return              A List<AI_Data_Extraction_Detail__c> containing the child mappings.
     *                      If no child mappings are found, an empty list is returned.
     */
    public static List<AI_Data_Extraction_Detail__c> findChildMappings(List<AI_Data_Extraction_Detail__c> listOfDetails, Id rootId) {
        try{
            List<AI_Data_Extraction_Detail__c> lstOfMapping = new List<AI_Data_Extraction_Detail__c>();
            for (AI_Data_Extraction_Detail__c detail : listOfDetails) {
                if (detail.Parent_Detail__c == rootId) {
                    lstOfMapping.add(detail);
                    lstOfMapping.addAll(findChildMappings(listOfDetails, detail.Id));
                }
            }
            return lstOfMapping;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'findChildMappings', '');
            return null;
        }
    }
    
    /**
     * Retrieves a list of related objects (wrapped in PicklistWrapper) based on the provided parameters.
     *
     * @param masterId    The identifier of the master object.
     * @param parentObject The type of the parent object for which related objects are being retrieved.
     * @param parentId     The identifier of the parent object.
     * @return A list of PicklistWrapper objects representing the related objects.
     */
    @AuraEnabled
    public static List<PicklistWrapper> getRelatedObjects(String masterId, String parentObject, String parentId){
        try{
            List<PicklistWrapper> lstOfWrapper = new List<PicklistWrapper>();
            Set<String> alreadySet= new Set<String>();
            for(AI_Data_Extraction_Detail__c detail : [SELECT Id, Object_Name__c FROM AI_Data_Extraction_Detail__c 
                                                    	WHERE AI_Data_Extraction_Mapping__c =:masterId 
                                                    	AND Parent_Detail__c =:parentId]){
                alreadySet.add(detail.Object_Name__c);
            }
        
        
        	GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
            
            if(parentObject != '' && parentObject.contains('__dlm')){
                if(gptfySetting.Enable_for_Data_Cloud__c){
                    Map<String, Object> metadataMap = getDMOObjectFromDataCloud(gptfySetting,parentObject);
                    List<Object> relationshipObjs = (List<Object>) metadataMap.get('relationships');
                    for(Object obj : relationshipObjs){
                        Map<String, Object> objMap = (Map<String, Object>) obj;
                        PicklistWrapper pv = new PicklistWrapper();
                            pv.value = String.valueOf(objMap.get('fromEntity'));
                            pv.label = String.valueOf(objMap.get('fromEntity')) + ' ('+pv.value+')';
                            pv.firstValue = String.valueOf(objMap.get('fromEntity'));
                            lstOfWrapper.add(pv);
                    }
                }
            }else{
                
                if(gptfySetting.Enable_for_Data_Cloud__c){
                    lstOfWrapper.addAll(getSObjectsFromDataCloud(gptfySetting));
                } 
                
                Schema.DescribeSObjectResult describeObj = schemaMap.get(parentObject).getDescribe();
                for(Schema.ChildRelationship cr: describeObj.getChildRelationships()){
                    if(schemaMap.containsKey(String.valueOf(cr.getChildSObject()))){
                        Schema.DescribeSObjectResult describeChildObj = schemaMap.get(String.valueOf(cr.getChildSObject())).getDescribe();
                        if(!alreadySet.contains(describeChildObj.getName()) && !AIConstants.EXTRACTION_OBJECTS_TO_SKIP.contains(describeChildObj.getName())){
                            PicklistWrapper pv = new PicklistWrapper();
                            pv.value = String.valueOf(describeChildObj.getName());
                            pv.label = String.valueOf(describeChildObj.getLabel()) + ' ('+pv.value+')';
                            pv.firstValue = String.valueOf(describeChildObj.getLabel());
                            lstOfWrapper.add(pv);
                            alreadySet.add(String.valueOf(describeChildObj.getName()));
                        }
                    }else if(String.valueOf(cr.getChildSObject()).endsWithIgnoreCase('__dlm')){
                        	PicklistWrapper pv = new PicklistWrapper();
                            pv.value = String.valueOf(cr.getChildSObject());
                            pv.label = String.valueOf(cr.getChildSObject()) + ' ('+pv.value+')';
                            pv.firstValue = String.valueOf(cr.getChildSObject());
                            lstOfWrapper.add(pv);
                    } 
                }
                if(!alreadySet.contains(AIConstants.CONTENT_VERSION_OBJECT_API) && !parentObject.equalsIgnoreCase(AIConstants.CONTENT_VERSION_OBJECT_API) && checkContentDocumentLinkObjectValidity(parentObject)){
                    PicklistWrapper pv = new PicklistWrapper();
                    pv.value = AIConstants.CONTENT_VERSION_OBJECT_API;
                    pv.label = AIConstants.CONTENT_VERSION_OBJECT_LABEL + ' ('+AIConstants.CONTENT_VERSION_OBJECT_API+')';
                    pv.firstValue = AIConstants.CONTENT_VERSION_OBJECT_LABEL;
                    alreadySet.add(AIConstants.CONTENT_VERSION_OBJECT_API);
                    lstOfWrapper.add(pv);
                }
                
           		
            }
            
            
            lstOfWrapper.sort();
            return lstOfWrapper;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'getRelatedObjects', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Upserts (updates or inserts) related object mappings based on the provided detail data.
     * This method takes a Map of detail data, where each entry represents a mapping
     * between keys and values.
     *
     * @param detailData A Map<String, String> containing the detail data for related object mappings.
     *                   The keys represent identifiers, and the values represent associated details.
     */
    @AuraEnabled
    public static void upsertRelatedObjectMapping(Map<String, String> detailData){
        try{
            String selectedObject = detailData.get('selectedObject');
            String selectedObjectLabel = detailData.get('selectedObjectLabel');
            String masterId = detailData.get('masterId');
            String parentId = detailData.get('parentId');
            String detailId = detailData.get('detailId');
            String parentObject = detailData.get('parentObject');
            String filterField = detailData.get('filterField');
            String recordLimit = detailData.get('recordLimit');
            String orderBy = detailData.get('orderBy');
            String relationshipField = detailData.get('relationshipField');
            String relationshipName = detailData.get('relationshipName');
            System.debug('upsertRelatedObjectMapping() parentId : '+parentId);
            System.debug('upsertRelatedObjectMapping() detailId : '+detailId);
                           
            
            if(String.isNotBlank(masterId)){
               // Schema.DescribeSObjectResult descObj = schemaMap.get(selectedObject).getDescribe(); 
                //try{     
                    AI_Data_Extraction_Detail__c detail = new AI_Data_Extraction_Detail__c();
                    detail.Where_Clause__c = filterField;
                    detail.Order_By__c = orderBy;
                    detail.Record_Limit__c = String.isNotBlank(recordLimit) ? Integer.valueOf(recordLimit) : null;
                    detail.RelationShipField__c = relationshipField;
                    if(String.isBlank(relationshipName)){
                        relationshipName = selectedObjectLabel;
                    }
                    detail.RelationShipName__c = relationshipName;
                    if(!String.isNotBlank(detailId)){
                        if(String.isNotBlank(parentId)){
                            System.debug('upsertRelatedObjectMapping() parentId : '+parentId);
                            AI_Data_Extraction_Detail__c deObj = [SELECT Id, Running_Index__c FROM AI_Data_Extraction_Detail__c WHERE Id=: parentId LIMIT 1];
                            detail.Running_Index__c = deObj.Running_Index__c == null ? 100 : deObj.Running_Index__c + 100;
                            detail.Parent_Detail__c = parentId;
                        }else{
                            detail.Running_Index__c = 0;
                        }
                        detail.AI_Data_Extraction_Mapping__c = masterId;
                        detail.Object_Name__c = selectedObject;
                        detail.Type__c = String.isNotBlank(parentId) ? 'GRANDCHILD' : 'CHILD';
                        FLSCheck.getInstance().insertDML(new List<AI_Data_Extraction_Detail__c>{detail});
                    }else{
                        detail.Id = detailId;
                        FLSCheck.getInstance().updateDML(new List<AI_Data_Extraction_Detail__c>{detail});
                    }

                    List<AI_Data_Extraction_Field__c> oldMapList = [SELECT Id FROM AI_Data_Extraction_Field__c WHERE AI_Data_Extraction_Mapping__c =:masterId 
                                                                AND Object__c =:selectedObject AND Type__c = 'OBJECT' LIMIT 1];
                    AI_Data_Extraction_Field__c obj = new AI_Data_Extraction_Field__c();
                    obj.Label__c = selectedObjectLabel;
                    if(oldMapList != null && !oldMapList.isEmpty()){
                        obj.Id = oldMapList.get(0).Id;
                        FLSCheck.getInstance().updateDML(new List<AI_Data_Extraction_Field__c>{obj});
                    }else{
                        obj.AI_Data_Extraction_Mapping__c = masterId;
                        obj.Object__c = selectedObject;
                        obj.Field__c = selectedObject;
                        obj.Type__c = 'OBJECT';
                        FLSCheck.getInstance().insertDML(new List<AI_Data_Extraction_Field__c>{obj});
                    }
                //}catch(Exception e){
                //  throw new AuraHandledException(e.getMessage());
                //}
            }
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'upsertRelatedObjectMapping', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves a list of SObjects represented as PicklistWrapper instances.
     *
     * This method is responsible for fetching SObjects and converting them into
     * PicklistWrapper objects, providing a convenient representation for further processing.
     *
     * @return A List of PicklistWrapper instances representing the retrieved SObjects.
     */
    @AuraEnabled
    public static List<PicklistWrapper> getSObjects(){
        try{
            List<PicklistWrapper> objects = new List<PicklistWrapper>();
            for(Schema.SObjectType o : Schema.getGlobalDescribe().values()){
                Schema.DescribeSObjectResult objResult = o.getDescribe();
                if(objResult.isUpdateable() && objResult.isAccessible()){
                    PicklistWrapper wrap = new PicklistWrapper();
                    wrap.label = objResult.getLabel()+' ('+objResult.getName()+')';
                    wrap.value = objResult.getName();
                    wrap.firstValue = objResult.getLabel();
                    objects.add(wrap);
                }
            }
            objects.sort();
            return objects;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'getSObjects', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves a list of PicklistWrapper objects representing target fields
     * based on the specified parentObject and selectedObject.
     *
     * @param parentObject    The parent object for which target fields are requested.
     * @param selectedObject  The selected object that determines the target fields.
     * @return                A List of PicklistWrapper objects containing details
     *                        about the target fields.
     */
    @AuraEnabled
    public static List<PicklistWrapper> getTargetFields(String parentObject, String selectedObject,Map<String, DataCloudWrapper> dataCloudObjectMap,Boolean isFromRelatedObjLwc){

        GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
        try{
            List<PicklistWrapper> options = new List<PicklistWrapper>();
            List<Object> relationshipList = new List<Object>();

            if(parentObject != '' && parentObject.contains('__dlm') && selectedObject != '' && selectedObject.contains('__dlm')){

                if(isFromRelatedObjLwc){
                    Map<String,Object> metadata = getDMOObjectFromDataCloud(gptfySetting,parentObject);
                	relationshipList = (List<Object>) metadata.get('relationships');
                }else{
                    relationshipList = (List<Object>) dataCloudObjectMap.get(parentObject).relationshipFields;
                }

                System.debug('relationshipList : '+relationshipList);
                for (Object obj : relationshipList) {
                        Map<String, Object> objMap = (Map<String, Object>) obj;
                        String objName = (String) objMap.get('fromEntity');

                        if(objName == selectedObject){
                            System.debug('objName : '+objName);
                            String objectApiName = (String) objMap.get('fromEntityAttribute');
                            String objectDisplayName = (String) objMap.get('fromEntityAttribute');
                            PicklistWrapper wrap = new PicklistWrapper();
                            wrap.label = objectDisplayName;
                            wrap.value = objectApiName;
                            wrap.firstValue = objName;
                            options.add(wrap);
                        }
                }
                
            }else if(parentObject != '' && !parentObject.contains('__dlm') && selectedObject != '' && selectedObject.contains('__dlm')){

                    if(isFromRelatedObjLwc){
                        Map<String,Object> metadata = getDMOObjectFromDataCloud(gptfySetting,selectedObject);
                        List<Object> primaryList = (List<Object>) metadata.get('primaryKeys');
                        for (Object metadataItem : primaryList) {
                            Map<String, Object> metadataMap = (Map<String, Object>) metadataItem;
                            String objectApiName = (String) metadataMap.get('name');
                            String objectDisplayName = (String) metadataMap.get('displayName');
                            PicklistWrapper wrap = new PicklistWrapper();
                            wrap.label = objectApiName;
                            wrap.value = objectApiName;
                            wrap.firstValue = selectedObject;
                            options.add(wrap);
                        }
                    }else{
                        if(dataCloudObjectMap != NULL && !dataCloudObjectMap.isEmpty()){
                            DataCloudWrapper dcWrap = dataCloudObjectMap.get(selectedObject);
                            for (Object metadataItem : dcWrap.primaryFields) {
                                Map<String, Object> metadataMap = (Map<String, Object>) metadataItem;
                                String objectApiName = (String) metadataMap.get('name');
                                String objectDisplayName = (String) metadataMap.get('displayName');
                                PicklistWrapper wrap = new PicklistWrapper();
                                wrap.label = objectDisplayName;
                                wrap.value = objectApiName;
                                wrap.firstValue = selectedObject;
                                options.add(wrap);
                            }
                        }
                    }
                
                    Schema.DescribeSObjectResult describeObj = Schema.getGlobalDescribe().get(parentObject).getDescribe();
                    for (Schema.ChildRelationship cr: describeObj.getChildRelationships()) {
                        if(String.valueOf(cr.getChildSObject()) == selectedObject){
                            PicklistWrapper wrap = new PicklistWrapper();
                            wrap.label = String.valueOf(cr.getField());
                            wrap.value = String.valueOf(cr.getField());
                            wrap.firstValue = String.valueOf(cr.getRelationshipName());
                            options.add(wrap);
                        }
                    }
            }else{
                // salesforce object
                Schema.DescribeSObjectResult describeObj = Schema.getGlobalDescribe().get(parentObject).getDescribe();
                for (Schema.ChildRelationship cr: describeObj.getChildRelationships()) {
                    if(String.valueOf(cr.getChildSObject()) == selectedObject){
                        PicklistWrapper wrap = new PicklistWrapper();
                        wrap.label = String.valueOf(cr.getField());
                        wrap.value = String.valueOf(cr.getField());
                        wrap.firstValue = String.valueOf(cr.getRelationshipName());
                        options.add(wrap);
                    }
                }
            }
            return options;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionController', 'getTargetFields', '');
            throw new AuraHandledException(e.getMessage());
        } 
    }
    
    public static Boolean checkContentDocumentLinkObjectValidity(String objectName){
        Boolean isValid = false;
        Schema.SObjectField field = schemaMap.get(AIConstants.CDL_OBJECT_API).getDescribe().fields.getMap().get(AIConstants.CDL_LINKED_ENTITY_FIELD_API);
        Schema.DescribeFieldResult fieldResult = field.getDescribe();
        if (fieldResult.isNamePointing() && fieldResult.getReferenceTo() != null) {
            for (Schema.SObjectType objectType : fieldResult.getReferenceTo()) {
                String oName = String.valueOf(objectType);
                if(oName.equalsIgnoreCase(objectName)){
                    isValid = true;
                    break;
                }
            }
        }
        return isValid;
    }
    
    
    @AuraEnabled
    public static Map<String,DataCloudWrapper> getObjectsWithFieldCountFromDataCloud(){
        Map<String,DataCloudWrapper> dcObjects = new Map<String,DataCloudWrapper>();
        GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
        if(gptfySetting.Enable_for_Data_Cloud__c){
            try{
                List<object> metadataList = AIDataCloudService.fetchDataModelObjectsList(gptfySetting);
                for (Object metadataItem : metadataList) {
                        Map<String, Object> metadataMap = (Map<String, Object>) metadataItem;
                        String objectApiName = (String) metadataMap.get('name');
                        String objectDisplayName = (String) metadataMap.get('displayName');
                        List<Object> fields = (List<Object>) metadataMap.get('fields');
                    	List<Object> primaryfieldsList = (List<Object>) metadataMap.get('primaryKeys');
                    	List<Object> relationshipList = (List<Object>) metadataMap.get('relationships');
                    	DataCloudWrapper dcwrap = new DataCloudWrapper();
                        dcwrap.label = objectDisplayName;
                        dcwrap.apiName = objectApiName;
                        dcwrap.fieldCount = fields.size();
                        dcwrap.primaryFields = primaryfieldsList;
                        dcwrap.relationshipFields = relationshipList;
                        dcObjects.put(objectApiName,dcwrap);
                }
                
            }catch(Exception e){
                return dcObjects;
            }
        }
         return dcObjects;
        
    }
    
    /**
     * Retrieves a list of SObjects represented as PicklistWrapper instances.
     *
     * This method is responsible for fetching SObjects and converting them into
     * PicklistWrapper objects, providing a convenient representation for further processing.
     *
     * @return A List of PicklistWrapper instances representing the retrieved SObjects.
     */
    @AuraEnabled
    public static List<PicklistWrapper> getSObjectsFromDataCloud(GPTfy_Settings__c gptfySetting){
        	List<PicklistWrapper> objects = new List<PicklistWrapper>();
            List<object> metadataList = AIDataCloudService.fetchDataModelObjectsList(gptfySetting);
            for (Object metadataItem : metadataList) {
                Map<String, Object> metadataMap = (Map<String, Object>) metadataItem;
                
                String objectApiName = (String) metadataMap.get('name');
                String objectDisplayName = (String) metadataMap.get('displayName');
                PicklistWrapper wrap = new PicklistWrapper();
                wrap.label = objectDisplayName+' ('+objectApiName+')';
                wrap.value = objectApiName;
                wrap.firstValue = objectDisplayName;
                objects.add(wrap);
            }
            objects.sort();
            return objects;
    }
    
    /**
     * Retrieves a list of SObjects represented as PicklistWrapper instances.
     *
     * This method is responsible for fetching SObjects and converting them into
     * PicklistWrapper objects, providing a convenient representation for further processing.
     *
     * @return A List of PicklistWrapper instances representing the retrieved SObjects.
     */
    @AuraEnabled
    public static Map<String, Object> getDMOObjectFromDataCloud(GPTfy_Settings__c gptfySetting,String dmoApiName){
        Map<String, Object> metadataMap = new Map<String, Object>();
            List<PicklistWrapper> objects = new List<PicklistWrapper>();
            List<object> metadataList = AIDataCloudService.fetchDataCloudFieldList(gptfySetting,dmoApiName);
            if(!metadataList.isEmpty()){
                metadataMap = (Map<String, Object>) metadataList[0];
            }
         return metadataMap;
    }
    
    
    public class DataCloudWrapper{
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public Integer fieldCount{get;set;}
        @AuraEnabled public String apiName{get;set;}
        @AuraEnabled public List<Object> primaryFields{get;set;}
        @AuraEnabled public List<Object> relationshipFields{get;set;}
    }
    
    public class DataWrapper{
        @AuraEnabled public Boolean hasError{get;set;}
        @AuraEnabled public List<String> detailIds{get;set;}
        @AuraEnabled public List<HierarchyWrapper> details{get;set;}
        @AuraEnabled public Map<String, HierarchyWrapper> detailMap{get;set;}
        @AuraEnabled public Map<String, DataCloudWrapper> dataCloudMap{get;set;}
    }
    
    public class HierarchyWrapper {
        @AuraEnabled public String detailId{get;set;}
        @AuraEnabled public Integer runningIndex{get;set;}
        @AuraEnabled public String parentId{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String objectLabel{get;set;}
        @AuraEnabled public String objLabel{get;set;}
        @AuraEnabled public String filterField{get;set;}
        @AuraEnabled public String fieldsCount{get;set;}
        @AuraEnabled public String orderBy{get;set;}
        @AuraEnabled public Integer recordLimit{get;set;}
        @AuraEnabled public String relationshipField{get;set;}
        @AuraEnabled public List<PicklistWrapper> relationshipOptions{get;set;}
        @AuraEnabled public List<HierarchyWrapper> children{get;set;}
    }
    
    public class MasterWrapper{
        @AuraEnabled public String mappingName{get;set;}
        @AuraEnabled public List<PicklistWrapper> objects{get;set;}
        @AuraEnabled public List<PicklistWrapper> dataSourceOptions{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String objectLabel{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String aiDataSource{get;set;}
        @AuraEnabled public List<PicklistWrapper> apexSecurityLayerOptions{get;set;}
        @AuraEnabled public String apexSecurityLayer{get;set;}
    }
    
    public class PicklistWrapper implements Comparable{
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public String firstValue{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String fieldType{get;set;}
        
        public Integer compareTo(Object objToCompare) {
        	return label.compareTo(((PicklistWrapper)objToCompare).label);
        }
    }
    
}