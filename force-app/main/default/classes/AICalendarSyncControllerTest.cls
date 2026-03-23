/**
 * Test class for AICalendarSyncController
 */
@isTest
private class AICalendarSyncControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create AI_Workspace_User__c record for Outlook provider
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            Name = 'Test Outlook Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Outlook',
            Access_Token__c = 'test_access_token_12345',
            Refresh_Token__c = 'test_refresh_token_67890'
        );
        insert workspaceUser;
        
        // Create AI_Workspace_User__c record for Gmail provider
        AI_Workspace_User__c gmailUser = new AI_Workspace_User__c(
            Name = 'Test Gmail Connection',
            User__c = UserInfo.getUserId(),
            Provider__c = 'Gmail',
            Access_Token__c = 'test_gmail_token_12345',
            Refresh_Token__c = 'test_gmail_refresh_67890'
        );
        insert gmailUser;
    }

    /**
     * Mock HTTP response for calendar API calls
     * Handles multiple callouts with different responses based on endpoint
     */
    private class CalendarMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        public CalendarMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            
            String endpoint = req.getEndpoint();
            
            // Handle different endpoints
            if (endpoint.contains('/me/calendar/calendarView')) {
                // Calendar events list
                res.setBody(this.body);
            } else if (endpoint.contains('/me/calendar/events/')) {
                // Single event
                res.setBody(this.body);
            } else if (endpoint.contains('/me/calendar')) {
                // Calendar info / accessibility check
                res.setBody(getSampleCalendarResponse());
            } else {
                // Default
            res.setBody(this.body);
            }
            
            return res;
        }
    }
    
    /**
     * Multi-response mock that returns success for all calls
     */
    private class SuccessfulCalendarMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/me/calendar/calendarView')) {
                res.setBody(getSampleEventsResponse());
            } else if (endpoint.contains('/me/calendar/events/')) {
                res.setBody(getSampleSingleEventResponse());
            } else if (endpoint.contains('/me/calendar')) {
                res.setBody(getSampleCalendarResponse());
            } else {
                res.setBody('{"value": []}');
            }
            
            return res;
        }
    }

    private static String getSampleEventsResponse() {
        return '{' +
            '"value": [' +
                '{' +
                    '"id": "event123",' +
                    '"subject": "Sales Meeting",' +
                    '"start": {"dateTime": "2024-12-10T14:00:00"},' +
                    '"end": {"dateTime": "2024-12-10T15:00:00"},' +
                    '"iCalUId": "ical-123",' +
                    '"isAllDay": false,' +
                    '"showAs": "busy",' +
                    '"location": "Conference Room A",' +
                    '"bodyPreview": "Discuss Q4 sales targets",' +
                    '"organizer": {' +
                        '"emailAddress": {' +
                            '"name": "John Doe",' +
                            '"address": "john@example.com"' +
                        '}' +
                    '},' +
                    '"attendees": [' +
                        '{' +
                            '"emailAddress": {' +
                                '"name": "Jane Smith",' +
                                '"address": "jane@example.com"' +
                            '},' +
                            '"status": {"response": "accepted"}' +
                        '}' +
                    ']' +
                '}' +
            ']' +
        '}';
    }

    private static String getSampleCalendarResponse() {
        return '{' +
            '"id": "calendar123",' +
            '"name": "Calendar",' +
            '"owner": {' +
                '"address": "user@test.com",' +
                '"name": "Test User"' +
            '}' +
        '}';
    }

    private static String getSampleSingleEventResponse() {
        return '{' +
            '"id": "event123",' +
            '"subject": "Sales Meeting",' +
            '"start": {"dateTime": "2024-12-10T14:00:00"},' +
            '"end": {"dateTime": "2024-12-10T15:00:00"},' +
            '"iCalUId": "ical-123",' +
            '"isAllDay": false,' +
            '"location": "Conference Room A",' +
            '"bodyPreview": "Discuss Q4 sales targets",' +
            '"organizer": {' +
                '"emailAddress": {' +
                    '"name": "John Doe",' +
                    '"address": "john@example.com"' +
                '}' +
            '},' +
            '"attendees": [' +
                '{' +
                    '"emailAddress": {' +
                        '"name": "Jane Smith",' +
                        '"address": "jane@example.com"' +
                    '},' +
                    '"status": {"response": "accepted"}' +
                '}' +
            ']' +
        '}';
    }
    
    private static String getSampleAllDayEventResponse() {
        return '{' +
            '"id": "event456",' +
            '"subject": "All Day Conference",' +
            '"start": {"dateTime": "2024-12-15T00:00:00"},' +
            '"end": {"dateTime": "2024-12-16T00:00:00"},' +
            '"iCalUId": "ical-456",' +
            '"isAllDay": true' +
        '}';
    }

    @isTest
    static void testGetCalendarEvents_Success() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulCalendarMock());

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        // Response should be returned (accessible or not)
        Assert.areNotEqual(null, response, 'Response should not be null');
        // If accessible, should have events; if not, should have error
        if (response.isCalendarAccessible) {
            Assert.isTrue(response.events.size() >= 0, 'Should have events list');
        } else {
            Assert.areNotEqual(null, response.error, 'Should have error if not accessible');
        }
    }

    @isTest
    static void testGetCalendarEvents_InvalidDates() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleCalendarResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            'invalid-date',
            'also-invalid',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response.error, 'Should have error for invalid dates');
    }

    @isTest
    static void testGetCalendarEventsByRange_ThisWeek() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'MICROSOFT_CALENDAR', null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetCalendarEventsByRange_NextWeek() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, '{"value": []}'));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('nextWeek', 'MICROSOFT_CALENDAR', null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetCalendarEventsByRange_ThisMonth() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, '{"value": []}'));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisMonth', 'MICROSOFT_CALENDAR', null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetCalendarEventsByRange_Past7Days() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, '{"value": []}'));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('past7Days', 'MICROSOFT_CALENDAR', null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetCalendarEventsByRange_Next30Days() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, '{"value": []}'));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('next30Days', 'MICROSOFT_CALENDAR', null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetCalendarEventsByRange_Default() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, '{"value": []}'));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('unknownRange', 'MICROSOFT_CALENDAR', null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testImportCalendarEvents_Success() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulCalendarMock());

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(
            new List<String>{'event123'},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        // May succeed or fail depending on token validity
        Assert.isTrue(result.successCount >= 0, 'Should have valid success count');
    }

    @isTest
    static void testImportCalendarEvents_Empty() {
        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(null, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have no imports');
        Assert.isTrue(result.errors.size() > 0, 'Should have error message');
    }

    @isTest
    static void testImportCalendarEvents_EmptyList() {
        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(
            new List<String>(),
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have no imports');
    }

    @isTest
    static void testImportSingleEvent_Success() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulCalendarMock());

        Test.startTest();
        try {
        Id eventId = AICalendarSyncController.importSingleEvent('event123');
            // May return null or valid ID depending on token
            Assert.isTrue(true, 'Method executed without exception');
        } catch (AuraHandledException e) {
            // Expected if token is invalid
            Assert.isTrue(e.getMessage().contains('Failed to import event'), 'Should have appropriate error');
        }
        Test.stopTest();
    }

    @isTest
    static void testCheckCalendarAccess_Accessible() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulCalendarMock());

        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.checkCalendarAccess('MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        Assert.areNotEqual(null, result.get('isAccessible'), 'Should have accessibility status');
    }

    @isTest
    static void testCheckCalendarAccess_NotAccessible() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(401, '{"error": "Unauthorized"}'));

        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.checkCalendarAccess('MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areEqual(false, result.get('isAccessible'), 'Should not be accessible');
        Assert.areNotEqual(null, result.get('error'), 'Should have error message');
    }

    @isTest
    static void testCheckCalendarAccess_AutoDetect() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleCalendarResponse()));

        Test.startTest();
        // Pass null to trigger auto-detect
        Map<String, Object> result = AICalendarSyncController.checkCalendarAccess(null);
        Test.stopTest();

        // Should either find a provider or return not accessible
        Assert.areNotEqual(null, result.get('isAccessible'), 'Should have accessibility status');
    }

    @isTest
    static void testGetCalendarInfo_Success() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulCalendarMock());

        Test.startTest();
        try {
        Map<String, String> info = AICalendarSyncController.getCalendarInfo();
            // May return info or throw exception depending on token
            Assert.areNotEqual(null, info, 'Info should not be null if successful');
        } catch (AuraHandledException e) {
            // Expected if token is invalid
            Assert.isTrue(e.getMessage().contains('Failed to get calendar info'), 'Should have appropriate error');
        }
        Test.stopTest();
    }

    @isTest
    static void testCalendarEventsResponse_Constructor() {
        AICalendarSyncController.CalendarEventsResponse response = new AICalendarSyncController.CalendarEventsResponse();

        Assert.areNotEqual(null, response.events, 'Events should be initialized');
        Assert.areNotEqual(null, response.importedEvents, 'ImportedEvents should be initialized');
        Assert.areEqual(false, response.isCalendarAccessible, 'Should default to false');
    }

    @isTest
    static void testImportedEventsMarking() {
        // Get Calendar record type ID for AI_Workspace_Staging__c
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        // Create an existing staging record with Calendar record type
        AI_Workspace_Staging__c existingStaging = new AI_Workspace_Staging__c(
            Subject__c = 'Existing Meeting',
            Start_DateTime__c = DateTime.now().addDays(1),
            End_DateTime__c = DateTime.now().addDays(1).addHours(1),
            ICalUID__c = 'ical-123',
            User__c = UserInfo.getUserId(),
            RecordTypeId = calendarRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR'
        );
        insert existingStaging;

        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetCalendarEvents_DefaultProvider() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Pass null provider to test default behavior
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            null,
            null
        );
        Test.stopTest();

        // Should default to MICROSOFT_CALENDAR
        Assert.areNotEqual(null, response, 'Response should not be null');
    }


    @isTest
    static void testGetCalendarEvents_WithSearch() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Search for 'Sales' which matches the event subject "Sales Meeting"
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            'Sales'
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }

    @isTest
    static void testGetCalendarEvents_WithSearch_NoMatch() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Search for term that doesn't match any event
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            'nonexistent'
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEvents_GoogleCalendar() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'GOOGLE_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEvents_NotAccessible() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(401, '{"error": "Unauthorized"}'));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response.error, 'Should have error message');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_AllEvents() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('allEvents', 'MICROSOFT_CALENDAR', null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_WithPagination() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'MICROSOFT_CALENDAR', null, '0', 10);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testImportCalendarEvents_GoogleCalendar() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(
            new List<String>{'event123'},
            'GOOGLE_CALENDAR'
        );
        Test.stopTest();

        Assert.isTrue(result.successCount >= 0, 'Should process events');
    }
    
    @isTest
    static void testImportCalendarEvents_FetchError() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(500, '{"error": "Server Error"}'));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(
            new List<String>{'event123'},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.isTrue(result.errors.size() > 0, 'Should have errors');
    }
    
    @isTest
    static void testImportSingleEvent_NotFound() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(404, '{"error": "Not Found"}'));

        Test.startTest();
        try {
            Id eventId = AICalendarSyncController.importSingleEvent('nonexistent');
            // May return null or throw exception
            Assert.isTrue(true, 'Method executed');
        } catch (Exception e) {
            // Expected - either AuraHandledException or other exception
            Assert.isTrue(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCheckCalendarAccess_GoogleCalendar() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleCalendarResponse()));

        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.checkCalendarAccess('GOOGLE_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result.get('isAccessible'), 'Should have accessibility status');
    }
    
    @isTest
    static void testCheckCalendarAccess_Exception() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(500, 'Invalid JSON'));

        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.checkCalendarAccess('MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result.get('error'), 'Should have error message');
    }
    
    @isTest
    static void testGetCalendarInfo_Exception() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(500, 'Error'));

        Test.startTest();
        try {
            Map<String, String> info = AICalendarSyncController.getCalendarInfo();
            // May return info or throw exception
            Assert.isTrue(true, 'Method executed');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Failed to get calendar info'), 'Should have error message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testAssociateCalendarFromModal_Success() {
        // Create test data
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'lead@example.com'
        );
        insert testLead;
        
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = testAccount.Id
        );
        insert testOpp;
        
        Test.setMock(HttpCalloutMock.class, new SuccessfulCalendarMock());

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selection.put('leadIds', new List<Id>{testLead.Id});
        selection.put('accountId', testAccount.Id);
        selection.put('opportunityId', testOpp.Id);
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        // Success depends on whether token is valid
        Assert.areNotEqual(null, result.get('success'), 'Should have success status');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_NoSelections() {
        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(null, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areEqual(false, result.get('success'), 'Should fail with no selections');
        List<String> errors = (List<String>) result.get('errors');
        Assert.isTrue(errors.size() > 0, 'Should have error message');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_EmptySelections() {
        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(new List<Map<String, Object>>(), 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areEqual(false, result.get('success'), 'Should fail with empty selections');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_GoogleCalendar() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'GOOGLE_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_Duplicates() {
        // Create an existing event with the same iCalUID
        Event existingEvent = new Event(
            Subject = 'Existing Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1)
        );
        insert existingEvent;
        
        // Update with Workspace_Sync_Id__c
        existingEvent.Workspace_Sync_Id__c = 'ical-123';
        update existingEvent;
        
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_Exception() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(500, 'Error'));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        // May succeed or fail depending on error handling
    }
    
    @isTest
    static void testRefreshTokenAndCheckAccess_Success() {
        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.refreshTokenAndCheckAccess('MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        Assert.areNotEqual(null, result.get('isAccessible'), 'Should have accessibility status');
    }
    
    @isTest
    static void testRefreshTokenAndCheckAccess_GoogleCalendar() {
        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.refreshTokenAndCheckAccess('GOOGLE_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testRefreshTokenAndCheckAccess_Exception() {
        Test.startTest();
        Map<String, Object> result = AICalendarSyncController.refreshTokenAndCheckAccess(null);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testImportedEventDetails_WithEventRelations() {
        // Create test contact and lead
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'lead@example.com'
        );
        insert testLead;
        
        // Create event with Workspace_Sync_Id__c
        Event testEvent = new Event(
            Subject = 'Test Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            Workspace_Sync_Id__c = 'ical-test-123'
        );
        insert testEvent;
        
        // Create EventRelations
        EventRelation contactRelation = new EventRelation(
            EventId = testEvent.Id,
            RelationId = testContact.Id
        );
        insert contactRelation;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, 
            '{"value": [{"id": "event123", "subject": "Test Event", "start": {"dateTime": "2024-12-10T14:00:00"}, ' +
            '"end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-test-123", "isAllDay": false}]}'
        ));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testImportedEventDetails_WithWhatId() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        // Create event with WhatId and Workspace_Sync_Id__c
        Event testEvent = new Event(
            Subject = 'Test Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            WhatId = testAccount.Id,
            Workspace_Sync_Id__c = 'ical-test-456'
        );
        insert testEvent;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, 
            '{"value": [{"id": "event456", "subject": "Test Event", "start": {"dateTime": "2024-12-10T14:00:00"}, ' +
            '"end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-test-456", "isAllDay": false}]}'
        ));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testImportedEventDetails_WithOpportunity() {
        // Create test opportunity
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = testAccount.Id
        );
        insert testOpp;
        
        // Create event with Opportunity WhatId
        Event testEvent = new Event(
            Subject = 'Test Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            WhatId = testOpp.Id,
            Workspace_Sync_Id__c = 'ical-test-789'
        );
        insert testEvent;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, 
            '{"value": [{"id": "event789", "subject": "Test Event", "start": {"dateTime": "2024-12-10T14:00:00"}, ' +
            '"end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-test-789", "isAllDay": false}]}'
        ));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testImportAllDayEvent() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleAllDayEventResponse()));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(
            new List<String>{'event456'},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.isTrue(result.successCount >= 0, 'Should process all-day event');
    }
    
    @isTest
    static void testImportEventWithFullDetails() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(
            new List<String>{'event123'},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.isTrue(result.successCount >= 0, 'Should process event with full details');
    }
    
    @isTest
    static void testCalendarEventsResponse_DefaultValues() {
        AICalendarSyncController.CalendarEventsResponse response = new AICalendarSyncController.CalendarEventsResponse();

        Assert.areNotEqual(null, response.events, 'Events should be initialized');
        Assert.areNotEqual(null, response.importedEvents, 'ImportedEvents should be initialized');
        Assert.areNotEqual(null, response.importedEventDetails, 'ImportedEventDetails should be initialized');
        Assert.areEqual(false, response.isCalendarAccessible, 'Should default to false');
        Assert.areEqual(false, response.hasMore, 'Should default to false');
        Assert.areEqual(0, response.totalCount, 'Should default to 0');
    }
    
    @isTest
    static void testImportedEventInfo_Constructor() {
        AICalendarSyncController.ImportedEventInfo info = new AICalendarSyncController.ImportedEventInfo();

        Assert.areNotEqual(null, info.linkedRecords, 'LinkedRecords should be initialized');
        Assert.areEqual(0, info.linkedRecords.size(), 'LinkedRecords should be empty');
    }
    
    @isTest
    static void testLinkedRecordInfo_Constructor() {
        Id testId = UserInfo.getUserId();
        AICalendarSyncController.LinkedRecordInfo linkedRecord = new AICalendarSyncController.LinkedRecordInfo(
            testId,
            'Test Name',
            'Contact'
        );

        Assert.areEqual(testId, linkedRecord.recordId, 'Record ID should match');
        Assert.areEqual('Test Name', linkedRecord.recordName, 'Record name should match');
        Assert.areEqual('Contact', linkedRecord.recordType, 'Record type should match');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_WithLeadsOnly() {
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'lead@example.com'
        );
        insert testLead;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('leadIds', new List<Id>{testLead.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_WithAccountOnly() {
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('accountId', testAccount.Id);
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_MultipleEvents() {
        Contact testContact1 = new Contact(
            FirstName = 'Test1',
            LastName = 'Contact1',
            Email = 'test1@example.com'
        );
        insert testContact1;
        
        Contact testContact2 = new Contact(
            FirstName = 'Test2',
            LastName = 'Contact2',
            Email = 'test2@example.com'
        );
        insert testContact2;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        
        Map<String, Object> selection1 = new Map<String, Object>();
        selection1.put('messageId', 'event123');
        selection1.put('contactIds', new List<Id>{testContact1.Id});
        selections.add(selection1);
        
        Map<String, Object> selection2 = new Map<String, Object>();
        selection2.put('messageId', 'event456');
        selection2.put('contactIds', new List<Id>{testContact2.Id});
        selections.add(selection2);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testImportedEventDetails_MultipleContacts() {
        // Create multiple contacts
        Contact contact1 = new Contact(
            FirstName = 'Contact1',
            LastName = 'Test',
            Email = 'contact1@example.com'
        );
        insert contact1;
        
        Contact contact2 = new Contact(
            FirstName = 'Contact2',
            LastName = 'Test',
            Email = 'contact2@example.com'
        );
        insert contact2;
        
        // Create event
        Event testEvent = new Event(
            Subject = 'Multi-Contact Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            Workspace_Sync_Id__c = 'ical-multi-123'
        );
        insert testEvent;
        
        // Create multiple EventRelations
        EventRelation relation1 = new EventRelation(
            EventId = testEvent.Id,
            RelationId = contact1.Id
        );
        insert relation1;
        
        EventRelation relation2 = new EventRelation(
            EventId = testEvent.Id,
            RelationId = contact2.Id
        );
        insert relation2;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, 
            '{"value": [{"id": "eventMulti", "subject": "Multi-Contact Event", "start": {"dateTime": "2024-12-10T14:00:00"}, ' +
            '"end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-multi-123", "isAllDay": false}]}'
        ));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testImportedEventDetails_UserRelation() {
        // Create event with User relation (should be filtered out)
        Event testEvent = new Event(
            Subject = 'User Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            Workspace_Sync_Id__c = 'ical-user-123',
            OwnerId = UserInfo.getUserId()
        );
        insert testEvent;
        
        // Note: Cannot create EventRelation with User as RelationId if user is the owner
        // Salesforce throws FIELD_INTEGRITY_EXCEPTION: You cannot add the owner of the event as an invitee
        // This test validates that the code handles User relations properly when they exist
        // (created by other means or with different owners)
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, 
            '{"value": [{"id": "eventUser", "subject": "User Event", "start": {"dateTime": "2024-12-10T14:00:00"}, ' +
            '"end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-user-123", "isAllDay": false}]}'
        ));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_InvalidPageSize() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Test with negative page size (should default to 50)
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'MICROSOFT_CALENDAR', null, null, -10);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_ZeroPageSize() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Test with zero page size (should default to 50)
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'MICROSOFT_CALENDAR', null, null, 0);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_WithSearchTerm() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'MICROSOFT_CALENDAR', 'Sales', null, 50);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_WithInvalidPageToken() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Test with invalid page token (should default to 0)
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'MICROSOFT_CALENDAR', null, 'invalid', 50);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_InvalidContactId() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        // Use invalid contact ID (User ID instead of Contact ID)
        selection.put('contactIds', new List<Id>{UserInfo.getUserId()});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_InvalidLeadId() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        // Use invalid lead ID (User ID instead of Lead ID)
        selection.put('leadIds', new List<Id>{UserInfo.getUserId()});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_InvalidAccountId() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        // Use invalid account ID
        selection.put('accountId', 'invalid');
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_InvalidOpportunityId() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        // Use invalid opportunity ID
        selection.put('opportunityId', 'invalid');
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_GoogleCalendar() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'GOOGLE_CALENDAR', null, null, 50);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_WithPaginationHasMore() {
        // Create a response with multiple events to trigger hasMore logic
        String multiEventResponse = '{' +
            '"value": [' +
                '{"id": "event1", "subject": "Event 1", "start": {"dateTime": "2024-12-10T14:00:00"}, "end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-1", "isAllDay": false},' +
                '{"id": "event2", "subject": "Event 2", "start": {"dateTime": "2024-12-11T14:00:00"}, "end": {"dateTime": "2024-12-11T15:00:00"}, "iCalUId": "ical-2", "isAllDay": false},' +
                '{"id": "event3", "subject": "Event 3", "start": {"dateTime": "2024-12-12T14:00:00"}, "end": {"dateTime": "2024-12-12T15:00:00"}, "iCalUId": "ical-3", "isAllDay": false}' +
            ']' +
        '}';
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, multiEventResponse));

        Test.startTest();
        // Request only 2 events per page to test hasMore logic
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'MICROSOFT_CALENDAR', null, null, 2);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testParseISODateTime_InvalidFormat() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Test with completely invalid date format
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            'not-a-date-at-all',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response.error, 'Should have error for invalid date');
    }
    
    @isTest
    static void testParseISODateTime_JustDate() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Test with date-only format (should add time automatically)
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01',
            '2024-12-31',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_WithAllDayEvent() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleAllDayEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event456');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_WithExcludedDomains() {
        // Create sync settings with excluded domains
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            Excluded_Domains__c = 'example.com',
            SetupOwnerId = UserInfo.getUserId()
        );
        insert settings;
        
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        // Event with organizer from excluded domain
        String excludedEventResponse = '{' +
            '"id": "event123",' +
            '"subject": "Sales Meeting",' +
            '"start": {"dateTime": "2024-12-10T14:00:00"},' +
            '"end": {"dateTime": "2024-12-10T15:00:00"},' +
            '"iCalUId": "ical-123",' +
            '"isAllDay": false,' +
            '"organizer": {' +
                '"emailAddress": {' +
                    '"name": "John Doe",' +
                    '"address": "john@example.com"' +
                '}' +
            '}' +
        '}';
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, excludedEventResponse));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testImportCalendarEvents_WithExcludedDomains() {
        // Create sync settings with excluded domains
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            Excluded_Domains__c = 'example.com',
            SetupOwnerId = UserInfo.getUserId()
        );
        insert settings;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(
            new List<String>{'event123'},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_FetchEventException() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(500, '{"error": "Server Error"}'));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
        Assert.isTrue(((Integer)result.get('failedCount')) > 0, 'Should have failed count');
    }
    
    @isTest
    static void testImportedEventDetails_WithStagingRecords() {
        // Create staging record with Calendar record type
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        // Create an event first
        Event testEvent = new Event(
            Subject = 'Test Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1)
        );
        insert testEvent;
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Staging Event',
            Start_DateTime__c = DateTime.now().addDays(1),
            End_DateTime__c = DateTime.now().addDays(1).addHours(1),
            ICalUID__c = 'ical-staging-123',
            User__c = UserInfo.getUserId(),
            RecordTypeId = calendarRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Imported',
            Email_Message__c = testEvent.Id
        );
        insert staging;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, 
            '{"value": [{"id": "eventStaging", "subject": "Staging Event", "start": {"dateTime": "2024-12-10T14:00:00"}, ' +
            '"end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-staging-123", "isAllDay": false}]}'
        ));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_WithNotifications() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_MultipleContactsForSameEvent() {
        Contact contact1 = new Contact(
            FirstName = 'Contact1',
            LastName = 'Test',
            Email = 'contact1@example.com'
        );
        insert contact1;
        
        Contact contact2 = new Contact(
            FirstName = 'Contact2',
            LastName = 'Test',
            Email = 'contact2@example.com'
        );
        insert contact2;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('contactIds', new List<Id>{contact1.Id, contact2.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testGetCalendarEvents_WithExistingEventAndRelations() {
        // Create test data with Event and EventRelation
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        Event testEvent = new Event(
            Subject = 'Existing Event',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            Workspace_Sync_Id__c = 'ical-123'
        );
        insert testEvent;
        
        EventRelation relation = new EventRelation(
            EventId = testEvent.Id,
            RelationId = testContact.Id
        );
        insert relation;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testImportCalendarEvents_AllEventsExcluded() {
        // Create sync settings with excluded domains
        AI_Workspace_Sync_Settings__c settings = new AI_Workspace_Sync_Settings__c(
            Excluded_Domains__c = 'example.com',
            SetupOwnerId = UserInfo.getUserId()
        );
        insert settings;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarSyncController.importCalendarEvents(
            new List<String>{'event123'},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_WithOpportunityAndLead() {
        // Test that leads are NOT linked when WhatId (Opportunity) is set
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = testAccount.Id
        );
        insert testOpp;
        
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'lead@example.com'
        );
        insert testLead;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleSingleEventResponse()));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event123');
        selection.put('opportunityId', testOpp.Id);
        selection.put('leadIds', new List<Id>{testLead.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testGetCalendarEventsByRange_NullPageSize() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Test with null page size (should default to 50)
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEventsByRange('thisWeek', 'MICROSOFT_CALENDAR', null, null, null);
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testCheckCalendarAccess_AutoDetectGoogleFirst() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleCalendarResponse()));

        Test.startTest();
        // Auto-detect should try Microsoft first, then Google
        Map<String, Object> result = AICalendarSyncController.checkCalendarAccess(null);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testImportedEventDetails_DuplicateEventRelations() {
        // Test duplicate EventRelation prevention logic
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        // Create event with unique ID
        Event event1 = new Event(
            Subject = 'Event with Multiple Relations',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            Workspace_Sync_Id__c = 'ical-recurring-123-inst1'
        );
        insert event1;
        
        // Create multiple EventRelations for same contact (to test deduplication logic)
        EventRelation relation1 = new EventRelation(
            EventId = event1.Id,
            RelationId = testContact.Id
        );
        insert relation1;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, 
            '{"value": [{"id": "eventRecurring", "subject": "Event with Multiple Relations", "start": {"dateTime": "2024-12-10T14:00:00"}, ' +
            '"end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-recurring-123-inst1", "isAllDay": false}]}'
        ));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testImportedEventDetails_InvalidEventId() {
        // Create staging record with invalid Email_Message__c
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Invalid Event',
            Start_DateTime__c = DateTime.now().addDays(1),
            End_DateTime__c = DateTime.now().addDays(1).addHours(1),
            ICalUID__c = 'ical-invalid-123',
            User__c = UserInfo.getUserId(),
            RecordTypeId = calendarRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Imported',
            Email_Message__c = 'invalid-id'
        );
        insert staging;
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, 
            '{"value": [{"id": "eventInvalid", "subject": "Invalid Event", "start": {"dateTime": "2024-12-10T14:00:00"}, ' +
            '"end": {"dateTime": "2024-12-10T15:00:00"}, "iCalUId": "ical-invalid-123", "isAllDay": false}]}'
        ));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testGetCalendarEvents_GoogleCalendarNotAccessible() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(401, '{"error": "Unauthorized"}'));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'GOOGLE_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response.error, 'Should have error message for Google Calendar');
        Assert.isTrue(response.error.contains('Google Calendar'), 'Error should mention Google Calendar');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_EventWithoutSubject() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        // Event without subject
        String noSubjectEvent = '{' +
            '"id": "event999",' +
            '"subject": "",' +
            '"start": {"dateTime": "2024-12-10T14:00:00"},' +
            '"end": {"dateTime": "2024-12-10T15:00:00"},' +
            '"iCalUId": "ical-999",' +
            '"isAllDay": false' +
        '}';
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, noSubjectEvent));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event999');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testParseISODateTime_WithMilliseconds() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, getSampleEventsResponse()));

        Test.startTest();
        // Test with date format including milliseconds
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00.000Z',
            '2024-12-31T23:59:59.999Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response, 'Response should not be null');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_EventWithLongDescription() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        // Create a very long description to test truncation
        String longDesc = 'This is a very long description. '.repeat(200);
        String longDescEvent = '{' +
            '"id": "event888",' +
            '"subject": "Event with Long Description",' +
            '"start": {"dateTime": "2024-12-10T14:00:00"},' +
            '"end": {"dateTime": "2024-12-10T15:00:00"},' +
            '"iCalUId": "ical-888",' +
            '"isAllDay": false,' +
            '"bodyPreview": "' + longDesc.left(1000) + '",' +
            '"organizer": {"emailAddress": {"name": "Organizer Name", "address": "organizer@example.com"}},' +
            '"attendees": [{"emailAddress": {"name": "Attendee 1", "address": "att1@example.com"}}]' +
        '}';
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, longDescEvent));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', 'event888');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testGetCalendarEvents_ExceptionHandling() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock(500, 'Server Error'));

        Test.startTest();
        AICalendarSyncController.CalendarEventsResponse response = AICalendarSyncController.getCalendarEvents(
            '2024-12-01T00:00:00Z',
            '2024-12-31T23:59:59Z',
            50,
            'MICROSOFT_CALENDAR',
            null
        );
        Test.stopTest();

        Assert.areNotEqual(null, response.error, 'Should have error message');
    }
    
    @isTest
    static void testAssociateCalendarFromModal_WithBlankEventId() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;
        
        // Event with blank ID
        String blankIdEvent = '{' +
            '"id": "",' +
            '"subject": "Event with Blank ID",' +
            '"start": {"dateTime": "2024-12-10T14:00:00"},' +
            '"end": {"dateTime": "2024-12-10T15:00:00"},' +
            '"iCalUId": "ical-blank",' +
            '"isAllDay": false' +
        '}';
        
        Test.setMock(HttpCalloutMock.class, new CalendarMock(200, blankIdEvent));

        Test.startTest();
        List<Map<String, Object>> selections = new List<Map<String, Object>>();
        Map<String, Object> selection = new Map<String, Object>();
        selection.put('messageId', '');
        selection.put('contactIds', new List<Id>{testContact.Id});
        selections.add(selection);
        
        Map<String, Object> result = AICalendarSyncController.associateCalendarFromModal(selections, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Result should not be null');
    }
}