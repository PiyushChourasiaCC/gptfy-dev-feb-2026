public with sharing class AIPromptBuilderController {
    
    public static final Set<String> READ_ONLY_FIELDS = new Set<String>{'OwnerId', AIConstants.NAMESPACE+'Type__c', AIConstants.NAMESPACE+'Status__c', AIConstants.NAMESPACE+'Object__c', AIConstants.NAMESPACE+'AI_Data_Extraction_Mapping__c', AIConstants.NAMESPACE+'Prompt_Version__c',AIConstants.NAMESPACE+'Message__c'};
    public static final Set<String> FULL_WIDTH_FIELDS = new Set<String>{AIConstants.NAMESPACE+'Prompt_Command__c', AIConstants.NAMESPACE+'Grounding_Content__c', AIConstants.NAMESPACE+'Grounding_Ethical__c',  AIConstants.NAMESPACE+'How_it_works__c'};
    private static final String TYPE_CANVAS = 'Canvas';
    private static final Set<String> TABS_TO_INCLUDE = new Set<String>{'Configuration'};
    private static final Set<String> SUB_TABS_TO_EXCLUDE = new Set<String>{AIConstants.NAMESPACE+'configuration_ai_model',AIConstants.NAMESPACE+'configuration_loopback',
                                                                AIConstants.NAMESPACE+'configuration_agentic'};
    private static final Set<String> FIELDS_TO_EXCLUDE = new Set<String>{AIConstants.NAMESPACE+'Custom_Prompt__c',AIConstants.NAMESPACE+'Include_Files__c',
                                                                AIConstants.NAMESPACE+'AI_Connection__c',AIConstants.NAMESPACE+'Temperature__c',
                                                                AIConstants.NAMESPACE+'Top_P__c',AIConstants.NAMESPACE+'Max_Output_Tokens__c',AIConstants.NAMESPACE+'Agentic_Function_Class__c'};
    private static final Set<String> FIELDS_TO_EXCLUDE_FOR_AGENTIC = new Set<String>{AIConstants.NAMESPACE+'Include_Files__c',AIConstants.NAMESPACE+'Enable_Loopback__c',
                                                                AIConstants.NAMESPACE+'Temperature__c', AIConstants.NAMESPACE+'Time_Saved_Coefficient__c',   //AIConstants.NAMESPACE+'AI_Connection__c' remove for agentic,
                                                                AIConstants.NAMESPACE+'Top_P__c',AIConstants.NAMESPACE+'Max_Output_Tokens__c',AIConstants.NAMESPACE+'Visibility_Exception_Message__c',
                                                                AIConstants.NAMESPACE+'Loopback_Message__c', AIConstants.NAMESPACE+'Custom_Prompt__c', AIConstants.NAMESPACE+'Prompt_Request_Id__c',
                                                                AIConstants.NAMESPACE+'Purpose__c', AIConstants.NAMESPACE+'How_it_works__c', AIConstants.NAMESPACE+'Visibility_Condition__c'};
    private static final Set<String> SUB_TABS_TO_EXCLUDE_FOR_AGENTIC = new Set<String>{AIConstants.NAMESPACE+'configuration_loopback'}; // AIConstants.NAMESPACE+'configuration_ai_model' remvoed agentic,
    private static final Set<String> TABS_TO_INCLUDE_FOR_AGENTIC = new Set<String>{'Configuration', 'Prompt'};
    private static final Set<String> SUB_TABS_TO_EXCLUDE_FOR_OTHERS = new Set<String>{AIConstants.NAMESPACE+'configuration_agentic'};

    @AuraEnabled
    public static ReturnWrapper getTabFields(String recordId){
        
        ReturnWrapper retWrap = new ReturnWrapper();
        
        String promptType = getPromptsType(recordId);

        Schema.DescribeSObjectResult promptObjType = Schema.SObjectType.AI_Prompt__c;
        Map<String, Schema.FieldSet> fieldSetMap = promptObjType.fieldSets.getMap();
        Map<String, Schema.SObjectField> fieldMap = promptObjType.fields.getMap();
        Map<String, List<Schema.FieldSetMember>> mapOfFieldSetNameToFields = new Map<String, List<Schema.FieldSetMember>>();
        
        Set<String> fieldApiNames = new Set<String>{'Id', AIConstants.NAMESPACE+'Status__c'};
        List<FieldSetSequenceWrapper> lstOfSequence = new List<FieldSetSequenceWrapper>();
        for(String fieldSetName : fieldSetMap.keySet()){
			String fieldDesc = String.valueOf(fieldSetMap.get(fieldSetName).getDescription());
            FieldSetSequenceWrapper fs_wrap = new FieldSetSequenceWrapper();
            fs_wrap.fieldSetName = fieldSetName;
            fs_wrap.sequence = 0;
            if(String.isNotBlank(fieldDesc)){
                try{
                    fs_wrap.sequence = Integer.valueOf(fieldDesc);
                }catch(Exception e){
                    //do-nothing
                }
            }
            lstOfSequence.add(fs_wrap);
            
            List<Schema.FieldSetMember> fieldSetMembers = fieldSetMap.get(fieldSetName).getFields();
            mapOfFieldSetNameToFields.put(fieldSetName, fieldSetMembers);
            if(fieldSetMembers != null && !fieldSetMembers.isEmpty()){
                for(Schema.FieldSetMember fsm : fieldSetMembers){
                    fieldApiNames.add(fsm.getFieldPath());
                }
            }
        }
        
        lstOfSequence.sort();
        
        String query = 'SELECT '+String.join(new List<String>(fieldApiNames), ', ')+' FROM '+AIConstants.NAMESPACE+'AI_Prompt__c WHERE Id =:recordId';
        AI_Prompt__c aiPrompt = Database.query(query);
        retWrap.readOnly = false;
        if(aiPrompt.Status__c == AIConstants.PMT_STATUS_ACTIVE){
            retWrap.readOnly = true;
        }
                
        Map<String, TabWrapper> mapOfTabs = new Map<String, TabWrapper>();
        if(lstOfSequence != null && !lstOfSequence.isEmpty()){
            GPTfy_Settings__c gptfySetting = GPTfy_Settings__c.getOrgDefaults();
            for(FieldSetSequenceWrapper fs_wrap : lstOfSequence){
                String fieldSetName = fs_wrap.fieldSetName;
                String fieldSetLabel = String.valueOf(fieldSetMap.get(fieldSetName).getLabel());
                if(String.isNotBlank(fieldSetLabel) && fieldSetLabel.contains('-')){
                    String tabName = fieldSetLabel.subStringBefore('-').trim();
                    String sectionName = fieldSetLabel.subStringAfter('-').trim();
					if(promptType == TYPE_CANVAS && !TABS_TO_INCLUDE.contains(tabName)){
                        continue;
                    }else if(promptType == TYPE_CANVAS && TABS_TO_INCLUDE.contains(tabName) && SUB_TABS_TO_EXCLUDE.contains(fieldSetName)){
                        continue;
                    }
                    if(promptType == AIConstants.AI_PMT_TYPE_AGENTIC && !TABS_TO_INCLUDE_FOR_AGENTIC.contains(tabName)){
                        continue;
                    }else if(promptType == AIConstants.AI_PMT_TYPE_AGENTIC && TABS_TO_INCLUDE_FOR_AGENTIC.contains(tabName) && SUB_TABS_TO_EXCLUDE_FOR_AGENTIC.contains(fieldSetName)){
                        continue;
                    }
                    if(promptType != AIConstants.AI_PMT_TYPE_AGENTIC && SUB_TABS_TO_EXCLUDE_FOR_OTHERS.contains(fieldSetName)){
                        continue;
                    }

                    List<Schema.FieldSetMember> fieldSetMembers = mapOfFieldSetNameToFields.get(fieldSetName);
                    List<FieldWrapper> fields = new List<FieldWrapper>();
                    if(fieldSetMembers != null && !fieldSetMembers.isEmpty()){
                        for(Schema.FieldSetMember fsm : fieldSetMembers){
                            FieldWrapper fm_wrap = new FieldWrapper();
                            fm_wrap.label = fsm.getLabel();
                            fm_wrap.apiName = fsm.getFieldPath();
                            fm_wrap.required = fsm.getRequired();
                            fm_wrap.type = String.valueOf(fsm.getType());
                            fm_wrap.readOnly = false;
                            fm_wrap.sldsClass = 'slds-col slds-size_1-of-2 slds-p-top_x-small';
                            fm_wrap.fieldValue = aiPrompt.get(fm_wrap.apiName);
                            
                            if(fm_wrap.apiName.endsWithIgnoreCase('Append_Timestamp__c') && aiPrompt.get(AIConstants.NAMESPACE+'Target_Field__c') == null){
                                fm_wrap.hideField = true;
                            }
                            if(fm_wrap.apiName.endsWithIgnoreCase('AI_Model_File_Processing__c') && !aiPrompt.Include_Files__c){
                                fm_wrap.hideField = true;
                            }
                            if(promptType == TYPE_CANVAS && FIELDS_TO_EXCLUDE.contains(fm_wrap.apiName)){
                                fm_wrap.hideField = true;
                            }
                            if(promptType == AIConstants.AI_PMT_TYPE_AGENTIC && FIELDS_TO_EXCLUDE_FOR_AGENTIC.contains(fm_wrap.apiName)){
                                fm_wrap.hideField = true;
                            }
                            if(promptType != TYPE_CANVAS && fm_wrap.apiName.endsWithIgnoreCase('Auto_Refresh_Duration__c')){
                                fm_wrap.hideField = true;
                            }
                            if(fm_wrap.apiName.endsWithIgnoreCase('Loopback_Message__c') && !aiPrompt.Enable_Loopback__c){
                                fm_wrap.hideField = true;
                            }
                            Schema.DescribeFieldResult fieldDesc = fieldMap.get(fm_wrap.apiName).getDescribe();
                            
                            if(!fieldDesc.isUpdateable() || READ_ONLY_FIELDS.contains(fm_wrap.apiName) || retWrap.readOnly){
                                fm_wrap.readOnly = true;
                            }if(FULL_WIDTH_FIELDS.contains(fm_wrap.apiName)){
                                fm_wrap.sldsClass = 'slds-col slds-size_1-of-1 slds-p-top_x-small';
                            }
    
                            if(String.isNotBlank(fm_wrap.apiName) && fm_wrap.apiName.endsWithIgnoreCase('Profiles__c')){
                               fm_wrap.isProfile = true;
                            }
                            if(String.isNotBlank(fm_wrap.apiName) && fm_wrap.apiName.endsWithIgnoreCase('Permission_Sets__c')){
                               fm_wrap.isPermissionSets = true;
                            }
                            if(String.isNotBlank(fm_wrap.apiName) && fm_wrap.apiName.endsWithIgnoreCase('Target_Field__c')){
                               fm_wrap.isTargetField = true;
                            }
                            if(String.isNotBlank(fm_wrap.apiName) && fm_wrap.apiName.endsWithIgnoreCase('Prompt_Command__c')){
                               fm_wrap.isPromptCommand = true;
                            }
                            if(String.isNotBlank(fm_wrap.apiName) && fm_wrap.apiName.endsWithIgnoreCase('Visibility_Condition__c')){
                               fm_wrap.isVisibilityCondition = true;
                            }
                            if(String.isNotBlank(fm_wrap.type) && fm_wrap.type.equalsIgnoreCase('MULTIPICKLIST')){
                               fm_wrap.isMultiselect = true;
                            }
                            
                            //System.debug(fm_wrap.apiName+'---'+);
                            if(String.isNotBlank(fm_wrap.apiName) && (fm_wrap.apiName.endsWithIgnoreCase('Include_Files__c') || fm_wrap.apiName.endsWithIgnoreCase('AI_Model_File_Processing__c')) && !gptfySetting.File_Processing__c ){
                               // skip to add field
                            }else{
                                fields.add(fm_wrap);
                            }
                        }
                    }

                    SectionWrapper sw = new SectionWrapper();
                    sw.sectionName = sectionName;
                    sw.expanded = true;
                    sw.fields = fields;
                    
                    TabWrapper tw = new TabWrapper();
                    tw.tabName = tabName;
                    if(!mapOfTabs.containsKey(tabName)){
                        tw.sections = new List<SectionWrapper>{sw};
                        mapOfTabs.put(tabName, tw);
                    }else{
                        mapOfTabs.get(tabName).sections.add(sw);
                    }
                }
            }
        }
        if(!mapOfTabs.isEmpty()){
            retWrap.tabs = mapOfTabs.values();
        }
        return retWrap;
    }
    private static String getPromptsType(String recordId){
        List<AI_Prompt__c> prompts = [SELECT Id, Type__c FROM AI_Prompt__c WHERE Id = :recordId];
        if(!prompts.isEmpty()){
            return prompts[0].Type__c;
        }
        return '';
    }
    public class FieldSetSequenceWrapper implements Comparable{
    	@AuraEnabled public String fieldSetName{get;set;}
        @AuraEnabled public Integer sequence{get;set;}
        public Integer compareTo(Object objToCompare) {
        	FieldSetSequenceWrapper wrap = (FieldSetSequenceWrapper)objToCompare;
        	Integer returnValue = 0;
	    	if(sequence > wrap.sequence)
		    	return 1;
	    	else if(sequence < wrap.sequence)
		    	return -1; 
        	return returnValue;
        }
    }
    
    @AuraEnabled
    public static List<FieldWrapper> getProfileOptions(){
        List<FieldWrapper> profileOptions = new List<FieldWrapper>();
        for(Profile p : [SELECT Id, Name FROM Profile ORDER BY Name LIMIT 50000]){
            FieldWrapper wrap = new FieldWrapper();
            wrap.label = p.Name;
            wrap.value = p.Name;
            profileOptions.add(wrap);
        }
        return profileOptions;
    }
    
    @AuraEnabled
    public static List<FieldWrapper> getPermissionSetsOptions(){
        List<FieldWrapper> permissionsOptions = new List<FieldWrapper>();
        for(PermissionSet p : [SELECT Id,label, Name FROM PermissionSet WHERE TYPE IN ('Regular','Standard') ORDER BY Name LIMIT 50000]){
            FieldWrapper wrap = new FieldWrapper();
            wrap.label = p.label;
            wrap.value = p.label;
            permissionsOptions.add(wrap);
        }
        permissionsOptions.sort();
        return permissionsOptions;
    }
    
    @AuraEnabled
    public static List<FieldWrapper> getTargetFieldOptions(String objName){
        List<FieldWrapper> options = new List<FieldWrapper>();
        
        FieldWrapper i_wrap = new FieldWrapper();
        i_wrap.label = '---None---';
        i_wrap.value = '';
        options.add(i_wrap);
        
        if(String.isNotBlank(objName)){
            Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        	Map<String, Schema.SObjectField> fieldMap = schemaMap.get(objName).getDescribe().fields.getMap();
            for(Schema.SObjectField sfield : fieldMap.Values()){
           		Schema.describeFieldResult dfield = sfield.getDescribe();
                String fieldType = String.valueOf(dfield.getType());
                if(dfield.isAccessible() && (fieldType == 'TEXTAREA' || fieldType == 'STRING')){	
                    FieldWrapper wrap = new FieldWrapper();
                    wrap.label = dfield.getLabel();
                    wrap.value = dfield.getname();
                    wrap.description = dfield.getname();
                    options.add(wrap);
                }
            }
        }
        return options;
    }
    
    @AuraEnabled
    public static void updatePrompt(Map<String, Object> data){
        AI_Prompt__c pmt = new AI_Prompt__c();
        for(String fName : data.keySet()){
            pmt.put(fName, data.get(fName));
        }
        FLSCheck.getInstance().updateDML(new List<AI_Prompt__c>{pmt});
    }
    
    public class ReturnWrapper{
        @AuraEnabled public Boolean readOnly{get;set;}
        @AuraEnabled public List<TabWrapper> tabs{get;set;}
    }
    
    public class TabWrapper{
        @AuraEnabled public String tabName{get;set;}
        @AuraEnabled public List<SectionWrapper> sections{get;set;}
    }
    
    public class SectionWrapper{
        @AuraEnabled public String sectionName{get;set;}
        @AuraEnabled public Boolean expanded{get;set;}
        @AuraEnabled public List<FieldWrapper> fields{get;set;}
    }
    
    public class FieldWrapper implements Comparable{
        @AuraEnabled public String apiName{get;set;}
        @AuraEnabled public String label{get;set;}
        @AuraEnabled public Object fieldValue{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String type{get;set;}
        @AuraEnabled public Boolean required{get;set;}
        @AuraEnabled public Boolean readOnly{get;set;}
        @AuraEnabled public String sldsClass{get;set;}
        @AuraEnabled public Boolean isMultiselect{get;set;}
        @AuraEnabled public Boolean isProfile{get;set;}
        @AuraEnabled public Boolean isPermissionSets{get;set;}
        @AuraEnabled public Boolean isTargetField{get;set;}
        @AuraEnabled public Boolean isPromptCommand{get;set;}
        @AuraEnabled public Boolean isVisibilityCondition{get;set;}
        @AuraEnabled public Boolean hideField{get;set;}

        public Integer compareTo(Object objToCompare) {
        	return label.compareTo(((FieldWrapper)objToCompare).label);
        }
    }
        
}