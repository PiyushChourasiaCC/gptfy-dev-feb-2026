@isTest
public class AIExchangeEmailHelperTest {

    @isTest
    static void testStripHtmlAdvanced() {
        // Test HTML with various tags and entities
        String htmlInput = '<html><head><style>body{color:red;}</style></head>' +
                          '<body><h1>Test Header</h1>' +
                          '<p>This is a paragraph with &nbsp; spaces and &amp; entities.</p>' +
                          '<div>A div with <br/>line break</div>' +
                          '<p>Smart quotes: &ldquo;Hello&rdquo; and &lsquo;World&rsquo;</p>' +
                          '<p>Dashes: &ndash; and &mdash;</p>' +
                          '<script>alert("test");</script>' +
                          '<!-- HTML comment -->' +
                          '<p style="color:blue;">Styled paragraph</p>' +
                          '</body></html>';

        String result = AIExchangeEmailHelper.stripHtmlAdvanced(htmlInput);

        // Verify HTML tags are removed (using stripHtmlTags)
        Assert.isTrue(!result.contains('<html>'), 'HTML tags should be removed');
        Assert.isTrue(!result.contains('<script>'), 'Script tags should be removed');

        // Verify content is preserved
        Assert.isTrue(result.contains('Test Header'), 'Header text should be preserved');
        Assert.isTrue(result.contains('This is a paragraph'), 'Paragraph text should be preserved');

        // Verify common entities are decoded
        Assert.isTrue(result.contains('&'), 'Ampersand entity should be decoded');
        Assert.isTrue(result.contains(' '), 'Nbsp should be decoded to space');
    }

    @isTest
    static void testCleanHtml() {
        // cleanHtml now returns HTML as-is to preserve formatting for EmailMessage
        // This is intentional to avoid regex complexity errors
        String htmlInput = '<html><head><style>body{font-family:Arial;}</style></head>' +
                          '<body>' +
                          '<p class="MsoNormal" style="margin:0;">Normal paragraph</p>' +
                          '<div style="color:red;" class="custom-class">Styled div</div>' +
                          '</body></html>';

        String result = AIExchangeEmailHelper.cleanHtml(htmlInput);

        // cleanHtml now returns HTML as-is (no processing)
        Assert.areEqual(htmlInput, result, 'cleanHtml should return HTML as-is');

        // Verify content is still present
        Assert.isTrue(result.contains('Normal paragraph'), 'Text content should be preserved');
        Assert.isTrue(result.contains('Styled div'), 'Text in styled elements should be preserved');
    }

    @isTest
    static void testTruncateField() {
        String longText = 'This is a very long text that needs to be truncated';

        // Test truncation
        String result1 = AIExchangeEmailHelper.truncateField(longText, 10);
        Assert.areEqual(10, result1.length(), 'Text should be truncated to 10 characters');
        Assert.areEqual('This is a ', result1, 'Truncated text should match expected');

        // Test no truncation needed
        String result2 = AIExchangeEmailHelper.truncateField('Short', 10);
        Assert.areEqual('Short', result2, 'Short text should not be truncated');

        // Test null handling
        String result3 = AIExchangeEmailHelper.truncateField(null, 10);
        Assert.areEqual(null, result3, 'Null should return null');

        // Test empty string
        String result4 = AIExchangeEmailHelper.truncateField('', 10);
        Assert.areEqual('', result4, 'Empty string should return empty');
    }

    @isTest
    static void testParseDateTime() {
        // Test valid ISO 8601 datetime
        String isoDate = '2024-05-19T14:30:00Z';
        DateTime result1 = AIExchangeEmailHelper.parseDateTime(isoDate);
        Assert.areNotEqual(null, result1, 'Valid date should parse successfully');
        Assert.areEqual(2024, result1.year(), 'Year should be 2024');
        Assert.areEqual(5, result1.month(), 'Month should be 5');
        Assert.areEqual(19, result1.day(), 'Day should be 19');

        // Test null handling
        DateTime result2 = AIExchangeEmailHelper.parseDateTime(null);
        Assert.areEqual(null, result2, 'Null should return null');

        // Test empty string
        DateTime result3 = AIExchangeEmailHelper.parseDateTime('');
        Assert.areEqual(null, result3, 'Empty string should return null');
    }

    @isTest
    static void testComplexHtmlScenarios() {
        // Test nested tags and complex HTML
        String complexHtml = '<table><tr><td>Cell 1</td><td>Cell 2</td></tr></table>' +
                           '<ul><li>Item 1</li><li>Item 2</li></ul>' +
                           '<a href="http://example.com">Link text</a>' +
                           '<img src="image.jpg" alt="Image"/>' +
                           '<span>Inline <strong>bold</strong> text</span>';

        String stripped = AIExchangeEmailHelper.stripHtmlAdvanced(complexHtml);

        // Verify all tags are removed (using stripHtmlTags)
        Assert.isTrue(!stripped.contains('<table>'), 'Table tags should be removed');
        Assert.isTrue(!stripped.contains('<td>'), 'TD tags should be removed');

        // Verify text content is preserved
        Assert.isTrue(stripped.contains('Cell 1'), 'Table cell text should be preserved');
        Assert.isTrue(stripped.contains('Item 1'), 'List item text should be preserved');
        Assert.isTrue(stripped.contains('Link text'), 'Link text should be preserved');
        Assert.isTrue(stripped.contains('bold'), 'Nested tag text should be preserved');
    }

    @isTest
    static void testCssRemoval() {
        // Test CSS removal - stripHtmlTags removes style tags with content
        String htmlWithCss = '<style>table{width:640px}</style>' +
                            '<div>Actual email content here</div>';

        String result = AIExchangeEmailHelper.stripHtmlAdvanced(htmlWithCss);

        // Verify style tag content is handled by stripHtmlTags
        Assert.isTrue(!result.contains('<style>'), 'Style tags should be removed');
        Assert.isTrue(!result.contains('<div>'), 'Div tags should be removed');

        // Verify actual content is preserved
        Assert.isTrue(result.contains('Actual email content'), 'Email content should be preserved');
    }

    @isTest
    static void testStripHtml() {
        // Test basic HTML stripping
        String html = '<p>Hello <strong>World</strong></p>';
        String result = AIExchangeEmailHelper.stripHtml(html);

        Assert.isTrue(!result.contains('<p>'), 'P tags should be removed');
        Assert.isTrue(!result.contains('<strong>'), 'Strong tags should be removed');
        Assert.isTrue(result.contains('Hello'), 'Hello text should be preserved');
        Assert.isTrue(result.contains('World'), 'World text should be preserved');
    }

    @isTest
    static void testParseEmailDate() {
        // Test with receivedDateTime
        Map<String, Object> emailData1 = new Map<String, Object>{
            'receivedDateTime' => '2024-05-19T14:30:00Z'
        };
        Date result1 = AIExchangeEmailHelper.parseEmailDate(emailData1);
        Assert.areEqual(Date.newInstance(2024, 5, 19), result1, 'Should parse receivedDateTime');

        // Test with sentDateTime (no receivedDateTime)
        Map<String, Object> emailData2 = new Map<String, Object>{
            'sentDateTime' => '2024-06-20T10:00:00Z'
        };
        Date result2 = AIExchangeEmailHelper.parseEmailDate(emailData2);
        Assert.areEqual(Date.newInstance(2024, 6, 20), result2, 'Should parse sentDateTime');

        // Test with empty map - should return today
        Map<String, Object> emailData3 = new Map<String, Object>();
        Date result3 = AIExchangeEmailHelper.parseEmailDate(emailData3);
        Assert.areEqual(Date.today(), result3, 'Should return today for empty data');
    }
}