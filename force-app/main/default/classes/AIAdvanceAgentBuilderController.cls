/**
 * @description Controller for AI Advance Agent Builder component
 *              Handles agent creation using AI-powered natural language processing with proper FLS checks and exception logging
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 11-19-2024
 * @last modified by Piyush Chourasia
 * @jira V2-7442
 */
public with sharing class AIAdvanceAgentBuilderController {
    
    private static final String APPLICATION_NAME = 'GPTfy';
    private static final String MODULE_NAME = 'AI Advance Agent Builder';
    private static final String CLASS_NAME = 'AIAdvanceAgentBuilderController';
    
    /**
     * Wrapper class for agent details returned from AI service
     * @jira V2-7442
     */
    public class AgentDetailsWrapper {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String systemPrompt { get; set; }
        @AuraEnabled public String welcomeMessage { get; set; }
        @AuraEnabled public List<String> selectedSkillIds { get; set; }
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public AgentDetailsWrapper() {
            this.selectedSkillIds = new List<String>();
            this.success = true;
        }
    }
    
    /**
     * Wrapper class for agent list display
     * Provides clean interface without exposing sObject directly
     * @jira V2-7442
     */
    public class AgentListWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String systemPrompt { get; set; }
        @AuraEnabled public String status { get; set; }
        
        public AgentListWrapper(AI_Agent__c agent) {
            this.id = agent.Id;
            this.name = agent.Name;
            this.systemPrompt = agent.System_Prompt__c;
            this.status = agent.Status__c;
            
            // Set description to empty or a generic message
            // Do NOT show system prompt content on cards
            this.description = agent.Description__c != null ? agent.Description__c : 'No description available';
        }
    }
    
    /**
     * Retrieves all active Agentic prompts available as skills
     * @return List of AI_Prompt__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<AI_Prompt__c> getAgenticPrompts() {
        String methodName = 'getAgenticPrompts';
        try {
            return [
                SELECT Id, Name 
                FROM AI_Prompt__c 
                WHERE Status__c = 'Active' AND Type__c = 'Agentic'
                WITH USER_MODE
                ORDER BY Name
                LIMIT 1000
            ];
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching agentic prompts: ' + e.getMessage());
        }
    }
    
    /**
     * Generates agent details using OpenAI based on user input and available prompts
     * Parses the AI response and returns structured agent details
     * @param userInput User's description of the agent
     * @param promptsJson JSON string containing available prompts
     * @return AgentDetailsWrapper with parsed agent details
     * @jira V2-7442
     */
    @AuraEnabled
    public static AgentDetailsWrapper generateAgentDetails(String userInput, String promptsJson) {
        String methodName = 'generateAgentDetails';
        String supportData = 'User Input: ' + userInput;
        AgentDetailsWrapper result = new AgentDetailsWrapper();
        
        try {
            if (String.isBlank(userInput)) {
                throw new AuraHandledException('User input cannot be empty');
            }
            
            // Get AI Connection for GPTfy
            AI_Connection__c connection = getGPTfyConnection();
            
            // Build system prompt from custom labels
            String systemPrompt = Label.AI_Agent_Builder_System_Prompt_Introduction + '\n\n' +
                Label.AI_Agent_Builder_System_Prompt_Requirements + ' ' +
                Label.AI_Agent_Builder_HTML_Formatting_Instructions + '\n\n' +
                Label.AI_Agent_Builder_Final_Instructions;
            
            // Build user prompt with available skills using custom label template
            String userPrompt = String.format(
                Label.AI_Agent_Builder_User_Prompt_Template,
                new List<String>{ userInput, promptsJson }
            );
            
            // Make callout to OpenAI with increased tokens for detailed response
            Integer maxOutputToken = connection.Max_Tokens__c != null ? Integer.valueOf(connection.Max_Tokens__c) : 2000;
            Decimal temperature = connection.Temperature__c != null ? connection.Temperature__c : 0.7;
            Decimal topP = connection.Top_P__c != null ? connection.Top_P__c : 1.0;
            
            HttpResponse response = null;
            try {
                response = AIGPTfyCalloutController.processGptfyRequest(
                    systemPrompt,
                    userPrompt,
                    connection,
                    maxOutputToken,
                    temperature,
                    topP
                );
            } catch (Exception calloutEx) {
                String detailedError = 'AI callout failed: ' + calloutEx.getMessage();
                detailedError += '\nConnection Details - Name: ' + connection.Name + ', Named Credential: ' + connection.Named_Credential__c;
                detailedError += ', AI Technology: ' + connection.AI_Technology__c;
                if (String.isNotBlank(connection.EndPoint_URL__c)) {
                    detailedError += ', Endpoint URL: ' + connection.EndPoint_URL__c;
                }
                GPTfyException.Log(calloutEx, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData + ', Connection: ' + connection.Name);
                throw new AuraHandledException(detailedError);
            }
            
            if (response != null && response.getStatusCode() == 200) {
                String responseBody = response.getBody();
                
                // Check if response is empty or just whitespace
                if (String.isBlank(responseBody)) {
                    throw new AuraHandledException('AI service returned an empty response');
                }
                
                // Use ChatGPTUtills.parseGPTfyResponse to extract the content
                String parsedContent = ChatGPTUtills.parseGPTfyResponse(responseBody);
                
                if (String.isNotBlank(parsedContent)) {
                    // Parse the JSON content into AgentDetailsWrapper
                    result = parseAgentDetailsFromJSON(parsedContent, userInput);
                    return result;
                }
                
                // If parsing returned null or empty, throw an error
                throw new AuraHandledException('Failed to parse AI response. Response may be in an unexpected format.');
            } else {
                String errorMsg = response != null ? 
                    'Status: ' + response.getStatusCode() + ' - ' + response.getStatus() + 
                    (String.isNotBlank(response.getBody()) ? ' - Body: ' + response.getBody().substring(0, Math.min(500, response.getBody().length())) : '') 
                    : 'No response from AI service';
                errorMsg += '\nConnection: ' + connection.Name + ' (Named Credential: ' + connection.Named_Credential__c + ')';
                throw new AuraHandledException('AI service error: ' + errorMsg);
            }
            
        } catch (AuraHandledException ahe) {
            result.success = false;
            result.errorMessage = ahe.getMessage();
            GPTfyException.Log(ahe, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw ahe;
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error generating agent details: ' + e.getMessage();
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException(result.errorMessage + ' (Type: ' + e.getTypeName() + ', Line: ' + e.getLineNumber() + ')');
        }
    }
    
    /**
     * Creates an agent record with associated skills
     * @param agentName Name of the agent
     * @param description Description of the agent
     * @param systemPrompt System prompt for the agent
     * @param welcomeMessage Welcome message for the agent
     * @param skillIds List of skill IDs to associate
     * @return ID of the created agent
     */
    @AuraEnabled
    public static String createAgent(String agentName, String description, String systemPrompt, String welcomeMessage, List<String> skillIds) {
        String methodName = 'createAgent';
        String supportData = 'Agent Name: ' + agentName + ', Skill IDs: ' + JSON.serialize(skillIds);
        
        try {
            if (String.isBlank(agentName)) {
                throw new AuraHandledException('Agent name cannot be empty');
            }
            
            // Query for Agentic AI Connection
            List<AI_Connection__c> agenticConnections = [
                SELECT Id
                FROM AI_Connection__c
                WHERE Type__c = 'Agentic'
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (agenticConnections.isEmpty()) {
                throw new AuraHandledException('No Agentic AI Connection found. Please configure an AI Connection with Type = Agentic.');
            }
            
            // Create agent record with AI_Model__c and default TTL values
            AI_Agent__c agent = new AI_Agent__c(
                Name = agentName,
                Description__c = description,
                System_Prompt__c = systemPrompt,
                Welcome_Message__c = welcomeMessage,
                Status__c = 'Draft',
                AI_Model__c = agenticConnections[0].Id,
                TTL__c = 60,
                TTL_Message__c = 'Expired'
            );
            
            // Insert agent with FLS check
            List<AI_Agent__c> agentsToInsert = FLSCheck.getInstance().insertDML(new List<AI_Agent__c>{agent});
            
            if (agentsToInsert == null || agentsToInsert.isEmpty()) {
                throw new AuraHandledException('Failed to create agent. Please check field-level security permissions.');
            }
            
            agent = agentsToInsert[0];

            List<AI_Prompt__c> prompts = [SELECT Id, Name FROM AI_Prompt__c WHERE Id IN :skillIds];
            skillIds.clear();

            for (AI_Prompt__c prompt : prompts) {
                skillIds.add(prompt.Id);
            }
            
            // Create junction records for skills
            if (skillIds != null && !skillIds.isEmpty()) {
                List<AI_Agent_Skill__c> agentSkills = new List<AI_Agent_Skill__c>();
                for (String skillId : skillIds) {
                    agentSkills.add(new AI_Agent_Skill__c(
                        AI_Agent__c = agent.Id,
                        AI_Prompt__c = skillId
                    ));
                }
                
                if (!agentSkills.isEmpty()) {
                    // Insert skills with FLS check
                    FLSCheck.getInstance().insertDML(agentSkills);
                }
            }
            
            return agent.Id;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error creating agent: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves all agents for the Explore Agents section
     * @return List of AgentListWrapper
     * @jira V2-7442
     */
    @AuraEnabled(cacheable=true)
    public static List<AgentListWrapper> getActiveAgents() {
        String methodName = 'getActiveAgents';
        try {
            List<AI_Agent__c> agents = [
                SELECT Id, Name, System_Prompt__c, Status__c, Developer_Name__c, Description__c
                FROM AI_Agent__c
                WITH USER_MODE
                ORDER BY Name DESC
            ];
            
            List<AgentListWrapper> wrappers = new List<AgentListWrapper>();
            for (AI_Agent__c agent : agents) {
                wrappers.add(new AgentListWrapper(agent));
            }
            
            return wrappers;
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching agents: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves the namespace prefix for the current org
     * Uses AIConstants.NAMESPACE to get the namespace dynamically
     * Returns empty string for non-namespaced orgs
     * @return String - The namespace prefix (without trailing underscore) or empty string
     * @jira V2-7442
     */
    @AuraEnabled(cacheable=true)
    public static String getNamespace() {
        try {
            String namespace = AIConstants.NAMESPACE;
            return String.isNotBlank(namespace) ? namespace : '';
        } catch (Exception e) {
            // Return empty string if any error occurs
            return '';
        }
    }
    
    /**
     * Parses the AI-generated JSON content into AgentDetailsWrapper
     * Handles JSON extraction from markdown code blocks and validates required fields
     * @param jsonContent The parsed content from AI response
     * @param fallbackInput User's original input for fallback description
     * @return AgentDetailsWrapper with parsed agent details
     * @jira V2-7442
     */
    private static AgentDetailsWrapper parseAgentDetailsFromJSON(String jsonContent, String fallbackInput) {
        AgentDetailsWrapper wrapper = new AgentDetailsWrapper();
        
        try {
            // Clean the content - remove markdown code blocks if present
            String cleanedContent = jsonContent.trim();
            
            if (cleanedContent.startsWith('```json')) {
                cleanedContent = cleanedContent.replaceFirst('(?i)^```json\\s*', '').replaceFirst('```\\s*$', '');
            } else if (cleanedContent.startsWith('```')) {
                cleanedContent = cleanedContent.replaceFirst('^```\\s*', '').replaceFirst('```\\s*$', '');
            }
            
            cleanedContent = cleanedContent.trim();
            
            // Extract JSON if it's embedded in text using pattern matching
            Pattern jsonPattern = Pattern.compile('\\{[\\s\\S]*\\}');
            Matcher jsonMatcher = jsonPattern.matcher(cleanedContent);
            if (jsonMatcher.find()) {
                cleanedContent = jsonMatcher.group(0);
            }
            
            // Parse the JSON
            Map<String, Object> parsedData = (Map<String, Object>) JSON.deserializeUntyped(cleanedContent);
            
            // Extract fields with defaults
            wrapper.name = parsedData.containsKey('name') ? String.valueOf(parsedData.get('name')) : 'New Agent';
            wrapper.description = parsedData.containsKey('description') ? String.valueOf(parsedData.get('description')) : fallbackInput;
            wrapper.systemPrompt = parsedData.containsKey('systemPrompt') ? String.valueOf(parsedData.get('systemPrompt')) : 'You are a helpful AI assistant.';
            wrapper.welcomeMessage = parsedData.containsKey('welcomeMessage') ? String.valueOf(parsedData.get('welcomeMessage')) : 'Hello! How can I help you today?';
            
            // Extract skill IDs
            if (parsedData.containsKey('selectedSkillIds') && parsedData.get('selectedSkillIds') != null) {
                List<Object> skillIdsObj = (List<Object>) parsedData.get('selectedSkillIds');
                wrapper.selectedSkillIds = new List<String>();
                for (Object skillIdObj : skillIdsObj) {
                    wrapper.selectedSkillIds.add(String.valueOf(skillIdObj));
                }
            }
            
            wrapper.success = true;
            return wrapper;
            
        } catch (Exception e) {
            wrapper.success = false;
            wrapper.errorMessage = 'Failed to parse agent details from JSON: ' + e.getMessage();
            // Set defaults for failed parsing
            wrapper.name = 'New Agent';
            wrapper.description = fallbackInput;
            wrapper.systemPrompt = 'You are a helpful AI assistant.';
            wrapper.welcomeMessage = 'Hello! How can I help you today?';
            wrapper.selectedSkillIds = new List<String>();
            return wrapper;
        }
    }
    
    /**
     * Helper method to get GPTfy connection
     * NOTE: Connection name is hardcoded - consider moving to Custom Metadata for environment-agnostic configuration
     * @return AI_Connection__c record
     */
    private static AI_Connection__c getGPTfyConnection() {
        String methodName = 'getGPTfyConnection';
        try {
            String connectionName = 'GPTfy (OpenAI)';
            
            List<AI_Connection__c> connections = [
                SELECT Id, Name, Named_Credential__c, Model__c, Max_Tokens__c, 
                       Temperature__c, Top_P__c, EndPoint_URL__c, AI_Technology__c,
                       Connector_Class__c, Processing_Class__c, Version__c, 
                       Additional_Parameters__c
                FROM AI_Connection__c
                WHERE Name = :connectionName
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (connections.isEmpty()) {
                throw new AuraHandledException('GPTfy connection (' + connectionName + ') not found. Please configure AI Connection.');
            }
            
            return connections[0];
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, 'Connection Name: GPTfy (OpenAI)');
            throw e;
        }
    }
}