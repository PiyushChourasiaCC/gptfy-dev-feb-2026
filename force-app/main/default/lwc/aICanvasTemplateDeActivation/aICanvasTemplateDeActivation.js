import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { updateRecord } from 'lightning/uiRecordApi';
import deActivateCanvasTemplate from '@salesforce/apex/AICanvasTemplateStatusManager.deActivateCanvasTemplate';

export default class AICanvasTemplateDeActivation extends LightningElement {
    @api recordId;
    isExecuting = false;

    // method that available for headless quick actions
    @api 
    async invoke() {
        // Prevent multiple executions
        if (this.isExecuting) {
            return;
        }
        
        this.isExecuting = true;
        try{
            // deactivate the canvas template
            await deActivateCanvasTemplate({recordId : this.recordId});
            this.showToast('success', 'Success', 'Canvas Template Deactivated Successfully!');
            // update the record to reflect the changes
            updateRecord({ fields: { Id: this.recordId }});
        }catch(error){
            this.showToast('error', 'Error', error);
        }finally{
            this.closeQuickAction();
            this.isExecuting = false;
        }
    }
    // toast Notification
    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    // close the modal
    handleClose(event){
        this.closeQuickAction();
    }
    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}