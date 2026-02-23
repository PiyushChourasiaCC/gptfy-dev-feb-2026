/**
 * EmailSyncDigestService - Generates and sends daily digest emails for email sync activity
 *
 * Purpose:
 * - Aggregates sync activity across all syncs for each user
 * - Sends a single consolidated email with links to synced activities
 * - Provides transparency and control to users about automated sync
 *
 * Features:
 * - Daily/weekly digest frequency options
 * - Grouped by Account/Opportunity for easy scanning
 * - One-click links to view synced EmailMessage records
 * - Summary statistics (imported, excluded, errors)
 */
public with sharing class AIEmailSyncDigestService {

    /**
     * Digest data structure for a single user
     */
    public class UserDigest {
        public Id userId { get; set; }
        public String userName { get; set; }
        public String userEmail { get; set; }
        public Integer totalImported { get; set; }
        public Integer totalExcluded { get; set; }
        public Integer totalUnmatched { get; set; }
        public Integer totalErrors { get; set; }
        public Integer syncCount { get; set; }
        public List<AI_Workspace_Sync_Log__c> syncLogs { get; set; }
        public List<DigestEmailGroup> emailGroups { get; set; }

        public UserDigest() {
            this.totalImported = 0;
            this.totalExcluded = 0;
            this.totalUnmatched = 0;
            this.totalErrors = 0;
            this.syncCount = 0;
            this.syncLogs = new List<AI_Workspace_Sync_Log__c>();
            this.emailGroups = new List<DigestEmailGroup>();
        }
    }

    /**
     * Grouped emails by parent record (Account/Opportunity)
     */
    public class DigestEmailGroup {
        public String groupName { get; set; }
        public String groupType { get; set; } // Account, Opportunity, Unassociated
        public Id groupId { get; set; }
        public List<DigestEmail> emails { get; set; }

        public DigestEmailGroup() {
            this.emails = new List<DigestEmail>();
        }
    }

    /**
     * Individual email in the digest
     */
    public class DigestEmail {
        public Id emailMessageId { get; set; }
        public String subject { get; set; }
        public String fromAddress { get; set; }
        public String fromName { get; set; }
        public DateTime messageDate { get; set; }
        public Boolean isIncoming { get; set; }
        public String matchedTo { get; set; } // Contact/Lead name
        public Integer confidence { get; set; }
    }

    /**
     * Generate digests for all users who had sync activity in the specified period
     *
     * @param sinceDatetime Only include sync logs after this time
     * @return Map of userId to UserDigest
     */
    public static Map<Id, UserDigest> generateDigests(DateTime sinceDatetime) {
        Map<Id, UserDigest> digestsByUser = new Map<Id, UserDigest>();

        // Query sync logs for the period
        List<AI_Workspace_Sync_Log__c> syncLogs = [
            SELECT Id, User__c, User__r.Name, User__r.Email,
                   Provider_Type__c, Status__c, Start_Time__c, End_Time__c,
                   Emails_Imported__c, Emails_Excluded__c, Emails_Unmatched__c,
                   Emails_Fetched__c, Error_Message__c, Exclusion_Summary__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Start_Time__c >= :sinceDatetime
              AND Status__c IN ('Success', 'Partial')
              AND Emails_Imported__c > 0
            ORDER BY User__c, Start_Time__c DESC
        ];

        if (syncLogs.isEmpty()) {
            return digestsByUser;
        }

        // Group by user
        for (AI_Workspace_Sync_Log__c log : syncLogs) {
            if (!digestsByUser.containsKey(log.User__c)) {
                UserDigest digest = new UserDigest();
                digest.userId = log.User__c;
                digest.userName = log.User__r.Name;
                digest.userEmail = log.User__r.Email;
                digestsByUser.put(log.User__c, digest);
            }

            UserDigest digest = digestsByUser.get(log.User__c);
            digest.syncLogs.add(log);
            digest.syncCount++;
            digest.totalImported += log.Emails_Imported__c != null ? (Integer) log.Emails_Imported__c : 0;
            digest.totalExcluded += log.Emails_Excluded__c != null ? (Integer) log.Emails_Excluded__c : 0;
            digest.totalUnmatched += log.Emails_Unmatched__c != null ? (Integer) log.Emails_Unmatched__c : 0;
            if (log.Status__c == 'Partial' || String.isNotBlank(log.Error_Message__c)) {
                digest.totalErrors++;
            }
        }

        // Fetch email details for each user's digest
        Set<Id> userIds = digestsByUser.keySet();
        populateEmailDetails(digestsByUser, sinceDatetime);

        return digestsByUser;
    }

    /**
     * Populate email details grouped by Account/Opportunity
     */
    private static void populateEmailDetails(Map<Id, UserDigest> digestsByUser, DateTime sinceDatetime) {
        // Query EmailMessages through AI_Workspace_Staging__c (which tracks synced emails)
        // The staging record's Email_Message__c lookup points to the imported EmailMessage
        Set<Id> emailMessageIds = new Set<Id>();
        for (AI_Workspace_Staging__c staging : [
            SELECT Email_Message__c
            FROM AI_Workspace_Staging__c
            WHERE RecordType.DeveloperName = 'Email'
              AND Email_Message__c != null
              AND CreatedDate >= :sinceDatetime
              AND User__c IN :digestsByUser.keySet()
            LIMIT 500
        ]) {
            emailMessageIds.add(staging.Email_Message__c);
        }
        
        if (emailMessageIds.isEmpty()) {
            return;
        }
        
        List<EmailMessage> emails = [
            SELECT Id, Subject, FromAddress, FromName, MessageDate, Incoming,
                   CreatedById, RelatedToId, RelatedTo.Name,
                   (SELECT RelationId, Relation.Name, RelationType
                    FROM EmailMessageRelations
                    WHERE RelationType IN ('FromAddress', 'ToAddress'))
            FROM EmailMessage
            WHERE Id IN :emailMessageIds
            ORDER BY RelatedToId, MessageDate DESC
        ];

        // Group emails by user and then by related record
        Map<Id, Map<Id, DigestEmailGroup>> groupsByUserAndRecord = new Map<Id, Map<Id, DigestEmailGroup>>();

        for (EmailMessage em : emails) {
            Id ownerId = em.CreatedById;
            if (!digestsByUser.containsKey(ownerId)) continue;

            if (!groupsByUserAndRecord.containsKey(ownerId)) {
                groupsByUserAndRecord.put(ownerId, new Map<Id, DigestEmailGroup>());
            }

            Map<Id, DigestEmailGroup> userGroups = groupsByUserAndRecord.get(ownerId);

            // Determine group key (RelatedToId or 'unassociated')
            Id groupKey = em.RelatedToId != null ? em.RelatedToId : null;
            String groupKeyStr = groupKey != null ? String.valueOf(groupKey) : 'unassociated';

            if (!userGroups.containsKey(groupKey)) {
                DigestEmailGroup emailGroup = new DigestEmailGroup();
                if (em.RelatedToId != null) {
                    emailGroup.groupId = em.RelatedToId;
                    emailGroup.groupName = em.RelatedTo != null ? em.RelatedTo.Name : 'Unknown';
                    // Determine type from Id prefix
                    String idPrefix = String.valueOf(em.RelatedToId).substring(0, 3);
                    emailGroup.groupType = idPrefix == '001' ? 'Account' :
                                     idPrefix == '006' ? 'Opportunity' : 'Record';
                } else {
                    emailGroup.groupName = 'Unassociated';
                    emailGroup.groupType = 'Unassociated';
                }
                userGroups.put(groupKey, emailGroup);
            }

            DigestEmailGroup currentGroup = userGroups.get(groupKey);

            // Create digest email entry
            DigestEmail de = new DigestEmail();
            de.emailMessageId = em.Id;
            de.subject = em.Subject;
            de.fromAddress = em.FromAddress;
            de.fromName = em.FromName;
            de.messageDate = em.MessageDate;
            de.isIncoming = em.Incoming;

            // Get matched contact/lead name from relations
            if (em.EmailMessageRelations != null) {
                for (EmailMessageRelation rel : em.EmailMessageRelations) {
                    if (rel.RelationType == 'FromAddress' || rel.RelationType == 'ToAddress') {
                        de.matchedTo = rel.Relation != null ? rel.Relation.Name : null;
                        break;
                    }
                }
            }

            currentGroup.emails.add(de);
        }

        // Assign groups to user digests
        for (Id userId : groupsByUserAndRecord.keySet()) {
            UserDigest digest = digestsByUser.get(userId);
            Map<Id, DigestEmailGroup> groups = groupsByUserAndRecord.get(userId);
            digest.emailGroups.addAll(groups.values());
        }
    }

    /**
     * Send digest emails to all users with activity
     *
     * @param sinceDatetime Only include sync activity after this time
     * @return Number of digest emails sent
     */
    public static Integer sendDigestEmails(DateTime sinceDatetime) {
        Map<Id, UserDigest> digests = generateDigests(sinceDatetime);

        if (digests.isEmpty()) {
            System.debug('No digest activity to send');
            return 0;
        }

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (UserDigest digest : digests.values()) {
            if (digest.totalImported == 0) continue;

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ digest.userEmail });
            email.setSubject(buildDigestSubject(digest));
            email.setHtmlBody(buildDigestHtmlBody(digest, baseUrl));
            email.setPlainTextBody(buildDigestPlainBody(digest, baseUrl));
            email.setSaveAsActivity(false);

            emailsToSend.add(email);
        }

        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend, false);
        }

        return emailsToSend.size();
    }

    /**
     * Build email subject line
     */
    private static String buildDigestSubject(UserDigest digest) {
        return 'Email Sync Digest: ' + digest.totalImported + ' emails synced to Salesforce';
    }

    /**
     * Build HTML email body
     */
    private static String buildDigestHtmlBody(UserDigest digest, String baseUrl) {
        String html = '<!DOCTYPE html><html><head><style>';
        html += 'body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.5; color: #333; }';
        html += '.container { max-width: 600px; margin: 0 auto; padding: 20px; }';
        html += '.header { background: linear-gradient(135deg, #1565C0, #0D47A1); color: white; padding: 20px; border-radius: 8px 8px 0 0; }';
        html += '.stats { display: flex; gap: 20px; margin: 20px 0; }';
        html += '.stat-box { background: #f5f5f5; padding: 15px; border-radius: 8px; text-align: center; flex: 1; }';
        html += '.stat-number { font-size: 24px; font-weight: bold; color: #1565C0; }';
        html += '.stat-label { font-size: 12px; color: #666; }';
        html += '.group { margin: 20px 0; border: 1px solid #e0e0e0; border-radius: 8px; overflow: hidden; }';
        html += '.group-header { background: #f5f5f5; padding: 12px 15px; font-weight: bold; border-bottom: 1px solid #e0e0e0; }';
        html += '.group-header a { color: #1565C0; text-decoration: none; }';
        html += '.email-item { padding: 12px 15px; border-bottom: 1px solid #f0f0f0; }';
        html += '.email-item:last-child { border-bottom: none; }';
        html += '.email-subject { font-weight: 500; }';
        html += '.email-subject a { color: #1565C0; text-decoration: none; }';
        html += '.email-meta { font-size: 12px; color: #666; margin-top: 4px; }';
        html += '.email-direction { display: inline-block; padding: 2px 6px; border-radius: 4px; font-size: 11px; }';
        html += '.incoming { background: #e3f2fd; color: #1565C0; }';
        html += '.outgoing { background: #e8f5e9; color: #2e7d32; }';
        html += '.footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; font-size: 12px; color: #666; }';
        html += '</style></head><body>';

        html += '<div class="container">';

        // Header
        html += '<div class="header">';
        html += '<h1 style="margin: 0; font-size: 20px;">Email Sync Digest</h1>';
        html += '<p style="margin: 5px 0 0 0; opacity: 0.9;">Your daily email sync summary</p>';
        html += '</div>';

        // Stats
        html += '<div class="stats">';
        html += '<div class="stat-box"><div class="stat-number">' + digest.totalImported + '</div><div class="stat-label">Emails Synced</div></div>';
        html += '<div class="stat-box"><div class="stat-number">' + digest.totalExcluded + '</div><div class="stat-label">Excluded</div></div>';
        html += '<div class="stat-box"><div class="stat-number">' + digest.syncCount + '</div><div class="stat-label">Sync Runs</div></div>';
        html += '</div>';

        // Email groups
        if (!digest.emailGroups.isEmpty()) {
            html += '<h2 style="font-size: 16px; margin: 25px 0 15px 0;">Synced Emails by ' + (digest.emailGroups[0].groupType == 'Account' ? 'Account' : 'Record') + '</h2>';

            for (DigestEmailGroup emailGroup : digest.emailGroups) {
                html += '<div class="group">';

                // Group header
                html += '<div class="group-header">';
                if (emailGroup.groupId != null) {
                    html += '<a href="' + baseUrl + '/' + emailGroup.groupId + '">' + escapeHtml(emailGroup.groupName) + '</a>';
                } else {
                    html += escapeHtml(emailGroup.groupName);
                }
                html += ' (' + emailGroup.emails.size() + ')';
                html += '</div>';

                // Emails (limit to 10 per group)
                Integer emailCount = 0;
                for (DigestEmail de : emailGroup.emails) {
                    if (emailCount >= 10) {
                        html += '<div class="email-item" style="text-align: center; color: #666;">+ ' + (emailGroup.emails.size() - 10) + ' more emails</div>';
                        break;
                    }

                    html += '<div class="email-item">';
                    html += '<div class="email-subject">';
                    html += '<span class="email-direction ' + (de.isIncoming ? 'incoming' : 'outgoing') + '">';
                    html += de.isIncoming ? 'Received' : 'Sent';
                    html += '</span> ';
                    html += '<a href="' + baseUrl + '/' + de.emailMessageId + '">' + escapeHtml(de.subject != null ? de.subject : '(No Subject)') + '</a>';
                    html += '</div>';
                    html += '<div class="email-meta">';
                    html += de.isIncoming ? 'From: ' : 'To: ';
                    html += escapeHtml(de.fromName != null ? de.fromName : de.fromAddress);
                    if (de.matchedTo != null) {
                        html += ' &bull; Matched to: ' + escapeHtml(de.matchedTo);
                    }
                    html += '</div>';
                    html += '</div>';

                    emailCount++;
                }

                html += '</div>';
            }
        }

        // Footer
        html += '<div class="footer">';
        html += '<p>This digest was automatically generated by GPTfy Email Sync.</p>';
        html += '<p><a href="' + baseUrl + '/lightning/o/AI_Workspace_Sync_Log__c/list">View all sync logs</a></p>';
        html += '</div>';

        html += '</div></body></html>';

        return html;
    }

    /**
     * Build plain text email body
     */
    private static String buildDigestPlainBody(UserDigest digest, String baseUrl) {
        String text = 'EMAIL SYNC DIGEST\n';
        text += '==================\n\n';

        text += 'Summary:\n';
        text += '- Emails Synced: ' + digest.totalImported + '\n';
        text += '- Emails Excluded: ' + digest.totalExcluded + '\n';
        text += '- Sync Runs: ' + digest.syncCount + '\n\n';

        text += 'SYNCED EMAILS\n';
        text += '-------------\n\n';

        for (DigestEmailGroup emailGroup : digest.emailGroups) {
            text += emailGroup.groupName + ' (' + emailGroup.emails.size() + ' emails)\n';

            Integer emailCount = 0;
            for (DigestEmail de : emailGroup.emails) {
                if (emailCount >= 10) {
                    text += '  + ' + (emailGroup.emails.size() - 10) + ' more emails\n';
                    break;
                }

                text += '  - ' + (de.isIncoming ? '[Received]' : '[Sent]') + ' ';
                text += (de.subject != null ? de.subject : '(No Subject)') + '\n';
                text += '    ' + baseUrl + '/' + de.emailMessageId + '\n';

                emailCount++;
            }
            text += '\n';
        }

        text += '\n---\n';
        text += 'View all sync logs: ' + baseUrl + '/lightning/o/AI_Workspace_Sync_Log__c/list\n';

        return text;
    }

    /**
     * Escape HTML special characters
     */
    private static String escapeHtml(String input) {
        if (input == null) return '';
        return input.escapeHtml4();
    }

    /**
     * Send digest for a specific user (useful for testing or manual trigger)
     *
     * @param userId The user to send digest to
     * @param sinceDatetime Only include sync activity after this time
     * @return True if digest was sent
     */
    public static Boolean sendDigestForUser(Id userId, DateTime sinceDatetime) {
        Map<Id, UserDigest> allDigests = generateDigests(sinceDatetime);

        if (!allDigests.containsKey(userId)) {
            return false;
        }

        UserDigest digest = allDigests.get(userId);
        if (digest.totalImported == 0) {
            return false;
        }

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ digest.userEmail });
        email.setSubject(buildDigestSubject(digest));
        email.setHtmlBody(buildDigestHtmlBody(digest, baseUrl));
        email.setPlainTextBody(buildDigestPlainBody(digest, baseUrl));
        email.setSaveAsActivity(false);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);

        return true;
    }
}