public class SampleDataSourceClass implements AIDataSourceInterface{
    
    public String getExternalData(AI_Data_Source__c dataSource, String extractedData){
        Map<String, Object> mainMap = (Map<String, Object>)JSON.deserializeUntyped(extractedData);
        if(mainMap.containsKey('Website') && mainMap.get('Website') != null){ //getting the website from the account extracted data.
             String apiData = SampleDataSourceClass.connectToExplorium(String.valueOf(mainMap.get('Website'))); //calling the explorium to get the information using the website.
            if(String.isNotBlank(apiData)){
                List<Object> apiDataList = (List<Object>)JSON.deserializeUntyped(apiData); //parsing the data returned from Explorium.
                if(apiDataList != null && !apiDataList.isEmpty()){
                    Map<String, Object> apiDataMap = (Map<String,Object>)apiDataList.get(0);
                    for(String key : apiDataMap.keySet()){
                        if(key == 'Business description'){
                            mainMap.put('Description', String.valueOf(apiDataMap.get(key))); //adding the description returned from Explorium to AI for processing.
                        }
                    }
                }
            }
        }
        return JSON.serialize(mainMap);
    }
    
    public static String connectToExplorium(String sourceUrl){
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Explorium'); //create a named credential for the external system you are calling
        request.setMethod('POST');

        request.setHeader('accept', 'application/json');
        request.setHeader('content-type', 'application/json');
        
        List<requestBody> lstObj = new List<requestBody>();
        lstObj.add(new requestBody(sourceUrl)); //passing the website URL
        String body = JSON.serialize(lstObj);
        
        request.setBody(body);

        Http http = new Http();
        HttpResponse response = http.send(request);
        System.debug('body: '+response.getBody());
        System.debug('status: '+response.getStatus());
        System.debug('statusCode: '+response.getStatusCode());
        return response.getBody();
    }
    
    public class requestBody{
        public String url {get; set;}
        public requestBody(String url){
            this.url = url;
        }
    }
}