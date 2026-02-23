/**
 * Service for sending notifications related to email matching.
 * Handles both Chatter posts and Custom Notifications (bell icon).
 * Extracted from ExchangeEmailController for better separation of concerns.
 */
public with sharing class AINotificationService {

    /**
     * Send notifications for matched emails.
     * Creates Chatter posts with @mentions and Custom Notifications (bell icon).
     * Uses bulk queries to avoid N+1 pattern.
     * 
     * NOTE: This method is currently not called from production code.
     * It was used by the legacy AIEmailMessageCreator flow which has been replaced
     * by the AI_Workspace_Staging__c approach.
     *
     * @param emailDataList - List of email data maps from provider
     * @param matchResults - List of corresponding match results
     */
    public static void sendMatchNotifications(
        List<Map<String, Object>> emailDataList,
        List<AIQuickMatchService.MatchResult> matchResults
    ) {
        try {
            // Get Custom Notification Type
            CustomNotificationType notificationType = getNotificationType();

            // BULK QUERY: Collect all IDs first to avoid N+1 queries
            Set<Id> contactIds = new Set<Id>();
            Set<Id> leadIds = new Set<Id>();
            Set<Id> accountIds = new Set<Id>();
            Set<Id> opportunityIds = new Set<Id>();
            Set<Id> caseIds = new Set<Id>();

            for (AIQuickMatchService.MatchResult match : matchResults) {
                if (match.confidence == 0 || match.matchType == 'None') continue;
                if (match.contactId != null) contactIds.add(match.contactId);
                if (match.leadId != null) leadIds.add(match.leadId);
                if (match.accountId != null) accountIds.add(match.accountId);
                if (match.opportunityId != null) opportunityIds.add(match.opportunityId);
                if (match.caseId != null) caseIds.add(match.caseId);
            }

            // BULK QUERIES: Fetch all records at once
            Map<Id, Contact> contactsMap = fetchContacts(contactIds);
            Map<Id, Lead> leadsMap = fetchLeads(leadIds);
            Map<Id, Account> accountsMap = fetchAccounts(accountIds);
            Map<Id, Opportunity> opportunitiesMap = fetchOpportunities(opportunityIds);
            Map<Id, Case> casesMap = fetchCases(caseIds);

            // Build notifications using cached data
            List<ConnectApi.BatchInput> batchInputs = new List<ConnectApi.BatchInput>();

            for (Integer i = 0; i < matchResults.size(); i++) {
                AIQuickMatchService.MatchResult match = matchResults[i];
                Map<String, Object> emailData = emailDataList[i];
                String subject = String.valueOf(emailData.get('subject'));

                // Skip if no match was found
                if (match.confidence == 0 || match.matchType == 'None') {
                    continue;
                }

                // Resolve target record info
                TargetInfo target = resolveTarget(
                    match, contactsMap, leadsMap, accountsMap, opportunitiesMap, casesMap
                );

                // Skip if we couldn't resolve the target
                if (target == null || String.isBlank(target.id)) {
                    continue;
                }

                // Send Custom Notification (Bell Icon)
                sendBellNotification(notificationType, subject, target, match);

                // Create Chatter post
                ConnectApi.BatchInput batchInput = createChatterPost(subject, target, match);
                if (batchInput != null) {
                    batchInputs.add(batchInput);
                }
            }

            // Post all Chatter notifications in batch
            postChatterBatch(batchInputs);

        } catch (Exception e) {
            // Don't fail the entire operation if notifications fail
            System.debug('Error sending notifications: ' + e.getMessage());
        }
    }

    /**
     * Send notifications for UNMATCHED emails.
     * Lets users know which emails couldn't be associated so they can create Contact/Account.
     *
     * @param emailDataList - List of unmatched email data maps
     * @param matchResults - List of corresponding (empty) match results
     */
    public static void sendUnmatchedNotifications(
        List<Map<String, Object>> emailDataList,
        List<AIQuickMatchService.MatchResult> matchResults
    ) {
        try {
            // Get Custom Notification Type
            CustomNotificationType notificationType = getNotificationType();

            List<ConnectApi.BatchInput> batchInputs = new List<ConnectApi.BatchInput>();

            for (Integer i = 0; i < emailDataList.size(); i++) {
                Map<String, Object> emailData = emailDataList[i];

                String subject = String.valueOf(emailData.get('subject'));
                String fromAddr = extractFromAddress(emailData);

                // Send Custom Notification (Bell Icon) for unmatched email
                sendUnmatchedBellNotification(notificationType, subject, fromAddr);

                // Create Chatter post for unmatched email
                ConnectApi.BatchInput batchInput = createUnmatchedChatterPost(subject, fromAddr);
                if (batchInput != null) {
                    batchInputs.add(batchInput);
                }
            }

            // Post all notifications in batch
            postChatterBatch(batchInputs);

        } catch (Exception e) {
            System.debug('Error sending unmatched notifications: ' + e.getMessage());
        }
    }

    // ============ Private Helper Methods ============

    /**
     * Get the custom notification type for workspace sync alerts
     */
    private static CustomNotificationType getNotificationType() {
        try {
            return [
                SELECT Id, DeveloperName
                FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('CustomNotificationType "AI_Workspace_Sync_Notification" not found.');
            return null;
        }
    }

    /**
     * Fetch contacts in bulk
     */
    private static Map<Id, Contact> fetchContacts(Set<Id> contactIds) {
        if (contactIds.isEmpty()) return new Map<Id, Contact>();
        return new Map<Id, Contact>([
            SELECT Id, Name, AccountId, Account.Name
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
        ]);
    }

    /**
     * Fetch leads in bulk
     */
    private static Map<Id, Lead> fetchLeads(Set<Id> leadIds) {
        if (leadIds.isEmpty()) return new Map<Id, Lead>();
        return new Map<Id, Lead>([
            SELECT Id, Name, Company
            FROM Lead
            WHERE Id IN :leadIds
            WITH USER_MODE
        ]);
    }

    /**
     * Fetch accounts in bulk
     */
    private static Map<Id, Account> fetchAccounts(Set<Id> accountIds) {
        if (accountIds.isEmpty()) return new Map<Id, Account>();
        return new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ]);
    }

    /**
     * Fetch opportunities in bulk
     */
    private static Map<Id, Opportunity> fetchOpportunities(Set<Id> opportunityIds) {
        if (opportunityIds.isEmpty()) return new Map<Id, Opportunity>();
        return new Map<Id, Opportunity>([
            SELECT Id, Name, Account.Name
            FROM Opportunity
            WHERE Id IN :opportunityIds
            WITH USER_MODE
        ]);
    }

    /**
     * Fetch cases in bulk
     */
    private static Map<Id, Case> fetchCases(Set<Id> caseIds) {
        if (caseIds.isEmpty()) return new Map<Id, Case>();
        return new Map<Id, Case>([
            SELECT Id, CaseNumber, Subject
            FROM Case
            WHERE Id IN :caseIds
            WITH USER_MODE
        ]);
    }

    /**
     * Resolve target record info from match result
     */
    private static TargetInfo resolveTarget(
        AIQuickMatchService.MatchResult match,
        Map<Id, Contact> contactsMap,
        Map<Id, Lead> leadsMap,
        Map<Id, Account> accountsMap,
        Map<Id, Opportunity> opportunitiesMap,
        Map<Id, Case> casesMap
    ) {
        TargetInfo target = new TargetInfo();

        if (match.contactId != null && contactsMap.containsKey(match.contactId)) {
            Contact c = contactsMap.get(match.contactId);
            target.name = c.Name;
            target.type = 'Contact';
            if (c.AccountId != null && c.Account != null) {
                target.name += ' (' + c.Account.Name + ')';
            }
            target.id = match.contactId;
        } else if (match.leadId != null && leadsMap.containsKey(match.leadId)) {
            Lead l = leadsMap.get(match.leadId);
            target.name = l.Name + ' (' + l.Company + ')';
            target.type = 'Lead';
            target.id = match.leadId;
        } else if (match.accountId != null && accountsMap.containsKey(match.accountId)) {
            Account a = accountsMap.get(match.accountId);
            target.name = a.Name;
            target.type = 'Account';
            target.id = match.accountId;
        } else if (match.opportunityId != null && opportunitiesMap.containsKey(match.opportunityId)) {
            Opportunity o = opportunitiesMap.get(match.opportunityId);
            target.name = o.Name;
            target.type = 'Opportunity';
            if (o.Account != null) {
                target.name += ' (' + o.Account.Name + ')';
            }
            target.id = match.opportunityId;
        } else if (match.caseId != null && casesMap.containsKey(match.caseId)) {
            Case cs = casesMap.get(match.caseId);
            target.name = 'Case #' + cs.CaseNumber + ' - ' + cs.Subject;
            target.type = 'Case';
            target.id = match.caseId;
        } else {
            return null;
        }

        return target;
    }

    /**
     * Send a bell notification for a matched email
     */
    private static void sendBellNotification(
        CustomNotificationType notificationType,
        String subject,
        TargetInfo target,
        AIQuickMatchService.MatchResult match
    ) {
        if (notificationType == null) {
            System.debug('No CustomNotificationType found - skipping bell notification for: ' + subject);
            return;
        }

        Messaging.CustomNotification notification = new Messaging.CustomNotification();

        // Truncate subject for title (max ~50 chars for readability)
        String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;
        notification.setTitle('✉️ ' + truncatedSubject);

        // Body includes match details and confidence
        String body = 'Matched to ' + target.type + ': ' + target.name + '\n';
        body += 'Confidence: ' + match.confidence + '%';
        if (match.matchDetails != null && !match.matchDetails.isEmpty()) {
            body += '\n' + String.join(match.matchDetails, ', ');
        }
        notification.setBody(body);

        notification.setNotificationTypeId(notificationType.Id);
        notification.setTargetId(target.id);

        try {
            notification.send(new Set<String>{UserInfo.getUserId()});
            System.debug('Sent notification for email: ' + subject + ' -> ' + target.type + ': ' + target.name);
        } catch (Exception e) {
            System.debug('Failed to send custom notification: ' + e.getMessage());
        }
    }

    /**
     * Send a bell notification for an unmatched email
     */
    private static void sendUnmatchedBellNotification(
        CustomNotificationType notificationType,
        String subject,
        String fromAddr
    ) {
        if (notificationType == null) return;

        Messaging.CustomNotification notification = new Messaging.CustomNotification();

        String truncatedSubject = subject.length() > 35 ? subject.substring(0, 35) + '...' : subject;
        notification.setTitle('⚠️ No match: ' + truncatedSubject);

        String body = 'Could not match email from: ' + fromAddr + '\n';
        body += 'Create a Contact or Account with this email/domain to auto-associate.';
        notification.setBody(body);

        notification.setNotificationTypeId(notificationType.Id);
        notification.setTargetId(UserInfo.getUserId());

        try {
            notification.send(new Set<String>{UserInfo.getUserId()});
            System.debug('Sent unmatched notification for email: ' + subject);
        } catch (Exception e) {
            System.debug('Failed to send unmatched notification: ' + e.getMessage());
        }
    }

    /**
     * Create a Chatter post for a matched email
     */
    private static ConnectApi.BatchInput createChatterPost(
        String subject,
        TargetInfo target,
        AIQuickMatchService.MatchResult match
    ) {
        ConnectApi.FeedItemInput feedItemInput = new ConnectApi.FeedItemInput();
        ConnectApi.MessageBodyInput messageBodyInput = new ConnectApi.MessageBodyInput();
        ConnectApi.TextSegmentInput textSegmentInput = new ConnectApi.TextSegmentInput();

        List<ConnectApi.MessageSegmentInput> messageSegments = new List<ConnectApi.MessageSegmentInput>();

        // Build message
        String message = '✉️ Email Auto-Match Result\n\n';
        message += 'Email: "' + subject + '"\n';
        message += 'Matched to: ' + target.type + ' - ' + target.name + '\n';
        message += 'Confidence: ' + match.confidence + '%\n';
        message += 'Match Details: ' + String.join(match.matchDetails, ', ') + '\n';

        textSegmentInput.text = message;
        messageSegments.add(textSegmentInput);

        // Add entity mention for the matched record
        ConnectApi.EntityLinkSegmentInput entityLinkSegmentInput = new ConnectApi.EntityLinkSegmentInput();
        entityLinkSegmentInput.entityId = target.id;
        messageSegments.add(entityLinkSegmentInput);

        messageBodyInput.messageSegments = messageSegments;
        feedItemInput.body = messageBodyInput;
        feedItemInput.feedElementType = ConnectApi.FeedElementType.FeedItem;
        feedItemInput.subjectId = UserInfo.getUserId();

        return new ConnectApi.BatchInput(feedItemInput);
    }

    /**
     * Create a Chatter post for an unmatched email
     */
    private static ConnectApi.BatchInput createUnmatchedChatterPost(String subject, String fromAddr) {
        ConnectApi.FeedItemInput feedItemInput = new ConnectApi.FeedItemInput();
        ConnectApi.MessageBodyInput messageBodyInput = new ConnectApi.MessageBodyInput();
        ConnectApi.TextSegmentInput textSegmentInput = new ConnectApi.TextSegmentInput();

        List<ConnectApi.MessageSegmentInput> messageSegments = new List<ConnectApi.MessageSegmentInput>();

        String message = '⚠️ Email Not Matched - Action Required\n\n';
        message += 'Email: "' + subject + '"\n';
        message += 'From: ' + fromAddr + '\n\n';
        message += 'This email was NOT imported because no matching Contact, Lead, or Account was found.\n\n';
        message += 'To import this email:\n';
        message += '1. Create a Contact or Lead with email: ' + fromAddr + '\n';
        message += '2. OR create an Account with website containing the sender\'s domain\n';
        message += '3. Then retry the Auto-Match\n';

        textSegmentInput.text = message;
        messageSegments.add(textSegmentInput);

        messageBodyInput.messageSegments = messageSegments;
        feedItemInput.body = messageBodyInput;
        feedItemInput.feedElementType = ConnectApi.FeedElementType.FeedItem;
        feedItemInput.subjectId = UserInfo.getUserId();

        return new ConnectApi.BatchInput(feedItemInput);
    }

    /**
     * Post Chatter items in batch
     */
    private static void postChatterBatch(List<ConnectApi.BatchInput> batchInputs) {
        if (!batchInputs.isEmpty() && !Test.isRunningTest()) {
            ConnectApi.ChatterFeeds.postFeedElementBatch(Network.getNetworkId(), batchInputs);
        }
    }

    /**
     * Extract from address from email data
     */
    private static String extractFromAddress(Map<String, Object> emailData) {
        String fromAddr = '';
        Object fromObj = emailData.get('from');
        if (fromObj instanceof Map<String, Object>) {
            Map<String, Object> fromMap = (Map<String, Object>) fromObj;
            Object emailAddrObj = fromMap.get('emailAddress');
            if (emailAddrObj instanceof Map<String, Object>) {
                fromAddr = String.valueOf(((Map<String, Object>) emailAddrObj).get('address'));
            }
        }
        return fromAddr;
    }

    /**
     * Inner class for resolved target information
     */
    private class TargetInfo {
        public String id;
        public String name;
        public String type;
    }
}