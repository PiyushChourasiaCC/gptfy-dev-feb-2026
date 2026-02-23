import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { createRecord, updateRecord } from 'lightning/uiRecordApi';

import getComponentObjects from '@salesforce/apex/AIPromptComponentController.getComponentObjects';
import getCustomSettings from '@salesforce/apex/AIUtility.getCustomSettings';

import PROMPT_CMP_OBJ from '@salesforce/schema/AI_Prompt_Component__c';

import ID_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Id';
import DATA_EX_ID_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Data_Extraction_Id__c';
import OBJ_NAME_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Object_Name__c';
import AI_PMT_FIELD from '@salesforce/schema/AI_Prompt_Component__c.AI_Prompt__c';
import NAME_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Name';
import ACTION_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Key__c';
import ADD_INS_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Additional_Instructions__c';
import CONS_VAL_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Constraint_Value__c';
import FORMAT_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Format__c';
import LANG_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Language__c';
import LENGTH_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Length__c';
import TONE_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Tone__c';
import USER_CUST_FIELD from '@salesforce/schema/AI_Prompt_Component__c.User_Customizable__c';

import BEF_ACTION_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_Before_Action__c';
import AFT_ACTION_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_After_Action__c';
import BEF_TONE_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_Before_Tone__c';
import AFT_TONE_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_After_Tone__c';
import BEF_LEN_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_Before_Length__c';
import AFT_LEN_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_After_Length__c';
import BEF_LANG_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_Before_Language__c';
import AFT_LANG_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_After_Language__c';
import BEF_FORMAT_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_Before_Format__c';
import AFT_FORMAT_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_After_Format__c';
import BEF_CONS_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_Before_Contraints__c';
import AFT_CONS_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_After_Contraints__c';
import BEF_OBJ_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_Before_Object__c';
import AFT_OBJ_FIELD from '@salesforce/schema/AI_Prompt_Component__c.Phrase_After_Object__c';

export default class AIPromptComponentOverride extends NavigationMixin(LightningElement) {

    @api parentId;
    @api recordId;

    @track showSpinner = false;

    @track selectedObject;
    @track objects;
    
    @track objectName;
    @track nameFieldApi;
    @track actionFieldApi;
    @track addInsFieldApi;
    @track consValFieldApi;
    @track formatFieldApi;
    @track langFieldApi;
    @track lenghtFieldApi;
    @track toneFieldApi;
    @track userCustFieldApi;
    @track objNameFieldApi;

    @track befActFieldApi;
    @track aftActFieldApi;
    @track befToneFieldApi;
    @track aftToneFieldApi;
    @track befLenFieldApi;
    @track aftLenFieldApi;
    @track befLangFieldApi;
    @track aftLangFieldApi;
    @track befFormatFieldApi;
    @track aftFormatFieldApi;
    @track befConsFieldApi;
    @track aftConsFieldApi;
    @track befObjFieldApi;
    @track aftObjFieldApi;

    @track showExtraFields = true;

    connectedCallback(){

        this.showExtraFields = false;
        getCustomSettings()
        .then(result => {          
            if(result && result['prefixSuffix']){
                this.showExtraFields = result['prefixSuffix'];
            }
        })
        .catch(error => {
            this.handleError(error);
        });

        this.objectName = PROMPT_CMP_OBJ.objectApiName;
        this.nameFieldApi = NAME_FIELD.fieldApiName;
        this.actionFieldApi = ACTION_FIELD.fieldApiName;
        this.addInsFieldApi = ADD_INS_FIELD.fieldApiName;
        this.consValFieldApi = CONS_VAL_FIELD.fieldApiName;
        this.formatFieldApi = FORMAT_FIELD.fieldApiName;
        this.langFieldApi = LANG_FIELD.fieldApiName;
        this.lenghtFieldApi = LENGTH_FIELD.fieldApiName;
        this.toneFieldApi = TONE_FIELD.fieldApiName;
        this.userCustFieldApi = USER_CUST_FIELD.fieldApiName;
        this.objNameFieldApi = OBJ_NAME_FIELD.fieldApiName;

        this.befActFieldApi = BEF_ACTION_FIELD.fieldApiName;
        this.aftActFieldApi = AFT_ACTION_FIELD.fieldApiName;
        this.befToneFieldApi = BEF_TONE_FIELD.fieldApiName;
        this.aftToneFieldApi = AFT_TONE_FIELD.fieldApiName;
        this.befLenFieldApi = BEF_LEN_FIELD.fieldApiName;
        this.aftLenFieldApi = AFT_LEN_FIELD.fieldApiName;
        this.befLangFieldApi = BEF_LANG_FIELD.fieldApiName;
        this.aftLangFieldApi = AFT_LANG_FIELD.fieldApiName;
        this.befFormatFieldApi = BEF_FORMAT_FIELD.fieldApiName;
        this.aftFormatFieldApi = AFT_FORMAT_FIELD.fieldApiName;
        this.befConsFieldApi = BEF_CONS_FIELD.fieldApiName;
        this.aftConsFieldApi = AFT_CONS_FIELD.fieldApiName;
        this.befObjFieldApi = BEF_OBJ_FIELD.fieldApiName;
        this.aftObjFieldApi = AFT_OBJ_FIELD.fieldApiName;


        if(this.parentId && !this.recordId){
            this.getObjectsFromMapping();
        }
    }

    async getObjectsFromMapping(){
        this.showSpinner = true;
        this.objects = undefined;
        this.selectedObject = undefined;

        await getComponentObjects({
            "parentId" : this.parentId
        })
        .then(result => {          
            if(result && result.length > 0){;
                this.objects = JSON.parse(JSON.stringify(result));
                this.selectedObject = this.objects[0].value;
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleObjectChange(event){
        this.selectedObject = event.target.value;
    }

    handleCancel(){
        //if(this.parentId){
            const value = this.recordId;
            const selectedEvent = new CustomEvent("close", {
                detail: { value }
            });
            this.dispatchEvent(selectedEvent);
        //}
    }

    handleSave(){
        var data = {};
        const inputFields = this.template.querySelectorAll('lightning-input-field');
        if(inputFields){
            inputFields.forEach(field =>{
                data[field.fieldName] = field.value;
            });
        }

        if(this.recordId){
            data[ID_FIELD.fieldApiName] = this.recordId;
        }else{
            data[AI_PMT_FIELD.fieldApiName] = this.parentId;
            for(var obj of this.objects){
                if(this.selectedObject == obj.value){
                    data[DATA_EX_ID_FIELD.fieldApiName] = obj.value;
                    data[OBJ_NAME_FIELD.fieldApiName] = obj.label;
                    break;
                }
            }
        }

        if(!data[NAME_FIELD.fieldApiName] || data[NAME_FIELD.fieldApiName] == '' || data[NAME_FIELD.fieldApiName] == null){
            this.showToast('error', 'Error', 'Component name is required.');
        }else if(!data[ACTION_FIELD.fieldApiName] || data[ACTION_FIELD.fieldApiName] == '' || data[ACTION_FIELD.fieldApiName] == null){
            this.showToast('error', 'Error', 'Action is required.');
        }else if(!this.recordId && (!this.selectedObject || this.selectedObject == '' || this.selectedObject == null)){
            this.showToast('error', 'Error', 'Object is required.');
        }else{
            if(this.recordId){
                this.updatePromptComponent(data);
            }else{
                this.createPromptComponent(data);
            }
        }
        //console.log('data: '+JSON.stringify(data));
    }

    updatePromptComponent(data){
        console.log('updatePromptComponent: '+JSON.stringify(data));
        this.showSpinner = true;
        const recordInput = {'fields':data};
        updateRecord(recordInput)
        .then(result => {
            this.showToast('success', 'Success', 'Record updated successfully.');
            this.handleCancel();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    createPromptComponent(data){
        this.showSpinner = true;
        console.log('createPromptComponent: '+JSON.stringify(data));
        const recordInput = {apiName:PROMPT_CMP_OBJ.objectApiName, 'fields':data};
        createRecord(recordInput)
        .then(result => {
            this.showToast('success', 'Success', 'Record created successfully.');
            this.handleCancel();
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
        if(error && error.body && error.body.output && error.body.output.errors && error.body.output.errors.length > 0 && error.body.output.errors[0].message){
            this.showToast('error', 'Error', error.body.output.errors[0].message);
        }else if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }
}