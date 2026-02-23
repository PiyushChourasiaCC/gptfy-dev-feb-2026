import { LightningElement, api, track } from 'lwc';
import SVG_LOGO from "@salesforce/resourceUrl/gptfylogo";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChatHistory from '@salesforce/apex/AIChatController.getChatHistory';
import createNewChat from '@salesforce/apex/AIChatController.createNewChat';
import makeCallout from '@salesforce/apex/AIChatController.makeCallout';

export default class AIChat extends LightningElement {
    @api response;
    @api containerHeight = 400;
    @track chatList = [];
    @track currentChat = {};
    @track showSpinner = false;
    svgURL = SVG_LOGO + '#logo';
    isInProgress = false;
    message = '';

     // Dynamic container style based on parent height
     get containerStyle() {
        return `height: ${this.containerHeight}px; max-height: ${this.containerHeight}px;`;
    }
    
    connectedCallback() {
        this.getFileChatHistory();
        this.setupResizeObserver();
    }

    disconnectedCallback() {
        this.scrollToBottom();
    }

    renderedCallback() {
        this.scrollToBottom();
        this.adjustChatHeight();
    }
    adjustChatHeight() {
        const chatContainer = this.template.querySelector('.chat-container');
        if (chatContainer && this.parentHeight) {
            chatContainer.style.height = `${this.parentHeight}px`;
            chatContainer.style.maxHeight = `${this.parentHeight}px`;
        }
    }
    setupResizeObserver() {
        if (window.ResizeObserver) {
            this.resizeObserver = new ResizeObserver(() => {
                this.adjustChatHeight();
            });
            
            const chatContainer = this.template.querySelector('.chat-container');
            if (chatContainer) {
                this.resizeObserver.observe(chatContainer);
            }
        }
    }
    async getFileChatHistory() {
        this.showSpinner = true;
        try {
            let response = await getChatHistory({ recordId: this.response.Id });
            if(response){
                this.chatList = JSON.parse(JSON.stringify(response))
            }else{
                this.chatList = [];
            }
        } catch (error) {
            this.error = JSON.stringify(error);
            this.showToast('error', 'Error', 'Failed to load chat history');
        }finally{
            this.showSpinner = false;
        }
    }

    scrollToBottom() {
        requestAnimationFrame(() => {
            const messagesContainer = this.refs.messagesContainer;
            if (messagesContainer) {
                messagesContainer.scrollTop = messagesContainer.scrollHeight;
            }
        });
    }

    handleKeyPress = (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleSendbtn();
        }
    }

    handleSendbtn() {
        this.message = this.template.querySelector('.message-input').value;
        if (this.message && this.message.trim()) {
            this.handleChatCreation();
        } else {
            this.showToast('error', 'Error', 'Please type something to ask.', 'dismissable');
        }
    }

    async handleChatCreation() {
        try {
            let response = await createNewChat({ 
                message: this.message 
            });
            this.chatList.push(JSON.parse(JSON.stringify(response)));
            this.template.querySelector('.message-input').value = '';
            this.isInProgress = true;
            this.scrollToBottom();
            this.makeCallout();
            this.message = '';
            
        } catch (error) {
            this.error = JSON.stringify(error);
            this.showToast('error', 'Error', this.error);
        }
    }

    async makeCallout() {
        try {
            let response = await makeCallout({ 
                recordId: this.response.Id, 
                currentChat : JSON.stringify(this.chatList[this.chatList.length - 1]) 
            });
            this.isInProgress = false;
            this.chatList[this.chatList.length - 1] = JSON.parse(JSON.stringify(response));
            this.scrollToBottom();
            
        } catch (error) {
            this.isInProgress = false;
            this.showToast('error', 'Error', 'Failed to get AI response');
        }
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
}