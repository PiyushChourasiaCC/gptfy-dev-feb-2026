import { LightningElement, track, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import GPTFY_SETTINGS_OBJ from '@salesforce/schema/GPTfy_Settings__c';
import SECURITY_AUDIT_OBJ from '@salesforce/schema/AI_Response__c';

import AiPromptWhereClauseFormulaComponent from 'c/aiPromptWhereClauseFormulaComponent';


import TYPE_EFFECT_FIELD from '@salesforce/schema/GPTfy_Settings__c.Typewriter_Effect__c';
import FILE_PROCESSING_FIELD from '@salesforce/schema/GPTfy_Settings__c.File_Processing__c';
import PREFIX_SUFFIX_FIELD from '@salesforce/schema/GPTfy_Settings__c.Prefix_Suffix__c';
import EXCEPTION_LOG_FIELD from '@salesforce/schema/GPTfy_Settings__c.Exception_Log__c';
import PROMPT_VERSION_FIELD from '@salesforce/schema/GPTfy_Settings__c.Prompt_Versioning__c';
import MAX_FILE_SIZE_FIELD from '@salesforce/schema/GPTfy_Settings__c.Max_File_Size__c';
import FILE_TYPE_FIELD from '@salesforce/schema/GPTfy_Settings__c.File_Type__c';
import MAX_FILE_COUNT_FIELD from '@salesforce/schema/GPTfy_Settings__c.Max_File_Count__c';
import REPORTING_PERIOD_FIELD from '@salesforce/schema/GPTfy_Settings__c.Reporting_Period__c';
import HOURLY_COST_FIELD from '@salesforce/schema/GPTfy_Settings__c.Hourly_Cost__c';
import ADDITIONAL_INPUT_SEPARATOR_FIELD from '@salesforce/schema/GPTfy_Settings__c.Additional_Input_Separator__c';
import WHERE_CLAUSE_FIELD from '@salesforce/schema/Retention_Preference__c.Where_Clause__c';
import ENABLE_FOR_DATACLOUD_FIELD from '@salesforce/schema/GPTfy_Settings__c.Enable_for_Data_Cloud__c';
import SALESFORCE_DOMAIN_URL_FIELD from '@salesforce/schema/GPTfy_Settings__c.Salesforce_Domain_URL__c';
import SALESFORCE_ADMIN_EMAIL_FIELD from '@salesforce/schema/GPTfy_Settings__c.Salesforce_Admin_Email__c';
import SALESFORCE_CLIENT_ID_FIELD from '@salesforce/schema/GPTfy_Settings__c.Salesforce_Client_Id__c';
import SALESFORCE_PRIVATE_KEY_FILE_ID_FIELD from '@salesforce/schema/GPTfy_Settings__c.Salesforce_Private_Key_File_Id__c';
import SALESFORCE_AUTH_NAMED_CREDENTIAL_FIELD from '@salesforce/schema/GPTfy_Settings__c.Salesforce_Auth_Named_Credential__c';
import DATA_CLOUD_NAMED_CREDENTIAL_FIELD from '@salesforce/schema/GPTfy_Settings__c.Data_Cloud_Named_Credentials__c';

import getDetails from '@salesforce/apex/AIOrgWideSetupController.getDetails';
import updateStatus from '@salesforce/apex/AIOrgWideSetupController.updateStatus';
import updateCustomSettings from '@salesforce/apex/AIUtility.updateCustomSettings';
import scheduleTheJob from '@salesforce/apex/AIOrgWideSetupController.scheduleJob';
import abortTheJob from '@salesforce/apex/AIOrgWideSetupController.abortJob';
import updateGPTfySettings from '@salesforce/apex/AIUtility.updateGPTfySettings';
import updateRetentionPreference from '@salesforce/apex/AIOrgWideSetupController.updateRetentionPreference';

import AI_Settings_Header_Label from '@salesforce/label/c.AI_Settings_Header_Label';

export default class OrgWideSetupComponent extends NavigationMixin(LightningElement) {

    label = {
        AI_Settings_Header_Label
    };

    DATA_TYPE_NUMBER = 'Number'
    @track showSpinner = false;
    @track activeTab = 1;
    @track isModalOpen = false;
    @track scheduledTime = '08:00'; 

    activeSessions = ['A', 'B', 'C'];

    connectedCallback(){
        this.getSetupDetails();
    }

    @track setupInfo;

    helpText_TypewriterEffect;
    helpText_FileProcessing;
    helpText_PrefixSuffix;
    helpText_ExceptionLog;
    helpText_PromptVersion;
    helpText_FileType;
    helpText_MaxFileSize;
    helpText_MaxFileCount;
    helpText_EnableForDataCloud;
    helpText_SalesforceDomainUrl;
    helpText_SalesforceClientId;
    helpText_SalesforceAdminEmail;
    helpText_SalesforcePrivateKeyFileId;
    helpText_SalesforceAuthNamedCredential;
    helpText_DataCloudNamedCredential;

    @wire(getObjectInfo, { objectApiName: GPTFY_SETTINGS_OBJ })
    wiredRecord({ error, data }) {
        if (error) {
            this.handleError(error);
        } else if (data) {
            if (data.fields) {
                if (data.fields[TYPE_EFFECT_FIELD.fieldApiName] && data.fields[TYPE_EFFECT_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_TypewriterEffect = data.fields[TYPE_EFFECT_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[FILE_PROCESSING_FIELD.fieldApiName] && data.fields[FILE_PROCESSING_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_FileProcessing = data.fields[FILE_PROCESSING_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[PREFIX_SUFFIX_FIELD.fieldApiName] && data.fields[PREFIX_SUFFIX_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_PrefixSuffix = data.fields[PREFIX_SUFFIX_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[EXCEPTION_LOG_FIELD.fieldApiName] && data.fields[EXCEPTION_LOG_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_ExceptionLog = data.fields[EXCEPTION_LOG_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[PROMPT_VERSION_FIELD.fieldApiName] && data.fields[PROMPT_VERSION_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_PromptVersion = data.fields[PROMPT_VERSION_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[FILE_TYPE_FIELD.fieldApiName] && data.fields[FILE_TYPE_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_FileType = data.fields[FILE_TYPE_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[MAX_FILE_SIZE_FIELD.fieldApiName] && data.fields[MAX_FILE_SIZE_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_MaxFileSize = data.fields[MAX_FILE_SIZE_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[MAX_FILE_COUNT_FIELD.fieldApiName] && data.fields[MAX_FILE_COUNT_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_MaxFileCount = data.fields[MAX_FILE_COUNT_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[HOURLY_COST_FIELD.fieldApiName] && data.fields[HOURLY_COST_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Hourly_Cost = data.fields[HOURLY_COST_FIELD.fieldApiName].inlineHelpText;
                }if (data.fields[ADDITIONAL_INPUT_SEPARATOR_FIELD.fieldApiName] && data.fields[ADDITIONAL_INPUT_SEPARATOR_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Hourly_Cost = data.fields[ADDITIONAL_INPUT_SEPARATOR_FIELD.fieldApiName].inlineHelpText;
                }if (data.fields[ENABLE_FOR_DATACLOUD_FIELD.fieldApiName] && data.fields[ENABLE_FOR_DATACLOUD_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_EnableForDataCloud = data.fields[ENABLE_FOR_DATACLOUD_FIELD.fieldApiName].inlineHelpText;
                }if (data.fields[SALESFORCE_DOMAIN_URL_FIELD.fieldApiName] && data.fields[SALESFORCE_DOMAIN_URL_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_SalesforceDomainUrl = data.fields[SALESFORCE_DOMAIN_URL_FIELD.fieldApiName].inlineHelpText;
                }if (data.fields[SALESFORCE_CLIENT_ID_FIELD.fieldApiName] && data.fields[SALESFORCE_CLIENT_ID_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_SalesforceClientId = data.fields[SALESFORCE_CLIENT_ID_FIELD.fieldApiName].inlineHelpText;
                }if (data.fields[SALESFORCE_ADMIN_EMAIL_FIELD.fieldApiName] && data.fields[SALESFORCE_ADMIN_EMAIL_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_SalesforceAdminEmail = data.fields[SALESFORCE_ADMIN_EMAIL_FIELD.fieldApiName].inlineHelpText;
                }if (data.fields[SALESFORCE_PRIVATE_KEY_FILE_ID_FIELD.fieldApiName] && data.fields[SALESFORCE_PRIVATE_KEY_FILE_ID_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_SalesforcePrivateKeyFileId = data.fields[SALESFORCE_PRIVATE_KEY_FILE_ID_FIELD.fieldApiName].inlineHelpText;
                }if (data.fields[SALESFORCE_AUTH_NAMED_CREDENTIAL_FIELD.fieldApiName] && data.fields[SALESFORCE_AUTH_NAMED_CREDENTIAL_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_SalesforceAuthNamedCredential = data.fields[SALESFORCE_AUTH_NAMED_CREDENTIAL_FIELD.fieldApiName].inlineHelpText;
                }if (data.fields[DATA_CLOUD_NAMED_CREDENTIAL_FIELD.fieldApiName] && data.fields[DATA_CLOUD_NAMED_CREDENTIAL_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_DataCloudNamedCredential = data.fields[DATA_CLOUD_NAMED_CREDENTIAL_FIELD.fieldApiName].inlineHelpText;
                }
                
            }
        }
    }

    getSetupDetails(){
        this.showSpinner = true;
        getDetails()
        .then(result => {
            this.setupInfo = JSON.parse(JSON.stringify(result));
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
       // console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error.', error.body.message);
        }else{
            this.showToast('error', 'Error.', error.toString());
        }
    }

    handleCustomLabelNavigate(){
        window.open("/lightning/setup/ExternalStrings/home", "_blank");
    }

    handleActiveTab(event) {
       this.activeTab = event.target.value;
    }

    handleStatusChange(event){
        const isActive = event.target.checked;
        if (isActive) {
            this.isModalOpen = true;
        } else {
            this.abortScheduledJob();
        }

        var status = event.target.checked;
        if(status && !this.setupInfo.noOfDays || this.setupInfo.noOfDays <= 0){
            this.showToast('error', 'Error.', '"Delete Security Records After (Days)" must be greater than 0.');
            this.handleUpdateSettings(false, this.setupInfo.noOfDays);
        }else{       
            this.handleUpdateSettings(status, this.setupInfo.noOfDays);
        }
    }

    handleExceptionLogChange(event){
        this.handleCustomSettingUpdate(EXCEPTION_LOG_FIELD.fieldApiName, event.target.checked);
    }

    handlePromptVersionChange(event){
        this.handleCustomSettingUpdate(PROMPT_VERSION_FIELD.fieldApiName, event.target.checked);
    }

    handleFileProcessingChange(event){
        this.handleCustomSettingUpdate(FILE_PROCESSING_FIELD.fieldApiName, event.target.checked);
    }

    handlePrefixSuffixChange(event){
        this.handleCustomSettingUpdate(PREFIX_SUFFIX_FIELD.fieldApiName, event.target.checked);
    }

    handleTypewriterEffectChange(event){
        this.handleCustomSettingUpdate(TYPE_EFFECT_FIELD.fieldApiName, event.target.checked);
    }

    handleMaxFileSizeChange(event){
        this.handleGPTfySettingUpdate(MAX_FILE_SIZE_FIELD.fieldApiName, parseInt(event.target.value));
    }

    handleFileTypeChange(event){
        this.handleGPTfySettingUpdate(FILE_TYPE_FIELD.fieldApiName, event.target.value);
    }

    handleMaxFileCountChange(event){
        this.handleGPTfySettingUpdate(MAX_FILE_COUNT_FIELD.fieldApiName, parseInt(event.target.value));
    }

    handleReportingPeriodChange(event){
        this.handleGPTfySettingUpdate(REPORTING_PERIOD_FIELD.fieldApiName, parseInt(event.target.value));
    }

    handleHourlyCostChange(event){
        this.handleGPTfySettingUpdate(HOURLY_COST_FIELD.fieldApiName, parseFloat(event.target.value));
    }

    handleAdditionalInstructions(event){
        this.handleGPTfySettingUpdate(ADDITIONAL_INPUT_SEPARATOR_FIELD.fieldApiName, event.target.value);
    }

    handleWhereClauseChange(event){
        this.handleRetentionPreferenceUpdate(WHERE_CLAUSE_FIELD.fieldApiName, event.target.value);
    }

    handleDaysUpdate(event){
        var value = event.target.value;
        if(value && value > 0){
            this.handleUpdateSettings(this.setupInfo.status, value);
        }else{
            this.showToast('error', 'Error.', '"Delete Security Records After (Days)" must be greater than 0.');
            this.handleUpdateSettings(this.setupInfo.status, this.setupInfo.noOfDays);
        }
    }

    
    handleEnableForDataCloudChange(event){
        this.handleGPTfySettingUpdate(ENABLE_FOR_DATACLOUD_FIELD.fieldApiName, event.target.checked);
    }

    handleSalesforceDomainUrlChange(event){
        this.handleGPTfySettingUpdate(SALESFORCE_DOMAIN_URL_FIELD.fieldApiName, event.target.value);
    }

    handleSalesforceClientIdChange(event){
        this.handleGPTfySettingUpdate(SALESFORCE_CLIENT_ID_FIELD.fieldApiName, event.target.value);
    }
    handleSalesforceAdminEmailChange(event){
        this.handleGPTfySettingUpdate(SALESFORCE_ADMIN_EMAIL_FIELD.fieldApiName, event.target.value);
    }

    handleSalesforcePrivatekeyFileIdChange(event){
        this.handleGPTfySettingUpdate(SALESFORCE_PRIVATE_KEY_FILE_ID_FIELD.fieldApiName, event.target.value);
    }

    handleSalesforceAuthNamedCredentialChange(event){
        this.handleGPTfySettingUpdate(SALESFORCE_AUTH_NAMED_CREDENTIAL_FIELD.fieldApiName, event.target.value);
    }

    handleDataCloudNamedCredentialChange(event){
        this.handleGPTfySettingUpdate(DATA_CLOUD_NAMED_CREDENTIAL_FIELD.fieldApiName, event.target.value);
    }


    handleUpdateSettings(status, value){
        this.showSpinner = true;
        updateStatus({
            isActive : status,
            noOfDays : value
        })
        .then(result => {
            this.setupInfo = JSON.parse(JSON.stringify(result));
            this.getSetupDetails();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleRetentionPreferenceUpdate(labelName, newValue){
        this.showSpinner = true;
        updateRetentionPreference({
            fieldName : labelName,
            value : newValue
        }).then(result => {
            this.getSetupDetails();
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleGPTfySettingUpdate(labelName, newValue){
        this.showSpinner = true;
        updateGPTfySettings({
            fieldName : labelName,
            value : newValue
        }).then(result => {
            this.getSetupDetails();
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleCustomSettingUpdate(labelName, newValue){
        this.showSpinner = true;
        updateCustomSettings({
            fieldName : labelName,
            value : newValue
        }).then(result => {
            this.getSetupDetails();
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleTimeChange(event) {
        this.scheduledTime = event.target.value;
    }

    closeModal() {
        this.isModalOpen = false;
        this.setupInfo.status = false;
        this.handleUpdateSettings(this.setupInfo.status, this.setupInfo.noOfDays);
    }

    scheduleJob() {
        const cronExpr = this.convertTimeToCron(this.scheduledTime);
        
        scheduleTheJob({ cronExpr: cronExpr })
        .then(() => {
            this.showToast('success', 'Success', 'Job scheduled successfully');
            this.isModalOpen = false;
            console.log(' In then => Job scheduled successfully');
        })
        .catch(error => {
            this.handleError(error);
            this.isModalOpen = false;
            console.log(' In catch => Job is not scheduled successfully');
        });

        //updateStatus
        this.handleUpdateSettings(true, this.setupInfo.noOfDays);
    }

    convertTimeToCron(time) {
        // Assume time is in HH:mm format
        const [hour, minute] = time.split(':');
        // 0 second, minute, hour, every day, every month, every weekday
        return `0 ${minute} ${hour} * * ?`;
    }

    abortScheduledJob() {
        abortTheJob()
        .then(() => {
            this.showToast('success', 'Success', 'Job aborted successfully');
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleOpenVisibilityCondition = async (e) => {
        console.log(SECURITY_AUDIT_OBJ)
        const result = await AiPromptWhereClauseFormulaComponent.open({
            size: 'medium',
            description: 'Where Clause',
            objectApiName: SECURITY_AUDIT_OBJ.objectApiName,
        });
        if (result) {
            this.handleRetentionPreferenceUpdate(WHERE_CLAUSE_FIELD.fieldApiName,result)
        }

    }


}