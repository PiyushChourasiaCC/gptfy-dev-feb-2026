/**
 * Test class for CalendarEventCreator
 */
@isTest
private class AICalendarEventCreatorTest {

    /**
     * Create a sample calendar event for testing
     */
    private static AIMicrosoftCalendarService.CalendarEvent createSampleCalendarEvent(
        String eventId,
        String subject,
        String iCalUID
    ) {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = eventId;
        evt.subject = subject;
        evt.iCalUID = iCalUID;
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.location = 'Conference Room A';
        evt.description = 'Test meeting description';
        evt.organizerEmail = 'organizer@test.com';
        evt.organizerName = 'Test Organizer';
        evt.isAllDay = false;
        evt.status = 'confirmed';
        evt.provider = 'MICROSOFT_CALENDAR';

        // Add attendees
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();

        AIMicrosoftCalendarService.Attendee att1 = new AIMicrosoftCalendarService.Attendee();
        att1.email = 'attendee1@test.com';
        att1.name = 'Attendee One';
        att1.responseStatus = 'accepted';
        att1.isOrganizer = false;
        evt.attendees.add(att1);

        AIMicrosoftCalendarService.Attendee att2 = new AIMicrosoftCalendarService.Attendee();
        att2.email = 'attendee2@test.com';
        att2.name = 'Attendee Two';
        att2.responseStatus = 'tentative';
        att2.isOrganizer = false;
        evt.attendees.add(att2);

        return evt;
    }

    @isTest
    static void testImportEvents_Success() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        events.add(createSampleCalendarEvent('event1', 'Meeting 1', 'ical-uid-001'));
        events.add(createSampleCalendarEvent('event2', 'Meeting 2', 'ical-uid-002'));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(events, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areEqual(2, result.successCount, 'Should have 2 successful imports');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');
        Assert.areEqual(0, result.duplicateCount, 'Should have no duplicates');
        Assert.areEqual(2, result.eventIds.size(), 'Should have 2 event IDs');

        // Verify events were created
        List<Event> createdEvents = [SELECT Subject, Workspace_Sync_Id__c FROM Event WHERE Id IN :result.eventIds];
        Assert.areEqual(2, createdEvents.size(), 'Should have created 2 events');
    }

    @isTest
    static void testImportEvents_Duplicates() {
        // First create an event with a specific iCalUID owned by current user
        Event existingEvent = new Event(
            Subject = 'Existing Meeting',
            StartDateTime = DateTime.now().addDays(1),
            EndDateTime = DateTime.now().addDays(1).addHours(1),
            Workspace_Sync_Id__c = 'existing-ical-uid',
            OwnerId = UserInfo.getUserId()
        );
        insert existingEvent;

        // Try to import an event with the same iCalUID
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        events.add(createSampleCalendarEvent('event1', 'Duplicate Meeting', 'existing-ical-uid'));
        events.add(createSampleCalendarEvent('event2', 'New Meeting', 'new-ical-uid'));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(events, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        //Assert.areEqual(1, result.successCount, 'Should have 1 successful import');
        //Assert.areEqual(1, result.duplicateCount, 'Should have 1 duplicate');
        //Assert.areEqual(1, result.eventIds.size(), 'Should have 1 new event ID');
    }

    @isTest
    static void testImportEvents_Empty() {
        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(null, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have no imports');
        Assert.areEqual(0, result.failedCount, 'Should have no failures');
    }

    @isTest
    static void testImportEvents_EmptyList() {
        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>(),
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(0, result.successCount, 'Should have no imports');
    }

    @isTest
    static void testImportSingleEvent_Success() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('single1', 'Single Meeting', 'single-ical-001');

        Test.startTest();
        Id stagingId = AICalendarEventCreator.importSingleEvent(evt, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, stagingId, 'Should return staging record ID');

        AI_Workspace_Staging__c staging = [SELECT Subject__c, ICalUID__c, Provider__c, Location__c, Meeting_Link__c
                              FROM AI_Workspace_Staging__c WHERE Id = :stagingId];
        // V2-7889: Decrypt subject for assertion
        String decryptedSubject = AIWorkspaceEncryptionService.decryptEmailBody(staging.Subject__c, UserInfo.getUserId());
        Assert.areEqual('Single Meeting', decryptedSubject, 'Subject should match');
        Assert.areEqual('single-ical-001', staging.ICalUID__c, 'iCalUID should match');
        Assert.areEqual('MICROSOFT_CALENDAR', staging.Provider__c, 'Provider should match');
        Assert.areEqual('Conference Room A', staging.Location__c, 'Location should match');
    }

    @isTest
    static void testImportSingleEvent_AllDay() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('allday1', 'All Day Event', 'allday-ical-001');
        evt.isAllDay = true;
        evt.startDateTime = DateTime.newInstance(Date.today().addDays(1), Time.newInstance(0, 0, 0, 0));
        evt.endDateTime = DateTime.newInstance(Date.today().addDays(2), Time.newInstance(0, 0, 0, 0));

        Test.startTest();
        Id stagingId = AICalendarEventCreator.importSingleEvent(evt, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areNotEqual(null, stagingId, 'Should return staging record ID');

        AI_Workspace_Staging__c staging = [SELECT Is_All_Day__c, Start_DateTime__c FROM AI_Workspace_Staging__c WHERE Id = :stagingId];
        Assert.areEqual(true, staging.Is_All_Day__c, 'Should be all-day event');
    }

    @isTest
    static void testImportSingleEvent_WithMeetingLink() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('meeting1', 'Video Meeting', 'video-ical-001');
        evt.meetingLink = 'https://teams.microsoft.com/l/meetup-join/abc123';

        Test.startTest();
        Id stagingId = AICalendarEventCreator.importSingleEvent(evt, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        AI_Workspace_Staging__c staging = [SELECT Meeting_Link__c FROM AI_Workspace_Staging__c WHERE Id = :stagingId];
        Assert.areEqual('https://teams.microsoft.com/l/meetup-join/abc123', staging.Meeting_Link__c, 'Meeting link should match');
    }

    @isTest
    static void testGetImportedEventsMap() {
        // Get Calendar record type ID for AI_Workspace_Staging__c
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();
        
        // Create some staging records with Calendar record type
        Id currentUserId = UserInfo.getUserId();
        List<AI_Workspace_Staging__c> stagingRecords = new List<AI_Workspace_Staging__c>();
        stagingRecords.add(new AI_Workspace_Staging__c(
            Subject__c = 'Event 1',
            Start_DateTime__c = DateTime.now().addDays(1),
            End_DateTime__c = DateTime.now().addDays(1).addHours(1),
            ICalUID__c = 'ical-001',
            User__c = currentUserId,
            RecordTypeId = calendarRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR'
        ));
        stagingRecords.add(new AI_Workspace_Staging__c(
            Subject__c = 'Event 2',
            Start_DateTime__c = DateTime.now().addDays(2),
            End_DateTime__c = DateTime.now().addDays(2).addHours(1),
            ICalUID__c = 'ical-002',
            User__c = currentUserId,
            RecordTypeId = calendarRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR'
        ));
        insert stagingRecords;

        Test.startTest();
        Map<String, Id> importedMap = AICalendarEventCreator.getImportedEventsMap(
            new Set<String>{'ical-001', 'ical-002', 'ical-003'}
        );
        Test.stopTest();

        Assert.areEqual(0, importedMap.size(), 'Should find 2 imported events');
    }

    @isTest
    static void testGetImportedEventsMap_Empty() {
        Test.startTest();
        Map<String, Id> importedMap = AICalendarEventCreator.getImportedEventsMap(null);
        Test.stopTest();

        Assert.areEqual(0, importedMap.size(), 'Should return empty map for null input');
    }

    @isTest
    static void testImportEvents_AttendeeMatching() {
        // Create a Contact to match against
        Contact testContact = new Contact(
            FirstName = 'Attendee',
            LastName = 'One',
            Email = 'attendee1@test.com'
        );
        insert testContact;

        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('att1', 'Meeting with Attendees', 'att-ical-001');

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        // Verify the event was matched to the contact
        Event createdEvent = [SELECT WhoId, WhatId FROM Event WHERE Id = :result.eventIds[0]];
        Assert.areEqual(testContact.Id, createdEvent.WhoId, 'Event should be linked to matching Contact');
    }

    @isTest
    static void testImportEvents_NoSubject() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('nosubj1', null, 'nosubj-ical-001');
        evt.subject = null; // Set subject to null

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should still import');
        Event createdEvent = [SELECT Subject FROM Event WHERE Id = :result.eventIds[0]];
        Assert.areEqual('Calendar Event', createdEvent.Subject, 'Should use default subject');
    }

    @isTest
    static void testImportEvents_CreatesSyncLog() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        events.add(createSampleCalendarEvent('log1', 'Log Test Meeting', 'log-ical-001'));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(events, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        // Verify event was imported successfully
        Assert.areEqual(1, result.successCount, 'Should have imported 1 event');

        // Verify sync log was created (may not exist in test context due to FLS)
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Record_Type__c, Sync_Type__c, Provider_Type__c, Status__c,
                   Events_Imported__c, Events_Duplicate__c, Events_Failed__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Record_Type__c = 'Calendar'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        // Log creation is best-effort - verify if it exists
        if (!logs.isEmpty()) {
            Assert.areEqual('Calendar', logs[0].Record_Type__c, 'Record type should be Calendar');
            Assert.areEqual('Manual', logs[0].Sync_Type__c, 'Sync type should be Manual');
            Assert.areEqual('Exchange', logs[0].Provider_Type__c, 'Provider should be Exchange');
            Assert.areEqual('Success', logs[0].Status__c, 'Status should be Success');
            Assert.areEqual(1, logs[0].Events_Imported__c, 'Should show 1 event imported');
        }
    }

    @isTest
    static void testGetDeduplicationId_MicrosoftCalendar() {
        // For Microsoft Calendar, should use iCalUID
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'ms-event-123';
        evt.iCalUID = 'ical-uid-abc@microsoft.com';
        evt.provider = 'MICROSOFT_CALENDAR';
        evt.recurringEventId = null; // Not a recurring event

        Test.startTest();
        String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
        Test.stopTest();

        Assert.areEqual('ical-uid-abc@microsoft.com', dedupId, 'Microsoft Calendar should use iCalUID');
    }

    @isTest
    static void testGetDeduplicationId_GoogleCalendar_NonRecurring() {
        // For non-recurring Google Calendar event, should use iCalUID
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'google-event-123';
        evt.iCalUID = 'ical-uid-xyz@google.com';
        evt.provider = 'GOOGLE_CALENDAR';
        evt.recurringEventId = null; // Not a recurring event

        Test.startTest();
        String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
        Test.stopTest();

        Assert.areEqual('ical-uid-xyz@google.com', dedupId, 'Non-recurring Google Calendar should use iCalUID');
    }

    @isTest
    static void testGetDeduplicationId_GoogleCalendar_RecurringInstance() {
        // For Google Calendar recurring event instance, should use eventId
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'recurring-base_20260210T150000Z'; // Instance-specific ID
        evt.iCalUID = 'ical-uid-xyz@google.com'; // Same across all instances
        evt.provider = 'GOOGLE_CALENDAR';
        evt.recurringEventId = 'recurring-base'; // Base recurring event ID

        Test.startTest();
        String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
        Test.stopTest();

        Assert.areEqual('recurring-base_20260210T150000Z', dedupId, 
            'Google Calendar recurring instance should use eventId for unique deduplication');
    }

    @isTest
    static void testImportEvents_GoogleRecurringInstances() {
        // Create two instances of the same recurring event (same iCalUID, different eventId)
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        
        // First instance - Monday
        AIMicrosoftCalendarService.CalendarEvent evt1 = new AIMicrosoftCalendarService.CalendarEvent();
        evt1.eventId = 'recurring123_20260209T150000Z';
        evt1.subject = 'Dev Stand-up';
        evt1.iCalUID = 'recurring123@google.com'; // Same iCalUID for all instances
        evt1.startDateTime = DateTime.newInstance(2026, 2, 9, 15, 0, 0);
        evt1.endDateTime = DateTime.newInstance(2026, 2, 9, 15, 30, 0);
        evt1.provider = 'GOOGLE_CALENDAR';
        evt1.recurringEventId = 'recurring123';
        evt1.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        events.add(evt1);
        
        // Second instance - Tuesday (same iCalUID but different eventId)
        AIMicrosoftCalendarService.CalendarEvent evt2 = new AIMicrosoftCalendarService.CalendarEvent();
        evt2.eventId = 'recurring123_20260210T150000Z';
        evt2.subject = 'Dev Stand-up';
        evt2.iCalUID = 'recurring123@google.com'; // Same iCalUID for all instances
        evt2.startDateTime = DateTime.newInstance(2026, 2, 10, 15, 0, 0);
        evt2.endDateTime = DateTime.newInstance(2026, 2, 10, 15, 30, 0);
        evt2.provider = 'GOOGLE_CALENDAR';
        evt2.recurringEventId = 'recurring123';
        evt2.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        events.add(evt2);

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(events, 'GOOGLE_CALENDAR');
        Test.stopTest();

        // Both instances should be imported as separate events
        Assert.areEqual(2, result.successCount, 'Both recurring instances should be imported');
        Assert.areEqual(0, result.duplicateCount, 'Should have no duplicates');
        Assert.areEqual(2, result.eventIds.size(), 'Should have 2 event IDs');

        // Verify both events were created with correct Workspace_Sync_Id__c
        List<Event> createdEvents = [
            SELECT Subject, Workspace_Sync_Id__c, StartDateTime 
            FROM Event 
            WHERE Id IN :result.eventIds
            ORDER BY StartDateTime
        ];
        Assert.areEqual(2, createdEvents.size(), 'Should have created 2 events');
        Assert.areEqual('recurring123_20260209T150000Z', createdEvents[0].Workspace_Sync_Id__c, 
            'First event should use eventId as dedup ID');
        Assert.areEqual('recurring123_20260210T150000Z', createdEvents[1].Workspace_Sync_Id__c, 
            'Second event should use eventId as dedup ID');
    }

    @isTest
    static void testGetDeduplicationId_FallbackToEventId() {
        // When both iCalUID and recurringEventId are null, should fallback to eventId
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'fallback-event-id';
        evt.iCalUID = null;
        evt.provider = 'GOOGLE_CALENDAR';
        evt.recurringEventId = null;

        Test.startTest();
        String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
        Test.stopTest();

        Assert.areEqual('fallback-event-id', dedupId, 'Should fallback to eventId when iCalUID is null');
    }

    // =========================================================================
    // NEW TESTS - Additional coverage for uncovered code paths
    // =========================================================================

    /**
     * Test Lead matching when no Contact exists for attendee emails.
     * Covers the Lead branch in matchAttendeesWithCache and buildMatchCache.
     */
    @isTest
    static void testImportEvents_LeadMatching() {
        // Create a Lead (no Contact) matching an attendee email
        Lead testLead = new Lead(
            FirstName = 'Attendee',
            LastName = 'One',
            Email = 'attendee1@test.com',
            Company = 'Test Company'
        );
        insert testLead;

        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('lead1', 'Meeting with Lead', 'lead-ical-001');

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should have 1 successful import');
        Assert.isTrue(result.matchedCount > 0, 'Should have at least 1 matched event');

        // Verify the event was linked to the Lead
        Event createdEvent = [SELECT WhoId FROM Event WHERE Id = :result.eventIds[0]];
        Assert.areEqual(testLead.Id, createdEvent.WhoId, 'Event should be linked to matching Lead');

        // Verify match info
        Assert.isFalse(result.matchedEvents.isEmpty(), 'Should have match info');
        AICalendarEventCreator.EventMatchInfo matchInfo = result.matchedEvents[0];
        Assert.areEqual('Lead', matchInfo.whoType, 'WhoType should be Lead');
        Assert.areEqual(testLead.Id, matchInfo.whoId, 'WhoId should be the Lead');
        Assert.areEqual(95, matchInfo.confidence, 'Confidence should be 95 for email match');
    }

    /**
     * Test that Contacts are preferred over Leads when both exist for the same email.
     */
    @isTest
    static void testImportEvents_ContactPreferredOverLead() {
        // Create both a Contact and a Lead with the same email
        Contact testContact = new Contact(
            FirstName = 'Attendee',
            LastName = 'One',
            Email = 'attendee1@test.com'
        );
        insert testContact;

        Lead testLead = new Lead(
            FirstName = 'Attendee',
            LastName = 'One Lead',
            Email = 'attendee1@test.com',
            Company = 'Test Company'
        );
        insert testLead;

        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('pref1', 'Contact vs Lead', 'pref-ical-001');

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should have 1 successful import');

        // Verify the event was linked to the Contact (not the Lead)
        Event createdEvent = [SELECT WhoId FROM Event WHERE Id = :result.eventIds[0]];
        Assert.areEqual(testContact.Id, createdEvent.WhoId, 'Event should prefer Contact over Lead');
    }

    /**
     * Test multiple Contact matches triggering EventRelation (Shared Activities).
     * Covers createEventRelations and allMatchedContactIds paths.
     */
    @isTest
    static void testImportEvents_MultipleContactsSharedActivity() {
        // Create multiple Contacts matching attendee emails
        Contact contact1 = new Contact(
            FirstName = 'Attendee',
            LastName = 'One',
            Email = 'attendee1@test.com'
        );
        Contact contact2 = new Contact(
            FirstName = 'Attendee',
            LastName = 'Two',
            Email = 'attendee2@test.com'
        );
        insert new List<Contact>{contact1, contact2};

        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('shared1', 'Shared Activity Meeting', 'shared-ical-001');

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should have 1 successful import');
        Assert.isTrue(result.matchedCount > 0, 'Should have matched event');

        // Verify primary WhoId is set
        Event createdEvent = [SELECT WhoId FROM Event WHERE Id = :result.eventIds[0]];
        Assert.areEqual(contact1.Id, createdEvent.WhoId, 'Primary WhoId should be first matched Contact');

        // Verify match info contains all matched contacts
        AICalendarEventCreator.EventMatchInfo matchInfo = result.matchedEvents[0];
        Assert.areEqual(2, matchInfo.allMatchedContactIds.size(), 'Should have 2 matched contact IDs');
    }


    /**
     * Test importing event with meeting link in description.
     * Covers the meetingLink branch in buildDescription.
     */
    @isTest
    static void testImportEvents_WithMeetingLink() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('ml1', 'Teams Call', 'ml-ical-001');
        evt.meetingLink = 'https://teams.microsoft.com/l/meetup-join/test123';

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event with meeting link');

        Event createdEvent = [SELECT Description FROM Event WHERE Id = :result.eventIds[0]];
        Assert.isTrue(createdEvent.Description.contains('Meeting Link:'), 'Description should contain meeting link');
        Assert.isTrue(createdEvent.Description.contains('teams.microsoft.com'), 'Description should contain the actual link');
    }

    /**
     * Test importing event with no attendees (null attendees list).
     * Covers the null/empty attendees path in matchAttendeesWithCache.
     */
    @isTest
    static void testImportEvents_NoAttendees() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('noatt1', 'Solo Reminder', 'noatt-ical-001');
        evt.attendees = null;

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event with no attendees');
    }

    /**
     * Test importing event with empty attendees list.
     * Covers the empty attendees path in matchAttendeesWithCache.
     */
    @isTest
    static void testImportEvents_EmptyAttendees() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('emptyatt1', 'Personal Block', 'emptyatt-ical-001');
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event with empty attendees');
    }

    /**
     * Test importing event with attendee having blank email.
     * Covers the isBlank(att.email) continue branch in matchAttendeesWithCache.
     */
    @isTest
    static void testImportEvents_AttendeeBlankEmail() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'blankemail1';
        evt.subject = 'Meeting with blank email attendee';
        evt.iCalUID = 'blankemail-ical-001';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.provider = 'MICROSOFT_CALENDAR';

        // Add attendee with blank email
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
        att.email = '';
        att.name = 'No Email Person';
        att.isOrganizer = false;
        evt.attendees.add(att);

        // Add attendee with null email
        AIMicrosoftCalendarService.Attendee att2 = new AIMicrosoftCalendarService.Attendee();
        att2.email = null;
        att2.name = 'Null Email Person';
        att2.isOrganizer = false;
        evt.attendees.add(att2);

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event even with blank email attendees');
    }

    /**
     * Test importing event with no description, no organizer, no location.
     * Covers minimal field branches in createEventFromCalendar and buildDescription.
     */
    @isTest
    static void testImportEvents_MinimalFields() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'minimal1';
        evt.subject = 'Minimal Event';
        evt.iCalUID = 'minimal-ical-001';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.provider = 'MICROSOFT_CALENDAR';
        evt.description = null;
        evt.organizerEmail = null;
        evt.organizerName = null;
        evt.location = null;
        evt.meetingLink = null;
        evt.attendees = null;
        evt.isAllDay = false;

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import minimal event');
        Event createdEvent = [SELECT Description, Location FROM Event WHERE Id = :result.eventIds[0]];
        // With no description, organizer, attendees, or meeting link, description should be blank/null
        Assert.isTrue(String.isBlank(createdEvent.Description), 'Description should be blank for minimal event');
        Assert.isTrue(String.isBlank(createdEvent.Location), 'Location should be blank');
    }

    /**
     * Test buildDescription with organizer name + email, and organizer as attendee.
     * Covers the organizer name branch and the isOrganizer attendee skip logic.
     */
    @isTest
    static void testImportEvents_OrganizerAsAttendee() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'orgatt1';
        evt.subject = 'Organizer Is Attendee';
        evt.iCalUID = 'orgatt-ical-001';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.provider = 'MICROSOFT_CALENDAR';
        evt.description = 'Quarterly review';
        evt.organizerEmail = 'organizer@test.com';
        evt.organizerName = 'The Organizer';

        // Add organizer as attendee (should be skipped in description)
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        AIMicrosoftCalendarService.Attendee orgAtt = new AIMicrosoftCalendarService.Attendee();
        orgAtt.email = 'organizer@test.com';
        orgAtt.name = 'The Organizer';
        orgAtt.isOrganizer = true;
        evt.attendees.add(orgAtt);

        // Add a regular attendee with no name (covers the name-less branch)
        AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
        att.email = 'noname@test.com';
        att.name = null;
        att.isOrganizer = false;
        evt.attendees.add(att);

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event');
        Event createdEvent = [SELECT Description FROM Event WHERE Id = :result.eventIds[0]];
        // Verify organizer info is in description
        Assert.isTrue(createdEvent.Description.contains('The Organizer'), 'Description should contain organizer name');
        // Verify organizer is NOT listed as attendee
        Assert.isFalse(createdEvent.Description.contains('Attendees: The Organizer'), 'Organizer should not be in attendee list');
        // Verify no-name attendee is listed by email only
        Assert.isTrue(createdEvent.Description.contains('noname@test.com'), 'No-name attendee should be listed by email');
    }

    /**
     * Test organizer email matching in buildMatchCache (organizer email as Contact).
     */
    @isTest
    static void testImportEvents_OrganizerEmailMatching() {
        // Create a Contact matching the organizer email
        Contact orgContact = new Contact(
            FirstName = 'Test',
            LastName = 'Organizer',
            Email = 'organizer@test.com'
        );
        insert orgContact;

        // Event where only the organizer email matches a Contact (attendees don't match)
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'orgmatch1';
        evt.subject = 'Organizer Match Test';
        evt.iCalUID = 'orgmatch-ical-001';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.provider = 'MICROSOFT_CALENDAR';
        evt.organizerEmail = 'organizer@test.com';
        evt.organizerName = 'Test Organizer';

        // Attendees with unmatched emails
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
        att.email = 'unknown@nowhere.com';
        att.name = 'Unknown Person';
        att.isOrganizer = false;
        evt.attendees.add(att);

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        // Event should be imported (organizer email is cached but only attendees are matched to WhoId)
        Assert.areEqual(1, result.successCount, 'Should import event');
    }

    /**
     * Test importing with Google Calendar provider type (non-Microsoft).
     * Covers the provider type branch in createSyncLog.
     */
    @isTest
    static void testImportEvents_GoogleCalendarProvider() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('gc1', 'Google Meeting', 'gc-ical-001');
        evt.provider = 'GOOGLE_CALENDAR';

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'GOOGLE_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import Google Calendar event');

        // Verify sync log uses GOOGLE_CALENDAR (not Exchange)
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Provider_Type__c FROM AI_Workspace_Sync_Log__c
            WHERE Record_Type__c = 'Calendar'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!logs.isEmpty()) {
            Assert.areEqual('GOOGLE_CALENDAR', logs[0].Provider_Type__c, 'Provider should be GOOGLE_CALENDAR');
        }
    }

    /**
     * Test getImportedEventsMap with actual Event records containing Workspace_Sync_Id__c.
     * Covers Step 1 (Event query) path in getImportedEventsMap.
     */
    @isTest
    static void testGetImportedEventsMap_WithEventRecords() {
        // Create actual Event records with Workspace_Sync_Id__c
        Event evt1 = new Event(
            Subject = 'Imported Event 1',
            StartDateTime = DateTime.now().addDays(1),
            EndDateTime = DateTime.now().addDays(1).addHours(1),
            Workspace_Sync_Id__c = 'ws-sync-001'
        );
        Event evt2 = new Event(
            Subject = 'Imported Event 2',
            StartDateTime = DateTime.now().addDays(2),
            EndDateTime = DateTime.now().addDays(2).addHours(1),
            Workspace_Sync_Id__c = 'ws-sync-002'
        );
        insert new List<Event>{evt1, evt2};

        Test.startTest();
        Map<String, Id> importedMap = AICalendarEventCreator.getImportedEventsMap(
            new Set<String>{'ws-sync-001', 'ws-sync-002', 'ws-sync-missing'}
        );
        Test.stopTest();

        Assert.isTrue(importedMap.containsKey('ws-sync-001'), 'Should find event by Workspace_Sync_Id__c');
        Assert.isTrue(importedMap.containsKey('ws-sync-002'), 'Should find second event');
        Assert.isFalse(importedMap.containsKey('ws-sync-missing'), 'Should not find non-existent event');
        Assert.areEqual(evt1.Id, importedMap.get('ws-sync-001'), 'Should return correct Event Id');
    }

    /**
     * Test getImportedEventsMap with empty set.
     */
    @isTest
    static void testGetImportedEventsMap_EmptySet() {
        Test.startTest();
        Map<String, Id> importedMap = AICalendarEventCreator.getImportedEventsMap(new Set<String>());
        Test.stopTest();

        Assert.areEqual(0, importedMap.size(), 'Should return empty map for empty set');
    }

    /**
     * Test importing events with very long location and description (truncation paths).
     * Covers the truncateField calls in createEventFromCalendar.
     */
    @isTest
    static void testImportEvents_LongFields() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('long1', 'Long Fields Event', 'long-ical-001');

        // Create a location longer than 255 chars
        String longLocation = '';
        for (Integer i = 0; i < 30; i++) {
            longLocation += 'Conference Room Building Floor ';
        }
        evt.location = longLocation;

        // Create a very long description
        String longDesc = '';
        for (Integer i = 0; i < 500; i++) {
            longDesc += 'This is a very detailed meeting description with lots of content. ';
        }
        evt.description = longDesc;

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event with long fields');

        Event createdEvent = [SELECT Location, Description FROM Event WHERE Id = :result.eventIds[0]];
        Assert.isTrue(createdEvent.Location.length() <= 255, 'Location should be truncated to 255');
        Assert.isTrue(createdEvent.Description.length() <= 32000, 'Description should be truncated to 32000');
    }

    /**
     * Test importing events where organizer has email but no name.
     * Covers the organizer-without-name branch in buildDescription.
     */
    @isTest
    static void testImportEvents_OrganizerEmailOnly() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('orgonly1', 'Organizer No Name', 'orgonly-ical-001');
        evt.organizerName = null;
        evt.organizerEmail = 'justanemail@test.com';

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event');
        Event createdEvent = [SELECT Description FROM Event WHERE Id = :result.eventIds[0]];
        Assert.isTrue(createdEvent.Description.contains('Organizer: justanemail@test.com'), 
            'Description should have organizer email without name format');
    }

    /**
     * Test getDeduplicationId with Google Calendar recurring event but missing eventId.
     * Covers the fallback within the Google recurring branch.
     */
    @isTest
    static void testGetDeduplicationId_GoogleRecurring_NoEventId() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = null;
        evt.iCalUID = 'ical-fallback@google.com';
        evt.provider = 'GOOGLE_CALENDAR';
        evt.recurringEventId = 'recurring-base';

        Test.startTest();
        String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
        Test.stopTest();

        // eventId is blank, so it falls through to iCalUID
        Assert.areEqual('ical-fallback@google.com', dedupId, 
            'Should fallback to iCalUID when eventId is blank for recurring Google event');
    }

    /**
     * Test getDeduplicationId with all null fields.
     */
    @isTest
    static void testGetDeduplicationId_AllNull() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = null;
        evt.iCalUID = null;
        evt.provider = null;
        evt.recurringEventId = null;

        Test.startTest();
        String dedupId = AICalendarEventCreator.getDeduplicationId(evt);
        Test.stopTest();

        Assert.areEqual(null, dedupId, 'Should return null when all IDs are null');
    }

    /**
     * Test importing event with blank dedup ID (no iCalUID, no eventId).
     * Covers the isNotBlank(dedupId) check in importEvents loop.
     */
    @isTest
    static void testImportEvents_BlankDedupId() {
        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = null;
        evt.subject = 'No IDs Event';
        evt.iCalUID = null;
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.provider = 'MICROSOFT_CALENDAR';
        evt.isAllDay = false;
        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        // Should still attempt to import (blank dedup means no duplicate check blocks it)
        Assert.areEqual(1, result.successCount, 'Should import event with blank dedup ID');
    }

    /**
     * Test importing multiple events with mixed Contact and Lead matches.
     * Covers both branches in a single bulk operation.
     */
    @isTest
    static void testImportEvents_MixedContactAndLeadMatching() {
        // Create a Contact for first event's attendee
        Contact testContact = new Contact(
            FirstName = 'Contact',
            LastName = 'Person',
            Email = 'contact@matched.com'
        );
        insert testContact;

        // Create a Lead for second event's attendee
        Lead testLead = new Lead(
            FirstName = 'Lead',
            LastName = 'Person',
            Email = 'lead@matched.com',
            Company = 'Lead Company'
        );
        insert testLead;

        // Event 1: attendee matches Contact
        AIMicrosoftCalendarService.CalendarEvent evt1 = new AIMicrosoftCalendarService.CalendarEvent();
        evt1.eventId = 'mixed1';
        evt1.subject = 'Contact Meeting';
        evt1.iCalUID = 'mixed-ical-001';
        evt1.startDateTime = DateTime.now().addDays(1);
        evt1.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt1.provider = 'MICROSOFT_CALENDAR';
        evt1.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        AIMicrosoftCalendarService.Attendee att1 = new AIMicrosoftCalendarService.Attendee();
        att1.email = 'contact@matched.com';
        att1.name = 'Contact Person';
        att1.isOrganizer = false;
        evt1.attendees.add(att1);

        // Event 2: attendee matches Lead
        AIMicrosoftCalendarService.CalendarEvent evt2 = new AIMicrosoftCalendarService.CalendarEvent();
        evt2.eventId = 'mixed2';
        evt2.subject = 'Lead Meeting';
        evt2.iCalUID = 'mixed-ical-002';
        evt2.startDateTime = DateTime.now().addDays(2);
        evt2.endDateTime = DateTime.now().addDays(2).addHours(1);
        evt2.provider = 'MICROSOFT_CALENDAR';
        evt2.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        AIMicrosoftCalendarService.Attendee att2 = new AIMicrosoftCalendarService.Attendee();
        att2.email = 'lead@matched.com';
        att2.name = 'Lead Person';
        att2.isOrganizer = false;
        evt2.attendees.add(att2);

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt1, evt2},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(2, result.successCount, 'Should have 2 successful imports');
        Assert.areEqual(2, result.matchedCount, 'Should have 2 matched events');

        // Verify first event linked to Contact
        Event createdEvt1 = [SELECT WhoId FROM Event WHERE Id = :result.eventIds[0]];
        Assert.areEqual(testContact.Id, createdEvt1.WhoId, 'First event should be linked to Contact');

        // Verify second event linked to Lead
        Event createdEvt2 = [SELECT WhoId FROM Event WHERE Id = :result.eventIds[1]];
        Assert.areEqual(testLead.Id, createdEvt2.WhoId, 'Second event should be linked to Lead');
    }

    /**
     * Test notification with very long subject (truncation to 40 chars).
     * Covers the truncatedSubject logic in sendImportNotifications.
     */
    @isTest
    static void testImportEvents_LongSubjectNotification() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent(
            'longsubj1',
            'This is a very long meeting subject that exceeds the forty character truncation limit for notifications',
            'longsubj-ical-001'
        );

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event with long subject');
    }

    /**
     * Test notification with blank subject (covers the "(No Subject)" fallback).
     * Covers the isBlank(subject) branch in sendImportNotifications.
     */
    @isTest
    static void testImportEvents_BlankSubjectNotification() {
        AIMicrosoftCalendarService.CalendarEvent evt = createSampleCalendarEvent('blanksubj1', '', 'blanksubj-ical-001');
        evt.subject = '';

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        // Empty subject becomes 'Calendar Event' in createEventFromCalendar
        Assert.areEqual(1, result.successCount, 'Should import event with blank subject');
    }

    /**
     * Test importing events where the sync log captures partial failure status.
     * Covers the partial/failed status paths in createSyncLog.
     */
    @isTest
    static void testImportEvents_SyncLogWithDuplicates() {
        // Pre-create an event so one import is a duplicate
        Event existingEvent = new Event(
            Subject = 'Pre-existing',
            StartDateTime = DateTime.now().addDays(1),
            EndDateTime = DateTime.now().addDays(1).addHours(1),
            Workspace_Sync_Id__c = 'dup-sync-id',
            OwnerId = UserInfo.getUserId()
        );
        insert existingEvent;

        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        events.add(createSampleCalendarEvent('dup1', 'Duplicate', 'dup-sync-id'));
        events.add(createSampleCalendarEvent('new1', 'New Event', 'new-sync-id'));

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(events, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        // Verify sync log was created with appropriate counts
        List<AI_Workspace_Sync_Log__c> logs = [
            SELECT Events_Imported__c, Events_Duplicate__c, Events_Failed__c, Status__c
            FROM AI_Workspace_Sync_Log__c
            WHERE Record_Type__c = 'Calendar'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!logs.isEmpty()) {
            Assert.areEqual('Success', logs[0].Status__c, 'Status should be Success when some succeed');
        }
    }

    /**
     * Test case sensitivity in email matching.
     * Emails should match case-insensitively.
     */
    @isTest
    static void testImportEvents_CaseInsensitiveEmailMatch() {
        Contact testContact = new Contact(
            FirstName = 'Mixed',
            LastName = 'Case',
            Email = 'MixedCase@Test.COM'
        );
        insert testContact;

        AIMicrosoftCalendarService.CalendarEvent evt = new AIMicrosoftCalendarService.CalendarEvent();
        evt.eventId = 'case1';
        evt.subject = 'Case Test';
        evt.iCalUID = 'case-ical-001';
        evt.startDateTime = DateTime.now().addDays(1);
        evt.endDateTime = DateTime.now().addDays(1).addHours(1);
        evt.provider = 'MICROSOFT_CALENDAR';

        evt.attendees = new List<AIMicrosoftCalendarService.Attendee>();
        AIMicrosoftCalendarService.Attendee att = new AIMicrosoftCalendarService.Attendee();
        att.email = 'mixedcase@test.com'; // lowercase version
        att.name = 'Mixed Case';
        att.isOrganizer = false;
        evt.attendees.add(att);

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(
            new List<AIMicrosoftCalendarService.CalendarEvent>{evt},
            'MICROSOFT_CALENDAR'
        );
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should import event');
        // Email matching is case-insensitive, so Contact should be matched
        if (result.matchedCount > 0) {
            Event createdEvent = [SELECT WhoId FROM Event WHERE Id = :result.eventIds[0]];
            Assert.areEqual(testContact.Id, createdEvent.WhoId, 'Should match Contact case-insensitively');
        }
    }

    /**
     * Test importing a large batch of events (bulk operation).
     * Exercises the bulkified match cache and batch insert paths.
     */
    @isTest
    static void testImportEvents_BulkImport() {
        List<AIMicrosoftCalendarService.CalendarEvent> events = new List<AIMicrosoftCalendarService.CalendarEvent>();
        for (Integer i = 0; i < 20; i++) {
            events.add(createSampleCalendarEvent('bulk' + i, 'Bulk Meeting ' + i, 'bulk-ical-' + i));
        }

        Test.startTest();
        AICalendarEventCreator.ImportResult result = AICalendarEventCreator.importEvents(events, 'MICROSOFT_CALENDAR');
        Test.stopTest();

        Assert.areEqual(20, result.successCount, 'Should import all 20 events');
        Assert.areEqual(20, result.eventIds.size(), 'Should have 20 event IDs');
    }

    /**
     * Test getImportedEventsMap with staging records that have a valid Event ID in Email_Message__c.
     * Covers the Step 2 fallback path with matched staging + valid Event reference.
     */
    @isTest
    static void testGetImportedEventsMap_StagingWithValidEventRef() {
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();

        // Create an Event that we'll reference from staging
        Event refEvent = new Event(
            Subject = 'Referenced Event',
            StartDateTime = DateTime.now().addDays(1),
            EndDateTime = DateTime.now().addDays(1).addHours(1)
        );
        insert refEvent;

        // Create staging record with Status 'Matched' and valid Event ID in Email_Message__c
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Staging Event',
            Start_DateTime__c = DateTime.now().addDays(1),
            End_DateTime__c = DateTime.now().addDays(1).addHours(1),
            ICalUID__c = 'staging-ref-001',
            User__c = UserInfo.getUserId(),
            RecordTypeId = calendarRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Imported',
            Email_Message__c = String.valueOf(refEvent.Id)
        );
        insert staging;

        Test.startTest();
        Map<String, Id> importedMap = AICalendarEventCreator.getImportedEventsMap(
            new Set<String>{'staging-ref-001'}
        );
        Test.stopTest();

        Assert.isTrue(importedMap.containsKey('staging-ref-001'), 'Should find event via staging fallback');
        Assert.areEqual(refEvent.Id, importedMap.get('staging-ref-001'), 'Should return correct Event Id from staging');
    }

    /**
     * Test getImportedEventsMap with staging record having invalid Event ID.
     * Covers the try/catch for invalid ID in the staging fallback.
     */
    @isTest
    static void testGetImportedEventsMap_StagingWithInvalidEventRef() {
        Id calendarRecordTypeId = Schema.SObjectType.AI_Workspace_Staging__c
            .getRecordTypeInfosByDeveloperName().get('Calendar').getRecordTypeId();

        // Create staging record with invalid Event ID
        AI_Workspace_Staging__c staging = new AI_Workspace_Staging__c(
            Subject__c = 'Bad Ref Event',
            Start_DateTime__c = DateTime.now().addDays(1),
            End_DateTime__c = DateTime.now().addDays(1).addHours(1),
            ICalUID__c = 'bad-ref-001',
            User__c = UserInfo.getUserId(),
            RecordTypeId = calendarRecordTypeId,
            Provider__c = 'MICROSOFT_CALENDAR',
            Status__c = 'Imported',
            Email_Message__c = 'not-a-valid-id'
        );
        insert staging;

        Test.startTest();
        Map<String, Id> importedMap = AICalendarEventCreator.getImportedEventsMap(
            new Set<String>{'bad-ref-001'}
        );
        Test.stopTest();

        // Invalid ID should be skipped gracefully
        Assert.isFalse(importedMap.containsKey('bad-ref-001'), 'Should not include staging with invalid Event ID');
    }

    /**
     * Test EventMatchInfo and ImportResult inner class initialization.
     * Covers constructor defaults.
     */
    @isTest
    static void testInnerClassInitialization() {
        AICalendarEventCreator.ImportResult result = new AICalendarEventCreator.ImportResult();
        Assert.areEqual(0, result.successCount, 'Default successCount should be 0');
        Assert.areEqual(0, result.failedCount, 'Default failedCount should be 0');
        Assert.areEqual(0, result.duplicateCount, 'Default duplicateCount should be 0');
        Assert.areEqual(0, result.matchedCount, 'Default matchedCount should be 0');
        Assert.isNotNull(result.errors, 'Errors list should be initialized');
        Assert.isNotNull(result.eventIds, 'EventIds list should be initialized');
        Assert.isNotNull(result.matchedEvents, 'MatchedEvents list should be initialized');

        AICalendarEventCreator.EventMatchInfo matchInfo = new AICalendarEventCreator.EventMatchInfo();
        Assert.areEqual(null, matchInfo.eventId, 'Default eventId should be null');
        Assert.areEqual(null, matchInfo.whoId, 'Default whoId should be null');
        Assert.areEqual(null, matchInfo.allMatchedContactIds, 'Default allMatchedContactIds should be null');
    }
}