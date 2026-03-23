/**
 * Microsoft Graph Calendar API service
 * Handles low-level API calls for calendar event retrieval from Microsoft Graph
 *
 * AUTHENTICATION: Uses access tokens from AI_Workspace_User__c
 * Tokens are retrieved and refreshed automatically via AIWorkspaceTokenService
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIMicrosoftCalendarService {

    private static final Integer DEFAULT_TIMEOUT = 120000;
    private static final Integer MAX_RESULTS = 50;

    // Microsoft Graph API endpoint (direct URL, not Named Credential)
    private static String getGraphApiEndpoint() {
        return AIWorkspaceTokenService.getMicrosoftGraphEndpoint();
    }
    
    /**
     * Get access token for the current user
     * Retrieves from AI_Workspace_User__c and refreshes if needed
     */
    private static String getAccessToken() {
        return AIWorkspaceTokenService.getAccessToken(AIWorkspaceTokenService.PROVIDER_OUTLOOK);
    }

    /**
     * Inner class representing a normalized calendar event
     */
    public class CalendarEvent {
        @AuraEnabled public String eventId;
        @AuraEnabled public String subject;
        @AuraEnabled public DateTime startDateTime;
        @AuraEnabled public DateTime endDateTime;
        @AuraEnabled public String location;
        @AuraEnabled public String description;
        @AuraEnabled public List<Attendee> attendees;
        @AuraEnabled public String organizerEmail;
        @AuraEnabled public String organizerName;
        @AuraEnabled public Boolean isAllDay;
        @AuraEnabled public String meetingLink;
        @AuraEnabled public String status;
        @AuraEnabled public String iCalUID;
        @AuraEnabled public String provider;
        @AuraEnabled public Boolean isImported;
        // Recurring event ID - for Google Calendar, this is the base event ID for recurring instances
        // Used for deduplication of recurring event series
        @AuraEnabled public String recurringEventId;
        // Linked record info (populated after import) - single record for backwards compatibility
        @AuraEnabled public Id linkedRecordId;
        @AuraEnabled public String linkedRecordName;
        @AuraEnabled public String linkedRecordType;
        // List of ALL linked records for multiple pills display
        @AuraEnabled public List<LinkedRecord> linkedRecords;

        public CalendarEvent() {
            this.attendees = new List<Attendee>();
            this.linkedRecords = new List<LinkedRecord>();
            this.provider = 'MICROSOFT_CALENDAR';
            this.isImported = false;
        }
    }
    
    /**
     * Inner class representing a linked Lead/Contact record
     */
    public class LinkedRecord {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String recordType; // 'Lead' or 'Contact'
        
        public LinkedRecord(Id recordId, String recordName, String recordType) {
            this.recordId = recordId;
            this.recordName = recordName;
            this.recordType = recordType;
        }
    }

    /**
     * Inner class representing an event attendee
     */
    public class Attendee {
        @AuraEnabled public String email;
        @AuraEnabled public String name;
        @AuraEnabled public String responseStatus;
        @AuraEnabled public Boolean isOrganizer;

        public Attendee() {
            this.isOrganizer = false;
        }
    }

    /**
     * Fetch calendar events within a date range with optional search
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of events to return (default 50)
     * @param searchTerm Optional search term to filter events (filtered in Apex, not API)
     * @return List of normalized calendar events
     */
    public static List<CalendarEvent> getEvents(DateTime startDate, DateTime endDate, Integer maxResults, String searchTerm) {
        List<CalendarEvent> events = new List<CalendarEvent>();

        if (maxResults == null || maxResults <= 0) {
            maxResults = MAX_RESULTS;
        }

        // If searching, fetch more results to filter from (up to 250)
        Integer fetchLimit = String.isNotBlank(searchTerm) ? Math.min(maxResults * 5, 250) : maxResults;

        try {
            // Format dates for Graph API (ISO 8601)
            String startDateStr = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endDateStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

            // Use calendarView endpoint for proper recurring event expansion
            // Note: calendarView does NOT support $search or $filter on subject
            // We fetch events and filter in Apex for search functionality
            String endpoint = getGraphApiEndpoint() + '/v1.0/me/calendar/calendarView'
                + '?startDateTime=' + EncodingUtil.urlEncode(startDateStr, 'UTF-8')
                + '&endDateTime=' + EncodingUtil.urlEncode(endDateStr, 'UTF-8')
                + '&$top=' + fetchLimit
                + '&$orderby=start/dateTime'
                + '&$select=id,subject,bodyPreview,body,start,end,location,attendees,organizer,iCalUId,onlineMeeting,isAllDay,showAs,responseStatus';

            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Prefer', 'outlook.timezone="UTC"');
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                events = parseEventsResponse(response.getBody());

                // Apply search filter in Apex (since calendarView doesn't support $search)
                if (String.isNotBlank(searchTerm)) {
                    events = filterEventsBySearchTerm(events, searchTerm, maxResults);
                }
            } else {
                throw new CalendarServiceException('Failed to fetch calendar events: ' + response.getStatusCode());
            }
        } catch (CalendarServiceException e) {
            throw e;
        } catch (Exception e) {
            throw new CalendarServiceException('Calendar service error: ' + e.getMessage());
        }

        return events;
    }

    /**
     * Fetch calendar events within a date range with offset-based pagination
     * @param startDate Start of date range
     * @param endDate End of date range
     * @param maxResults Maximum number of events to return
     * @param offset Number of events to skip (for pagination)
     * @param searchTerm Optional search term to filter events
     * @return List of normalized calendar events
     */
    public static List<CalendarEvent> getEventsWithOffset(DateTime startDate, DateTime endDate, Integer maxResults, Integer offset, String searchTerm) {
        List<CalendarEvent> events = new List<CalendarEvent>();

        if (maxResults == null || maxResults <= 0) {
            maxResults = MAX_RESULTS;
        }
        if (offset == null || offset < 0) {
            offset = 0;
        }

        try {
            // Format dates for Graph API (ISO 8601)
            String startDateStr = startDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endDateStr = endDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

            // Use calendarView endpoint for proper recurring event expansion
            // $skip is used for pagination
            String endpoint = getGraphApiEndpoint() + '/v1.0/me/calendar/calendarView'
                + '?startDateTime=' + EncodingUtil.urlEncode(startDateStr, 'UTF-8')
                + '&endDateTime=' + EncodingUtil.urlEncode(endDateStr, 'UTF-8')
                + '&$top=' + maxResults
                + '&$skip=' + offset
                + '&$orderby=start/dateTime'
                + '&$select=id,subject,bodyPreview,body,start,end,location,attendees,organizer,iCalUId,onlineMeeting,isAllDay,showAs,responseStatus';

            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Prefer', 'outlook.timezone="UTC"');
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                events = parseEventsResponse(response.getBody());

                // Apply search filter in Apex (since calendarView doesn't support $search)
                if (String.isNotBlank(searchTerm)) {
                    events = filterEventsBySearchTerm(events, searchTerm, maxResults);
                }
            } else {
                throw new CalendarServiceException('Failed to fetch calendar events: ' + response.getStatusCode());
            }
        } catch (CalendarServiceException e) {
            throw e;
        } catch (Exception e) {
            throw new CalendarServiceException('Calendar service error: ' + e.getMessage());
        }

        return events;
    }

    /**
     * Filter events by search term (subject, description, location, organizer, attendees)
     * @param events List of events to filter
     * @param searchTerm Search term to match
     * @param maxResults Maximum results to return
     * @return Filtered list of events
     */
    private static List<CalendarEvent> filterEventsBySearchTerm(List<CalendarEvent> events, String searchTerm, Integer maxResults) {
        if (events == null || events.isEmpty() || String.isBlank(searchTerm)) {
            return events;
        }

        List<CalendarEvent> filtered = new List<CalendarEvent>();
        String searchLower = searchTerm.toLowerCase();

        for (CalendarEvent evt : events) {
            if (eventMatchesSearch(evt, searchLower)) {
                filtered.add(evt);
                if (filtered.size() >= maxResults) {
                    break;
                }
            }
        }

        return filtered;
    }

    /**
     * Check if an event matches the search term
     * Searches: subject, description, location, organizer name/email, attendee names/emails
     */
    private static Boolean eventMatchesSearch(CalendarEvent evt, String searchLower) {
        // Check subject
        if (String.isNotBlank(evt.subject) && evt.subject.toLowerCase().contains(searchLower)) {
            return true;
        }

        // Check description/body
        if (String.isNotBlank(evt.description) && evt.description.toLowerCase().contains(searchLower)) {
            return true;
        }

        // Check location
        if (String.isNotBlank(evt.location) && evt.location.toLowerCase().contains(searchLower)) {
            return true;
        }

        // Check organizer
        if (String.isNotBlank(evt.organizerName) && evt.organizerName.toLowerCase().contains(searchLower)) {
            return true;
        }
        if (String.isNotBlank(evt.organizerEmail) && evt.organizerEmail.toLowerCase().contains(searchLower)) {
            return true;
        }

        // Check attendees
        if (evt.attendees != null) {
            for (Attendee att : evt.attendees) {
                if (String.isNotBlank(att.name) && att.name.toLowerCase().contains(searchLower)) {
                    return true;
                }
                if (String.isNotBlank(att.email) && att.email.toLowerCase().contains(searchLower)) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * Fetch a single calendar event by ID
     * @param eventId The Microsoft Graph event ID
     * @return The calendar event details
     */
    public static CalendarEvent getEvent(String eventId) {
        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            String endpoint = getGraphApiEndpoint() + '/v1.0/me/events/' + EncodingUtil.urlEncode(eventId, 'UTF-8')
                + '?$select=id,subject,bodyPreview,body,start,end,location,attendees,organizer,iCalUId,onlineMeeting,isAllDay,showAs,responseStatus';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Prefer', 'outlook.timezone="UTC"');
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
            req.setEndpoint(getGraphApiEndpoint() + '/v1.0/me/calendar');
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
     * Get the primary calendar info
     * @return Map with calendar details (id, name, owner)
     */
    public static Map<String, String> getCalendarInfo() {
        Map<String, String> calendarInfo = new Map<String, String>();

        try {
            // Get access token from AI_Workspace_User__c
            String accessToken = getAccessToken();
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(getGraphApiEndpoint() + '/v1.0/me/calendar');
            req.setMethod('GET');
            req.setTimeout(DEFAULT_TIMEOUT);
            req.setHeader('Authorization', 'Bearer ' + accessToken);

            Http http = new Http();
            HttpResponse response = http.send(req);

            if (response.getStatusCode() == 200) {
                Map<String, Object> calendar = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                calendarInfo.put('id', (String) calendar.get('id'));
                calendarInfo.put('name', (String) calendar.get('name'));

                Map<String, Object> owner = (Map<String, Object>) calendar.get('owner');
                if (owner != null) {
                    calendarInfo.put('ownerEmail', (String) owner.get('address'));
                    calendarInfo.put('ownerName', (String) owner.get('name'));
                }
            }
        } catch (Exception e) {
        }

        return calendarInfo;
    }

    /**
     * Parse the events response from Graph API
     */
    private static List<CalendarEvent> parseEventsResponse(String responseBody) {
        List<CalendarEvent> events = new List<CalendarEvent>();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> eventList = (List<Object>) parsed.get('value');

        if (eventList != null) {
            for (Object eventObj : eventList) {
                Map<String, Object> eventData = (Map<String, Object>) eventObj;
                CalendarEvent evt = parseEventData(eventData);
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
    private static CalendarEvent parseEventData(Map<String, Object> eventData) {
        if (eventData == null) {
            return null;
        }

        CalendarEvent evt = new CalendarEvent();
        evt.eventId = (String) eventData.get('id');
        evt.subject = (String) eventData.get('subject');
        evt.iCalUID = (String) eventData.get('iCalUId');
        evt.isAllDay = eventData.get('isAllDay') == true;

        // Parse description from body
        Map<String, Object> body = (Map<String, Object>) eventData.get('body');
        if (body != null) {
            String content = (String) body.get('content');
            String contentType = (String) body.get('contentType');
            // Strip HTML if needed
            if (contentType == 'html' && String.isNotBlank(content)) {
                evt.description = stripHtml(content);
            } else {
                evt.description = content;
            }
        }
        // Fallback to bodyPreview if body is empty
        if (String.isBlank(evt.description)) {
            evt.description = (String) eventData.get('bodyPreview');
        }

        // Parse start/end times
        Map<String, Object> startObj = (Map<String, Object>) eventData.get('start');
        Map<String, Object> endObj = (Map<String, Object>) eventData.get('end');

        if (startObj != null) {
            evt.startDateTime = parseGraphDateTime((String) startObj.get('dateTime'), evt.isAllDay);
        }
        if (endObj != null) {
            evt.endDateTime = parseGraphDateTime((String) endObj.get('dateTime'), evt.isAllDay);
        }

        // Parse location
        Map<String, Object> locationObj = (Map<String, Object>) eventData.get('location');
        if (locationObj != null) {
            evt.location = (String) locationObj.get('displayName');
        }

        // Parse organizer
        Map<String, Object> organizer = (Map<String, Object>) eventData.get('organizer');
        if (organizer != null) {
            Map<String, Object> emailAddr = (Map<String, Object>) organizer.get('emailAddress');
            if (emailAddr != null) {
                evt.organizerEmail = (String) emailAddr.get('address');
                evt.organizerName = (String) emailAddr.get('name');
            }
        }

        // Parse attendees
        List<Object> attendeeList = (List<Object>) eventData.get('attendees');
        if (attendeeList != null) {
            for (Object attObj : attendeeList) {
                Map<String, Object> attData = (Map<String, Object>) attObj;
                Attendee att = parseAttendee(attData, evt.organizerEmail);
                if (att != null) {
                    evt.attendees.add(att);
                }
            }
        }
        
        // V2-7889: Fix for cross-platform meetings (Gmail → Outlook)
        // When viewing a meeting invitation where the organizer is external (e.g., Gmail),
        // Microsoft Graph may incorrectly show the calendar owner as organizer
        // Check if the API organizer is in the attendees list - if so, swap them
        if (String.isNotBlank(evt.organizerEmail) && evt.attendees != null && evt.attendees.size() == 1) {
            // Single attendee scenario: if organizer is calendar owner and there's one attendee,
            // the attendee is likely the real organizer (cross-platform invite)
            Attendee singleAttendee = evt.attendees[0];
            if (String.isNotBlank(singleAttendee.email) && 
                !singleAttendee.email.equalsIgnoreCase(evt.organizerEmail)) {
                // Swap: attendee becomes organizer, organizer becomes attendee
                String tempEmail = evt.organizerEmail;
                String tempName = evt.organizerName;
                
                evt.organizerEmail = singleAttendee.email;
                evt.organizerName = singleAttendee.name;
                
                singleAttendee.email = tempEmail;
                singleAttendee.name = tempName;
                singleAttendee.isOrganizer = false;
            }
        }

        // Parse meeting link
        Map<String, Object> onlineMeeting = (Map<String, Object>) eventData.get('onlineMeeting');
        if (onlineMeeting != null) {
            evt.meetingLink = (String) onlineMeeting.get('joinUrl');
        }
        // Fallback: check location for meeting link
        if (String.isBlank(evt.meetingLink) && String.isNotBlank(evt.location)) {
            evt.meetingLink = extractMeetingLink(evt.location);
        }

        // Parse status (showAs: busy, tentative, free, etc.)
        String showAs = (String) eventData.get('showAs');
        evt.status = mapShowAsToStatus(showAs);

        return evt;
    }

    /**
     * Parse an attendee from event data
     */
    private static Attendee parseAttendee(Map<String, Object> attData, String organizerEmail) {
        if (attData == null) {
            return null;
        }

        Attendee att = new Attendee();

        Map<String, Object> emailAddr = (Map<String, Object>) attData.get('emailAddress');
        if (emailAddr != null) {
            att.email = (String) emailAddr.get('address');
            att.name = (String) emailAddr.get('name');
        }

        // Check if this is the organizer
        att.isOrganizer = String.isNotBlank(att.email) &&
                          String.isNotBlank(organizerEmail) &&
                          att.email.equalsIgnoreCase(organizerEmail);

        // Parse response status
        Map<String, Object> status = (Map<String, Object>) attData.get('status');
        if (status != null) {
            att.responseStatus = (String) status.get('response');
        }

        return att;
    }

    /**
     * Parse Microsoft Graph datetime string to Apex DateTime
     * Graph format: "2024-01-15T14:00:00.0000000"
     */
    private static DateTime parseGraphDateTime(String dateTimeStr, Boolean isAllDay) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }

        try {
            // Remove fractional seconds if present
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
            }

            // Parse the datetime
            if (isAllDay) {
                // All-day events just have date
                Date d = Date.valueOf(dateTimeStr.substring(0, 10));
                return DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
            } else {
                // Full datetime
                return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
            }
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Map Graph API showAs value to a simple status
     */
    private static String mapShowAsToStatus(String showAs) {
        if (String.isBlank(showAs)) {
            return 'confirmed';
        }

        switch on showAs.toLowerCase() {
            when 'busy' {
                return 'confirmed';
            }
            when 'tentative' {
                return 'tentative';
            }
            when 'free' {
                return 'free';
            }
            when 'oof', 'workingelsewhere' {
                return 'confirmed';
            }
            when else {
                return 'confirmed';
            }
        }
    }

    /**
     * Extract meeting link from text (Zoom, Teams, Meet, etc.)
     */
    private static String extractMeetingLink(String text) {
        // Meeting link extraction skipped for now - can be added as future enhancement
        // NO REGEX - avoids "regex too complicated" errors
        return null;
    }

    /**
     * Strip HTML tags from content
     * NO REGEX - uses Salesforce built-in stripHtmlTags()
     */
    private static String stripHtml(String html) {
        if (String.isBlank(html)) {
            return '';
        }

        // Use Salesforce built-in method - no regex
        String text = html.stripHtmlTags();

        // Decode common HTML entities using simple replace() - no regex
        text = text.replace('&nbsp;', ' ');
        text = text.replace('&amp;', '&');
        text = text.replace('&lt;', '<');
        text = text.replace('&gt;', '>');
        text = text.replace('&quot;', '"');

        return text.trim();
    }

    /**
     * Custom exception for calendar service errors
     */
    public class CalendarServiceException extends Exception {}
}