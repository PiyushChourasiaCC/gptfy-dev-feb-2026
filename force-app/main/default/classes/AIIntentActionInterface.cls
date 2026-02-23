/**
 * @description Interface for custom Apex logic execution when an AI Intent Action is triggered.
 *              Implement this interface to handle custom operations based on AI responses.
 *              The implementing class must be specified in the Apex_Class_Name__c field
 *              of the AI_Intent_Action__c record with Action_Type__c = 'Apex'.
 *
 * @author            : Sagar Alwani
 * @group             : GPTfy
 * @last modified on  : 19-02-2026
 * @last modified by  : Sagar Alwani
 **/
global interface AIIntentActionInterface {
    
    /**
     * Execute custom Apex logic for an intent action.
     *
     * @param request Map containing:
     *                - agentId (Id): The AI_Agent__c Id that triggered this action
     *                - responseBody (String): Full AI response JSON from OpenAI Responses API
     *                - intentParams (Map<String, Object>): Extracted parameters for this intent
     *                - relatedToId (String): Primary record ID the conversation relates to
     *                - recordId (String): Alternative record identifier
     *
     * @return Map<String, Object> containing:
     *                - success (Boolean): Whether the action succeeded
     *                - message (String): Optional message to return to user
     *                - errorMessage (String): Error details if failed
     *
     * @example
     * public class MyIntentHandler implements AIIntentActionInterface {
     *     public Map<String, Object> invokeApex(Map<String, Object> request) {
     *         Id agentId = (Id) request.get('agentId');
     *         String responseBody = (String) request.get('responseBody');
     *         Map<String, Object> intentParams = (Map<String, Object>) request.get('intentParams');
     *         String relatedToId = (String) request.get('relatedToId');
     *         
     *         // Your custom logic here
     *         
     *         return new Map<String, Object>{
     *             'success' => true,
     *             'message' => 'Operation completed!'
     *         };
     *     }
     * }
     */
    Map<String, Object> invokeApex(Map<String, Object> request);
}