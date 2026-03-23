global with sharing class AIGlobalUtility {

    global static AI_Response__c getExtractedData(Id recordId, String promptId){
        AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
        AI_Response__c response = new AI_Response__c();
        response.Start_Date_Time__c = System.Now();
        response = ChatGPTUtills.getExtractedData(recordId, aiPrompt, null, response);
        return response;
    }
    /**
     * @description: Deletes expired vector stores from OpenAI and updates corresponding AI_Response__c records.
     *               This method is called by the batch job (AIDeleteExpiredVectorStoresBatch) to clean up
     *               vector stores that are no longer needed. It retrieves agent configurations to get Named
     *               Credentials, makes DELETE API calls to OpenAI for each vector store, and updates the
     *               AI_Response__c records to mark them as processed with cleared vector store IDs.
     *               Individual deletion failures are caught to prevent batch termination.
     * @param aiResponses List of AI_Response__c records with vector stores to be deleted
     * @return List<AI_Response__c> Updated list of AI_Response__c records (successfully deleted ones are updated)
     * @jira: V2-7341
     */
    global static List<AI_Response__c> deleteExpiredVectorStores(List<AI_Response__c> aiResponses){
        List<AI_Response__c> recordsToUpdate = new List<AI_Response__c>();
        Set<String> agentNames = new Set<String>();
        Map<String, AI_Agent__c> agentMap = new Map<String, AI_Agent__c>(); 

        for(AI_Response__c aiResp : aiResponses) {
            if(String.isNotBlank(aiResp.Agent_Name__c)) {
                agentNames.add(aiResp.Agent_Name__c);
            }
        }

        if(agentNames.isEmpty()) {
            return aiResponses; // No agent names found, nothing to process
        }   
        List<AI_Agent__c> agents = [    
            SELECT Developer_Name__c, AI_Model__r.Named_Credential__c, Name
            FROM AI_Agent__c 
            WHERE Name IN :agentNames 
            WITH SECURITY_ENFORCED
            LIMIT 100
        ];

        for(AI_Agent__c agent : agents) {
            agentMap.put(agent.Name, agent);
        }
      
        for (AI_Response__c aiResponse : aiResponses) {
            try {
                String vectorStoreId = aiResponse.Vector_Store_Id__c;
                AIAgenticChatAPIService.deleteVectorStore(agentMap.get(aiResponse.Agent_Name__c).AI_Model__r.Named_Credential__c,vectorStoreId);

                recordsToUpdate.add(new AI_Response__c(
                    Id = aiResponse.Id,
                    Vector_Store_Id__c = null,
                    Session_Expired__c = true,
                    Status__c = AIConstants.RESP_STATUS_PROCESSED
                ));
            } catch (Exception e) {
                // do not update the record if deletion fails
            }
        }
        
        if (!recordsToUpdate.isEmpty()) {   
            return (List<AI_Response__c>) FLSCheck.getInstance().upsertDML(recordsToUpdate);
        }
        return aiResponses;
    }

    /**
     * @description: Encrypts a plain text string using a specific user's context.
     *               This method provides a secure way to encrypt sensitive data without exposing
     *               the encryption key or salt. The encryption is user-specific, meaning only the
     *               same user (with the same User ID) can decrypt the data.
     * 
     * Encryption Details:
     * - Algorithm: AES256 with Managed IV
     * - Key: Generated using SHA256(OrgId + UserId + CustomSalt)
     * - Output: Base64-encoded encrypted string
     * 
     * IMPORTANT: You must provide the User ID that will be used for both encryption and decryption.
     *            The same User ID must be used to decrypt the data later.
     * 
     * @param plainText The plain text string to encrypt
     * @param userId The Salesforce User ID to use for encryption key generation (REQUIRED)
     * @return Base64-encoded encrypted string, or null if input is blank
     * @throws AIWorkspaceEncryptionService.EncryptionException if encryption fails
     * @jira V2-7889
     * 
     * @example
     * Id userId = '005XXXXXXXXXXXXXX';
     * String encrypted = AIGlobalUtility.encryptData('Sensitive Information', userId);
     * System.debug('Encrypted: ' + encrypted);
     */
    global static String encryptData(String plainText, Id userId) {
        return AIWorkspaceEncryptionService.encrypt(plainText, userId);
    }

    /**
     * @description: Decrypts an encrypted string using a specific user's context.
     *               This method can only decrypt data that was encrypted using the same User ID.
     *               The decryption key is generated using the provided User ID.
     * 
     * IMPORTANT: You must provide the SAME User ID that was used during encryption.
     *            Using a different User ID will result in decryption failure.
     * 
     * @param encryptedText The Base64-encoded encrypted string
     * @param userId The Salesforce User ID to use for decryption key generation (REQUIRED)
     * @return Decrypted plain text string, or null if input is blank
     * @throws AIWorkspaceEncryptionService.EncryptionException if decryption fails
     * @jira V2-7889
     * 
     * @example
     * Id userId = '005XXXXXXXXXXXXXX';
     * String decrypted = AIGlobalUtility.decryptData(encryptedString, userId);
     * System.debug('Decrypted: ' + decrypted);
     */
    global static String decryptData(String encryptedText, Id userId) {
        return AIWorkspaceEncryptionService.decrypt(encryptedText, userId);
    }
}