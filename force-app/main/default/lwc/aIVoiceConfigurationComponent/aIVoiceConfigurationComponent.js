import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord  } from 'lightning/uiRecordApi';

import getConfigurationDetails from '@salesforce/apex/AIVoiceConfigurationController.getConfigurationDetails';
import updateConfiguration from '@salesforce/apex/AIVoiceConfigurationController.updateConfiguration';
import updateConfigurationDetail from '@salesforce/apex/AIVoiceConfigurationController.updateConfigurationDetail';

const COLUMNS = [
    { label: 'Prompt', fieldName: 'aiPromptName', sortable: true },
    { label: 'Profile', fieldName: 'profile', sortable: true },
    { label: 'Related To Object', fieldName: 'objectName', sortable: true },
    {
        type: 'action', 
        typeAttributes: { 
            rowActions: [
                { label: 'Edit', name: 'edit'},
                { label: 'Delete', name: 'delete' },
            ] 
        }
    }
];

export default class AIVoiceConfigurationComponent extends LightningElement {

    @track configInfo;
    @track showSpinner = false;

    @track columns = COLUMNS;
    defaultSortDirection = 'asc';
    sortDirection = 'asc';
    sortedBy;

    @track selectedRecordId;
    @track detailData = {};
    @track showAddModal = false;
    @track showSaveButon = false;

    connectedCallback(){
        this.doInit();
    }

    async doInit(){
        this.showSpinner = true;
        this.configInfo = undefined;
        this.showSaveButon = false;
        getConfigurationDetails()
        .then(result => {
            if(result){
                this.configInfo = JSON.parse(JSON.stringify(result));
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleDurationChange(event){
        this.configInfo.duration = event.target.value;
        this.showSaveButon = true;
    }

    handleAIModelChange(event){
        this.configInfo.aiModelId = event.target.value;
        this.showSaveButon = true;
    }

    handleAsyncToggle(event){
        this.configInfo.asyncRequest = event.target.checked;
        this.showSaveButon = true;
    }

    handleFileUploadModelChange(event){
        this.configInfo.fileUploadModelId = event.target.value;
        this.showSaveButon = true;
    }

    handlePollingModelChange(event){
        this.configInfo.pollingModelId = event.target.value;
        this.showSaveButon = true;
    }

    handlePollingTimeframeChange(event){
        this.configInfo.pollingTimeframe = event.target.value;
        this.showSaveButon = true;
    }

    handlePollingCounterChange(event){
        this.configInfo.pollingCounter = event.target.value;
        this.showSaveButon = true;
    }

    handleSave(){
        this.showSpinner = true;
        this.showSaveButon = false;
        if(this.configInfo && this.configInfo['pollingTimeframe'] == ''){
            this.configInfo['pollingTimeframe'] = null;
        }
        if(this.configInfo && this.configInfo['pollingCounter'] == ''){
            this.configInfo['pollingCounter'] = null;
        }
        updateConfiguration({
            "wrap" : JSON.stringify(this.configInfo)
        })
        .then(result => {
            this.doInit();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleAddModal(){
        if(this.showAddModal){
            this.showAddModal = false;
            this.detailData = {};
            this.doInit();
        }else{
            this.showAddModal = true;
        }
    }

    handleRowAction(event){
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if(row && row.detailId){
            this.selectedRecordId = row.detailId;
            if(actionName == 'edit'){
                this.detailData = row;
                this.handleAddModal();    
            }else if(actionName == 'delete'){
                deleteRecord(this.selectedRecordId)
                .then(() => {
                    this.showToast('success', 'Success', 'Record Deleted Successfully.');
                    this.doInit();
                })
                .catch(error => {
                    this.handleError(error);
                });
            }
        }
    }

    handleSaveDetail(){
        if(!this.detailData || !this.detailData.aiPromptId || this.detailData.aiPromptId == null || this.detailData.aiPromptId == ''){
            this.showToast('error', 'Error.', 'Required fields missing.');
        }else{
            this.showSpinner = true;
            updateConfigurationDetail({
                "wrap" : JSON.stringify(this.detailData),
                "configId" : this.configInfo.configId
            })
            .then(result => {
                this.handleAddModal();
            })
            .catch(error => {
                this.handleError(error);
            });
        }   
    }

    handleDetailChange(event){
        var fName = event.target.dataset.name;
        this.detailData[fName] = event.detail.value;
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
        const cloneData = [...this.configInfo.details];

        cloneData.sort(this.sortBy(sortedBy, sortDirection === 'asc' ? 1 : -1));
        this.configInfo.details = cloneData;
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
            this.showToast('error', 'Error.', error.body.message);
        }else{
            this.showToast('error', 'Error.', error.toString());
        }
    }

}