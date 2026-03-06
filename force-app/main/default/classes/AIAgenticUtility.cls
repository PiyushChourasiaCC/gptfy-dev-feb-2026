/**
 * @description:
 *   AIAgenticUtility is a backend utility/service layer responsible for handling the 
 *   retrieval of agentic prompts, user permissions, and GPT interactions.
 *   It also manages dynamic queries and integrates with external AI services.
 * 
 * @author            : Rishabh Goel
 * @group             : Plumcloud Labs
 * @last modified on  : 29-07-2025
 * @last modified by  : Rishabh Goel
 **/
global with sharing class AIAgenticUtility {
    
    /** Namespace for agentic prompts and permission sets. */
    public static final String NAMESPACE = AIPromptController.getNameSpace();

    /** Standard chat expiration message. */
    public static final String CHAT_EXPIRED = Label.CHAT_EXPIRED;

    /** Message when AI context loss or exception happens. */
    public static final String AI_FAILED_IN_LAST_STEP = Label.AI_Failed_In_Last_Step;
    /** Instructions for generating record links in agentic output. */
    public static final String SYSTEM_PROMPT_INTERNAL = Label.AI_Current_Record_Identification_Instructions;  

    public static final String STRICT_INSTRUCTIONS = Label.AI_View_Record_Hyperlink_Instructions;
    
    // /** Strict system instructions for prompt context. */
    // public static final String STRICT_INSTRUCTIONS = 'IMPORTANT: For each provided record, add a Link to the record on "View Record" distinctly and clearly.'+
    //         'Generate this link using the current Salesforce'+
    //         'base URL, appending the specific record`s ID to the end of the URL path (USE: '+URL.getOrgDomainUrl().toExternalForm() + '/<RecordId>) '+
    //         'and replace the <RecordId> with the actual record Id received in the response.'+ 
    //         'The link must reliably open the record in view-only (read-only) mode. Ensure the record ID is embedded in the URL for proper navigation, '+
    //         'but is not displayed elsewhere on the UI.';

    /**
     * Custom exception for agentic utility error handling.
     */
    public class AIAgenticUtilityException extends Exception {}

    // ---------- Helper Error Response Utilities ----------

    /**
     * Returns a standardized error response wrapper for exceptions.
     * @param ex Exception encountered in processing.
     * @return AIAgenticWebService.ResponseWrapper indicating error status.
     */
    @TestVisible
    private static AIAgenticWebService.ResponseWrapper errorResponse(Exception ex) {
        AIAgenticWebService.ResponseWrapper resp = new AIAgenticWebService.ResponseWrapper();
        resp.status = 'Error';
        resp.statusCode = 500;
        resp.message = ex.getMessage();
        return resp;
    }

    /**
     * Returns a standardized error response wrapper for string messages.
     * @param msg Error message string.
     * @return AIAgenticWebService.ResponseWrapper indicating error status.
     */
    @TestVisible
    private static AIAgenticWebService.ResponseWrapper errorResponse(String msg) {
        AIAgenticWebService.ResponseWrapper resp = new AIAgenticWebService.ResponseWrapper();
        resp.status = 'Error';
        resp.statusCode = 500;
        resp.message = msg;
        return resp;
    }

    // ---------- Main Agent Invocation ----------
    /**
     * Main agent invocation entry point: handles session validation, conversation context,
     * function execution, AI callouts, response management, and audit tracking.
     * @param request Agentic request wrapper to process.
     * @return AIAgenticWebService.ResponseWrapper with AI response.
     * @jira: V2-7341
     */
    global static AIAgenticWebService.ResponseWrapper invokeAgent(AIAgenticWebService.RequestWrapper request) {
        try {
            // Prepare for agentic call: context, audit, permissions, etc.
            List<FunctionResult> fncResults = new List<FunctionResult>();
            AIAgenticWebService.ResponseWrapper response = new AIAgenticWebService.ResponseWrapper();
            AI_Response__c aiResponse = getAIResponseByThreadId(request.userContextId);
            aiResponse.Client__c = request.userAgent;

            if(request.setOfVectorStoreIds != null && request.setOfVectorStoreIds.size() > 0){
                List<String> vectorStoreIdsList = new List<String>(request.setOfVectorStoreIds);
                aiResponse.Vector_Store_Id__c = vectorStoreIdsList[0];
            }

            request = getPromptOptions(request,aiResponse);

            aiResponse.Agent_Name__c = request.config.Name;
            // Validate session TTL if response record exists
            if(aiResponse.Id != null){
                String sessionInfo = AIAgenticChatController.validateTTL(request.userContextId, (request.config.TTL__c != null ||  request.config.TTL__c != 0 ? request.config.TTL__c : null));
                if(sessionInfo == 'Invalid Session'){
                    response.message = (request.config.TTL_Message__c != null ? request.config.TTL_Message__c : CHAT_EXPIRED);
                    return response;
                }
                // If using threadId, set conversation context for multi-turn dialogs
                if(aiResponse.Thread_Id__c != null && String.isNotBlank(aiResponse.Thread_Id__c) && request.config.Use_Thread_Id__c){
                    request.previousResponseId = aiResponse.Thread_Id__c;
                }else{
                    request.previousResponseId = null;
                }
            }
            if(aiResponse.User_Context_Id__c == null || String.isBlank(aiResponse.User_Context_Id__c)){
                aiResponse.User_Context_Id__c = request.userContextId;
            }
            List<AI_Security_Audit_Detail__c> securityAuditDetails = getSecurityAuditDetailRecord(aiResponse.Id);

            // Build conversation history for the prompt
            request.conversation = getPreviousInterations(securityAuditDetails, request);

            // Use last audit detail for session update
            AI_Security_Audit_Detail__c securityAuditDetail = securityAuditDetails[securityAuditDetails.size()-1];

            aiResponse.AI_Callout_Start_Time__c = System.now();
            // Check if AI Model has a Processing Class — if so, bypass AI callout entirely
            if(String.isNotBlank(request.config.AI_Model__r.Processing_Class__c)){
                try {
                    Type processingType = Type.forName('', request.config.AI_Model__r.Processing_Class__c);
                    if(processingType == null){
                        response.message = 'Processing class not found: ' + request.config.AI_Model__r.Processing_Class__c;
                        return response;
                    }
                    AIAgenticProcessingInterface processor = (AIAgenticProcessingInterface) processingType.newInstance();
                    response.responseBody = processor.getProcessedResponse(request);
                    aiResponse.AI_Callout_End_Time__c = System.now();
                    aiResponse.AI_Processed_Data_No_PII__c = response.responseBody;
                    aiResponse.AI_Processed_Data_PII_Added__c = response.responseBody;
                } catch (Exception procEx) {
                    response.message = 'Error executing processing class: ' + procEx.getMessage();
                    return response;
                }
            } else {
                response = AIAgenticCalloutService.fetchQualifiedPrompt(request);
                //System.debug(response);
                // Handle context loss on API error
                if(response.message != null && String.isNotBlank(response.message)){
                    response.message = AI_FAILED_IN_LAST_STEP;
                    aiResponse.Status__c = AIConstants.RESP_STATUS_PROCESSED;
                    ChatGPTUtills.insertAIResponse(aiResponse, true);
                    return response;
                }
                response = getThreadId(response, aiResponse.Thread_Id__c);

                aiResponse.Thread_Id__c = (response.userContextId != null && String.isNotBlank(response.userContextId)) ? response.userContextId : aiResponse.Thread_Id__c;
                aiResponse.AI_Callout_End_Time__c = System.now();
                aiResponse.AI_Processed_Data_No_PII__c = response.responseBody;
                System.debug('Sagar1: Response.responseBody ' + response.responseBody); 
                // Parse and handle function call details from AI output
                ResponseDetails responseDetailsObj = getParsedResponse(response.responseBody);
                aiResponse.AI_Processed_Data_PII_Added__c = aiResponse.AI_Processed_Data_PII_Added__c != null ? aiResponse.AI_Processed_Data_PII_Added__c : JSON.serialize(responseDetailsObj);
                System.debug('Sagar1: ResponseDetailsObj = ' + JSON.serialize(responseDetailsObj));
                // If we have messages, process Agent Intents
                if(responseDetailsObj != null && responseDetailsObj.messages.size() > 0){
                    response.responseBody = String.join(responseDetailsObj.messages, ',');
                }else{
                    for (FunctionCallDetail fncDetail : responseDetailsObj.fncDetails) {
                        Map<String, Object> functionParams = fncDetail.arguments;

                        try {
                            AI_Prompt__c prompt = AIPromptSelector.getAIPromptByName(fncDetail.name);
                            aiResponse = getPreparedAIResponse(aiResponse, prompt);
                            Type impl = Type.forName('', prompt.Agentic_Function_Class__c);
                            AIAgenticInterface obj = (AIAgenticInterface) impl.newInstance();
                            String results = obj.executeMethod(prompt.Name, functionParams);
                            response.responseBody = getMessageFromResult(results);
                            fncResults.add(new FunctionResult(fncDetail.name, fncDetail.callId, results));
                        } catch (Exception execEx) {
                            return errorResponse(execEx);
                        }
                    }
                    try {
                        List<Object> messages = getAssistantCallInput(request.conversation, responseDetailsObj.fncDetails, fncResults);
                        Map<String,String> assitantCallResponse = AIAgenticCalloutService.getAssistantReply(request, messages);
                        response.responseBody = assitantCallResponse.get('response');
                        aiResponse.Thread_Id__c = assitantCallResponse.get('threadId');
                    } catch (Exception calloutExp) {
                        // Fails silently; context remains
                    }
                }
            }

            if (request.agentIntents != null && !request.agentIntents.isEmpty()) {
                    // Build RequestContext for Update Field actions
                    System.debug('Sagar1:beforeCalling ActionContext');
                    AgentActionProcessor.RequestContext actionContext = new AgentActionProcessor.RequestContext(
                        request.relatedToId,
                        request.recordId
                    );
                    System.debug(': ActionContext = ' + JSON.serialize(actionContext));
                    AgentActionProcessor.ActionResult actionResult = AgentActionProcessor.process(response.responseBody, request.config.Id, actionContext);
                    System.debug('Sagar1: ActionResult = ' + JSON.serialize(actionResult));
                    if(response.responseBody != null) {
                        response.responseBody = actionResult.message;
                    }
                    response.intents = actionResult.intents;
                    response.detectedLanguage = actionResult.language;
                }
            // Audit new chat detail interactions
            securityAuditDetail = getDetailWithChatInteractions(securityAuditDetail, request.userMessage, response.responseBody, fncResults);

            // Track AI usage and update tokens/save time
            List<AI_Usage_Tracking__c> upsertList = new List<AI_Usage_Tracking__c>();
            aiResponse = AIUsageTrackingController.getTokensFromResponse(aiResponse);
            if(aiResponse.Total_Tokens__c > 0){
                List<AI_Usage_Tracking__c> lstOfTrackings = AIUsageTrackingController.getUsageTrackings(aiResponse);
                if(lstOfTrackings != null && !lstOfTrackings.isEmpty()){
                    upsertList.addAll(lstOfTrackings);
                }
            }
            // Set error for blank AI outputs
            if(String.isBlank(aiResponse.AI_Processed_Data_PII_Added__c)){
                aiResponse.Message__c = AIConstants.AI_BLANK_RESPONSE;
                aiResponse.Status__c = AIConstants.RESP_STATUS_ERROR;
            }

            aiResponse.End_Date_Time__c = System.Now();
            aiResponse = ChatGPTUtills.insertAIResponse(aiResponse, true);
            response.responseId = aiResponse.Name;
            response.userContextId = getAIResponseUserContextId(aiResponse, request.userContextId);

            if(securityAuditDetail.AI_Security_Audit__c == null){
                securityAuditDetail.AI_Security_Audit__c = aiResponse.Id;
            }

            // User-based license usage audit
            AILicenseManagerController.updateLicenseUsage();

            // Update tracking with time/save info if present
            if(aiResponse != null && !upsertList.isEmpty()){
                for(AI_Usage_Tracking__c track : upsertList){
                    track.Lifetime_Saving_Seconds__c += aiResponse?.Time_Saved_Seconds__c != null ? aiResponse?.Time_Saved_Seconds__c : 0;
                }
                List<AI_Usage_Tracking__c> utList = FLSCheck.getInstance().upsertDML(upsertList);
                AIUsageTrackingController.upsertUsageTrackingDetails(utList, aiResponse.Time_Saved_Seconds__c);
            }
            FLSCheck.getInstance().upsertDML(new List<AI_Security_Audit_Detail__c> {securityAuditDetail});
            return response;
        } catch (Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * Builds the user conversation context/history for prompt invocation, including prior interactions.
     * @param securityAuditDetails List of prior audit details.
     * @param request              Current agentic request wrapper.
     * @return List<Object>        History payload for OpenAI/agentic prompt.
     * @jira: V2-7341
     */
    public static List<Object> getPreviousInterations(List<AI_Security_Audit_Detail__c> securityAuditDetails, AIAgenticWebService.RequestWrapper request){
        List<Map<String, Object>> contentArray = new List<Map<String, Object>>();
        contentArray.add(new Map<String, Object>{
            'type' => 'input_text',
            'text' => String.format(STRICT_INSTRUCTIONS, new List<Object> {URL.getOrgDomainUrl().toExternalForm()}) + 
                      (String.isNotBlank(request.developerInstructions) ? '\n\n' + SYSTEM_PROMPT_INTERNAL + '\n\nCURRENT RECORD CONTEXT: ' + request.developerInstructions : '') +
                      '\n\n' + extractExtraInformationFromRequest(request) + '\n\n User: ' + request.userMessage
        });
        if(request.imageFileIds != null && request.imageFileIds.size() > 0){
            for(String fileId : request.imageFileIds){
                contentArray.add(new Map<String,Object>{
                    'type' => 'input_image',
                    'file_id' => fileId
                });
            }
        }
        List<Object> previousInterations = new List<Object>();
        if(request.config.Use_Thread_Id__c){
            previousInterations.add(new Map<String,Object>{'role' => 'user', 'content' => contentArray});
            return previousInterations;
        }
        for(AI_Security_Audit_Detail__c detail : securityAuditDetails){
            if(!String.isBlank(detail.Message__c)){
                List<Object> detailInterations = (List<Object>)JSON.deserializeUntyped(detail.Message__c);
                previousInterations.addAll(detailInterations);
            }
        }
        previousInterations.add(new Map<String,Object>{'role' => 'user', 'content' => contentArray});
        return previousInterations;
    }
    public static String extractExtraInformationFromRequest(AIAgenticWebService.RequestWrapper request){
        String extraInformations = Label.AI_Response_Formatting_Instructions, additionalInfo = '';

        List<User> users = fetchUser(request.userIdentificationField, request.userIdentificationValue);
        if(!users.isEmpty()){
            if(request.additionalInformation != null && request.additionalInformation.size() > 0){
                additionalInfo = 'Responses must use the ';
                for(String key : request.additionalInformation.keySet()){
                    additionalInfo+= key = ' = ' + String.valueOf(request.additionalInformation.get(key)) + ',';
                }
                additionalInfo = additionalInfo.subStringBeforeLast(',') + ' details to answer user`s questions. Enforce these requirements throughout every interaction without exception.'; 
            }
            return String.format(extraInformations, new List<Object>{
                (request.language != null ? request.language : users[0].LanguageLocaleKey),
                (request.locale != null ? request.locale : users[0].LocaleSidKey) ,
                additionalInfo,
                (request.format != null ? request.format : 'HTML.')
            });
        }
        return String.format(extraInformations, new List<Object>{
            (request.language != null ? request.language : 'English' ),
            (request.locale != null ? request.locale : 'English (Canada)' ) ,
            additionalInfo,
            (request.format != null ? request.format : 'HTML.')
        });
    }

    /**
     * Updates the chat history for the given audit detail record, serializes the session.
     * @param detail         Audit detail record.
     * @param userMessage    Current user message.
     * @param assistantReply AI assistant reply.
     * @param results        List of function results executed in session.
     * @return Updated audit detail record.
     */
    public static AI_Security_Audit_Detail__c getDetailWithChatInteractions(AI_Security_Audit_Detail__c detail, String userMessage, String assistantReply, List<FunctionResult> results){
        Integer maxLength = AI_Security_Audit_Detail__c.Message__c.getDescribe().getLength();
        List<ChatHistory> previousChats = new List<ChatHistory>();
        List<ChatHistory> currentChats = new List<ChatHistory>();

        currentChats.add(new ChatHistory('user', userMessage));
        currentChats.add(new ChatHistory('assistant', assistantReply));
        currentChats.add(new ChatHistory('developer', ''));

        String serializedCurrentChat =  JSON.serialize(currentChats);
        if(String.isEmpty(detail.Message__c)){
            detail.Message__c = serializedCurrentChat;
            return detail;
        }else if((detail.Message__c.length() + serializedCurrentChat.length()) > maxLength){
            return new AI_Security_Audit_Detail__c(Type__c = AIConstants.AI_MODEL_TYPE_CHAT, Message__c = serializedCurrentChat);
        }else{
            previousChats = (List<ChatHistory>) JSON.deserialize(detail.Message__c, List<ChatHistory>.class);
            previousChats.addAll(currentChats);
            detail.Message__c = JSON.serialize(previousChats);
        }
        return detail;
    }

    /**
     * Retrieves all Security Audit Details for a given AI Response record id, or returns a new record if none exist.
     * @param responseId Response record Id to query by.
     * @return List of audit detail records.
     */
    public static List<AI_Security_Audit_Detail__c>  getSecurityAuditDetailRecord(String responseId){
        List<AI_Security_Audit_Detail__c> securityAuditDetails = [
            SELECT Id, Message__c, Type__c, AI_Security_Audit__c
            FROM AI_Security_Audit_Detail__c 
            WHERE AI_Security_Audit__c = :responseId
            AND Type__c = :AIConstants.AI_MODEL_TYPE_CHAT
            ORDER BY CreatedDate ASC
        ];
        if(securityAuditDetails.isEmpty()){
            return new List<AI_Security_Audit_Detail__c> {new AI_Security_Audit_Detail__c(Type__c = AIConstants.AI_MODEL_TYPE_CHAT)};
        }else{
            return securityAuditDetails;
        }
    }

    /**
     * Utility to extract 'message' from returned JSON or fallback to raw string.
     * @param result Raw JSON or string returned from AI.
     * @return Parsed message string.
     */
    public static String getMessageFromResult(String result){
        if (String.isBlank(result)) return result;
        try {
            Map<String,Object> parsedJson = (Map<String,Object>)JSON.deserializeUntyped(result);
            if(parsedJson.containsKey('message')){
                return String.valueOf(parsedJson.get('message'));
            }
            return result;
        } catch (Exception e) {
            return result;
        }
    }

    /**
     * Gets User Context Id for response, updating the record if needed.
     * @param response   AI_Response__c record.
     * @param threadId   Thread/session id.
     * @return Updated User Context Id string.
     */
    public static String getAIResponseUserContextId(AI_Response__c response, String threadId){
        if(!String.isBlank(threadId)){
            return threadId;
        }
        List<AI_Response__c> responses = [SELECT Id, Name,User_Context_Id__c FROM AI_Response__c WHERE Id = :response.Id];
        responses[0].User_Context_Id__c = responses[0].Name;
        FLSCheck.getInstance().updateDML(new List<AI_Response__c> {responses[0]});
        return responses[0].User_Context_Id__c;
    }

    /**
     * Builds assistant call input by combining previous messages, new calls, and results.
     * @param messages Prior messages for context.
     * @param calls    Function calls to be included.
     * @param results  Results from previous function executions.
     * @return List of assistant input objects.
     */
    public static List<Object> getAssistantCallInput(List<Object> messages, List<FunctionCallDetail> calls, List<FunctionResult> results ){
        for(FunctionCallDetail call : calls) {
            messages.add(new Map<String,Object> {
                'type' => 'function_call',
                'call_id' => call.callId,
                'name' => call.name,
                'arguments' => JSON.serialize(call.arguments)
            });
        }
        for(FunctionResult result : results) {
            messages.add(new Map<String,Object>{
                'type' => 'function_call_output',
                'call_id' => result.callId,
                'output' => result.outputJson
            });
        }
        return messages;
    }

    /**
     * Fetch AI_Response__c record by threadId and return stub if none found.
     * @param threadId Conversation/thread context id.
     * @return Partially-filled AI_Response__c record.
     */
    public static AI_Response__c getAIResponseByThreadId(String threadId){
        if(!String.isBlank(threadId)){
            List<AI_Response__c> responses = [SELECT Id, Thread_Id__c, User_Context_Id__c, Vector_Store_Id__c, AI_Processed_Data_PII_Added__c FROM AI_Response__c WHERE User_Context_Id__c = :threadId OR Name = :threadId];
            if(responses.isEmpty()){
                return new AI_Response__c();
            }else{
                return new AI_Response__c(Id = responses[0].Id,User_Context_Id__c = responses[0].User_Context_Id__c,
                                            Thread_Id__c = responses[0].Thread_Id__c, 
                                            Vector_Store_Id__c = responses[0].Vector_Store_Id__c,
                                            AI_Processed_Data_PII_Added__c = responses[0].AI_Processed_Data_PII_Added__c);
            }
        }else{
            return new AI_Response__c();
        }
    }

    /**
     * Prepares an AI_Response__c object with details from agentic prompt configuration.
     * @param response AI_Response__c record.
     * @param aiPrompt AI_Prompt__c prompt record.
     * @return Response object populated with prompt fields.
     */
    public static AI_Response__c getPreparedAIResponse(AI_Response__c response, AI_Prompt__c aiPrompt){
        response.GPT_Config__c = aiPrompt.AI_Connection__r.Name;
        response.AI_Prompt__c = aiPrompt.Id;
        response.Prompt_Command__c = aiPrompt.Prompt_Command__c;
        response.Profiles__c = aiPrompt.Profiles__c;
        response.Prompt_Version__c = aiPrompt.Prompt_Version__c;
        response.How_It_Works__c = aiPrompt.How_It_Works__c;
        response.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
        response.Message__c = '';
        return response;
    }

    // ---------- Get Thread Id ----------
    /**
     * Updates the threadId field of the response wrapper based on the AI API response.
     * @param response AIAgenticWebService.ResponseWrapper record.
     * @param threadId Existing thread ID.
     * @return Updated response wrapper with threadId.
     */
    public static AIAgenticWebService.ResponseWrapper getThreadId(AIAgenticWebService.ResponseWrapper response, String threadId) {
        try {
            response.userContextId = threadId;
            if (String.isBlank(response.responseBody)) {
                return response;
            }
            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody);
            if (dataMap != null && dataMap.containsKey('id')) {
                response.userContextId = String.valueOf(dataMap.get('id'));
            }
            return response;
        } catch (Exception ex) {
            return errorResponse(ex);
        }
    }

    // ---------- Parse Agentic Response ----------
    /**
     * Parses generic AI response JSON and extracts function calls/messages for further handling.
     * @param response Raw string response from agentic API.
     * @return Parsed ResponseDetails object containing messages and function calls.
     */
    public static ResponseDetails getParsedResponse(String response) {
        ResponseDetails rspDetails = new ResponseDetails();
        try {
            if (String.isBlank(response)) {
                return rspDetails;
            }
            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(response);
            if (dataMap != null && dataMap.containsKey('output')) {
                List<Object> outputObject = (List<Object>) JSON.deserializeUntyped(JSON.serialize(dataMap.get('output')));
                if (!outputObject.isEmpty()) {
                    for (Object fncObj : outputObject) {
                        Map<String, Object> fncObjMap = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(fncObj));
                        if (fncObjMap != null && fncObjMap.containsKey('type') && 
                            String.valueOf(fncObjMap.get('type')) == 'message') {
                            List<Object> contentList = (List<Object>)fncObjMap.get('content');
                            if (contentList != null && !contentList.isEmpty()) {
                                Map<String, Object> contentMap = (Map<String, Object>)contentList.get(0);
                                if (contentMap != null && contentMap.containsKey('text')) {
                                    rspDetails.messages.add(String.valueOf(contentMap.get('text')) + '\n');
                                }
                            }
                        }else if(fncObjMap != null && fncObjMap.containsKey('type') && 
                                String.valueOf(fncObjMap.get('type')) == 'function_call'){
                            FunctionCallDetail detail = new FunctionCallDetail();
                            detail.name = String.valueOf(fncObjMap.get('name'));
                            detail.callId = String.valueOf(fncObjMap.get('call_id')); 
                            detail.arguments = (Map<String,Object>)JSON.deserializeUntyped(String.valueOf(fncObjMap.get('arguments')));
                            rspDetails.fncDetails.add(detail);
                        }
                    }
                }
            }
            return rspDetails;
        } catch (Exception ex) {
            return rspDetails;
        }
    }

    // ---------- Prompt Option Builder ----------
    /**
     * Retrieves and prepares prompt functions for the request, verifying user and permissions.
     * @param request AIAgenticWebService.RequestWrapper request.
     * @return Modified request, updated with functions and config.
     * @jira: V2-7341
     */
    public static AIAgenticWebService.RequestWrapper getPromptOptions(AIAgenticWebService.RequestWrapper request,AI_Response__c aiResponse) {
        try {
            request.promptFunctions = new List<Object>();
            List<User> users = fetchUser(request.userIdentificationField, request.userIdentificationValue);
            if (!users.isEmpty()) {
                if (checkGPTfyPermissionAssignment(users[0].Id)) {
                    Set<String> assignedPermissionSets = new Set<String>();
                    for (PermissionSetAssignment psa : [SELECT Id, PermissionSet.Label FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId()]) {
                        assignedPermissionSets.add(psa.PermissionSet.Label.toLowerCase());
                    }

                    List<AI_Agent__c> lstOfConfigs = getDynamicQueryResults(request.agentName);
                    if (lstOfConfigs != null && !lstOfConfigs.isEmpty()) {
                        request.config = lstOfConfigs.get(0);
                        if (request.config.AI_Agent_Skills__r != null && request.config.AI_Agent_Skills__r.size() > 0) {
                            for (AI_Agent_Skill__c ap : request.config.AI_Agent_Skills__r) {
                                AI_Prompt__c pmt = ap.AI_Prompt__r;
                                if ((String.isBlank(pmt.Profiles__c) && String.isBlank(pmt.Permission_Sets__c)) ||
                                    (String.isNotBlank(pmt.Profiles__c) && pmt.Profiles__c.containsIgnoreCase(users[0].Profile.Name)) ||
                                    (String.isNotBlank(pmt.Permission_Sets__c) && GPTfyConsoleController.checkMatchingSets(assignedPermissionSets, pmt.Permission_Sets__c.toLowerCase().split(';')))) {
                                    request.promptFunctions.add(promptFunctionDefinition(pmt));
                                }
                            }
                        }
                        if(request.setOfVectorStoreIds == null){
                            request.setOfVectorStoreIds = new Set<String>();
                        }
                        request.setOfVectorStoreIds.addAll(getVectorStoreIds(request.config, aiResponse));
                        if(request.setOfVectorStoreIds.size() > 0){
                            request.promptFunctions.add(fileSearchDefinition(request.setOfVectorStoreIds));
                        }
                        // Attach Agent Intents to the request
                        attachAgentIntentsToRequest(request);
                    }
                }
            }
            return request;
        } catch (Exception ex) {
            return request;
        }
    }

    /**
     * Attaches active Agent Intents to the request for AI processing.
     * @param request AIAgenticWebService.RequestWrapper to update.
     */
    public static void attachAgentIntentsToRequest(AIAgenticWebService.RequestWrapper request) {
        try {
            if (request.config == null || request.config.AI_Agent_Intents__r == null || request.config.AI_Agent_Intents__r.isEmpty()) {
                return;
            }
            
            // Action types that require AI to extract parameters
            // Skip Canned Response, Flow, Apex, Invoke Agent - they don't need AI extraction
            Set<String> actionTypesRequiringExtraction = new Set<String>{
                'Update Field', 'Create Record'
            };

            // Pre-query AI_Intent_Action_Detail__c for Create Record and Update Field actions (AI Extracted only)
            Set<Id> fieldMappingActionIds = new Set<Id>();
            for (AI_Agent_Intent__c intent : request.config.AI_Agent_Intents__r) {
                if (intent.AI_Intent_Actions__r != null) {
                    for (AI_Intent_Action__c action : intent.AI_Intent_Actions__r) {
                        if (action.Action_Type__c == 'Create Record' || action.Action_Type__c == 'Update Field') {
                            fieldMappingActionIds.add(action.Id);
                        }
                    }
                }
            }

            // Query child detail records for Create Record / Update Field actions — only AI Extracted rows go to the AI
            Map<Id, List<AI_Intent_Action_Detail__c>> detailsByActionId = new Map<Id, List<AI_Intent_Action_Detail__c>>();
            if (!fieldMappingActionIds.isEmpty()) {
                for (AI_Intent_Action_Detail__c detail : [
                    SELECT Id, Field_API_Name__c, Type__c, Value__c, AI_Intent_Action__c
                    FROM AI_Intent_Action_Detail__c
                    WHERE AI_Intent_Action__c IN :fieldMappingActionIds
                      AND Type__c = :AIConstants.ACTION_DETAIL_TYPE_AI_EXTRACTED
                    ORDER BY Sequence__c ASC NULLS LAST
                ]) {
                    if (!detailsByActionId.containsKey(detail.AI_Intent_Action__c)) {
                        detailsByActionId.put(detail.AI_Intent_Action__c, new List<AI_Intent_Action_Detail__c>());
                    }
                    detailsByActionId.get(detail.AI_Intent_Action__c).add(detail);
                }
            }
            
            // Build object keyed by intent name (without #)
            Map<String, Object> intentsPayload = new Map<String, Object>();
            for (AI_Agent_Intent__c intent : request.config.AI_Agent_Intents__r) {
                // Build actions array - only include actions that need AI parameter extraction
                List<Object> actionsPayload = new List<Object>();
                if (intent.AI_Intent_Actions__r != null && !intent.AI_Intent_Actions__r.isEmpty()) {
                    for (AI_Intent_Action__c action : intent.AI_Intent_Actions__r) {
                        // Only include actions that require AI extraction
                        if (!actionTypesRequiringExtraction.contains(action.Action_Type__c)) {
                            continue; // Skip Canned Response, Flow, Apex, Invoke Agent
                        }
                        
                        Map<String, Object> actionMap = new Map<String, Object>{
                            'type' => action.Action_Type__c
                        };
                        if (String.isNotBlank(action.Object_Name__c)) {
                            actionMap.put('object', action.Object_Name__c);
                        }

                        if (action.Action_Type__c == 'Create Record' || action.Action_Type__c == 'Update Field') {
                            // Build fields array from child AI_Intent_Action_Detail__c records
                            List<AI_Intent_Action_Detail__c> actionDetails = detailsByActionId.get(action.Id);
                            if (actionDetails != null && !actionDetails.isEmpty()) {
                                List<Object> fieldsArray = new List<Object>();
                                for (AI_Intent_Action_Detail__c detail : actionDetails) {
                                    Map<String, Object> fieldMap = new Map<String, Object>{
                                        'field' => detail.Field_API_Name__c
                                    };
                                    if (String.isNotBlank(detail.Value__c)) {
                                        fieldMap.put('description', detail.Value__c);
                                    }
                                    fieldsArray.add(fieldMap);
                                }
                                actionMap.put('fields', fieldsArray);
                            }
                            if (String.isNotBlank(action.Description__c)) {
                                actionMap.put('description', action.Description__c);
                            }
                        } else {
                            // Other action types that need extraction (future-proof)
                            if (String.isNotBlank(action.Field_API_Name__c)) {
                                actionMap.put('field', action.Field_API_Name__c);
                            }
                            if (String.isNotBlank(action.Description__c)) {
                                actionMap.put('description', action.Description__c);
                            }
                        }
                        actionsPayload.add(actionMap);
                    }
                }
                
                // Build intent object
                Map<String, Object> intentData = new Map<String, Object>{
                    'description' => intent.Description__c
                };
                if (!actionsPayload.isEmpty()) {
                    intentData.put('actions', actionsPayload);
                }
                
                // Key by intent name (use Name directly, AI will use #NAME in response)
                intentsPayload.put(intent.Name, intentData);
            }
            request.agentIntents = intentsPayload;
        } catch (Exception ex) {
            // Silently fail - intents are optional
        }
    }
    public static List<AI_Agent__c> getDynamicQueryResults(String agentName){
        String activeStatus = AIConstants.PMT_STATUS_ACTIVE, typeAgentic = AIConstants.AI_PMT_TYPE_AGENTIC;
        
        String baseQuery = 'SELECT Id,Name, AI_Model__c, TTL__c, TTL_Message__c, Use_Thread_Id__c, ' +
            'AI_Model__r.Named_Credential__c, AI_Model__r.Model__c, AI_Model__r.Type__c, ' +
            'AI_Model__r.Temperature__c, AI_Model__r.Top_p__c, AI_Model__r.Max_Tokens__c, AI_Model__r.Additional_Parameters__c, ' +
            'AI_Model__r.Processing_Class__c, ' +
            'System_Prompt__c, RAG__c, ' +
            '(SELECT Id, AI_Prompt__c, AI_Prompt__r.Profiles__c, AI_Prompt__r.Permission_Sets__c, ' +
                'AI_Prompt__r.Description__c, AI_Prompt__r.Prompt_Command__c, AI_Prompt__r.Name ' +
            'FROM AI_Agent_Skills__r ' +
            'WHERE AI_Prompt__r.Status__c = :activeStatus ' +
                'AND AI_Prompt__r.Type__c = :typeAgentic), ' +
            '(SELECT Id, Name, Description__c, Sequence__c, Is_Active__c, ' +
                '(SELECT Id, Action_Type__c, Object_Name__c, Field_API_Name__c, Description__c, Sequence__c ' +
                'FROM AI_Intent_Actions__r ' +
                'WHERE Is_Active__c = true ' +
                'ORDER BY Sequence__c ASC) ' +
            'FROM AI_Agent_Intents__r ' +
            'WHERE Is_Active__c = true ' +
            'ORDER BY Sequence__c ASC) ' +
            'FROM AI_Agent__c ';

        String condition = '';
        if (String.isNotBlank(agentName)) {
            // If agentName is provided
            condition = 'WHERE Developer_Name__c = :agentName ';
        } else {
            // If agentName is empty, get latest by CreatedDate
            condition = 'ORDER BY CreatedDate ASC ';
        }
        String limitClause = 'LIMIT 1';

        String finalQuery = baseQuery + condition + limitClause;
        // Bind variables for safety
        List<AI_Agent__c> lstOfConfigs;
        if (String.isNotBlank(agentName)) {
            return Database.query(finalQuery.replace(':agentName', '\'' + String.escapeSingleQuotes(agentName) + '\''));
        } else {
            return Database.query(finalQuery);
        }
    }

    /**
     * Retrieves vector store external IDs for the current agentic configuration (RAG).
     * @param config Agentic configuration record.
     * @return List of vector store external IDs.
     * @jira: V2-7341
     */
    public static Set<String> getVectorStoreIds(AI_Agent__c config, AI_Response__c aiResponse){
        try{
            Set<String> setOfVectorStoreIds = new Set<String>();
            if(config.RAG__c != null && String.isNotBlank(config.RAG__c)){
                List<String> schedulerIds = config.RAG__c.split(';');
                List<AI_RAG_Sync__c> schedulers = [SELECT Id, External_Id__c FROM AI_RAG_Sync__c WHERE Id IN :schedulerIds AND External_Id__c != NULL];
                for(AI_RAG_Sync__c scheduler : schedulers){
                    setOfVectorStoreIds.add(scheduler.External_Id__c);
                }
            }
            if(aiResponse.Vector_Store_Id__c != null && String.isNotBlank(aiResponse.Vector_Store_Id__c)){
                setOfVectorStoreIds.add(aiResponse.Vector_Store_Id__c);
            }
            return setOfVectorStoreIds;
        }catch(Exception ex){
            return new Set<String>();
        }
    } 

    /**
     * Helper to define a file search prompt function for RAG/vector store, formatted for OpenAI.
     * @param setOfVectorStoreIds List of external IDs.
     * @return Map describing function for file search.
     */
    public static Map<String, Object> fileSearchDefinition(Set<String> setOfVectorStoreIds){
        return new Map<String, Object>{
            'type' => 'file_search',
            'vector_store_ids' => setOfVectorStoreIds,
            'max_num_results' => 20
        };
    }

    /**
     * Helper to define a function for agentic prompt interfacing, formatted for OpenAI.
     * @param pmt AI_Prompt__c record.
     * @return Map describing function, parameters, and description.
     */
    public static Map<String, Object> promptFunctionDefinition(AI_Prompt__c pmt) {
        try {
            return new Map<String, Object>{
                'type' => 'function',
                'name' => pmt.Name,
                'description' => pmt.Description__c,
                'parameters' => String.isNotBlank(pmt.Prompt_Command__c) ? (Map<String, Object>) JSON.deserializeUntyped(pmt.Prompt_Command__c) : null
            };
        } catch (Exception ex) {
            return new Map<String, Object>();
        }
    }

    // ---------- GPTfy Permission Check ----------
    /**
     * Checks if user has a permission assignment in GPTfy package namespace.
     * @param userId User Id to check.
     * @return Boolean true if assignment exists, false otherwise.
     */
    public static Boolean checkGPTfyPermissionAssignment(String userId) {
        try {
            String l_namespace = NAMESPACE;
            if (String.isNotBlank(l_namespace) && l_namespace.endsWithIgnoreCase('__')) {
                l_namespace = l_namespace.removeEndIgnoreCase('__');
            }
            List<PermissionSetAssignment> gptfyPermSetAssignments = [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSet.NamespacePrefix = :l_namespace];
            return (gptfyPermSetAssignments != null && !gptfyPermSetAssignments.isEmpty());
        } catch (Exception ex) {
            return false;
        }
    }

    // ---------- User Lookup with Fallback ----------
    /**
     * Fetch user details by given field and value.
     * @param field Field API name (e.g., ProfileId).
     * @param value Field value to match.
     * @return List<User> matching the criteria.
     */
    public static List<User> fetchUser(String field, String value) {
        if(field == null || String.isBlank(field)){
            field = 'Id';
        }
        if(value == null || String.isBlank(value)){
            value = UserInfo.getUserId();
        }
        try {
            String query = 'SELECT toLabel(LocaleSidKey) LocaleSidKey,toLabel(LanguageLocaleKey) LanguageLocaleKey,';
            if (field != 'Profile.Name') {
                query += 'Profile.Name,';
            }
            query += String.escapeSingleQuotes(field) + ' FROM User WHERE ' + String.escapeSingleQuotes(field) + ' = :value LIMIT 1';
            return (List<User>) Database.query(query);    
        } catch (Exception ex) {
            return new List<User>();
        }
    }

    /**
     * @description
     *   Wrapper class holding function call details from AI response.
     */
    public class FunctionCallDetail {
        public String name;
        public String callId;
        public Map<String, Object> arguments;
    }

    /**
     * @description
     *   Response details wrapper for parsed AI agentic results/messages/calls.
     */
    public class ResponseDetails{
        public List<FunctionCallDetail> fncDetails;
        public List<String> messages;
        public ResponseDetails(){
            this.fncDetails = new List<FunctionCallDetail>();
            this.messages = new List<String>();
        }
    }

    /**
     * @description
     *   Helper class to wrap prompt function signature/parameters.
     */
    public class FunctionsDetails {
        public String name;
        public Map<String, Object> parameters;
        public FunctionsDetails() {}
        public FunctionsDetails(String functionName, Map<String, Object> functionParams) {
            this.name = functionName;
            this.parameters = functionParams;
        }
    }

    /**
     * @description
     *   Helper class for storing results of agentic function calls during AI session.
     */
    public class FunctionResult {
        public String name;
        public String callId;
        public String outputJson;
        public FunctionResult(String name, String callId, String outputJson) {
            this.name = name;
            this.callId = callId;
            this.outputJson = outputJson;
        }
    }

    /**
     * @description
     *   Helper class to record chat history (user/assistant/developer roles).
     */
    public class ChatHistory{
        public String role;
        public String content;
        public ChatHistory(String role, String content){
            this.role = role;
            this.content = content;
        }
    }
}