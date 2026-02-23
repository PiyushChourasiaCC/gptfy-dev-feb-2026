/**
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIExchangeEmailController {

    public static final String NAMESAPCE = AIConstants.NAMESPACE;

    /**
     * Retrieves emails from configured email provider (Microsoft Graph by default)
     * @param recordLimit - Number of emails to retrieve (max 100)
     * @param offset - Pagination offset (for offset-based pagination)
     * @param filterCriteria - OData filter string
     * @param providerType - Optional provider type (defaults to MICROSOFT_GRAPH)
     * @param pageToken - Optional page token for cursor-based pagination (Gmail)
     * @return Map containing emails array, total count, hasMore flag, and nextPageToken
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getExchangeEmails(
        Integer recordLimit,
        Integer offset,
        String filterCriteria,
        String searchTerm,
        String providerType,
        String pageToken
    ) {
        try {
            // Validate inputs
            if (recordLimit == null || recordLimit < 1) recordLimit = 50;
            if (recordLimit > 100) recordLimit = 100;
            if (offset == null || offset < 0) offset = 0;

            // Get provider instance
            AIEmailProviderService provider = String.isNotBlank(providerType) ?
                AIEmailProviderFactory.getProvider(providerType) :
                AIEmailProviderFactory.getDefaultProvider();

            // Build request
            AIEmailProviderService.EmailProviderRequest request =
                new AIEmailProviderService.EmailProviderRequest();
            request.recordLimit = recordLimit;
            request.offset = offset;
            request.filterCriteria = filterCriteria;
            request.searchTerm = searchTerm;
            request.providerType = providerType;
            request.pageToken = pageToken;

            // Call provider
            AIEmailProviderService.EmailProviderResponse providerResponse =
                provider.getEmails(request);

            List<Map<String, Object>> emails = providerResponse.emails;

            // Enrich emails with associations using provider-agnostic service
            if (emails != null && !emails.isEmpty()) {
                emails = AIEmailAssociationService.enrichEmailsWithAssociations(emails);
            }

            return new Map<String, Object>{
                'success' => true,
                'emails' => emails,
                'totalCount' => providerResponse.totalCount,
                'hasMore' => providerResponse.hasMore,
                'nextPageToken' => providerResponse.nextPageToken
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage(),
                'errorType' => e.getTypeName()
            };
        }
    }
    
    /**
     * Imports selected emails into Salesforce as EmailMessage records
     * @param messageIds - List of provider message IDs
     * @param parentRecordId - ID of parent Salesforce record
     * @param providerType - Optional provider type (defaults to MICROSOFT_GRAPH)
     * @return Map with success/failed counts and error messages
     */
    @AuraEnabled
    public static Map<String, Object> importSelectedEmails(
        List<String> messageIds,
        Id parentRecordId,
        String providerType
    ) {
        try {
            // Validate inputs
            if (messageIds == null || messageIds.isEmpty()) {
                throw new IllegalArgumentException('No emails selected for import');
            }

            if (parentRecordId == null) {
                throw new IllegalArgumentException('Parent record ID is required');
            }

            // Get provider instance
            AIEmailProviderService provider = String.isNotBlank(providerType) ?
                AIEmailProviderFactory.getProvider(providerType) :
                AIEmailProviderFactory.getDefaultProvider();

            // Fetch full email data from provider using BATCH API
            // This reduces callouts from N to ceil(N/batch_size), respecting governor limits
            List<Map<String, Object>> emailDataList = provider.getEmailsBatch(messageIds);

            // Filter out nulls (failed fetches)
            List<Map<String, Object>> validEmailDataList = new List<Map<String, Object>>();
            for (Map<String, Object> emailData : emailDataList) {
                if (emailData != null) {
                    validEmailDataList.add(emailData);
                }
            }

            // Apply exclusion filters (marketing, confidential, internal)
            String userEmail = provider.getUserEmail();
            AIEmailExclusionService.BatchExclusionResult exclusionResult =
                AIEmailExclusionService.filterBatch(validEmailDataList, providerType, userEmail);

            // Use only non-excluded emails
            validEmailDataList = exclusionResult.includedEmails;
            Integer excludedCount = exclusionResult.excludedEmails.size();

            // If all emails were excluded, return early with exclusion info
            if (validEmailDataList.isEmpty() && excludedCount > 0) {
                List<String> exclusionErrors = new List<String>();
                Map<String, Integer> exclusionCounts = exclusionResult.exclusionCounts;
                for (String category : exclusionCounts.keySet()) {
                    Integer count = exclusionCounts.get(category);
                    if (count > 0) {
                        exclusionErrors.add(count + ' ' + category.toLowerCase() + ' email(s) excluded by filter settings');
                    }
                }
                return new Map<String, Object>{
                    'success' => true,
                    'successCount' => 0,
                    'failedCount' => 0,
                    'duplicateCount' => 0,
                    'excludedCount' => excludedCount,
                    'errors' => exclusionErrors
                };
            }

            // Create staging records (users link manually later)
            AIWorkspaceStagingCreator.StagingResult stagingResult =
                AIWorkspaceStagingCreator.createEmailStagingRecords(
                    validEmailDataList,
                    providerType,
                    userEmail,
                    null  // No sync log for manual imports
                );
            
            Integer successCount = stagingResult.successCount;
            Integer failedCount = stagingResult.failedCount;
            Integer duplicateCount = stagingResult.duplicateCount;
            List<String> errors = stagingResult.errors;

            // Add exclusion info to errors for UI visibility
            if (excludedCount > 0) {
                Map<String, Integer> exclusionCounts = exclusionResult.exclusionCounts;
                for (String category : exclusionCounts.keySet()) {
                    Integer count = exclusionCounts.get(category);
                    if (count > 0) {
                        errors.add(count + ' ' + category.toLowerCase() + ' email(s) excluded by filter settings');
                    }
                }
            }
            
            // Send notifications for successfully imported emails
            if (!stagingResult.stagingRecordIds.isEmpty()) {
                sendEmailImportNotifications(stagingResult.stagingRecordIds);
            }

            return new Map<String, Object>{
                'success' => true,
                'successCount' => successCount,
                'failedCount' => failedCount,
                'duplicateCount' => duplicateCount,
                'excludedCount' => excludedCount,
                'errors' => errors
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage(),
                'successCount' => 0,
                'failedCount' => messageIds != null ? messageIds.size() : 0
            };
        }
    }
    
    /**
     * Checks if user is authenticated with the configured email provider
     * @param providerType - Optional provider type (defaults to MICROSOFT_GRAPH)
     * @return Boolean indicating authentication status
     */
    @AuraEnabled
    public static Boolean checkAuthenticationStatus(String providerType) {
        try {
            AIEmailProviderService provider = String.isNotBlank(providerType) ?
                AIEmailProviderFactory.getProvider(providerType) :
                AIEmailProviderFactory.getDefaultProvider();

            return provider.isAuthenticated();

        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Gets authentication details including user email address
     * Auto-detects provider if not specified
     * 
     * Uses AI_Workspace_User__c to detect authenticated providers and
     * AI_Workspace_Sync_Settings__c to check enabled providers.
     * 
     * @param providerType - Optional provider type
     * @return Map with isAuthenticated, userEmail, and providerType
     */
    @AuraEnabled
    public static Map<String, Object> getAuthenticationDetails(String providerType) {
        try {
            AIEmailProviderService provider;
            String detectedProviderType = providerType;

            // If no provider specified, try to auto-detect
            if (String.isBlank(providerType)) {
                Id currentUserId = UserInfo.getUserId();
                
                // Get providers that are both authenticated and enabled
                List<String> activeProviders = AIEmailProviderFactory.getActiveAuthenticatedProviders(currentUserId);
                
                for (String activeProviderType : activeProviders) {
                    try {
                        AIEmailProviderService p = AIEmailProviderFactory.getProvider(activeProviderType);
                        Boolean isAuth = p.isAuthenticated();
            
                        if (isAuth) {
                            String userEmail = p.getUserEmail();
                            
                            provider = p;
                            // Map to sync provider type (Outlook -> MICROSOFT_EMAIL, Gmail -> GMAIL_EMAIL)
                            detectedProviderType = activeProviderType == 'Outlook' ? 'MICROSOFT_EMAIL' : 'GMAIL_EMAIL';
                            break; // Found an authenticated provider
                        }
                    } catch (Exception e) {
                        continue;
                    }
                }
                
                // If still no provider found, fallback to default
                if (provider == null) {
                    provider = AIEmailProviderFactory.getDefaultProvider();
                    detectedProviderType = 'MICROSOFT_GRAPH';
                }
            } else {
                provider = AIEmailProviderFactory.getProvider(providerType);
            }

            Boolean isAuth = provider.isAuthenticated();
            String userEmail = isAuth ? provider.getUserEmail() : '';

            return new Map<String, Object>{
                'success' => true,
                'isAuthenticated' => isAuth,
                'userEmail' => userEmail,
                'providerType' => detectedProviderType,
                'namespace' => AIPromptController.getNameSpace()
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'isAuthenticated' => false,
                'userEmail' => '',
                'error' => e.getMessage(),
                'namespace' => AIPromptController.getNameSpace()
            };
        }
    }

    /**
     * Refreshes the access token and returns authentication details.
     * Call this method when the page loads to ensure a fresh token before any API calls.
     * This handles token refresh (DML) BEFORE any callouts happen.
     * 
     * @param providerType - Provider type: 'MICROSOFT_GRAPH', 'MICROSOFT_EMAIL', 'GMAIL', or 'GMAIL_EMAIL'
     * @return Map with isAuthenticated, userEmail, providerType, and any errors
     */
    @AuraEnabled
    public static Map<String, Object> refreshTokenAndGetDetails(String providerType) {
        try {
            // Convert provider type to AIWorkspaceTokenService format
            // Handle all provider type formats: GMAIL, GMAIL_EMAIL -> Gmail; MICROSOFT_GRAPH, MICROSOFT_EMAIL -> Outlook
            String normalizedType = String.isNotBlank(providerType) ? providerType.toUpperCase() : '';
            String provider = (normalizedType == 'GMAIL' || normalizedType == 'GMAIL_EMAIL') ? 'Gmail' : 'Outlook';
            
            // Check if user has a connection
            if (!AIWorkspaceTokenService.hasConnection(provider)) {
                return new Map<String, Object>{
                    'success' => true,
                    'isAuthenticated' => false,
                    'userEmail' => '',
                    'providerType' => providerType,
                    'namespace' => AIPromptController.getNameSpace(),
                    'refreshed' => false,
                    'message' => 'No connection found for ' + provider
                };
            }
            
            // Attempt to refresh the token (this does callout + DML)
            String accessToken;
            try {
                accessToken = AIWorkspaceTokenService.refreshAndGetToken(provider);
            } catch (AIWorkspaceTokenService.AuthenticationException e) {
                // Token refresh failed - user needs to re-authenticate
                return new Map<String, Object>{
                    'success' => true,
                    'isAuthenticated' => false,
                    'userEmail' => '',
                    'providerType' => providerType,
                    'namespace' => AIPromptController.getNameSpace(),
                    'refreshed' => false,
                    'message' => e.getMessage()
                };
            }
            
            // Token refreshed successfully - we assume access is available
            // IMPORTANT: We cannot call getUserEmail() here because:
            // 1. refreshAndGetToken() does callout + DML (saves refreshed token)
            // 2. Calling getUserEmail() would be another callout after DML
            // 3. This causes "You have uncommitted work pending" error
            // 
            // Since the token refresh succeeded, we assume the user has valid credentials.
            // The user email will be fetched on the next request (after this transaction commits).
            return new Map<String, Object>{
                'success' => true,
                'isAuthenticated' => true,
                'userEmail' => '', // Will be fetched separately
                'providerType' => providerType,
                'namespace' => AIPromptController.getNameSpace(),
                'refreshed' => true,
                'message' => 'Token refreshed successfully'
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'isAuthenticated' => false,
                'userEmail' => '',
                'error' => e.getMessage(),
                'namespace' => AIPromptController.getNameSpace(),
                'refreshed' => false
            };
        }
    }

    /**
     * Initiates OAuth authentication flow
     * @return URL for user to complete authentication
     */
    @AuraEnabled
    public static String initiateAuthentication() {
        // This would redirect user to OAuth consent page
        // Implementation depends on Named Credential configuration
        // For now, return instruction message
        return 'Please contact your administrator to configure Microsoft Exchange authentication.';
    }

    /**
     * Find smart matches for a given email
     * @param senderEmail - Sender's email address
     * @param senderName - Sender's display name
     * @param subject - Email subject
     * @param connectedAccountEmail - Optional email address of the connected provider account to exclude from matching
     * @return List of MatchResult objects
     */
    @AuraEnabled(cacheable=true)
    public static List<AISmartMatchingEngine.MatchResult> getSmartMatches(
        String senderEmail,
        String senderName,
        String subject,
        String connectedAccountEmail
    ) {
        try {
            return AISmartMatchingEngine.findMatches(senderEmail, senderName, subject, connectedAccountEmail);
        } catch (Exception e) {
            return new List<AISmartMatchingEngine.MatchResult>();
        }
    }

    /**
     * Auto-match emails using 2-phase approach
     * Phase 1: Quick logical matching (synchronous) - THIS METHOD
     * Phase 2: AI enhancement (asynchronous) - scheduled after this completes
     *
     * @param messageIds - List of provider message IDs to sync
     * @param contextRecordId - Current record context for fallback matching
     * @param providerType - Email provider type (MICROSOFT_GRAPH, GMAIL, etc.)
     * @return Map with match results and sync status
     */
    @AuraEnabled
    public static Map<String, Object> autoMatch(
        List<String> messageIds,
        Id contextRecordId,
        String providerType
    ) {
        try {
            // Validate inputs
            if (messageIds == null || messageIds.isEmpty()) {
                throw new IllegalArgumentException('No emails selected for matching');
            }

            // Enforce 20-email limit for optimal performance
            if (messageIds.size() > 20) {
                throw new IllegalArgumentException(
                    'Please select 20 or fewer emails per sync. You have ' + messageIds.size() +
                    ' selected. You can run multiple syncs if needed.'
                );
            }

            // Get provider instance (works with Gmail or Exchange)
            AIEmailProviderService provider = String.isNotBlank(providerType) ?
                AIEmailProviderFactory.getProvider(providerType) :
                AIEmailProviderFactory.getDefaultProvider();

            // Fetch full email data from provider using BATCH API
            // This reduces callouts from N to ceil(N/batch_size), respecting governor limits
            List<Map<String, Object>> batchResults = provider.getEmailsBatch(messageIds);

            // Filter out nulls (failed fetches)
            List<Map<String, Object>> emailDataList = new List<Map<String, Object>>();
            for (Map<String, Object> emailData : batchResults) {
                if (emailData != null) {
                    emailDataList.add(emailData);
                }
            }

            if (emailDataList.isEmpty()) {
                throw new IllegalArgumentException('Could not fetch any emails from provider');
            }

            // Apply exclusion filters (marketing, confidential, internal)
            String userEmail = provider.getUserEmail();
            AIEmailExclusionService.BatchExclusionResult exclusionResult =
                AIEmailExclusionService.filterBatch(emailDataList, providerType, userEmail);

            // Use only non-excluded emails
            emailDataList = exclusionResult.includedEmails;
            Integer excludedByFilterCount = exclusionResult.excludedEmails.size();

            // If all emails were excluded, return early with exclusion info
            if (emailDataList.isEmpty() && excludedByFilterCount > 0) {
                List<String> exclusionErrors = new List<String>();
                Map<String, Integer> exclusionCounts = exclusionResult.exclusionCounts;
                for (String category : exclusionCounts.keySet()) {
                    Integer count = exclusionCounts.get(category);
                    if (count > 0) {
                        exclusionErrors.add(count + ' ' + category.toLowerCase() + ' email(s) excluded by filter settings');
                    }
                }
                return new Map<String, Object>{
                    'success' => true,
                    'totalEmails' => excludedByFilterCount,
                    'successCount' => 0,
                    'failedCount' => 0,
                    'duplicateCount' => 0,
                    'excludedCount' => excludedByFilterCount,
                    'unmatchedCount' => 0,
                    'matchResults' => new List<Object>(),
                    'matchType' => 'Staging',
                    'errors' => exclusionErrors
                };
            }

            // Create staging records for ALL emails (no matching - users link manually later)
            AIWorkspaceStagingCreator.StagingResult stagingResult =
                AIWorkspaceStagingCreator.createEmailStagingRecords(
                    emailDataList,
                    providerType,
                    userEmail,
                    null  // No sync log for manual imports
                );

            Integer successCount = stagingResult.successCount;
            Integer failedCount = stagingResult.failedCount;
            Integer duplicateCount = stagingResult.duplicateCount;
            List<String> importErrors = stagingResult.errors;
            List<Id> createdRecordIds = stagingResult.stagingRecordIds;

            // Build response with exclusion info if any
            List<String> allErrors = new List<String>(importErrors);

            // Add exclusion info to errors for UI visibility
            if (excludedByFilterCount > 0) {
                Map<String, Integer> exclusionCounts = exclusionResult.exclusionCounts;
                for (String category : exclusionCounts.keySet()) {
                    Integer count = exclusionCounts.get(category);
                    if (count > 0) {
                        allErrors.add(count + ' ' + category.toLowerCase() + ' email(s) excluded by filter settings');
                    }
                }
            }

            return new Map<String, Object>{
                'success' => true,
                'totalEmails' => emailDataList.size() + excludedByFilterCount,
                'successCount' => successCount,
                'failedCount' => failedCount,
                'duplicateCount' => duplicateCount,
                'excludedCount' => excludedByFilterCount,
                'unmatchedCount' => 0,  // No matching in staging approach
                'matchResults' => new List<Object>(),  // No match results in staging approach
                'matchType' => 'Staging',
                'stagingRecordIds' => createdRecordIds,
                'errors' => allErrors
            };

        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage(),
                'totalEmails' => messageIds != null ? messageIds.size() : 0,
                'successCount' => 0,
                'failedCount' => messageIds != null ? messageIds.size() : 0
            };
        }
    }

    /**
     * @deprecated Use autoMatch() instead which now creates staging records.
     *
     * DEPRECATED - Old AI-based sync method (redirects to autoMatch for backwards compatibility)
     * Auto-sync emails with AI-powered matching
     * @param messageIds - List of provider message IDs to sync
     * @param contextRecordId - Optional context record (Account, Contact, etc.)
     * @param providerType - Email provider type
     * @return Map with match results and sync status
     */
    @AuraEnabled
    public static Map<String, Object> autoSyncWithAI(
        List<String> messageIds,
        Id contextRecordId,
        String providerType
    ) {
        // Redirect to autoMatch which now creates staging records
        return autoMatch(messageIds, contextRecordId, providerType);
    }

    /**
     * @deprecated This method uses EmailMatchingService which has SOQL-in-loop issues.
     * Consider using AIQuickMatchService.matchBatch() for previewing matches.
     *
     * Preview AI matches for a single email (without creating records)
     * @param messageId - Provider message ID
     * @param contextRecordId - Optional context record
     * @param providerType - Email provider type
     * @return Match result for preview
     */
    @AuraEnabled
    public static AIEmailMatchingService.MatchResult previewAIMatch(
        String messageId,
        Id contextRecordId,
        String providerType
    ) {
        try {
            // Get provider instance
            AIEmailProviderService provider = String.isNotBlank(providerType) ?
                AIEmailProviderFactory.getProvider(providerType) :
                AIEmailProviderFactory.getDefaultProvider();

            // Fetch email data
            Map<String, Object> emailData = provider.getSingleEmail(messageId);

            if (emailData == null) {
                throw new AIEmailMatchingService.EmailMatchingException(
                    'Could not fetch email from provider'
                );
            }

            // Match email
            return AIEmailMatchingService.matchEmail(emailData, contextRecordId);

        } catch (Exception e) {
            throw new AuraHandledException('Preview failed: ' + e.getMessage());
        }
    }
    

    /**
     * Search for Contacts and Leads by name or email
     * Used in Quick Match modal for search functionality
     * @param searchTerm - The search query (minimum 2 characters)
     * @return List of search results with recordId, recordName, objectType, email
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> searchContactAndLead(String searchTerm) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return results;
        }
        
        String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        
        try {
            // Search Contacts
            for (Contact c : [
                SELECT Id, Name, Email, Account.Name
                FROM Contact
                WHERE (Name LIKE :searchPattern OR Email LIKE :searchPattern)
                WITH USER_MODE
                LIMIT 5
            ]) {
                results.add(new Map<String, Object>{
                    'recordId' => c.Id,
                    'recordName' => c.Name,
                    'objectType' => 'Contact',
                    'email' => c.Email,
                    'details' => c.Account != null ? c.Account.Name : ''
                });
            }
            
            // Search Leads
            for (Lead l : [
                SELECT Id, Name, Email, Company
                FROM Lead
                WHERE (Name LIKE :searchPattern OR Email LIKE :searchPattern)
                AND IsConverted = false
                WITH USER_MODE
                LIMIT 5
            ]) {
                results.add(new Map<String, Object>{
                    'recordId' => l.Id,
                    'recordName' => l.Name,
                    'objectType' => 'Lead',
                    'email' => l.Email,
                    'details' => l.Company != null ? l.Company : ''
                });
            }
            
        } catch (Exception e) {
            // Error occurred during search
        }
        
        return results;
    }

    /**
     * Get all Accounts associated with the given Contact IDs
     * Includes primary Account (Contact.AccountId) and secondary Accounts (AccountContactRelation)
     * @param contactIds - List of Contact IDs
     * @return List of Account options for combobox (value, label)
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAccountsForContacts(List<Id> contactIds) {
        List<Map<String, String>> accountOptions = new List<Map<String, String>>();
        Set<Id> accountIds = new Set<Id>();
        Map<Id, String> accountIdToName = new Map<Id, String>();
        List<Id> primaryAccountIds = new List<Id>(); // Track order for primary accounts
        
        if (contactIds == null || contactIds.isEmpty()) {
            return accountOptions;
        }
        
        try {
            // Query primary Accounts from Contact.AccountId
            for (Contact c : [
                SELECT Id, AccountId, Account.Name
                FROM Contact
                WHERE Id IN :contactIds
                AND AccountId != null
                WITH USER_MODE
            ]) {
                if (c.AccountId != null && !accountIds.contains(c.AccountId)) {
                    accountIds.add(c.AccountId);
                    accountIdToName.put(c.AccountId, c.Account.Name);
                    primaryAccountIds.add(c.AccountId);
                }
            }
            
            // Query secondary Accounts from AccountContactRelation (if org has multi-account enabled)
            if (Schema.getGlobalDescribe().containsKey('AccountContactRelation')) {
                List<SObject> acrRecords = Database.query(
                    'SELECT AccountId, Account.Name FROM AccountContactRelation ' +
                    'WHERE ContactId IN :contactIds AND AccountId != null WITH USER_MODE'
                );
                
                for (SObject acr : acrRecords) {
                    Id accountId = (Id) acr.get('AccountId');
                    SObject account = (SObject) acr.getSObject('Account');
                    String accountName = (String) account.get('Name');
                    
                    if (!accountIds.contains(accountId)) {
                        accountIds.add(accountId);
                        accountIdToName.put(accountId, accountName);
                    }
                }
            }
            
            // Build results: primary accounts first, then secondary
            for (Id accId : primaryAccountIds) {
                accountOptions.add(new Map<String, String>{
                    'value' => accId,
                    'label' => accountIdToName.get(accId)
                });
            }
            
            // Add remaining secondary accounts
            for (Id accId : accountIds) {
                if (!primaryAccountIds.contains(accId)) {
                    accountOptions.add(new Map<String, String>{
                        'value' => accId,
                        'label' => accountIdToName.get(accId)
                    });
                }
            }
            
        } catch (Exception e) {
            // Error occurred during query
        }
        
        return accountOptions;
    }

    /**
     * Get Opportunities for the given Account, sorted by CreatedDate descending
     * @param accountId - Account ID
     * @return List of Opportunity options for combobox (value, label)
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getOpportunitiesForAccount(Id accountId) {
        List<Map<String, String>> oppOptions = new List<Map<String, String>>();
        
        if (accountId == null) {
            return oppOptions;
        }
        
        try {
            for (Opportunity opp : [
                SELECT Id, Name, StageName, CloseDate
                FROM Opportunity
                WHERE AccountId = :accountId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 50
            ]) {
                String label = opp.Name;
                if (opp.StageName != null) {
                    label += ' (' + opp.StageName + ')';
                }
                
                oppOptions.add(new Map<String, String>{
                    'value' => opp.Id,
                    'label' => label
                });
            }
        } catch (Exception e) {
            // Error occurred during query
        }
        
        return oppOptions;
    }

    /**
     * Associate selected emails with user-chosen Contact/Lead/Account/Opportunity
     * Creates staging records for audit trail, then creates EmailMessage and EmailMessageRelation records
     * @param selections - List of { messageId, contactIds, leadIds, accountId, opportunityId }
     * @param providerType - Email provider type
     * @return Map with success status, counts, and errors
     */
    @AuraEnabled
    public static Map<String, Object> associateEmailsFromModal(
        List<Map<String, Object>> selections,
        String providerType
    ) {
        Map<String, Object> result = new Map<String, Object>{
            'success' => true,
            'successCount' => 0,
            'failedCount' => 0,
            'duplicateCount' => 0,
            'excludedCount' => 0,
            'errors' => new List<String>()
        };
        
        //try {
            if (selections == null || selections.isEmpty()) {
                throw new IllegalArgumentException('No selections provided');
            }
            
            // Check CRUD permissions for EmailMessage
            if (!Schema.sObjectType.EmailMessage.isCreateable()) {
                result.put('success', false);
                result.put('failedCount', selections.size());
                ((List<String>) result.get('errors')).add('Insufficient permissions to create EmailMessage records');
                return result;
            }
            
            // Get Email record type ID
            Id emailRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
                .getRecordTypeInfosByDeveloperName()
                .get('Email')
                .getRecordTypeId();
            
            // Extract message IDs
            List<String> messageIds = new List<String>();
            for (Map<String, Object> selection : selections) {
                messageIds.add((String) selection.get('messageId'));
            }
            
            // Get provider instance
            AIEmailProviderService provider = String.isNotBlank(providerType) ?
                AIEmailProviderFactory.getProvider(providerType) :
                AIEmailProviderFactory.getDefaultProvider();
            
            // Fetch full email data from provider
            List<Map<String, Object>> emailDataList = provider.getEmailsBatch(messageIds);
            
            // Filter out nulls
            List<Map<String, Object>> validEmailDataList = new List<Map<String, Object>>();
            for (Map<String, Object> emailData : emailDataList) {
                if (emailData != null) {
                    validEmailDataList.add(emailData);
                }
            }
            
            if (validEmailDataList.isEmpty()) {
                throw new IllegalArgumentException('Could not fetch emails from provider');
            }
            
            // Apply exclusion filters
            String userEmail = provider.getUserEmail();
            AIEmailExclusionService.BatchExclusionResult exclusionResult =
                AIEmailExclusionService.filterBatch(validEmailDataList, providerType, userEmail);
            
            validEmailDataList = exclusionResult.includedEmails;
            Integer excludedCount = exclusionResult.excludedEmails.size();
            
            // Map email data by message ID for lookup (use provider ID, not internetMessageId)
            Map<String, Map<String, Object>> messageIdToEmailData = new Map<String, Map<String, Object>>();
            Map<String, Map<String, Object>> messageIdToSelection = new Map<String, Map<String, Object>>();
            for (Map<String, Object> emailData : validEmailDataList) {
                String providerId = (String) emailData.get('id');
                if (String.isNotBlank(providerId)) {
                    messageIdToEmailData.put(providerId, emailData);
                }
            }
            for (Map<String, Object> selection : selections) {
                messageIdToSelection.put((String) selection.get('messageId'), selection);
            }
            
            // STEP 1: Create staging records for audit trail
            List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
            Map<Integer, Map<String, Object>> indexToEmailData = new Map<Integer, Map<String, Object>>();
            Map<Integer, Map<String, Object>> indexToSelection = new Map<Integer, Map<String, Object>>();
            
            for (Map<String, Object> emailData : validEmailDataList) {
                String providerId = (String) emailData.get('id');
                Map<String, Object> selection = messageIdToSelection.get(providerId);
                
                if (selection == null) {
                    continue;
                }
                
                AI_Workspace_Staging__c staging = createStagingRecordFromEmail(
                    emailData,
                    emailRecordTypeId,
                    providerType,
                    userEmail
                );
                
                Integer idx = stagingRecords.size();
                stagingRecords.add(staging);
                indexToEmailData.put(idx, emailData);
                indexToSelection.put(idx, selection);
            }
            
            // Insert staging records with FLS enforcement
            Map<Integer, Id> indexToStagingId = new Map<Integer, Id>();
            if (!stagingRecords.isEmpty()) {
                // Check object-level create permission
                if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
                    result.put('success', false);
                    ((List<String>) result.get('errors')).add('Insufficient permissions to create AI Workspace Staging records');
                    result.put('failedCount', stagingRecords.size());
                    return result;
                }
                
                // Strip inaccessible fields for FLS enforcement
                SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.CREATABLE, stagingRecords);
                List<AI_Workspace_Staging__c> accessibleRecords = securityDecision.getRecords();
                
                Database.SaveResult[] stagingResults = Database.insert(accessibleRecords, false);
                for (Integer i = 0; i < stagingResults.size(); i++) {
                    if (stagingResults[i].isSuccess()) {
                        indexToStagingId.put(i, stagingResults[i].getId());
                    } else {
                        // Capture staging insert errors
                        result.put('failedCount', (Integer) result.get('failedCount') + 1);
                        for (Database.Error err : stagingResults[i].getErrors()) {
                            ((List<String>) result.get('errors')).add('Staging record creation failed: ' + err.getMessage());
                        }
                    }
                }
            }
            
            // STEP 2: Create EmailMessage records with user selections
            List<EmailMessage> emailMessagesToInsert = new List<EmailMessage>();
            Map<Integer, Integer> emailIndexToStagingIndex = new Map<Integer, Integer>();
            
            for (Integer stagingIdx : indexToStagingId.keySet()) {
                Map<String, Object> emailData = indexToEmailData.get(stagingIdx);
                Map<String, Object> selection = indexToSelection.get(stagingIdx);
                
                EmailMessage em = createEmailMessageFromData(emailData, selection, providerType);
                
                Integer emailIdx = emailMessagesToInsert.size();
                emailMessagesToInsert.add(em);
                emailIndexToStagingIndex.put(emailIdx, stagingIdx);
            }
            
            // Insert EmailMessage records with FLS enforcement
            Map<Integer, Id> emailIndexToEmailMessageId = new Map<Integer, Id>();
            if (!emailMessagesToInsert.isEmpty()) {
                // Check object-level create permission
                if (!Schema.sObjectType.EmailMessage.isCreateable()) {
                    result.put('success', false);
                    ((List<String>) result.get('errors')).add('Insufficient permissions to create EmailMessage records');
                    result.put('failedCount', emailMessagesToInsert.size());
                    return result;
                }
                
                // Strip inaccessible fields for FLS enforcement
                SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.CREATABLE, emailMessagesToInsert);
                List<EmailMessage> accessibleEmails = securityDecision.getRecords();
                
                Database.SaveResult[] insertResults = Database.insert(accessibleEmails, false);
                
                for (Integer i = 0; i < insertResults.size(); i++) {
                    if (insertResults[i].isSuccess()) {
                        emailIndexToEmailMessageId.put(i, insertResults[i].getId());
                        result.put('successCount', (Integer) result.get('successCount') + 1);
                    } else {
                        result.put('failedCount', (Integer) result.get('failedCount') + 1);
                        for (Database.Error err : insertResults[i].getErrors()) {
                            String errorMsg = 'EmailMessage insert failed: ' + err.getMessage() + ' | Fields: ' + err.getFields();
                            ((List<String>) result.get('errors')).add(errorMsg);
                        }
                    }
                }
            }
            
            // STEP 3: Create EmailMessageRelation records
            List<EmailMessageRelation> relations = new List<EmailMessageRelation>();
            for (Integer emailIdx : emailIndexToEmailMessageId.keySet()) {
                Id emailMessageId = emailIndexToEmailMessageId.get(emailIdx);
                Integer stagingIdx = emailIndexToStagingIndex.get(emailIdx);
                Map<String, Object> selection = indexToSelection.get(stagingIdx);
                
                // Add Contact relations
                List<Object> contactIdsList = (List<Object>) selection.get('contactIds');
                if (contactIdsList != null) {
                    for (Object contactIdObj : contactIdsList) {
                        EmailMessageRelation emr = new EmailMessageRelation();
                        emr.EmailMessageId = emailMessageId;
                        emr.RelationId = (Id) contactIdObj;
                        emr.RelationType = 'OtherAddress';
                        relations.add(emr);
                    }
                }
                
                // Add Lead relations
                List<Object> leadIdsList = (List<Object>) selection.get('leadIds');
                if (leadIdsList != null) {
                    for (Object leadIdObj : leadIdsList) {
                        EmailMessageRelation emr = new EmailMessageRelation();
                        emr.EmailMessageId = emailMessageId;
                        emr.RelationId = (Id) leadIdObj;
                        emr.RelationType = 'OtherAddress';
                        relations.add(emr);
                    }
                }
            }
            
            // Insert relations with FLS enforcement
            if (!relations.isEmpty()) {
                // Check object-level create permission
                if (Schema.sObjectType.EmailMessageRelation.isCreateable()) {
                    // Strip inaccessible fields for FLS enforcement
                    SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.CREATABLE, relations);
                    List<EmailMessageRelation> accessibleRelations = securityDecision.getRecords();
                    
                    Database.insert(accessibleRelations, false);
                }
            }
            
            // STEP 4: Update staging records to mark as Processed
            List<AI_Workspace_Staging__c> stagingToUpdate = new List<AI_Workspace_Staging__c>();
            for (Integer emailIdx : emailIndexToEmailMessageId.keySet()) {
                Integer stagingIdx = emailIndexToStagingIndex.get(emailIdx);
                Id stagingId = indexToStagingId.get(stagingIdx);
                Id emailMessageId = emailIndexToEmailMessageId.get(emailIdx);
                
                if (stagingId != null && emailMessageId != null) {
                    AI_Workspace_Staging__c updateRecord = new AI_Workspace_Staging__c(Id = stagingId);
                    updateRecord.Status__c = 'Matched';
                    updateRecord.Email_Message__c = String.valueOf(emailMessageId);
                    stagingToUpdate.add(updateRecord);
                }
            }
            
            if (!stagingToUpdate.isEmpty()) {
                // Check object-level update permission
                if (Schema.sObjectType.AI_Workspace_Staging__c.isUpdateable()) {
                    // Strip inaccessible fields for FLS enforcement
                    SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPDATABLE, stagingToUpdate);
                    List<AI_Workspace_Staging__c> accessibleRecords = securityDecision.getRecords();
                    
                    Database.update(accessibleRecords, false);
                }
            }
            
            // Send notifications for imported emails
            sendEmailImportNotificationsFromModal(emailIndexToEmailMessageId, indexToEmailData, emailIndexToStagingIndex);
            
            // Add exclusion info to result
            result.put('excludedCount', excludedCount);
            if (excludedCount > 0) {
                ((List<String>) result.get('errors')).add(
                    excludedCount + ' email(s) excluded by filter settings'
                );
            }

        
        return result;
    }
    
    /**
     * Helper: Create staging record from email data
     */
    private static AI_Workspace_Staging__c createStagingRecordFromEmail(
        Map<String, Object> emailData,
        Id recordTypeId,
        String providerType,
        String userEmail
    ) {
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c();
        staging.RecordTypeId = recordTypeId;
        staging.Provider__c = providerType;
        staging.Provider_Id__c = (String) emailData.get('id');
        staging.Provider_Conversation_Id__c = (String) emailData.get('conversationId');
        staging.Message_Identifier__c = (String) emailData.get('internetMessageId');
        staging.User__c = UserInfo.getUserId();
        staging.Import_Date__c = DateTime.now();
        staging.Status__c = 'Pending'; // Will be updated to 'Matched' after processing
        
        // Subject
        staging.Subject__c = truncateString((String) emailData.get('subject'), 4000);
        
        // Body content
        Map<String, Object> body = (Map<String, Object>) emailData.get('body');
        if (body != null) {
            String bodyContent = (String) body.get('content');
            String contentType = (String) body.get('contentType');
            
            if (contentType == 'html') {
                staging.Html_Body__c = truncateString(bodyContent, 32000);
            } else {
                staging.Text_Body__c = truncateString(bodyContent, 32000);
            }
        }
        
        // From address
        Map<String, Object> fromObj = (Map<String, Object>) emailData.get('from');
        if (fromObj != null) {
            Map<String, Object> emailAddress = (Map<String, Object>) fromObj.get('emailAddress');
            if (emailAddress != null) {
                staging.From_Address__c = (String) emailAddress.get('address');
                staging.From_Name__c = truncateString((String) emailAddress.get('name'), 255);
            }
        }
        
        // To/Cc/Bcc addresses
        staging.To_Address__c = extractEmailAddresses(
            (List<Object>) emailData.get('toRecipients'), 4000
        );
        staging.Cc_Address__c = extractEmailAddresses(
            (List<Object>) emailData.get('ccRecipients'), 4000
        );
        staging.Bcc_Address__c = extractEmailAddresses(
            (List<Object>) emailData.get('bccRecipients'), 4000
        );
        
        // Message date
        staging.Message_Date__c = parseEmailDateTime(emailData.get('receivedDateTime'));
        
        // Determine if incoming (use the From_Address we already extracted)
        staging.Is_Incoming__c = isIncomingEmail(staging.From_Address__c, userEmail);
        
        // Importance
        String importance = (String) emailData.get('importance');
        if (String.isNotBlank(importance)) {
            staging.Importance__c = importance.capitalize();
        }
        
        // Has attachments
        staging.Has_Attachments__c = emailData.get('hasAttachments') == true;
        
        return staging;
    }
    
    /**
     * Helper: Extract email addresses from recipients list
     */
    private static String extractEmailAddresses(List<Object> recipients, Integer maxLength) {
        if (recipients == null || recipients.isEmpty()) {
            return null;
        }
        
        List<String> addresses = new List<String>();
        for (Object recipient : recipients) {
            Map<String, Object> recMap = (Map<String, Object>) recipient;
            Map<String, Object> emailAddr = (Map<String, Object>) recMap.get('emailAddress');
            if (emailAddr != null) {
                String addr = (String) emailAddr.get('address');
                if (String.isNotBlank(addr)) {
                    addresses.add(addr);
                }
            }
        }
        
        String result = String.join(addresses, '; ');
        return truncateString(result, maxLength);
    }
    
    /**
     * Helper: Check if email is incoming
     */
    private static Boolean isIncomingEmail(String sender, String userEmail) {
        if (String.isBlank(sender) || String.isBlank(userEmail)) {
            return true;
        }
        return !sender.equalsIgnoreCase(userEmail);
    }
    
    /**
     * Helper: Truncate string to max length
     */
    private static String truncateString(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    /**
     * Helper: Create EmailMessage from email data and user selection
     */
    private static EmailMessage createEmailMessageFromData(
        Map<String, Object> emailData,
        Map<String, Object> selection,
        String providerType
    ) {
        EmailMessage em = new EmailMessage();
        
        // Standard fields
        em.Subject = (String) emailData.get('subject');
        
        // Body content - check content type to set either HtmlBody or TextBody
        // Note: Both TextBody and HtmlBody have a 32,000 character limit
        Map<String, Object> body = (Map<String, Object>) emailData.get('body');
        if (body != null) {
            String bodyContent = (String) body.get('content');
            String contentType = (String) body.get('contentType');
            
            if (contentType == 'html') {
                em.HtmlBody = truncateString(bodyContent, 32000);
            } else {
                em.TextBody = truncateString(bodyContent, 32000);
            }
        } else {
            // Fallback to bodyPreview if full body not available
            em.TextBody = truncateString((String) emailData.get('bodyPreview'), 32000);
        }
        
        em.MessageDate = parseEmailDateTime(emailData.get('receivedDateTime'));
        em.MessageIdentifier = (String) emailData.get('internetMessageId');
        em.Incoming = true;
        em.Status = '3'; // Sent/Received
        
        // From address
        Map<String, Object> fromObj = (Map<String, Object>) emailData.get('from');
        if (fromObj != null) {
            Map<String, Object> emailAddress = (Map<String, Object>) fromObj.get('emailAddress');
            if (emailAddress != null) {
                em.FromAddress = (String) emailAddress.get('address');
                em.FromName = (String) emailAddress.get('name');
            }
        }
        
        // To address
        List<Object> toRecipients = (List<Object>) emailData.get('toRecipients');
        if (toRecipients != null && !toRecipients.isEmpty()) {
            List<String> toAddresses = new List<String>();
            for (Object recipient : toRecipients) {
                String emailAddr = extractEmailAddress(recipient);
                if (String.isNotBlank(emailAddr)) {
                    toAddresses.add(emailAddr);
                }
            }
            if (!toAddresses.isEmpty()) {
                em.ToAddress = String.join(toAddresses, ';');
            }
        }
        
        // CC address
        List<Object> ccRecipients = (List<Object>) emailData.get('ccRecipients');
        if (ccRecipients != null && !ccRecipients.isEmpty()) {
            List<String> ccAddresses = new List<String>();
            for (Object recipient : ccRecipients) {
                String emailAddr = extractEmailAddress(recipient);
                if (String.isNotBlank(emailAddr)) {
                    ccAddresses.add(emailAddr);
                }
            }
            if (!ccAddresses.isEmpty()) {
                em.CcAddress = String.join(ccAddresses, ';');
            }
        }
        
        // BCC address
        List<Object> bccRecipients = (List<Object>) emailData.get('bccRecipients');
        if (bccRecipients != null && !bccRecipients.isEmpty()) {
            List<String> bccAddresses = new List<String>();
            for (Object recipient : bccRecipients) {
                String emailAddr = extractEmailAddress(recipient);
                if (String.isNotBlank(emailAddr)) {
                    bccAddresses.add(emailAddr);
                }
            }
            if (!bccAddresses.isEmpty()) {
                em.BccAddress = String.join(bccAddresses, ';');
            }
        }
        
        // Set RelatedToId (Opportunity or Account)
        String opportunityId = (String) selection.get('opportunityId');
        String accountId = (String) selection.get('accountId');
        
        if (String.isNotBlank(opportunityId)) {
            em.RelatedToId = opportunityId;
        } else if (String.isNotBlank(accountId)) {
            em.RelatedToId = accountId;
        }
        
        // Custom field for provider tracking
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.EmailMessage.fields.getMap();
        if (fieldMap.containsKey(NAMESAPCE+'Email_Provider_Type__c') && 
            fieldMap.get(NAMESAPCE+'Email_Provider_Type__c').getDescribe().isCreateable()) {
            em.put(NAMESAPCE+'Email_Provider_Type__c', providerType);
        }
        
        return em;
    }
    
    /**
     * Helper: Parse email datetime from ISO 8601 format
     * Handles formats like "2026-01-28T04:07:16Z" or "2026-01-28T04:07:16.123Z"
     */
    private static DateTime parseEmailDateTime(Object dateTimeObj) {
        if (dateTimeObj == null) {
            return DateTime.now();
        }
        
        try {
            String dateTimeStr = String.valueOf(dateTimeObj);
            
            // Remove 'Z' if present (UTC indicator)
            if (dateTimeStr.endsWith('Z')) {
                dateTimeStr = dateTimeStr.substring(0, dateTimeStr.length() - 1);
            }
            
            // Replace 'T' with space for Salesforce DateTime.valueOf() format
            dateTimeStr = dateTimeStr.replace('T', ' ');
            
            // Remove milliseconds if present (e.g., ".123")
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substring(0, dateTimeStr.indexOf('.'));
            }
            
            return DateTime.valueOf(dateTimeStr);
        } catch (Exception e) {
            return DateTime.now();
        }
    }
    
    /**
     * Send notifications for imported emails
     * @param stagingRecordIds List of staging record IDs
     */
    private static void sendEmailImportNotifications(List<Id> stagingRecordIds) {
        if (stagingRecordIds.isEmpty()) {
            return;
        }
        
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                return;
            }
            
            CustomNotificationType notifType = notifTypes[0];
            
            // Query staging records with EmailMessage references and User__c for notification target
            List<AI_Workspace_Staging__c> stagingRecords = [
                SELECT Id, Subject__c, Email_Message__c, Status__c, User__c
                FROM AI_Workspace_Staging__c
                WHERE Id IN :stagingRecordIds
            ];
            
            // Send notifications for each staging record
            for (AI_Workspace_Staging__c staging : stagingRecords) {
                try {
                    // Determine target ID - use EmailMessage if available, otherwise staging record
                    Id targetId = staging.Id; // Default to staging record
                    
                    if (String.isNotBlank(staging.Email_Message__c)) {
                        try {
                            targetId = Id.valueOf(staging.Email_Message__c);
                        } catch (Exception e) {
                            // Invalid Email_Message__c, use staging record ID
                        }
                    }
                    
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    
                    // Truncate subject for title
                    String subject = staging.Subject__c != null ? staging.Subject__c : '(No Subject)';
                    String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
                    
                    notification.setTitle('✉️ Email imported: ' + truncatedSubject);
                    notification.setBody('Email imported successfully.\nClick to view the email.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(targetId);
                    
                    // Send to the staging record's owner (User__c), not the current running user
                    // This ensures notifications go to the correct user during scheduled syncs
                    Id recipientUserId = staging.User__c != null ? staging.User__c : UserInfo.getUserId();
                    notification.send(new Set<String>{recipientUserId});
                } catch (Exception e) {
                    // Notification send failed
                }
            }
        } catch (Exception e) {
            // Error sending notifications
        }
    }
    
    /**
     * Helper: Send notifications for emails imported from the modal
     * This directly uses the EmailMessage IDs from memory since they're already available
     * 
     * @param emailIndexToEmailMessageId Map of email index to EmailMessage ID
     * @param indexToEmailData Map of index to email data
     * @param emailIndexToStagingIndex Map of email index to staging index
     */
    private static void sendEmailImportNotificationsFromModal(
        Map<Integer, Id> emailIndexToEmailMessageId,
        Map<Integer, Map<String, Object>> indexToEmailData,
        Map<Integer, Integer> emailIndexToStagingIndex
    ) {
        if (emailIndexToEmailMessageId == null || emailIndexToEmailMessageId.isEmpty()) {
            return;
        }
        
        try {
            // Query for the Custom Notification Type
            String notifTypeName = AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE;
            
            List<CustomNotificationType> notifTypes = [
                SELECT Id, DeveloperName FROM CustomNotificationType
                WHERE DeveloperName = :notifTypeName
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                return;
            }
            
            CustomNotificationType notifType = notifTypes[0];
            
            // Send notifications for each successfully created EmailMessage
            for (Integer emailIdx : emailIndexToEmailMessageId.keySet()) {
                Id emailMessageId = emailIndexToEmailMessageId.get(emailIdx);
                Integer stagingIdx = emailIndexToStagingIndex.get(emailIdx);
                
                // Get subject from email data
                String subject = '(No Subject)';
                if (indexToEmailData != null && stagingIdx != null && indexToEmailData.containsKey(stagingIdx)) {
                    Map<String, Object> emailData = indexToEmailData.get(stagingIdx);
                    if (emailData != null && emailData.get('subject') != null) {
                        subject = (String) emailData.get('subject');
                    }
                }
                
                try {
                    String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
                    
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setTitle('✉️ Email imported: ' + truncatedSubject);
                    notification.setBody('Email imported successfully.\nClick to view the email.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(emailMessageId);
                    
                    Id recipientId = UserInfo.getUserId();
                    
                    notification.send(new Set<String>{recipientId});
                } catch (Exception e) {
                    // Notification send failed
                }
            }
        } catch (Exception e) {
            // Error sending notifications
        }
    }

    /**
     * Helper: Extract email address from recipient object
     * Handles both Microsoft Graph and Gmail API formats, and malformed data
     * 
     * @param recipient - Recipient object from email data
     * @return Clean email address or null
     */
    private static String extractEmailAddress(Object recipient) {
        if (recipient == null) {
            return null;
        }
        
        try {
            // Handle Map format (Microsoft Graph / Gmail standard format)
            if (recipient instanceof Map<String, Object>) {
                Map<String, Object> recMap = (Map<String, Object>) recipient;
                
                // Try standard emailAddress.address format (Microsoft Graph)
                Map<String, Object> emailAddr = (Map<String, Object>) recMap.get('emailAddress');
                if (emailAddr != null) {
                    String address = (String) emailAddr.get('address');
                    if (String.isNotBlank(address)) {
                        return cleanEmailAddress(address);
                    }
                }
                
                // Try direct 'email' field (Gmail alternative format)
                String email = (String) recMap.get('email');
                if (String.isNotBlank(email)) {
                    return cleanEmailAddress(email);
                }
                
                // Try direct 'address' field (alternative format)
                String address = (String) recMap.get('address');
                if (String.isNotBlank(address)) {
                    return cleanEmailAddress(address);
                }
            }
            
            // Handle String format (fallback for malformed data)
            if (recipient instanceof String) {
                return cleanEmailAddress((String) recipient);
            }
            
        } catch (Exception e) {
            // Error extracting email address
        }
        
        return null;
    }
    
    /**
     * Helper: Clean and validate email address
     * Removes display names and extracts actual email from formats like:
     * - "Display Name" <email@domain.com>
     * - Display Name <email@domain.com>
     * - <email@domain.com>
     * - email@domain.com
     * 
     * @param rawEmail - Raw email string that may contain display name
     * @return Clean email address or null if invalid
     */
    private static String cleanEmailAddress(String rawEmail) {
        if (String.isBlank(rawEmail)) {
            return null;
        }
        
        String cleaned = rawEmail.trim();
        
        // Extract email from "Display Name" <email@domain.com> or Display Name <email@domain.com>
        if (cleaned.contains('<') && cleaned.contains('>')) {
            Integer startIdx = cleaned.indexOf('<');
            Integer endIdx = cleaned.indexOf('>');
            if (startIdx < endIdx) {
                cleaned = cleaned.substring(startIdx + 1, endIdx).trim();
            }
        }
        
        // Remove any remaining quotes
        cleaned = cleaned.replace('"', '').replace('\'', '').trim();
        
        // Validate email format (basic check for @)
        if (cleaned.contains('@') && cleaned.contains('.')) {
            return cleaned;
        }
        
        return null;
    }

}