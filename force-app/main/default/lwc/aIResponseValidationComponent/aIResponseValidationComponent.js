import { api, track, LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getResponseValidations from '@salesforce/apex/AIResponseValidationController.getResponseValidations';
import deleteResponseValidation from '@salesforce/apex/AIResponseValidationController.deleteResponseValidation';
import updateResponseValidationCondition from '@salesforce/apex/AIResponseValidationController.updateResponseValidationCondition';

const actions = [
    { label: 'Edit', name: 'Edit_Record' },
    { label: 'Delete', name: 'delete' },
];

const tableColumns = [
    {type: 'number', fieldName: 'sequence', label: 'SEQUENCE', initialWidth:120},
    {type: 'text', fieldName: 'action', label: 'ACTION'},
    {type: 'text', fieldName: 'value', label: 'VALUE'},
    {
        type: 'action',
        typeAttributes: { rowActions: actions },
    },
];

export default class AIResponseValidationComponent extends NavigationMixin(LightningElement) {

    @api recordId;
    @track showSpinner;

    @track responseValidations;
    @track actionOptions;

    @track columns = tableColumns;

    @track deleteResponseValidationId;
    @track showDeleteComponent = false;
    @track showAddComponent = false;
    @track addComponentDetails = undefined;
    @track showModifyComponent = false;
    @track modifyComponentDetails = undefined;

    @track conditionEdited = true;
    @track responseValidationCondition;
    @track responseValidationMessage;
    @track isPromptActive = false;

    connectedCallback(){
        this.getAllResponseValidations();
    }

    async getAllResponseValidations(){
        this.showSpinner = true;
        this.responseValidations = undefined;
        this.responseValidationCondition = '';
        this.responseValidationMessage = '';
        await getResponseValidations({
            "promptId" : this.recordId
        })
        .then(result => {     
            this.responseValidations = JSON.parse(JSON.stringify(result.responseValidations));  
            this.actionOptions = JSON.parse(JSON.stringify(result.actionOptions));
            this.responseValidationCondition = result.responseValidationCondition;   
            this.responseValidationMessage = result.responseValidationMessage;
            //Jira 7221:  Issues/Feedbacks from 1.12 Testing
            this.isPromptActive = result.isPromptActive;
            if(this.isPromptActive){
                 this.columns = [{type: 'number', fieldName: 'sequence', label: 'SEQUENCE', initialWidth:120},
                                {type: 'text', fieldName: 'action', label: 'ACTION'},
                                {type: 'text', fieldName: 'value', label: 'VALUE'}
                            ];   
            }
           
            this.showSpinner = false;
            this.conditionEdited = true;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleModifyCondition(){
        this.conditionEdited = false;
    }

    handleSaveCondition(){
        this.responseValidationCondition = this.template.querySelector(".responseValidationCondition").value;
        this.responseValidationMessage = this.template.querySelector(".responseValidationMessage").value;
        this.modifyCondition();
    }

    async modifyCondition(){
        this.showSpinner = true;
        await updateResponseValidationCondition({
            "condition" : this.responseValidationCondition,
            "message" : this.responseValidationMessage,
            "recordId" : this.recordId
        })
        .then(result => {          
            this.showSpinner = false;
            this.showToast('success', 'Success', 'Prompt Validations condition modified sucessfully.');
        })
        .catch(error => {
            this.handleError(error);
        });

    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if(row && row.id){
            var responseValidationId = row.id;
            console.log('action: '+actionName);
            if(actionName){
                if(actionName == 'Edit_Record'){
                    this.modifyComponentDetails = {
                        "responseValidationId": responseValidationId, "action": row.action, 
                        "value": row.value, "sequence": row.sequence
                    };
                    this.handleModifyModalState();
                }else if(actionName == 'delete'){
                    this.deleteResponseValidationId = responseValidationId;
                    this.handleDeleteModalState();                    
                }
            }
        }
    }

    handleAddResponseValidation(){
        this.addComponentDetails = {};
        this.handleAddModalState();
    }

    handleAddModalState(){
        if(this.showAddComponent){
            this.showAddComponent = false;
            this.addComponentDetails = undefined;
        }else{
            this.showAddComponent = true;
        }
    }

    handleModifyModalState(){
        if(this.showModifyComponent){
            this.showModifyComponent = false;
            this.modifyComponentDetails = undefined;
        }else{
            this.showModifyComponent = true;
        }
    }

    handleDeleteModalState(){
        if(this.showDeleteComponent){
            this.showDeleteComponent = false;
            this.deleteResponseValidationId = undefined;
        }else{
            this.showDeleteComponent = true;
        }
    }

    handleValidationDelete(){
        if(this.deleteResponseValidationId){
            var responseValidationId = this.deleteResponseValidationId;
            this.deleteValidationRecord(responseValidationId);
        }
    }

    async deleteValidationRecord(responseValidationId){
        this.showSpinner = true;
        this.handleDeleteModalState();

        await deleteResponseValidation({
            "responseValidationId" : responseValidationId
        })
        .then(result => {          
            this.showToast('success', 'Success', 'Record deleted sucessfully.');
            this.getAllResponseValidations();
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
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }

    /*
    refreshRecord(){
        const selectedEvent = new CustomEvent("refresh");
        this.dispatchEvent(selectedEvent);

        const fields = {'Id' : this.recordId};
        const recordInput = { fields };
        updateRecord(recordInput)
        .then(() => {
        })
        .catch(error => {
            this.handleError(error);
        });
    }
    */
}