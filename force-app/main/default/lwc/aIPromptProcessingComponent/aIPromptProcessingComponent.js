import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord, createRecord, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import PROMPT_PROCESS_OBJ from '@salesforce/schema/AI_Response_Processing__c';

import ID_FIELD from '@salesforce/schema/AI_Response_Processing__c.Id';
import PMT_CMP_FIELD from '@salesforce/schema/AI_Response_Processing__c.AI_Prompt_Component__c';
import ACTION_FIELD from '@salesforce/schema/AI_Response_Processing__c.Action__c';
import DESC_FIELD from '@salesforce/schema/AI_Response_Processing__c.Description__c';
import TIMESTAMP_FIELD from '@salesforce/schema/AI_Response_Processing__c.Append_Timestamp__c';
import DEST_FIELD from '@salesforce/schema/AI_Response_Processing__c.Destination_Field__c';

import getPromptProcessingData from '@salesforce/apex/AIPromptComponentController.getPromptProcessingData';
import getResponseProcessingData from '@salesforce/apex/AIPromptComponentController.getResponseProcessingData';

const actions = [
    { label: 'Edit', name: 'edit'},
    { label: 'Delete', name: 'delete' },
];

export default class AIPromptProcessingComponent extends LightningElement {

    @api recordId;
    @track records;
    @track fields;
    @track showSpinner = false;

    defaultSortDirection = 'asc';
    sortDirection = 'asc';
    sortedBy;

    @track showAddModal = false;
    @track selectedRecordId;

    @track promotProcessingObjectName;
    @track actionFieldApi;
    @track descFieldApi;
    @track destFieldApi;
    @track timestampFieldApi;

    @track helpText_fieldApi;
    
    @track showAppendTimestampField = false;

    @wire(getObjectInfo, { objectApiName: PROMPT_PROCESS_OBJ })
    wiredRecord({ error, data }) {
        if(error){
            this.handleError(error);
        }else if(data){
            if(data.fields){
                if(data.fields['Destination_Field__c'] && data.fields['Destination_Field__c'].inlineHelpText){
                    this.helpText_fieldApi = data.fields['Destination_Field__c'].inlineHelpText;
                }
            }
        }
    }

    connectedCallback(){
        this.promotProcessingObjectName = PROMPT_PROCESS_OBJ.objectApiName;
        this.actionFieldApi = ACTION_FIELD.fieldApiName;
        this.descFieldApi = DESC_FIELD.fieldApiName;
        this.destFieldApi = DEST_FIELD.fieldApiName;
        this.timestampFieldApi = TIMESTAMP_FIELD.fieldApiName;

        this.getObjectsFromMapping();
    }

    async getObjectsFromMapping(){
        this.showSpinner = true;
        this.fields = undefined;
        this.records = undefined;
        this.selectedRecordId = undefined;

        await getPromptProcessingData({
            "recordId" : this.recordId
        })
        .then(result => {          
            //console.log('result: '+JSON.stringify(result));
            if(result && result.records && result.records.length > 0){
                var tempFields = JSON.parse(JSON.stringify(result.fields));
                for(var field of tempFields){
                    field['sortable'] = true;
                    //if(field.fieldName == 'Name'){
                        //field['type'] = 'url';
                        //field['typeAttributes'] = {label:{fieldName:field.fieldName}, tooltip:{fieldName : field.fieldName}, target: "_self"};
                        //field['fieldName'] = field.fieldName+"_____recordLink";
                    //}
                }
                var actionObj = {
                    type: 'action',
                    typeAttributes: { rowActions: actions },
                }
                tempFields.push(actionObj);
                this.fields = JSON.parse(JSON.stringify(tempFields));

                var tempRecords = JSON.parse(JSON.stringify(result.records));
                //for(var rec of tempRecords){
                    //rec['Name_____recordLink'] = '/'+rec['Id'];
                //}
                this.records = JSON.parse(JSON.stringify(tempRecords));
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if(row && row.Id){
            this.selectedRecordId = row.Id;
            if(actionName == 'edit'){
                this.handleAddModal();
            }else if(actionName == 'delete'){
                deleteRecord(this.selectedRecordId)
                .then(() => {
                    this.showToast('success', 'Success', 'Record Deleted Successfully.');
                    this.getObjectsFromMapping();
                })
                .catch(error => {
                    this.handleError(error);
                });
            }
        }
    }

    handleAddModal(){
        if(this.showAddModal){
            this.showAddModal = false;
            this.getObjectsFromMapping();
        }else{
            this.showAddModal = true;
            this.getProcessingData();
        }
    }

    fieldOptions;
    destinationFieldApi;
    description;
    action;
    async getProcessingData(){
        this.showSpinner = true;
        this.fieldOptions = undefined;
        await getResponseProcessingData({
            "recordId" : this.selectedRecordId,
            "parentId" : this.recordId
        })
        .then(result => {          
            if(result && result.action){
                this.action = result.action;
                this.description = result.description;
                this.destinationFieldApi = result.destinationFieldApi;
            }
            if(result && result.fieldOptions && result.fieldOptions.length > 0){
                this.fieldOptions = JSON.parse(JSON.stringify(result.fieldOptions));
            }
            const res = this.fieldOptions.find(item => item.value === this.destinationFieldApi);
            if(res && (res.fieldType == 'STRING' || res.fieldType == 'TEXTAREA')){
                this.showAppendTimestampField = true;
            }else{
                this.showAppendTimestampField = false;
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleFieldChange(event){
        this.destinationFieldApi = event.target.value;
        const result = this.fieldOptions.find(item => item.value === this.destinationFieldApi);
        if(result && (result.fieldType == 'STRING' || result.fieldType == 'TEXTAREA')){
            this.showAppendTimestampField = true;
        }else{
            this.showAppendTimestampField = false;
        }
    }

    handleSave(){
        var data = {};
        const inputFields = this.template.querySelectorAll('lightning-input-field');
        if(inputFields){
            inputFields.forEach(field =>{
                data[field.fieldName] = field.value;
            });
        }

        data[DEST_FIELD.fieldApiName] = this.destinationFieldApi;
        if(this.selectedRecordId){
            data[ID_FIELD.fieldApiName] = this.selectedRecordId;
        }else{
            data[PMT_CMP_FIELD.fieldApiName] = this.recordId;
        }

        if(!data[DEST_FIELD.fieldApiName] || data[DEST_FIELD.fieldApiName] == '' || data[DEST_FIELD.fieldApiName] == null){
            this.showToast('error', 'Error', 'Destination Field is required.');
        }else if(!data[ACTION_FIELD.fieldApiName] || data[ACTION_FIELD.fieldApiName] == '' || data[ACTION_FIELD.fieldApiName] == null){
            this.showToast('error', 'Error', 'Action is required.');
        }else{
            if(this.selectedRecordId){
                this.updatePromptComponent(data);
            }else{
                this.createPromptComponent(data);
            }
        }
    }

    updatePromptComponent(data){
        console.log('updatePromptComponent: '+JSON.stringify(data));
        this.showSpinner = true;
        const recordInput = {'fields':data};
        updateRecord(recordInput)
        .then(result => {
            this.showToast('success', 'Success', 'Record updated successfully.');
            this.handleCancel();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    createPromptComponent(data){
        this.showSpinner = true;
        console.log('createPromptComponent: '+JSON.stringify(data));
        const recordInput = {apiName:PROMPT_PROCESS_OBJ.objectApiName, 'fields':data};
        createRecord(recordInput)
        .then(result => {
            this.showToast('success', 'Success', 'Record created successfully.');
            this.handleCancel();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    sortBy(field, reverse, primer) {
        const key = primer
            ? function (x) {
                  return primer(x[field]);
              }
            : function (x) {
                  return x[field];
              };

        return function (a, b) {
            a = key(a);
            b = key(b);
            return reverse * ((a > b) - (b > a));
        };
    }

    onHandleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        const cloneData = [...this.records];

        cloneData.sort(this.sortBy(sortedBy, sortDirection === 'asc' ? 1 : -1));
        this.records = cloneData;
        this.sortDirection = sortDirection;
        this.sortedBy = sortedBy;
    }

    handleCancel(){
        this.handleAddModal();
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
        if(error && error.body && error.body.output && error.body.output.errors && error.body.output.errors.length > 0 && error.body.output.errors[0].message){
            this.showToast('error', 'Error', error.body.output.errors[0].message);
        }else if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }

}