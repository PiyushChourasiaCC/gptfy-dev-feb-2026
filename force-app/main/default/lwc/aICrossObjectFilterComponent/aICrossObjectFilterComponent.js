import { api, wire, track, LightningElement } from 'lwc';
import { getRecord, getFieldValue, updateRecord, getRecordNotifyChange  } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import fetchHierarchy from '@salesforce/apex/AICrossObjectFilterController.fetchHierarchy';
import deleteFilters from '@salesforce/apex/AICrossObjectFilterController.deleteFilters';
import updateCofiCondition from '@salesforce/apex/AICrossObjectFilterController.updateCofiCondition';

import TARGET_OBJ_FIELD from '@salesforce/schema/AI_Prompt_Scheduler__c.Object_Name__c';
import COFI_CDTN_FIELD from '@salesforce/schema/AI_Prompt_Scheduler__c.Cross_Object_Filter_Condition__c';
const fields = [TARGET_OBJ_FIELD, COFI_CDTN_FIELD];

const actions = [
    //{ label: 'Add Related Filter', name: 'Add_Related_Filter'},
    { label: 'Modify Filter', name: 'Modify_Filter' },
    { label: 'Delete', name: 'delete' },
];

const tableColumns = [
    {type: 'number', fieldName: 'sequence', label: 'SEQUENCE', initialWidth:120},
    {type: 'text', fieldName: 'objectName', label: 'OBJECT NAME'},
    {type: 'text', fieldName: 'relationshipField', label: 'RELATIONSHIP FIELD'},
    {type: 'text', fieldName: 'whereClause', label: 'WHERE CLAUSE', wrapText: true},
    {type: 'text', fieldName: 'operator', label: 'OPERATOR', initialWidth:150},
    {type: 'text', fieldName: 'filterValue', label: 'QUALIFY COUNT', initialWidth:150},
    {
        type: 'action',
        typeAttributes: { rowActions: actions },
    },
];

export default class AICrossObjectFilterComponent extends NavigationMixin(LightningElement) {

    @api recordId;
    @track showSpinner;
    @track filters;
    @track expandedRows = [];
    @track columns = tableColumns;
    @track showObjectLabel = false;
    @track operatorOptions;

    @track deleteFilterId;
    @track showDeleteComponent = false;
    @track showAddComponent = false;
    @track addComponentDetails = undefined;
    @track showModifyComponent = false;
    @track modifyComponentDetails = undefined;

    @track cofiConditionEdited = true;

    @wire(getRecord, { recordId: '$recordId', fields })
    master;

    get targetObject() {
        if(this.recordId){
            return getFieldValue(this.master.data, TARGET_OBJ_FIELD);
        }
        return '';
    }

    get cofiCondition() {
        if(this.recordId){
            return getFieldValue(this.master.data, COFI_CDTN_FIELD);
        }
        return '';
    }

    connectedCallback(){
        this.getAllFilters(true);
    }

    refreshParent(){
        this.getAllFilters(false);
    }

    async getAllFilters(stopRefresh){
        this.showSpinner = true;
        this.filters = undefined;
        await fetchHierarchy({
            "masterId" : this.recordId
        })
        .then(result => {          
            if(result && result.filters && result.filters.length > 0){
                this.filters = JSON.parse(JSON.stringify(result.filters).split('children').join('_children'));
            }
            if(result.filterIds && result.filterIds.length > 0){
                this.expandedRows = JSON.parse(JSON.stringify(result.filterIds));
            }
            if(result.operatorOptions && result.operatorOptions.length > 0){
                this.operatorOptions = JSON.parse(JSON.stringify(result.operatorOptions));
            }
            if(!stopRefresh){
                this.refreshRecord();
            }
            this.showSpinner = false;
            this.cofiConditionEdited = true;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleExpandAll(){
        const grid =  this.template.querySelector('lightning-tree-grid');
        if(grid){
            grid.expandAll();
        }
    }

    handleCollapseAll(){
        const grid =  this.template.querySelector('lightning-tree-grid');
        if(grid){
            grid.collapseAll();
        }
    }

    handleModifyCondition(){
        this.cofiConditionEdited = false;
    }

    handleSaveCondition(){
        var cofiCondition = this.template.querySelector(".cofiCondition").value;
        this.modifyCondition(cofiCondition);
    }

    async modifyCondition(cofiCondition){
        this.showSpinner = true;
        await updateCofiCondition({
            "condition" : cofiCondition,
            "recordId" : this.recordId
        })
        .then(result => {          
            this.showToast('success', 'Success', 'Cross-Object Filter condition modified sucessfully.');
            this.refreshParent();
        })
        .catch(error => {
            this.handleError(error);
        });

    }

    handleShowObjectLabel(){
        var tempColmns = JSON.parse(JSON.stringify(this.columns));
        var obj = {type: 'text', fieldName: 'objectLabel', label: 'OBJECT LABEL'};
        tempColmns.splice(1, 0, obj);
        this.columns = JSON.parse(JSON.stringify(tempColmns));
        this.showObjectLabel = true;
    }

    handleHideObjectLabel(){
        var tempColums = [];
        for(var obj of this.columns){
            if(obj.fieldName != 'objectLabel'){
                tempColums.push(obj);
            }
        }
        this.columns = JSON.parse(JSON.stringify(tempColums));
        this.showObjectLabel = false;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if(row && row.filterId){

            var filterId = row.filterId;
            var objectName = row.objectName;

            if(actionName){
                if(actionName == 'Add_Related_Filter'){
                    this.addComponentDetails = {"objectName": objectName, "filterId": filterId, "filterValue": 0};
                    this.handleAddModalState();
                }
                else if(actionName == 'Modify_Filter'){
                    this.modifyComponentDetails = {
                        "filterId": filterId, "objectName": objectName, "relationshipOptions" : row.relationshipOptions,
                        "relationshipField": row.relationshipField, "whereClause": row.whereClause, "operator": row.operator, 
                        "filterValue": row.filterValue, "sequence": row.sequence, "parentId": row.parentId
                    };
                    this.handleModifyModalState();
                }
                else if(actionName == 'delete'){
                    this.deleteFilterId = filterId;
                    this.handleDeleteModalState();
                }
            }
        }
        
    }

    handleAddRelatedFilter(){
        this.addComponentDetails = {"objectName": this.targetObject};
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
            this.deleteFilterId = undefined;
        }else{
            this.showDeleteComponent = true;
        }
    }

    handleMappingDelete(){
        if(this.deleteFilterId){
            var filterId = this.deleteFilterId;
            this.deleteMapping(filterId);
        }
    }

    async deleteMapping(filterId){

        this.showSpinner = true;
        this.handleDeleteModalState();

        await deleteFilters({
            "masterId" : this.recordId,
            "filterId" : filterId
        })
        .then(result => {          
            this.showToast('success', 'Success', 'Cross-Object Filter deleted sucessfully.');
            this.refreshParent();
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
}