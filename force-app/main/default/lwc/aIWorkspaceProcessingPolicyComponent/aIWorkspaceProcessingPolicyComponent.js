import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import getPolicyData from '@salesforce/apex/AIWorkspaceProcessingPolicyController.getPolicyData';
import savePolicy from '@salesforce/apex/AIWorkspaceProcessingPolicyController.savePolicy';

import POLICY_OBJECT from '@salesforce/schema/AI_Workspace_Processing_Policy__c';
import PROMPT_FIELD from '@salesforce/schema/AI_Workspace_Processing_Policy__c.Prompt__c';
import USERS_FIELD from '@salesforce/schema/AI_Workspace_Processing_Policy__c.Users__c';
import PROFILES_FIELD from '@salesforce/schema/AI_Workspace_Processing_Policy__c.Profiles__c';

export default class AIWorkspaceProcessingPolicyComponent extends NavigationMixin(LightningElement) {

    @api recordId;
    @api objectApiName;

    @track showSpinner = false;
    @track modalHeader = 'New Workspace Processing Policy';
    
    @track policyName;
    @track promptId;
    @track userIds;
    @track profileIds;

    @track helpText_Name;
    @track helpText_Prompt;
    @track helpText_Users;
    @track helpText_Profiles;

    @track promptFieldApi = PROMPT_FIELD.fieldApiName;
    @track usersFieldApi = USERS_FIELD.fieldApiName;
    @track profilesFieldApi = PROFILES_FIELD.fieldApiName;
    @track policyObjectApi = POLICY_OBJECT.objectApiName;

    @wire(getObjectInfo, { objectApiName: POLICY_OBJECT })
    wiredRecord({ error, data }) {
        if (error) {
            this.handleError(error);
        } else if (data) {
            if (data.fields) {
                if (data.fields['Name'] && data.fields['Name'].inlineHelpText) {
                    this.helpText_Name = data.fields['Name'].inlineHelpText;
                }
                if (data.fields[PROMPT_FIELD.fieldApiName] && data.fields[PROMPT_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Prompt = data.fields[PROMPT_FIELD.fieldApiName].inlineHelpText;
                }
                if (data.fields[USERS_FIELD.fieldApiName] && data.fields[USERS_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Users = data.fields[USERS_FIELD.fieldApiName].inlineHelpText;
                }
                if (data.fields[PROFILES_FIELD.fieldApiName] && data.fields[PROFILES_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Profiles = data.fields[PROFILES_FIELD.fieldApiName].inlineHelpText;
                }
            }
        }
    }

    connectedCallback() {
        this.loadPolicyData();
    }

    async loadPolicyData() {
        if (!this.recordId) {
            return;
        }

        this.showSpinner = true;
        
        await getPolicyData({
            "recordId": this.recordId
        })
        .then(result => {
            if (result) {
                this.policyName = result.policyName;
                this.promptId = result.promptId;
                this.userIds = result.userIds;
                this.profileIds = result.profileIds;
                this.modalHeader = 'Edit ' + result.policyName;
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleNameChange(event) {
        this.policyName = event.target.value;
    }

    handlePromptChange(event) {
        this.promptId = event.target.value;
    }

    handleSave = () => {
        if (!this.policyName || this.policyName == '' || this.policyName == null) {
            this.showToast('warning', 'Alert!', 'Policy Name is required.');
            return;
        }

        const inputField = this.template.querySelector('lightning-input-field');
        if (inputField) {
            if (!inputField.reportValidity()) {
                this.showToast('warning', 'Alert!', 'Please provide a valid Prompt.');
                return;
            }
            this.promptId = inputField.value;
        }

        if (!this.promptId || this.promptId == '' || this.promptId == null) {
            this.showToast('warning', 'Alert!', 'Prompt is required.');
            return;
        }

        this.savePolicyData();
    }

    async savePolicyData() {
        this.showSpinner = true;

        var userIds = '';
        var profileIds = '';

        const userBuilder = this.template.querySelector('c-a-i-user-selection-builder');
        if (userBuilder) {
            var userObj = userBuilder.getValue();
            if (userObj) {
                userIds = userObj.value;
            }
        }

        const profileBuilder = this.template.querySelector('c-a-i-profile-selection-builder');
        if (profileBuilder) {
            var profileObj = profileBuilder.getValue();
            if (profileObj) {
                profileIds = profileObj.value;
            }
        }

        var obj = {
            "recordId": this.recordId,
            "policyName": this.policyName,
            "promptId": this.promptId,
            "userIds": userIds,
            "profileIds": profileIds
        };

        console.log('obj: '+JSON.stringify(obj));

        await savePolicy({
            "data": obj
        }).then(result => {
            console.log('result: '+JSON.stringify(result));
                if (result && result != null && result != '') {
                    const wasNewRecord = !this.recordId;
                    this.recordId = result;
                    this.showToast('success', 'Success', 'Policy saved successfully.');
                    
                    if (wasNewRecord) {
                        this.navigateToRecordPage();
                    } else {
                        this.handleCancel();
                    }
                } else {
                    this.showSpinner = false;
                    this.showToast('error', 'Error', 'Something went wrong. Please try again.');
                }
            })
            .catch(error => {
                this.handleError(error);
            });
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent("cancel", {}));
        if (this.recordId) {
            this.navigateToRecordPage();
        } else {
            this.navigateToListView();
        }
    }

    navigateToRecordPage() {
        if (this.recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.recordId,
                    objectApiName: this.objectApiName,
                    actionName: 'view'
                }
            });
        } else {
            const value = this.recordId;
            const selectedEvent = new CustomEvent("cancel", {
                detail: { value }
            });
            this.dispatchEvent(selectedEvent);
        }
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
            variant: variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    handleError(error) {
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if (error && error.body && error.body.message) {
            this.showToast('error', 'Error', error.body.message);
        } else {
            this.showToast('error', 'Error', error.toString());
        }
    }
}