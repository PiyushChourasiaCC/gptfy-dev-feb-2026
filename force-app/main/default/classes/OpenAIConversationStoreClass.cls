/**
 * @description Simple storage mechanism for OpenAI conversations
 * Keeps track of function calls and responses to maintain conversation state
 * 
 * This storage solution follows OpenAI's conversation state management best practices
 * by preserving previous responses and function call results to provide continuity
 * across multiple API requests using the Response API's previous_response_id parameter.
 */
public with sharing class OpenAIConversationStoreClass {
    // Simple in-memory store for testing purposes
    // In production, this would be replaced with a persistent storage mechanism
    private static Map<String, Map<String, Object>> responseStore = new Map<String, Map<String, Object>>();
    private static Map<String, Map<String, Object>> functionCallStore = new Map<String, Map<String, Object>>();
    
    // Constants for storage limits
    private static final Integer MAX_RESPONSES = 100;
    private static final Integer MAX_FUNCTION_CALLS = 200;
    
    /**
     * @description Store response details with automatic cleanup of old entries
     * @param responseId OpenAI response ID
     * @param responseData Response data
     */
    public static void storeResponse(String responseId, Map<String, Object> responseData) {
        if (String.isBlank(responseId)) {
            System.debug(LoggingLevel.WARN, 'Attempted to store response with blank ID');
            return;
        }
        
        // Clean up old responses if we're at the limit
        if (responseStore.size() >= MAX_RESPONSES) {
            List<String> responseIds = new List<String>(responseStore.keySet());
            responseIds.sort(); // Sort by ID (which should correlate with timestamp)
            Integer toRemove = Math.max(1, MAX_RESPONSES / 10); // Remove 10% or at least 1
            
            for (Integer i = 0; i < toRemove && i < responseIds.size(); i++) {
                responseStore.remove(responseIds[i]);
                System.debug('Removed old response: ' + responseIds[i]);
            }
        }
        
        responseStore.put(responseId, responseData);
        System.debug('Stored response with ID: ' + responseId);
        System.debug('Current response store size: ' + responseStore.size());
    }
    
    /**
     * @description Store function call details with automatic cleanup of old entries
     * @param callId Function call ID
     * @param functionData Function call data including results
     */
    public static void storeFunctionCall(String callId, Map<String, Object> functionData) {
        if (String.isBlank(callId)) {
            System.debug(LoggingLevel.WARN, 'Attempted to store function call with blank ID');
            return;
        }
        
        // Clean up old function calls if we're at the limit
        if (functionCallStore.size() >= MAX_FUNCTION_CALLS) {
            List<String> callIds = new List<String>(functionCallStore.keySet());
            callIds.sort(); // Sort by ID (which should correlate with timestamp)
            Integer toRemove = Math.max(1, MAX_FUNCTION_CALLS / 10); // Remove 10% or at least 1
            
            for (Integer i = 0; i < toRemove && i < callIds.size(); i++) {
                functionCallStore.remove(callIds[i]);
                System.debug('Removed old function call: ' + callIds[i]);
            }
        }
        
        // Add timestamp if not present
        if (!functionData.containsKey('timestamp')) {
            functionData.put('timestamp', System.now());
        }
        
        functionCallStore.put(callId, functionData);
        System.debug('Stored function call with ID: ' + callId);
        System.debug('Current function call store size: ' + functionCallStore.size());
    }
    
    /**
     * @description Get response details with error handling
     * @param responseId OpenAI response ID
     * @return Map<String, Object> Response data or empty map if not found
     */
    public static Map<String, Object> getResponse(String responseId) {
        try {
            if (String.isBlank(responseId)) {
                System.debug(LoggingLevel.WARN, 'Attempted to retrieve response with blank ID');
                return new Map<String, Object>();
            }
            
            if (!responseStore.containsKey(responseId)) {
                System.debug(LoggingLevel.INFO, 'Response not found for ID: ' + responseId);
                return new Map<String, Object>();
            }
            
            System.debug('Retrieved response for ID: ' + responseId);
            return responseStore.get(responseId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving response: ' + e.getMessage());
            return new Map<String, Object>();
        }
    }
    
    /**
     * @description Get function call details with error handling
     * @param callId Function call ID
     * @return Map<String, Object> Function call data or empty map if not found
     */
    public static Map<String, Object> getFunctionCall(String callId) {
        try {
            if (String.isBlank(callId)) {
                System.debug(LoggingLevel.WARN, 'Attempted to retrieve function call with blank ID');
                return new Map<String, Object>();
            }
            
            if (!functionCallStore.containsKey(callId)) {
                System.debug(LoggingLevel.INFO, 'Function call not found for ID: ' + callId);
                return new Map<String, Object>();
            }
            
            System.debug('Retrieved function call for ID: ' + callId);
            return functionCallStore.get(callId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving function call: ' + e.getMessage());
            return new Map<String, Object>();
        }
    }
    
    /**
     * @description Get all function calls associated with a response
     * Includes error handling and sorting by timestamp
     * @param responseId OpenAI response ID
     * @return Map<String, Map<String, Object>> Map of function call IDs to function call data
     */
    public static Map<String, Map<String, Object>> getFunctionCallsForResponse(String responseId) {
        try {
            if (String.isBlank(responseId)) {
                System.debug(LoggingLevel.WARN, 'Attempted to retrieve function calls with blank response ID');
                return new Map<String, Map<String, Object>>();
            }
            
            // Filter function calls by response ID and sort by timestamp
            Map<String, Map<String, Object>> result = new Map<String, Map<String, Object>>();
            List<FunctionCallWrapper> sortedCalls = new List<FunctionCallWrapper>();
            
            for (String callId : functionCallStore.keySet()) {
                Map<String, Object> callData = functionCallStore.get(callId);
                if (callData.containsKey('response_id') && callData.get('response_id') == responseId) {
                    sortedCalls.add(new FunctionCallWrapper(callData));
                }
            }
            
            // Sort by timestamp
            sortedCalls.sort();
            
            // Rebuild map with sorted calls
            for (FunctionCallWrapper wrapper : sortedCalls) {
                Map<String, Object> callData = wrapper.callData;
                String callId = (String)callData.get('call_id');
                result.put(callId, callData);
            }
            
            System.debug('Retrieved ' + result.size() + ' function calls for response ID: ' + responseId);
            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving function calls: ' + e.getMessage());
            return new Map<String, Map<String, Object>>();
        }
    }
    
    /**
     * @description Clear all stored responses and function calls
     * Use this for testing or to reset the store
     */
    public static void clearAll() {
        Integer responseCount = responseStore.size();
        Integer functionCallCount = functionCallStore.size();
        
        responseStore.clear();
        functionCallStore.clear();
        
        System.debug('Cleared ' + responseCount + ' responses and ' + 
                    functionCallCount + ' function calls from storage');
    }
    
    /**
     * @description Get storage statistics
     * @return Map<String, Integer> Map containing current storage statistics
     */
    public static Map<String, Integer> getStorageStats() {
        return new Map<String, Integer>{
            'responseCount' => responseStore.size(),
            'functionCallCount' => functionCallStore.size(),
            'maxResponses' => MAX_RESPONSES,
            'maxFunctionCalls' => MAX_FUNCTION_CALLS
        };
    }
    
    /**
     * @description Wrapper class for sorting function calls by timestamp
     */
    private class FunctionCallWrapper implements Comparable {
        public Map<String, Object> callData;
        public DateTime timestamp;
        
        public FunctionCallWrapper(Map<String, Object> callData) {
            this.callData = callData;
            this.timestamp = (DateTime)callData.get('timestamp');
            if (this.timestamp == null) {
                this.timestamp = DateTime.now(); // Default to now if no timestamp
            }
        }
        
        public Integer compareTo(Object other) {
            FunctionCallWrapper otherWrapper = (FunctionCallWrapper)other;
            if (this.timestamp > otherWrapper.timestamp) return -1;
            if (this.timestamp < otherWrapper.timestamp) return 1;
            return 0;
        }
    }
}