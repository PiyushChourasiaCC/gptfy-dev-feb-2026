/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIDataExtractionService {
    
    public static Map<String, Schema.SObjectType> schemaMap;
    public static Boolean isResponsesApi;
    static {
        schemaMap = Schema.getGlobalDescribe();
    }
    
    public STATIC String RT_REGEX = (String)Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Regex').getRecordTypeId();
    public STATIC String RT_BLOCKLIST = (String)Schema.SObjectType.AI_Security_Filters__c.getRecordTypeInfosByName().get('Blocklist').getRecordTypeId();
    		
    /**
     * Extracts relevant data based on the provided record ID, AI prompt, map of file references, and existing AI response object.
     * 
     * @param recordId The ID of the record associated with the data extraction process.
     * @param aiPrompt The AI prompt object containing information relevant to the data extraction.
     * @param mapOfFiles A map where the keys represent file names, and the values contain lists of file paths associated with the data extraction.
     * @param resp The existing AI response object used for the data extraction.
     * @return DataPIIWrapper The DataPIIWrapper is store the AI response record updated with the extracted data and mapOfPIIKeyToMatchCompleteWord.
     */
    public static DataPIIWrapper extractData(Id recordId, AI_Prompt__c aiPrompt, Map<String, List<String>> mapOfFiles, AI_Response__c resp){
        try{
            isResponsesApi = (aiPrompt.Include_Files__c == true && AIConstants.RESPONSES_API_MODEL.contains(aiPrompt.AI_Model_File_Processing__r.Model__c)) ? true : false;
            AI_Data_Extraction_Mapping__c extractionMapping = AIDataExtractionSelector.getAIDataExtractionMappingById(aiPrompt.AI_Data_Extraction_Mapping__c);
        
            List<AI_Security_Filters__c> filters = AIDataExtractionSelector.getAISecurityFilters();
            List<AI_Data_Extraction_Detail__c> extractionDetails = AIDataExtractionSelector.getAIDataExtractionDetailByMappingId(extractionMapping.Id);
            List<AI_Data_Extraction_Field__c> extractionFields = AIDataExtractionSelector.getAIDataExtractionFieldsByMappingId(extractionMapping.Id);
            
            Map<String,List<AI_Data_Extraction_Field__c>> extractionFieldsMap = new  Map<String,List<AI_Data_Extraction_Field__c>>();
            Map<String, Set<String>> mapOfObjectNameToAddtionalQueryFields = new Map<String, Set<String>>();
            for(AI_Data_Extraction_Field__c extractionField: extractionFields){
                if(extractionFieldsMap.containsKey(extractionField.Object__c)){
                    extractionFieldsMap.get(extractionField.Object__c).add(extractionField);
                }else{
                    extractionFieldsMap.put(extractionField.Object__c, new List<AI_Data_Extraction_Field__c>{extractionField});
                }
                if(String.isNotBlank(extractionField.Formula__c)){
                    if(!mapOfObjectNameToAddtionalQueryFields.containsKey(extractionField.Object__c)){
                        mapOfObjectNameToAddtionalQueryFields.put(extractionField.Object__c, new Set<String>());
                    }
                    Schema.SObjectType objType = schemaMap.get(extractionField.Object__c);
                    FormulaEval.FormulaInstance ff = Formula.builder()
                        .withType(objType)
                        .withReturnType(FormulaEval.FormulaReturnType.valueOf(extractionField.Field_Type__c))
                        .withFormula(extractionField.Formula__c)
                        .build();
                    Set<String> formulaRefercedFields = ff.getReferencedFields();
                    if(formulaRefercedFields != null && !formulaRefercedFields.isEmpty()){
                        // Jira v2/7550 : Issues/Feedbacks Reported in 1.13
                        Map<String, Schema.SObjectField> fieldsMap = objType.getDescribe().fields.getMap();
                        // Validate that all referenced fields exist and are accessible
                        List<String> inaccessibleFields = new List<String>();
                        List<String> nonExistentFields = new List<String>();
                        
                        for(String fieldName : formulaRefercedFields){
                            Schema.SObjectField field = fieldsMap.get(fieldName);
            
                            if(field == null){
                                nonExistentFields.add(fieldName);
                            }else{
                                Schema.DescribeFieldResult dfr = field.getDescribe();
                                if(!dfr.isAccessible()){
                                    inaccessibleFields.add(fieldName);
                                }
                            }
                        }
                        
                        // Throw error if there are invalid fields
                        if (!nonExistentFields.isEmpty()) {
                            String errorMsg = 'The following fields do not exist on ' +
                                extractionField.Object__c + ': ' +
                                String.join(nonExistentFields, ', ') +
                                ' in the formula.';
                            throw AIUtility.getMessageAuraHandledException(errorMsg);
                        }
                        
                        if (!inaccessibleFields.isEmpty()) {
                            String errorMsg = 'You do not have access to the following fields on ' +
                                extractionField.Object__c + ': ' +
                                String.join(inaccessibleFields, ', ') +
                                ' used in the formula.';
                            throw AIUtility.getMessageAuraHandledException(errorMsg);
                        }
                        
                        mapOfObjectNameToAddtionalQueryFields.get(extractionField.Object__c).addAll(formulaRefercedFields);
                    }
                }
            }
        
            Map<String,String> pIIKey = new Map<String,String>();
            Map<String,Boolean> mapOfPIIKeyToMatchCompleteWord = new Map<String,Boolean>();
            List<AI_Data_Extraction_Field__c> parentExtractionFields = extractionFieldsMap.get(extractionMapping.Object_Name__c);
            Map<String, Schema.SObjectField> parentFieldMap;
            if(schemaMap.containsKey(extractionMapping.Object_Name__c)){
                parentFieldMap = schemaMap.get(extractionMapping.Object_Name__c).getDescribe().fields.getMap();
            }
            
            Set<String> setOfParentFieldApis = queryFields(parentExtractionFields, parentFieldMap);
            String currencyISOCode = UserInfo.getDefaultCurrency();
            if(UserInfo.isMultiCurrencyOrganization() && parentFieldMap.containsKey('CurrencyIsoCode')){
                if(!setOfParentFieldApis.contains('CurrencyIsoCode')){
                    setOfParentFieldApis.add('CurrencyIsoCode');
                }
            }
            Set<String> setOfCaseInsensitiveParentFieldApis = new Set<String>();
            for(String fName : setOfParentFieldApis){
                setOfCaseInsensitiveParentFieldApis.add(fName.toLowerCase());
            }
        	if(mapOfObjectNameToAddtionalQueryFields != null && mapOfObjectNameToAddtionalQueryFields.containsKey(extractionMapping.Object_Name__c)){
                for(String fName : mapOfObjectNameToAddtionalQueryFields.get(extractionMapping.Object_Name__c)){
                    if(!setOfCaseInsensitiveParentFieldApis.contains(fName.toLowerCase())){
                        setOfParentFieldApis.add(fName);
                        setOfCaseInsensitiveParentFieldApis.add(fName.toLowerCase());
                    }
                }
            }
            String query = 'SELECT '+String.join(new List<String>(setOfParentFieldApis), ',')+' FROM '+extractionMapping.Object_Name__c+' WHERE Id=:recordId WITH SECURITY_ENFORCED LIMIT 1';  
        	//System.debug('recordId: '+recordId);
            //System.debug(query);    
            Sobject parentSobject = Database.query(query);
            if(UserInfo.isMultiCurrencyOrganization() && parentFieldMap.containsKey('CurrencyIsoCode')){
                if(parentSobject.get('CurrencyIsoCode') != NULL){
                    currencyISOCode = String.valueOf(parentSobject.get('CurrencyIsoCode'));
                }
            }
            Map<String, Object> parentData = new Map<String, Object>();
            
            GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
        	String nullValue = gptfySetting.Blank_Replacement_Value__c != null ? gptfySetting.Blank_Replacement_Value__c : null;
            
            Integer i = 1;
        	if(parentExtractionFields != NULL){
            	for(AI_Data_Extraction_Field__c extractionField  : parentExtractionFields){
                //if(setOfParentFieldApis.contains(extractionField.Field__c)){
                    
                    String fValue = getFieldValue(extractionField, parentSobject, extractionMapping.Object_Name__c);
                    fValue = String.isNotBlank(fValue) ? fValue.trim() : fValue;
                    if(extractionField.Send_To_AI__c){
                        if(String.isNotBlank(fValue)){
                            // @Jira: 4752 : Percentage and Currency Field is extracted as number 
                            if(extractionField.Field_Type__c == 'PERCENT'){
                                parentData.put(extractionField.Field__c, fValue+'%');
                            }else if(extractionField.Field_Type__c == 'CURRENCY'){
                                parentData.put(extractionField.Field__c, currencyISOCode+' '+fValue);
                            }else{
                                parentData.put(extractionField.Field__c, fValue);
                            }
                        }else if(String.isNotBlank(nullValue)){
                            String val = nullValue.equalsIgnoreCase('NULL') ? null : nullValue;
                            parentData.put(extractionField.Field__c, val);
                        } 
                    }
                    if(String.isNotBlank(fValue) && String.isNotBlank(extractionField.Masking_Scope__c) ){
                        // Jira 5988: Security Layer 1 and 2 is conflict
                        if(!pIIKey.containsKey(fValue)){
                            if(extractionField.Masking_Scope__c == 'Entire Value' && String.isNotBlank(extractionField.Anonymize_With__c)){
                                pIIKey.put(fValue, checkEntireValueUniqeReplacement(pIIKey.values(), i, extractionField.Anonymize_With__c));
                            }else if(extractionField.Masking_Scope__c == 'Specific Patterns'){
                                // @Jira : 4802 : Add mapOfPIIKeyToMatchCompleteWord param for identify MatchCompleteWord is true or false.
                                applyFilters(filters, fValue, pIIKey,mapOfPIIKeyToMatchCompleteWord);
                            }
                        }
                        i++;
                    }
                //}
                }
            }
            parentData.put('Object Name', extractionMapping.Object_Name__c);
            if(mapOfFiles != null && mapOfFiles.containsKey(recordId)){
                parentData.put('files', mapOfFiles.get(recordId));
            }
            
            Map<String, Object> dataMap = new Map<String, Object>();
            dataMap.putAll(parentData);
            
            Map<String, List<String>> mapOfExIdToRecordIdsForChild = new Map<String, List<String>>();
            Map<String, List<String>> mapOfExIdToDCRecordIdsForChild = new Map<String, List<String>>();
            
            Map<String, List<String>> mapOfParentIdToRelationshipNames = new Map<String, List<String>>();
            Map<String, List<Map<String, Object>>> mapOfKeyToChildRecords = new Map<String, List<Map<String, Object>>>();
            
            Map<String, Map<String, Object>> mapOfIdToData = new Map<String, Map<String, Object>>();
            Map<String, String> mapOfRecIdToRelationShipName = new Map<String, String>();
            
            for(AI_Data_Extraction_Detail__c extractionDetail : extractionDetails){
                
                List<Object> dataList = new List<Object>();
				Set<String> dcPrimaryFields = new Set<String>();
                if(extractionFieldsMap.containsKey(extractionDetail.Object_Name__c)){
                    List<AI_Data_Extraction_Field__c> detailExtractionFields = extractionFieldsMap.get(extractionDetail.Object_Name__c);
                    
                    Schema.DescribeSObjectResult objResult;
                    if(schemaMap.containsKey(extractionDetail.Object_Name__c)){
                        objResult = schemaMap.get(extractionDetail.Object_Name__c).getDescribe();
                    }

                    Map<String, Schema.SObjectField> fieldMap;
                    if(objResult != null){
                        fieldMap = objResult.fields.getMap();
                    }
                    
                    try{
                        if(gptfySetting.Enable_for_Data_Cloud__c && extractionDetail.Object_Name__c.endsWithIgnoreCase('__dlm')){
                            Map<String, Object> metadataList = AIDataExtractionController.getDMOObjectFromDataCloud(gptfySetting,extractionDetail.Object_Name__c);
                            List<Object> primaryList = (List<Object>) metadataList.get('primaryKeys');
                            for (Object metadataItem : primaryList) {
                                Map<String, Object> metadataMap = (Map<String, Object>) metadataItem;
                                String fieldApiName = (String) metadataMap.get('name');
                                dcPrimaryFields.add(fieldApiName);
                            }
                    	}
                    }catch(Exception e){
                        
                    }
                    
                    
                    Set<String> setOfFieldApis = queryFields(detailExtractionFields, fieldMap);
                    
                    if(!dcPrimaryFields.isEmpty()){
                        setOfFieldApis.addAll(dcPrimaryFields);
                    }
                    //adding relationship field to the queryfields as well
                    if(!setOfFieldApis.contains(extractionDetail.RelationshipField__c)){
                        setOfFieldApis.add(extractionDetail.RelationshipField__c);
                    }
                    
                    // @Jira: 5038: External Object Extraction issue at 3rd Level
                    if(extractionDetail.Parent_Detail__c != null && String.isNotBlank(extractionDetail.Object_Name__c) && extractionDetail.Object_Name__c.endsWithIgnoreCase('__x') && String.isNotBlank(extractionDetail.Parent_Detail__r.Object_Name__c) && extractionDetail.Parent_Detail__r.Object_Name__c.endsWithIgnoreCase('__x')){
                        if(extractionDetail.RelationshipField__c.endsWithIgnoreCase('__c')){
                            setOfFieldApis.add(extractionDetail.RelationshipField__c.removeEndIgnoreCase('__c')+'__r.Id');
                        }
                    }
                    
                    Set<String> setOfCaseInsensitiveFieldApis = new Set<String>();
                    for(String fName : setOfParentFieldApis){
                        setOfCaseInsensitiveFieldApis.add(fName.toLowerCase());
                    }
                    if(mapOfObjectNameToAddtionalQueryFields != null && mapOfObjectNameToAddtionalQueryFields.containsKey(extractionDetail.Object_Name__c)){
                        for(String fName : mapOfObjectNameToAddtionalQueryFields.get(extractionDetail.Object_Name__c)){
                            if(!setOfCaseInsensitiveFieldApis.contains(fName.toLowerCase())){
                                setOfFieldApis.add(fName);
                                setOfCaseInsensitiveFieldApis.add(fName.toLowerCase());
                            }
                		}
                    }
                    
                    // @Jira 4487 : Data Context Mapping with Data Cloud Integration
                    List<SObject> sobjs = new List<SObject>();
                    if(extractionDetail.Type__c == 'GRANDCHILD' && extractionDetail.Parent_Detail__c != null && String.isNotBlank(extractionDetail.Object_Name__c) && 
                           		extractionDetail.Object_Name__c.endsWithIgnoreCase('__dlm') && String.isNotBlank(extractionDetail.Parent_Detail__r.Object_Name__c) 
                       				//&& !extractionDetail.Parent_Detail__r.Object_Name__c.endsWithIgnoreCase('__dlm')  
                      ){
                           List<String> dcRecordIds = mapOfExIdToDCRecordIdsForChild.get(extractionDetail.Parent_Detail__c);
                           sobjs = queryRecordsForChildQueryable(recordId, extractionDetail, String.join(new List<String>(setOfFieldApis), ','),dcRecordIds);
                    }else{
                        sobjs = queryRecordsForChildQueryable(recordId, extractionDetail, String.join(new List<String>(setOfFieldApis), ','),null);
                    }
                    
                    for(Sobject sobj : sobjs){
                        Map<String, Object> data = new Map<String, Object>();
                        for(AI_Data_Extraction_Field__c extractionField  : detailExtractionFields){
                            //if(setOfFieldApis.contains(extractionField.Field__c)){
                                String fValue = getFieldValue(extractionField, sobj, extractionDetail.Object_Name__c);
                                fValue = String.isNotBlank(fValue) ? fValue.trim() : fValue;
                                if(extractionField.Send_To_AI__c){
                                    if(String.isNotBlank(fValue)){
                                        data.put(extractionField.Field__c, fValue);
                                    }else if(String.isNotBlank(nullValue)){
                                        String val = nullValue.equalsIgnoreCase('NULL') ? null : nullValue;
                                        data.put(extractionField.Field__c, val);
                                    }
                                }if(String.isNotBlank(extractionField.Masking_Scope__c) && String.isNotBlank(fValue)){
                                    // Jira 5988: Security Layer 1 and 2 is conflict
                        			if(!pIIKey.containsKey(fValue)){
                                        if(extractionField.Masking_Scope__c == 'Entire Value' && String.isNotBlank(extractionField.Anonymize_With__c)){
                                            pIIKey.put(fValue, checkEntireValueUniqeReplacement(pIIKey.values(), i, extractionField.Anonymize_With__c));
                                        }else if(extractionField.Masking_Scope__c == 'Specific Patterns'){
                                            // @Jira : 4802 : Add mapOfPIIKeyToMatchCompleteWord param for identify MatchCompleteWord is true or false.
                                            applyFilters(filters, fValue, pIIKey, mapOfPIIKeyToMatchCompleteWord);
                                        }
                                    }
                                    i++;
                                }
                            //}
                        }
                        
                        String recId = String.valueOf(sobj.get('Id'));
                        if(mapOfFiles != null && mapOfFiles.containsKey(recId)){
                            data.put('files', mapOfFiles.get(recId));
                        }
                        mapOfIdToData.put(recId, data);
                        
                        if(!mapOfRecIdToRelationShipName.containsKey(recId)){
                            mapOfRecIdToRelationShipName.put(recId, extractionDetail.RelationshipName__c);
                        }
                        
                        // @Jira: 5038: External Object Extraction issue at 3rd Level
                        String parentId = String.valueOf(sobj.get(extractionDetail.RelationshipField__c));
                        if(extractionDetail.Parent_Detail__c != null && String.isNotBlank(extractionDetail.Object_Name__c) && 
                           		extractionDetail.Object_Name__c.endsWithIgnoreCase('__x') && String.isNotBlank(extractionDetail.Parent_Detail__r.Object_Name__c) && 
                           		extractionDetail.Parent_Detail__r.Object_Name__c.endsWithIgnoreCase('__x')){
                                    if(extractionDetail.RelationshipField__c.endsWithIgnoreCase('__c') && sobj.get(extractionDetail.RelationshipField__c) != null && sobj.getSObject(extractionDetail.RelationshipField__c.removeEndIgnoreCase('__c')+'__r') != null){
                                        parentId = String.valueOf(sobj.getSObject(extractionDetail.RelationshipField__c.removeEndIgnoreCase('__c')+'__r').get('Id'));
                                    }
                        }
                        
                        // @Jira 4487 : Data Context Mapping with Data Cloud Integration
						//System.debug('extractionDetail: '+extractionDetail);
                        //System.debug('sobj: '+sobj);
                        if(extractionDetail.Parent_Detail__c != null && String.isNotBlank(extractionDetail.Object_Name__c) && 
                           		extractionDetail.Object_Name__c.endsWithIgnoreCase('__dlm') && String.isNotBlank(extractionDetail.Parent_Detail__r.Object_Name__c) && 
                           		extractionDetail.Parent_Detail__r.Object_Name__c.endsWithIgnoreCase('__dlm')  ){
                                    if(mapOfExIdToRecordIdsForChild.containsKey(extractionDetail.Parent_Detail__c)){
                                        List<String> parentDetail = mapOfExIdToRecordIdsForChild.get(extractionDetail.Parent_Detail__c);
                                        if(parentDetail != null && !parentDetail.isEmpty()){
                                           // System.debug('parentId assigned with '+parentDetail);
                                            parentId = parentDetail[0];
                                        }
                                        
                                    }
                        } 

                        
                        if(!mapOfParentIdToRelationshipNames.containsKey(parentId)){
                            mapOfParentIdToRelationshipNames.put(parentId, new List<String>());
                        }
                        mapOfParentIdToRelationshipNames.get(parentId).add(extractionDetail.RelationshipName__c);
                        
                        String key = parentId +'~'+ extractionDetail.RelationshipName__c;
                        if(!mapOfKeyToChildRecords.containsKey(key)){
                            mapOfKeyToChildRecords.put(key, new List<Map<String, Object>>());
                        }
                        mapOfKeyToChildRecords.get(key).add(data);
                        if(extractionDetail.Parent_Detail__c == null){
                            if(!mapOfExIdToRecordIdsForChild.containsKey(extractionDetail.Id)){
                                mapOfExIdToRecordIdsForChild.put(extractionDetail.Id, new List<String>());
                            }
                            mapOfExIdToRecordIdsForChild.get(extractionDetail.Id).add(recId);
                            
                                if(!mapOfExIdToDCRecordIdsForChild.containsKey(extractionDetail.Id)){
                                    mapOfExIdToDCRecordIdsForChild.put(extractionDetail.Id, new List<String>());
                                }
                                mapOfExIdToDCRecordIdsForChild.get(extractionDetail.Id).add(recId);
                                if(extractionDetail.Object_Name__c.endsWithIgnoreCase('__dlm')  && !dcPrimaryFields.isEmpty() ){
                                    for(String dcField : dcPrimaryFields){
                                        mapOfExIdToDCRecordIdsForChild.get(extractionDetail.Id).add(String.valueOf(sobj.get(dcField)));
                                    }
                                }
                                
                            
                            
                        }
                    }
                }

            }

            Map<String, AI_Data_Extraction_Detail__c> mapOfExtractionDetails = new Map<String, AI_Data_Extraction_Detail__c>(extractionDetails);
            
            for(String extId : mapOfExIdToRecordIdsForChild.keySet()){
                AI_Data_Extraction_Detail__c detail = mapOfExtractionDetails.get(extId);
                List<Object> dataList = new List<Object>();
                for(String recId : mapOfExIdToRecordIdsForChild.get(extId)){
                    Map<String, Object> data = new Map<String, Object>();
                    data.putAll(mapOfIdToData.get(recId));
                    if(data != null && mapOfParentIdToRelationshipNames.containsKey(recId)){
                        for(String relationShipName : mapOfParentIdToRelationshipNames.get(recId)){
                            String key = recId +'~'+ relationShipName;
                            if(mapOfKeyToChildRecords != null && mapOfKeyToChildRecords.containsKey(key)){
                                data.put(relationShipName, (Object)mapOfKeyToChildRecords.get(key));
                            }
                        }
                    }
                    dataList.add(data);
                }
                parentData.put(detail.RelationshipName__c, dataList);
            }
            resp.Data_Original__c = JSON.serializePretty(parentData, true);
            resp.Data_PII_Key__c = JSON.serializePretty(pIIKey);
            
            // @Jira : 4802 : Add DataPIIWrapper with response and mapOfPIIKeyToMatchCompleteWord.
            return new DataPIIWrapper(resp,mapOfPIIKeyToMatchCompleteWord);
        }catch(Exception e){
            //System.debug(e.getStackTraceString());
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionService', 'extractData', '');
            throw new ChatGPTUtills.ApplicationException(e.getMessage());
        } 
    }
    
    /**
     * Queries and retrieves a set of field names based on the provided list of AI data extraction fields and the map of SObject fields.
     * 
     * @param extractionFields A list of AI data extraction fields containing the necessary information for querying fields.
     * @param fieldMap A map where the keys represent field names, and the values contain the corresponding SObject fields for the query.
     * @return Set<String> A set of field names retrieved based on the AI data extraction fields and the SObject fields for further processing or analysis.
     */
    public static Set<String> queryFields(List<AI_Data_Extraction_Field__c> extractionFields, Map<String, Schema.SObjectField> fieldMap){
        set<String> setOfFields = new set<String>();
        setOfFields.add('Id');
        if(extractionFields != NULL){
           for(AI_Data_Extraction_Field__c extractionField :extractionFields){
            if(extractionField.Type__c == 'FIELD' && extractionField.Field__c !='Id'){
                if(String.isBlank(extractionField.Formula__c)){
                    //Jira 7221:  Issues/Feedbacks from 1.12 Testing
                    setOfFields.add(extractionField.Field__c);
                    //if(extractionField.Object__c.endsWithIgnoreCase('__dlm') || extractionField.Field__c.contains('.') /*|| fieldMap.get(extractionField.Field__c).getDescribe().isAccessible())*/){
                        //setOfFields.add(extractionField.Field__c);
                    //}
                } 
            }
          } 
        }
        
        return setOfFields;
    }
	
    /**
     * Anonymizes the data within the provided AI response object to protect sensitive information and maintain data privacy.
     * 
     * @param resp The AI response object containing data to be anonymized.
     * @param mapPIIKeyIsMatchWord The mapPIIKeyIsMatchWord map containing data of security layer matchCompleteWord.
     * @return AI_Response__c The AI response record with anonymized data, ensuring the protection of sensitive information.
     */
    public static AI_Response__c anonymizeData(AI_Response__c resp,Map<String,Boolean> mapPIIKeyIsMatchWord){
        try{
            String PIIData = resp.Data_Original__c;
            Map<String, String> pIIKey = (Map<String, String>)JSON.deserialize(resp.Data_PII_Key__c, Map<String, String>.class);
            Map<String, String> decryptPIIKey = new Map<String, String>();
            List<String> keys = new List<String>(pIIKey.keySet());
            List<SFKeyWrapper> keyWrapperList = new List<SFKeyWrapper>();
            if(keys != null && keys.size() > 0){
                for (Integer i = keys.size() - 1; i >= 0; i--) {
                   SFKeyWrapper w = new SFKeyWrapper(keys[i]);
                   keyWrapperList.add(w);
                }
            }
            keyWrapperList.sort();
            for(SFKeyWrapper w : keyWrapperList){
                if(String.isNotBlank(PIIData) && PIIData.indexOf(w.keyName) >= 0){
                   // @Jira 4786: Blocklist is failing to mask some of the upper/lowercase variations
                    // @Jira : 4802 : create spattern based on mapOfPIIKeyToMatchCompleteWord
                   String spattern = Pattern.quote(w.keyName);
                   // @Jira : 5987 : Match Complete word is failing
                   /*if(!mapPIIKeyIsMatchWord.isEmpty() && mapPIIKeyIsMatchWord.containsKey(w.KeyName) && mapPIIKeyIsMatchWord.get(w.KeyName)){
                      // spattern = '(?<=\\s)?('+Pattern.quote(w.keyName)+')(?=\\s)';
                       spattern = Pattern.quote(w.keyName);
                   }else{
                       spattern = Pattern.quote(w.keyName);
                   }*/                     
                   Pattern p = Pattern.compile(spattern);
                    Matcher matcher = p.matcher(PIIData);
                    if (matcher.find()) {
                        PIIData = matcher.replaceAll(pIIKey.get(w.keyName));
                    }
                }
                decryptPIIKey.put(pIIKey.get(w.keyName), w.keyName);
            }
            resp.Data_Decrypt_PII_Key__c = JSON.serializePretty(decryptPIIKey);
            resp.Data_PII_Removed__c = PIIData;
            return resp;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionService', 'anonymizeData', '');
            return null;
        }
    }
	
    /**
     * De-anonymizes the data within the provided AI response object using the corresponding GPT response to retrieve the original information.
     * 
     * @param resp The AI response object containing the anonymized data to be restored.
     * @param gptResponse The GPT response string used for de-anonymizing the data.
     * @return String The de-anonymized data extracted from the AI response and GPT response for further processing or analysis.
     */
    public static String deAnonymizeData(AI_Response__c resp, String gptResponse){
        try{
            if(String.isNotBlank(gptResponse)){
                Map<String, String> decryptPIIKey = (Map<String, String>)JSON.deserialize(resp.Data_Decrypt_PII_Key__c, Map<String, String>.class);
                List<String> keys = new List<String>(decryptPIIKey.keySet());
                List<SFKeyWrapper> keyWrapperList = new List<SFKeyWrapper>();
                if(keys != null && keys.size() > 0){
                    for (Integer i = keys.size() - 1; i >= 0; i--) {
                       SFKeyWrapper w = new SFKeyWrapper(keys[i]);
                       keyWrapperList.add(w);
                    }
                }
                keyWrapperList.sort();
                for(SFKeyWrapper sfkey : keyWrapperList){
                    if(String.isNotBlank(gptResponse) && gptResponse.indexOf(sfkey.keyName) >= 0){
                        // @Jira : 4802 : remove \\b in spattern
                        //String spattern = '\\b(?i)' + Pattern.quote(key) + '\\b';
                        String spattern = '(?i)' + Pattern.quote(sfkey.keyName);
                        Pattern p = Pattern.compile(spattern);
                        Matcher matcher = p.matcher(gptResponse);
                        if (matcher.find()) {
                            gptResponse = matcher.replaceAll(decryptPIIKey.get(sfkey.keyName));
                        }
                        //gptResponse = gptResponse.replace(key, decryptPIIKey.get(key));
                    }
                } 
            }
            return gptResponse;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AIDataExtractionService', 'deAnonymizeData', '');
            return null;
        }
    }
    
    /**
     * Queries and retrieves a list of child SObject records based on the provided parent ID, AI data extraction detail, and field information, considering child query restrictions.
     * 
     * @param parentId The ID of the parent record associated with the query for child SObject records.
     * @param extractionDetail The AI data extraction detail object containing relevant information for the query.
     * @param fields A string representing the fields to be included in the query for the SObject records.
     * @return List<SObject> A list of child SObject records retrieved based on the provided parameters, considering child query restrictions, for further processing or analysis.
     */
    public static List<SObject> queryRecordsForChildQueryable(Id parentId, AI_Data_Extraction_Detail__c extractionDetail, String fields,List<String> dcRecordIds){
        List<String> idList = new List<String>();
        // @jira : 4662 Handle ORDER BY in Where Clause of Data Extraction
        String orderbyFieldApi = 'CreatedDate';
        if(extractionDetail.Object_Name__c.endsWithIgnoreCase('__x')){ //this check is for external objects
            orderbyFieldApi = 'CreatedDate__c';
        }
        //else if(extractionDetail.Object_Name__c.endsWithIgnoreCase('__dlm')){
          //  orderbyFieldApi = 'ssot__CreatedDate__c';    
        //}
        String defaultOrderByClause = ' ORDER BY '+orderbyFieldApi+' DESC ';
        String defaultWhereClause = extractionDetail.Where_Clause__c;
        Integer defaultLimit = NULL;
        if(String.isNotBlank(extractionDetail.RelationshipName__c) && extractionDetail.RelationshipName__c == 'ActivityHistories'){
            defaultOrderByClause = ' ORDER BY ActivityDate DESC, LastModifiedDate DESC ';
            defaultWhereClause = '';
            defaultLimit = 500;
        }
        String whereClause = AIUtility.getFormattedWhereClause(defaultWhereClause,defaultOrderByClause,defaultLimit,false);
        
        String parentObject = extractionDetail.Parent_Detail__c != null ? extractionDetail.Parent_Detail__r.Object_Name__c : extractionDetail.AI_Data_Extraction_Mapping__r.Object_Name__c;
        String rName = extractionDetail.RelationshipName__c;
        if(rName != Null && rName.endsWithIgnoreCase('__dlm')){
            whereClause = whereClause.replace(defaultOrderByClause, ' ');
            String conditions= (dcRecordIds != null && !dcRecordIds.isEmpty())? ' IN :dcRecordIds ' : ' =:parentId ' ;
            if(whereClause.containsIgnoreCase(' WHERE Id != NULL ')){
               	 whereClause = whereClause.replace(' WHERE Id != NULL ',' WHERE '+extractionDetail.RelationshipField__c+conditions);
            }else{
                 whereClause = ' WHERE '+extractionDetail.RelationshipField__c+conditions+ whereClause;
            }
            
            String query = 'SELECT '+fields+' FROM '+rName+whereClause;
            //System.debug('query : '+query);
            List<sObject> dcRecords = Database.query(query);
            return dcRecords;
        }else if(extractionDetail.Object_Name__c != Null && extractionDetail.Object_Name__c.endsWithIgnoreCase('__dlm') && rName != Null && !rName.endsWithIgnoreCase('__dlm')){
            whereClause = whereClause.replace(defaultOrderByClause, ' ');
        }
        
        
        
        
        // @Jira : 4596 - Account Id not considered while it is selected as Relationship field in Data Context Mapping
        Map<String,String> mapDynamicRelationshipFields = new Map<String,String>{
            'Task' => 'AccountId'
        };
        if(String.isNotBlank(rName) && mapDynamicRelationshipFields.containsKey(rName) && String.isNotBlank(extractionDetail.RelationshipField__c) 
           								&& extractionDetail.RelationshipField__c == mapDynamicRelationshipFields.get(rName)){
           return getDynamicChildParentQuery(rName,fields,mapDynamicRelationshipFields.get(rName),parentId,whereClause,extractionDetail);
        } 
        
        Map<String,String> mapObjNames = new Map<String,String>{
            'Task' => 'Tasks',
            'Event' => 'Events',
            'Feed Item'=> 'Feeds',
            'Content Version' => 'ContentDocumentLink'
        };
            
        if(String.isNotBlank(rName) && mapObjNames.containsKey(rName) && String.isNotBlank(extractionDetail.RelationshipField__c) && !extractionDetail.RelationshipField__c.equalsIgnoreCase('WhatId') && !extractionDetail.RelationshipField__c.endsWithIgnoreCase('__r')){
            rName = mapObjNames.get(rName);
        }
        Boolean isContentVersion = rName.equalsIgnoreCase('ContentDocumentLink');
        String query = isContentVersion ? 'SELECT ContentDocumentId FROM ContentDocumentLink WHERE '
                                                : 'SELECT Id, (SELECT '+fields+' FROM '+rName+''+whereClause+') FROM '+parentObject+' WHERE ';

        if(extractionDetail.Type__c == 'CHILD'){
            query += isContentVersion ? 'LinkedEntityId =:parentId' : 'Id =:parentId';
        }else if(extractionDetail.Type__c == 'GRANDCHILD'){ 
            if(extractionDetail.relationShipField__c.equalsIgnoreCase('WhatId') || extractionDetail.relationShipField__c.equalsIgnoreCase('WhoId') || isContentVersion){
                String field = extractionDetail.Parent_Detail__r.relationShipField__c;
                for(sObject sobj :database.query('SELECT Id from '+extractionDetail.Parent_Detail__r.Object_Name__c+' WHERE '+field+' =:parentId ')){
                    idList.add(String.valueOf(sobj.get('Id')));
                }
                query += isContentVersion ?  ' LinkedEntityId IN:idList' : ' Id IN:idList ' ;
            }else{
                query += isContentVersion ?  ' LinkedEntityId =:parentId' : extractionDetail.Parent_Detail__r.relationShipField__c+' =:parentId';
            }
        }
        
        if(isContentVersion && idList.isEmpty() && extractionDetail.Type__c == 'GRANDCHILD'){
            return new List<SObject>();
        }
        //System.debug('query: '+query);
        List<sObject> lstOfRecords = Database.query(query);
        
        lstOfRecords = getVarifiedRecords(isContentVersion, lstOfRecords, fields, whereClause);

        if(isContentVersion){
            return lstOfRecords;
        }
        
        List<SObject> lstToReturn = new List<SObject>();
        
        for(sObject so : lstOfRecords){
            if(so.getSobjects(rName) != null){
                lstToReturn.addAll((List<sObject>)so.getSobjects(rName));
            }
        }
        //System.debug(' --------     1stofRecord ------------');
        //System.debug(lstOfRecords);
        //System.debug(lstToReturn);
        
        return lstToReturn;
    }
    private static List<sObject> getVarifiedRecords(Boolean isContentVersion, List<sObject> lstOfRecords, String fields, String whereClause){
        if(!isContentVersion){
            return lstOfRecords;
        }else{
            //System.debug(whereClause);
            Set<Id> contentDocumentIds = new Set<Id>();
            for(Sobject sobj : lstOfRecords){
                contentDocumentIds.add((Id)sobj.get('ContentDocumentId'));
            }
            if(!contentDocumentIds.isEmpty()){
                String whereClauseFormatted = (whereClause.containsIgnoreCase('WHERE') == true ? ' AND ' + whereClause.substringAfter('WHERE') : whereClause);
                Set<String> fieldsList = new Set<String>(fields.split(','));
                //System.debug(fieldsList);
                fieldsList.add('ContentSize');
                fieldsList.add('FileExtension');
                if(fieldsList.contains('VersionData') && isResponsesApi == true){
                    fieldsList.remove('VersionData');
                }
                //System.debug(fieldsList);

                String query = 'SELECT '+String.join(fieldsList,',')+' FROM ContentVersion WHERE ContentDocumentId IN :contentDocumentIds '+whereClauseFormatted;
                //System.debug(query);
                List<sObject> records = Database.query(query);
                return validateContentVersion(records);
            }else{
                return lstOfRecords;
            }
        }
    }
    private static List<SObject> validateContentVersion(List<sObject> records){
        List<sObject> validContentVersion = new List<sObject>();
        GPTfy_Settings__c settings = GPTfy_Settings__c.getOrgDefaults();
        for(sObject cv : records){
            if(cv.get('ContentSize') != null){
                if(settings.Max_File_Size__c != NULL){
                        Double s = (Integer.valueOf(cv.get('ContentSize'))/1024);
                        s= (s/1024);
                    if(s > settings.Max_File_Size__c){
                        continue;
                    }
                }                     
                }
            if(String.isNotBlank(settings.File_Type__c)){
                String ftype = String.valueOf(cv.get('FileExtension')).toLowerCase();
                List<String> fileTypesSetting = settings.File_Type__c.split(',');
                for(String f : fileTypesSetting){
                    if(ftype.contains(f.toLowerCase())){
                        validContentVersion.add(cv);
                    }
                }
            }else{
                validContentVersion.add(cv);
            }
        }
        return validContentVersion;
    }
    
    /**
     * Retrieves the list of sobject relationship.
     * @param objectName: The name of the object whose value is to be retrieved from the SObject.
     * @param fields: The name of the field whose value is to be retrieved from the SObject.
     * @param field: The field is contain the where clause field Which we apply filter relationship field.
     * @return List<sobject> : its return list of sobjects.
     */
    public static List<sobject> getDynamicChildParentQuery(String objectName,String fields,String field,Id parentId,String whereClause,
                                                             AI_Data_Extraction_Detail__c extractionDetail){
        List<String> idList = new List<String>();
        String queryStr = '';
        queryStr = 'SELECT '+fields+' FROM '+objectName+''+whereClause;
        if(extractionDetail.Type__c == 'CHILD'){
            // @jira : 4662 Handle ORDER BY in Where Clause of Data Extraction
            if(whereClause.containsIgnoreCase(' WHERE Id != NULL ')){
                whereClause = whereClause.replace(' WHERE Id != NULL ',' WHERE '+field+' =:parentId ');
            }
            queryStr = 'SELECT '+fields+' FROM '+objectName+''+whereClause;
        }else if(extractionDetail.Type__c == 'GRANDCHILD'){ 
                String rfield = extractionDetail.Parent_Detail__r.relationShipField__c;
            	// @jira : 4662 Handle ORDER BY in Where Clause of Data Extraction
                String rWhereClause = AIUtility.getFormattedWhereClause(extractionDetail.Parent_Detail__r.Where_Clause__c,NULL,NULL,false);
                if(rWhereClause.containsIgnoreCase(' WHERE Id != NULL ')){
               			 rWhereClause = rWhereClause.replace(' WHERE Id != NULL ',' WHERE '+rfield+' =:parentId ');
            	}
                for(sObject sobj :database.query('SELECT Id from '+extractionDetail.Parent_Detail__r.Object_Name__c+rWhereClause)){
                    idList.add(String.valueOf(sobj.get('Id')));
                }
            	if(whereClause.containsIgnoreCase(' WHERE Id != NULL ')){
               		 whereClause = whereClause.replace(' WHERE Id != NULL ',' WHERE '+field+' IN:idList ');
            	}
                queryStr = 'SELECT '+fields+' FROM '+objectName+whereClause;
        }
        return Database.query(queryStr);
    }
    
    /**
     * Retrieves the value of a specific field from the provided SObject based on the field name.
     * 
     * @param fName The name of the field whose value is to be retrieved from the SObject.
     * @param so The SObject containing the field whose value is being retrieved.
     * @return String The value of the specified field from the SObject for further processing or analysis.
     */
    public static String getFieldValue(AI_Data_Extraction_Field__c extractionField, SObject so, String objName){
        String fName = extractionField.Field__c;
        String value = '';
        if(extractionField.Object__c == 'ContentVersion' && fName == 'VersionData' && isResponsesApi == true){
            return value;
        }
        if(String.isNotBlank(extractionField.Formula__c)){
            FormulaEval.FormulaInstance ff = Formula.builder()
                .withType(schemaMap.get(objName))
                .withReturnType(FormulaEval.FormulaReturnType.valueOf(extractionField.Field_Type__c))
                .withFormula(extractionField.Formula__c)
                .build();
            value = String.valueOf(ff.evaluate(so));
        }else{
            if(fName.containsIgnoreCase('.')){
                List<String> relationshipFields = fName.split('\\.');
                if(relationshipFields != null && !relationshipFields.isEmpty()){
                    SObject rObj = so;
                    for(Integer i = 0; i < relationshipFields.size(); i++){
                        if(rObj != null){
                            String rName = relationshipFields.get(i);
                            if((relationshipFields.size()-1) == i){
                                value = String.valueOf(rObj.get(rName));
                            }else{
                                rObj = rObj.getSObject(rName);
                            }
                        }else{
                            break;
                        }
                    }
                }
            }else{
                value = String.valueOf(so.get(fName));
            }
        }
        return value;
    }
    
     // Security Layer 2 (Only For TEXTAREA, RICHTEXTAREA)
     /**
     * Applies the specified AI security filters to the provided input, considering the designated PII (Personally Identifiable Information) keys for masking sensitive information.
     * 
     * @param filters A list of AI security filters containing the criteria for applying security measures to the input data.
     * @param input The input string to which the security filters are to be applied.
     * @param mapPIIKeys A map where the keys represent Personally Identifiable Information (PII) keys, and the values contain the corresponding data for masking sensitive information.
     * @param mapPIIKeyIsMatchWord A map where the keys represent Personally Identifiable Information (PII) keys and the values contain the matchcompleteword value of security layer.
     * @return Map<String, String> A map where the keys represent the filtered data, and the values contain the corresponding modified or masked data based on the applied security filters.
     */
    public static Map<String, String> applyFilters(List<AI_Security_Filters__c> filters, String input, Map<String, String> mapPIIKeys,Map<String,Boolean> mapPIIKeyIsMatchWord){
        for(AI_Security_Filters__c sf : filters){
            try {
                Integer count = 1;
                if(String.isNotBlank(sf.Blocklist__c) && sf.RecordTypeId == RT_BLOCKLIST){
                    for(String item : sf.Blocklist__c.split(';')){
                        item = item.trim();
                        if(input.containsIgnoreCase(item)){
                            String spattern = '(?i)' + Pattern.quote(item);
                            Pattern p = Pattern.compile(spattern);
                            Matcher matcher = p.matcher(input);
                            // @Jira 4786: Blocklist is failing to mask some of the upper/lowercase variations
                    		while(matcher.find()){
                                String finding = matcher.group();
                                String replacement = (!mapPIIKeys.isEmpty() && mapPIIKeys.containsKey(finding)) ? mapPIIKeys.get(finding) : checkUniqueReplacement(mapPIIKeys.values(), count, sf.Replacement_Value__c, sf.Type__c);
                            	input.replace(finding, replacement);
                                mapPIIKeys.put(finding, replacement);
                                count++;
                            }
                        }
                    }
                }else if(sf.RecordTypeId == RT_REGEX && String.isNotBlank(sf.Search_Pattern__c)){
                    Pattern regexPattern = Pattern.compile(sf.AI_Optimized_Search_Pattern__c);
                    Matcher matcher = regexPattern.matcher(input);
                    while(matcher.find() && (Limits.getCpuTime() < Limits.getLimitCpuTime())) {
                        String finding = matcher.group();
                        if(sf.AI_Ignore_Special_Characters__c){
                            finding = replaceSpecialCharacters(finding);
                        }
                        String replacement = (!mapPIIKeys.isEmpty() && mapPIIKeys.containsKey(finding)) ? mapPIIKeys.get(finding) : checkUniqueReplacement(mapPIIKeys.values(), count, sf.Replacement_Value__c, sf.Type__c);
                        
                        mapPIIKeyIsMatchWord.put(finding,sf.AI_Match_Complete_Word__c);  
                        input.replace(finding, replacement);
                        mapPIIKeys.put(finding, replacement);
                        count++;
                    }
                }
            } catch(Exception e){
                throw new ChatGPTUtills.ApplicationException('Security Filter "'+sf.Name+'" is failing, please modify or use another filter. Error: '+e.getMessage());
            }
        }
        return mapPIIKeys;
    }
    
    public static String replaceSpecialCharacters(String value){
        if(String.isNotBlank(Label.Special_Characters_to_Skip_on_Masking)){
            List<String> lstOfSpecialCharacters = Label.Special_Characters_to_Skip_on_Masking.split(' ');
            if(String.isNotBlank(value)){
                for(String sc : lstOfSpecialCharacters){
                    if(value.endsWith(sc)){
                        value = value.removeEnd(sc);                    
                    }if(value.startsWith(sc)){
                        value = value.removeStart(sc);                    
                    }
                }
            }
        }
        //removing brackets
        if(String.isNotBlank(value)){
            if(value.startsWith('(') && value.endsWith(')')){
                value = value.removeStart('(').removeEnd(')');       
            }if(value.startsWith('{') && value.endsWith('}')){
                value = value.removeStart('{').removeEnd('}');       
            }if(value.startsWith('[') && value.endsWith(']')){
                value = value.removeStart('[').removeEnd(']');       
            }if(value.startsWith('<') && value.endsWith('>')){
                value = value.removeStart('<').removeEnd('>');       
            }
        }  
		return value;
    }
    
    /*
    public static Boolean checkMatch(Matcher matcher, AI_Security_Filters__c sf){
        Boolean noMatchFound = false;
        try{
            matcher.group();
        }catch(Exception e){
            if(String.isNotBlank(e.getMessage()) && e.getMessage().equalsIgnoreCase('No match found')){
                noMatchFound = true;
            }else{
                throw new ChatGPTUtills.ApplicationException('Security Filter "'+sf.Name+'" is failing, please modify or use another filter. Error: '+e.getMessage());
            } 
        }
        return noMatchFound;
    }
	*/
    
    /**
     * Checks for the uniqueness of replacement values within the provided list of replacements, ensuring a unique value for the specified Salesforce type.
     * 
     * @param lstReplacements The list of existing replacement values to be checked for uniqueness.
     * @param count The count of existing replacement values.
     * @param replacementValue The replacement value to be checked for uniqueness within the list.
     * @param sfType The type of Salesforce object or field associated with the replacement value.
     * @return String The replacement value confirmed to be unique for the specified Salesforce type within the list of replacements.
     */
    private static String checkUniqueReplacement(List<String> lstReplacements, Integer count, String replacementValue, String sfType){
        String replacement = replacementValue+(sfType == 'Email' ? '-00'+count+'@mock.com' : '-00'+count);
        return (lstReplacements.size() > 0 && lstReplacements.indexOf(replacement) != -1) ? checkUniqueReplacement(lstReplacements, count+1, replacementValue, sfType) : replacement;
    }
    
    /**
     * Checks for the uniqueness of the entire replacement value within the provided list of replacements, ensuring a unique value for replacement purposes.
     * 
     * @param lstReplacements The list of existing replacement values to be checked for the uniqueness of the entire value.
     * @param count The count of existing replacement values.
     * @param replacementValue The replacement value to be checked for uniqueness within the list.
     * @return String The replacement value confirmed to be entirely unique within the list of replacements.
     */
    private static String checkEntireValueUniqeReplacement(List<String> lstReplacements, Integer count, String replacementValue){
        String replacement = replacementValue.replace('{n}', count+'');
        return (lstReplacements.size() > 0 && lstReplacements.indexOf(replacement) != -1) ? checkEntireValueUniqeReplacement(lstReplacements, count+1, replacementValue) : replacement;
    }
    
    class SFKeyWrapper implements Comparable{
        String keyName;
        public SFKeyWrapper(String name){
            this.keyName = name;
        }
        public Integer compareTo(Object compareTo) {
            SFKeyWrapper s = (SFKeyWrapper) compareTo;
            return s.KeyName.length() - this.keyName.length();
		}
    }
    
    // @Jira : 4802 : Create DataPIIWrapper for pass data of response and mapOfPIIKeyToMatchCompleteWord
    public class DataPIIWrapper {
        public AI_Response__c resp {get;set;}
        public Map<String,Boolean> mapOfPIIKeyToMatchCompleteWord {get;set;}
        public DataPIIWrapper(AI_Response__c resp,Map<String,Boolean> mapOfPIIKeyToMatchCompleteWord){
            this.resp = resp;
            this.mapOfPIIKeyToMatchCompleteWord = mapOfPIIKeyToMatchCompleteWord;
        }
	}
    
    /*public static void getEvaluatedFormula(){
        FormulaEval.FormulaInstance ff = Formula.builder()
            .withType(Schema.getGlobalDescribe().get('Account'))
            .withReturnType(FormulaEval.FormulaReturnType.STRING)
            .withFormula('name & " (" & website & ")"')
            .build();
        
        String fieldNameList = String.join(ff.getReferencedFields(),',');
        String queryStr = 'select ' + fieldNameList + ' from Account where id = \'0018d00000mAh4yAAC\' LIMIT 1';
        Account s = Database.query(queryStr);
        
        //system.debug(ff.evaluate(s));
    }*/
    
    public class ApplicationException extends Exception {}
}