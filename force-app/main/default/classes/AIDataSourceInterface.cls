/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 11-23-2023
* @last modified by  : Rishabh Goel
**/
global interface AIDataSourceInterface {
	String getExternalData(AI_Data_Source__c dataSource, String extractedData);  
}