public class SampleAIProcessingClassFlash2 implements AIProcessingInterface {
    
    public HttpResponse getProcessedResponse(AI_Connection__c aiModel, AI_Prompt__c aiPrompt, String promptCommand, String extractedData){
        
        String message = promptCommand+' '+extractedData;
        Map<String, Object> reqBodymap = new Map<String, Object>{
            'contents' => new Map<String, Object>{
                'role' => 'user',
                'parts' => new List<Object>{
                    new Map<String, Object>{
                        'text' => message
                    }
                }
            }
        };
        String strBody = JSON.serialize(reqBodymap); 
        
        HttpRequest req = new HttpRequest();
        String endpoint = 'callout:'+aiModel.Named_Credential__c+aiModel.EndPoint_URL__c;
        //aiModel.Named_Credential__c = 'Google_Flash_2_0'
        //aiModel.EndPoint_URL__c = /v1/projects/gptfy-ai-playground/locations/us-central1/publishers/google/models/gemini-2.0-flash-exp:streamGenerateContent'
        req.setEndpoint(endPoint);
        
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setBody(strBody);
        Http api = new Http();
        HttpResponse response = api.send(req);
        
        System.debug('body: '+response.getBody());
        System.debug('status: '+response.getStatus());
        System.debug('statusCode: '+response.getStatusCode());
        
    	return response;
    }
    
    /*
    public static HttpResponse processRequest(){
        Map<String, Object> reqBodymap = new Map<String, Object>{
            'contents' => new Map<String, Object>{
                'role' => 'user',
                'parts' => new List<Object>{
                    new Map<String, Object>{
                        'text' => 'Where does sun rises from?'
                    }
                }
            }
        };
        String strBody = JSON.serialize(reqBodymap); 
        
        HttpRequest req = new HttpRequest();
        String endPoint = 'callout:Google_Flash_2_0/v1/projects/gptfy-ai-playground/locations/us-central1/publishers/google/models/gemini-2.0-flash-exp:streamGenerateContent';//+aiModel.EndPoint_URL__c;
        req.setEndpoint(endPoint);
        
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setBody(strBody);
        Http api = new Http();
        HttpResponse response = api.send(req);
        
        System.debug('body: '+response.getBody());
        System.debug('status: '+response.getStatus());
        System.debug('statusCode: '+response.getStatusCode());

		return response; 
    }
	*/
    
}