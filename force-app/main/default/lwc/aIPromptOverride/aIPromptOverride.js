import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getPromptData from '@salesforce/apex/AIPromptController.getPromptData';
import getObjectBasedOptions from '@salesforce/apex/AIPromptController.getObjectBasedOptions';
//import getCustomSettings from '@salesforce/apex/AIUtility.getCustomSettings';
import saveAIPrompt from '@salesforce/apex/AIPromptController.saveAIPrompt';
//import isValidVisibilityCondition from '@salesforce/apex/AIPromptValidationController.isValidVisibilityCondition';


//import AiPromptWhereClauseFormulaComponent from 'c/aiPromptWhereClauseFormulaComponent';

//import LOCALE_AUTOMATION_FIELD from '@salesforce/schema/AI_Prompt__c.AI_Locale_Automation__c';
//import LOCALE_GPTFY_CONSOLE_FIELD from '@salesforce/schema/AI_Prompt__c.AI_Locale_GPTfy_Console__c';
//import GROUNDING_CONTENT_FIELD from '@salesforce/schema/AI_Prompt__c.Grounding_Content__c';
//import GROUNDING_ETHICAL_FIELD from '@salesforce/schema/AI_Prompt__c.Grounding_Ethical__c';
//import HOW_IT_WORKS_FIELD from '@salesforce/schema/AI_Prompt__c.How_it_works__c';
//import CUSTOM_PROMPT_FIELD from '@salesforce/schema/AI_Prompt__c.Custom_Prompt__c';
//import VISIBILITY_CONDITION_FIELD from '@salesforce/schema/AI_Prompt__c.Visibility_Condition__c';
//import TARGET_FIELD_FIELD from '@salesforce/schema/AI_Prompt__c.Target_Field__c';
//import TOP_P_FIELD from '@salesforce/schema/AI_Prompt__c.Top_P__c';
//import TEMPERATURE_FIELD from '@salesforce/schema/AI_Prompt__c.Temperature__c';
//import MAX_OUTPUT_TOKENS_FIELD from '@salesforce/schema/AI_Prompt__c.Max_Output_Tokens__c';
//import INCLUDE_FILES_FIELD from '@salesforce/schema/AI_Prompt__c.Include_Files__c';
//import RECORD_TYPE_FIELD from '@salesforce/schema/AI_Prompt__c.Record_Type__c';
//import PROFILES_FIELD from '@salesforce/schema/AI_Prompt__c.Profiles__c';
//import Purpose_FIELD from '@salesforce/schema/AI_Prompt__c.Purpose__c';
//import Description_FIELD from '@salesforce/schema/AI_Prompt__c.Description__c';
import TYPE_FIELD from '@salesforce/schema/AI_Prompt__c.Type__c';
import AI_Data_Extraction_Mapping_FIELD from '@salesforce/schema/AI_Prompt__c.AI_Data_Extraction_Mapping__c';
import AI_Connection_FIELD from '@salesforce/schema/AI_Prompt__c.AI_Connection__c';
import Object_FIELD from '@salesforce/schema/AI_Prompt__c.Object__c';
//import EXP_SITE_FIELD from '@salesforce/schema/AI_Prompt__c.Object__c';
//import USAGE_FIELD from '@salesforce/schema/AI_Prompt__c.Object__c';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import PMT_OBJECT from '@salesforce/schema/AI_Prompt__c';

export default class AIPromptOverride extends NavigationMixin(LightningElement) {

    @api recordId;
    @api objectApiName;
    @api isPromptCatalog = false;
    @api selectedCatalogPurpose;

    @track showSpinner = false;

    @track modalHeader = 'New Prompt';

    @track promptName;
    @track targetObject;
    //@track description;
    //@track profileIds;
    //@track recordTypeIds;
    //@track selectedPurpose;
    @track extractionMappingId;
    @track extractionMappingName;
    //@track customPrompt;
    @track aiConnection;
    @track selectedType;
    //@track promptCommand;
    //@track includeFiles;
    //@track maxOutputTokens;
    //@track temprature;
    //@track topP;
    //@track targetField;
    //@track appendTimestamp;
    //@track visibilityCondition;
    //@track howItWorks;
    //@track groundingEthical;
    //@track groundingContent;
    //@track localeAutomation;
    //@track localeGptfyConsole;
    //@track selectedUsage;
    //@track selectedSites;

    @track objects;
    //@track profileOptions;
    //@track recordTypeOptions;
    @track extractOptions;
    @track connectOptions;
    @track typeOptions;
    //@track targetFieldOptions;
    //@track groundingEthicalOptions;
    //@track groundingContentOptions;
    //@track localeAutomationContentOptions;
    //@track localeGptfyConsoleContentOptions;
    //@track usageOptions;
    //@track siteOptions;

    //@track mergeFieldObjectOptions;
    //@track mergeFieldOptions;
    //@track selectedMergeFieldObjectOption;
    //@track selectedMergeFieldOption;

    @track helpText_PromptName;
    @track helpText_TargetObject;
    @track helpText_Connection;
    @track helpText_Mapping;
    @track helpText_type;
    /*
    @track helpText_description;
    @track helpText_Purpose;
    @track helpText_Profile;
    @track helpText_RecordType;
    @track helpText_IncludeFiles;
    @track helpText_MaxOutputTokens;
    @track helpText_Temprature;
    @track helpText_TopP;
    @track helpText_TargetField;
    @track helpText_VisibilityCondition;
    @track helpText_AllowUserInput;
    @track helpText_HowItWorks;
    @track helpText_GroundingContent;
    @track helpText_GroundingEthical;
    @track helpText_LocaleAutomation;
    @track helpText_LocaleGPTfyConsole;
    @track helpText_ExpSite;
    @track helpText_Usage;

    @track showIncludeFiles = true;
    @track showAppendTimestampField = false;
    */

    @wire(getObjectInfo, { objectApiName: PMT_OBJECT })
    wiredRecord({ error, data }) {
        if (error) {
            this.handleError(error);
        } else if (data) {
            if (data.fields) {
                if (data.fields['Name'] && data.fields['Name'].inlineHelpText) {
                    this.helpText_PromptName = data.fields['Name'].inlineHelpText;
                } if (data.fields[Object_FIELD.fieldApiName] && data.fields[Object_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_TargetObject = data.fields[Object_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[AI_Connection_FIELD.fieldApiName] && data.fields[AI_Connection_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Connection = data.fields[AI_Connection_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[AI_Data_Extraction_Mapping_FIELD.fieldApiName] && data.fields[AI_Data_Extraction_Mapping_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Mapping = data.fields[AI_Data_Extraction_Mapping_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[TYPE_FIELD.fieldApiName] && data.fields[TYPE_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_type = data.fields[TYPE_FIELD.fieldApiName].inlineHelpText;
                } 
                /*
                if (data.fields[Description_FIELD.fieldApiName] && data.fields[Description_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_description = data.fields[Description_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[Purpose_FIELD.fieldApiName] && data.fields[Purpose_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Purpose = data.fields[Purpose_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[PROFILES_FIELD.fieldApiName] && data.fields[PROFILES_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Profile = data.fields[PROFILES_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[RECORD_TYPE_FIELD.fieldApiName] && data.fields[RECORD_TYPE_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_RecordType = data.fields[RECORD_TYPE_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[INCLUDE_FILES_FIELD.fieldApiName] && data.fields[INCLUDE_FILES_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_IncludeFiles = data.fields[INCLUDE_FILES_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[MAX_OUTPUT_TOKENS_FIELD.fieldApiName] && data.fields[MAX_OUTPUT_TOKENS_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_MaxOutputTokens = data.fields[MAX_OUTPUT_TOKENS_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[TEMPERATURE_FIELD.fieldApiName] && data.fields[TEMPERATURE_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Temprature = data.fields[TEMPERATURE_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[TOP_P_FIELD.fieldApiName] && data.fields[TOP_P_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_TopP = data.fields[TOP_P_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[TARGET_FIELD_FIELD.fieldApiName] && data.fields[TARGET_FIELD_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_TargetField = data.fields[TARGET_FIELD_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[VISIBILITY_CONDITION_FIELD.fieldApiName] && data.fields[VISIBILITY_CONDITION_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_VisibilityCondition = data.fields[VISIBILITY_CONDITION_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[CUSTOM_PROMPT_FIELD.fieldApiName] && data.fields[CUSTOM_PROMPT_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_AllowUserInput = data.fields[CUSTOM_PROMPT_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[HOW_IT_WORKS_FIELD.fieldApiName] && data.fields[HOW_IT_WORKS_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_HowItWorks = data.fields[HOW_IT_WORKS_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[GROUNDING_CONTENT_FIELD.fieldApiName] && data.fields[GROUNDING_CONTENT_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_GroundingContent = data.fields[GROUNDING_CONTENT_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[GROUNDING_ETHICAL_FIELD.fieldApiName] && data.fields[GROUNDING_ETHICAL_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_GroundingEthical = data.fields[GROUNDING_ETHICAL_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[LOCALE_AUTOMATION_FIELD.fieldApiName] && data.fields[LOCALE_AUTOMATION_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_LocaleAutomation = data.fields[LOCALE_AUTOMATION_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[LOCALE_GPTFY_CONSOLE_FIELD.fieldApiName] && data.fields[LOCALE_GPTFY_CONSOLE_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_LocaleGPTfyConsole = data.fields[LOCALE_GPTFY_CONSOLE_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[EXP_SITE_FIELD.fieldApiName] && data.fields[EXP_SITE_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_ExpSite = data.fields[EXP_SITE_FIELD.fieldApiName].inlineHelpText;
                } if (data.fields[USAGE_FIELD.fieldApiName] && data.fields[USAGE_FIELD.fieldApiName].inlineHelpText) {
                    this.helpText_Usage = data.fields[USAGE_FIELD.fieldApiName].inlineHelpText;
                }
                */
            }
        }
    }


    connectedCallback() {
        this.getDefaultData();
    }

    async getDefaultData() {

        /*
        this.showIncludeFiles = false;
        getCustomSettings()
        .then(result => {          
            if(result && result['fileProcessing']){
                this.showIncludeFiles = result['fileProcessing'];
            }
        })
        .catch(error => {
            this.handleError(error);
        });
        */

        this.showSpinner = true;
        this.objects = undefined;
        //this.profileOptions = undefined;
        //this.recordTypeOptions = undefined;
        this.extractOptions = undefined;
        this.connectOptions = undefined;
        //this.customPrompt = false;
        this.typeOptions = undefined;
        //this.mergeFieldObjectOptions = undefined;
        //this.mergeFieldOptions = undefined;
        //this.targetFieldOptions = undefined;
        //this.groundingEthicalOptions = undefined;
        //this.groundingContentOptions = undefined;
        //this.localeAutomationContentOptions = undefined;
        //this.localeGptfyConsoleContentOptions = undefined;
       // this.siteOptions = undefined;
        //this.usageOptions = undefined;

        //this.description = undefined;
        this.promptName = undefined;
        this.targetObject = undefined;
        this.extractionMappingId = undefined;
        this.extractionMappingName = undefined;
        //this.profileIds = undefined;
        //this.recordTypeIds = undefined;
        //this.selectedPurpose = undefined;
        this.aiConnection = undefined;
        this.selectedType = undefined;
        //this.appendTimestamp = false;
        //this.includeFiles = false;
        //this.targetField = undefined;
        //this.visibilityCondition = undefined;
        //this.howItWorks = undefined;
        //this.allowUserInput = false;
        //this.groundingContent = undefined;
        //this.groundingEthical = undefined;
        //this.localeAutomation = undefined;
        //this.localeGptfyConsole = undefined;
        //this.selectedSites = undefined;
        //this.selectedUsage = undefined;


        await getPromptData({
            "recordId": this.recordId
        })
        .then(result => {
            if (result && result.objects && result.objects.length > 0) {
                this.objects = JSON.parse(JSON.stringify(result.objects));
                if (result.promptName && result.promptName != '' && result.promptName != null) {
                    //this.description = result.description;
                    this.promptName = result.promptName;
                    this.modalHeader = 'Edit ' + result.promptName;
                    this.targetObject = result.objectName;
                    this.extractionMappingId = result.extractionMappingId;
                    this.extractionMappingName = result.extractionMappingName;
                    //this.profileIds = result.profileIds;
                    //this.selectedSites = result.selectedSites;
                    //this.selectedUsage = result.selectedUsage;
                    //this.groundingContent = result.groundingContent;
                    //this.groundingEthical = result.groundingEthical;
                    //this.localeAutomation = result.localeAutomation;
                    //this.localeGptfyConsole = result.localeGptfyConsole;
                    //this.recordTypeIds = result.recordTypeIds;
                    //this.customPrompt = result.customPrompt;
                    //this.selectedPurpose = result.selectedPurpose;
                    this.aiConnection = result.aiConnection;
                    this.selectedType = result.selectedType;
                    //this.allowUserInput = result.allowUserInput;
                    //this.includeFiles = result.includeFiles;
                    //this.maxOutputTokens = result.maxOutputTokens;
                    //this.temprature = result.temprature;
                    //this.topP = result.topP;
                    //this.targetField = result.targetField;
                    //this.visibilityCondition = result.visibilityCondition
                    //this.howItWorks = result.howItWorks;
                    //this.appendTimestamp = result.appendTimestamp;
                }
                if (result.extractOptions && result.extractOptions.length > 0) {
                    this.extractOptions = JSON.parse(JSON.stringify(result.extractOptions));
                }
                if (result.connectOptions && result.connectOptions.length > 0) {
                    this.connectOptions = JSON.parse(JSON.stringify(result.connectOptions));
                    if (!this.aiConnection || !this.recordId) {
                        this.aiConnection = this.connectOptions[0].value;
                    }
                } if (result.typeOptions && result.typeOptions.length > 0) {
                    this.typeOptions = JSON.parse(JSON.stringify(result.typeOptions));
                    if (!this.selectedType || !this.recordId) {
                        this.selectedType = this.typeOptions[0].value;
                    }
                }

                //if (result.profileOptions && result.profileOptions.length > 0) {
                    //this.profileOptions = JSON.parse(JSON.stringify(result.profileOptions));
                //} if (result.recordTypeOptions && result.recordTypeOptions.length > 0) {
                    //this.recordTypeOptions = JSON.parse(JSON.stringify(result.recordTypeOptions));
                //} if (result.siteOptions && result.siteOptions.length > 0) {
                    //this.siteOptions = JSON.parse(JSON.stringify(result.siteOptions));
                //} if (result.usageOptions && result.usageOptions.length > 0) {
                   // this.usageOptions = JSON.parse(JSON.stringify(result.usageOptions));
                //} 
                 //if (result.purposeOptions && result.purposeOptions.length > 0) {
                    //this.purposeOptions = JSON.parse(JSON.stringify(result.purposeOptions));
                //} 
                //if (result.groundingContentOptions && result.groundingContentOptions.length > 0) {
                    //this.groundingContentOptions = JSON.parse(JSON.stringify(result.groundingContentOptions));
                //}if (result.groundingEthicalOptions && result.groundingEthicalOptions.length > 0) {
                    //this.groundingEthicalOptions = JSON.parse(JSON.stringify(result.groundingEthicalOptions));
                //}
                //if (result.localeAutomationContentOptions && result.localeAutomationContentOptions.length > 0) {
                    //this.localeAutomationContentOptions = JSON.parse(JSON.stringify(result.localeAutomationContentOptions));
                    //this.localeAutomationContentOptions = [{label: '---None---', value: ''}, ...this.localeAutomationContentOptions]
                //}
                //if (result.localeGptfyConsoleContentOptions && result.localeGptfyConsoleContentOptions.length > 0) {
                    //this.localeGptfyConsoleContentOptions = JSON.parse(JSON.stringify(result.localeGptfyConsoleContentOptions));
                    //this.localeGptfyConsoleContentOptions = [{label: '---None---', value: ''}, ...this.localeGptfyConsoleContentOptions]
                //} 
                //if (result.mergeFieldObjectOptions && result.mergeFieldObjectOptions.length > 0) {
                    //this.mergeFieldObjectOptions = JSON.parse(JSON.stringify(result.mergeFieldObjectOptions));
                //} 
                //if (result.targetFieldOptions && result.targetFieldOptions.length > 0) {
                    //this.targetFieldOptions = JSON.parse(JSON.stringify(result.targetFieldOptions));

                    //const res = this.targetFieldOptions.find(item => item.value === this.targetField);
                    //if (res && (res.fieldType == 'STRING' || res.fieldType == 'TEXTAREA')) {
                        //this.showAppendTimestampField = true;
                    //} //else {
                        //this.showAppendTimestampField = false;
                    //}
                //}
            } else {
                this.showToast('warning', 'Alert!', 'No objects found.');
            }
            if(this.isPromptCatalog && this.selectedCatalogPurpose){
                this.selectedPurpose = [this.selectedCatalogPurpose];
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    /*
    get showTextPrompt() {
        if (this.selectedType == 'Text') {
            return true;
        }
        return false;
    }
    */

    handleObjectChange(event) {
        this.targetObject = event.target.value;
        if (this.targetObject) {
            this.getObjectDependentOptions();
        }
    }


    async getObjectDependentOptions() {
        this.showSpinner = true;
        this.extractOptions = undefined;
        this.extractionMappingId = undefined;
        //this.recordTypeOptions = undefined;
        //this.recordTypeIds = undefined;
        //this.targetFieldOptions = undefined;
        //this.targetField = undefined;

        await getObjectBasedOptions({
            "objName": this.targetObject
        })
            .then(result => {
                //if (result.recordTypeOptions && result.recordTypeOptions.length > 0) {
                    //this.recordTypeOptions = JSON.parse(JSON.stringify(result.recordTypeOptions));
                //}

                //if (result.targetFieldOptions && result.targetFieldOptions.length > 0) {
                    //this.targetFieldOptions = JSON.parse(JSON.stringify(result.targetFieldOptions));
                //}

                this.extractOptions = [];
                var obj = { "label": "+ Create Mapping", "value": "ADD_MAPPING", "description": "This option creates a new mapping automatically." };
                this.extractOptions.push(obj);

                if (result.extractOptions && result.extractOptions.length > 0) {
                    for (var opt of result.extractOptions) {
                        this.extractOptions.push(opt);
                    }
                    //this.extractOptions = JSON.parse(JSON.stringify());
                    if (!this.recordId) {
                        this.extractionMappingId = this.extractOptions[0].value;
                        //this.getMergeObjectsData();
                    }
                }
                this.showSpinner = false;
            })
            .catch(error => {
                this.handleError(error);
            });
    }

    /*
    getMergeObjectsData() {
        this.showSpinner = true;
        this.mergeFieldOptions = undefined;
        this.mergeFieldObjectOptions = undefined;
        this.selectedMergeFieldObjectOption = undefined;
        this.selectedMergeFieldOption = undefined;

        getMergeObjects({
            "extId": this.extractionMappingId
        })
            .then(result => {
                if (result && result.length > 0) {
                    this.mergeFieldObjectOptions = JSON.parse(JSON.stringify(result));
                }
                this.showSpinner = false;
            })
            .catch(error => {
                this.handleError(error);
            });
    }

    getMergeFieldsData() {
        this.showSpinner = true;
        this.mergeFieldOptions = undefined;
        this.selectedMergeFieldOption = undefined;

        var objName;
        for (var opt of this.mergeFieldObjectOptions) {
            if (opt.value == this.selectedMergeFieldObjectOption) {
                objName = opt.label;
                break;
            }
        }

        getMergeFields({
            "detailId": this.selectedMergeFieldObjectOption,
            "extId": this.extractionMappingId,
            "objName": objName
        })
            .then(result => {
                if (result && result.length > 0) {
                    this.mergeFieldOptions = JSON.parse(JSON.stringify(result));
                }
                this.showSpinner = false;
            })
            .catch(error => {
                this.handleError(error);
            });
    }
    */

    /*
    handleRecordTypeChange(event) {
        this.recordTypeIds = event.target.value;
    }

    handleProfileChange(event) {
        this.profileIds = event.target.value;
    }

    handleSiteChange(event){
        this.selectedSites = event.target.value;
    }

    handleUsageChange(event){
        this.selectedUsage = event.target.value;
    }

    handleGroundingEthicalChange(event){
        this.groundingEthical = event.target.value;
    }

    handleGroundingContentChange(event){
        this.groundingContent = event.target.value;
    }

    handleLocaleAutomationChange(event){
        this.localeAutomation = event.target.value;
    }

    handleLocaleGptfyConsoleChange(event){
        this.localeGptfyConsole = event.target.value;
    }

    handlePurposeChange(event) {
        this.selectedPurpose = event.target.value;
    }
    */

    handleMappingChange(event) {
        this.extractionMappingId = event.target.value;
        //this.getMergeObjectsData();
    }

    handleNameChange(event) {
        this.promptName = event.target.value;
    }

    /*
    handleDescChange(event) {
        this.description = event.target.value;
    }

    handleCustomPromptChange(event) {
        this.customPrompt = event.target.checked;
    }
    */

    handleConnectionChange(event) {
        this.aiConnection = event.target.value;
    }

    handleTypeChange(event) {
        this.selectedType = event.target.value;
    }

    /*
    handleAllowUserInputChange(event) {
        this.allowUserInput = event.target.checked;
    }

    handleIncludeFilesChange(event) {
        this.includeFiles = event.target.checked;
    }

    handleAppendTimestamp(event){
        this.appendTimestamp = event.target.checked;
    }
    */
    /*
    handleMergeFieldObjectChange(event) {
        this.selectedMergeFieldObjectOption = event.target.value;
        this.getMergeFieldsData();
    }

    handleMergeFieldChange(event) {
        this.selectedMergeFieldOption = event.target.value;
    }
    */
    /*
    handleMaxOutputTokensChange(event) {
        this.maxOutputTokens = event.target.value;
    }

    handleTempratureChange(event) {
        this.temprature = event.target.value;
    }

    handleTopPChange(event) {
        this.topP = event.target.value;
    }

    handleTargetFieldChange(event) {
        this.targetField = event.target.value;
        const res = this.targetFieldOptions.find(item => item.value === this.targetField);
        if (res && (res.fieldType == 'STRING' || res.fieldType == 'TEXTAREA')) {
            this.showAppendTimestampField = true;
        } else {
            this.showAppendTimestampField = false;
        }
    }
    */
    /*
    handleCopy() {
        if (this.selectedMergeFieldOption) {
            var mergeField = '{{{' + this.selectedMergeFieldOption + '}}}';
            //navigator.clipboard.writeText(mergeField);
            const listener = function(ev) {
                ev.preventDefault();
                ev.clipboardData.setData('text/plain', mergeField);
            };
            document.addEventListener('copy', listener);
            document.execCommand('copy');
            document.removeEventListener('copy', listener);
        }
    }
    */

    /*
    handleVisibilityConditionChange = (e) => {
        this.visibilityCondition = e.target.value;
    }

    handleHowItWorksChange(event){
        this.howItWorks = event.target.value;
    }
    */

    handleSave = () => {
        if (!this.targetObject || this.targetObject == '' || this.targetObject == null) {
            this.showToast('warning', 'Alert!', 'Target Object is missing.');
        } else if (!this.aiConnection || this.aiConnection == '' || this.aiConnection == null) {
            this.showToast('warning', 'Alert!', 'AI Connection is missing.');
        } else if (!this.promptName || this.promptName == '' || this.promptName == null) {
            this.showToast('warning', 'Alert!', 'Prompt Name is missing.');
        } else if (!this.extractionMappingId || this.extractionMappingId == '' || this.extractionMappingId == null) {
            this.showToast('warning', 'Alert!', 'Data Context Mapping is missing.');
        } else if (!this.selectedType || this.selectedType == '' || this.selectedType == null) {
            this.showToast('warning', 'Alert!', 'Type is required.');
        //} else if ((!this.promptCommand || this.promptCommand == '' || this.promptCommand == null) && this.selectedType == 'Text') {
            //this.showToast('warning', 'Alert!', 'Prompt Command is required for Text type prompt.');
        } else{
            this.saveMapping();
        } /*else {
            if(this.visibilityCondition && this.visibilityCondition != '' && this.visibilityCondition != null){
                isValidVisibilityCondition({"objName": this.targetObject , "whereClause": this.visibilityCondition})
                    .then((res)=>{
                        if(res){
                            this.saveMapping();
                        }else{
                            this.showToast('warning', 'Alert!', 'Visibility Condition is not valid.');
                        }
                    }).catch(error=> {
                        this.showToast('warning', 'Alert!', 'Visibility Condition is not valid.');
                    })
            }else{
                this.saveMapping();
            }
        }*/
    }

    async saveMapping() {
        this.showSpinner = true;
        //var profileIds = '';
        //if (this.profileIds && this.profileIds.length > 0) {
            //profileIds = this.profileIds.join(";");
        //}
        //var recordTypeIds = '';
        //if (this.recordTypeIds && this.recordTypeIds.length > 0) {
            //recordTypeIds = this.recordTypeIds.join(";");
        //}
        //var selectedPurpose = '';
        //if (this.selectedPurpose && this.selectedPurpose.length > 0) {
            //selectedPurpose = this.selectedPurpose.join(";");
        //}

        //var groundingEthical = '';
        //if (this.groundingEthical && this.groundingEthical.length > 0) {
            //groundingEthical = this.groundingEthical.join(";");
        //}

        //var groundingContent = '';
        //if (this.groundingContent && this.groundingContent.length > 0) {
            //groundingContent = this.groundingContent.join(";");
        //}

        //var selectedUsage = '';
        //if (this.selectedUsage && this.selectedUsage.length > 0) {
            //selectedUsage = this.selectedUsage.join(";");
        //}

        //var selectedSites = '';
        //if (this.selectedSites && this.selectedSites.length > 0) {
            //selectedSites = this.selectedSites.join(";");
        //}

        var obj = {
            "recordId": this.recordId,
            //"description": this.description,
            "promptName": this.promptName,
            "extractionMappingId": this.extractionMappingId,
            //"profileIds": profileIds,
            //"recordTypeIds": recordTypeIds,
            //"groundingContent" : groundingContent,
            //"groundingEthical" : groundingEthical,
            //"localeAutomation" : this.localeAutomation,
            //"localeGptfyConsole" : this.localeGptfyConsole,
            "targetObject": this.targetObject,
            //"customPrompt": this.customPrompt,
            "selectedPurpose": this.selectedCatalogPurpose,
            "aiConnection": this.aiConnection,
            "selectedType": this.selectedType,
            //"allowUserInput": this.allowUserInput,
            //"includeFiles": this.includeFiles,
            //"maxOutputTokens": this.maxOutputTokens,
            //"temprature": this.temprature,
            //"topP": this.topP,
            //"targetField": this.targetField,
            //"appendTimestamp" : this.appendTimestamp,
            //"visibilityCondition": this.visibilityCondition,
            //"howItWorks" : this.howItWorks,
            //"selectedSites" : selectedSites,
            //"selectedUsage" : selectedUsage
        };
        await saveAIPrompt({
            "data": obj
        }).then(result => {
                if (result && result != null && result != '') {
                    const wasNewRecord = !this.recordId;
                    this.recordId = result;
                    this.showToast('success', 'Success', 'Record saved successfully.');
                    
                    // Navigate based on whether it was a new record or edit
                    if(this.isPromptCatalog){
                        const selectedEvent = new CustomEvent("close", {});
                        this.dispatchEvent(selectedEvent);
                    } else if (wasNewRecord) {
                        // For new records, navigate directly to the record page
                        this.naviagteToRecordPage();
                    } else {
                        // For existing records, call handleCancel which will navigate
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
        if(this.isPromptCatalog){
            const selectedEvent = new CustomEvent("close", {});
            this.dispatchEvent(selectedEvent);
        }else if (this.recordId) {
            this.naviagteToRecordPage();
        } else {
            this.navigateToListView();
        }
    }

    naviagteToRecordPage() {
        if (this.recordId) {
            // Navigate to the record page
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.recordId,
                    objectApiName: this.objectApiName,
                    actionName: 'view'
                }
            });
        } else {
            // If no recordId, dispatch cancel event to parent
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

    /*
    handleOpenVisibilityCondition = async (e) => {
        const result = await AiPromptWhereClauseFormulaComponent.open({
            size: 'medium',
            description: 'Visibility Condition',
            objectApiName: this.targetObject,
        });
        if (result) {
            this.visibilityCondition = result;
        }

    }
    */
}