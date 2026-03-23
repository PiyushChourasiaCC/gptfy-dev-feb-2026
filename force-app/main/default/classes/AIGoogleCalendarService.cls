/**
 * Google Calendar API service
 * Handles low-level API calls for calendar event retrieval from Google Calendar
 *
 * AUTHENTICATION: Uses access tokens from AI_Workspace_User__c
 * Tokens are retrieved and refreshed automatically via AIWorkspaceTokenService
 */
public with sharing class AIGoogleCalendarService {

    private static final Integer DEFAULT_TIMEOUT = 120000;
    private static final Integer MAX_RESULTS = 50;

    // Google API endpoint (direct URL, not Named Credential)
    private static String getCalendarApiEndpoint() {
        return AIWorkspaceTokenService.getGoogleApiEndpoint();
    }

    private static String getGmailApiEndpoint() {
        return AIWorkspaceTokenService.getGmailEndpoint();
    }
    
    /**
     * Get access token for the current user
     * Retrieves from AI_Workspace_User__c and refreshes if needed
     */
    private static String getAccessToken() {
        return AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_GMAIL);
    }

    /**
     * Fetch calendar events within a date range with optional search
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of events to return (default 50)
     * @param searchTerm Optional search term to filter events (uses Google's 'q' parameter)
     * @return List of normalized calendar events
     */
    public static List<AIMicrosoftCalendarService.CalendarEvent> getEvents(DateTime startDate, DateTime endDate, Integer maxResults, String searchTerm) {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();

        if (maxResults == null || maxResults <= 0) {
            maxResults = MAX_RESULTS;
        }

        try {
            // Format dates for Google Calendar API (RFC 3339)
            String startDateStr = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endDateStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

            // Build the request URL using Named Credential
            String endpoint = getCalendarApiEndpoint() + '/calendar/v3/calendars/primary/events'
                + '?timeMin=' + EncodingUtil.urlEncode(startDateStr, 'UTF-8')
                + '&timeMax=' + EncodingUtil.urlEncode(endDateStr, 'UTF-8')
                + '&maxResults=' + maxResults;
            
            // Add search term if provided
            if (String.isNotBlank(searchTerm)) {
                endpoint += '&q=' + EncodingUtil.urlEncode(searchTerm, 'UTF-8');
            }
                
            endpoint += '&singleEvents=true'
                + '&orderBy=startTime';

            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                events = parseEventsResponse(response.getBody());
            } else {
                throw new CalendarServiceException('Failed to fetch calendar events: ' + response.getStatusCode());
            }
        } catch (CalendarServiceException e) {
            throw e;
        } catch (Exception e) {
            throw new CalendarServiceException('Google Calendar service error: ' + e.getMessage());
        }

        return events;
    }

    /**
     * Fetch calendar events within a date range with offset-based pagination
     * Google Calendar API uses pageToken, but we simulate offset by fetching and skipping
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of events to return
     * @param offset Number of events to skip (for pagination)
     * @param searchTerm Optional search term to filter events
     * @return List of normalized calendar events
     */
    public static List<AIMicrosoftCalendarService.CalendarEvent> getEventsWithOffset(DateTime startDate, DateTime endDate, Integer maxResults, Integer offset, String searchTerm) {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();

        if (maxResults == null || maxResults <= 0) {
            maxResults = MAX_RESULTS;
        }
        if (offset == null || offset < 0) {
            offset = 0;
        }

        try {
            // Format dates for Google Calendar API (RFC 3339)
            String startDateStr = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endDateStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

            // Google Calendar API doesn't support $skip, so we fetch offset + maxResults and skip in Apex
            Integer fetchLimit = offset + maxResults;
            
            // Build the request URL
            String endpoint = getCalendarApiEndpoint() + '/calendar/v3/calendars/primary/events'
                + '?timeMin=' + EncodingUtil.urlEncode(startDateStr, 'UTF-8')
                + '&timeMax=' + EncodingUtil.urlEncode(endDateStr, 'UTF-8')
                + '&maxResults=' + fetchLimit;
            
            // Add search term if provided
            if (String.isNotBlank(searchTerm)) {
                endpoint += '&q=' + EncodingUtil.urlEncode(searchTerm, 'UTF-8');
            }
                
            endpoint += '&singleEvents=true'
                + '&orderBy=startTime';

            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                List<AIMicrosoftCalendarService.CalendarEvent> allEvents = parseEventsResponse(response.getBody());
                
                // Skip the first 'offset' events
                for (Integer i = offset; i < allEvents.size() && events.size() < maxResults; i++) {
                    events.add(allEvents[i]);
                }
            } else {
                throw new CalendarServiceException('Failed to fetch calendar events: ' + response.getStatusCode());
            }
        } catch (CalendarServiceException e) {
            throw e;
        } catch (Exception e) {
            throw new CalendarServiceException('Google Calendar service error: ' + e.getMessage());
        }

        return events;
    }

    /**
     * Fetch a single calendar event by ID
     * @param eventId The Google Calendar event ID
     * @return The calendar event details
     */
    public static AIMicrosoftCalendarService.CalendarEvent getEvent(String eventId) {
        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            String endpoint = getCalendarApiEndpoint()
                + '/calendar/v3/calendars/primary/events/' + EncodingUtil.urlEncode(eventId, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> eventData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                return parseEventData(eventData);
            } else {
                throw new CalendarServiceException('Failed to fetch event: ' + response.getStatusCode());
            }
        } catch (CalendarServiceException e) {
            throw e;
        } catch (Exception e) {
            throw new CalendarServiceException('Error fetching event: ' + e.getMessage());
        }
    }

    /**
     * Check if calendar API is accessible with current credentials
     * @return true if authenticated and calendar is accessible
     */
    public static Boolean isCalendarAccessible() {
        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(getCalendarApiEndpoint() + '/calendar/v3/calendars/primary');
            req.setMethod('GET');
            req.setTimeout(30000);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            return response.getStatusCode() == 200;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Get the calendar info
     * @return Map with calendar details (email)
     */
    public static Map<String, String> getCalendarInfo() {
        Map<String, String> calendarInfo = new Map<String, String>();

        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            // Get user email from Gmail API (same OAuth credential)
            HttpRequest req = new HttpRequest();
            req.setEndpoint(getGmailApiEndpoint() + '/gmail/v1/users/me/profile');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> profile = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String email = (String) profile.get('emailAddress');
                calendarInfo.put('ownerEmail', email);
                calendarInfo.put('name', 'Google Calendar');
            }
        } catch (Exception e) {
            // Ignore
        }

        return calendarInfo;
    }

    /**
     * Parse the events response from Google Calendar API
     */
    private static List<AIMicrosoftCalendarService.CalendarEvent> parseEventsResponse(String responseBody) {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> eventList = (List<Object>) parsed.get('items');

        if (eventList != null) {
            for (Object eventObj : eventList) {
                Map<String, Object> eventData = (Map<String, Object>) eventObj;
                AIMicrosoftCalendarService.CalendarEvent evt = parseEventData(eventData);
                if (evt != null) {
                    events.add(evt);
                }
            }
        }

        return events;
    }

    /**
     * Parse a single event data map into CalendarEvent object
     */
    private static AIMicrosoftCalendarService.CalendarEvent parseEventData(Map<String, Object> eventData) {
        if (eventData == null) {
            return null;
        }

        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = (String) eventData.get('id');
        evt.subject = (String) eventData.get('summary');
        evt.iCalUID = (String) eventData.get('iCalUID');
        evt.description = (String) eventData.get('description');
        evt.provider = 'GOOGLE_CALENDAR';
        
        // Parse recurringEventId - this is the base event ID for instances of recurring events
        // When singleEvents=true, each instance gets a unique iCalUID but shares the same recurringEventId
        // This is critical for deduplication of recurring event series
        evt.recurringEventId = (String) eventData.get('recurringEventId');

        // Parse start/end times
        Map<String, Object> startObj = (Map<String, Object>) eventData.get('start');
        Map<String, Object> endObj = (Map<String, Object>) eventData.get('end');

        if (startObj != null) {
            // Check if it's an all-day event (has 'date' instead of 'dateTime')
            if (startObj.containsKey('date')) {
                evt.isAllDay = true;
                evt.startDateTime = parseGoogleDate((String) startObj.get('date'));
            } else {
                evt.isAllDay = false;
                evt.startDateTime = parseGoogleDateTime((String) startObj.get('dateTime'));
            }
        }

        if (endObj != null) {
            if (endObj.containsKey('date')) {
                evt.endDateTime = parseGoogleDate((String) endObj.get('date'));
            } else {
                evt.endDateTime = parseGoogleDateTime((String) endObj.get('dateTime'));
            }
        }

        // Parse location
        evt.location = (String) eventData.get('location');

        // V2-7889: Parse organizer - Use creator field as primary source (actual event creator)
        // The 'organizer' field in Google Calendar represents the calendar owner, which can differ
        // from the actual person who created the event (especially for delegated/shared calendars)
        Map<String, Object> creator = (Map<String, Object>) eventData.get('creator');
        Map<String, Object> organizer = (Map<String, Object>) eventData.get('organizer');
        
        // Prefer creator over organizer for accurate event attribution
        if (creator != null) {
            evt.organizerEmail = (String) creator.get('email');
            evt.organizerName = (String) creator.get('displayName');
        } else if (organizer != null) {
            // Fallback to organizer if creator is not available
            evt.organizerEmail = (String) organizer.get('email');
            evt.organizerName = (String) organizer.get('displayName');
        }

        // Parse attendees
        List<Object> attendeeList = (List<Object>) eventData.get('attendees');
        if (attendeeList != null) {
            for (Object attObj : attendeeList) {
                Map<String, Object> attData = (Map<String, Object>) attObj;
                AIMicrosoftCalendarService.Attendee att = parseAttendee(attData);
                if (att != null) {
                    evt.attendees.add(att);
                }
            }
        }

        // Parse meeting link (Google Meet or conference data)
        Map<String, Object> conferenceData = (Map<String, Object>) eventData.get('conferenceData');
        if (conferenceData != null) {
            List<Object> entryPoints = (List<Object>) conferenceData.get('entryPoints');
            if (entryPoints != null) {
                for (Object epObj : entryPoints) {
                    Map<String, Object> ep = (Map<String, Object>) epObj;
                    String entryPointType = (String) ep.get('entryPointType');
                    if (entryPointType == 'video') {
                        evt.meetingLink = (String) ep.get('uri');
                        break;
                    }
                }
            }
        }

        // Parse status
        String status = (String) eventData.get('status');
        evt.status = mapGoogleStatusToStatus(status);

        return evt;
    }

    /**
     * Parse an attendee from event data
     */
    private static AIMicrosoftCalendarService.Attendee parseAttendee(Map<String, Object> attData) {
        if (attData == null) {
            return null;
        }

        AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
        att.email = (String) attData.get('email');
        att.name = (String) attData.get('displayName');
        att.isOrganizer = attData.get('organizer') == true;
        att.responseStatus = (String) attData.get('responseStatus');

        return att;
    }

    /**
     * Parse Google Calendar date string (all-day events)
     * Format: "2024-01-15"
     */
    private static DateTime parseGoogleDate(String dateStr) {
        if (String.isBlank(dateStr)) {
            return null;
        }

        try {
            Date d = Date.valueOf(dateStr);
            return DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Parse Google Calendar datetime string
     * Format: "2024-01-15T14:00:00-08:00" or "2024-01-15T14:00:00Z"
     */
    private static DateTime parseGoogleDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }

        try {
            // Handle timezone offset format
            String normalized = dateTimeStr;

            // Remove timezone offset if present (e.g., -08:00, +05:30)
            if (dateTimeStr.length() > 19) {
                // Check for Z suffix
                if (dateTimeStr.endsWith('Z')) {
                    normalized = dateTimeStr.substring(0, dateTimeStr.length() - 1);
                } else {
                    // Remove timezone offset like -08:00 or +05:30
                    Integer offsetIndex = dateTimeStr.lastIndexOf('+');
                    if (offsetIndex == -1) {
                        offsetIndex = dateTimeStr.lastIndexOf('-');
                        // Make sure we're not catching the date separator
                        if (offsetIndex > 10) {
                            normalized = dateTimeStr.substring(0, offsetIndex);
                        }
                    } else {
                        normalized = dateTimeStr.substring(0, offsetIndex);
                    }
                }
            }

            // Parse as GMT (Google returns in UTC when requested)
            return DateTime.valueOfGmt(normalized.replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Map Google Calendar status to simple status
     */
    private static String mapGoogleStatusToStatus(String status) {
        if (String.isBlank(status)) {
            return 'confirmed';
        }

        switch on status.toLowerCase() {
            when 'confirmed' {
                return 'confirmed';
            }
            when 'tentative' {
                return 'tentative';
            }
            when 'cancelled' {
                return 'cancelled';
            }
            when else {
                return 'confirmed';
            }
        }
    }

    /**
     * Custom exception for calendar service errors
     */
    public class CalendarServiceException extends Exception {}
}