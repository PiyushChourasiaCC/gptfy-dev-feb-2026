/**
 * @description Test class for AIChatController
 * This test class manages chat history and AI file processing for the AI Security Audit feature.
 * It provides comprehensive testing for retrieving, creating, and updating chat history records.
 * 
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 11-07-2025
 * @last modified by Piyush Chourasia
 */
@isTest
private class AIChatControllerTest {
    
    /**
     * Test setup method to create necessary test data
     */
    @TestSetup
    static void makeData() {
        // Create test AI Connection records
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4',
            Named_Credential__c = 'Test_Credential'
        );
        insert aiConnection;
        
        AI_Connection__c aiConnectionFile = new AI_Connection__c(
            Name = 'Test AI Connection File',
            Model__c = 'gpt-4-turbo',
            Named_Credential__c = 'Test_Credential_File',
            Type__c = 'File'
        );
        insert aiConnectionFile;
        
        // Create test AI Prompt record
        AI_Prompt__c aiPrompt = new AI_Prompt__c(
            Name = 'Test AI Prompt',
            AI_Connection__c = aiConnection.Id,
            AI_Model_File_Processing__c = aiConnectionFile.Id,
            Include_Files__c = true
        );
        insert aiPrompt;
        
        // Create test AI Response record
        AI_Response__c aiResponse = new AI_Response__c(
            AI_Prompt__c = aiPrompt.Id,
            Vector_Store_Id__c = 'vs_test_123',
            Thread_Id__c = 'thread_test_123',
            Data_PII_Removed__c = 'Test extracted data content for processing'
        );
        insert aiResponse;
        
        // Create test AI Security Audit Detail records with chat history
        List<AIChatController.ChatHistory> chatHistoryList = new List<AIChatController.ChatHistory>();
        
        AIChatController.ChatHistory chat1 = new AIChatController.ChatHistory();
        chat1.question = 'What is the security status?';
        chat1.question_timestamp = '10:30 AM';
        chat1.answer = 'The security status is good.';
        chat1.answer_timestamp = '10:31 AM';
        chat1.sequence = 1;
        chatHistoryList.add(chat1);
        
        AIChatController.ChatHistory chat2 = new AIChatController.ChatHistory();
        chat2.question = 'Any vulnerabilities found?';
        chat2.question_timestamp = '10:35 AM';
        chat2.answer = 'No critical vulnerabilities were found.';
        chat2.answer_timestamp = '10:36 AM';
        chat2.sequence = 2;
        chatHistoryList.add(chat2);
        
        AI_Security_Audit_Detail__c chatDetail = new AI_Security_Audit_Detail__c(
            AI_Security_Audit__c = aiResponse.Id,
            Type__c = 'Chat',
            Message__c = JSON.serialize(chatHistoryList)
        );
        insert chatDetail;
        
        // Create additional detail record for testing multiple records
        List<AIChatController.ChatHistory> chatHistoryList2 = new List<AIChatController.ChatHistory>();
        
        AIChatController.ChatHistory chat3 = new AIChatController.ChatHistory();
        chat3.question = 'What are the recommendations?';
        chat3.question_timestamp = '11:00 AM';
        chat3.answer = 'Please implement additional security measures.';
        chat3.answer_timestamp = '11:01 AM';
        chat3.sequence = 3;
        chatHistoryList2.add(chat3);
        
        AI_Security_Audit_Detail__c chatDetail2 = new AI_Security_Audit_Detail__c(
            AI_Security_Audit__c = aiResponse.Id,
            Type__c = 'Chat',
            Message__c = JSON.serialize(chatHistoryList2)
        );
        insert chatDetail2;
    }
    
    /**
     * Mock HTTP callout class for successful AI responses
     */
    private class MockAIResponseSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String responseBody = '{"id": "response_12345", "object": "response", "content": "This is a test AI response to the user question."}';
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * Mock HTTP callout class for AI response errors
     */
    private class MockAIResponseError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(500);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error": {"message": "Internal server error"}}');
            return res;
        }
    }
    
    /**
     * Test retrieving chat history with existing records
     */
    @isTest
    static void testGetChatHistory_WithExistingRecords() {
        // Get test data
        AI_Response__c aiResponse = [SELECT Id FROM AI_Response__c LIMIT 1];
        
        Test.startTest();
        List<AIChatController.ChatHistory> chatHistory = AIChatController.getChatHistory(aiResponse.Id);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(chatHistory, 'Chat history should not be null');
        Assert.areEqual(3, chatHistory.size(), 'Should have 3 chat history records');
        
        // Verify first chat
        Assert.areEqual('What is the security status?', chatHistory[0].question, 'First chat question should match');
        Assert.areEqual('The security status is good.', chatHistory[0].answer, 'First chat answer should match');
        Assert.areEqual(1, chatHistory[0].sequence, 'First chat sequence should be 1');
        
        // Verify second chat
        Assert.areEqual('Any vulnerabilities found?', chatHistory[1].question, 'Second chat question should match');
        Assert.areEqual('No critical vulnerabilities were found.', chatHistory[1].answer, 'Second chat answer should match');
        Assert.areEqual(2, chatHistory[1].sequence, 'Second chat sequence should be 2');
        
        // Verify third chat
        Assert.areEqual('What are the recommendations?', chatHistory[2].question, 'Third chat question should match');
        Assert.areEqual('Please implement additional security measures.', chatHistory[2].answer, 'Third chat answer should match');
        Assert.areEqual(3, chatHistory[2].sequence, 'Third chat sequence should be 3');
    }
    
    /**
     * Test retrieving chat history with no existing records
     */
    @isTest
    static void testGetChatHistory_NoExistingRecords() {
        // Create a new AI Response without chat details
        AI_Connection__c aiConnection = [SELECT Id FROM AI_Connection__c LIMIT 1];
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        AI_Response__c newAiResponse = new AI_Response__c(
            AI_Prompt__c = aiPrompt.Id,
            Vector_Store_Id__c = 'vs_test_456',
            Thread_Id__c = 'thread_test_456'
        );
        insert newAiResponse;
        
        Test.startTest();
        List<AIChatController.ChatHistory> chatHistory = AIChatController.getChatHistory(newAiResponse.Id);
        Test.stopTest();
        
        // Assertions
        Assert.isNull(chatHistory, 'Chat history should be null for record without chat details');
    }
    
    /**
     * Test creating new chat history
     */
    @isTest
    static void testCreateNewChat() {
        String testMessage = 'How can I improve the security of my application?';
        
        Test.startTest();
        AIChatController.ChatHistory newChat = AIChatController.createNewChat(testMessage);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(newChat, 'New chat should not be null');
        Assert.areEqual(testMessage, newChat.question, 'Question should match input message');
        Assert.isNotNull(newChat.question_timestamp, 'Question timestamp should be set');
        Assert.isNull(newChat.answer, 'Answer should be null initially');
        Assert.isNull(newChat.answer_timestamp, 'Answer timestamp should be null initially');
        Assert.isNull(newChat.sequence, 'Sequence should be null initially');
    }
    
    /**
     * Test successful AI callout and chat history update
     */
    @isTest
    static void testMakeCallout_Success() {
        // Get test data
        AI_Response__c aiResponse = [SELECT Id FROM AI_Response__c LIMIT 1];
        
        // Create test chat
        AIChatController.ChatHistory testChat = AIChatController.createNewChat('What security measures should I implement?');
        String currentChatJson = JSON.serialize(testChat);
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new MockAIResponseSuccess());
        
        Test.startTest();
        AIChatController.ChatHistory result = AIChatController.makeCallout(aiResponse.Id, currentChatJson);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result chat should not be null');
        Assert.areEqual('What security measures should I implement?', result.question, 'Question should match input');
        Assert.isNotNull(result.answer, 'Answer should be populated');
        Assert.isNotNull(result.answer_timestamp, 'Answer timestamp should be set');
        Assert.isNotNull(result.sequence, 'Sequence should be set');
        
        // Verify AI Response record was updated
        AI_Response__c updatedResponse = [SELECT Thread_Id__c FROM AI_Response__c WHERE Id = :aiResponse.Id];
        Assert.areEqual('response_12345', updatedResponse.Thread_Id__c, 'Thread ID should be updated');
        
        // Verify chat detail was created/updated
        List<AI_Security_Audit_Detail__c> details = [SELECT Message__c FROM AI_Security_Audit_Detail__c WHERE AI_Security_Audit__c = :aiResponse.Id AND Type__c = 'Chat' ORDER BY CreatedDate DESC];
        Assert.isTrue(details.size() > 0, 'Chat detail should be created');
        
        List<AIChatController.ChatHistory> savedChats = (List<AIChatController.ChatHistory>) JSON.deserialize(details[0].Message__c, List<AIChatController.ChatHistory>.class);
        Assert.isTrue(savedChats.size() > 0, 'Saved chats should exist');
    }
     /**
     * Test successful AI callout and chat history update
     */
    @isTest
    static void testMakeCalloutNoDetails_Success() {
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        AI_Response__c aiResponse = new AI_Response__c(
            AI_Prompt__c = aiPrompt.Id,
            Vector_Store_Id__c = 'vs_test_456',
            Thread_Id__c = 'thread_test_456'
        );
        insert aiResponse;
        
        // Create test chat
        AIChatController.ChatHistory testChat = AIChatController.createNewChat('What security measures should I implement?');
        String currentChatJson = JSON.serialize(testChat);
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new MockAIResponseSuccess());
        
        Test.startTest();
        AIChatController.ChatHistory result = AIChatController.makeCallout(aiResponse.Id, currentChatJson);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result chat should not be null');
        Assert.areEqual('What security measures should I implement?', result.question, 'Question should match input');
        Assert.isNotNull(result.answer, 'Answer should be populated');
        Assert.isNotNull(result.answer_timestamp, 'Answer timestamp should be set');
        Assert.isNotNull(result.sequence, 'Sequence should be set');
        
        // Verify AI Response record was updated
        AI_Response__c updatedResponse = [SELECT Thread_Id__c FROM AI_Response__c WHERE Id = :aiResponse.Id];
        Assert.areEqual('response_12345', updatedResponse.Thread_Id__c, 'Thread ID should be updated');
        
        // Verify chat detail was created/updated
        List<AI_Security_Audit_Detail__c> details = [SELECT Message__c FROM AI_Security_Audit_Detail__c WHERE AI_Security_Audit__c = :aiResponse.Id AND Type__c = 'Chat' ORDER BY CreatedDate DESC];
        Assert.isTrue(details.size() > 0, 'Chat detail should be created');
        
        List<AIChatController.ChatHistory> savedChats = (List<AIChatController.ChatHistory>) JSON.deserialize(details[0].Message__c, List<AIChatController.ChatHistory>.class);
        Assert.isTrue(savedChats.size() > 0, 'Saved chats should exist');
    }
    /**
     * Test AI callout with file processing enabled
     */
    @isTest
    static void testMakeCallout_WithFileProcessing() {
        // Get test data and modify to use file processing
        AI_Response__c aiResponse = [SELECT Id, AI_Prompt__c FROM AI_Response__c LIMIT 1];
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c WHERE Id = :aiResponse.AI_Prompt__c];
        aiPrompt.Include_Files__c = true;
        update aiPrompt;
        
        // Create test chat
        AIChatController.ChatHistory testChat = AIChatController.createNewChat('Analyze the uploaded files for security issues');
        String currentChatJson = JSON.serialize(testChat);
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new MockAIResponseSuccess());
        
        Test.startTest();
        AIChatController.ChatHistory result = AIChatController.makeCallout(aiResponse.Id, currentChatJson);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result chat should not be null');
        Assert.areEqual('Analyze the uploaded files for security issues', result.question, 'Question should match input');
        Assert.isNotNull(result.answer, 'Answer should be populated');
    }
    
    /**
     * Test AI callout with existing chat history reaching field limit
     */
    @isTest
    static void testMakeCallout_FieldLimitExceeded() {
        // Get test data
        AI_Response__c aiResponse = [SELECT Id FROM AI_Response__c LIMIT 1];
        
        // Create a very long chat history to exceed field limit
        List<AIChatController.ChatHistory> longChatHistory = new List<AIChatController.ChatHistory>();
        for (Integer i = 0; i < 50; i++) {
            AIChatController.ChatHistory chat = new AIChatController.ChatHistory();
            chat.question = 'This is a very long question that is being repeated multiple times to test the field limit functionality. Question number ' + i;
            chat.answer = 'This is a very long answer that is being repeated multiple times to test the field limit functionality. Answer number ' + i;
            chat.sequence = i + 1;
            longChatHistory.add(chat);
        }
        
        // Update existing chat detail with long history
        AI_Security_Audit_Detail__c existingDetail = [SELECT Id FROM AI_Security_Audit_Detail__c WHERE AI_Security_Audit__c = :aiResponse.Id AND Type__c = 'Chat' LIMIT 1];
        existingDetail.Message__c = JSON.serialize(longChatHistory);
        update existingDetail;
        
        // Create test chat
        AIChatController.ChatHistory testChat = AIChatController.createNewChat('One more question to trigger field limit');
        String currentChatJson = JSON.serialize(testChat);
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new MockAIResponseSuccess());
        
        Test.startTest();
        AIChatController.ChatHistory result = AIChatController.makeCallout(aiResponse.Id, currentChatJson);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(result, 'Result chat should not be null');
        Assert.areEqual('One more question to trigger field limit', result.question, 'Question should match input');
        Assert.isNotNull(result.answer, 'Answer should be populated');
        
        // Verify new chat detail was created due to field limit
        List<AI_Security_Audit_Detail__c> details = [SELECT Id, Message__c FROM AI_Security_Audit_Detail__c WHERE AI_Security_Audit__c = :aiResponse.Id AND Type__c = 'Chat' ORDER BY CreatedDate DESC];
        Assert.isTrue(details.size() >= 2, 'Should have at least 2 chat detail records');
    }
    
    /**
     * Test ChatHistory comparison functionality
     */
    @isTest
    static void testChatHistory_Comparison() {
        Test.startTest();
        
        // Create test chat histories
        AIChatController.ChatHistory chat1 = new AIChatController.ChatHistory();
        chat1.sequence = 1;
        
        AIChatController.ChatHistory chat2 = new AIChatController.ChatHistory();
        chat2.sequence = 2;
        
        AIChatController.ChatHistory chat3 = new AIChatController.ChatHistory();
        chat3.sequence = null;
        
        AIChatController.ChatHistory chat4 = new AIChatController.ChatHistory();
        chat4.sequence = null;
        
        Test.stopTest();
        
        // Test comparison logic
        Assert.areEqual(-1, chat1.compareTo(chat2), 'Chat1 should be less than Chat2');
        Assert.areEqual(1, chat2.compareTo(chat1), 'Chat2 should be greater than Chat1');
        Assert.areEqual(-1, chat3.compareTo(chat1), 'Null sequence should be less than non-null');
        Assert.areEqual(1, chat1.compareTo(chat3), 'Non-null sequence should be greater than null');
        Assert.areEqual(0, chat3.compareTo(chat4), 'Two null sequences should be equal');
    }
    
    /**
     * Test ChatHistory fluent methods
     */
    @isTest
    static void testChatHistory_FluentMethods() {
        Test.startTest();
        
        AIChatController.ChatHistory chat = new AIChatController.ChatHistory();
        
        // Test fluent method chaining
        chat.addQuestion('Test question')
            .addAnswer('Test answer')
            .addSequence(5);
        
        Test.stopTest();
        
        // Assertions
        Assert.areEqual('Test question', chat.question, 'Question should be set correctly');
        Assert.isNotNull(chat.question_timestamp, 'Question timestamp should be set');
        Assert.areEqual('Test answer', chat.answer, 'Answer should be set correctly');
        Assert.isNotNull(chat.answer_timestamp, 'Answer timestamp should be set');
        Assert.areEqual(5, chat.sequence, 'Sequence should be set correctly');
    }
    
    /**
     * Test edge case with null chat message
     */
    @isTest
    static void testCreateNewChat_NullMessage() {
        Test.startTest();
        AIChatController.ChatHistory newChat = AIChatController.createNewChat(null);
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(newChat, 'New chat should not be null');
        Assert.isNull(newChat.question, 'Question should be null');
        Assert.isNotNull(newChat.question_timestamp, 'Question timestamp should still be set');
    }
    
    /**
     * Test edge case with empty chat message
     */
    @isTest
    static void testCreateNewChat_EmptyMessage() {
        Test.startTest();
        AIChatController.ChatHistory newChat = AIChatController.createNewChat('');
        Test.stopTest();
        
        // Assertions
        Assert.isNotNull(newChat, 'New chat should not be null');
        Assert.areEqual('', newChat.question, 'Question should be empty string');
        Assert.isNotNull(newChat.question_timestamp, 'Question timestamp should be set');
    }
    
    /**
     * Test chat history sorting
     */
    @isTest
    static void testChatHistory_Sorting() {
        Test.startTest();
        
        // Create unordered chat history
        List<AIChatController.ChatHistory> chatList = new List<AIChatController.ChatHistory>();
        
        AIChatController.ChatHistory chat3 = new AIChatController.ChatHistory();
        chat3.sequence = 3;
        chatList.add(chat3);
        
        AIChatController.ChatHistory chat1 = new AIChatController.ChatHistory();
        chat1.sequence = 1;
        chatList.add(chat1);
        
        AIChatController.ChatHistory chat2 = new AIChatController.ChatHistory();
        chat2.sequence = 2;
        chatList.add(chat2);
        
        // Sort the list
        chatList.sort();
        
        Test.stopTest();
        
        // Assertions
        Assert.areEqual(1, chatList[0].sequence, 'First item should have sequence 1');
        Assert.areEqual(2, chatList[1].sequence, 'Second item should have sequence 2');
        Assert.areEqual(3, chatList[2].sequence, 'Third item should have sequence 3');
    }
    
    /**
     * Test error handling in makeCallout
     */
    @isTest
    static void testMakeCallout_ErrorHandling() {
        // Get test data
        AI_Response__c aiResponse = [SELECT Id FROM AI_Response__c LIMIT 1];
        
        // Create test chat
        AIChatController.ChatHistory testChat = AIChatController.createNewChat('Test question that will fail');
        String currentChatJson = JSON.serialize(testChat);
        
        // Setup mock error response
        Test.setMock(HttpCalloutMock.class, new MockAIResponseError());
        
        Test.startTest();
        try {
            AIChatController.makeCallout(aiResponse.Id, currentChatJson);
            Assert.fail('Expected exception to be thrown');
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage().contains('Response Failed'), 'Error message should contain response failure');
        }
        Test.stopTest();
    }
    
    /**
     * Test bulk chat processing scenario
     */
    @isTest
    static void testGetChatHistory_BulkProcessing() {
        // Create multiple AI Response records with chat histories
        AI_Connection__c aiConnection = [SELECT Id FROM AI_Connection__c LIMIT 1];
        AI_Prompt__c aiPrompt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        List<AI_Response__c> aiResponses = new List<AI_Response__c>();
        for (Integer i = 0; i < 5; i++) {
            aiResponses.add(new AI_Response__c(
                AI_Prompt__c = aiPrompt.Id,
                Vector_Store_Id__c = 'vs_bulk_' + i,
                Thread_Id__c = 'thread_bulk_' + i
            ));
        }
        insert aiResponses;
        
        Test.startTest();
        
        // Test multiple chat history retrievals
        List<List<AIChatController.ChatHistory>> allChatHistories = new List<List<AIChatController.ChatHistory>>();
        for (AI_Response__c response : aiResponses) {
            List<AIChatController.ChatHistory> chatHistory = AIChatController.getChatHistory(response.Id);
            allChatHistories.add(chatHistory);
        }
        
        Test.stopTest();
        
        // Assertions
        Assert.areEqual(5, allChatHistories.size(), 'Should have 5 chat history lists');
        for (List<AIChatController.ChatHistory> chatHistory : allChatHistories) {
            Assert.isNull(chatHistory, 'Chat history should be null for records without chat details');
        }
    }
}