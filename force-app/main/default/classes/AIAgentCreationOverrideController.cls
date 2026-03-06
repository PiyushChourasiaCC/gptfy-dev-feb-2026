/**
 * @description Controller for AIAgentCreationOverride component
 * Handles fetching and saving AI Agent configuration data with proper FLS checks and exception logging
 * @author Plumcloud Labs
 * @jira V2-7442
 */
public with sharing class AIAgentCreationOverrideController {
    
    private static final String APPLICATION_NAME = 'GPTfy';
    private static final String MODULE_NAME = 'AI Agent';
    private static final String CLASS_NAME = 'AIAgentCreationOverrideController';
    
    /**
     * Wrapper class for agent data with field values
     * Provides a clean interface without exposing sObject directly
     */
    public class AgentWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String systemPrompt { get; set; }
        @AuraEnabled public String welcomeMessage { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String aiModel { get; set; }
        @AuraEnabled public Boolean useThreadId { get; set; }
        @AuraEnabled public String ttlMessage { get; set; }
        @AuraEnabled public Decimal ttl { get; set; }
        
        public AgentWrapper(AI_Agent__c agent) {
            this.id = agent.Id;
            this.name = agent.Name;
            this.description = agent.Description__c;
            this.systemPrompt = agent.System_Prompt__c;
            this.welcomeMessage = agent.Welcome_Message__c;
            this.status = agent.Status__c;
            this.aiModel = agent.AI_Model__c;
            this.useThreadId = agent.Use_Thread_Id__c != null ? agent.Use_Thread_Id__c : false;
            this.ttlMessage = agent.TTL_Message__c;
            this.ttl = agent.TTL__c;
        }
    }
    
    /**
     * Wrapper class for complete agent data with related information
     */
    public class AgentDataWrapper {
        @AuraEnabled public AgentWrapper agent { get; set; }
        @AuraEnabled public List<SkillWrapper> currentSkills { get; set; }
        @AuraEnabled public List<String> selectedKnowledgeBases { get; set; }
        @AuraEnabled public List<String> selectedProfiles { get; set; }
        @AuraEnabled public List<String> selectedPermissionSets { get; set; }
        @AuraEnabled public List<String> selectedChannels { get; set; }
    }
    
    /**
     * Wrapper class for skill information
     */
    public class SkillWrapper {
        @AuraEnabled public String skillId { get; set; }
        @AuraEnabled public String promptId { get; set; }
        @AuraEnabled public String promptName { get; set; }
    }
    
    /**
     * Wrapper class for dropdown/listbox options
     */
    public class OptionWrapper {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }
    
    /**
     * Wrapper class for AI Agent Intent information
     */
    public class IntentWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal sequence { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        
        public IntentWrapper(AI_Agent_Intent__c intent) {
            this.id = intent.Id;
            this.name = intent.Name;
            this.description = intent.Description__c;
            this.sequence = intent.Sequence__c;
            this.isActive = intent.Is_Active__c != null ? intent.Is_Active__c : false;
        }
    }
    
    /**
     * Fetches complete agent data with related information
     * @param agentId ID of the AI_Agent__c record
     * @return AgentDataWrapper containing all agent information
     */
    @AuraEnabled
    public static AgentDataWrapper getAgentData(Id agentId) {
        String methodName = 'getAgentData';
        try {
            if (String.isBlank(agentId)) {
                throw new AuraHandledException('Agent ID is required');
            }
            
            AgentDataWrapper wrapper = new AgentDataWrapper();
            
            // Fetch agent record with all fields
            List<AI_Agent__c> agents = [
                SELECT Id, Name, Description__c, System_Prompt__c, Welcome_Message__c, Status__c,
                       AI_Model__c, RAG__c, Profiles__c, Permission_Sets__c,
                       Use_Thread_Id__c, TTL_Message__c, TTL__c, Channels__c
                FROM AI_Agent__c
                WHERE Id = :agentId
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (agents.isEmpty()) {
                throw new AuraHandledException('Agent record not found');
            }
            
            AI_Agent__c agentRecord = agents[0];
            
            // Wrap agent data in AgentWrapper
            wrapper.agent = new AgentWrapper(agentRecord);
            
            // Fetch current skills
            wrapper.currentSkills = getAgentSkills(agentId);
            
            // Parse selected knowledge bases from RAG__c field
            wrapper.selectedKnowledgeBases = new List<String>();
            if (String.isNotBlank(agentRecord.RAG__c)) {
                wrapper.selectedKnowledgeBases = agentRecord.RAG__c.split(';');
            }
            
            // Parse selected profiles
            wrapper.selectedProfiles = new List<String>();
            if (String.isNotBlank(agentRecord.Profiles__c)) {
                wrapper.selectedProfiles = agentRecord.Profiles__c.split(';');
            }
            
            // Parse selected permission sets
            wrapper.selectedPermissionSets = new List<String>();
            if (String.isNotBlank(agentRecord.Permission_Sets__c)) {
                wrapper.selectedPermissionSets = agentRecord.Permission_Sets__c.split(';');
            }
            
            // Parse selected channels from Channels__c field
            wrapper.selectedChannels = new List<String>();
            if (String.isNotBlank(agentRecord.Channels__c)) {
                wrapper.selectedChannels = agentRecord.Channels__c.split(';');
            }
            
            return wrapper;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, 'Agent ID: ' + agentId);
            throw new AuraHandledException('Error fetching agent data: ' + e.getMessage());
        }
    }
    
    /**
     * Fetches AI Connection records where Type__c = 'Agentic'
     * @return List of OptionWrapper for dropdown
     */
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getAgenticAIModels() {
        String methodName = 'getAgenticAIModels';
        try {
            List<OptionWrapper> options = new List<OptionWrapper>();
            
            List<AI_Connection__c> connections = [
                SELECT Id, Name
                FROM AI_Connection__c
                WHERE Type__c = 'Agentic'
                WITH USER_MODE
                ORDER BY Name
                LIMIT 1000
            ];
            
            for (AI_Connection__c conn : connections) {
                OptionWrapper option = new OptionWrapper();
                option.label = conn.Name;
                option.value = conn.Id;
                options.add(option);
            }
            
            return options;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching AI models: ' + e.getMessage());
        }
    }
    
    /**
     * Fetches all AI_RAG_Sync__c records for knowledge base selection
     * @return List of OptionWrapper for dual listbox
     */
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getKnowledgeBases() {
        String methodName = 'getKnowledgeBases';
        try {
            List<OptionWrapper> options = new List<OptionWrapper>();
            
            List<AI_RAG_Sync__c> ragSyncs = [
                SELECT Id, Name
                FROM AI_RAG_Sync__c
                WITH USER_MODE
                ORDER BY Name
                LIMIT 1000
            ];
            
            for (AI_RAG_Sync__c rag : ragSyncs) {
                OptionWrapper option = new OptionWrapper();
                option.label = rag.Name;
                option.value = rag.Id;
                options.add(option);
            }
            
            return options;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching knowledge bases: ' + e.getMessage());
        }
    }
    
    /**
     * Fetches current AI_Agent_Skill__c junction records for an agent
     * @param agentId ID of the AI_Agent__c record
     * @return List of SkillWrapper with prompt information
     */
    @AuraEnabled
    public static List<SkillWrapper> getAgentSkills(Id agentId) {
        String methodName = 'getAgentSkills';
        try {
            List<SkillWrapper> skills = new List<SkillWrapper>();
            
            List<AI_Agent_Skill__c> agentSkills = [
                SELECT Id, AI_Prompt__c, AI_Prompt__r.Name
                FROM AI_Agent_Skill__c
                WHERE AI_Agent__c = :agentId
                WITH USER_MODE
                ORDER BY AI_Prompt__r.Name
                LIMIT 50000
            ];
            
            for (AI_Agent_Skill__c skill : agentSkills) {
                SkillWrapper wrapper = new SkillWrapper();
                wrapper.skillId = skill.Id;
                wrapper.promptId = skill.AI_Prompt__c;
                wrapper.promptName = skill.AI_Prompt__r.Name;
                skills.add(wrapper);
            }
            
            return skills;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, 'Agent ID: ' + agentId);
            throw new AuraHandledException('Error fetching agent skills: ' + e.getMessage());
        }
    }
    
    /**
     * Fetches available prompts for skill selection
     * @return List of OptionWrapper for dual listbox
     */
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getAvailablePrompts() {
        String methodName = 'getAvailablePrompts';
        try {
            List<OptionWrapper> options = new List<OptionWrapper>();
            
            List<AI_Prompt__c> prompts = [
                SELECT Id, Name
                FROM AI_Prompt__c
                WHERE Status__c = 'Active' AND Type__c = 'Agentic'
                WITH USER_MODE
                ORDER BY Name
                LIMIT 1000
            ];
            
            for (AI_Prompt__c prompt : prompts) {
                OptionWrapper option = new OptionWrapper();
                option.label = prompt.Name;
                option.value = prompt.Id;
                options.add(option);
            }
            
            return options;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching available prompts: ' + e.getMessage());
        }
    }
    
    /**
     * Fetches all Profile options
     * @return List of OptionWrapper for dual listbox
     */
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getProfileOptions() {
        String methodName = 'getProfileOptions';
        try {
            List<OptionWrapper> options = new List<OptionWrapper>();
            
            List<Profile> profiles = [
                SELECT Id, Name
                FROM Profile
                ORDER BY Name
                LIMIT 50000
            ];
            
            for (Profile p : profiles) {
                OptionWrapper option = new OptionWrapper();
                option.label = p.Name;
                option.value = p.Name;
                options.add(option);
            }
            
            return options;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching profiles: ' + e.getMessage());
        }
    }
    
    /**
     * Fetches all Permission Set options
     * @return List of OptionWrapper for dual listbox
     */
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getPermissionSetOptions() {
        String methodName = 'getPermissionSetOptions';
        try {
            List<OptionWrapper> options = new List<OptionWrapper>();
            
            List<PermissionSet> permissionSets = [
                SELECT Id, Label
                FROM PermissionSet
                WHERE Type IN ('Regular', 'Standard')
                ORDER BY Label
                LIMIT 50000
            ];
            
            for (PermissionSet ps : permissionSets) {
                OptionWrapper option = new OptionWrapper();
                option.label = ps.Label;
                option.value = ps.Label;
                options.add(option);
            }
            
            return options;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, null);
            throw new AuraHandledException('Error fetching permission sets: ' + e.getMessage());
        }
    }
    
    /**
     * Saves agent data and manages related junction records
     * @param agentData JSON string of AgentWrapper data
     * @param selectedSkillIds List of selected AI_Prompt__c IDs
     * @param selectedKnowledgeBaseIds List of selected AI_RAG_Sync__c IDs
     * @param selectedProfiles List of selected profile names
     * @param selectedPermissionSets List of selected permission set names
     * @param selectedChannels List of selected channel names
     * @return ID of the updated agent
     */
    @AuraEnabled
    public static String saveAgent(
        String agentData,
        List<String> selectedSkillIds,
        List<String> selectedKnowledgeBaseIds,
        List<String> selectedProfiles,
        List<String> selectedPermissionSets,
        List<String> selectedChannels
    ) {
        String methodName = 'saveAgent';
        String supportData = 'Agent Data: ' + agentData;
        
        try {
            if (String.isBlank(agentData)) {
                throw new AuraHandledException('Agent data is required');
            }
            
            // Deserialize agent wrapper data
            AgentWrapper agentWrapper = (AgentWrapper) JSON.deserialize(agentData, AgentWrapper.class);
            
            if (String.isBlank(agentWrapper.id)) {
                throw new AuraHandledException('Agent ID is required');
            }
            
            // Create AI_Agent__c record from wrapper
            AI_Agent__c agent = new AI_Agent__c(
                Id = agentWrapper.id,
                Name = agentWrapper.name,
                Description__c = agentWrapper.description,
                System_Prompt__c = agentWrapper.systemPrompt,
                Welcome_Message__c = agentWrapper.welcomeMessage,
                Status__c = agentWrapper.status,
                AI_Model__c = agentWrapper.aiModel,
                Use_Thread_Id__c = agentWrapper.useThreadId != null ? agentWrapper.useThreadId : false,
                TTL_Message__c = agentWrapper.ttlMessage,
                TTL__c = agentWrapper.ttl
            );
            
            // Convert lists to semicolon-separated strings
            agent.RAG__c = String.isNotBlank(String.join(selectedKnowledgeBaseIds, ';')) 
                ? String.join(selectedKnowledgeBaseIds, ';') 
                : null;
            
            agent.Profiles__c = String.isNotBlank(String.join(selectedProfiles, ';')) 
                ? String.join(selectedProfiles, ';') 
                : null;
            
            agent.Permission_Sets__c = String.isNotBlank(String.join(selectedPermissionSets, ';')) 
                ? String.join(selectedPermissionSets, ';') 
                : null;
            
            // Convert selected channels to semicolon-separated string
            agent.Channels__c = String.isNotBlank(String.join(selectedChannels, ';')) 
                ? String.join(selectedChannels, ';') 
                : null;
            
            // Update agent record with FLS check
            List<AI_Agent__c> agentsToUpdate = FLSCheck.getInstance().updateDML(new List<AI_Agent__c>{agent});
            
            if (agentsToUpdate == null || agentsToUpdate.isEmpty()) {
                throw new AuraHandledException('Failed to update agent. Please check field-level security permissions.');
            }
            
            // Manage AI_Agent_Skill__c junction records
            if (selectedSkillIds != null) {
                manageAgentSkills(agent.Id, selectedSkillIds);
            }
            
            return agent.Id;
            
        } catch (JSONException e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('JSON parsing error: ' + e.getMessage());
        } catch (DmlException e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Database error: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error saving agent: ' + e.getMessage());
        }
    }
    
    /**
     * Manages AI_Agent_Skill__c junction records
     * Deletes skills that are no longer selected and inserts new ones
     * @param agentId ID of the AI_Agent__c record
     * @param selectedSkillIds List of selected AI_Prompt__c IDs
     */
    private static void manageAgentSkills(Id agentId, List<String> selectedSkillIds) {
        String methodName = 'manageAgentSkills';
        String supportData = 'Agent ID: ' + agentId + ', Selected Skill IDs: ' + JSON.serialize(selectedSkillIds);
        
        try {
            // Get current skills
            List<AI_Agent_Skill__c> currentSkills = [
                SELECT Id, AI_Prompt__c
                FROM AI_Agent_Skill__c
                WHERE AI_Agent__c = :agentId
                WITH USER_MODE
                LIMIT 50000
            ];
            
            Set<String> currentPromptIds = new Set<String>();
            Map<String, AI_Agent_Skill__c> promptToSkillMap = new Map<String, AI_Agent_Skill__c>();
            
            for (AI_Agent_Skill__c skill : currentSkills) {
                currentPromptIds.add(skill.AI_Prompt__c);
                promptToSkillMap.put(skill.AI_Prompt__c, skill);
            }
            
            Set<String> newPromptIds = new Set<String>(selectedSkillIds);
            
            // Determine skills to delete (current but not selected)
            List<AI_Agent_Skill__c> skillsToDelete = new List<AI_Agent_Skill__c>();
            for (String promptId : currentPromptIds) {
                if (!newPromptIds.contains(promptId)) {
                    skillsToDelete.add(promptToSkillMap.get(promptId));
                }
            }
            
            // Determine skills to insert (selected but not current)
            List<AI_Agent_Skill__c> skillsToInsert = new List<AI_Agent_Skill__c>();
            for (String promptId : newPromptIds) {
                if (!currentPromptIds.contains(promptId)) {
                    skillsToInsert.add(new AI_Agent_Skill__c(
                        AI_Agent__c = agentId,
                        AI_Prompt__c = promptId
                    ));
                }
            }
            
            // Perform DML operations with FLS check
            if (!skillsToDelete.isEmpty()) {
                FLSCheck.getInstance().deleteDML(skillsToDelete);
            }
            
            if (!skillsToInsert.isEmpty()) {
                FLSCheck.getInstance().insertDML(skillsToInsert);
            }
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw e;
        }
    }
    
    /**
     * Updates only the Name field of an AI_Agent__c record
     * @param agentId - The ID of the agent record to update
     * @param newName - The new name for the agent
     */
    @AuraEnabled
    public static void updateAgentName(Id agentId, String newName) {
        String methodName = 'updateAgentName';
        String supportData = 'Agent ID: ' + agentId + ', New Name: ' + newName;
        
        try {
            if (String.isBlank(agentId)) {
                throw new AuraHandledException('Agent ID is required');
            }
            
            if (String.isBlank(newName)) {
                throw new AuraHandledException('Agent name cannot be empty');
            }
            
            AI_Agent__c agent = new AI_Agent__c(
                Id = agentId,
                Name = newName.trim()
            );
            
            // Update with FLS check
            List<AI_Agent__c> agentsToUpdate = FLSCheck.getInstance().updateDML(new List<AI_Agent__c>{agent});
            
            if (agentsToUpdate == null || agentsToUpdate.isEmpty()) {
                throw new AuraHandledException('Failed to update agent name. Please check field-level security permissions.');
            }
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error updating agent name: ' + e.getMessage());
        }
    }
    
    /**
     * Deletes an AI Agent record and its related records
     * @param agentId ID of the AI_Agent__c record to delete
     */
    @AuraEnabled
    public static void deleteAgent(Id agentId) {
        String methodName = 'deleteAgent';
        String supportData = 'Agent ID: ' + agentId;
        
        try {
            if (String.isBlank(agentId)) {
                throw new AuraHandledException('Agent ID is required');
            }
            
            // Fetch the agent record
            List<AI_Agent__c> agents = [
                SELECT Id 
                FROM AI_Agent__c 
                WHERE Id = :agentId
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (agents.isEmpty()) {
                throw new AuraHandledException('Agent record not found');
            }
            
            // Delete the agent record with FLS check (cascade delete will handle related records)
            Boolean deleteSuccess = FLSCheck.getInstance().deleteDML(agents);
            
            if (!deleteSuccess) {
                throw new AuraHandledException('Failed to delete agent. Please check object-level security permissions.');
            }
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error deleting agent: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves the namespace prefix for the current org
     * Uses AIConstants.NAMESPACE to get the namespace dynamically
     * Returns empty string for non-namespaced orgs
     * @return String - The namespace prefix (without trailing underscore) or empty string
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
     * Fetches AI Agent Intents for display
     * @param agentId ID of the AI_Agent__c record
     * @return List of IntentWrapper containing intent information
     */
    @AuraEnabled
    public static List<IntentWrapper> getAgentIntents(Id agentId) {
        String methodName = 'getAgentIntents';
        String supportData = 'Agent ID: ' + agentId;
        try {
            if (String.isBlank(agentId)) {
                throw new AuraHandledException('Agent ID is required');
            }
            
            List<AI_Agent_Intent__c> intents = [
                SELECT Id, Name, Description__c, Sequence__c, Is_Active__c
                FROM AI_Agent_Intent__c
                WHERE AI_Agent__c = :agentId
                WITH USER_MODE
                ORDER BY Sequence__c ASC NULLS LAST, Name ASC
            ];
            
            List<IntentWrapper> intentWrappers = new List<IntentWrapper>();
            for (AI_Agent_Intent__c intent : intents) {
                intentWrappers.add(new IntentWrapper(intent));
            }
            
            return intentWrappers;
            
        } catch (Exception e) {
            GPTfyException.Log(e, APPLICATION_NAME, MODULE_NAME, CLASS_NAME, methodName, supportData);
            throw new AuraHandledException('Error fetching agent intents: ' + e.getMessage());
        }
    }
}