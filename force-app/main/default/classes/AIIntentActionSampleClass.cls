/**
 * @description Sample implementation of AIIntentActionInterface.
 *
 * @author            : Sagar Alwani
 * @group             : GPTfy
 * @last modified on  : 19-02-2026
 * @last modified by  : Sagar Alwani
 **/
public with sharing class AIIntentActionSampleClass implements AIIntentActionInterface {
    
    public Map<String, Object> invokeApex(Map<String, Object> request) {
        try {
            // Extract request values
            Id agentId = (Id) request.get('agentId');
            String responseBody = (String) request.get('responseBody');
            Map<String, Object> intentParams = (Map<String, Object>) request.get('intentParams');
            String relatedToId = (String) request.get('relatedToId');
            String recordId = (String) request.get('recordId');
            
            // Your custom logic here
            
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Operation completed successfully!'
            };
            
        } catch (Exception ex) {
            return new Map<String, Object>{
                'success' => false,
                'errorMessage' => ex.getMessage()
            };
        }
    }
}