import { LightningElement, track , wire, api} from 'lwc';
import gptfylogo from '@salesforce/resourceUrl/GPTfy';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import { minimize, EnclosingUtilityId } from 'lightning/platformUtilityBarApi';
import fetchAgents from '@salesforce/apex/AIAgenticChatController.fetchAgents';
import getAISettings from '@salesforce/apex/AIAgenticChatController.getAISettings';

export default class RAIAgenticChatContainer extends LightningElement {
    @api aiResponseName;
    @api chatHeight = 600; // Configurable chat height in pixels (default: 600px)
    @track currentRecordId;
    @track currentObjectApiName;
    @track open; 
    @track selectedAgent = '';
    @track tempSelectedAgent = '';
    @track showChatWindow = false;
    @track availableHeight = 400;
    @track agents = [];
    @track agentInfo = {};
    @track showSpinner;
    @track hasMultipleAgents = false;
    @track aiSettings = {};
    @track isChatOpen = false;
    aiResponse = '';
    gptfylogo = gptfylogo;
    
    // Computed style for chat container height
    get chatContainerStyle() {
        return `height: ${this.chatHeight}px;`;
    }

    @wire(EnclosingUtilityId) utilityId;

    @wire(getAISettings)
    wiredAISettings({ error, data }) {
        if (data) {
            this.aiSettings = data;
        }
    }


    @wire(CurrentPageReference) 
    wiredPageRef(pageRef) {
        if (pageRef) {
            const recordIdOfCurrentPage = pageRef.attributes?.recordId || null;
            this.currentRecordId = recordIdOfCurrentPage;
            const objectNameOfCurrentPage = pageRef.attributes?.objectApiName || null;
            this.currentObjectApiName = objectNameOfCurrentPage;
        }
    }
    connectedCallback(){
        this.showSpinner = true;
        this.calculateAvailableHeight();
        this.fetchAccessibleAgent();
    }
    async fetchAccessibleAgent(){
        try{
            let response = await fetchAgents();
            if(response && response.length > 1){
                this.agents = JSON.parse(JSON.stringify(response));
                this.selectedAgent = this.agents[0].label.length > 30 ? this.agents[0].label.substring(0,30) + '...' : this.agents[0].label;
                this.tempSelectedAgent = this.selectedAgent;
                this.agents[0].selected = true;
                this.agentInfo = this.agents[0];
                this.hasMultipleAgents = true;
            }else if(response && response.length === 1){
                this.selectedAgent = response[0].label.length > 30 ? response[0].label.substring(0,30) + '...' : response[0].label; 
                this.tempSelectedAgent = this.selectedAgent;
                this.agentInfo = JSON.parse(JSON.stringify(response))[0];
                this.hasMultipleAgents = false;
            }else{
                this.showToast('error', 'Error', 'No Active Agent Found!', 'dismissable');
                this.closeChat();

            }
            this.showSpinner = false;
        }catch(error){
            this.showSpinner = false;
            console.error('Error calculating height:', error);
        }
    }
    calculateAvailableHeight() {
        try {
            // Calculate header height and subtract from viewport
            const headerHeight = 60; // Approximate header height
            const viewportHeight = window.innerHeight;
            this.availableHeight = Math.max(300, viewportHeight - headerHeight);
            
        } catch (error) {
            console.error('Error calculating height:', error);
            this.availableHeight = 400; // Fallback
        }
    }
    closeChat(){
        this.isChatOpen = false;
        if (this.utilityId) {
            minimize(this.utilityId)
                .then(result => {
                    // Optionally show success/failure
                    console.log('Utility bar minimized:', result);
                })
                .catch(error => {
                    // Handle any errors
                    console.error('Minimize failed:', error);
                });
        }
        this.dispatchEvent(new CustomEvent('closechat'));
    }
    
    openChat(){
        this.isChatOpen = true;
    }
    endChat(){
        let chatComp = this.template.querySelector('[data-id="agentic-chat"]');
        chatComp && chatComp.endChat();
        this.isChatOpen = false;
    }

    handleSelect(event) {
        let chatComp = this.template.querySelector('[data-id="agentic-chat"]');
        chatComp && chatComp.clearThreadId();

        let tempAgents = JSON.parse(JSON.stringify(this.agents));
        let tempObj = tempAgents.findIndex(obj => obj.label === this.tempSelectedAgent);
        this.selectedAgent = this.tempSelectedAgent.length > 30 ? this.tempSelectedAgent.substring(0,30) + '...' : this.tempSelectedAgent;
        this.agentInfo = this.agents[tempObj];
        this.open = false;
    }
    handleSelection(event){
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
    toggleDropdown(event){
        this.open = !this.open;
    }
    showToast(variant, title, message, mode) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
            mode: mode
        });
        this.dispatchEvent(event);
    }
    handleChangeAgent(evt){
        let agentName = evt.detail?.agentName;
        if(agentName){
            let tempAgents = JSON.parse(JSON.stringify(this.agents));
            let tempObj = tempAgents.findIndex(obj => obj.label === agentName);
            if(tempObj === -1){
                this.showToast('error', 'Error', 'The selected chat does not belong to the agent assigned to you', 'dismissable');
                let chatComp = this.template.querySelector('[data-id="agentic-chat"]');
                chatComp && chatComp.handleNewButton();
            }else{
                tempAgents.forEach(item => {
                    item.selected = false;
                });
                tempAgents[tempObj].selected = true; 
                this.agents = tempAgents;
                this.tempSelectedAgent = agentName;
                
                let chatComp = this.template.querySelector('[data-id="agentic-chat"]');
                chatComp && chatComp.clearThreadId();

                this.selectedAgent = this.tempSelectedAgent.length > 30 ? this.tempSelectedAgent.substring(0,30) + '...' : this.tempSelectedAgent;
                this.agentInfo = {...this.agents[tempObj], threadId : evt.detail.threadId};
                this.open = false;
            }
        }
    }
}