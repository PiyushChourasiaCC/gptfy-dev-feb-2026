import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { updateRecord } from 'lightning/uiRecordApi';
import cloneRecord from '@salesforce/apex/AIPromptCloningController.cloneRecord';
import getAIPromptData from '@salesforce/apex/AIPromptCloningController.getAIPromptData';

export default class AIPromptCloning extends NavigationMixin(LightningElement) {

    @api recordId;

    @track retrievedRecordId = false;
    @track showSpinner = false;
    @track promptData = {};

    renderedCallback() {
        if (!this.retrievedRecordId && this.recordId) {
            this.retrievedRecordId = true;
            this.fetchAIPromptData();
        }
    }

    fetchAIPromptData(){
        this.showSpinner = true;
        getAIPromptData({
            recordId : this.recordId
        })
        .then(result => {
            this.promptData = JSON.parse(result);
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
            this.showSpinner = false;
        });
    }

    handleSave(event){
        let isValid = true;
        let inputFields = this.template.querySelectorAll('.validate');

        inputFields.forEach(inputField => {
            if(inputField.dataset.fieldname == 'DuplicateContextMapping'){
                this.promptData[inputField.dataset.fieldname] = inputField.checked;
            }else if (inputField.value) {
                this.promptData[inputField.dataset.fieldname] = inputField.value;
            }else if (inputField.required){
                inputField.reportValidity();
                isValid = false;
            }
        });

        if(isValid){
            this.showSpinner = true;
            this.init();
        }else{
            this.showToast('error', 'Error', 'Please fill all required information');
        }
    }

    handleCancel(event){
        this.closeQuickAction();
    }

    async init(){
        await cloneRecord({
            recordId : this.recordId,
            name : this.promptData.Name,
            description : this.promptData.Description,
            isDuplicateContextMapping : this.promptData.DuplicateContextMapping,
        })
        .then(result => {
            this.closeQuickAction();
            this.showToast('success', 'Success!', 'Prompt cloned successfully.');
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