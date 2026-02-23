import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import userId from '@salesforce/user/Id';

import checkPermissionSet from '@salesforce/apex/AISetupAssistantController.checkPermissionSet';
import getPromptOptions from '@salesforce/apex/AISetupAssistantController.getPromptOptions';
import updateSelectedPromptSettings from '@salesforce/apex/AISetupAssistantController.updateSelectedPromptSettings';
import updateRecordPageSettings from '@salesforce/apex/AISetupAssistantController.updateRecordPageSettings';
import getSelectedRecordPages from '@salesforce/apex/AISetupAssistantController.getSelectedRecordPages';
import startDataReview from '@salesforce/apex/AISetupAssistantController.startDataReview';
import checkDataReviewStatus from '@salesforce/apex/AISetupAssistantController.checkDataReviewStatus';
import completeDataReview from '@salesforce/apex/AISetupAssistantController.completeDataReview';

import HowToAddGPTfyConsole from "@salesforce/resourceUrl/HowToAddGPTfyConsole";

export default class AISetupAssistant extends NavigationMixin(LightningElement) {

    userId = userId;

    editRecordPageImageUrl = HowToAddGPTfyConsole;

    @track showSpinner;

    @track currentStep = '1';
    @track promptOptions;

    get showStep1(){
        if(this.currentStep == '1'){
            return true;
        }
        return false;
    }

    get showStep2(){
        if(this.currentStep == '2'){
            return true;
        }
        return false;
    }

    get showStep3(){
        if(this.currentStep == '3'){
            return true;
        }
        return false;
    }

    get showStep4(){
        if(this.currentStep == '4'){
            return true;
        }
        return false;
    }

    get pendingTime(){
        if(this.currentStep == '1'){
            return 20;
        }else if(this.currentStep == '2'){
            return 15;
        }else if(this.currentStep == '3'){
            return 5;
        }else if(this.currentStep == '4'){
            return 0;
        }
    }

    connectedCallback(){
        this.checkPermissionAssignment();
    }

    @track permissionAssignmentMissing = false;
    @track permissionSetAssignmentUrl;

    checkPermissionAssignment(){
        this.showSpinner = true;
        this.permissionAssignmentMissing = false;
        checkPermissionSet()
        .then(result => {
            if(result){
                this.getPromptOptions();
            }else{
                this.permissionSetAssignmentUrl = "/lightning/setup/PermSets/page?address=/udd/PermissionSet/assignPermissionSet.apexp?userId="+userId;
                this.permissionAssignmentMissing = true;
                this.showSpinner = false;
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    getPromptOptions(){
        this.showSpinner = true;
        this.promptOptions = undefined;

        getPromptOptions()
        .then(result => {
            if(result && result.length > 0){
                this.promptOptions = JSON.parse(JSON.stringify(result));
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handlePromptSelect(event){
        var index = event.target.dataset.index;
        if(index >= 0){
            let selected = false;
            if(this.promptOptions[index]['selected']){
                selected = true;
            }
            this.promptOptions[index]['selected'] = !selected;
        }
    }

    @track selectedPrompts;
    handleStep1Next(){
        this.selectedPrompts = [];
        var selectedPromptIds = [];
        if(this.promptOptions && this.promptOptions.length > 0){
            for(var pmt of this.promptOptions){
                if(pmt['selected']){
                    this.selectedPrompts.push(pmt);
                    selectedPromptIds.push(pmt['id']);
                }
            }
        }
        if(this.selectedPrompts && this.selectedPrompts.length > 0){
            this.updateSelectedPromptSettings(selectedPromptIds);
            this.currentStep = '2';
            this.checkDataReviewStatus();
        }else{
            this.showToast('warning', 'Alert.', 'Please select a Goal first before moving forward.');
        }
    }

    updateSelectedPromptSettings(selectedPromptIds){
        this.showSpinner = true;
        updateSelectedPromptSettings({
            "promptIds" : selectedPromptIds
        })
        .then(result => {
            this.currentStep = '2';
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleStep2Previous(){
        this.currentStep = '1';
    }

    @track selectedObjects;
    handleStep2Next(){

        for(var pmt of this.selectedPrompts){
            if((!pmt['candidateId'] || pmt['candidateId'] == null || pmt['candidateId'] == '') && !pmt['noRecordFound']){
                this.showToast('warning', 'Alert.', 'Please make sure all the steps are completed before moving forward.');
                return;
            }
        }

        this.selectedObjects = undefined;
        if(this.promptOptions && this.promptOptions.length > 0){
            var selectedObjectNames = [];
            this.selectedObjects = [];
            for(var pmt of this.promptOptions){
                if(!selectedObjectNames.includes(pmt['objectName']) && pmt['selected']){
                    this.selectedObjects.push({
                        "objectLabel" : pmt['objectLabel'],
                        "objectName" : pmt['objectName'],
                        "isCompleted" : false
                    });
                    selectedObjectNames.push(pmt['objectName']);
                }  
            }
        }
        this.getSelectedRecordPages();
    }

    getSelectedRecordPages(){
        this.showSpinner = true;
        getSelectedRecordPages()
        .then(result => {
            if(result && result.length > 0){
                var tempObjects = JSON.parse(JSON.stringify(this.selectedObjects));
                for(var obj of tempObjects){
                    if(result.includes(obj['objectName'])){
                        obj['isCompleted'] = true;
                    }
                }
                this.selectedObjects = JSON.parse(JSON.stringify(tempObjects));
            }
            this.currentStep = '3';
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleStep3Previous(){
        this.currentStep = '2';
    }

    handleStep3Next(){
        for(var obj of this.selectedObjects){
            if(!obj['isCompleted']){
                this.showToast('warning', 'Alert.', 'Please make sure all the steps are completed before moving forward.');
                return;
            }
        }

        var selectedObjectNames = [];
        for(var obj of this.selectedObjects){
            selectedObjectNames.push(obj['objectName']);
        }
        this.updateRecordPageSettings(selectedObjectNames);
    }

    updateRecordPageSettings(selectedObjectNames){
        this.showSpinner = true;
        updateRecordPageSettings({
            "objNames" : selectedObjectNames
        })
        .then(result => {
            this.currentStep = '4';
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleStep4Previous(){
        this.currentStep = '3';
    }

    handleRecordPageNavigation(event){
        let objName = event.target.dataset.objname;
        let candidateId = undefined;
        if(this.selectedPrompts && this.selectedPrompts.length > 0){
            for(var pmt of this.selectedPrompts){
                if(pmt.objectName == objName && pmt['candidateId']){
                    candidateId = pmt['candidateId'];
                    break;
                }
            }
        }
        if(candidateId){
            window.open("/"+candidateId, "_blank");
        }else{
            window.open("/lightning/o/"+objName+"/list", "_blank");
        }
    }

    handleLaunchClick(event){
        let candidateId = event.target.dataset.id;
        let objName = event.target.dataset.objname;
        if(candidateId){
            window.open("/"+candidateId, "_blank");
        }else{
            window.open("/lightning/o/"+objName+"/list", "_blank");
        }
    }

    handleMarkAsCompleted(event){
        let index = event.target.dataset.index;
        this.selectedObjects[index]['isCompleted'] = true;
    }

    @track isReviewRunning = false;
    handleRunDataReview(){
        this.isReviewRunning = true;
        var pmtIds = [];
        for(var pmt of this.selectedPrompts){
            pmt['candidateId'] = undefined;
            pmt['noRecordFound'] = false;
            pmtIds.push(pmt['id']);
        }
    
        startDataReview({
            "promptIds" : pmtIds
        })
        .then(result => {
            this._interval = setInterval(() => {  
                this.progress = this.progress + 1;   
                this.checkDataReviewStatus();
                if(this.progress === 100000 || !this.isReviewRunning) {  
                    clearInterval(this._interval);  
                }  
            }, this.progress);
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleRunDataComplete(){
        var pmtIds = [];
        for(var pmt of this.selectedPrompts){
            pmtIds.push(pmt['id']);
        }

        this.showSpinner = true;
        completeDataReview({
            "promptIds" : pmtIds
        })
        .then(result => {
            this.showSpinner = false;
            this.checkDataReviewStatus();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    disconnectedCallback(){
        clearInterval(this._interval);  
    }

    @track progress = 5000;
    _interval;

    checkDataReviewStatus(){
        checkDataReviewStatus()
        .then(result => {
            if(result && result.isReviewRunning){
                this.isReviewRunning = true;
            }else{
                this.isReviewRunning = false;
            }
            if(result && result.mapOfCandidates){
                for(var pmt of this.selectedPrompts){
                    var pmtId = pmt['id'];
                    if(result.mapOfCandidates[pmtId] && result.mapOfCandidates[pmtId] != null && result.mapOfCandidates[pmtId] != ''){         
                        if(result.mapOfCandidates[pmtId] != 'NO_RECORD_FOUND'){
                            pmt['candidateId'] = result.mapOfCandidates[pmtId];
                        }else{
                            pmt['noRecordFound'] = true;
                        }
                    }
                }
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    navigateToListView(objName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: objName,
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
            this.showToast('error', 'Error.', error.body.message);
        }else{
            this.showToast('error', 'Error.', error.toString());
        }
    }
}