public with sharing class AIVoiceConfigurationController {
	
    @AuraEnabled
    public static ConfigurationWrapper getConfigurationDetails(){
        List<AI_Voice_Configuration__c> lstOfConfiguration = [SELECT Id, AI_Model__c, Duration_Minutes__c, 
                                                              AI_Model_File_Upload__c, AI_Model_Polling__c,
                                                              Async_Request__c, Maximum_Polling_Counter__c,
                                                              Polling_Timeframe__c
                                                              FROM AI_Voice_Configuration__c LIMIT 1];
        ConfigurationWrapper wrap = new ConfigurationWrapper();
        wrap.modelOptions = getModelOptions();
        wrap.profileOptions = new List<AIDataExtractionController.PicklistWrapper>();
		AIDataExtractionController.PicklistWrapper i_pf = new AIDataExtractionController.PicklistWrapper();
        i_pf.label = '--None--';
        i_pf.value = '';
        wrap.profileOptions.add(i_pf);        
        List<AIDataExtractionController.PicklistWrapper> profiles = AIPromptController.getProfileOptions();
        if(profiles != null && !profiles.isEmpty()){
            wrap.profileOptions.addAll(profiles);
        }
        
        wrap.objects = new List<AIDataExtractionController.PicklistWrapper>();
        AIDataExtractionController.PicklistWrapper i_obj = new AIDataExtractionController.PicklistWrapper();
        i_obj.label = '--None--';
        i_obj.value = '';
        wrap.objects.add(i_obj);
        List<AIDataExtractionController.PicklistWrapper> objects = AIDataExtractionController.getSObjects();
        if(objects != null && !objects.isEmpty()){
            wrap.objects.addAll(objects);
        }
        
        wrap.promptOptions = getPromptOptions();
        
        if(lstOfConfiguration != null && !lstOfConfiguration.isEmpty()){
            AI_Voice_Configuration__c config = lstOfConfiguration.get(0);
            wrap.configId = config.Id;
            wrap.aiModelId = config.AI_Model__c;
            wrap.fileUploadModelId = config.AI_Model_File_Upload__c;
            wrap.pollingModelId = config.AI_Model_Polling__c;
            wrap.duration = config.Duration_Minutes__c != null ? config.Duration_Minutes__c : 1;
            wrap.pollingTimeframe = config.Polling_Timeframe__c != null ? config.Polling_Timeframe__c : null;
            wrap.pollingCounter = config.Maximum_Polling_Counter__c != null ? config.Maximum_Polling_Counter__c : null;
            wrap.asyncRequest = config.Async_Request__c != null && config.Async_Request__c ? true : false;
            
            List<AI_Voice_Configuration_Detail__c> lstOfDetails = [SELECT Id, Profile__c, AI_Prompt__c, AI_Prompt__r.Name, Related_To_Object__c  
                                                                   FROM AI_Voice_Configuration_Detail__c
                                                                   WHERE AI_Voice_Configuration__c =:config.Id];
            if(lstOfDetails != null && !lstOfDetails.isEmpty()){
                List<ConfigurationDetailWrapper> details = new List<ConfigurationDetailWrapper>();
                for(AI_Voice_Configuration_Detail__c detail : lstOfDetails){
                    ConfigurationDetailWrapper d_wrap = new ConfigurationDetailWrapper();
                    d_wrap.detailId = detail.Id;
                    d_wrap.profile = detail.Profile__c;
                    d_wrap.aiPromptId = detail.AI_Prompt__c;
                    d_wrap.aiPromptName = detail.AI_Prompt__c != null ? detail.AI_Prompt__r.Name : null;
                    d_wrap.objectName = detail.Related_To_Object__c;
                    details.add(d_wrap);
                }
                wrap.details = details;
            }
        }
        return wrap;
    }
    
    public static List<AIDataExtractionController.PicklistWrapper> getModelOptions(){
        try{
            List<AIDataExtractionController.PicklistWrapper> typeOptions = new List<AIDataExtractionController.PicklistWrapper>();
            
            AIDataExtractionController.PicklistWrapper i_pf = new AIDataExtractionController.PicklistWrapper();
            i_pf.label = '--None--';
            i_pf.value = '';
            typeOptions.add(i_pf);
            
            List<String> activeAIModal = new List<String>();
            for(AI_Card_Configuration__c cc : [SELECT Id, Name FROM AI_Card_Configuration__c 
                                               WHERE Enabled__c = true 
                                               AND Feature__c = :AIConstants.GPTfy_Card_Configuration_MDT_AMODL]){
                activeAIModal.add(cc.Name.toLowercase());
            }
            
            for(AI_Connection__c p : [SELECT Id, Name FROM AI_Connection__c 
                                      WHERE Type__c =:AIConstants.AI_MODEL_TYPE_VOICE
                                      ORDER BY Name LIMIT 50000]){
                if(activeAIModal.contains(p.Name.toLowercase())){
                    AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                    wrap.label = p.Name;
                    wrap.value = p.Id;
                    typeOptions.add(wrap);
                }
            }
            return typeOptions;
        }catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<AIDataExtractionController.PicklistWrapper> getPromptOptions(){
        List<AIDataExtractionController.PicklistWrapper> lst = new List<AIDataExtractionController.PicklistWrapper>();
        List<AI_Prompt__c> lstOfPrompts = [SELECT Id, Name, Object__c, Prompt_Command__c
                                           FROM AI_Prompt__c 
                                           WHERE Status__c =:AIConstants.PMT_STATUS_ACTIVE
                                           AND Object__c = 'ContentVersion'];
        if(lstOfPrompts != null && !lstOfPrompts.isEmpty()){
            for(AI_Prompt__c pmt : lstOfPrompts){
                if(String.isNotBlank(pmt.Prompt_Command__c)){
                    AIDataExtractionController.PicklistWrapper wrap = new AIDataExtractionController.PicklistWrapper();
                    wrap.label = pmt.Name;
                    wrap.value = pmt.Id;
                    lst.add(wrap);
                } 
            }
        }
        return lst;
    }
    
    @AuraEnabled
    public static void updateConfiguration(String wrap){
        try{
            ConfigurationWrapper data = (ConfigurationWrapper) System.JSON.deserialize(wrap, ConfigurationWrapper.class);
            AI_Voice_Configuration__c obj = new AI_Voice_Configuration__c();
            if(data != null){
                if(String.isNotBlank(data.configId)){
                    obj.Id = data.configId;
                }
                obj.Duration_Minutes__c = data.duration != NULL && data.duration > 0 ? data.duration : 0;
                obj.AI_Model__c = String.isNotBlank(data.aiModelId) ? data.aiModelId : null;
                obj.AI_Model_File_Upload__c = String.isNotBlank(data.fileUploadModelId) ? data.fileUploadModelId : null;
                obj.AI_Model_Polling__c = String.isNotBlank(data.pollingModelId) ? data.pollingModelId : null;
                obj.Polling_Timeframe__c = data.pollingTimeframe != NULL ? (Integer)data.pollingTimeframe : null;
                obj.Maximum_Polling_Counter__c = data.pollingCounter != NULL ? (Integer)data.pollingCounter : null;
                obj.Async_Request__c = data.asyncRequest != NULL && data.asyncRequest ? true : false;
            }
            FLSCheck.getInstance().upsertDML(new List<AI_Voice_Configuration__c>{obj});
        }catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void updateConfigurationDetail(String wrap, String configId){
        try{
            ConfigurationDetailWrapper data = (ConfigurationDetailWrapper) System.JSON.deserialize(wrap, ConfigurationDetailWrapper.class);
            AI_Voice_Configuration_Detail__c obj = new AI_Voice_Configuration_Detail__c();
            if(String.isNotBlank(data.detailId) && data.detailId != null && data.detailId != 'null'){
                obj.Id = data.detailId;
            }else{
                obj.AI_Voice_Configuration__c = configId;
            }
            obj.Profile__c = data.profile;
            obj.Related_To_Object__c = data.objectName;
            obj.AI_Prompt__c = String.isNotBlank(data.aiPromptId) ? data.aiPromptId : null;
            FLSCheck.getInstance().upsertDML(new List<AI_Voice_Configuration_Detail__c>{obj});
        }catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    public class ConfigurationWrapper{
        @AuraEnabled public String configId{get;set;}
        @AuraEnabled public String aiModelId{get;set;}
        @AuraEnabled public String fileUploadModelId{get;set;}
        @AuraEnabled public String pollingModelId{get;set;}
        @AuraEnabled public Decimal duration{get;set;}
        @AuraEnabled public Decimal pollingTimeframe{get;set;}
        @AuraEnabled public Decimal pollingCounter{get;set;}
        @AuraEnabled public Boolean asyncRequest{get;set;}   
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> modelOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> profileOptions{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> objects{get;set;}
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> promptOptions{get;set;}
        @AuraEnabled public List<ConfigurationDetailWrapper> details{get;set;}
    }
    
    public class ConfigurationDetailWrapper{
        @AuraEnabled public String detailId{get;set;}
        @AuraEnabled public String profile{get;set;}
        @AuraEnabled public String aiPromptId{get;set;}
        @AuraEnabled public String aiPromptName{get;set;}
        @AuraEnabled public String objectName{get;set;}
    }
    
}