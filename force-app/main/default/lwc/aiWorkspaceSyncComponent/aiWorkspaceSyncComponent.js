import { LightningElement, track } from 'lwc';
import gptfyLogo from '@salesforce/resourceUrl/gptfylogo';

export default class AiWorkspaceSyncComponent extends LightningElement {
    @track activeView = 'email';
    @track showSettingsModal = false;
    @track emailProvider = 'MICROSOFT_GRAPH';
    @track taskProvider = 'MICROSOFT_GRAPH';
    @track calendarProvider = 'MICROSOFT_CALENDAR';

    connectedCallback() {
        // Default to email view on load
        this.activeView = 'email';
    }
    
    handleProviderChange(event) {
        const { provider, type } = event.detail;
        const oldEmailProvider = this.emailProvider;
        const oldTaskProvider = this.taskProvider;
        const oldCalendarProvider = this.calendarProvider;
        
        if (type === 'email') {
            this.emailProvider = provider;
        } else if (type === 'task') {
            this.taskProvider = provider;
        } else if (type === 'calendar') {
            this.calendarProvider = provider;
        }
        
        // Refresh the active component after provider change
        // Force re-render by toggling the view
        if ((type === 'email' && this.isEmailView && oldEmailProvider !== provider) ||
            (type === 'task' && this.isTaskView && oldTaskProvider !== provider) ||
            (type === 'calendar' && this.isCalendarView && oldCalendarProvider !== provider)) {
            this.refreshActiveView();
        }
    }
    
    refreshActiveView() {
        const currentView = this.activeView;
        // Temporarily set to null to force unmount
        this.activeView = null;
        // Use setTimeout to ensure component unmounts before remounting
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.activeView = currentView;
        }, 100);
    }

    handleEmailClick() {
        this.activeView = 'email';
    }

    handleTaskClick() {
        this.activeView = 'task';
    }

    handleCalendarClick() {
        this.activeView = 'calendar';
    }

    handleSettingsClick() {
        this.showSettingsModal = true;
        // Update the modal with current provider settings
        this.notifyModalOfCurrentProviders();
    }
    
    notifyModalOfCurrentProviders() {
        // This will be handled by passing the current providers as attributes
        // The modal will initialize with these values
    }

    handleCloseModal() {
        this.showSettingsModal = false;
    }

    handleModalBackdropClick(event) {
        if (event.target.classList.contains('modal-backdrop')) {
            this.handleCloseModal();
        }
    }

    get isEmailView() {
        return this.activeView === 'email';
    }

    get isTaskView() {
        return this.activeView === 'task';
    }

    get isCalendarView() {
        return this.activeView === 'calendar';
    }

    get emailButtonClass() {
        return this.activeView === 'email' ? 'nav-button active' : 'nav-button';
    }

    get taskButtonClass() {
        return this.activeView === 'task' ? 'nav-button active' : 'nav-button';
    }

    get calendarButtonClass() {
        return this.activeView === 'calendar' ? 'nav-button active' : 'nav-button';
    }

    get modalClass() {
        return this.showSettingsModal ? 'settings-modal active' : 'settings-modal';
    }

    get logoUrl() {
        return gptfyLogo;
    }
}