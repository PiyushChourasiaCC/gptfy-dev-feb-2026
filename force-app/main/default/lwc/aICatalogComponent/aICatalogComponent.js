import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

import AI_CONN_OBJ from '@salesforce/schema/AI_Connection__c';
import CONN_TECH_FIELD from '@salesforce/schema/AI_Connection__c.AI_Technology__c';
import CONN_NAME_FIELD from '@salesforce/schema/AI_Connection__c.Name';
import NAMED_CREDENTIAL_FIELD from '@salesforce/schema/AI_Connection__c.Named_Credential__c';
import CONNECTOR_CLASS_FIELD from '@salesforce/schema/AI_Connection__c.Connector_Class__c';
import PROCESSING_CLASS_FIELD from '@salesforce/schema/AI_Connection__c.Processing_Class__c';
import INFRASTRUCTURE_FIELD from '@salesforce/schema/AI_Connection__c.Infrastructure__c';
import SECURITY_LAYER_FIELD from '@salesforce/schema/AI_Connection__c.Security_Layer__c';
import VERSION_FIELD from '@salesforce/schema/AI_Connection__c.Version__c';
import ENABLE_IN_SANDBOX_FIELD from '@salesforce/schema/AI_Connection__c.Enable_in_Sandbox__c';
import MODEL_FIELD from '@salesforce/schema/AI_Connection__c.Model__c';
import MAX_TOKENS_FIELD from '@salesforce/schema/AI_Connection__c.Max_Tokens__c';
import TEMPERATURE_FIELD from '@salesforce/schema/AI_Connection__c.Temperature__c';
import ENDPOINT_URL_FIELD from '@salesforce/schema/AI_Connection__c.EndPoint_URL__c';
import TOP_P_FIELD from '@salesforce/schema/AI_Connection__c.Top_P__c';

import getCatalogOptions from '@salesforce/apex/CatalogController.getCatalogOptions';
import getFields from '@salesforce/apex/CatalogController.getFields';

import Connections_header_label from '@salesforce/label/c.Connections_header_label';

export default class AICatalogComponent extends NavigationMixin(LightningElement) {

    label = {
        Connections_header_label
    };

    @track objectApiName = AI_CONN_OBJ.objectApiName;

    @track showSpinner = false;

    @track connectionOptions;

    /*@track fields = [
        { 'Name': NAMED_CREDENTIAL_FIELD.fieldApiName },
        { 'Name': CONN_TECH_FIELD.fieldApiName },
        { 'Name': CONNECTOR_CLASS_FIELD.fieldApiName },
        { 'Name': INFRASTRUCTURE_FIELD.fieldApiName },
        { 'Name': PROCESSING_CLASS_FIELD.fieldApiName },
        { 'Name': SECURITY_LAYER_FIELD.fieldApiName },
        { 'Name': VERSION_FIELD.fieldApiName },
        { 'Name': ENABLE_IN_SANDBOX_FIELD.fieldApiName },
        { 'Name': MODEL_FIELD.fieldApiName },
        { 'Name': MAX_TOKENS_FIELD.fieldApiName },
        { 'Name': TEMPERATURE_FIELD.fieldApiName },
        { 'Name': ENDPOINT_URL_FIELD.fieldApiName },
        { 'Name': TOP_P_FIELD.fieldApiName }
    ];*/

    @track fields = [];

    // Create Own Properties Start
    @track showCCComponent = false;
    @track showEditBtn = false;
    @track metadata;
    @track sobj;
    // Create Own Properties End

    connectedCallback() {
        this.doInit();
    }

    async doInit() {
        this.showSpinner = true;
        this.connectionOptions = undefined;

        await getCatalogOptions()
            .then(result => {
                if (result && result.length > 0) {
                    this.connectionOptions = JSON.parse(JSON.stringify(result));
                    this.getFieldOptions();
                }
                this.showSpinner = false;
            })
            .catch(error => {
                this.handleError(error);
            });

    }

    getFieldOptions() {
        this.showSpinner = true;
        getFields()
            .then(result => {
                if (result && result.length > 0) {
                    this.fields = result;
                }
                this.showSpinner = false;
            })
            .catch(error => {
                this.handleError(error);
            });
    }


    handleConnectionNavigate(event) {
        var resName = event.target.dataset.id;
        var resource = undefined;
        for (var res of this.connectionOptions) {
            if (res.aiName == resName) {
                resource = res;
                break;
            }
        }
        if (resource) {
            if (resource.conId && resource.conId != null && resource.conId != '') {
                this.navigateToViewRecordPage(resource.conId);
            } else {
                this.handleNewConnection(resource);
            }
        }
    }

    handleNewConnection(resource) {
        const defaultValues = encodeDefaultFieldValues({
            [CONN_TECH_FIELD.fieldApiName]: resource.aiName,
            [CONN_NAME_FIELD.fieldApiName]: resource.aiLabel
        });

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: AI_CONN_OBJ.objectApiName,
                actionName: 'new'
            },
            state: {
                defaultFieldValues: defaultValues
            }
        });
    }

    navigateToViewRecordPage(recId) {
        // Navigate to the view record page
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recId,
                actionName: 'view'
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

    handleCreateYourOwn() {
        this.metadata = '';
        this.showEditBtn = false;
        this.showCCComponent = true;
        this.sobj = undefined;
    }

    handleCancel(event) {
        this.showCCComponent = false;
    }

    handleSuccess() {
        if (this.sobj && this.sobj.Id) {
            notifyRecordUpdateAvailable([{ recordId: this.sobj.Id }]);
        }
        this.metadata = undefined;
        this.sobj = undefined;
        this.showCCComponent = false;
        const cmp = this.template.querySelector('c-gptfy-card-detail-component');
        cmp.doInit();
    }

    handleEditCard(event) {
        let mdt = event.detail.rec.mdtRecord;
        mdt.Icon_Details = mdt.Icon_Details.substring(mdt.Icon_Details.lastIndexOf('/') + 1);
        this.metadata = mdt;
        this.showCCComponent = true;
        this.showEditBtn = true;
        this.showSpinner = false;
        if (event.detail.rec.hasOwnProperty('record')) {
            this.sobj = event.detail.rec.record;
        } else {
            this.sobj = undefined;
        }
    }
}