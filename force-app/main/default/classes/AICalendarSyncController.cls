/**
 * CalendarSyncController
 * Apex controller for calendar sync LWC functionality
 *
 * Provides methods for:
 * - Fetching calendar events from Microsoft Graph
 * - Importing events into Salesforce
 * - Checking which events are already imported
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AICalendarSyncController {

    /**
     * Response wrapper for calendar events
     */
    public class CalendarEventsResponse {
        @AuraEnabled public List<AIMicrosoftCalendarService.CalendarEvent> events;
        @AuraEnabled public Map<String, Id> importedEvents;
        @AuraEnabled public Map<String, ImportedEventInfo> importedEventDetails;
        @AuraEnabled public String error;
        @AuraEnabled public Boolean isCalendarAccessible;
        @AuraEnabled public String nextPageToken;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer totalCount;

        public CalendarEventsResponse() {
            this.events = new List<AIMicrosoftCalendarService.CalendarEvent>();
            this.importedEvents = new Map<String, Id>();
            this.importedEventDetails = new Map<String, ImportedEventInfo>();
            this.isCalendarAccessible = false;
            this.hasMore = false;
            this.totalCount = 0;
        }
    }

    /**
     * Details about an imported event including associations
     */
    public class ImportedEventInfo {
        @AuraEnabled public Id eventId;
        @AuraEnabled public Id whoId;
        @AuraEnabled public String whoName;
        @AuraEnabled public String whoType;
        @AuraEnabled public Id whatId;
        @AuraEnabled public String whatName;
        @AuraEnabled public String whatType;
        // List of ALL linked records for this event (for multiple pills display)
        @AuraEnabled public List<LinkedRecordInfo> linkedRecords;
        
        public ImportedEventInfo() {
            this.linkedRecords = new List<LinkedRecordInfo>();
        }
    }
    
    /**
     * Info about a single linked record (Lead/Contact)
     */
    public class LinkedRecordInfo {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String recordType; // 'Lead' or 'Contact'
        
        public LinkedRecordInfo(Id recordId, String recordName, String recordType) {
            this.recordId = recordId;
            this.recordName = recordName;
            this.recordType = recordType;
        }
    }

    /**
     * Get calendar events for a date range
     * @param startDate Start of date range (ISO string)
     * @param endDate End of date range (ISO string)
     * @param maxResults Maximum events to return
     * @param provider 'GOOGLE_CALENDAR' or 'MICROSOFT_CALENDAR' (optional, defaults to MICROSOFT_CALENDAR)
     * @param searchTerm Optional search term
     * @return CalendarEventsResponse with events and import status
     */
    @AuraEnabled(cacheable=false)
    public static CalendarEventsResponse getCalendarEvents(
        String startDate,
        String endDate,
        Integer maxResults,
        String provider,
        String searchTerm
    ) {
        CalendarEventsResponse response = new CalendarEventsResponse();

        // Default to Microsoft Calendar if not specified
        if (String.isBlank(provider)) {
            provider = 'MICROSOFT_CALENDAR';
        }

        try {
            // Parse dates
            DateTime startDt = parseISODateTime(startDate);
            DateTime endDt = parseISODateTime(endDate);

            if (startDt == null || endDt == null) {
                response.error = 'Invalid date range provided';
                return response;
            }

            // Check calendar access based on provider
            if (provider == 'GOOGLE_CALENDAR') {
                response.isCalendarAccessible = AIGoogleCalendarService.isCalendarAccessible();
            } else {
                response.isCalendarAccessible = AIMicrosoftCalendarService.isCalendarAccessible();
            }

            if (!response.isCalendarAccessible) {
                response.error = provider == 'GOOGLE_CALENDAR'
                    ? 'Google Calendar access not available. Please ensure calendar.readonly scope is granted.'
                    : 'Outlook Calendar access not available. Please ensure Calendars.Read permission is granted.';
                return response;
            }

            // Fetch events based on provider
            List<AIMicrosoftCalendarService.CalendarEvent> events;
            if (provider == 'GOOGLE_CALENDAR') {
                events = AIGoogleCalendarService.getEvents(startDt, endDt, maxResults, searchTerm);
            } else {
                events = AIMicrosoftCalendarService.getEvents(startDt, endDt, maxResults, searchTerm);
            }

            response.events = events;

            // Check which events are already imported
            // Collect BOTH dedupIds (new format) AND iCalUIDs (old format) for backwards compatibility
            Set<String> calendarIds = new Set<String>();
            Set<String> iCalUIDs = new Set<String>();
            for (AIMicrosoftCalendarService.CalendarEvent evt : events) {
                String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
                if (String.isNotBlank(dedupId)) {
                    calendarIds.add(dedupId);
                }
                // Also collect iCalUIDs for backwards compatibility with existing staging records
                if (String.isNotBlank(evt.iCalUID)) {
                    iCalUIDs.add(evt.iCalUID);
                    calendarIds.add(evt.iCalUID); // Add to query set
                }
            }

            if (!calendarIds.isEmpty()) {
                response.importedEvents = AICalendarEventCreator.getImportedEventsMap(calendarIds);

                // Get detailed info including associations
                response.importedEventDetails = getImportedEventDetails(calendarIds);

                // Mark events as imported and add association info
                for (AIMicrosoftCalendarService.CalendarEvent evt : response.events) {
                    String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
                    // Check by dedupId first, then fallback to iCalUID for backwards compatibility
                    Boolean foundByDedupId = response.importedEvents.containsKey(dedupId);
                    Boolean foundByICalUID = String.isNotBlank(evt.iCalUID) && response.importedEvents.containsKey(evt.iCalUID);
                    evt.isImported = foundByDedupId || foundByICalUID;
                    
                    // Get details using dedupId first, fallback to iCalUID
                    ImportedEventInfo info = null;
                    if (foundByDedupId && response.importedEventDetails.containsKey(dedupId)) {
                        info = response.importedEventDetails.get(dedupId);
                    } else if (foundByICalUID && response.importedEventDetails.containsKey(evt.iCalUID)) {
                        info = response.importedEventDetails.get(evt.iCalUID);
                    }
                    
                    if (info != null) {
                        // Set first record for backwards compatibility
                        evt.linkedRecordId = info.whoId != null ? info.whoId : info.whatId;
                        evt.linkedRecordName = info.whoName != null ? info.whoName : info.whatName;
                        evt.linkedRecordType = info.whoType != null ? info.whoType : info.whatType;
                        // Set ALL linked records for multiple pills display
                        if (info.linkedRecords != null && !info.linkedRecords.isEmpty()) {
                            for (LinkedRecordInfo lr : info.linkedRecords) {
                                evt.linkedRecords.add(new AIMicrosoftCalendarService.LinkedRecord(
                                    lr.recordId, lr.recordName, lr.recordType
                                ));
                            }
                        }
                    }
                }
            }

        } catch (Exception e) {
            response.error = 'Error fetching calendar events: ' + e.getMessage();
        }

        return response;
    }

    /**
     * Get calendar events for common date ranges with pagination support
     * @param rangeType 'thisWeek', 'nextWeek', 'thisMonth', 'next30Days', 'allEvents'
     * @param provider 'GOOGLE_CALENDAR' or 'MICROSOFT_CALENDAR'
     * @param searchTerm Optional search term
     * @param pageToken Optional pagination token for next page
     * @param pageSize Optional page size (default 50)
     * @return CalendarEventsResponse with events and pagination info
     */
    @AuraEnabled(cacheable=false)
    public static CalendarEventsResponse getCalendarEventsByRange(String rangeType, String provider, String searchTerm, String pageToken, Integer pageSize) {
        
        DateTime startDt;
        DateTime endDt;

        Date today = Date.today();

        switch on rangeType {
            when 'thisWeek' {
                // Start of current week (Monday) to end of week (Sunday)
                startDt = DateTime.newInstance(today.toStartOfWeek(), Time.newInstance(0, 0, 0, 0));
                endDt = startDt.addDays(7);
            }
            when 'nextWeek' {
                Date nextWeekStart = today.toStartOfWeek().addDays(7);
                startDt = DateTime.newInstance(nextWeekStart, Time.newInstance(0, 0, 0, 0));
                endDt = startDt.addDays(7);
            }
            when 'thisMonth' {
                startDt = DateTime.newInstance(today.toStartOfMonth(), Time.newInstance(0, 0, 0, 0));
                endDt = DateTime.newInstance(today.addMonths(1).toStartOfMonth(), Time.newInstance(0, 0, 0, 0));
            }
            when 'next30Days' {
                startDt = DateTime.now();
                endDt = startDt.addDays(30);
            }
            when 'past7Days' {
                endDt = DateTime.now();
                startDt = endDt.addDays(-7);
            }
            when 'allEvents' {
                // All events: 6 months in the past to 6 months in the future
                startDt = DateTime.now().addMonths(-6);
                endDt = DateTime.now().addMonths(6);
            }
            when else {
                // Default to this week
                startDt = DateTime.newInstance(today.toStartOfWeek(), Time.newInstance(0, 0, 0, 0));
                endDt = startDt.addDays(7);
            }
        }

        // Default page size to 50
        if (pageSize == null || pageSize <= 0) {
            pageSize = 50;
        }

        return getCalendarEventsWithPagination(
            startDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            endDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            pageSize,
            provider,
            searchTerm,
            pageToken
        );
    }
    
    /**
     * Get calendar events with pagination support
     * @param startDate Start of date range (ISO string)
     * @param endDate End of date range (ISO string)
     * @param maxResults Maximum events to return per page
     * @param provider 'GOOGLE_CALENDAR' or 'MICROSOFT_CALENDAR'
     * @param searchTerm Optional search term
     * @param pageToken Optional pagination token
     * @return CalendarEventsResponse with events and pagination info
     */
    private static CalendarEventsResponse getCalendarEventsWithPagination(
        String startDate,
        String endDate,
        Integer maxResults,
        String provider,
        String searchTerm,
        String pageToken
    ) {
        CalendarEventsResponse response = new CalendarEventsResponse();

        // Default to Microsoft Graph if not specified
        if (String.isBlank(provider)) {
            provider = 'MICROSOFT_CALENDAR';
        }

        try {
            // Parse dates
            DateTime startDt = parseISODateTime(startDate);
            DateTime endDt = parseISODateTime(endDate);

            if (startDt == null || endDt == null) {
                response.error = 'Invalid date range provided';
                return response;
            }

            // Check calendar access based on provider
            if (provider == 'GOOGLE_CALENDAR') {
                response.isCalendarAccessible = AIGoogleCalendarService.isCalendarAccessible();
            } else {
                response.isCalendarAccessible = AIMicrosoftCalendarService.isCalendarAccessible();
            }

            if (!response.isCalendarAccessible) {
                response.error = provider == 'GOOGLE_CALENDAR'
                    ? 'Google Calendar access not available. Please ensure calendar.readonly scope is granted.'
                    : 'Outlook Calendar access not available. Please ensure Calendars.Read permission is granted.';
                return response;
            }

            // Fetch events based on provider with pagination
            List<AIMicrosoftCalendarService.CalendarEvent> events;
            String nextToken = null;
            
            // For pagination, we use offset-based approach since Graph API calendarView doesn't support skipToken well
            // Parse pageToken as offset
            Integer offset = 0;
            if (String.isNotBlank(pageToken)) {
                try {
                    offset = Integer.valueOf(pageToken);
                } catch (Exception e) {
                    offset = 0;
                }
            }
            
            // Fetch more events than needed to determine if there are more
            Integer fetchLimit = maxResults + 1;
            
            if (provider == 'GOOGLE_CALENDAR') {
                events = AIGoogleCalendarService.getEventsWithOffset(startDt, endDt, fetchLimit, offset, searchTerm);
            } else {
                events = AIMicrosoftCalendarService.getEventsWithOffset(startDt, endDt, fetchLimit, offset, searchTerm);
            }

            // Check if there are more events
            if (events.size() > maxResults) {
                response.hasMore = true;
                response.nextPageToken = String.valueOf(offset + maxResults);
                // Remove the extra event we fetched
                events.remove(events.size() - 1);
            } else {
                response.hasMore = false;
                response.nextPageToken = null;
            }

            response.events = events;
            // Don't set totalCount here - calendar APIs don't provide accurate totals
            // The LWC will calculate display based on pagination state
            // totalCount stays at 0 (default) to indicate "unknown"

            // Check which events are already imported
            // Collect BOTH dedupIds (new format) AND iCalUIDs (old format) for backwards compatibility
            Set<String> calendarIds = new Set<String>();
            Set<String> iCalUIDs = new Set<String>();
            for (AIMicrosoftCalendarService.CalendarEvent evt : events) {
                String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
                if (String.isNotBlank(dedupId)) {
                    calendarIds.add(dedupId);
                }
                // Also collect iCalUIDs for backwards compatibility with existing staging records
                if (String.isNotBlank(evt.iCalUID)) {
                    iCalUIDs.add(evt.iCalUID);
                    calendarIds.add(evt.iCalUID); // Add to query set
                }
            }

            if (!calendarIds.isEmpty()) {
                response.importedEvents = AICalendarEventCreator.getImportedEventsMap(calendarIds);

                // Get detailed info including associations
                response.importedEventDetails = getImportedEventDetails(calendarIds);

                // Mark events as imported and add association info
                for (AIMicrosoftCalendarService.CalendarEvent evt : response.events) {
                    String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
                    // Check by dedupId first, then fallback to iCalUID for backwards compatibility
                    Boolean foundByDedupId = response.importedEvents.containsKey(dedupId);
                    Boolean foundByICalUID = String.isNotBlank(evt.iCalUID) && response.importedEvents.containsKey(evt.iCalUID);
                    evt.isImported = foundByDedupId || foundByICalUID;
                    
                    // Get details using dedupId first, fallback to iCalUID
                    ImportedEventInfo info = null;
                    if (foundByDedupId && response.importedEventDetails.containsKey(dedupId)) {
                        info = response.importedEventDetails.get(dedupId);
                    } else if (foundByICalUID && response.importedEventDetails.containsKey(evt.iCalUID)) {
                        info = response.importedEventDetails.get(evt.iCalUID);
                    }
                    
                    if (info != null) {
                        // Set first record for backwards compatibility
                        evt.linkedRecordId = info.whoId != null ? info.whoId : info.whatId;
                        evt.linkedRecordName = info.whoName != null ? info.whoName : info.whatName;
                        evt.linkedRecordType = info.whoType != null ? info.whoType : info.whatType;
                        // Set ALL linked records for multiple pills display
                        if (info.linkedRecords != null && !info.linkedRecords.isEmpty()) {
                            for (LinkedRecordInfo lr : info.linkedRecords) {
                                evt.linkedRecords.add(new AIMicrosoftCalendarService.LinkedRecord(
                                    lr.recordId, lr.recordName, lr.recordType
                                ));
                            }
                        }
                    }
                }
            }

        } catch (Exception e) {
            response.error = 'Error fetching calendar events: ' + e.getMessage();
        }

        return response;
    }

    /**
     * Import selected calendar events
     * @param eventIds List of calendar event IDs to import
     * @param provider 'GOOGLE_CALENDAR' or 'MICROSOFT_CALENDAR' (optional, defaults to MICROSOFT_CALENDAR)
     * @return ImportResult with success/failure details
     */
    @AuraEnabled
    public static AICalendarEventCreator.ImportResult importCalendarEvents(List<String> eventIds, String provider) {
        AICalendarEventCreator.ImportResult result = new AICalendarEventCreator.ImportResult();

        if (eventIds == null || eventIds.isEmpty()) {
            result.errors.add('No events selected for import');
            return result;
        }

        // Default to Microsoft Graph if not specified
        if (String.isBlank(provider)) {
            provider = 'MICROSOFT_CALENDAR';
        }

        try {
            // Fetch full event details for each ID based on provider
            List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();

            for (String eventId : eventIds) {
                try {
                    AIMicrosoftCalendarService.CalendarEvent evt;
                    if (provider == 'GOOGLE_CALENDAR') {
                        evt = AIGoogleCalendarService.getEvent(eventId);
                    } else {
                        evt = AIMicrosoftCalendarService.getEvent(eventId);
                    }
                    if (evt != null) {
                        events.add(evt);
                    }
                } catch (Exception e) {
                    result.errors.add('Failed to fetch event ' + eventId + ': ' + e.getMessage());
                }
            }

            // Create Event records without automatic matching
            // User will manually select which records to link via the modal
            if (!events.isEmpty()) {
                result = createEventsWithoutMatching(events, provider);
            }

        } catch (Exception e) {
            result.errors.add('Error importing events: ' + e.getMessage());
        }

        return result;
    }

    /**
     * Import a single calendar event
     * @param eventId The calendar event ID to import
     * @return The created Salesforce Event Id
     */
    @AuraEnabled
    public static Id importSingleEvent(String eventId) {
        try {
            AIMicrosoftCalendarService.CalendarEvent calEvent =
                AIMicrosoftCalendarService.getEvent(eventId);

            if (calEvent != null) {
                return AICalendarEventCreator.importSingleEvent(calEvent, 'MICROSOFT_CALENDAR');
            }

            return null;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to import event: ' + e.getMessage());
        }
    }

    /**
     * Refreshes the access token and returns calendar access status.
     * Call this method when the page loads to ensure a fresh token before any API calls.
     * This handles token refresh (DML) BEFORE any callouts happen.
     * 
     * @param provider - Provider type: 'MICROSOFT_CALENDAR' or 'GOOGLE_CALENDAR'
     * @return Map with isAccessible, ownerEmail, provider, and any errors
     */
    @AuraEnabled
    public static Map<String, Object> refreshTokenAndCheckAccess(String provider) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Convert provider type to AIWorkspaceTokenService format
            String tokenProvider = provider == 'GOOGLE_CALENDAR' ? 'Gmail' : 'Outlook';
            
            // Check if user has a connection
            if (!AIWorkspaceTokenService.hasConnection(tokenProvider)) {
                result.put('isAccessible', false);
                result.put('provider', provider);
                result.put('namespace', AIPromptController.getNameSpace());
                result.put('refreshed', false);
                result.put('message', 'No connection found for ' + tokenProvider);
                return result;
            }
            
            // Attempt to refresh the token (this does callout + DML)
            try {
                AIWorkspaceTokenService.refreshAndGetToken(tokenProvider);
            } catch (AIWorkspaceTokenService.AuthenticationException e) {
                // Token refresh failed - user needs to re-authenticate
                result.put('isAccessible', false);
                result.put('provider', provider);
                result.put('namespace', AIPromptController.getNameSpace());
                result.put('refreshed', false);
                result.put('error', e.getMessage());
                return result;
            }
            
            // Token refreshed successfully - we assume access is available
            // IMPORTANT: We cannot call isCalendarAccessible() or getCalendarInfo() here because:
            // 1. refreshAndGetToken() does callout + DML (saves refreshed token)
            // 2. Calling isCalendarAccessible() would be another callout after DML
            // 3. This causes "You have uncommitted work pending" error
            // 
            // Since the token refresh succeeded, we assume the user has valid credentials.
            // If there's an actual permission issue, it will be caught when fetching events.
            result.put('isAccessible', true);
            result.put('provider', provider);
            result.put('namespace', AIPromptController.getNameSpace());
            result.put('refreshed', true);
            
        } catch (Exception e) {
            result.put('isAccessible', false);
            result.put('error', 'Error refreshing token: ' + e.getMessage());
            result.put('namespace', AIPromptController.getNameSpace());
            result.put('refreshed', false);
        }
        
        return result;
    }

    /**
     * Check if calendar sync is available for current user
     * @param provider Optional provider to check ('GOOGLE_CALENDAR' or 'MICROSOFT_CALENDAR'). If null, auto-detects.
     * @return Map with access status and any error message
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> checkCalendarAccess(String provider) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // If no provider specified, try to auto-detect
            if (String.isBlank(provider)) {
                // Try Microsoft first, then Google
                if (AIMicrosoftCalendarService.isCalendarAccessible()) {
                    provider = 'MICROSOFT_CALENDAR';
                } else if (AIGoogleCalendarService.isCalendarAccessible()) {
                    provider = 'GOOGLE_CALENDAR';
                }
            }

            Boolean isAccessible = false;
            Map<String, String> calendarInfo = new Map<String, String>();

            if (provider == 'GOOGLE_CALENDAR') {
                isAccessible = AIGoogleCalendarService.isCalendarAccessible();
                if (isAccessible) {
                    calendarInfo = AIGoogleCalendarService.getCalendarInfo();
                }
            } else if (provider == 'MICROSOFT_CALENDAR') {
                isAccessible = AIMicrosoftCalendarService.isCalendarAccessible();
                if (isAccessible) {
                    calendarInfo = AIMicrosoftCalendarService.getCalendarInfo();
                }
            }

            result.put('isAccessible', isAccessible);
            result.put('provider', provider);
            result.put('namespace', AIPromptController.getNameSpace());

            if (isAccessible) {
                result.put('calendarName', calendarInfo.get('name'));
                result.put('ownerEmail', calendarInfo.get('ownerEmail'));
            } else {
                String errorMsg = provider == 'GOOGLE_CALENDAR'
                    ? 'Google Calendar access not available. Please ensure calendar.readonly scope is granted.'
                    : 'Outlook Calendar access not available. Please ensure Calendars.Read permission is granted.';
                result.put('error', errorMsg);
            }
        } catch (Exception e) {
            result.put('isAccessible', false);
            result.put('error', 'Error checking calendar access: ' + e.getMessage());
            result.put('namespace', AIPromptController.getNameSpace());
        }

        return result;
    }

    /**
     * Get calendar info for display
     * @return Map with calendar details
     */
    @AuraEnabled
    public static Map<String, String> getCalendarInfo() {
        try {
            return AIMicrosoftCalendarService.getCalendarInfo();
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get calendar info: ' + e.getMessage());
        }
    }

    /**
     * Get detailed info for imported events including linked Lead/Contact
     * 
     * This method queries Event records directly using Workspace_Sync_Id__c
     * to get the Event ID, then queries EventRelation for linked Lead/Contact.
     * 
     * This approach works regardless of whether staging records exist or not.
     */
    private static Map<String, ImportedEventInfo> getImportedEventDetails(Set<String> calendarIds) {
        Map<String, ImportedEventInfo> details = new Map<String, ImportedEventInfo>();

        if (calendarIds == null || calendarIds.isEmpty()) {
            return details;
        }

        try {
            Map<Id, String> eventIdToICalUID = new Map<Id, String>();
            
            
            // Step 1: Query Event records directly using Workspace_Sync_Id__c
            // This is the most reliable source - directly from the Event record
            // Use namespace-aware field name for both field map check and query
            // NOTE: We do NOT filter by OwnerId here because Workspace_Sync_Id__c is unique across the org.
            // If ANY user has imported an event with this iCalUID, it should be shown as imported
            // for ALL users to prevent duplicate value errors on insert.
            String workspaceSyncIdField = AIConstants.NAMESPACE + 'Workspace_Sync_Id__c';
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Event.fields.getMap();
            if (fieldMap.containsKey(workspaceSyncIdField)) {
                // For recurring events, multiple Events may share the same iCalUID
                // We track which iCalUIDs already have an Event ID to avoid duplicates
                Set<String> processedICalUIDs = new Set<String>();
                Integer totalEventsQueried = 0;
                Integer eventsSkippedAsDuplicates = 0;
                
                String queryStr = 'SELECT Id, ' + workspaceSyncIdField + ', WhatId, What.Name, OwnerId, Owner.Name FROM Event ' +
                                 'WHERE ' + workspaceSyncIdField + ' IN :calendarIds';
                for (Event evt : Database.query(queryStr)) {
                    totalEventsQueried++;
                    String iCalUID = (String) evt.get(workspaceSyncIdField);
                    if (String.isNotBlank(iCalUID)) {
                        // Skip if we've already processed this iCalUID to avoid aggregating
                        // EventRelations from multiple recurring event instances
                        if (processedICalUIDs.contains(iCalUID)) {
                            eventsSkippedAsDuplicates++;
                            continue;
                        }
                        processedICalUIDs.add(iCalUID);
                        
                        ImportedEventInfo info = new ImportedEventInfo();
                        info.eventId = evt.Id;
                        
                        // Populate WhatId (Account or Opportunity)
                        if (evt.WhatId != null) {
                            info.whatId = evt.WhatId;
                            info.whatName = evt.What.Name;
                            // Determine type from ID prefix
                            String whatPrefix = String.valueOf(evt.WhatId).substring(0, 3);
                            if (whatPrefix == '001') {
                                info.whatType = 'Account';
                                // Add to linkedRecords for pill display
                                LinkedRecordInfo linkedRecord = new LinkedRecordInfo(
                                    evt.WhatId,
                                    evt.What.Name,
                                    'Account'
                                );
                                info.linkedRecords.add(linkedRecord);
                            } else if (whatPrefix == '006') {
                                info.whatType = 'Opportunity';
                                // Add to linkedRecords for pill display
                                LinkedRecordInfo linkedRecord = new LinkedRecordInfo(
                                    evt.WhatId,
                                    evt.What.Name,
                                    'Opportunity'
                                );
                                info.linkedRecords.add(linkedRecord);
                            }
                        }
                        
                        eventIdToICalUID.put(evt.Id, iCalUID);
                        details.put(iCalUID, info);
                    }
                }
                
            }
            
            // Step 2: Fallback - Query staging records for any remaining IDs
            // (for backwards compatibility with events that don't have Workspace_Sync_Id__c set)
            // NOTE: We do NOT filter by User__c to be consistent with Step 1.
            // If ANY user has imported this event, it should show as imported for all.
            Set<String> remainingIds = new Set<String>();
            for (String iCalUID : calendarIds) {
                if (!details.containsKey(iCalUID)) {
                    remainingIds.add(iCalUID);
                }
            }
            
            if (!remainingIds.isEmpty()) {
                // Track processed iCalUIDs to avoid duplicates from multiple staging records
                Set<String> stagingProcessedICalUIDs = new Set<String>();
                
                for (AI_Workspace_Staging__c staging : [
                    SELECT Id, ICalUID__c, Email_Message__c
                    FROM AI_Workspace_Staging__c
                    WHERE ICalUID__c IN :remainingIds
                    AND RecordType.DeveloperName = 'Calendar'
                    AND Status__c = 'Matched'
                    AND Email_Message__c != null
                ]) {
                    if (String.isNotBlank(staging.ICalUID__c) && String.isNotBlank(staging.Email_Message__c)) {
                        // Skip if we've already processed this iCalUID from staging
                        if (stagingProcessedICalUIDs.contains(staging.ICalUID__c)) {
                            continue;
                        }
                        stagingProcessedICalUIDs.add(staging.ICalUID__c);
                        
                        try {
                            Id eventId = Id.valueOf(staging.Email_Message__c);
                            ImportedEventInfo info = new ImportedEventInfo();
                            info.eventId = eventId;
                            eventIdToICalUID.put(eventId, staging.ICalUID__c);
                            details.put(staging.ICalUID__c, info);
                        } catch (Exception ex) {
                            // Invalid ID, skip
                        }
                    }
                }
            }
            
            // Step 3: Query EventRelation to get actual Lead/Contact associations
            if (!eventIdToICalUID.isEmpty()) {
                
                // Track which record IDs have been added per iCalUID to prevent duplicates
                Map<String, Set<Id>> iCalUIDToAddedRecordIds = new Map<String, Set<Id>>();
                Integer totalEventRelationsQueried = 0;
                Integer contactLeadRelations = 0;
                Integer userRelationsSkipped = 0;
                Integer duplicatesSkipped = 0;
                
                // Query ALL EventRelations, then filter by object type based on ID prefix
                for (EventRelation er : [
                    SELECT EventId, RelationId, Relation.Name
                    FROM EventRelation
                    WHERE EventId IN :eventIdToICalUID.keySet()
                ]) {
                    totalEventRelationsQueried++;
                    // Determine the object type from the RelationId prefix
                    String relationType = '';
                    if (er.RelationId != null) {
                        String prefix = String.valueOf(er.RelationId).substring(0, 3);
                        if (prefix == '003') {
                            relationType = 'Contact';
                        } else if (prefix == '00Q') {
                            relationType = 'Lead';
                        } else if (prefix == '005') {
                            relationType = 'User';
                        }
                    }
                    
                    // Only process Contact and Lead (not User)
                    if (relationType == 'Contact' || relationType == 'Lead') {
                        contactLeadRelations++;
                        String iCalUID = eventIdToICalUID.get(er.EventId);
                        if (iCalUID != null && details.containsKey(iCalUID)) {
                            ImportedEventInfo info = details.get(iCalUID);
                            
                            // Initialize the Set for this iCalUID if not exists
                            if (!iCalUIDToAddedRecordIds.containsKey(iCalUID)) {
                                iCalUIDToAddedRecordIds.put(iCalUID, new Set<Id>());
                            }
                            
                            // Skip if this record ID was already added (prevent duplicate pills)
                            if (iCalUIDToAddedRecordIds.get(iCalUID).contains(er.RelationId)) {
                                duplicatesSkipped++;
                                continue;
                            }
                            
                            // Add to linkedRecords list for multiple pills display
                            LinkedRecordInfo linkedRecord = new LinkedRecordInfo(
                                er.RelationId,
                                er.Relation.Name,
                                relationType
                            );
                            info.linkedRecords.add(linkedRecord);
                            iCalUIDToAddedRecordIds.get(iCalUID).add(er.RelationId);
                            
                            // Also set first one as primary (for backwards compatibility)
                            if (info.whoId == null) {
                                info.whoId = er.RelationId;
                                info.whoName = er.Relation.Name;
                                info.whoType = relationType;
                            }
                        }
                    } else if (relationType == 'User') {
                        userRelationsSkipped++;
                    }
                }
                
                // Log final linkedRecords count per iCalUID
                for (String iCalUID : details.keySet()) {
                    ImportedEventInfo info = details.get(iCalUID);
                }
            }
            
        } catch (Exception e) {
            // Error getting imported event details
        }

        return details;
    }

    /**
     * Parse ISO 8601 datetime string
     */
    private static DateTime parseISODateTime(String isoString) {
        if (String.isBlank(isoString)) {
            return null;
        }

        try {
            // Handle various ISO formats
            String normalized = isoString
                .replace('T', ' ')
                .replace('Z', '')
                .substringBefore('.');

            // If it's just a date, add time
            if (!normalized.contains(' ')) {
                normalized += ' 00:00:00';
            }

            return DateTime.valueOfGmt(normalized);
        } catch (Exception e) {
            return null;
        }
    }
    
    
    /**
     * Associate calendar events from modal with selected Contacts/Leads/Accounts/Opportunities
     * This method will be called from the aiAutoRecordMatchingModal component
     * 
     * @param selections List of selections containing event IDs and associated record IDs
     * @param providerType Provider type (MICROSOFT_CALENDAR or GOOGLE_CALENDAR)
     * @return Map with success status and counts
     */
    @AuraEnabled
    public static Map<String, Object> associateCalendarFromModal(
        List<Map<String, Object>> selections,
        String providerType
    ) {
        Map<String, Object> result = new Map<String, Object>{
            'success' => true,
            'successCount' => 0,
            'failedCount' => 0,
            'duplicateCount' => 0,
            'excludedCount' => 0,
            'errors' => new List<String>()
        };
        
        try {
            if (selections == null || selections.isEmpty()) {
                throw new IllegalArgumentException('No selections provided');
            }
            
            // Extract provider event IDs (these are Microsoft Graph IDs or Google Calendar IDs, NOT iCalUIDs)
            List<String> providerEventIds = new List<String>();
            Map<String, Map<String, Object>> providerIdToSelection = new Map<String, Map<String, Object>>();
            for (Map<String, Object> selection : selections) {
                String providerId = (String) selection.get('messageId'); // Using messageId for consistency with email modal
                providerEventIds.add(providerId);
                providerIdToSelection.put(providerId, selection);
            }
            
            // First, fetch calendar events from provider to get their iCalUID/deduplication IDs
            // This is needed to look up existing events by Workspace_Sync_Id__c
            Map<String, String> providerIdToDeduplicationId = new Map<String, String>();
            Map<String, AIMicrosoftCalendarService.CalendarEvent> providerIdToEvent = new Map<String, AIMicrosoftCalendarService.CalendarEvent>();
            
            for (String providerId : providerEventIds) {
                try {
                    AIMicrosoftCalendarService.CalendarEvent evt;
                    if (providerType == 'GOOGLE_CALENDAR') {
                        evt = AIGoogleCalendarService.getEvent(providerId);
                    } else {
                        evt = AIMicrosoftCalendarService.getEvent(providerId);
                    }
                    if (evt != null) {
                        String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
                        if (String.isNotBlank(dedupId)) {
                            providerIdToDeduplicationId.put(providerId, dedupId);
                            providerIdToEvent.put(providerId, evt);
                        }
                    }
                } catch (Exception e) {
                    // Event fetch failed, will be handled by importCalendarEvents
                }
            }
            
            // Import the events first
            AICalendarEventCreator.ImportResult importResult = importCalendarEvents(providerEventIds, providerType);
            
            // Check if there were any errors (non-duplicate errors)
            if (importResult.errors != null && !importResult.errors.isEmpty()) {
                // Don't return immediately - we may still be able to link to existing duplicates
                result.put('failedCount', importResult.failedCount);
            }
            
            result.put('successCount', importResult.successCount);
            result.put('failedCount', importResult.failedCount);
            result.put('duplicateCount', importResult.duplicateCount);
            
            // Collect all Event IDs to link - both newly created AND existing duplicates
            List<Id> allEventIdsToLink = new List<Id>();
            List<Map<String, Object>> allSelectionsToLink = new List<Map<String, Object>>();
            
            // Add newly created events
            if (!importResult.eventIds.isEmpty()) {
                allEventIdsToLink.addAll(importResult.eventIds);
                // For new events, use selections in order (assumption: events created in order)
                for (Integer i = 0; i < importResult.eventIds.size() && i < selections.size(); i++) {
                    allSelectionsToLink.add(selections[i]);
                }
            }
            
            // For duplicates, find existing Event IDs using deduplication IDs (iCalUID) and link user's selections
            if (importResult.duplicateCount > 0) {
                // Collect deduplication IDs for lookup
                Set<String> deduplicationIds = new Set<String>();
                Map<String, String> dedupIdToProviderId = new Map<String, String>();
                for (String providerId : providerIdToDeduplicationId.keySet()) {
                    String dedupId = providerIdToDeduplicationId.get(providerId);
                    deduplicationIds.add(dedupId);
                    dedupIdToProviderId.put(dedupId, providerId);
                }
                
                // Look up existing events by their Workspace_Sync_Id__c (deduplication ID)
                Map<String, Id> existingEventsMap = AICalendarEventCreator.getImportedEventsMap(deduplicationIds);
                
                // Add existing events for linking
                for (String dedupId : existingEventsMap.keySet()) {
                    Id existingEventId = existingEventsMap.get(dedupId);
                    String providerId = dedupIdToProviderId.get(dedupId);
                    
                    // Only add if not already in the list (from new imports)
                    if (!allEventIdsToLink.contains(existingEventId) && providerIdToSelection.containsKey(providerId)) {
                        allEventIdsToLink.add(existingEventId);
                        allSelectionsToLink.add(providerIdToSelection.get(providerId));
                    }
                }
                
                // If we found existing events for duplicates, treat as success (user can link their records)
                if (!existingEventsMap.isEmpty()) {
                    result.put('success', true);
                    // Update success count to include duplicates that were linked
                    Integer linkedDuplicates = existingEventsMap.size();
                    result.put('successCount', importResult.successCount + linkedDuplicates);
                    result.put('duplicateCount', 0); // No longer treating as duplicates since we're linking
                    // Remove the error message about duplicates
                    ((List<String>) result.get('errors')).clear();
                }
            }
            
            // Link events to Contacts/Leads/Accounts/Opportunities
            if (!allEventIdsToLink.isEmpty()) {
                linkEventsToRecords(allEventIdsToLink, allSelectionsToLink);
                
                // Send notifications for imported events
                sendEventImportNotifications(allEventIdsToLink);
            }
            
            // Set success if we linked any events
            if (!allEventIdsToLink.isEmpty()) {
                result.put('success', true);
            }
            
        } catch (Exception e) {
            result.put('success', false);
            result.put('failedCount', selections != null ? selections.size() : 0);
            ((List<String>) result.get('errors')).add(e.getMessage());
        }
        
        return result;
    }
    
    /**
     * Link Events to Salesforce records (Contacts, Leads, Accounts, Opportunities)
     * Respects Salesforce limitations:
     * - WhatId can be set to ONE Opportunity or Account (Opportunity takes priority)
     * - EventRelation can link to multiple Contacts/Leads
     * - CRITICAL: Cannot link to Lead if WhatId is set (Account/Opportunity)
     * 
     * @param eventIds List of created Event IDs
     * @param selections List of user selections with contactIds, leadIds, accountId, opportunityId
     */
    private static void linkEventsToRecords(List<Id> eventIds, List<Map<String, Object>> selections) {
        if (eventIds == null || eventIds.isEmpty() || selections == null || selections.isEmpty()) {
            return;
        }
        
        // Build map of event index to selection
        // Assumption: eventIds are in the same order as successful selections
        Map<Integer, Map<String, Object>> eventIndexToSelection = new Map<Integer, Map<String, Object>>();
        Integer successfulIndex = 0;
        for (Map<String, Object> selection : selections) {
            if (successfulIndex < eventIds.size()) {
                eventIndexToSelection.put(successfulIndex, selection);
                successfulIndex++;
            }
        }
        
        // Step 1: Update Events with WhatId (Account or Opportunity)
        List<Event> eventsToUpdate = new List<Event>();
        Map<Id, Boolean> eventIdHasWhatId = new Map<Id, Boolean>();
        
        for (Integer i = 0; i < eventIds.size(); i++) {
            Id eventId = eventIds[i];
            Map<String, Object> selection = eventIndexToSelection.get(i);
            
            if (selection == null) {
                continue;
            }
            
            String opportunityId = (String) selection.get('opportunityId');
            String accountId = (String) selection.get('accountId');
            
            // Priority: Opportunity first, then Account
            if (String.isNotBlank(opportunityId) && isValidOpportunityId(opportunityId)) {
                Event evt = new Event(Id = eventId, WhatId = opportunityId);
                eventsToUpdate.add(evt);
                eventIdHasWhatId.put(eventId, true);
            } else if (String.isNotBlank(accountId) && isValidAccountId(accountId)) {
                Event evt = new Event(Id = eventId, WhatId = accountId);
                eventsToUpdate.add(evt);
                eventIdHasWhatId.put(eventId, true);
            } else {
                eventIdHasWhatId.put(eventId, false);
            }
        }
        
        // Update Events with WhatId (with FLS enforcement)
        if (!eventsToUpdate.isEmpty()) {
            // Check object-level update permission
            // Use FLSCheck for FLS/OLS enforcement
            List<Event> accessibleEvents = FLSCheck.getInstance().updateCheck(eventsToUpdate);
            if (accessibleEvents != null && !accessibleEvents.isEmpty()) {
                update accessibleEvents;
            }
        }
        
        // Step 2: Create EventRelation records for Contacts and Leads
        List<EventRelation> relationsToInsert = new List<EventRelation>();
        Set<String> createdRelations = new Set<String>(); // Prevent duplicates: eventId-relationId
        
        for (Integer i = 0; i < eventIds.size(); i++) {
            Id eventId = eventIds[i];
            Map<String, Object> selection = eventIndexToSelection.get(i);
            
            if (selection == null) {
                continue;
            }
            
            Boolean hasWhatId = eventIdHasWhatId.get(eventId);
            List<Object> contactIdsList = (List<Object>) selection.get('contactIds');
            List<Object> leadIdsList = (List<Object>) selection.get('leadIds');
            
            // Create EventRelation for Contacts
            if (contactIdsList != null && !contactIdsList.isEmpty()) {
                for (Object contactIdObj : contactIdsList) {
                    Id contactId = (Id) contactIdObj;
                    if (!isValidContactId(contactId)) {
                        continue;  // Skip invalid IDs
                    }
                    String key = String.valueOf(eventId) + '-' + String.valueOf(contactId);
                    
                    if (!createdRelations.contains(key)) {
                        EventRelation er = new EventRelation();
                        er.EventId = eventId;
                        er.RelationId = contactId;
                        relationsToInsert.add(er);
                        createdRelations.add(key);
                    }
                }
            }
            
            // Create EventRelation for Leads ONLY if WhatId is NOT set
            // Salesforce restriction: Cannot link Lead to Event with Account/Opportunity WhatId
            if (!hasWhatId && leadIdsList != null && !leadIdsList.isEmpty()) {
                for (Object leadIdObj : leadIdsList) {
                    Id leadId = (Id) leadIdObj;
                    if (!isValidLeadId(leadId)) {
                        continue;  // Skip invalid IDs
                    }
                    String key = String.valueOf(eventId) + '-' + String.valueOf(leadId);
                    
                    if (!createdRelations.contains(key)) {
                        EventRelation er = new EventRelation();
                        er.EventId = eventId;
                        er.RelationId = leadId;
                        relationsToInsert.add(er);
                        createdRelations.add(key);
                    }
                }
            }
        }
        
        // Insert EventRelation records (with FLS enforcement)
        if (!relationsToInsert.isEmpty()) {
            // Check object-level create permission
            // Use FLSCheck for FLS/OLS enforcement
            List<EventRelation> accessibleRelations = FLSCheck.getInstance().insertCheck(relationsToInsert);
            if (accessibleRelations != null && !accessibleRelations.isEmpty()) {
                insert accessibleRelations;
            }
        }
    }
    
    /**
     * Create Event records without automatic attendee matching
     * Used for manual imports where user will select which records to link
     * @param calendarEvents List of calendar events to import
     * @param providerType The calendar provider (MICROSOFT_CALENDAR, GOOGLE_CALENDAR)
     * @return ImportResult with created Event IDs
     */
    private static AICalendarEventCreator.ImportResult createEventsWithoutMatching(
        List<AIMicrosoftCalendarService.CalendarEvent> calendarEvents,
        String providerType
    ) {
        AICalendarEventCreator.ImportResult result = new AICalendarEventCreator.ImportResult();
        
        if (calendarEvents == null || calendarEvents.isEmpty()) {
            return result;
        }
        
        // Check FLS for Event object
        if (!Schema.sObjectType.Event.isCreateable()) {
            result.errors.add('Insufficient permissions to create Event records');
            return result;
        }
        
        // Collect all deduplication IDs for checking existing events
        // For Google recurring events: uses eventId (unique per instance)
        // For others: uses iCalUID
        Set<String> calendarEventIds = new Set<String>();
        for (AIMicrosoftCalendarService.CalendarEvent evt : calendarEvents) {
            String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
            if (String.isNotBlank(dedupId)) {
                calendarEventIds.add(dedupId);
            }
        }
        
        // Find existing events with these calendar IDs (deduplication)
        // Use namespace-aware field name for dynamic query
        String workspaceSyncIdField = AIConstants.NAMESPACE + 'Workspace_Sync_Id__c';
        Set<String> existingEventIds = new Set<String>();
        if (!calendarEventIds.isEmpty()) {
            String dedupQueryStr = 'SELECT ' + workspaceSyncIdField + ' FROM Event ' +
                                   'WHERE ' + workspaceSyncIdField + ' IN :calendarEventIds LIMIT 10000';
            for (Event existingEvent : Database.query(dedupQueryStr)) {
                String syncId = (String) existingEvent.get(workspaceSyncIdField);
                if (String.isNotBlank(syncId)) {
                    existingEventIds.add(syncId);
                }
            }
        }
        
        // Prepare events to insert - NO automatic matching
        List<Event> eventsToInsert = new List<Event>();
        
        for (AIMicrosoftCalendarService.CalendarEvent calEvt : calendarEvents) {
            // Skip if already imported (use deduplication ID for proper recurring event handling)
            String dedupId = AICalendarEventCreator.getDeduplicationId(calEvt);
            if (String.isNotBlank(dedupId) && existingEventIds.contains(dedupId)) {
                result.duplicateCount++;
                continue;
            }
            
            try {
                Event sfEvent = new Event();
                
                // Required fields
                sfEvent.Subject = String.isNotBlank(calEvt.subject) ? calEvt.subject : 'Calendar Event';
                sfEvent.OwnerId = UserInfo.getUserId();
                
                // Handle all-day events
                if (calEvt.isAllDay == true) {
                    sfEvent.IsAllDayEvent = true;
                    if (calEvt.startDateTime != null) {
                        sfEvent.ActivityDate = calEvt.startDateTime.date();
                        sfEvent.StartDateTime = calEvt.startDateTime;
                    }
                    if (calEvt.endDateTime != null) {
                        sfEvent.EndDateTime = calEvt.endDateTime;
                    }
                } else {
                    sfEvent.IsAllDayEvent = false;
                    if (calEvt.startDateTime != null) {
                        sfEvent.StartDateTime = calEvt.startDateTime;
                    }
                    if (calEvt.endDateTime != null) {
                        sfEvent.EndDateTime = calEvt.endDateTime;
                    }
                }
                
                // Optional fields
                if (String.isNotBlank(calEvt.location)) {
                    sfEvent.Location = calEvt.location.left(255);
                }
                
                // Build description with event details
                List<String> descParts = new List<String>();
                if (String.isNotBlank(calEvt.description)) {
                    descParts.add(calEvt.description);
                }
                if (String.isNotBlank(calEvt.organizerName) || String.isNotBlank(calEvt.organizerEmail)) {
                    String organizer = 'Organizer: ';
                    if (String.isNotBlank(calEvt.organizerName)) {
                        organizer += calEvt.organizerName;
                    }
                    if (String.isNotBlank(calEvt.organizerEmail)) {
                        organizer += ' <' + calEvt.organizerEmail + '>';
                    }
                    descParts.add(organizer);
                }
                if (calEvt.attendees != null && !calEvt.attendees.isEmpty()) {
                    List<String> attendeeNames = new List<String>();
                    for (AIMicrosoftCalendarService.Attendee att : calEvt.attendees) {
                        if (String.isNotBlank(att.name)) {
                            attendeeNames.add(att.name);
                        } else if (String.isNotBlank(att.email)) {
                            attendeeNames.add(att.email);
                        }
                    }
                    if (!attendeeNames.isEmpty()) {
                        descParts.add('Attendees: ' + String.join(attendeeNames, ', '));
                    }
                }
                if (!descParts.isEmpty()) {
                    sfEvent.Description = String.join(descParts, '\n\n').left(32000);
                }
                
                // Essential custom field for deduplication
                // Use getDeduplicationId for proper Google Calendar recurring event handling
                String syncId = AICalendarEventCreator.getDeduplicationId(calEvt);
                if (String.isNotBlank(syncId)) {
                    sfEvent.Workspace_Sync_Id__c = syncId;
                }
                // Note: Provider info is tracked on AI_Workspace_Staging__c, not on Event
                
                eventsToInsert.add(sfEvent);
            } catch (Exception e) {
                result.errors.add('Error processing event: ' + e.getMessage());
                result.failedCount++;
            }
        }
        
        // Insert events (with FLS enforcement)
        if (!eventsToInsert.isEmpty()) {
            // Check object-level create permission
            if (!Schema.sObjectType.Event.isCreateable()) {
                result.errors.add('Insufficient permissions to create Event records');
                result.failedCount = eventsToInsert.size();
                return result;
            }
            
            // Use FLSCheck for FLS/OLS enforcement
            List<Event> accessibleEvents = FLSCheck.getInstance().insertCheck(eventsToInsert);
            
            if (accessibleEvents == null || accessibleEvents.isEmpty()) {
                return result;
            }
            
            Database.SaveResult[] saveResults = Database.insert(accessibleEvents, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.eventIds.add(saveResults[i].getId());
                    result.successCount++;
                } else {
                    result.failedCount++;
                    String errorMsg = saveResults[i].getErrors()[0].getMessage();
                    result.errors.add('Failed to create event: ' + errorMsg);
                }
            }
        }
        
        return result;
    }
    
    /**
     * Send notifications for imported calendar events
     * @param eventIds List of Event record IDs that were imported
     */
    private static void sendEventImportNotifications(List<Id> eventIds) {
        try {
            // Query for the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];

            if (notifTypes.isEmpty()) {
                return;
            }

            CustomNotificationType notifType = notifTypes[0];
            
            // Query the Event records to get their subjects
            Map<Id, Event> eventsMap = new Map<Id, Event>([
                SELECT Id, Subject
                FROM Event
                WHERE Id IN :eventIds
            ]);

            for (Id eventId : eventIds) {
                try {
                    Event evt = eventsMap.get(eventId);
                    if (evt == null) {
                        continue;
                    }
                    
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();

                    // Truncate subject for title
                    String subject = String.isNotBlank(evt.Subject) ? evt.Subject : '(No Subject)';
                    String truncatedSubject = subject.length() > 40
                        ? subject.substring(0, 40) + '...'
                        : subject;

                    notification.setTitle('📅 Event imported: ' + truncatedSubject);
                    notification.setBody('Calendar event imported successfully.\nClick to view the event.');
                    notification.setNotificationTypeId(notifType.Id);
                    notification.setTargetId(eventId);

                    notification.send(new Set<String>{UserInfo.getUserId()});
                } catch (Exception e) {
                    // Failed to send event notification
                }
            }
        } catch (Exception e) {
            // Error sending event import notifications
        }
    }
    
    /**
     * Validation helper methods to ensure IDs are valid before DML operations
     */
    private static Boolean isValidContactId(Id recordId) {
        return recordId != null && String.valueOf(recordId).startsWith('003');
    }

    private static Boolean isValidLeadId(Id recordId) {
        return recordId != null && String.valueOf(recordId).startsWith('00Q');
    }

    private static Boolean isValidAccountId(String recordId) {
        return String.isNotBlank(recordId) && recordId.startsWith('001');
    }

    private static Boolean isValidOpportunityId(String recordId) {
        return String.isNotBlank(recordId) && recordId.startsWith('006');
    }
}