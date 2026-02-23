import { LightningElement, track, api } from 'lwc';
import findRecords from "@salesforce/apex/CustomLookupController.getRecords";
import getPicklistValues from "@salesforce/apex/CustomLookupController.getPicklistValues";
import getsobjectMappingFields from "@salesforce/apex/CustomLookupController.getsobjectMappingFields";
import createResponseMapping from "@salesforce/apex/CustomLookupController.createResponseMapping";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AICustomLookupComponent extends LightningElement {
    @api field = 'Name';
    @track recordsList;
    @track searchKey = "";
    @api selectedValue;
    @api selectedRecordId;
    @api objectApiName;
    @api iconName;
    @api lookupLabel;
    @api name;
    @track isNewRecord = false;
    @track message;
    @track selectedRecordList = [];
    @track aiModelOptions = [];
    selectedAIModel = '';
    @api responseMappingOptions = [];
    showSpinner = false;
    showFieldPicker = false;
    startObjName;
    @track selectedField = {};
    @track dynamicCmpCreationStates = [];

    connectedCallback(){
        getPicklistValues({objectName:this.objectApiName,fieldName:'AI_Model__c'})
        .then((result) => {
            var tempOptions = [];
            tempOptions.push({label:'-None-', value:''});
            for(var key in result){
                tempOptions.push({label:result[key], value:key});
            }
            this.aiModelOptions = tempOptions;
        })
        .catch((error) => {
            console.log('error key : ' + JSON.stringify(error));
            
        });
        this.fetchsobjectMappingFields();
    }

    fetchsobjectMappingFields(){
        getsobjectMappingFields({objectName:'AI_Response__c', fieldSetName:'Response_Mapping'})
        .then((result) => {
            var tempResponseMapping = [];
            let index = 1;
            for(var key in result){
                tempResponseMapping.push({index:index, label:result[key], field:key, selectedMapping:'', mappingOptions: [{label:'-None-', value:''}]});
                index++;
            }
            this.responseMappingOptions = tempResponseMapping;
        })
        .catch((error) => {
            console.log('error key : ' + JSON.stringify(error));
        });
    }
    
    onLeave(event) {
        setTimeout(() => {
            this.searchKey = "";
            this.recordsList = null;
        }, 300);
    }
    onRecordSelection(event) {
        this.selectedRecordId = event.target.dataset.key;
        this.selectedValue = event.target.dataset.name;
        this.recordsList.forEach(element => {
            if (element.Id == event.target.dataset.key) {
                this.selectedRecordList = {Id:this.selectedRecordId, name:this.selectedValue};
            }
        });
        this.searchKey = "";
        this.onSeletedRecordUpdate();
    }
    handleKeyChange(event) {
        const searchKey = event.target.value;
        this.searchKey = searchKey;
        this.getLookupResult();
    }
    removeRecordOnLookup(event) {
        this.searchKey = "";
        this.selectedValue = null;
        this.selectedRecordId = null;
        this.recordsList = null;
        this.onSeletedRecordUpdate();
    }
    getLookupResult() {
        findRecords({ objectName: this.objectApiName, field: this.field, searchTerm: this.searchKey })
            .then((result) => {
                if (result.length === 0) {
                    this.recordsList = [];
                    this.message = "No Records Found";
                } else {
                    this.recordsList = result;
                    this.message = "";
                }
                this.error = undefined;
            })
            .catch((error) => {
                console.log('error key : ' + JSON.stringify(error));
                this.error = error;
                this.recordsList = undefined;
            });
    }

    onSeletedRecordUpdate() {
        const passEventr = new CustomEvent('select', {
            detail: { record: this.selectedRecordList, sectionName: this.name }
        });
        this.dispatchEvent(passEventr);
    }
    createNewRecord() {
        this.isNewRecord = !this.isNewRecord;
    }
    handleAIModelChange(event){
        this.selectedAIModel = event.detail.value;
    }
    handleMappingOptionChange(event){
        let index = event.target.dataset.index-1;
        let fieldVal = event.detail.value;
        this.responseMappingOptions[index].selectedMapping =fieldVal;
        if(fieldVal && fieldVal.indexOf('>') != -1){
            var inputCmp = this.template.querySelector('.textAreaBody');
            if(inputCmp && inputCmp.value){
                let sampleResponseJSON = JSON.parse(inputCmp.value);
                let fieldValArray = fieldVal.split('>');
                for(let i=0;i<fieldValArray.length;i++){
                    let node = fieldValArray[i].trim();
                    if(node && node.length >0 && node != '>'){
                        sampleResponseJSON = sampleResponseJSON[node];
                        if(Array.isArray(sampleResponseJSON)){
                            sampleResponseJSON = sampleResponseJSON[0];
                        }
                    }
                }
                let keys = this.getKeys(sampleResponseJSON);
                var keyOptions = [];
                if(keys){
                    for(let j=0;j<keys.length;j++){
                        keyOptions.push({label:keys[j], value:keys[j]});
                    }
                }
                var options = [];
                options.push({uniqueid:0, selector:true, dataList:keyOptions, righArrow:true, selectedMapping:fieldVal, label:false});
                this.dynamicCmpCreationStates = options;
            }

            this.startObjName = event.detail.value.replace('>', '');
            this.selectedField['index'] = index;
            this.selectedField['visible'] = false;
            this.selectedField['title'] = '';
            this.selectedField['api'] = '';
            this.showFieldPicker = true;
        }
    }

    setValue(event){
        let uniqueid = event.target.dataset.uniqueid;
        let fieldVal = event.detail.value;
        if(uniqueid < this.dynamicCmpCreationStates.length-1){
            var newdynamicCmpCreationStates = [];
            for(let k=0;k<this.dynamicCmpCreationStates.length;k++){
                if(k<=uniqueid){
                    newdynamicCmpCreationStates.push(this.dynamicCmpCreationStates[k]);
                }
            }
            this.dynamicCmpCreationStates = newdynamicCmpCreationStates;
        }
        if(fieldVal && fieldVal.indexOf('>') != -1){
            this.dynamicCmpCreationStates[uniqueid].selector = true;
            this.dynamicCmpCreationStates[uniqueid].label = false;
            let tfieldVal = '';
            
            if(this.dynamicCmpCreationStates){
                for(let k=0;k<this.dynamicCmpCreationStates.length;k++){
                    tfieldVal += this.dynamicCmpCreationStates[k].selectedMapping;
                }
            }
            tfieldVal += fieldVal;
            var inputCmp = this.template.querySelector('.textAreaBody');
            if(inputCmp && inputCmp.value){
                let sampleResponseJSON = JSON.parse(inputCmp.value);
                let fieldValArray = tfieldVal.split('>');
                for(let i=0;i<fieldValArray.length;i++){
                    let node = fieldValArray[i].trim();
                    if(node && node.length >0 && node != '>'){
                        sampleResponseJSON = sampleResponseJSON[node];
                        if(Array.isArray(sampleResponseJSON)){
                            sampleResponseJSON = sampleResponseJSON[0];
                        }
                    }
                }
                let keys = this.getKeys(sampleResponseJSON);
                var keyOptions = [];
                if(keys){
                    for(let j=0;j<keys.length;j++){
                        keyOptions.push({label:keys[j], value:keys[j]});
                    }
                }
                this.dynamicCmpCreationStates.push({uniqueid:parseInt(uniqueid)+1, selector:true, dataList:keyOptions, righArrow:true, selectedMapping:fieldVal, label:false});
            }
            //this.responseMappingOptions[this.selectedField.index].selectedMapping = tfieldVal;
        }else{
            this.dynamicCmpCreationStates[uniqueid].selector = false;
            this.dynamicCmpCreationStates[uniqueid].label = true;
            this.dynamicCmpCreationStates[uniqueid]['selectedFieldInfoStr'] = fieldVal;
            this.dynamicCmpCreationStates[uniqueid]['selectedFieldInfo'] = fieldVal;
            this.selectedField.visible = true;
            let tfieldVal = '';
            for(let k=0;k<this.dynamicCmpCreationStates.length;k++){
                tfieldVal += this.dynamicCmpCreationStates[k].selectedMapping;
            }
            this.selectedField.title = tfieldVal+fieldVal;
            this.selectedField.api = tfieldVal.replaceAll(' >','.').trim()+fieldVal;
        }
    }

    openSelector(event){
        let uniqueid = event.currentTarget.dataset.uniqueid;
        this.selectedField.visible = false;
        this.selectedField.title = '';
        this.selectedField.api = '';
        this.dynamicCmpCreationStates[uniqueid].selector = true;
        this.dynamicCmpCreationStates[uniqueid].label = false;
        this.dynamicCmpCreationStates[uniqueid]['selectedFieldInfoStr'] = '';
        this.dynamicCmpCreationStates[uniqueid]['selectedFieldInfo'] = '';
    }

    handleSelectField(event){
        this.responseMappingOptions[this.selectedField.index].mappingOptions.push({label:this.selectedField.title, value:this.selectedField.api});
        this.responseMappingOptions[this.selectedField.index].selectedMapping = this.selectedField.api;
        this.startObjName = '';
        this.selectedField.index = 0;
        this.selectedField.visible = false;
        this.selectedField.title = '';
        this.selectedField.api = '';
        this.showFieldPicker = false;
    }

    closeFieldPicker(event){
        this.responseMappingOptions[this.selectedField.index].selectedMapping = '';
        this.startObjName = '';
        this.selectedField.index = 0;
        this.selectedField.visible = false;
        this.selectedField.title = '';
        this.selectedField.api = '';
        this.showFieldPicker = false;
    }

    handleChangeSampleResponse(event){
        var inputCmp = this.template.querySelector('.textAreaBody');
        inputCmp.setCustomValidity('');

        let sampleResponse = event.detail.value;
        if(sampleResponse){
            try{
                let sampleResponseJSON = JSON.parse(sampleResponse);
                let keys = this.getKeys(sampleResponseJSON);//Object.keys(sampleResponseJSON);
                let tempMappingOptions = [];
                tempMappingOptions.push({label:'-None-', value:''});
                if(keys){
                    for(let j=0;j<keys.length;j++){
                        tempMappingOptions.push({label:keys[j], value:keys[j]});
                    }
                }
                
                if(this.responseMappingOptions){
                    for(let i=0;i<this.responseMappingOptions.length;i++){
                        this.responseMappingOptions[i].selectedMapping = '';
                        this.responseMappingOptions[i].mappingOptions = tempMappingOptions;
                    }
                }
                this.responseMappingOptions = [...this.responseMappingOptions];
            }catch(err) {
                inputCmp.setCustomValidity(err);
            }
        }
        inputCmp.reportValidity();
    }

    getKeys(data) {
        return Object.entries(data).reduce((r, [key, value]) => {
            if (value && typeof value === 'object'){
                r.push(key+' >');
            }else{
                r.push(key);
            }
            return r
        }, []);
    }
   
    handleSave(event){
        let isValid = true;
        let obj = {}
        let mFields = [];
        const inputFields = this.template.querySelectorAll('.field-input');
        if(inputFields){
            inputFields.forEach(element=>{
                if(element.required && !element.value){
                    element.reportValidity();
                    isValid = false;
                }else{
                    obj[element.name] = element.value;
                    if(element.name != 'label' && element.name != 'name'){
                        mFields.push(element.name);
                    }
                }
            });
        }
        
        if(!isValid){
            this.showToast('error', 'Error', 'Please fill required fields and try again.');
        }else if(isValid){
            let hasResponseMapping = false;
            let responseMappingJSON = {};
            if(this.responseMappingOptions){
                for(let i=0;i<this.responseMappingOptions.length;i++){
                    if(this.responseMappingOptions[i].selectedMapping){
                        hasResponseMapping = true;
                        responseMappingJSON[this.responseMappingOptions[i].field] = this.responseMappingOptions[i].selectedMapping;
                    }
                }
            }
            if(hasResponseMapping){
               
                this.showSpinner = true;
                createResponseMapping({METADATA_FIELDS:mFields, params:obj, responseMappingParams:responseMappingJSON})
                .then((result) => {
                    if(result){
                        obj['Id'] = result;
                    }
                    this.selectedRecordId = obj.name;
                    this.selectedValue = obj.label;
                    const passEventr = new CustomEvent('select', {
                        detail: { record: obj, sectionName: this.name }
                    });
                    this.dispatchEvent(passEventr);
                    this.isNewRecord = false;
                    this.showSpinner = false;
                })
                .catch((error) => {
                    this.showSpinner = false;
                    console.log('error key : ' + JSON.stringify(error));
                    this.showToast('error', 'Error', error.body.message);
                });
            }else{
                this.showToast('error', 'Error', 'Please select atleast one Response Mapping to continue.');
            }
        }
    }
    handleSuccess(event) {
        this.isNewRecord = false;
        const evt = new ShowToastEvent({
            title: 'Success',
            message: 'Record created successfully!',
            variant: 'success',
        });
        this.dispatchEvent(evt);
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant: variant,
            message: message,
        });
        this.dispatchEvent(event);
    }
}