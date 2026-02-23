/**
 * @description       : Test class for VoiceProcessingWrapper and AIVoiceProcessingInterface
 * @author            : Sohit Sharma
 * @group             : Plumcloud Labs
 * @last modified on  : 28-11-2024
 * @last modified by  : Sohit Sharma
 * @Jira              : v2/7290 : GPTfy Voice Enhancements
**/
@isTest
public class VoiceProcessingWrapperTest {
    
    // Mock implementation of AIVoiceProcessingInterface for testing
    public class MockVoiceProcessor implements AIVoiceProcessingInterface {
        public HttpResponse getProcessedResponse(VoiceProcessingWrapper voiceWrap) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            
            // Validate wrapper has required data
            if (voiceWrap != null && voiceWrap.aiModel != null) {
                Map<String, Object> responseBody = new Map<String, Object>{
                    'success' => true,
                    'message' => 'Voice processed successfully',
                    'modelName' => voiceWrap.aiModel.Name,
                    'isIOS' => voiceWrap.isIOS
                };
                response.setBody(JSON.serialize(responseBody));
            } else {
                response.setStatusCode(400);
                response.setStatus('Bad Request');
                response.setBody('{"error": "Invalid request"}');
            }
            
            return response;
        }
    }
    
    // Mock implementation that throws exception
    public class MockVoiceProcessorWithError implements AIVoiceProcessingInterface {
        public HttpResponse getProcessedResponse(VoiceProcessingWrapper voiceWrap) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setStatus('Internal Server Error');
            response.setBody('{"error": "Processing failed"}');
            return response;
        }
    }
    
    @TestSetup
    static void setupTestData() {
        // Create AI Connection for testing
        AI_Connection__c aiConnection = TestUtility.getConnection('AnyAI_AnyPlatform', false);
        aiConnection.Name = 'Voice AI Model';
        aiConnection.Type__c = 'Voice';
        aiConnection.Model__c = 'whisper-1';
        aiConnection.Named_Credential__c = 'VoiceAPI';
        aiConnection.EndPoint_URL__c = '/v1/audio/transcriptions';
        insert aiConnection;
        
        // Create test ContentVersion (audio file)
        ContentVersion cv = new ContentVersion(
            Title = 'Test Audio File',
            PathOnClient = 'test_audio.mp3',
            VersionData = Blob.valueOf('Test audio content'),
            IsMajorVersion = true
        );
        insert cv;
    }
    
    // ==================== Test VoiceProcessingWrapper Constructor ====================
    
    
    
    @isTest
    static void testWrapperWithCompleteHttpRequest() {
        AI_Connection__c aiModel = [SELECT Id, Name FROM AI_Connection__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title FROM ContentVersion LIMIT 1];
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:VoiceAPI/v1/audio/transcriptions');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'multipart/form-data');
        request.setHeader('Authorization', 'Bearer test_token');
        request.setTimeout(120000);
        
        Test.startTest();
        VoiceProcessingWrapper wrapper = new VoiceProcessingWrapper(request, aiModel, cv, true);
        Test.stopTest();
        
        Assert.isNotNull(wrapper.request, 'Request should not be null');
        Assert.areEqual('callout:VoiceAPI/v1/audio/transcriptions', wrapper.request.getEndpoint(), 'Endpoint should match');
        Assert.areEqual('POST', wrapper.request.getMethod(), 'Method should be POST');
    }
    
    
    
}