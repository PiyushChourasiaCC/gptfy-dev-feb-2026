/**
 * @description:
 *   AIAgenticFunctionHandler implements the AIAgenticInterface and serves as the central handler for
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
public with sharing class AIAgenticFunctionHandler implements AIAgenticInterface {

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
     * @param ex      The Java exception caught during method execution.
     * @return String Serialized JSON object indicating failure and including the message.
     */
    private String errorResponse(Exception ex) {
        return JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => ex.getMessage()
        });
    }

    /**
     * @description
     *   Utility method for returning a JSON error response with a custom string message.
     * @param message Error message to include in the response.
     * @return String Serialized JSON object indicating failure and including the message.
     */
    private String errorResponse(String message) {
        return JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        });
    }

    /**
     * @description
     *   Entry point for dispatching supported agentic function calls.
     *   Delegates to helper methods based on the requestParam string.
     * @param requestParam  The functional method or action to execute.
     * @param parameters    Input parameters for the operation.
     * @return String       JSON-encoded operation response or error.
     */
    public String executeMethod(String requestParam, Map<String, Object> parameters) {
        try {
            switch on requestParam {
                // Account-related finders
                when 'find_Account_by_name', 'find_Account_by_industry'  { return findAccount(parameters); }
                when 'find_Account_by_Id'                                { return findAccountById(parameters); }
                // Opportunity
                when 'find_Opportunity_by_name'                          { return findOpportunity(parameters); }
                // Contact
                when 'find_Contact_by_lastname'                          { return findContact(parameters); }
                // Case
                when 'search_Case_by_casenumber'                         { return findCase(parameters); }
                // Case creation
                when 'create_Case_for_Contact', 'create_Case_for_Account', 'create_Case'  { return createCase(parameters); }
                // Case comments
                when 'add_Case_Comment'                                  { return addCaseComment(parameters); }
                // Account details fetchers
                when 'get_Account_details_by_name'                       { return fetchAccountDetails(parameters); }
                when 'get_Account_details_by_Id'                         { return fetchAccountDetailsById(parameters); }
                // Account and Contact creators
                when 'create_Account_by_Name'                            { return createAccount(parameters); }
                when 'create_Contact_by_Name'                            { return createContact(parameters); }
                // Fallback/default for undefined methods
                when else                                                { return errorResponse('Method is not defined.'); }
            }
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Finds an Account record by its unique Id(s) supplied in parameters and returns details.
     * @param parameters   Map of field names and their values as key-value pairs.
     * @return String      JSON response with success, record list, and main AccountId.
     */
    public String findAccountById(Map<String, Object> parameters) {
        if (!hasObjectPerm('Account', 'read'))
            return errorResponse('Insufficient read permission on Account object.');
        String query = 'SELECT Id, Name, Industry FROM Account WHERE ';
        try {
            for (String key : parameters.keySet()) {
                query += key + ' = \'' + String.valueOf(parameters.get(key)) + '\' AND ';
            }
            if (query.trim().endsWithIgnoreCase('AND')) {
                query = query.substringBeforeLast('AND');
            }
            List<Account> accounts = (List<Account>)Database.query(query);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Found ' + accounts.size() + ' accounts.',
                'count' => accounts.size(),
                'accounts' => accounts,
                'AccountId' => (accounts.size() > 0 ? accounts[0].Id : null)
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Finds Account records using LIKE filters on parameters (e.g., name/industry).
     * @param parameters   Map of field names and search values.
     * @return String      JSON success structure and returned Accounts.
     */
    public String findAccount(Map<String, Object> parameters) {
        if (!hasObjectPerm('Account', 'read'))
            return errorResponse('Insufficient read permission on Account object.');
        String query = 'SELECT Id, Name, Industry FROM Account WHERE ';
        try {
            for (String key : parameters.keySet()) {
                String value = '%' + String.valueOf(parameters.get(key)) + '%';
                query += key + ' LIKE \'' + value + '\' AND ';
            }
            if(query.trim().endsWithIgnoreCase('AND')) {
                query = query.substringBeforeLast('AND');
            }
            List<Account> accounts = (List<Account>)Database.query(query);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Found ' + accounts.size() + ' accounts.',
                'count' => accounts.size(),
                'accounts' => accounts,
                'AccountId' => (accounts.size() > 0 ? accounts[0].Id : null)
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Finds Opportunity records using LIKE filters based on input parameters.
     * @param parameters   Map of Opportunity fields and search strings.
     * @return String      JSON object with matching opportunities and main OpportunityId.
     */
    public String findOpportunity(Map<String, Object> parameters) {
        if (!hasObjectPerm('Opportunity', 'read'))
            return errorResponse('Insufficient read permission on Opportunity object.');
        String query = 'SELECT Id, Name FROM Opportunity WHERE ';
        try {
            for (String key : parameters.keySet()) {
                String value = '%' + String.valueOf(parameters.get(key)) + '%';
                query += key + ' LIKE \'' + value + '\' AND ';
            }
            if(query.trim().endsWithIgnoreCase('AND')) {
                query = query.substringBeforeLast('AND');
            }
            List<Opportunity> opportunities = (List<Opportunity>)Database.query(query);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Found ' + opportunities.size() + ' opportunities.',
                'count' => opportunities.size(),
                'opportunities' => opportunities,
                'OpportunityId' => (opportunities.size() > 0 ? opportunities[0].Id : null)
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Finds Contact records using LIKE filtering on supplied parameter keys.
     * @param parameters   Map of last names and/or other searchable fields.
     * @return String      JSON response object listing contacts and first ContactId.
     */
    public String findContact(Map<String, Object> parameters) {
        if (!hasObjectPerm('Contact', 'read'))
            return errorResponse('Insufficient read permission on Contact object.');
        String query = 'SELECT Id, LastName, FirstName, Email, CreatedDate FROM Contact WHERE ';
        try {
            for (String key : parameters.keySet()) {
                String value = '%' + String.valueOf(parameters.get(key)) + '%';
                query += key + ' LIKE \'' + value + '\' AND ';
            }
            if(query.trim().endsWithIgnoreCase('AND')) {
                query = query.substringBeforeLast('AND');
            }
            List<Contact> contacts = (List<Contact>)Database.query(query);
            System.debug(contacts);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Found ' + contacts.size() + ' contacts.',
                'count' => contacts.size(),
                'contacts' => contacts,
                'ContactId' => (contacts.size() > 0 ? contacts[0].Id : null)
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Finds Case records by case number or other input parameter using LIKE.
     * @param parameters   Map of Case fields and filter strings.
     * @return String      JSON result including Cases, primary ParentId, and metadata.
     */
    public String findCase(Map<String, Object> parameters) {
        if (!hasObjectPerm('Case', 'read'))
            return errorResponse('Insufficient read permission on Case object.');
        String query = 'SELECT Id, CaseNumber FROM Case WHERE ';
        try {
            for (String key : parameters.keySet()) {
                String value = '%' + String.valueOf(parameters.get(key)) + '%';
                query += key + ' LIKE \'' + value + '\' AND ';
            }
            if(query.trim().endsWithIgnoreCase('AND')) {
                query = query.substringBeforeLast('AND');
            }
            List<Case> cases = (List<Case>)Database.query(query);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Found ' + cases.size() + ' cases.',
                'count' => cases.size(),
                'cases' => cases,
                'ParentId' => (cases.size() > 0 ? cases[0].Id : null)
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Creates a new Case record using key/value pairs in parameters.
     *   Checks for object FLS and DML permissions using FLSCheck utility.
     * @param parameters   Map of Case field names and values for record creation.
     * @return String      JSON success response with Case metadata and newly created ParentId.
     */
    public String createCase(Map<String, Object> parameters) {
        if (!hasObjectPerm('Case', 'create'))
            return errorResponse('Insufficient create permission on Case object.');
        try {
            SObject caseRec = new Case();
            for (String key : parameters.keySet()) {
                caseRec.put(key, String.valueOf(parameters.get(key)));
            }
            FLSCheck.getInstance().insertDML(new List<SObject> {caseRec});
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Created 1 case',
                'count' => 1,
                'case' => caseRec,
                'ParentId' => caseRec.Id
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Adds a new CaseComment to a specified Case.
     *   Checks permissions and performs DML.
     * @param parameters   Map of CaseComment fields and values.
     * @return String      JSON object signaling creation success and attached metadata.
     */
    public String addCaseComment(Map<String, Object> parameters) {
        if (!hasObjectPerm('CaseComment', 'create'))
            return errorResponse('Insufficient create permission on CaseComment object.');
        try {
            SObject caseComment = new CaseComment();
            for (String key : parameters.keySet()) {
                caseComment.put(key, String.valueOf(parameters.get(key)));
            }
            FLSCheck.getInstance().insertDML(new List<SObject>{caseComment});
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Created 1 caseComment',
                'count' => 1,
                'caseComment' => caseComment
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Fetches Account details by matching provided search parameters.
     *   Includes related Contacts, Opportunities, and Tasks.
     * @param parameters   Map of Account field names and LIKE values.
     * @return String      JSON object with account and related lists.
     */
    public String fetchAccountDetails(Map<String, Object> parameters) {
        try {
            String query =
                'SELECT Id, Name, Industry, Website, ' +
                '(SELECT Id, FirstName, LastName, Email FROM Contacts), ' +
                '(SELECT Id, Name, StageName FROM Opportunities), ' +
                '(SELECT Id, Subject, Status FROM Tasks) ' +
                'FROM Account WHERE ';
            for (String key : parameters.keySet()) {
                String value = '%' + String.valueOf(parameters.get(key)) + '%';
                query += key + ' LIKE \'' + value + '\' AND ';
            }
            if(query.trim().endsWithIgnoreCase('AND')) {
                query = query.substringBeforeLast('AND');
            }
            List<Account> accounts = Database.query(query);
            if (accounts.isEmpty()) {
                return JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'message' => 'No Account found'
                });
            }
            Account acc = accounts[0];
            List<Contact> contacts = acc.Contacts;
            List<Opportunity> opportunities = acc.Opportunities;
            List<Task> tasks = acc.Tasks;
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Fetched account with related details.',
                'account' => acc,
                'contacts' => contacts,
                'opportunities' => opportunities,
                'tasks' => tasks,
                'AccountId' => acc.Id
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Fetches Account details by unique Id(s) supplied in parameters. Includes related objects.
     * @param parameters   Map of Account field(s) and their unique Id(s). 
     * @return String      JSON object with full account and related records, or error if not found.
     */
    public String fetchAccountDetailsById(Map<String, Object> parameters) {
        try {
            String query =
                'SELECT Id, Name, Industry, Website, ' +
                '(SELECT Id, FirstName, LastName, Email FROM Contacts), ' +
                '(SELECT Id, Name, StageName FROM Opportunities), ' +
                '(SELECT Id, Subject, Status FROM Tasks) ' +
                'FROM Account WHERE ';
            for (String key : parameters.keySet()) {
                query += key + ' = \'' + String.valueOf(parameters.get(key)) + '\' AND ';
            }
            if(query.trim().endsWithIgnoreCase('AND')) {
                query = query.substringBeforeLast('AND');
            }
            List<Account> accounts = Database.query(query);
            if (accounts.isEmpty()) {
                return JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'message' => 'No Account found'
                });
            }
            Account acc = accounts[0];
            List<Contact> contacts = acc.Contacts;
            List<Opportunity> opportunities = acc.Opportunities;
            List<Task> tasks = acc.Tasks;
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Fetched account with related details.',
                'account' => acc,
                'contacts' => contacts,
                'opportunities' => opportunities,
                'tasks' => tasks,
                'AccountId' => acc.Id
            });
        } catch(Exception ex) {
            return errorResponse(ex);
        }
    }

    /**
     * @description
     *   Creates a new Account record as per input parameters.
     * @param parameters   Map containing Account fields for creation.
     * @return String      JSON response signaling creation success or failure.
     */
    public String createAccount(Map<String, Object> parameters) {
        try {
            Account account = new Account();
            for (String key : parameters.keySet()) {
                account.put(key, String.valueOf(parameters.get(key)));
            }
            insert account;
            return JSON.serialize(new Map<String, Object>{
                'status' => 'success',
                'message' => 'Successfully Created an Account ' + String.valueOf(parameters.get('Name')) + ' with RecordId : ' + account.Id,
                'RecordId' => account.Id
            });
        } catch (Exception e) {
            return JSON.serialize(new Map<String, Object>{
                'status' => 'errored',
                'message' => e.getMessage()
            });
        }
    }

    /**
     * @description
     *   Creates a new Contact record using the input parameter values.
     * @param parameters   Map of Contact fields for record creation.
     * @return String      JSON result with creation status and message.
     */
    public String createContact(Map<String, Object> parameters) {
        try {
            Contact contact = new Contact();
            for (String key : parameters.keySet()) {
                contact.put(key, String.valueOf(parameters.get(key)));
            }
            insert contact;
            return JSON.serialize(new Map<String, Object>{
                'status' => 'success',
                'message' => 'Successfully Created a Contact ' + String.valueOf(parameters.get('FirstName')) + ' ' + String.valueOf(parameters.get('LastName')) + ' RecordId : ' + contact.Id,
                'RecordId' => contact.Id
            });
        } catch (Exception e) {
            System.debug(e.getMessage());
            System.debug(e.getStackTraceString());
            return JSON.serialize(new Map<String, Object>{
                'status' => 'errored',
                'message' => e.getMessage()
            });
        }
    }
}