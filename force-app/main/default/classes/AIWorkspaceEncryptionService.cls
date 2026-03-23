/**
 * AIWorkspaceEncryptionService - Centralized encryption/decryption service for email bodies
 * 
 * This service provides encryption and decryption for sensitive email body content
 * stored in AI_Workspace_Staging__c records. Uses the same encryption approach
 * as AIWorkspaceTokenService for consistency.
 * 
 * Encryption Details:
 * - Algorithm: AES256 with Managed IV
 * - Key Generation: SHA256(OrgId + UserId + CustomSalt)
 * - Encoding: Base64 for storage in text fields
 * 
 * @author GPTfy
 * @date 2026-03-09
 * @Jira V2-7889
 */
public with sharing class AIWorkspaceEncryptionService {
    
    private static final String CUSTOM_SALT = 'Kx9#mP2vL8qGPTfy';
    private static final String ALGORITHM = 'AES256';
    
    /**
     * Generate encryption key unique to a specific user and org
     * Key = SHA256(OrgId + UserId + CustomSalt)
     */
    private static Blob getEncryptionKey(Id userId) {
        String keySource = UserInfo.getOrganizationId() + userId + CUSTOM_SALT;
        return Crypto.generateDigest('SHA-256', Blob.valueOf(keySource));
    }
    
    /**
     * Encrypt email body content using user/org-specific key
     * 
     * @param emailBody The plain text or HTML email body to encrypt
     * @param userId The user ID for key generation
     * @return Base64-encoded encrypted string, or null if input is blank
     */
    public static String encryptEmailBody(String emailBody, Id userId) {
        if (String.isBlank(emailBody)) {
            return null;
        }
        
        try {
            Blob encryptionKey = getEncryptionKey(userId);
            Blob dataToEncrypt = Blob.valueOf(emailBody);
            Blob encryptedData = Crypto.encryptWithManagedIV(ALGORITHM, encryptionKey, dataToEncrypt);
            return EncodingUtil.base64Encode(encryptedData);
        } catch (Exception e) {
            throw new EncryptionException('Failed to encrypt email body: ' + e.getMessage());
        }
    }
    
    /**
     * Decrypt email body content using user/org-specific key
     * 
     * @param encryptedBody The Base64-encoded encrypted email body
     * @param userId The user ID for key generation
     * @return Decrypted email body, or null if input is blank
     */
    public static String decryptEmailBody(String encryptedBody, Id userId) {
        if (String.isBlank(encryptedBody)) {
            return null;
        }
        
        try {
            Blob encryptionKey = getEncryptionKey(userId);
            Blob encryptedData = EncodingUtil.base64Decode(encryptedBody);
            Blob decryptedData = Crypto.decryptWithManagedIV(ALGORITHM, encryptionKey, encryptedData);
            return decryptedData.toString();
        } catch (Exception e) {
            throw new EncryptionException('Failed to decrypt email body: ' + e.getMessage());
        }
    }
    
    /**
     * Bulk encrypt email bodies for batch processing
     * 
     * @param emailBodies List of email bodies to encrypt
     * @param userId The user ID for key generation
     * @return Map of index to encrypted body (index matches input list)
     */
    public static Map<Integer, String> encryptEmailBodies(List<String> emailBodies, Id userId) {
        Map<Integer, String> encryptedBodies = new Map<Integer, String>();
        
        if (emailBodies == null || emailBodies.isEmpty()) {
            return encryptedBodies;
        }
        
        Blob encryptionKey = getEncryptionKey(userId);
        
        for (Integer i = 0; i < emailBodies.size(); i++) {
            String emailBody = emailBodies[i];
            
            if (String.isBlank(emailBody)) {
                encryptedBodies.put(i, null);
                continue;
            }
            
            try {
                Blob dataToEncrypt = Blob.valueOf(emailBody);
                Blob encryptedData = Crypto.encryptWithManagedIV(ALGORITHM, encryptionKey, dataToEncrypt);
                encryptedBodies.put(i, EncodingUtil.base64Encode(encryptedData));
            } catch (Exception e) {
                throw new EncryptionException('Failed to encrypt email body at index ' + i + ': ' + e.getMessage());
            }
        }
        
        return encryptedBodies;
    }
    
    /**
     * Bulk decrypt email bodies for batch processing
     * 
     * @param encryptedBodies List of encrypted email bodies
     * @param userId The user ID for key generation
     * @return Map of index to decrypted body (index matches input list)
     */
    public static Map<Integer, String> decryptEmailBodies(List<String> encryptedBodies, Id userId) {
        Map<Integer, String> decryptedBodies = new Map<Integer, String>();
        
        if (encryptedBodies == null || encryptedBodies.isEmpty()) {
            return decryptedBodies;
        }
        
        Blob encryptionKey = getEncryptionKey(userId);
        
        for (Integer i = 0; i < encryptedBodies.size(); i++) {
            String encryptedBody = encryptedBodies[i];
            
            if (String.isBlank(encryptedBody)) {
                decryptedBodies.put(i, null);
                continue;
            }
            
            try {
                Blob encryptedData = EncodingUtil.base64Decode(encryptedBody);
                Blob decryptedData = Crypto.decryptWithManagedIV(ALGORITHM, encryptionKey, encryptedData);
                decryptedBodies.put(i, decryptedData.toString());
            } catch (Exception e) {
                throw new EncryptionException('Failed to decrypt email body at index ' + i + ': ' + e.getMessage());
            }
        }
        
        return decryptedBodies;
    }
    
    /**
     * Generic encrypt method - encrypts any string using specified user's context
     * V2-7889: Generic method for encrypting any string data
     * 
     * IMPORTANT: The same userId must be provided during decryption
     * 
     * @param plainText The plain text string to encrypt
     * @param userId The user ID for key generation (REQUIRED)
     * @return Base64-encoded encrypted string, or null if input is blank
     */
    public static String encrypt(String plainText, Id userId) {
        if (String.isBlank(plainText)) {
            return null;
        }
        
        try {
            Blob encryptionKey = getEncryptionKey(userId);
            Blob dataToEncrypt = Blob.valueOf(plainText);
            Blob encryptedData = Crypto.encryptWithManagedIV(ALGORITHM, encryptionKey, dataToEncrypt);
            return EncodingUtil.base64Encode(encryptedData);
        } catch (Exception e) {
            throw new EncryptionException('Failed to encrypt data: ' + e.getMessage());
        }
    }
    
    /**
     * Generic decrypt method - decrypts any string using specified user's context
     * V2-7889: Generic method for decrypting any string data
     * 
     * IMPORTANT: Must use the SAME userId that was used during encryption
     * 
     * @param encryptedText The Base64-encoded encrypted string
     * @param userId The user ID for key generation (REQUIRED - must match encryption userId)
     * @return Decrypted plain text string, or null if input is blank
     */
    public static String decrypt(String encryptedText, Id userId) {
        if (String.isBlank(encryptedText)) {
            return null;
        }
        
        try {
            Blob encryptionKey = getEncryptionKey(userId);
            Blob encryptedData = EncodingUtil.base64Decode(encryptedText);
            Blob decryptedData = Crypto.decryptWithManagedIV(ALGORITHM, encryptionKey, encryptedData);
            return decryptedData.toString();
        } catch (Exception e) {
            throw new EncryptionException('Failed to decrypt data: ' + e.getMessage());
        }
    }
    
    public class EncryptionException extends Exception {}
}
