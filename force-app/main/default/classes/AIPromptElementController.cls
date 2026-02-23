/**
 * @description               : Controller class for handling AI Prompt Element operations, including CRUD actions, picklist retrieval, and data wrapping.
 * @author                    : Piyush Chourasia
 * @group                     : Plumcloud Labs
 * @last modified on          : 04-09-2025
 * @last modified by          : Piyush Chourasia
 **/
public with sharing class AIPromptElementController {

    /**
     * @description             : Fetches initial details for a prompt, including prompt metadata, picklist values, and related elements.
     * @param promptId          : ID of the parent AI_Prompt__c record.
     * @return                  : DetailsWrapper containing prompt details, picklist options, and related elements.
     */
    @AuraEnabled
    public static DetailsWrapper getInitialDetails(String promptId) {
        try {
            DetailsWrapper wrap = new DetailsWrapper();
            wrap.promptDetails = getPromptDetails(promptId);
            wrap.widthOptions = getPicklistValues('Width__c');
            wrap.iconOptions = getPicklistValues('Icon__c');
            wrap.promptElements = getPromptElements(promptId);
            return wrap;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description             : Retrieves details for a specific AI_Prompt__c record.
     * @param promptId          : ID of the AI_Prompt__c record.
     * @return                  : PromptDetails wrapper with key fields from AI_Prompt__c.
     */
    private static PromptDetails getPromptDetails(String promptId) {
        List<AI_Prompt__c> prompts = [SELECT Id, Name, Status__c, Object__c
                                    FROM AI_Prompt__c
                                    WHERE Id = :promptId
                                ];
        return !prompts.isEmpty() ? new PromptDetails(prompts[0]) : null;
    }

    /**
     * @description             : Retrieves picklist values for a specified field on AI_Prompt_Element__c.
     * @param fieldApiName      : API name of the picklist field (e.g., Width__c).
     * @return                  : List of PicklistWrapper objects with label/value pairs.
     */
    private static List<AIDataExtractionController.PicklistWrapper> getPicklistValues(String fieldApiName) {
        return AIPromptController.getPickListValues(
            GPTfyConsoleController.NAMESPACE + 'AI_Prompt_Element__c',
            GPTfyConsoleController.NAMESPACE + fieldApiName
        );
    }

    /**
     * @description             : Fetches all AI_Prompt_Element__c records related to a parent prompt.
     * @param promptId          : ID of the parent AI_Prompt__c record.
     * @return                  : List of PromptElementWrapper objects with formatted data.
     */
    private static List<PromptElementWrapper> getPromptElements(Id promptId) {
        List<PromptElementWrapper> wrappers = new List<PromptElementWrapper>();
        try {
            for (AI_Prompt_Element__c elem : [
                SELECT Id, Name, AI_Parent_Prompt__c, AI_Parent_Prompt__r.Name,
                       AI_Prompt__c, AI_Prompt__r.Name,
                       AI_Summary_Prompt__c, AI_Summary_Prompt__r.Name,
                       Height__c, Width__c, Icon__c, Sequence__c, Inherit_Prompt_Security__c
                FROM AI_Prompt_Element__c
                WHERE AI_Parent_Prompt__c = :promptId 
                ORDER BY Sequence__c
            ]) {
                wrappers.add(new PromptElementWrapper(elem));
            }
            return wrappers;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description             : Creates a new AI_Prompt_Element__c record from JSON input.
     * @param jsonString        : Serialized PromptElementWrapper containing field values.
     */
    @AuraEnabled
    public static void createPromptElement(String jsonString) {
        try {
            PromptElementWrapper wrapper = (PromptElementWrapper) JSON.deserialize(jsonString, PromptElementWrapper.class);
            FLSCheck.getInstance().insertDML(new List<AI_Prompt_Element__c>{ new AI_Prompt_Element__c(
                AI_Parent_Prompt__c = wrapper.parentPromptId,
                AI_Prompt__c = wrapper.promptId,
                AI_Summary_Prompt__c = wrapper.summaryPromptId,
                Height__c = wrapper.height ,
                Width__c = wrapper.width,
                Icon__c = wrapper.icon,
                Sequence__c = wrapper.sequence,
                Inherit_Prompt_Security__c = Boolean.valueOf(wrapper.inheritPromptSecurity)
            )});
        } catch (Exception ex) {
            System.debug(ex.getMessage());
            throw new AuraHandledException(ex.getMessage());  
        }
    }

    /**
     * @description : Updates an existing AI_Prompt_Element__c record from JSON input.
     * @param jsonString: Serialized PromptElementWrapper with updated field values.
     */
    @AuraEnabled
    public static void updatePromptElement(String jsonString) {
        try {
            PromptElementWrapper wrapper = (PromptElementWrapper) JSON.deserialize(jsonString, PromptElementWrapper.class);

            AI_Prompt_Element__c elem = [SELECT Id, Name, AI_Parent_Prompt__c, AI_Parent_Prompt__r.Name,
                                            AI_Prompt__c, AI_Prompt__r.Name,
                                            AI_Summary_Prompt__c, AI_Summary_Prompt__r.Name,
                                            Height__c, Width__c, Icon__c, Sequence__c, Inherit_Prompt_Security__c
                                        FROM AI_Prompt_Element__c
                                        WHERE Id = :wrapper.id LIMIT 1];

            elem.AI_Prompt__c = wrapper.promptId;
            elem.AI_Summary_Prompt__c = wrapper.summaryPromptId;
            elem.Height__c = wrapper.height;
            elem.Width__c = wrapper.width;
            elem.Icon__c = wrapper.icon;
            elem.Sequence__c = wrapper.sequence;
            elem.Inherit_Prompt_Security__c = wrapper.inheritPromptSecurity;
            
            FLSCheck.getInstance().updateDML(new List<AI_Prompt_Element__c>{elem});
        } catch (Exception ex) {
            System.debug(ex.getMessage());
            System.debug(ex.getStackTraceString());
            throw new AuraHandledException(ex.getMessage());  
        }
    }

    /**
     * @description: Deletes a specific AI_Prompt_Element__c record.
     * @param elementId : ID of the AI_Prompt_Element__c record to delete.
     */
    @AuraEnabled
    public static void deletePromptElement(Id elementId) {
        try {
            List<AI_Prompt_Element__c> elements = [SELECT Id FROM AI_Prompt_Element__c WHERE Id = :elementId LIMIT 1];
            FLSCheck.getInstance().deleteDML(elements);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());  
        }
    }

    // Inner wrapper classes with comments
    /**
     * @description: Aggregates all data needed for the prompt element UI.
     */
    public class DetailsWrapper {
        @AuraEnabled public PromptDetails promptDetails;
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> widthOptions;
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> iconOptions;
        @AuraEnabled public List<PromptElementWrapper> promptElements;
    }

    /**
     * @description: Contains key details from the parent AI_Prompt__c record.
     */
    public class PromptDetails {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String objectName;

        public PromptDetails(AI_Prompt__c prompt) {
            this.id = prompt.Id;
            this.name = prompt.Name;
            this.status = prompt.Status__c;
            this.objectName = prompt.Object__c;
        }
    }

    /**
     * @description: Wrapper for AI_Prompt_Element__c data with relationship names.
     */
    public class PromptElementWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id parentPromptId;
        @AuraEnabled public String parentPromptName;
        @AuraEnabled public Id promptId;
        @AuraEnabled public String promptName;
        @AuraEnabled public Id summaryPromptId;
        @AuraEnabled public String summaryPromptName;
        @AuraEnabled public Decimal height;
        @AuraEnabled public String width;
        @AuraEnabled public String icon;
        @AuraEnabled public Integer sequence;
        @AuraEnabled public Boolean inheritPromptSecurity;

        public PromptElementWrapper(AI_Prompt_Element__c elem) {
            this.id = elem.Id;
            this.name = elem.Name;
            this.parentPromptId = elem.AI_Parent_Prompt__c;
            this.parentPromptName = elem.AI_Parent_Prompt__r?.Name;
            this.promptId = elem.AI_Prompt__c;
            this.promptName = elem.AI_Prompt__r?.Name;
            this.summaryPromptId = elem.AI_Summary_Prompt__c;
            this.summaryPromptName = elem.AI_Summary_Prompt__r?.Name;
            this.height = elem.Height__c;
            this.width = elem.Width__c;
            this.icon = elem.Icon__c;
            this.sequence = elem.Sequence__c != null ? Integer.valueOf(elem.Sequence__c) : null;
            this.inheritPromptSecurity = elem.Inherit_Prompt_Security__c;
        }
    }
}