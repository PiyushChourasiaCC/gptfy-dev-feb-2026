import { LightningElement, api,wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {  createRecord, updateRecord  } from 'lightning/uiRecordApi';
import PROMPT_SCHEDULER_OBJ from '@salesforce/schema/AI_Prompt_Scheduler__c';

import ID_FIELD from '@salesforce/schema/AI_Prompt_Scheduler__c.Id';
import PROMPT_FIELD from '@salesforce/schema/AI_Prompt_Scheduler__c.Prompt__c';
import AI_SCH_FIELD from '@salesforce/schema/AI_Prompt_Scheduler__c.AI_Scheduler__c';
import REC_LIMIT_FIELD from '@salesforce/schema/AI_Prompt_Scheduler__c.Record_Limit__c';
import WHERE_CLAUSE_FIELD from '@salesforce/schema/AI_Prompt_Scheduler__c.Where_Clause__c';

import getPromptOptions from '@salesforce/apex/AIPromptSchedulerController.getPromptOptions';
import getPromptSchedulerData from '@salesforce/apex/AIPromptSchedulerController.getPromptSchedulerData';
import getPromptSchedulerDetail from '@salesforce/apex/AIPromptSchedulerController.getPromptSchedulerDetail';
import AiPromptWhereClauseFormulaComponent from 'c/aiPromptWhereClauseFormulaComponent';
import isValidVisibilityCondition from '@salesforce/apex/AIPromptValidationController.isValidVisibilityCondition';

import { NavigationMixin } from 'lightning/navigation';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';

export default class AiPromptSchedulerOverride extends NavigationMixin(LightningElement) {
    
    @api recordId;
    @api schedulerData;
    @api selectedObjectName;
    @api schedulerId;
    promptOptions = []
    
    showSpinner = true;

    

    @wire(getObjectInfo, { objectApiName: PROMPT_SCHEDULER_OBJ.objectApiName })
    wiredRecord({ error, data }) {
       // let j = JSON.parse(JSON.stringify(data));
       // console.log(j)
        if(error){
            this.handleError(error);
        }else if(data){
            if(data.fields){
                if(data.fields['Prompt__c'] && data.fields['Prompt__c'].inlineHelpText){
                    this.helpText_Prompt = data.fields['Prompt__c'].inlineHelpText;
                }if(data.fields['Record_Limit__c'] && data.fields['Record_Limit__c'].inlineHelpText){
                    this.helpText_RecordLimit = data.fields['Record_Limit__c'].inlineHelpText;
                }if(data.fields['Where_Clause__c'] && data.fields['Where_Clause__c'].inlineHelpText){
                    this.helpText_WhereClause = data.fields['Where_Clause__c'].inlineHelpText;
                }
            }
        }
    }

    connectedCallback(){
        this.promptSchedulerObjectApi = PROMPT_SCHEDULER_OBJ.objectApiName;
        this.promptFieldApi = PROMPT_FIELD.fieldApiName;
        this.recordLimitFieldApi = REC_LIMIT_FIELD.fieldApiName;
        this.whereClauseFieldApi = WHERE_CLAUSE_FIELD.fieldApiName;
        this.showAddModal = this.showModal;
        this.getAllPromptOptions();
    }


    handleWhereClauseChange(event){
        this.schedulerData.whereClause = event.target.value;
    }

    handleRecordLimitChange(event){
        this.schedulerData.recordLimit = event.target.value;
    }

    handleOpenVisibilityCondition = async (e) => {
        const result = await AiPromptWhereClauseFormulaComponent.open({
            size: 'medium',
            description: 'WHERE Clause',
            objectApiName: this.selectedObjectName,
        });
        if (result) {
            let s = this.schedulerData;
            s.whereClause = result;
            this.schedulerData = s;
        }
    }

    handlePromptChange(event){
        this.schedulerData.promptId = event.target.value;
        for(var pmt of this.promptOptions){
            if(pmt.value == this.schedulerData.promptId){
                if(this.selectedObjectName != pmt.description){
                    this.schedulerData.whereClause = '';
                }
                this.selectedObjectName = pmt.description;
                break;
            }
        }
    }

    getCurrentPromptSchedulerDetail(recId){
        this.schedulerData = {};
        getPromptSchedulerDetail({
            "recordId" : recId
        })
        .then(result => {
            this.schedulerData = JSON.parse(JSON.stringify(result));
            if(this.schedulerData && this.schedulerData['objectName']){
                this.selectedObjectName = this.schedulerData['objectName'];
            }
            //for(var pmt of this.promptOptions){
             //   if(this.schedulerData && pmt.value == this.schedulerData.promptId){
                   // this.selectedObjectName = pmt.description;
                  //  break;
              //  }
            //}
            this.showAddModal = true;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    async getPromptSchedulers(){
        this.showSpinner = true;
        this.fields = undefined;
        this.records = undefined;
        this.selectedRecordId = undefined;
        this.selectedObjectName = undefined;

        await getPromptSchedulerData({
            "recordId" : this.recordId
        })
        .then(result => {          
            //console.log('result: '+JSON.stringify(result));
            if(result && result.records && result.records.length > 0){
                var tempFields = JSON.parse(JSON.stringify(result.fields));

                var referenceFields = [];
                for(var field of tempFields){
                    field['sortable'] = true;
                    if(field.fieldName == 'Name' || field.isReference == true){
                        if(field.isReference == true){
                            referenceFields.push(field.fieldName);
                        }
                        field['type'] = 'url';

                        let refField = field.fieldName;
                        if(refField.endsWith('__c')){
                            refField = refField.slice(0, -3)+'__r.Name';
                        }else if(refField.endsWith('Id')){
                            refField = refField.slice(0, -2)+'.Name';
                        }
                        referenceFields.push(refField);

                        field['typeAttributes'] = {label:{fieldName:refField}, tooltip:{fieldName : refField}, target: "_self"};
                        field['fieldName'] = field.fieldName+"_____recordLink";                   
                    }
                }
                var actionObj = {
                    type: 'action',
                    typeAttributes: { rowActions: actions },
                }
                tempFields.push(actionObj);
                this.fields = JSON.parse(JSON.stringify(tempFields));

                var tempRecords = JSON.parse(JSON.stringify(result.records));
                for(var rec of tempRecords){
                    if(referenceFields && referenceFields.length > 0){
                        for(var refField of referenceFields){
                            if(refField == 'Name'){
                                rec['Name_____recordLink'] = '/'+rec['Id'];
                            }else{
                                if(refField.includes('.')){
                                    rec[refField] = rec[refField.split('.')[0]][refField.split('.')[1]];
                                }else{
                                    rec[refField+'_____recordLink'] = '/'+rec[refField];
                                }
                            }
                        }
                    }
                }

                this.records = JSON.parse(JSON.stringify(tempRecords));
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    getAllPromptOptions(){
        this.showSpinner = true;
        getPromptOptions()
        .then(result => {
            this.promptOptions = JSON.parse(JSON.stringify(result));
            this.showSpinner = false;
            if(this.recordId)
                this.getCurrentPromptSchedulerDetail(this.recordId);
            else
               this.schedulerData = { promptId: ''}
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handlePromptChange(event){
        this.schedulerData.promptId = event.target.value;
        for(var pmt of this.promptOptions){
            if(this.schedulerData && pmt.value == this.schedulerData.promptId){
                if(this.selectedObjectName != pmt.description){
                    this.schedulerData.whereClause = '';
                }
                this.selectedObjectName = pmt.description;
                break;
            }
        }
    }

    handleSave(){
        var data = {
            [WHERE_CLAUSE_FIELD.fieldApiName] : this.schedulerData.whereClause,
            [REC_LIMIT_FIELD.fieldApiName] : this.schedulerData.recordLimit 
        };

        if(this.schedulerData.id){
            data[ID_FIELD.fieldApiName] = this.schedulerData.id;
        }else{
            data[AI_SCH_FIELD.fieldApiName] = (this.recordId)? this.recordId : this.schedulerId;
            data[PROMPT_FIELD.fieldApiName] = this.schedulerData.promptId
        }

        if((!data[PROMPT_FIELD.fieldApiName] || data[PROMPT_FIELD.fieldApiName] == '' || data[PROMPT_FIELD.fieldApiName] == null) && !this.schedulerData.id){
            this.showToast('error', 'Error', 'Prompt is required.');
        }else{

            if(data[WHERE_CLAUSE_FIELD.fieldApiName] && data[WHERE_CLAUSE_FIELD.fieldApiName] != '' && data[WHERE_CLAUSE_FIELD.fieldApiName] != null){
                isValidVisibilityCondition({"objName": this.selectedObjectName , "whereClause": data[WHERE_CLAUSE_FIELD.fieldApiName]})
                    .then((res)=>{
                        if(res){
                            if(this.schedulerData.id){
                                this.updatePromptComponent(data);
                            }else{
                                this.createPromptComponent(data);
                            }
                        }else{
                            this.showToast('warning', 'Alert!', 'Where Clause is not valid.');
                        }
                    }).catch(error=> {
                        this.showToast('warning', 'Alert!', 'Where Clause is not valid.');
                    })
            }else{
                if(this.schedulerData.id){
                    this.updatePromptComponent(data);
                }else{
                    this.createPromptComponent(data);
                }
            }

           
        }
    }

    updatePromptComponent(data){
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
        const recordInput = {apiName:PROMPT_SCHEDULER_OBJ.objectApiName, 'fields':data};
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

    handleCancel() {
        if (this.recordId || this.schedulerId) {
            this.naviagteToRecordPage();
        } else {
            this.navigateToListView();
        }
    }

    naviagteToRecordPage() {
        const value = (this.recordId)? this.recordId:this.schedulerId ;
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