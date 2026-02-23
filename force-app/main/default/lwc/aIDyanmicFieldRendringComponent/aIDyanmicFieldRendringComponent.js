import { LightningElement, api, track, wire } from 'lwc';
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import AI_RESPONSE_OBJ from '@salesforce/schema/AI_Response__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getFieldData from '@salesforce/apex/AIDyanmicFieldRendringController.getFieldData';

export default class AIDyanmicFieldRendringComponent extends LightningElement {
    @api recordId;
    @api fieldApiName;
    @api fieldName;
    @track showModal = false;
    @track fieldVal = '';
    @track fields = [];
    @track data;

    @track aiRes = AI_RESPONSE_OBJ;

    @wire(getObjectInfo, {objectApiName: AI_RESPONSE_OBJ})
    results({error, data}){
        if(data){
            if(data && data.fields){
                var apiNames = this.fieldApiName.split(';');
                for(var field in data.fields){
                    if(apiNames && apiNames.length > 0){
                        for(var apiName of apiNames){
                            if(field.endsWith(apiName)){
                                this.fields.push(data.fields[field]);
                                break;
                            }
                        } 
                    }
                }
            }
            if(this.fields && this.fields.length > 0){
                this.doInit();
            }
        }
    }

    async doInit(){
        var fieldNames = [];
        for(var field of this.fields){
            fieldNames.push(field.apiName);
        }
        await getFieldData({
            "fieldNames" : fieldNames,
            "recordId" : this.recordId
        })
        .then(result => {
            if(result){
                var data = [];
                for(var field of this.fields){
                    if(field.apiName && result[field.apiName]){
                        data.push({'apiName':field.apiName, 'label':field.label, 'value':result[field.apiName]});
                    }
                }
                this.data = JSON.parse(JSON.stringify(data));
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleClick(event) {
        this.showModal = !this.showModal;
        this.fieldVal = undefined;
        if(event && event.target && event.target.name){
            for(var dt of this.data){
                if(dt.apiName == event.target.name){
                    this.fieldVal = dt.value;
                    break;
                }
            }
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