public class SampleAIProcessingClass implements AIProcessingInterface {
    
    public HttpResponse getProcessedResponse(AI_Connection__c aiModel, AI_Prompt__c aiPrompt, String promptCommand, String extractedData){
        
        String message = 'Human: '+promptCommand+' '+extractedData+' \nAssistant:';
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
        HttpResponse response = api.send(req);

		return response;        
    }
    
}