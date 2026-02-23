/*
 *  @Jira 4487 : Data Context Mapping with Data Cloud Integration
 *  Created By and Date : Sohit Sharma / 17-sept-25
 *  Uses : Data Cloud Integration
*/      
public with sharing class AIDataCloudService {
    
    
    // Method to fetch metadata for entityType=DataModelObject
    public static String getsalesforceAccessToken(GPTfy_Settings__c gptfySetting) {
        String clientid = gptfySetting.Salesforce_Client_Id__c;
        String adminEmail = gptfySetting.Salesforce_Admin_Email__c;
        String tokenUrl = gptfySetting.Salesforce_Domain_URL__c;
        String salesforceAuthNamedCred = gptfySetting.Salesforce_Auth_Named_Credential__c;
        String privateKeyFileContents = retrievePKContent(gptfySetting.Salesforce_Private_Key_File_Id__c);
        String jwtBody = getJWTBody(clientId, adminEmail, tokenUrl);
        String jwt = 'SAMPLE_JWT';
        jwt = getSignedPrivatekey(jwtBody, privateKeyFileContents);
        String accessToken = fetchToken(jwt,salesforceAuthNamedCred);
		Map<String, Object> dataCloudToken = getDataCloudTokenAndDomainURL(accessToken,salesforceAuthNamedCred);
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
    
    static String fetchToken(String jwtValue,String salesforceAuthNamedCred){
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:'+salesforceAuthNamedCred+'/services/oauth2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        Http http = new Http();
        String requestBody = 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' +
                             '&assertion=' + EncodingUtil.urlEncode(jwtValue, 'UTF-8');

        req.setBody(requestBody);
        HTTPResponse res = http.send(req);
        String response = res.getBody();
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(response);
        //System.debug(m.get('access_token'));
        return String.valueOf(m.get('access_token'));
    }
    
    // Method to fetch metadata for entityType=DataModelObject
    public static Map<String, Object> getDataCloudTokenAndDomainURL(String token,String salesforceAuthNamedCred) {
        Map<String, Object> m = new Map<String, Object>();
        // Create the HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:'+salesforceAuthNamedCred+'/services/a360/token');
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
                m = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                return m;
            } else {
                System.debug('Error: ' + res.getStatusCode() + ' - ' + res.getStatus());
                return m;
            }
    }
    
    

    // Method to fetch metadata for entityType=DataModelObject
    public static String fetchDataModelObjects(GPTfy_Settings__c gptfySetting) {
        // Create the HTTP request
            String accessToken = getsalesforceAccessToken(gptfySetting);
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
                return res.getBody(); // You can parse this JSON as needed
            } else {
                System.debug('Error: ' + res.getStatusCode() + ' - ' + res.getStatus());
                return 'Error: ' + res.getBody();
            }
    }
    
    
    // Method to fetch metadata for entityType=DataModelObject
    public static List<Object> fetchDataModelObjectsList(GPTfy_Settings__c gptfySetting) {
        List<Object> metadataList = new List<Object>();
        try {
            // Create the HTTP request
            String accessToken = getsalesforceAccessToken(gptfySetting);
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
        // Create the HTTP request
            String accessToken = getsalesforceAccessToken(gptfySetting);
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
                 // You can parse this JSON as needed
            }
            return metadataList;
    }

}