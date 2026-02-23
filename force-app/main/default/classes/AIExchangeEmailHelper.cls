public with sharing class AIExchangeEmailHelper {

    /**
     * Parse email date from email data object
     * Extracts receivedDateTime or sentDateTime and converts to Date
     */
    public static Date parseEmailDate(Map<String, Object> emailData) {
        // Try receivedDateTime first
        Object receivedDateTime = emailData.get('receivedDateTime');
        if (receivedDateTime != null) {
            try {
                String dateStr = String.valueOf(receivedDateTime);
                // Parse ISO 8601 date format (e.g., 2024-01-15T10:30:00Z)
                DateTime dt = DateTime.valueOf(dateStr.replace('T', ' ').replace('Z', ''));
                return dt.date();
            } catch (Exception e) {
                // Fall through to try other fields
            }
        }

        // Try sentDateTime
        Object sentDateTime = emailData.get('sentDateTime');
        if (sentDateTime != null) {
            try {
                String dateStr = String.valueOf(sentDateTime);
                DateTime dt = DateTime.valueOf(dateStr.replace('T', ' ').replace('Z', ''));
                return dt.date();
            } catch (Exception e) {
                // Fall through to default
            }
        }

        // Try createdDateTime
        Object createdDateTime = emailData.get('createdDateTime');
        if (createdDateTime != null) {
            try {
                String dateStr = String.valueOf(createdDateTime);
                DateTime dt = DateTime.valueOf(dateStr.replace('T', ' ').replace('Z', ''));
                return dt.date();
            } catch (Exception e) {
                // Fall through to default
            }
        }

        // Default to today if no valid date found
        return Date.today();
    }

    /**
     * Strips HTML tags from content using simple character-by-character parsing
     * NO REGEX - avoids "regex too complicated" errors
     */
    public static String stripHtml(String html) {
        if (String.isBlank(html)) return '';

        // Use Salesforce built-in method - no regex
        String result = html.stripHtmlTags();

        // Decode common HTML entities using simple replace (not replaceAll)
        result = decodeHtmlEntities(result);

        return result.trim();
    }

    /**
     * Advanced HTML stripping - now simplified to just use stripHtmlTags
     * NO REGEX - stores content as-is with minimal processing
     */
    public static String stripHtmlAdvanced(String html) {
        if (String.isBlank(html)) return '';

        // Use Salesforce built-in method - no regex
        String result = html.stripHtmlTags();

        // Decode HTML entities
        result = decodeHtmlEntities(result);

        // Simple whitespace cleanup without regex
        result = normalizeWhitespace(result);

        return result.trim();
    }

    /**
     * Creates clean HTML - now returns content as-is
     * Email body is stored with original HTML formatting
     * NO REGEX
     */
    public static String cleanHtml(String html) {
        if (String.isBlank(html)) return '';

        // Return HTML as-is - EmailMessage field supports HTML content
        // No processing needed - avoids regex complexity errors
        return html;
    }

    /**
     * Decode HTML entities using simple String.replace() - NO REGEX
     */
    private static String decodeHtmlEntities(String text) {
        if (String.isBlank(text)) return text;

        // Use replace() not replaceAll() - no regex
        text = text.replace('&nbsp;', ' ');
        text = text.replace('&amp;', '&');
        text = text.replace('&lt;', '<');
        text = text.replace('&gt;', '>');
        text = text.replace('&quot;', '"');
        text = text.replace('&#39;', '\'');
        text = text.replace('&apos;', '\'');
        text = text.replace('&mdash;', '—');
        text = text.replace('&ndash;', '–');
        text = text.replace('&ldquo;', '"');
        text = text.replace('&rdquo;', '"');
        text = text.replace('&lsquo;', '\'');
        text = text.replace('&rsquo;', '\'');
        text = text.replace('&hellip;', '...');
        text = text.replace('&#8217;', '\'');
        text = text.replace('&#8220;', '"');
        text = text.replace('&#8221;', '"');
        text = text.replace('&#8211;', '–');
        text = text.replace('&#8212;', '—');
        text = text.replace('&#160;', ' ');
        text = text.replace('&#x27;', '\'');
        text = text.replace('&#x2F;', '/');
        text = text.replace('&#60;', '<');
        text = text.replace('&#62;', '>');

        return text;
    }

    /**
     * Normalize whitespace without regex
     * Collapses multiple spaces into single space
     */
    private static String normalizeWhitespace(String text) {
        if (String.isBlank(text)) return text;

        // Simple approach: split by whitespace and rejoin
        List<String> parts = new List<String>();
        String currentWord = '';

        for (Integer i = 0; i < text.length(); i++) {
            String ch = text.substring(i, i + 1);
            if (ch == ' ' || ch == '\t') {
                if (String.isNotBlank(currentWord)) {
                    parts.add(currentWord);
                    currentWord = '';
                }
            } else if (ch == '\n' || ch == '\r') {
                if (String.isNotBlank(currentWord)) {
                    parts.add(currentWord);
                    currentWord = '';
                }
                // Preserve newlines
                if (parts.isEmpty() || parts[parts.size() - 1] != '\n') {
                    parts.add('\n');
                }
            } else {
                currentWord += ch;
            }
        }

        if (String.isNotBlank(currentWord)) {
            parts.add(currentWord);
        }

        // Rejoin with single spaces, preserving newlines
        String result = '';
        for (Integer i = 0; i < parts.size(); i++) {
            String part = parts[i];
            if (part == '\n') {
                result += '\n';
            } else {
                if (String.isNotBlank(result) && !result.endsWith('\n')) {
                    result += ' ';
                }
                result += part;
            }
        }

        return result;
    }

    /**
     * Truncates field to maximum length
     */
    public static String truncateField(String value, Integer maxLength) {
        if (String.isBlank(value)) return value;
        if (value.length() <= maxLength) return value;

        return value.substring(0, maxLength);
    }

    /**
     * Parses ISO 8601 datetime from Graph API
     */
    public static DateTime parseDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) return null;

        // Graph API returns ISO 8601: "2024-05-19T14:30:00Z"
        return (DateTime) JSON.deserialize('"' + dateTimeStr + '"', DateTime.class);
    }
}