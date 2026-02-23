import { LightningElement, track, wire, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import AiPromptWhereClauseFormulaComponent from 'c/aiPromptWhereClauseFormulaComponent';

import getRelatedObjects from '@salesforce/apex/AIDataExtractionController.getRelatedObjects';
import getTargetFields from '@salesforce/apex/AIDataExtractionController.getTargetFields';
import upsertRelatedObjectMapping from '@salesforce/apex/AIDataExtractionController.upsertRelatedObjectMapping';
import isValidVisibilityCondition from '@salesforce/apex/AIPromptValidationController.isValidVisibilityCondition';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import DETAIL_MAPPING_OBJECT from '@salesforce/schema/AI_Data_Extraction_Detail__c';

export default class AIDataExtractionDetailComponent extends LightningElement {

    orderByOptions = [
        {"label" : "Descending", "value" : "DESC"},
        {"label" : "Ascending", "value" : "ASC"} 
    ];

    _masterId;
    _parentId;
    _parentObject;
    _detailId;
    _objectName;
    _relationshipFieldOptions;
    _selectedRelationshipField;
    _objectLabel;
    _recordLimit;
    _orderBy;
    _filterField;
    _datacloudobjects

    
    @track showSpinner = false;

    @api
    set dcObjects(value){ this._datacloudobjects = value }
    get dcObjects(){ return this._datacloudobjects }

    @api 
    set parentId(value){this._parentId = value;}
    get parentId(){return this._parentId;}

    @api 
    set parentObject(value){this._parentObject = value;}
    get parentObject(){return this._parentObject;}

    @api 
    set detailId(value){this._detailId = value;}
    get detailId(){return this._detailId;}

    @api 
    set objectName(value){this._objectName = value;}
    get objectName(){return this._objectName;}

    @api 
    set objectLabel(value){this._objectLabel = value;}
    get objectLabel(){return this._objectLabel;}

    @api 
    set relationshipFieldOptions(value){this._relationshipFieldOptions = value;}
    get relationshipFieldOptions(){return this._relationshipFieldOptions;}

    @api 
    set selectedRelationshipField(value){this._selectedRelationshipField = value;}
    get selectedRelationshipField(){return this._selectedRelationshipField;}

    @api 
    set filterField(value){this._filterField = value;}
    get filterField(){return this._filterField;}

    @api 
    set recordLimit(value){this._recordLimit = value;}
    get recordLimit(){return this._recordLimit;}

    @api 
    set orderBy(value){this._orderBy = value;}
    get orderBy(){return this._orderBy;}

    @api 
    set masterId(value){
        this._masterId = value;
        this.doInit();
    }
    get masterId(){
        return this._masterId;
    }

    @track relatedObjectOptions;
    @track selectedObject;
    @track selectedObjectLabel;
    @track selectedRelationshipName;
    @track disableSelectedObject = false;


    @track helpText_ObjectName;
    @track helpText_RelationField;
    @track helpText_WhereClause;
    @track helpText_OrderBy;
    @track helpText_RecordLimit;


    @wire(getObjectInfo, { objectApiName: DETAIL_MAPPING_OBJECT })
    wiredRecord({ error, data }) {
        if(error){
            this.handleError(error);
        }else if(data){
            if(data.fields){
                if(data.fields['Object_Name__c'] && data.fields['Object_Name__c'].inlineHelpText){
                    this.helpText_ObjectName = data.fields['Object_Name__c'].inlineHelpText;
                }if(data.fields['RelationshipField__c'] && data.fields['RelationshipField__c'].inlineHelpText){
                    this.helpText_RelationField = data.fields['RelationshipField__c'].inlineHelpText;
                }if(data.fields['Where_Clause__c'] && data.fields['Where_Clause__c'].inlineHelpText){
                    this.helpText_WhereClause = data.fields['Where_Clause__c'].inlineHelpText;
                }if(data.fields['Order_By__c'] && data.fields['Order_By__c'].inlineHelpText){
                    this.helpText_OrderBy = data.fields['Order_By__c'].inlineHelpText;
                }if(data.fields['Record_Limit__c'] && data.fields['Record_Limit__c'].inlineHelpText){
                    this.helpText_RecordLimit = data.fields['Record_Limit__c'].inlineHelpText;
                }
            }
        }
    }

    doInit(){
        this.showSpinner = true;
        this.relatedObjectOptions = undefined;
        this.selectedObject = undefined;

        if(this.detailId && this.detailId.length > 0){
            if(this.relationshipFieldOptions && this.relationshipFieldOptions.length > 0 && this.selectedRelationshipField){
                for(var field of this.relationshipFieldOptions){
                    if(field.value == this.selectedRelationshipField){
                        this.selectedRelationshipName = field.firstValue;
                        break;
                    }
                }
            }
            this.selectedObject = this.objectName;
            this.selectedObjectLabel = this.objectLabel;
            this.disableSelectedObject = true;
            this.showSpinner = false;
        }else{
            this.relationshipFieldOptions = undefined;
            this.selectedObject = undefined;
            this.selectedRelationshipField = undefined;
            this.selectedRelationshipName = undefined;
            this.filterField = undefined;
            this.orderBy = "DESC";
            this.recordLimit = undefined;
            this.getChildObjects();
        }
    }

    async getChildObjects(){
        this.showSpinner = true;
        this.relatedObjectOptions = undefined;
        this.relationshipFieldOptions = undefined;
        this.selectedRelationshipField = undefined;
        this.selectedRelationshipName = undefined;
        this.selectedObject = undefined;
        this.filterField = undefined;
        this.orderBy = "DESC";
        this.recordLimit = undefined;

        await getRelatedObjects({
            "masterId" : this.masterId,
            "parentId" : this.parentId,
            "parentObject" : this.parentObject
        })
        .then(result => {          
            if(result && result.length > 0){;
                this.relatedObjectOptions = JSON.parse(JSON.stringify(result));
            }else{
                this.showToast('warning', 'Alert', 'No related objects are present for '+this.parentObject+'.');
                this.handleCancel();
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleObjectChange(event){
        this.selectedObject = event.target.value;
        if(this.relatedObjectOptions && this.relatedObjectOptions.length > 0 && this.selectedObject){
            for(var obj of this.relatedObjectOptions){
                if(obj.value == this.selectedObject){
                    this.selectedObjectLabel = obj.firstValue;
                    break;
                }
            }
        }else{
            this.selectedObjectLabel = undefined;
        }
        this.getRelationshipFieldOptions();
    }

    handleObjectLabelChange(event){
        this.selectedObjectLabel = event.target.value;
    }

    async getRelationshipFieldOptions(){

        this.relationshipFieldOptions = undefined;
        this.selectedRelationshipField = undefined;
        this.selectedRelationshipName = undefined;

        if(this.selectedObject){
            this.showSpinner = true;
            await getTargetFields({
                "parentObject" : this.parentObject,
                "selectedObject" : this.selectedObject,
                "dataCloudObjectMap": this._datacloudobjects,
                "isFromRelatedObjLwc" : true
            })
            .then(result => {       
                if(result && result.length > 0){;
                    this.relationshipFieldOptions = JSON.parse(JSON.stringify(result));
                    this.selectedRelationshipField = this.relationshipFieldOptions[0].value;
                    this.selectedRelationshipName = this.relationshipFieldOptions[0].firstValue;
                }
                this.showSpinner = false;
            })
            .catch(error => {
                this.handleError(error);
            });
        }
        
    }

    handleRelationshipFieldChange(event){
        this.selectedRelationshipField = event.target.value;
        this.selectedRelationshipName = undefined;
        if(this.selectedRelationshipField && this.relationshipFieldOptions && this.relationshipFieldOptions.length > 0){
            for(var field of this.relationshipFieldOptions){
                if(field.value == this.selectedRelationshipField){
                    this.selectedRelationshipName = field.firstValue;
                    break;
                }
            }
        }
    }

    handleFilterFieldChange(event){
        this.filterField = event.target.value;
    }

    handleOrderByChange(event){
        this.orderBy = event.target.value;
    }

    handleRecordLimitChange(event){
        this.recordLimit = event.target.value;
    }

    handleCancel(){
        const selectedEvent = new CustomEvent("close");
        this.dispatchEvent(selectedEvent);
    }

    handleSave(){
        if((!this.selectedObject || this.selectedObject == '' || this.selectedObject == null) && !this.disableSelectedObject){
            this.showToast('warning', 'Alert', 'Related Object is required.');
        }else if(!this.selectedObjectLabel || this.selectedObjectLabel == '' || this.selectedObjectLabel == null){
            this.showToast('warning', 'Alert', 'User Friendly Label is required.');
        }else if(!this.selectedRelationshipField || this.selectedRelationshipField == '' || this.selectedRelationshipField == null){
            this.showToast('warning', 'Alert', 'Relationship field is required.');
        }else{
            var obj = {
                "selectedObject" : this.selectedObject,
                "selectedObjectLabel" : this.selectedObjectLabel,
                "masterId" : this.masterId,
                "parentId" : this.parentId,
                "detailId" : this.detailId,
                "parentObject" : this.parentObject,
                "filterField" : this.filterField,
                "orderBy" : this.orderBy,
                "recordLimit" : this.recordLimit,
                "relationshipField" : this.selectedRelationshipField,
                "relationshipName" : this.selectedRelationshipName
            };
            if(this.filterField && this.filterField != '' && this.filterField != null){
                isValidVisibilityCondition({"objName": this.selectedObject , "whereClause": this.filterField})
                    .then((res)=>{
                        if(res){
                            this.saveMapping(obj);
                        }else{
                            if(this.selectedObject == 'ActivityHistory'){
                                this.showToast('warning', 'Alert!', 'Where Clause is not supported in ActivityHistory.');
                            }else{
                                this.showToast('warning', 'Alert!', 'Where Clause is not valid.');
                            }      
                        }
                    }).catch(error=> {
                        this.showToast('warning', 'Alert!', 'Where Clause is not valid.');
                    })
            }else{
                this.saveMapping(obj);
            }
            
        }
    }

    async saveMapping(obj){
        this.showSpinner = true;
        await upsertRelatedObjectMapping({
            "detailData" : obj
        })
        .then(result => {          
            this.showToast('success', 'Success', 'Related object mapping inserted sucessfully.');
            const selectedEvent = new CustomEvent("refresh");
            this.dispatchEvent(selectedEvent);
            this.handleCancel();
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleOpenVisibilityCondition = async (e) => {
        const result = await AiPromptWhereClauseFormulaComponent.open({
            size: 'medium',
            description: 'Visibility Condition',
            objectApiName: this.selectedObject,
        });
        if (result) {
            this.filterField = result;
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