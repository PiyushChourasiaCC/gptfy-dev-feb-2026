import { api, wire, track, LightningElement } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import fetchDetailHierarchy from '@salesforce/apex/AIDataExtractionController.fetchDetailHierarchy';
import deleteRelatedObjectMapping from '@salesforce/apex/AIDataExtractionController.deleteRelatedObjectMapping';
import updateDataExtractionMappingAsDraft from '@salesforce/apex/AIDataExtractionController.updateDataExtractionMappingAsDraft';

import TARGET_OBJ_FIELD from '@salesforce/schema/AI_Data_Extraction_Mapping__c.Object_Name__c';
const fields = [TARGET_OBJ_FIELD];

const actions = [
    { label: 'Add Related Object', name: 'Add_Related_Object'},
    { label: 'Reconfigure', name: 'Modify_Object' },
    { label: 'Field Mappings', name: 'Field_Mappings'},
    { label: 'Delete', name: 'delete' },
];

const tableColumns = [
    {type: 'text', fieldName: 'objectName', label: 'Object Name'},
    {type: 'text', fieldName: 'relationshipField', label: 'Relationship Field'},
    {type: 'text', fieldName: 'filterField', label: 'WHERE Clause'},
    {type: 'text', fieldName: 'fieldsCount', label: 'Fields'}
];

export default class AIDataExtractionComponent extends NavigationMixin(LightningElement) {
    @api recordId;
    
    @track showSpinner = false;
    @track detailMappings;
    @track detailMap;
    @track expanded = false;
    @track expandedRows = [];
    @track showObjectLabel = false;

    @track showDeleteComponent = false;
    @track showFieldMappingComponent = false;
    @track showAddComponent = false;
    @track showModifyObjectComponent = false;

    @track deleteDetailId = undefined;
    @track fieldMappingObjectName = undefined;
    @track fieldMappingObjectLabel = undefined;
    @track addComponentDetails = undefined;
    @track modifyObjectComponentDetails = undefined;
    @track columns;
    @track datacloudobjects;

    @wire(getRecord, { recordId: '$recordId', fields })
    master;

    get targetObject() {
        if(this.recordId){
            return getFieldValue(this.master.data, TARGET_OBJ_FIELD);
        }
        return '';
    }

    connectedCallback(){
        this.getAllMappings(true);
    }

    handleRefreshFromChild(){
        this.updateDataExtractionMappingDraft();
        this.getAllMappings(false);
    }

    updateDataExtractionMappingDraft(){
        this.showSpinner = false;
        updateDataExtractionMappingAsDraft({
            "recordId" : this.recordId
        })
        .then(result => {   
            updateRecord({ fields: { Id: this.recordId } });
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    async getAllMappings(stopRefresh){
        this.showSpinner = true;
        this.detailMappings = undefined;
        this.columns = undefined;
        this.showObjectLabel = false;


        
            await fetchDetailHierarchy({
                          "masterId" : this.recordId
                    }).then(result => {       
                        if(result && result.details && result.details.length > 0){
                            this.detailMappings = JSON.parse(JSON.stringify(result.details).split('children').join('_children'));
                        }
                        if(result && result.detailMap){
                            this.detailMap = JSON.parse(JSON.stringify(result.detailMap));
                        }
                        if(result.detailIds && result.detailIds.length > 0){
                            this.expandedRows = JSON.parse(JSON.stringify(result.detailIds));
                        }

                        if(result && result.dataCloudMap){
                            this.datacloudobjects = JSON.parse(JSON.stringify(result.dataCloudMap));
                        }

                        this.columns = JSON.parse(JSON.stringify(tableColumns));
                        var actionObj = {
                            type: 'action',
                            typeAttributes: { rowActions: actions },
                        }
                        this.columns.push(actionObj);
                        if(!stopRefresh){
                            this.handleRefresh();
                        }
                        this.showSpinner = false;
                    })
                    .catch(error => {
                        this.handleError(error);
                    });

        
    }

    handleShowObjectLabel(){
        var tempColmns = JSON.parse(JSON.stringify(this.columns));
        var obj = {type: 'text', fieldName: 'objLabel', label: 'OBJECT LABEL'};
        tempColmns.splice(1, 0, obj);
        this.columns = JSON.parse(JSON.stringify(tempColmns));
        this.showObjectLabel = true;
    }

    handleHideObjectLabel(){
        var tempColums = [];
        for(var obj of this.columns){
            if(obj.fieldName != 'objLabel'){
                tempColums.push(obj);
            }
        }
        this.columns = JSON.parse(JSON.stringify(tempColums));
        this.showObjectLabel = false;
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


    handleRowAction= (event)=> {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        console.log('row.detailId : '+row.detailId)
        console.log('row.objectName : '+row.objectName)
        console.log('row.runningIndex : '+row.runningIndex)
        if(row && row.detailId){

            var detailId = row.detailId == 'NA' ? '' : row.detailId;
            var objectName = row.objectName;

            if(actionName){
                if(actionName == 'Add_Related_Object'){
                    if(detailId === ''){
                        this.addComponentDetails = {"objectName": objectName, "detailId": detailId};
                        this.handleAddModalState();
                    }else{
                        if(row.runningIndex && row.runningIndex >=100){
                            this.showToast('error','Error','You have exceeded the maximum limit of 3 levels for related objects.')
                        }else{
                            this.addComponentDetails = {"objectName": objectName, "detailId": detailId};
                            this.handleAddModalState();
                            }
                    }
                    
                }
                else if(actionName == 'Modify_Object'){
                    if(detailId && this.detailMap && this.detailMap[detailId]){
                        this.modifyObjectComponentDetails = {
                            "detailId" : detailId,
                            "objectName" : objectName,
                            "objectLabel" :this.detailMap[detailId].objectLabel,
                            "relationshipOptions" : this.detailMap[detailId].relationshipOptions,
                            "filterField" : this.detailMap[detailId].filterField,
                            "orderBy" : this.detailMap[detailId].orderBy,
                            "recordLimit" : this.detailMap[detailId].recordLimit,
                            "relationshipField" : this.detailMap[detailId].relationshipField,
                        };
                        this.handleModifyObjectModalState();
                    }else{
                        this.handleNavigateToMasterEdit();
                    }
                    
                }
                else if(actionName == 'Field_Mappings'){
                    this.fieldMappingObjectName = objectName;
                    this.fieldMappingObjectLabel = row.objectLabel;
                    this.handleFieldMappingModalState();
                }
                else if(actionName == 'delete'){
                    if(detailId){
                        this.deleteDetailId = detailId;
                        this.handleDeleteModalState();
                    }else{
                        this.showToast('warning', 'Alert', 'Target Object cannot be deleted.');
                    }
                }
            }
        }
        
    }

    handleAddModalState(){
        if(this.showAddComponent){
            this.showAddComponent = false;
            this.addComponentDetails = undefined;
        }else{
            this.showAddComponent = true;
        }
    }

    handleModifyObjectModalState(){
        if(this.showModifyObjectComponent){
            this.showModifyObjectComponent = false;
            this.modifyObjectComponentDetails = undefined;
        }else{
            this.showModifyObjectComponent = true;
        }
    }

    handleFieldMappingModalState(){
        if(this.showFieldMappingComponent){
            this.showFieldMappingComponent = false;
            this.fieldMappingObjectName = undefined;
        }else{
            this.showFieldMappingComponent = true;
        }
    }


    handleDeleteModalState(){
        if(this.showDeleteComponent){
            this.showDeleteComponent = false;
            this.deleteDetailId = undefined;
        }else{
            this.showDeleteComponent = true;
        }
    }

    handleMappingDelete(){
        if(this.deleteDetailId){
            var detailId = this.deleteDetailId;
            this.deleteMapping(detailId);
        }
    }

    async deleteMapping(detailId){

        this.showSpinner = true;
        this.handleDeleteModalState();

        await deleteRelatedObjectMapping({
            "masterId" : this.recordId,
            "detailId" : detailId,
            "targetObject" : this.targetObject
        })
        .then(result => {          
            this.showToast('success', 'Success', 'Related Mappings deleted sucessfully.');
            this.handleRefreshFromChild(false);
        })
        .catch(error => {
            this.handleError(error);
        });

    }

    handleNavigateToMasterEdit() {
        const config = {
            type: "standard__recordPage",
            attributes: {
                recordId: this.recordId,
                actionName: "edit"
            }
        };
        this[NavigationMixin.Navigate](config);
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

    handleRefresh(){
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