import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';

 import RESP_DATA_FIELD from '@salesforce/schema/AI_Response__c.AI_Processed_Data_PII_Added__c';
import PMT_ID_FIELD from '@salesforce/schema/AI_Response__c.AI_Prompt__c';
import TIME_SAV_FIELD from '@salesforce/schema/AI_Response__c.Time_Saved_Seconds__c';
import USER_CONTEXT_FIELD from '@salesforce/schema/AI_Response__c.User_Context_Id__c';

import TIME_ZONE from '@salesforce/i18n/timeZone';
import getSecurityAudit from '@salesforce/apex/GPTfyConsoleController.getSecurityAudit';
import getChatMessageSecurityAuditDetails from '@salesforce/apex/GPTfyConsoleController.getChatMessageSecurityAuditDetails'; 


export default class GptResponse extends LightningElement {

    @api gptAnsParam;
    @api canvasConfig = {showCanvas : false};
    timeZone = TIME_ZONE;

    @api recordId;
    @api responseId;

    @track gptResponseUrl;
    @track gptResponseName;
    @track gptResponseDate;
    @track aiResponse;
    @track chatMessages = [];

    @track showSpinner = false;

   // connectedCallback(){
        //if(!this.gptAnsParam){
            //this.getAIResponse();
        //}
   // }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if(currentPageReference && currentPageReference.state && currentPageReference.state.c__id){
            this.responseId = currentPageReference.state?.c__id;
        }
        if(this.responseId && this.responseId != null && this.responseId != ''){
            this.recordId = this.responseId;
        }
        if(this.recordId && this.recordId != null && this.recordId != '' && !this.gptAnsParam){
            this.getAIResponse();
        } 
    }

    async getAIResponse(){
        this.showSpinner = true;
        await getSecurityAudit({
            "responseId" : this.recordId
        })
        .then(result => {          
            this.showSpinner = false;
            if(result && result.length > 0){
                this.aiResponse = JSON.parse(JSON.stringify(result[0]));
                if(this.aiResponse && this.aiResponse[USER_CONTEXT_FIELD.fieldApiName] != null && this.aiResponse[USER_CONTEXT_FIELD.fieldApiName] != ''){
                    this.handleChatResponse();
                }else{
                    this.handleResponse();
                }
                
            }else{
                this.handleError('Record not found.')
            }
            
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleChatResponse(){
            getChatMessageSecurityAuditDetails({ "responseId" : this.recordId })
                    .then(result => {
                        if(result && result.length > 0){
                            let messages = JSON.parse(JSON.stringify(result));
                            this.chatMessages = messages;
                        }
                    }).catch(error => { 
                        this.handleError(error); 
                    });
    }

    handleResponse(){
        let result = this.aiResponse[RESP_DATA_FIELD.fieldApiName];
        this.gptResponseUrl = '/'+this.aiResponse.Id;
        this.gptResponseName = this.aiResponse.Name+'\n';
        this.gptResponseDate = this.aiResponse.CreatedDate;
        this.timeSaved = this.aiResponse[TIME_SAV_FIELD.fieldApiName];
        //this.manageSentimentColor();

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

        this.gptAnsParam = result;
    } 

    /*
    manageSentimentColor(){
        this.gptResponseSentiment = undefined;
        let result = this.aiResponse[RESP_DATA_FIELD.fieldApiName];
        let promptId = this.aiResponse[PMT_ID_FIELD.fieldApiName];

        if(result && this.isJSONString(result) && promptId && this.mapOfSentimentKey && this.mapOfSentimentKey.hasOwnProperty(promptId)){
            var sentimentKey = this.mapOfSentimentKey[promptId];
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
    }*/

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
    @api
    resizeCanvas(){
        const childComponent = this.template.querySelector('c-a-i-canvas');
        childComponent && childComponent.resizeCanvas();
    }

}