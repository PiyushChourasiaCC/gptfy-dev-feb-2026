/**
 * Transforms Gmail API response format to Microsoft Graph-compatible format
 * This allows the existing UI code to work with Gmail emails
 * FIXED VERSION: Properly maps fields for EmailMessageCreator compatibility
 */
public class AIGmailEmailTransformer {

    /**
     * Transform Gmail message to Graph-compatible format
     */
    public static Map<String, Object> transformToGraphFormat(Map<String, Object> gmailMessage) {
        Map<String, Object> graphFormat = new Map<String, Object>();

        // Get headers first - we need Message-Id from headers
        Map<String, String> headers = extractHeaders(gmailMessage);

        // Basic fields
        graphFormat.put('id', gmailMessage.get('id'));
        
        // CRITICAL FIX: Use the RFC 2822 Message-Id header for internetMessageId
        // This is the actual email identifier used for deduplication (matches Salesforce standard behavior)
        // The Message-Id header looks like: <CAMZ5ncDfhBkA=bnhaGV67GwMfTTPYxcrhnaSFFui2F8sJxpG9Q@mail.gmail.com>
        String messageIdHeader = headers.get('Message-Id');
        if (String.isBlank(messageIdHeader)) {
            // Also try lowercase version as header names can vary
            messageIdHeader = headers.get('Message-ID');
        }
        if (String.isNotBlank(messageIdHeader)) {
            graphFormat.put('internetMessageId', messageIdHeader);
        } else {
            // Fallback to Gmail ID only if Message-Id header is not available (unusual)
            graphFormat.put('internetMessageId', gmailMessage.get('id'));
        }

        // Subject
        graphFormat.put('subject', headers.get('Subject'));

        // From - CRITICAL FIX: Use 'address' not 'email' to match EmailMessageCreator expectations
        Map<String, Object> fromField = new Map<String, Object>();
        Map<String, Object> fromAddress = new Map<String, Object>();
        String fromHeader = headers.get('From');
        if (String.isNotBlank(fromHeader)) {
            Map<String, String> parsedFrom = parseEmailAddress(fromHeader);
            fromAddress.put('name', parsedFrom.get('name'));
            fromAddress.put('address', parsedFrom.get('address')); // FIXED: was 'email', should be 'address'
        }
        fromField.put('emailAddress', fromAddress);
        graphFormat.put('from', fromField);

        // Recipients - NEW: Parse and add recipient fields for proper association
        graphFormat.put('toRecipients', parseRecipients(headers.get('To')));
        graphFormat.put('ccRecipients', parseRecipients(headers.get('Cc')));
        graphFormat.put('bccRecipients', parseRecipients(headers.get('Bcc')));

        // ConversationId - NEW: Add for thread tracking
        String threadId = (String) gmailMessage.get('threadId');
        if (String.isNotBlank(threadId)) {
            graphFormat.put('conversationId', threadId);
        }

        // Date - Gmail uses internalDate (milliseconds since epoch as STRING)
        // IMPORTANT: Use formatGmt() to output in UTC timezone (the 'Z' suffix means UTC)
        Object internalDateObj = gmailMessage.get('internalDate');
        if (internalDateObj != null) {
            try {
                Long internalDate;
                if (internalDateObj instanceof String) {
                    internalDate = Long.valueOf((String) internalDateObj);
                } else {
                    internalDate = (Long) internalDateObj;
                }
                DateTime dt = DateTime.newInstance(internalDate);
                // Use formatGmt() not format() - the 'Z' suffix means UTC, so we must format in GMT
                graphFormat.put('receivedDateTime', dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
                // CRITICAL FIX: Also preserve the original internalDate for sync window tracking
                // AIEmailSyncChainableQueueable.parseEmailDate() checks internalDate first
                graphFormat.put('internalDate', internalDate);
            } catch (Exception e) {
                graphFormat.put('receivedDateTime', DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
            }
        } else {
            graphFormat.put('receivedDateTime', DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
        }

        // Snippet (preview)
        graphFormat.put('bodyPreview', gmailMessage.get('snippet'));

        // Body
        Map<String, Object> body = new Map<String, Object>();
        String bodyContent = extractBody(gmailMessage);
        if (String.isBlank(bodyContent)) {
            // Fallback to snippet if body extraction fails
            bodyContent = (String) gmailMessage.get('snippet');
            body.put('contentType', 'text');
        } else {
            body.put('contentType', 'html'); // Gmail typically returns HTML
        }
        body.put('content', bodyContent != null ? bodyContent : '');
        graphFormat.put('body', body);

        // Has attachments
        graphFormat.put('hasAttachments', hasAttachments(gmailMessage));

        // Read status - check if 'UNREAD' label exists
        List<Object> labelIds = (List<Object>) gmailMessage.get('labelIds');
        Boolean isRead = true;
        if (labelIds != null) {
            for (Object labelId : labelIds) {
                if ('UNREAD'.equals(labelId)) {
                    isRead = false;
                    break;
                }
            }
        }
        graphFormat.put('isRead', isRead);

        // IMPORTANT: Pass through labelIds for exclusion service (marketing/confidential detection)
        graphFormat.put('labelIds', labelIds);

        // Importance (Gmail doesn't have this, default to normal)
        graphFormat.put('importance', 'normal');

        return graphFormat;
    }

    /**
     * Parse recipients string to Graph API format
     * NEW METHOD: Properly formats recipients for EmailMessageCreator
     */
    private static List<Map<String, Object>> parseRecipients(String recipientsString) {
        List<Map<String, Object>> recipients = new List<Map<String, Object>>();

        if (String.isBlank(recipientsString)) {
            return recipients;
        }

        // Split by comma to handle multiple recipients
        List<String> recipientList = recipientsString.split(',');
        for (String recipient : recipientList) {
            recipient = recipient.trim();
            if (String.isNotBlank(recipient)) {
                Map<String, String> parsed = parseEmailAddress(recipient);
                Map<String, Object> recipientObj = new Map<String, Object>();
                Map<String, Object> emailAddress = new Map<String, Object>();
                emailAddress.put('name', parsed.get('name'));
                emailAddress.put('address', parsed.get('address')); // CRITICAL: Use 'address' not 'email'
                recipientObj.put('emailAddress', emailAddress);
                recipients.add(recipientObj);
            }
        }

        return recipients;
    }

    /**
     * Extract headers from Gmail message payload
     */
    private static Map<String, String> extractHeaders(Map<String, Object> gmailMessage) {
        Map<String, String> headerMap = new Map<String, String>();

        Map<String, Object> payload = (Map<String, Object>) gmailMessage.get('payload');
        if (payload == null) return headerMap;

        List<Object> headers = (List<Object>) payload.get('headers');
        if (headers == null) return headerMap;

        for (Object headerObj : headers) {
            Map<String, Object> header = (Map<String, Object>) headerObj;
            String name = (String) header.get('name');
            String value = (String) header.get('value');
            headerMap.put(name, value);
        }

        return headerMap;
    }

    /**
     * Parse email address from "Name <email@example.com>" format
     * FIXED: Returns 'address' key instead of 'email' for compatibility
     */
    private static Map<String, String> parseEmailAddress(String emailString) {
        Map<String, String> result = new Map<String, String>();

        if (String.isBlank(emailString)) {
            result.put('name', '');
            result.put('address', ''); // FIXED: was 'email'
            return result;
        }

        // Pattern: "Name" <email@example.com> or just email@example.com
        if (emailString.contains('<')) {
            Integer startIndex = emailString.indexOf('<');
            Integer endIndex = emailString.indexOf('>');

            if (startIndex > 0 && endIndex > startIndex) {
                String name = emailString.substring(0, startIndex).trim();
                name = name.replace('"', ''); // Remove quotes - NO REGEX

                String email = emailString.substring(startIndex + 1, endIndex).trim();

                result.put('name', name);
                result.put('address', email); // FIXED: was 'email'
            } else {
                // Malformed, use whole string as both
                result.put('name', emailString);
                result.put('address', emailString);
            }
        } else {
            // Just email address without name
            result.put('name', emailString);
            result.put('address', emailString); // FIXED: was 'email'
        }

        return result;
    }

    /**
     * Extract body content from Gmail message
     * ENHANCED: Better multipart handling and fallback logic
     */
    private static String extractBody(Map<String, Object> gmailMessage) {
        Map<String, Object> payload = (Map<String, Object>) gmailMessage.get('payload');
        if (payload == null) {
            return '';
        }

        String mimeType = (String) payload.get('mimeType');

        // Try to get body from payload.body.data (simple messages)
        Map<String, Object> body = (Map<String, Object>) payload.get('body');
        if (body != null) {
            Integer bodySize = (Integer) body.get('size');

            String data = (String) body.get('data');
            if (String.isNotBlank(data)) {
                String decoded = decodeBase64Url(data);
                return decoded;
            }
        }

        // If not in body, check parts (multipart message)
        List<Object> parts = (List<Object>) payload.get('parts');
        if (parts != null) {
            return extractBodyFromParts(parts, 0);
        }

        return '';
    }

    // Maximum recursion depth to prevent stack overflow with deeply nested MIME
    private static final Integer MAX_MIME_DEPTH = 10;

    /**
     * Extract body from message parts (recursive with depth limit)
     * ENHANCED: Better handling of multipart/alternative and nested parts
     * PROTECTED: Depth limit prevents stack overflow on malformed emails
     */
    private static String extractBodyFromParts(List<Object> parts, Integer depth) {
        // Prevent stack overflow on deeply nested MIME structures
        if (depth > MAX_MIME_DEPTH) {
            return '';
        }

        String htmlContent = null;
        String textContent = null;

        for (Object partObj : parts) {
            if (partObj == null) continue;

            Map<String, Object> part = (Map<String, Object>) partObj;
            String mimeType = (String) part.get('mimeType');


            // Check for multipart types first and recurse
            if (mimeType != null && (mimeType.startsWith('multipart/') || 'multipart'.equals(mimeType))) {
                List<Object> nestedParts = (List<Object>) part.get('parts');
                if (nestedParts != null) {
                    String nestedContent = extractBodyFromParts(nestedParts, depth + 1);
                    // For multipart/alternative, collect the best version
                    if (String.isNotBlank(nestedContent)) {
                        if (nestedContent.contains('<html') || nestedContent.contains('<HTML')) {
                            htmlContent = nestedContent; // Prefer HTML from nested
                        } else if (htmlContent == null) {
                            textContent = nestedContent; // Use as text fallback
                        }
                    }
                }
            }
            // Direct content parts
            else if ('text/html'.equals(mimeType)) {
                Map<String, Object> body = (Map<String, Object>) part.get('body');
                if (body != null) {
                    String data = (String) body.get('data');
                    if (String.isNotBlank(data)) {
                        String decodedHtml = decodeBase64Url(data);
                        if (String.isNotBlank(decodedHtml)) {
                            htmlContent = decodedHtml;
                        }
                    }
                }
            } else if ('text/plain'.equals(mimeType)) {
                Map<String, Object> body = (Map<String, Object>) part.get('body');
                if (body != null) {
                    String data = (String) body.get('data');
                    if (String.isNotBlank(data)) {
                        String decodedText = decodeBase64Url(data);
                        if (String.isNotBlank(decodedText) && textContent == null) {
                            textContent = decodedText;
                        }
                    }
                }
            }
        }

        // Return the best content we found
        String result = '';
        if (String.isNotBlank(htmlContent)) {
            result = htmlContent;
        } else if (String.isNotBlank(textContent)) {
            result = textContent;
        }

        return result;
    }

    /**
     * Check if message has attachments
     */
    private static Boolean hasAttachments(Map<String, Object> gmailMessage) {
        Map<String, Object> payload = (Map<String, Object>) gmailMessage.get('payload');
        if (payload == null) return false;

        List<Object> parts = (List<Object>) payload.get('parts');
        if (parts == null) return false;

        return hasAttachmentsInParts(parts);
    }

    /**
     * Recursively check parts for attachments
     */
    private static Boolean hasAttachmentsInParts(List<Object> parts) {
        for (Object partObj : parts) {
            Map<String, Object> part = (Map<String, Object>) partObj;

            // Check if this part is an attachment
            String filename = (String) part.get('filename');
            if (String.isNotBlank(filename)) {
                return true;
            }

            // Check nested parts
            List<Object> nestedParts = (List<Object>) part.get('parts');
            if (nestedParts != null && hasAttachmentsInParts(nestedParts)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Decode Base64 URL-safe string (Gmail uses this encoding)
     */
    private static String decodeBase64Url(String encoded) {
        if (String.isBlank(encoded)) return '';

        // Replace URL-safe characters with standard Base64
        String base64 = encoded.replace('-', '+').replace('_', '/');

        // Add padding if needed
        Integer padding = Math.mod(4 - Math.mod(base64.length(), 4), 4);
        for (Integer i = 0; i < padding; i++) {
            base64 += '=';
        }

        try {
            Blob decodedBlob = EncodingUtil.base64Decode(base64);
            return decodedBlob.toString();
        } catch (Exception e) {
            return '';
        }
    }
}