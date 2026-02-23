@RestResource(urlMapping='/testVoiceTranscript/v1/')
global with sharing class MyRestAPI {

    @HttpPost
    global static String handlePostRequest() {
        try {
            // Call a separate method with the 3 parameters
            /*List<Account> testAccounts = [SELECT Id 
                                                FROM Account 
                                                WHERE id=:accIds];
                                    
            System.debug('Retrieved Accounts: ' + testAccounts);
            for(Account a : testAccounts){
                AudioRecorderController.createContentDocumentLink(cvId, a.Id, isIOS);
            } */
            
            RestRequest req = RestContext.request;
            String body = String.valueOf(req.requestBody.toString());
            System.debug('body: '+body);
            MyResponse mapBody = (MyResponse)JSON.deserialize(body,MyResponse.class); 
            String cdId, accId;
            Boolean isIOS;
            if(mapBody.cdId != ''){
                cdId = mapBody.cdId;
            }
            if(mapBody.accId != ''){
                accId = mapBody.accId;
            }
            if(mapBody.isIOS != null){
                isIOS = mapBody.isIOS;
            }
            System.debug('cdId: '+cdId+', accId: '+accId+', isIOS: '+isIOS);
            List<ContentVersion> cv = [Select Id,ContentDocumentId from ContentVersion where ContentDocumentId=: cdId limit 1];
            AudioRecorderController.createContentDocumentLink(cv[0].Id, accId, isIOS);
           // return new MyResponse('{ "message": "success" } '); // Return the response
           return 'success';
        } catch (Exception e) {
            // Handle errors and return an appropriate response
            return 'Error : ' + e.getMessage();
        }
    }
    
    global class MyResponse {
        global String cdId {get; set;}
        global String accId {get; set;}
        global Boolean isIOS {get; set;}
        global MyResponse(String cdId,String accId,Boolean isIOS){
            this.cdId = cdId;
            this.accId = accId;
            this.isIOS = isIOS;
        }
    }
}