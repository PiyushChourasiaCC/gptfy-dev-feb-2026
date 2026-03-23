import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

// Apex methods
import getExchangeEmails from '@salesforce/apex/AIExchangeEmailController.getExchangeEmails';
import autoMatch from '@salesforce/apex/AIExchangeEmailController.autoMatch';
import getAuthenticationDetails from '@salesforce/apex/AIExchangeEmailController.getAuthenticationDetails';
import refreshTokenAndGetDetails from '@salesforce/apex/AIExchangeEmailController.refreshTokenAndGetDetails';
import importSelectedEmails from '@salesforce/apex/AIExchangeEmailController.importSelectedEmails';
import getProviderSettings from '@salesforce/apex/AISyncSettingsService.getProviderSettings';
import checkEmailSyncPermissions from '@salesforce/apex/AIWorkspacePermissionService.checkEmailSyncPermissions';

import gptfyLogo from '@salesforce/resourceUrl/gptfylogo';



export default class aiExchangeEmailSelector extends NavigationMixin(LightningElement) {
    // Public properties
    @api recordId; // Parent record context
    @api objectApiName; // Parent object type
    @api flexipageRegionWidth; // Detect if in narrow region for compact mode
    @api selectedProvider = 'MICROSOFT_EMAIL'; // Provider passed from parent

    // Tracked properties
    @track emails = [];
    @track selectedEmails = [];
    @track isLoading = true;
    @track error;
    @track isAuthenticated = false;
    @track userEmailAddress = ''; // Authenticated user's email
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
    @track totalEmails = 0;
    @track totalEmailsFetched = false; // Flag to track if we've fetched initial total count
    @track hasMoreEmails = false; // Tracks if there are more emails to fetch
    @track nextPageToken = null; // For Gmail cursor-based pagination
    pageTokens = [null]; // Store tokens for each page (index = page - 1)
    pageEmailCounts = [0]; // Track actual email count per page (index = page - 1)
    @track cumulativeEmailCount = 0; // Running total of emails fetched across all pages

    // Filters
    searchKey = '';
    activeFilter = 'today';

    // UI state
    showLoadingOverlay = false;
    loadingMessage = '✨ Loading your inbox...';
    loadingSubtext = 'Connecting to email provider';
    lastSyncTime = 'Just now';

    // Modal state
    @track showQuickMatchModal = false;
    @track modalItems = []; // Items to pass to the modal component

    // Debounce timeout
    debounceTimeout;
    searchDebounceTimeout;


    get providerOptions() {
        return [
            { label: 'Microsoft Outlook', value: 'MICROSOFT_EMAIL' },
            { label: 'Gmail', value: 'GMAIL_EMAIL' }
        ];
    }

    handleProviderChange(event) {
        this.selectedProvider = event.detail.value;
        this.resetPagination();
        this.emails = [];
        this.userEmailAddress = ''; // Clear email when switching providers
        this.checkAuthentication();
    }

    handleProviderSwitch(event) {
        const provider = event.currentTarget.dataset.provider;
        if (provider && provider !== this.selectedProvider) {
            this.selectedProvider = provider;
            this.resetPagination();
            this.emails = [];
            this.userEmailAddress = ''; // Clear email when switching providers
            this.checkAuthentication();
        }
    }

    /**
     * Reset all pagination state to initial values
     */
    resetPagination() {
        this.currentPage = 1;
        this.pageTokens = [null];
        this.pageEmailCounts = [0];
        this.totalEmails = 0;
        this.totalEmailsFetched = false; // Reset flag so total will be fetched again
        this.hasMoreEmails = false;
        this.nextPageToken = null;
        this.cumulativeEmailCount = 0;
    }

    /**
     * Lifecycle hook - component connected to DOM
     */
    connectedCallback() {
        this.loadProviderSettings();
    }
    
    /**
     * Load provider settings from org configuration
     * Determines if both providers are enabled or only one
     */
    loadProviderSettings() {
        getProviderSettings()
            .then(settings => {
                this.providerSettings = settings;

                // Only auto-select if parent hasn't already set the provider
                // Note: selectedProvider comes from parent via @api, so don't override if it's already set
                // The parent component is responsible for determining the correct provider
                
                this.checkAuthentication();
            })
            .catch(error => {
                console.error('Error loading provider settings:', error);
                // Fallback to default behavior
                this.checkAuthentication();
            });
    }

    /**
     * Handle retry connection button click
     */
    handleRetryConnection() {
        // Set loading state immediately before async call
        this.isLoading = true;
        this.isAuthenticated = false;
        // Small delay to ensure UI updates before API call
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.checkAuthentication();
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
     * Check authentication and get user email address
     * On first load (selectedProvider is null), auto-detects which provider user is authenticated with
     * Now also refreshes the access token on page load to ensure it's fresh
     */
    async checkAuthentication() {
        this.isLoading = true;
        try {
            // First, try to refresh the token (this ensures fresh token before any API calls)
            // This handles the DML (token save) before any callouts happen
            const refreshResult = await refreshTokenAndGetDetails({ providerType: this.selectedProvider });
            
            if (refreshResult.success && refreshResult.isAuthenticated) {
                // Token refreshed successfully - use these details
                this.isAuthenticated = true;
                this.namespace = refreshResult.namespace || '';

                // Note: Don't override selectedProvider - parent component controls this

                // If userEmail is empty (due to callout-after-DML prevention), fetch it separately
                if (refreshResult.userEmail) {
                    this.userEmailAddress = refreshResult.userEmail;
                } else {
                    // Fetch user email in a separate call (after DML transaction is committed)
                    this.fetchUserEmail();
                }

                this.loadEmails();
            } else {
                // Token refresh failed or no connection - fall back to regular auth check
                const result = await getAuthenticationDetails({ providerType: this.selectedProvider });

                if (result.success) {
                    this.isAuthenticated = result.isAuthenticated;
                    this.userEmailAddress = result.userEmail;
                    this.namespace = result.namespace || '';

                    // Note: Don't override selectedProvider - parent component controls this

                    if (this.isAuthenticated) {
                        this.loadEmails();
                    } else {
                        // Not authenticated - show empty state (no error toast)
                        this.userEmailAddress = ''; // Clear email when not authenticated
                        this.isLoading = false;
                    }
                } else {
                    // Authentication check failed - show empty state (no error toast)
                    this.userEmailAddress = ''; // Clear email when authentication fails
                    this.isLoading = false;
                }
            }
        } catch (error) {
            // Silent error handling - show empty state instead of error toast
            console.error('Error checking authentication:', error);
            this.isAuthenticated = false;
            this.userEmailAddress = ''; // Clear email on error
            this.isLoading = false;
        } finally {
            if (!this.isAuthenticated) {
                this.isLoading = false;
            }
        }
    }

    /**
     * Fetch user email address separately (called after token refresh to avoid callout-after-DML)
     */
    async fetchUserEmail() {
        try {
            const result = await getAuthenticationDetails({ providerType: this.selectedProvider });
            if (result.success && result.userEmail) {
                this.userEmailAddress = result.userEmail;
            }
        } catch (error) {
            console.error('Error fetching user email:', error);
            // Not critical - display will fallback to provider name
        }
    }

    /**
     * Load emails from the selected email provider
     */
    async loadEmails() {
        this.isLoading = true;
        this.error = undefined;

        try {
            const offset = (this.currentPage - 1) * this.pageSize;
            // Get the page token for the current page (Gmail uses cursor-based pagination)
            const pageToken = this.pageTokens[this.currentPage - 1] || null;

            const result = await getExchangeEmails({
                recordLimit: this.pageSize,
                offset: offset,
                filterCriteria: this.buildFilterCriteria(),
                searchTerm: this.searchKey,
                providerType: this.selectedProvider,
                pageToken: pageToken
            });

            if (result.success) {
                this.emails = this.processEmailData(result.emails);
                this.lastSyncTime = 'Just now';

                // Track actual email count for this page
                const currentPageEmailCount = this.emails.length;
                this.pageEmailCounts[this.currentPage - 1] = currentPageEmailCount;

                // Store the nextPageToken for the next page (Gmail pagination)
                if (result.nextPageToken) {
                    this.nextPageToken = result.nextPageToken;
                    this.pageTokens[this.currentPage] = result.nextPageToken;
                } else {
                    this.nextPageToken = null;
                }

                // Calculate cumulative email count (sum of all pages visited)
                this.cumulativeEmailCount = 0;
                for (let i = 0; i < this.currentPage; i++) {
                    this.cumulativeEmailCount += this.pageEmailCounts[i] || 0;
                }

                // Handle total count - update on every page load since filters may change
                // Only use the API totalCount if it's available (> 0)
                if (result.totalCount && result.totalCount > 0) {
                    this.totalEmails = result.totalCount;
                    this.totalEmailsFetched = true;
                } else {
                    // When totalCount is 0 or not provided (filtered results), 
                    // calculate from cumulative count as we paginate
                    if (!this.hasMoreEmails && this.cumulativeEmailCount > 0) {
                        // We've reached the end, so cumulative count is the total
                        this.totalEmails = this.cumulativeEmailCount;
                    } else if (this.cumulativeEmailCount > 0) {
                        // Still have more pages, show cumulative count with "+"
                        this.totalEmails = this.cumulativeEmailCount;
                    } else {
                        // First page load with no total - show current page count
                        this.totalEmails = this.emails.length;
                    }
                }

                // Determine if there are more emails
                if (this.selectedProvider === 'GMAIL_EMAIL') {
                    // Gmail uses cursor-based pagination with nextPageToken
                    this.hasMoreEmails = !!result.nextPageToken;

                    // For filtered results (Today, Has Files, Search), update total when we reach the end
                    // This gives us the accurate count for the filtered set
                    if (!this.hasMoreEmails && this.cumulativeEmailCount > 0 && !this.totalEmailsFetched) {
                        this.totalEmails = this.cumulativeEmailCount;
                    }
                } else {
                    // Microsoft Graph uses offset-based pagination
                    // Primary: use hasMore flag from API (checks @odata.nextLink)
                    if (result.hasMore !== undefined && result.hasMore !== null) {
                        this.hasMoreEmails = result.hasMore;
                    } else if (this.totalEmails > 0) {
                        // Secondary: compare cumulative count vs total
                        this.hasMoreEmails = this.cumulativeEmailCount < this.totalEmails;
                    } else {
                        // Fallback: if we got a full page, assume there might be more
                        this.hasMoreEmails = this.emails.length >= this.pageSize;
                    }
                }

            } else {
                throw new Error(result.error || 'Failed to load emails');
            }
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }


    /**
     * Process raw email data from Graph API
     * Sorts emails by date descending (newest first)
     * Uses receivedDateTime for inbox emails, sentDateTime for sent emails
     */
    processEmailData(emails) {
        if (!emails || emails.length === 0) return [];

        // Sort by receivedDateTime or sentDateTime (for sent items)
        const sortedEmails = [...emails].sort((a, b) => {
            // Use receivedDateTime first, fall back to sentDateTime for sent items
            const dateA = a.receivedDateTime 
                ? new Date(a.receivedDateTime).getTime() 
                : (a.sentDateTime ? new Date(a.sentDateTime).getTime() : 0);
            const dateB = b.receivedDateTime 
                ? new Date(b.receivedDateTime).getTime() 
                : (b.sentDateTime ? new Date(b.sentDateTime).getTime() : 0);
            return dateB - dateA;
        });

        return sortedEmails.map(email => {
            // Determine avatar gradient based on sender name
            const senderName = email.from?.emailAddress?.name || email.from?.emailAddress?.address;
            const avatarGradient = this.getAvatarGradient(senderName);

            // Map associations to badges with deduplication
            // Show Lead, Contact, User, Account, Opportunity badges
            // Filter out staging-related types and other record types - don't expose staging records
            const allowedTypes = ['Lead', 'Contact', 'User', 'Account', 'Opportunity'];
            let associationBadges = [];
            if (email.associations && email.associations.length > 0) {
                const seen = new Set();
                associationBadges = email.associations
                    .filter(assoc => {
                        // Only include allowed types (real Salesforce records)
                        if (!allowedTypes.includes(assoc.type)) {
                            return false;
                        }
                        const key = `${assoc.type}:${assoc.name}`;
                        if (seen.has(key)) {
                            return false;
                        }
                        seen.add(key);
                        return true;
                    })
                    .map((assoc, index) => {
                        let cssClass = 'badge badge-link';
                        if (assoc.type === 'Contact') cssClass += ' badge-contact';
                        else if (assoc.type === 'Lead') cssClass += ' badge-lead';
                        else if (assoc.type === 'User') cssClass += ' badge-user';
                        else if (assoc.type === 'Account') cssClass += ' badge-account';
                        else if (assoc.type === 'Opportunity') cssClass += ' badge-opportunity';
                        else cssClass += ' badge-default';

                        return {
                            key: `${email.id}-${assoc.type}-${assoc.name}-${index}`,
                            name: assoc.name,
                            type: assoc.type,
                            recordId: assoc.recordId,
                            cssClass: cssClass
                        };
                    });
            }

            // Check if email is already imported
            const isImported = email.isImported || false;

            // Build row class - add 'imported' class if already imported
            let rowClass = email.isRead ? 'email-row read' : 'email-row unread';
            if (isImported) {
                rowClass += ' imported';
            }

            return {
                id: email.id,
                subject: email.subject || '(No Subject)',
                bodyPreview: email.bodyPreview || '',
                fromName: email.from?.emailAddress?.name || email.from?.emailAddress?.address || 'Unknown',
                fromAddress: email.from?.emailAddress?.address || '',
                fromInitials: this.getInitials(email.from?.emailAddress?.name),
                // Use receivedDateTime for inbox emails, sentDateTime for sent items
                receivedTime: new Date(email.receivedDateTime || email.sentDateTime),
                receivedTimeFormatted: this.formatTime(email.receivedDateTime || email.sentDateTime),
                hasAttachments: email.hasAttachments,
                isImportant: email.importance === 'high',
                isRead: email.isRead,
                isImported: isImported,
                selected: this.selectedEmails.some(e => e.id === email.id) && !isImported,
                rowClass: rowClass,
                avatarStyle: `background: ${avatarGradient}`,
                hasAssociations: associationBadges.length > 0,
                associationBadges: associationBadges,
                // Include recipient data for Quick Match modal to match against TO/CC recipients
                toRecipients: email.toRecipients || [],
                ccRecipients: email.ccRecipients || [],
                from: email.from // Include full from object for consistency
            };
        });
    }

    /**
     * Get initials from full name
     */
    getInitials(name) {
        if (!name) return '??';

        const parts = name.split(' ');
        if (parts.length >= 2) {
            return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
        }
        return name.substring(0, 2).toUpperCase();
    }

    /**
     * Get deterministic avatar gradient based on name
     */
    getAvatarGradient(name) {
        const gradients = [
            'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
            'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
            'linear-gradient(135deg, #fa709a 0%, #fee140 100%)',
            'linear-gradient(135deg, #30cfd0 0%, #330867 100%)',
            'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
            'linear-gradient(135deg, #a8edea 0%, #fed6e3 100%)',
            'linear-gradient(135deg, #ff9a9e 0%, #fecfef 100%)',
            'linear-gradient(135deg, #ffecd2 0%, #fcb69f 100%)'
        ];

        // Simple hash function for deterministic color selection
        let hash = 0;
        for (let i = 0; i < (name || '').length; i++) {
            hash = name.charCodeAt(i) + ((hash << 5) - hash);
        }

        return gradients[Math.abs(hash) % gradients.length];
    }

    /**
     * Get CSS class for badge based on record type
     */
    getBadgeCssClass(recordType) {
        const type = (recordType || '').toLowerCase();
        if (type === 'contact') {
            return 'badge linked-contact';
        } else if (type === 'lead') {
            return 'badge linked-lead';
        } else if (type === 'user') {
            return 'badge linked-user';
        }
        return 'badge linked';
    }

    /**
     * Format datetime for display
     */
    formatTime(dateTimeStr) {
        if (!dateTimeStr) return '';

        const emailDate = new Date(dateTimeStr);
        const now = new Date();
        const diffMs = now - emailDate;
        const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
        const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

        if (diffHours < 1) {
            return 'Just now';
        } else if (diffHours < 2) {
            return '1 hour ago';
        } else if (diffHours < 24) {
            return `${diffHours} hours ago`;
        } else if (diffDays === 1) {
            return 'Yesterday';
        } else if (diffDays < 7) {
            return `${diffDays} days ago`;
        } else {
            return emailDate.toLocaleDateString('en-US', {
                month: 'short',
                day: 'numeric',
                year: 'numeric'
            });
        }
    }

    /**
     * Build OData filter criteria based on active filters
     */
    buildFilterCriteria() {
        let filters = [];

        // Search filter REMOVED - handled by searchTerm parameter
        // When searching, don't apply other filters to avoid conflicts
        if (this.searchKey) {
            return '';
        }

        // Date filter - use receivedDateTime which works for both inbox and sent items
        // Microsoft Graph API populates receivedDateTime for all email types
        if (this.activeFilter === 'today') {
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            filters.push(`receivedDateTime ge ${today.toISOString()}`);
        }

        // All Emails filter - no additional filter needed, just fetch all emails
        // (removed unread filter - now showing all emails regardless of read status)

        // Has attachments filter
        if (this.activeFilter === 'files') {
            filters.push('hasAttachments eq true');
        }

        return filters.length > 0 ? filters.join(' and ') : '';
    }

    /**
     * Handle checkbox click directly
     * Stops propagation to prevent double-toggle from row click
     */
    handleCheckboxClick(event) {
        event.stopPropagation();

        const emailId = event.target.dataset.emailId;
        const isChecked = event.target.checked;

        // Find the email
        const email = this.emails.find(e => e.id === emailId);

        // Don't allow selection of imported emails
        if (email && email.isImported) {
            event.target.checked = false;
            return;
        }

        this.updateEmailSelection(emailId, isChecked, email);
    }

    /**
     * Handle row selection toggle
     */
    handleRowSelection(event) {
        // Don't toggle if clicking checkbox (handled by handleCheckboxClick)
        if (event.target.type === 'checkbox') {
            return;
        }

        // Don't toggle if clicking quick import button
        if (event.target.classList.contains('quick-btn')) {
            return;
        }

        const emailId = event.currentTarget.dataset.emailId;
        const checkbox = event.currentTarget.querySelector('input[type="checkbox"]');

        // Find the email to check if it's imported
        const email = this.emails.find(e => e.id === emailId);

        // Don't allow selection of imported emails
        if (email && email.isImported) {
            return;
        }

        // Toggle checkbox state
        const newCheckedState = !checkbox.checked;
        checkbox.checked = newCheckedState;

        this.updateEmailSelection(emailId, newCheckedState, email);
    }

    /**
     * Common method to update email selection state
     */
    updateEmailSelection(emailId, isSelected, email) {
        // Update selected emails array
        if (isSelected) {
            if (email && !this.selectedEmails.find(e => e.id === emailId)) {
                this.selectedEmails.push(email);
            }
        } else {
            this.selectedEmails = this.selectedEmails.filter(e => e.id !== emailId);
        }

        // Update email selected state in main list
        this.emails = this.emails.map(e => {
            if (e.id === emailId) {
                return { ...e, selected: isSelected };
            }
            return e;
        });
    }

    /**
     * Handle quick import of single email
     */
    async handleQuickImport(event) {
        event.stopPropagation();

        const emailId = event.currentTarget.dataset.emailId;
        const email = this.emails.find(e => e.id === emailId);

        if (!email) return;

        // Show loading overlay
        this.showLoadingOverlay = true;
        this.loadingMessage = '✨ Importing your email...';
        this.loadingSubtext = 'GPTfy is preparing your email for AI magic';

        try {
            const result = await importSelectedEmails({
                messageIds: [emailId],
                parentRecordId: this.recordId,
                providerType: this.selectedProvider
            });

            // Wait minimum 1.5s for smooth UX
            await this.delay(1500);

            this.showLoadingOverlay = false;

            if (result.success && result.successCount > 0) {
                // Show success toast
                this.showToast(
                    'Success',
                    '🎉 Email imported successfully!',
                    'success'
                );

                // Remove email from list with animation
                this.removeEmailFromList(emailId);

                // Refresh total imported count

                // Dispatch event for parent components
                this.dispatchEvent(new CustomEvent('emailimported', {
                    detail: { emailId: emailId, count: 1 }
                }));
            } else {
                throw new Error(result.error || 'Import failed');
            }
        } catch (error) {
            this.showLoadingOverlay = false;
            this.handleError(error);
        }
    }

    /**
     * Handle Quick Match button click - opens modal for user to review/modify matches
     */
    async handleAutoSyncWithAI() {
        if (this.selectedEmails.length === 0) {
            this.showToast('Warning', 'Please select at least one email', 'warning');
            return;
        }

        // Check 20-email limit
        const MAX_EMAILS = 20;
        if (this.selectedEmails.length > MAX_EMAILS) {
            this.showToast(
                'Too Many Emails Selected',
                `Please select ${MAX_EMAILS} or fewer emails per sync. You have ${this.selectedEmails.length} selected. You can run multiple syncs if needed.`,
                'warning'
            );
            return;
        }

        // Check permissions before proceeding
        try {
            const permResult = await checkEmailSyncPermissions();
            if (!permResult.hasAccess) {
                this.showToast('Insufficient Permissions', permResult.errorMessage, 'error');
                return;
            }
        } catch (err) {
            console.error('Error checking permissions:', err);
            // Continue anyway - permission check is informational
        }

        // Open modal with selected emails
        await this.openQuickMatchModal();
    }

    /**
     * Open Quick Match modal - prepare items for the modal component
     */
    async openQuickMatchModal() {
        // Prepare items for the modal component
        this.modalItems = this.selectedEmails;
        this.showQuickMatchModal = true;
    }

    /**
     * Close Quick Match modal
     */
    handleCloseModal() {
        this.showQuickMatchModal = false;
        this.modalItems = [];
    }

    /**
     * Handle modal error event
     */
    handleModalError(event) {
        const errorMessage = event.detail && event.detail.message 
            ? (typeof event.detail.message === 'string' ? event.detail.message : JSON.stringify(event.detail.message))
            : 'Failed to import email(s)';
        
        this.showToast('Error', errorMessage, 'error');
        this.handleCloseModal();
    }

    /**
     * Handle modal success event
     */
    async handleModalSuccess(event) {
        const { count, excludedCount, duplicateCount } = event.detail;
        
        // Build message based on results
        let message = '';
        let variant = 'success';
        
        if (count > 0) {
            // Some emails were imported successfully
            message = `${count} email(s) imported successfully! Check the bell icon (🔔) for details.`;
        } else if (excludedCount > 0) {
            // No imports, but some were excluded
            message = `${excludedCount} email(s) excluded by exclusion rules. No emails imported.`;
            variant = 'info';
        } else if (duplicateCount > 0) {
            // No imports, but some were duplicates
            message = `${duplicateCount} email(s) already imported (duplicates). No new emails imported.`;
            variant = 'info';
        } else {
            // No imports and no exclusions/duplicates
            message = '0 email(s) imported.';
            variant = 'warning';
        }
        
        // Show toast with appropriate message
        this.showToast(count > 0 ? 'Success' : 'Info', message, variant);

                // Close modal
                this.handleCloseModal();
        
        // Clear selection BEFORE reloading emails
        this.clearSelection();

                // Refresh email list
                await this.loadEmails();

                // Dispatch event
                this.dispatchEvent(new CustomEvent('emailsimported', {
            detail: { count: count }
        }));
    }

    /**
     * Show match results summary (placeholder for future UI enhancement)
     */
    showMatchResultsSummary(matchResults) {
        // Match results are available for future UI modal enhancement
        // Currently handled via toast notifications
    }

    /**
     * Remove email from list with animation
     */
    removeEmailFromList(emailId) {
        // Remove from emails array
        this.emails = this.emails.filter(e => e.id !== emailId);

        // Update counts
        this.totalEmails = Math.max(0, this.totalEmails - 1);
        this.cumulativeEmailCount = Math.max(0, this.cumulativeEmailCount - 1);

        // Update the current page's email count
        if (this.pageEmailCounts[this.currentPage - 1] > 0) {
            this.pageEmailCounts[this.currentPage - 1]--;
        }
    }

    /**
     * Clear all selections
     */
    clearSelection() {
        this.selectedEmails = [];

        // Uncheck all checkboxes in data
        this.emails = this.emails.map(e => ({ ...e, selected: false }));
    }

    /**
     * Handle search input
     */
    handleSearch(event) {
        this.searchKey = event.target.value;

        // Debounce search
        clearTimeout(this.debounceTimeout);
        this.debounceTimeout = setTimeout(() => {
            this.resetPagination();
            this.loadEmails();
        }, 500);
    }

    /**
     * Handle filter chip click
     */
    handleFilterClick(event) {
        this.activeFilter = event.currentTarget.dataset.filter;
        this.resetPagination();
        this.loadEmails();
    }

    /**
     * Handle refresh button click
     */
    handleRefresh() {
        this.showLoadingOverlay = true;
        this.loadingMessage = '🔄 Refreshing your inbox...';
        this.loadingSubtext = 'Checking for new emails';
        this.resetPagination();

        this.loadEmails().finally(() => {
            setTimeout(() => {
                this.showLoadingOverlay = false;
            }, 1000);
        });
    }

    /**
     * Handle previous page
     */
    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.loadEmails();
        }
    }

    /**
     * Handle next page
     */
    handleNextPage() {
        if (!this.isLastPage) {
            this.currentPage++;
            this.loadEmails();
        }
    }




    /**
     * Handle error
     */
    handleError(error) {
        this.error = error.body?.message || error.message || 'An unexpected error occurred';
        this.isLoading = false;
        this.showLoadingOverlay = false;

        // Check for 401 Unauthorized or authentication errors
        if (this.error.includes('401') || 
            this.error.includes('Unauthorized') || 
            this.error.includes('No Gmail connection') ||
            this.error.includes('No Outlook connection') ||
            this.error.includes('authenticate')) {
            this.isAuthenticated = false;
            // Don't show error toast for authentication issues - let empty state handle it
            return;
        }

        // Only show toast for non-authentication errors
        this.showToast('Error', this.error, 'error');
    }

    /**
     * Show toast notification
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    /**
     * Delay helper for smooth UX
     */
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    /**
     * Handle click on association badge to navigate to the linked record
     * Opens the record in a new browser tab
     */
    handleAssociationClick(event) {
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

    // Computed properties

    get hasEmails() {
        return this.emails && this.emails.length > 0;
    }

    get hasSelection() {
        return this.selectedEmails.length > 0;
    }

    get selectionCount() {
        return this.selectedEmails.length;
    }

    get selectionBarClass() {
        return this.hasSelection ? 'selection-bar active' : 'selection-bar';
    }

    get loadingOverlayClass() {
        return this.showLoadingOverlay ? 'loading-overlay active' : 'loading-overlay';
    }

    get unreadCount() {
        // This is an approximation based on loaded emails, ideally should come from API
        return this.emails.filter(e => !e.isRead).length;
    }


    /**
     * Get the starting email number for the current page (1-indexed)
     */
    get pageStart() {
        if (this.emails.length === 0) return 0;
        // Simple offset-based calculation: (page - 1) * pageSize + 1
        return (this.currentPage - 1) * this.pageSize + 1;
    }

    /**
     * Get the ending email number for the current page
     */
    get pageEnd() {
        if (this.emails.length === 0) return 0;
        // Start position + number of emails on current page - 1
        return this.pageStart + this.emails.length - 1;
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
        // No emails loaded means we're at the last page
        if (this.emails.length === 0) return true;

        // If we have fewer emails than page size, it's definitely the last page
        if (this.emails.length < this.pageSize) return true;

        // Primary check: use hasMoreEmails flag (set from API response)
        if (!this.hasMoreEmails) return true;

        // Secondary check: if we have totalEmails and cumulative >= total, it's the last page
        if (this.totalEmails > 0 && this.cumulativeEmailCount >= this.totalEmails) return true;

        return false;
    }

    /**
     * Get display text for total emails
     * Shows accurate counts from Gmail labels API for unfiltered views
     * Shows cumulative count with "+" for filtered views (Today, Has Files, Search)
     */
    get totalEmailsDisplay() {
        // If we have more emails to fetch and total wasn't set by labels API,
        // show "+" to indicate there are more
        if (this.hasMoreEmails && !this.totalEmailsFetched) {
            return this.totalEmails + '+';
        }
        return this.totalEmails;
    }

    /**
     * Check if Previous button should be disabled
     */
    get isPreviousDisabled() {
        return this.isFirstPage;
    }

    /**
     * Check if Next button should be disabled
     * Disabled when on last page OR when there are fewer emails than page size
     */
    get isNextDisabled() {
        // Disable if on last page
        if (this.isLastPage) return true;
        
        // Disable if no more emails to fetch and we have fewer than page size
        if (!this.hasMoreEmails && this.emails.length < this.pageSize) return true;
        
        return false;
    }

    // Filter classes
    get todayFilterClass() { return this.activeFilter === 'today' ? 'active' : ''; }
    get allEmailsFilterClass() { return this.activeFilter === 'all' ? 'active' : ''; }
    get filesFilterClass() { return this.activeFilter === 'files' ? 'active' : ''; }
    
    // Filter active state for showing counts
    get isTodayFilter() { return this.activeFilter === 'today'; }
    get isAllEmailsFilter() { return this.activeFilter === 'all'; }
    get isFilesFilter() { return this.activeFilter === 'files'; }

    // Provider switch classes
    get gmailSwitchClass() { return 'provider-btn' + (this.selectedProvider === 'GMAIL_EMAIL' ? ' active' : ''); }
    get outlookSwitchClass() { return 'provider-btn' + (this.selectedProvider === 'MICROSOFT_EMAIL' ? ' active' : ''); }

    // Show provider switch only when BOTH providers are enabled in org settings
    get showProviderSwitch() { 
        return this.providerSettings.bothEnabled; 
    }
    
    // Show message when neither provider is enabled
    get showNoProviderMessage() {
        return this.providerSettings.neitherEnabled;
    }

    // Logo
    get logoUrl() {
        return gptfyLogo;
    }

    get providerDisplayName() {
        return this.selectedProvider === 'GMAIL_EMAIL'
            ? 'Gmail'
            : 'Microsoft Exchange / Outlook';
    }

    get notAccessibleMessage() {
        return 'Email access is not available. Please ensure the mail.read scope is granted.';
    }

    get inboxTitle() {
        return this.userEmailAddress || (this.selectedProvider === 'GMAIL_EMAIL' ? 'Google Gmail' : 'Outlook');
    }

    get isCompactMode() {
        return this.flexipageRegionWidth === 'SMALL';
    }

    get authenticationSettingsUrl() {
        // URL to Workspace Authentication tab with namespace prefix for packaged apps
        return '/lightning/n/' + this.namespace + 'Workspace_Authentication';
    }

}