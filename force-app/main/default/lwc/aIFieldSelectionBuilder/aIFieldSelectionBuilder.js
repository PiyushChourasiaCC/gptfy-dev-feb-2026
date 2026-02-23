import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from "lightning/uiRecordApi";

import PMT_OBJ from "@salesforce/schema/AI_Prompt__c";

import PMT_ID_FIELD from "@salesforce/schema/AI_Prompt__c.Id";
import PMT_OBJ_FIELD from "@salesforce/schema/AI_Prompt__c.Object__c";

import getTargetFieldOptions from '@salesforce/apex/AIPromptBuilderController.getTargetFieldOptions';

export default class AIFieldSelectionBuilder extends LightningElement {

    @api fieldLabel;
    @api fieldApiName;
    @api fieldValue;
    @api required;
    @api recordId;
    @api readOnly = false;

    @track fieldApiNames = [];
    @track promptObjectApi = PMT_OBJ.objectApiName;
    @track fieldOptions;

    async connectedCallback(){
        this.fieldApiNames = [
            PMT_ID_FIELD, 
            PMT_OBJ_FIELD,
            {
                "fieldApiName" : this.fieldApiName,
                "objectApiName" : PMT_OBJ.objectApiName
            }
        ];
    }

    @track objName;
    @track selectedValue;
    @wire(getRecord, { recordId: "$recordId", optionalFields: '$fieldApiNames' })
    wiredRecord({error, data}){
        if(error){
            this.handleError(error);
        }else if(data){
            if(data.fields && data.fields[PMT_OBJ_FIELD.fieldApiName] && data.fields[PMT_OBJ_FIELD.fieldApiName].value){
                this.objName = data.fields[PMT_OBJ_FIELD.fieldApiName].value;
                this.doInit();
            }
        }
    }

    async doInit(){
        getTargetFieldOptions({
            "objName" : this.objName
        })
        .then(result => {
            this.fieldOptions = JSON.parse(JSON.stringify(result));
            this.selectedValue = this.fieldValue;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleFieldChange(event){
        this.selectedValue = event.target.value;
        const selectedEvent = new CustomEvent("fieldchange", {
            detail : {'apiName':this.fieldApiName, 'required':this.required, 'value':this.selectedValue}
        });
        this.dispatchEvent(selectedEvent);
    }

    @api
    getValue(){
        var obj = {'apiName':this.fieldApiName, 'required':this.required, 'value':this.selectedValue};
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