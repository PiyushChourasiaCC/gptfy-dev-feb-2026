/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 01-12-2024
* @last modified by  : Rishabh Goel
**/
@isTest
public class AILicenseManagerControllerTest {
	
    @isTest
    static void getLicensesTestNegative(){
        List<Object> lstOfLicenses1 = AILicenseManagerController.getLicenses();
        License_Usage__c usg = License_Usage__c.getInstance(UserInfo.getUserId());
        usg.No_of_Callouts__c = 1;
        usg.Last_Ran_Date__c = System.today();
        INSERT usg;
        
        List<Object> lstOfLicenses2 = AILicenseManagerController.getLicenses();
        Boolean licenseCheck = AILicenseManagerController.isLicenseAvailable();
        AILicenseManagerController.updateLicenseUsage();
        
        Map<String, Object> tempMap = new Map<String, Object>{
            'usageLimit'=> 100,
            'startDate'=> Date.today().addDays(-10),
            'endDate'=> Date.today().addDays(10),
            'recordId' => 'SAMPLE_ID',
            'orgId' => UserInfo.getOrganizationId(),
            'licenseType' => 'Pro'
        };
        String jsonStr = JSON.serializePretty(tempMap);
        String licenseKey = AILicenseManagerController.encryptData(jsonStr);
		
        Test.startTest();
        String message = AILicenseManagerController.validateLicenseKey(new map<String, Object>{'licenseKey' => licenseKey});
        Test.stopTest();
        System.assert(String.isBlank(message));
    }
    
    
    @isTest
    static void getLicensesTest(){
        
        List<Object> lstOfLicenses = AILicenseManagerController.getLicenses();
        Boolean licenseCheck = AILicenseManagerController.isLicenseAvailable();
        AILicenseManagerController.updateLicenseUsage();
        
        Map<String, Object> tempMap = new Map<String, Object>{
            'usageLimit'=> 100,
            'startDate'=> Date.today().addDays(-10),
            'endDate'=> Date.today().addDays(10),
            'recordId' => 'SAMPLE_ID',
            'orgId' => UserInfo.getOrganizationId(),
            'licenseType' => 'Pro'
        };
        String jsonStr = JSON.serializePretty(tempMap);
        String licenseKey = AILicenseManagerController.encryptData(jsonStr);
		
        Test.startTest();
        String message = AILicenseManagerController.validateLicenseKey(new map<String, Object>{'licenseKey' => licenseKey});
        Test.stopTest();
        System.assert(String.isBlank(message));
    }
}