/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 01-12-2024
* @last modified by  : Rishabh Goel
**/
public with sharing class AILicenseManagerController {
    
    public static final String NAMESPACE = AIPromptController.getNamespace();
    
    @AuraEnabled
    public static List<Object> getLicenses(){
        List<License__mdt> plList = [SELECT Id, DeveloperName, Start_Date__c, End_Date__c, Trial__c, License_Type__c, Usage_Limit__c 
                                     FROM License__mdt 
                                     ORDER BY Trial__c ASC, End_Date__c DESC];
        List<Object> data = new List<Object>();
        if(plList != null && !plList.isEmpty()){
            if(plList.size() == 1 && plList.get(0).Trial__c){
                data.add(getMappedLicense(plList.get(0), 'Active'));
            }else{
                for(License__mdt li : plList){
                    String status = 'Inactive';
                    if(li.Start_Date__c <= Date.today() && (li.End_Date__c >= Date.today() || li.End_Date__c == NULL) && !li.Trial__c){
                    	status = 'Active';
                	}
                    data.add(getMappedLicense(li, status));
                }
            }
        }
        return data;
    }
    
    public static Map<String, Object> getMappedLicense(License__mdt li, String status){
        return new Map<String, Object>{
            'uniqueId' => li.DeveloperName,
            'usageLimit' => (li.Usage_Limit__c != null ? (Integer)li.Usage_Limit__c : 0) + ' AI Callouts/User Every Month',
            'startDate' => li.Start_Date__c,
            'endDate' => li.End_Date__c,
            'licenseType' => li.License_Type__c,
            'status' => status
        };
    }
    
    @AuraEnabled
    public static Map<String, Object> getLicensesForCheck(){
        Map<String, Object> maps = new Map<String, Object>();
        if(!licenceCheckRequired()){
			maps.put('licenseBypass', true);
        }
        maps.put('licenses', getLicenses());
        return maps;
    }
	
    public static Boolean isLicenseAvailable(){
        Date currentDate = Date.today();
        
        if(!licenceCheckRequired()){
			return true;
        }
        
        Integer usageLimit = 0;
        List<License__mdt> lst = [SELECT Id, Usage_Limit__c, Trial__c, Start_Date__c, End_Date__c 
                                  FROM License__mdt 
                                  ORDER BY Usage_Limit__c DESC NULLS LAST
                                  LIMIT 50000];
        if(lst != null && !lst.isEmpty()){
            if(lst.size() == 1 && lst.get(0).Trial__c){
                usageLimit = lst.get(0).Usage_Limit__c != null ? (Integer)lst.get(0).Usage_Limit__c : 0;
            }else{
                for(License__mdt mdt : lst){
                    if(!mdt.Trial__c && mdt.Start_Date__c <= currentDate && mdt.End_Date__c >= currentDate){
                        usageLimit = mdt.Usage_Limit__c != null ? (Integer)mdt.Usage_Limit__c : 0;
                        break;
                    }
                }
            }
        }

        if(usageLimit > 0){
            Integer currentUsage = 0;
            License_Usage__c usg = License_Usage__c.getInstance(UserInfo.getUserId());
            if(usg != null && usg.No_of_Callouts__c != null && usg.No_of_Callouts__c > 0){
                currentUsage = (Integer)usg.No_of_Callouts__c;
                if(usg.Last_Ran_Date__c != null && (usg.Last_Ran_Date__c.month() != System.Today().month() || usg.Last_Ran_Date__c.year() != System.Today().year())){
                    currentUsage = 0;
                }
            }
            if(currentUsage < usageLimit){
                return true;
            }
        }
        
        return false;
    }

    public static void updateLicenseUsage(){
        if(!licenceCheckRequired()){
			return;
        }
        
        License_Usage__c usg = License_Usage__c.getInstance(UserInfo.getUserId());
        if(usg.Id == null){
            usg.No_of_Callouts__c = 1;
            usg.Last_Ran_Date__c = System.today();
            FLSCheck.getInstance().insertDML(new List<License_Usage__c>{usg});
        }else{
            if(usg.Last_Ran_Date__c != null && (usg.Last_Ran_Date__c.month() != System.Today().month() || usg.Last_Ran_Date__c.year() != System.Today().year())){
                usg.No_of_Callouts__c = 0;
            }
            usg.Last_Ran_Date__c = System.today();
            usg.No_of_Callouts__c = usg.No_of_Callouts__c + 1;
            FLSCheck.getInstance().updateDML(new List<License_Usage__c>{usg});
        }
    }
    
    public static Boolean licenceCheckRequired(){
        Set<String> orgTypesToSkipLicenseCheck = new Set<String>{'Developer Edition'};
        Set<String> orgNamesToSkipLicenseCheck = new Set<String>{'PlumCloud Labs Data Masker App', 'PlumCloud Labs GPTfy App', 'Cloud Compliance QA Org'};
        Organization org = [SELECT id, Name, OrganizationType, isSandbox FROM Organization LIMIT 1];
        if(org != null && (org.isSandbox || orgTypesToSkipLicenseCheck.contains(org.OrganizationType) || orgNamesToSkipLicenseCheck.contains(org.Name)) && !Test.isRunningTest()){
            return false;
        }
       	return true;
    }
    
    private static String decryptData(String decryptedData){
        String crtptoPrivateKey = 'UGNMYWJJbmRpYTEyMzQ1Ng==';
        String clearData = '';
        try{
            Blob privateKey = EncodingUtil.base64Decode(crtptoPrivateKey);
            String urlDecodedData = EncodingUtil.urlDecode(decryptedData, 'ASCII');
            Blob base64Data;
            
            base64Data = EncodingUtil.convertFromHex(urlDecodedData);
            Blob  clearText = Crypto.decryptWithManagedIV('AES128', privateKey, base64Data);
            clearData = clearText.toString();
        }catch(Exception e){ 
            clearData = '';
        }  
        return clearData;
    }

    @AuraEnabled
    public static String validateLicenseKey(map<String, Object> dataMap){
        try{
            String message = '';
            if(dataMap.containsKey('licenseKey') && String.isNotBlank(String.valueOf(dataMap.get('licenseKey')))){
                String licenseKey = String.valueOf(dataMap.get('licenseKey'));
                String decryptedLicenseKey = decryptData(licenseKey);
                if(String.isNotBlank(decryptedLicenseKey)){
                    Map<String, Object> mapOfKeyToValue = (Map<String, Object>)JSON.deserializeUntyped(decryptedLicenseKey);
                    if(mapOfKeyToValue != null && !mapOfKeyToValue.isEmpty() && mapOfKeyToValue.containsKey('orgId')){
                        String orgId = String.valueOf(mapOfKeyToValue.get('orgId'));
                        String org18Id = UserInfo.getOrganizationId();
                        String orgId15Char = org18Id.substring(0, 15);
                        if(orgId == org18Id || orgId == orgId15Char){
                            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
                            Metadata.CustomMetadata metaRec = populateMetadataValues(mapOfKeyToValue);
                            mdContainer.addMetadata(metaRec);
                            if(!Test.isRunningTest()){
                                String jId = Metadata.Operations.enqueueDeployment(mdContainer, null);
                            }   
                        }else{
                            message = 'Invalid License Key for this Organization.';
                        }
                    }else{
                        message = 'Invalid Key : Error in reading License Key.';
                    }
                }else{
                    message = 'Invalid Key : Error in reading License Key.';
                }
            }else{
                message = 'License Key not found';
            }
            return message;
        }catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
    }

    public static Metadata.CustomMetadata populateMetadataValues(Map<String, Object> keyDetailsMap){
        Metadata.CustomMetadata metaRec = new Metadata.CustomMetadata();
        String keyId =  String.valueOf(keyDetailsMap.get('recordId'));   
        metaRec.fullName = NAMESPACE+'License__mdt.'+keyId;
        metaRec.label = keyId;   
        
        Metadata.CustomMetadataValue customField1 = new Metadata.CustomMetadataValue();
        customField1.field = NAMESPACE+'Usage_Limit__c';
        customField1.value = Integer.valueOf(keyDetailsMap.get('usageLimit'));
        metaRec.values.add(customField1);

        Metadata.CustomMetadataValue customField2 = new Metadata.CustomMetadataValue();
        customField2.field = NAMESPACE+'Start_Date__c';
        customField2.value = Date.valueOf(String.valueOf(keyDetailsMap.get('startDate')));
        metaRec.values.add(customField2);

        Metadata.CustomMetadataValue customField3 = new Metadata.CustomMetadataValue();
        customField3.field = NAMESPACE+'End_Date__c';
        customField3.value =  Date.valueOf(String.valueOf(keyDetailsMap.get('endDate')));
        metaRec.values.add(customField3);
        
        Metadata.CustomMetadataValue customField4 = new Metadata.CustomMetadataValue();
        customField4.field = NAMESPACE+'License_Type__c';
        customField4.value = String.valueOf(keyDetailsMap.get('licenseType'));
        metaRec.values.add(customField4);
        return metaRec;
    }
    
    /*
    Map<String, Object> tempMap = new Map<String, Object>{
        'usageLimit'=> 100,
        'startDate'=> Date.today(),
        'endDate'=> Date.today().addDays(12),
        'recordId' => 'SAMPLE_ID',
        'orgId' => '00D8d00000AWAOQ',
        'licenseType' => 'Pro'
    };
    String jsonStr = JSON.serializePretty(tempMap);
    String key = AILicenseManagerController.encryptData(jsonStr);
    update new AI_Response__c(
        id = 'a078d000007SWR1AAO', 
        data_original__c = key
    );
    */
    
    public static String encryptData(String clearText){
        String encryptedData = '';
        try{
            Blob privateKey = EncodingUtil.base64Decode('UGNMYWJJbmRpYTEyMzQ1Ng==');
            Blob cipherText = Crypto.encryptWithManagedIV('AES128', privateKey, Blob.valueOf(clearText));
            encryptedData = EncodingUtil.convertToHex(cipherText);
        }catch(Exception e){}
        return encryptedData;
    }

}