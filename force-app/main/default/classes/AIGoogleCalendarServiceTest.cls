/**
 * Test class for AIGoogleCalendarService
 * Tests Google Calendar API integration
 */
@isTest
public class AIGoogleCalendarServiceTest {

    /**
     * Helper method to setup workspace user with Gmail/Google token
     */
    private static void setupWorkspaceUser() {
        AI_Workspace_User__c workspaceUser = new AI_Workspace_User__c(
            User__c = UserInfo.getUserId(),
            Access_Token__c = 'test_access_token_12345',
            Refresh_Token__c = 'test_refresh_token_12345',
            Provider__c = 'GMAIL'
        );
        insert workspaceUser;
    }

    /**
     * Test getEvents with basic parameters
     */
    @isTest
    static void testGetEvents_Success() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEvents(startDate, endDate, 50, null);
        Test.stopTest();
        
        Assert.isTrue(events.size() > 0, 'Should return events');
        Assert.areEqual('event_1', events[0].eventId, 'Should have correct event ID');
    }

    /**
     * Test getEvents with search term
     */
    @isTest
    static void testGetEvents_WithSearchTerm() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEvents(startDate, endDate, 50, 'meeting');
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should return events');
    }

    /**
     * Test getEvents with null maxResults
     */
    @isTest
    static void testGetEvents_NullMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEvents(startDate, endDate, null, null);
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should return events with default max results');
    }

    /**
     * Test getEvents with zero maxResults
     */
    @isTest
    static void testGetEvents_ZeroMaxResults() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEvents(startDate, endDate, 0, null);
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should return events with default max results');
    }

    /**
     * Test getEvents with API error
     */
    @isTest
    static void testGetEvents_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(401));
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        try {
            List<AIMicrosoftCalendarService.CalendarEvent> events = 
                AIGoogleCalendarService.getEvents(startDate, endDate, 50, null);
            Assert.fail('Should throw CalendarServiceException');
        } catch (AIGoogleCalendarService.CalendarServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch calendar events'), 
                'Should throw exception with error message');
        }
        Test.stopTest();
    }

    /**
     * Test getEvents with generic exception
     */
    @isTest
    static void testGetEvents_GenericException() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        try {
            List<AIMicrosoftCalendarService.CalendarEvent> events = 
                AIGoogleCalendarService.getEvents(startDate, endDate, 50, null);
            Assert.fail('Should throw CalendarServiceException');
        } catch (AIGoogleCalendarService.CalendarServiceException e) {
            Assert.isTrue(e.getMessage().contains('Google Calendar service error'), 
                'Should wrap generic exception');
        }
        Test.stopTest();
    }

    /**
     * Test getEventsWithOffset with basic parameters
     */
    @isTest
    static void testGetEventsWithOffset_Success() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEventsWithOffset(startDate, endDate, 10, 0, null);
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should return events');
    }

    /**
     * Test getEventsWithOffset with offset
     */
    @isTest
    static void testGetEventsWithOffset_WithOffset() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEventsWithOffset(startDate, endDate, 5, 1, null);
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should return events with offset');
    }

    /**
     * Test getEventsWithOffset with null parameters
     */
    @isTest
    static void testGetEventsWithOffset_NullParameters() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEventsWithOffset(startDate, endDate, null, null, null);
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should handle null parameters');
    }

    /**
     * Test getEventsWithOffset with negative offset
     */
    @isTest
    static void testGetEventsWithOffset_NegativeOffset() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEventsWithOffset(startDate, endDate, 10, -5, null);
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should handle negative offset');
    }

    /**
     * Test getEventsWithOffset with search term
     */
    @isTest
    static void testGetEventsWithOffset_WithSearchTerm() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarEventsResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEventsWithOffset(startDate, endDate, 10, 0, 'meeting');
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should return events with search term');
    }

    /**
     * Test getEventsWithOffset with API error
     */
    @isTest
    static void testGetEventsWithOffset_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(500));
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        try {
            List<AIMicrosoftCalendarService.CalendarEvent> events = 
                AIGoogleCalendarService.getEventsWithOffset(startDate, endDate, 10, 0, null);
            Assert.fail('Should throw CalendarServiceException');
        } catch (AIGoogleCalendarService.CalendarServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch calendar events'), 
                'Should throw exception');
        }
        Test.stopTest();
    }

    /**
     * Test getEvent with valid event ID
     */
    @isTest
    static void testGetEvent_Success() {
        Test.setMock(HttpCalloutMock.class, new MockSingleEventResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event, 'Should return event');
        Assert.areEqual('event_123', event.eventId, 'Should have correct event ID');
    }

    /**
     * Test getEvent with API error
     */
    @isTest
    static void testGetEvent_ApiError() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse(404));
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            AIMicrosoftCalendarService.CalendarEvent event = 
                AIGoogleCalendarService.getEvent('invalid_id');
            Assert.fail('Should throw CalendarServiceException');
        } catch (AIGoogleCalendarService.CalendarServiceException e) {
            Assert.isTrue(e.getMessage().contains('Failed to fetch event'), 
                'Should throw exception');
        }
        Test.stopTest();
    }

    /**
     * Test getEvent with generic exception
     */
    @isTest
    static void testGetEvent_GenericException() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        try {
            AIMicrosoftCalendarService.CalendarEvent event = 
                AIGoogleCalendarService.getEvent('event_123');
            Assert.fail('Should throw CalendarServiceException');
        } catch (AIGoogleCalendarService.CalendarServiceException e) {
            Assert.isTrue(e.getMessage().contains('Error fetching event'), 
                'Should wrap generic exception');
        }
        Test.stopTest();
    }

    /**
     * Test isCalendarAccessible with valid credentials
     */
    @isTest
    static void testIsCalendarAccessible_Success() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarAccessibleResponse(200));
        setupWorkspaceUser();
        
        Test.startTest();
        Boolean isAccessible = AIGoogleCalendarService.isCalendarAccessible();
        Test.stopTest();
        
        Assert.areEqual(true, isAccessible, 'Should return true for accessible calendar');
    }

    /**
     * Test isCalendarAccessible with invalid credentials
     */
    @isTest
    static void testIsCalendarAccessible_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarAccessibleResponse(401));
        setupWorkspaceUser();
        
        Test.startTest();
        Boolean isAccessible = AIGoogleCalendarService.isCalendarAccessible();
        Test.stopTest();
        
        Assert.areEqual(false, isAccessible, 'Should return false for inaccessible calendar');
    }

    /**
     * Test isCalendarAccessible with exception
     */
    @isTest
    static void testIsCalendarAccessible_Exception() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        Boolean isAccessible = AIGoogleCalendarService.isCalendarAccessible();
        Test.stopTest();
        
        Assert.areEqual(false, isAccessible, 'Should return false on exception');
    }

    /**
     * Test getCalendarInfo success
     */
    @isTest
    static void testGetCalendarInfo_Success() {
        Test.setMock(HttpCalloutMock.class, new MockCalendarInfoResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        Map<String, String> info = AIGoogleCalendarService.getCalendarInfo();
        Test.stopTest();
        
        Assert.areEqual('user@example.com', info.get('ownerEmail'), 'Should return owner email');
        Assert.areEqual('Google Calendar', info.get('name'), 'Should return calendar name');
    }

    /**
     * Test getCalendarInfo with exception
     */
    @isTest
    static void testGetCalendarInfo_Exception() {
        Test.setMock(HttpCalloutMock.class, new MockExceptionResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        Map<String, String> info = AIGoogleCalendarService.getCalendarInfo();
        Test.stopTest();
        
        Assert.isNotNull(info, 'Should return empty map on exception');
    }

    /**
     * Test parsing all-day event
     */
    @isTest
    static void testParseEvent_AllDayEvent() {
        Test.setMock(HttpCalloutMock.class, new MockAllDayEventResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEvents(startDate, endDate, 50, null);
        Test.stopTest();
        
        Assert.isTrue(events.size() > 0, 'Should return events');
        Assert.areEqual(true, events[0].isAllDay, 'Should be all-day event');
    }

    /**
     * Test parsing event with attendees
     */
    @isTest
    static void testParseEvent_WithAttendees() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithAttendeesResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isTrue(event.attendees.size() > 0, 'Should have attendees');
        Assert.areEqual('attendee@example.com', event.attendees[0].email, 'Should have correct attendee email');
    }

    /**
     * Test parsing event with conference data
     */
    @isTest
    static void testParseEvent_WithConferenceData() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithConferenceResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event.meetingLink, 'Should have meeting link');
        Assert.isTrue(event.meetingLink.contains('meet.google.com'), 'Should have Google Meet link');
    }

    /**
     * Test parsing event with different statuses
     */
    @isTest
    static void testParseEvent_StatusMapping() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithStatusResponse('tentative'));
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.areEqual('tentative', event.status, 'Should map status correctly');
    }

    /**
     * Test parsing cancelled event
     */
    @isTest
    static void testParseEvent_CancelledStatus() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithStatusResponse('cancelled'));
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.areEqual('cancelled', event.status, 'Should map cancelled status');
    }

    /**
     * Test parsing confirmed event
     */
    @isTest
    static void testParseEvent_ConfirmedStatus() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithStatusResponse('confirmed'));
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.areEqual('confirmed', event.status, 'Should map confirmed status');
    }

    /**
     * Test parsing event with unknown status
     */
    @isTest
    static void testParseEvent_UnknownStatus() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithStatusResponse('unknown'));
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.areEqual('confirmed', event.status, 'Should default to confirmed for unknown status');
    }

    /**
     * Test parsing event with null status
     */
    @isTest
    static void testParseEvent_NullStatus() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithStatusResponse(null));
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.areEqual('confirmed', event.status, 'Should default to confirmed for null status');
    }

    /**
     * Test parsing datetime with Z suffix
     */
    @isTest
    static void testParseDateTimeWithZ() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithDateTimeZ());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event.startDateTime, 'Should parse datetime with Z');
    }

    /**
     * Test parsing datetime with timezone offset
     */
    @isTest
    static void testParseDateTimeWithOffset() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithTimezoneOffset());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event.startDateTime, 'Should parse datetime with timezone offset');
    }

    /**
     * Test parsing datetime with positive timezone offset
     */
    @isTest
    static void testParseDateTimeWithPositiveOffset() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithPositiveTimezoneOffset());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event.startDateTime, 'Should parse datetime with positive offset');
    }

    /**
     * Test parsing event with recurring event ID
     */
    @isTest
    static void testParseEvent_WithRecurringEventId() {
        Test.setMock(HttpCalloutMock.class, new MockRecurringEventResponse());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event.recurringEventId, 'Should have recurring event ID');
    }

    /**
     * Test parsing event with null data
     */
    @isTest
    static void testParseEvent_NullData() {
        Test.setMock(HttpCalloutMock.class, new MockNullEventResponse());
        setupWorkspaceUser();
        
        DateTime startDate = DateTime.newInstance(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstance(2024, 1, 31, 23, 59, 59);
        
        Test.startTest();
        List<AIMicrosoftCalendarService.CalendarEvent> events = 
            AIGoogleCalendarService.getEvents(startDate, endDate, 50, null);
        Test.stopTest();
        
        Assert.isNotNull(events, 'Should handle null event data');
    }

    /**
     * Test parsing event with invalid date
     */
    @isTest
    static void testParseEvent_InvalidDate() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithInvalidDate());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event, 'Should handle invalid date gracefully');
    }

    /**
     * Test parsing event with invalid datetime
     */
    @isTest
    static void testParseEvent_InvalidDateTime() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithInvalidDateTime());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event, 'Should handle invalid datetime gracefully');
    }

    /**
     * Test parsing event with null attendee data
     */
    @isTest
    static void testParseEvent_NullAttendeeData() {
        Test.setMock(HttpCalloutMock.class, new MockEventWithNullAttendee());
        setupWorkspaceUser();
        
        Test.startTest();
        AIMicrosoftCalendarService.CalendarEvent event = 
            AIGoogleCalendarService.getEvent('event_123');
        Test.stopTest();
        
        Assert.isNotNull(event, 'Should handle null attendee data');
    }

    // ==================== MOCK CLASSES ====================

    /**
     * Mock for calendar events response
     */
    private class MockCalendarEventsResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'items' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'event_1',
                        'summary' => 'Test Event',
                        'start' => new Map<String, Object>{
                            'dateTime' => '2024-01-15T10:00:00Z'
                        },
                        'end' => new Map<String, Object>{
                            'dateTime' => '2024-01-15T11:00:00Z'
                        },
                        'status' => 'confirmed'
                    },
                    new Map<String, Object>{
                        'id' => 'event_2',
                        'summary' => 'Another Event',
                        'start' => new Map<String, Object>{
                            'dateTime' => '2024-01-16T14:00:00Z'
                        },
                        'end' => new Map<String, Object>{
                            'dateTime' => '2024-01-16T15:00:00Z'
                        },
                        'status' => 'confirmed'
                    }
                }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for single event response
     */
    private class MockSingleEventResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Test Event',
                'description' => 'Test Description',
                'location' => 'Test Location',
                'iCalUID' => 'test@google.com',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00Z'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00Z'
                },
                'organizer' => new Map<String, Object>{
                    'email' => 'organizer@example.com',
                    'displayName' => 'Organizer Name'
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for error response
     */
    private class MockErrorResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockErrorResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Error occurred"}');
            return res;
        }
    }

    /**
     * Mock for exception response
     */
    private class MockExceptionResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Network error');
        }
    }

    /**
     * Mock for calendar accessible response
     */
    private class MockCalendarAccessibleResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockCalendarAccessibleResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"primary"}');
            return res;
        }
    }

    /**
     * Mock for calendar info response
     */
    private class MockCalendarInfoResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> profile = new Map<String, Object>{
                'emailAddress' => 'user@example.com'
            };
            
            res.setBody(JSON.serialize(profile));
            return res;
        }
    }

    /**
     * Mock for all-day event response
     */
    private class MockAllDayEventResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'items' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'event_1',
                        'summary' => 'All Day Event',
                        'start' => new Map<String, Object>{
                            'date' => '2024-01-15'
                        },
                        'end' => new Map<String, Object>{
                            'date' => '2024-01-16'
                        },
                        'status' => 'confirmed'
                    }
                }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for event with attendees
     */
    private class MockEventWithAttendeesResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Meeting',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00Z'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00Z'
                },
                'attendees' => new List<Object>{
                    new Map<String, Object>{
                        'email' => 'attendee@example.com',
                        'displayName' => 'Attendee Name',
                        'responseStatus' => 'accepted',
                        'organizer' => false
                    }
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for event with conference data
     */
    private class MockEventWithConferenceResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Video Meeting',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00Z'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00Z'
                },
                'conferenceData' => new Map<String, Object>{
                    'entryPoints' => new List<Object>{
                        new Map<String, Object>{
                            'entryPointType' => 'video',
                            'uri' => 'https://meet.google.com/abc-defg-hij'
                        }
                    }
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for event with specific status
     */
    private class MockEventWithStatusResponse implements HttpCalloutMock {
        private String status;
        
        public MockEventWithStatusResponse(String status) {
            this.status = status;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Event',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00Z'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00Z'
                },
                'status' => this.status
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for event with datetime Z
     */
    private class MockEventWithDateTimeZ implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Event',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00Z'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00Z'
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for event with timezone offset
     */
    private class MockEventWithTimezoneOffset implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Event',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00-08:00'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00-08:00'
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for event with positive timezone offset
     */
    private class MockEventWithPositiveTimezoneOffset implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Event',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00+05:30'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00+05:30'
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for recurring event
     */
    private class MockRecurringEventResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Recurring Event',
                'recurringEventId' => 'recurring_base_id',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00Z'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00Z'
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for null event response
     */
    private class MockNullEventResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> response = new Map<String, Object>{
                'items' => new List<Object>{ null }
            };
            
            res.setBody(JSON.serialize(response));
            return res;
        }
    }

    /**
     * Mock for event with invalid date
     */
    private class MockEventWithInvalidDate implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Event',
                'start' => new Map<String, Object>{
                    'date' => 'invalid-date'
                },
                'end' => new Map<String, Object>{
                    'date' => 'invalid-date'
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for event with invalid datetime
     */
    private class MockEventWithInvalidDateTime implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Event',
                'start' => new Map<String, Object>{
                    'dateTime' => 'invalid-datetime'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => 'invalid-datetime'
                },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }

    /**
     * Mock for event with null attendee
     */
    private class MockEventWithNullAttendee implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> event = new Map<String, Object>{
                'id' => 'event_123',
                'summary' => 'Event',
                'start' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T10:00:00Z'
                },
                'end' => new Map<String, Object>{
                    'dateTime' => '2024-01-15T11:00:00Z'
                },
                'attendees' => new List<Object>{ null },
                'status' => 'confirmed'
            };
            
            res.setBody(JSON.serialize(event));
            return res;
        }
    }
}