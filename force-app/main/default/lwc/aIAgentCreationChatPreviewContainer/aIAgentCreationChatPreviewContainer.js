import { LightningElement, track, wire, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import fetchAgents from '@salesforce/apex/AIAgenticChatController.fetchAgents';
import fetchDefaultAgent from '@salesforce/apex/AIAgenticChatController.fetchDefaultAgent';

export default class AIAgentCreationChatPreviewContainer extends LightningElement {
    @api aiResponseName;
    @api defaultAgentId;

    @track currentRecordId;
    @track currentObjectApiName;
    @track open = false; 
    @track selectedAgent = '';
    @track tempSelectedAgent = '';
    @track availableHeight = 600;
    @track agents = [];
    @track agentInfo = {};
    @track showSpinner = false;
    @track hasMultipleAgents = false;
    aiResponse = '';

    @wire(CurrentPageReference) 
    wiredPageRef(pageRef) {
        if (pageRef) {
            const recordIdOfCurrentPage = pageRef.attributes?.recordId || null;
            this.currentRecordId = recordIdOfCurrentPage;
            const objectNameOfCurrentPage = pageRef.attributes?.objectApiName || null;
            this.currentObjectApiName = objectNameOfCurrentPage;
        }
    }

    connectedCallback() {
        console.log('AIAgentCreationChatPreview - connectedCallback');
        console.log('defaultAgentId:', this.defaultAgentId);
        this.showSpinner = true;
        this.calculateAvailableHeight();
        if (this.defaultAgentId && this.defaultAgentId != null && this.defaultAgentId != '') {
            console.log('Fetching default agent with ID:', this.defaultAgentId);
            this.fetchDefaultAgent();
        } else {
            console.log('No defaultAgentId provided, fetching accessible agents');
            this.fetchAccessibleAgent();
        }
    }

    async fetchDefaultAgent() {
        try {
            console.log('Calling fetchDefaultAgent Apex with ID:', this.defaultAgentId);
            let response = await fetchDefaultAgent({ defaultAgentId: this.defaultAgentId });
            console.log('fetchDefaultAgent response:', response);
            if (response) {
                this.agents = JSON.parse(JSON.stringify([response]));
                this.selectedAgent = response.label.length > 30 ? response.label.substring(0, 30) + '...' : response.label;
                this.agentInfo = response;
                this.hasMultipleAgents = false;
                this.showSpinner = false;
                console.log('Agent loaded successfully:', this.selectedAgent);
            } else {
                console.warn('No agent response received');
                this.showToast('error', 'Error', 'No Active Agent Found!', 'dismissable');
                this.showSpinner = false;
            }
        } catch (error) {
            console.error('Error fetching default agent:', error);
            console.error('Error details:', error.body?.message || error.message);
            this.showSpinner = false;
        }
    }

    async fetchAccessibleAgent() {
        try {
            console.log('Calling fetchAgents Apex');
            let response = await fetchAgents();
            console.log('fetchAgents response:', response);
            if (response && response.length > 1) {
                this.agents = JSON.parse(JSON.stringify(response));
                this.selectedAgent = this.agents[0].label.length > 30 ? this.agents[0].label.substring(0, 30) + '...' : this.agents[0].label;
                this.agents[0].selected = true;
                this.agentInfo = this.agents[0];
                this.hasMultipleAgents = true;
                console.log('Multiple agents loaded, selected:', this.selectedAgent);
            } else if (response && response.length === 1) {
                this.selectedAgent = response[0].label.length > 30 ? response[0].label.substring(0, 30) + '...' : response[0].label; 
                this.agentInfo = JSON.parse(JSON.stringify(response))[0];
                this.hasMultipleAgents = false;
                console.log('Single agent loaded:', this.selectedAgent);
            } else {
                console.warn('No agents found in response');
                this.showToast('error', 'Error', 'No Active Agent Found!', 'dismissable');
            }
            this.showSpinner = false;
        } catch (error) {
            this.showSpinner = false;
            console.error('Error fetching agents:', error);
            console.error('Error details:', error.body?.message || error.message);
        }
    }

    calculateAvailableHeight() {
        try {
            // Set a fixed height suitable for the embedded panel
            // Account for header height (~60px) to get proper chat body height
            this.availableHeight = 640;
        } catch (error) {
            console.error('Error calculating height:', error);
            this.availableHeight = 640; // Fallback
        }
    }

    closeChat() {
        this.dispatchEvent(new CustomEvent('closechat'));
    }

    endChat() {
        let chatComp = this.template.querySelector('[data-id="agentic-chat"]');
        chatComp && chatComp.endChat();
    }

    handleSelect(event) {
        let chatComp = this.template.querySelector('[data-id="agentic-chat"]');
        chatComp && chatComp.clearThreadId();

        let tempAgents = JSON.parse(JSON.stringify(this.agents));
        let tempObj = tempAgents.findIndex(obj => obj.label === this.tempSelectedAgent);
        this.selectedAgent = this.tempSelectedAgent.length > 30 ? this.tempSelectedAgent.substring(0, 30) + '...' : this.tempSelectedAgent;
        this.agentInfo = this.agents[tempObj];
        this.open = false;
    }

    handleSelection(event) {
        let tempAgents = JSON.parse(JSON.stringify(this.agents));
        let tempObj = tempAgents.findIndex(obj => obj.value === event.target.value);
        tempAgents.forEach(item => {
            item.selected = false;
        });
        tempAgents[tempObj].selected = true; 
        this.agents = tempAgents;
        this.tempSelectedAgent = event.target.name;
    }

    closeTooltip() {
        this.open = false;
    }

    toggleDropdown(event) {
        this.open = !this.open;
    }

    handleOverlayClick() {
        this.open = false;
    }

    showToast(variant, title, message, mode) {
        const event = new ShowToastEvent({
            title: title,
            variant: variant,
            message: message,
            mode: mode
        });
        this.dispatchEvent(event);
    }

    handleChangeAgent(evt) {
        let agentName = evt.detail?.agentName;
        if (agentName) {
            let tempAgents = JSON.parse(JSON.stringify(this.agents));
            let tempObj = tempAgents.findIndex(obj => obj.label === agentName);
            if (tempObj === -1) {
                this.showToast('error', 'Error', 'The selected chat does not belong to the agent assigned to you', 'dismissable');
                let chatComp = this.template.querySelector('[data-id="agentic-chat"]');
                chatComp && chatComp.handleNewButton();
            } else {
                tempAgents.forEach(item => {
                    item.selected = false;
                });
                tempAgents[tempObj].selected = true; 
                this.agents = tempAgents;
                this.tempSelectedAgent = agentName;
                
                let chatComp = this.template.querySelector('[data-id="agentic-chat"]');
                chatComp && chatComp.clearThreadId();

                this.selectedAgent = this.tempSelectedAgent.length > 30 ? this.tempSelectedAgent.substring(0, 30) + '...' : this.tempSelectedAgent;
                this.agentInfo = {...this.agents[tempObj], threadId: evt.detail.threadId};
                this.open = false;
            }
        }
    }

    /**
     * Public API method to refresh the agent data
     * Called by parent component after save/update operations
     */
    @api
    async refreshAgent() {
        try {
            this.showSpinner = true;
            if (this.defaultAgentId && this.defaultAgentId != null && this.defaultAgentId != '') {
                await this.fetchDefaultAgent();
            } else {
                await this.fetchAccessibleAgent();
            }
        } catch (error) {
            console.error('Error refreshing agent:', error);
        } finally {
            this.showSpinner = false;
        }
    }
}