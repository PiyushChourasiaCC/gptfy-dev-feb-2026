public class SampleAuthClass implements AIAuthenticationInterface{
	
    public HttpRequest getAuthenticatedRequest(AI_Connection__c aiModel){
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:OpenAI/v1/chat/completions');  
        return req;
    }
    
}