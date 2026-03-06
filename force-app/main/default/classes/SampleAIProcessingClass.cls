public class SampleAIProcessingClass implements AIProcessingInterface {
    
    public HttpResponse getProcessedResponse(AI_Connection__c aiModel, AI_Prompt__c aiPrompt, String promptCommand, String extractedData){
        
        /*String message = 'Human: '+promptCommand+' '+extractedData+' \nAssistant:';
        Map<String, Object> reqBodymap = new Map<String, Object>{
            'prompt' => message,
            'max_tokens_to_sample' => aiModel.Max_Tokens__c,
            'temperature' => aiModel.Temperature__c,
            'top_p' => aiModel.Top_P__c
        };
        String strBody = JSON.serialize(reqBodymap); 
        
        HttpRequest req = new HttpRequest();
        String endPoint = 'callout:AWSBedrock'+aiModel.EndPoint_URL__c;
        req.setEndpoint(endPoint);
        
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setBody(strBody);
        Http api = new Http();
        HttpResponse response = api.send(req); */
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:SnowflakeDS');  // Replace with your Named Credential name
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);

        Map<String, Object> body = new Map<String, Object>{
            'statement' => 'SELECT * FROM Employee LIMIT 10',
            'timeout' => 60,
            'warehouse' => 'COMPUTE_WH',
            'database' => 'TESTDB',
            'schema' => 'MYSCHEMA',
            'role' => 'SYSADMIN'
        };
        req.setBody(JSON.serialize(body));
		Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() == 200) {
            // Parse response: res.getBody() contains JSON with 'resultSet' for data
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            System.debug('Query Result: ' + response);
        } else {
            System.debug('Error: ' + res.getStatusCode() + ' - ' + res.getBody());
        }

		return res;        
    }
    
}