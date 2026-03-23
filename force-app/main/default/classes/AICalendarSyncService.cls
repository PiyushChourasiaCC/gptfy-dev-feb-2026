/**
 * CalendarSyncService - Service for automated calendar sync
 *
 * Handles:
 * - Fetching calendar events from Microsoft Graph OR Google Calendar
 * - Auto-detecting which provider the user has configured
 * - Importing events into Salesforce Event records
 * - Running as a specific user context for OAuth credentials
 * - Creating sync logs for visibility
 *
 * Called by AIUserSyncQueueable during scheduled sync runs.
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AICalendarSyncService {

    /**
     * NEW: Entry point for workspace-based sync (with access token).
     * Used by AIWorkspaceSyncQueueable when syncing via stored refresh tokens.
     * Does NOT rely on Named Credentials or user context.
     * 
     * @param userId The user whose calendar should be synced
     * @param provider 'Outlook' or 'Gmail' (from AI_Workspace_User__c.Provider__c)
     * @param accessToken Fresh access token from OAuth refresh
     */
    public static void syncUserCalendarWithToken(Id userId, String provider, String accessToken) {
        syncUserCalendarWithToken(userId, provider, accessToken, false);
    }
    
    /**
     * Overloaded method with isRunNowMode parameter
     * NEW BEHAVIOR (2026-02-13):
     * - Run Now: Always uses lookback/lookahead days from settings (default 7 days lookback, 30 days lookahead)
     * - Scheduler: Always uses lookback/lookahead days from settings
     * 
     * This ensures that events modified or inserted after the last sync are captured,
     * as calendar events can be updated at any time.
     * 
     * @param userId The user whose calendar should be synced
     * @param provider 'Outlook' or 'Gmail' (from AI_Workspace_User__c.Provider__c)
     * @param accessToken Fresh access token from OAuth refresh
     * @param isRunNowMode True if triggered by Run Now button, false for scheduled sync
     */
    public static void syncUserCalendarWithToken(Id userId, String provider, String accessToken, Boolean isRunNowMode) {
        DateTime startTime = DateTime.now();
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        
        if (settings == null || !settings.Calendar_Sync_Enabled__c) {
            return;
        }
        
        SyncResult result = new SyncResult();
        result.userId = userId;
        result.syncType = 'Scheduled';
        result.providerType = provider == 'Outlook' ? 'MICROSOFT_CALENDAR' : 'GOOGLE_CALENDAR';
        
        try {
            // Calculate date range from settings
            Integer lookbackDays = settings.Calendar_Lookback_Days__c != null ?
                (Integer) settings.Calendar_Lookback_Days__c : 7;
            Integer lookaheadDays = settings.Calendar_Lookahead_Days__c != null ?
                (Integer) settings.Calendar_Lookahead_Days__c : 30;
            Integer maxEvents = settings.Max_Calendar_Events_Per_User__c != null ?
                (Integer) settings.Max_Calendar_Events_Per_User__c : 50;
            
            DateTime startDate;
            DateTime endDate;
            
            // FIXED (2026-02-15): Calendar APIs filter by event START time, not modification time
            // To properly sync calendar events, we need to understand that:
            // - Lookback Days: How far back to look for events (by their START date)
            // - Lookahead Days: How far forward to look for events (by their START date)
            // 
            // This is different from email sync which uses modification time.
            // For calendar events, we sync all events whose start time falls within the window.
            if (lookbackDays <= 0) {
                lookbackDays = 7;
            }
            if (lookaheadDays <= 0) {
                lookaheadDays = 30;
            }
            
            // Use the configured lookback/lookahead days directly
            // This defines the window of event START times to sync
            startDate = DateTime.now().addDays(-lookbackDays);
            endDate = DateTime.now().addDays(lookaheadDays);
            
            // Set sync window dates for logging
            result.syncWindowStart = startDate;
            result.syncWindowEnd = endDate;
            
            // Fetch events using token-based fetch service
            List<Map<String, Object>> rawEvents;
            if (provider == 'Outlook') {
                rawEvents = AIOutlookFetchService.fetchCalendarEvents(accessToken, startDate, endDate, maxEvents);
            } else {
                rawEvents = AIGmailFetchService.fetchCalendarEvents(accessToken, startDate, endDate, maxEvents);
            }
            
            result.eventsFetched = rawEvents != null ? rawEvents.size() : 0;
            
            if (rawEvents == null || rawEvents.isEmpty()) {
                result.status = 'Success';
                result.eventsImported = 0;
                createSyncLog(result, startTime);
                return;
            }
            
            // Convert raw events to CalendarEvent objects
            List<AIMicrosoftCalendarService.CalendarEvent> events = convertToCalendarEvents(rawEvents, provider, result.providerType);
            
            if (events.isEmpty()) {
                result.status = 'Success';
                result.eventsImported = 0;
                createSyncLog(result, startTime);
                return;
            }
            
            // NOTE: For calendar sync, we do NOT update syncWindowEnd with the newest event date
            // Unlike email sync, calendar events should always use the full lookahead window because:
            // - Calendar events can be modified at any time (not just new events)
            // - We're already using lookback/lookahead days to capture all changes
            // - The sync window should represent the actual query range, not the last event processed
            // This ensures the sync log accurately reflects the date range queried from the provider
            
            // V2-7889: Apply exclusion filters before creating staging records
            String excludedDomains = AISyncSettingsService.getExcludedDomains();
            String excludedLabels = AISyncSettingsService.getExcludedLabelsCategories();
            
            AIWorkspaceFilterService.FilterResult filterResult =
                AIWorkspaceFilterService.applyAllFilters(
                    convertEventsToMaps(events),
                    excludedDomains,
                    excludedLabels,
                    'Calendar',
                    provider == 'Outlook' ? 'Outlook' : 'Gmail'
                );
            
            Integer eventsExcluded = filterResult.excludedCount;
            
            // V2-7889: Build exclusion summary from filter results
            String exclusionSummary = buildExclusionSummary(filterResult.exclusionReasons);
            
            // Convert filtered events back to CalendarEvent objects
            List<AIMicrosoftCalendarService.CalendarEvent> filteredEvents = 
                convertMapsToCalendarEvents(filterResult.includedRecords, provider, result.providerType);
            
            // Import events to staging (deduplication and matching handled inside)
            AIWorkspaceStagingCreator.StagingResult stagingResult =
                AIWorkspaceStagingCreator.createCalendarStagingRecords(filteredEvents, result.providerType, null, userId, false);
            
            // V2-7889: Phase 1 tracking - staging record creation only (not Lead/Contact matching)
            // Matched = Successfully created staging records
            // Unmatched = Failed to create staging records
            result.eventsDuplicate = stagingResult.duplicateCount;
            result.eventsMatched = stagingResult.successCount;      // Successfully created staging records
            result.eventsUnmatched = stagingResult.failedCount;     // Failed to create staging records
            result.eventsExcluded = eventsExcluded;                 // Excluded by domain/label filters
            result.exclusionSummary = exclusionSummary;             // Detailed breakdown
            result.eventsImported = 0;  // Always 0 in Phase 1 (Phase 3 handles imports)
            result.eventsFailed = 0;  // No failures if staging records created successfully
            result.status = stagingResult.errors.isEmpty() ? 'Success' : 'Partial';
            
            if (!stagingResult.errors.isEmpty()) {
                result.errorMessage = String.join(stagingResult.errors, '; ');
            }
            
        } catch (Exception e) {
            result.status = 'Failed';
            result.errorMessage = e.getMessage();
        }
        
        createSyncLog(result, startTime);
    }
    
    /**
     * Convert raw event maps to CalendarEvent objects
     * @param rawEvents List of event data maps from fetch service
     * @param provider 'Outlook' or 'Gmail'
     * @param providerType 'MICROSOFT_CALENDAR' or 'GOOGLE_CALENDAR'
     * @return List of CalendarEvent objects
     */
    private static List<AIMicrosoftCalendarService.CalendarEvent> convertToCalendarEvents(
        List<Map<String, Object>> rawEvents, 
        String provider,
        String providerType
    ) {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        for (Map<String, Object> eventMap : rawEvents) {
            try {
                AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
                
                if (provider == 'Outlook') {
                    // Microsoft Graph format
                    evt.eventId = (String) eventMap.get('id');
                    evt.iCalUID = (String) eventMap.get('iCalUId');
                    evt.subject = (String) eventMap.get('subject');
                    evt.isAllDay = eventMap.get('isAllDay') == true;
                    
                    // Parse start/end times
                    Map<String, Object> startMap = (Map<String, Object>) eventMap.get('start');
                    Map<String, Object> endMap = (Map<String, Object>) eventMap.get('end');
                    
                    if (startMap != null) {
                        evt.startDateTime = parseGraphDateTime((String) startMap.get('dateTime'), evt.isAllDay);
                    }
                    if (endMap != null) {
                        evt.endDateTime = parseGraphDateTime((String) endMap.get('dateTime'), evt.isAllDay);
                    }
                    
                    // Location
                    Map<String, Object> locMap = (Map<String, Object>) eventMap.get('location');
                    if (locMap != null) {
                        evt.location = (String) locMap.get('displayName');
                    }
                    
                    // Body/Description
                    Map<String, Object> bodyMap = (Map<String, Object>) eventMap.get('body');
                    if (bodyMap != null) {
                        String content = (String) bodyMap.get('content');
                        if (String.isNotBlank(content)) {
                            evt.description = content.stripHtmlTags();
                        }
                    }
                    if (String.isBlank(evt.description)) {
                        evt.description = (String) eventMap.get('bodyPreview');
                    }
                    
                    // Online meeting link
                    Map<String, Object> onlineMeeting = (Map<String, Object>) eventMap.get('onlineMeeting');
                    if (onlineMeeting != null) {
                        evt.meetingLink = (String) onlineMeeting.get('joinUrl');
                    }
                    
                    // Organizer
                    Map<String, Object> organizer = (Map<String, Object>) eventMap.get('organizer');
                    if (organizer != null) {
                        Map<String, Object> emailAddr = (Map<String, Object>) organizer.get('emailAddress');
                        if (emailAddr != null) {
                            evt.organizerEmail = (String) emailAddr.get('address');
                            evt.organizerName = (String) emailAddr.get('name');
                        }
                    }
                    
                    // Attendees
                    evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();
                    List<Object> attendeeList = (List<Object>) eventMap.get('attendees');
                    if (attendeeList != null) {
                        for (Object attObj : attendeeList) {
                            Map<String, Object> attData = (Map<String, Object>) attObj;
                            AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
                            Map<String, Object> emailAddr = (Map<String, Object>) attData.get('emailAddress');
                            if (emailAddr != null) {
                                att.email = (String) emailAddr.get('address');
                                att.name = (String) emailAddr.get('name');
                            }
                            evt.attendees.add(att);
                        }
                    }
                    
                } else {
                    // Google Calendar format
                    evt.eventId = (String) eventMap.get('id');
                    evt.iCalUID = (String) eventMap.get('iCalUID');
                    evt.subject = (String) eventMap.get('summary');
                    evt.description = (String) eventMap.get('description');
                    evt.location = (String) eventMap.get('location');
                    
                    // Parse start/end times
                    Map<String, Object> startMap = (Map<String, Object>) eventMap.get('start');
                    Map<String, Object> endMap = (Map<String, Object>) eventMap.get('end');
                    
                    if (startMap != null) {
                        if (startMap.containsKey('date')) {
                            evt.isAllDay = true;
                            evt.startDateTime = parseGoogleDate((String) startMap.get('date'));
                        } else {
                            evt.startDateTime = parseGoogleDateTime((String) startMap.get('dateTime'));
                        }
                    }
                    if (endMap != null) {
                        if (endMap.containsKey('date')) {
                            evt.endDateTime = parseGoogleDate((String) endMap.get('date'));
                        } else {
                            evt.endDateTime = parseGoogleDateTime((String) endMap.get('dateTime'));
                        }
                    }
                    
                    // Organizer
                    Map<String, Object> organizer = (Map<String, Object>) eventMap.get('organizer');
                    if (organizer != null) {
                        evt.organizerEmail = (String) organizer.get('email');
                        evt.organizerName = (String) organizer.get('displayName');
                    }
                    
                    // Meeting link
                    evt.meetingLink = (String) eventMap.get('hangoutLink');
                    
                    // Attendees
                    evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();
                    List<Object> attendeeList = (List<Object>) eventMap.get('attendees');
                    if (attendeeList != null) {
                        for (Object attObj : attendeeList) {
                            Map<String, Object> attData = (Map<String, Object>) attObj;
                            AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
                            att.email = (String) attData.get('email');
                            att.name = (String) attData.get('displayName');
                            att.responseStatus = (String) attData.get('responseStatus');
                            evt.attendees.add(att);
                        }
                    }
                }
                
                evt.provider = providerType;
                events.add(evt);
                
            } catch (Exception e) {
                // Continue with other events
            }
        }
        
        return events;
    }
    
    /**
     * Parse Microsoft Graph datetime string
     */
    private static DateTime parseGraphDateTime(String dateTimeStr, Boolean isAllDay) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }
        
        try {
            if (dateTimeStr.contains('.')) {
                dateTimeStr = dateTimeStr.substringBefore('.');
            }
            
            if (isAllDay) {
                Date d = Date.valueOf(dateTimeStr.substring(0, 10));
                return DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
            } else {
                return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
            }
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Parse Google Calendar datetime string (RFC 3339)
     */
    private static DateTime parseGoogleDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }
        
        try {
            // Handle timezone offset
            if (dateTimeStr.contains('+')) {
                dateTimeStr = dateTimeStr.substringBefore('+');
            } else if (dateTimeStr.endsWith('Z')) {
                dateTimeStr = dateTimeStr.removeEnd('Z');
            }
            
            return DateTime.valueOfGmt(dateTimeStr.replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Parse Google Calendar date string (for all-day events)
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
     * Sync calendar events for the current user.
     * Auto-detects which calendar provider is available (Microsoft or Google).
     * Uses OAuth credentials from the user's Named Credential principal.
     */
    public static void syncUserCalendar(Id userId) {
        DateTime startTime = DateTime.now();
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();

        if (settings == null || !settings.Calendar_Sync_Enabled__c) {
            return;
        }

        SyncResult result = new SyncResult();
        result.userId = userId;
        result.syncType = 'Scheduled';

        try {
            // Detect which calendar provider is available
            String provider = detectCalendarProvider();
            result.providerType = provider;

            if (String.isBlank(provider)) {
                result.status = 'Skipped';
                result.errorMessage = 'No calendar provider accessible - OAuth may not be configured for Microsoft or Google';
                createSyncLog(result, startTime);
                return;
            }

            // Calculate date range from settings
            Integer lookbackDays = settings.Calendar_Lookback_Days__c != null ?
                (Integer) settings.Calendar_Lookback_Days__c : 7;
            Integer lookaheadDays = settings.Calendar_Lookahead_Days__c != null ?
                (Integer) settings.Calendar_Lookahead_Days__c : 30;
            Integer maxEvents = settings.Max_Calendar_Events_Per_User__c != null ?
                (Integer) settings.Max_Calendar_Events_Per_User__c : 50;

            // Validate lookback/lookahead days to prevent invalid date ranges
            if (lookbackDays <= 0) {
                lookbackDays = 7;
            }
            if (lookaheadDays <= 0) {
                lookaheadDays = 30;
            }

            DateTime startDate = DateTime.now().addDays(-lookbackDays);
            DateTime endDate = DateTime.now().addDays(lookaheadDays);

            // Fetch events from the appropriate provider
            List<AIMicrosoftCalendarService.CalendarEvent> events;
            if (provider == 'GOOGLE_CALENDAR') {
                events = AIGoogleCalendarService.getEvents(startDate, endDate, maxEvents, null);
            } else {
                events = AIMicrosoftCalendarService.getEvents(startDate, endDate, maxEvents, null);
            }

            result.eventsFetched = events.size();

            if (events.isEmpty()) {
                result.status = 'Success';
                result.eventsImported = 0;
                createSyncLog(result, startTime);
                return;
            }

            // Import events to staging (deduplication and matching handled inside)
            AIWorkspaceStagingCreator.StagingResult stagingResult =
                AIWorkspaceStagingCreator.createCalendarStagingRecords(events, provider, null, userId, false);

            // Use actual counts from staging result
            result.eventsImported = stagingResult.importedCount;    // Actual Event records created
            // V2-7889: Phase 1 tracking
            result.eventsDuplicate = stagingResult.duplicateCount;
            result.eventsMatched = stagingResult.successCount;      // Successfully created staging records
            result.eventsUnmatched = stagingResult.failedCount;     // Failed to create staging records
            result.eventsImported = 0;  // Always 0 in Phase 1
            result.eventsFailed = 0;  // No failures if staging records created
            result.status = stagingResult.errors.isEmpty() ? 'Success' : 'Partial';

            if (!stagingResult.errors.isEmpty()) {
                result.errorMessage = String.join(stagingResult.errors, '; ');
            }

        } catch (Exception e) {
            result.status = 'Failed';
            result.errorMessage = e.getMessage();
        }

        createSyncLog(result, startTime);
    }

    /**
     * Processes a batch of raw events from Microsoft Graph (Delta Sync)
     */
    public static void processDeltaEvents(List<Object> rawEvents, Id userId) {
        if (rawEvents == null || rawEvents.isEmpty()) return;
        
        DateTime startTime = DateTime.now();
        SyncResult result = new SyncResult();
        result.userId = userId;
        result.syncType = 'Delta';
        result.providerType = 'MICROSOFT_CALENDAR';

        try {
            // Convert to CalendarEvent objects
            // Simple manual mapping since JSON.deserialize might fail on generic Object list elements
            List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
            
            for (Object obj : rawEvents) {
                Map<String, Object> eventMap = (Map<String, Object>) obj;
                // Basic mapping required for import logic
                AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
                evt.eventId = (String) eventMap.get('id');
                evt.iCalUID = (String) eventMap.get('iCalUId');
                evt.subject = (String) eventMap.get('subject');
                
                // Start/End
                Map<String, Object> startMap = (Map<String, Object>) eventMap.get('start');
                Map<String, Object> endMap = (Map<String, Object>) eventMap.get('end');
                
                if (startMap != null) evt.startDateTime = (DateTime) JSON.deserialize('"' + (String)startMap.get('dateTime') + '"', DateTime.class);
                if (endMap != null) evt.endDateTime = (DateTime) JSON.deserialize('"' + (String)endMap.get('dateTime') + '"', DateTime.class);
                
                evt.isAllDay = (Boolean) eventMap.get('isAllDay');
                
                // Location
                Map<String, Object> locMap = (Map<String, Object>) eventMap.get('location');
                if (locMap != null) evt.location = (String) locMap.get('displayName');
                
                // Body
                Map<String, Object> bodyMap = (Map<String, Object>) eventMap.get('body');
                if (bodyMap != null) evt.description = (String) bodyMap.get('content');
                
                evt.meetingLink = (String) eventMap.get('webLink'); // Map webLink to meetingLink or ignore if strictly meeting link

                
                events.add(evt);
            }
            
            result.eventsFetched = events.size();

            // Import events to staging (deduplication and matching handled inside)
            if (!events.isEmpty()) {
                AIWorkspaceStagingCreator.StagingResult stagingResult = 
                    AIWorkspaceStagingCreator.createCalendarStagingRecords(events, 'MICROSOFT_CALENDAR', null, userId, false);
                result.eventsImported = stagingResult.importedCount;    // Actual Event records created
                // V2-7889: Phase 1 tracking
                result.eventsMatched = stagingResult.successCount;      // Successfully created staging records
                result.eventsUnmatched = stagingResult.failedCount;     // Failed to create staging records
                result.eventsDuplicate = stagingResult.duplicateCount;
                result.eventsImported = 0;  // Always 0 in Phase 1
                result.eventsFailed = 0;  // No failures if staging records created
                if (!stagingResult.errors.isEmpty()) result.errorMessage = String.join(stagingResult.errors, '; ');
            }
            
            result.status = String.isBlank(result.errorMessage) ? 'Success' : 'Partial';

        } catch (Exception e) {
            result.status = 'Failed';
            result.errorMessage = e.getMessage();
        } finally {
            createSyncLog(result, startTime);
        }
    }

    /**
     * Detect which calendar provider is available for the current user.
     * Tries Microsoft first, then Google.
     * @return Provider name ('MICROSOFT_CALENDAR', 'GOOGLE_CALENDAR') or null if none available
     */
    private static String detectCalendarProvider() {
        // Try Microsoft first
        try {
            if (AIMicrosoftCalendarService.isCalendarAccessible()) {
                return 'MICROSOFT_CALENDAR';
            }
        } catch (Exception e) {
            // Continue to try Google Calendar
        }

        // Try Google Calendar
        try {
            if (AIGoogleCalendarService.isCalendarAccessible()) {
                return 'GOOGLE_CALENDAR';
            }
        } catch (Exception e) {
            // No calendar provider accessible
        }

        return null;
    }

    /**
     * Create a sync log entry for visibility
     */
    private static void createSyncLog(SyncResult result, DateTime startTime) {
        try {
            if (!Schema.sObjectType.AI_Workspace_Sync_Log__c.isCreateable()) {
                return;
            }

            // Use specific provider type for Calendar sync (MICROSOFT_CALENDAR or GOOGLE_CALENDAR)
            String calendarProviderType;
            if (String.isNotBlank(result.providerType)) {
                if (result.providerType == 'MICROSOFT_CALENDAR') {
                    calendarProviderType = 'MICROSOFT_CALENDAR';
                } else if (result.providerType == 'GOOGLE_CALENDAR') {
                    calendarProviderType = 'GOOGLE_CALENDAR';
                } else {
                    calendarProviderType = result.providerType; // Use as-is if already specific
                }
            } else {
                calendarProviderType = 'MICROSOFT_CALENDAR'; // Default
            }
            
            // V2-7889: Phase 1 tracking - use Emails_ fields for consistency with UI
            // Formula: Fetched = Matched + Duplicate + Unmatched + Excluded
            AI_Workspace_Sync_Log__c log = new AI_Workspace_Sync_Log__c(
                User__c = result.userId,
                Sync_Type__c = result.syncType,
                Provider_Type__c = calendarProviderType,
                Record_Type__c = 'Calendar',
                Status__c = result.status,
                Start_Time__c = startTime,
                End_Time__c = DateTime.now(),
                Sync_Window_Start__c = result.syncWindowStart,
                Sync_Window_End__c = result.syncWindowEnd,
                Emails_Fetched__c = result.eventsFetched,
                Emails_Matched__c = result.eventsMatched,      // Successfully created staging records
                Emails_Duplicate__c = result.eventsDuplicate,
                Emails_Unmatched__c = result.eventsUnmatched,  // Failed to create staging records
                Emails_Excluded__c = result.eventsExcluded,    // Excluded by domain/label filters
                Emails_Imported__c = 0,  // Always 0 in Phase 1
                Events_Imported__c = 0,  // Always 0 in Phase 1
                Events_Duplicate__c = result.eventsDuplicate,
                Events_Failed__c = 0,  // No failures in Phase 1
                Exclusion_Summary__c = result.exclusionSummary,  // Detailed breakdown
                Error_Message__c = AIExchangeEmailHelper.truncateField(result.errorMessage, 32000)
            );

            // Calculate processing time
            Long processingMs = DateTime.now().getTime() - startTime.getTime();
            log.Processing_Time_Seconds__c = processingMs / 1000.0;

            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ log };
            FLSCheck.getInstance().insertDML(logsToInsert);
        } catch (Exception e) {
            // Ignore
        }
    }

    /**
     * Wrapper class for sync result
     */
    public class SyncResult {
        public Id userId;
        public String syncType;
        public String providerType;
        public String status;
        public DateTime syncWindowStart;
        public DateTime syncWindowEnd;
        public Integer eventsFetched = 0;
        public Integer eventsImported = 0;     // Actual Event records created
        public Integer eventsDuplicate = 0;
        public Integer eventsMatched = 0;      // Matched to Lead/Contact
        public Integer eventsUnmatched = 0;    // Not matched to any Lead/Contact
        public Integer eventsExcluded = 0;     // Excluded by domain/label filters
        public Integer eventsFailed = 0;
        public String errorMessage;
        public String exclusionSummary;        // Detailed breakdown of exclusions
    }
    
    /**
     * V2-7889: Convert CalendarEvent objects to Map format for filter service
     * The filter service expects organizer in Microsoft Graph API format:
     * { "emailAddress": { "address": "email@domain.com" } }
     */
    private static List<Map<String, Object>> convertEventsToMaps(List<AIMicrosoftCalendarService.CalendarEvent> events) {
        List<Map<String, Object>> eventMaps = new List<Map<String, Object>>();
        
        for (AIMicrosoftCalendarService.CalendarEvent evt : events) {
            Map<String, Object> eventMap = new Map<String, Object>();
            eventMap.put('id', evt.eventId);
            eventMap.put('subject', evt.subject);
            
            // Convert organizer to Graph API format for filter service
            if (String.isNotBlank(evt.organizerEmail)) {
                Map<String, Object> organizer = new Map<String, Object>();
                Map<String, Object> emailAddress = new Map<String, Object>();
                emailAddress.put('address', evt.organizerEmail);
                emailAddress.put('name', evt.organizerName);
                organizer.put('emailAddress', emailAddress);
                eventMap.put('organizer', organizer);
            }
            
            // Note: categories field doesn't exist on CalendarEvent - labels are checked separately
            eventMap.put('startDateTime', evt.startDateTime);
            eventMap.put('endDateTime', evt.endDateTime);
            eventMap.put('location', evt.location);
            eventMap.put('isAllDay', evt.isAllDay);
            eventMap.put('iCalUID', evt.iCalUID);
            eventMap.put('provider', evt.provider);
            
            // Store the original event object for reconstruction
            eventMap.put('_originalEvent', evt);
            
            eventMaps.add(eventMap);
        }
        
        return eventMaps;
    }
    
    /**
     * V2-7889: Convert Map format back to CalendarEvent objects after filtering
     * Uses the stored original event object to preserve all fields
     */
    private static List<AIMicrosoftCalendarService.CalendarEvent> convertMapsToCalendarEvents(
        List<Map<String, Object>> eventMaps,
        String provider,
        String providerType
    ) {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        for (Map<String, Object> eventMap : eventMaps) {
            // Use the original event object if available (preserves all fields)
            AIMicrosoftCalendarService.CalendarEvent evt = 
                (AIMicrosoftCalendarService.CalendarEvent) eventMap.get('_originalEvent');
            
            if (evt != null) {
                events.add(evt);
            }
        }
        
        return events;
    }
    
    // V2-7889: Build exclusion summary from filter results
    private static String buildExclusionSummary(Map<String, Integer> exclusionReasons) {
        if (exclusionReasons == null || exclusionReasons.isEmpty()) {
            return null;
        }
        
        List<String> summaryParts = new List<String>();
        
        // Sort reasons for consistent output
        List<String> sortedReasons = new List<String>(exclusionReasons.keySet());
        sortedReasons.sort();
        
        for (String reason : sortedReasons) {
            Integer count = exclusionReasons.get(reason);
            if (count > 0) {
                summaryParts.add(reason + ': ' + count);
            }
        }
        
        return summaryParts.isEmpty() ? null : String.join(summaryParts, ', ');
    }
}