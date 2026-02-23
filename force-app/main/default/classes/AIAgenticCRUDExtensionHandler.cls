/**
 * @description:
 *   AIAgenticCRUDExtensionHandler implements the AIAgenticInterface and serves as the central handler for
 *   agentic function calls related to core Salesforce objects (Account, Contact, Opportunity, Case).
 *   It supports CRUD operations and queries, access control checks, standardized error handling,
 *   and JSON-formatted responses for common AI agent workflows.
 *   
 *   This class helps ensure robust, secured, and reusable agentic integrations for external AI automation.
 *
 * @author              : Piyush Chourasia
 * @group               : Plumcloud Labs
 * @last modified on    : 13-08-2025
 * @last modified by    : Piyush Chourasia
 */
public with sharing class AIAgenticCRUDExtensionHandler implements AIAgenticInterface {

    /**
     * @description
     *   Checks the current user's object-level permission (CRUD) for the specified sObject type.
     * @param sObjectName   The API name of the Salesforce object (e.g., 'Account').
     * @param permType      Permission type: 'read', 'create', 'update', 'delete'.
     * @return Boolean      True if permission is available; false otherwise.
     */
    private Boolean hasObjectPerm(String sObjectName, String permType) {
        Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe().get(sObjectName).getDescribe();
        if (permType == 'read')      return describeResult.isAccessible();
        if (permType == 'create')    return describeResult.isCreateable();
        if (permType == 'update')    return describeResult.isUpdateable();
        if (permType == 'delete')    return describeResult.isDeletable();
        return false;
    }

    /**
     * @description
     *   Utility method for returning a JSON error response with exception details.
     * @param ex      The exception caught during method execution.
     * @return String Serialized JSON object indicating failure and including the message.
     */
    private String errorResponse(Exception ex) {
        System.debug('=== ERROR RESPONSE ===');
        System.debug('Exception Message: ' + ex.getMessage());
        System.debug('Exception Type: ' + ex.getTypeName());
        System.debug('Stack Trace: ' + ex.getStackTraceString());
        
        return JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => ex.getMessage(),
            'stackTrace' => ex.getStackTraceString()
        });
    }

    /**
     * @description
     *   Utility method for returning a JSON error response with a custom string message.
     * @param message Error message to include in the response.
     * @return String Serialized JSON object indicating failure and including the message.
     */
    private String errorResponse(String message) {
        System.debug('=== CUSTOM ERROR RESPONSE ===');
        System.debug('Error Message: ' + message);
        
        return JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        });
    }

    /**
     * @description
     *   Entry point for dispatching supported CRUD extension function calls.
     *   Handles Update and Delete operations for core Salesforce objects.
     * @param requestParam  The functional method or action to execute.
     * @param parameters    Input parameters for the operation.
     * @return String       JSON-encoded operation response or error.
     */
    public String executeMethod(String requestParam, Map<String, Object> parameters) {
        System.debug('=== AIAgenticCRUDExtensionHandler.executeMethod START ===');
        System.debug('Request Parameter: ' + requestParam);
        System.debug('Input Parameters: ' + JSON.serializePretty(parameters));
        
        try {
            switch on requestParam {
                // Account Update/Delete operations
                when 'update_Account_by_Id' { 
                    System.debug('Routing to updateAccount');
                    return updateAccount(parameters); 
                }
                when 'update_Account_by_Name' { 
                    System.debug('Routing to updateAccountByName');
                    return updateAccountByName(parameters); 
                }
                
                // Fallback for undefined methods
                when else { 
                    System.debug('ERROR: Unknown method: ' + requestParam);
                    return errorResponse('Method is not defined in CRUD Extension Handler: ' + requestParam); 
                }
            }
        } catch(Exception ex) {
            System.debug('EXCEPTION in executeMethod: ' + ex.getMessage());
            System.debug('Exception type: ' + ex.getTypeName());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            return errorResponse(ex);
        }
    }

    // ===============================
    // ACCOUNT UPDATE OPERATIONS WITH DEBUG
    // ===============================

    /**
     * @description
     *   Updates an Account record by ID with the provided field values.
     * @param parameters   Map containing 'recordId' and field names with new values.
     * @return String      JSON response indicating success or failure.
     */
    public String updateAccount(Map<String, Object> parameters) {
        System.debug('=== updateAccount (by ID) DEBUG START ===');
        System.debug('Input parameters: ' + JSON.serializePretty(parameters));
        
        // Permission check
        Boolean hasUpdatePerm = hasObjectPerm('Account', 'update');
        System.debug('Account update permission: ' + hasUpdatePerm);
        
        if (!hasUpdatePerm) {
            String errorMsg = 'Insufficient update permission on Account object.';
            System.debug('ERROR: ' + errorMsg);
            return errorResponse(errorMsg);
        }
        
        if (!parameters.containsKey('recordId')) {
            String errorMsg = 'recordId parameter is required for update operations.';
            System.debug('ERROR: ' + errorMsg);
            return errorResponse(errorMsg);
        }
        
        try {
            String recordId = String.valueOf(parameters.get('recordId'));
            System.debug('Updating Account with ID: ' + recordId);
            
            Account accountToUpdate = new Account(Id = recordId);
            System.debug('Created Account instance with ID: ' + accountToUpdate.Id);
            
            System.debug('Processing field updates...');
            Integer fieldCount = 0;
            for (String key : parameters.keySet()) {
                if (key != 'recordId') {
                    Object value = parameters.get(key);
                    System.debug('Setting field: ' + key + ' = ' + value);
                    accountToUpdate.put(key, value);
                    fieldCount++;
                }
            }
            System.debug('Total fields to update: ' + fieldCount);
            
            System.debug('Account before update: ' + JSON.serializePretty(accountToUpdate));
            
            System.debug('Calling FLSCheck.getInstance().updateDML...');
            FLSCheck.getInstance().updateDML(new List<SObject>{accountToUpdate});
            System.debug('Update DML completed successfully');
            
            Map<String, Object> response = new Map<String, Object>{
                'success' => true,
                'message' => 'Successfully updated Account',
                'recordId' => recordId,
                'updatedFields' => fieldCount
            };
            
            System.debug('Final response: ' + JSON.serializePretty(response));
            System.debug('=== updateAccount (by ID) DEBUG END ===');
            
            return JSON.serialize(response);
            
        } catch(Exception ex) {
            System.debug('EXCEPTION in updateAccount: ' + ex.getMessage());
            System.debug('Exception type: ' + ex.getTypeName());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            System.debug('=== updateAccount (by ID) DEBUG END (ERROR) ===');
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Updates an Account record by Name with the provided field values.
     *   First finds the Account by name, then updates it.
     * @param parameters   Map containing 'Name' and field names with new values.
     * @return String      JSON response indicating success or failure.
     */
    public String updateAccountByName(Map<String, Object> parameters) {
        System.debug('=== updateAccountByName DEBUG START ===');
        System.debug('Input parameters: ' + JSON.serializePretty(parameters));
        
        // Permission check
        Boolean hasReadPerm = hasObjectPerm('Account', 'read');
        Boolean hasUpdatePerm = hasObjectPerm('Account', 'update');
        System.debug('Account read permission: ' + hasReadPerm);
        System.debug('Account update permission: ' + hasUpdatePerm);
        
        if (!hasReadPerm || !hasUpdatePerm) {
            String errorMsg = 'Insufficient read/update permission on Account object.';
            System.debug('ERROR: ' + errorMsg);
            return errorResponse(errorMsg);
        }
        
        if (!parameters.containsKey('Name')) {
            String errorMsg = 'Name parameter is required for update by name operations.';
            System.debug('ERROR: ' + errorMsg);
            return errorResponse(errorMsg);
        }
        
        try {
            String accountName = String.valueOf(parameters.get('Name'));
            System.debug('Searching for Account with name: ' + accountName);
            
            // First, find the Account by name
            List<Account> existingAccounts = [SELECT Id, Name FROM Account WHERE Name = :accountName LIMIT 1];
            System.debug('Query executed. Found ' + existingAccounts.size() + ' accounts');
            
            if (existingAccounts.isEmpty()) {
                String errorMsg = 'No Account found with name: ' + accountName;
                System.debug('ERROR: ' + errorMsg);
                return errorResponse(errorMsg);
            }
            
            Account accountToUpdate = existingAccounts[0];
            System.debug('Found Account - ID: ' + accountToUpdate.Id + ', Name: ' + accountToUpdate.Name);
            
            System.debug('Processing field updates...');
            Integer fieldCount = 0;
            for (String key : parameters.keySet()) {
                if (key != 'Name') {  // Don't update the search criteria
                    Object value = parameters.get(key);
                    System.debug('Setting field: ' + key + ' = ' + value);
                    accountToUpdate.put(key, value);
                    fieldCount++;
                }
            }
            System.debug('Total fields to update: ' + fieldCount);
            
            System.debug('Account before update: ' + JSON.serializePretty(accountToUpdate));
            
            // Perform the update
            System.debug('Calling FLSCheck.getInstance().updateDML...');
            FLSCheck.getInstance().updateDML(new List<SObject>{accountToUpdate});
            System.debug('Update DML completed successfully');
            
            Map<String, Object> response = new Map<String, Object>{
                'success' => true,
                'message' => 'Successfully updated Account: ' + accountName,
                'recordId' => accountToUpdate.Id,
                'accountName' => accountName,
                'updatedFields' => fieldCount
            };
            
            System.debug('Final response: ' + JSON.serializePretty(response));
            System.debug('=== updateAccountByName DEBUG END ===');
            
            return JSON.serialize(response);
            
        } catch(Exception ex) {
            System.debug('EXCEPTION in updateAccountByName: ' + ex.getMessage());
            System.debug('Exception type: ' + ex.getTypeName());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            System.debug('=== updateAccountByName DEBUG END (ERROR) ===');
            return errorResponse(ex);
        }
    }
}