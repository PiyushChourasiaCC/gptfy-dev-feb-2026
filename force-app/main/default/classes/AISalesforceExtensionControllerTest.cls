/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 10-30-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public class AISalesforceExtensionControllerTest {
	
    @isTest
    static void controllerTest(){
        Test.StartTest(); 
        Account acc = new Account();
		acc.Name = 'Test Account' ;
		insert acc;
        
        ApexPages.StandardController sc = new ApexPages.StandardController(acc);
        AISalesforceExtensionController obj = new AISalesforceExtensionController(sc);
        String recId = obj.getRecordId();
        obj.getCurrentPackageName();
		Test.StopTest();
        
        System.assert(String.isNotBlank(recId));
    }
    
}