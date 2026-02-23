import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord } from 'lightning/uiRecordApi';

import getPromptComponentData from '@salesforce/apex/AIPromptComponentController.getPromptComponentData';

const actions = [
    { label: 'Edit', name: 'edit'},
    { label: 'Delete', name: 'delete' },
];

export default class AIPromptRelatedComponent extends LightningElement {

    @api recordId;
    @track records;
    @track fields;
    @track showSpinner = false;

    defaultSortDirection = 'asc';
    sortDirection = 'asc';
    sortedBy;

    @track showAddModal = false;
    @track selectedRecordId;

    connectedCallback(){
        this.getObjectsFromMapping();
    }

    async getObjectsFromMapping(){
        this.showSpinner = true;
        this.fields = undefined;
        this.records = undefined;
        this.selectedRecordId = undefined;

        await getPromptComponentData({
            "recordId" : this.recordId
        })
        .then(result => {          
            //console.log('result: '+JSON.stringify(result));
            if(result && result.records && result.records.length > 0){
                var tempFields = JSON.parse(JSON.stringify(result.fields));
                for(var field of tempFields){
                    field['sortable'] = true;
                    if(field.fieldName == 'Name'){
                        field['type'] = 'url';
                        field['typeAttributes'] = {label:{fieldName:field.fieldName}, tooltip:{fieldName : field.fieldName}, target: "_self"};
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
                    rec['Name_____recordLink'] = '/'+rec['Id'];
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
        }
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