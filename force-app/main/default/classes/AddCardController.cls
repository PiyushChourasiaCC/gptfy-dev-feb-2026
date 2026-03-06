public with sharing class AddCardController implements Metadata.DeployCallback {
    
    private static final String NAMESPACE = AIExtractionFieldMappingController.NAMESPACE;
    private static final String OBJECT_NAME = NAMESPACE + 'AI_Prompt__c';
    private static final String PICKLIST_FIELD_NAME = NAMESPACE + 'Purpose__c';
    private static final String STATIC_RESOURCE_MISSING_ERROR = 'Static resource not exist.';
    private static final String NAME = 'Name';
    private static final String RESPONSE_MAPPING = 'Response_Mapping__c';
    private static final String REQUEST_MAPPING = 'Request_Mapping__c';
    private static final String feature = 'Feature';
    private static final String CARD_TYPE = 'Feature__c';
    private static final String ICON_SOURCE = 'Icon_Source__c';
    private static final String ICON_DETAIL = 'Icon_Details__c';
    private static final String ENABLED = 'Enabled__c';
    private static final String ICON_SOURCE_STATIC_RESOURCE = 'Static Resource';
    private static final String CARD_TYPE_CTLOG = 'CTLOG';
    private static final String CARD_TYPE_AMODL = 'AMODL';
    private static final String CARD_TYPE_APIDS = 'APIDS';
    private static final List<String> METADATA_FIELDS = new List<String>{'Feature__c', 'Icon_Source__c', 'Icon_Details__c', 'Description__c', 'Sequence__c', 'Enabled__c'};
        
    @AuraEnabled
    public static boolean createCardConfiguration(Map<String, Object> params) {
        boolean hasSuccess = false;
        try{
            String staticResource = '';
            if((String)params.get(ICON_SOURCE) == ICON_SOURCE_STATIC_RESOURCE){
                staticResource = (String)params.get(ICON_DETAIL);
                staticResource = staticResource.trim(); 
            }
            
            if(String.isNotBlank(staticResource)){
                List<StaticResource> resource = [SELECT Id, Name FROM StaticResource WHERE Name =: staticResource LIMIT 1];
                if(resource.size() < 1){
                    throw new AuraHandledException(STATIC_RESOURCE_MISSING_ERROR);
                }
            }
            if(!test.isRunningTest()){
                if(params.get(CARD_TYPE) == CARD_TYPE_CTLOG){
                    insertPicklistValue(OBJECT_NAME, PICKLIST_FIELD_NAME, (String)params.get(NAME));
                }
            }   
            
            AI_Card_Configuration__c oCardConfiguration = new AI_Card_Configuration__c();
            oCardConfiguration.Name = (String)params.get(NAME);
            for(String field : METADATA_FIELDS){
                if(params.containsKey(field)){
                    if(params.get(CARD_TYPE) != CARD_TYPE_CTLOG && field == ENABLED){
                        oCardConfiguration.put(NAMESPACE+field, false);
                    }else{
                        if(field == 'Sequence__c'){
                            oCardConfiguration.put(NAMESPACE+field, Decimal.valueOf(String.valueOf(params.get(field))));
                        }else{
                            oCardConfiguration.put(NAMESPACE+field, params.get(field));
                        }
                    }
                }
            }
            FLSCheck.getInstance().insertDML(new List<AI_Card_Configuration__c>{oCardConfiguration});
            hasSuccess = true;
        }catch(DMLException dmlex){
            throw new AuraHandledException(dmlex.getDMLMessage(0));
        }catch(Exception ex){
            throw new AuraHandledException(ex.getMessage());
        }   
        return hasSuccess;
    }
    
    @AuraEnabled
    public static boolean updateCardConfiguration(Map<String, Object> params) {  
        boolean hasUpdated = false;
        try{
            AI_Card_Configuration__c oCardConfiguration = new AI_Card_Configuration__c();
            oCardConfiguration.Id = (String)params.get('Id');
            for (String key : METADATA_FIELDS) {
                if(params.containsKey(key)){
                    if(params.get(CARD_TYPE) != CARD_TYPE_CTLOG && key == ENABLED){
                        oCardConfiguration.put(NAMESPACE+key, false);
                    }else{
                        if(key == 'Sequence__c'){
                            oCardConfiguration.put(NAMESPACE+key,Integer.valueOf(params.get(key)));
                        }else{
                            oCardConfiguration.put(NAMESPACE+key, params.get(key));
                        }
                    }
                }
            }
            FLSCheck.getInstance().upsertDML(new List<AI_Card_Configuration__c>{oCardConfiguration});
            hasUpdated = true;
            return hasUpdated;
        }catch(DMLException dmlex){
            throw new AuraHandledException(dmlex.getDMLMessage(0));
        }catch(Exception ex){
            throw new AuraHandledException(ex.getMessage());
        }
    }
    
    @AuraEnabled
    public static boolean deleteCardConfiguration(String fieldValue, String metadataName, String metadataLabel, String cardType, String recordId){

        boolean hasDeleted = false;
        try{
            AI_Card_Configuration__c oCardConfiguration = new AI_Card_Configuration__c(Id=recordId);
            MetadataService.MetadataPort service = createService();
            if(cardType == CARD_TYPE_CTLOG){
                if(!Test.isRunningTest()){                    
                    MetadataService.CustomField customField = (MetadataService.CustomField) service.readMetadata('CustomField', new String[] { OBJECT_NAME+'.'+PICKLIST_FIELD_NAME }).getRecords()[0];
                    for(MetadataService.CustomValue cv : customField.valueSet.valueSetDefinition.value){
                        if(cv.fullName == fieldValue){
                            cv.label = fieldValue;
                            cv.fullName = fieldValue;
                            cv.isActive = false;
                            break;
                        }
                    }
                    MetadataService.SaveResult[] updateResult = service.updateMetadata(new MetadataService.Metadata[] { customField }); 
                    
                    List<AI_Prompt__c> lstPrompts = new List<AI_Prompt__c>();
                    // @Jira : 4584 Review CheckMarx Security Issues - GPTfy
                    String sSOQL = ('SELECT Id, Name, Purpose__c FROM AI_Prompt__c WHERE Purpose__c INCLUDES (\'' + fieldValue + '\')').replace('\\\'', '\'');
                    for(AI_Prompt__c ap : database.query(String.escapeSingleQuotes(sSOQL).replace('\\\'', '\''))){
                        Set<String> currentValues = new Set<String>(ap.Purpose__c.split(';'));
                        currentValues.remove(fieldValue);
                        ap.Purpose__c = String.join(new List<String>(currentValues), ';');
                        
                        lstPrompts.add(ap);
                    }
                    FLSCheck.getInstance().updateDML(new List<AI_Prompt__c>(lstPrompts));
                }
            }
            else if(cardType == CARD_TYPE_APIDS){
            	List<AI_Data_Source__c> lstOfDataSource = [SELECT Id FROM AI_Data_Source__c WHERE Name =:metadataLabel];
                if(lstOfDataSource != null && !lstOfDataSource.isEmpty()){
                    FLSCheck.getInstance().deleteDML(lstOfDataSource);
                }
            }
            else if(cardType == CARD_TYPE_AMODL){
                List<AI_Prompt__c> lstOfPrompt = [SELECT Id FROM AI_Prompt__c WHERE AI_Connection__r.Name =:metadataLabel LIMIT 1];
                if(lstOfPrompt != null && !lstOfPrompt.isEmpty()){
                    throw new ChatGPTUtills.ApplicationException('Cannot be deleted as the record is associated with prompts.');
                }else{
                    List<AI_Connection__c> lstOfConnToDelete = [SELECT Id FROM AI_Connection__c WHERE Name =:metadataLabel];
                    if(lstOfConnToDelete != null && !lstOfConnToDelete.isEmpty()){
                        FLSCheck.getInstance().deleteDML(lstOfConnToDelete);
                    }
                }
            }
            
            if(oCardConfiguration != null){
                FLSCheck.getInstance().deleteDML(new List<sObject>{oCardConfiguration});
                hasDeleted = true;
            }
        }catch(Exception ex){
            throw new AuraHandledException(ex.getMessage()); 
        }
        return hasDeleted;
    }
    
    @AuraEnabled
    public static List<dataWrap> getCardConfiguration(String feature){
        List<dataWrap> lstDataWrap = new List<dataWrap>();
        List<AI_Card_Configuration__c> lstCardConfiguration = new List<AI_Card_Configuration__c>();
        
        Map<String, Set<String>> mapRecordName = new Map<String, Set<String>>();
        Map<String, Map<String, List<AI_Prompt__c>>> mapMatrics = new Map<String, Map<String, List<AI_Prompt__c>>>();
        Map<String, Decimal> mapSecondTotal = new Map<String, Decimal>();
        Map<String, Decimal> mapMoneyTotal = new Map<String, Decimal>();
        
        for(AI_Card_Configuration__c cardConfiguration : [SELECT Id, Name, Feature__c, Icon_Source__c, Description__c, Enabled__c, Icon_Details__c, Sequence__c FROM AI_Card_Configuration__c WHERE Feature__c =: feature AND Icon_Details__c != NULL ORDER BY Sequence__c]){
            if(cardConfiguration.Icon_Source__c == ICON_SOURCE_STATIC_RESOURCE){
                try{
                    cardConfiguration.Icon_Details__c = URL.getOrgDomainUrl().toExternalForm() + PageReference.forResource(cardConfiguration.Icon_Details__c).getUrl().SubStringBefore('?');
                }catch(Exception e){}
            }
            if(!mapRecordName.containsKey(cardConfiguration.Feature__c)){
                mapRecordName.put(cardConfiguration.Feature__c, new Set<String>());
            }
            mapRecordName.get(cardConfiguration.Feature__c).add(cardConfiguration.Name);
            lstCardConfiguration.add(cardConfiguration);
        }
        if(feature == CARD_TYPE_CTLOG){
            if(mapRecordName.containsKey(CARD_TYPE_CTLOG) && mapRecordName.get(CARD_TYPE_CTLOG).size() > 0){
                mapMatrics = getMatricsOne(mapRecordName.get(CARD_TYPE_CTLOG),feature);
                List<Map<String, Decimal>> lstROITotal = getMatricsTwo(mapRecordName.get(CARD_TYPE_CTLOG),feature);
                mapSecondTotal = lstROITotal[0];
                mapMoneyTotal = lstROITotal[1];
            }
            
            for(AI_Card_Configuration__c cardConfiguration : lstCardConfiguration){
                //if(mdt.Enabled__c){
                    dataWrap wrap = new dataWrap();
                    wrap.mdtRecord = new metadataWrap(cardConfiguration);
                    wrap.record = null;
                    if(mapMatrics.containsKey(cardConfiguration.Name)){
                        Integer actCount = 0;
                        Integer totalCount = 0;
                        if(mapMatrics.get(cardConfiguration.Name).containsKey('Active')){
                            actCount = mapMatrics.get(cardConfiguration.Name).get('Active').size();
                        }
                        if(mapMatrics.get(cardConfiguration.Name).containsKey('Total')){
                            totalCount = mapMatrics.get(cardConfiguration.Name).get('Total').size();
                        }
                        wrap.matrics1 = actCount+'/'+totalCount+' Prompts Deployed';
                    }else{
                        wrap.matrics1 = '0/0 Prompts Deployed';
                    }
                    String hours = '';
                    if(!mapSecondTotal.isEmpty() && mapSecondTotal.containsKey(cardConfiguration.Name)){
                        hours = (mapSecondTotal.get(cardConfiguration.Name) / 3600) > 1000 ? ((mapSecondTotal.get(cardConfiguration.Name) / 3600)/1000).round(System.RoundingMode.CEILING) +'k Hours' : (mapSecondTotal.get(cardConfiguration.Name) / 3600).round(System.RoundingMode.CEILING)+' Hours' ;
                    }else{
                        hours = '0 Hours';
                    }
                    String money = '';
                    if(!mapMoneyTotal.isEmpty() && mapMoneyTotal.containsKey(cardConfiguration.Name)){
                        //String currencySymbol = Test.isRunningTest() ? '$' : ConnectApi.Organization.getSettings().UserSettings.currencySymbol;
                        //money = mapMoneyTotal.get(cardConfiguration.Name) > 1000 ? currencySymbol+(mapMoneyTotal.get(cardConfiguration.Name)/1000).round(System.RoundingMode.CEILING) +'k Saved' : currencySymbol+mapMoneyTotal.get(cardConfiguration.Name).round(System.RoundingMode.CEILING)+' Saved';
                        money = mapMoneyTotal.get(cardConfiguration.Name) > 1000 ? (mapMoneyTotal.get(cardConfiguration.Name)/1000).round(System.RoundingMode.CEILING) +'k Saved' : mapMoneyTotal.get(cardConfiguration.Name).round(System.RoundingMode.CEILING)+' Saved';
                    }else{
                        money = '0 Saved';
                    }
                    wrap.matrics2 = hours+' / '+money;
                    lstDataWrap.add(wrap);
                //}
            }
        } else if(feature == CARD_TYPE_AMODL){
            Map<String, AI_Connection__c> mapAIConnection = new Map<String, AI_Connection__c>();
            if(mapRecordName.containsKey(CARD_TYPE_AMODL) && mapRecordName.get(CARD_TYPE_AMODL).size() > 0){
                for(AI_Connection__c c : [SELECT Id, Name, AI_Technology__c, Named_Credential__c FROM AI_Connection__c WHERE  Name IN : mapRecordName.get(CARD_TYPE_AMODL)]){
                    mapAIConnection.put(c.Name, c);
                }
            }
            for(AI_Card_Configuration__c cardConfiguration : lstCardConfiguration){
                dataWrap wrap = new dataWrap();
                    wrap.mdtRecord = new metadataWrap(cardConfiguration);
                    if(!mapAIConnection.isEmpty() && mapAIConnection.containsKey(cardConfiguration.Name)){                    
                        wrap.record = mapAIConnection.get(cardConfiguration.Name);
                    }else{
                        wrap.record = null;
                    }
                    lstDataWrap.add(wrap);
                }
                
        }else if(feature == CARD_TYPE_APIDS){
            Map<String, AI_Data_Source__c> mapDataSource = new Map<String, AI_Data_Source__c>();
            if(mapRecordName.containsKey(CARD_TYPE_APIDS) && mapRecordName.get(CARD_TYPE_APIDS).size() > 0){
                for(AI_Data_Source__c c : [SELECT Id, Name, Named_Credential__c, Source__c, EndPoint_URL__c FROM AI_Data_Source__c WHERE Name IN : mapRecordName.get(CARD_TYPE_APIDS)]){
                    mapDataSource.put(c.Name, c);
                }
            }
            for(AI_Card_Configuration__c cardConfiguration : lstCardConfiguration){
                dataWrap wrap = new dataWrap();
                wrap.mdtRecord = new metadataWrap(cardConfiguration);
                if(!mapDataSource.isEmpty() && mapDataSource.containsKey(cardConfiguration.Name)){                    
                    wrap.record = mapDataSource.get(cardConfiguration.Name);
                }else{
                    wrap.record = null;
                }
                lstDataWrap.add(wrap);
            }
        }
        return lstDataWrap;
    }

    @AuraEnabled
    public static String getResponseMapping(String recordId){
        map<String, String> mapResponseMapping = new map<String, String>();
        mapResponseMapping.put('Name', '');
        mapResponseMapping.put('Id', '');
        mapResponseMapping.put('namespace', NAMESPACE);
        String responseMapping = '';
        if(String.isNotBlank(recordId)){
            for(AI_Connection__c ac : [SELECT AI_Response_Mapping__c FROM AI_Connection__c WHERE Id=:recordId AND AI_Response_Mapping__c != null]){
                responseMapping = ac.AI_Response_Mapping__c;
            }
            if(String.isNotBlank(responseMapping)){
                for(AI_Response_Mapping__c rm : [SELECT Id, Name FROM AI_Response_Mapping__c WHERE Id=:responseMapping]){
                    mapResponseMapping.put('Name', rm.Name);
                    mapResponseMapping.put('Id', rm.Id);
                }
            }
        }
        return JSON.serialize(mapResponseMapping);
    }
    
    @AuraEnabled
    public static String getRequestMapping(String recordId){
        map<String, String> mapRequestMapping = new map<String, String>();
        mapRequestMapping.put('Name', '');
        mapRequestMapping.put('Id', '');
        mapRequestMapping.put('namespace', NAMESPACE);
        
        String requestMapping = '';
        if(String.isNotBlank(recordId)){
            for(AI_Connection__c ac : [SELECT AI_Request_Mapping__c FROM AI_Connection__c WHERE Id=:recordId AND AI_Request_Mapping__c != null]){
                requestMapping = ac.AI_Request_Mapping__c;
            }
            if(String.isNotBlank(requestMapping)){
                for(Request_Mapping__c  rm : [SELECT Id, Name FROM Request_Mapping__c  WHERE Id =: requestMapping]){ 
                    mapRequestMapping.put('Name', rm.Name);
                    mapRequestMapping.put('Id', rm.Id);
                }
            }
        }
        return JSON.serialize(mapRequestMapping);
    }
    
    @AuraEnabled
    public static AI_Connection__c createConnection(Map<String, Object> params){
        try{
            AI_Connection__c c = new AI_Connection__c();
            String recName = (String)params.get(NAME);
            
            if(String.isNotBlank(recName)){
                for(AI_Connection__c ac : [SELECT Id, Name, Named_Credential__c, AI_Technology__c, Connector_Class__c, Infrastructure__c, Security_Layer__c, Version__c, Enable_in_Sandbox__c, Model__c, EndPoint_URL__c, Type__c FROM AI_Connection__c WHERE Name =: recName LIMIT 1]){
                    c = ac;
                }
            }
            
            c.Name = recName;
            
            c.Named_Credential__c = (String)params.get(NAMESPACE + 'Named_Credential__c');
            c.AI_Technology__c = (String)params.get(NAMESPACE + 'AI_Technology__c');
            c.Connector_Class__c = (String)params.get(NAMESPACE + 'Connector_Class__c');
            c.Processing_Class__c = (String)params.get(NAMESPACE + 'Processing_Class__c');
            c.Infrastructure__c = (String)params.get(NAMESPACE + 'Infrastructure__c');
            c.Security_Layer__c = (String)params.get(NAMESPACE + 'Security_Layer__c');
            c.Version__c = (String)params.get(NAMESPACE + 'Version__c');
            c.Enable_in_Sandbox__c = params.get(NAMESPACE + 'Enable_in_Sandbox__c') != null ? Boolean.valueOf(''+params.get(NAMESPACE + 'Enable_in_Sandbox__c')) : false;
            c.Model__c = (String)params.get(NAMESPACE + 'Model__c');
            c.Max_Tokens__c = (params.get(NAMESPACE + 'Max_Tokens__c') != '' &&  params.get(NAMESPACE + 'Max_Tokens__c') != null) ? Decimal.valueOf(''+params.get(NAMESPACE + 'Max_Tokens__c')) : null;
            c.Max_Total_Tokens__c = (params.get(NAMESPACE + 'Max_Total_Tokens__c') != '' && params.get(NAMESPACE + 'Max_Total_Tokens__c') != null ) ? Decimal.valueOf(''+params.get(NAMESPACE + 'Max_Total_Tokens__c')) : null;
            c.Temperature__c = (params.get(NAMESPACE + 'Temperature__c') != '' && params.get(NAMESPACE + 'Temperature__c') != null ) ? Decimal.valueOf(''+params.get(NAMESPACE + 'Temperature__c')) : null;
            c.EndPoint_URL__c = (String)params.get(NAMESPACE + 'EndPoint_URL__c');
            c.Top_P__c = (params.get(NAMESPACE + 'Top_P__c') != '' && params.get(NAMESPACE + 'Top_P__c') != null ) ? Decimal.valueOf(''+params.get(NAMESPACE + 'Top_P__c')) : null;
            c.Additional_Parameters__c = (String)params.get(NAMESPACE+'Additional_Parameters__c');
            c.Type__c = (String)params.get(NAMESPACE+'Type__c');
            c.AI_Response_Mapping__c = (params.get(RESPONSE_MAPPING) != null && params.get(RESPONSE_MAPPING) != '') ? String.valueOf(''+params.get(RESPONSE_MAPPING)) : null;
            c.AI_Request_Mapping__c = (params.get(REQUEST_MAPPING) != null && params.get(REQUEST_MAPPING) != '') ? String.valueOf(''+params.get(REQUEST_MAPPING)) : null;
            c = (AI_Connection__c)FLSCheck.getInstance().upsertDML(new List<AI_Connection__c>{c}).get(0);
            
			return c;
        }catch(exception ex){
            system.debug('============================== ex.getMessage : '+(ex.getMessage()+'--'+ex.getStackTraceString()));
            throw new AuraHandledException(ex.getMessage()+'--'+ex.getStackTraceString()); 
        }
    }
    
    @AuraEnabled
    public static AI_Data_Source__c createDataSource(Map<String, Object> params){

        try{
            AI_Data_Source__c c = new AI_Data_Source__c();
            String recName = (String)params.get(NAME);
            if(String.isNotBlank(recName)){
                for(AI_Data_Source__c ac : [SELECT Id, Name, Named_Credential__c, Source__c, EndPoint_URL__c, Connector_Class__c FROM AI_Data_Source__c WHERE Name =: recName LIMIT 1]){
                    c = ac;
                }
            }
            c.Name = recName;
            c.Named_Credential__c = (String)params.get(NAMESPACE + 'Named_Credential__c');
            c.Source__c = (String)params.get(NAMESPACE + 'Source__c');
            c.Connector_Class__c = (String)params.get(NAMESPACE + 'Connector_Class__c');
            c.EndPoint_URL__c = (String)params.get(NAMESPACE + 'EndPoint_URL__c');
            c = (AI_Data_Source__c)FLSCheck.getInstance().upsertDML(new List<AI_Data_Source__c>{c}).get(0);
	
            return c;
        }catch(exception ex){
            throw new AuraHandledException(ex.getMessage()+'--'+ex.getStackTraceString()); 
        }

    }
    
    @AuraEnabled
    public static String handleCardActivate(Map<String, Object> params){
        boolean hasError = false;
        String supportData = 'Parameters: '+JSON.serialize(params);
        List<sObject> records = new List<sObject>();
        try{
            
            String recName = (String)params.get(NAME);
            String feature = (String)params.get(feature);
            String SOQL = '';
            if(feature == CARD_TYPE_AMODL){
                SOQL = 'SELECT AI_Technology__c, Connector_Class__c, Processing_Class__c, Type__c, Custom_Metadata__c, Additional_Parameters__c, Enable_in_Sandbox__c, EndPoint_URL__c, Infrastructure__c, Key__c, Max_Tokens__c, Model__c, Named_Credential__c, Security_Layer__c, Temperature__c, Top_P__c, Version__c, External_Id__c, AI_Response_Mapping__c, AI_Request_Mapping__c, Id, Name FROM AI_Connection__c WHERE Name =: recName ';
            }else if(feature == CARD_TYPE_APIDS){
                SOQL = 'SELECT Id, Name, Named_Credential__c, Source__c, EndPoint_URL__c, Connector_Class__c FROM AI_Data_Source__c WHERE Name =: recName ';
            }
            List<AI_Card_Configuration__c> mdt = [SELECT Id, Name, Enabled__c FROM AI_Card_Configuration__c WHERE Name =: recName AND Feature__c =: feature LIMIT 1];
            records = database.query(SOQL);
            if(mdt.size() < 1 || records.size() < 1){
                hasError = true;
                throw AIUtility.getMessageAuraHandledException('Missing required steps, please complete all necessary actions.'); 
            }
            
            if(records.size() == 1){
                List<String> requiredFields = new List<String>();
                sObject c = records[0];
                
                if(feature == CARD_TYPE_AMODL){
                    if(String.isBlank((String)c.get(NAMESPACE +'Named_Credential__c')) && String.isBlank((String)c.get(NAMESPACE +'Connector_Class__c')) && String.isBlank((String)c.get(NAMESPACE +'Processing_Class__c'))){
                           requiredFields.add(' Named Credential or Connector Class or Processing Class');
                    }
                    
                    if(String.isBlank((String)c.get(NAMESPACE +'AI_Technology__c'))){
                        requiredFields.add(' AI Technology');
                    }
                    
                    if(String.isBlank((String)c.get(NAMESPACE +'Infrastructure__c'))){
                        requiredFields.add(' Platform');
                    }
                    
                    if(String.isBlank((String)c.get(NAMESPACE +'Version__c'))){
                        requiredFields.add(' Version');
                    }
                    
                    if(c.get(NAMESPACE+'Temperature__c') == null){
                        requiredFields.add(' Temperature');
                    }
                }
                if(feature == CARD_TYPE_APIDS){
                    if(String.isBlank((String)c.get(NAMESPACE +'Connector_Class__c'))){
                           requiredFields.add(' Connector Class');
                    }
                    if(String.isBlank((String)c.get(NAMESPACE +'Source__c'))){
                        requiredFields.add(' Source'); 
                    }
                }
                
                
                if(requiredFields.size() > 0){
                    String errorMessage = 'Error: The:';
                    String glue = '';
                    for(String field : requiredFields){
                        errorMessage += glue + field;
                        glue = ',';
                    }
                    
                    if(requiredFields.size() > 1){
                        errorMessage += ' fields are mandatory in Connection Details. Please fill in the required information.';
                    }else if(requiredFields.size() == 1){
                        errorMessage += ' field is mandatory in Connection Details. Please fill in the required information.';
                    }
                    
                    
                    hasError = true;
                    
                    throw AIUtility.getMessageAuraHandledException(errorMessage);
                }else{
                    if(String.isNotBlank((String)c.get(NAMESPACE +'Named_Credential__c'))){
                        List<NamedCredential> namedCreds = [SELECT Id, DeveloperName, MasterLabel FROM NamedCredential WHERE DeveloperName =: (String)c.get(NAMESPACE +'Named_Credential__c') LIMIT 1];
                        if(namedCreds.size() < 1){
                            hasError = true;
                            throw AIUtility.getMessageAuraHandledException('Card activation failed. The provided Named Credential could not be found.');
                        }
                    }if(String.isNotBlank((String)c.get(NAMESPACE +'Connector_Class__c'))){
                        List<ApexClass> apexCls = [SELECT Id FROM ApexClass WHERE Name =: (String)c.get(NAMESPACE +'Connector_Class__c') LIMIT 1];
                        if(apexCls.size() < 1 && !Test.isRunningTest()){
                            hasError = true;
                            throw AIUtility.getMessageAuraHandledException('Card activation failed. The provided Connector Class could not be found.');
                        }
                    }
                    
                    if(feature == CARD_TYPE_AMODL){
                        if(String.isNotBlank((String)c.get(NAMESPACE +'Processing_Class__c'))){
                            List<ApexClass> apexCls = [SELECT Id FROM ApexClass WHERE Name =: (String)c.get(NAMESPACE +'Processing_Class__c') LIMIT 1];
                            if(apexCls.size() < 1){
                                hasError = true;
                                throw AIUtility.getMessageAuraHandledException('Card activation failed. The provided Processing Class could not be found.');
                            }
                        }
                        if(c.get(NAMESPACE+'Temperature__c') == null || (decimal)c.get(NAMESPACE+'Temperature__c') < 0 || (decimal)c.get(NAMESPACE+'Temperature__c') > 1){
                            throw AIUtility.getMessageAuraHandledException('Card activation failed. Temperature needs to be between 0 and 1.');
                        }
                    }
                }
                
                if(feature == CARD_TYPE_AMODL){
                    if(c.get(NAMESPACE+'Type__c') == '' || c.get(NAMESPACE+'Type__c') == null || c.get(NAMESPACE+'Type__c') == AIConstants.AI_MODEL_TYPE_CHAT){
                        String validationCommand = 'Give me the name of account';
                        String validationBody = '{"Account" : {"Name" : "Validation Account"}}';
                        //System.debug('connection call validation: '+c);
                        String msg = AIGPTfyCalloutController.validateRequest(validationCommand, validationBody, (AI_Connection__c)c);
                        if(String.isNotBlank(msg)){
                            hasError = true;
                            throw AIUtility.getMessageAuraHandledException('Card activation failed. Unable to perform a successfull validation with AI. Error: '+msg);
                        }
                    }else if(!String.isBlank((String)c.get(NAMESPACE+'Type__c')) && c.get(NAMESPACE+'Type__c') == AIConstants.AI_MODEL_TYPE_AGENTIC){//JIRA V2-7410 : Enhance Validation/Handshake process for Agentic
                        String msg = AIGPTfyCalloutController.validateVoiceRequest((AI_Connection__c)c);
                        if(String.isNotBlank(msg)){
                            hasError = true;
                            throw AIUtility.getMessageAuraHandledException('Card activation failed. Unable to perform a successfull validation with AI. Error: '+msg);
                        }
                    }
                }
                
            }else if(records.size() > 1){
                hasError = true;
                throw AIUtility.getMessageAuraHandledException('Sorry, we\'ve detected duplicate connections. Please review your connections and remove any duplicates.');
            }
            if(!hasError){
                AI_Card_Configuration__c oCardConfiguration = mdt[0];
                oCardConfiguration.Enabled__c = true;
                FLSCheck.getInstance().updateDML(new List<AI_Card_Configuration__c>{oCardConfiguration});
            }
        }catch(Exception ex){
            // Jira v2/7832 : Improve AI Model (Connections) for Enhanced Troubleshooting
            if(records.size() > 0){
                supportData += '\n Record: '+JSON.serialize(records[0]);
            }
            String logId = GPTfyException.log(ex, 'GPTfy', '', 'AddCardController', 'handleCardActivate', supportData);
            String logUrl = String.isNotBlank(logId) ? URL.getOrgDomainUrl().toExternalForm() + '/' + logId : '';
            String errorMessage = ex.getMessage();
            if(String.isNotBlank(logUrl)){
                errorMessage += ' ' + logUrl;
            }
            return errorMessage;
        }
        return null;
    }
    
    @testvisible
    private static Boolean insertPicklistValue(String objectName, String fieldName, String fieldValue) {
        boolean hasAdded = false;       
        
        Set<String> setPicklistValues = getPicklistFieldValues(objectName, fieldName);
        
        if(!setPicklistValues.contains(fieldValue)){
            MetadataService.MetadataPort service = createService(); 
            
            MetadataService.CustomField customField;
            if(!Test.isRunningTest()){
                customField =  (MetadataService.CustomField) service.readMetadata('CustomField', new String[] { objectName+'.'+fieldName }).getRecords()[0];       
            }else{
                customField = new MetadataService.CustomField();
                MetadataService.ValueSetValuesDefinition valueSetDefinition = new MetadataService.ValueSetValuesDefinition();
                valueSetDefinition.value = new List<MetadataService.CustomValue>();
				customField.valueSet = new MetadataService.ValueSet();
                customField.valueSet.valueSetDefinition = valueSetDefinition;
            }
            MetadataService.CustomValue newVal = new MetadataService.CustomValue();
            newVal.label = fieldValue;
            newVal.fullName = fieldValue;
            newVal.default_x = false; 
            customField.valueSet.valueSetDefinition.value.add(newVal);
            
            MetadataService.SaveResult[] result = service.updateMetadata(new MetadataService.Metadata[] { customField });
            
            hasAdded = (!Test.isRunningTest()?result[0].success:true);
        }else{
            hasAdded = true;
        }        
        return hasAdded;
    }

    public static Set<String> getPicklistFieldValues(String objectName, String fieldName) {
        Set<String> setPicklistValues = new Set<String>();
        // Describe the SObject
        Schema.DescribeSObjectResult describeSObjectResult = Schema.getGlobalDescribe().get(objectName).getDescribe();
        // Retrieve the specified field
        Schema.DescribeFieldResult fieldResult = describeSObjectResult.fields.getMap().get(fieldName).getDescribe();
        // Check if the field type is picklist
        if (fieldResult.getType() == Schema.DisplayType.MultiPicklist) {
            List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
            for (Schema.PicklistEntry entry : picklistValues) {
                setPicklistValues.add(entry.getValue());
            }
        }
        return setPicklistValues;
    }
    
    public static MetadataService.MetadataPort createService() {
        MetadataService.MetadataPort service = new MetadataService.MetadataPort();
        service.timeout_x = 120000;
        service.SessionHeader = new MetadataService.SessionHeader_element();
        service.SessionHeader.sessionId = fetchUserSessionIdUsingVF(); 
        
        return service;
    }
    
    public static String fetchUserSessionIdUsingVF(){
        try{
            PageReference reportPage = Page.MetadataServiceSession;
            String vfContent = reportPage.getContent().toString();
            Integer startP = vfContent.indexOf('Start_Of_Session_Id') + 'Start_Of_Session_Id'.length();
            Integer endP = vfContent.indexOf('End_Of_Session_Id');
            return vfContent.substring(startP, endP);
        }catch(Exception ex){
            System.debug('Unable to generate a session Id.');
        }
        return null;
    }
    
    private static Map<String, Map<String, List<AI_Prompt__c>>> getMatricsOne(Set<String> setPurpose,String feature){
        Map<String, Map<String, List<AI_Prompt__c>>> mapMatrics = new Map<String, Map<String, List<AI_Prompt__c>>>();
        
        String SOQL = '';
        String pmtType = AIConstants.AI_PMT_TYPE_AGENTIC;
        if(feature == CARD_TYPE_CTLOG){
            SOQL = 'SELECT Purpose__c, Status__c, Type__c FROM AI_Prompt__c WHERE Purpose__c != null AND Type__c != \''+pmtType+'\' AND Purpose__c INCLUDES (';
        }else{
            SOQL = 'SELECT Purpose__c, Status__c FROM AI_Prompt__c WHERE Purpose__c != null AND Purpose__c INCLUDES (';
        }
        String pickVal = '';
        String glue = '';
        
        for(String str : setPurpose){
            pickVal += glue + '\''+str+'\'';
            glue = ',';
        }
        SOQL += pickVal + ')';
        
        for(AI_Prompt__c ap : database.query(SOQL)){
            List<String> purpose = new List<String>();
            if(ap.Purpose__c.contains(';')){
                purpose = ap.Purpose__c.split(';');
            }else{
                purpose.add(ap.Purpose__c);
            }
            for(String p : purpose){
                if(!mapMatrics.containsKey(p)){
                    mapMatrics.put(p, new Map<String, List<AI_Prompt__c>>());
                }
                if(ap.Status__c == 'Active'){
                    if(!mapMatrics.get(p).containsKey('Active')){
                        mapMatrics.get(p).put('Active', new List<AI_Prompt__c>());
                    }
                    mapMatrics.get(p).get('Active').add(ap);
                }
                if(!mapMatrics.get(p).containsKey('Total')){
                    mapMatrics.get(p).put('Total', new List<AI_Prompt__c>());
                }
                mapMatrics.get(p).get('Total').add(ap);
            }
        }
        return mapMatrics;
    }
    
    private static List<Map<String, Decimal>> getMatricsTwo(Set<String> setPurpose,String feature){
        List<Map<String, Decimal>> lstTotals = new List<Map<String, Decimal>>();
        
        Map<String, Decimal> mapSecondTotal = new Map<String, Decimal>();
        Map<String, Decimal> mapMoneyTotal = new Map<String, Decimal>();
        String SOQL = '';
        String pmtType = AIConstants.AI_PMT_TYPE_AGENTIC;
        if(feature == CARD_TYPE_CTLOG){
            SOQL = 'SELECT AI_Prompt__c, Lifetime_Saving_Seconds__c, Money_Saved__c, AI_Prompt__r.Purpose__c FROM AI_Usage_Tracking__c WHERE AI_Prompt__r.Type__c != \''+pmtType+'\' AND AI_Prompt__r.Purpose__c INCLUDES(';
        }else{
            SOQL = 'SELECT AI_Prompt__c, Lifetime_Saving_Seconds__c, Money_Saved__c, AI_Prompt__r.Purpose__c FROM AI_Usage_Tracking__c WHERE AI_Prompt__r.Purpose__c INCLUDES(';
        }
        String pickVal = '';
        String glue = '';
        
        for(String str : setPurpose){
            pickVal += glue + '\''+str+'\'';
            glue = ',';
        }
        SOQL += pickVal + ')';
        for(AI_Usage_Tracking__c ut : database.query(SOQL)){
            List<String> purpose = new List<String>();
            if(ut.AI_Prompt__r.Purpose__c.contains(';')){
                purpose = ut.AI_Prompt__r.Purpose__c.split(';');
            }else{
                purpose.add(ut.AI_Prompt__r.Purpose__c);
            }
            
            for(String p : purpose){
                if(!mapSecondTotal.containsKey(p)){
                    mapSecondTotal.put(p, ut.Lifetime_Saving_Seconds__c);
                }else{
                    decimal val = mapSecondTotal.get(p);
                    mapSecondTotal.put(p, val+ut.Lifetime_Saving_Seconds__c );
                }
                
                if(!mapMoneyTotal.containsKey(p)){
                    mapMoneyTotal.put(p, ut.Money_Saved__c);
                }else{
                    decimal val = mapMoneyTotal.get(p);
                    mapMoneyTotal.put(p, val+ut.Money_Saved__c );
                }
            }
        }
        
        lstTotals.add(mapSecondTotal);
        lstTotals.add(mapMoneyTotal);
        
        return lstTotals;
    }
    
    /**
     * Retrieves the custom metadata based on the provided metadata ID, enabling access to the corresponding GPTfy card configuration metadata.
     * 
     * @param metadataId The ID of the custom metadata record representing the GPTfy card configuration.
     * @return metadataWrap The custom metadata record containing the configuration details for a specific GPTfy card.
     */
    @AuraEnabled
    public static metadataWrap getCardConfigurationRecord(String cardConfigId){
        return new metadataWrap([SELECT Id, Name, Feature__c, Icon_Source__c, Description__c, Enabled__c, Icon_Details__c, Sequence__c FROM AI_Card_Configuration__c WHERE Id =: cardConfigId LIMIT 1]);
    }
    
    /**
     * Check the static resources name is valid or not.
     * @param resourceName : The resourceName is name of static resource.
     * @return Boolean : if static resources is valid then return true otherwise return false.
     */
    @AuraEnabled
    public static Boolean isExistingStaticResource(String resourceName) {
        if(resourceName.contains(NAMESPACE)){
            resourceName = resourceName.remove(NAMESPACE);
        }
        List<StaticResource> matchingResources = [SELECT Id FROM StaticResource WHERE Name = :resourceName LIMIT 1];
        return !matchingResources.isEmpty();
    }
    
    @AuraEnabled
    public static String getNameSpace(){
        return AIPromptController.getNameSpace();
    }
    
    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        if (result.status != Metadata.DeployStatus.Succeeded) { 
        }
    }
    
    public class dataWrap{
        @AuraEnabled public metadataWrap mdtRecord {get; set;}
        @AuraEnabled public sObject record {get; set;}
        @AuraEnabled public String matrics1 {get; set;}
        @AuraEnabled public String matrics2 {get; set;}
    }
    
    public class metadataWrap{
        @AuraEnabled public String Id {get; set;}
        @AuraEnabled public String MasterLabel {get; set;}
        @AuraEnabled public String Description {get; set;}
        @AuraEnabled public String DeveloperName {get; set;}
        @AuraEnabled public String Card_Type {get; set;}
        @AuraEnabled public String Icon_Details {get; set;}
        @AuraEnabled public String Icon_Source {get; set;}
        @AuraEnabled public decimal Sequence {get; set;}
        @AuraEnabled public boolean Enabled {get; set;}
        
        public metadataWrap(AI_Card_Configuration__c cardConfiguration){
            this.Id = cardConfiguration.Id;
            this.MasterLabel = cardConfiguration.Name;
            this.Description = cardConfiguration.Description__c;
            this.Card_Type = cardConfiguration.Feature__c;
            this.Icon_Details = cardConfiguration.Icon_Details__c;
            this.Icon_Source = cardConfiguration.Icon_Source__c;
            this.Sequence = cardConfiguration.Sequence__c;
            this.Enabled = cardConfiguration.Enabled__c;
        }
    }
}