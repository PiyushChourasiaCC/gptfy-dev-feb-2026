import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import DATA_EXT_FIELD from '@salesforce/schema/AI_Prompt__c.AI_Data_Extraction_Mapping__c';
const fields = [DATA_EXT_FIELD];

export default class AIDataExtractionContainer extends LightningElement {

    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields })
    prompt;

    get dataExtractionId() {
        if(this.recordId){
            return getFieldValue(this.prompt.data, DATA_EXT_FIELD);
        }
        return '';
    }

}