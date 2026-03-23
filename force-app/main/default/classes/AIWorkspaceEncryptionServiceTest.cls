/**
 * Test class for AIWorkspaceEncryptionService
 * 
 * Tests encryption and decryption of email bodies using AES256 with Managed IV.
 * Ensures data security and proper handling of edge cases.
 * 
 * @author GPTfy
 * @date 2026-03-09
 * @Jira V2-7889
 */
@isTest
private class AIWorkspaceEncryptionServiceTest {
    
    @isTest
    static void testEncryptEmailBody_Success() {
        Id userId = UserInfo.getUserId();
        String plainText = 'This is a test email body with sensitive information.';
        
        Test.startTest();
        String encrypted = AIWorkspaceEncryptionService.encryptEmailBody(plainText, userId);
        Test.stopTest();
        
        Assert.isNotNull(encrypted, 'Encrypted body should not be null');
        Assert.areNotEqual(plainText, encrypted, 'Encrypted body should be different from plain text');
        Assert.isTrue(encrypted.length() > 0, 'Encrypted body should have content');
    }
    
    @isTest
    static void testDecryptEmailBody_Success() {
        Id userId = UserInfo.getUserId();
        String plainText = 'This is a test email body with sensitive information.';
        
        Test.startTest();
        String encrypted = AIWorkspaceEncryptionService.encryptEmailBody(plainText, userId);
        String decrypted = AIWorkspaceEncryptionService.decryptEmailBody(encrypted, userId);
        Test.stopTest();
        
        Assert.areEqual(plainText, decrypted, 'Decrypted body should match original plain text');
    }
    
    @isTest
    static void testEncryptDecrypt_LargeContent() {
        Id userId = UserInfo.getUserId();
        String largeText = '';
        for (Integer i = 0; i < 1000; i++) {
            largeText += 'This is line ' + i + ' of a large email body with lots of content. ';
        }
        
        Test.startTest();
        String encrypted = AIWorkspaceEncryptionService.encryptEmailBody(largeText, userId);
        String decrypted = AIWorkspaceEncryptionService.decryptEmailBody(encrypted, userId);
        Test.stopTest();
        
        Assert.areEqual(largeText, decrypted, 'Large content should decrypt correctly');
    }
    
    @isTest
    static void testEncryptEmailBody_NullInput() {
        Id userId = UserInfo.getUserId();
        
        Test.startTest();
        String encrypted = AIWorkspaceEncryptionService.encryptEmailBody(null, userId);
        Test.stopTest();
        
        Assert.isNull(encrypted, 'Encrypting null should return null');
    }
    
    @isTest
    static void testEncryptEmailBody_BlankInput() {
        Id userId = UserInfo.getUserId();
        
        Test.startTest();
        String encrypted = AIWorkspaceEncryptionService.encryptEmailBody('', userId);
        Test.stopTest();
        
        Assert.isNull(encrypted, 'Encrypting blank string should return null');
    }
    
    @isTest
    static void testDecryptEmailBody_NullInput() {
        Id userId = UserInfo.getUserId();
        
        Test.startTest();
        String decrypted = AIWorkspaceEncryptionService.decryptEmailBody(null, userId);
        Test.stopTest();
        
        Assert.isNull(decrypted, 'Decrypting null should return null');
    }
    
    @isTest
    static void testDecryptEmailBody_BlankInput() {
        Id userId = UserInfo.getUserId();
        
        Test.startTest();
        String decrypted = AIWorkspaceEncryptionService.decryptEmailBody('', userId);
        Test.stopTest();
        
        Assert.isNull(decrypted, 'Decrypting blank string should return null');
    }
    
    @isTest
    static void testEncryptEmailBodies_Bulk() {
        Id userId = UserInfo.getUserId();
        List<String> bodies = new List<String>{
            'First email body',
            'Second email body',
            null,
            'Fourth email body'
        };
        
        Test.startTest();
        Map<Integer, String> encrypted = AIWorkspaceEncryptionService.encryptEmailBodies(bodies, userId);
        Test.stopTest();
        
        Assert.areEqual(4, encrypted.size(), 'Should return 4 encrypted bodies');
        Assert.isNotNull(encrypted.get(0), 'First body should be encrypted');
        Assert.isNotNull(encrypted.get(1), 'Second body should be encrypted');
        Assert.isNull(encrypted.get(2), 'Null body should remain null');
        Assert.isNotNull(encrypted.get(3), 'Fourth body should be encrypted');
    }
    
    @isTest
    static void testDecryptEmailBodies_Bulk() {
        Id userId = UserInfo.getUserId();
        List<String> bodies = new List<String>{
            'First email body',
            'Second email body',
            'Third email body'
        };
        
        Test.startTest();
        Map<Integer, String> encrypted = AIWorkspaceEncryptionService.encryptEmailBodies(bodies, userId);
        Map<Integer, String> decrypted = AIWorkspaceEncryptionService.decryptEmailBodies(
            new List<String>{encrypted.get(0), encrypted.get(1), encrypted.get(2)},
            userId
        );
        Test.stopTest();
        
        Assert.areEqual(bodies[0], decrypted.get(0), 'First body should decrypt correctly');
        Assert.areEqual(bodies[1], decrypted.get(1), 'Second body should decrypt correctly');
        Assert.areEqual(bodies[2], decrypted.get(2), 'Third body should decrypt correctly');
    }
    
    @isTest
    static void testEncryptionIsUserSpecific() {
        Id userId1 = UserInfo.getUserId();
        User testUser = [SELECT Id FROM User WHERE Id != :userId1 AND IsActive = true LIMIT 1];
        Id userId2 = testUser.Id;
        
        String plainText = 'User-specific encryption test';
        
        Test.startTest();
        String encrypted1 = AIWorkspaceEncryptionService.encryptEmailBody(plainText, userId1);
        String encrypted2 = AIWorkspaceEncryptionService.encryptEmailBody(plainText, userId2);
        Test.stopTest();
        
        Assert.areNotEqual(encrypted1, encrypted2, 'Same text encrypted with different user IDs should produce different ciphertext');
    }
    
    @isTest
    static void testEncryptEmailBody_HtmlContent() {
        Id userId = UserInfo.getUserId();
        String htmlContent = '<html><body><h1>Test Email</h1><p>This is a <strong>test</strong> email.</p></body></html>';
        
        Test.startTest();
        String encrypted = AIWorkspaceEncryptionService.encryptEmailBody(htmlContent, userId);
        String decrypted = AIWorkspaceEncryptionService.decryptEmailBody(encrypted, userId);
        Test.stopTest();
        
        Assert.areEqual(htmlContent, decrypted, 'HTML content should decrypt correctly');
    }
    
    @isTest
    static void testEncryptEmailBody_SpecialCharacters() {
        Id userId = UserInfo.getUserId();
        String specialText = 'Test with special chars: !@#$%^&*()_+-=[]{}|;:\'",.<>?/~`';
        
        Test.startTest();
        String encrypted = AIWorkspaceEncryptionService.encryptEmailBody(specialText, userId);
        String decrypted = AIWorkspaceEncryptionService.decryptEmailBody(encrypted, userId);
        Test.stopTest();
        
        Assert.areEqual(specialText, decrypted, 'Special characters should decrypt correctly');
    }
    
    @isTest
    static void testBulkEncrypt_EmptyList() {
        Id userId = UserInfo.getUserId();
        
        Test.startTest();
        Map<Integer, String> encrypted = AIWorkspaceEncryptionService.encryptEmailBodies(new List<String>(), userId);
        Test.stopTest();
        
        Assert.isTrue(encrypted.isEmpty(), 'Empty list should return empty map');
    }
    
    @isTest
    static void testBulkEncrypt_NullList() {
        Id userId = UserInfo.getUserId();
        
        Test.startTest();
        Map<Integer, String> encrypted = AIWorkspaceEncryptionService.encryptEmailBodies(null, userId);
        Test.stopTest();
        
        Assert.isTrue(encrypted.isEmpty(), 'Null list should return empty map');
    }
}
