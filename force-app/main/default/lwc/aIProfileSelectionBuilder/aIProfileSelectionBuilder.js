import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProfileOptions from '@salesforce/apex/AIPromptBuilderController.getProfileOptions';

export default class AIProfileSelectionBuilder extends LightningElement {

    @api fieldLabel;
    @api fieldApiName;
    @api fieldValue;
    @api required;
    @api recordId;
    @api readOnly = false;

    @track profileOptions;
    @track selectedValues = [];

    async connectedCallback(){
        this.doInit();
    }

    async doInit(){
        getProfileOptions()
        .then(result => {
            this.profileOptions = JSON.parse(JSON.stringify(result));
            if(this.fieldValue){
                this.selectedValues = this.fieldValue.split(';');
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleProfileChange(event){
        this.selectedValues = event.target.value;
        const selectedEvent = new CustomEvent("fieldchange");
        this.dispatchEvent(selectedEvent);
    }

    @api
    getValue(){
        var values = '';
        if(this.selectedValues && this.selectedValues.length > 0){
            values = this.selectedValues.join(';');
        }
        var obj = {'apiName':this.fieldApiName, 'required':this.required, 'value':values};
        return obj;
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