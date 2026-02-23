import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { updateRecord } from 'lightning/uiRecordApi';
import cloneRecord from '@salesforce/apex/AIDataExtractionCloningController.cloneRecord';

export default class AIDataExtractionCloning extends NavigationMixin(LightningElement) {

    @api recordId;

    @track retrievedRecordId = false;
    @track showSpinner = true;

    renderedCallback() {
        if (!this.retrievedRecordId && this.recordId) {
            this.retrievedRecordId = true;
            this.init();
        }
    }

    async init(){
        await cloneRecord({
            recordId : this.recordId
        })
        .then(result => {
            this.closeQuickAction();
            this.showToast('success', 'Success!', 'Data Context Mapping cloned successfully.');
            this.handleNavigation(result);
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleNavigation(recId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recId,
                actionName: 'view',
            },
        });
    }

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            this.showToast('error', 'Cloning failed.', error.body.message);
        }else{
            this.showToast('error', 'Cloning failed.', error.toString());
        }
        this.closeQuickAction();
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    closeQuickAction() {
        this.refreshRecord();
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    refreshRecord(){
        const selectedEvent = new CustomEvent("refresh");
        this.dispatchEvent(selectedEvent);

        const fields = {'Id' : this.recordId};
        const recordInput = { fields };
        updateRecord(recordInput)
        .then(() => {
        })
        .catch(error => {
            this.handleError(error);
        });
    }

}