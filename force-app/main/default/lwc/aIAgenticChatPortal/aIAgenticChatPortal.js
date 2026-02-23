import { LightningElement, api, track, wire } from 'lwc';
import SVG_LOGO from "@salesforce/resourceUrl/gptfylogo";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import makeCallout from '@salesforce/apex/AIChatController.makeCallout';
import fetchAIChatHistory from '@salesforce/apex/AIAgenticChatController.fetchAIChatHistory';
import validateTTL from '@salesforce/apex/AIAgenticChatController.validateTTL';
import createNewChat from '@salesforce/apex/AIAgenticChatController.createNewChat';
import endChat from '@salesforce/apex/AIAgenticChatController.endChat';
import fetchRecordName from '@salesforce/apex/AIAgenticChatController.fetchRecordName';
import uploadAdditionalFiles from '@salesforce/apex/AIAgenticChatController.uploadAdditionalFiles';
import getStaticResourceUrl from '@salesforce/apex/AIAgenticChatController.getStaticResourceUrl';
import { getRecord } from 'lightning/uiRecordApi';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import Id from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import PHOTO_FIELD from '@salesforce/schema/User.SmallPhotoUrl';
//@Jira V2-7426
import CHAT_ENDED from '@salesforce/label/c.CHAT_ENDED';
import CHAT_EXPIRED from '@salesforce/label/c.CHAT_EXPIRED';



export default class AIAgenticChat extends NavigationMixin(LightningElement) {
    userId = Id;
    userName;
    userPhotoUrl;

    @wire(getRecord, { recordId: '$userId', fields: [NAME_FIELD, PHOTO_FIELD] })
    userDetails({ error, data }) {
        if (data) {
            this.userName = data.fields.Name.value;
            this.userPhotoUrl = data.fields.SmallPhotoUrl.value;
        }
    }
    @api recordId;
    @api objectApiName;
    @api response;
    @api containerHeight = 400;
    @api aiResponseName = '';
    @api gptfylogo;
    @api aiSettings;
    @api themeConfig = {}; // Theme configuration passed from parent
    @track agenticConfig;
    @track chatList = [];
    @track currentChat = {};
    @track showSpinner = false;
    @track threadId;
    svgURL = SVG_LOGO;
    isInProgress = false;
    message = '';
    @track expiredChatMessage;
    @track vectorStoreId = '';
    @track imageFileIds = [];
    @track autoNavEnabled = false; // Actual saved state
    @track tempAutoNavEnabled = false; // Temporary state for settings modal

    @wire(fetchRecordName, { recordId: '$recordId', objectApiName: '$objectApiName' })
    nameResult;

    @api
    get agentInfo(){
        return this.agenticConfig;
    }
    set agentInfo(val){
        if(val){
            let tempVal = JSON.parse(JSON.stringify(val));
            if(this.agenticConfig && tempVal.value !== this.agenticConfig.value){
                if(this.threadId || this.aiResponseName || tempVal.threadId){
                    if(!this.threadId && tempVal.threadId){
                        this.threadId = tempVal.threadId;
                    }
                    this.fetchChatHistory();
                }else{
                    this.agenticConfig = tempVal;
                    this.handleNewButton();
                }
            }
            this.agenticConfig = tempVal;
        }
    }

    get userThreadId(){
        return this.threadId || this.aiResponseName;
    }
    get name() {
        return this.nameResult.data ? this.nameResult.data : '';
    }
    // Dynamic container style based on parent height with theme CSS custom properties
    get containerStyle() {
        const theme = this.themeConfig || {};
        const cssVars = `
            --chat-primary-color: ${theme.primaryColor || '#5B21B6'};
            --chat-start-button-color: ${theme.startChatButtonColor || '#5B21B6'};
            --chat-start-button-text-color: ${theme.startChatButtonTextColor || '#FFFFFF'};
            --chat-background-color: ${theme.chatBackgroundColor || '#F8F9FA'};
            --chat-user-message-bg: ${theme.userMessageBackgroundColor || '#5B21B6'};
            --chat-user-message-text: ${theme.userMessageTextColor || '#FFFFFF'};
            --chat-bot-message-bg: ${theme.botMessageBackgroundColor || '#E9ECEE'};
            --chat-bot-message-text: ${theme.botMessageTextColor || '#000000'};
            --chat-input-text-color: ${theme.inputTextColor || '#000000'};
            --chat-input-border-color: ${theme.inputBorderColor || '#5B21B6'};
            --chat-attachment-icon-color: ${theme.attachmentIconColor || '#5B21B6'};
            --chat-send-icon-color: ${theme.sendIconColor || '#5B21B6'};
            --chat-font-family: ${theme.chatFontFamily || 'Salesforce Sans, Arial, sans-serif'};
        `;
        const fontFamily = theme.chatFontFamily || 'Salesforce Sans, Arial, sans-serif';
        let heightofMessagesArea = this.containerHeight;
        return `height: ${heightofMessagesArea}px; max-height: ${heightofMessagesArea}px; font-family: ${fontFamily}; ${cssVars}`;
    }

    // Get bot logo URL - use custom URL if provided, otherwise use default
    get botLogoURL() {
        // Default: Use GPTfy logo
        return this.svgURL;
    }

    // Dynamic styles for Start New Chat button
    get startChatButtonStyle() {
        const theme = this.themeConfig || {};
        const fontFamily = theme.chatFontFamily || 'Salesforce Sans, Arial, sans-serif';
        return `font-family: ${fontFamily}; background: ${theme.startChatButtonColor || '#5B21B6'}; color: ${theme.startChatButtonTextColor || '#FFFFFF'};`;
    }

    // Dynamic styles for chat messages area
    get chatMessagesAreaStyle() {
        const theme = this.themeConfig || {};
        return `background: ${theme.chatBackgroundColor || '#F8F9FA'};`;
    }

    // Dynamic styles for user message bubble
    get userBubbleStyle() {
        const theme = this.themeConfig || {};
        const fontSize = theme.chatMessageFontSize || '14';
        return `background: ${theme.userMessageBackgroundColor || '#5B21B6'}; color: ${theme.userMessageTextColor || '#FFFFFF'}; font-size: ${fontSize}px;`;
    }

    // Dynamic styles for bot message bubble
    get botBubbleStyle() {
        const theme = this.themeConfig || {};
        const fontSize = theme.chatMessageFontSize || '14';
        return `background: ${theme.botMessageBackgroundColor || '#E9ECEE'}; color: ${theme.botMessageTextColor || '#000000'}; font-size: ${fontSize}px;`;
    }

    // Dynamic styles for bot avatar
    get botAvatarStyle() {
        const theme = this.themeConfig || {};
        return `background-color: ${theme.primaryColor || '#5B21B6'};`;
    }

    // Helper to convert hex color to rgba with opacity
    hexToRgba(hex, opacity) {
        if (!hex) return `rgba(255, 255, 255, ${opacity})`;
        hex = hex.replace('#', '');
        if (hex.length === 3) {
            hex = hex.split('').map(char => char + char).join('');
        }
        const r = parseInt(hex.substring(0, 2), 16);
        const g = parseInt(hex.substring(2, 4), 16);
        const b = parseInt(hex.substring(4, 6), 16);
        return `rgba(${r}, ${g}, ${b}, ${opacity})`;
    }

    // Dynamic styles for input field
    get inputFieldStyle() {
        const theme = this.themeConfig || {};
        return `--chat-input-text-color: ${theme.inputTextColor || '#000000'}; --chat-input-border-color: ${theme.inputBorderColor || '#5B21B6'};`
    }

    // Dynamic styles for input area background with blur effect
    get inputAreaStyle() {
        const theme = this.themeConfig || {};
        const bgColor = theme.chatBackgroundColor || '#F8F9FA';
        return `--chat-background-color: ${bgColor}; background: ${bgColor}; backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px);`;
    }

    // Dynamic color for attachment icon
    get attachmentIconStyle() {
        const theme = this.themeConfig || {};
        return `--slds-c-icon-color-foreground-default: ${theme.attachmentIconColor || '#5B21B6'};`;
    }

    // Dynamic color for send icon
    get sendIconStyle() {
        const theme = this.themeConfig || {};
        return `--slds-c-icon-color-foreground-default: ${theme.sendIconColor || '#5B21B6'};`;
    }

    // Dynamic styles for empty state message
    get emptyMessageStyle() {
        const theme = this.themeConfig || {};
        return `color: ${theme.primaryColor || '#5B21B6'};`;
    }

    // Dynamic styles for typing dots
    get typingDotStyle() {
        const theme = this.themeConfig || {};
        return `background: ${theme.primaryColor || '#5B21B6'};`;
    }
    /**
     * Getter for file type accept attribute
     * Converts AI Settings format (e.g., "doc, pdf, png") to HTML input format (e.g., ".doc,.pdf,.png")
     * Handles single or multiple file types with or without spaces
     * @returns {String} Comma-separated file extensions with dots
     */
    get fileType(){
        if(this.aiSettings && this.aiSettings.fileType){
            // Split by comma, trim whitespace, add dot prefix to each type
            const types = this.aiSettings.fileType
                .split(',')
                .map(type => '.' + type.trim())
                .filter(type => type.length > 1) // Remove empty entries
                .join(',');
            
            return types || '.pdf,.png,.jpg,.jpeg,.doc,.docx,.xlsx,.csv,.txt';
        }
        
        // Default file types if no settings provided
        return '.pdf,.png,.jpg,.jpeg,.doc,.docx,.xlsx,.csv,.txt';
    }

    /**
     * Dynamic CSS class for send button based on progress state
     */
    get sendButtonClass() {
        const baseClass = 'send-button slds-top-m_x-small custom-icon-send slds-p-top_xx-small slds-p-right_x-small';
        return this.isInProgress ? `${baseClass} icon-disabled` : baseClass;
    }

    /**
     * Dynamic CSS class for file upload button based on progress state
     */
    get fileUploadButtonClass() {
        const baseClass = 'send-button slds-top-mx-small custom-icon-send slds-p-top_xx-small';
        return this.isInProgress ? `${baseClass} icon-disabled` : baseClass;
    }

    /**
     * Dynamic CSS class for settings button based on progress state
     */
    get settingsButtonClass() {
        const baseClass = 'send-button slds-top-m_x-small custom-icon-send slds-p-top_xx-small slds-p-left_xx-small';
        return this.isInProgress ? `${baseClass} icon-disabled` : baseClass;
    }
    
    connectedCallback() {
        this.fetchChatHistory();
        this.loadBotLogo();
    }
    async loadBotLogo(){
        if(this.themeConfig && this.themeConfig.botLogoUrl && this.themeConfig.botLogoUrl !== ''){
            let resourceUrl = await getStaticResourceUrl({ resourceName: this.themeConfig.botLogoUrl });
            if(resourceUrl){
                this.svgURL = resourceUrl;
            }
        }
    }
    async fetchChatHistory(){
        try{
            this.chatList = [{question : '', answer : this.agenticConfig.welcomeMessage}];
            if(this.threadId || this.aiResponseName){
                this.showSpinner = true;
                let response = await fetchAIChatHistory({auditId : this.threadId || this.aiResponseName,agentDeveloperName : this.agenticConfig.value});
                if(response){
                    let parsedResponse = JSON.parse(JSON.stringify(response));
                    if(parsedResponse.chats.length >= 1){
                        this.chatList = parsedResponse.chats;
                    }else{
                        this.handleNewButton();
                    }
                    this.showSpinner = false;
                    if(this.agenticConfig && parsedResponse.agentName !== this.agenticConfig.label){    
                        this.dispatchEvent(new CustomEvent('changeagent', { detail : { agentName : parsedResponse.agentName, threadId : this.threadId}}));
                    }
                }else{
                    this.showSpinner = false;
                }
            }
        }catch(error){
            this.showSpinner = false;
        }
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
    scrollToBottom() {
        requestAnimationFrame(() => {
            const messagesContainer = this.refs.messagesContainer;
            if (messagesContainer) {
                messagesContainer.scrollTop = messagesContainer.scrollHeight;
            }
        });
    }

    /**
     * Focus on the message input field
     * Uses setTimeout to ensure DOM is updated before focusing
     */
    focusInput() {
        setTimeout(() => {
            try {
                // Try multiple selectors to find the input
                let inputField = this.template.querySelector('lightning-input.message-input');
                
                if (inputField) {
                    // For lightning-input, we need to call focus() on the component itself
                    inputField.focus();
                } else {
                    // Fallback: try to find the native input element directly
                    inputField = this.template.querySelector('.message-input input');
                    if (inputField) {
                        inputField.focus();
                    }
                }
            } catch (error) {
                console.log('Focus input error:', error);
            }
        }, 150);
    }

    handleKeyPress = (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleSendbtn();
        }
    }

    handleSendbtn() {
        // Prevent sending if already in progress
        if (this.isInProgress) {
            return;
        }
        
        this.message = this.template.querySelector('.message-input').value;
        if (this.message && this.message.trim()) {
            this.chatList.push({question : this.message});
            this.template.querySelector('.message-input').value = '';
            this.handleChatCreation();
        } else {
            this.showToast('error', 'Error', 'Please type something to ask.', 'dismissable');
        }
    }

    async handleChatCreation() {
        try {
            this.isInProgress = true;
            let response = await createNewChat({ request : JSON.stringify({
                    agentName : this.agenticConfig.value,
                    userMessage : this.message,
                    userContextId : this.threadId || this.aiResponseName,
                    developerInstructions : (this.recordId ? 'User is viewing ' + this.objectApiName + ' record:\n- ID:  ' + this.recordId + '\n' + 'Name: '+ this.name + '\n' : ''),
                    userAgent : 'GPTfy Agent',
                    setOfVectorStoreIds : this.vectorStoreId ? [this.vectorStoreId] : [],
                    imageFileIds : this.imageFileIds ? this.imageFileIds : []
                })
            });
            let parsedResponse = JSON.parse(response);
            console.log('parsedResponse', parsedResponse);
            if(parsedResponse.message && parsedResponse.message.length > 0){
                this.expiredChatMessage = parsedResponse.message;
                this.isInProgress = false;
            }else{
                this.expiredChatMessage = null;
                this.threadId = parsedResponse.userContextId;
                this.chatList[this.chatList.length - 1] = {question : this.message, answer : parsedResponse.responseBody};
                this.isInProgress = false;
                this.scrollToBottom();
                this.message = '';
                
                // Focus back on input after response
                this.focusInput();
                
                // AutoNav: if enabled and a RecordId is present, navigate to it
                if (this.autoNavEnabled) {
                    const navId = this.extractRecordIdFromResponse(parsedResponse);
                    if (navId) {
                        // Small delay to allow UI to update before navigation
                        setTimeout(() => {
                            this.navigateToRecord(navId, parsedResponse.responseBody);
                        }, 500);
                    }
                }

            }
        } catch (error) {
            this.error = JSON.stringify(error);
            this.showToast('error', 'Error', this.error);
            this.isInProgress = false;
            // Focus back on input even on error
            this.focusInput();
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
            
            // Focus back on input after response
            this.focusInput();
            
            // AutoNav on callout response
            if (this.autoNavEnabled) {
                const navId = this.extractRecordIdFromResponse(response);
                if (navId) {
                    setTimeout(() => {
                        this.navigateToRecord(navId, response.answer || response.responseBody);
                    }, 500);
                }
            }
        } catch (error) {
            this.isInProgress = false;
            this.showToast('error', 'Error', 'Failed to get AI response');
            // Focus back on input even on error
            this.focusInput();
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
    @track showSettings = false;

    toggleSettingsWindow() {
        // Prevent opening settings if in progress
        if (this.isInProgress) {
            return;
        }
        
        // When opening settings, copy current saved state to temp state
        if (!this.showSettings) {
            this.tempAutoNavEnabled = this.autoNavEnabled;
        }
        this.showSettings = !this.showSettings;
    }

    closeSettings() {
        // When canceling, discard temp changes and revert to saved state
        this.tempAutoNavEnabled = this.autoNavEnabled;
        this.showSettings = false;
    }
    
    handleDone(){
        let inputElem = this.template.querySelector('[data-id="threadId"]');
        if(inputElem){
            
            if(this.threadId !== inputElem.value && inputElem.value !== ''){
                this.threadId = inputElem.value;
                this.fetchChatHistory();
                this.validateSession();
            }else if(inputElem.value === ''){
                this.handleNewButton(true);
            }
        }
        let config = this.template.querySelector('[data-id="config"]');
        if(config){
            this.agenticConfig = config.value;
        }
        
        // Save the temp AutoNav state to actual state when Done is clicked
        this.autoNavEnabled = this.tempAutoNavEnabled;
        
        this.showSettings = false;
    }
    //@Jira V2-7426
    async validateSession(){
        try{  
            let ttlMinutes = this.agenticConfig ? this.agenticConfig.ttlMinutes ? this.agenticConfig.ttlMinutes : null : null;
            let response = await validateTTL({threadId : this.threadId || this.aiResponseName, ttlMinutes : ttlMinutes});
            if(response === 'Valid Session' || response === 'New Session'){
                this.expiredChatMessage = null;
            }else if(response === 'Invalid Session'){
                this.expiredChatMessage = this.agenticConfig ? this.agenticConfig.ttlMessage ?  this.agenticConfig.ttlMessage : CHAT_EXPIRED : CHAT_EXPIRED;
            }
        }catch(error){

        }
    }
    @api
    handleNewButton(preserveAutoNav = false){
        this.expiredChatMessage = null;
        this.threadId = '';
        this.vectorStoreId = null;
        this.imageFileIds = [];
        if(this.agenticConfig.welcomeMessage){
            this.chatList = [{question : '', answer : this.agenticConfig.welcomeMessage}];
        }else{
            this.chatList = [];
        }
        // Disable AutoNav on new chat (unless explicitly preserving)
        if(preserveAutoNav !== true){
            this.autoNavEnabled = false;
            this.tempAutoNavEnabled = false;
            
            // Force update the checkbox if settings modal is open
            setTimeout(() => {
                const checkbox = this.template.querySelector('[data-id="autonav"]');
                if(checkbox) {
                    checkbox.checked = false;
                }
            }, 0);
        }
    }
    get hasRunningThread(){
        return !this.threadId;
    }
    //@Jira V2-7426
    @api 
    async endChat(){
        if(this.threadId){
            try{
                this.showSpinner = true;
                await endChat({threadId : this.threadId});
                this.expiredChatMessage =  CHAT_ENDED;
                this.vectorStoreId = null;
                this.imageFileIds = [];
            }catch(error){
                this.expiredChatMessage = null;
            }finally{
                this.showSpinner = false;
            }
        }
    }
    get inputAreaCSS(){
        return this.aiResponseName ? 'chat-input-area-console' : 'chat-input-area';
    }
    get chatContainerCSS(){
        return this.aiResponseName ? 'chat-container-console' : 'chat-container';
    }
    @api 
    clearThreadId(){
        this.threadId = null;
    }

    openFileChooser() {
        // Prevent file upload if in progress
        if (this.isInProgress) {
            return;
        }
        
        const input = this.template.querySelector('[data-id="nativeFileInput"]');
        if (input) {
            this.showSpinner = true;
            input.value = null;
            
            // Add focus listener to detect cancel
            const handleCancel = () => {
                // Small delay to allow onchange to fire first if files were selected
                setTimeout(() => {
                    if (!input.files || input.files.length === 0) {
                        this.showSpinner = false;
                    }
                    window.removeEventListener('focus', handleCancel);
                }, 300);
            };
            
            window.addEventListener('focus', handleCancel);
            input.click();
        }
    }

    /**
     * Handles selected files with count and size validation
     * Validates file count against maxFileCount and size against maxFileSize from AI Settings
     * @param {Event} event - File input change event
     */
    async handleNativeFiles(event) {
        try {
            const files = Array.from(event.target.files || []);
            if (!files.length) {
                this.showSpinner = false;
                return;
            }

            // Get max file count from settings (default 5 if not specified)
            const maxFileCount = this.aiSettings?.maxFileCount || 5;
            
            // Validate file count
            let filesToProcess = files;
            const excessFiles = [];

            if (files.length > maxFileCount) {
                // Separate allowed and excess files
                filesToProcess = files.slice(0, maxFileCount);
                const rejected = files.slice(maxFileCount);
                
                rejected.forEach(file => {
                    excessFiles.push(file.name);
                });

                // Show warning for excess files
                const excessFileNames = excessFiles.join(', ');
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'File Count Limit Exceeded',
                        message: `Maximum ${maxFileCount} file(s) allowed at once. Excess files not uploaded: ${excessFileNames}`,
                        variant: 'warning',
                        mode: 'sticky'
                    })
                );
            }

            // Get max file size in MB from settings (default 4 MB if not specified)
            const maxFileSizeMB = this.aiSettings?.maxFileSize || 4;
            const maxFileSizeBytes = maxFileSizeMB * 1024 * 1024; // Convert MB to bytes

            // Validate file sizes and separate valid/invalid files
            const validFiles = [];
            const rejectedFiles = [];

            filesToProcess.forEach(file => {
                if (file.size > maxFileSizeBytes) {
                    rejectedFiles.push({
                        name: file.name,
                        size: (file.size / (1024 * 1024)).toFixed(2) // Convert to MB for display
                    });
                } else {
                    validFiles.push(file);
                }
            });

            // Show warning for size-rejected files
            if (rejectedFiles.length > 0) {
                const rejectedFileNames = rejectedFiles
                    .map(f => `${f.name} (${f.size} MB)`)
                    .join(', ');
                
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'File Size Limit Exceeded',
                        message: `Maximum file size is ${maxFileSizeMB} MB. Files not uploaded: ${rejectedFileNames}`,
                        variant: 'warning',
                        mode: 'sticky'
                    })
                );
            }

            // If no valid files remain, stop processing
            if (validFiles.length === 0) {
                this.showSpinner = false;
                return;
            }

            // Convert valid files to base64 format for Apex
            const fileData = await Promise.all(validFiles.map(async file => {
                const base64 = await this.readFileAsBase64(file);
                return {
                    fileName: file.name,
                    mimeType: file.type || 'application/octet-stream',
                    base64Data: base64,
                    fileSize: file.size
                };
            }));

            // Call your existing Apex method
            const result = await uploadAdditionalFiles({ 
                filesJSON : JSON.stringify(fileData),
                vectorStoreId: this.vectorStoreId,
                namedCredential : this.agenticConfig.namedCredential,
                threadId: this.threadId
            });

            if(result){
                let tempResult = JSON.parse(JSON.stringify(result));
                this.threadId = tempResult.userContextId;
                this.vectorStoreId = tempResult.vectorStroreId;
                this.imageFileIds = tempResult.imageFileIds;
            }
            
            // Handle success with detailed feedback
            let successMessage = `${validFiles.length} file(s) uploaded successfully`;
            
            // Add rejection details if any
            const rejectionDetails = [];
            if (excessFiles.length > 0) {
                rejectionDetails.push(`${excessFiles.length} exceeded count limit`);
            }
            if (rejectedFiles.length > 0) {
                rejectionDetails.push(`${rejectedFiles.length} exceeded size limit`);
            }
            
            if (rejectionDetails.length > 0) {
                successMessage += ` (${rejectionDetails.join(', ')})`;
            }
            
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: successMessage,
                    variant: 'success'
                })
            );

        } catch (error) {
            let errorMessage = error?.body?.message || error?.message || 'Failed to upload files';
            if(errorMessage.indexOf('Apex heap size too large') > -1){
                errorMessage = 'File size too large. Please try uploading files less than 1 MB.';
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Upload Failed',
                    message: errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.showSpinner = false;
        }
    }

    // Helper to read file as base64
    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                // Remove data URL prefix (e.g., "data:image/png;base64,")
                const base64 = reader.result.split(',')[1];
                resolve(base64);
            };
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }
    /**
     * Handles AutoNav checkbox toggle in settings modal
     * Updates only the temporary state - actual state is saved on Done click
     */
    handleAutoNavToggle(event) {
        this.tempAutoNavEnabled = event.target.checked || false;
    }
    
    /**
     * Extracts the RecordId from various response formats
     * Specifically handles AIAgenticFunctionHandler response structure
     * @param {Object|String} resp - The response object or string from the API
     * @returns {String|null} - The extracted Salesforce Record ID or null
     */
    extractRecordIdFromResponse(resp) {
        if (!resp) {
            console.log('extractRecordIdFromResponse: No response provided');
            return null;
        }

        console.log('extractRecordIdFromResponse - Input:', JSON.stringify(resp, null, 2));

        // Step 1: Check if RecordId is at top level (direct response)
        if (resp.RecordId && this.validateSalesforceId(resp.RecordId)) {
            console.log('RecordId found at top level:', resp.RecordId);
            return resp.RecordId;
        }

        // Step 2: Check responseBody (most common case for AIAgenticFunctionHandler)
        if (resp.responseBody) {
            console.log('Found responseBody, processing...');
            let responseBody = resp.responseBody;

            // If responseBody is a string, parse it
            if (typeof responseBody === 'string') {
                console.log('responseBody is string, attempting to parse...');
                try {
                    responseBody = JSON.parse(responseBody);
                    console.log('Successfully parsed responseBody:', responseBody);
                } catch (e) {
                    console.log('Failed to parse responseBody as JSON, trying regex...');
                    // Try regex extraction from string
                    const idMatch = responseBody.match(/["']?RecordId["']?\s*:\s*["']?([a-zA-Z0-9]{15,18})["']?/);
                    if (idMatch && idMatch[1]) {
                        console.log('Regex extracted RecordId:', idMatch[1]);
                        return idMatch[1];
                    }
                }
            }

            // Now check the parsed responseBody for RecordId
            if (responseBody && typeof responseBody === 'object') {
                const recordId = responseBody.RecordId || responseBody.recordId || responseBody.Id || responseBody.id;
                if (recordId && this.validateSalesforceId(recordId)) {
                    console.log('RecordId found in parsed responseBody:', recordId);
                    return recordId;
                }
            }
        }

        // Step 3: Check answer property (for chat history responses)
        if (resp.answer) {
            console.log('Found answer property, checking...');
            let answer = resp.answer;
            
            if (typeof answer === 'string') {
                try {
                    answer = JSON.parse(answer);
                } catch (e) {
                    // Try regex if parsing fails
                    const idMatch = answer.match(/["']?RecordId["']?\s*:\s*["']?([a-zA-Z0-9]{15,18})["']?/);
                    if (idMatch && idMatch[1]) {
                        console.log('Regex extracted RecordId from answer:', idMatch[1]);
                        return idMatch[1];
                    }
                }
            }
            
            if (answer && typeof answer === 'object') {
                const recordId = answer.RecordId || answer.recordId || answer.Id || answer.id;
                if (recordId && this.validateSalesforceId(recordId)) {
                    console.log('RecordId found in answer:', recordId);
                    return recordId;
                }
            }
        }

        console.log('No RecordId found in response');
        return null;
    }

    /**
     * Validates if the given string is a valid Salesforce ID (15 or 18 characters)
     * @param {String} id - The ID string to validate
     * @returns {String|null} - The ID if valid, null otherwise
     */
    validateSalesforceId(id) {
        if (!id || typeof id !== 'string') return null;
        
        // Salesforce IDs are 15 or 18 alphanumeric characters
        // They start with a 3-character prefix that identifies the object type
        return /^[a-zA-Z0-9]{15,18}$/.test(id) ? id : null;
    }

    /**
     * Navigate to the created record in the same window
     * Uses Lightning Navigation to navigate without full page refresh
     * @param {string} recordId - The Salesforce record ID to navigate to
     * @param {string} responseBody - Optional response body for context in toast
     */
    navigateToRecord(recordId, responseBody) {
        if (!recordId) {
            console.error('navigateToRecord: No recordId provided');
            return;
        }

        console.log('Navigating to record:', recordId);

        // Generate the navigation page reference
        const pageReference = {
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        };

        // Show toast notification before navigation
        this.showRecordCreatedToast(recordId, responseBody);

        // Navigate in the same window/tab using Lightning Navigation
        // This preserves the Lightning Experience context without full page refresh
        this[NavigationMixin.Navigate](pageReference);
    }

    /**
     * Shows a success toast notification when a record is created and navigation is triggered
     */
    showRecordCreatedToast(recordId, responseBody) {
        // Extract record type or use generic message
        let message = 'Record created successfully. Navigating to record...';
        
        // Try to extract object name from response if available
        if (responseBody && typeof responseBody === 'string') {
            const objectNameMatch = responseBody.match(/created|Created|new|New\s+(\w+)/);
            if (objectNameMatch && objectNameMatch[1]) {
                message = `${objectNameMatch[1]} created successfully. Navigating to record...`;
            }
        }

        this.showToast(
            'success',
            'Record Created',
            message,
            'dismissable'
        );
    }

}