import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDetails from '@salesforce/apex/AICockpitController.getDetails';

// Import Schema References
import AI_PROMPT_OBJECT from '@salesforce/schema/AI_Prompt__c';
import AI_RAG_SYNC_OBJECT from '@salesforce/schema/AI_RAG_Sync__c';
import AI_DATA_EXTRACTION_MAPPING_OBJECT from '@salesforce/schema/AI_Data_Extraction_Mapping__c';
import AI_MASS_PROCESS_OBJECT from '@salesforce/schema/AI_Scheduler__c';
import AI_RESPONSE_OBJECT from '@salesforce/schema/AI_Response__c';
import AI_SECURITY_FILTERS_OBJECT from '@salesforce/schema/AI_Security_Filters__c';

export default class CockpitComponent extends NavigationMixin(LightningElement) {

    @track showSpinner = false;
    @track timeSaved = '0h';
    @track moneySaved = '0';
    @track activePrompts = 0;
    @track namespace = '';
    @track incompleteSetup = false;
    @track activeTab = 'analytics';
    
    // Analytics section metrics
    @track promptsDeployed = '0 Prompts Deployed';
    //@track roiSavings = 0;
    @track aiInsightsUsers = '0 Active Users';
    @track qualityFeedbacks = '0 Feedbacks';
    
    // Agentic section metrics
    @track agentsMetric = '0 Active Agents';
    @track promptCatalogMetric = '0 Prompts Deployed';
    @track skillsPromptsMetric = '0 Active Prompts';
    @track ragKnowledgeMetric = '0 Sources';
    @track dataContextMappingMetric = '0 Deployed';
    
    // Workspace Sync section metrics
    @track workspaceSyncMetric = 'Manage Workspace Sync';
    @track emailSyncMetric = 'Manage Email Sync';
    @track calendarSyncMetric = 'Manage Calendar Sync';
    @track taskSyncMetric = 'Manage Tasks Sync';
    @track workspaceSyncSchedulerMetric = 'Manage Scheduler and Logs';
    
    // Advanced section metrics
    @track apiDataSourcesMetric = '0 Active';
    @track aiModelsMetric = '0 Active';
    @track aiSettingsMetric = 'Setup Retention';
    @track securityAuditsMetric = '0 Audit Records';
    @track securityLayersMetric = '3 Layers Enforced';
    @track massProcessingMetric = '0 Jobs Scheduled';

    get setupWizardUrl(){
        return '/lightning/n/'+this.namespace+'Setup';
    }

    connectedCallback(){
        this.loadCockpitData();
    }

    loadCockpitData(){
        this.showSpinner = true;
        getDetails()
        .then(result => {
            if(result){
                // Check for incomplete setup
                this.incompleteSetup = result.incompleteSetup || false;
                
                // Convert seconds to hours and format
                const totalSeconds = result.timeSavedSeconds || 0;
                const hours = (totalSeconds / 3600).toFixed(2);
                this.timeSaved = hours + 'h';
                
                // Format money saved with currency symbol
                const money = result.moneySaved || 0;
                this.moneySaved = money;//this.formatNumber(money);
                
                // Set active prompts count
                this.activePrompts = result.activePrompts || 0;
                
                // Set namespace for navigation
                this.namespace = result.namespace || '';
                
                // Analytics section metrics
                this.promptsDeployed = (result.noOfPrompts || 0) + ' Prompts Deployed';
                //this.roiSavings = (result.totalSavings || 0);
                this.aiInsightsUsers = result.usageDetail || '0 Active Users';
                this.qualityFeedbacks = (result.noOfFeedbacks || 0) + ' Feedbacks';
                
                // Agentic section metrics
                this.agentsMetric = (result.noOfAgents || 0) + ' Active Agents';
                this.promptCatalogMetric = (result.noOfPrompts || 0) + ' Prompts Deployed';
                this.skillsPromptsMetric = (result.noOfPrompts || 0) + ' Active Prompts';
                this.ragKnowledgeMetric = (result.noOfRAGSyncs || 0) + ' Sources';
                this.dataContextMappingMetric = (result.noOfMappings || 0) + ' Deployed';
                
                // Advanced section metrics
                this.apiDataSourcesMetric = (result.noOfDataSources || 0) + ' Active';
                this.aiModelsMetric = (result.noOfModels || 0) + ' Active';
                this.aiSettingsMetric = result.retentionMetric || 'Setup Retention';
                this.securityAuditsMetric = (result.noOfResponses || 0) + ' Audit Records';
                this.securityLayersMetric = '3 Layers Enforced'; // Static for now
                this.massProcessingMetric = result.scheduledPrompts+' Jobs Scheduled'
            }
                    this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
            this.showSpinner = false;
        });
    }

    formatNumber(num) {
        if (num >= 1000000) {
            return (num / 1000000).toFixed(1) + 'M';
        } else if (num >= 1000) {
            return (num / 1000).toFixed(1) + 'K';
        }
        return num.toFixed(2);
    }

    // Tab scroll handlers
    handleScrollToAnalytics(event) {
        event.preventDefault();
        this.activeTab = 'analytics';
        this.scrollToSection('analytics-section');
    }

    handleScrollToAgentic(event) {
        event.preventDefault();
        this.activeTab = 'agentic';
        this.scrollToSection('agentic-section');
    }

    handleScrollToWorkspaceSync(event) {
        event.preventDefault();
        this.activeTab = 'workspaceSync';
        this.scrollToSection('workspace-sync-section');
    }

    handleScrollToAdvanced(event) {
        event.preventDefault();
        this.activeTab = 'advanced';
        this.scrollToSection('advanced-section');
    }

    // Helper method to check active tab
    isActiveTab(tabName) {
        return this.activeTab === tabName;
    }

    // Getters for tab classes and aria-selected
    get analyticsTabClass() {
        return this.activeTab === 'analytics' ? 'slds-tabs_default__item slds-is-active' : 'slds-tabs_default__item';
    }

    get agenticTabClass() {
        return this.activeTab === 'agentic' ? 'slds-tabs_default__item slds-is-active' : 'slds-tabs_default__item';
    }

    get workspaceSyncTabClass() {
        return this.activeTab === 'workspaceSync' ? 'slds-tabs_default__item slds-is-active' : 'slds-tabs_default__item';
    }

    get advancedTabClass() {
        return this.activeTab === 'advanced' ? 'slds-tabs_default__item slds-is-active' : 'slds-tabs_default__item';
    }

    get analyticsTabSelected() {
        return this.activeTab === 'analytics';
    }

    get agenticTabSelected() {
        return this.activeTab === 'agentic';
    }

    get workspaceSyncTabSelected() {
        return this.activeTab === 'workspaceSync';
    }

    get advancedTabSelected() {
        return this.activeTab === 'advanced';
    }

    scrollToSection(sectionId) {
        try {
            // Use requestAnimationFrame to ensure DOM is ready
            requestAnimationFrame(() => {
                const section = this.template.querySelector(`[data-id="${sectionId}"]`);
                const scrollableContainer = this.template.querySelector('.scrollable-content');
                
                if (section && scrollableContainer) {
                    // Get the position of the section relative to the scrollable container
                    const sectionTop = section.offsetTop;
                    const containerTop = scrollableContainer.offsetTop;
                    
                    // Calculate scroll position (section position relative to container)
                    const scrollPosition = sectionTop - containerTop - 20; // 20px offset for spacing
                    
                    // Scroll the scrollable container
                    // Check if scrollTo method exists, otherwise use custom smooth scroll
                    if (typeof scrollableContainer.scrollTo === 'function') {
                        scrollableContainer.scrollTo({
                            top: scrollPosition,
                            behavior: 'smooth'
                        });
                    } else {
                        // Fallback: Custom smooth scroll animation for environments where scrollTo is not available
                        this.smoothScrollTo(scrollableContainer, scrollPosition);
                    }
                } else {
                    if (!section) {
                        console.error('Section not found:', sectionId);
                    }
                    if (!scrollableContainer) {
                        console.error('Scrollable container not found');
                    }
                }
            });
        } catch (error) {
            console.error('Error scrolling to section:', error);
        }
    }

    /**
     * Custom smooth scroll implementation for fallback
     * @param {HTMLElement} element - The element to scroll
     * @param {number} targetPosition - The target scroll position
     * @param {number} duration - Animation duration in milliseconds
     */
    smoothScrollTo(element, targetPosition, duration = 400) {
        const startPosition = element.scrollTop;
        const distance = targetPosition - startPosition;
        let startTime = null;

        // Easing function for smooth animation (ease-in-out)
        const easeInOutQuad = (time, start, change, duration) => {
            time /= duration / 2;
            if (time < 1) return change / 2 * time * time + start;
            time--;
            return -change / 2 * (time * (time - 2) - 1) + start;
        };

        const animateScroll = (currentTime) => {
            if (startTime === null) startTime = currentTime;
            const timeElapsed = currentTime - startTime;
            const nextScrollPosition = easeInOutQuad(timeElapsed, startPosition, distance, duration);
            
            element.scrollTop = nextScrollPosition;
            
            if (timeElapsed < duration) {
                requestAnimationFrame(animateScroll);
            } else {
                // Ensure we end at exact target position
                element.scrollTop = targetPosition;
            }
        };

        requestAnimationFrame(animateScroll);
    }

    // Navigation handlers for Analytics tab
    handleROIDashboard() {
        this.navigateToTab('ROI_Dashboard');
    }

    handleAIInsightsDashboard() {
        this.navigateToTab('AI_Insights_Dashboard');
    }

    handleQualityInsights() {
        this.navigateToTab('Quality_Insights');
    }

    handleTrending() {
        this.navigateToTab('Trending');
    }

    // Navigation handlers for Agentic tab
    handleAgents() {
        this.navigateToTab('Agents');
    }

    handlePromptCatalog() {
        this.navigateToTab('Catalog');
    }

    handleSkillsPrompts() {
        this.navigateToListView(AI_PROMPT_OBJECT.objectApiName);
    }

    handleRAGKnowledgeBase() {
        this.navigateToListView(AI_RAG_SYNC_OBJECT.objectApiName);
    }

    handleDataContextMapping() {
        this.navigateToListView(AI_DATA_EXTRACTION_MAPPING_OBJECT.objectApiName);
    }

    // Navigation handlers for Workspace Sync tab
    handleWorkspaceAuthentication() {
        this.navigateToTab('Workspace_Authentication');
    }

    handleWorkspaceSync() {
        this.navigateToTab('AI_Workspace_Sync');
    }

    /*
    handleEmailSync() {
        this.navigateToTab('');
    }

    handleCalendarSync() {
        this.navigateToTab('');
    }

    handleTaskSync() {
        this.navigateToTab('');
    }
    */

    handleWorkspaceSyncScheduler() {
        this.navigateToTab('AI_Workspace_Sync_Scheduler');
    }

    // Navigation handlers for Advanced tab
    handleAPIDataSources() {
        this.navigateToTab('AI_Data_Source');
    }

    handleAIModels() {
        this.navigateToTab('Connections');
    }

    handleAISettings() {
        this.navigateToTab('AI_Settings');
    }

    handleSecurityAudits() {
        this.navigateToListView(AI_RESPONSE_OBJECT.objectApiName);
    }

    handleSecurityLayers() {
        this.navigateToListView(AI_SECURITY_FILTERS_OBJECT.objectApiName);
    }

    handleAIMassProcessing() {
        this.navigateToListView(AI_MASS_PROCESS_OBJECT.objectApiName);
    }

    // Helper methods for navigation
    navigateToTab(tabName) {
        window.open('/lightning/n/' + this.namespace + tabName, '_self');
    }

    navigateToListView(objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: objectApiName,
                actionName: 'list'
            }
        });
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    handleError(error){
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }
}