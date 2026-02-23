/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 10-30-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AISalesforceExtensionController {
    
    public static String NAMESPACE_PREFIX = AIPromptController.getNameSpace();
    public String recordId;
    
    public String getRecordId() {
        return recordId;
    }
    
    public String getCurrentPackageName() {
        return NAMESPACE_PREFIX;
    }

    public AISalesforceExtensionController(ApexPages.StandardController controller){
    	this.recordId = String.valueOf(controller.getRecord().get('id'));
    }
    
}