import { LightningElement, api, wire } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPromptContentDocumentId from '@salesforce/apex/AIJsonGeneration.getPromptContentDocumentId';
import getPromptContentVersion from '@salesforce/apex/AIJsonGeneration.getPromptContentVersion';
import importReinstateVersion from '@salesforce/apex/AIJsonGeneration.importReinstateVersion';
import AIPrompt from "@salesforce/messageChannel/AI_Prompt__c"
import {subscribe, MessageContext, APPLICATION_SCOPE,   
        unsubscribe,publish} from 'lightning/messageService';

export default class AIPromptVersionControlComponent extends NavigationMixin(LightningElement) {

    @api recordId;
    hasRecords = false;
    showSpinner = true;
    showReinstatePopup = false;
    contentDocumentId;
    currentVersionNumber;
    totalRecords = 0;

    versionDetails;

    @api columns = [];
    @api records = [];

    @wire(MessageContext)
    context
    
    connectedCallback(){
        this.subscribeMessage()
        this.columns.push({ label: 'Version Number', fieldName: 'VersionNumberUrl', type: 'url' , typeAttributes: {label: { fieldName: 'VersionNumber' },target: '_blank'},sortable: false});
        this.columns.push({ label: 'Content Modified By', fieldName: 'ModifiedByUrl', type: 'url', typeAttributes: {label: { fieldName: 'ModifiedByName' },target: '_blank'},sortable: false});
        this.columns.push({ label: 'Content Modified Date', fieldName: 'LastModifiedDate', type: 'date', typeAttributes:{day: 'numeric', month: 'numeric',year: 'numeric', hour: '2-digit',  minute: '2-digit', timeZone:'UTC'},sortable: false});
        this.columns.push({ label: 'What Changed?', fieldName: 'ReasonForChange', type: 'text', sortable: false });
        this.columns.push({ type: "button", typeAttributes: {label: {fieldName: 'blabel'}, name: 'Reinstate',  title: {fieldName: 'btitle'}, disabled: {fieldName: 'bdisabled'}, value: {fieldName: 'bvalue'}, class: {fieldName: 'bclass'}, variant: {fieldName: 'bvariant'}} , initialWidth: 110});
        
        this.fetchContentdocumentId();
    }

    subscribeMessage(){
        subscribe(this.context, AIPrompt,   
                 (data)=>{this.handleDataRefresh(data)},  
                                         {scope:APPLICATION_SCOPE})
    }

    handleDataRefresh(data){
        if(data.isRefresh){
            this.fetchContentdocumentId();
        }
    }

    handleRefresh(event){
        this.fetchContentdocumentId();
    }

    fetchContentdocumentId(){
        this.showSpinner = true;
        getPromptContentDocumentId({recordId:this.recordId})
        .then(result => {    
            if(result){
                this.contentDocumentId = result.split('_')[0];
                this.currentVersionNumber = result.split('_')[1];
                this.fetchPromptContentVersion();
            }else{
                this.showSpinner = false;
            }     
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    fetchPromptContentVersion(){
        getPromptContentVersion({contentDocumentId:this.contentDocumentId})
        .then(result => {    
            this.totalRecords = result.length;
            if(result.length>0){
                result.forEach((element, index) => {  
                    result[index]['ModifiedByUrl'] = '/ ' + element.LastModifiedById;
                    result[index]['ModifiedByName'] = element.LastModifiedBy.Name;  
                    result[index]['VersionNumberUrl'] = '/sfc/servlet.shepherd/version/download/'+element.Id;  
                    result[index]['blabel'] = 'Reinstate';
                    result[index]['btitle'] = 'Reinstate';
                    result[index]['bvalue'] = 'Reinstate';
                    if(this.currentVersionNumber == element.VersionNumber){
                        result[index]['bdisabled'] = true;
                        result[index]['bclass'] = 'slds-button_neutral';
                    }else{
                        result[index]['bdisabled'] = false;
                        result[index]['bclass'] = 'slds-button_brand';
                        result[index]['bvariant'] = 'brand';
                    }
                    result[index].VersionNumber = 'Version ' + element.VersionNumber;
                });
                this.hasRecords = true;
            }
            this.records = result;
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    navigateToRelatedList(event){
        if(this.contentDocumentId){
            this[NavigationMixin.Navigate] ({
                type: 'standard__recordRelationshipPage', 
                attributes: {
                   recordId: this.contentDocumentId, 
                   objectApiName: 'ContentDocument', 
                   relationshipApiName: 'ContentVersions', 
                   actionName: 'view' 
                } 
            });
        }
    }

    
    handleRowAction(event){
        const recId =  event.detail.row.Id;  
        const actionName = event.detail.action.name;
        if (actionName === 'Reinstate') {
            this.versionDetails = event.detail.row;
            this.showReinstatePopup = true;
        }
    }

    handleHideReinstatePopup(event){
        this.versionDetails = {};
        this.showReinstatePopup = false;
    }

    handleConfirmReinstatePopup(event){
        this.handleImportReinstateVersion(this.versionDetails.Id, this.versionDetails.VersionNumber);
    }

    handleImportReinstateVersion(tVersionId, versionNumber){
        this.showSpinner = true;
        importReinstateVersion({recordId:this.recordId, versionId:tVersionId})
        .then(result => {    
            this.showReinstatePopup = false;
            updateRecord({ fields: { Id: this.recordId }});
            this.fetchContentdocumentId();
            this.showToast('success', 'Success', versionNumber+' reinstated successfully!');
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
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

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

}