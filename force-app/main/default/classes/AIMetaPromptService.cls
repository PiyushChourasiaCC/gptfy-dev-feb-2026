/**
 * @description Orchestrates meta-prompt LLM calls for AI Prompt Factory golden prompt generation.
 * Loads meta-prompt from AI_GPTfy_Warehouse__c and calls ChatGPTUtills for LLM processing
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 03-02-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
public with sharing class AIMetaPromptService {

    private static final String LOG_PREFIX = '[AIMetaPromptService]';

    /**
     * @description Load the active meta-prompt from GPTfy Warehouse.
     * @return The meta-prompt text from Value__c field
     */
    public static String loadMetaPrompt() {
        List<AI_GPTfy_Warehouse__c> records = [
            SELECT Value__c
            FROM AI_GPTfy_Warehouse__c
            WHERE Type__c = 'Prompt Factory'
            AND Sub_Type__c = 'Meta Prompt'
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (records.isEmpty() || String.isBlank(records[0].Value__c)) {
            throw new AIMetaPromptServiceException(
                'No Meta Prompt found in GPTfy Warehouse. ' +
                'Create a record with Type__c = "Prompt Factory" and Sub_Type__c = "Meta Prompt".'
            );
        }

        return records[0].Value__c;
    }

    /**
     * @description Load the company context from GPTfy Warehouse.
     * Returns null if no company context is configured.
     * @return The company context markdown, or null
     */
    public static String loadCompanyContext() {
        List<AI_GPTfy_Warehouse__c> records = [
            SELECT Value__c
            FROM AI_GPTfy_Warehouse__c
            WHERE Type__c = 'Prompt Factory'
            AND Sub_Type__c = 'Company Context'
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (records.isEmpty() || String.isBlank(records[0].Value__c)) {
            return null;
        }

        return records[0].Value__c;
    }

    /**
     * @description Assemble the full meta-prompt with optional company context injected.
     * @param metaPrompt The raw meta-prompt text
     * @param contextPackage The object-specific context package
     * @return The combined user prompt with company context (if available)
     */
    private static String assembleMetaPrompt(String metaPrompt, String contextPackage) {
        String companyContext = loadCompanyContext();

        if (String.isBlank(companyContext)) {
            return contextPackage;
        }

        // Inject company context between meta-prompt instructions and object-specific context
        return '## COMPANY PROFILE\n\n' + companyContext + '\n\n---\n\n' + contextPackage;
    }

    /**
     * @description Generate a golden prompt by calling the LLM with meta-prompt + context.
     * Uses ChatGPTUtills.processRequest for the LLM callout.
     * @param contextPackage The assembled context markdown (from AIContextAssembler)
     * @param connectionId AI Connection ID for the generation LLM
     * @return The generated golden prompt text
     */
    public static String generateGoldenPrompt(String contextPackage, Id connectionId) {
        if (String.isBlank(contextPackage)) {
            throw new AIMetaPromptServiceException('Context package cannot be empty.');
        }

        if (connectionId == null) {
            throw new AIMetaPromptServiceException('AI Connection ID is required.');
        }

        // Load meta-prompt
        String metaPrompt = loadMetaPrompt();

        // Assemble with company context
        String fullContext = assembleMetaPrompt(metaPrompt, contextPackage);

        // Query AI Connection with all required fields
        List<AI_Connection__c> connections = [
            SELECT Id, Name, AI_Technology__c, Model__c, EndPoint_URL__c,
                   Named_Credential__c, Temperature__c, Max_Tokens__c, Top_P__c,
                   Max_Total_Tokens__c, Processing_Class__c, Connector_Class__c,
                   Additional_Parameters__c, Version__c, Type__c
            FROM AI_Connection__c
            WHERE Id = :connectionId
            WITH USER_MODE
            LIMIT 1
        ];

        if (connections.isEmpty()) {
            throw new AIMetaPromptServiceException('AI Connection not found: ' + connectionId);
        }

        AI_Connection__c connection = connections[0];

        // Create a temporary AI_Prompt__c object for the callout
        // This is needed by AIGPTfyCalloutController.processRequest
        AI_Prompt__c tempPrompt = new AI_Prompt__c();
        tempPrompt.Prompt_Command__c = metaPrompt;
        tempPrompt.AI_Connection__c = connection.Id;
        tempPrompt.AI_Connection__r = connection;
        tempPrompt.Max_Output_Tokens__c = 16000;
        tempPrompt.Temperature__c = 0.7;
        tempPrompt.Type__c = AIConstants.AI_MODEL_TYPE_CHAT;

        System.debug(LOG_PREFIX + ' Calling LLM with meta-prompt (' + metaPrompt.length() +
                     ' chars) and context (' + fullContext.length() + ' chars)');

        // Make the LLM callout
        String response = AIGPTfyCalloutController.processRequest(
            metaPrompt,
            fullContext,
            tempPrompt
        );

        if (String.isBlank(response)) {
            throw new AIMetaPromptServiceException('LLM returned empty response.');
        }

        // Check for errors in response
        String errorMessage = ChatGPTUtills.getErrorMessage(response);
        if (String.isNotBlank(errorMessage)) {
            throw new AIMetaPromptServiceException('LLM call failed: ' + errorMessage);
        }

        // Parse the response based on AI technology
        String parsedResponse;
        if (connection.AI_Technology__c == AIConstants.PRODUCT_NAME) {
            parsedResponse = ChatGPTUtills.parseGPTfyResponse(response);
        } else if (connection.AI_Technology__c == 'OpenAI_ChatGPT') {
            parsedResponse = ChatGPTUtills.parseChatGptResponse(response, connection.Model__c);
        } else {
            parsedResponse = ChatGPTUtills.parseOtherResponse(response);
        }

        if (String.isBlank(parsedResponse)) {
            throw new AIMetaPromptServiceException('Failed to parse LLM response.');
        }

        System.debug(LOG_PREFIX + ' Generated golden prompt: ' + parsedResponse.length() + ' chars');

        return parsedResponse;
    }

    /**
     * @description Refine an existing golden prompt based on user instructions.
     * @param currentPrompt The current golden prompt text
     * @param refinementInstruction User's refinement instruction
     * @param connectionId AI Connection ID for the refinement LLM
     * @return The refined golden prompt text
     */
    public static String refineGoldenPrompt(String currentPrompt, String refinementInstruction, Id connectionId) {
        if (String.isBlank(currentPrompt)) {
            throw new AIMetaPromptServiceException('Current prompt cannot be empty for refinement.');
        }
        
        if (String.isBlank(refinementInstruction)) {
            throw new AIMetaPromptServiceException('Refinement instruction cannot be empty.');
        }
        
        if (connectionId == null) {
            throw new AIMetaPromptServiceException('AI Connection ID is required.');
        }
        
        // Query AI Connection with all required fields
        List<AI_Connection__c> connections = [
            SELECT Id, Name, AI_Technology__c, Model__c, EndPoint_URL__c,
                   Named_Credential__c, Temperature__c, Max_Tokens__c, Top_P__c,
                   Max_Total_Tokens__c, Processing_Class__c, Connector_Class__c,
                   Additional_Parameters__c, Version__c, Type__c
            FROM AI_Connection__c
            WHERE Id = :connectionId
            WITH USER_MODE
            LIMIT 1
        ];
        
        if (connections.isEmpty()) {
            throw new AIMetaPromptServiceException('AI Connection not found: ' + connectionId);
        }
        
        AI_Connection__c connection = connections[0];
        
        // Build refinement system prompt
        String systemPrompt = 'You are an expert prompt engineer. ' +
            'The user has a golden prompt (a detailed instruction set for an LLM). ' +
            'Apply the user\'s refinement instruction to the prompt. ' +
            'Return ONLY the complete modified prompt — no commentary, no explanation. ' +
            'Preserve all existing rules and structure unless the instruction specifically asks to change them.';
        
        // Build user prompt with current prompt and refinement instruction
        String userPrompt = '## CURRENT GOLDEN PROMPT\n\n' + currentPrompt +
            '\n\n---\n\n## REFINEMENT INSTRUCTION\n\n' + refinementInstruction +
            '\n\n---\n\nReturn the complete modified prompt:';
        
        // Create a temporary AI_Prompt__c object for the callout
        AI_Prompt__c tempPrompt = new AI_Prompt__c();
        tempPrompt.Prompt_Command__c = systemPrompt;
        tempPrompt.AI_Connection__c = connection.Id;
        tempPrompt.AI_Connection__r = connection;
        tempPrompt.Max_Output_Tokens__c = 16000;
        tempPrompt.Temperature__c = 0.7;
        tempPrompt.Type__c = AIConstants.AI_MODEL_TYPE_CHAT;
        
        System.debug(LOG_PREFIX + ' Refining prompt with instruction: ' + refinementInstruction);
        
        // Make the LLM callout
        String response = AIGPTfyCalloutController.processRequest(
            systemPrompt,
            userPrompt,
            tempPrompt
        );
        
        if (String.isBlank(response)) {
            throw new AIMetaPromptServiceException('LLM returned empty response.');
        }
        
        // Check for errors in response
        String errorMessage = ChatGPTUtills.getErrorMessage(response);
        if (String.isNotBlank(errorMessage)) {
            throw new AIMetaPromptServiceException('LLM call failed: ' + errorMessage);
        }
        
        // Parse the response based on AI technology
        String parsedResponse;
        if (connection.AI_Technology__c == AIConstants.PRODUCT_NAME) {
            parsedResponse = ChatGPTUtills.parseGPTfyResponse(response);
        } else if (connection.AI_Technology__c == 'OpenAI_ChatGPT') {
            parsedResponse = ChatGPTUtills.parseChatGptResponse(response, connection.Model__c);
        } else {
            parsedResponse = ChatGPTUtills.parseOtherResponse(response);
        }
        
        if (String.isBlank(parsedResponse)) {
            throw new AIMetaPromptServiceException('Failed to parse LLM response.');
        }
        
        System.debug(LOG_PREFIX + ' Refined prompt: ' + parsedResponse.length() + ' chars');
        
        return parsedResponse;
    }

    /**
     * @description Custom exception for meta-prompt service errors.
     */
    public class AIMetaPromptServiceException extends Exception {}
}
