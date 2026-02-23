/**
 * AIChatController
 * 
 * This Apex controller manages chat history and AI file processing for the AI Security Audit feature.
 * It provides methods to retrieve, create, and update chat history records, as well as to interact with AI models.
 * 
 * Key Features:
 * - Retrieves and sorts chat history for a given record.
 * - Handles creation and storage of new chat messages.
 * - Manages field size constraints for long text area fields.
 * - Integrates with external AI callout utilities and response handling.
 */
public with sharing class AIChatController {

    /**
     * Retrieves the complete chat history for a given recordId.
     * - Aggregates all chat messages from related AI_Security_Audit_Detail__c records.
     * - Deserializes JSON message data into ChatHistory objects.
     * - Sorts the chat history by sequence for chronological order.
     *
     * @param recordId The parent record Id (AI_Security_Audit__c).
     * @return List of ChatHistory objects, sorted by sequence.
     */
    @AuraEnabled
    public static List<ChatHistory> getChatHistory(String recordId){
        List<ChatHistory> chatHistory = new List<ChatHistory>();
        List<AI_Security_Audit_Detail__c> details = getSecurityAuditDetails(recordId);
        if(details != null && !details.isEmpty()){
            for(AI_Security_Audit_Detail__c detail : details){
                // Deserialize each Message__c JSON into ChatHistory list and aggregate
                chatHistory.addAll((List<ChatHistory>)JSON.deserialize(detail.Message__c,  List<ChatHistory>.class));
            }
            // Sort chat history by sequence
            chatHistory.sort();
            return chatHistory;
        }
        return null;
    }

    /**
     * Helper method to retrieve all AI_Security_Audit_Detail__c records of type 'Chat' for a given parent record.
     * - Orders results by CreatedDate ascending for chronological processing.
     *
     * @param recordId The parent AI_Security_Audit__c Id.
     * @return List of AI_Security_Audit_Detail__c records.
     */
    private static List<AI_Security_Audit_Detail__c> getSecurityAuditDetails(String recordId){
        List<AI_Security_Audit_Detail__c> details = [SELECT Id, Message__c                                                        
                                                        FROM AI_Security_Audit_Detail__c
                                                        WHERE AI_Security_Audit__c =:recordId AND Type__c = 'Chat'
                                                        ORDER BY CreatedDate ASC
                                                        LIMIT 49999];
        return details;
    }

    /**
     * Creates a new ChatHistory object with the provided question.
     * - Initializes the question and timestamp.
     *
     * @param message The user's question.
     * @return A new ChatHistory object with the question set.
     */
    @AuraEnabled
    public static ChatHistory createNewChat(String message){
        return new ChatHistory().addQuestion(message);
    }

    /**
     * Handles the AI callout process and updates chat history accordingly.
     * - Retrieves the latest chat, prepares and sends an AI callout, and parses the response.
     * - Appends the new Q&A to the chat history, ensuring field size constraints are respected.
     * - If the current detail record exceeds the max length, creates a new detail record.
     *
     * @param recordId The AI_Response__c Id for context.
     * @param currentChat The current chat (serialized ChatHistory).
     * @return The updated ChatHistory object with answer and sequence.
     */
    @AuraEnabled
    public static ChatHistory makeCallout(String recordId, String currentChat){
        // Get the max allowed length for the Message__c field
        Integer maxLength = AI_Security_Audit_Detail__c.Message__c.getDescribe().getLength();
        // Deserialize the current chat
        ChatHistory lastChat = (ChatHistory)JSON.deserialize(currentChat, ChatHistory.class);

        // Retrieve related AI response and connection details
        List<AI_Response__c> responses = [SELECT Id, Vector_Store_Id__c, Thread_Id__c, AI_Prompt__r.AI_Model_File_Processing__c,
                                AI_Prompt__r.AI_Connection__c, Data_PII_Removed__c,AI_Prompt__r.Include_Files__c
                                    FROM AI_Response__c 
                                    WHERE Id = :recordId 
                                    LIMIT 1];

        // Determine which connection to use based on Include_Files__c
        String connectionId = responses[0].AI_Prompt__r.Include_Files__c == true ? 
                                responses[0].AI_Prompt__r.AI_Model_File_Processing__c : 
                                responses[0].AI_Prompt__r.AI_Connection__c;

        List<AI_Connection__c> connections = [SELECT Id, Model__c, Named_Credential__c,Max_Tokens__c,Temperature__c,Additional_Parameters__c,Top_p__c
                                                FROM AI_Connection__c
                                                WHERE Id =:connectionId 
                                                LIMIT 1];

        // Prepare the AI callout wrapper
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrap = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        wrap.vectorStoreId = responses[0].Vector_Store_Id__c;
        wrap.aiModel = connections[0];
        wrap.promptCommand = lastChat.question;
        wrap.previousResponseId = responses[0].Thread_Id__c;
        wrap.extractedData = responses[0].Data_PII_Removed__c;
        wrap = AIResponsesApiCalloutUtility.createResponses(wrap);

        // Update the thread ID in the response record
        FLSCheck.getInstance().updateDML(new List<AI_Response__c>{new AI_Response__c(Id = recordId, Thread_Id__c = wrap.previousResponseId)});

        // Retrieve existing chat details for the record
        List<AI_Security_Audit_Detail__c> details = getSecurityAuditDetails(recordId);

        // Parse the AI response
        String parsedResponse = ChatGPTUtills.parseGPTfyResponse(wrap.response);

        // Update the last chat with the answer
        lastChat = lastChat.addQuestion(lastChat.question).addAnswer(parsedResponse);

        AI_Security_Audit_Detail__c detail;
        List<ChatHistory> chatHistories;
        if(!details.isEmpty()){
            detail = details[0];
            // Deserialize existing chat history or initialize new list
            if(detail.Message__c != null && detail.Message__c != ''){
                chatHistories = (List<ChatHistory>) JSON.deserialize(detail.Message__c, List<ChatHistory>.class);
            }else{
                chatHistories = new List<ChatHistory>();
            }
            // Sort and append the new chat with incremented sequence
            chatHistories.sort();
            lastChat = lastChat.addSequence(chatHistories.size() + 1);
            chatHistories.add(lastChat);
            String serializeChats = JSON.serialize(chatHistories);
            // If within field size, update; else, create a new detail record
            if(serializeChats.length() <= maxLength){
                detail.Message__c = serializeChats;
            }else{
                chatHistories = new List<ChatHistory>();
                chatHistories.add(lastChat);
                detail = new AI_Security_Audit_Detail__c(
                            Type__c='Chat', 
                            Message__c = JSON.serialize(chatHistories),
                            AI_Security_Audit__c = recordId
                            );
            }
        }else{
            // No existing details; create new chat history and detail record
            chatHistories = new List<ChatHistory>();
            lastChat = lastChat.addSequence(1);
            chatHistories.add(lastChat);
            detail = new AI_Security_Audit_Detail__c(
                            Type__c='Chat', 
                            Message__c = JSON.serialize(chatHistories),
                            AI_Security_Audit__c = recordId
                            );
        }
        
        // Upsert the detail record with the updated chat history
        FLSCheck.getInstance().upsertDML(new List<AI_Security_Audit_Detail__c>{detail});

        return lastChat;
    }

    /**
     * ChatHistory class represents a single Q&A exchange in the chat.
     * - Implements Comparable for sorting by sequence.
     * - Provides fluent methods to set question, answer, and sequence.
     */
    public class ChatHistory implements Comparable {
        @AuraEnabled public String question;
        @AuraEnabled public String question_timestamp;
        @AuraEnabled public String answer;
        @AuraEnabled public String answer_timestamp;
        @AuraEnabled public Integer sequence;
    
        /**
         * Sets the question and timestamp.
         * @param question The user's question.
         * @return The updated ChatHistory instance.
         */
        public ChatHistory addQuestion(String question) {
            this.question = question; 
            this.question_timestamp = System.now().format('h:mm a');
            return this;
        }

        /**
         * Sets the answer and timestamp.
         * @param answer The AI's answer.
         * @return The updated ChatHistory instance.
         */
        public ChatHistory addAnswer(String answer) {
            this.answer = answer; 
            this.answer_timestamp = System.now().format('h:mm a');
            return this;
        }

        /**
         * Sets the sequence number for ordering.
         * @param sequence The sequence number.
         * @return The updated ChatHistory instance.
         */
        public ChatHistory addSequence(Integer sequence) {
            this.sequence = sequence;
            return this;
        }
    
        /**
         * Compares this ChatHistory to another by sequence for sorting.
         * Handles nulls safely.
         * @param obj The other ChatHistory object.
         * @return Integer comparison result.
         */
        public Integer compareTo(Object obj) {
            ChatHistory other = (ChatHistory)obj;
            if (this.sequence == null && other.sequence == null) return 0;
            if (this.sequence == null) return -1;
            if (other.sequence == null) return 1;
            return this.sequence - other.sequence;
        }
    }
}