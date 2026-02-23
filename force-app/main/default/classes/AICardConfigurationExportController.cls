/**
 * @description       : 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 27-02-2024
 * @last modified by  : Rishabh Goel
**/
public with sharing class AICardConfigurationExportController {
	
    public static String NAMESPACE_PREFIX = AIPromptController.getNameSpace();
    
    /**
     * Retrieves the name of the current package, providing information about the package context within Salesforce.
     * 
     * @return String The name of the current package, indicating the package in which the method is being executed.
    */
    public String getCurrentPackageName() {
        return NAMESPACE_PREFIX;
    }
    
    public static String requestType{get;set;}
    public AICardConfigurationExportController() {
        requestType = ApexPages.currentPage().getParameters().get('type');
    }
    
    /**
     * Navigates to the designated list view, providing a PageReference object for redirecting to the specified list view within the Salesforce platform.
     * 
     * @return PageReference A PageReference object representing the navigation to the designated list view.
    */
    public PageReference navigateToListView(){
        Schema.DescribeSObjectResult result = AI_Card_Configuration__c.SObjectType.getDescribe(); 
        PageReference pageRef = new PageReference('/' + result.getKeyPrefix()); 
  		pageRef.setRedirect(true); 
        return pageRef;
    }
    
    /**
     * Retrieves the mapping information for exporting data, providing an ExportMappingWrapper object containing the necessary mappings for the export process.
     * 
     * @return ExportMappingWrapper An ExportMappingWrapper object representing the mapping information for data export, ready for further processing or analysis.
     */
    @AuraEnabled
    public static ExportMappingWrapper getMappings(){
        try{
            ExportMappingWrapper wrap = new ExportMappingWrapper();
            wrap.exportedOn = System.today();
            wrap.orgId = UserInfo.getOrganizationId();
            wrap.exportedBy = UserInfo.getName();
            wrap.cardConfigs = getCardConfigurations();
            return wrap;
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AICardConfigurationExportController', 'getMappings', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Retrieves the mapping information for exporting data, providing an ExportMappingWrapper object containing the necessary mappings for the export process.
     * 
     * @return List<ExportMappingWrapper.CardConfigurationWrapper> An ExportMappingWrapper object representing the mapping information for data export, ready for further processing or analysis.
     */
    public static List<ExportMappingWrapper.CardConfigurationWrapper> getCardConfigurations(){
        List<ExportMappingWrapper.CardConfigurationWrapper> lstOfWrapper = new List<ExportMappingWrapper.CardConfigurationWrapper>();
        List<AI_Card_Configuration__c> lst = [SELECT Id, Name, Description__c, Icon_Details__c, Icon_Source__c, Sequence__c, Feature__c, Enabled__c
                                              FROM AI_Card_Configuration__c //WHERE Enabled__c = True
                                              ORDER BY Feature__c, Sequence__c, Name LIMIT 50000];
        if(lst != null && !lst.isEmpty()){
            for(AI_Card_Configuration__c cc : lst){
                ExportMappingWrapper.CardConfigurationWrapper wrap = getMappedWrapper(cc);
                lstOfWrapper.add(wrap);
            }
        }
        return lstOfWrapper;
    }
    
    
    public static ExportMappingWrapper.CardConfigurationWrapper getMappedWrapper(AI_Card_Configuration__c cc){
        ExportMappingWrapper.CardConfigurationWrapper wrap = new ExportMappingWrapper.CardConfigurationWrapper();
        wrap.salesforceId = cc.Id;
        wrap.configName = cc.Name;
        wrap.description = cc.Description__c;
        wrap.iconDetails = cc.Icon_Details__c;
        wrap.iconSource = cc.Icon_Source__c;
        wrap.sequence = cc.Sequence__c != null && cc.Sequence__c > 0 ? (Integer)cc.Sequence__c : 0;
        wrap.feature = cc.Feature__c;  
        wrap.enabled = cc.Enabled__c;
        return wrap;
    }
    
    
    /**
     * Reads and processes the file data provided as a string, extracting relevant information and organizing it into a map for further manipulation or analysis.
     * 
     * @param fileData The string representation of the file data to be processed and organized into a map.
     * @return Map<String, Object> A map where the keys represent data attributes, and the values contain the corresponding extracted information from the file data for further processing or analysis.
    */
    @AuraEnabled
    public static map<string, object> readFileData(String fileData){
        map<string, object> mapOfData = new map<string, object>();
        try{
            ExportMappingWrapper wrap = (ExportMappingWrapper)System.JSON.deserialize(fileData, ExportMappingWrapper.class);
            if(wrap != null){
                if(wrap.cardConfigs != null && !wrap.cardConfigs.isEmpty()){ 
                    mapOfData.put('hasError', false);
                	mapOfData.put('data', wrap);
                }else{
                    mapOfData.put('hasError', true);
                	mapOfData.put('message', 'No Cards in the File to Import.');
                }
            }else{
                mapOfData.put('hasError', true);
                mapOfData.put('message', 'Empty Export File.');
            }

            return mapOfData;
        }catch(Exception e){
            mapOfData.put('hasError', true);
            mapOfData.put('message', e.getMessage());
            GPTfyException.log(e, 'GPTfy', '', 'AICardConfigurationExportController', 'readFileData', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Saves the cards if specified.
     * 
     * @param cards A list of ExportMappingWrapper.CardConfigurationWrapper objects containing the prompts to be saved.
     */
    @AuraEnabled
    public static void saveCards(List<ExportMappingWrapper.CardConfigurationWrapper> cards, Boolean isPostInstall){
        try{
        	insertCards(cards, isPostInstall);
        }catch(Exception e){
            GPTfyException.log(e, 'GPTfy', '', 'AICardConfigurationExportController', 'saveCards', '');
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    public static Map<String, AI_Card_Configuration__c> insertCards(List<ExportMappingWrapper.CardConfigurationWrapper> cards, Boolean isPostInstall){
        Map<String, AI_Card_Configuration__c> mapOfExtIdToCardConfig = new Map<String, AI_Card_Configuration__c>();
        for(ExportMappingWrapper.CardConfigurationWrapper wrap : cards){
            AI_Card_Configuration__c cc = getMappedCardConfig(wrap, isPostInstall);
            mapOfExtIdToCardConfig.put(wrap.salesforceId, cc);
        }
        
        Map<String, SObject> cleanedRecords;
        if(isPostInstall){
            cleanedRecords = FLSCheck.getInstance().upsertDML(mapOfExtIdToCardConfig, true);
        }else{
            cleanedRecords = FLSCheck.getInstance().upsertDML(mapOfExtIdToCardConfig, AI_Card_Configuration__c.Fields.External_Id__c, true);
        }
        for(String key : cleanedRecords.keySet()){
            mapOfExtIdToCardConfig.put(key, (AI_Card_Configuration__c)cleanedRecords.get(key));
        }
        return mapOfExtIdToCardConfig;
    }
    
    public static AI_Card_Configuration__c getMappedCardConfig(ExportMappingWrapper.CardConfigurationWrapper wrap, Boolean isPostInstall){
        AI_Card_Configuration__c cc = new AI_Card_Configuration__c();
       	cc.External_Id__c = wrap.salesforceId;
        cc.Name = wrap.configName;
        cc.Description__c = wrap.description;
        cc.Icon_Details__c = wrap.iconDetails;
        cc.Icon_Source__c = wrap.iconSource;
        cc.Sequence__c = wrap.sequence != null && wrap.sequence > 0 ? (Integer)wrap.sequence : 0;
        cc.Feature__c = wrap.feature;
        if(isPostInstall && wrap.enabled != null && wrap.enabled){
            cc.Enabled__c = true;
        }
        return cc;
    }
    
}