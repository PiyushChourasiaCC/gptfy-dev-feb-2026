/**
 * @description: 
 *   AICanvasController provides Lightning-enabled methods to retrieve AI Canvas template 
 *   details, their components, and associated AI prompts from the backend. 
 *   This is used to drive UI experiences for dynamic AI canvas rendering.
 *                      
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 04-09-2025
 * @last modified by  : Piyush Chourasia
 **/
public with sharing class AICanvasController {

    public static final String NAMESPACE = AIPromptController.getNameSpace();

    /**
     * @description:
     *   Retrieves details of the winning AI Canvas Template for a given record ID and object type.
     *
     * @param recordId       - The record ID used for current record
     * @param objectApiName  - The API name of the object (e.g., Account, Case)
     * @return CanvasTemplateDetails if a matching template is found, else null
     */
    @AuraEnabled
    public static Boolean isCanvasUser(){
        try{
            List<String> validPermSets = new List<String>{'SGPT_Admin', 'SGPT_User', 'SGPT_Portal_User'};
            String l_namespace = NAMESPACE;
            if(String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')){
                l_namespace = l_namespace.removeEndIgnoreCase('__');
            }
            List<PermissionSetAssignment> psas = [SELECT Id FROM PermissionSetAssignment 
                                                WHERE PermissionSet.Name IN :validPermSets 
                                                AND AssigneeId = :UserInfo.getUserId()
                                                AND PermissionSet.NamespacePrefix =:l_namespace];
            if(psas != null && !psas.isEmpty()){
                return true;
            }
            return false;
        }catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description:
     *   Retrieves details of the winning AI Canvas Template for a given record ID and object type.
     *
     * @param recordId       - The record ID used for current record
     * @param objectApiName  - The API name of the object (e.g., Account, Case)
     * @return CanvasTemplateDetails if a matching template is found, else null
     * @Jira V2-6591
     */
    @AuraEnabled
    public static CanvasDetails getPromptElementsWithPrompts(String promptId, String recordId, String objectApiName, String parentAIResponse,Boolean notInitialLoad) {
        try {
            List<PromptElement> promptElementsWrap = new List<PromptElement>();
            List<PromptDetail> promptDetailsWrap = new List<PromptDetail>();
            List<AIDataExtractionController.PicklistWrapper> picklistWrapper = 
                AIPromptController.getPickListValues(GPTfyConsoleController.NAMESPACE+'AI_Feedback__c', GPTfyConsoleController.NAMESPACE+'Category__c');
            Set<Id> promptIds = new Set<Id>();
            String userSignature = AICanvasService.getUserSignature();
            AI_Response__c parentResponse;
            if(!String.isEmpty(parentAIResponse)){
                parentResponse = AICanvasService.fetchSecurityAuditRecord(parentAIResponse,recordId);
                promptId = parentResponse.AI_Prompt__c;
            }else if(promptId == null || promptId == ''){
                AI_Prompt__c winnerPrompt = AICanvasService.fetchWinnerPrompt(recordId, objectApiName);
                if(winnerPrompt == null){
                    return null;
                }
                promptId = winnerPrompt.Id;
            }
            if(parentResponse == null && promptId != null && notInitialLoad != null && notInitialLoad == false){
                parentResponse = AICanvasService.fetchSecurityAuditRecordByPromptId(promptId,recordId);
            }

            AI_Prompt__c prompt = AICanvasService.getPromptDetails(recordId, objectApiName,promptId);

            if(prompt == null){
                return null;
            }
            if(!String.isEmpty(objectApiName) && objectApiName != prompt.Object__c){
                return null;
            }
            
            String emailActionName = AICanvasService.getEmailActionName(objectApiName);

            if(parentResponse != null){
                for(AI_Response__c resp : parentResponse.Parent_Security_Audits__r){
                    if(!String.isEmpty(resp.Prompt_Element_Details__c)){
                        PromptElement pElement = (PromptElement)JSON.deserialize(resp.Prompt_Element_Details__c, PromptElement.class);
                        promptElementsWrap.add(pElement);
                        promptIds.add(pElement.prompt);
                        if(pElement.summaryPrompt != null){
                            promptIds.add(pElement.summaryPrompt);
                        }
                    }
                }
            }
            if(parentResponse == null || promptElementsWrap.isEmpty()){
                List<AI_Prompt_Element__c> promptElements = AICanvasService.getPromptElementsByPromptId(promptId);

                if(!promptElements.isEmpty()){
                    for(AI_Prompt_Element__c element : promptElements){
                        promptIds.add(element.AI_Prompt__c);
                        if(element.AI_Summary_Prompt__c != null){
                            promptIds.add(element.AI_Summary_Prompt__c);
                        }
                        promptElementsWrap.add(new PromptElement(element));
                    }
                }
            }

            if (promptIds.isEmpty()) {
                return null;
            }

            // Fetch all prompts referenced in the components
            List<AI_Prompt__c> prompts = AICanvasService.fetchPrompts(promptIds);

            for (AI_Prompt__c prmt : prompts) {
                promptDetailsWrap.add(new PromptDetail(prmt));
            }

            if (promptElementsWrap.isEmpty() && promptDetailsWrap.isEmpty()) {
                return null;
            }

            return new CanvasDetails(userSignature,emailActionName,new PromptDetail(prompt),promptElementsWrap,promptDetailsWrap,picklistWrapper);
        } catch (Exception ex) {
            // Return a controlled error for front-end handling
            throw new AuraHandledException(ex.getMessage());
        }
    }
    /**
     * @description:
     *   Retrieves details of the winning AI Canvas Template for a given record ID and object type.
     *
     * @param recordId       - The record ID used for current record
     * @param objectApiName  - The API name of the object (e.g., Account, Case)
     * @return CanvasTemplateDetails if a matching template is found, else null
     * @Jira V2-6591
     */
    @AuraEnabled
    public static AI_Response__c getSecurityAudit(String promptId, String recordId,Boolean notInitialLoad, String responseId) {
        try {
            AI_Response__c aiResponse = new AI_Response__c();
            if(notInitialLoad == true){
                aiResponse = getNewAIResponse(recordId,promptId);
            }else if(!String.isBlank(responseId) && responseId.length() > 0){
                aiResponse = AICanvasService.fetchSecurityAuditRecord(responseId,recordId);
            }else{
                aiResponse = AICanvasService.fetchSecurityAuditRecordByPromptId(promptId,recordId);
            }
            if(aiResponse == null){
                aiResponse = getNewAIResponse(recordId,promptId);
            }
            if(aiResponse != null){
                return aiResponse;
            }
            return null;
        }catch(Exception ex){
            throw new AuraHandledException(ex.getMessage());
        }
    }
    private static AI_Response__c getNewAIResponse(String recordId, String promptId){
        AI_Response__c aiResponse = new AI_Response__c();
        aiResponse.Record_Id__c = recordId;
        aiResponse.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
        aiResponse.Is_Canvas_Response__c = true;
        aiResponse.AI_Prompt__c = promptId;
            
        List<SObject> records = FLSCheck.getInstance().insertDML(new List<AI_Response__c>{aiResponse});

        return AICanvasService.fetchSecurityAuditRecord(records.get(0).Id,recordId);
    }
    @AuraEnabled
    public static AI_Response__c updateParentAIResponse(String parentAIResponse, String childAiResponseIds, String recordId){
        try {
            Set<Id> childResponseIds = (Set<Id>)JSON.deserialize(childAiResponseIds, Set<Id>.class);
            
            List<AI_Response__c> aiResponses = AICanvasService.fetchAIResponses(childResponseIds, recordId);
            List<AI_Response__c> responseToBeUpdated = new List<AI_Response__c>();
            Integer promptToken = 0;
            Integer completionToken = 0;

            for(AI_Response__c resp : aiResponses){
                resp.AI_Parent_Response__c = parentAIResponse;
                completionToken+= (resp.Completion_Tokens__c != null ? Integer.valueOf(resp.Completion_Tokens__c) : 0);
                promptToken+= (resp.Prompt_Tokens__c != null ? Integer.valueOf(resp.Prompt_Tokens__c) : 0);
                responseToBeUpdated.add(resp);
            }
            responseToBeUpdated.add(new AI_Response__c(
                    Id = parentAIResponse, 
                    Completion_Tokens__c = completionToken, 
                    Prompt_Tokens__c = promptToken, 
                    Status__c = AIConstants.RESP_STATUS_PROCESSED,
                    Is_Canvas_Response__c = true));
            
            FLSCheck.getInstance().upsertDML(responseToBeUpdated);
            
            AI_Response__c aiResponse = AICanvasService.fetchSecurityAuditRecord(parentAIResponse,recordId);

            if(aiResponse != null){
                return aiResponse;
            }
            return null;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description:
     *   Inner class that wraps component details of a Canvas Template.
     */
    public class SecurityAudit{
        @AuraEnabled public String Id;
        @AuraEnabled public String name;
        @AuraEnabled public String responseBody;
        @AuraEnabled public String feedbackType;
        @AuraEnabled public String message;
        @AuraEnabled public String howItWorks;
        @AuraEnabled public Double timeSaved;

        /**
         * @description:
         *  Constructor to convert and populate fields from the internal response structure.
         */
        public SecurityAudit(AI_Response__c aIResponse) {
            this.Id = aIResponse.Id;
            this.responseBody = aIResponse.AI_Processed_Data_PII_Added__c;
            this.name = aIResponse.Name;
            this.feedbackType = (aIResponse.Feedbacks__r != null && aIResponse.Feedbacks__r.size() > 0) ? aIResponse.Feedbacks__r[0].Type__c : '';
            this.message = aIResponse.Message__c;
            this.howItWorks = aIResponse.How_it_works__c;
            this.timeSaved = aIResponse.Time_Saved_Seconds__c;
        }
    }
    /**
     * @description:
     *   Inner class representing prompt metadata linked to the template.
     */
    public class CanvasTemplatePrompt {
        @AuraEnabled public String Id;
        @AuraEnabled public String promptRequestId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer autoRefreshDuration;


        public CanvasTemplatePrompt(AI_Prompt__c templatePrompt) {
            this.Id = templatePrompt.Id;
            this.promptRequestId = templatePrompt.Prompt_Request_Id__c;
            this.name = templatePrompt.Name;
            this.autoRefreshDuration = Integer.valueOf(templatePrompt.Auto_Refresh_Duration__c);
        }
    }

     /**
     * @description:
     *   Inner class that wraps component details of a Canvas Template.
     */
    public class PromptElement {
        @AuraEnabled public String Id;
        @AuraEnabled public String prompt;
        @AuraEnabled public String summaryPrompt;
        @AuraEnabled public Integer sequence;
        @AuraEnabled public String width;
        @AuraEnabled public Integer height;
        @AuraEnabled public String cardIcon;
        @AuraEnabled public String parentPrompt;
        @AuraEnabled public String response;
        @AuraEnabled public Boolean inheritPromptSecurity;

        public PromptElement(AI_Prompt_Element__c promptEle) {
            this.Id = promptEle.Id;
            this.prompt = promptEle.AI_Prompt__c;
            this.summaryPrompt = promptEle.AI_Summary_Prompt__c;
            this.sequence = Integer.valueOf(promptEle.Sequence__c);
            this.width = promptEle.Width__c;
            this.cardIcon = promptEle.Icon__c;
            this.height = Integer.valueOf(promptEle.Height__c);
            this.parentPrompt = promptEle.AI_Parent_Prompt__c;
            this.inheritPromptSecurity = promptEle.Inherit_Prompt_Security__c;
        }
        public PromptElement setResponse(String response){
            this.response = response;
            return this;
        }
    }

    /**
     * @description:
     *   Inner class representing prompt metadata linked to the template.
     */
    public class PromptDetail {
        @AuraEnabled public String Id;
        @AuraEnabled public String promptRequestId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer autoRefreshDuration;

        public PromptDetail(AI_Prompt__c prompt) {
            this.Id = prompt.Id;
            this.promptRequestId = prompt.Prompt_Request_Id__c;
            this.name = prompt.Name;
            this.autoRefreshDuration = Integer.valueOf(prompt.Auto_Refresh_Duration__c);
        }
    }
    /**
     * @description:
     *   Wrapper for combining Canvas Template Components and associated Prompts in one object.
     */
    public class CanvasDetails {
        @AuraEnabled public String userSignature;
        @AuraEnabled public String emailActionName;
        @AuraEnabled public PromptDetail prompt;
        @AuraEnabled public List<PromptElement> promptElements;
        @AuraEnabled public List<PromptDetail> promptDetails;
        @AuraEnabled public List<AIDataExtractionController.PicklistWrapper> picklistWrapper;
        @AuraEnabled public String namespace;

        public CanvasDetails(
                String userSignature,
                String emailActionName,
                PromptDetail prompt,
                List<PromptElement> promptElements, 
                List<PromptDetail> promptDetails,
                List<AIDataExtractionController.PicklistWrapper> picklistWrapper) {
            this.userSignature = userSignature;
            this.emailActionName = emailActionName;
            this.prompt = prompt;
            this.promptElements = promptElements;
            this.promptDetails = promptDetails;
            this.picklistWrapper = picklistWrapper;
            this.namespace = AIConstants.NAMESPACE;
        }
    }
}