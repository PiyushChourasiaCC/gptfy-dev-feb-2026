import { LightningElement, api, track, wire } from 'lwc';
import gptfylogo from '@salesforce/resourceUrl/GPTfy';
import getPromptElementsWithPrompts from '@salesforce/apex/AICanvasController.getPromptElementsWithPrompts';
import getSecurityAudit from '@salesforce/apex/AICanvasController.getSecurityAudit';
import updateParentAIResponse from '@salesforce/apex/AICanvasController.updateParentAIResponse';
import isCanvasUser from '@salesforce/apex/AICanvasController.isCanvasUser';
import isAdminUser from '@salesforce/apex/GPTfyConsoleController.isAdminUser';

import TIME_ZONE from '@salesforce/i18n/timeZone';

import TIME_SAV_FIELD from '@salesforce/schema/AI_Response__c.Time_Saved_Seconds__c';
import HOW_IT_WORK_FIELD from '@salesforce/schema/AI_Response__c.How_it_works__c';
import RESP_ID_FIELD from '@salesforce/schema/AI_Response__c.Id';
import RESP_NAME_FIELD from '@salesforce/schema/AI_Response__c.Name';
import RESP_CREATED from '@salesforce/schema/AI_Response__c.CreatedDate';
import RESP_LAST_MODIFIED_DATE from '@salesforce/schema/AI_Response__c.LastModifiedDate';


import FEEDBACK_TYPE_FIELD from '@salesforce/schema/AI_Feedback__c.Type__c';

export default class AICanvas extends LightningElement {
    timeZone = TIME_ZONE;
    @api recordId; // The record Id
    @api objectApiName;
    @api promptId = '';
    @api skipWireUpdate = false;
    @api parentAIResponseId = '';
    @api existingParentAIResponse = '';
    
    @track loading = true;
    @track error;
    @track columnCount = 3; // Default column count - always 3 per row
    @track autoRefresh = true;
    @track lastRefreshDate;
    @track nextRefreshDate;
    @track showExpandModal = false;
    @track expandedCardContent = '';
    @track expandedCardName = '';
    @track expandedCardIndex = null;
    @track canvasMessage = '';
    @track promptElements = new Map();
    @track promptDetails = new Map();
    @track picklistWrapper = {};
    // Email info
    @track emailActionName;
    @track userSignature;
    @track canvasBodyContent = '';
    @track notInitialLoad = false;
    @track showCanvasHeader;
    @track parentAIResponse;
    @track dislikeState = false;
    @track showFeedbackModal=false;
    @track showHowItWorksDocked = false;
    @track showPopOutContent = false;
    @track hasCanvasUser = false;
    @track hasAdminUser = false;
    @track buttonComponentSettings = {isGlobalContext : true, showRefreshButton : true, showZoomButton : false};

    // Prompt vars
    @track prompt;
    @track securityAudit;
    @track namespace = '';

    gptfylogo = gptfylogo;
    canvasTemplate;
    // Auto-refresh timer
    autoRefreshTimer;
    // Auto refresh interval in milliseconds
    AUTO_REFRESH_INTERVAL;
    // auto refresh time in hour
    autoRefreshTime;
    // Layout stabilizers
    masonryLayoutPending = false;
    resizeTimeout = null;
    layoutLock = false;
    initialLayoutApplied = false;

    gptResponseUrl;
    gptResponseName;
    gptResponseDate;
    timeSaved;
    howItWorks;
    wiredTodosResult;
    isUpdating = false;

    informativeMessage = `
        <div class="slds-box slds-theme_info slds-text-align_center slds-m-around_medium">
            <div class="slds-text-heading_medium slds-m-bottom_small">
                <lightning-icon icon-name="utility:info" size="small" class="slds-m-right_x-small"></lightning-icon>
                No Data Available
            </div>
            <p class="slds-text-align_left slds-m-bottom_x-small">Please check the following before proceeding:</p>
            <div class="slds-text-align_left slds-m-left_medium">
                <ul class="slds-list_dotted">
                    <li class="slds-m-bottom_xx-small">Ensure you have correct profile access.</li>
                    <li class="slds-m-bottom_xx-small">Ensure this record meets the Visibility condition.</li>
                    <li class="slds-m-bottom_xx-small">Ensure that Prompt is Active</li>
                    <li class="slds-m-bottom_xx-small">Ensure that Prompt has at-least one Prompt Element</li>
                    <li class="slds-m-bottom_xx-small">Contact your administrator if the issue persists</li>
                </ul>
            </div>
        </div>
        `;

    @api
    get showHeader(){
        return this.showCanvasHeader ?? true;
    }
    set showHeader(val){
        this.showCanvasHeader = val;
    }
    @api
    get isNotInitialLoad(){
        return this.notInitialLoad;
    }
    set isNotInitialLoad(val){
        this.notInitialLoad = val;
    }
    // default message for l;oading
    defaultWaitMessage = 'Anonymizing your data for secure AI processing :)';

    connectedCallback(){
        if(!this.skipWireUpdate){
            this.canvasMessage = 'Loading...';
            this.checkAdminUser();
            this.checkIsCanvasUser();
            this.getPromptElementData();
        }else{
            this.loading = false;
        }
    }
    checkAdminUser(){
        isAdminUser()
        .then(result => {          
            this.hasAdminUser = result;
        })
        .catch(error => {
            this.canvasMessage = error.body ? error.body.message : JSON.stringify(error) ;
        });
    }
    async checkIsCanvasUser(){
        try{
            let result = await isCanvasUser();
            if(result === true){
                this.hasCanvasUser = true;
            }else{
                this.hasCanvasUser = false;
            }
        }catch(error){
            this.loading = false;
            this.canvasMessage = error.body ? error.body.message : JSON.stringify(error) ;
        }
    }
    async getPromptElementData(){
        try{
            this.isUpdating = false;
            let response = await getPromptElementsWithPrompts({ promptId: (this.promptId ? this.promptId : ''),recordId : this.recordId, objectApiName: this.objectApiName, parentAIResponse : this.parentAIResponseId, notInitialLoad : this.notInitialLoad });
            if(response){
                let parsedResponse = JSON.parse(JSON.stringify(response));
                this.prompt = parsedResponse.prompt;
                this.emailActionName = parsedResponse.emailActionName;
                this.userSignature = parsedResponse.userSignature;
                if(this.prompt.autoRefreshDuration){
                        // this.AUTO_REFRESH_INTERVAL = 2 * 60 * 1000;
                        this.AUTO_REFRESH_INTERVAL = this.prompt.autoRefreshDuration * 60 * 60 * 1000;
                        this.lastRefreshDate = new Date();
                        this.updateNextRefreshDate();
                        // Setup auto refresh
                        this.setupAutoRefresh();
                }
                await this.getSecurityAudit();
                this.promptElements = new Map(
                    this.sortPromptElements(this.parseResults(parsedResponse.promptElements))
                    .map(promptElement => [promptElement.Id, promptElement]));
                this.promptDetails = new Map(
                    this.parseResults(parsedResponse.promptDetails)
                    .map(promptDetail => [promptDetail.Id, promptDetail]));
                this.picklistWrapper = JSON.parse(JSON.stringify(parsedResponse.picklistWrapper));
                this.namespace = parsedResponse.namespace;
                this.relatePromptWithComponent();
                
                // Apply layout once with a delay to ensure DOM is ready
                if (!this.initialLayoutApplied) {
                    // First time layout should have a longer delay to ensure all components are rendered
                    setTimeout(() => {
                        this.initialLayoutApplied = true;
                        this.applyMasonryLayout();
                    }, 250);
                } else {
                    // Subsequent layouts can use a shorter delay
                    this.scheduleMasonryLayout(100);
                }
                // Add window resize listener for responsiveness
                window.addEventListener('resize', this.debounce(this.handleResize.bind(this), 250)); 
                this.canvasMessage = '';
                this.fireHideFooter(false);
            } 
            else if(response === null){
                this.loading = false;
                this.canvasMessage = this.informativeMessage;
                this.fireHideFooter(true);
            }
        }catch(error){
            this.loading = false;
            this.canvasMessage = error.body ? error.body.message : error ;
            this.fireHideFooter(true);
        }
    }
    fireHideFooter(hideFooter){
        this.dispatchEvent(new CustomEvent('hidefooter', 
            {
                detail :{
                    hideFooter : hideFooter
                },
                bubbles : true,
                composed : true
            }));
    }
    async getSecurityAudit(){
        try{
            let response = await getSecurityAudit({promptId: (this.promptId ? this.promptId : this.prompt ? this.prompt.Id : ''), recordId : this.recordId, notInitialLoad : this.notInitialLoad, responseId : this.parentAIResponseId});
            if(response) {
                this.parentAIResponse = JSON.parse(JSON.stringify(response));
                this.gptResponseUrl = '/' + this.parentAIResponse[RESP_ID_FIELD.fieldApiName];
                this.gptResponseName = this.parentAIResponse[RESP_NAME_FIELD.fieldApiName] + '\n';
                this.gptResponseDate = this.parentAIResponse[RESP_CREATED.fieldApiName];
                this.timeSaved = this.parentAIResponse[TIME_SAV_FIELD.fieldApiName];
                this.howItWorks = this.parentAIResponse[HOW_IT_WORK_FIELD.fieldApiName];
                this.lastRefreshDate = this.parentAIResponse[RESP_CREATED.fieldApiName];
                this.updateNextRefreshDate();
                var feedbacks = this.parentAIResponse[this.namespace+'Feedbacks__r'];
                if(feedbacks && feedbacks.length > 0){
                    var feedbk = feedbacks[0];
                    if(feedbk[FEEDBACK_TYPE_FIELD.fieldApiName] == 'Dislike'){
                        this.dislikeState = true;
                    }else{
                        this.dislikeState = false;
                    }
                }
                if(!this.parentAIResponseId){
                    this.fireSecurityAuditCreatedEvent();
                }
            }
        }catch(error){
            console.log(JSON.stringify(error));
        }finally{
            this.loading = false;
        }
    }
    fireSecurityAuditCreatedEvent(){
        this.dispatchEvent(new CustomEvent('parentresponsecreated', 
            {
                detail :{
                    parentAIResponse : this.parentAIResponse
                },
                bubbles : true,
                composed : true
            }));
    }
    // Schedule a layout update with debouncing
    scheduleMasonryLayout(delay) {
        if (this.masonryLayoutPending) return;
        
        this.masonryLayoutPending = true;
        requestAnimationFrame(() => {
            setTimeout(() => {
                this.masonryLayoutPending = false;
                this.applyMasonryLayout();
            }, delay);
        });
    }

    relatePromptWithComponent() {
        let tempPromptElements = new Map();
        for (const [key, value] of this.promptElements) {
            tempPromptElements.set(key, {
                ...value, 
                cardStyle : 'prompt-card loading',
                cardIcon : value.cardIcon ? value.cardIcon : 'custom1',
                promptRecord: this.promptDetails.get(value.prompt),
                response: value.response || '',
                summaryResponse: value.summaryResponse || ''
            });
        }
        this.promptElements = tempPromptElements;
    }

    parseResults(results) {
        return JSON.parse(JSON.stringify(results));
    }

    sortPromptElements(records) {
        return records.sort((a, b) => a.sequence - b.sequence);
    }

    disconnectedCallback() {
        // Remove event listener when component is destroyed
        window.removeEventListener('resize', this.debounce(this.handleResize.bind(this), 250));
        // Clear auto-refresh timer
        this.clearAutoRefreshTimer();
    }

    get promptElementsArr() {
        return this.promptElements && this.promptElements.size > 0 && 
                this.parseResults(Array.from(this.promptElements.values()));
    }

    // Setup auto-refresh timer
    setupAutoRefresh() {
        this.clearAutoRefreshTimer(); // Clear any existing timer
        
        if (this.autoRefresh && this.AUTO_REFRESH_INTERVAL && this.showHeader) {
            this.autoRefreshTimer = setTimeout(() => {
                this.handleRefresh();
                // Setup the next refresh after this one completes
                this.setupAutoRefresh();
            }, this.AUTO_REFRESH_INTERVAL);
        }
    }

    // Clear auto-refresh timer
    clearAutoRefreshTimer() {
        if (this.autoRefreshTimer) {
            clearTimeout(this.autoRefreshTimer);
            this.autoRefreshTimer = null;
        }
    }

    // Update the next refresh date based on last refresh and interval
    updateNextRefreshDate() {
        if (this.lastRefreshDate && this.AUTO_REFRESH_INTERVAL) {
            this.nextRefreshDate = new Date(this.lastRefreshDate.getTime() + this.AUTO_REFRESH_INTERVAL);
        } else {
            this.nextRefreshDate = null;
        }
    }

    // Debounce function to prevent excessive resize calculations
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }

    handleResize() {
        // Only apply layout if the component is fully loaded
        if (!this.loading && this.promptElementsArr && this.promptElementsArr.length > 0) {
            // Use debounced layout update
            this.scheduleMasonryLayout(100);
        }
    }

    applyMasonryLayout() {
        // Prevent concurrent layout operations
        if (this.layoutLock) return;
        this.layoutLock = true;

        requestAnimationFrame(() => {
            const containerEl = this.template.querySelector('.prompt-masonry-container');
            if (!containerEl) {
                this.layoutLock = false;
                return;
            }
            
            const cardElements = [...this.template.querySelectorAll('.prompt-card-wrapper')];
            if (!cardElements.length) {
                this.layoutLock = false;
                return;
            }
            
            // Check if we're on mobile
            const isMobile = window.innerWidth <= 768;
            
            if (isMobile) {
                // On mobile, stack everything in a single column
                cardElements.forEach(element => {
                    element.style.position = 'static';
                    element.style.width = '100%';
                    element.style.transform = 'none';
                    element.style.top = '';
                    element.style.left = '';
                });
                
                // Reset container height for natural flow
                containerEl.style.height = 'auto';
                this.layoutLock = false;
                return;
            }
            
            // For desktop view, use the masonry layout
            
            // Get container width - use clientWidth to avoid scrollbar issues
            const containerWidth = containerEl.clientWidth;
            const gapSize = 2; // Increased gap size between cards
            
            // Fixed column count to 3
            this.columnCount = 3;
            
            // Calculate adjusted column width to account for gaps properly
            const totalGapWidth = gapSize * (this.columnCount - 1);
            const unitColumnWidth = (containerWidth - totalGapWidth) / this.columnCount;
            
            // Initialize column heights
            let rowPositions = [0, 0, 0]; // Current Y position for each position unit

            // First reset all cards to default state
            cardElements.forEach(element => {
                element.style.position = 'static';
                element.style.visibility = 'hidden';
                element.style.width = '';
                element.style.transform = 'none';
            });
            
            // Force a reflow to get accurate heights
            containerEl.offsetHeight;
            
            const cardHeights = new Map();
            
            // First pass: measure all elements in their natural flow state
            cardElements.forEach(element => {
                const elementId = element.dataset.id;
                const templateComponent = this.promptElements.get(elementId);
                
                // Temporarily set width to what it will be in the layout
                const cardWidthUnits = this.getTemplateColumnWidth(templateComponent);
                const tempWidth = unitColumnWidth * cardWidthUnits + (cardWidthUnits - 1) * gapSize;
                element.style.width = `${tempWidth}px`;
                
                // Force layout and get height
                const elementHeight = element.offsetHeight + gapSize; // Add gap for vertical spacing
                
                // Store height in map
                cardHeights.set(elementId, elementHeight);
            });
            
            // Reset the container for absolute positioning
            containerEl.style.position = 'relative';
            
            // Second pass: position each card using cached heights
            let containerHeight = 0;
            
            // Check if we have only one card
            const isSingleCard = cardElements.length === 1;
            
            // Process each card in sequence order
            for (let i = 0; i < this.promptElementsArr.length; i++) {
                const templateComponent = this.promptElementsArr[i];
                const element = cardElements.find(el => el.dataset.id === templateComponent.Id);
                
                if (!element) continue;
                
                // Get width in column units (1, 2, or 3)
                const cardWidthUnits = this.getTemplateColumnWidth(templateComponent);
                const actualWidth = unitColumnWidth * cardWidthUnits + (cardWidthUnits - 1) * gapSize;
                
                // For multiple cards, find best position for this card
                let bestPosition = this.findBestPositionForCard(rowPositions, cardWidthUnits);
                
                // Get the card height from our cache
                const cardHeight = cardHeights.get(element.dataset.id) || 0;
                
                // Calculate exact position
                const topPosition = rowPositions[bestPosition];
                const leftPosition = bestPosition * (unitColumnWidth + gapSize);
                
                // Position the card
                element.style.position = 'absolute';
                element.style.top = `${topPosition}px`;
                element.style.left = `${leftPosition}px`;
                element.style.width = `${actualWidth}px`;
                element.style.visibility = 'visible';
                
                const cardElement = element.querySelector('.prompt-card');
                if (cardElement) {
                    if(templateComponent.height){
                        cardElement.style.height = `${templateComponent.height}px`;

                        const contentElement = element.querySelector('.prompt-card-content');
                        if (contentElement) {
                            contentElement.style.height = `${templateComponent.height}vh`;
                        }
                    }
                    cardElement.style.marginTop = '5px';
                    cardElement.style.border = '1px solid rgba(0,0,0,0.1)';
                }

                // Update row positions for the columns this card occupies
                for (let j = 0; j < cardWidthUnits; j++) {
                    if (bestPosition + j < this.columnCount) {
                        rowPositions[bestPosition + j] = topPosition + cardHeight;
                    }
                }
                
                // Update container height
                containerHeight = Math.max(...rowPositions);
            }
            
            // Set final container height plus some padding
            containerEl.style.height = `${containerHeight + 20}px`;
            this.layoutLock = false;
        });
    }

    // Find the best position to place a card of given width
    findBestPositionForCard(rowPositions, cardWidth) {
        // For single-column card (width=1), find the shortest column
        if (cardWidth === 1) {
            return rowPositions.indexOf(Math.min(...rowPositions));
        }
        
        // For multi-column cards, find consecutive columns with minimum combined height
        const maxPosition = this.columnCount - cardWidth;
        
        if (maxPosition < 0) {
            // Card is wider than available columns, place at start
            return 0;
        }
        
        let bestPosition = 0;
        let minHeight = Infinity;
        
        // Check each possible starting position
        for (let i = 0; i <= maxPosition; i++) {
            const positionsToConsider = rowPositions.slice(i, i + cardWidth);
            const maxHeightAtPosition = Math.max(...positionsToConsider);
            
            if (maxHeightAtPosition < minHeight) {
                minHeight = maxHeightAtPosition;
                bestPosition = i;
            }
        }
        
        return bestPosition;
    }

    // Get column width in units (1, 2, or 3)
    getTemplateColumnWidth(record) {
        if (!record || !record.width) return 1;
        
        switch (record.width) {
            case '1/3 Column':
                return 1;
            case '2/3 Column':
                return 2;
            case '3/3 Column':
                return 3;
            default:
                return 3; // Default to 1/3 column if not specified
        }
    }

    // Handle DOM updates and apply layout when needed
    renderedCallback() {
        if (!this.loading && this.hasCanvasTemplates && !this.masonryLayoutPending) {
            // Only trigger layout if it's not already pending
            this.scheduleMasonryLayout(100);
        }
    }
    
    // EXPAND MODAL FUNCTIONS
    expandCard(event) {
        // Capture card measurements BEFORE modal opens to prevent reflow
        this.captureLayoutSnapshot();
        
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const templateComponentId = event.currentTarget.dataset.id;
        
        // Get the selected template component
        const selectedComponent = this.promptElements.get(templateComponentId);
        
        if (selectedComponent) {
            this.expandedCardName = selectedComponent.promptRecord?.name || 'Response Details';
            this.expandedCardContent = selectedComponent?.responseDetails?.responseBody;
            this.expandedCardIndex = index;
            
            // Open the modal
            this.showExpandModal = true;
            
            const modalComponent = this.template.querySelector('c-a-i-canvas-modal');
            if (modalComponent && this.expandedCardContent) {
                modalComponent.templateComponentId = templateComponentId;
                modalComponent.bodyContent = this.expandedCardContent;
                modalComponent.lastRefreshDate = this.lastRefreshDate;
                modalComponent.selectedComponent = selectedComponent;
                modalComponent.iconName = 'custom:'+selectedComponent.cardIcon;
                modalComponent.hasAdminUser = this.hasAdminUser;
                modalComponent.openModal();
            }
        }
    }
    
    // Capture layout measurements before modal operations
    captureLayoutSnapshot() {
        const containerEl = this.template.querySelector('.prompt-masonry-container');
        if (containerEl) {
            // Force a layout calculation to ensure container height is correct
            const height = containerEl.offsetHeight;
            // Fix the height temporarily to prevent reflow
            containerEl.style.minHeight = `${height}px`;
        }
    }
    
    // GLOBAL REFRESH
    handleRefresh() {
        this.buttonComponentSettings.showZoomButton = false;
        // Set the notinitial load to true so that we can bring data from callout
        this.notInitialLoad = true;
        // Capture layout before loading state changes
        this.captureLayoutSnapshot();
        
        // Clear current records
        this.loading = true;
        
        // Reinitialize prompts - since we're not using separate methods for this in the original code,
        this.getPromptElementData();
    }

    // Check if we have any templates to display
    get hasCanvasTemplates() {
        return this.promptElements && this.promptElements.size > 0;
    }
    
    get hasPrompts() {
        return this.hasCanvasTemplates;
    }

    // Handle the card mutation when they received the data
    handleCardMutation(evt) {
        let templateComponent = JSON.parse(JSON.stringify(evt.detail.templateComponent));
        this.promptElements.set(templateComponent.Id, templateComponent);
        this.promptElements = new Map(this.promptElements);
        this.setCanvasContentBody();
        this.scheduleMasonryLayout(100);
        this.checkIfAllResponseReceived();
    }
    checkIfAllResponseReceived(){
        let allResponseReceived = true;
        let responseIds = [];
        for (const [key, value] of this.promptElements) {
            if(value?.summaryResponseDetails?.Id){
                responseIds.push(value?.summaryResponseDetails?.Id);
            }
            if(value?.responseDetails?.Id){
                responseIds.push(value?.responseDetails?.Id);
            }
            if(value?.summaryPrompt && value?.summaryResponse && value?.summaryResponse.length === 0){
                allResponseReceived = false;
            }
            if(value?.responseDetails && value?.responseDetails?.responseBody && value.responseDetails.responseBody.length === 0){
                allResponseReceived = false;
            }
            
        }
        if(allResponseReceived && !this.isUpdating && responseIds.length > 0){
            this.isUpdating = true;
            this.buttonComponentSettings.showZoomButton = true;
            this.updateParentResponse(responseIds);
        }
    }
    async updateParentResponse(responseIds){
        try{
            let response = await updateParentAIResponse({parentAIResponse : this.parentAIResponse.Id,childAiResponseIds : JSON.stringify(responseIds), recordId : this.recordId});
            if(response){
                this.parentAIResponse = JSON.parse(JSON.stringify(response));
                this.parentAIResponse[RESP_CREATED.fieldApiName] = this.parentAIResponse[RESP_LAST_MODIFIED_DATE.fieldApiName];
                this.timeSaved = this.parentAIResponse[TIME_SAV_FIELD.fieldApiName];
                this.fireSecurityAuditUpdateEvent();
            }
        }catch(error){
            console.log(JSON.stringify(error));
        }
    }
    fireSecurityAuditUpdateEvent(){
        this.dispatchEvent(new CustomEvent('parentresponseupdated', 
            {
                detail :{
                    parentAIResponse : this.parentAIResponse
                },
                bubbles : true,
                composed : true
            }));
    }
    // Set the canvasbody so that it can directly used in pdf generation, copy and emails
    setCanvasContentBody(){
        let tempResponse = '';
        for (const [key, value] of this.promptElements) {
            tempResponse+= value?.responseDetails && value?.responseDetails?.responseBody && value?.responseDetails?.responseBody.length > 0 ? value?.responseDetails?.responseBody : '';
            tempResponse+='<br><br>';
        }
        this.canvasBodyContent = tempResponse;
        this.fireBodyContentChange();
    }
    fireBodyContentChange(){
        this.dispatchEvent(new CustomEvent('bodychange', 
            {
                detail : {
                    canvasBodyContent : this.canvasBodyContent
                },
                bubbles:true,
                composed:true
            }));
    }

    // Update the feedback type locally so that the button remains disable if feedback is captured
    handleFeedbackCaptured(evt){
        let templateComponent = this.promptElements.get(evt.detail.templateComponentId);
        templateComponent.responseDetails.feedbackType = evt.detail.dislikeState === true ? 'Dislike' : '';
        this.promptElements.set(evt.detail.templateComponentId, templateComponent);
        this.promptElements = new Map(this.promptElements);
    }
    handleFeedbackOpenClose(evt){
        this.showFeedbackModal = evt.detail.showFeedbackModal;
    }
    handleDislikeButtonClick() {
        this.showFeedbackModal = true;
    }
    get feedbackTitle(){
        return this.dislikeState === true ? "Feedback Given" : "Give Feedback";
    }
    fireFeedbackCaptured(evt){
        this.dislikeState = evt.detail.dislikeState;
    }
    handleHowItWorks(){
        if(this.showHowItWorksDocked){
            this.showHowItWorksDocked = false;
        }else{
            this.showHowItWorksDocked = true;
        }
    }
    get showFooter(){
        return this.showHeader && this.canvasMessage === '';
    }
    get parentResponseId(){
        return this.parentAIResponse ? this.parentAIResponse.Id : '';
    }
    @api 
    resizeCanvas(){
        this.applyMasonryLayout();
    }
    handleZoomOut(){
        this.showPopOutContent = true;
    }
    handlePopOutContent(){
        this.showPopOutContent = false;
    }
    get canvasConfig(){
        return {
            notInitialLoad: false,objectApiName:this.objectApiName,parentAIResponseId:this.parentAIResponse.Id,promptValue:'',recordId:this.recordId,
            showCanvas:true,showCanvasHeader:false,skipWireUpdate:false,existingParentAIResponse:''
        }
    }
}