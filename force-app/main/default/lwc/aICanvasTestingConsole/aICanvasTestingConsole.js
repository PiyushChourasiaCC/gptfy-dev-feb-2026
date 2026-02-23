import { LightningElement, wire, track, api } from 'lwc';
import getCanvasTemplate from '@salesforce/apex/AICanvasTestingConsoleController.getCanvasTemplate';
import isValidVisibilityCondition from '@salesforce/apex/GPTfyConsoleController.isValidVisibilityCondition';
import gptfylogo from '@salesforce/resourceUrl/gptfylogo';

export default class AICanvasTestingConsole extends LightningElement {
    @api recordId;

    @track error;
    @track recordPickerError;
    @track targetobjectRecordId;
    @track canvasTemplateData;
    @track disableButton = false;
    @track validRecord = false;

    gptfylogo = gptfylogo;

    @wire(getCanvasTemplate, {recordId: '$recordId'})
    canvasTemplate({ error, data }){
        if(data){
            if(data.errorMessage){
                this.error = data.errorMessage;
            }else{
                this.canvasTemplateData = JSON.parse(JSON.stringify(data));
                this.error = '';
            }
            this.disableButton = true;
        }else if(error){
            this.error = error?.body?.message;
        }
    }

    get objectName(){
        return this.canvasTemplateData ? this.canvasTemplateData.objectApiName : null;
    }
    handlerRecordPicker(evt){
        this.targetobjectRecordId = evt.detail.recordId;
        if(this.targetobjectRecordId){
            this.validateVisibilityCondition();
        }
        this.validRecord = false;
    }
    async validateVisibilityCondition(){
        const recordPicker = this.template.querySelector('lightning-record-picker');
        try{
            let response = await isValidVisibilityCondition({
                objectApiName : this.objectName,
                recordId: this.targetobjectRecordId,
                whereClause: this.canvasTemplateData.visibilityCondition,
                selectedRecordTypes: null
            });
            if(response && response === true){
                this.disableButton = false;
                this.recordPickerError = '';
            }else{
                this.disableButton = true;
                this.recordPickerError =  'This record does not match with the prompt\'s visibility condition.';
            }
            recordPicker.setCustomValidity(this.recordPickerError);
            recordPicker.reportValidity();
        }catch(error){
            this.error = error;
        }
    }
    initiateCanvas(){
        this.validRecord = true;
    }
}