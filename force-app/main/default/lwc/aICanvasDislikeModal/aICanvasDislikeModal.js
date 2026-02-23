import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveFeedback from '@salesforce/apex/GPTfyConsoleController.saveFeedback';

export default class AICanvasDislikeModal extends LightningElement {
    @api categoryOptions;
    @api responseId;
    isFeedbackCaptured = false;
    feedbackCategory = [];
    feedbackDetail = '';
    feedbackDetailPlaceholder = "What was the issue with the response? How could it be improved?";

    handleSubmitFeedback(){
        let feedback = 'Dislike';
        var feedbackCategory = this.feedbackCategory && this.feedbackCategory.length > 0 ? this.feedbackCategory.join(";") : '';
        var feedbackDetail = this.feedbackDetail ? this.feedbackDetail : '';
        saveFeedback({
            "responseId" : this.responseId, 
            "feedback" : feedback,
            "feedbackCategory" : feedbackCategory, 
            "feebackDetail" : feedbackDetail
        })
        .then(result => {
            this.showToast('Success', 'Feedback captured!', 'success');
            this.fireOpenCloseModal(true,false);
            this.fireFeedbackCaptured();
        })
        .catch(error => {
            this.showToast('Error', error, 'error');
        });
    }
    fireFeedbackCaptured(){
        this.dispatchEvent(new CustomEvent('feedbackcaptured', 
            { detail : {
                dislikeState : true
            }}));
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
    handleFeedbackCancel(){
        this.feedbackDetail = '';
        this.feedbackCategory = [];
        this.fireOpenCloseModal(true, false);
    }
    handleFeedbackDetailChange(event){
        this.feedbackDetail = event.target.value;
    }

    handleFeedbackCategoryChange(event){
        this.feedbackCategory = event.target.value;
    }
    fireOpenCloseModal(isOpen, showFeedbackModal){
        this.dispatchEvent(new CustomEvent('openclose' , 
            { detail : {
                isOpen : isOpen,
                showFeedbackModal : showFeedbackModal
            }
        }));
    }
}