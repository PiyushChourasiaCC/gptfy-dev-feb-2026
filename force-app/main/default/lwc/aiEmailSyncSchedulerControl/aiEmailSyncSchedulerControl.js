import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import WS_SYNC_LOG_OBJECT from '@salesforce/schema/AI_Workspace_Sync_Log__c';
import PROVIDER_TYPE_FIELD from '@salesforce/schema/AI_Workspace_Sync_Log__c.Provider_Type__c';

import getSchedulerStatus from '@salesforce/apex/AIEmailSyncSchedulerController.getSchedulerStatus';
import getRecentSyncLogs from '@salesforce/apex/AIEmailSyncSchedulerController.getRecentSyncLogs';
import startScheduler from '@salesforce/apex/AIEmailSyncSchedulerController.startScheduler';
import stopScheduler from '@salesforce/apex/AIEmailSyncSchedulerController.stopScheduler';
import runSyncNow from '@salesforce/apex/AIEmailSyncSchedulerController.runSyncNow';
import getSyncJobStatus from '@salesforce/apex/AIEmailSyncSchedulerController.getSyncJobStatus';
import isAdminUser from '@salesforce/apex/GPTfyConsoleController.isAdminUser';
import getProviderSettings from '@salesforce/apex/AISyncSettingsService.getProviderSettings';
import checkSchedulerPermissions from '@salesforce/apex/AIWorkspacePermissionService.checkSchedulerPermissions';

export default class aiEmailSyncSchedulerControl extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track error;
    @track isAdmin = false;

    // Provider settings
    @track providerSettings = {
        outlookEnabled: false,
        gmailEnabled: false,
        bothEnabled: false,
        neitherEnabled: true,
        singleProvider: null
    };

    // Scheduler status
    @track isRunning = false;
    @track syncEnabled = false;
    @track calendarSyncEnabled = false;
    @track taskSyncEnabled = false;
    @track frequencyMinutes = 60;
    @track nextRunTime;
    @track lastRunTime;
    @track jobState;

    // Sync logs
    @track syncLogs = [];
    @track logsLoading = false;

    // Provider Type picklist values map
    providerTypeLabels = {};

    // Wire adapter to get Provider Type picklist values
    @wire(getPicklistValues, { recordTypeId: '012000000000000AAA', fieldApiName: PROVIDER_TYPE_FIELD })
    wiredProviderTypePicklist({ error, data }) {
        if (data) {
            // Create a map of value -> label
            data.values.forEach(item => {
                this.providerTypeLabels[item.value] = item.label;
            });
        } else if (error) {
            console.error('Error loading Provider Type picklist:', error);
        }
    }

    // Sync log table columns (using wrapper field names for namespace compatibility)
    logColumns = [
        {
            label: 'Date',
            fieldName: 'createdDate',
            type: 'date',
            typeAttributes: {
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            },
            sortable: true
        },
        {
            label: 'User',
            fieldName: 'userName',
            type: 'text'
        },
        {
            label: 'Status',
            fieldName: 'status',
            type: 'text',
            cellAttributes: {
                class: { fieldName: 'statusClass' }
            }
        },
        {
            label: 'Provider Type',
            fieldName: 'providerType',
            type: 'text'
        },
        {
            label: 'Fetched',
            fieldName: 'emailsFetched',
            type: 'number'
        },
        {
            label: 'Staged',
            fieldName: 'emailsMatched',
            type: 'number'
        },
        {
            label: 'Duplicate',
            fieldName: 'emailsDuplicate',
            type: 'number'
        },
        {
            label: 'Excluded',
            fieldName: 'emailsExcluded',
            type: 'number'
        },
        {
            label: 'Time (s)',
            fieldName: 'processingTimeSeconds',
            type: 'number'
        },
        {
            label: '',
            type: 'button-icon',
            fixedWidth: 60,
            typeAttributes: {
                iconName: 'utility:preview',
                title: 'View Details',
                variant: 'bare',
                alternativeText: 'View'
            }
        }
    ];

    connectedCallback() {
        this.checkAdminAccess();
        this.loadProviderSettings();
        this.loadStatus();
        this.loadSyncLogs();
    }

    async checkAdminAccess() {
        try {
            this.isAdmin = await isAdminUser();
        } catch (err) {
            this.isAdmin = false;
        }
    }

    async loadProviderSettings() {
        try {
            const settings = await getProviderSettings();
            this.providerSettings = settings;
        } catch (err) {
            console.error('Error loading provider settings:', err);
            // Default to neitherEnabled = true if we can't load settings
            this.providerSettings.neitherEnabled = true;
        }
    }

    async loadStatus() {
        this.isLoading = true;
        this.error = null;

        try {
            const result = await getSchedulerStatus();

            if (result.success) {
                this.isRunning = result.isRunning;
                this.syncEnabled = result.syncEnabled;
                this.calendarSyncEnabled = result.calendarSyncEnabled;
                this.taskSyncEnabled = result.taskSyncEnabled;
                this.frequencyMinutes = result.frequencyMinutes;
                this.nextRunTime = result.nextRunTime;
                this.lastRunTime = result.lastRunTime;
                this.jobState = result.state;
            } else {
                this.error = result.error;
            }
        } catch (err) {
            this.error = err.body?.message || err.message || 'Failed to load status';
        } finally {
            this.isLoading = false;
        }
    }

    async loadSyncLogs() {
        this.logsLoading = true;
        try {
            const logs = await getRecentSyncLogs({ limitCount: 20 });
            // Wrapper already provides userName, just add statusClass and format providerType
            this.syncLogs = logs.map(log => ({
                ...log,
                userName: log.userName || 'Unknown',
                statusClass: log.status === 'Completed' ? 'slds-text-color_success' :
                            log.status === 'Failed' ? 'slds-text-color_error' : '',
                providerType: this.formatProviderType(log.providerType)
            }));
        } catch (err) {
            // Error logged silently - UI will show empty state
        } finally {
            this.logsLoading = false;
        }
    }

    handleRowAction(event) {
        const row = event.detail.row;
        // Generate URL and open in new tab
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.Id,
                objectApiName: WS_SYNC_LOG_OBJECT.objectApiName,
                actionName: 'view'
            }
        }).then(url => {
            window.open(url, '_blank');
        });
    }

    async handleStart() {
        this.isLoading = true;

        try {
            // Check permissions before starting scheduler
            const permResult = await checkSchedulerPermissions();
            if (!permResult.hasAccess) {
                this.showToast('Insufficient Permissions', permResult.errorMessage, 'error');
                this.isLoading = false;
                return;
            }
            
            const result = await startScheduler();

            if (result.success) {
                this.updateFromResult(result);
                this.showToast('Success', 'Workspace sync scheduler started', 'success');
            } else if (result.type === 'warning') {
                // Show warning toast for configuration issues
                this.showToast('Warning', result.message, 'warning');
            } else {
                throw new Error(result.error);
            }
        } catch (err) {
            this.showToast('Error', err.body?.message || err.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleStop() {
        this.isLoading = true;

        try {
            const result = await stopScheduler();

            if (result.success) {
                this.updateFromResult(result);
                this.showToast('Success', 'Workspace sync scheduler stopped', 'success');
            } else {
                throw new Error(result.error);
            }
        } catch (err) {
            this.showToast('Error', err.body?.message || err.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRunNow() {
        // Immediately disable button to prevent double-clicks
        this.isLoading = true;

        try {
            // Check permissions before running sync
            const permResult = await checkSchedulerPermissions();
            if (!permResult.hasAccess) {
                this.showToast('Insufficient Permissions', permResult.errorMessage, 'error');
                this.isLoading = false;
                return;
            }
            
            // First check job status to provide immediate feedback
            const jobStatus = await getSyncJobStatus();
            
            // If scheduler is active and a job is running, tell user to stop scheduler
            if (jobStatus.isSchedulerActive && jobStatus.isRunning) {
                const message = `The scheduler is currently running a sync job${jobStatus.createdByName ? ' (started by ' + jobStatus.createdByName + ')' : ''}. Please stop the scheduler first, wait for the current job to finish, then use Run Now.`;
                this.showToast('Scheduler Active', message, 'warning');
                this.isLoading = false;
                return;
            }
            
            // If any job is running (from any source), show warning
            if (jobStatus.isRunning) {
                const jobInfo = jobStatus.jobId ? ` (Job ID: ${jobStatus.jobId.substring(0, 15)})` : '';
                const userInfo = jobStatus.createdByName ? ` started by ${jobStatus.createdByName}` : '';
                const message = `A sync job${userInfo} is already in progress${jobInfo}. Please wait until it finishes.`;
                this.showToast('Job In Progress', message, 'info');
                this.isLoading = false;
                return;
            }
            
            // No job running - proceed with Run Now
            const result = await runSyncNow();

            if (result.success) {
                this.showToast('Success', result.message || 'Sync started', 'success');
                // Refresh logs after a moment
                setTimeout(() => {
                    this.loadStatus();
                    this.loadSyncLogs();
                }, 3000);
            } else if (result.type === 'warning') {
                // Show info toast for configuration issues or job already running
                this.showToast('Info', result.message, 'info');
            } else {
                throw new Error(result.error);
            }
        } catch (err) {
            this.showToast('Error', err.body?.message || err.message, 'error');
        } finally {
            // Re-enable button after response
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.loadProviderSettings();
        this.loadStatus();
        this.loadSyncLogs();
    }

    handleRefreshLogs() {
        this.loadSyncLogs();
    }

    handleNavigateToSettings() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Workspace_Sync'
            }
        });
    }

    handleViewAllLogs() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: WS_SYNC_LOG_OBJECT.objectApiName,
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });
    }

    updateFromResult(result) {
        this.isRunning = result.isRunning;
        this.syncEnabled = result.syncEnabled;
        this.calendarSyncEnabled = result.calendarSyncEnabled;
        this.taskSyncEnabled = result.taskSyncEnabled;
        this.frequencyMinutes = result.frequencyMinutes;
        this.nextRunTime = result.nextRunTime;
        this.lastRunTime = result.lastRunTime;
        this.jobState = result.state;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }

    // Computed properties
    get statusLabel() {
        return this.isRunning ? 'Running' : 'Stopped';
    }

    get statusVariant() {
        return this.isRunning ? 'success' : 'warning';
    }

    get formattedNextRun() {
        if (!this.nextRunTime) return 'Not scheduled';
        return this.formatDateTime(this.nextRunTime);
    }

    get formattedLastRun() {
        if (!this.lastRunTime) return 'Never';
        return this.formatDateTime(this.lastRunTime);
    }

    get frequencyLabel() {
        if (!this.frequencyMinutes) return 'Not configured';
        if (this.frequencyMinutes < 60) {
            return `Every ${this.frequencyMinutes} minutes`;
        } else if (this.frequencyMinutes === 60) {
            return 'Every hour';
        } else {
            const hours = Math.floor(this.frequencyMinutes / 60);
            return `Every ${hours} hour${hours > 1 ? 's' : ''}`;
        }
    }

    get showStartButton() {
        return !this.isRunning && this.isAdmin;
    }

    get showStopButton() {
        return this.isRunning && this.isAdmin;
    }

    get showContent() {
        return !this.isLoading && !this.providerSettings.neitherEnabled;
    }

    get showNoProviderMessage() {
        return !this.isLoading && this.providerSettings.neitherEnabled;
    }

    get syncEnabledLabel() {
        return this.syncEnabled ? 'Enabled' : 'Disabled';
    }

    get syncEnabledVariant() {
        return this.syncEnabled ? 'success' : 'light';
    }

    get statusBadgeClass() {
        return this.isRunning ? 'slds-badge_success' : 'slds-badge_warning';
    }

    get syncEnabledBadgeClass() {
        return this.syncEnabled ? 'slds-badge_success' : 'slds-badge_lightest';
    }

    // Negated getters for template
    get notCalendarSyncEnabled() {
        return !this.calendarSyncEnabled;
    }

    get notTaskSyncEnabled() {
        return !this.taskSyncEnabled;
    }

    get hasLogs() {
        return this.syncLogs && this.syncLogs.length > 0;
    }

    get logCount() {
        return this.syncLogs ? this.syncLogs.length : 0;
    }

    get notSyncEnabled() {
        return !this.syncEnabled;
    }

    get noLogs() {
        return !this.hasLogs;
    }

    get notLogsLoading() {
        return !this.logsLoading;
    }

    get noNextRunTime() {
        return !this.nextRunTime;
    }

    get noLastRunTime() {
        return !this.lastRunTime;
    }

    formatDateTime(dateTimeStr) {
        if (!dateTimeStr) return '';
        const dt = new Date(dateTimeStr);
        return dt.toLocaleString('en-US', {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
    }

    formatProviderType(providerType) {
        if (!providerType) return '';
        
        // Use the dynamically loaded picklist labels
        return this.providerTypeLabels[providerType] || providerType;
    }
}