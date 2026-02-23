/**
 * @description Controller for handling interactions with OpenAI's Response API
 * This class supports multiple features:
 * - Text generation with conversation context
 * - Function calling for Salesforce data operations
 * - File handling and processing
 * - Web search integration
 * - Rich text output with citations
 * 
 * Based on OpenAI's Response API: https://api.openai.com/v1/responses
 * Documentation: https://platform.openai.com/docs/api-reference/responses
 */
public with sharing class OpenAIResponseClass {
    // API configuration from custom metadata
    private static final String OPENAI_API_KEY = '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';
    private static final String OPENAI_RESPONSES_ENDPOINT = 'https://api.openai.com/v1/responses';
    private static final String OPENAI_FILES_ENDPOINT = 'https://api.openai.com/v1/files';
    
    // Timeout configurations
    private static final Integer DEFAULT_TIMEOUT = 120000; // 2 minutes
    private static final Integer STREAMING_TIMEOUT = 30000; // 30 seconds timeout for streaming requests
    
    // Function definitions for account-related tools
    private static final List<Map<String, Object>> ACCOUNT_FUNCTION_TOOLS = new List<Map<String, Object>>{
        new Map<String, Object>{
            'type' => 'function',
            'name' => 'search_accounts',
            'description' => 'Search for Salesforce accounts by name. Use this when a user asks about a specific company or wants to find accounts matching certain names. Returns up to 5 matching accounts with detailed information including contacts.',
            'parameters' => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'search_term' => new Map<String, Object>{
                        'type' => 'string',
                        'description' => 'The company name or partial name to search for. Will match any account containing this term (case-insensitive).'
                    }
                },
                'required' => new List<String>{'search_term'},
                'additionalProperties' => false
            },
            'strict' => true
        },
        new Map<String, Object>{
            'type' => 'function',
            'name' => 'get_account_details',
            'description' => 'Get detailed information about a specific Salesforce account by its ID. Use this when you need to fetch fresh details about an account that has already been identified.',
            'parameters' => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'account_id' => new Map<String, Object>{
                        'type' => 'string',
                        'description' => 'The Salesforce ID of the account to retrieve details for'
                    }
                },
                'required' => new List<String>{'account_id'},
                'additionalProperties' => false
            },
            'strict' => true
        }
    };
    
    /**
     * Custom exception class for OpenAI API errors
     */
    public class OpenAIException extends Exception {}
    
    /**
     * @description Class to wrap output text with rich text capabilities
     * Used to pass text content by reference between methods
     */
    private class RichText {
        public String plainText = '';
        public List<Map<String, Object>> segments = new List<Map<String, Object>>();
        
        public void addText(String text) {
            if (text == null) return;
            
            plainText += text;
            segments.add(new Map<String, Object>{
                'type' => 'text',
                'content' => text
            });
        }
        
        public void addLink(String text, String url, String citation) {
            if (text == null) return;
            
            plainText += text;
            segments.add(new Map<String, Object>{
                'type' => 'link',
                'content' => text,
                'url' => url,
                'citation' => citation
            });
        }
        
        /**
         * @description Convert to HTML for rich text display
         * Returned as a Map with both HTML and plain text for flexibility
         */
        public Map<String, String> toFormattedOutput() {
            String html = '';
            
            for (Map<String, Object> segment : segments) {
                String type = (String)segment.get('type');
                String content = (String)segment.get('content');
                
                if (type == 'link') {
                    String url = (String)segment.get('url');
                    String citation = (String)segment.get('citation') != null ? 
                                     ' (' + (String)segment.get('citation') + ')' : '';
                    
                    // Escape HTML in content and citation for security
                    content = escapeHtml(content);
                    citation = escapeHtml(citation);
                    
                    // Create link with safe URL and target="_blank"
                    html += '<a href="' + escapeHtml(url) + '" target="_blank" rel="noopener noreferrer">' 
                         + content + citation + '</a>';
                } else {
                    // Regular text - convert line breaks and escape HTML
                    html += formatTextWithLineBreaks(content);
                }
            }
            
            return new Map<String, String>{
                'html' => html,
                'text' => plainText
            };
        }
        
        /**
         * @description Escape HTML to prevent XSS issues
         */
        private String escapeHtml(String input) {
            if (input == null) return '';
            
            return input
                .replace('&', '&amp;')
                .replace('<', '&lt;')
                .replace('>', '&gt;')
                .replace('"', '&quot;')
                .replace('\'', '&#x27;');
        }
        
        /**
         * @description Format text with proper HTML line breaks
         */
        private String formatTextWithLineBreaks(String input) {
            if (input == null) return '';
            
            String escapedText = escapeHtml(input);
            return escapedText.replace('\n', '<br>');
        }
    }
    
    /**
     * @description Sends a message to OpenAI API with support for text generation, function calling,
     * web search, and file processing.
     * 
     * @param message The user's input message (text content)
     * @param fileId Optional file ID for file-based queries (PDF, DOC, etc.)
     * @param isStreaming Whether to use streaming response
     * @param previousResponseId ID of the previous response for conversation context
     * @return Map<String, Object> Response containing message, search results, and function call results
     */
    @AuraEnabled
    public static Map<String, Object> sendMessage(String message, String fileId, Boolean isStreaming, String previousResponseId) {
        try {
            System.debug('Received parameters:');
            System.debug('message: ' + message);
            System.debug('fileId: ' + fileId);
            System.debug('isStreaming: ' + isStreaming);
            System.debug('previousResponseId: ' + previousResponseId);

            if (String.isBlank(OPENAI_API_KEY)) {
                throw new OpenAIException('OpenAI API Key not found');
            }

            // Set default value for isStreaming if null
            isStreaming = (isStreaming != null) ? isStreaming : false;

            // Build the user content list
            List<Map<String, Object>> userContent = new List<Map<String, Object>>();
            
            // Add file content if provided
            if (String.isNotBlank(fileId)) {
                System.debug('Adding file content with ID: ' + fileId);
                Map<String, Object> fileContent = new Map<String, Object>{
                    'type' => 'input_file',
                    'file_id' => fileId
                };
                userContent.add(fileContent);
                System.debug('Added file content: ' + JSON.serialize(fileContent));
            }
            
            // Add text content
            Map<String, Object> textContent = new Map<String, Object>{
                'type' => 'input_text',
                'text' => message
            };
            userContent.add(textContent);
            
            // Prepare the input for the API request
            List<Map<String, Object>> input = new List<Map<String, Object>>();
            
            // Always include the user message
            Map<String, Object> userMessage = new Map<String, Object>{
                'role' => 'user',
                'content' => userContent
            };
            
            // If it's a new conversation, add system instructions
            if (String.isBlank(previousResponseId)) {
                // Include a developer message with system instructions
                Map<String, Object> developerMessage = new Map<String, Object>{
                    'role' => 'developer',
                    'content' => 'You are a helpful assistant integrated with Salesforce. You can search for and retrieve account information when needed.'
                };
                input.add(developerMessage);
            }
            
            // Add the user message
            input.add(userMessage);

            // Prepare the tools list
            List<Map<String, Object>> tools = new List<Map<String, Object>>(ACCOUNT_FUNCTION_TOOLS);
            
            // Add web search tool if no file is provided
            if (String.isBlank(fileId)) {
                tools.add(new Map<String, Object>{
                    'type' => 'web_search_preview',
                    'search_context_size' => 'medium'
                });
            }

            // Build the request body
            Map<String, Object> requestBody = new Map<String, Object>{
                'model' => 'gpt-4o',
                'input' => input,
                'tools' => tools,
                'stream' => isStreaming,
                'tool_choice' => 'auto'  // Let the model choose the most appropriate tool
            };

            // Add previous response ID for conversation continuity if available
            if (String.isNotBlank(previousResponseId)) {
                requestBody.put('previous_response_id', previousResponseId);
            }

            System.debug('Request Body: ' + JSON.serialize(requestBody));

            // Configure HTTP request
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(OPENAI_RESPONSES_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + OPENAI_API_KEY);
            
            // Set timeout based on isStreaming value
            if (isStreaming) {
                req.setTimeout(STREAMING_TIMEOUT);
                req.setHeader('Transfer-Encoding', 'chunked');
            } else {
                req.setTimeout(DEFAULT_TIMEOUT);
            }

            // Convert request body to JSON and send
            String requestBodyString = JSON.serialize(requestBody);
            req.setBody(requestBodyString);

            // Send request and process response
            HttpResponse res = http.send(req);
            System.debug('Response Status Code: ' + res.getStatusCode());
            
            // Only log response body if not too large to avoid heap size issues
            if (res.getBody().length() < 100000) {
                System.debug('Response Body: ' + res.getBody());
            } else {
                System.debug('Response Body is too large to log completely');
            }

            if (res.getStatusCode() == 200) {
                // Parse response
                Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                
                // Store the response for future reference
                if (responseMap.containsKey('id')) {
                    String responseId = (String)responseMap.get('id');
                    OpenAIConversationStoreClass.storeResponse(responseId, responseMap);
                }
                
                // Process response to extract text, function calls, and search results
                return processResponse(responseMap);
            } else if (res.getStatusCode() == 400 && res.getBody().contains('No tool call found for function call output')) {
                // Handle the case where OpenAI doesn't recognize the function call output
                // This happens when we try to use function call results for calls that weren't made in the context
                
                // Log the error for debugging
                System.debug('Error: OpenAI doesn\'t recognize the function call in the context');
                System.debug('Attempting to resend without function call outputs');
                
                // Try again but without referencing previous response ID
                // This will start a new conversation but preserve the user message
                requestBody.remove('previous_response_id');
                
                // Update the request
                req.setBody(JSON.serialize(requestBody));
                System.debug('Retrying with updated request body: ' + JSON.serialize(requestBody));
                
                // Send the updated request
                res = http.send(req);
                
                if (res.getStatusCode() == 200) {
                    // Parse response
                    Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                    
                    // Store the response for future reference
                    if (responseMap.containsKey('id')) {
                        String responseId = (String)responseMap.get('id');
                        OpenAIConversationStoreClass.storeResponse(responseId, responseMap);
                    }
                    
                    // Process response to extract text, function calls, and search results
                    return processResponse(responseMap);
                } else {
                    return new Map<String, Object>{
                        'status' => 'error',
                        'error' => 'API returned status code: ' + res.getStatusCode() + ' with body: ' + res.getBody(),
                        'recovery' => 'Retried without previous_response_id but still failed'
                    };
                }
            } else {
                return new Map<String, Object>{
                    'status' => 'error',
                    'error' => 'API returned status code: ' + res.getStatusCode() + ' with body: ' + res.getBody()
                };
            }
        } catch (Exception e) {
            System.debug('Error in sendMessage: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return new Map<String, Object>{
                'status' => 'error',
                'error' => e.getMessage()
            };
        }
    }
    
    /**
     * @description Process the response from OpenAI API to extract text, function calls, and search results.
     * 
     * @param responseMap The raw response map from OpenAI API
     * @return Map<String, Object> Processed response with extracted data
     */
    private static Map<String, Object> processResponse(Map<String, Object> responseMap) {
        // Initialize the RichText container to capture all text
        RichText outputContent = new RichText();
        List<Map<String, Object>> citations = new List<Map<String, Object>>();
        List<Map<String, Object>> searchResults = new List<Map<String, Object>>();
        List<Map<String, Object>> functionCalls = new List<Map<String, Object>>();
        
        // Process output array to extract different types of items
        if (responseMap.containsKey('output')) {
            List<Object> outputs = (List<Object>)responseMap.get('output');
            System.debug('Processing ' + outputs.size() + ' output items');
            
            for (Object item : outputs) {
                Map<String, Object> outputMap = (Map<String, Object>)item;
                String outputType = (String)outputMap.get('type');
                System.debug('Processing output type: ' + outputType);
                
                if (outputType == 'function_call') {
                    // Handle function calls - this updates outputContent directly through reference
                    processFunctionCall(outputMap, functionCalls, outputContent, (String)responseMap.get('id'));
                } else if (outputType == 'web_search_call' || outputType == 'file_search_call') {
                    // Handle search results
                    if (outputMap.containsKey('search_results')) {
                        searchResults = (List<Map<String, Object>>)outputMap.get('search_results');
                        
                        // Process search results for citations
                        processSearchResults(searchResults, citations, outputContent);
                    }
                } else if (outputType == 'message') {
                    // Extract text from message content
                    List<Object> content = (List<Object>)outputMap.get('content');
                    for (Object contentItem : content) {
                        Map<String, Object> contentMap = (Map<String, Object>)contentItem;
                        if (contentMap.get('type') == 'output_text') {
                            String textPart = (String)contentMap.get('text');
                            outputContent.addText(textPart);
                        }
                    }
                }
            }
        }
        
        // Convert rich content to formatted output
        Map<String, String> formattedOutput = outputContent.toFormattedOutput();
        
        // Build the final result map
        Map<String, Object> result = new Map<String, Object>{
            'status' => responseMap.get('status'),
            'id' => responseMap.get('id'),
            'response' => formattedOutput.get('text'),
            'responseHtml' => formattedOutput.get('html'),
            'hasRichContent' => !citations.isEmpty(),
            'citations' => citations,
            'search_results' => searchResults,
            'function_calls' => functionCalls,
            'output' => responseMap.get('output') // Include the raw output for debugging
        };
        
        if (responseMap.containsKey('error')) {
            result.put('error', responseMap.get('error'));
        }
        
        return result;
    }
    
    /**
     * @description Process web search results to extract citations
     * 
     * @param searchResults List of search results
     * @param citations List to store citation data
     * @param outputContent RichText object to update with citation links
     */
    private static void processSearchResults(List<Map<String, Object>> searchResults, 
                                           List<Map<String, Object>> citations, 
                                           RichText outputContent) {
        if (searchResults == null || searchResults.isEmpty()) {
            return;
        }
        
        // Add a section header for search results
        outputContent.addText('\n\nSearch Results:\n');
        
        Integer citationIndex = 1;
        
        for (Map<String, Object> result : searchResults) {
            // Only process results with URLs
            if (result.containsKey('url') && result.get('url') != null) {
                String url = (String)result.get('url');
                String title = result.containsKey('title') ? (String)result.get('title') : 'Source ' + citationIndex;
                
                // Add formatted citation entry
                outputContent.addText('• ');
                outputContent.addLink(title, url, '[' + citationIndex + ']');
                outputContent.addText('\n');
                
                // Add to citations list
                citations.add(new Map<String, Object>{
                    'index' => citationIndex,
                    'url' => url,
                    'title' => title
                });
                
                citationIndex++;
            }
        }
        
        // Add a line break after citations
        if (citationIndex > 1) {
            outputContent.addText('\n');
        }
    }
    
    /**
     * @description Process a function call from the model, execute it, and store for future reference.
     * 
     * @param outputMap The output map containing function call details
     * @param functionCalls List to store function call details and results
     * @param outputContent RichText object to update with function results
     * @param responseId The response ID for associating function calls with responses
     */
    private static void processFunctionCall(Map<String, Object> outputMap, 
                                          List<Map<String, Object>> functionCalls, 
                                          RichText outputContent, 
                                          String responseId) {
        System.debug('Function call details: ' + JSON.serialize(outputMap));
        String functionName = (String)outputMap.get('name');
        String arguments = (String)outputMap.get('arguments');
        String callId = (String)outputMap.get('call_id');
        
        System.debug('Function name: ' + functionName);
        System.debug('Function arguments: ' + arguments);
        System.debug('Call ID: ' + callId);
        
        // Execute the function and get results
        Map<String, Object> functionResult = new Map<String, Object>();
        String resultText = '';
        
        try {
            if (functionName == 'search_accounts') {
                Map<String, Object> args = (Map<String, Object>)JSON.deserializeUntyped(arguments);
                String searchTerm = (String)args.get('search_term');
                System.debug('Searching accounts with term: ' + searchTerm);
                List<Account> accounts = searchAccounts(searchTerm);
                System.debug('Found ' + accounts.size() + ' accounts');
                
                // Format account results as text
                resultText = formatAccountSearchResults(accounts, searchTerm);
                
                // Add formatted results to function result
                functionResult.put('accounts', accounts);
                functionResult.put('search_term', searchTerm);
                functionResult.put('result_text', resultText);
            } else if (functionName == 'get_account_details') {
                Map<String, Object> args = (Map<String, Object>)JSON.deserializeUntyped(arguments);
                String accountId = (String)args.get('account_id');
                System.debug('Getting account details for ID: ' + accountId);
                Account account = getAccountDetails(accountId);
                System.debug('Retrieved account: ' + account);
                
                // Format account details as text
                resultText = formatAccountDetails(account, accountId);
                
                // Add formatted results to function result
                functionResult.put('account', account);
                functionResult.put('account_id', accountId);
                functionResult.put('result_text', resultText);
            }
        } catch (Exception e) {
            System.debug('Error executing function ' + functionName + ': ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            resultText = 'Error executing function: ' + e.getMessage();
            functionResult.put('error', e.getMessage());
        }
        
        // Create the function call record for storage and tracking
        Map<String, Object> functionCallRecord = new Map<String, Object>{
            'call_id' => callId,
            'name' => functionName,
            'arguments' => arguments,
            'result' => functionResult,
            'result_text' => resultText,
            'response_id' => responseId,
            'timestamp' => System.now()
        };
        
        // Store function call for future reference
        if (String.isNotBlank(callId)) {
            OpenAIConversationStoreClass.storeFunctionCall(callId, functionCallRecord);
        }
        
        // Add function call details to the list
        functionCalls.add(new Map<String, Object>{
            'name' => functionName,
            'arguments' => arguments,
            'result' => functionResult,
            'call_id' => callId,
            'result_text' => resultText
        });
        
        // Append the result text to the outputContent
        outputContent.addText(resultText);
    }
    
    /**
     * @description Format account search results as readable text.
     * 
     * @param accounts List of accounts found in search
     * @param searchTerm The search term used
     * @return String Formatted account search results
     */
    private static String formatAccountSearchResults(List<Account> accounts, String searchTerm) {
        if (accounts == null || accounts.isEmpty()) {
            return 'No accounts found matching "' + searchTerm + '"';
        }
        
        String result = 'Found ' + accounts.size() + ' matching accounts:\n\n';
        for (Account acc : accounts) {
            result += '- ' + acc.Name + ' (ID: ' + acc.Id + ')\n';
            if (acc.Industry != null) result += '  Industry: ' + acc.Industry + '\n';
            if (acc.AnnualRevenue != null) result += '  Annual Revenue: $' + acc.AnnualRevenue + '\n';
            if (acc.Type != null) result += '  Type: ' + acc.Type + '\n';
            if (acc.Rating != null) result += '  Rating: ' + acc.Rating + '\n';
            if (acc.Phone != null) result += '  Phone: ' + acc.Phone + '\n';
            if (acc.Website != null) result += '  Website: ' + acc.Website + '\n';
            if (acc.Description != null) result += '  Description: ' + acc.Description + '\n';
            if (acc.NumberOfEmployees != null) result += '  Employees: ' + acc.NumberOfEmployees + '\n';
            
            // Format billing address if any part is present
            List<String> addressParts = new List<String>();
            if (acc.BillingStreet != null) addressParts.add(acc.BillingStreet);
            if (acc.BillingCity != null) addressParts.add(acc.BillingCity);
            if (acc.BillingState != null) addressParts.add(acc.BillingState);
            if (acc.BillingPostalCode != null) addressParts.add(acc.BillingPostalCode);
            if (acc.BillingCountry != null) addressParts.add(acc.BillingCountry);
            
            if (!addressParts.isEmpty()) {
                result += '  Address: ' + String.join(addressParts, ', ') + '\n';
            }
            
            if (acc.Contacts != null && !acc.Contacts.isEmpty()) {
                result += '  Key Contacts:\n';
                for (Contact con : acc.Contacts) {
                    result += '    - ' + con.FirstName + ' ' + con.LastName;
                    if (con.Email != null) result += ' (' + con.Email + ')';
                    if (con.Phone != null) result += ' Tel: ' + con.Phone;
                    result += '\n';
                }
            }
            result += '\n';
        }
        
        return result;
    }
    
    /**
     * @description Format account details as readable text.
     * 
     * @param account Account object with details
     * @param accountId The account ID requested
     * @return String Formatted account details
     */
    private static String formatAccountDetails(Account account, String accountId) {
        if (account == null) {
            return 'No account found with ID: ' + accountId;
        }
        
        String result = 'Account Details for ' + account.Name + ':\n\n';
        result += '- Industry: ' + (account.Industry != null ? account.Industry : 'Not specified') + '\n';
        result += '- Annual Revenue: ' + (account.AnnualRevenue != null ? '$' + account.AnnualRevenue : 'Not specified') + '\n';
        result += '- Type: ' + (account.Type != null ? account.Type : 'Not specified') + '\n';
        result += '- Rating: ' + (account.Rating != null ? account.Rating : 'Not specified') + '\n';
        result += '- Phone: ' + (account.Phone != null ? account.Phone : 'Not specified') + '\n';
        result += '- Website: ' + (account.Website != null ? account.Website : 'Not specified') + '\n';
        result += '- Description: ' + (account.Description != null ? account.Description : 'Not specified') + '\n';
        result += '- Number of Employees: ' + (account.NumberOfEmployees != null ? String.valueOf(account.NumberOfEmployees) : 'Not specified') + '\n';
        result += '- Account Source: ' + (account.AccountSource != null ? account.AccountSource : 'Not specified') + '\n';
        result += '- Created Date: ' + account.CreatedDate.format() + '\n';
        result += '- Last Modified Date: ' + account.LastModifiedDate.format() + '\n';
        
        // Format billing address
        List<String> addressParts = new List<String>();
        if (account.BillingStreet != null) addressParts.add(account.BillingStreet);
        if (account.BillingCity != null) addressParts.add(account.BillingCity);
        if (account.BillingState != null) addressParts.add(account.BillingState);
        if (account.BillingPostalCode != null) addressParts.add(account.BillingPostalCode);
        if (account.BillingCountry != null) addressParts.add(account.BillingCountry);
        
        result += '- Billing Address: ' + (addressParts.isEmpty() ? 'Not specified' : String.join(addressParts, ', ')) + '\n';
        
        if (account.Contacts != null && !account.Contacts.isEmpty()) {
            result += '\nKey Contacts:\n';
            for (Contact con : account.Contacts) {
                result += '- ' + con.FirstName + ' ' + con.LastName;
                if (con.Email != null) result += ' (' + con.Email + ')';
                if (con.Phone != null) result += ' Tel: ' + con.Phone;
                result += '\n';
            }
        }
        
        return result;
    }
    
    /**
     * @description Uploads a file to OpenAI for processing.
     * Supports various file types including PDF, DOC, DOCX, and text files.
     * 
     * @param fileName Name of the file being uploaded
     * @param fileContent Binary content of the file
     * @return String File ID from OpenAI
     */
    @AuraEnabled
    public static String uploadFile(String fileName, Blob fileContent) {
        if (String.isBlank(OPENAI_API_KEY)) {
            throw new OpenAIException('OpenAI API Key not found');
        }

        // Get content type based on file extension
        //String contentType = getContentType(fileName.toLowerCase());
        String contentType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        
        if (contentType == null) {
            throw new OpenAIException('Unsupported file type. Supported file types include PDF, DOC, DOCX, TXT, and more.');
        }

        // Create multipart form data for file upload
        String boundary = '---------------------------' + String.valueOf(DateTime.now().getTime());
        
        // Construct the body as form data
        String header = '--' + boundary + '\r\n' +
                       'Content-Disposition: form-data; name="purpose"\r\n\r\n' +
                       'assistants\r\n' +
                       '--' + boundary + '\r\n' +
                       'Content-Disposition: form-data; name="file"; filename="' + fileName + '"\r\n' +
                       'Content-Type: ' + contentType + '\r\n\r\n';
        
        String footer = '\r\n--' + boundary + '--';
        
        // Convert the header and footer to blobs
        Blob headerBlob = Blob.valueOf(header);
        Blob footerBlob = Blob.valueOf(footer);
        
        // Concatenate all parts
       /* Blob bodyBlob = Blob.valueOf('');
        bodyBlob = concatBlob(bodyBlob, headerBlob);
        bodyBlob = concatBlob(bodyBlob, fileContent);
        bodyBlob = concatBlob(bodyBlob, footerBlob); */
        
        String file = EncodingUtil.base64Encode(fileContent);
        String bodyPayload = header + file + footer;

        //System.debug(EncodingUtil.base64Encode(bodyBlob));
        // Send request to OpenAI Files API
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(OPENAI_FILES_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + OPENAI_API_KEY);
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setBodyAsBlob(Blob.valueOf(bodyPayload));
        req.setTimeout(120000); // 2 minutes timeout for file uploads
        
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            Map<String, Object> response = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            return (String)response.get('id');
        } else {
            throw new OpenAIException('API Error: ' + res.getStatusCode() + ' - ' + res.getBody());
        }
    }
    
    /**
     * @description Helper method to concatenate blobs.
     * 
     * @param blob1 First blob
     * @param blob2 Second blob
     * @return Blob Concatenated blob
     */
    private static Blob concatBlob(Blob blob1, Blob blob2) {
        String base64Blob1 = EncodingUtil.base64Encode(blob1);
        String base64Blob2 = EncodingUtil.base64Encode(blob2);
        String combinedBlob = base64Blob1 + base64Blob2;
        return EncodingUtil.base64Decode(combinedBlob);
    }

    /**
     * @description Gets the MIME type for a file based on its extension.
     * Supports common document formats for processing.
     * 
     * @param fileName Name of the file to check
     * @return String MIME type of the file or null if unsupported
     */
    private static String getContentType(String fileName) {
        Map<String, String> extensionToMimeType = new Map<String, String>{
            '.c' => 'text/x-c',
            '.cpp' => 'text/x-c++',
            '.cs' => 'text/x-csharp',
            '.css' => 'text/css',
            '.doc' => 'application/msword',
            '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            '.go' => 'text/x-golang',
            '.html' => 'text/html',
            '.java' => 'text/x-java',
            '.js' => 'text/javascript',
            '.json' => 'application/json',
            '.md' => 'text/markdown',
            '.pdf' => 'application/pdf',
            '.php' => 'text/x-php',
            '.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            '.py' => 'text/x-python',
            '.rb' => 'text/x-ruby',
            '.sh' => 'application/x-sh',
            '.tex' => 'text/x-tex',
            '.ts' => 'application/typescript',
            '.txt' => 'text/plain'
        };
        
        for (String extension : extensionToMimeType.keySet()) {
            if (fileName.endsWith(extension)) {
                return extensionToMimeType.get(extension);
            }
        }
        return null;
    }
    
    
    // Constants for query limits
    private static final Integer MAX_SEARCH_RESULTS = 5;
    private static final Integer MAX_CONTACTS_PER_ACCOUNT = 3;
    
    /**
     * @description Search for accounts by name with rich details
     * Non-cacheable version for OpenAI function calling to ensure fresh data
     * 
     * @param searchTerm The search term to match against account names
     * @return List<Account> List of matching accounts with their contacts
     */
    @AuraEnabled
    public static List<Account> searchAccounts(String searchTerm) {
        try {
            if (String.isBlank(searchTerm)) {
                return new List<Account>();
            }
            
            // Escape any special characters in the search term
            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            
            return [
                SELECT Id, Name, AnnualRevenue, Industry, 
                       Description, Website, Phone, 
                       BillingStreet, BillingCity, BillingState, 
                       BillingPostalCode, BillingCountry,
                       NumberOfEmployees, Type,
                       CreatedDate, LastModifiedDate,
                       Rating, AccountSource,
                       (SELECT Id, FirstName, LastName, Email, Phone 
                        FROM Contacts 
                        LIMIT :MAX_CONTACTS_PER_ACCOUNT)
                FROM Account 
                WHERE Name LIKE :searchPattern
                WITH SECURITY_ENFORCED
                ORDER BY Name
                LIMIT :MAX_SEARCH_RESULTS
            ];
        } catch (System.QueryException e) {
            System.debug(LoggingLevel.ERROR, 'Query error in searchAccounts: ' + e.getMessage());
            throw new AuraHandledException('Error searching accounts: ' + e.getMessage());
        } catch (System.SecurityException e) {
            System.debug(LoggingLevel.ERROR, 'Security error in searchAccounts: ' + e.getMessage());
            throw new AuraHandledException('Insufficient permissions to search accounts');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error in searchAccounts: ' + e.getMessage());
            throw new AuraHandledException('An unexpected error occurred while searching accounts');
        }
    }
    
    /**
     * @description Get detailed information about a specific account
     * Non-cacheable version for OpenAI function calling to ensure fresh data
     * 
     * @param accountId The ID of the account to retrieve
     * @return Account The account with its related contacts
     * @throws AuraHandledException if the account cannot be retrieved
     */
    @AuraEnabled
    public static Account getAccountDetails(Id accountId) {
        try {
            if (accountId == null) {
                throw new AuraHandledException('Account ID is required');
            }
            
            return [
                SELECT Id, Name, AnnualRevenue, Industry, 
                       Description, Website, Phone, 
                       BillingStreet, BillingCity, BillingState, 
                       BillingPostalCode, BillingCountry,
                       NumberOfEmployees, Type,
                       CreatedDate, LastModifiedDate,
                       Rating, AccountSource,
                       (SELECT Id, FirstName, LastName, Email, Phone 
                        FROM Contacts 
                        LIMIT :MAX_CONTACTS_PER_ACCOUNT)
                FROM Account 
                WHERE Id = :accountId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (System.QueryException e) {
            System.debug(LoggingLevel.ERROR, 'Query error in getAccountDetails: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving account details: ' + e.getMessage());
        } catch (System.SecurityException e) {
            System.debug(LoggingLevel.ERROR, 'Security error in getAccountDetails: ' + e.getMessage());
            throw new AuraHandledException('Insufficient permissions to access account details');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error in getAccountDetails: ' + e.getMessage());
            throw new AuraHandledException('An unexpected error occurred while retrieving account details');
        }
    }
    
    
    
}