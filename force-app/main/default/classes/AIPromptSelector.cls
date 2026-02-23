/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIPromptSelector {
    
    STATIC FINAL String STATUS_ACTIVE = 'Active';

    static Set<String> getDefaultFields(){
        return new Set<String>{
            'Id',
            'Name',
            'AI_Locale_Automation__c',
            'AI_Locale_GPTfy_Console__c',
            'Prompt_Command__c',
            'AI_Data_Extraction_Mapping__c',
            'Custom_Prompt__c',
            'Max_Output_Tokens__c',
            'Temperature__c',
            'Top_P__c',
            'Target_Field__c',
            'Append_Timestamp__c',
            'Prompt_Version__c',
            'Profiles__c',
            'Grounding_Content__c',
            'Grounding_Ethical__c',
            'How_It_Works__c',    
            'Record_Type__c',
            'Visibility_Condition__c',
            'Object__c',    
            'Message__c',
            'Enable_Loopback__c',
            'Loopback_Message__c', 
            'Type__c', 
            'Status__c',
            'Include_Files__c',
            'Response_Validation_Condition__c',
            'Response_Validation_Message__c',
            'AI_Connection__r.AI_Response_Mapping__c', 
            'AI_Connection__r.AI_Request_Mapping__c',
            'Agentic_Function_Class__c',
            'AI_Data_Extraction_Mapping__r.AI_Data_Source__c, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Connector_Class__c, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Name, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.EndPoint_URL__c, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Named_Credential__c, AI_Data_Extraction_Mapping__r.AI_Data_Source__r.Source__c,AI_Data_Extraction_Mapping__r.Apex_Security_Layer__r.Apex_Class_Name__c, AI_Data_Extraction_Mapping__r.Object_Name__c',
            'AI_Connection__c,AI_Connection__r.Additional_Parameters__c,AI_Connection__r.Version__c,AI_Connection__r.Connector_Class__c,AI_Connection__r.Top_P__c,AI_Connection__r.AI_Technology__c,AI_Connection__r.Name,AI_Connection__r.EndPoint_URL__c,AI_Connection__r.Model__c,AI_Connection__r.Temperature__c,AI_Connection__r.Max_Total_Tokens__c,AI_Connection__r.Max_Tokens__c,AI_Connection__r.Named_Credential__c,AI_Connection__r.Processing_Class__c,AI_Connection__r.Type__c',
            'AI_Model_File_Processing__c,AI_Model_File_Processing__r.Additional_Parameters__c,AI_Model_File_Processing__r.Version__c,AI_Model_File_Processing__r.Connector_Class__c,AI_Model_File_Processing__r.Top_P__c,AI_Model_File_Processing__r.AI_Technology__c,AI_Model_File_Processing__r.Name,AI_Model_File_Processing__r.EndPoint_URL__c,AI_Model_File_Processing__r.Model__c,AI_Model_File_Processing__r.Temperature__c,AI_Model_File_Processing__r.Max_Total_Tokens__c,AI_Model_File_Processing__r.Max_Tokens__c,AI_Model_File_Processing__r.Named_Credential__c,AI_Model_File_Processing__r.Processing_Class__c'
        };
    }

    static String getQueryFieldsString(){
        List<String> queryFieldList = new List<String>(getDefaultFields());
        return String.join(queryFieldList,',');
    }

    public static List<AI_Prompt__c> getAIPromptByObjectId(Id objectId){
        String sObjName = objectId.getSObjectType().getDescribe().getName();
        //String profileId = UserInfo.getProfileId();
        String query = 'SELECT Id,Name,Custom_Prompt__c FROM AI_Prompt__c WHERE Object__c=:sObjName and Status__c=: STATUS_ACTIVE';
        return Database.query(query);
    }


    public static AI_Prompt__c getAIPromptById(Id promptId){
        String query = 'SELECT ' + getQueryFieldsString() + ' FROM AI_Prompt__c WHERE Id=:promptId LIMIT 1';
        List<AI_Prompt__c> aiPromptList = Database.query(query);
        return aiPromptList.isEmpty() ? null : aiPromptList[0];
    }
    public static AI_Prompt__c getAIPromptByPromptRequestId(String promptRequestId){
        String query = 'SELECT ' + getQueryFieldsString() + ' FROM AI_Prompt__c WHERE Prompt_Request_Id__c=:promptRequestId LIMIT 1';
        List<AI_Prompt__c> aiPromptList = Database.query(query);
        return aiPromptList.isEmpty() ? null : aiPromptList[0];
    }
    public static AI_Prompt__c getAIPromptByName(String name){
        String query = 'SELECT ' + getQueryFieldsString() + ' FROM AI_Prompt__c WHERE Name=:name LIMIT 1';
        List<AI_Prompt__c> aiPromptList = Database.query(query);
        return aiPromptList.isEmpty() ? null : aiPromptList[0];
    }
}