public class SampleVoiceConnectorClass implements AIAuthenticationInterface {
    public HttpRequest getAuthenticatedRequest(AI_Connection__c aiModel){
        HttpRequest request = new HttpRequest();
         // Google chirp
        //String endPoint = 'callout:Google_Speech_Connect_General'+aiModel.EndPoint_URL__c;
        // Wishper
        String endPoint = 'callout:OpenAI_Whisper'+aiModel.EndPoint_URL__c;
        request.setEndPoint(endPoint);    
        return request;
    }
}