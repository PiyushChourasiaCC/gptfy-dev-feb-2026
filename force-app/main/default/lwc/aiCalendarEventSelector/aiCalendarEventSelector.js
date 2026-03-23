import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getCalendarEventsByRange from '@salesforce/apex/AICalendarSyncController.getCalendarEventsByRange';
import importCalendarEvents from '@salesforce/apex/AICalendarSyncController.importCalendarEvents';
import checkCalendarAccess from '@salesforce/apex/AICalendarSyncController.checkCalendarAccess';
import refreshTokenAndCheckAccess from '@salesforce/apex/AICalendarSyncController.refreshTokenAndCheckAccess';
import getProviderSettings from '@salesforce/apex/AISyncSettingsService.getProviderSettings';
import checkCalendarSyncPermissions from '@salesforce/apex/AIWorkspacePermissionService.checkCalendarSyncPermissions';
import gptfyLogo from '@salesforce/resourceUrl/gptfylogo';

export default class aiCalendarEventSelector extends NavigationMixin(LightningElement) {
    @api recordId;
    @api selectedProvider = 'MICROSOFT_CALENDAR'; // Provider passed from parent

    @track events = [];
    @track isLoading = true;
    @track isImporting = false;
    @track isCalendarAccessible = false;
    @track calendarEmail = '';
    @track selectedRange = 'thisWeek';
    @track namespace = ''; // Package namespace for navigation URLs
    
    // Provider settings from org configuration
    @track providerSettings = {
        outlookEnabled: false,
        gmailEnabled: false,
        bothEnabled: false,
        neitherEnabled: true,
        singleProvider: null
    };
    
    // Pagination - tracked for reactive UI updates
    @track currentPage = 1;
    @track pageSize = 50;
    @track totalEvents = 0;
    @track hasMoreEvents = false;
    @track nextPageToken = null;
    @track cumulativeEventCount = 0;
    
    // Search state
    searchKey = '';
    debounceTimeout;
    
    // Persistent selection tracking across pages
    selectedEventIds = new Set();

    // Modal state
    @track showQuickMatchModal = false;
    @track modalItems = [];

    // Avatar gradient colors
    gradients = [
        'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
        'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        'linear-gradient(135deg, #fa709a 0%, #fee140 100%)',
        'linear-gradient(135deg, #30cfd0 0%, #330867 100%)',
        'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
        'linear-gradient(135deg, #a8edea 0%, #fed6e3 100%)',
        'linear-gradient(135deg, #ff9a9e 0%, #fecfef 100%)',
        'linear-gradient(135deg, #ffecd2 0%, #fcb69f 100%)'
    ];

    connectedCallback() {
        this.loadProviderSettings();
    }
    
    /**
     * Load provider settings from org configuration
     */
    loadProviderSettings() {
        getProviderSettings()
            .then(settings => {
                this.providerSettings = settings;

                // Note: selectedProvider comes from parent via @api, so don't override
                // The parent component is responsible for determining the correct provider

                this.checkAccess();
            })
            .catch(error => {
                console.error('Error loading provider settings:', error);
                this.checkAccess();
            });
    }

    async checkAccess() {
        this.isLoading = true;
        try {
            // First, try to refresh the token (this ensures fresh token before any API calls)
            const refreshResult = await refreshTokenAndCheckAccess({ provider: this.selectedProvider });
            
            if (refreshResult.refreshed && refreshResult.isAccessible) {
                // Token refreshed successfully - use these details
                this.isCalendarAccessible = true;
                this.namespace = refreshResult.namespace || '';

                // Note: Don't override selectedProvider - parent component controls this

                // If ownerEmail is empty (due to callout-after-DML prevention), fetch it separately
                if (refreshResult.ownerEmail) {
                    this.calendarEmail = refreshResult.ownerEmail;
                } else {
                    // Fetch calendar info in a separate call (after DML transaction is committed)
                    this.fetchCalendarEmail();
                }

                await this.loadEvents();
            } else {
                // Token refresh failed or no access - fall back to regular access check
                const result = await checkCalendarAccess({ provider: this.selectedProvider });
                this.isCalendarAccessible = result.isAccessible;
                this.calendarEmail = result.ownerEmail || '';
                this.namespace = result.namespace || '';

                // Note: Don't override selectedProvider - parent component controls this

                if (this.isCalendarAccessible) {
                    await this.loadEvents();
                }
            }
        } catch (error) {
            this.isCalendarAccessible = false;
            // Note: Don't override selectedProvider - parent component controls this
        } finally {
            this.isLoading = false;
        }
    }

    handleProviderSwitch(event) {
        const provider = event.currentTarget.dataset.provider;
        if (provider && provider !== this.selectedProvider) {
            this.selectedProvider = provider;
            this.events = [];
            this.resetPagination();
            this.checkAccess();
        }
    }

    /**
     * Handle retry connection button click
     * Refreshes token and checks access without navigating away
     */
    handleRetryConnection() {
        this.isLoading = true;
        this.isCalendarAccessible = false;
        // Small delay to ensure UI updates before API call
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.checkAccess();
        }, 100);
    }

    /**
     * Handle connect button click - dispatch event to parent to open settings modal
     */
    handleConnectClick() {
        const event = new CustomEvent('opensettings');
        this.dispatchEvent(event);
    }

    /**
     * Fetch calendar email address separately (called after token refresh to avoid callout-after-DML)
     */
    async fetchCalendarEmail() {
        try {
            const result = await checkCalendarAccess({ provider: this.selectedProvider });
            if (result.isAccessible && result.ownerEmail) {
                this.calendarEmail = result.ownerEmail;
            }
        } catch (error) {
            console.error('Error fetching calendar email:', error);
            // Not critical - display will fallback to provider name
        }
    }

    async loadEvents() {
        this.isLoading = true;
        try {
            // Get page token for current page (offset-based)
            const pageToken = this.currentPage > 1 ? String((this.currentPage - 1) * this.pageSize) : null;
            
            const response = await getCalendarEventsByRange({
                rangeType: this.selectedRange,
                provider: this.selectedProvider,
                searchTerm: this.searchKey,
                pageToken: pageToken,
                pageSize: this.pageSize
            });

            if (response.error) {
                this.showToastMessage(response.error, 'error');
                this.events = [];
                return;
            }

            // Format events and restore selection state from persistent Set
            this.events = (response.events || []).map(evt => {
                const formatted = this.formatEvent(evt, response.importedEvents);
                // Restore selection if this event was previously selected
                formatted.selected = this.selectedEventIds.has(evt.eventId || evt.iCalUID);
                return formatted;
            });
            
            // Update pagination state
            this.hasMoreEvents = response.hasMore || false;
            this.nextPageToken = response.nextPageToken;
            
            // Update cumulative count for display
            const currentPageEventCount = this.events.length;
            this.cumulativeEventCount = (this.currentPage - 1) * this.pageSize + currentPageEventCount;
            
            // totalEvents = what we know so far (cumulative)
            // The getter totalEventsDisplay will add "+" if there are more
            this.totalEvents = this.cumulativeEventCount;
            
            // Load total imported count from database
        } catch (error) {
            this.showToastMessage('Failed to load calendar events: ' + this.getErrorMessage(error), 'error');
            this.events = [];
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * Reset all pagination state to initial values
     */
    resetPagination() {
        this.currentPage = 1;
        this.totalEvents = 0;
        this.hasMoreEvents = false;
        this.nextPageToken = null;
        this.cumulativeEventCount = 0;
        // Clear selections when changing provider/range
        this.selectedEventIds.clear();
    }
    
    /**
     * Load total imported event count from database (filtered by current provider)
     * This queries the total count of Event records for the current provider
     */

    formatEvent(evt, importedMap) {
        // For Google Calendar recurring events, use eventId for lookup (matches backend deduplication)
        // For non-recurring or Microsoft events, use iCalUID
        const lookupKey = (evt.provider === 'GOOGLE_CALENDAR' && evt.recurringEventId) ? evt.eventId : evt.iCalUID;
        const isImported = evt.isImported || (importedMap && importedMap[lookupKey]);

        // Build linked badge label and class if there's a linked record (for backwards compatibility)
        const allowedTypes = ['contact', 'lead', 'user'];
        let linkedBadgeLabel = null;
        let linkedBadgeClass = 'badge linked';
        const recordType = (evt.linkedRecordType || '').toLowerCase();
        
        if (evt.linkedRecordName && allowedTypes.includes(recordType)) {
            linkedBadgeLabel = evt.linkedRecordName;
            if (recordType === 'contact') {
                linkedBadgeClass = 'badge linked-contact';
            } else if (recordType === 'lead') {
                linkedBadgeClass = 'badge linked-lead';
            } else if (recordType === 'user') {
                linkedBadgeClass = 'badge linked-user';
            }
        }
        
        // Process multiple linked records for multiple pills display
        let linkedRecordsFormatted = [];
        if (evt.linkedRecords && evt.linkedRecords.length > 0) {
            linkedRecordsFormatted = evt.linkedRecords.map((lr, index) => {
                const type = (lr.recordType || '').toLowerCase();
                let badgeClass = 'badge linked';
                if (type === 'contact') {
                    badgeClass = 'badge linked-contact';
                } else if (type === 'lead') {
                    badgeClass = 'badge linked-lead';
                } else if (type === 'user') {
                    badgeClass = 'badge linked-user';
                } else if (type === 'account') {
                    badgeClass = 'badge linked-account';
                } else if (type === 'opportunity') {
                    badgeClass = 'badge linked-opportunity';
                }
                return {
                    key: lr.recordId + '-' + index,
                    recordId: lr.recordId,
                    recordName: lr.recordName,
                    recordType: lr.recordType,
                    badgeClass: badgeClass
                };
            });
        }

        // Generate initials and avatar
        const initials = this.getInitials(evt.subject);
        const avatarStyle = `background: ${this.getAvatarGradient(evt.subject)}`;

        // Build row class
        let rowClass = 'event-row';
        if (isImported) rowClass += ' imported';
        if (evt.isAllDay) rowClass += ' allday';

        return {
            ...evt,
            selected: false,
            isImported: isImported,
            formattedTime: this.formatEventTime(evt),
            hasAttendees: evt.attendees && evt.attendees.length > 0,
            attendeeCount: evt.attendees ? evt.attendees.length : 0,
            attendeeEmails: this.formatAttendeeEmails(evt.attendees),
            linkedBadgeLabel: linkedBadgeLabel,
            linkedBadgeClass: linkedBadgeClass,
            linkedRecordId: evt.linkedRecordId,
            linkedRecordType: evt.linkedRecordType,
            linkedRecordsFormatted: linkedRecordsFormatted,
            hasMultipleLinkedRecords: linkedRecordsFormatted.length > 0,
            initials: initials,
            avatarStyle: avatarStyle,
            rowClass: rowClass
        };
    }

    getInitials(subject) {
        if (!subject) return '📅';
        // NO REGEX - simple split by space and filter empty
        const words = subject.trim().split(' ').filter(w => w.length > 0);
        if (words.length >= 2) {
            return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
        }
        return subject.substring(0, 2).toUpperCase();
    }

    getAvatarGradient(subject) {
        let hash = 0;
        for (let i = 0; i < (subject || '').length; i++) {
            hash = subject.charCodeAt(i) + ((hash << 5) - hash);
        }
        return this.gradients[Math.abs(hash) % this.gradients.length];
    }

    formatEventTime(evt) {
        if (!evt.startDateTime) return '';

        const start = new Date(evt.startDateTime);
        const end = evt.endDateTime ? new Date(evt.endDateTime) : null;

        const options = {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            hour: evt.isAllDay ? undefined : 'numeric',
            minute: evt.isAllDay ? undefined : '2-digit'
        };

        let timeStr = start.toLocaleDateString('en-US', options);

        if (end && !evt.isAllDay) {
            timeStr += ' - ' + end.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        }

        return timeStr;
    }

    formatAttendeeEmails(attendees) {
        if (!attendees || attendees.length === 0) return '';

        const emails = attendees
            .filter(att => !att.isOrganizer)
            .slice(0, 3)
            .map(att => att.email);

        let result = emails.join(', ');
        if (attendees.length > 3) {
            result += ` +${attendees.length - 3} more`;
        }

        return result;
    }

    handleRangeChange(event) {
        this.selectedRange = event.currentTarget.dataset.range;
        this.resetPagination();
        this.loadEvents();
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
        
        clearTimeout(this.debounceTimeout);
        this.debounceTimeout = setTimeout(() => {
            this.resetPagination();
            this.loadEvents();
        }, 500);
    }

    handleRefresh() {
        this.resetPagination();
        if (this.isCalendarAccessible) {
            this.loadEvents();
        } else {
            this.checkAccess();
        }
    }
    
    /**
     * Handle previous page
     */
    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.loadEvents();
        }
    }

    /**
     * Handle next page
     */
    handleNextPage() {
        if (!this.isLastPage) {
            this.currentPage++;
            this.loadEvents();
        }
    }
    
    /**
     * Get the starting event number for the current page (1-indexed)
     */
    get pageStart() {
        if (this.events.length === 0) return 0;
        return (this.currentPage - 1) * this.pageSize + 1;
    }

    /**
     * Get the ending event number for the current page
     */
    get pageEnd() {
        if (this.events.length === 0) return 0;
        return this.pageStart + this.events.length - 1;
    }

    /**
     * Check if we're on the first page
     */
    get isFirstPage() {
        return this.currentPage === 1;
    }

    /**
     * Check if we're on the last page
     */
    get isLastPage() {
        // No events loaded means we're at the last page
        if (this.events.length === 0) return true;

        // If we have fewer events than page size, it's definitely the last page
        if (this.events.length < this.pageSize) return true;

        // If hasMoreEvents is false, this is the last page
        if (!this.hasMoreEvents) return true;

        return false;
    }

    /**
     * Get the count of events on the current page
     */
    get currentPageEventCount() {
        return this.events ? this.events.length : 0;
    }

    /**
     * Get display text for total events (with "+" for estimates)
     */
    get totalEventsDisplay() {
        if (this.hasMoreEvents) {
            return this.cumulativeEventCount + '+';
        }
        return this.cumulativeEventCount;
    }

    /**
     * Check if Previous button should be disabled
     */
    get isPreviousDisabled() {
        return this.isFirstPage;
    }

    /**
     * Check if Next button should be disabled
     * Disabled when on last page OR when there are fewer events than page size
     */
    get isNextDisabled() {
        // Disable if on last page
        if (this.isLastPage) return true;
        
        // Disable if no more events to fetch and we have fewer than page size
        if (!this.hasMoreEvents && this.events.length < this.pageSize) return true;
        
        return false;
    }

    /**
     * Handle checkbox click directly
     * Stops propagation to prevent double-toggle from row click
     */
    handleCheckboxClick(event) {
        event.stopPropagation();

        const eventId = event.target.dataset.eventId;
        const isChecked = event.target.checked;

        // Don't allow selection of imported events
        if (event.target.disabled) {
            event.target.checked = false;
            return;
        }

        this.updateEventSelection(eventId, isChecked);
    }

    handleRowClick(event) {
        // Don't toggle if clicking checkbox (handled by handleCheckboxClick)
        if (event.target.type === 'checkbox') {
            return;
        }

        // Don't toggle if clicking on meeting link
        if (event.target.tagName === 'A') {
            return;
        }

        const eventId = event.currentTarget.dataset.eventId;
        const checkbox = event.currentTarget.querySelector('input[type="checkbox"]');

        // Don't toggle if already imported
        if (checkbox && checkbox.disabled) {
            return;
        }

        // Toggle checkbox state
        const newCheckedState = !checkbox.checked;
        checkbox.checked = newCheckedState;

        this.updateEventSelection(eventId, newCheckedState);
    }

    /**
     * Common method to update event selection state
     * Maintains persistent selection across pages
     */
    updateEventSelection(eventId, isSelected) {
        // Update persistent selection Set
        if (isSelected) {
            this.selectedEventIds.add(eventId);
        } else {
            this.selectedEventIds.delete(eventId);
        }
        
        // Update current page display
        this.events = this.events.map(evt => {
            if (evt.eventId === eventId) {
                return { ...evt, selected: isSelected };
            }
            return evt;
        });
    }

    handleMeetingLinkClick(event) {
        // Prevent row click from triggering
        event.stopPropagation();
    }

    /**
     * Handle click on linked record badge to navigate to the record
     * Opens the record in a new browser tab
     */
    handleBadgeClick(event) {
        event.stopPropagation(); // Prevent row selection
        
        const recordId = event.currentTarget.dataset.recordId;
        const recordType = event.currentTarget.dataset.recordType;
        
        if (!recordId) {
            return;
        }

        // Open record in new browser tab
        const recordUrl = `/${recordId}`;
        window.open(recordUrl, '_blank');
    }

    handleEventSelect(event) {
        const eventId = event.target.dataset.eventId;
        this.updateEventSelection(eventId, event.target.checked);
    }

    handleClearSelection() {
        // Clear persistent selection Set
        this.selectedEventIds.clear();
        // Clear current page display
        this.events = this.events.map(evt => ({ ...evt, selected: false }));
    }

    handleLogoError(event) {
        // Hide logo if it fails to load
        event.target.style.display = 'none';
    }

    async handleImportSelected() {
        // Use the persistent Set for all selected events across pages
        const eventIds = Array.from(this.selectedEventIds);
        
        if (eventIds.length === 0) {
            this.showToastMessage('No events selected for import', 'warning');
            return;
        }
        
        // Check 20-event limit for manual selection
        const MAX_EVENTS = 20;
        if (eventIds.length > MAX_EVENTS) {
            this.showToastMessage(
                `Please select ${MAX_EVENTS} or fewer events per import. You have ${eventIds.length} selected. You can run multiple imports if needed.`,
                'warning'
            );
            return;
        }
        
        // Check permissions before proceeding
        try {
            const permResult = await checkCalendarSyncPermissions();
            if (!permResult.hasAccess) {
                this.showToastMessage(permResult.errorMessage, 'error');
                return;
            }
        } catch (err) {
            console.error('Error checking permissions:', err);
            // Continue anyway - permission check is informational
        }
        
        // Get the selected events for the modal
        const selectedEvents = this.events.filter(evt => this.selectedEventIds.has(evt.eventId));
        
        // Prepare modal items from selected events
        // The modal expects: id, subject, fromName, bodyPreview, organizerEmail, organizerName, attendees
        this.modalItems = selectedEvents.map(evt => ({
            id: evt.eventId,
            messageId: evt.eventId,
            subject: evt.subject || '(No Subject)',
            fromName: evt.organizerName || evt.organizerEmail || 'Unknown Organizer',
            bodyPreview: evt.location || evt.attendeeEmails || '',
            organizerEmail: evt.organizerEmail,
            organizerName: evt.organizerName,
            attendees: evt.attendees || [], // Pass attendees array for smart matching
            receivedDateTime: evt.startDateTime
        }));
        
        this.showQuickMatchModal = true;
    }

    handleModalSuccess(event) {
        const { count, excludedCount, duplicateCount } = event.detail;
        
        // Build message based on results
        let message = '';
        let variant = 'success';
        
        if (count > 0) {
            // Some events were imported successfully
            message = `${count} event(s) imported successfully! Check the bell icon (🔔) for details.`;
        } else if (excludedCount > 0) {
            // No imports, but some were excluded
            message = `${excludedCount} event(s) excluded by exclusion rules. No events imported.`;
            variant = 'info';
        } else if (duplicateCount > 0) {
            // No imports, but some were duplicates
            message = `${duplicateCount} event(s) already imported (duplicates). No new events imported.`;
            variant = 'info';
        } else {
            // No imports and no exclusions/duplicates
            message = '0 event(s) imported.';
            variant = 'warning';
        }
        
        this.showToastMessage(message, variant);
        this.showQuickMatchModal = false;
        
        // Add delay to ensure database transaction is committed before refreshing
        setTimeout(() => {
            this.loadEvents();
        }, 1000);
        
        this.handleClearSelection();
        this.dispatchEvent(new CustomEvent('eventsimported', {
            detail: { count: count }
        }));
    }

    handleCloseModal() {
        this.showQuickMatchModal = false;
        this.modalItems = [];
    }

    handleModalError(event) {
        // Handle error event from modal
        const errorMessage = event.detail && event.detail.message 
            ? (typeof event.detail.message === 'string' ? event.detail.message : JSON.stringify(event.detail.message))
            : 'Failed to import event(s)';
        
        this.showToastMessage(errorMessage, 'error');
        this.handleCloseModal();
    }

    showToastMessage(message, variant) {
        const titles = {
            success: 'Success',
            error: 'Error',
            warning: 'Warning',
            info: 'Info'
        };
        this.dispatchEvent(new ShowToastEvent({
            title: titles[variant] || 'Info',
            message: message,
            variant: variant
        }));
    }

    getErrorMessage(error) {
        if (typeof error === 'string') return error;
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return 'Unknown error';
    }

    // Getters for computed properties
    get logoUrl() {
        return gptfyLogo;
    }

    get authenticationSettingsUrl() {
        // URL to Workspace Authentication tab with namespace prefix for packaged apps
        return '/lightning/n/' + this.namespace + 'Workspace_Authentication';
    }


    get hasEvents() {
        return this.events && this.events.length > 0;
    }

    get hasSelection() {
        // Check persistent Set for any selections across all pages
        return this.selectedEventIds.size > 0;
    }

    get selectedCount() {
        // Return count from persistent Set (includes selections from all pages)
        return this.selectedEventIds.size;
    }

    // Selection bar class - floating pill animation
    get selectionBarClass() {
        return this.hasSelection ? 'selection-bar active' : 'selection-bar';
    }

    // Loading overlay class
    get loadingOverlayClass() {
        return this.isImporting ? 'loading-overlay active' : 'loading-overlay';
    }

    // Filter button classes
    get past7DaysFilterClass() {
        return this.selectedRange === 'past7Days' ? 'active' : '';
    }

    get thisWeekFilterClass() {
        return this.selectedRange === 'thisWeek' ? 'active' : '';
    }

    get nextWeekFilterClass() {
        return this.selectedRange === 'nextWeek' ? 'active' : '';
    }

    get thisMonthFilterClass() {
        return this.selectedRange === 'thisMonth' ? 'active' : '';
    }

    get allEventsFilterClass() {
        return this.selectedRange === 'allEvents' ? 'active' : '';
    }
    
    // Filter active state for showing counts
    get isPast7DaysFilter() { return this.selectedRange === 'past7Days'; }
    get isThisWeekFilter() { return this.selectedRange === 'thisWeek'; }
    get isNextWeekFilter() { return this.selectedRange === 'nextWeek'; }
    get isThisMonthFilter() { return this.selectedRange === 'thisMonth'; }
    get isAllEventsFilter() { return this.selectedRange === 'allEvents'; }

    // Keep old getters for backwards compatibility
    get past7DaysVariant() {
        return this.selectedRange === 'past7Days' ? 'brand' : 'neutral';
    }

    get thisWeekVariant() {
        return this.selectedRange === 'thisWeek' ? 'brand' : 'neutral';
    }

    get nextWeekVariant() {
        return this.selectedRange === 'nextWeek' ? 'brand' : 'neutral';
    }

    get thisMonthVariant() {
        return this.selectedRange === 'thisMonth' ? 'brand' : 'neutral';
    }

    // Provider switch getters
    get gmailSwitchClass() {
        return 'provider-btn' + (this.selectedProvider === 'GOOGLE_CALENDAR' ? ' active' : '');
    }

    get outlookSwitchClass() {
        return 'provider-btn' + (this.selectedProvider === 'MICROSOFT_CALENDAR' ? ' active' : '');
    }

    get showProviderSwitch() {
        // Show provider switch only when BOTH providers are enabled in org settings
        return this.providerSettings.bothEnabled;
    }
    
    get showNoProviderMessage() {
        return this.providerSettings.neitherEnabled;
    }

    get calendarTitle() {
        return this.calendarEmail || (this.selectedProvider === 'GOOGLE_CALENDAR' ? 'Google Calendar' : 'Outlook Calendar');
    }

    get notAccessibleMessage() {
        return 'Calendar access is not available. Please ensure the calendars read permission is granted.';
    }
}