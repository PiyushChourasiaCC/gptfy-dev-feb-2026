public class PiyushTestSendEmails {
// Change this to your recipient address
    public static final String RECIPIENT_EMAIL = 'Piyush2@gptfy.dev';

    // Sends N emails (max 100 per transaction)
    public static void sendEmails(Integer howMany) {
        if (howMany == null || howMany <= 0) {
            howMany = 1;
        }
        if (howMany > 100) {
            howMany = 100;
        }

        Messaging.reserveSingleEmailCapacity(howMany);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        String subjectText =
            'Re: FW: Q4 ROI Analysis  | Amendment #3 — €2.5M Budget Revision [Action Required]';

        // Optional: set Reply-To header
        String replyToAddress = 'no-reply@mckinsey-notifications.com';

        String htmlBody =
'<!DOCTYPE html>' +
'<html xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">' +
'<head>' +
'<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />' +
'<meta name="viewport" content="width=device-width, initial-scale=1.0" />' +
'<style type="text/css">' +
'  @media only screen and (max-width: 600px) { .mobile-hide { display: none !important; } }' +
'  p { margin: 0; padding: 0; }' +
'  .ExternalClass { width: 100%; }' +
'</style>' +
'</head>' +
'<body style="margin:0;padding:0;font-family:Segoe UI,Arial,sans-serif;">' +

'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">' +
'<tr><td align="center" bgcolor="#f4f4f4">' +

'<table width="600" cellpadding="20" style="background:#1a237e;"><tr><td>' +
'  <span style="color:#ffffff;font-size:18px;font-weight:bold;">McKinsey &amp; Company</span>' +
'</td></tr></table>' +

'<table width="600" cellpadding="30" bgcolor="#ffffff"><tr><td style="font-size:14px;line-height:1.6;color:#333;">' +

'<p>Hi John &amp; Team,</p>' +
'<p>Hope you&apos;re doing well!</p>' +

'<p>Following up on <strong>yesterday&apos;s call</strong> — please find below the revised projections incorporating the <em>APAC regional adjustments</em> we discussed:</p>' +

'<blockquote style="border-left:4px solid #1a237e;padding-left:15px;margin:20px 0;color:#555;">' +
'  <p><strong>Original message from Søren Müller (Dec 12):</strong></p>' +
'  <p>"Die Kostenanalyse zeigt eine Abweichung von <span style="color:red;">−23.7%</span> gegenüber dem ursprünglichen Budget. Wir müssen die Ressourcenallokation überdenken."</p>' +
'  <p><em>Translation: The cost analysis shows a deviation of −23.7% compared to the original budget...</em></p>' +
'</blockquote>' +

'<h3 style="color:#1a237e;border-bottom:1px solid #ddd;padding-bottom:8px;">Key Financial Metrics</h3>' +

'<table width="100%" cellpadding="10" cellspacing="0" border="1" style="border-collapse:collapse;border-color:#ddd;font-size:13px;">' +
'<thead style="background:#e8eaf6;">' +
'  <tr>' +
'    <th align="left">Region</th>' +
'    <th align="right">Q4 Actual (€)</th>' +
'    <th align="right">Variance</th>' +
'    <th align="center">Status</th>' +
'  </tr>' +
'</thead>' +
'<tbody>' +
'  <tr>' +
'    <td>North America</td>' +
'    <td align="right">€1,247,893.45</td>' +
'    <td align="right" style="color:green;">+12.3%</td>' +
'    <td align="center"></td>' +
'  </tr>' +
'  <tr>' +
'    <td>EMEA</td>' +
'    <td align="right">€892,104.00</td>' +
'    <td align="right" style="color:red;">−8.7%</td>' +
'    <td align="center"></td>' +
'  </tr>' +
'  <tr>' +
'    <td>APAC (日本・中国・韓国)</td>' +
'    <td align="right">¥89,450,000 <small>(≈€547,832)</small></td>' +
'    <td align="right" style="color:orange;">−2.1%</td>' +
'    <td align="center"></td>' +
'  </tr>' +
'  <tr style="background:#fff3e0;">' +
'    <td><strong>TOTAL</strong></td>' +
'    <td align="right"><strong>€2,687,829.45</strong></td>' +
'    <td align="right"><strong>+1.2%</strong></td>' +
'    <td align="center">—</td>' +
'  </tr>' +
'</tbody>' +
'</table>' +

'<p style="margin-top:20px;"><strong>Action Items:</strong></p>' +
'<ol>' +
'  <li>Review attached spreadsheet <code>Q4_Analysis_v3.2_FINAL(2).xlsx</code></li>' +
'  <li>Confirm budget allocation by <u>Friday, Jan 17th @ 5:00 PM GMT</u></li>' +
'  <li>Schedule follow-up with 田中さん (Tanaka-san) re: Japan subsidiary</li>' +
'</ol>' +

'<p style="background:#fff8e1;padding:15px;border-radius:4px;margin:20px 0;">' +
'  <strong>REMINDER:</strong> The board meeting is scheduled for <span style="white-space:nowrap;">2025-01-20T14:00:00+00:00</span>. ' +
'  Please ensure all documentation is submitted via the secure portal (SSO required).' +
'</p>' +

'<p>Let me know if you have any questions!</p>' +

'<p>Best regards,<br/>' +
'<strong>María José García-Fernández</strong><br/>' +
'<em>Senior Partner | Digital &amp; Analytics Practice</em><br/>' +
'McKinsey &amp; Company</p>' +

'<p style="font-size:12px;margin-top:10px;">' +
'Tel: +44 (0)20 7839 8040 ext. 4472<br/>' +
'Mobile: +34 612 345 678 (WhatsApp)' +
'</p>' +

'</td></tr></table>' +

'<table width="600" cellpadding="15" style="background:#f5f5f5;font-size:11px;color:#666;"><tr><td>' +
'<p><strong>Confidentiality Notice:</strong> This e-mail message, including any attachments, is for the sole use of the intended recipient(s) and may contain confidential and privileged information. Any unauthorized review, use, disclosure, or distribution is prohibited.</p>' +
'<p style="margin-top:10px;">McKinsey &amp; Company, Inc. | 1 Jermyn Street, London SW1Y 4UH</p>' +
'</td></tr></table>' +

'</td></tr></table>' +

'</body></html>';

        String plainTextBody =
'Hi John & Team,' + '\n\n' +
'Hope you\'re doing well!' + '\n\n' +
'Following up on yesterday\'s call — please find below the revised projections incorporating the APAC regional adjustments we discussed:' + '\n\n' +
'> Original message from Søren Müller (Dec 12):' + '\n' +
'> "Die Kostenanalyse zeigt eine Abweichung von −23.7% gegenüber dem ursprünglichen Budget. Wir müssen die Ressourcenallokation überdenken."' + '\n' +
'> Translation: The cost analysis shows a deviation of −23.7% compared to the original budget...' + '\n\n' +
'KEY FINANCIAL METRICS' + '\n' +
'=====================' + '\n' +
'Region              | Q4 Actual (€)    | Variance | Status' + '\n' +
'--------------------|------------------|----------|-------' + '\n' +
'North America       | €1,247,893.45    | +12.3%   | OK' + '\n' +
'EMEA                | €892,104.00      | −8.7%    | WARN' + '\n' +
'APAC (日本・中国・韓国) | ¥89,450,000       | −2.1%   | REVIEW' + '\n' +
'--------------------|------------------|----------|-------' + '\n' +
'TOTAL               | €2,687,829.45    | +1.2%    | —' + '\n\n' +
'ACTION ITEMS:' + '\n' +
'1. Review attached spreadsheet Q4_Analysis_v3.2_FINAL(2).xlsx' + '\n' +
'2. Confirm budget allocation by Friday, Jan 17th @ 5:00 PM GMT' + '\n' +
'3. Schedule follow-up with 田中さん (Tanaka-san) re: Japan subsidiary' + '\n\n' +
'REMINDER: The board meeting is scheduled for 2025-01-20T14:00:00+00:00.' + '\n\n' +
'Best regards,' + '\n' +
'María José García-Fernández' + '\n' +
'Senior Partner | Digital & Analytics Practice' + '\n' +
'McKinsey & Company' + '\n' +
'Tel: +44 (0)20 7839 8040 ext. 4472' + '\n' +
'Mobile: +34 612 345 678' + '\n\n' +
'---' + '\n' +
'CONFIDENTIALITY NOTICE: This e-mail message, including any attachments, is for the sole use of the intended recipient(s)...';

        for (Integer i = 0; i < howMany; i++) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[] { RECIPIENT_EMAIL });
            email.setSubject(subjectText);
            email.setReplyTo(replyToAddress);
            email.setHtmlBody(htmlBody);
            email.setPlainTextBody(plainTextBody);
            emails.add(email);
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);
        System.debug('Sent ' + results.size() + ' emails.');
    }
}