public class openAIConnector implements AIAuthenticationInterface{
  
    public HttpRequest getAuthenticatedRequest(AI_Connection__c aiModel){
        HttpRequest req = new HttpRequest();
       // req.setEndpoint('callout:OpenAI/v1/completions');
        req.setEndpoint('callout:GPTfy/api/gptfyall');
        return req;
    }
    
}