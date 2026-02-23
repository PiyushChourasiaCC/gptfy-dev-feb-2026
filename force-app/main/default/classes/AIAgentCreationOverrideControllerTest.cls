/**
 * @description Test class for AIAgentCreationOverrideController
 * @author Plumcloud Labs
 */
@isTest
public with sharing class AIAgentCreationOverrideControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create AI Connection with Type = Agentic
        AI_Connection__c agenticConn = new AI_Connection__c(
            Name = 'Test Agentic Model',
            Type__c = 'Agentic',
            Named_Credential__c = 'TestCred',
            AI_Technology__c = 'GPTfy'
        );
        insert agenticConn;
        
        // Create AI Agent
        AI_Agent__c agent = new AI_Agent__c(
            Name = 'Test Agent',
            Description__c = 'Test Description',
            System_Prompt__c = 'Test System Prompt',
            Welcome_Message__c = 'Welcome!',
            Status__c = 'Active',
            AI_Model__c = agenticConn.Id,
            Use_Thread_Id__c = true,
            TTL_Message__c = 'Session expired',
            TTL__c = 30,
            RAG__c = '',
            Profiles__c = 'System Administrator',
            Permission_Sets__c = 'Test Permission',
            Channels__c = 'Web;Mobile'
        );
        insert agent;
        
        // Create AI Prompts for skills
        AI_Prompt__c prompt1 = new AI_Prompt__c(
            Name = 'Test Skill 1',
            Object__c = 'Account',
            Status__c = 'Active',
            Type__c = 'Agentic'
        );
        AI_Prompt__c prompt2 = new AI_Prompt__c(
            Name = 'Test Skill 2',
            Object__c = 'Contact',
            Status__c = 'Active',
            Type__c = 'Agentic'
        );
        insert new List<AI_Prompt__c>{prompt1, prompt2};
        
        // Create AI Agent Skill junction
        AI_Agent_Skill__c skill = new AI_Agent_Skill__c(
            AI_Agent__c = agent.Id,
            AI_Prompt__c = prompt1.Id
        );
        insert skill;
    }
    
    private static AI_Agent__c getTestAgent() {
        return [SELECT Id, Name, Description__c, System_Prompt__c, Welcome_Message__c, 
                Status__c, AI_Model__c, Use_Thread_Id__c, TTL_Message__c, TTL__c 
                FROM AI_Agent__c LIMIT 1];
    }
    
    private static AI_Prompt__c getTestPrompt(String name) {
        return [SELECT Id FROM AI_Prompt__c WHERE Name = :name LIMIT 1];
    }
    
    @isTest
    static void testGetAgentData() {
        AI_Agent__c agent = getTestAgent();
        
        Test.startTest();
        AIAgentCreationOverrideController.AgentDataWrapper result = AIAgentCreationOverrideController.getAgentData(agent.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.agent, 'Agent wrapper should not be null');
        Assert.areEqual('Test Agent', result.agent.name, 'Agent name should match');
        Assert.isNotNull(result.currentSkills, 'Skills should not be null');
    }
    
    @isTest
    static void testGetAgentDataBlankId() {
        Test.startTest();
        try {
            AIAgentCreationOverrideController.getAgentData(null);
            Assert.fail('Should throw exception for blank ID');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetAgenticAIModels() {
        Test.startTest();
        List<AIAgentCreationOverrideController.OptionWrapper> result = AIAgentCreationOverrideController.getAgenticAIModels();
        Test.stopTest();
        
        Assert.isTrue(result.size() > 0, 'Should return at least one AI model');
        Assert.areEqual('Test Agentic Model', result[0].label, 'Model name should match');
    }
    
    @isTest
    static void testGetKnowledgeBases() {
        Test.startTest();
        List<AIAgentCreationOverrideController.OptionWrapper> result = AIAgentCreationOverrideController.getKnowledgeBases();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testGetAgentSkills() {
        AI_Agent__c agent = getTestAgent();
        
        Test.startTest();
        List<AIAgentCreationOverrideController.SkillWrapper> result = AIAgentCreationOverrideController.getAgentSkills(agent.Id);
        Test.stopTest();
        
        Assert.isTrue(result.size() > 0, 'Should return at least one skill');
    }
    
    @isTest
    static void testGetAvailablePrompts() {
        Test.startTest();
        List<AIAgentCreationOverrideController.OptionWrapper> result = AIAgentCreationOverrideController.getAvailablePrompts();
        Test.stopTest();
        
        Assert.isTrue(result.size() >= 2, 'Should return at least two prompts');
    }
    
    @isTest
    static void testGetProfileOptions() {
        Test.startTest();
        List<AIAgentCreationOverrideController.OptionWrapper> result = AIAgentCreationOverrideController.getProfileOptions();
        Test.stopTest();
        
        Assert.isTrue(result.size() > 0, 'Should return profiles');
    }
    
    @isTest
    static void testGetPermissionSetOptions() {
        Test.startTest();
        List<AIAgentCreationOverrideController.OptionWrapper> result = AIAgentCreationOverrideController.getPermissionSetOptions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }
    
    @isTest
    static void testSaveAgent() {
        AI_Agent__c agent = getTestAgent();
        AI_Prompt__c prompt2 = getTestPrompt('Test Skill 2');
        
        AIAgentCreationOverrideController.AgentWrapper wrapper = new AIAgentCreationOverrideController.AgentWrapper(agent);
        wrapper.name = 'Updated Agent';
        wrapper.description = 'Updated Description';
        
        String agentJson = JSON.serialize(wrapper);
        
        Test.startTest();
        String resultId = AIAgentCreationOverrideController.saveAgent(
            agentJson,
            new List<String>{prompt2.Id},
            new List<String>(),
            new List<String>{'System Administrator'},
            new List<String>{'Test Permission'},
            new List<String>{'Web'}
        );
        Test.stopTest();
        
        Assert.areEqual(agent.Id, resultId, 'Should return agent ID');
        AI_Agent__c updated = [SELECT Name FROM AI_Agent__c WHERE Id = :agent.Id];
        Assert.areEqual('Updated Agent', updated.Name, 'Name should be updated');
    }
    
    @isTest
    static void testSaveAgentBlankData() {
        Test.startTest();
        try {
            AIAgentCreationOverrideController.saveAgent(null, null, null, null, null, null);
            Assert.fail('Should throw exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSaveAgentBlankId() {
        AIAgentCreationOverrideController.AgentWrapper wrapper = new AIAgentCreationOverrideController.AgentWrapper(
            new AI_Agent__c(Name = 'Test')
        );
        
        Test.startTest();
        try {
            AIAgentCreationOverrideController.saveAgent(JSON.serialize(wrapper), null, null, null, null, null);
            Assert.fail('Should throw exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testUpdateAgentName() {
        AI_Agent__c agent = getTestAgent();
        
        Test.startTest();
        AIAgentCreationOverrideController.updateAgentName(agent.Id, 'New Agent Name');
        Test.stopTest();
        
        AI_Agent__c updated = [SELECT Name FROM AI_Agent__c WHERE Id = :agent.Id];
        Assert.areEqual('New Agent Name', updated.Name, 'Name should be updated');
    }
    
    @isTest
    static void testUpdateAgentNameBlankId() {
        Test.startTest();
        try {
            AIAgentCreationOverrideController.updateAgentName(null, 'Test');
            Assert.fail('Should throw exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testUpdateAgentNameBlankName() {
        AI_Agent__c agent = getTestAgent();
        
        Test.startTest();
        try {
            AIAgentCreationOverrideController.updateAgentName(agent.Id, '');
            Assert.fail('Should throw exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteAgent() {
        AI_Agent__c agent = getTestAgent();
        
        Test.startTest();
        AIAgentCreationOverrideController.deleteAgent(agent.Id);
        Test.stopTest();
        
        List<AI_Agent__c> agents = [SELECT Id FROM AI_Agent__c WHERE Id = :agent.Id];
        Assert.isTrue(agents.isEmpty(), 'Agent should be deleted');
    }
    
    @isTest
    static void testDeleteAgentBlankId() {
        Test.startTest();
        try {
            AIAgentCreationOverrideController.deleteAgent(null);
            Assert.fail('Should throw exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetNamespace() {
        Test.startTest();
        String result = AIAgentCreationOverrideController.getNamespace();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Namespace should not be null');
    }
    
    @isTest
    static void testWrapperClasses() {
        Test.startTest();
        // Test AgentWrapper
        AI_Agent__c agent = new AI_Agent__c(
            Name = 'Test',
            Description__c = 'Desc',
            System_Prompt__c = 'Prompt',
            Welcome_Message__c = 'Welcome',
            Status__c = 'Active',
            Use_Thread_Id__c = true,
            TTL_Message__c = 'TTL',
            TTL__c = 10
        );
        AIAgentCreationOverrideController.AgentWrapper aw = new AIAgentCreationOverrideController.AgentWrapper(agent);
        Assert.areEqual('Test', aw.name, 'Name should match');
        
        // Test AgentDataWrapper
        AIAgentCreationOverrideController.AgentDataWrapper adw = new AIAgentCreationOverrideController.AgentDataWrapper();
        adw.agent = aw;
        adw.currentSkills = new List<AIAgentCreationOverrideController.SkillWrapper>();
        adw.selectedKnowledgeBases = new List<String>();
        adw.selectedProfiles = new List<String>();
        adw.selectedPermissionSets = new List<String>();
        adw.selectedChannels = new List<String>();
        Assert.isNotNull(adw.agent, 'Agent should not be null');
        
        // Test SkillWrapper
        AIAgentCreationOverrideController.SkillWrapper sw = new AIAgentCreationOverrideController.SkillWrapper();
        sw.skillId = 'test';
        sw.promptId = 'prompt';
        sw.promptName = 'Prompt Name';
        Assert.areEqual('test', sw.skillId, 'Skill ID should match');
        
        // Test OptionWrapper
        AIAgentCreationOverrideController.OptionWrapper ow = new AIAgentCreationOverrideController.OptionWrapper();
        ow.label = 'Label';
        ow.value = 'Value';
        Assert.areEqual('Label', ow.label, 'Label should match');
        Test.stopTest();
    }
}