@RestResource(urlMapping='/v1/generatePublicURL/*')
global with sharing class AISalesforcePublicURLGeneratorService {

    @HttpPost
    global static ResponseWrapper runRequest(){
        ResponseWrapper ret_wrap = new ResponseWrapper();
        RestRequest req = RestContext.request; 
        try{
            String jsonBody = req.requestBody.toString();
            if(String.isNotBlank(jsonBody)){
                RequestWrapper wrap = (RequestWrapper)JSON.deserializeStrict(jsonBody, RequestWrapper.class);
                ContentDistribution cd = new ContentDistribution();
                cd.Name = wrap.cvId;
                cd.ContentVersionId = wrap.cvId;
                cd.PreferencesAllowViewInBrowser = true;
                cd.PreferencesLinkLatestVersion = true;
                cd.PreferencesNotifyOnVisit = false;
                cd.PreferencesPasswordRequired = false;
                cd.PreferencesAllowOriginalDownload = true;
                cd.expirydate = System.now().addhours(1);
                cd.preferencesExpires = true;
                cd = (ContentDistribution)FLSCheck.getInstance().insertDML(new List<ContentDistribution>{cd}).get(0);
                
                cd = [SELECT Id, ContentDownloadUrl 
                      FROM ContentDistribution 
                      WHERE Id =:cd.Id];
               	ret_wrap.fileUrl = cd.ContentDownloadUrl;
            }
        }catch(Exception e){
            System.debug('e: '+e.getMessage());
        }
        return ret_wrap;
    }
    
    global class RequestWrapper{
        global String cvId{get;set;}
    }
    
    global class ResponseWrapper{
        global String fileUrl{get;set;}
    }
    
}