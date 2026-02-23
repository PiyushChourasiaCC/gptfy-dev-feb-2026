/**
 * @description:
 *   AIAgenticChatController serves as the server-side controller for handling all agentic chat-related
 *   operations exposed to Aura and Lightning Web Components. It retrieves agent configurations,
 *   manages chat sessions, performs TTL (Time To Live) validation, and provides chat history access.
 *   Methods are marked @AuraEnabled to allow remote invocation from client-side components.
 *
 * @author             : Piyush Chourasia
 * @group              : Plumcloud Labs
 * @last modified on   : 15-08-2025
 * @last modified by   : Piyush Chourasia
 */
public with sharing class AIAgenticChatController {
    
    // Constants for exception logging
    private static final String APPLICATION_NAME = 'GPTfy';
    private static final String MODULE_NAME = 'AI Agentic Chat';
    private static final String CLASS_NAME = 'AIAgenticChatController';

     /**
     * Custom exception for agentic utility error handling.
     */
    public class AIAgenticChatControllerException extends Exception {}
    
    /**
     * Retrieves AI Settings from custom metadata/settings
     * @return Map<String, Object> containing AI configuration settings
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAISettings(){
        String methodName = 'getAISettings';
        try {
            return AIUtility.getCustomSettings();
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching AI settings: ' + e.getMessage());
        }
    }
    
    /**
     * Uploads additional files to the specified vector store using the provided named credential.
     *
     * @param filesJSON         - JSON string of FileWrapper objects containing file metadata and base64 data.
     * @param vectorStoreId     - The identifier of the target vector store.
     * @param namedCredential   - The named credential for authenticating the upload request.
     * @param threadId          - The thread identifier for the chat session.
     * @return ResponseWrapper - custom wrapper containing upload results
     * @throws AuraHandledException - For error propagation to client-side handlers.
     * @jira: V2-7341
     */
    @AuraEnabled
    public static ResponseWrapper uploadAdditionalFiles(
        String filesJSON,
        String vectorStoreId,
        String namedCredential,
        String threadId
    ) {
        String methodName = 'uploadAdditionalFiles';
        String supportData = 'ThreadID: ' + threadId + ', VectorStoreId: ' + vectorStoreId;
        
        try {
            if (String.isBlank(filesJSON)) {
                throw new AuraHandledException('Files JSON is required');
            }
            
            List<FileWrapper> files = (List<FileWrapper>)JSON.deserialize(filesJSON, List<FileWrapper>.class);
            ResponseWrapper responseWrapper = new ResponseWrapper();
            
            if((!files.isEmpty()) && String.isBlank(vectorStoreId)){
                responseWrapper = AIAgenticChatAPIService.uploadFilesAndCreateVectorStore(files, namedCredential);
            }else if(!files.isEmpty() && String.isNotBlank(vectorStoreId)){
                responseWrapper = AIAgenticChatAPIService.uploadFilesToVectorStore(files, namedCredential, vectorStoreId);
            }

            AI_Response__c aiResponse = AIAgenticUtility.getAIResponseByThreadId(threadId);
            String userContextId = aiResponse.User_Context_Id__c;
            aiResponse.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
            
            if(String.isNotBlank(responseWrapper.vectorStroreId)){
                aiResponse.Vector_Store_Id__c = responseWrapper.vectorStroreId;
                aiResponse = ChatGPTUtills.insertAIResponse(aiResponse, true);    
                responseWrapper.userContextId = AIAgenticUtility.getAIResponseUserContextId(aiResponse,userContextId);
            }else{
                responseWrapper.userContextId = threadId;
            }
        
            return responseWrapper;
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error uploading files: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves a list of available agentic AI configurations for chat initiation.
     *
     * @return List<Agent> - A serializable wrapper object containing label, developer name,
     *         TTL minutes, and custom TTL message for each configuration.
     * @throws AuraHandledException - Propagates error messages to the client for graceful handling.
     */
    @AuraEnabled
    public static List<Agent> fetchAgents(){
        String methodName = 'fetchAgents';
        
        try {
            List<Agent> agents = new List<Agent>();
            
            List<User> users = AIAgenticUtility.fetchUser('ID', UserInfo.getUserId());
            if (!users.isEmpty()) {
                if (AIAgenticUtility.checkGPTfyPermissionAssignment(users[0].Id)) {
                    Set<String> assignedPermissionSets = new Set<String>();
                    
                    for (PermissionSetAssignment psa : [
                        SELECT Id, PermissionSet.Label 
                        FROM PermissionSetAssignment 
                        WHERE AssigneeId = :users[0].Id
                    ]) {
                        assignedPermissionSets.add(psa.PermissionSet.Label.toLowerCase());
                    }
                    
                    List<AI_Agent__c> agentList = [
                        SELECT ID, Name, Developer_Name__c, TTL__c, TTL_Message__c, 
                               Profiles__c, Permission_Sets__c, Welcome_Message__c,
                               AI_Model__r.Named_Credential__c
                        FROM AI_Agent__c
                        WHERE Status__c = :AIConstants.PMT_STATUS_ACTIVE
                        WITH USER_MODE
                    ];
                    
                    if (agentList != null && !agentList.isEmpty()) {
                        for (AI_Agent__c agent : agentList) {
                            if ((String.isBlank(agent.Profiles__c) && String.isBlank(agent.Permission_Sets__c)) ||
                                (String.isNotBlank(agent.Profiles__c) && agent.Profiles__c.containsIgnoreCase(users[0].Profile.Name)) ||
                                (String.isNotBlank(agent.Permission_Sets__c) && GPTfyConsoleController.checkMatchingSets(assignedPermissionSets, agent.Permission_Sets__c.toLowerCase().split(';')))) {
                                    agents.add(new Agent(agent));
                            }
                        }
                    }
                }
            }
            return agents;
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching agents: ' + e.getMessage());
        }
    }

    /**
     * Validates if the chat thread identified by threadId is still within its Time To Live (TTL).
     *
     * @param threadId    - The unique identifier for the conversation thread.
     * @param ttlMinutes  - The allowed TTL value in minutes. If null, session is always valid unless expired.
     * @return String     - 'Valid Session', 'Invalid Session', or 'New Session'
     * @throws AuraHandledException - For error propagation to client.
     */
    @AuraEnabled
    public static String validateTTL(String threadId, Decimal ttlMinutes){
        String methodName = 'validateTTL';
        String supportData = 'ThreadID: ' + threadId + ', TTL Minutes: ' + ttlMinutes;
        
        try {
            // Retrieve response records for the given thread
            List<AI_Response__c> records = [
                SELECT Id, CreatedDate, Session_Expired__c, Vector_Store_Id__c, Agent_Name__c
                FROM AI_Response__c 
                WHERE User_Context_Id__c = :threadId OR Name = :threadId
                WITH USER_MODE
                LIMIT 1
            ];

            // Check for expiration or TTL violation
            if(!records.isEmpty()){
                if(records[0].Session_Expired__c == true){
                    return 'Invalid Session';
                }
                if(ttlMinutes == null){
                    return 'Valid Session';
                }
                if(DateTime.now() < records[0].CreatedDate.addMinutes(Integer.valueOf(ttlMinutes))){
                    return 'Valid Session';
                }
                if(records[0] != null && records[0].Vector_Store_Id__c != null){
                    AIGlobalUtility.deleteExpiredVectorStores(new List<AI_Response__c>{records[0]});
                }else{
                    records[0].Session_Expired__c = true;
                    records[0].Status__c = AIConstants.RESP_STATUS_PROCESSED;
                    FLSCheck.getInstance().upsertDML(new List<AI_Response__c>{records[0]});
                }
                return 'Invalid Session';
            } else {
                return 'New Session';
            }
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error validating TTL: ' + e.getMessage());
        }
    }

    /**
     * Fetches the most recent valid audit session identifier for security or chat auditing purposes.
     *
     * @return String - The latest User_Context_Id__c or an empty string if no sessions exist.
     * @throws AuraHandledException - On query failure.
     */
    @AuraEnabled
    public static String fetchLatestSecurityAuditId(){
        String methodName = 'fetchLatestSecurityAuditId';
        
        try {
            // Query the most recent response record with a non-null audit id
            List<AI_Response__c> responses = [
                SELECT Id, User_Context_Id__c 
                FROM AI_Response__c 
                WHERE User_Context_Id__c != null 
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            
            if(responses.isEmpty()){
                return '';
            } else {
                return responses[0].User_Context_Id__c;
            }
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching audit ID: ' + e.getMessage());
        }
    }

    /**
     * Retrieves the chat history for a given audit/session id.
     *
     * @param auditId - The session/audit identifier for the chat conversation.
     * @param agentDeveloperName - The developer name of the agent.
     * @return AIChatContainer - Container with agent name and chat history.
     * @throws AuraHandledException - On SOQL or processing errors.
     */
    @AuraEnabled
    public static AIChatContainer fetchAIChatHistory(String auditId, String agentDeveloperName){
        String methodName = 'fetchAIChatHistory';
        String supportData = 'AuditID: ' + auditId + ', Agent: ' + agentDeveloperName;
        
        try {
            List<AI_Agent__c> agents = [
                SELECT Id, Welcome_Message__c 
                FROM AI_Agent__c 
                WHERE Developer_Name__c = :agentDeveloperName
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (agents.isEmpty()) {
                throw new AuraHandledException('Agent not found');
            }
            
            List<AIChat> chats = new List<AIChat>();
            
            // Query the response record and related security audit details containing chat messages
            List<AI_Response__c> responses = [
                SELECT Id, Agent_Name__c, 
                    (SELECT Id, Message__c FROM Security_Audit_Detail__r WHERE Type__c = 'Chat' ORDER BY CreatedDate ASC) 
                FROM AI_Response__c 
                WHERE User_Context_Id__c = :auditId OR Name = :auditId
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (responses.isEmpty()) {
                return new AIChatContainer('', new List<AIChat>());
            }
            
            AI_Response__c resp = responses[0];
            String userMessage = '', assistantReply = '';
            chats.add(new AIChat('', agents[0].Welcome_Message__c));
            
            if(!resp.Security_Audit_Detail__r.isEmpty()){
                for(AI_Security_Audit_Detail__c detail : resp.Security_Audit_Detail__r){
                    // Each audit detail contains a serialized list of AIRole objects (user/assistant roles and content)
                    List<AIRole> roles = (List<AIRole>) JSON.deserialize(detail.Message__c, List<AIRole>.class);
                    // Iterate in chunks, pulling user/assistant pairs
                    for(Integer i = 0; i < roles.size(); i+=3){
                        userMessage = roles[i].role == 'user'
                            ? roles[i].content
                            : roles[i+1].role == 'user'
                                ? roles[i+1].content
                                : roles[i+2].role == 'user'
                                    ? roles[i+2].content
                                    : 'No History';
                        assistantReply = roles[i].role == 'assistant'
                            ? roles[i].content
                            : roles[i+1].role == 'assistant'
                                ? roles[i+1].content
                                : roles[i+2].role == 'assistant'
                                    ? roles[i+2].content
                                    : 'No History';
                        chats.add(new AIChat(userMessage, assistantReply));
                    }
                }
            }
            return new AIChatContainer(resp.Agent_Name__c,chats);
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error fetching chat history: ' + e.getMessage());
        }
    }
    
    /**
     * Fetches a specific agent by ID (used for preview components)
     *
     * @param defaultAgentId - The ID of the agent to fetch
     * @return Agent - The agent wrapper
     * @throws AuraHandledException - On query failure
     */
    @AuraEnabled
    public static Agent fetchDefaultAgent(String defaultAgentId){
        String methodName = 'fetchDefaultAgent';
        String supportData = 'AgentID: ' + defaultAgentId;
        
        try {
            if (String.isBlank(defaultAgentId)) {
                throw new AuraHandledException('Agent ID is required');
            }
            
            List<AI_Agent__c> agents = [
                SELECT ID, Name, Developer_Name__c, TTL__c, TTL_Message__c, 
                       Profiles__c, Permission_Sets__c, Welcome_Message__c,
                       AI_Model__r.Named_Credential__c
                FROM AI_Agent__c 
                WHERE Id = :defaultAgentId
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (agents.isEmpty()) {
                throw new AuraHandledException('Agent not found');
            }
            
            return new Agent(agents[0]);
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error fetching agent: ' + e.getMessage());
        }
    }
    
    /**
     * Initiates a new AI-powered chat session using the provided serialized request.
     *
     * @param request - JSON string representing the AIAgenticWebService.RequestWrapper parameters.
     * @return String - The serialized ResponseWrapper from the agent invocation utility.
     * @throws AuraHandledException - For error propagation to client-side handlers.
     */
    @AuraEnabled
    public static String createNewChat(String request){
        String methodName = 'createNewChat';
        String supportData = 'Request: ' + request;
        
        try {
            if (String.isBlank(request)) {
                throw new AuraHandledException('Request is required');
            }
            
            AIAgenticWebService.RequestWrapper wrap = (AIAgenticWebService.RequestWrapper)JSON.deserialize(request, AIAgenticWebService.RequestWrapper.class);
            // Set identification info from current user context
            wrap.userIdentificationField = 'Id';
            wrap.userIdentificationValue = UserInfo.getUserId();
            // Invoke the chat agent utility and serialize the result
            AIAgenticWebService.ResponseWrapper respWrap = AIAgenticUtility.invokeAgent(wrap);
            return JSON.serialize(respWrap);
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error creating chat: ' + e.getMessage());
        }
    }

    /**
     * Ends the current chat session by marking the session/thread as expired.
     *
     * @param threadId - The unique chat session identifier to close.
     * @throws AuraHandledException - On update/DML failure.
     * @jira: V2-7341
     */
    @AuraEnabled
    public static void endChat(String threadId){
        String methodName = 'endChat';
        String supportData = 'ThreadID: ' + threadId;
        
        try {
            if (String.isBlank(threadId)) {
                throw new AuraHandledException('Thread ID is required');
            }
            
            // Fetch the active response for the session and update the session expired status
            List<AI_Response__c> responses = [
                SELECT Id, Name, Session_Expired__c, Status__c, Vector_Store_Id__c, Agent_Name__c, CreatedDate
                FROM AI_Response__c 
                WHERE User_Context_Id__c = :threadId
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (responses.isEmpty()) {
                throw new AuraHandledException('Chat session not found');
            }
            
            AI_Response__c resp = responses[0];
            
            if(resp != null && resp.Vector_Store_Id__c != null){
                AIGlobalUtility.deleteExpiredVectorStores(new List<AI_Response__c>{resp});
            }else if(resp != null){
                resp.Session_Expired__c = true;
                resp.Status__c = AIConstants.RESP_STATUS_PROCESSED;
                FLSCheck.getInstance().upsertDML(new List<AI_Response__c>{resp});
            }
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error ending chat: ' + e.getMessage());
        }
    }

    /**
     * Retrieves the Name field for a record by its id and object API name.
     * SECURITY FIX: Validates object API name against Schema to prevent SOQL injection
     *
     * @param recordId      - The target record's unique Id.
     * @param objectApiName - The API name of the target SObject type.
     * @return String       - The Name field for the given record or empty string if not found.
     * @throws AuraHandledException - On parameter validation or SOQL failure.
     */
    @AuraEnabled(cacheable=true)
    public static String fetchRecordName(String recordId, String objectApiName) {
        String methodName = 'fetchRecordName';
        String supportData = 'RecordID: ' + recordId + ', Object: ' + objectApiName;
        
        try {
            if (String.isBlank(recordId) || String.isBlank(objectApiName)) {
                throw new AuraHandledException('Invalid parameters');
            }
            
            // SECURITY FIX: Validate objectApiName against Schema to prevent SOQL injection
            Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objectApiName)?.getDescribe();
            if (objDescribe == null || !objDescribe.isAccessible()) {
                throw new AuraHandledException('Invalid or inaccessible object');
            }
            
            // Use bind variables for safe dynamic SOQL
            String query = 'SELECT Name FROM ' + String.escapeSingleQuotes(objectApiName) + ' WHERE Id = :recordId WITH USER_MODE LIMIT 1';
            List<SObject> results = Database.query(query);
            
            return results.isEmpty() ? '' : (String)results[0].get('Name');
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            return '';
        }
    }

    /**
     * @Jira v2/7822 : Enhance GPTfy Agent to be available in Experience Cloud
     * Gets the URL for a static resource by its name.
     * @param resourceName - The developer name of the static resource
     * @return String - The URL of the static resource, or null if not found
     */
    @AuraEnabled(cacheable=true)
    public static String getStaticResourceUrl(String resourceName) {
        String methodName = 'getStaticResourceUrl';
        try {
            if (String.isBlank(resourceName)) {
                return null;
            }
            List<StaticResource> resources = [
                SELECT Id, Name, NamespacePrefix, SystemModstamp
                FROM StaticResource 
                WHERE Name = :resourceName 
                LIMIT 1
            ];
            if (resources.isEmpty()) {
                return null;
            }
            StaticResource resource = resources[0];
            String fullResourceName = String.isNotBlank(resource.NamespacePrefix) 
                ? resource.NamespacePrefix + '__' + resource.Name 
                : resource.Name;
            Long timestamp = resource.SystemModstamp.getTime();
            String baseUrl = Site.getBaseUrl();
            if (String.isBlank(baseUrl)) {
                baseUrl = '';
            }
            return baseUrl + '/resource/' + timestamp + '/' + fullResourceName;
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            return null;
        }
    }



    // ==================== WRAPPER CLASSES ====================

    /**
     * AIRole wrapper for chat message participant type and message content.
     * Used for serializing/deserializing chat transcript messages.
     */
    public class AIRole{
        @AuraEnabled public String role;
        @AuraEnabled public String content;

        public AIRole(String role, String content){
            this.role = role;
            this.content = content;
        }
    }

    /**
     * AIChatContainer wrapper for complete chat history with agent information
     */
    public class AIChatContainer{
        @AuraEnabled public String agentName;
        @AuraEnabled public List<AIChat> chats;
        
        public AIChatContainer(String agentName, List<AIChat> chats){
            this.agentName = agentName;
            this.chats = chats;
        }
    }
    
    /**
     * AIChat wrapper to represent a pair of user question and assistant reply.
     * Used to convey structured chat history to the client layer.
     */
    public class AIChat{
        @AuraEnabled public String question;
        @AuraEnabled public String answer;

        public AIChat(String question, String answer){
            this.question = question;
            this.answer = answer;
        }
    }
    
    /**
     * Agent wrapper contains metadata describing
     * each available agent configuration for user interface selection.
     */
    public class Agent{
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Boolean selected;
        @AuraEnabled public Decimal ttlMinutes;
        @AuraEnabled public String ttlMessage;
        @AuraEnabled public String welcomeMessage;
        @AuraEnabled public String namedCredential;

        public Agent(AI_Agent__c agentObj){
            this.label = agentObj.Name;
            this.value = agentObj.Developer_Name__c;
            this.selected = false;
            this.ttlMinutes = agentObj.TTL__c;
            this.ttlMessage = agentObj.TTL_Message__c;
            this.welcomeMessage = agentObj.Welcome_Message__c;
            this.namedCredential = agentObj.AI_Model__r.Named_Credential__c;   
        }
    }
    
    /**
     * FileWrapper for file upload operations
     * @jira: V2-7341
     */
    public class FileWrapper {
        @AuraEnabled public String fileName;
        @AuraEnabled public String mimeType;
        @AuraEnabled public String base64Data;
        @AuraEnabled public Integer fileSize;
    }
    
    /**
     * ResponseWrapper for image file ids and vector store id
     * @jira: V2-7341
     */
    public class ResponseWrapper{
        @AuraEnabled public String vectorStroreId;
        @AuraEnabled public List<String> imageFileIds;
        @AuraEnabled public List<String> uploadedFileIds;
        @AuraEnabled public String userContextId;
        
        public ResponseWrapper(){
            this.vectorStroreId = '';
            this.imageFileIds = new List<String>();
            this.uploadedFileIds = new List<String>();
            this.userContextId = '';
        }   
    }
}