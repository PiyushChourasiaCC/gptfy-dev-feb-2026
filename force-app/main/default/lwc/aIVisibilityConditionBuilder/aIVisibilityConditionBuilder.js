import { LightningElement, api, wire } from 'lwc';
import { getRecord } from "lightning/uiRecordApi";
import AiPromptWhereClauseFormulaComponent from 'c/aiPromptWhereClauseFormulaComponent';

import PMT_VISIBILITY_CONDITION_FIELD from "@salesforce/schema/AI_Prompt__c.Visibility_Condition__c";
import PMT_TARGET_OBJECT_FIELD from "@salesforce/schema/AI_Prompt__c.Object__c";

const fields = [PMT_VISIBILITY_CONDITION_FIELD,PMT_TARGET_OBJECT_FIELD];

export default class AIVisibilityConditionBuilder extends LightningElement {
    @api fieldLabel;
    @api fieldApiName;
    @api fieldValue;
    @api required;
    @api recordId;
    @api readOnly = false;
    visibilityConditionValue = ''
    targetObj = ''

    @wire(getRecord, { recordId: "$recordId", fields })
    wiredRecord({error, data}){
        if(error){
            this.handleError(error);
        }else if(data){
            //if(data.fields && data.fields[PMT_VISIBILITY_CONDITION_FIELD.fieldApiName] && data.fields[PMT_VISIBILITY_CONDITION_FIELD.fieldApiName].value){
                //this.visibilityConditionValue = data.fields[PMT_VISIBILITY_CONDITION_FIELD.fieldApiName].value;
            //}
            this.visibilityConditionValue = this.fieldValue;
            if(data.fields && data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName] && data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName].value){
                this.targetObj = data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName].value;
            }
        }
    }

    handleFieldChange = (e)=> {
        this.visibilityConditionValue = e.target.value;
        const selectedEvent = new CustomEvent("fieldchange");
        this.dispatchEvent(selectedEvent);
    }

    handleOpenVisibilityCondition = async(e)=> {
        const result = await AiPromptWhereClauseFormulaComponent.open({
            size: 'medium',
            description: 'Visibility Condition',
            objectApiName: this.targetObj,
        });
        if (result) {
            this.visibilityConditionValue = result;
            const selectedEvent = new CustomEvent("fieldchange");
            this.dispatchEvent(selectedEvent);
        }
    }

    @api
    getValue(){
        var obj = {'apiName':this.fieldApiName, 'required':this.required, 'value':this.visibilityConditionValue};
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