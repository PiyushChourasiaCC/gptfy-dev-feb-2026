import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import upsertResponseValidation from '@salesforce/apex/AIResponseValidationController.upsertResponseValidation';

export default class AIAddResponseValidationComponent extends LightningElement {

    _promptId;
    _responseValidationId;
    _sequence;
    _actionOptions;
    _validationAction;
    _validationValue;

    @track showSpinner = false;

    @api 
    set responseValidationId(value){this._responseValidationId = value;}
    get responseValidationId(){return this._responseValidationId;}

    @api 
    set sequence(value){this._sequence = value;}
    get sequence(){return this._sequence;}

    @api 
    set validationAction(value){this._validationAction = value;}
    get validationAction(){return this._validationAction;}

    @api 
    set validationValue(value){this._validationValue = value;}
    get validationValue(){return this._validationValue;}

    @api 
    set actionOptions(value){this._actionOptions = value;}
    get actionOptions(){return this._actionOptions;}

    @api 
    set promptId(value){
        this._promptId = value;
    }
    get promptId(){
        return this._promptId;
    }

    sequenceHelpText = "Range: 1 - 99. Sequence number assigned here are used to define 'Response Validation Condition'.";

    handleSequenceChange(event){
        this.sequence = event.target.value;
    }

    handleValidationActionChange(event){
        this.validationAction = event.target.value;
    }

    handleValidationValueChange(event){
        this.validationValue = event.target.value;
    }

    handleCancel(){
        const selectedEvent = new CustomEvent("close");
        this.dispatchEvent(selectedEvent);
    }

    handleSave(){
        if(!this.sequence || this.sequence == '' || this.sequence == null || this.sequence <= 0){
            this.showToast('warning', 'Alert', 'Sequence is required and can only be a positive Integer.');
        }else if(!this.validationAction || this.validationAction == '' || this.validationAction == null){
            this.showToast('warning', 'Alert', 'Action is required.');
        }else if(!this.validationValue || this.validationValue == '' || this.validationValue == null){
            this.showToast('warning', 'Alert', 'Value is required.');
        }else{
            var obj = {
                "promptId" : this.promptId,
                "responseValidationId" : this.responseValidationId,
                "validationAction" : this.validationAction,
                "validationValue": this.validationValue,
                "sequence" : this.sequence+''
            };
            this.saveRecord(obj);
        }
    }

    async saveRecord(obj){
        this.showSpinner = true;
        await upsertResponseValidation({
            "data" : obj,
        })
        .then(result => {          
            this.showToast('success', 'Success', 'Record inserted sucessfully.');
            const selectedEvent = new CustomEvent("refresh");
            this.dispatchEvent(selectedEvent);
            this.handleCancel();
            this.showSpinner = false;
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
    }

}