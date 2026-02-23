import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getRelatedObjects from '@salesforce/apex/AICrossObjectFilterController.getRelatedObjects';
import getTargetFields from '@salesforce/apex/AIDataExtractionController.getTargetFields';
import upsertRelatedFilter from '@salesforce/apex/AICrossObjectFilterController.upsertRelatedFilter';

export default class AIAddCrossObjectFilterComponent extends LightningElement {
    _masterId;
    _parentId;
    _parentObject;
    _filterId;
    _objectName;
    _relationshipFieldOptions;
    _selectedRelationshipField;
    _whereClause;
    _sequence;
    _operatorOptions;
    _operator;
    _filterValue;

    @track showSpinner = false;

    @api 
    set parentId(value){this._parentId = value;}
    get parentId(){return this._parentId;}

    @api 
    set parentObject(value){this._parentObject = value;}
    get parentObject(){return this._parentObject;}

    @api 
    set filterId(value){this._filterId = value;}
    get filterId(){return this._filterId;}

    @api 
    set objectName(value){this._objectName = value;}
    get objectName(){return this._objectName;}

    @api 
    set relationshipFieldOptions(value){this._relationshipFieldOptions = value;}
    get relationshipFieldOptions(){return this._relationshipFieldOptions;}

    @api 
    set selectedRelationshipField(value){this._selectedRelationshipField = value;}
    get selectedRelationshipField(){return this._selectedRelationshipField;}

    @api 
    set whereClause(value){this._whereClause = value;}
    get whereClause(){return this._whereClause;}

    @api 
    set sequence(value){this._sequence = value;}
    get sequence(){return this._sequence;}

    @api 
    set operator(value){this._operator = value;}
    get operator(){return this._operator;}

    @api 
    set filterValue(value){this._filterValue = value;}
    get filterValue(){return this._filterValue;}

    @api 
    set operatorOptions(value){this._operatorOptions = value;}
    get operatorOptions(){return this._operatorOptions;}

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
    @track selectedRelationshipName;
    @track disableSelectedObject = false;

    sequenceHelpText = "Range: 1 - 99. Sequence number assigned here are used to define 'Cross Object Filter Condition'.";
    valueHelpText = 'Actual record count of the related object is compared against this field. If it matches, then the parent record is qualified else it is disqualified.';
    whereClauseHelpText = "Filter related object records by adding a SOQL where condition in this field. Do skip the 'WHERE' keyword.";

    doInit(){
        this.showSpinner = true;
        this.relatedObjectOptions = undefined;
        this.selectedObject = undefined;

        if(this.filterId && this.filterId.length > 0){
            if(this.relationshipFieldOptions && this.relationshipFieldOptions.length > 0 && this.selectedRelationshipField){
                for(var field of this.relationshipFieldOptions){
                    if(field.value == this.selectedRelationshipField){
                        this.selectedRelationshipName = field.firstValue;
                        break;
                    }
                }
            }
            this.selectedObject = this.objectName;
            this.disableSelectedObject = true;
            this.showSpinner = false;
        }else{
            this.relationshipFieldOptions = undefined;
            this.selectedObject = undefined;
            this.selectedRelationshipField = undefined;
            this.selectedRelationshipName = undefined;
            this.whereClause = undefined;
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
        this.whereClause = undefined;

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
        this.filterValue = 0;
        this.operator = 'Equals';
        this.getRelationshipFieldOptions();
    }

    async getRelationshipFieldOptions(){

        this.relationshipFieldOptions = undefined;
        this.selectedRelationshipField = undefined;
        this.selectedRelationshipName = undefined;

        if(this.selectedObject){
            this.showSpinner = true;
            await getTargetFields({
                "parentObject" : this.parentObject,
                "selectedObject" : this.selectedObject
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

    handleSequenceChange(event){
        this.sequence = event.target.value;
    }

    handleOperatorChange(event){
        this.operator = event.target.value;
    }

    handleFilterValueChange(event){
        this.filterValue = event.target.value;
    }

    handleWhereClauseChange(event){
        this.whereClause = event.target.value;
    }

    handleCancel(){
        const selectedEvent = new CustomEvent("close");
        this.dispatchEvent(selectedEvent);
    }

    handleSave(){
        if(!this.selectedObject || this.selectedObject == '' || this.selectedObject == null){
            this.showToast('warning', 'Alert', 'Related Object is required.');
        }else if(!this.selectedRelationshipField || this.selectedRelationshipField == '' || this.selectedRelationshipField == null){
            this.showToast('warning', 'Alert', 'Relationship field is required.');
        }else if(!this.operator || this.operator == '' || this.operator == null){
            this.showToast('warning', 'Alert', 'Operator is required.');
        }else if(this.filterValue+"" == '' || this.filterValue+"" == null || this.filterValue < 0){
            this.showToast('warning', 'Alert', 'Qualify Count is required.');
        }else if(!this.sequence || this.sequence == '' || this.sequence == null || this.sequence <= 0){
            this.showToast('warning', 'Alert', 'Sequence is required and can only be a positive Integer.');
        }else{
            var obj = {
                "selectedObject" : this.selectedObject,
                "masterId" : this.masterId,
                "parentId" : this.parentId,
                "filterId" : this.filterId,
                "parentObject" : this.parentObject,
                "operator" : this.operator,
                "filterValue": this.filterValue,
                "sequence" : this.sequence+'',
                "whereClause" : this.whereClause,
                "relationshipField" : this.selectedRelationshipField,
                "relationshipName" : this.selectedRelationshipName
            };
            this.saveMapping(obj);
        }
    }

    async saveMapping(obj){
        this.showSpinner = true;
        await upsertRelatedFilter({
            "filterData" : obj,
        })
        .then(result => {          
            this.showToast('success', 'Success', 'Cross-Object Filter inserted sucessfully.');
            const selectedEvent = new CustomEvent("refresh");
            this.dispatchEvent(selectedEvent);
            this.handleCancel();
            this.showSpinner = false;
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
}