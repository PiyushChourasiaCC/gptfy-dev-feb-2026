import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { updateRecord } from 'lightning/uiRecordApi';
import validateDataContextMapping from '@salesforce/apex/AIJsonGeneration.validateDataContextMapping';
import AIPrompt from "@salesforce/messageChannel/AI_Prompt__c"
import {subscribe, MessageContext, APPLICATION_SCOPE,   
        unsubscribe,publish} from 'lightning/messageService';

export default class AIDataContextMappingActivationComponent extends LightningElement {
    @api recordId;

    retrievedRecordId = false;
    showSpinner = true;

    @wire(MessageContext)
    context;

    renderedCallback(){
        if (!this.retrievedRecordId && this.recordId) {
            this.retrievedRecordId = true;
            this.runDataContextMappingActivation();
        }
    }

    runDataContextMappingActivation(){
        this.showSpinner = true;
        validateDataContextMapping({
            "recordId" : this.recordId
        })
        .then(result => {         
            if(result && result.length > 0){
                this.showToast('error', 'Error', result);
            }else{
                this.showToast('success', 'Success', 'Data Context Mapping Activated Successfully.');
            }
            updateRecord({ fields: { Id: this.recordId }});
            publish(this.context, AIPrompt, {'isRefresh':true});
            this.closeQuickAction();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
        this.closeQuickAction();
    }

    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }


}