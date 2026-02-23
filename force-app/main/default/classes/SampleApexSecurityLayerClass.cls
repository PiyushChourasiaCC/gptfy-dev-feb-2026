public class SampleApexSecurityLayerClass implements AIApexSecurityLayerInterface{
    
    public AIApexSecurityLayerDataWrapper getExtractData(AIApexSecurityLayerDataWrapper wrapper){
        Map<String, String> pIIKey = (Map<String, String>)JSON.deserialize(wrapper.response.Data_PII_Key__c, Map<String, String>.class);
        pIIKey.put('489-36-83535566u', 'AP-0874-001');
        pIIKey.put('489-36-83535566u)', 'AP-0874-001');
        wrapper.response.Data_PII_Key__c = JSON.serialize(pIIKey);
        return wrapper;
    } 
    
}