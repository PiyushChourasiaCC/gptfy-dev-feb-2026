global class SnP_SparkChatProcessingClass implements AIProcessingInterface {
	
    global HttpResponse getProcessedResponse(AI_Connection__c aiModel, AI_Prompt__c aiPrompt, String promptCommand, String extractedData){
        String query = promptCommand +' : '+extractedData;
        String requestBody = JSON.serialize(new Map<String, Object>{'query' => query});
        
		//Create a named credential with URL as "https://sparkapiextdev.spglobal.com"
		//Store the named credential Developer name in AI Model's Named Credential field
		//Store the endpoint "/sparkchat" in AI Model's Named Endpoint URL field
        String endpoint = 'callout:'+aiModel.Named_Credential__c+aiModel.EndPoint_URL__c;
        
        HTTPRequest req = new HTTPRequest();
        req.setMethod('POST');
        req.setEndpoint(endpoint);
        //req.setHeader('api-key', ''); //Add the key directly in the Named Credential as part of the custom headers
        req.setHeader('Content-Type', 'application/json');
        req.setBody(requestBody);
        HTTPResponse res = new HTTP().send(req);

		return res;        
    }
    
}