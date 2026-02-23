import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, updateRecord } from "lightning/uiRecordApi";

import getTabFields from '@salesforce/apex/AIPromptBuilderController.getTabFields';
import updatePrompt from '@salesforce/apex/AIPromptBuilderController.updatePrompt';
import isValidVisibilityCondition from '@salesforce/apex/AIPromptValidationController.isValidVisibilityCondition';

import PROMPT_OBJ from '@salesforce/schema/AI_Prompt__c';

import PROMPT_ID_FIELD from '@salesforce/schema/AI_Prompt__c.Id';
//import PROMPT_TARGET_FIELD from '@salesforce/schema/AI_Prompt__c.Target_Field__c';
//import PROMPT_APPEND_TIMESTAMP_FIELD from '@salesforce/schema/AI_Prompt__c.Append_Timestamp__c';
import PROMPT_INCLUDE_FILES_FIELD from '@salesforce/schema/AI_Prompt__c.Include_Files__c';
import PROMPT_ENABLE_LOOPBACK_FIELD from '@salesforce/schema/AI_Prompt__c.Enable_Loopback__c';
import PROMPT_LOOPBACK_MESSAGE_FIELD from '@salesforce/schema/AI_Prompt__c.Loopback_Message__c';
import PROMPT_MODEL_FILE_PROCESSING_FIELD from '@salesforce/schema/AI_Prompt__c.AI_Model_File_Processing__c';
import PMT_TARGET_OBJECT_FIELD from "@salesforce/schema/AI_Prompt__c.Object__c";
//import PMT_AVAIL_FOR_AGENTIC_FIELD from "@salesforce/schema/AI_Prompt__c.Available_for_Agentic__c";
//import PMT_AGENTIC_FINDER_FIELDS_FIELD from "@salesforce/schema/AI_Prompt__c.Record_Finder_Fields__c";
//import PMT_AGENTIC_FINDER_FILTER_FIELD from "@salesforce/schema/AI_Prompt__c.Record_Finder_Filter__c";
import PMT_TYPE_FIELD from '@salesforce/schema/AI_Prompt__c.Type__c';

const PMT_FIELDS = [PROMPT_ID_FIELD,PMT_TARGET_OBJECT_FIELD,PMT_TYPE_FIELD];

export default class AIPromptBuilder extends LightningElement {
    @api recordId;
    @api objectApiName;
    @track data;
    @track readOnly;
    @track isTrue = true;

    @track showSpinner = false;
    @track promptObjectApi = PROMPT_OBJ.objectApiName;
    @track showActions = false;
    @track targetObject;
    @track isCanvasPrompt;
    @track isAgenticPrompt;

    get isCanvasAndAgentic(){
        return this.isCanvasPrompt || this.isAgenticPrompt;
    }

    //@track agenticFinderFieldsFieldApi = PMT_AGENTIC_FINDER_FIELDS_FIELD.fieldApiName;
    //@track agenticFinderFilterFieldApi = PMT_AGENTIC_FINDER_FILTER_FIELD.fieldApiName;

    @wire(getRecord, { recordId: "$recordId", fields: PMT_FIELDS})
    wiredRecord({error, data}){
        if(error){
            this.handleError(error);
        }else if(data){
            if(data.fields && data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName] && data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName].value){
                this.targetObject = data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName].value;
            }
            if(data.fields && data.fields[PMT_TYPE_FIELD.fieldApiName] && data.fields[PMT_TYPE_FIELD.fieldApiName].value){
                this.isCanvasPrompt = data.fields[PMT_TYPE_FIELD.fieldApiName].value === 'Canvas';
                this.isAgenticPrompt = data.fields[PMT_TYPE_FIELD.fieldApiName].value === 'Agentic';
            }
            this.doInit();
        }
    }

    @track activeTabName;
    async doInit(){
        this.showActions = false;
        this.showSpinner = true;
        //this.isLoaded = false;
        //this._showAgenticTab = false;
        getTabFields({recordId: this.recordId})
        .then(result => {
            if(result && result.tabs && result.tabs.length > 0 && !this.activeTabName){
                this.activeTabName = result.tabs[0].tabName;
            }
            this.data = JSON.parse(JSON.stringify(result.tabs));
            this.readOnly = result.readOnly;
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    connectedCallback() {
        window.addEventListener('keydown', this.handleKeyDown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this.handleKeyDown);
    }

    handleKeyDown = (event) => {
         if (this.showActions && ( event.ctrlKey || (window.navigator.userAgent.includes('Mac OS X') && event.metaKey )) && (event.key === 's' || event.key === 'S')) {
            event.preventDefault(); // prevent the default save action (like browser save dialog)
            this.handleSave();
        }
    }

    /*
    @track _showAgenticTab = false;
    @track isLoaded = false;
    renderedCallback(){
        if(!this.isLoaded){
            this.recalculateAgenticTabVisibility();
        }
    }

    set showAgenticTab(value){
        this._showAgenticTab = value;
    }

    get showAgenticTab(){
        this.recalculateAgenticTabVisibility();
        return this._showAgenticTab;
    }

    recalculateAgenticTabVisibility(){
        this._showAgenticTab = false;
        var element = this.template.querySelector('[data-id="'+PMT_AVAIL_FOR_AGENTIC_FIELD.fieldApiName+'"]');
        if(element){
            this.isLoaded = true;
            if(element.value){
                this._showAgenticTab = true;
            }
        }else if(this.data && this.data.length > 0){
            this.isLoaded = true;
            for(var tab of this.data){
                for(var sect of tab.sections){
                    for(var field of sect.fields){
                        if(field.apiName == PMT_AVAIL_FOR_AGENTIC_FIELD.fieldApiName && field.fieldValue){
                            this._showAgenticTab = true;
                            break;
                        }
                    }
                }
            }
        }
    }
    */

    handleTabActive(event){
        this.activeTabName = event.target.value;
    }

    handleSectionExpand(event){
        var tIndex = event.target.dataset.tindex;
        var sIndex = event.target.dataset.sindex;
        if(tIndex != undefined && sIndex != undefined){
            this.data[tIndex].sections[sIndex]['expanded'] = !this.data[tIndex].sections[sIndex]['expanded'];
        }
    }

    handleFieldChanges(event){
        this.showActions = true;
        /*
        if(event && event.detail && event.detail.apiName && event.detail.apiName == PROMPT_TARGET_FIELD.fieldApiName){
            var hideAppendTimestamp = true;
            if(event.detail.value && event.detail.value != null && event.detail.value != ''){
                hideAppendTimestamp = false;
            }
            for(var tab of this.data){
                for(var sect of tab.sections){
                    for(var field of sect.fields){
                        if(field.apiName == PROMPT_APPEND_TIMESTAMP_FIELD.fieldApiName){
                            field.hideField = hideAppendTimestamp;
                            break;
                        }
                    }
                }
            }
        }
        */
       
        if(event && event.target && event.target.fieldName && event.target.fieldName == PROMPT_INCLUDE_FILES_FIELD.fieldApiName){
            var hideFileProcessingField = true;
            if(event.detail.value){
                hideFileProcessingField = false;
            }
            for(var tab of this.data){
                for(var sect of tab.sections){
                    for(var field of sect.fields){
                        if(field.apiName == PROMPT_MODEL_FILE_PROCESSING_FIELD.fieldApiName){
                            field.hideField = hideFileProcessingField;
                            break;
                        }
                    }
                }
            }
        }
        if(event && event.target && event.target.fieldName && event.target.fieldName == PROMPT_ENABLE_LOOPBACK_FIELD.fieldApiName){
            var hideLoopbackMessgae = true;
            if(event.detail.value){
                hideLoopbackMessgae = false;
            }
            for(var tab of this.data){
                for(var sect of tab.sections){
                    for(var field of sect.fields){
                        if(field.apiName == PROMPT_LOOPBACK_MESSAGE_FIELD.fieldApiName){
                            field.hideField = hideLoopbackMessgae;
                            break;
                        }
                    }
                }
            }
        }
    }

    handleSave(){
        var data = {};

        data[PROMPT_ID_FIELD.fieldApiName] = this.recordId;
        let validAll = true;
        var inputFields = this.template.querySelectorAll('lightning-input-field');
        if(inputFields && inputFields.length > 0){
            inputFields.forEach(element => {
                if(element.dataset.type === 'DOUBLE'){
                    data[element.fieldName] = parseFloat(element.value);
                }else{
                    data[element.fieldName] = element.value;
                }
                if (!element.dataset.hide && !element.reportValidity()) {
                    validAll = false;
                    this.showToast('error', 'Error', element.dataset.label+' is Invalid');
                    return;
                }
                if((element.dataset.hide === false || element.dataset.hide === 'false' || !element.dataset.hide) && element.fieldName === PROMPT_LOOPBACK_MESSAGE_FIELD.fieldApiName && (element.value === null || element.value === '')){
                    validAll = false;
                    element.reportValidity()
                    this.showToast('error', 'Error', element.dataset.label+' is Invalid');
                    return;
                }
                if((element.dataset.hide === false || element.dataset.hide === 'false' || !element.dataset.hide) && element.fieldName === PROMPT_LOOPBACK_MESSAGE_FIELD.fieldApiName && (element.value !== null || element.value !== '')){
                    try{
                        JSON.parse(element.value);
                    }catch(e){
                        validAll = false;
                        element.reportValidity();
                        this.showToast('error', 'Error', 'The Loopback message contains invalid JSON data. Please correct the JSON format.');
                        return;
                    }
                }
                
            });
        }

        if(!validAll){
            this.showSpinner = false;
            return;
        }


        var multiselectFields = this.template.querySelectorAll('c-a-i-multiselect-field-builder');
        if(multiselectFields && multiselectFields.length > 0){
            multiselectFields.forEach(element => {
                var obj = element.getValue();
                if(obj){
                    data[obj.apiName] = obj.value;
                }
            });
        }

        var profileFields = this.template.querySelectorAll('c-a-i-profile-selection-builder');
        if(profileFields && profileFields.length > 0){
            profileFields.forEach(element => {
                var obj = element.getValue();
                if(obj){
                    data[obj.apiName] = obj.value;
                }
            });
        }

        var permissionSetsFields = this.template.querySelectorAll('c-a-i-permission-sets-selection-builder');
        if(permissionSetsFields && permissionSetsFields.length > 0){
            permissionSetsFields.forEach(element => {
                var obj = element.getValue();
                if(obj){
                    data[obj.apiName] = obj.value;
                }
            });
        }

        var targetFields = this.template.querySelectorAll('c-a-i-field-selection-builder');
        if(targetFields && targetFields.length > 0){
            targetFields.forEach(element => {
                var obj = element.getValue();
                if(obj){
                    data[obj.apiName] = obj.value;
                }
            });
        }
        
        var pmtCmdFields = this.template.querySelectorAll('c-a-i-prompt-command-builder');
        if(pmtCmdFields && pmtCmdFields.length > 0){
            pmtCmdFields.forEach(element => {
                var obj = element.getValue();
                if(obj){
                    data[obj.apiName] = obj.value;
                }
            });
        }

        var visCdtnFields = this.template.querySelectorAll('c-a-i-visibility-condition-builder');
        if(visCdtnFields && visCdtnFields.length > 0){
            visCdtnFields.forEach(element => {
                let obj = element.getValue()
                var visibilityCondition = obj.value;
                if(visibilityCondition && visibilityCondition != '' && visibilityCondition != null){
                    isValidVisibilityCondition({"objName": this.targetObject , "whereClause": visibilityCondition})
                        .then((res)=>{
                            if(res){
                                data[obj.apiName] = visibilityCondition;
                                this.recordSave(data)
                            }else{
                                this.showToast('warning', 'Alert!', 'Visibility Condition is not valid.');
                            }
                        }).catch(error=> {
                            this.showToast('warning', 'Alert!', 'Visibility Condition is not valid.');
                        })
                }else{
                    data[obj.apiName] = visibilityCondition;
                    this.recordSave(data);
                }
            });
        }else{
            this.recordSave(data);
        }
    }

    recordSave(data) {
        if(data){
            this.showSpinner = true;
            updatePrompt({data: data})
            .then(result => {
                this.showToast('success', 'Success', 'Record updated sucessfully.');
                //this.refreshRecord();
                this.doInit();
            })
            .catch(error => {
                this.handleError(error);
            });
        }
    }

    /*
    refreshRecord(){
        const fields = {};
        fields[PROMPT_ID_FIELD.fieldApiName] = this.recordId;
        const recordInput = { fields };
        updateRecord(recordInput)
        .then(() => {})
        .catch((error) => {
            this.handleError(error);
        });
    }
    */

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
        }else if(error && error.body && error.body.fieldErrors && Object.keys(error.body.fieldErrors).length > 0){
            let fieldKey = Object.keys(error.body.fieldErrors)[0];
            let errorMessage = error.body.fieldErrors[fieldKey][0].message;
            this.showToast('error', 'Error', errorMessage);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }
}