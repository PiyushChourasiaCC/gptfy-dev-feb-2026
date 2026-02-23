import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getTasks from '@salesforce/apex/AITaskSyncController.getTasks';
    import getGoogleTasks from '@salesforce/apex/AITaskSyncController.getGoogleTasks';
import getTaskLists from '@salesforce/apex/AITaskSyncController.getTaskLists';
import getGoogleTaskLists from '@salesforce/apex/AITaskSyncController.getGoogleTaskLists';
import importTasks from '@salesforce/apex/AITaskSyncController.importTasks';
import importGoogleTasks from '@salesforce/apex/AITaskSyncController.importGoogleTasks';
import checkTaskAccess from '@salesforce/apex/AITaskSyncController.checkTaskAccess';
import refreshTokenAndCheckAccess from '@salesforce/apex/AITaskSyncController.refreshTokenAndCheckAccess';
import getProviderSettings from '@salesforce/apex/AISyncSettingsService.getProviderSettings';
import checkTaskSyncPermissions from '@salesforce/apex/AIWorkspacePermissionService.checkTaskSyncPermissions';
import gptfyLogo from '@salesforce/resourceUrl/gptfylogo';

export default class aiTaskSelector extends NavigationMixin(LightningElement) {
    @api recordId;

    @track tasks = [];
    @track taskLists = [];
    @track isLoading = true;
    @track isImporting = false;
    @track isTaskAccessible = false;
    @track userEmail = '';
    @track selectedList = 'all';
    @track selectedFilter = 'pending'; // pending, all, completed
    @track searchKey = '';
    @track selectedProvider = 'MICROSOFT_GRAPH'; // 'GOOGLE_TASKS' or 'MICROSOFT_GRAPH'
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
    @track totalTasks = 0;
    @track hasMoreTasks = false;
    @track nextPageToken = null;
    @track cumulativeTaskCount = 0;

    // Persistent selection tracking across pages
    // Map of taskId -> {compositeId, taskId} for import
    selectedTasksMap = new Map();
    
    // Modal state for Quick Match
    @track showQuickMatchModal = false;
    @track modalItems = [];
    
    // Avatar gradient colors (same as calendar/email)
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
                
                // If only one provider is enabled, auto-select it
                if (settings.singleProvider) {
                    // Map to task-specific provider names
                    this.selectedProvider = settings.singleProvider === 'GMAIL' ? 'GOOGLE_TASKS' : 'MICROSOFT_GRAPH';
                }
                
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
            const refreshResult = await refreshTokenAndCheckAccess({ providerType: this.selectedProvider });
            
            if (refreshResult.refreshed && refreshResult.isAccessible) {
                // Token refreshed successfully - use these details
                this.isTaskAccessible = true;
                this.namespace = refreshResult.namespace || '';
                
                // If userEmail is empty (due to callout-after-DML prevention), fetch it separately
                if (refreshResult.userEmail) {
                    this.userEmail = refreshResult.userEmail;
                } else {
                    // Fetch user email in a separate call (after DML transaction is committed)
                    this.fetchUserEmail();
                }
                
                await this.loadTaskLists();
                await this.loadTasks();
            } else {
                // Token refresh failed or no access - fall back to regular access check
                const result = await checkTaskAccess({ providerType: this.selectedProvider });
                this.isTaskAccessible = result.isAccessible;
                this.userEmail = result.userEmail || '';
                this.namespace = result.namespace || '';

                if (this.isTaskAccessible) {
                    await this.loadTaskLists();
                    await this.loadTasks();
                }
            }
        } catch (error) {
            this.isTaskAccessible = false;
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Fetch user email address separately (called after token refresh to avoid callout-after-DML)
     */
    async fetchUserEmail() {
        try {
            const result = await checkTaskAccess({ providerType: this.selectedProvider });
            if (result.isAccessible && result.userEmail) {
                this.userEmail = result.userEmail;
            }
        } catch (error) {
            console.error('Error fetching user email:', error);
            // Not critical - display will fallback to provider name
        }
    }

    async loadTaskLists() {
        try {
            // Call the appropriate method based on selected provider
            if (this.selectedProvider === 'GOOGLE_TASKS') {
                this.taskLists = await getGoogleTaskLists();
            } else {
                this.taskLists = await getTaskLists();
            }
        } catch (error) {
            // Silently handle - task lists may not be available
            console.error('Error loading task lists:', error);
        }
    }

    async loadTasks() {
        this.isLoading = true;
        try {
            const includeCompleted = this.selectedFilter === 'all' || this.selectedFilter === 'completed';
            
            // Get page token for current page (offset-based)
            const pageToken = this.currentPage > 1 ? String((this.currentPage - 1) * this.pageSize) : null;
            
            // Call the appropriate method based on selected provider
            let response;
            if (this.selectedProvider === 'GOOGLE_TASKS') {
                response = await getGoogleTasks({
                    listFilter: this.selectedList,
                    includeCompleted: includeCompleted,
                    maxResults: this.pageSize,
                    pageToken: pageToken
                });
            } else {
                response = await getTasks({
                    listFilter: this.selectedList,
                    includeCompleted: includeCompleted,
                    maxResults: this.pageSize,
                    pageToken: pageToken
                });
            }

            if (response.error) {
                this.showToastMessage(response.error, 'error');
                this.tasks = [];
                return;
            }

            let filteredTasks = response.tasks || [];

            // Filter by status if needed (additional client-side filtering)
            if (this.selectedFilter === 'pending') {
                filteredTasks = filteredTasks.filter(t => t.status !== 'completed');
            } else if (this.selectedFilter === 'completed') {
                filteredTasks = filteredTasks.filter(t => t.status === 'completed');
            }

            // Format tasks and restore selection state from persistent Map
            this.tasks = filteredTasks.map(task => {
                const formatted = this.formatTask(task, response.importedTasks);
                // Restore selection if this task was previously selected
                formatted.selected = this.selectedTasksMap.has(task.taskId);
                return formatted;
            });
            
            // Update pagination state
            this.hasMoreTasks = response.hasMore || false;
            this.nextPageToken = response.nextPageToken;
            
            // Update cumulative count for display
            const currentPageTaskCount = this.tasks.length;
            this.cumulativeTaskCount = (this.currentPage - 1) * this.pageSize + currentPageTaskCount;
            
            // totalTasks = what we know so far (cumulative)
            // The getter totalTasksDisplay will add "+" if there are more
            this.totalTasks = this.cumulativeTaskCount;
            
            // Load total imported count from database
        } catch (error) {
            this.showToastMessage('Failed to load tasks: ' + this.getErrorMessage(error), 'error');
            this.tasks = [];
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * Reset all pagination state to initial values
     */
    resetPagination() {
        this.currentPage = 1;
        this.totalTasks = 0;
        this.hasMoreTasks = false;
        this.nextPageToken = null;
        this.cumulativeTaskCount = 0;
        // Clear selections when changing provider/filter/list
        this.selectedTasksMap.clear();
    }
    
    /**
     * Load total imported task count from database (filtered by current provider)
     * This queries the total count of Task records for the current provider
     */

    formatTask(task, importedMap) {
        const isImported = task.isImported || (importedMap && importedMap[task.taskId]);

        // Generate initials and avatar
        const initials = this.getInitials(task.title);
        const avatarStyle = `background: ${this.getAvatarGradient(task.title)}`;

        // Build row class
        let rowClass = 'task-row';
        if (isImported) rowClass += ' imported';
        if (task.status === 'completed') rowClass += ' completed';

        // Format due date
        let formattedDueDate = '';
        let isOverdue = false;
        let dueDateClass = 'due-date';
        if (task.dueDateTime) {
            const dueDate = new Date(task.dueDateTime);
            const today = new Date();
            today.setHours(0, 0, 0, 0);

            if (dueDate < today && task.status !== 'completed') {
                isOverdue = true;
                dueDateClass = 'due-date overdue';
            }

            formattedDueDate = dueDate.toLocaleDateString('en-US', {
                weekday: 'short',
                month: 'short',
                day: 'numeric'
            });
        }

        // Priority class
        const priorityClass = 'badge priority-' + (task.importance || 'normal').toLowerCase();

        // Process multiple linked records for multiple pills display (same as Calendar)
        let linkedRecordsFormatted = [];
        if (task.linkedRecords && task.linkedRecords.length > 0) {
            linkedRecordsFormatted = task.linkedRecords.map((lr, index) => {
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
        
        // Legacy single-badge support (for backwards compatibility)
        // Only show badges for Lead, Contact, User, Account, Opportunity
        const allowedTypes = ['contact', 'lead', 'user', 'account', 'opportunity'];
        let linkedBadgeLabel = null;
        let linkedBadgeClass = 'badge linked';
        let linkedRecordUrl = null;
        const recordType = (task.linkedRecordType || '').toLowerCase();
        
        // Only show badge if it's an allowed type
        if (task.linkedRecordName && allowedTypes.includes(recordType)) {
            linkedBadgeLabel = task.linkedRecordName;
            // Set badge class based on record type
            if (recordType === 'contact') {
                linkedBadgeClass = 'badge linked-contact';
            } else if (recordType === 'lead') {
                linkedBadgeClass = 'badge linked-lead';
            } else if (recordType === 'user') {
                linkedBadgeClass = 'badge linked-user';
            } else if (recordType === 'account') {
                linkedBadgeClass = 'badge linked-account';
            } else if (recordType === 'opportunity') {
                linkedBadgeClass = 'badge linked-opportunity';
            }
            // Build URL to the record
            if (task.linkedRecordId) {
                linkedRecordUrl = '/' + task.linkedRecordId;
            }
        }

        return {
            ...task,
            selected: false,
            isImported: isImported,
            initials: initials,
            avatarStyle: avatarStyle,
            rowClass: rowClass,
            formattedDueDate: formattedDueDate,
            hasDueDate: !!task.dueDateTime,
            isOverdue: isOverdue,
            dueDateClass: dueDateClass,
            priorityClass: priorityClass,
            isHighPriority: task.importance === 'high',
            compositeId: task.listId + '::' + task.taskId,
            linkedRecordsFormatted: linkedRecordsFormatted,
            hasMultipleLinkedRecords: linkedRecordsFormatted.length > 0,
            linkedBadgeLabel: linkedBadgeLabel,
            linkedBadgeClass: linkedBadgeClass,
            linkedRecordUrl: linkedRecordUrl,
            linkedRecordType: task.linkedRecordType
        };
    }

    getInitials(title) {
        if (!title) return '?';
        // NO REGEX - simple split by space and filter empty
        const words = title.trim().split(' ').filter(w => w.length > 0);
        if (words.length >= 2) {
            return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
        }
        return title.substring(0, 2).toUpperCase();
    }

    getAvatarGradient(title) {
        let hash = 0;
        for (let i = 0; i < (title || '').length; i++) {
            hash = title.charCodeAt(i) + ((hash << 5) - hash);
        }
        return this.gradients[Math.abs(hash) % this.gradients.length];
    }

    handleFilterChange(event) {
        this.selectedFilter = event.currentTarget.dataset.filter;
        this.resetPagination();
        this.loadTasks();
    }

    handleListChange(event) {
        this.selectedList = event.target.value;
        this.resetPagination();
        this.loadTasks();
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
    }

    handleRefresh() {
        this.resetPagination();
        if (this.isTaskAccessible) {
            this.loadTasks();
        } else {
            this.checkAccess();
        }
    }
    
    /**
     * Handle retry connection button click
     * Attempts to refresh token and check access again
     */
    handleRetryConnection() {
        this.checkAccess();
    }

    /**
     * Handle checkbox click directly
     * Stops propagation to prevent double-toggle from row click
     */
    handleCheckboxClick(event) {
        event.stopPropagation();

        const taskId = event.target.dataset.taskId;
        const isChecked = event.target.checked;

        // Don't allow selection of imported tasks
        if (event.target.disabled) {
            event.target.checked = false;
            return;
        }

        this.updateTaskSelection(taskId, isChecked);
    }

    handleRowClick(event) {
        // Don't toggle if clicking checkbox (handled by handleCheckboxClick)
        if (event.target.type === 'checkbox') {
            return;
        }

        const taskId = event.currentTarget.dataset.taskId;
        const checkbox = event.currentTarget.querySelector('input[type="checkbox"]');

        // Don't toggle if already imported
        if (checkbox && checkbox.disabled) {
            return;
        }

        // Toggle checkbox state
        const newCheckedState = !checkbox.checked;
        checkbox.checked = newCheckedState;

        this.updateTaskSelection(taskId, newCheckedState);
    }

    /**
     * Common method to update task selection state
     * Maintains persistent selection across pages
     */
    updateTaskSelection(taskId, isSelected) {
        // Find the task to get its compositeId
        const task = this.tasks.find(t => t.taskId === taskId);
        
        // Update persistent selection Map
        if (isSelected && task) {
            this.selectedTasksMap.set(taskId, {
                compositeId: task.compositeId,
                taskId: taskId
            });
        } else {
            this.selectedTasksMap.delete(taskId);
        }
        
        // Update current page display
        this.tasks = this.tasks.map(t => {
            if (t.taskId === taskId) {
                return { ...t, selected: isSelected };
            }
            return t;
        });
    }

    handleClearSelection() {
        // Clear persistent selection Map
        this.selectedTasksMap.clear();
        // Clear current page display
        this.tasks = this.tasks.map(task => ({ ...task, selected: false }));
    }

    handleLogoError(event) {
        event.target.style.display = 'none';
    }

    handleViewRecord(event) {
        event.preventDefault();
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordId;
        if (recordId) {
            // Generate URL and open in new tab
            this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    actionName: 'view'
                }
            }).then(url => {
                window.open(url, '_blank');
            });
        }
    }
    
    handleBadgeClick(event) {
        event.stopPropagation(); // Prevent row selection
        
        const recordId = event.currentTarget.dataset.recordId;
        const recordType = event.currentTarget.dataset.recordType;
        
        if (!recordId) {
            return;
        }

        // Generate URL and open in new tab
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: recordType,
                actionName: 'view'
            }
        }).then(url => {
            window.open(url, '_blank');
        });
    }

    async handleImportSelected() {
        // Use the persistent Map for all selected tasks across pages
        if (this.selectedTasksMap.size === 0) {
            this.showToastMessage('No tasks selected for import', 'warning');
            return;
        }
        
        // Check 20-task limit for manual selection
        const MAX_TASKS = 20;
        if (this.selectedTasksMap.size > MAX_TASKS) {
            this.showToastMessage(
                `Please select ${MAX_TASKS} or fewer tasks per import. You have ${this.selectedTasksMap.size} selected. You can run multiple imports if needed.`,
                'warning'
            );
            return;
        }
        
        // Check permissions before proceeding
        try {
            const permResult = await checkTaskSyncPermissions();
            if (!permResult.hasAccess) {
                this.showToastMessage(permResult.errorMessage, 'error');
                return;
            }
        } catch (err) {
            console.error('Error checking permissions:', err);
            // Continue anyway - permission check is informational
        }
        
        // Get the selected tasks for the modal
        const selectedTaskIds = Array.from(this.selectedTasksMap.keys());
        const selectedTasks = this.tasks.filter(task => selectedTaskIds.includes(task.taskId));
        
        // Prepare modal items from selected tasks
        // The modal expects: id, messageId, subject, fromName, bodyPreview
        // For tasks, use the connected user's email for smart matching
        this.modalItems = selectedTasks.map(task => {
            const taskData = this.selectedTasksMap.get(task.taskId);
            return {
                id: task.taskId,
                messageId: taskData.compositeId, // Use compositeId for the import call (format: listId::taskId)
                subject: task.title || '(No Title)',
                fromName: task.listName || 'Task',
                bodyPreview: task.bodyPreview || task.notes || '',
                receivedDateTime: task.dueDate,
                assignedToEmail: this.userEmail, // Connected user's email for smart matching
                assignedToName: '', // Name not available for tasks
                // Include additional task data for debugging
                _taskData: {
                    taskId: task.taskId,
                    listId: task.listId,
                    compositeId: taskData.compositeId
                }
            };
        });
        
        this.showQuickMatchModal = true;
    }

    handleModalSuccess(event) {
        const { count, excludedCount, duplicateCount } = event.detail;
        
        // Build message based on results
        let message = '';
        let variant = 'success';
        
        if (count > 0) {
            // Some tasks were imported successfully
            message = `${count} task(s) imported successfully! Check the bell icon (🔔) for details.`;
        } else if (excludedCount > 0) {
            // No imports, but some were excluded
            message = `${excludedCount} task(s) excluded by exclusion rules. No tasks imported.`;
            variant = 'info';
        } else if (duplicateCount > 0) {
            // No imports, but some were duplicates
            message = `${duplicateCount} task(s) already imported (duplicates). No new tasks imported.`;
            variant = 'info';
        } else {
            // No imports and no exclusions/duplicates
            message = '0 task(s) imported.';
            variant = 'warning';
        }
        
        this.showToastMessage(message, variant);
        this.showQuickMatchModal = false;
        this.loadTasks();
        this.handleClearSelection();
        this.dispatchEvent(new CustomEvent('tasksimported', {
            detail: { count: count }
        }));
    }

    handleCloseModal() {
        this.showQuickMatchModal = false;
        this.modalItems = [];
    }

    handleModalError(event) {
        const errorMessage = event.detail?.message || 'An error occurred';
        this.showToastMessage(errorMessage, 'error');
        this.showQuickMatchModal = false;
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


    get hasTasks() {
        return this.tasks && this.tasks.length > 0;
    }

    get filteredTasks() {
        if (!this.tasks) return [];
        if (!this.searchKey) return this.tasks;
        const searchLower = this.searchKey.toLowerCase();
        return this.tasks.filter(task =>
            (task.title && task.title.toLowerCase().includes(searchLower)) ||
            (task.listName && task.listName.toLowerCase().includes(searchLower))
        );
    }

    get hasSelection() {
        // Check persistent Map for any selections across all pages
        return this.selectedTasksMap.size > 0;
    }

    get selectedCount() {
        // Return count from persistent Map (includes selections from all pages)
        return this.selectedTasksMap.size;
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
    get pendingFilterClass() {
        return this.selectedFilter === 'pending' ? 'active' : '';
    }

    get allFilterClass() {
        return this.selectedFilter === 'all' ? 'active' : '';
    }

    get completedFilterClass() {
        return this.selectedFilter === 'completed' ? 'active' : '';
    }

    get listOptions() {
        const options = [{ label: 'All Lists', value: 'all' }];
        if (this.taskLists) {
            for (const list of this.taskLists) {
                options.push({ label: list.displayName, value: list.listId });
            }
        }
        return options;
    }

    get notAccessibleMessage() {
        if (this.selectedProvider === 'GOOGLE_TASKS') {
            return 'Google Tasks access is not available. Please ensure the tasks.readonly scope is granted in your Google OAuth configuration.';
        }
        return 'Microsoft To-Do access is not available. Please ensure the Tasks.Read permission is granted in your Microsoft 365 / Azure AD configuration.';
    }

    // Provider switch getters
    get googleSwitchClass() {
        return 'provider-btn' + (this.selectedProvider === 'GOOGLE_TASKS' ? ' active' : '');
    }

    get outlookSwitchClass() {
        return 'provider-btn' + (this.selectedProvider === 'MICROSOFT_GRAPH' ? ' active' : '');
    }

    get showProviderSwitch() {
        // Show provider switch only when BOTH providers are enabled in org settings
        return this.providerSettings.bothEnabled;
    }
    
    get showNoProviderMessage() {
        return this.providerSettings.neitherEnabled;
    }

    get taskTitle() {
        return this.userEmail || (this.selectedProvider === 'GOOGLE_TASKS' ? 'Google Tasks' : 'Outlook Tasks');
    }
    
    get providerName() {
        return this.selectedProvider === 'GOOGLE_TASKS' ? 'Google Tasks' : 'Microsoft To-Do';
    }
    
    /**
     * Get the provider type for the modal/Apex calls
     * Maps UI provider names to Apex-expected provider names
     */
    get modalProviderType() {
        // MICROSOFT_GRAPH is used for UI/API calls, but Apex expects MICROSOFT_TASKS for task imports
        if (this.selectedProvider === 'MICROSOFT_GRAPH') {
            return 'MICROSOFT_TASKS';
        }
        return this.selectedProvider; // GOOGLE_TASKS stays as is
    }

    handleProviderSwitch(event) {
        const provider = event.currentTarget.dataset.provider;
        if (provider && provider !== this.selectedProvider) {
            this.selectedProvider = provider;
            this.tasks = [];
            this.taskLists = [];
            this.userEmail = ''; // Clear the email when switching providers
            this.resetPagination();
            // Always call checkAccess - it will handle both providers appropriately
            this.checkAccess();
        }
    }
    
    /**
     * Handle previous page
     */
    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.loadTasks();
        }
    }

    /**
     * Handle next page
     */
    handleNextPage() {
        if (!this.isLastPage) {
            this.currentPage++;
            this.loadTasks();
        }
    }
    
    /**
     * Get the starting task number for the current page (1-indexed)
     */
    get pageStart() {
        if (this.tasks.length === 0) return 0;
        return (this.currentPage - 1) * this.pageSize + 1;
    }

    /**
     * Get the ending task number for the current page
     */
    get pageEnd() {
        if (this.tasks.length === 0) return 0;
        return this.pageStart + this.tasks.length - 1;
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
        // No tasks loaded means we're at the last page
        if (this.tasks.length === 0) return true;

        // If we have fewer tasks than page size, it's definitely the last page
        if (this.tasks.length < this.pageSize) return true;

        // If hasMoreTasks is false, this is the last page
        if (!this.hasMoreTasks) return true;

        return false;
    }

    /**
     * Get the count of tasks on the current page
     */
    get currentPageTaskCount() {
        return this.tasks ? this.tasks.length : 0;
    }

    /**
     * Get display text for total tasks (with "+" for estimates)
     */
    get totalTasksDisplay() {
        if (this.hasMoreTasks) {
            return this.cumulativeTaskCount + '+';
        }
        return this.cumulativeTaskCount;
    }

    /**
     * Check if Previous button should be disabled
     */
    get isPreviousDisabled() {
        return this.isFirstPage;
    }

    /**
     * Check if Next button should be disabled
     * Disabled when on last page OR when there are fewer tasks than page size
     */
    get isNextDisabled() {
        // Disable if on last page
        if (this.isLastPage) return true;
        
        // Disable if no more tasks to fetch and we have fewer than page size
        if (!this.hasMoreTasks && this.tasks.length < this.pageSize) return true;
        
        return false;
    }
}