public class SampleTestClass {

    public static final String endpoint = 'https://scribe.kensho.com/api/v2/transcription';
    public static final String BOUNDARY = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
	public static final String EXTRABOUNDARY = '--' + BOUNDARY;
    
    public static void sendFileToKensho6(String authToken, String cdId) {
        ContentVersion cv = [SELECT Id, Title, VersionData,fileType,VersionDataUrl, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId =:cdId];
         HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint); // Replace with the actual endpoint
        req.setMethod('POST');
        
        // Set the headers
        req.setHeader('Authorization', 'Bearer YOUR_ACCESS_TOKEN'); // Replace with your actual token
        req.setHeader('Content-Type', 'multipart/form-data; boundary=boundary_string'); // Use a custom boundary string
        
        // Create the multipart body
        String boundary = '--boundary_string'; // The same boundary string used in Content-Type
        string body = '';

        // Add the file data in the correct multipart format
        body += boundary + '\n';
        body += 'Content-Disposition: form-data; name="file"; filename="' + cv.Title + '"\n';
        body += 'Content-Type: audio/webm\n\n';
        body += cv.VersionData.toString() + '\n'; // File content

        // Close the boundary
        body += boundary + '--';

        // Set the body of the request
        req.setBody(body.toString());
        
        // Send the request
        Http http = new Http();
        HttpResponse response = http.send(req);
        System.debug('body: '+response.getBody());
        System.debug('status: '+response.getStatus());
        System.debug('statusCode: '+response.getStatusCode());
    }
    
    public static void sendFileToKensho(String authToken, String cdId){
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId =:cdId];
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'multipart/form-data; boundary='+BOUNDARY);
        req.setHeader('Authorization', 'Bearer '+authToken);
        String formBody = 'media='+EncodingUtil.base64Encode(cv.VersionData);
        req.setHeader('Content-Disposition', 'form-data; name="media"; filename="audio.mp3"');
        req.setBody(formBody);
		//req.setBodyAsBlob(cv.VersionData);
        Http http = new Http();
        HttpResponse response = http.send(req);
        System.debug('body: '+response.getBody());
        System.debug('status: '+response.getStatus());
        System.debug('statusCode: '+response.getStatusCode());
        /*
        ContentVersion cv = [SELECT Id, Title, VersionData,fileType,VersionDataUrl, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId =:cdId];
        System.debug(cv);
        String fileName = cv.Title+'.mp3';
        Blob file = cv.VersionData;
        */
        /*String contentType = 'audio/mpeg';
        String bodyHex = EncodingUtil.convertToHex(Blob.valueOf(EXTRABOUNDARY + '\r\nContent-Disposition: form-data; name="media"; filename="audio1.mp3"\r\nContent-Type: ' + contentType + '\r\n\r\n'));
        bodyHex += EncodingUtil.convertToHex(file);
        bodyHex += EncodingUtil.convertToHex(Blob.valueOf('\r\n' + EXTRABOUNDARY ));
        Blob b = EncodingUtil.convertFromHex(bodyHex); */
        
        /* String boundary = '--------------------------887272062520970998138428';
          String header = '--'+boundary+'\n';
              header += 'Content-Disposition: form-data; name="data"; filename="'+fileName +'"\nContent-Type: application/octet-stream\n\n';
         
         // String footer = '\n--'+boundary+'--';
         String bodyStart = '--' + boundary + '\r\n' +
                               'Content-Disposition: form-data; name="media"; filename="' + cv.Title + '"\r\n' +
                               'Content-Type: application/mp3\r\n\r\n';
            String bodyEnd = '\r\n--' + boundary + '--\r\n';

            
            Blob bodyStartBlob = Blob.valueOf(bodyStart);
            Blob bodyEndBlob = Blob.valueOf(bodyEnd); */

        //String finalBody = EncodingUtil.convertToHex(bodyStartBlob) + EncodingUtil.convertToHex(file) + EncodingUtil.convertToHex(bodyEndBlob);
        // System.debug(finalBody);
		//Blob combinedDataAsBlob = EncodingUtil.convertFromHex(finalBody);
       // HttpRequest req = new HttpRequest();
       // req.setHeader('Accept', '*/*');
       // req.setHeader('Content-Type','application/json');
        //req.setHeader('Content-Type', 'multipart/form-data; '+boundary);
        //req.setHeader('Content-Type','multipart/form-data; boundary='+boundary);
        //req.setHeader('Content-Disposition', 'form-data; name="media"; filename="audio.mp3"');
       // req.setHeader('Content-Type', contentType);
        //req.setHeader('Content-Length', '196');
      //  req.setHeader('Content-Length',String.valueof(body.length()));
       // req.setMethod('POST');
       // req.setTimeout(120000);
        //req.setHeader('Authorization', 'Bearer '+authToken);
       // req.setEndpoint(endpoint);
        //req.setBodyAsBlob(file);
       // req.setBody(cv.VersionDataUrl);
        
       /* map<string, object> mapToSerialize = new map<string, object>();
        mapToSerialize.put('media_url', 'https://sgpt-dev-dev-ed.develop.lightning.force.com/');
        string jsonstring = JSON.serialize(mapToSerialize);
        req.setBody(jsonstring); */
        //Http h = new Http();
        //HttpResponse response = h.send(req);

       // System.debug('body: '+response.getBody());
        //System.debug('status: '+response.getStatus());
        //System.debug('statusCode: '+response.getStatusCode());
    }
    
    public static void sendFileToKensho2(String authToken, String cdId){
        ContentVersion cv = [SELECT Id, Title, VersionData,ContentSize, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId =:cdId];
        
        String fileName = cv.Title+'.mp3';
        Blob file = cv.VersionData;
        String fileContentEncoded = EncodingUtil.base64Encode(file);
        System.debug(file);
        System.debug(fileContentEncoded);
		try {
            // Construct the HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://scribe.kensho.com/api/v2/transcription');
           // req.setEndpoint('https://210d5742-6a01-44ab-bc2b-3e41112bcaa2.mock.pstmn.io/postman');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + authToken);
            
            
            
            /*req.setHeader('Content-Type', HttpFormBuilder.GetContentType());
            // Generate form body
            String body = '';
            body += HttpFormBuilder.WriteBoundary();
            body += HttpFormBuilder.WriteBodyParameter('media', fileContentEncoded);
            body += HttpFormBuilder.WriteBoundary(HttpFormBuilder.EndingType.CrLf);
         
            Blob formBlob = EncodingUtil.base64Decode(body);
         
            req.setHeader('Content-Length', String.valueOf(formBlob.size()));
            req.setBodyAsBlob(formBlob); */
            
           /* String boundary = '----WebKitFormBoundary7MA4YWxkTrZu1gW';
              String header = '--'+boundary+'\n' + 'Content-Disposition: form-data; name="media"; filename=\"'+fileName +'\"\nContent-Type: audio/mp3\n\n';
             
              String footer = '\n--'+boundary+'--';
               
              String body = EncodingUtil.base64Encode(file); //encodes the blob into a base64 encoded String
               
              body = header + body + footer;
            
             req.setBody(body);
              req.setTimeout(60000);
              req.setHeader('Content-Length',String.valueof(body.length())); */
            
            
   
           /* // hexa method
            String contentType = 'audio/webm';
            String bodyHex = EncodingUtil.convertToHex(Blob.valueOf(EXTRABOUNDARY + '\r\nContent-Disposition: form-data; name="media"; filename="recording (3).webm"\r\nContent-Type: ' + contentType + '\r\n\r\n'));
            bodyHex += EncodingUtil.convertToHex(file);
            bodyHex += EncodingUtil.convertToHex(Blob.valueOf('\r\n' + EXTRABOUNDARY ));
            Blob b = EncodingUtil.convertFromHex(bodyHex); 
            
            req.setBodyAsBlob(b); */
            
            // Boundary for multipart form-data
          //  String boundary = '--------------------------' + EncodingUtil.urlEncode(String.valueOf(DateTime.now().getTime()), 'UTF-8');
            String boundary = '----WebKitFormBoundary7MA4YWxkTrZu1gW';
            
            // Construct the body
            String body = '--' + boundary + '\r\n' +
                          'Content-Disposition: form-data; name=\"media\"; filename=\"[PROXY]\"\r\n' +
                          'Content-Type: audio/webm\r\n\r\n' +
                          EncodingUtil.base64Encode(file) + '\r\n' +
                          '--' + boundary + '--\r\n';
			System.debug(body);
            System.debug(String.valueof(body.length()));
            req.setBody(body);  
          // req.setHeader('Content-Length','196');
           // req.setBodyAsBlob(Blob.valueOf(body));
          //  req.setBody(EncodingUtil.base64Encode(file));
            
            
            // 1st method
            req.setHeader('Content-Type', 'multipart/form-data; boundary='+boundary);
            req.setHeader('Accept', '*/*');
            req.setHeader('Content-Disposition', 'form-data; name="media"; filename=\"'+filename+'\"');
           // req.setHeader('Content-Type', 'audio/webm');
        	//req.setBodyAsBlob(file);
            
            
        	//
        	//
        	/*  try 2nd method
        	 * String boundary = '__boundary__xxx';
			String header = '--'+boundary+'\n'
  							 + 'Content-Disposition: form-data; name="media"; filename="'+fileName
   								+'"\nContent-Type: application/json';
            String footer = '\n--'+boundary+'--';
        	String encoded = EncodingUtil.base64Encode(Blob.valueOf(header))+EncodingUtil.base64Encode(file)+EncodingUtil.base64Encode(Blob.valueOf(footer));
 			req.setBodyAsBlob(EncodingUtil.base64Decode(encoded)); */
        	
        	//req.setBodyAsBlob(file);
        	//req.setBody(fileContentEncoded);
            // Send the request
            System.debug(req);
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            // Process the response
            if (response.getStatusCode() == 200) {
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                System.debug('jsonResponse: '+jsonResponse);
                System.debug('body: '+response.getBody());
                System.debug('status: '+response.getStatus());
                System.debug('statusCode: '+response.getStatusCode());
            } else {
                System.debug('Failed to transcribe: ' + response.getBody());
            }
        } catch (Exception e) {
            System.debug('Exception occurred: ' + e.getMessage());

        }
        
        
    }
    
    
     public static void sendTranscriptionRequest(String authToken, String cdId) {
         ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId =:cdId];
        
       // String fileName = cv.Title+'.webm';
        Blob file = cv.VersionData;
        Http http = new Http();
        HttpRequest req = new HttpRequest();

        // Set endpoint and method
        req.setEndpoint('https://scribe.kensho.com/api/v2/transcription');
        req.setMethod('POST');

        // Set headers
        req.setHeader('Authorization', 'Bearer ' + authToken);
        
        // Boundary for multipart/form-data
        String boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setHeader('Accept', '*/*');

        // File details
        String fileName = 'recording.mp3'; // Use the correct file name and extension
        Blob fileBlob = file; // Replace with actual method to get the Blob content

        // Construct the body with binary data
        String bodyStart = '--' + boundary + '\r\n' +
                           'Content-Disposition: form-data; name="media"; filename="' + fileName + '"\r\n' +
                           'Content-Type: audio/mp3\r\n\r\n';

        String bodyEnd = '\r\n--' + boundary + '--\r\n';
		Blob bodyStartBlob = Blob.valueOf(bodyStart);
        Blob bodyEndBlob = Blob.valueOf(bodyEnd);
        // Combine start, blob, and end
         String fullBody = bodyStart+EncodingUtil.base64Encode(fileBlob)+bodyEnd;
        req.setBody(fullBody);

        // Send the HTTP request
        try {
            HttpResponse response = http.send(req);
            if (response.getStatusCode() == 200) {
                System.debug('Success: ' + response.getBody());
            } else {
                System.debug('Error: ' + response.getStatus() + ' - ' + response.getBody());
            }
        } catch (Exception e) {
            System.debug('Exception: ' + e.getMessage());
        }
    }
    
     public static void sendTranscriptionRequest2(String authToken, String cdId) {
         ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId =:cdId];
        
       // String fileName = cv.Title+'.webm';
        Blob file = cv.VersionData;
        Http http = new Http();
        HttpRequest req = new HttpRequest();

        // Set endpoint and method
        req.setEndpoint('https://scribe.kensho.com/api/v2/transcription');
        req.setMethod('POST');

        // Set headers
        req.setHeader('Authorization', 'Bearer ' + authToken);
        
        // Boundary for multipart/form-data
        //String boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setHeader('Accept', '*/*');

        // File details
        String fileName = 'recording.mp3'; // Use the correct file name and extension
        Blob fileBlob = file; // Replace with actual method to get the Blob content

      // Additional changes commented GW: that fix issue with occasional corruption of files
      String boundary = '----------------------------741e90d31eff';
      String header = '--'+boundary+'\nContent-Disposition: form-data; name="media"; filename="'+filename+'";nContent-Type: audio/mp3';
      // GW: Do not prepend footer with rn, you'll see why in a moment
      // String footer = 'rn--'+boundary+'--'; 
      String footer = '--'+boundary+'--';             
      String headerEncoded = EncodingUtil.base64Encode(Blob.valueOf(header+'\r\n\r\n'));
      while(headerEncoded.endsWith('='))
      {
       header+=' ';
       headerEncoded = EncodingUtil.base64Encode(Blob.valueOf(header+'\r\n\r\n'));
      }
      String bodyEncoded = EncodingUtil.base64Encode(file);
      // GW: Do not encode footer yet
      // String footerEncoded = EncodingUtil.base64Encode(Blob.valueOf(footer));
 
      Blob bodyBlob = null;
      String last4Bytes = bodyEncoded.substring(bodyEncoded.length()-4,bodyEncoded.length());
 
      // GW: Replacing this entire section
      /*
      if(last4Bytes.endsWith('='))
      {
           Blob decoded4Bytes = EncodingUtil.base64Decode(last4Bytes);
           HttpRequest tmp = new HttpRequest();
           tmp.setBodyAsBlob(decoded4Bytes);
           String last4BytesFooter = tmp.getBody()+footer;   
           bodyBlob = EncodingUtil.base64Decode(headerEncoded+bodyEncoded.substring(0,bodyEncoded.length()-4)+EncodingUtil.base64Encode(Blob.valueOf(last4BytesFooter)));
      }
      else
      {
            bodyBlob = EncodingUtil.base64Decode(headerEncoded+bodyEncoded+footerEncoded);
      }
      */
     // GW: replacement section to get rid of padding without corrupting data
     if(last4Bytes.endsWith('==')) {
        // The '==' sequence indicates that the last group contained only one 8 bit byte
        // 8 digit binary representation of CR is 00001101
        // 8 digit binary representation of LF is 00001010
        // Stitch them together and then from the right split them into 6 bit chunks
        // 0000110100001010 becomes 0000 110100 001010
        // Note the first 4 bits 0000 are identical to the padding used to encode the
        // second original 6 bit chunk, this is handy it means we can hard code the response in
        // The decimal values of 110100 001010 are 52 10
        // The base64 mapping values of 52 10 are 0 K
        // See http://en.wikipedia.org/wiki/Base64 for base64 mapping table
        // Therefore, we replace == with 0K
        // Note: if using nn instead of rn replace == with 'oK'
        last4Bytes = last4Bytes.substring(0,2) + '0K';
        bodyEncoded = bodyEncoded.substring(0,bodyEncoded.length()-4) + last4Bytes;
        // We have appended the rn to the Blob, so leave footer as it is.
        String footerEncoded = EncodingUtil.base64Encode(Blob.valueOf(footer));
        bodyBlob = EncodingUtil.base64Decode(headerEncoded+bodyEncoded+footerEncoded);
      } else if(last4Bytes.endsWith('=')) {
        // '=' indicates that encoded data already contained two out of 3x 8 bit bytes
        // We replace final 8 bit byte with a CR e.g. r
        // 8 digit binary representation of CR is 00001101
        // Ignore the first 2 bits of 00 001101 they have already been used up as padding
        // for the existing data.
        // The Decimal value of 001101 is 13
        // The base64 value of 13 is N
        // Therefore, we replace = with N
        // Note: if using n instead of r replace = with 'K'
        last4Bytes = last4Bytes.substring(0,3) + 'N';
        bodyEncoded = bodyEncoded.substring(0,bodyEncoded.length()-4) + last4Bytes;
        // We have appended the CR e.g. r, still need to prepend the line feed to the footer
        footer = '\n' + footer;
        String footerEncoded = EncodingUtil.base64Encode(Blob.valueOf(footer));
        bodyBlob = EncodingUtil.base64Decode(headerEncoded+bodyEncoded+footerEncoded);              
      } else {
        // Prepend the CR LF to the footer
        footer = '\r\n' + footer;
        String footerEncoded = EncodingUtil.base64Encode(Blob.valueOf(footer));
        bodyBlob = EncodingUtil.base64Decode(headerEncoded+bodyEncoded+footerEncoded);  
      }
         
         
         
         
        req.setBodyAsBlob(bodyBlob);

        // Send the HTTP request
        try {
            HttpResponse response = http.send(req);
            if (response.getStatusCode() == 200) {
                System.debug('Success: ' + response.getBody());
            } else {
                System.debug('Error: ' + response.getStatus() + ' - ' + response.getBody());
            }
        } catch (Exception e) {
            System.debug('Exception: ' + e.getMessage());
        }
    }
    
    
    
    @AuraEnabled
    public static String generatetoken(){
        
		//String endpoint = 'https://scribe.kensho.com/oauth2/refresh?refresh_token=Qa_DwI8NaodaaOzP1qsUlLIEoLUgVvBeHk8Ae5cGO9U';
        String endpoint = 'callout:kenshoapi/oauth2/refresh?refresh_token=Qa_DwI8NaodaaOzP1qsUlLIEoLUgVvBeHk8Ae5cGO9U';
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(endpoint);
        
        Http http = new Http();
        HttpResponse response = http.send(req);

        System.debug('body: '+response.getBody());
        System.debug('status: '+response.getStatus());
        System.debug('statusCode: '+response.getStatusCode());
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        System.debug(m.get('access_token'));
        return String.valueOf(m.get('access_token'));
    }
    
    public static void createPublicUrl(String authToken,String cdId){
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId =:cdId];
         ContentDistribution cd = new ContentDistribution();
            
                    cd.Name = 'Test2';
                    
                    cd.ContentVersionId = cv.id;
                    
                    cd.PreferencesAllowViewInBrowser= true;
                    
                    cd.PreferencesLinkLatestVersion=true;
                    
                    cd.PreferencesNotifyOnVisit=false;
                    
                    cd.PreferencesPasswordRequired=false;
                    
                    cd.PreferencesAllowOriginalDownload= true;
                    cd.expirydate = System.now().addhours(1);
        			cd.preferencesExpires = true;
                    insert cd;
                    
                    cd = [Select id,DistributionPublicUrl, ContentDownloadUrl,createddate from ContentDistribution where id=:cd.Id];
                    System.debug(cd);
           testurlkensho(authToken,cd.ContentDownloadUrl);
    }
    
     @future(callout=true)
     public static void testurlkensho(String authToken,String publicUrl){
         System.debug('public URL');
         System.debug(publicUrl);
        /* ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId =:cdId];
         Savepoint sp = Database.setSavepoint();
         
         ContentDistribution cd = new ContentDistribution();
            
                    cd.Name = 'Test2';
                    cd.ContentVersionId = cv.id;
                    cd.PreferencesAllowViewInBrowser= true;
                    cd.PreferencesLinkLatestVersion=true;
                    cd.PreferencesNotifyOnVisit=false;
                    cd.PreferencesPasswordRequired=false;
                    cd.PreferencesAllowOriginalDownload= true;
                    
                    insert cd;
                    
                    cd = [Select id,DistributionPublicUrl, ContentDownloadUrl,createddate from ContentDistribution where id=:cd.Id];
                    System.debug(cd); */
            
            try {
                // Call external service...
                 
                 
                 
                     Http http = new Http();
                    HttpRequest req = new HttpRequest();
                     
            
                    // Set endpoint and method
                    req.setEndpoint('https://scribe.kensho.com/api/v2/transcription');
                    req.setMethod('POST');
            
                    // Set headers
                    req.setHeader('Authorization', 'Bearer ' + authToken);
                    req.setHeader('Content-Type', 'application/json');
                    Map<String, Object> requestBody = new Map<String, Object>{
                                        'media_url' => publicUrl
                                    };  
                          
                     req.setBody(JSON.serialize(requestBody));
                   // Database.releaseSavepoint(sp);
                    HttpResponse response = http.send(req);
            
                    System.debug('body: '+response.getBody());
                    System.debug('status: '+response.getStatus());
                    System.debug('statusCode: '+response.getStatusCode());
                    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    System.debug(m);
                
                String transcriptId = String.valueOf(m.get('transcription_id'));
                String endpoint = 'https://scribe.kensho.com/api/v2/transcription/'+transcriptId;
                HttpRequest req2 = new HttpRequest();
                req2.setMethod('GET');
                req2.setEndpoint(endpoint);
                req2.setHeader('Authorization', 'Bearer ' + authToken);
                Http http2 = new Http();
                HttpResponse response2 = http2.send(req2);
        
                System.debug('body: '+response2.getBody());
                System.debug('status: '+response2.getStatus());
                System.debug('statusCode: '+response2.getStatusCode());
                
                
            } catch (Exception e) {
               // Database.rollback(sp);
               // Database.releaseSavepoint(sp);
            }
       
    }
    
    @AuraEnabled
    public static String sendblobTojs(){ 
         ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId = '069J7000002zRWYIA2'];
        return EncodingUtil.base64Encode(cv.VersionData);
    }
    
    public static void sendFileToGCPBucket(String fileName, Blob fileBody){
        String bucketName = 'gcp-voice-api-demo';
        String endpoint = 'callout:Google_DataStore/upload/storage/v1/b/' + bucketName + '/o?uploadType=media&name=' + fileName;
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/octet-stream');
        req.setHeader('Content-Length', String.valueOf(fileBody.size()));
        req.setBodyAsBlob(fileBody);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            System.debug('File uploaded successfully: ' + res.getBody());
        } else {
            System.debug('Failed to upload file: ' + res.getBody());
        }
    }
    
    public static String asyncSubmitFileForTranscript(){
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Google_Speech_Connect_General/v1/speech:longrunningrecognize');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        String requestBody = '{"config": {"encoding":"MP3", "languageCode": "en-US", "sampleRateHertz":48000}, "audio": {"uri":"gs://gcp-voice-api-demo/HowDoSalesforceEinsteinPlatformBotsWork.mp3"}}';
        req.setBody(requestBody);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            return res.getBody(); // Process transcription result
        } else {
            throw new CalloutException('Error during transcription: ' + res.getBody());
        }
    }
    
    public static String asyncGetTranscriptForFile(String asyncJobId){
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setTimeout(120000);
        String endPoint = 'callout:Google_Speech_Connect_General/v1/operations/'+asyncJobId;
        request.setEndpoint(endPoint);
        HttpResponse response = http.send(request);
        System.debug('body: '+response.getBody());
        System.debug('status: '+response.getStatus());
        System.debug('statusCode: '+response.getStatusCode());
        return response.getBody();
    }
}