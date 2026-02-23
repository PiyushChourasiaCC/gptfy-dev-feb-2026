import { LightningElement, track,wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';

import AI_DATASOURCE_OBJ from '@salesforce/schema/AI_Data_Source__c';
import DATA_SOURCE_FIELD from '@salesforce/schema/AI_Data_Source__c.Source__c';
import DATA_NAME_FIELD from '@salesforce/schema/AI_Data_Source__c.Name';
import NAMED_CREDENTIAL_FIELD from '@salesforce/schema/AI_Data_Source__c.Named_Credential__c';
import CONNECTOR_CLASS_FIELD from '@salesforce/schema/AI_Data_Source__c.Connector_Class__c';
import ENDPOINT_URL_FIELD from '@salesforce/schema/AI_Data_Source__c.EndPoint_URL__c';
import getDataSourceOptions from '@salesforce/apex/DataSourceController.getDataSourceOptions';
import getFields from '@salesforce/apex/DataSourceController.getFields';
import getLicensesForCheck from "@salesforce/apex/AILicenseManagerController.getLicensesForCheck";
import LICENSES_STARTER_PLAN from '@salesforce/label/c.LICENSES_STARTER_PLAN';
import LICENSES_PRO_PLAN from '@salesforce/label/c.LICENSES_PRO_PLAN';
import LICENSES_ENTERPRISE_PLAN from '@salesforce/label/c.LICENSES_ENTERPRISE_PLAN';
import Premium_Feature_Licenses_Message_Label from '@salesforce/label/c.Premium_Feature_Licenses_Message_Label';

import API_DataSource_Header_Label from '@salesforce/label/c.API_DataSource_Header_Label';

export default class AiDataSourceComponent extends NavigationMixin(LightningElement) {
    @track showSpinner = false;
    @track sourceOption;

    @track objectApiName = AI_DATASOURCE_OBJ.objectApiName;
    @track yellowLabelLicensesMessage = Premium_Feature_Licenses_Message_Label;
    label = {
        API_DataSource_Header_Label
    };

    /*@track fields = [{ 'Name': NAMED_CREDENTIAL_FIELD.fieldApiName },
    { 'Name': DATA_SOURCE_FIELD.fieldApiName },
    { 'Name': CONNECTOR_CLASS_FIELD.fieldApiName },
    { 'Name': ENDPOINT_URL_FIELD.fieldApiName }];*/

    @track fields = [];

    // Create Own Properties Start
    @track showCCComponent = false;
    @track showEditBtn = false;
    @track metadata;
    @track sobj;
    // Create Own Properties End

    @track isLicensePresent = false;
    
    get disableCSS(){
        if(!this.isLicensePresent){
            return 'pointer-events: none;cursor: default;opacity: 0.6;'
        }else{
            return 'pointer-events: all;'
        }
    }

    @wire(CurrentPageReference)
    currentPageReference

    connectedCallback() {
        this.doInit();
    }



    async doInit() {
        console.log(this.currentPageReference.state)
        this.showSpinner = true;
        this.sourceOption = undefined;
        await getLicensesForCheck()
        .then(result => {
            if(result){
                if(result.licenseBypass){
                    this.isLicensePresent = true;
                }else{
                    if(result.licenses && result.licenses.length > 0){
                        result.licenses.forEach((item)=> {
                            if(item.status === 'Active'){
                                let licenseType = item.licenseType.toLowerCase()
                                if(licenseType === LICENSES_ENTERPRISE_PLAN.toLowerCase() || licenseType === LICENSES_PRO_PLAN.toLowerCase()){
                                    this.isLicensePresent = true;
                                }
                            }
                        })
                    }
                }
            }
        })
        .catch(error => {
            this.handleError(error);
        });

        await getDataSourceOptions()
            .then(result => {
                if (result && result.length > 0) {
                    this.sourceOption = JSON.parse(JSON.stringify(result));
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
        for (var res of this.sourceOption) {
            if (res.aiName == resName) {
                resource = res;
                break;
            }
        }
        if (resource) {
            console.log('res: ' + JSON.stringify(resource));
            if (resource.conId && resource.conId != null && resource.conId != '') {
                this.navigateToViewRecordPage(resource.conId);
            } else {
                this.handleNewConnection(resource);
            }
        }
    }

    handleNewConnection(resource) {
        const defaultValues = encodeDefaultFieldValues({
            [DATA_SOURCE_FIELD.fieldApiName]: resource.aiName,
            [DATA_NAME_FIELD.fieldApiName]: resource.aiLabel
        });

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: AI_DATASOURCE_OBJ.objectApiName,
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
        //this.doInit();
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