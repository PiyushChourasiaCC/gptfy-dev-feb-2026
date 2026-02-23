import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, updateRecord } from "lightning/uiRecordApi";

import getMergeObjects from '@salesforce/apex/AIPromptController.getMergeObjects';
import getMergeFields from '@salesforce/apex/AIPromptController.getMergeFields';

import ID_FIELD from "@salesforce/schema/AI_Prompt__c.Id";
import DATA_EXT_FIELD from "@salesforce/schema/AI_Prompt__c.AI_Data_Extraction_Mapping__c";
import PMT_CMD_FIELD from "@salesforce/schema/AI_Prompt__c.Prompt_Command__c";
import PMT_TYPE_FIELD from "@salesforce/schema/AI_Prompt__c.Type__c";

const fields = [DATA_EXT_FIELD, PMT_CMD_FIELD, PMT_TYPE_FIELD];

export default class AIPromptCommandBuilder extends LightningElement {

    @api recordId;
    @api readOnly;
    @api fieldValue;
    @api invokedFromChild = false;

    @track showSpinner = false;

    @track promptCommand;
    @track originalPromptCommand;
    @track mergeFieldObjectOptions;
    @track mergeFieldOptions;
    @track selectedMergeFieldObjectOption;
    @track selectedMergeFieldOption;
    @track extractionMappingId;

    @track isJsonPrompt;

    @wire(getRecord, { recordId: "$recordId", fields })
    wiredRecord({error, data}){
        if(error){
            this.handleError(error);
        }else if(data){
            var pmtType;
            if(data.fields && data.fields[PMT_TYPE_FIELD.fieldApiName] && data.fields[PMT_TYPE_FIELD.fieldApiName].value){
                pmtType = data.fields[PMT_TYPE_FIELD.fieldApiName].value;
            }

            this.extractionMappingId = data.fields[DATA_EXT_FIELD.fieldApiName].value;
            var pmtCommand = data.fields[PMT_CMD_FIELD.fieldApiName].value ? data.fields[PMT_CMD_FIELD.fieldApiName].value : '';

            if(this.invokedFromChild){
                this.promptCommand = this.fieldValue;
                this.originalPromptCommand = this.fieldValue;
            }else{
                this.promptCommand = pmtCommand;
                this.originalPromptCommand = pmtCommand;
            }
            
            this.isJsonPrompt = false;
            if(pmtType == 'JSON'){
                this.isJsonPrompt = true;
            }else{
                this.getMergeObjectsData();
            }
            
        }
    }

    async doInit(){}

    //get extractionMappingId() {
        //return getFieldValue(this.prompt.data, DATA_EXT_FIELD);
    //}

    //connectedCallback() {
        //this.getMergeObjectsData();
    //}

    @api
    getValue(){
        var obj = {'apiName':PMT_CMD_FIELD.fieldApiName, 'value':this.promptCommand};
        return obj;
    }

    get showSaveButton(){
        if(this.promptCommand !== this.originalPromptCommand && !this.invokedFromChild){
            return true;
        }
        return false;
    }

    get disabledFieldOptions(){
        if(this.mergeFieldOptions && this.mergeFieldOptions.length > 0){
            return false;
        }
        return true;
    }

    get disabledCopyButton(){
        if(this.selectedMergeFieldObjectOption && this.selectedMergeFieldOption){
            return false;
        }
        return true;
    }

    handlePromptCommandChange(event) {
        this.promptCommand = event.target.value;
        const selectedEvent = new CustomEvent("fieldchange");
        this.dispatchEvent(selectedEvent);
    }

    handleMergeFieldObjectChange(event) {
        this.selectedMergeFieldObjectOption = event.target.value;
        this.getMergeFieldsData();
    }

    handleMergeFieldChange(event) {
        this.selectedMergeFieldOption = event.target.value;
    }

    getMergeObjectsData() {
        this.showSpinner = true;
        this.mergeFieldOptions = undefined;
        this.mergeFieldObjectOptions = undefined;
        this.selectedMergeFieldObjectOption = undefined;
        this.selectedMergeFieldOption = undefined;

        getMergeObjects({
            "extId": this.extractionMappingId
        })
        .then(result => {
            if (result && result.length > 0) {
                this.mergeFieldObjectOptions = JSON.parse(JSON.stringify(result));
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    getMergeFieldsData() {
        this.showSpinner = true;
        this.mergeFieldOptions = undefined;
        this.selectedMergeFieldOption = undefined;

        var objName;
        for (var opt of this.mergeFieldObjectOptions) {
            if (opt.value == this.selectedMergeFieldObjectOption) {
                objName = opt.label;
                break;
            }
        }

        getMergeFields({
            "detailId": this.selectedMergeFieldObjectOption,
            "extId": this.extractionMappingId,
            "objName": objName
        })
        .then(result => {
            if (result && result.length > 0) {
                this.mergeFieldOptions = JSON.parse(JSON.stringify(result));
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleCancel(){
        this.promptCommand = this.originalPromptCommand;
    }

    handleSave(){
        this.updatePromptCommand();
    }

    updatePromptCommand(){
        var fields = {[ID_FIELD.fieldApiName]: this.recordId, [PMT_CMD_FIELD.fieldApiName]: this.promptCommand};
        const recordInput = {fields};
        updateRecord(recordInput)
        .then((result) => {
            this.showToast('success', 'Success', 'Prompt Command updated successfully.');
        })
        .catch((error) => {
            this.handleError(error);
        });
    }

    handleCopy() {
        if (this.selectedMergeFieldOption) {
            var mergeField = '{{{' + this.selectedMergeFieldOption + '}}}';
            //navigator.clipboard.writeText(mergeField);
            const listener = function(ev) {
                ev.preventDefault();
                ev.clipboardData.setData('text/plain', mergeField);
            };
            document.addEventListener('copy', listener);
            document.execCommand('copy');
            document.removeEventListener('copy', listener);
        }
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
    }

}