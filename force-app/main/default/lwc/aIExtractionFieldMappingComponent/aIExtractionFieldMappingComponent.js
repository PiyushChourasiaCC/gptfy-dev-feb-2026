import { api, track, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFieldMappings from '@salesforce/apex/AIExtractionFieldMappingController.getFieldMappings';
import saveFieldMappings from '@salesforce/apex/AIExtractionFieldMappingController.saveFieldMappings';
import getParentFields from '@salesforce/apex/AIExtractionFieldMappingController.getParentFields';
import validateFormula from '@salesforce/apex/AIExtractionFieldMappingController.validateFormula';
import Context_Mapping_Field_Disable from '@salesforce/label/c.Context_Mapping_Field_Disable';

export default class AIExtractionFieldMappingComponent extends LightningElement {

    @api recordId;
    @api objectName;
    @track parentfields;
    @track fields;
    @track showSpinner = false;
    @track anonymizeWithOptions;

    formulaReturnTypeOptions = [
        {"label" : "BOOLEAN", "value" : "BOOLEAN"},
        {"label" : "DATE", "value" : "DATE"},
        {"label" : "DATETIME", "value" : "DATETIME"},
        {"label" : "DECIMAL", "value" : "DECIMAL"},
        {"label" : "DOUBLE", "value" : "DOUBLE"},
        {"label" : "ID", "value" : "ID"},
        {"label" : "INTEGER", "value" : "INTEGER"},
        {"label" : "LONG", "value" : "LONG"},
        {"label" : "STRING", "value" : "STRING"},
        {"label" : "TIME", "value" : "TIME"}
    ];

    connectedCallback(){
        
        if(this.recordId && this.objectName){
            this.getMappings();
        }
    }

    handleCancel(){
        if(this.recordId && this.objectName){
            this.getMappings();
            const selectedEvent = new CustomEvent("close");
            this.dispatchEvent(selectedEvent);
        }
    }

    async getMappings(){
        this.showSpinner = true;
        this.fields = undefined;
        this.parentfields = undefined;
        await getFieldMappings({
            recordId : this.recordId,
            objectName : this.objectName
        })
        .then(result => {       
            if(result && result.fields && result.fields.length > 0){;
                this.fields =  JSON.parse(JSON.stringify(result.fields));
                let jsonData = JSON.parse(Context_Mapping_Field_Disable)
                let mapDisableField = new Map(Object.entries(jsonData))
                let disableFieldList = []
                if(mapDisableField && mapDisableField.size > 0 && mapDisableField.get(this.objectName)){
                        disableFieldList = mapDisableField.get(this.objectName)
                }
                for(let i = 0; i < this.fields.length; i++){
                     if(disableFieldList.includes(this.fields[i]['fieldName'])){
                          this.fields[i].disableFieldCss = 'pointer-events: none;cursor: default;opacity: 0.6;' 
                     }
                    if(!this.fields[i].hasOwnProperty('selectedMaskingOption') || this.fields[i].selectedMaskingOption == "" || this.fields[i].selectedMaskingOption == undefined){
                        this.fields[i]['isBlank'] = true;
                        this.fields[i]['hasSpecificValue'] = false;
                        this.fields[i]['hasEntireValue'] = false;
                    }else if(this.fields[i].selectedMaskingOption == 'Specific Patterns'){
                        this.fields[i]['hasSpecificValue'] = true;
                        this.fields[i]['isBlank'] = false;
                        this.fields[i]['hasEntireValue'] = false;
                    }else if(this.fields[i].selectedMaskingOption == 'Entire Value'){
                        this.fields[i]['hasEntireValue'] = true;
                        this.fields[i]['hasSpecificValue'] = false;
                        this.fields[i]['isBlank'] = false;
                    }
                } 
                this.parentfields = this.fields;
                this.anonymizeWithOptions = JSON.parse(JSON.stringify(result.anonymizeWithOptions))
            }else{
                var message = 'No fields found on the object.';
                this.showToast('error', 'Error!', message);
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleLabelChange(event){
        var value = event.target.value;
        var fieldName = event.target.name;
        if(this.fields && this.fields.length > 0){
            for(var field of this.fields){
                if(field.fieldName == fieldName){
                    field.label = value;
                    break;
                }
            }
        }
    }

    handleSendToAiChange(event){
        var value = event.target.checked;
        var index = event.target.dataset.findex;
        this.fields[index]['sendToAI'] = value;
        this.fields[index]['selectedMaskingOption'] = '';
        this.fields[index]['anonymizeWith'] = '';
        this.fields[index]['isBlank'] = true;
        this.fields[index]['hasSpecificValue'] = false;
        this.fields[index]['hasEntireValue'] = false;
    }

    handleMaskOption(event){
        var index = event.target.dataset.findex;
        var val = event.target.value;
        this.fields[index]['selectedMaskingOption'] = val;
        if(val == ""){
            this.fields[index]['isBlank'] = true;
            this.fields[index]['hasSpecificValue'] = false;
            this.fields[index]['hasEntireValue'] = false;
        }else if(val == 'Specific Patterns'){
            this.fields[index]['hasSpecificValue'] = true;
            this.fields[index]['isBlank'] = false;
            this.fields[index]['hasEntireValue'] = false;
        }else if(val == 'Entire Value'){
            this.fields[index]['hasEntireValue'] = true;
            this.fields[index]['hasSpecificValue'] = false;
            this.fields[index]['isBlank'] = false;
        }
    }

    handleAnonymizeWithChange(event){
        var value = event.target.value;
        var index = event.target.dataset.findex;
        this.fields[index]['anonymizeWith'] = value;
    }

    handleQuickSave(){
        this.doSave(true);
    }

    handleSave(){
        this.doSave(false);
    }

    doSave(isQuickSave){
        var exsits = false;
        //@JIRA V2-7485 : Save Failure: Unable to Save Data Context Mapping when Unchecking Searched Fields
        var fieldsToModify = [];
        var addedFields = [];
        for(var field of this.parentfields){
            if(!addedFields.includes(field['fieldName'])){
                fieldsToModify.push(field);
                addedFields.push(field['fieldName']);
                if(field['hasEntireValue'] || field['sendToAI']){
                    exsits = true;
                }
            }
        }
        for(var field of this.fields){
            if(!addedFields.includes(field['fieldName'])){
                fieldsToModify.push(field);
                addedFields.push(field['fieldName']);
                if(field['hasEntireValue'] || field['sendToAI']){
                    exsits = true;
                }
            }
        }
        //@JIRA V2-7485 : Save Failure: Unable to Save Data Context Mapping when Unchecking Searched Fields

        if(exsits){
            var isError = false;
            var message = '';
            for(var field of fieldsToModify){//@JIRA V2-7485 : Save Failure: Unable to Save Data Context Mapping when Unchecking Searched Fields
                if(field['hasEntireValue'] && (!field['anonymizeWith'] || field['anonymizeWith'] == null || field['anonymizeWith'] == '')){
                    isError = true;
                    message = 'Please make sure to select "Masking Value" when "Masking Scope" is selected.';
                    break;
                }else if(!field.label || field.label == null || field.label == ''){
                    isError = true;
                    message = 'Please make sure to "Label" is filled.';
                    break;
                }
            }
            if(isError){ 
                this.showToast('error', 'Error!', message);
            }else{
                this.saveMappings(fieldsToModify, isQuickSave);
            }
        }else{
            var message = 'Please make sure to select atleast one field.';
            this.showToast('error', 'Error!', message);
        }
    }

    //@JIRA V2-7485 : Save Failure: Unable to Save Data Context Mapping when Unchecking Searched Fields
    async saveMappings(fieldsToModify, isQuickSave){
        //this.fields = this.parentfields;
        this.showSpinner = true;
        await saveFieldMappings({
            recordId : this.recordId,
            objectName : this.objectName,
            fields : fieldsToModify
        })
        .then(result => {            
            this.showToast('success', 'Success', 'Field mappings updated successfully.');
            if(!isQuickSave){ 
                this.handleRefresh();
                const selectedEvent = new CustomEvent("close");
                this.dispatchEvent(selectedEvent);
            }
            this.getMappings();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    @track showFormulaFieldModal = false;
    toggleAddFormulaField(){
        this.formulaFieldData = {};
        if(!this.showFormulaFieldModal){
            this.showFormulaFieldModal = true;
        }else{
            this.showFormulaFieldModal = false;
        }
    }

    handleFormulaEditClick(event){
        var index = event.target.dataset.findex;
        var field = this.fields[index];
        this.formulaFieldData = {
            "label" : field.label,
            "apiName" : field.fieldName,
            "returnType" : field.fieldType,
            "formula" : field.formula,
            "ogIndex" : parseInt(index),
        };
        this.showFormulaFieldModal = true;
    }

    handleFormulaLabelChange(event){
        var fLabel = event.target.value;
        this.formulaFieldData['label'] = fLabel;
        if(this.formulaFieldData.ogIndex == null || this.formulaFieldData.ogIndex == '' || this.formulaFieldData.ogIndex == undefined || this.formulaFieldData.ogIndex < 0){
            if(fLabel && fLabel != null && fLabel != ''){
                this.formulaFieldData['apiName'] = fLabel.replace(/[^a-zA-Z0-9]/g, '')+'__c';
            }else{
                this.formulaFieldData['apiName'] = '';
            }
        }
    }

    handleFormulaValueChange(event){
        this.formulaFieldData['formula'] = event.target.value;
    }

    handleFormulaReturnTypeChange(event){
        this.formulaFieldData['returnType'] = event.target.value;
    }

    @track formulaFieldData = {};
    async handleFormulaFieldConfirm(){
        if(!this.formulaFieldData['label'] || this.formulaFieldData['label'] == null || this.formulaFieldData['label'] == '' ||
            !this.formulaFieldData['formula'] || this.formulaFieldData['formula'] == null || this.formulaFieldData['formula'] == '' ||
            !this.formulaFieldData['returnType'] || this.formulaFieldData['returnType'] == null || this.formulaFieldData['returnType'] == ''){
            this.showToast('error', 'Error', 'Required fields missing.');
        }else{
            this.displaySpinner = true;

            if(this.formulaFieldData.ogIndex == null || this.formulaFieldData.ogIndex == '' || this.formulaFieldData.ogIndex == undefined || this.formulaFieldData.ogIndex < 0){
                let fieldAPIName = this.formulaFieldData['apiName'].toLowerCase();
                await this.fields.map((obj) => {
                        let fname = obj.fieldName.toLowerCase();
                        if(fname === fieldAPIName){
                            this.showToast('error', 'Error', 'Duplicate field name. Enter a unique field name.');
                            this.displaySpinner = false;
                            return;
                        }
                });
            }
             

            if(this.displaySpinner){
                validateFormula({
                    objName : this.objectName,
                    returnType : this.formulaFieldData['returnType'],
                    formulaStr : this.formulaFieldData['formula']
                })
                .then(result => { 
                        if(this.formulaFieldData['ogIndex'] >= -1){
                            this.fields[this.formulaFieldData['ogIndex']]['fieldName'] = this.formulaFieldData['apiName'];
                            this.fields[this.formulaFieldData['ogIndex']]['label'] = this.formulaFieldData['label'];
                            this.fields[this.formulaFieldData['ogIndex']]['displayLabel'] = this.formulaFieldData['label']+" ("+this.formulaFieldData['apiName']+")";
                            this.fields[this.formulaFieldData['ogIndex']]['formula'] = this.formulaFieldData['formula'];
                            this.fields[this.formulaFieldData['ogIndex']]['fieldType'] = this.formulaFieldData['returnType'];
                        }else{
                            var obj = {
                                "fieldName" : this.formulaFieldData['apiName'],
                                "label" : this.formulaFieldData['label'],
                                "displayLabel" : this.formulaFieldData['label']+" ("+this.formulaFieldData['apiName']+")",
                                "sendToAI" : true,
                                "anonymizeWith" : "",
                                "selectedMaskingOption" : "",
                                "formula" : this.formulaFieldData['formula'],
                                "maskSopeOptions" : JSON.parse(JSON.stringify(result)),
                                "fieldType" : this.formulaFieldData['returnType']
                            };
                            if(!obj.hasOwnProperty('selectedMaskingOption') || obj.selectedMaskingOption == "" || obj.selectedMaskingOption == undefined){
                                obj['isBlank'] = true;
                                obj['hasSpecificValue'] = false;
                                obj['hasEntireValue'] = false;
                            }else if(obj.selectedMaskingOption == 'Entire Value'){
                                obj['hasEntireValue'] = true;
                                obj['hasSpecificValue'] = false;
                                obj['isBlank'] = false;
                            }
                            
                            var index = 0;
                            for(var field of this.fields){
                                if(field.fieldValue && field.fieldValue != null && field.fieldValue != ''){
                                    index++;
                                }else{
                                    break;
                                }
                            }
                            
                            var fields = [];
                            var fIndex = 0;
                
                            if(index == 0){
                                fields.push(obj);
                            }
                            for(var field of this.fields){
                                fields.push(field);
                                if(fIndex == (index-1)){
                                    fields.push(obj);
                                }
                                fIndex++;
                            }
                            this.fields = JSON.parse(JSON.stringify(fields));
                        }
                        this.toggleAddFormulaField();
                    
                    this.displaySpinner = false;
                    
                })
                .catch(error => {
                    console.error('Formula validation error:', JSON.stringify(error));
                    // let errorMessage = 'Invalid formula, please check and try again.';
                    this.handleError(error);
                    this.displaySpinner = false;
                });
            }

        }
    }

    @track showRelatedFieldsModal = false;
    @track displaySpinner = false;
    toggleAddRelatedFields(){
        if(!this.showRelatedFieldsModal){
            this.showRelatedFieldsModal = true;
            this.getParentDetailFields(this.objectName, true, 0);
        }else{
            this.showRelatedFieldsModal = false;
            this.relatedFieldsData = [];
            //this.getMappings();
        }
    }

    handleRelatedFieldChange(event){
        var index = event.target.dataset.index;
        this.relatedFieldsData[index]['selectedValue'] = undefined;

        for(var opt of this.relatedFieldsData[index]['options']){
            if(opt.value == event.target.value){
                this.relatedFieldsData[index]['selectedValue'] = opt;
                break;
            }
        }

        var records = [];
        for(var rec of this.relatedFieldsData){
            if(rec.index <= index){
                records.push(rec);
            }
        }
        this.relatedFieldsData = JSON.parse(JSON.stringify(records));
        if(this.relatedFieldsData[index]['selectedValue']){
            var objName = this.relatedFieldsData[index]['selectedValue'].parentName;
            if(objName && objName.length > 0){
                this.getParentDetailFields(objName, false, (parseInt(index)+1));
            }
        }
    }

    @track relatedFieldsData = [];
    async getParentDetailFields(currentObjName, onlyLookupFields, index){
        this.displaySpinner = true;
        await getParentFields({
            objName : currentObjName,
            onlyLookupFields : onlyLookupFields
        })
        .then(result => {  
            var options = [];
            if(index > 4){
                for(var opt of result){
                    if(!opt.parentName || opt.parentName == null || opt.parentName == ''){
                        options.push(opt);
                    }
                }
            }else{
                options = JSON.parse(JSON.stringify(result));
            }
            var obj = {
                "index" : index,
                "options" : options,
                "selectedValue" : undefined
            };
            if(!this.relatedFieldsData){
                this.relatedFieldsData = [];
            }
            this.relatedFieldsData.push(obj);
            this.displaySpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleRelatedFieldConfirm(){
        var isError = false;
        var relationships = [];
        var relationshipLabel;
        var selectedOpt;
        if(this.relatedFieldsData && this.relatedFieldsData.length > 0){
            var index = 0;
            for(var opt of this.relatedFieldsData){
                if(!opt.selectedValue || opt.selectedValue == null){
                    isError = true;
                    break;
                }
                
                if(index == (this.relatedFieldsData.length - 1)){
                    relationships.push(opt.selectedValue.value);
                    relationshipLabel = opt.selectedValue.label;
                    selectedOpt = opt.selectedValue;
                }else{
                    relationships.push(opt.selectedValue.relationshipName);
                }
                index++;
            }   
        }else{
            isError = true;
        }
        if(isError || !relationships || relationships.length == 0){
            this.showToast('error', 'Error', 'Required fields missing.');
        }else{
            var relationshipField = relationships.join('.');
            var obj = {
                "fieldName" : relationshipField,
                "label" : relationshipLabel,
                "displayLabel" : relationshipLabel+" ("+relationshipField+")",
                "sendToAI" : true,
                "anonymizeWith" : "",
                "selectedMaskingOption" : selectedOpt.selectedMaskingOption ? selectedOpt.selectedMaskingOption : "",
                "maskSopeOptions" : selectedOpt.maskSopeOptions,
                "fieldType" : selectedOpt.fieldType
                
            };
            if(!obj.hasOwnProperty('selectedMaskingOption') || obj.selectedMaskingOption == "" || obj.selectedMaskingOption == undefined){
                obj['isBlank'] = true;
                obj['hasSpecificValue'] = false;
                obj['hasEntireValue'] = false;
            }else if(obj.selectedMaskingOption == 'Specific Patterns'){
                obj['hasSpecificValue'] = true;
                obj['isBlank'] = false;
                obj['hasEntireValue'] = false;
            }else if(obj.selectedMaskingOption == 'Entire Value'){
                obj['hasEntireValue'] = true;
                obj['hasSpecificValue'] = false;
                obj['isBlank'] = false;
            }
            
            var index = 0;
            for(var field of this.fields){
                if(field.fieldValue && field.fieldValue != null && field.fieldValue != ''){
                    index++;
                }else{
                    break;
                }
            }
            
            var fields = [];
            var fIndex = 0;

            if(index == 0){
                fields.push(obj);
            }
            for(var field of this.fields){
                fields.push(field);
                if(fIndex == (index-1)){
                    fields.push(obj);
                }
                fIndex++;
            }
            this.fields = JSON.parse(JSON.stringify(fields));
            this.toggleAddRelatedFields();
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

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }

    handleRefresh(){
        const selectedEvent = new CustomEvent("refresh");
        this.dispatchEvent(selectedEvent);
    }

    handleInputChange(event){
        let fieldVal = event.target.value;
        if(this.parentfields){
            if(fieldVal && fieldVal.length > 2){
                var filterResult = this.parentfields.filter((element) => element.displayLabel.toLowerCase().indexOf(fieldVal.toLowerCase()) != -1);
                this.fields = filterResult;
            }else{
                this.fields = this.parentfields;
            }
        }
    }

}