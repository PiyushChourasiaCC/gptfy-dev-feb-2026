import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getInitData from '@salesforce/apex/AISyncScheduleController.getInitData';
import getFieldOptions from '@salesforce/apex/AIPromptActionController.getFieldOptions';
import updateSyncScheduler from '@salesforce/apex/AISyncScheduleController.updateSyncScheduler';

import AiPromptWhereClauseFormulaComponent from 'c/aiPromptWhereClauseFormulaComponent';
//@JIRA V2-7334 : File based RAG Sync
export default class AISyncOverrideComponent extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    @track showSpinner = false;
    @track modalHeader = 'New AI RAG Sync';
    @track data;

    connectedCallback() {
        this.doInit();
    }

    doInit() {
        this.data = undefined;
        this.showSpinner = true;
        getInitData({
            recordId: this.recordId
        })
            .then(result => {
                if (result && result.fields && result.fields.length > 0) {
                    for (var i = 0; i < result.fields.length; i++) {
                        result.fields[i]['index'] = i;
                    }
                }
                this.data = JSON.parse(JSON.stringify(result));
                if (this.data.name && this.data.name != '' && this.data.name != null) {
                    this.modalHeader = 'Edit ' + this.data.name;
                }
                this.showSpinner = false;
            })
            .catch(error => {
                this.handleError(error);
            });
    }

    handleFieldChange(event) {
        var fName = event.target.dataset.fname;
        this.data[fName] = event.target.value;

        if (fName == 'objectName') {
            getFieldOptions({
                objectName: event.target.value,
                isCreatable: false
            })
                .then(result => {
                    if (result && result.length > 0) {
                        var data = JSON.parse(JSON.stringify(this.data));
                        data.fieldOptions = JSON.parse(JSON.stringify(result));
                        data.fields = undefined;
                        this.data = JSON.parse(JSON.stringify(data));
                    } else {
                        this.data.fieldOptions = [];
                    }
                })
                .catch(error => {
                    this.handleError(error);
                });
        }
    }

    handleFieldValueChange(event) {
        var index = event.target.dataset.index;
        var fName = event.target.dataset.fname;
        this.data.fields[index][fName] = event.target.value;
    }

    handleOpenVisibilityCondition = async (e) => {
        const result = await AiPromptWhereClauseFormulaComponent.open({
            size: 'medium',
            description: 'Where Clause',
            objectApiName: this.data.objectName,
        });
        if (result) {
            this.data.whereClause = result;
        }
    }

    handleAddField() {
        var data = JSON.parse(JSON.stringify(this.data));
        if (!data.fields) {
            data.fields = [];
        }
        var newIndex = data.fields.length;
        data.fields.push({
            "fieldApi": "",
            "nodeName": "",
            "index": newIndex
        });
        this.data = JSON.parse(JSON.stringify(data));
    }

    handleDeleteField(event) {
        var index = event.target.dataset.index;
        var data = JSON.parse(JSON.stringify(this.data));
        data['fields'].splice(index, 1);
        var count = 0;
        for (var fm of data['fields']) {
            fm['index'] = count;
            count++;
        }
        this.data = JSON.parse(JSON.stringify(data));
    }

    handleSave() {
        // Validate required fields using reportValidity
        const allValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox')]
            .reduce((validSoFar, inputCmp) => {
                inputCmp.reportValidity();
                return validSoFar && inputCmp.checkValidity();
            }, true);

        if (!allValid) {
            this.showToast('error', 'Error', 'Please complete all required fields.');
            return;
        }

        // Additional field validation
        if (this.checkFieldValidity()) {
            return;
        }

        this.showSpinner = true;
        updateSyncScheduler({
            data: JSON.stringify(this.data),
            recordId: this.recordId
        })
            .then(result => {
                if (result && result != '' && result != null) {
                    this.recordId = result;
                }
                this.showToast('success', 'Success', 'Record Saved Successfully.');
                this.handleCancel();
            })
            .catch(error => {
                this.handleError(error);
            });
    }

    checkFieldValidity() {
        var isError = false;
        //if(!this.data.fields || this.data.fields.length == 0){
        //isError = true;
        //}else{
        if (this.data.fields && this.data.fields.length > 0) {
            for (var field of this.data.fields) {
                if (!field.fieldApi || field.fieldApi == null || field.fieldApi == '' ||
                    !field.nodeName || field.nodeName == null || field.nodeName == '') {
                    isError = true;
                    break;
                }
            }
        }

        //}
        if (isError == false && this.data.objectName
            && (this.data.fields == null
                || !this.data.fields
                || this.data.fields == undefined
                || (this.data.fields && this.data.fields.length == 0))) {
            isError = true;
            this.showToast('error', 'Error', 'Please add atleast one Field for Select Object to continue.');
        }else if (isError == false && this.data.objectName && (!this.data.fileFormat || this.data.fileFormat == null || this.data.fileFormat == '')){
            isError = true;
            this.showToast('error', 'Error', 'Please select File Format to continue.');
        }else if (isError == false && this.data.objectName && (!this.data.fileName || this.data.fileName == null || this.data.fileName == '')){
            isError = true;
            this.showToast('error', 'Error', 'Please select File Name to continue.');
        }
        if (isError) {
            return true;
        }
        return false;
    }

    handleCancel() {
        if (this.recordId) {
            this.naviagteToRecordPage();
        } else {
            this.navigateToListView();
        }
    }

    naviagteToRecordPage() {
        const value = this.recordId;
        const selectedEvent = new CustomEvent("cancel", {
            detail: { value }
        });
        this.dispatchEvent(selectedEvent);
    }

    navigateToListView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: this.objectApiName,
                actionName: 'list'
            }
        });
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