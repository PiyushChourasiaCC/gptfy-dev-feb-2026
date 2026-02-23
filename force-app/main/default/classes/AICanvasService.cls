/**
 * @description:
 *   AICanvasService is a backend utility/service layer responsible for handling the 
 *   retrieval of AI Canvas templates, template components, prompts, and record-level 
 *   visibility logic based on user profile and conditions.
 *   It also handles the card level action like prompt callouts and summary propt callouts
 * 
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 04-09-2025
 * @last modified by  : Piyush Chourasia
 **/
public with sharing class AICanvasService {
    @TestVisible
    private static final String NO_PROMPT_ERROR = 'This prompt is currently unavailable or you lack the required permissions to access it. It may also belong to a different system object. Please contact your administrator or try using a different prompt.';
    @TestVisible
    private static final String INACTIVE_PROMPT_ERROR = 'This prompt has been deactivated and needs to be enabled before you can view responses. Please activate it to continue.';
    private static final String DIFFERENT_PROFILE_ERROR = 'The selected profile does not match the required criteria. Please verify your profile settings and try again.';
    private static final String DIFFERENT_PERMISSIONSETS_ERROR = 'The selected permission sets does not match the required criteria. Please verify your permission sets and try again.';
    @TestVisible
    private static final String SUCCESS_MESSAGE = 'Success';
    private static final String VISIBILITY_ERROR = 'Visibility Condition does not match.';
    public static final String NAMESPACE = AIPromptController.getNameSpace();


    /**
     * @description:
     *   Determines the most appropriate (winning) AI Canvas Template based on:
     *   - Object API name
     *   - User profile access (Profiles__c field)
     *   - Record-level visibility conditions
     *
     * @param recordId       - ID of the current record being evaluated
     * @param objectApiName  - API name of the SObject
     * @return Matched AI_Canvas_Template__c or null if none matches
     */
    public static AI_Prompt__c fetchWinnerPrompt(String recordId, String objectApiName) {
        String profileName = getCurrentUserProfileName();
        AI_Prompt__c winnerPrompt;
        Set<String> assignedPermissionsets = getCurrentUserPermissionSets();

        // Loop through all active templates for the object and find one matching the current profile
        for (AI_Prompt__c prompt : fetchAIPrompts(objectApiName)) {
            if(String.isBlank(prompt.Profiles__c) && String.isBlank(prompt.Permission_Sets__c)){
                winnerPrompt = prompt;
                break;
            }else if ((!String.isBlank(prompt.Profiles__c) && prompt.Profiles__c.containsIgnoreCase(profileName)) && 
                    !String.isBlank(prompt.Permission_Sets__c)  && !assignedPermissionSets.isEmpty() && GPTfyConsoleController.checkMatchingSets(assignedPermissionSets, prompt.Permission_Sets__c.toLowerCase().split(';'))) {
                winnerPrompt = prompt;
                break;
            }else if(!String.isBlank(prompt.Profiles__c) && prompt.Profiles__c.containsIgnoreCase(profileName)){
                winnerPrompt = prompt;
                break;
            }else if(!String.isBlank(prompt.Permission_Sets__c)  && !assignedPermissionSets.isEmpty() && GPTfyConsoleController.checkMatchingSets(assignedPermissionSets, prompt.Permission_Sets__c.toLowerCase().split(';'))){
                winnerPrompt = prompt;
                break;
            }
        }

        if (winnerPrompt == null) {
            return null;
        }

        // Check visibility condition at record level
        List<SObject> record = fetchCurrentRecord(recordId, objectApiName, winnerPrompt);
        if (record == null || record.isEmpty()) {
            return null;
        }

        return winnerPrompt;
    }

    /**
     * @description:
     *   Retrieves the current user's profile name
     *
     * @return Profile name of the logged-in user
     */
    public static String getCurrentUserProfileName() {
        List<Profile> profiles =  [SELECT Id, Name 
                                    FROM Profile 
                                    WHERE Id = :UserInfo.getProfileId() 
                                    LIMIT 1];
        if(!profiles.isEmpty()){
            return profiles[0].Name;
        }
        return null;
    }
    
    /**
     * @description:
     *   Retrieves the current user's permission sets name
     *
     * @return Permission Sets name of the logged-in user
     */
    public static Set<String> getCurrentUserPermissionSets() {
        String l_namespace = NAMESPACE;
        if(String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')){
            l_namespace = l_namespace.removeEndIgnoreCase('__');
        }
        // Jira 6566: Security - Permission Set Dependency
		Set<String> assignedPermissionSets = new Set<String>();        
        for(PermissionSetAssignment psa : [SELECT Id, PermissionSet.Label 
                                           FROM PermissionSetAssignment
                                           WHERE AssigneeId =:UserInfo.getUserId()]){
            assignedPermissionSets.add(psa.PermissionSet.Label.toLowerCase());
        }
        return assignedPermissionSets;
    }

    /**
     * @description:
     *   Fetches all active AI Canvas Templates for a given object type.
     *
     * @param objectApiName - API name of the object
     * @return List of AI_Canvas_Template__c records
     */
    private static List<AI_Prompt__c> fetchAIPrompts(String objectApiName) {
        return [
            SELECT Id, Object__c, Profiles__c, Auto_Refresh_Duration__c, Visibility_Condition__c, Permission_Sets__c
            FROM AI_Prompt__c 
            WHERE Status__c = :AIConstants.PMT_STATUS_ACTIVE 
            AND Type__c = 'Canvas'
            AND Object__c = :objectApiName
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    /**
     * @description:
     *   Retrieves the current user's signature
     *
     * @return signature of the logged-in user
     */
    public static String getUserSignature() {
        String userSignature = '';
        List<User> lstOfUser = [SELECT Id, Signature FROM User WHERE Id =:UserInfo.getUserId() LIMIT 1];
        if(lstOfUser != null && !lstOfUser.isEmpty()){
            userSignature = lstOfUser.get(0).Signature;
        }
        return userSignature;
    }
    /**
     * @description:
     *   Retrieves the current object's global email action
     *
     * @return email action name
     */
    public static String getEmailActionName(String objectApiName) {
        String emailActionName = '';
        List<QuickAction.DescribeAvailableQuickActionResult> lstOfQuickActions = QuickAction.DescribeAvailableQuickActions(objectApiName);
        if(lstOfQuickActions != null && !lstOfQuickActions.isEmpty()){
            for(QuickAction.DescribeAvailableQuickActionResult qa : lstOfQuickActions){
                if(qa.getType() == 'SendEmail'){
                    String actionName = qa.getName();
                    if(actionName.startsWithIgnoreCase(objectApiName)){
                        emailActionName = actionName;
                        break;
                    }else if(!actionName.startsWithIgnoreCase(objectApiName)){
                        emailActionName =  'Global.'+actionName;
                    }
                }
            }
        }
        return emailActionName;
    }
    /**
     * @description:
     *   Dynamically builds and executes a SOQL query to validate record-level visibility 
     *   based on the template's condition (Visibility_Condition__c).
     *
     * @param recordId       - ID of the current record
     * @param objectApiName  - API name of the object
     * @param winnerTemplate - Selected template to validate against
     * @return List<SObject> containing the record if it meets the condition, otherwise empty
     */
    private static List<SObject> fetchCurrentRecord(String recordId, String objectApiName, AI_Prompt__c winnerPrompt) {
        try {
            String query = 'SELECT Id FROM '+String.escapeSingleQuotes(objectApiName)+' WHERE Id =:recordId ';
            query = buildWhereClause(query, winnerPrompt);
            List<sobject> objList = Database.query(query);
        	return objList;
        }catch(Exception e){
            System.debug(e.getMessage());
            System.debug(e.getStackTraceString());
            return null;
        }
    }
     /**
     * @description:
     *   Dynamically prepares the where condition for the records
     *
     * @param query       - initial query
     * @param winnerTemplate - Selected template to validate against
     * @return String complete query
     */
    public static String buildWhereClause(String query, AI_Prompt__c winnerPrompt){
        String whereClause = winnerPrompt?.Visibility_Condition__c != null ? winnerPrompt?.Visibility_Condition__c : '';
        if(String.isNotBlank(whereClause)){
            whereClause = whereClause.trim();
            if(whereClause.startsWithIgnoreCase('ORDER BY ') || whereClause.startsWithIgnoreCase('LIMIT ')){
                query += ' '+String.escapeSingleQuotes(whereClause);
            }else{
                query += ' AND '+String.escapeSingleQuotes(whereClause);
            }
        }
        if(query.containsIgnoreCase(' LIMIT ')){
            Integer index = query.lastIndexOfIgnoreCase(' LIMIT ');
            if(index > -1){
                query = query.substring(0, index);
            }
        }
        query += ' LIMIT 5000 ';

        query = query.replace('\\\'', '\'');
        return query;
    }

    /**
     * @description:
     *   Fetches AI Prompt records by a given set of IDs.
     *
     * @param promptIds - Set of AI_Prompt__c record IDs to retrieve
     * @return List of AI_Prompt__c records
     */
    public static List<AI_Prompt__c> fetchPrompts(Set<Id> promptIds) {
        List<AI_Prompt__c> prompts = [SELECT Id, Prompt_Request_Id__c, Name, Auto_Refresh_Duration__c
                                        FROM AI_Prompt__c 
                                        WHERE Id IN :promptIds];

        return prompts;
    }
    /**
      * @description:
     *  Makes a REST API callout and optionally updates a parent Security Audit record
     *  with the returned AI response details if successful.
     * 
     * @param requestJSON - Json request from the lwc
     * @param promptId    - Prompt Id to be fired
     * @param parentAuditRecordId    - parent security audit record id
     * @param templateComponentId    - canvas template component Id
     * @return AICanvasCardController.ResponseWrapper - an wrapper that holds AI response 
     */
    public static AICanvasCardController.ResponseWrapper invokeCallout(
            String requestJSON, 
            String promptId,  
            String parentAIResponseId,
            String recordId,
            AICanvasController.PromptElement elementWrap){
        AIPromptProcessingInvokable.ResponseWrapper response = new AIPromptProcessingInvokable.ResponseWrapper();
        // Security Audit record that will be created
        AI_Response__c aIResponse;

        try {
            // Perform the callout
            response = doCallout(requestJSON, promptId, response);
            // Only process when found one response record created
            if(response.responseId != null && !String.isBlank(response.responseId)){
                // First update the security audit with canvas template component id
                updateSecurityAuditRecord(response.responseId, parentAIResponseId,elementWrap);
                // Now fetch the newly created security audit record 
                aIResponse = fetchSecurityAuditRecord(response.responseId,recordId); 
            }
            if(aIResponse != null){
                return new AICanvasCardController.ResponseWrapper(aIResponse);
            }
            if(response != null && response.message != null){
                return new AICanvasCardController.ResponseWrapper(response.message);
            }
        } catch(Exception exp) {
            // Catch and store error message in response
            return new AICanvasCardController.ResponseWrapper(exp.getMessage());
        }
        return null;
    }
    /**
     * @description:
     *  helper method to update the existing Ai Response with parent audit and canvas template
     * 
     * @param responseId - AI Response Id
     * @param parentAuditRecordId    - Parent Security Record record Id 
     * @param templateComponentId    - canvas template component Id
     * @Jira V2-6591
     */
    public static void updateSecurityAuditRecord(String responseId, String parentAIResponseId,AICanvasController.PromptElement elementWrap){
        // Update AI_Response__c with parent audit linkage if response ID is present
        if (!String.isBlank(responseId)) {
            // New instance with Existing record Id and canvas template component Id
            AI_Response__c aIResponse = new AI_Response__c(Id = responseId, AI_Parent_Response__c = parentAIResponseId);
            if(elementWrap != null){
                aIResponse.Prompt_Element_Details__c = JSON.serialize(elementWrap);
            }
            // Upser record
            FLSCheck.getInstance().upsertDML(new List<AI_Response__c>{aIResponse});
        }
    }
    /**
     * @description:
     *      helper method to deserialize request JSON and perform the API callout.
     * 
     * @param requestJSON - JSON string representing the AI prompt request wrapper
     * @param promptId    - The ID of the AI prompt
     * @param response    - The response object to be populated
     * @return ResponseWrapper containing the callout result
     */
    public static AIPromptProcessingInvokable.ResponseWrapper doCallout(String requestJSON, String promptId, AIPromptProcessingInvokable.ResponseWrapper response) {
        // Deserialize input JSON into a RequestWrapper object
        AIPromptProcessingInvokable.RequestWrapper request = 
            (AIPromptProcessingInvokable.RequestWrapper) JSON.deserialize(requestJSON, AIPromptProcessingInvokable.RequestWrapper.class);

        // Perform the actual callout using the invokable logic
        return AIPromptProcessingInvokable.invokeCallout(request, response, promptId);
    }
     /**
     * @description:
     *  helper method to fetch the security Audit record with the feedbacks
     * 
     * @param securityAuditRecordId - JSON string representing the AI prompt request wrapper
     * @return AI_Response__c the desirect security audit record
     * @Jira V2-6591
     */
    public static AI_Response__c fetchSecurityAuditRecord(String securityAuditRecordId, String recordId){
        List<AI_Response__c> responses =  [SELECT Id, Name, AI_Processed_Data_No_PII__c, AI_Processed_Data_PII_Added__c,Message__c,How_it_works__c,Time_Saved_Seconds__c,
                                AI_Prompt__c, Status__c,CreatedDate,LastModifiedDate,Is_Canvas_Response__c,Record_Id__c,Data_PII_Key__c,Prompt_Tokens__c,
                                Total_Tokens__c,Time_Estimate_Seconds__c,Profiles__c,Data_Original__c,Data_PII_Removed__c,Completion_Tokens__c,
                                (SELECT Id, Type__c FROM Feedbacks__r WHERE User__c =:UserInfo.getUserId() LIMIT 1),
                                (SELECT Id,Prompt_Element_Details__c FROM Parent_Security_Audits__r WHERE CreatedById =:UserInfo.getUserId())
                                FROM AI_Response__c WHERE Id =:securityAuditRecordId 
                                AND (CreatedById =:UserInfo.getUserId() OR Scheduled_Run__c != NULL)
                                AND Record_Id__c = :recordId
                                ORDER BY CreatedDate DESC
                                LIMIT 1];
        if(!responses.isEmpty()){
            return responses.get(0);
        }
        return null;
    }
    public static AI_Response__c fetchSecurityAuditRecordByPromptId(String promptId, String recordId){
        List<AI_Response__c> responses =  [SELECT Id, Name, AI_Processed_Data_No_PII__c, AI_Processed_Data_PII_Added__c,Message__c,How_it_works__c,Time_Saved_Seconds__c,
                                AI_Prompt__c, Status__c,CreatedDate,
                                (SELECT Id, Type__c FROM Feedbacks__r WHERE User__c =:UserInfo.getUserId() LIMIT 1),
                                (SELECT Id,Prompt_Element_Details__c FROM Parent_Security_Audits__r WHERE CreatedById =:UserInfo.getUserId())
                                FROM AI_Response__c WHERE AI_Prompt__c = :promptId
                                AND (CreatedById =:UserInfo.getUserId() OR Scheduled_Run__c != NULL)
                                AND Record_Id__c = :recordId
                                ORDER BY CreatedDate DESC
                                LIMIT 1];
        if(!responses.isEmpty()){
            return responses.get(0);
        }
        return null;
    }
    public static List<AI_Response__c> fetchAIResponses(Set<Id> childAIReponseIds, String recordId){
        List<AI_Response__c> responses =  [SELECT Id, Name, Prompt_Tokens__c, Completion_Tokens__c
                                FROM AI_Response__c 
                                WHERE Id IN :childAIReponseIds
                                AND Record_Id__c = :recordId];
        if(!responses.isEmpty()){
            return responses;
        }
        return null;
    }
    /**
     * @description:
     *  helper method to fetch the security Audit record with the feedbacks by prompt Id
     * 
     * @param securityAuditRecordId - JSON string representing the AI prompt request wrapper
     * @return AI_Response__c the desirect security audit record
     */
    public static AI_Response__c fetchSecurityAuditByPromptId(String promptId,String parentAIResponse, String recordId){
        List<AI_Response__c> responses =  [SELECT Id, Name, AI_Processed_Data_No_PII__c, AI_Processed_Data_PII_Added__c,Message__c,How_it_works__c, Time_Saved_Seconds__c,
                                            (SELECT Id, Type__c FROM Feedbacks__r WHERE User__c =:UserInfo.getUserId() LIMIT 1)
                                            FROM AI_Response__c WHERE AI_Prompt__c = :promptId 
                                            AND AI_Parent_Response__c = :parentAIResponse 
                                            AND (CreatedById =:UserInfo.getUserId() OR Scheduled_Run__c != NULL)
                                            AND Record_Id__c = :recordId
                                            ORDER BY CreatedDate DESC
                                            LIMIT 1];
        if(!responses.isEmpty()){
            return responses.get(0);
        }
        return null;
    }
     /**
     * @description:
     *  helper method to check if the prompt is active or not
     * 
     * @param promptId - Id of the prompt
     * @return Boolean either active or not
     */
    public static String validatePrompt(String promptId, String recordId, String objectApiName){
        String profileName = getCurrentUserProfileName();
        Set<String> assignedPermissionsets = getCurrentUserPermissionSets();
        List<AI_Prompt__c> prompts = [SELECT Id, Status__c, Profiles__c, Visibility_Condition__c, Visibility_Exception_Message__c,Permission_Sets__c
                                    FROM AI_Prompt__c 
                                    WHERE Id = :promptId 
                                    AND Object__c = :objectApiName];
        return getValidationMessage(prompts,profileName,recordId,objectApiName,assignedPermissionsets);
    }
    private static String getValidationMessage(List<AI_Prompt__c> prompts, String profileName,String recordId,String objectApiName,Set<String> assignedPermissionsets){
        if(prompts.isEmpty()){
            return NO_PROMPT_ERROR;
        }else if(!prompts.isEmpty() && prompts[0].Status__c != 'Active'){
            return INACTIVE_PROMPT_ERROR;
        }else if(!String.isBlank(prompts[0].Profiles__c)  && !prompts[0].Profiles__c.containsIgnoreCase(profileName)){
            return DIFFERENT_PROFILE_ERROR;
        }else if(!String.isBlank(prompts[0].Permission_Sets__c)  && !assignedPermissionSets.isEmpty() && !GPTfyConsoleController.checkMatchingSets(assignedPermissionSets, prompts[0].Permission_Sets__c.toLowerCase().split(';'))){
            return DIFFERENT_PERMISSIONSETS_ERROR;
        }else{
            // Check visibility condition at record level
            List<SObject> record = fetchCurrentRecord(recordId, objectApiName,prompts[0]);
            if (record == null || record.isEmpty()) {
                if(String.isBlank(prompts[0].Visibility_Exception_Message__c)){
                    return VISIBILITY_ERROR;
                }
                return prompts[0].Visibility_Exception_Message__c;
            }
            return SUCCESS_MESSAGE;
        }
    }
    /**
     * @description:
     *  helper method to check if the prompt is active or not
     * 
     * @param promptId - Id of the prompt
     * @return Boolean either active or not
     */
    public static String validatePrompt(String promptId, String objectApiName){
        List<AI_Prompt__c> prompts = [SELECT Id, Status__c, Profiles__c, Visibility_Condition__c
                                        FROM AI_Prompt__c 
                                        WHERE Id = :promptId 
                                        AND Object__c = :objectApiName];
        if(prompts.isEmpty()){
            return NO_PROMPT_ERROR;
        }else if(!prompts.isEmpty() && prompts[0].Status__c != 'Active'){
            return INACTIVE_PROMPT_ERROR;
        }
        return SUCCESS_MESSAGE;
    }
    /**
     * @description:
     *  helper method to check if the prompt is active or not
     * 
     * @param promptId - Id of the prompt
     * @return Boolean either active or not
     */
    public static String validateSummaryPrompt(String promptId, String objectApiName, String recordId){
        String profileName = getCurrentUserProfileName();
        Set<String> assignedPermissionsets = getCurrentUserPermissionSets();
        List<AI_Prompt__c> prompts = [SELECT Id, Status__c, Profiles__c, Visibility_Condition__c,Visibility_Exception_Message__c, Permission_Sets__c
                                    FROM AI_Prompt__c 
                                    WHERE Id = :promptId];
        return getValidationMessage(prompts,profileName,recordId,objectApiName,assignedPermissionsets);
    }
     /**
     * @description:
     *  helper method to check if the prompt is active or not
     * 
     * @param promptId - Id of the prompt
     * @return Boolean either active or not
     */
    public static String validateSummaryPrompt(String promptId){
        List<AI_Prompt__c> prompts = [SELECT Id, Status__c, Profiles__c, Visibility_Condition__c
                                        FROM AI_Prompt__c 
                                        WHERE Id = :promptId];
        if(prompts.isEmpty()){
            return NO_PROMPT_ERROR;
        }else if(!prompts.isEmpty() && prompts[0].Status__c != 'Active'){
            return INACTIVE_PROMPT_ERROR;
        }
        return SUCCESS_MESSAGE;
    }

    ////////////////////////////////////////
    /**
     * @description:
     *   Fetches all active AI Canvas Templates for a given object type.
     *
     * @param objectApiName - API name of the object
     * @return List of AI_Canvas_Template__c records
     */
    public static List<AI_Prompt_Element__c> getPromptElementsByPromptId(String promptId) {
        List<AI_Prompt_Element__c> promptElements = [SELECT Id, Height__c, Width__c, AI_Prompt__c, AI_Parent_Prompt__c, Icon__c, 
                                                    Sequence__c, AI_Summary_Prompt__c, Inherit_Prompt_Security__c
                                                    FROM AI_Prompt_Element__c 
                                                    WHERE AI_Parent_Prompt__c = :promptId
                                                ];
        return promptElements;
    }
    /**
     * @description:
     *  helper method to fetch the security Audit record with the feedbacks by prompt Id
     * 
     * @param securityAuditRecordId - JSON string representing the AI prompt request wrapper
     * @return AI_Response__c the desirect security audit record
     */
    public static List<AI_Response__c> getSecurityAuditsByParent(String parentAuditId){
        List<AI_Response__c> responses =  [SELECT Id, Name, AI_Processed_Data_PII_Added__c
                                            FROM AI_Response__c 
                                            WHERE AI_Parent_Response__c =:parentAuditId];
       return responses;
    }
    /**
     * @description:
     *  helper method to fetch the security Audit record with the feedbacks by prompt Id
     * 
     * @param securityAuditRecordId - JSON string representing the AI prompt request wrapper
     * @return AI_Response__c the desirect security audit record
     */
    public static AI_Prompt__c getPromptDetails(String recordId, String objectApiName,String promptId){
        String profileName = getCurrentUserProfileName();
        Set<String> assignedPermissionsets = getCurrentUserPermissionSets();

        AI_Prompt__c winnerPrompt;
        List<AI_Prompt__c> prompts =  [SELECT Id, Name,Object__c,Auto_Refresh_Duration__c,Prompt_Request_Id__c, Profiles__c, Permission_Sets__c,
                                        Visibility_Condition__c,Visibility_Exception_Message__c
                                        FROM AI_Prompt__c 
                                        WHERE Id =:promptId];

        if(prompts.isEmpty()){
            return null;
        }else if(String.isBlank(prompts[0].Profiles__c) && String.isBlank(prompts[0].Permission_Sets__c)){
            winnerPrompt = prompts[0];
        }else if ((!String.isBlank(prompts[0].Profiles__c) && prompts[0].Profiles__c.containsIgnoreCase(profileName)) && 
                !String.isBlank(prompts[0].Permission_Sets__c)  && !assignedPermissionSets.isEmpty() && GPTfyConsoleController.checkMatchingSets(assignedPermissionSets, prompts[0].Permission_Sets__c.toLowerCase().split(';'))) {
            winnerPrompt = prompts[0];
        }else if(!String.isBlank(prompts[0].Profiles__c) && prompts[0].Profiles__c.containsIgnoreCase(profileName)){
            winnerPrompt = prompts[0];
        }else if(!String.isBlank(prompts[0].Permission_Sets__c)  && !assignedPermissionSets.isEmpty() && GPTfyConsoleController.checkMatchingSets(assignedPermissionSets, prompts[0].Permission_Sets__c.toLowerCase().split(';'))){
            winnerPrompt = prompts[0];
        }
        System.debug(winnerPrompt);
        if (winnerPrompt == null) {
            return null;
        }

        // Check visibility condition at record level
        List<SObject> record = fetchCurrentRecord(recordId, objectApiName, winnerPrompt);
        if (record == null || record.isEmpty()) {
            return null;
        }

        return winnerPrompt;
    }
}