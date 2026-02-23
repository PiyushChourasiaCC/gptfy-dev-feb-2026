import { api, track, LightningElement,wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import PMT_TARGET_OBJECT_FIELD from "@salesforce/schema/AI_Prompt__c.Object__c";
import PMT_ID_FIELD from "@salesforce/schema/AI_Prompt__c.Id";
import PMT_VISIBILITY_CONDITION_FIELD from "@salesforce/schema/AI_Prompt__c.Visibility_Condition__c";
import PMT_INCLUDE_FILES_FIELD from "@salesforce/schema/AI_Prompt__c.Include_Files__c";
import PMT_ALLOW_USERINPUT_FIELD from "@salesforce/schema/AI_Prompt__c.Custom_Prompt__c";
import PMT_RECORD_TYPES_FIELD from "@salesforce/schema/AI_Prompt__c.Record_Type__c";
import PMT_TYPE_FIELD from "@salesforce/schema/AI_Prompt__c.Type__c";
import AI_PROMPT_MODEL_RELATIONSHIP from "@salesforce/schema/AI_Prompt__c.AI_Model_File_Processing__r.Model__c";
import PMT_AI_MODEL_FILES_FIELD from "@salesforce/schema/AI_Prompt__c.AI_Model_File_Processing__c";
import PMT_AI_MODEL_FIELD from "@salesforce/schema/AI_Connection__c.Model__c";

import PMT_VISIBILITY_EXCEPTION_MESSAGE_FIELD from "@salesforce/schema/AI_Prompt__c.Visibility_Exception_Message__c";
import { getRecord } from "lightning/uiRecordApi";
import isValidVisibilityCondition from '@salesforce/apex/GPTfyConsoleController.isValidVisibilityCondition';
import getPromptActionOptionsOpenForm from '@salesforce/apex/GPTfyConsoleController.getPromptActionOptionsOpenForm';
import getDefaultFields from '@salesforce/apex/GPTfyConsoleController.getDefaultFieldsString';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { NavigationMixin } from 'lightning/navigation';
import checkValidationPromptCommand from '@salesforce/apex/AIJsonGeneration.checkValidationPromptCommand';
import AIPrompt from "@salesforce/messageChannel/AI_Prompt__c"
import { publish, MessageContext} from 'lightning/messageService';
import { updateRecord } from 'lightning/uiRecordApi';

import TIME_ZONE from '@salesforce/i18n/timeZone';

import gptfylogo from '@salesforce/resourceUrl/gptfylogo';

import RESP_DATA_FIELD from '@salesforce/schema/AI_Response__c.AI_Processed_Data_PII_Added__c';
import ACTUAL_RESP_DATA_FIELD from '@salesforce/schema/AI_Response__c.AI_Processed_Data_No_PII__c';
import TIME_SAV_FIELD from '@salesforce/schema/AI_Response__c.Time_Saved_Seconds__c';
import RESP_ID_FIELD from '@salesforce/schema/AI_Response__c.Id';
import RESP_MESSAGE_FIELD from '@salesforce/schema/AI_Response__c.Message__c';
import RESP_STATUS_FIELD from '@salesforce/schema/AI_Response__c.Status__c';
import RESP_HOW_IT_WORKS_FIELD from '@salesforce/schema/AI_Response__c.How_it_works__c';
import RESP_RECORD_ID_FIELD from '@salesforce/schema/AI_Response__c.Record_Id__c';
import IS_CANVAS_FIELD from '@salesforce/schema/AI_Response__c.Is_Canvas_Response__c';
import THREAD_ID_FIELD from '@salesforce/schema/AI_Response__c.Thread_Id__c';

import FEEDBACK_TYPE_FIELD from '@salesforce/schema/AI_Feedback__c.Type__c';

import initiateGPT from '@salesforce/apex/ChatGPTUtills.initiateGPT';
import getAllResponses from '@salesforce/apex/GPTfyConsoleController.getAllResponses';
import checkForContentVersions from '@salesforce/apex/GPTfyConsoleController.checkForContentVersions';
import saveFeedback from '@salesforce/apex/GPTfyConsoleController.saveFeedback';
import isAdminUser from '@salesforce/apex/GPTfyConsoleController.isAdminUser';
import getLatestRecordOfSecurityAudit from '@salesforce/apex/GPTfyConsoleController.getLatestRecordOfSecurityAudit';

import processFileRequest from '@salesforce/apex/ChatGPTUtills.processFileRequest';
import getAnalyzeResult from '@salesforce/apex/ChatGPTUtills.getAnalyzeResult';
import getCustomSettings from '@salesforce/apex/AIUtility.getCustomSettings';
import processResponsesFileRequest from '@salesforce/apex/ChatGPTUtills.processResponsesFileRequest';
import getAnalyzeResponsesResult from '@salesforce/apex/ChatGPTUtills.getAnalyzeResponsesResult';
import getPromptResponse from '@salesforce/apex/ChatGPTUtills.getPromptResponse';
import checkIfResponsesApiModel from '@salesforce/apex/AIUtility.checkIfResponsesApiModel';


const fields = [PMT_VISIBILITY_CONDITION_FIELD,PMT_TARGET_OBJECT_FIELD,PMT_ID_FIELD,PMT_INCLUDE_FILES_FIELD,PMT_TYPE_FIELD
                    ,PMT_ALLOW_USERINPUT_FIELD,PMT_RECORD_TYPES_FIELD,PMT_VISIBILITY_EXCEPTION_MESSAGE_FIELD,AI_PROMPT_MODEL_RELATIONSHIP,
                    PMT_AI_MODEL_FILES_FIELD
                ];


export default class AIPromptTestingConsole extends NavigationMixin(LightningElement) {

    
    timeZone = TIME_ZONE
    gptfylogo = gptfylogo;

    @api recordId;
    @api mobileView;

    @track fileTypeLimit
    @track maxFileSize
    @track maxFileCount

    @track defaultWaitMessage = 'Anonymizing your data for secure AI processing :)';
    @track verbiage = 'This text takes about [TIME_ESTIMATED] seconds to read. Processing and anonymizing for AI now :)';
    @track waitMsg;

    @track showSpinner = false;
    @track openFormActions = [];
    @track mapOfSentimentKey;

    @track allowUserInput;
    @track includeFiles = false;
    @track userInput;
    @track promptDescription = '';
    @track targetobjectRecordId
    @track targetObj = 'Account';
    @track recordTypes;
    @track visibilityExceptionMessage;
    @track type = '';

    @track currentResponseCount = 0;
    @track noOfResponses;
    @track enableTypeWriterEffect = true;
    @track userSignature = '';
    @track namespace;
    @track emailActionName;
    @track selectedVisibilityExceptionMessage = '';
    @track gptfyBtnDisable = false;
    @track attachmentIconEnable = false;

    @track isCanvasTypePrompt = false;
    @track canvasBodyContent = '';
    @track canvasConfig;
    @track responseLoaded = false;
    @track isCanvasPrompt = false;
    @track connectionModel = '';
    @track availableHeight = 400;
    @track aiResponse;
    @wire(MessageContext)
    context;

    aiResponseList;


    get disableGPTfyButton () {
        return this.gptfyBtnDisable;
    }

    get visibleOpenForm () {
        return (this.openFormActions && this.openFormActions.length > 0) ? true : false ;
    }

    connectedCallback(){
        this.responseLoaded = true;
        this.checkAdminUser();
        if(this.mobileView){
            this.showExpanded = true; 
        }
        this.waitMsg = undefined;
        this.canvasConfig = this.initializeCanvasProperties();

        this.enableTypeWriterEffect = false;
        getCustomSettings()
        .then(result => {          
            if(result){
                if(result['typeEffect']){
                    this.enableTypeWriterEffect = result['typeEffect'];
                }
                this.attachmentIconEnable = result['fileProcessing'];
                
            }
        })
        .catch(error => {
            this.handleError(error);
        });

        getLatestRecordOfSecurityAudit({ promptId: this.recordId})
        .then(result => {          
            if(result && result.length > 0){
                this.targetobjectRecordId = result[0][RESP_RECORD_ID_FIELD.fieldApiName];
            }
        }).catch(error => {
            this.handleError(error);
        });
    }

    
    fetchPromptActionsOpenForm(){
        getPromptActionOptionsOpenForm({ promptId: this.recordId})
                .then((result)=> {
                    if(result && result.actions && result.actions.length > 0){
                        let actions = JSON.parse(JSON.stringify(result.actions));
                            this.openFormActions = actions;
                    }else{
                        this.openFormActions = []
                    }
                }).catch((error)=> {
                    this.handleError(error);
                })

    }


    @wire(getRecord, { recordId: "$recordId", fields })
    wiredRecord({error, data}){
        if(error){
            this.handleError(error);
        }else if(data){
            this.isCanvasPrompt = false;
            if(data.fields && data.fields[PMT_VISIBILITY_CONDITION_FIELD.fieldApiName] && data.fields[PMT_VISIBILITY_CONDITION_FIELD.fieldApiName].value){
                this.visibilityConditionValue = data.fields[PMT_VISIBILITY_CONDITION_FIELD.fieldApiName].value;
            }
            if(data.fields && data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName] && data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName].value){
                this.targetObj = data.fields[PMT_TARGET_OBJECT_FIELD.fieldApiName].value;
            }
            if(data.fields && data.fields[PMT_INCLUDE_FILES_FIELD.fieldApiName] && data.fields[PMT_INCLUDE_FILES_FIELD.fieldApiName].value){
                this.includeFiles = data.fields[PMT_INCLUDE_FILES_FIELD.fieldApiName].value;
            }
            if(data.fields && data.fields[PMT_ALLOW_USERINPUT_FIELD.fieldApiName] && data.fields[PMT_ALLOW_USERINPUT_FIELD.fieldApiName].value){
                this.allowUserInput = data.fields[PMT_ALLOW_USERINPUT_FIELD.fieldApiName].value;
            }
            if(data.fields && data.fields[PMT_RECORD_TYPES_FIELD.fieldApiName] && data.fields[PMT_RECORD_TYPES_FIELD.fieldApiName].value){
                this.recordTypes = data.fields[PMT_RECORD_TYPES_FIELD.fieldApiName].value;
            }
            if(data.fields && data.fields[PMT_VISIBILITY_EXCEPTION_MESSAGE_FIELD.fieldApiName] && data.fields[PMT_VISIBILITY_EXCEPTION_MESSAGE_FIELD.fieldApiName].value){
                this.visibilityExceptionMessage = data.fields[PMT_VISIBILITY_EXCEPTION_MESSAGE_FIELD.fieldApiName].value;
            }
            if(data.fields && data.fields[PMT_TYPE_FIELD.fieldApiName] && data.fields[PMT_TYPE_FIELD.fieldApiName].value && data.fields[PMT_TYPE_FIELD.fieldApiName].value === 'Canvas'){
                this.isCanvasPrompt = true;
            }
            if(data.fields && data.fields[PMT_AI_MODEL_FILES_FIELD.fieldApiName] && data.fields[PMT_AI_MODEL_FILES_FIELD.fieldApiName].value){
                let model = data.fields[PMT_AI_MODEL_FILES_FIELD.fieldApiName.replace('__c', '__r')].value.fields[PMT_AI_MODEL_FIELD.fieldApiName].value; 
                this.connectionModel = model;
            }
            //this.canvasConfig = this.initializeCanvasProperties();
            this.showSpinner = false;
        }
    }
    initializeCanvasProperties(){
        let tempCanvasConfig = {
            showCanvas:false, 
            promptValue: this.recordId, 
            objectApiName: this.targetObj, 
            recordId: this.targetobjectRecordId,
            showCanvasHeader: false,
            parentAIResponseId : '',
            skipWireUpdate : false,
            notInitialLoad :false,
            existingParentAIResponse:''
        };
        return tempCanvasConfig;
    }
    

    checkAdminUser(){
        this.showSpinner = true;
        isAdminUser()
        .then(result => {          
            this.hasAdminUser = result;
        })
        .catch(error => {
            this.handleError(error);
        });
    }


    checkValidationPrompt(){
        if(!this.targetobjectRecordId || this.targetobjectRecordId == null || this.targetobjectRecordId == undefined){
            this.showToast('error', 'Error', 'Please select record.', 'dismissable');
        }else {
            checkValidationPromptCommand({
                    "recordId" : this.recordId
                })
                .then(result => {
                    if(result && result.length > 0){
                        this.showToast('error', 'Error', result);
                        this.showSpinner = false;
                        updateRecord({ fields: { Id: this.recordId }});
                        publish(this.context, AIPrompt, {'isRefresh':true});
                    }else{
                        this.initiateGPTOnClick();
                        
                    }
                          
                })
                .catch(error => {
                    this.handleError(error);
                    this.showSpinner = false;
                });
        }
        
    }

    initiateGPTOnClick(){
        this.isCanvasTypePrompt = false;
        this.canvasConfig.showCanvas = false;
        
        var cdIds = [];
            if(this.selectedFiles && this.selectedFiles.length > 0){
                for(var file of this.selectedFiles){
                    cdIds.push(file.docId);
                }
            }

            if(this.attachmentIconEnable && this.includeFiles && (!cdIds || cdIds == null || cdIds.length == 0)){
                this.showFileAlertModal = true;
            }else{
                this.showSpinner = true;
                this.showExpanded = false;
                if(this.attachmentIconEnable && this.includeFiles){
                    this.checkModelAndInitiateFileProcessing(cdIds);
                }else{
                    if(this.isCanvasPrompt){
                        this.isCanvasTypePrompt = this.isCanvasPrompt;
                        this.initiateGPTCanvas();
                    }else{
                        this.canvasConfig.showCanvas = false;
                        this.initiateGPTProcess();
                    }
                }
            }

    }
    initiateGPTCanvas(){
        this.aiResponseList = undefined;
        this.aiResponse = undefined;
        this.noOfResponses = 0;

        this.showExpanded = true;
        this.showSpinner = false;
        this.responseLoaded = false;
        let tempCanvasConfig = this.initializeCanvasProperties();
        tempCanvasConfig.showCanvas = true;
        tempCanvasConfig.notInitialLoad = true;
        setTimeout(() => {
            this.responseLoaded = true;
        }, 0);
        this.canvasConfig = tempCanvasConfig;
    }
    initiateGPTProcess(mapOfFiles){
        this.waitMsg = this.defaultWaitMessage;

        initiateGPT({
            "recordId" : this.targetobjectRecordId, 
            "promptId" : this.recordId, 
            "userInput" : this.userInput, 
            "mapOfFiles" : mapOfFiles,
            "isGptfyConsole" : true
        })
        .then(result => {
            if(result && result[RESP_STATUS_FIELD.fieldApiName] && result[RESP_STATUS_FIELD.fieldApiName] == 'Errored' && result[RESP_MESSAGE_FIELD.fieldApiName] && result[RESP_MESSAGE_FIELD.fieldApiName] != null){
                var msg = result[RESP_MESSAGE_FIELD.fieldApiName];
                this.showToast('error', 'Error', msg, 'dismissable');
                this.showSpinner = false; 
                this.responseLoaded = true;
            }else{
                this.getGptResponses();
            } 
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    async getGptResponses(){
        this.aiResponseList = undefined;
        this.aiResponse = undefined;
        this.showSpinner = true;
        this.noOfResponses = 0;
        this.selectedFiles = undefined;

        await getAllResponses({
            "recordId" : this.targetobjectRecordId
        })
        .then(result => {          
            if(result && result.length > 0){
                this.aiResponseList = JSON.parse(JSON.stringify(result));
                this.noOfResponses = this.aiResponseList.length;
                this.showSpinner = false;
                this.aiResponse = this.aiResponseList[0];
                this.currentResponseCount = 0;
                this.handleResponse(true); 
                this.fetchPromptActionsOpenForm();
                //updateRecord({ fields: { Id: this.recordId }});
                //publish(this.context, AIPrompt, {'isRefresh':true});
            }
            this.showExpanded = true; 
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    testmethodcheck = () => {
        console.log('called testmethodcheck')
    }

    gptResponseUrl;
    gptResponseName;
    gptResponseDate;
    timeSaved;
    gptResponseSentiment = 'text-align:left;justify-content:left;background-color:white;';
    howItWorks;
    //collapsedGptAns = '';

    handleResponse(showTypingEffect){
       // this.updateRecordView(this.recordId);
        let result = this.aiResponse[RESP_DATA_FIELD.fieldApiName];
        this.gptResponseUrl = '/'+this.aiResponse.Id;
        this.gptResponseName = this.aiResponse.Name+'\n';
        this.gptResponseDate = this.aiResponse.CreatedDate;
        this.timeSaved = this.aiResponse[TIME_SAV_FIELD.fieldApiName];

        this.showHowItWorks = false;
        this.howItWorks = undefined;
        if(this.aiResponse[RESP_HOW_IT_WORKS_FIELD.fieldApiName] && this.aiResponse[RESP_HOW_IT_WORKS_FIELD.fieldApiName] != null && this.aiResponse[RESP_HOW_IT_WORKS_FIELD.fieldApiName] != ''){
            this.howItWorks = this.aiResponse[RESP_HOW_IT_WORKS_FIELD.fieldApiName];
        }

        if(this.aiResponse[ACTUAL_RESP_DATA_FIELD.fieldApiName] && showTypingEffect){
            if(this.isJSONString(this.aiResponse[ACTUAL_RESP_DATA_FIELD.fieldApiName])){
                var tokenInfo = JSON.parse(this.aiResponse[ACTUAL_RESP_DATA_FIELD.fieldApiName]);
                if(tokenInfo.entitlementMessage && tokenInfo.entitlementMessage != null && tokenInfo.entitlementMessage != ''){
                    var msg = tokenInfo.entitlementMessage;
                    if(msg && msg.includes("click here") && tokenInfo.entitlementLink){
                        msg = msg.replace("click here", "{0}");
                        const tevt = new ShowToastEvent({
                            "title": "Info!",
                            "message": msg,
                            "messageData": [
                                {
                                    url: tokenInfo.entitlementLink,
                                    label: "click here"
                                }
                            ],
                            "mode" : "sticky"
                        });
                        this.dispatchEvent(tevt);
                    }else{
                        this.showToast('info', 'Info!', msg, 'sticky');
                    }
                }
            }
        }

        this.manageSentimentColor();

        if(result && result.includes('Answer:\n{')){
            result = result.replace('Answer:\n{', '{');
        }

        if(this.isJSONString(result)){
            result = this.convertNestedJSONToReadableFormat(JSON.parse(result));
        }

        if(result){
            let regex = /(<table[^>]*>)([\s\S]*?)(<\/table>)/g;
            result = result.replace(regex, function(match, p1, p2, p3) {
                return p1 + p2.replace(/\n/g, '') + p3;
            });
        }
        if(result){
            result = result.replace(/\n/g, '<br>');
        }
        
        this.gptAns = '';
        if(showTypingEffect && result){
            if(this.enableTypeWriterEffect){
                this.typingEffect(result);
            }else{
                this.gptAns = result;
            }
        }else{
            this.gptAns = result;
        }

        /*
        this.collapsedGptAns = '';
        if(this.gptAns){
            const wordSections = this.gptAns.split(" ");
            if(wordSections && wordSections.length > 15){
                for(var i=0; i<15; i++){
                    this.collapsedGptAns += wordSections[i]+' ';
                }
                this.collapsedGptAns += '...';
            }else{
                this.collapsedGptAns = this.gptAns;
            }
        }
        */

        this.assignDefaultFeedbackData();
        updateRecord({ fields: { Id: this.recordId }});
        publish(this.context, AIPrompt, {'isRefresh':true});
    }
    
    manageSentimentColor(){
        this.gptResponseSentiment = undefined;
        let result = this.aiResponse[RESP_DATA_FIELD.fieldApiName];

        if(result && this.isJSONString(result) && this.recordId && this.mapOfSentimentKey && this.mapOfSentimentKey.hasOwnProperty(this.recordId)){
            var sentimentKey = this.mapOfSentimentKey[this.recordId];
            if(sentimentKey){
                var sentimentValue = this.getSentimentValue(JSON.parse(result), sentimentKey);

                var jsonSentiment;
                if(sentimentValue && this.isJSONObject(sentimentValue)){
                    jsonSentiment = sentimentValue;
                }else if(sentimentValue && this.isJSONString(sentimentValue)){
                    jsonSentiment = JSON.parse(sentimentValue);
                }else{
                    if(sentimentValue && sentimentValue.includes("Positive")){
                        this.gptResponseSentiment = 'height: 10px; background-color: #2e844a;';
                    }else if(sentimentValue && sentimentValue.includes("Negative")){
                        this.gptResponseSentiment = 'height: 10px; background-color: #ec3f3f;';
                    }
                }   
                
                if(jsonSentiment){
                    var sentValue = jsonSentiment['Sentiment'];
                    if(sentValue && sentValue.includes("Positive")){
                        this.gptResponseSentiment = 'height: 10px; background-color: #2e844a;';
                    }else if(sentValue && sentValue.includes("Negative")){
                        this.gptResponseSentiment = 'height: 10px; background-color: #ec3f3f;';
                    }
                }
            }
        }
    }

    getSentimentValue(jsonObj, sentimentKey, indent = 0){
        for(let property in jsonObj){
            if(jsonObj.hasOwnProperty(property)){
                if(property === sentimentKey){
                    return jsonObj[property];
                }
                if(typeof jsonObj[property] === 'object'){
                    this.getSentimentValue(jsonObj[property], sentimentKey, indent + 1);
                }
            }
        }
        return '';
    }

    isJSONObject(obj){
        try {
          JSON.parse(JSON.stringify(obj));
        } catch (e) {
          return false;
        }
        return true;
    }

    isJSONString(str){
        try {
          JSON.parse(str);
        } catch (e) {
          return false;
        }
        return true;
    }

    convertNestedJSONToReadableFormat(jsonObj, indent = 0) {
        let result = '';
        for(let property in jsonObj){
            if(jsonObj.hasOwnProperty(property)){
                if(typeof jsonObj[property] === 'object'){
                    var resp = this.convertNestedJSONToReadableFormat(jsonObj[property], indent + 1);
                    if(resp && resp != null && resp != ''){
                        result += resp;
                    }
                }else{
                    result += '<b style="color:gray">'+property+':</b> ';
                    result += jsonObj[property]+'<br>';
                }
            }
        }
        return result;
    }
    
    
    convertNestedJSONToReadableFormatInText(jsonObj, indent = 0) {
        let result = '';
        for(let property in jsonObj){
            if(jsonObj.hasOwnProperty(property)){
                if(typeof jsonObj[property] === 'object'){
                    var resp = this.convertNestedJSONToReadableFormat(jsonObj[property], indent + 1);
                    if(resp && resp != null && resp != ''){
                        result += resp;
                    }
                }else{
                    result += ''+property+': ';
                    result += jsonObj[property]+'\n';
                }
            }
        }
        return result;
    }
    

    gptAns;
    typingEffect(gptAns){
        const wordSections = gptAns.split(" ");
        var t = this;
        var i = 0;
        t.gptAns = '';

        const typingSpeed = 100;
        const timer = setInterval(() => {
            if(i > wordSections.length){
                clearInterval(timer);
                return;
            }
            if(wordSections[i]){
                t.gptAns += wordSections[i]+' ';
            }
            i++;
        }, typingSpeed);
    }

    @track showModifyModal = false;
    handleModifyPrompt(){
        if(this.showModifyModal){
            this.showModifyModal = false;
        }else{
            this.showModifyModal = true;
        }
    }

    showToast(variant, title, message, mode) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
            mode: mode
        });
        this.dispatchEvent(event);
    }

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message, 'dismissable');
        }else{
            this.showToast('error', 'Error', error.toString(), 'dismissable');
        }
    }

    @track showAttachModal = false;
    @track attachColumns = [
        { label: 'Title', fieldName: 'title', hideDefaultActions : true },
        { label: 'File Type', fieldName: 'fileType', hideDefaultActions : true },
        { label: 'File Size', fieldName: 'fileSize', hideDefaultActions : true }
    ];
    @track attachmentData;
    @track attachActiveSessions = [];

     handleFilesModal(){

        if(!this.targetobjectRecordId || this.targetobjectRecordId == null || this.targetobjectRecordId == undefined){
            this.showToast('error', 'Error', 'Please select record.', 'dismissable');
            return;
        }

        this.waitMsg = undefined;
        this.showSpinner = true;
        this.attachmentData = undefined;
        this.attachActiveSessions = [];
        checkForContentVersions({
            "recordId" : this.targetobjectRecordId, 
            "promptId" : this.recordId
        })
        .then(result => {
            this.showSpinner = false;
            if(result && result.length > 0){
                this.showAttachModal = true;
                let attachmentDataList = JSON.parse(JSON.stringify(result));
                getCustomSettings()
                    .then(result => {          
                        if(result){
                            if(result['maxFileCount'])
                                this.maxFileCount = result['maxFileCount'];
                        }
                        this.attachmentData = attachmentDataList
                        for(var rec of this.attachmentData){
                            this.attachActiveSessions.push(rec["recId"]);
                        }
                    })
                    .catch(error => {
                        this.handleError(error);
                    });
                
            }else{
                this.showToast('warning', 'Alert', 'No related files found!', 'dismissable');
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleAttachCancel(){
        this.showAttachModal = false;
    }

    @track selectedFiles;
    handleAttach(){
        this.selectedFiles = undefined;
        var selectedTables = this.template.querySelectorAll("lightning-datatable");

        if(selectedTables && selectedTables.length > 0){
            this.selectedFiles = [];
            for(var selectTable of selectedTables){
                for(var obj of selectTable.getSelectedRows()){
                    this.selectedFiles.push(obj);
                }
            }
        } 

        if(!this.selectedFiles || this.selectedFiles.length == 0){
            this.showToast('error', 'Error', 'Please select atleast one file.', 'dismissable');
        }else{
            this.handleAttachCancel();
        }
    }

    handleFileRemove(event){
        var docId = event.target.dataset.docid;
        this.selectedFiles = this.selectedFiles.filter(obj => {
            return obj.docId !== docId;
        });
    }

    @track timeoutRef = null;
    disconnectedCallback() {
        clearTimeout(this.timeoutRef);
    }

    initiateFileProcessing(cdIds, fwrapStr){
            this.waitMsg = 'Uploading files to AI...';
            
            processFileRequest({
                "promptId": this.recordId,
                "recordId" : this.targetobjectRecordId,
                "userInput" : this.userInput,
                "cdIds" : cdIds,
                "fwrapStr" : fwrapStr
            })
            .then(result => {
                console.log('result: '+JSON.stringify(result));
                if(result && result.isError){
                    this.showToast('error', 'Error', result.errorMessage, 'dismissable');
                }else{
                    if(result && result.delay && parseInt(result.delay) > 0){
                        this.timeoutRef = setTimeout(() => {
                            this.initiateFileProcessing(cdIds, JSON.stringify(result));
                        }, (parseInt(result.delay) * 1000));
                    }else{
                        this.getAnalyzedFiles(result);
                    }
                }
            })
            .catch(error => {
                this.handleError(error);
            });
        }
    
        async getAnalyzedFiles(fileData){
            var isRunning = false;
            var skipAdditionalCall = false;
    
            this.waitMsg = 'Checking if the files are processed by AI...';
    
            var contents = {};
    
            await getAnalyzeResult({
                "promptId": this.recordId,
                "fwrapStr" : JSON.stringify(fileData)
            })
            .then(result => {  
                console.log('result: '+JSON.stringify(result));   
                if(result && result.mapOfCdIdToFileData){
                    for(var cdId in result.mapOfCdIdToFileData){
                        var objStr = result.mapOfCdIdToFileData[cdId];
                        var obj = JSON.parse(objStr);
    
                        if(obj.status == 'running'){
                            isRunning = true;
                        }else if(obj.status == 'succeeded'){
                            if(obj.analyzeResult && obj.analyzeResult.content){
                                contents[cdId] = obj.analyzeResult.content;
                            }
                        }
                    }
                }else if(result.runId && result.threadId){
                    if(result.runStatus == 'queued' || result.runStatus == 'in_progress'){
                        isRunning = true;
                    }else{
                        if(result && result.aiResponseId && result.aiResponseId != null && result.aiResponseId != ''){
                            skipAdditionalCall = true;
                        }
                    }
                }
                
            })
            .catch(error => {
                this.handleError(error);
            });
    
            if(isRunning){
                this.waitMsg = 'Files are still processing, will check again after 5 seconds...';
                this.timeoutRef = setTimeout(() => {
                    this.getAnalyzedFiles(fileData);
                }, 5000);
            }else{
                this.waitMsg = 'Files are processed sucessfully...';
                if(skipAdditionalCall){
                    this.getGptResponses();
                }else{
                    var mapOfFiles = {};
                    for(var file of this.selectedFiles){
                        if(contents && contents.hasOwnProperty(file.docId)){
                            if(!mapOfFiles[file.recId]){
                                mapOfFiles[file.recId] = [];
                            }
                            mapOfFiles[file.recId].push(contents[file.docId]);
                        }
                    }
                    this.initiateGPTProcess(mapOfFiles);
                }
            }
        }


    @track likeState;
    @track dislikeState;
    @track showFeedbackModal = false;
    @track feedbackCategoryOptions;
    @track feedbackCategory;
    @track feedbackDetail;
    @track feedbackDetailPlaceholder;

    assignDefaultFeedbackData(){
        this.likeState = false;
        this.dislikeState = false;
        this.showFeedbackModal = false;
        this.feedbackDetail = '';
        this.feedbackCategory = [];
        this.feedbackDetailPlaceholder = '';
        if(this.aiResponse){
            var feedbacks = this.aiResponse[this.namespace+'Feedbacks__r'];
            if(feedbacks && feedbacks.length > 0){
                var feedbk = feedbacks[0];
                if(feedbk[FEEDBACK_TYPE_FIELD.fieldApiName] == 'Like'){
                    this.likeState = true;
                }else if(feedbk[FEEDBACK_TYPE_FIELD.fieldApiName] == 'Dislike'){
                    this.dislikeState = true;
                }
            }
            //if(this.aiResponse[RESP_FEEDBACK_CATEGORY_FIELD.fieldApiName]){
                //this.feedbackCategory = this.aiResponse[RESP_FEEDBACK_CATEGORY_FIELD.fieldApiName].split(';');
            //}if(this.aiResponse[RESP_FEEDBACK_DETAIL_FIELD.fieldApiName]){
                //this.feedbackCategory = this.aiResponse[RESP_FEEDBACK_DETAIL_FIELD.fieldApiName];
            //}
        }
    }

    handleLikeButtonClick() {
        this.likeState = !this.likeState;
        if(this.likeState){
            this.feedbackDetailPlaceholder = "What do you like about the response?"
            this.dislikeState = false;
            this.feedbackDetail = '';
            this.feedbackCategory = [];
            this.showFeedbackModal = true;
        }else{
            this.feedbackCategory = [];
            this.feedbackDetail = '';
            this.handleSubmitFeedback();
        }
    }

    handleDislikeButtonClick() {
        this.dislikeState = !this.dislikeState;
        if(this.dislikeState){
            this.feedbackDetailPlaceholder = "What was the issue with the response? How could it be improved?";
            this.likeState = false;
            this.feedbackDetail = '';
            this.feedbackCategory = [];
            this.showFeedbackModal = true;
        }else{
            this.feedbackCategory = [];
            this.feedbackDetail = '';
            this.handleSubmitFeedback();
        }
    }

    handleFeedbackCancel(){
        this.assignDefaultFeedbackData();
    }

    handleFeedbackDetailChange(event){
        this.feedbackDetail = event.target.value;
    }

    handleFeedbackCategoryChange(event){
        this.feedbackCategory = event.target.value;
    }

    handleSubmitFeedback(){
        var feedback = '';
        if(this.likeState){
            feedback = 'Like';
        }else if(this.dislikeState){
            feedback = 'Dislike';
        }

        var feedbackCategory = this.feedbackCategory && this.feedbackCategory.length > 0 ? this.feedbackCategory.join(";") : '';
        var feedbackDetail = this.feedbackDetail ? this.feedbackDetail : '';
        saveFeedback({
            "responseId" : this.aiResponse[RESP_ID_FIELD.fieldApiName], 
            "feedback" : feedback,
            "feedbackCategory" : feedbackCategory, 
            "feebackDetail" : feedbackDetail
        })
        .then(result => {
            this.showToast('success', 'Success', 'Feedback captured!', 'dismissable');
            this.getGptResponses();
        })
        .catch(error => {
            this.handleError(error);
        });
    }


    @track showFileAlertModal;
    handleFileAlertCancel(){
        this.showFileAlertModal = false;
    }

    handleFileAlertConfirm(){
        this.showFileAlertModal = false;
        this.showSpinner = true;
        this.showExpanded = false;
        this.checkModelAndInitiateFileProcessing([]);
    }

    checkModelAndInitiateFileProcessing(cdIds){
        checkIfResponsesApiModel({
            modelName: this.connectionModel
        })
        .then(result => {
            if(result){
                this.initiateFileProcessingUsingResponsesAPI(cdIds);
            }else{
                this.initiateFileProcessing(cdIds, "{}");
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    @track showHowItWorks = false;
    handleHowItWorks(){
        if(this.showHowItWorks){
            this.showHowItWorks = false;
        }else{
            this.showHowItWorks = true;
        }
        const childComponent = this.template.querySelector('c-gpt-response');
        childComponent && childComponent.resizeCanvas();
    }

    handlerRecordPicker = (e) => {
        
        this.targetobjectRecordId = e.detail.recordId;
        if(e.detail.recordId){
            this.checkVisibilityConditionGPTfyButton(this.visibilityConditionValue,this.recordTypes,this.visibilityExceptionMessage);
        }else{
            this.gptfyBtnDisable = false;
        }
    }

    changePromptInput(event){
        this.userInput = event.detail.value;
    }

    handleEnter(event){
        if(event.keyCode === 13){
            this.initiateGPT();
        }
    }

    checkVisibilityConditionGPTfyButton = async(visibilityCondition, selectedRecordTypes, visibilityExceptionMsg) => {
        if((visibilityCondition !== undefined && visibilityCondition !== '') || (selectedRecordTypes && selectedRecordTypes.length > 0)){
           this.gptfyBtnDisable = true;
           await isValidVisibilityCondition({
               objectApiName : this.targetObj,
               recordId: this.targetobjectRecordId,
               whereClause: visibilityCondition,
               selectedRecordTypes: selectedRecordTypes
           }).then((res)=>{
               if(res){
                   this.gptfyBtnDisable = false
                   this.selectedVisibilityExceptionMessage = ''
               }else{
                   this.gptfyBtnDisable = true;
                   if(visibilityExceptionMsg && visibilityExceptionMsg !== null){
                       this.selectedVisibilityExceptionMessage = visibilityExceptionMsg
                   }else{
                       this.selectedVisibilityExceptionMessage = 'This record does not match with the prompt\'s visibility condition.'
                   }
                   
               }                                    
           }).catch((e)=> {
               this.handleError(e);
           })
        }else{
           this.gptfyBtnDisable = false;
           this.selectedVisibilityExceptionMessage = ''
        }
   }

   @track showOpenFormModal;
    //@track selectedFormAction;
    handleOpenFormClick(){
        if(!this.showOpenFormModal){
            this.showOpenFormModal = true;
        }else{
            this.showOpenFormModal = false;
        }
    }


    handleOpenFormOptionSelect(event){
        //var actionId = event.target.dataset.id;
        var index = event.target.dataset.index;
        var action = this.openFormActions[index];
        this.handleFormOpen(action);
    }

    handleFormOpen(selectedAction){
        var actionId = selectedAction['actionId'];
        if(actionId && actionId != null && actionId != ''){
            getDefaultFields({
                actionId : actionId,
                responseId: this.aiResponse[RESP_ID_FIELD.fieldApiName],
            }).then((res)=>{
                var sobj = {};
                if(res){
                    sobj = JSON.parse(res);
                }

                var p_obj = {};
                for(var key in sobj){
                    if(key != 'attributes'){
                        p_obj[key] = sobj[key];
                    }
                }

                const defaultValues = encodeDefaultFieldValues(p_obj);
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: selectedAction['objectName'],
                        actionName: 'new'
                    },
                    state: {
                        defaultFieldValues: defaultValues,
                        useRecordTypeCheck: 'true'
                    }
                });
                
            }).catch((e)=> {
                this.handleError(e);
            })
        }
    }
    get hasContentToDisplay(){
        return this.gptAns || this.isCanvasTypePrompt;
    }
    handleParentResponseCreated(evt){
        let responseBool = false;
        this.aiResponse = JSON.parse(JSON.stringify(evt.detail.parentAIResponse));
        if(this.canvasConfig.parentAIResponseId === null || this.canvasConfig.parentAIResponseId === ''){
            this.aiResponse[IS_CANVAS_FIELD.fieldApiName] = true;
            if(this.aiResponseList && this.aiResponseList.length > 0){
                this.aiResponseList.unshift(this.aiResponse);
            }else{
                this.aiResponseList = [];
                this.aiResponseList.push(this.aiResponse);
            }
            let tempCanvasConfig = JSON.parse(JSON.stringify(this.canvasConfig));
            tempCanvasConfig.parentAIResponseId = this.aiResponse.Id;
            tempCanvasConfig.skipWireUpdate = true;
            this.canvasConfig = tempCanvasConfig;
            responseBool = true;
            this.currentResponseCount = 0;
        }
        this.handleResponse(responseBool); 
    }
    handleParentResponseUpdated(evt){
        this.aiResponse = JSON.parse(JSON.stringify(evt.detail.parentAIResponse));
        if(!this.aiResponseList){
            this.aiResponseList = [];
            this.aiResponseList.push(this.aiResponse);
        }
        let tempRespList = JSON.parse(JSON.stringify(this.aiResponseList));
        const index = tempRespList.findIndex(resp => {
            return resp.Id ===  this.aiResponse.Id;
        });
        if(index){
            tempRespList[index] = this.aiResponse;
            this.aiResponseList = tempRespList;
        }
        this.handleResponse(false); 
    }
    handleBodyChange(evt){
        this.gptAns = '';
        this.canvasBodyContent = evt.detail.canvasBodyContent;
    }
    
    handleCanvasError(){
        console.log('Error in canvas');
         updateRecord({ fields: { Id: this.recordId }});
         publish(this.context, AIPrompt, {'isRefresh':true});
    }
    get popoutCanvasConfig(){
        let tempCanvasConfig = JSON.parse(JSON.stringify(this.canvasConfig));
        tempCanvasConfig = this.initializeCanvasProperties(tempCanvasConfig);
        if(this.gptAns){
            tempCanvasConfig.showCanvas = false;
        }else{
            tempCanvasConfig.showCanvas = true;
        }

        return tempCanvasConfig;
    }
    handleHideFooter(evt){
        this.hideFooter = evt.detail.hideFooter;
    }
    get hasAllLoadedContent(){
        return (this.gptAns && this.gptAns.length > 0) || (this.canvasBodyContent && this.canvasBodyContent.length > 0);
    }
    showPopOutContent = false;
    handlePopOutContent(){
        this.showPopOutContent = !this.showPopOutContent;
    }
    async initiateFileProcessingUsingResponsesAPI(cdIds) {
        this.waitMsg = 'Uploading files to AI...';
    
        try {
            const result = await processResponsesFileRequest({
                "promptId": this.recordId,
                "recordId": this.targetobjectRecordId,
                "userInput": this.userInput,
                "cdIds": cdIds
            });
    
            let tempResult = JSON.parse(result);
    
            if(tempResult.aiResponse[RESP_STATUS_FIELD.fieldApiName] === 'Errored'){
                this.showToast('error','Error', tempResult.aiResponse[RESP_MESSAGE_FIELD.fieldApiName], 'dismissable');
                this.showSpinner = false;
                return;
            }
            // Poll for each uploaded file and collect their final statuses
            const statusPromises = tempResult.uploadedFileIds.map(fileId =>
                this.getAnalyzedResponsesFiles(fileId, tempResult)
            );
            const statuses = await Promise.all(statusPromises);
    
            // Check if any file failed
            const failedFiles = tempResult.uploadedFileIds.filter((_, idx) => statuses[idx] === 'Failed');
    
            if (failedFiles.length > 0) {
                const userConfirmed = await this.showFailedStatusConfirmation(failedFiles);
                if (!userConfirmed) {
                    return; // Stop if user does not want to proceed
                }
            }
            this.makePromptResponseCallout(tempResult);
        } catch (error) {
            if(error?.body?.message?.startsWith('Apex heap size too large')){
                this.showSpinner = false;
                this.showToast('error', 'Error', 'File size too large. Please try uploading files less than 2.5 mb.', 'dismissable');
            }else{
                this.handleError(error);
            }
        }
    }
    getAnalyzedResponsesFiles(fileId, wrap) {
        this.waitMsg = 'Checking if the files are processed by AI...';
    
        return new Promise((resolve, reject) => {
            const checkStatus = () => {
                getAnalyzeResponsesResult({
                    "fileId": fileId,
                    "wrapJSON": JSON.stringify(wrap)
                })
                .then(result => {
                    if (result === 'completed') {
                        resolve('completed');
                    } else if (result === 'in_progress') {
                        setTimeout(checkStatus, 2000);
                    } else if (result === 'failed') {
                        resolve('Failed');
                    } else {
                        resolve(result); // Handle any other status as needed
                    }
                })
                .catch(error => {
                    this.handleError(error);
                    resolve('Failed'); // Treat errors as failures
                });
            };
            checkStatus();
        });
    }
    showFailedStatusConfirmation(failedFiles) {
        return new Promise((resolve) => {
            // Replace with your UI logic (e.g., modal dialog)
            const message = `Some files failed to process: ${failedFiles.join(', ')}. Do you want to continue with the rest?`;
            const userConfirmed = window.confirm(message); // Example using browser confirm
            resolve(userConfirmed);
        });
    }
    async makePromptResponseCallout(wrap){
        this.waitMsg = this.defaultWaitMessage;
        try {
            const result = await getPromptResponse({
                "wrapJSON" : JSON.stringify(wrap)
            });
            // Only call getGptResponses if user agrees or no failures
            this.getGptResponses();
    
        } catch (error) {
            this.handleError(error);
        }
    }
}