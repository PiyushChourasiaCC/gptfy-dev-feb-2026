import { api, track, LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMasterData from '@salesforce/apex/AIDataExtractionController.getMasterData';
import modifyMaster from '@salesforce/apex/AIDataExtractionController.modifyMaster';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import EXT_MAPPING_OBJECT from '@salesforce/schema/AI_Data_Extraction_Mapping__c';

export default class AIDataExtractionOverride  extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    @track objects;
    @track showSpinner = false;
    
    @track description;
    @track mappingName;
    @track targetObject;
    @track selectedObjectLabel;
    @track aiDataSource;

    @track helpText_MapName;
    @track helpText_TargetObject;
    @track helpText_Description;

    @track dataSourceOptions;
    @track helpText_DataSource;

    @track apexSecurityLayerOptions;
    @track apexSecurityLayer;

    @wire(getObjectInfo, { objectApiName: EXT_MAPPING_OBJECT })
    wiredRecord({ error, data }) {
        if(error){
            this.handleError(error);
        }else if(data){
            if(data.fields){
                if(data.fields['Name'] && data.fields['Name'].inlineHelpText){
                    this.helpText_PromptName = data.fields['Name'].inlineHelpText;
                }if(data.fields['Object_Name__c'] && data.fields['Object_Name__c'].inlineHelpText){
                    this.helpText_TargetObject = data.fields['Object_Name__c'].inlineHelpText;
                }if(data.fields['Description__c'] && data.fields['Description__c'].inlineHelpText){
                    this.helpText_description = data.fields['Description__c'].inlineHelpText;
                }if(data.fields['AI_Data_Source__c'] && data.fields['AI_Data_Source__c'].inlineHelpText){
                    this.helpText_DataSource = data.fields['AI_Data_Source__c'].inlineHelpText;
                }
            }
        }
    }
    

    connectedCallback(){
        this.getDefaultData();
    }

    async getDefaultData(){
        this.showSpinner = true;
        this.objects = undefined;
        this.description = undefined;
        this.mappingName = undefined;
        this.targetObject = undefined;
        this.selectedObjectLabel = undefined;
        this.aiDataSource = undefined;
        this.dataSourceOptions = undefined;
        this.apexSecurityLayerOptions = undefined;

        await getMasterData({
            "recordId" : this.recordId
        })
        .then(result => {          
            if(result && result.objects && result.objects.length > 0){;
                this.objects = JSON.parse(JSON.stringify(result.objects));
                if(result.mappingName && result.mappingName != '' && result.mappingName != null){
                    this.description = result.description;
                    this.mappingName = result.mappingName;
                    this.targetObject = result.objectName;
                    this.selectedObjectLabel = result.objectLabel;
                    this.aiDataSource = result.aiDataSource;
                    this.apexSecurityLayer = result.apexSecurityLayer;
                }
                if(result.dataSourceOptions && result.dataSourceOptions.length > 0){
                    this.dataSourceOptions = JSON.parse(JSON.stringify(result.dataSourceOptions));
                }
                if(result.apexSecurityLayerOptions && result.apexSecurityLayerOptions.length > 0){
                    this.apexSecurityLayerOptions = JSON.parse(JSON.stringify(result.apexSecurityLayerOptions));
                }
            }else{
                this.showToast('warning', 'Alert!', 'No objects found.');
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleObjectChange(event){
        var objName = event.target.value;
        if(objName){
            for(var obj of this.objects){
                if(obj.value == objName){
                    this.selectedObjectLabel = obj.firstValue;
                }
            }
        }else{
            this.selectedObjectLabel = '';
        }
    }

    handleLabelChange(event){
        this.selectedObjectLabel = event.target.value;
    }

    handleSave(){
        var mappingName = this.template.querySelector(".mappingName").value;
        var targetObject = this.template.querySelector(".targetObject").value;
        var description = this.template.querySelector(".description").value;
        if(!mappingName || mappingName == '' || mappingName == null){
            this.showToast('warning', 'Alert', 'Mapping name cannot be blank.');
        }else if(!targetObject || targetObject == '' || targetObject == null){
            this.showToast('warning', 'Alert', 'Target object must be selected.');
        }else if(!this.selectedObjectLabel || this.selectedObjectLabel == '' || this.selectedObjectLabel == null){
            this.showToast('warning', 'Alert', 'Object Label cannot be blank.');
        }else{
            this.modifyRecord(mappingName, targetObject, description);
        }
    }

    async modifyRecord(mappingName, targetObject, description){
        this.showSpinner = true;

        var obj = {
            "recordId" : this.recordId,
            "mappingName" : mappingName,
            "targetObject" : targetObject,
            "description" : description,
            "objLabel" : this.selectedObjectLabel,
            "aiDataSource" : this.aiDataSource,
            "apexSecurityLayer" : this.apexSecurityLayer
        };

        await modifyMaster({
            "data" : obj
        })
        .then(result => {          
            if(result && result.length > 0){
                this.showToast('success', 'Success', 'AI Data Context Mapping modified successfully.');
                this.recordId = result;
                this.handleCancel();
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleDataSourceChange(event){
        this.aiDataSource = event.target.value;
    }

    handleApexSecurityLayerChange(event){
        this.apexSecurityLayer = event.target.value;
    }

    handleCancel(){
        if(this.recordId){
            this.naviagteToRecordPage();
        }else{
            this.navigateToListView();
        }
    }

    naviagteToRecordPage(){
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