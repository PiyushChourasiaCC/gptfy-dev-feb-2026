public class SampleVoiceProcessingClass implements AIVoiceProcessingInterface {
    public HttpResponse getProcessedResponse(VoiceProcessingWrapper voiceWrap){
        HttpRequest request = voiceWrap.request;
        request.setMethod('POST');
        request.setTimeout(120000);
        
         String boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
         String body = '';
            body += '--' + boundary + '\r\n';
            body += 'Content-Disposition: form-data; name="model"\r\n\r\n';
            body += 'whisper-1\r\n';
            body += '--' + boundary + '\r\n';
            body += 'Content-Disposition: form-data; name="file"; filename="' + voiceWrap.cv.Title + '.mp3' + '"\r\n';
            body += 'Content-Type: application/octet-stream\r\n\r\n';
            Blob headerBlob = Blob.valueOf(body);
            Blob footerBlob = Blob.valueOf('\r\n--' + boundary + '--');
            List<Blob> blobs = new List<Blob>{ headerBlob,voiceWrap.cv.VersionData,footerBlob };
            List<String> hexStrings = new List<String>();
            for(Blob b : blobs){
                    hexStrings.add(EncodingUtil.convertToHex(b));
            }
            String combinedHex = String.join(hexStrings, '');
            Blob combinedBlob =  EncodingUtil.convertFromHex(combinedHex);
            
             request.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
             request.setBodyAsBlob(combinedBlob);
        
        
        
        
        // Google chirp body
        /*request.setHeader('Content-Type', 'application/json');
                Map<String, Object> requestBody;
                if(voiceWrap.isIOS){
                    requestBody = new Map<String, Object>{
                        'config' => new Map<String, Object>{
                            'languageCode' => 'en-US', 'model' => 'default','enableAutomaticPunctuation' => true, 'encoding' => 'WEBM_OPUS', 'sampleRateHertz' => 48000,
                            'enableSeparateRecognitionPerChannel' => true, 'audioChannelCount' => 2
                        },
                        'audio' => new Map<String, Object>{'content' => EncodingUtil.base64Encode(voiceWrap.cv.VersionData)}
                    };
                }else{
                    requestBody = new Map<String, Object>{
                        'config' => new Map<String, Object>{
                            'languageCode' => 'en-US', 'model' => 'default', 'encoding' => 'WEBM_OPUS','enableAutomaticPunctuation' => true, 'sampleRateHertz' => 48000
                        },
                        'audio' => new Map<String, Object>{'content' => EncodingUtil.base64Encode(voiceWrap.cv.VersionData)}
                    };  
                }
         System.debug(requestBody);
         request.setBody(JSON.serialize(requestBody)); */
         Http api = new Http();
         HttpResponse response = api.send(request);
        
         return response;  
    }
}