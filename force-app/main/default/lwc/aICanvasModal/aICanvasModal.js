import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import TIME_ZONE from '@salesforce/i18n/timeZone';

export default class AICanvasModal extends LightningElement {
    timeZone = TIME_ZONE;
    @api recordId;
    @api title;
    @api isOpen = false;
    @api bodyContent;
    @api lastRefreshDate;
    @api emailActionName
    @api userSignature;
    @api templateComponentId;
    @api iconName;
    @api selectedComponent;
    @api hasAdminUser = false;
    @api namespace = '';

    @track categoryOptions;
    @track showHowItWorksDocked = false;
   

    @api 
    get feedbackCategoryOptions(){
        return this.categoryOptions;
    }
    set feedbackCategoryOptions(val){
        if(val){
            this.categoryOptions = JSON.parse(JSON.stringify(val));
        }
    }
    
    @api
    openModal() {
        this.isOpen = true;
        this.dislikeState = this.selectedComponent.responseDetails.feedbackType === '' ? false : true;
    }
    
    @api
    closeModal() {
        this.isOpen = false;
    }
    
    get linkTotheRecord(){
        return '/'+this.selectedComponent.responseDetails.Id;
    }

    // Settings for action button component
    get buttonComponentSettings(){
        return {isGlobalContext: false, showRefreshButton: false, showZoomButton : true};
    }
    
    get showHowItWorksLink(){
        return this.selectedComponent ? this.selectedComponent?.responseDetails?.howItWorks ? true : false : false; 
    }
    get timeSaved(){
        return this.selectedComponent ? this.selectedComponent?.responseDetails?.timeSaved ? this.selectedComponent?.responseDetails?.timeSaved : null : null;
    }
    handleHowItWorks(evt){
        this.showHowItWorksDocked = !this.showHowItWorksDocked;
    }
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
    handleFeedbackOpenClose(evt){
        this.isOpen = evt.detail.isOpen;
        this.showFeedbackModal = evt.detail.showFeedbackModal;
    }
    handleDislikeButtonClick() {
        this.isOpen = false;
        this.showFeedbackModal = true;
    }
    get feedbackTitle(){
        return this.dislikeState === true ? "Feedback Given" : "Give Feedback";
    }
    fireFeedbackCaptured(evt){
        this.dislikeState = evt.detail.dislikeState;
        this.dispatchEvent(new CustomEvent('feedbacksuccess', 
            { detail : {
                templateComponentId : this.templateComponentId,
                dislikeState : this.dislikeState
            }}));
    }
    get canvasConfig(){
        return {showCanvas: false};
    }
    get showFooter(){
        return this.selectedComponent?.responseDetails?.name;
    }
}