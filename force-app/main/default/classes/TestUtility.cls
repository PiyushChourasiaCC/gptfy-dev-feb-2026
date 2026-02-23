/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public with sharing class TestUtility {
    
    public static Account getAccount(Boolean isInsert){
        Account obj = new Account();
        obj.name = 'test account';
        if(isInsert){
            insert obj;
        }
        return obj;
    }
    
    public static Contact getContact(String accId, Boolean isInsert){
        Contact con = new Contact();
        con.AccountId = accId;
        con.LastName = 'TEST';
        con.Email = 'test@gmail.com';
        if(isInsert){
            insert con;
        }
        return con;
    }
    
    public static Case getCase(String accId, String conId, Boolean isInsert){
        Case c = new Case();
        c.AccountId = accId;
        c.ContactId = conId;
        c.Subject = 'Testing';
        if(isInsert){
            insert c;
        }
        return c;
    }
	
    public static AI_Connection__c getConnection(String tech, Boolean isInsert){
        AI_Connection__c obj = new AI_Connection__c();
        obj.Named_Credential__c = 'GPTfy';
        obj.Name = tech;
        obj.AI_Technology__c = tech;
        obj.EndPoint_URL__c = '/test.com';
        obj.Max_Tokens__c = 2000;
        obj.Version__c = '1';
        obj.Temperature__c = 0.1;
        obj.Infrastructure__c = 'Others';
        //obj.Response_Mapping__c = 'GPTfy';
        if(isInsert){
            insert obj;
        }
        return obj;
    }
    
    public static void insertDataExtraction(){
        Map<String, String> data = new Map<String, String>();
        data.put('recordId', null);
        data.put('mappingName', 'Test Mapping');
        data.put('targetObject', 'Account');
        data.put('description', 'test desc');
        data.put('objLabel', 'Account');
        data.put('aiDataSource', null);
        String masterId = AIDataExtractionController.modifyMaster(data);
        AIDataExtractionController.upsertRelatedObjectMapping(new Map<String, String>{
            'selectedObject' => 'Contact', 'selectedObjectLabel' => 'Contact', 'masterId' => masterId, 'parentId' => '', 'detailId' => '',
            'parentObject' => 'Account', 'relationshipField' => 'AccountId', 'relationshipName' => 'Contacts'       
        });
        AI_Data_Extraction_Detail__c detail = [SELECT Id FROM AI_Data_Extraction_Detail__c LIMIT 1];
        AIDataExtractionController.upsertRelatedObjectMapping(new Map<String, String>{
            'selectedObject' => 'Case', 'selectedObjectLabel' => 'Case', 'masterId' => masterId, 'parentId' => detail.Id, 'detailId' => '',
            'parentObject' => 'Contact', 'relationshipField' => 'ContactId', 'relationshipName' => 'Cases'       
        });
        
        AIDataExtractionController.upsertRelatedObjectMapping(new Map<String, String>{
            'selectedObject' => 'ActivityHistory', 'selectedObjectLabel' => 'ActivityHistory', 'masterId' => masterId, 'parentId' => detail.Id, 'detailId' => '',
            'parentObject' => 'Contact', 'relationshipField' => 'WhoId', 'relationshipName' => 'ActivityHistories'       
        });
        
        AIExtractionFieldMappingController.FieldWrapper acctField = new AIExtractionFieldMappingController.FieldWrapper();
        acctField.fieldName = 'Name';
        acctField.label = 'Name';
        acctField.sendToAI = true;
        acctField.scanForPII = true;
        acctField.anonymizeWith = 'PersonFull{n}';
        acctField.fieldType = 'String';
        acctField.selectedMaskingOption = 'Entire Value';
        AIExtractionFieldMappingController.saveFieldMappings(masterId, 'Account', new List<AIExtractionFieldMappingController.FieldWrapper>{acctField});
        
        AIExtractionFieldMappingController.FieldWrapper acctField2 = new AIExtractionFieldMappingController.FieldWrapper();
        acctField2.fieldName = 'Description';
        acctField2.label = 'Description';
        acctField2.sendToAI = true;
        acctField2.scanForPII = true;
        acctField2.fieldType = 'TEXTAREA';
        //conField2.anonymizeWith = 'PersonFull{n}';
        acctField2.selectedMaskingOption = 'Specific Patterns';
        AIExtractionFieldMappingController.saveFieldMappings(masterId, 'Account', new List<AIExtractionFieldMappingController.FieldWrapper>{acctField2});
        
        AIExtractionFieldMappingController.FieldWrapper conField = new AIExtractionFieldMappingController.FieldWrapper();
        conField.fieldName = 'FirstName';
        conField.label = 'FirstName';
        conField.sendToAI = true;
        conField.scanForPII = true;
        conField.fieldType = 'String';
        conField.anonymizeWith = 'PersonFull{n}';
        conField.selectedMaskingOption = 'Entire Value';
        AIExtractionFieldMappingController.saveFieldMappings(masterId, 'Contact', new List<AIExtractionFieldMappingController.FieldWrapper>{conField});
        
        AIExtractionFieldMappingController.FieldWrapper conField2 = new AIExtractionFieldMappingController.FieldWrapper();
        conField2.fieldName = 'Description';
        conField2.label = 'Description';
        conField2.sendToAI = true;
        conField2.scanForPII = true;
        conField2.fieldType = 'TEXTAREA';
        //conField2.anonymizeWith = 'PersonFull{n}';
        conField2.selectedMaskingOption = 'Specific Patterns';
        AIExtractionFieldMappingController.saveFieldMappings(masterId, 'Contact', new List<AIExtractionFieldMappingController.FieldWrapper>{conField2});
        
        AIExtractionFieldMappingController.FieldWrapper conField3 = new AIExtractionFieldMappingController.FieldWrapper();
        conField3.fieldName = 'Account.Description';
        conField3.label = 'Description';
        conField3.sendToAI = true;
        conField3.scanForPII = true;
        conField3.fieldType = 'TEXTAREA';
        //conField2.anonymizeWith = 'PersonFull{n}';
        conField3.selectedMaskingOption = 'Specific Patterns';
        AIExtractionFieldMappingController.saveFieldMappings(masterId, 'Contact', new List<AIExtractionFieldMappingController.FieldWrapper>{conField3});
        
        AIExtractionFieldMappingController.FieldWrapper caseField = new AIExtractionFieldMappingController.FieldWrapper();
        caseField.fieldName = 'Subject';
        caseField.label = 'Subject';
        caseField.sendToAI = true;
        caseField.scanForPII = true;
        caseField.fieldType = 'String';
        caseField.anonymizeWith = 'PersonFull{n}';
        caseField.selectedMaskingOption = 'Entire Value';
        AIExtractionFieldMappingController.saveFieldMappings(masterId, 'Case', new List<AIExtractionFieldMappingController.FieldWrapper>{caseField});
        
        AIExtractionFieldMappingController.FieldWrapper activityField = new AIExtractionFieldMappingController.FieldWrapper();
        activityField.fieldName = 'Subject';
        activityField.label = 'Subject';
        activityField.sendToAI = true;
        activityField.scanForPII = true;
        activityField.fieldType = 'String';
        activityField.anonymizeWith = 'PersonFull{n}';
        activityField.selectedMaskingOption = 'Entire Value';
        AIExtractionFieldMappingController.saveFieldMappings(masterId, 'ActivityHistory', new List<AIExtractionFieldMappingController.FieldWrapper>{activityField});
    }
    
    public static AI_Prompt_Component__c getPromptComponent(String pmtId, String dataExtId, String objName, Boolean isInsert){
        AI_Prompt_Component__c obj = new AI_Prompt_Component__c();
        obj.Key__c = 'Summary';
        obj.Object_Name__c = objName;
        obj.Data_Extraction_Id__c = dataExtId;
        obj.AI_Prompt__c = pmtId;
        obj.Name = objName;
        if(isInsert){
            insert obj;
        }
        return obj;
    }
    
    public static AI_Response_Processing__c getResponseProcessing(String cmpId, String destField, Boolean isInsert){
        AI_Response_Processing__c rp = new AI_Response_Processing__c();
        rp.Action__c = 'Update Field';
        rp.AI_Prompt_Component__c = cmpId;
        rp.Destination_Field__c = destField;
        if(isInsert){
            insert rp;
        }
        return rp;
    }

    public static Contentversion getContentversion(String title, String pathOnClient, String versionData, Boolean isInsert){
        ContentVersion cv = new Contentversion();
        cv.title = title;
        cv.PathOnClient = pathOnClient;
        cv.versiondata = Blob.valueOf(versionData);
        if(isInsert){
            insert cv;
        }
        return cv;
    }
    
    public static ContentDocumentLink getContentDocumentLink(String linkedEntityId, String contentDocumentId, Boolean isInsert){
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = contentDocumentId;
        cdl.ShareType = 'I';
        cdl.LinkedEntityId = linkedEntityId; 
        cdl.Visibility = 'AllUsers'; 
        if(isInsert){
           insert cdl;
        }
        return cdl;
    }

    public static AI_Scheduler__c getScheduler(String schedulerName, String schedularType, String schedulerDetail, String cronExp, Time scheduleTime, Integer retryCount, Boolean isInsert){
        AI_Scheduler__c sch = new AI_Scheduler__c();
        sch.Name = schedulerName;
        sch.Scheduling_Frequency__c = schedularType;
        sch.Schedule_Detail__c = schedulerDetail;
        sch.Cron_Expression__c = cronExp;
        sch.Schedule_time__c = scheduleTime;
        sch.Retry_Count__c = retryCount;
        if(isInsert){
            insert sch;
        }
        return sch;
    }

    public static AI_Prompt__c getAIPrompt(String name, String obj, String status, Boolean isInsert){
        AI_Prompt__c prompt = new AI_Prompt__c();
        prompt.Name = name;
        prompt.Object__c = obj;
        prompt.Status__c = status;
        //prompt.Prompt_Request_Id__c = 'SAMPLE_ID';
        if(isInsert){
            insert prompt;
        }
        return prompt;
    }

    public static AI_Prompt_Scheduler__c getAIPromptScheduler(String promptId, String schedulerId, Boolean isInsert){
        AI_Prompt_Scheduler__c promptScheduler = new AI_Prompt_Scheduler__c();
        promptScheduler.Prompt__c = promptId;
        promptScheduler.AI_Scheduler__c = schedulerId;
        if(isInsert){
            insert promptScheduler;
        }
        return promptScheduler;
    }
    
    public static AI_Scheduled_Run__c getAIScheduledRun(String schedulerId, Boolean isInsert){
        AI_Scheduled_Run__c scheduledRun = new AI_Scheduled_Run__c();
        scheduledRun.Scheduler__c = schedulerId;
        scheduledRun.Run_Date_Time__c = DateTime.now().addDays(1);
        if(isInsert){
            insert scheduledRun;
        }
        return scheduledRun;
    }
    
    public static AI_Response__c getAIResponse(String scheduledRunId, String promptSchedulerId, String processedDataPIIAdded, Boolean isInsert){
        AI_Response__c response = new AI_Response__c();
        response.Scheduled_Run__c = scheduledRunId;
        response.Prompt_Scheduler__c = promptSchedulerId;
        response.AI_Processed_Data_PII_Added__c = processedDataPIIAdded;
        if(isInsert){
            insert response;
        }
        return response;
    }
    
    public static AI_Security_Filters__c getAISecurityFilter(String type, String rtId, Boolean isInsert){
        AI_Security_Filters__c filter = new AI_Security_Filters__c();
        filter.Comment__c = 'Test';
        filter.Name = 'Test';
        filter.Type__c = type;
        filter.Search_Pattern__c = '\\d{4}';
        filter.RecordTypeId = rtId;
        filter.Blocklist__c = '123;456';
        filter.Status__c = 'Active';
        if(isInsert){
            insert filter;
        }
        return filter;
    }
    
    public static AI_Data_Source__c getAIDataSource(Boolean isInsert){
        AI_Data_Source__c ds = new AI_Data_Source__c();
        ds.Name = 'Test';
        ds.Source__c = 'DnB';
        ds.Connector_Class__c = 'AIDataSourceInterface';
        
        if(isInsert){
            insert ds;
        }
        return ds;
    }
    
    public static AI_Cross_Object_Filter__c createCrossObjectFilter(String promptSchId, String objName, Boolean isInsert){
        AI_Cross_Object_Filter__c filter = new AI_Cross_Object_Filter__c();
        filter.operator__c = 'Equals';
        filter.Object_API__c = 'Contact';
        filter.Object_Label__c = 'Contact';
        filter.Relationship_Field__c = 'AccountId';
        filter.Relationship_Name__c = 'Contacts';
        filter.Sequence__c = 1;
        filter.Value__c = 0;
        filter.AI_Prompt_Scheduler__c = promptSchId;
        if(isInsert){
            insert filter;
        }
        return filter;
    }

    public static AI_Card_Configuration__c createCardConfiguration(String name,String feature,Boolean isInsert){
        AI_Card_Configuration__c card = new AI_Card_Configuration__c();
        card.Name = name;
        card.Enabled__c = true;
        card.Feature__c = feature;
        card.Icon_Source__c = 'SLDS Icon';
        card.Icon_Details__c ='custom:custom28';
        if(isInsert){
            insert card;
        }
        return card;
    }

	public static AI_Response_Mapping__c createResponseMapping(String name,Boolean isInsert){
        AI_Response_Mapping__c resMapping = new AI_Response_Mapping__c();
        resMapping.Name = name;
        if(isInsert){
            insert resMapping;
        }
        return resMapping;
    }
    
    
    public static Request_Mapping__c createRequestMapping(String name,Boolean isInsert){
        Request_Mapping__c reqMapping = new Request_Mapping__c();
        reqMapping.Name = name;
        if(isInsert){
            insert reqMapping;
        }
        return reqMapping;
    }

    public static ContentVersion createContentVersion(String title, Boolean isInsert){
        ContentVersion cv = new Contentversion();
        cv.title = title;
        cv.PathOnClient = title+'.key';
        
        String body = '-----BEGIN RSA PRIVATE KEY-----'+
                    'MIIEpAIBAAKCAQEAxVyXPhg0y99JNO7ATSNckoIKW4xM32745ZeHQ0ZaN28r+eCS'+
                    'ce3VSKcHCX4W2mITgp3rZvaBB4IzIA9SYSOMZVFekjGR6X8YZf14gu/LLeS1jWfE'+
                    'vbR6H2wuL1vKgQhqtLho6VTPqXf1XDYssNE77r3+YLQKgE1sSxuKLcrmWlK8nrIZ'+
                    'C6m9O5eSplztIVRVY1M1HIt7mazHxUyVakLB55Jbkp8CNqNiPgM3sZz0Vmwx1cJw'+
                    '0HJ3//7OIW1VkE0/iKnXlZIn9dWLnYCURW8pSJ2MASHCfVck0vEgvdN8e/lH/H6s'+
                    'YclHf07toMWL1azL2riMUU0nzCmQhSkOCMgamQIDAQABAoIBAQCMkx7HA8bXT/t8'+
                    '0HH4f694S1fFTXGT1B9EqWGW8Y1g3racDPFCZPz9+rpwcHcmpaTv7Du34uyUxJBV'+
                    'zZQHzKI7qHGL//LGNdjTDG/CE7rMvZLzXW4tEVfK+esLoH3k2nHmt1NCnz4qn18M'+
                    'hynd56qgqoN9rb+tE3iHJt6NL3BT9EjuV/RxsMv8uHZNQl5E/bzsmP47c+xVKW44'+
                    '0TD9eprHusCdvNge1wbgdBk+r31pOtPP2Z3PVu09IElXMsXVPReiCDCeQ3uQ78av'+
                    '0+PHN8Ls2VwkUKdSOUKmrLozPdQKhpVMvGv81JzMWvlO2dZ7+1yCYCGXTdamGoMC'+
                    'EbLrJFnhAoGBAPcqD/kFkF6DLPsEfJaiB5HZmXSRbG/lkLUdDnWynCXG1Q7SS2I8'+
                    'ixWUbInmeGzRuJ0PJ0u5/DKi5OBG73C1yeDRjYKmLhJGNHOYN4Cf7A8ndNMzLVJ8'+
                    'TNUSoQO7HXEgF4DF14F1MWuTHM3xHMf63CyARIhQsivtCXKi+jziFMjfAoGBAMxq'+
                    'wclHC+nmU8L91LEvx5kkyOquYixAYm1Jb5pZp54W4as1IYiSg9hbhZpXqhnJn/xu'+
                    '9iaS/fIR9ck44mE75USozxm2/c5pafKC4Vc88WMya+4fiFuhka1rupa3B5vJmCjx'+
                    '2bSinqaGD27SyM6dmgqiuxGEte7oSeC+OZUbKnOHAoGAM+qr7DzU9GVNX3Szztg+'+
                    'Cs7QQwIA6wgne0OdM+/OiMjZHAHkP8BD3saMffLhPMpYovT55hgs913sAYgk52Ho'+
                    'A8dAmD7b0o7YmadRkT0GUrCRA4PuczMU2HTPSX9WUdrR1QS5ncHGHbiLBl8tEnyJ'+
                    'HvfabV+17TAfGetN8Nf0UbUCgYAff/f6v0L7uS2BJ8JFx5oXZE69sz+XmBhSxPU4'+
                    'sMYem2INEvPm6sT8ayYMYaPps2M+8A5oZVBSpCfe6TAhUayDxwua59L2otHbuAVn'+
                    'fxGnepadLCjEDgK32Zj4Lp4yiH81GAe3STPvb0sjhcHB7RFWwDrZeTzb4tm3kzim'+
                    'XHhPMwKBgQCDpcC0qAZBYx4FLLdrn1+ig2aifnNod4NUJXPrglWhAQDDhK3ALQ/M'+
                    'I90Wo4J0NgzaC15KF0/g1dcNN8IJt2J3ViHQS1kVwA9ytj1+/ZBL+Co9dA5IEoib'+
                    'euCvSuA5bOa1YP0fkuNi6Vb2kjdJpkFeQb+80rpT1+UbQU3AQYZgtw=='+
                    '-----END RSA PRIVATE KEY-----';        
        Blob data = Blob.valueOf(body);  
        
        cv.versiondata = data;
        if(isInsert){
            insert cv;
        }
        return cv;
    }
    
    public static AI_Prompt_Action__c getAIPromptAction(String promptId, String action, Boolean isInsert){
        AI_Prompt_Action__c pa = new AI_Prompt_Action__c();
        pa.AI_Prompt__c = promptId;
        pa.Action__c = action;
        if(isInsert){
            insert pa;
        }
        return pa;
    }
    
    public static AI_Prompt_Action_Detail__c getAIPromptActionDetail(String actionId, String actionFieldName,String actionType, Boolean isInsert){
         AI_Prompt_Action_Detail__c actionDetail = new AI_Prompt_Action_Detail__c();
            actionDetail.AI_Prompt_Action__c = actionId;
            actionDetail.Field_API_Name__c = actionFieldName;
            actionDetail.Type__c = actionType;
        if(isInsert){
            insert actionDetail;
        }
        return actionDetail;
    }
    
    public static AI_Prompt_Element__c getAIPromptElement(String promptId, String parentpromptId,String summarypromptId, 
                                                           Integer sequence, String width, Integer height, String Icon, 
                                                           Boolean inheritPromptSecurity, Boolean isInsert){
        AI_Prompt_Element__c promptElement = new AI_Prompt_Element__c(
            AI_Parent_Prompt__c = parentpromptId,
            AI_Prompt__c = promptId,
            AI_Summary_Prompt__c = summarypromptId,
            Sequence__c = sequence,
            Width__c = width,
            Height__c = height,
            Icon__c = Icon,
            Inherit_Prompt_Security__c = inheritPromptSecurity
        );
        if(isInsert){
            insert promptElement;
        }
        return promptElement;
    }
}