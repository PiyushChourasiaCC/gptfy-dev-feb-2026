import { LightningElement, track, api } from 'lwc';
import getPromptResponse from '@salesforce/apex/AICanvasCardController.getPromptResponse';
import getSummaryPromptResponse from '@salesforce/apex/AICanvasCardController.getSummaryPromptResponse';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AICanvasCard extends LightningElement {
    @api recordId;
    @api canvasTemplatePrompts;
    @api notInitialLoad;
    @api parentAIResponseId;
    @api objectApiName;
    @track templateComponent;
    @track prompt;
    
    
    @api
    get canvasTemplateComponent(){
        return this.templateComponent;
    }
    set canvasTemplateComponent(templateComponentRecord){
        if(templateComponentRecord){
            // Deep clone the template component to avoid reference issues
            this.templateComponent = JSON.parse(JSON.stringify(templateComponentRecord));
        }
    }
    get isLoading(){
        // Determine loading state based on whether we have summary prompt or regular prompt response
        return this.hasSummaryPrompt ? 
            !(this.templateComponent && this.templateComponent.summaryResponse) :
            !(this.templateComponent && this.templateComponent.responseDetails && this.templateComponent.responseDetails.responseBody)
    }
    get hasSummaryPrompt(){
        // Check if this component has a summary prompt configured and available in the prompts map
        return this.templateComponent && this.templateComponent.summaryPrompt && this.canvasTemplatePrompts.has(this.templateComponent.summaryPrompt);
    }
    get responseContent(){
        return this.hasSummaryPrompt ? this.templateComponent.summaryResponse : this.templateComponent.responseDetails.responseBody;
    }
    get promptName(){
        return this.templateComponent && this.canvasTemplatePrompts.get(this.templateComponent.prompt).name;
    }
    connectedCallback(){
        if(this.templateComponent && this.canvasTemplatePrompts){
            this.loadPromptDetails(this.canvasTemplatePrompts.get(this.templateComponent.prompt));
        }
    }
    async loadPromptDetails(prompt) {
        let request = this.getRequest(prompt);
        try{
            let response = await getPromptResponse({requestJSON : JSON.stringify(request), 
                                    promptId : prompt.Id, recordId : this.recordId,
                                    parentAIResponseId : this.parentAIResponseId,
                                    notInitialLoad : this.notInitialLoad, objectApiName : this.objectApiName,
                                    inheritPromptSecurity : this.templateComponent.inheritPromptSecurity,
                                    promptElementDetails : JSON.stringify(this.templateComponent)});
            if(response){
                let parsedResponse = JSON.parse(JSON.stringify(response));
                parsedResponse.responseBody = parsedResponse.responseBody ? this.beutifyResponse(parsedResponse.responseBody) : 
                        parsedResponse.message ? parsedResponse.message : '';
                this.templateComponent.responseDetails = parsedResponse;
                if(this.hasSummaryPrompt){
                    this.invokeSummaryCallout(parsedResponse.Id);
                }else{
                    this.templateComponent.cardStyle = 'prompt-card';
                }
                this.fireChangeEvent();
            }
        }catch(error){
            this.showToast('Error', error?.body?.message, 'error');
        }
    }
    async invokeSummaryCallout(auditRecordId){
        let prompt = this.canvasTemplatePrompts.get(this.templateComponent.summaryPrompt);
        let request = this.getRequest(prompt);
        request.recordId = auditRecordId;
        try{
            let response = await getSummaryPromptResponse({
                                requestJSON : JSON.stringify(request), promptId : prompt.Id,
                                recordId : this.recordId,
                                parentAIResponseId : this.parentAIResponseId,
                                notInitialLoad : this.notInitialLoad,objectApiName : this.objectApiName,
                                inheritPromptSecurity : this.templateComponent.inheritPromptSecurity,
                                auditRecordId: auditRecordId});

            if(response){
                let parsedResponse = JSON.parse(JSON.stringify(response));
                this.templateComponent.summaryResponseDetails = parsedResponse;
                if(parsedResponse.message){
                    this.templateComponent.summaryResponse = parsedResponse.message;
                }else{
                    this.templateComponent.summaryResponse = this.beutifyResponse(parsedResponse.responseBody);
                }
                this.templateComponent.cardStyle = 'prompt-card';
                this.fireChangeEvent();
            }
        }catch(error){
            this.showToast('Error', error?.body?.message, 'error');
        }
    }
    getRequest(prompt){
        return  {
            promptRequestId: prompt.promptRequestId, 
            recordId: this.recordId,
            customPromptCommand: ''
        };
    }
    // Beutify the body of the response
    beutifyResponse(responseBody){
        let result = responseBody;

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
        
        return result;
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
    fireChangeEvent(){
        this.dispatchEvent(new CustomEvent('mutation' , {detail : {
            templateComponent : this.templateComponent
        }}));
    }
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
    get canvasConfig(){
        return {showCanvas: false};
    }
}