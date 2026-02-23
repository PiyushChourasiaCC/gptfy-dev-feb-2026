public with sharing class JWTAuthenticationService {
	public static final String NO_FILE_MESSAGE = 'Either the specified file does not exist or you do not have access to it.';
	
    public static Map<String, Object> getAuthenticationDetails(AI_Connection__c aiModel){    
        Map<String, Object> response = new Map<String, Object>();
        Map<String, Object> additionalParamMap;
        if(String.isNotBlank(aiModel.Additional_Parameters__c)){
            try{
                additionalParamMap = (Map<String, Object>)JSON.deserializeUntyped(aiModel.Additional_Parameters__c);
            }catch(Exception e){}
        }
        
        String privateKeyFileId = additionalParamMap != null && additionalParamMap.containsKey('privateKeyFileId') ? String.valueOf(additionalParamMap.get('privateKeyFileId')) : null;
        String clientId = additionalParamMap != null && additionalParamMap.containsKey('clientId') ? String.valueOf(additionalParamMap.get('clientId')) : null; 
        String authUrl = additionalParamMap != null && additionalParamMap.containsKey('authUrl') ? String.valueOf(additionalParamMap.get('authUrl')) : null; 
        String tokenUrl = additionalParamMap != null && additionalParamMap.containsKey('tokenUrl') ? String.valueOf(additionalParamMap.get('tokenUrl')) : null;
        
        String privateKeyFileContent = retrievePKContent(privateKeyFileId);
        if(String.isNotBlank(privateKeyFileContent)){
            response = getAuthenticatedDetail(clientId, authUrl, clientId, privateKeyFileContent, tokenUrl);    
        }else{
            response = new Map<String, Object>{
                'message' => NO_FILE_MESSAGE, 'hasError' => true
            };
        }
        return response;
    }

    private static Map<String, Object> getAuthenticatedDetail(String clientId, String mydomain, String adminEmail, String privateKeyFileContents, String tokenUrl){
        String jwtBody = getJWTBody(clientId, adminEmail, tokenUrl);
        String jwt = 'SAMPLE_JWT';
        if(!Test.isRunningTest()){
            jwt = getSignedPrivatekey(jwtBody, privateKeyFileContents);
        }    
        Map<String, Object> response = fetchToken(jwt, mydomain);     
        return response;
    }

    private static String getSignedPrivatekey(String jwt, String privateKeyFileContents){
        Blob privateKey = EncodingUtil.base64Decode(privateKeyFileContents);
        Blob signature = Crypto.sign('RSA-SHA256', Blob.valueOf(jwt), privateKey);
        jwt += '.' + base64URLencode(signature);  
        return jwt;
    }

    private static String retrievePKContent(String docId){
        List<ContentVersion> lstOfVersions = [SELECT Title, ContentDocumentId, VersionData 
                                              FROM ContentVersion 
                                              WHERE ContentDocumentId =:docId];
        if(lstOfVersions != null && !lstOfVersions.isEmpty()){
            ContentVersion base64Content = lstOfVersions.get(0);
            String keyContents = base64Content.VersionData.tostring();
            keyContents = keyContents.replace('-----BEGIN PRIVATE KEY-----', '');
            keyContents = keyContents.replace('-----END PRIVATE KEY-----', '');
            keyContents = keyContents.replace('\n', ''); 
            return keyContents;
        }
        return null;  
    }

    private static String getJWTBody(String clientId, String adminEmail, String tokenUrl){
        String encoded_JWT_Header = createHeader('RS256');
        String encoded_JWT_Claims_Set = generateJsonBody(clientId, adminEmail, tokenUrl);
        return encoded_JWT_Header + '.' + encoded_JWT_Claims_Set;
    }
    
    private static String createHeader(String algName){
        JSONGenerator header = JSON.createGenerator(false);
        header.writeStartObject();
        header.writeStringField('alg', algName);
        header.writeStringField('typ', 'JWT');
        header.writeEndObject();
        String encodedHeader = base64URLencode(Blob.valueOf(header.getAsString()));
        return encodedHeader;
    }
    
    private static String base64URLencode(Blob input){ 
        String output = encodingUtil.base64Encode(input);
        output = output.replace('+', '-');
        output = output.replace('/', '_');
        while ( output.endsWith('=')){
            output = output.subString(0,output.length()-1);
        }
        return output;
    }

    private static String generateJsonBody(String clientId, String adminEmail, String tokenUrl){
        JSONGenerator body = JSON.createGenerator(false);
        body.writeStartObject();
        body.writeStringField('aud', tokenUrl);
        body.writeStringField('iss', clientId);
        body.writeStringField('sub', clientId);
        
        DateTime rightNow = DateTime.now();
        Long iatTime = rightNow.getTime() / 1000;
        body.writeStringField('iat', String.valueOf(iatTime));
        Long expTime = rightNow.getTime() / 1000 +300;
        body.writeStringField('exp', String.valueOf(expTime));
        body.writeEndObject();
        
        String encodeJWTClaims = base64URLencode(Blob.valueOf(body.getAsString()));        
        return encodeJWTClaims;
    }
    
    private static Map<String, Object> fetchToken(string jwtValue, String mydomain){
        HttpRequest req = new HttpRequest();
        req.setEndpoint(mydomain+'/oauth2/default/v1/token?scope=kensho:app:scribe&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion='+jwtValue);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        Http http = new Http();
        HTTPResponse res = http.send(req);
        String response = res.getBody();
        Map<String, Object> returnResponse;
        JSONParser parser = JSON.createParser(response);
        while (parser.nextToken() != null) {
            if (parser.getCurrentToken() == JSONToken.START_OBJECT) {
                JWTResponse jwtResp = (JWTResponse)parser.readValueAs(JWTResponse.class);
                Boolean hasError = false;
                if(jwtResp.error != null && String.isNotBlank(jwtResp.error)){
                    hasError = true;
                }
                returnResponse = new Map<String, Object>{
                    'hasError' => hasError, 'message' => (jwtResp.error+' ('+jwtResp.error_description+')'), 'accessToken' => jwtResp.access_token
                };
                parser.skipChildren();
            }
        }
        
        return returnResponse;
    }
    
    private with sharing class JWTResponse {
        public String access_token;
        public String instance_url; 
        public String error;
        public String error_description;
    }  
}