import { LightningElement, api, track, wire } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import runTestCycle from '@salesforce/apex/AIAgenticTestingFrameworkCtrl.runTestCycle';
export default class AIRunTestCycle extends LightningElement {

    @api recordId;

    @track retrievedRecordId = false;
    @track showSpinner = true;

    renderedCallback() {
        if (!this.retrievedRecordId && this.recordId) {
            this.retrievedRecordId = true;
            this.doInit();
        }
    }

    async doInit(){
        this.showSpinner = true;
        await runTestCycle({
            recordId : this.recordId
        })
        .then(result => {        
            this.showToast('success', 'Success', 'Test Cycle execution started successfully.');
            updateRecord({ fields: { Id: this.recordId }});
            this.closeQuickAction();
        })
        .catch(error => {
            this.handleError(error);
            this.closeQuickAction();
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

    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }
}