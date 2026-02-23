import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord  } from 'lightning/uiRecordApi';

import PROMPT_SCHEDULER_OBJ from '@salesforce/schema/AI_Prompt_Scheduler__c';


import getPromptSchedulerData from '@salesforce/apex/AIPromptSchedulerController.getPromptSchedulerData';
import getPromptSchedulerDetail from '@salesforce/apex/AIPromptSchedulerController.getPromptSchedulerDetail';
import getPromptOptions from '@salesforce/apex/AIPromptSchedulerController.getPromptOptions';

const actions = [
    { label: 'Edit', name: 'edit'},
    { label: 'Delete', name: 'delete' },
];

export default class AIPromptSchedulerComponent extends LightningElement {
    @api recordId;

    @track records;
    @track fields;
    @track showSpinner;

    defaultSortDirection = 'asc';
    sortDirection = 'asc';
    sortedBy;

    @track helpText_Prompt;
    @track helpText_RecordLimit;
    @track helpText_WhereClause;

    @track showAddModal = false;
    @track selectedRecordId;
    @track selectedObjectName;

    @track promptSchedulerObjectApi;
    @track promptFieldApi;
    @track recordLimitFieldApi;
    @track whereClauseFieldApi;

    @track editPromptSchedulerData;
    @track isEditMode = false;

    @track promptOptions;


    connectedCallback(){
        this.promptSchedulerObjectApi = PROMPT_SCHEDULER_OBJ.objectApiName;
        
            this.getAllPromptOptions();
            this.getPromptSchedulers();
        
    }

    async getPromptSchedulers(){
        this.showSpinner = true;
        this.fields = undefined;
        this.records = undefined;
        this.selectedRecordId = undefined;
        this.selectedObjectName = undefined;

        await getPromptSchedulerData({
            "recordId" : this.recordId
        })
        .then(result => {          
            //console.log('result: '+JSON.stringify(result));
            if(result && result.records && result.records.length > 0){
                var tempFields = JSON.parse(JSON.stringify(result.fields));

                var referenceFields = [];
                for(var field of tempFields){
                    field['sortable'] = true;
                    if(field.fieldName == 'Name' || field.isReference == true){
                        if(field.isReference == true){
                            referenceFields.push(field.fieldName);
                        }
                        field['type'] = 'url';

                        let refField = field.fieldName;
                        if(refField.endsWith('__c')){
                            refField = refField.slice(0, -3)+'__r.Name';
                        }else if(refField.endsWith('Id')){
                            refField = refField.slice(0, -2)+'.Name';
                        }
                        referenceFields.push(refField);

                        field['typeAttributes'] = {label:{fieldName:refField}, tooltip:{fieldName : refField}, target: "_self"};
                        field['fieldName'] = field.fieldName+"_____recordLink";                   
                    }
                }
                var actionObj = {
                    type: 'action',
                    typeAttributes: { rowActions: actions },
                }
                tempFields.push(actionObj);
                this.fields = JSON.parse(JSON.stringify(tempFields));

                var tempRecords = JSON.parse(JSON.stringify(result.records));
                for(var rec of tempRecords){
                    if(referenceFields && referenceFields.length > 0){
                        for(var refField of referenceFields){
                            if(refField == 'Name'){
                                rec['Name_____recordLink'] = '/'+rec['Id'];
                            }else{
                                if(refField.includes('.')){
                                    rec[refField] = rec[refField.split('.')[0]][refField.split('.')[1]];
                                }else{
                                    rec[refField+'_____recordLink'] = '/'+rec[refField];
                                }
                            }
                        }
                    }
                }

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
                //this.showAddModal = true;
                this.getCurrentPromptSchedulerDetail(this.selectedRecordId);
                this.handleAddModal();    
            }else if(actionName == 'delete'){
                deleteRecord(this.selectedRecordId)
                .then(() => {
                    this.showToast('success', 'Success', 'Record Deleted Successfully.');
                    this.getPromptSchedulers();
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
            this.getPromptSchedulers();
        }else{
            this.showAddModal = true;
            this.schedulerData = {};
        }
    }

    getAllPromptOptions(){
        this.showSpinner = true;
        getPromptOptions()
        .then(result => {
            this.promptOptions = JSON.parse(JSON.stringify(result));
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleCancel(){
        this.handleAddModal();
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


    @track schedulerData;
    getCurrentPromptSchedulerDetail(recId){
        this.schedulerData = {};
        getPromptSchedulerDetail({
            "recordId" : recId
        })
        .then(result => {
            this.schedulerData = JSON.parse(JSON.stringify(result));
            if(this.schedulerData && this.schedulerData['objectName']){
                this.selectedObjectName = this.schedulerData['objectName'];
            }
            this.showAddModal = true;
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
        if(error && error.body && error.body.output && error.body.output.errors && error.body.output.errors.length > 0 && error.body.output.errors[0].message){
            this.showToast('error', 'Error', error.body.output.errors[0].message);
        }else if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }
}