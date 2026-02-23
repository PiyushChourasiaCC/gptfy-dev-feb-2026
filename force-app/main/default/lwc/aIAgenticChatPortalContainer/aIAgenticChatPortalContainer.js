//@Jira v2/7822 : Enhance GPTfy Agent to be available in Experience Cloud
import { LightningElement, track , wire, api} from 'lwc';
import gptfylogo from '@salesforce/resourceUrl/GPTfy';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import { minimize, EnclosingUtilityId } from 'lightning/platformUtilityBarApi';
import fetchAgents from '@salesforce/apex/AIAgenticChatController.fetchAgents';
import getAISettings from '@salesforce/apex/AIAgenticChatController.getAISettings';

export default class AIAgenticChatConsoleContainer extends LightningElement {
    @api aiResponseName;
    @api chatAvatarIconName = 'utility:chat';
    @api chatHeight = 600; // Configurable chat height in pixels (default: 600px)
    @api floatingIconColor = '#FFFFFF';
    @api selectAgentDialogBackgroundColor = '#FFFFFF';
    // Theme Colors - Customizable from Experience Cloud Builder
    @api primaryColor = '#5B21B6'; // Action Color - Header, buttons, floating button background
    @api headerTextColor = '#FFFFFF'; // Header text and icon color
    @api startChatButtonColor = '#5B21B6'; // Start New Chat button background
    @api startChatButtonTextColor = '#FFFFFF'; // Start New Chat button text color
    @api chatBackgroundColor = '#F8F9FA'; // Chat messages area background
    @api userMessageBackgroundColor = '#5B21B6'; // User message bubble background
    @api userMessageTextColor = '#FFFFFF'; // User message text color
    @api botMessageBackgroundColor = '#E9ECEE'; // Bot message bubble background
    @api botMessageTextColor = '#000000'; // Bot message text color
    @api inputTextColor = '#000000'; // Input field text color
    @api inputBorderColor = '#5B21B6'; // Input field border color
    @api attachmentIconColor = '#5B21B6'; // Attachment/link icon color
    @api sendIconColor = '#5B21B6'; // Send button icon color
    @api botLogoUrl = ''; // Full URL for custom bot logo (e.g., from Static Resource or ContentAsset)
    @api chatMessageFontSize = '14'; // Font size for chat messages in pixels
    @api chatFontFamily = 'Salesforce Sans, Arial, sans-serif'; // Font family for all chat text
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
    @track aiSettings = {};
    @track isChatOpen = false;
    @api multiAgentFlag = false; // Configurable flag to show/hide multi-agent dropdown
    // Legacy properties - kept for backward compatibility
    @api textColor = '#FFFFFF'; // Deprecated - Use headerTextColor instead
    @api botLogoResourceName = ''; // Deprecated - Use botLogoUrl instead (resource names can't be dynamically loaded)

    aiResponse = '';
    gptfylogo = gptfylogo;
    
    // Theme configuration object to pass to child component (aIAgenticChat)
    get themeConfig() {
        return {
            primaryColor: this.primaryColor,
            headerTextColor: this.headerTextColor,
            startChatButtonColor: this.startChatButtonColor,
            startChatButtonTextColor: this.startChatButtonTextColor,
            chatBackgroundColor: this.chatBackgroundColor,
            userMessageBackgroundColor: this.userMessageBackgroundColor,
            userMessageTextColor: this.userMessageTextColor,
            botMessageBackgroundColor: this.botMessageBackgroundColor,
            botMessageTextColor: this.botMessageTextColor,
            inputTextColor: this.inputTextColor,
            inputBorderColor: this.inputBorderColor,
            attachmentIconColor: this.attachmentIconColor,
            sendIconColor: this.sendIconColor,
            botLogoUrl: this.botLogoUrl,
            chatMessageFontSize: this.chatMessageFontSize,
            chatFontFamily: this.chatFontFamily
        };
    }

    get floatingIconName(){
        return this.chatAvatarIconName || 'utility:chat';
    }

    // Dynamic styles for Start New Chat button
    get selectDialogButtonStyle() {
        const fontFamily = this.chatFontFamily || 'Salesforce Sans, Arial, sans-serif';
        return `--chat-dialog-background-color: ${this.startChatButtonColor || '#5B21B6'}; font-family: ${fontFamily}; background: ${this.startChatButtonColor || '#5B21B6'}; color: ${this.startChatButtonTextColor || '#FFFFFF'};`;
    }
    get selectDialogBackgroundColor() {
        return `background: ${this.selectAgentDialogBackgroundColor || '#FFFFFF'};`;
    }

    // Computed style for chat container with all CSS custom properties for theming
    get chatContainerStyle() {
        return `height: ${this.chatHeight}px; ${this.cssCustomProperties}`;
    }

    // Computed style for chat agent name
    get chatAgentNameStyle() {
        let fontFamily = this.chatFontFamily || 'Salesforce Sans, Arial, sans-serif';
        return `font-family: ${fontFamily};`;
    }

    // Computed style for floating chat button (includes CSS custom properties for theming)
    get floatingButtonStyle() {
        return `--chat-primary-color: ${this.primaryColor || '#5B21B6'}; --chat-header-text-color: ${this.floatingIconColor || '#FFFFFF'};`;
    }

    toggleDropdown(event){
        this.open = !this.open;
    }

    // All CSS custom properties for theming - passed to child components
    get cssCustomProperties() {
        return `
            --chat-primary-color: ${this.primaryColor};
            --chat-header-text-color: ${this.headerTextColor};
            --chat-start-button-color: ${this.startChatButtonColor};
            --chat-start-button-text-color: ${this.startChatButtonTextColor};
            --chat-background-color: ${this.chatBackgroundColor};
            --chat-user-message-bg: ${this.userMessageBackgroundColor};
            --chat-user-message-text: ${this.userMessageTextColor};
            --chat-bot-message-bg: ${this.botMessageBackgroundColor};
            --chat-bot-message-text: ${this.botMessageTextColor};
            --chat-input-text-color: ${this.inputTextColor};
            --chat-input-border-color: ${this.inputBorderColor};
            --chat-attachment-icon-color: ${this.attachmentIconColor};
            --chat-send-icon-color: ${this.sendIconColor};
        `;
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
            }else if(response && response.length === 1){
                this.selectedAgent = response[0].label.length > 30 ? response[0].label.substring(0,30) + '...' : response[0].label; 
                this.tempSelectedAgent = this.selectedAgent;
                this.agentInfo = JSON.parse(JSON.stringify(response))[0];
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
            const headerHeight = 100; // Approximate header height
            //const viewportHeight = window.innerHeight;
            const viewportHeight = this.chatHeight;
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