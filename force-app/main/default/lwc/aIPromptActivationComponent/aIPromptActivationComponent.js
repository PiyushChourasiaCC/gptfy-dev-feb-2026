import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { updateRecord } from 'lightning/uiRecordApi';
import generatePromptCommand from '@salesforce/apex/AIJsonGeneration.generatePromptCommand';
import checkValidationPromptCommand from '@salesforce/apex/AIJsonGeneration.checkValidationPromptCommand';
import isEnablePromptVersioning from '@salesforce/apex/AIJsonGeneration.isEnablePromptVersioning';
import isPromptVersionEmpty from '@salesforce/apex/AIJsonGeneration.isPromptVersionEmpty';
import updateWhatNeeded from '@salesforce/apex/AIJsonGeneration.updateWhatNeeded';
import AIPrompt from "@salesforce/messageChannel/AI_Prompt__c"
import {subscribe, MessageContext, APPLICATION_SCOPE,   
        unsubscribe,publish} from 'lightning/messageService';

export default class AIPromptActivationComponent extends LightningElement {
    @api recordId;

    retrievedRecordId = false;
    showSpinner = true;
    enablePromptVersioning = false;
    promptActivatied = false;

    @wire(MessageContext)
    context;

    renderedCallback(){
        if (!this.retrievedRecordId && this.recordId) {
            this.retrievedRecordId = true;
            this.runPromptActivation();
        }
    }

    handleContinue(event){
        this.showSpinner = true;
        const textarea = this.template.querySelector('lightning-textarea');
        //console.log('---'+ (textarea?textarea.value:''));
        this.createPrompt(textarea?textarea.value:'');
    }


    createPrompt = (comment)=> {
        generatePromptCommand({
            "recordId" : this.recordId
        })
        .then(result => {         
            if(result && result.length > 0){
                this.showToast('error', 'Error', result);
                updateRecord({ fields: { Id: this.recordId }});
                publish(this.context, AIPrompt, {'isRefresh':true});
                this.showSpinner = false;
                this.closeQuickAction();
            }else if(comment){
                updateWhatNeeded({
                    "recordId" : this.recordId,
                    "comment" : comment
                })
                .then(result => {         
                    this.showToast('success', 'Success', 'Prompt Activated Successfully.');
                    publish(this.context, AIPrompt, {'isRefresh':true});
                    updateRecord({ fields: { Id: this.recordId }});
                    this.showSpinner = false;
                    this.closeQuickAction();
                })
                .catch(error => {
                    this.handleError(error);
                });
            }else{
                this.showToast('success', 'Success', 'Prompt Activated Successfully.');
                publish(this.context, AIPrompt, {'isRefresh':true});
                updateRecord({ fields: { Id: this.recordId }});
                this.showSpinner = false;
                this.closeQuickAction();
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }


    handleClose(event){
        // if(this.promptActivatied){
        //     this.showToast('success', 'Success', 'Prompt Activated Successfully.');
        //     updateRecord({ fields: { Id: this.recordId }});
        // }
        this.closeQuickAction();
    }

    runPromptActivation(comment){

        this.showSpinner = true;
        checkValidationPromptCommand({
            "recordId" : this.recordId
        })
        .then(result => {         
            if(result && result.length > 0){
                this.showToast('error', 'Error', result);
                updateRecord({ fields: { Id: this.recordId }});
                publish(this.context, AIPrompt, {'isRefresh':true});
                this.closeQuickAction();
            }else{
                this.promptActivatied = true;
                this.enablePromptVersioningHelper();
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    enablePromptVersioningHelper(){
        isEnablePromptVersioning()
        .then(result => {         
           if(result){
                isPromptVersionEmpty({
                    "recordId" : this.recordId
                })
                .then(isVersionContentEmpty => {
                    if(isVersionContentEmpty){
                        this.createPrompt();
                    }else{
                        this.enablePromptVersioning = result; 
                        this.showSpinner = false; 
                    }
                
                }).catch(error => {
                    this.handleError(error);
                })
           }else{
                this.createPrompt()
            }
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
        this.closeQuickAction();
    }

    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

}