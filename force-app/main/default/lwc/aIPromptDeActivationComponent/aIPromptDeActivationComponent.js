import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { updateRecord } from 'lightning/uiRecordApi';

import deactivatePrompt from '@salesforce/apex/AIPromptDeactivateController.deactivatePrompt';

export default class AIPromptDeActivationComponent extends LightningElement {
    @api recordId;

    retrievedRecordId = false;
    showSpinner = true;

    renderedCallback() {
        if (!this.retrievedRecordId && this.recordId) {
            this.retrievedRecordId = true;
            this.runPromptDeActivation();
        }
    }

    runPromptDeActivation() {
        deactivatePrompt({
            "recordId": this.recordId
        }).then(result => {
                if (result && result.length > 0) {
                    this.showToast('error', 'Error', result);
                } else {
                    this.showToast('success', 'Success', 'Prompt Deactivated Successfully.');
                }
                updateRecord({ fields: { Id: this.recordId } });
                this.closeQuickAction();
            })
            .catch(error => {
                this.handleError(error);
            });
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant: variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    handleError(error) {
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if (error && error.body && error.body.message) {
            this.showToast('error', 'Error', error.body.message);
        } else {
            this.showToast('error', 'Error', error.toString());
        }
        this.closeQuickAction();
    }

    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}