import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import createCardConfiguration from '@salesforce/apex/AddCardController.createCardConfiguration';
import updateCardConfiguration from '@salesforce/apex/AddCardController.updateCardConfiguration';
import deleteCardConfiguration from '@salesforce/apex/AddCardController.deleteCardConfiguration';

import createConnection from '@salesforce/apex/AddCardController.createConnection';
import createDataSource from '@salesforce/apex/AddCardController.createDataSource';

import validateAction from '@salesforce/apex/AddCardController.handleCardActivate';
import getResponseMapping from '@salesforce/apex/AddCardController.getResponseMapping';
import getRequestMapping from '@salesforce/apex/AddCardController.getRequestMapping';
import isExistingStaticResource from '@salesforce/apex/AddCardController.isExistingStaticResource';

export default class GptfyAddCardComponent extends LightningElement {
    @api cardType;
    @api record;
    @api header = 'Modal Header';
    @api objectApiName;
    @api fields;
    @api sobj;

    @api showEditBtn = false;

    @track showSpinner = false;

    @track catalog = false;
    @track tabName = 'Connection Details';
    @track isConnection = true;
    @track nameFieldLabel = 'Model Name';

    @track name = '';
    @track source = 'Static Resource';
    @track icondetail = '';
    @track sequence;
    @track description = '';
    @track recId = '';
    @track requestMapping = '';
    @track requestMappingId = '';
    @track requestMappingMetadataName = '';
    @track responseMapping = '';
    @track responseMappingId = '';
    @track responseMappingMetadataName = '';


    @track showIconOption = false;

    get sourceOptions() {
        return [
            { label: 'Static Resource', value: 'Static Resource' },
            { label: 'SLDS Icon', value: 'SLDS Icon' },
        ];
    }

    get iconOption() {
        let options = [];
        for (let i = 1; i <= 113; i++) {
            options.push({ label: 'custom' + i, value: 'custom:custom' + i });
        }
        return options;
    }

    connectedCallback() {
        if (this.sobj) {
            this.recId = this.sobj.Id;
            this.fetchResponseMapping(this.recId);
            this.fetchRequestMapping(this.recId);
        } else {
            this.recId = '';
            this.fetchResponseMapping(this.recId);
            this.fetchRequestMapping(this.recId);
        }

        if (this.cardType == 'CTLOG') {
            this.catalog = true;
        } else {
            this.catalog = false;
        }

        if (this.cardType == 'APIDS') {
            this.tabName = 'Data Source Details';
            this.nameFieldLabel = 'Data Source Name';
            this.isConnection = false;
        }

        if (this.record && this.record.hasOwnProperty('MasterLabel')) {
            this.header = 'Edit ' + this.record.MasterLabel;
            this.name = this.record.MasterLabel;
            this.source = this.record.Icon_Source;
            this.icondetail = this.record.Icon_Details;
            this.sequence = this.record.Sequence;
            this.description = this.record.Description;

            if (this.source == 'SLDS Icon') {
                this.showIconOption = true;
            } else {
                this.showIconOption = false;
            }
        }
    }

    fetchResponseMapping(recId) {
        getResponseMapping({
            recordId: recId
        }).then(result => {
            let response = JSON.parse(result);
            this.responseMappingMetadataName = (response.namespace ? response.namespace : '') + 'AI_Response_Mapping__c';
            this.responseMapping = response.Name;
            this.responseMappingId = response.Id;
        }).catch(error => {
            console.log('error', error);
        });
    }

    fetchRequestMapping(recId) {
        getRequestMapping({
            recordId: recId
        }).then(result => {
            let response = JSON.parse(result);
            this.requestMapping = response.Name;
            this.requestMappingId = response.Id;
        }).catch(error => {
            console.log('error', error);
        });
    }

    handleNameChange(event) {
        this.name = event.detail.value;
    }

    handleIconDetailChange(event) {
        this.icondetail = event.detail.value;
    }

    handleSequenceChange(event) {
        this.sequence = event.detail.value;
    }

    handleDescriptionChange(event) {
        this.description = event.detail.value;
    }

    handleSourceChange(event) {
        this.source = event.detail.value;
        if (this.source == 'SLDS Icon') {
            this.showIconOption = true;
        } else {
            this.showIconOption = false;
        }
        this.icondetail = ''
    }

    handleCancel() {
        const selectedEvent = new CustomEvent("cancel");
        this.dispatchEvent(selectedEvent);
    }

    deleteMetadataRecord() {
        this.showSpinner = true;
        if (this.record) {
            deleteCardConfiguration({
                'fieldValue': this.record.MasterLabel,
                'metadataName': this.record.DeveloperName,
                'metadataLabel': this.record.MasterLabel,
                'cardType': this.cardType,
                'recordId': this.record.Id
            }).then(result => {
                console.log('====================== result : '+result);
                if (result) {
                    this.showToast('success', 'Success', 'Card removed successfully.');
                    this.handleSuccess();
                }
                this.showSpinner = false;
            }).catch(error => {
                this.handleError(error);
                this.showSpinner = false;
            });
        } else {
            this.showSpinner = false;
        }
    }

    checkValidation = async() => {
        if(( !this.catalog || !this.showEditBtn) && (this.name === '' || this.name === undefined)){
             return false;
        }else if(this.source === '' || this.source === undefined){
             return false;
        }else if(this.icondetail === '' || this.icondetail === undefined){
             return false;
        }
        else if(this.sequence === '' || this.sequence === undefined){
             return false;
        }else if(this.description === '' || this.description === undefined){
             return false;
        }
        return true;
    }

    updateRecord = async()=> {
        this.showSpinner = true;

        this.checkValidation()
             .then((valid)=>{
                if(valid){
                        isExistingStaticResource({ 'resourceName': this.icondetail}).then((result)=> {
                        if(this.source === 'Static Resource'){
                            if(!result){
                                this.handleError('Invalid Static Resource');
                                return
                            }
                        }
                        let params = {
                                    'OldName': this.record.MasterLabel,
                                    'NewName': this.name,
                                    'isActive': true,
                                    'MetadataName': this.record.DeveloperName,
                                    'MetadataLabel': this.name,
                                    'Description__c': this.description,
                                    'Enabled__c': true,
                                    'Icon_Details__c': this.icondetail,
                                    'Icon_Source__c': this.source,
                                    'Sequence__c': this.sequence,
                                    'Feature__c': this.cardType,
                                    'Id': this.record.Id
                                };
                                updateCardConfiguration({ 'params': params }).then(result => {
                                    setTimeout(() => {
                                        if (result) {
                                            if (this.cardType == 'AMODL') {
                                                this.handleConnectionCreate();
                                            } else if (this.cardType == 'APIDS') {
                                                this.handleDataSourceCreate();
                                            }
                                            this.showToast('success', 'Success', 'Card updated successfully.');
                                            this.handleSuccess();
                                        }
                                        this.showSpinner = false;
                                    }, "5000");
                                }).catch(error => {
                                    this.handleError(error);
                                    this.showSpinner = false;
                                });
                    
                        }).catch(error => {
                            this.handleError(error);
                            return false;
                          });
                    
                }else{
                    this.showToast('error', 'Error', 'Required fields are missing.');
                    this.showSpinner = false;
                }
             })
    }

   

    createRecord = async() => {

        this.checkValidation()
             .then((valid)=>{
                if(valid){
                      isExistingStaticResource({ 'resourceName': this.icondetail}).then((result)=> {
                        if(this.source === 'Static Resource'){
                            if(!result){
                                this.handleError('Invalid Static Resource');
                                return
                             }
                        }
                         let readyToSubmit = false;
                                if (this.name && this.cardType && this.source && this.icondetail && this.description && this.sequence) {
                                    readyToSubmit = true;
                                }
                                if (this.cardType != 'CTLOG' && readyToSubmit) {
                                    readyToSubmit = this.validToSubmit();
                                }
                                this.showSpinner = true;
                                if (readyToSubmit) {
                                    let params = {
                                        'Name': this.name,
                                        'Feature__c': this.cardType,
                                        'Icon_Source__c': this.source,
                                        'Icon_Details__c': this.icondetail,
                                        'Description__c': this.description,
                                        'Sequence__c': this.sequence,
                                        'Enabled__c': true,
                                        'CardName': this.cardType + '_' + this.name
                                    };
                                    createCardConfiguration({ 'params': params }).then(result => {
                                        if (result) {
                                            if (this.cardType == 'AMODL') {
                                                this.handleConnectionCreate();
                                            } else if (this.cardType == 'APIDS') {
                                                this.handleDataSourceCreate();
                                            }
                
                                            this.showToast('success', 'Success', 'Card created successfully.');
                                            this.handleSuccess();
                                        }
                                        this.showSpinner = false;
                                    }).catch(error => {
                                        this.handleError(error);
                                        this.showSpinner = false;
                                    });
                                } else {
                                    this.showToast('error', 'Error', 'Required fields are missing.');
                                    this.showSpinner = false;
                                }


                    }).catch(error => {
                            this.handleError(error);
                            return false;
                          });

                }else{
                    this.showToast('error', 'Error', 'Required fields are missing.');
                    this.showSpinner = false;
                }
            })
    }

    handleError(error) {
        this.showSpinner = false;
        console.log(JSON.stringify(error));

        var msg = error.toString();
        if (error && error.body && error.body.output && error.body.output.errors && error.body.output.errors.length > 0 && error.body.output.errors[0].message) {
            msg = error.body.output.errors[0].message;
        } else if (error && error.body && error.body.message) {
            msg = error.body.message;
        }
        console.log('msg: ' + msg);
        this.showToast('error', 'Error', msg);
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant: variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    handleSuccess() {
        const selectedEvent = new CustomEvent("success");
        this.dispatchEvent(selectedEvent);
    }

    handleConnectionCreate() {
        let params = {};
        params['Name'] = this.name;
        params['Response_Mapping__c'] = this.responseMappingId;
        params['Request_Mapping__c'] = this.requestMappingId;
        const inputFields = this.template.querySelectorAll('lightning-input-field');
        inputFields.forEach(field => {
            params[field.fieldName] = field.value;
        });
        console.log('params: ' + JSON.stringify(params));
        createConnection({ 'params': params }).then(result => {
            setTimeout(() => {
                if (result) {
                    console.log('============================== result : ' + JSON.stringify(result));
                }
                this.showSpinner = false;
            }, "5000");
        }).catch(error => {
            this.handleError(error);
            this.showSpinner = false;
        });
    }

    handleDataSourceCreate() {
        let params = {};
        params['Name'] = this.name;
        const inputFields = this.template.querySelectorAll('lightning-input-field');
        inputFields.forEach(field => {
            params[field.fieldName] = field.value;
        });
        createDataSource({ 'params': params }).then(result => {
            setTimeout(() => {
                if (result) {
                }
                this.showSpinner = false;
            }, "5000");
        }).catch(error => {
            this.handleError(error);
            this.showSpinner = false;
        });
    }

    validToSubmit() {
        let hasValid = true;
        const inputFields = this.template.querySelectorAll('lightning-input-field');
        inputFields.forEach(field => {
            if (!field.fieldName.endsWith("Enable_in_Sandbox__c")) {
                if (field.required && (field.value == null || field.value == '' || field.value == undefined)) {
                    hasValid = false;
                }
            } else {
                console.log('======================== field.value : ' + field.value);
            }
        });
        return hasValid;
    }

    handleActivate() {
        let hasSuccess = false;
        if (this.name && this.cardType && this.source && this.icondetail && this.description && this.sequence) {
            let params = {};
            params['Name'] = this.name;
            params['Feature'] = this.cardType;
            validateAction({ 'params': params }).then(result => {
                if (!result) {
                    this.showToast('success', 'Success', 'Card activated successfully.');
                    this.handleSuccess();
                }
            }).catch(error => {
                this.handleError(error);
                this.showSpinner = false;
            });
        } else {
            this.showToast('error', 'Error', 'Required fields are missing.');
        }
    }

    handleSelectResponseMapping(event) {
        if (event.detail) {
            this.responseMapping = event.detail.record.name;
            this.responseMappingId = event.detail.record.Id;
        }
    }

    handleSelectRequestMapping(event) {
        if (event.detail) {
            this.requestMapping = event.detail.record.name;
            this.requestMappingId = event.detail.record.Id;
        }
    }

}