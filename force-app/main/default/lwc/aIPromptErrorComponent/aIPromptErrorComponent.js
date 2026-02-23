import { LightningElement,wire,api } from 'lwc';
import { getRecord } from "lightning/uiRecordApi";
import PROMPT_MESSAGE_FIELD from '@salesforce/schema/AI_Prompt__c.Message__c';
import PROMPT_ID_FIELD from '@salesforce/schema/AI_Prompt__c.Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PMT_FIELDS = [PROMPT_ID_FIELD,PROMPT_MESSAGE_FIELD];

export default class AIPromptErrorComponent extends LightningElement {

    @api recordId
    message = ''
    errorMessageVisible = false;

    @wire(getRecord, { recordId: "$recordId", fields: PMT_FIELDS})
        wiredRecord({error, data}){
            if(error){
                this.handleError(error);
            }else if(data){
                if(data.fields && data.fields[PROMPT_MESSAGE_FIELD.fieldApiName] && data.fields[PROMPT_MESSAGE_FIELD.fieldApiName].value){
                    this.errorMessageVisible = true;
                    this.message = data.fields[PROMPT_MESSAGE_FIELD.fieldApiName].value;
                }else{
                    this.errorMessageVisible = false;
                    this.message = '';
                }
            }
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

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }
}