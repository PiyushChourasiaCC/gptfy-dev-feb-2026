public with sharing class DataSourceController {
    @AuraEnabled
    public static List<Object> getDataSourceOptions(){
        
        String namespace = AIExtractionFieldMappingController.NAMESPACE;
        
        List<AIExtractionFieldMappingController.PicklistAttributeWrapper> allOptions = AIExtractionFieldMappingController.getPickListValues(namespace+'AI_Data_Source__c', namespace+'Source__c');
        
        Set<String> setOfStaticResources = new Set<String>();
        for(AIExtractionFieldMappingController.PicklistAttributeWrapper opt : allOptions){
            setOfStaticResources.add(opt.value);
        }
        
        List<StaticResource> lstOfResources = [SELECT Id, Description, Name FROM StaticResource WHERE Name IN :setOfStaticResources];
        Map<String, StaticResource> mapOfNameToSR = new Map<String, StaticResource>();
        for(StaticResource sr : lstOfResources){
            mapOfNameToSR.put(sr.Name, sr);
        }
        
        Map<String, String> mapOfSources = new Map<String, String>();
        List<AI_Data_Source__c> lstOfSources = [SELECT Id, Name, Named_Credential__c, Source__c, EndPoint_URL__c FROM AI_Data_Source__c WHERE Source__c != NULL];
        for(AI_Data_Source__c sou : lstOfSources){
            mapOfSources.put(sou.Source__c, sou.Id);
        }
        
        List<Object> cardOptions = new List<Object>();
        for(AIExtractionFieldMappingController.PicklistAttributeWrapper opt : allOptions){
            String resName = opt.value;
            String resUrl = '';
            String resDesc = '';
            if(!mapOfNameToSR.isEmpty() && mapOfNameToSR.containsKey(resName)){
                resUrl = URL.getOrgDomainUrl().toExternalForm()+'/resource/'+namespace+resName;
                resDesc = mapOfNameToSR.get(resName).Description;
            }
            
            String conId = '';
            if(!mapOfSources.isEmpty() && mapOfSources.containsKey(resName)){
                conId = mapOfSources.get(resName);
            }
            
            cardOptions.add(new Map<String, String>{
                'aiLabel' => opt.label, 'aiName' => resName, 'iconUrl' => resUrl, 'aiDesc' => resDesc, 'conId' => conId
                    });
        }
        return cardOptions;
    }
    
    @AuraEnabled
    public static List<FieldSetWrappper> getFields(){
        String namespace = AIExtractionFieldMappingController.NAMESPACE;
        List<FieldSetWrappper> fieldData = new List<FieldSetWrappper>();
        for(Schema.FieldSetMember field : SobjectType.AI_Data_Source__c.FieldSets.AI_Data_Source_Creation_Fields.getFields()){ 
            fieldData.add(new FieldSetWrappper(field, namespace));
        }
        return fieldData; 
    }
}