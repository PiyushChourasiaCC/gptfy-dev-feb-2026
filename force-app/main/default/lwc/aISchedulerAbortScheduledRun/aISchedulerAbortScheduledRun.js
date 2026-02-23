import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import abortJobs from '@salesforce/apex/AISchedulerOverrideController.abortJobs';

export default class AISchedulerAbortScheduledRun extends NavigationMixin(LightningElement) {
 
    showSpinner = false;
    header = 'Cancel';
    @api recordId;

    handleConfirm(event){
        this.showSpinner = true;
        abortJobs({recordId:this.recordId})
        .then(result => {    
            this.navigateToViewRecordPage(this.recordId);
            this.showToast('success', 'Success', 'Scheduled Run cancelled successfully!');    
        })
        .catch(error => {
            this.handleError(error); 
        });
    }

     navigateToViewRecordPage(recId) {
        // Navigate to the view record page
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recId,
                actionName: 'view'
            }
        });
    }

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    handleClose(event){
        this.dispatchEvent(new CloseActionScreenEvent());
    }

}