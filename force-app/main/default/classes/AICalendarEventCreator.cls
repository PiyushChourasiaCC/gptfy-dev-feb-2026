/**
 * CalendarEventCreator
 * Creates Salesforce Event records from calendar events with auto-matching
 *
 * Features:
 * - Creates Event records from calendar data
 * - Prevents duplicates using Workspace_Sync_Id__c
 * - Auto-matches attendees to Contacts/Leads using bulkified matching
 * - Creates EventRelation records for Shared Activities (multiple contacts per event)
 * 
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AICalendarEventCreator {

    /**
     * Result of an import operation
     */
    public class ImportResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failedCount;
        @AuraEnabled public Integer duplicateCount;
        @AuraEnabled public Integer excludedCount;
        @AuraEnabled public Integer matchedCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<Id> eventIds;
        @AuraEnabled public List<EventMatchInfo> matchedEvents;

        public ImportResult() {
            this.successCount = 0;
            this.failedCount = 0;
            this.duplicateCount = 0;
            this.excludedCount = 0;
            this.matchedCount = 0;
            this.errors = new List<String>();
            this.eventIds = new List<Id>();
            this.matchedEvents = new List<EventMatchInfo>();
        }
    }

    /**
     * Information about a matched event
     */
    public class EventMatchInfo {
        @AuraEnabled public Id eventId;
        @AuraEnabled public String eventSubject;
        @AuraEnabled public Id whoId;
        @AuraEnabled public String whoName;
        @AuraEnabled public String whoType;
        @AuraEnabled public Id whatId;
        @AuraEnabled public String whatName;
        @AuraEnabled public String whatType;
        @AuraEnabled public Integer confidence;
        @AuraEnabled public List<Id> allMatchedContactIds; // All matched contacts for Shared Activities
    }

    /**
     * Cache for bulkified Contact/Lead lookup
     */
    private class MatchCache {
        public Map<String, Contact> emailToContact = new Map<String, Contact>();
        public Map<String, Lead> emailToLead = new Map<String, Lead>();
    }

    /**
     * Import calendar events into Salesforce Event records
     * @param calendarEvents List of calendar events to import
     * @param providerType The calendar provider (MICROSOFT_CALENDAR, GOOGLE_CALENDAR)
     * @return ImportResult with success/failure counts
     */
    public static ImportResult importEvents(
        List<AIMicrosoftCalendarService.CalendarEvent> calendarEvents,
        String providerType
    ) {
        ImportResult result = new ImportResult();

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
            String dedupId = getDeduplicationId(evt);
            if (String.isNotBlank(dedupId)) {
                calendarEventIds.add(dedupId);
            }
        }

        // Find existing events with these calendar IDs
        Set<String> existingEventIds = getExistingEventIds(calendarEventIds);

        // BULKIFIED: Collect all attendee emails across all events for single query
        MatchCache cache = buildMatchCache(calendarEvents);

        // Get authenticated user's Contact/Lead match as fallback (single API call)
        AIQuickMatchService.MatchResult userMatch = AIQuickMatchService.getAuthenticatedUserMatch();

        // Prepare events to insert - match attendees BEFORE insert
        List<Event> eventsToInsert = new List<Event>();
        List<EventMatchInfo> matchInfoList = new List<EventMatchInfo>();
        // Track all matched contacts per event for EventRelation creation
        List<List<Id>> eventToAllMatchedIds = new List<List<Id>>();

        for (AIMicrosoftCalendarService.CalendarEvent calEvt : calendarEvents) {
            // Skip if already imported (use deduplication ID for proper recurring event handling)
            String dedupId = getDeduplicationId(calEvt);
            if (String.isNotBlank(dedupId) && existingEventIds.contains(dedupId)) {
                result.duplicateCount++;
                continue;
            }

            try {
                Event sfEvent = createEventFromCalendar(calEvt, providerType);

                // BULKIFIED: Match attendees using cached data (no SOQL in loop)
                EventMatchInfo matchInfo = matchAttendeesWithCache(calEvt, sfEvent, cache);

                // FALLBACK: If no match from attendees, use authenticated user's Contact/Lead
                if (matchInfo == null && userMatch != null && userMatch.confidence > 0) {
                    matchInfo = new EventMatchInfo();
                    if (userMatch.contactId != null) {
                        sfEvent.WhoId = userMatch.contactId;
                        matchInfo.whoId = userMatch.contactId;
                        matchInfo.whoName = userMatch.matchDetails.isEmpty() ? 'User Contact' : userMatch.matchDetails[0];
                        matchInfo.whoType = 'Contact';
                        matchInfo.confidence = 100;
                        matchInfo.allMatchedContactIds = userMatch.contactIds;
                    } else if (userMatch.leadId != null) {
                        sfEvent.WhoId = userMatch.leadId;
                        matchInfo.whoId = userMatch.leadId;
                        matchInfo.whoName = userMatch.matchDetails.isEmpty() ? 'User Lead' : userMatch.matchDetails[0];
                        matchInfo.whoType = 'Lead';
                        matchInfo.confidence = 100;
                        matchInfo.allMatchedContactIds = new List<Id>{ userMatch.leadId };
                    }
                    // Also set WhatId if Account found
                    if (userMatch.accountId != null) {
                        sfEvent.WhatId = userMatch.accountId;
                        matchInfo.whatId = userMatch.accountId;
                        matchInfo.whatType = 'Account';
                    }
                }

                if (matchInfo != null) {
                    matchInfo.eventSubject = sfEvent.Subject;
                }

                eventsToInsert.add(sfEvent);
                matchInfoList.add(matchInfo); // Store matchInfo (may be null)
                // Store all matched IDs for EventRelation creation
                eventToAllMatchedIds.add(matchInfo != null && matchInfo.allMatchedContactIds != null
                    ? matchInfo.allMatchedContactIds
                    : new List<Id>());
            } catch (Exception e) {
                result.failedCount++;
                result.errors.add('Error creating event "' + calEvt.subject + '": ' + e.getMessage());
            }
        }

        eventsToInsert = (List<Event>)FLSCheck.getInstance().insertCheck(eventsToInsert);
        // Insert events
        if(eventsToInsert != null && !eventsToInsert.isEmpty()){
            Database.SaveResult[] saveResults = Database.insert(eventsToInsert, false);

            // Collect Event IDs for EventRelation creation
            Map<Id, List<Id>> eventIdToRelationIds = new Map<Id, List<Id>>();

            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.successCount++;
                    Id eventId = saveResults[i].getId();
                    result.eventIds.add(eventId);

                    // Use the matchInfo we captured during matching (has confidence and names)
                    EventMatchInfo matchInfo = matchInfoList[i];
                    if (matchInfo != null) {
                        matchInfo.eventId = eventId;
                        result.matchedEvents.add(matchInfo);
                        result.matchedCount++;
                    }

                    // Collect additional contacts for EventRelation (beyond WhoId)
                    List<Id> allMatchedIds = eventToAllMatchedIds[i];
                    if (allMatchedIds != null && allMatchedIds.size() > 1) {
                        // First ID is already set as WhoId, create EventRelation for the rest
                        List<Id> additionalIds = new List<Id>();
                        Event insertedEvent = eventsToInsert[i];
                        for (Id matchedId : allMatchedIds) {
                            // Skip the one already set as WhoId
                            if (matchedId != insertedEvent.WhoId) {
                                additionalIds.add(matchedId);
                            }
                        }
                        if (!additionalIds.isEmpty()) {
                            eventIdToRelationIds.put(eventId, additionalIds);
                        }
                    }
                } else {
                    result.failedCount++;
                    String errorMsg = '';
                    for (Database.Error err : saveResults[i].getErrors()) {
                        errorMsg += err.getMessage() + ' ';
                    }
                    result.errors.add('Failed to insert event: ' + errorMsg.trim());
                }
            }

            // Create EventRelation records for Shared Activities
            if (!eventIdToRelationIds.isEmpty()) {
                createEventRelations(eventIdToRelationIds);
            }

            // Send bell notifications for all imported events
            if (result.successCount > 0) {
                sendImportNotifications(result, eventsToInsert, matchInfoList);
            }
        }

        // Create sync log entry
        createSyncLog(result, providerType);

        return result;
    }

    /**
     * Build cache of Contacts/Leads from all attendee emails across all events
     * BULKIFIED: Single SOQL query for Contacts, single for Leads
     */
    private static MatchCache buildMatchCache(List<AIMicrosoftCalendarService.CalendarEvent> calendarEvents) {
        MatchCache cache = new MatchCache();

        // Collect all unique attendee emails from all events
        Set<String> allAttendeeEmails = new Set<String>();
        for (AIMicrosoftCalendarService.CalendarEvent calEvt : calendarEvents) {
            if (calEvt.attendees != null) {
                for (AIMicrosoftCalendarService.Attendee att : calEvt.attendees) {
                    if (String.isNotBlank(att.email)) {
                        allAttendeeEmails.add(att.email.trim().toLowerCase());
                    }
                }
            }
            // Also check organizer email
            if (String.isNotBlank(calEvt.organizerEmail)) {
                allAttendeeEmails.add(calEvt.organizerEmail.trim().toLowerCase());
            }
        }

        if (allAttendeeEmails.isEmpty()) {
            return cache;
        }

        // Query 1: Bulk fetch Contacts by email
        for (Contact c : [
            SELECT Id, Name, Email, AccountId
            FROM Contact
            WHERE Email IN :allAttendeeEmails
        ]) {
            if (String.isNotBlank(c.Email)) {
                cache.emailToContact.put(c.Email.toLowerCase(), c);
            }
        }

        // Query 2: Bulk fetch Leads by email (only non-converted)
        for (Lead l : [
            SELECT Id, Name, Email, Company
            FROM Lead
            WHERE Email IN :allAttendeeEmails
            AND IsConverted = false
        ]) {
            if (String.isNotBlank(l.Email)) {
                cache.emailToLead.put(l.Email.toLowerCase(), l);
            }
        }

        return cache;
    }

    /**
     * Match attendees to Contacts/Leads using cached data (no SOQL in loop)
     * Sets WhoId on Event and collects ALL matched contacts for EventRelation
     * @param calEvt The calendar event with attendee data
     * @param sfEvent The Salesforce Event to update with WhoId
     * @param cache Pre-built cache of email -> Contact/Lead mappings
     * @return EventMatchInfo with primary match and all matched contact IDs
     */
    private static EventMatchInfo matchAttendeesWithCache(
        AIMicrosoftCalendarService.CalendarEvent calEvt,
        Event sfEvent,
        MatchCache cache
    ) {
        if (calEvt.attendees == null || calEvt.attendees.isEmpty()) {
            return null;
        }

        // Collect ALL matching Contacts and Leads for this event
        List<Id> allMatchedContactIds = new List<Id>();
        List<Id> allMatchedLeadIds = new List<Id>();
        Contact primaryContact = null;
        Lead primaryLead = null;

        for (AIMicrosoftCalendarService.Attendee att : calEvt.attendees) {
            if (String.isBlank(att.email)) continue;

            String email = att.email.trim().toLowerCase();

            // Check for Contact match
            if (cache.emailToContact.containsKey(email)) {
                Contact c = cache.emailToContact.get(email);
                allMatchedContactIds.add(c.Id);
                if (primaryContact == null) {
                    primaryContact = c;
                }
            }
            // Check for Lead match (only if no Contact for this email)
            else if (cache.emailToLead.containsKey(email)) {
                Lead l = cache.emailToLead.get(email);
                allMatchedLeadIds.add(l.Id);
                if (primaryLead == null) {
                    primaryLead = l;
                }
            }
        }

        // No matches found
        if (allMatchedContactIds.isEmpty() && allMatchedLeadIds.isEmpty()) {
            return null;
        }

        // Build match info
        EventMatchInfo matchInfo = new EventMatchInfo();
        matchInfo.confidence = 95; // Direct email match

        // Prefer Contacts over Leads for primary WhoId
        if (primaryContact != null) {
            sfEvent.WhoId = primaryContact.Id;
            matchInfo.whoId = primaryContact.Id;
            matchInfo.whoName = primaryContact.Name;
            matchInfo.whoType = 'Contact';
            // Store ALL matched Contact IDs for EventRelation
            matchInfo.allMatchedContactIds = allMatchedContactIds;
        } else if (primaryLead != null) {
            sfEvent.WhoId = primaryLead.Id;
            matchInfo.whoId = primaryLead.Id;
            matchInfo.whoName = primaryLead.Name;
            matchInfo.whoType = 'Lead';
            // Store ALL matched Lead IDs for EventRelation
            matchInfo.allMatchedContactIds = allMatchedLeadIds;
        }

        return matchInfo;
    }

    /**
     * Create EventRelation records for Shared Activities
     * Links additional Contacts/Leads beyond the primary WhoId
     * @param eventIdToRelationIds Map of Event ID to list of Contact/Lead IDs
     */
    private static void createEventRelations(Map<Id, List<Id>> eventIdToRelationIds) {
        if (eventIdToRelationIds == null || eventIdToRelationIds.isEmpty()) {
            return;
        }

        List<SObject> relationsToInsert = new List<SObject>();
        Schema.SObjectType eventRelationType = Schema.getGlobalDescribe().get('EventRelation');

        // EventRelation may not exist in all orgs (requires Shared Activities enabled)
        if (eventRelationType == null) {
            return;
        }

        for (Id eventId : eventIdToRelationIds.keySet()) {
            for (Id relationId : eventIdToRelationIds.get(eventId)) {
                SObject er = eventRelationType.newSObject();
                er.put('EventId', eventId);
                er.put('RelationId', relationId);
                relationsToInsert.add(er);
            }
        }

        if (!relationsToInsert.isEmpty()) {
            // Use partial success to handle any permission issues
            relationsToInsert = (List<EventRelation>)FLSCheck.getInstance().insertCheck(relationsToInsert);
            if(relationsToInsert != null && !relationsToInsert.isEmpty()){
                Database.SaveResult[] results = Database.insert(relationsToInsert, false);
                Integer successCount = 0;
                for (Database.SaveResult sr : results) {
                    if (sr.isSuccess()) {
                        successCount++;
                    }
                }
            }
        }
    }

    /**
     * Send bell notifications for all imported calendar events.
     * For matched events: clicking notification navigates to the matched CRM record.
     * For unmatched events: clicking notification navigates to the Event record itself.
     * @param result The import result containing event IDs
     * @param eventsToInsert The list of events that were inserted
     * @param matchInfoList The list of match info corresponding to each event
     */
    private static void sendImportNotifications(
        ImportResult result,
        List<Event> eventsToInsert,
        List<EventMatchInfo> matchInfoList
    ) {
        try {
            // Get notification type
            List<CustomNotificationType> notifTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :AIConstants.WORKSPACE_SYNC_NOTIFICATION_TYPE
                LIMIT 1
            ];

            if (notifTypes.isEmpty()) {
                return;
            }

            Id notifTypeId = notifTypes[0].Id;
            Id currentUserId = UserInfo.getUserId();

            // Iterate through all successfully imported events
            for (Integer i = 0; i < eventsToInsert.size(); i++) {
                Event sfEvent = eventsToInsert[i];

                // Skip if event wasn't successfully inserted (no Id)
                if (sfEvent.Id == null) {
                    continue;
                }

                EventMatchInfo matchInfo = (i < matchInfoList.size()) ? matchInfoList[i] : null;

                // Build notification
                String subject = sfEvent.Subject;
                if (String.isBlank(subject)) subject = '(No Subject)';
                String truncatedSubject = subject.length() > 40 ? subject.substring(0, 40) + '...' : subject;

                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle('📅 Event imported: ' + truncatedSubject);
                notification.setNotificationTypeId(notifTypeId);

                // Always navigate to the Event record (not the matched CRM record)
                notification.setBody('Event imported successfully.\nClick to view the event.');
                notification.setTargetId(sfEvent.Id);

                try {
                    notification.send(new Set<String>{ currentUserId });
                } catch (Exception e) {
                }
            }
        } catch (Exception e) {
        }
    }

    /**
     * Create a sync log entry for the calendar import
     */
    private static void createSyncLog(ImportResult result, String providerType) {
        try {
            AI_Workspace_Sync_Log__c log = new AI_Workspace_Sync_Log__c();
            log.User__c = UserInfo.getUserId();
            log.Record_Type__c = 'Calendar';
            log.Sync_Type__c = 'Manual';
            log.Provider_Type__c = providerType == 'MICROSOFT_CALENDAR' ? 'Exchange' : providerType;
            log.Start_Time__c = DateTime.now();
            log.End_Time__c = DateTime.now();
            log.Events_Imported__c = result.successCount;
            log.Events_Duplicate__c = result.duplicateCount;
            log.Events_Failed__c = result.failedCount;

            if (result.failedCount > 0 || !result.errors.isEmpty()) {
                log.Status__c = result.successCount > 0 ? 'Partial' : 'Failed';
                log.Error_Message__c = String.join(result.errors, '\n').left(131072);
            } else {
                log.Status__c = 'Success';
            }

            FLSCheck.getInstance().insertDML(new List<AI_Workspace_Sync_Log__c>{log});
        } catch (Exception e) {
            // Don't fail the import if logging fails
        }
    }

    /**
     * Import a single calendar event
     * @param calendarEvent The calendar event to import
     * @param providerType The calendar provider
     * @return The created Event Id, or null if failed
     */
    public static Id importSingleEvent(
        AIMicrosoftCalendarService.CalendarEvent calendarEvent,
        String providerType
    ) {
        // Use AIWorkspaceStagingCreator to create staging records
        AIWorkspaceStagingCreator.StagingResult result = 
            AIWorkspaceStagingCreator.createCalendarStagingRecords(
                new List<AIMicrosoftCalendarService.CalendarEvent>{ calendarEvent },
                providerType,
                null  // No sync log for single imports
            );

        if (result.stagingRecordIds != null && !result.stagingRecordIds.isEmpty()) {
            return result.stagingRecordIds[0];
        }

        return null;
    }

    /**
     * Check which events have already been imported (with actual Salesforce Event created)
     * 
     * This method checks BOTH:
     * 1. Event records directly - the most reliable source
     * 2. AI_Workspace_Staging__c - for backwards compatibility where Event doesn't have Workspace_Sync_Id__c
     * 
     * IMPORTANT: Only returns events where an actual Salesforce Event record exists.
     * Staging records without a valid Event are NOT considered "imported".
     * 
     * @param calendarEventIds Set of calendar event IDs (iCalUIDs)
     * @return Map of calendarEventId to Salesforce Event Id
     */
    public static Map<String, Id> getImportedEventsMap(Set<String> calendarEventIds) {
        Map<String, Id> importedMap = new Map<String, Id>();

        if (calendarEventIds == null || calendarEventIds.isEmpty()) {
            return importedMap;
        }

        try {
            // Step 1: Query Event records directly using Workspace_Sync_Id__c
            // This is the most reliable source - the actual Event exists
            // Use namespace-aware field name for both field map check and query
            // NOTE: We do NOT filter by OwnerId here because Workspace_Sync_Id__c is unique across the org.
            // If ANY user has imported an event with this iCalUID, it should be marked as imported
            // for ALL users to prevent duplicate value errors on insert.
            String workspaceSyncIdField = AIConstants.NAMESPACE + 'Workspace_Sync_Id__c';
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Event.fields.getMap();
            if (fieldMap.containsKey(workspaceSyncIdField)) {
                String queryStr = 'SELECT Id, ' + workspaceSyncIdField + ' FROM Event ' +
                                 'WHERE ' + workspaceSyncIdField + ' IN :calendarEventIds';
                for (Event evt : Database.query(queryStr)) {
                    String iCalUID = (String) evt.get(workspaceSyncIdField);
                    if (String.isNotBlank(iCalUID)) {
                        importedMap.put(iCalUID, evt.Id);
                    }
                }
            }
            
            // Step 2: Fallback - Query staging records that have a valid Event ID
            // Only for IDs not found in Step 1
            // NOTE: Also removed User__c filter to be consistent with Step 1
            Set<String> remainingIds = new Set<String>();
            for (String iCalUID : calendarEventIds) {
                if (!importedMap.containsKey(iCalUID)) {
                    remainingIds.add(iCalUID);
                }
            }
            
            if (!remainingIds.isEmpty()) {
                for (AI_Workspace_Staging__c staging : [
                    SELECT Id, ICalUID__c, Email_Message__c
                    FROM AI_Workspace_Staging__c
                    WHERE ICalUID__c IN :remainingIds
                    AND RecordType.DeveloperName = 'Calendar'
                    AND Status__c = 'Imported'
                    AND Email_Message__c != null
                ]) {
                    if (String.isNotBlank(staging.ICalUID__c) && String.isNotBlank(staging.Email_Message__c)) {
                        try {
                            // Verify it's a valid Event ID
                            Id eventId = Id.valueOf(staging.Email_Message__c);
                            importedMap.put(staging.ICalUID__c, eventId);
                        } catch (Exception ex) {
                            // Invalid ID, skip
                        }
                    }
                }
            }
        } catch (Exception e) {
        }

        return importedMap;
    }

    /**
     * Get set of calendar event IDs that already exist in Salesforce
     */
    private static Set<String> getExistingEventIds(Set<String> calendarEventIds) {
        Set<String> existingIds = new Set<String>();

        if (calendarEventIds == null || calendarEventIds.isEmpty()) {
            return existingIds;
        }

        // Check FLS
        if (!Schema.sObjectType.Event.fields.Workspace_Sync_Id__c.isAccessible()) {
            return existingIds;
        }

        // Query without USER_MODE since FLS is already checked above
        List<Event> existingEvents = [
            SELECT Workspace_Sync_Id__c
            FROM Event
            WHERE Workspace_Sync_Id__c IN :calendarEventIds
            AND OwnerId = :UserInfo.getUserId()
        ];

        for (Event evt : existingEvents) {
            existingIds.add(evt.Workspace_Sync_Id__c);
        }

        return existingIds;
    }

    /**
     * Create a Salesforce Event from a calendar event
     */
    private static Event createEventFromCalendar(
        AIMicrosoftCalendarService.CalendarEvent calEvt,
        String providerType
    ) {
        Event sfEvent = new Event();

        // Required fields
        sfEvent.Subject = String.isNotBlank(calEvt.subject) ? calEvt.subject : 'Calendar Event';
        sfEvent.OwnerId = UserInfo.getUserId();

        // Handle all-day events
        if (calEvt.isAllDay == true) {
            sfEvent.IsAllDayEvent = true;
            // For all-day events, set ActivityDate
            if (calEvt.startDateTime != null) {
                sfEvent.ActivityDate = calEvt.startDateTime.date();
            }
            // All-day events also need StartDateTime/EndDateTime
            if (calEvt.startDateTime != null) {
                sfEvent.StartDateTime = calEvt.startDateTime;
            }
            if (calEvt.endDateTime != null) {
                sfEvent.EndDateTime = calEvt.endDateTime;
            }
        } else {
            // Regular timed events
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
            sfEvent.Location = AIExchangeEmailHelper.truncateField(calEvt.location, 255);
        }

        // Build description with event details
        String description = buildDescription(calEvt);
        if (String.isNotBlank(description)) {
            sfEvent.Description = AIExchangeEmailHelper.truncateField(description, 32000);
        }

        // Essential custom fields for deduplication and provider tracking
        // These persist even after Staging records are deleted
        // 
        // IMPORTANT: For Google Calendar recurring events (singleEvents=true), all instances
        // share the same iCalUID but have unique eventIds. We must use eventId for deduplication
        // to allow each recurring instance to be imported as a separate Salesforce Event.
        sfEvent.Workspace_Sync_Id__c = getDeduplicationId(calEvt);

        // Note: Provider info is tracked on AI_Workspace_Staging__c, not on Event

        return sfEvent;
    }
    
    /**
     * Get the deduplication ID for a calendar event.
     * 
     * For Google Calendar recurring events: use eventId (unique per instance)
     * For all other events: use iCalUID (unique per event/series)
     * 
     * This is critical because Google Calendar API with singleEvents=true returns
     * recurring event instances with the SAME iCalUID but different eventIds.
     * Without this, only the first instance of a recurring event would be imported.
     * 
     * @param calEvt The calendar event
     * @return The unique identifier to use for deduplication
     */
    public static String getDeduplicationId(AIMicrosoftCalendarService.CalendarEvent calEvt) {
        // For Google Calendar recurring events, use eventId as it's unique per instance
        // The presence of recurringEventId indicates this is an instance of a recurring event
        if (calEvt.provider == 'GOOGLE_CALENDAR' && String.isNotBlank(calEvt.recurringEventId)) {
            // Use eventId for recurring event instances - it's unique per occurrence
            if (String.isNotBlank(calEvt.eventId)) {
                return calEvt.eventId;
            }
        }
        
        // For non-recurring Google events, Microsoft Calendar, and other providers: use iCalUID
        if (String.isNotBlank(calEvt.iCalUID)) {
            return calEvt.iCalUID;
        }
        
        // Final fallback to eventId
        return calEvt.eventId;
    }

    /**
     * Build description text with event details
     */
    private static String buildDescription(AIMicrosoftCalendarService.CalendarEvent calEvt) {
        List<String> parts = new List<String>();

        // Original description
        if (String.isNotBlank(calEvt.description)) {
            parts.add(calEvt.description);
        }

        // Add organizer info
        if (String.isNotBlank(calEvt.organizerEmail)) {
            String organizer = 'Organizer: ' + calEvt.organizerEmail;
            if (String.isNotBlank(calEvt.organizerName)) {
                organizer = 'Organizer: ' + calEvt.organizerName + ' <' + calEvt.organizerEmail + '>';
            }
            parts.add(organizer);
        }

        // Add attendee list
        if (calEvt.attendees != null && !calEvt.attendees.isEmpty()) {
            List<String> attendeeNames = new List<String>();
            for (AIMicrosoftCalendarService.Attendee att : calEvt.attendees) {
                if (att.isOrganizer != true) {
                    String attStr = String.isNotBlank(att.name) ?
                        att.name + ' <' + att.email + '>' : att.email;
                    attendeeNames.add(attStr);
                }
            }
            if (!attendeeNames.isEmpty()) {
                parts.add('Attendees: ' + String.join(attendeeNames, ', '));
            }
        }

        // Add meeting link if present
        if (String.isNotBlank(calEvt.meetingLink)) {
            parts.add('Meeting Link: ' + calEvt.meetingLink);
        }

        return String.join(parts, '\n\n');
    }
}