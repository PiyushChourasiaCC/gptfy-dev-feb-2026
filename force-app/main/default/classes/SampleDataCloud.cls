public class SampleDataCloud {
    
    void getDataModelUsingScript(){
        ConnectApi.CdpQueryMetadataOutput data = ConnectApi.CdpQuery.getProfileMetadata('ssot__Account__dlm');
        System.debug(data);
        //System.debug(data.metadata);
        List<Object> listObj = data.metadata;
        for(Object obj : data.metadata){
                 System.debug(obj);
                 //System.debug(obj.get('fields'));
                Map<String,Object> mapObj = (Map<String,Object>) obj;
                //System.debug(mapObj.size());
                List<Object> lo = (List<Object>)mapObj.get('fields');
                System.debug(lo);
        }
    }
    
    
    // Method to fetch metadata for entityType=DataModelObject
    public static String getsalesforceAccessToken() {
        
        //String jwt  = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiIzTVZHOURSRWdpQnFOOVdtNklqdDF6OGhMLjh5WjNuQ1RkVFFmUDl5QldyYVFTX2xwRUhqSUFNbWhUTmZ1ZG45bzFxc3hsZ2JTek81ZnBRSFR3RUNCIiwic3ViIjoic29oaXRAY2xvdWRjb21wbGlhbmNlLmFwcC5zZ3B0LWRldiIsImF1ZCI6Imh0dHBzOi8vc2dwdC1kZXYtZGV2LWVkLmRldmVsb3AubXkuc2FsZXNmb3JjZS5jb20iLCJleHAiOjE3NTMwOTU0Nzl9.sW06MXz6j5tb4skfZ8AISPrfn0djS02YOmDSPhiytosfCkO9k_H5R3jrOCq9bLCCuZ19pa8sL2BYIaEW9db-CIZM_9Rq6QdpVyrjS9CfwXqHVQXx4XqMaUoqM9Bg9c6Qq_NyKwAjHr1vvaDOfOPW-L0q0P2EEyAJbFPwhksyF_RAiJLFa6xNw9SZ-fV09ussCr9BLV7ZfVXL1o7s5EVWj86SR4mQqVpCGgPYVvJDw2nvMOBqQPHweb9CP7os6Ne_3YRpcPySaBXOTCtxLdehPxkyvtzmIp5P912CMuvL4uwGrVVeuLaLQfX6ZtTZEdfhmg_C0jlD06M8eCQmUPv8ng';
		String clientid = '3MVG9DREgiBqN9Wm6Ijt1z8hL.8yZ3nCTdTQfP9yBWraQS_lpEHjIAMmhTNfudn9o1qsxlgbSzO5fpQHTwECB';
        String adminEmail = 'sohit@cloudcompliance.app.sgpt-dev';
        String tokenUrl = 'https://sgpt-dev-dev-ed.develop.my.salesforce.com';
        String privateKeyFileContents = retrievePKContent('069J7000009a4u6IAA');
        
        String jwtBody = getJWTBody(clientId, adminEmail, tokenUrl);
        String jwt = 'SAMPLE_JWT';
        jwt = getSignedPrivatekey(jwtBody, privateKeyFileContents);
        
        
        String accessToken = fetchToken(jwt);
		Map<String, Object> dataCloudToken = getDataCloudTokenAndDomainURL(accessToken);
        //fetchDataModelObjects(dataCloudToken);
        //fetchDataModelObjectsList(dataCloudToken);
        return String.valueOf(dataCloudToken.get('access_token'));
    }
    
    static String getJWTBody(String clientId, String adminEmail, String tokenUrl){
        String encoded_JWT_Header = createHeader('RS256');
        String encoded_JWT_Claims_Set = generateJsonBody(clientId, adminEmail, tokenUrl);
        return encoded_JWT_Header + '.' + encoded_JWT_Claims_Set;
    }
    
    static String createHeader(String algName){
        JSONGenerator header = JSON.createGenerator(false);
        header.writeStartObject();
        header.writeStringField('alg', algName);
        header.writeStringField('typ', 'JWT');
        header.writeEndObject();
        String encodedHeader = base64URLencode(Blob.valueOf(header.getAsString()));
        return encodedHeader;
    }
    
    static String generateJsonBody(String clientId, String adminEmail, String tokenUrl){
        JSONGenerator body = JSON.createGenerator(false);
        body.writeStartObject();
        body.writeStringField('aud', tokenUrl);
        body.writeStringField('iss', clientId);
        body.writeStringField('sub', adminEmail);
        
        DateTime rightNow = DateTime.now();
        Long iatTime = rightNow.getTime() / 1000;
        body.writeStringField('iat', String.valueOf(iatTime));
        Long expTime = rightNow.getTime() / 1000 +300;
        body.writeStringField('exp', String.valueOf(expTime));
        body.writeEndObject();
        
        String encodeJWTClaims = base64URLencode(Blob.valueOf(body.getAsString()));        
        return encodeJWTClaims;
    }
    
    static String base64URLencode(Blob input){ 
        String output = encodingUtil.base64Encode(input);
        output = output.replace('+', '-');
        output = output.replace('/', '_');
        while ( output.endsWith('=')){
            output = output.subString(0,output.length()-1);
        }
        return output;
    }
    
    static String retrievePKContent(String docId){
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
    
    static String getSignedPrivatekey(String jwt, String privateKeyFileContents){
        Blob privateKey = EncodingUtil.base64Decode(privateKeyFileContents);
        Blob signature = Crypto.sign('RSA-SHA256', Blob.valueOf(jwt), privateKey);
        jwt += '.' + base64URLencode(signature);  
        return jwt;
    }
    
    static String fetchToken(String jwtValue){
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Test_SalesforceAuth/services/oauth2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        Http http = new Http();
        String requestBody = 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' +
                             '&assertion=' + EncodingUtil.urlEncode(jwtValue, 'UTF-8');

        req.setBody(requestBody);
        HTTPResponse res = http.send(req);
        String response = res.getBody();
		System.debug('response : ');
        System.debug(response);
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(response);
        System.debug(m.get('access_token'));
        return String.valueOf(m.get('access_token'));
    }
    
    // Method to fetch metadata for entityType=DataModelObject
    public static Map<String, Object> getDataCloudTokenAndDomainURL(String token) {
        //String coreAuthToken = '';
        Map<String, Object> m = new Map<String, Object>();
        try {
            // Create the HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Test_SalesforceAuth/services/a360/token');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            // Construct the body as a URL-encoded string
            String body = 'grant_type=urn:salesforce:grant-type:external:cdp'
                        + '&subject_token='+token+
                        + '&subject_token_type=urn:ietf:params:oauth:token-type:access_token';
            req.setBody(body);

            // Send the HTTP request
            Http http = new Http();
            HttpResponse res = http.send(req);

            // Check the response
            if (res.getStatusCode() == 200) {
                System.debug(res.getBody());
                m = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                System.debug(m.get('access_token'));
                return m;
            } else {
                System.debug('Error: ' + res.getStatusCode() + ' - ' + res.getStatus());
                return m;
            }
        } catch (Exception e) {
            System.debug('Exception: ' + e.getMessage());
            return m;
        }
    }
    
    

    // Method to fetch metadata for entityType=DataModelObject
    public static String fetchDataModelObjects(GPTfy_Settings__c gptfySetting) {
        try {
            // Create the HTTP request
            String accessToken = getsalesforceAccessToken();
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:'+gptfySetting.Data_Cloud_Named_Credentials__c+'/api/v1/metadata?entityType=DataModelObject');
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
			req.setHeader('Authorization', 'Bearer '+accessToken);

            // Send the HTTP request
            Http http = new Http();
            HttpResponse res = http.send(req);

            // Check the response
            if (res.getStatusCode() == 200) {
                System.debug(res.getBody());
                return res.getBody(); // You can parse this JSON as needed
            } else {
                System.debug('Error: ' + res.getStatusCode() + ' - ' + res.getStatus());
                return 'Error: ' + res.getBody();
            }
        } catch (Exception e) {
            System.debug('Exception: ' + e.getMessage());
            return 'Exception: ' + e.getMessage();
        }
    }
    
    
    // Method to fetch metadata for entityType=DataModelObject
    public static List<Object> fetchDataModelObjectsList(GPTfy_Settings__c gptfySetting) {
        List<Object> metadataList = new List<Object>();
        try {
            // Create the HTTP request
            String accessToken = getsalesforceAccessToken();
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:'+gptfySetting.Data_Cloud_Named_Credentials__c+'/api/v1/metadata?entityType=DataModelObject');
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
			req.setHeader('Authorization', 'Bearer '+accessToken);

            // Send the HTTP request
            Http http = new Http();
            HttpResponse res = http.send(req);
			Map<String, String> objNameMap = new Map<String,String>();
            // Check the response
            if (res.getStatusCode() == 200) {
                Map<String, Object> fullResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                // Get metadata list
                metadataList = (List<Object>) fullResponse.get('metadata');
        
                
                System.debug('object List :');
                System.debug(objNameMap);
                return metadataList; // You can parse this JSON as needed
            } else {
                System.debug('Error: ' + res.getStatusCode() + ' - ' + res.getStatus());
                return metadataList;
            }
        } catch (Exception e) {
            System.debug('Exception: ' + e.getMessage());
            return metadataList;
        }
    }
    
    
    // Method to fetch metadata for entityType=DataModelObject
    public static List<Object> fetchDataCloudFieldList(GPTfy_Settings__c gptfySetting,String dmoApiName) {
        List<Object> metadataList = new List<Object>();
        try {
            // Create the HTTP request
            String accessToken = getsalesforceAccessToken();
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:'+gptfySetting.Data_Cloud_Named_Credentials__c+'/api/v1/profile/metadata/'+dmoApiName);
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
			req.setHeader('Authorization', 'Bearer '+accessToken);

            // Send the HTTP request
            Http http = new Http();
            HttpResponse res = http.send(req);
			Map<String, String> objNameMap = new Map<String,String>();
            // Check the response
            if (res.getStatusCode() == 200) {
                Map<String, Object> fullResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                // Get metadata list
                metadataList = (List<Object>) fullResponse.get('metadata');
                return metadataList; // You can parse this JSON as needed
            } else {
                System.debug('Error: ' + res.getStatusCode() + ' - ' + res.getStatus());
                return metadataList;
            }
        } catch (Exception e) {
            System.debug('Exception: ' + e.getMessage());
            return metadataList;
        }
    }
}