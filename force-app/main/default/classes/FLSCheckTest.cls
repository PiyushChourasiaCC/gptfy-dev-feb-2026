/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class FLSCheckTest {

    static testMethod void test1() {
        List<Contact> cList= new List<Contact>();
        Contact c1 = new Contact();
        c1.email = 'qwe@ewq.com';
        c1.FirstName = 'fName';
        c1.LastName = 'lName';
        cList.add(c1);
        Test.startTest();
            FLSCheck.getInstance().insertDML(cList);
            List<Contact> conList = [SELECT Id , Email, FirstName, LastName FROM Contact];
            for(Contact c : conList){
                c.FirstName='css';
            }
        
        	//FLSCheck.getInstance().updateCheck(new Map<String, Contact>(conList));
            FLSCheck.getInstance().updateDML(conList);
        
        	FLSCheck.getInstance().upsertDML(conList);
        
            Boolean isDelete = FLSCheck.getInstance().deleteDML(conList);
        
            system.assertNotEquals(isDelete, null);
        
        Test.stopTest(); 
    }
}