import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord } from 'lightning/uiRecordApi';

import getPromptActions from '@salesforce/apex/AIPromptActionController.getPromptActions';
import getParentFields from '@salesforce/apex/AIPromptActionController.getParentFields';
import getFieldOptions from '@salesforce/apex/AIPromptActionController.getFieldOptions';
import upsertPromptActions from '@salesforce/apex/AIPromptActionController.upsertPromptActions';

const ACTION_COLUMNS = [
    { label: 'Type', fieldName: 'actionType' },
    { label: 'Action', fieldName: 'actionLabel' },
    { label: 'Description', fieldName: 'description' }
];

export default class AIPromptActionComponent extends LightningElement {
    @api recordId;

    @track typeOptions;
    @track fieldActionTypeOptions;
    @track targetObjectFieldOptions;
    @track actions;
    @track actionColumns = ACTION_COLUMNS;
    @track showSpinner = false;
    @track objectName;
    @track jsonNodeOptions;
    @track objectOptions;
    @track showActions;

    connectedCallback(){
        this.doInit();
    }

    doInit(){
        this.showSpinner = true;
        this.actions = undefined;
        this.currentAction = {};
        this.showActions = false;
        getPromptActions({
            recordId: this.recordId
        })
        .then(result => {
            if(result && result.actions && result.actions.length > 0){
                this.actions = JSON.parse(JSON.stringify(result.actions));
            }
            this.typeOptions = JSON.parse(JSON.stringify(result.typeOptions));
            this.fieldActionTypeOptions = JSON.parse(JSON.stringify(result.fieldActionTypeOptions));
            this.targetObjectFieldOptions = JSON.parse(JSON.stringify(result.targetObjectFieldOptions));

            this.showActions = result.showActions;
            if(this.actionColumns && this.actionColumns.length > 0){
                var actionsPresent = false;
                var col_index = 0
                for(var col of this.actionColumns){
                    if(col.type == 'action'){
                        actionsPresent = true;
                        break;
                    }
                    col_index++;
                }
                if(!actionsPresent && this.showActions){
                    this.actionColumns.push({
                        type: 'action',
                        typeAttributes: { 
                            rowActions: [
                                { label: 'Edit', name: 'edit' },
                                { label: 'Delete', name: 'delete' },
                            ] 
                        },
                    });
                }else if(actionsPresent && col_index > -1 && !this.showActions){
                    this.actionColumns.splice(col_index, 1);
                }
            }
            if(result && result.jsonNodeOptions && result.jsonNodeOptions.length > 0){
                this.jsonNodeOptions = JSON.parse(JSON.stringify(result.jsonNodeOptions));
            }
            this.objectOptions = JSON.parse(JSON.stringify(result.objectOptions));
            this.objectName = result.objectName;
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    @track showAddEditModal = false;
    @track currentAction = {};
    handleAddPromptAction(){
        if(!this.showAddEditModal){
            this.showAddEditModal = true;
        }else{
            this.showAddEditModal = false;
            this.currentAction = {};
            this.doInit();
        }
    }

    handleRowAction(event){
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        switch (actionName) {
            case 'delete':
                this.deleteRow(row);
                break;
            case 'edit':
                this.currentAction = row;
                this.handleAddPromptAction();
                break;
            default:
        }
    }

    deleteRow(row){
        deleteRecord(row.id)
        .then(() => {
            this.showToast('success', 'Success', 'Record Deleted Successfully.');
            this.doInit();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    get isApexAction(){
        return this.currentAction.actionType == 'Invoke Apex';
    }

    get isFlowAction(){
        return this.currentAction.actionType == 'Invoke Flow';
    }

    get isUpdateFieldAction(){
        return this.currentAction.actionType == 'Update Field';
    }

    get isCreateRecordAction(){
        return (this.currentAction.actionType == 'Create Record' || this.currentAction.actionType == 'Open a Form');
    }

    handleTypeChange(event){
        this.currentAction['actionType'] = event.target.value;
        this.currentAction['relatedFieldsData'] = [];
        this.currentAction['promptComponent'] = null;
        this.currentAction['flowApiName'] = null;
        this.currentAction['apexClassName'] = null;
        this.currentAction['objectName'] = null;
        this.currentAction['fieldMappings'] = null;

        if(this.currentAction.actionType == 'Update Field'){
            this.getParentDetailFields(this.objectName, 0);
        }
    }

    handleApexClassChange(event){
        this.currentAction['apexClassName'] = event.target.value;    
    }

    handleFlowNameChange(event){
        this.currentAction['flowApiName'] = event.target.value;    
    }

    handlePromptComponentChange(event){
        this.currentAction['promptComponent'] = event.target.value;    
    }

    handleSequenceChange(event){
        var seq = null;
        if(event.target.value && event.target.value != '' && event.target.value != null){
            seq = parseInt(event.target.value);
        }
        this.currentAction['sequence'] = seq;
    }

    handleDescriptionChange(event){
        this.currentAction['description'] = event.target.value;
    }

    handleAppendTimestampChange(event){
        this.currentAction['appendTimestamp'] = event.target.checked;
    }

    handleUpdateFieldTargetFieldRemove(){
        this.currentAction.fieldApiName = undefined;
        this.getParentDetailFields(this.objectName, 0);
    }

    handleRelatedFieldChange(event){
        var index = event.target.dataset.index;
        this.currentAction.relatedFieldsData[index]['selectedValue'] = undefined;

        for(var opt of this.currentAction.relatedFieldsData[index]['options']){
            if(opt.value == event.target.value){
                this.currentAction.relatedFieldsData[index]['selectedValue'] = opt;
                break;
            }
        }

        var records = [];
        for(var rec of this.currentAction.relatedFieldsData){
            if(rec.index <= index){
                records.push(rec);
            }
        }
        this.currentAction.relatedFieldsData = JSON.parse(JSON.stringify(records));
        if(this.currentAction.relatedFieldsData[index]['selectedValue']){
            var objName = this.currentAction.relatedFieldsData[index]['selectedValue'].parentName;
            if(objName && objName.length > 0){
                this.getParentDetailFields(objName, (parseInt(index)+1));
            }
        }
    }

    async getParentDetailFields(currentObjName, index){
        await getParentFields({
            objName : currentObjName
        })
        .then(result => {  
            var options = [];
            if(index > 4){
                for(var opt of result){
                    if(!opt.parentName || opt.parentName == null || opt.parentName == ''){
                        options.push(opt);
                    }
                }
            }else{
                options = JSON.parse(JSON.stringify(result));
            }
            var obj = {
                "index" : index,
                "options" : options,
                "selectedValue" : undefined
            };
            if(!this.currentAction.relatedFieldsData){
                this.currentAction.relatedFieldsData = [];
            }
            this.currentAction.relatedFieldsData.push(obj);
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleObjectNameChange(event){
        this.currentAction['objectName'] = event.target.value;
        this.getFieldOptions();
    }

    async getFieldOptions(){
        this.currentAction['fieldOptions'] = undefined;
        this.currentAction['fieldMappings'] = undefined;
        await getFieldOptions({
            objectName : this.currentAction['objectName'],
            isCreatable : true
        })
        .then(result => {  
            this.currentAction['fieldOptions'] = JSON.parse(JSON.stringify(result));
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleFieldChange(event){
        var fName = event.target.dataset.fname;
        var index = event.target.dataset.index;

        var action = JSON.parse(JSON.stringify(this.currentAction));

        action['fieldMappings'][index][fName] = event.target.value;
        if(fName == 'type'){
            action['fieldMappings'][index]['value'] = null;
        }

        for(var fm of action['fieldMappings']){
            fm['isReference'] = false;
            fm['jsonNode'] = false;
            fm['isHardcoded'] = false;
            if(fm.type == 'Reference Field'){
                fm['isReference'] = true;
            }else if(fm.type == 'AI Response'){
                fm['jsonNode'] = true;
            }else{
                fm['isHardcoded'] = true;
            }
        }

        this.currentAction = JSON.parse(JSON.stringify(action));
    }

    handleAddField(){
        var action = JSON.parse(JSON.stringify(this.currentAction));
        if(!action['fieldMappings']){
            action['fieldMappings'] = [];
        }
        var newIndex = action['fieldMappings'].length;
        var obj = {
            "index" : newIndex,
            "type" : "Hardcoded",
            "isReference" : false,
            "jsonNode" : false,
            "isHardcoded" : true
        };
        action['fieldMappings'].push(obj);

        this.currentAction = JSON.parse(JSON.stringify(action));
    }

    async handleDeleteField(event){
        var index = event.target.dataset.index;
        var action = JSON.parse(JSON.stringify(this.currentAction));

        action['fieldMappings'].splice(index, 1);

        var count = 0;
        for(var fm of action['fieldMappings']){
            fm['index'] = count;
            count++;
        }

        if(!action['fieldMappings'] || action['fieldMappings'].length == 0){
            this.currentAction = undefined;
        }else{

        }this.currentAction = JSON.parse(JSON.stringify(action));
    }

    handleRelatedFieldConfirm(){
        var isError = false;
        var relationships = [];
        if(this.currentAction['id'] && this.currentAction['id'] != null && this.currentAction['id'] != ''){
            if(!this.currentAction['fieldApiName'] || this.currentAction['fieldApiName'] == null || this.currentAction['fieldApiName'] == ''){
                if(this.currentAction.relatedFieldsData && this.currentAction.relatedFieldsData.length > 0){
                    var index = 0;
                    for(var opt of this.currentAction.relatedFieldsData){
                        if(!opt.selectedValue || opt.selectedValue == null){
                            isError = true;
                            break;
                        }
                        if(index == (this.currentAction.relatedFieldsData.length - 1)){
                            relationships.push(opt.selectedValue.value);
                        }else{
                            relationships.push(opt.selectedValue.relationshipName);
                        }
                        index++;
                    }   
                }else{
                    isError = true;
                }
            }else{
                relationships.push(this.currentAction['fieldApiName']);
            }
        }else{
            if(this.currentAction.relatedFieldsData && this.currentAction.relatedFieldsData.length > 0){
                var index = 0;
                for(var opt of this.currentAction.relatedFieldsData){
                    if(!opt.selectedValue || opt.selectedValue == null){
                        isError = true;
                        break;
                    }
                    if(index == (this.currentAction.relatedFieldsData.length - 1)){
                        relationships.push(opt.selectedValue.value);
                    }else{
                        relationships.push(opt.selectedValue.relationshipName);
                    }
                    index++;
                }   
            }else{
                isError = true;
            }
        }
        if(!isError && relationships && relationships.length > 0){
            return relationships.join('.');
        }
        return null;
    }

    async handleSave(){
        var isError = false;
        if(!this.currentAction || !this.currentAction.actionType || this.currentAction.actionType == '' || this.currentAction.actionType == null){
            isError = true;
        }else if(this.currentAction && this.currentAction.actionType == 'Update Field'){
            var rField = this.handleRelatedFieldConfirm();
            console.log('rField: '+rField);
            this.currentAction['fieldApiName'] = rField;
            
            if(!this.currentAction.promptComponent || this.currentAction.promptComponent == null || this.currentAction.promptComponent == ''){
                isError = true;
            }else if(!this.currentAction['fieldApiName'] || this.currentAction['fieldApiName'] == null || this.currentAction['fieldApiName'] == ''){
                isError = true;
            }
        }else if(this.currentAction && this.currentAction.actionType == 'Invoke Flow'){
            if(!this.currentAction.flowApiName || this.currentAction.flowApiName == null || this.currentAction.flowApiName == ''){
                isError = true;
            }
        }else if(this.currentAction && this.currentAction.actionType == 'Invoke Apex'){
            if(!this.currentAction.apexClassName || this.currentAction.apexClassName == null || this.currentAction.apexClassName == ''){
                isError = true;
            }
        }else if(this.currentAction && (this.currentAction.actionType == 'Create Record' || this.currentAction.actionType == 'Open a Form')){
            if(!this.currentAction.objectName || this.currentAction.objectName == null || this.currentAction.objectName == ''){
                isError = true;
            }else if(!this.currentAction.fieldMappings || this.currentAction.fieldMappings.length == 0){
                isError = true;
            }
            if(this.currentAction.fieldMappings && this.currentAction.fieldMappings.length > 0){
                for(var fm of this.currentAction.fieldMappings){
                    if(!fm.fieldName || fm.fieldName == null || fm.fieldName == ''){
                        isError = true;
                    }else if(!fm.type || fm.type == null || fm.type == ''){
                        isError = true;
                    }else if((!fm.value || fm.value == null || fm.value == '') && fm.type != 'Hardcoded'){
                        isError = true;
                    }
                    if(isError){
                        break;
                    }
                }
            }
        }
        if(isError){
            this.showToast('error', 'Error', 'Required fields missing.');
        }else{
            await upsertPromptActions({
                data : JSON.stringify(this.currentAction),
                recordId : this.recordId
            })
            .then(result => {  
                this.showToast('success', 'Success', 'Record updated successfully.');
                this.handleAddPromptAction();
                this.doInit();
            })
            .catch(error => {
                this.handleError(error);
            });
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