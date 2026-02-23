import { LightningElement, api, track } from 'lwc';
import getInitialDetails from '@salesforce/apex/AIPromptElementController.getInitialDetails';
import createPromptElement from '@salesforce/apex/AIPromptElementController.createPromptElement';
import updatePromptElement from '@salesforce/apex/AIPromptElementController.updatePromptElement';
import deletePromptElement from '@salesforce/apex/AIPromptElementController.deletePromptElement';

import PROMPT_ELEMENT_OBJECT from '@salesforce/schema/AI_Prompt_Element__c';
import SECURITY_AUDIT_OBJECT_API_NAME from '@salesforce/schema/AI_Response__c';

import STATUS_FIELD from '@salesforce/schema/AI_Prompt__c.Status__c';
import OBJECT_FIELD from '@salesforce/schema/AI_Prompt__c.Object__c';
import TYPE_FIELD from '@salesforce/schema/AI_Prompt__c.Type__c';

const actions = [
    { label: 'Edit', name: 'edit'},
    { label: 'Delete', name: 'delete' },
];

export default class AIPromptElementComponent extends LightningElement {
    @api recordId;
    @api promptId;
    @api objectApiName;

    @track promptElements = [];
    @track isPromptActive = false;
    @track showModal = false;
    @track isEditMode = false;
    @track isSaving = false;
    @track currentElement = {};
    @track widthOptions = [];
    @track iconOptions  = [];
    @track showSpinner = false;
    @track columns = [];

    promptElementObjectApiName = PROMPT_ELEMENT_OBJECT;
    // Lookup Filter for Active Prompts
    @track promptFilter = {};
    @track summaryPromptFilter = {};

    connectedCallback(){
        this.doInit();
    }

    async doInit(){
        try{
            this.showSpinner = true;
            let response = await getInitialDetails({promptId : this.promptId});
            if(response){
                let parsedResponse = JSON.parse(JSON.stringify(response));
                this.promptDetails = parsedResponse.promptDetails;
                this.isPromptActive = parsedResponse.promptDetails.status === 'Active' ? true : false;
                this.widthOptions = parsedResponse.widthOptions;
                this.iconOptions = parsedResponse.iconOptions;
                this.promptElements = parsedResponse.promptElements;
                this.promptElements = parsedResponse.promptElements ? this.getUpdatedPromptElements() : [];
                this.setColumns();
                this.preparePromptFilter();
                this.prepareSummaryPromptFilter();
                this.showSpinner = false;
            }
        }catch(error){
            this.error = error?.body ? error.body.message : JSON.stringify(error);
            this.showSpinner = false;
        }
    }
    getUpdatedPromptElements(){
        let tempPromptElements = JSON.parse(JSON.stringify(this.promptElements));
        const newArr = tempPromptElements.map(obj => ({
            ...obj,
            promptRecordUrl : '/'+obj.promptId,
            summaryPromptRecordUrl : obj.summaryPromptId ? '/'+obj.summaryPromptId : ''
          }));
        return newArr;
    }
    setColumns(){
        let tempColumns = [
            {
                label: 'Prompt',
                fieldName: 'promptRecordUrl', 
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'promptName' }, 
                    tooltip: { fieldName: 'promptName' },
                    target: '_blank'
                }
            },{
                label: 'Summary Prompt',
                fieldName: 'summaryPromptRecordUrl', 
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'summaryPromptName' }, 
                    tooltip: { fieldName: 'summaryPromptName' },
                    target: '_blank'
                }
            },{
                label: 'Height',
                fieldName: 'height', 
                type: 'number'
            },{
                label: 'Width',
                fieldName: 'width', 
                type: 'text'
            },{
                label: 'Sequence',
                fieldName: 'sequence', 
                type: 'number'
            },
        ];
        if(!this.isPromptActive){
            tempColumns.push({
                    type: 'action',
                    typeAttributes: { 
                        rowActions: actions,
                }
            });
        }
        this.columns = tempColumns;
    }
    preparePromptFilter(){
        this.promptFilter = {
            criteria: [
                { fieldPath: STATUS_FIELD.fieldApiName, operator: 'eq', value: 'Active' },
                { fieldPath: TYPE_FIELD.fieldApiName, operator: 'ne', value: 'Canvas' },
                { fieldPath: OBJECT_FIELD.fieldApiName, operator: 'eq', value: this.promptDetails.objectName }
            ],
            filterLogic: '1 AND 2 AND 3'
        };
    }
    prepareSummaryPromptFilter(){
        this.summaryPromptFilter = {
            criteria: [
                { fieldPath: STATUS_FIELD.fieldApiName, operator: 'eq', value: 'Active' },
                { fieldPath: TYPE_FIELD.fieldApiName, operator: 'ne', value: 'Canvas' },
                { fieldPath: OBJECT_FIELD.fieldApiName, operator: 'eq', value: SECURITY_AUDIT_OBJECT_API_NAME.objectApiName}
            ],
            filterLogic: '1 AND 2 AND 3'
        };
    }
    get hasData() {
        return this.promptElements && this.promptElements.length > 0;
    }

    get modalTitle() {
        return this.isEditMode ? 'Edit Prompt Element' : 'New Prompt Element';
    }

    handleRefresh() {
        this.doInit();
    }

    handleAddNew() {
        this.currentElement = {parentPromptName : this.promptDetails.name, parentPromptId : this.promptId, inheritPromptSecurity : false}
        this.isEditMode = false;
        this.showModal = true;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        switch (actionName) {
            case 'edit':
                this.handleEdit(row);
                break;
            case 'delete':
                this.handleDelete(row);
                break;
        }
    }

    handleEdit(row) {
        this.currentElement = { ...row };
        this.isEditMode = true;
        this.showModal = true;
    }

    async handleDelete(row) {
        try {
            await deletePromptElement({ elementId: row.id });
            await this.handleRefresh();
        } catch (error) {
            console.error('Error deleting element:', error);
        }
    }

    closeModal() {
        this.showModal = false;
        this.currentElement = {};
        this.isEditMode = false;
        this.isSaving = false;
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        let value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        value = (field === 'height' ? value ? parseFloat(value) : null : value);
        this.currentElement = { ...this.currentElement, [field]: value };
    }

    validateRequiredFields() {

        // Get fields using data-id
        const promptIdField = this.template.querySelector('lightning-record-picker[data-field="promptId"]');
        const widthField = this.template.querySelector('lightning-combobox[data-field="width"]');
        const sequenceField = this.template.querySelector('lightning-input[data-field="sequence"]');

        let isValid = true;

        // Custom validation: prompt should be selected
        if (!promptIdField.value) {
            promptIdField.setCustomValidity('Complete this field.');
            promptIdField.reportValidity()
            isValid = false;
        } else {
            promptIdField.setCustomValidity('');
            promptIdField.reportValidity()
        }

        // Custom validation: prompt should be selected
        if (!widthField.value) {
            widthField.setCustomValidity('Complete this field.');
            widthField.reportValidity()
            isValid = false;
        } else {
            widthField.setCustomValidity('');
            widthField.reportValidity()
        }

         // Custom validation: prompt should be selected
         if (!sequenceField.value) {
            sequenceField.setCustomValidity('Complete this field.');
            sequenceField.reportValidity()
            isValid = false;
        } else if(sequenceField.value && sequenceField.value > 99 || sequenceField.value < 1){
            sequenceField.setCustomValidity('Please select a sequence from 1-99.');
            sequenceField.reportValidity()
            isValid = false;
        }else {
            sequenceField.setCustomValidity('');
            sequenceField.reportValidity()
        }
        return isValid;
    }

    async handleSave() {
        if (!this.validateRequiredFields()) {
            console.error('Please fill all required fields');
            return;
        }

        try {
            if (this.isEditMode) {
                await updatePromptElement({ jsonString: JSON.stringify(this.currentElement) });
            } else {
                await createPromptElement({ jsonString: JSON.stringify(this.currentElement) });
            }
            
            await this.handleRefresh();
            this.closeModal();
        } catch (error) {
            console.error('Error saving element:', error);
        } finally {
            this.isSaving = false;
        }
    }

    handleSubmit(event) {
        event.preventDefault();
        this.handleSave();
    }
}