import { LightningElement, api, track } from 'lwc';
import getMappings from '@salesforce/apex/AIPromptExportController.getMappings';

export default class AIGlobalPromptExportComponent extends LightningElement {
    @track showSpinner = false;
    @api parentprompts;
    @api promptsMap;
    @api isImport = false;
    @track prompts;
    @track allPromptSelected = false;

    get hasRecords(){
        return (this.prompts && this.prompts.length>0);
    }

    connectedCallback(){
        this.prompts = JSON.parse(JSON.stringify(this.parentprompts));
    }

    handleAllPromptSelect(event){
        var connectionIds = [];
        var removedConnectionIds = [];
        var extractionMappingIds = [];
        var removedExtractionMappingIds = [];
        var selectedPrompt = [];
        this.allPromptSelected = event.target.checked;
        for(var i = 0; i < this.prompts.length; i++){
            this.prompts[i]['selected'] = event.target.checked;
            if (event.target.checked) {
                selectedPrompt.push(this.prompts[i]);
                if(this.prompts[i].type === 'Canvas' && this.prompts[i].promptElements && this.promptsMap){
                    for(var pmtEle of this.prompts[i].promptElements){
                        if(pmtEle.promptId){
                            let tempprompt = this.promptsMap.get(pmtEle.promptId);
                            if(tempprompt){
                                selectedPrompt.push(tempprompt);
                                connectionIds.push(tempprompt.connectionId);
                                extractionMappingIds.push(tempprompt.extractionMappingId);
                            }
                        }
                        if(pmtEle.summaryPromptId){
                            let summaryprompt = this.promptsMap.get(pmtEle.summaryPromptId);
                            if(summaryprompt){
                                selectedPrompt.push(summaryprompt);
                                connectionIds.push(summaryprompt.connectionId);
                                extractionMappingIds.push(summaryprompt.extractionMappingId);
                            }
                        }
                    }
                }
                connectionIds.push(this.prompts[i].connectionId);
                extractionMappingIds.push(this.prompts[i].extractionMappingId);
            } else {
                if(this.prompts[i].type === 'Canvas' && this.prompts[i].promptElements && this.promptsMap){
                    for(var pmtEle of this.prompts[i].promptElements){
                        if(pmtEle.promptId){
                            let tempprompt = this.promptsMap.get(pmtEle.promptId);
                            if(tempprompt){
                                removedConnectionIds.push(tempprompt.connectionId);
                                removedExtractionMappingIds.push(tempprompt.extractionMappingId);
                            }
                        }
                        if(pmtEle.summaryPromptId){
                            let summaryprompt = this.promptsMap.get(pmtEle.summaryPromptId);
                            if(summaryprompt){
                                removedConnectionIds.push(summaryprompt.connectionId);
                                removedExtractionMappingIds.push(summaryprompt.extractionMappingId);
                            }
                        }
                    }
                }
                removedConnectionIds.push(this.prompts[i].connectionId);
                removedExtractionMappingIds.push(this.prompts[i].extractionMappingId);
            }
        }
        //var selectedPrompt = this.prompts.filter(prompt => prompt.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : {
                    data:selectedPrompt,
                    connectionIds:connectionIds, 
                    removedConnectionIds:removedConnectionIds, 
                    extractionMappingIds:extractionMappingIds, 
                    removedExtractionMappingIds:removedExtractionMappingIds
                }
        }}));
    }

    handlePromptSelect(event){
        var mIndex = event.target.dataset.mid;
        //alert(mIndex);
        this.prompts[mIndex]['selected'] = event.target.checked;

        this.allPromptSelected = false;
        var selectedPrompts = [];
        for(var pmt of this.prompts){
            if(pmt.selected){
                selectedPrompts.push(pmt);
            }
        }
        if(selectedPrompts && selectedPrompts.length == this.prompts.length){
            this.allPromptSelected = true;
        }
        var connectionIds = [];
        var removedConnectionIds = [];
        var extractionMappingIds = [];
        var removedExtractionMappingIds = [];

        var selectedPrompt = this.prompts.filter(prompt => prompt.selected);

        let promptData = this.prompts[mIndex];
        if(event.target.checked){
            if(promptData.type === 'Canvas' && promptData.promptElements && this.promptsMap){
                for(var pmtEle of promptData.promptElements){
                    if(pmtEle.promptId){
                        let tempprompt = this.promptsMap.get(pmtEle.promptId);
                        if(tempprompt){
                            selectedPrompt.push(tempprompt);
                            if(tempprompt.connectionId){
                                connectionIds.push(tempprompt.connectionId);
                            }
                            if(tempprompt.extractionMappingId){
                                extractionMappingIds.push(tempprompt.extractionMappingId);
                            }
                        }
                    }
                    if(pmtEle.summaryPromptId){
                        let summaryprompt = this.promptsMap.get(pmtEle.summaryPromptId);
                        if(summaryprompt){
                            selectedPrompt.push(summaryprompt);
                            connectionIds.push(summaryprompt.connectionId);
                            extractionMappingIds.push(summaryprompt.extractionMappingId);
                        }
                    }
                }
            }
            connectionIds.push(promptData.connectionId);
            if(promptData.includeFiles && promptData.aIModelFileProcessing && promptData.aIModelFileProcessing.length > 0){
                    connectionIds.push(promptData.aIModelFileProcessing);
            }
            extractionMappingIds.push(promptData.extractionMappingId);
        }else{
            if(promptData.type === 'Canvas' && promptData.promptElements && this.promptsMap){
                for(var pmtEle of promptData.promptElements){
                    if(pmtEle.promptId){
                        let tempprompt = this.promptsMap.get(pmtEle.promptId);
                        if(tempprompt){
                            if(tempprompt.connectionId){
                                removedConnectionIds.push(tempprompt.connectionId);
                            }
                            if(tempprompt.extractionMappingId){
                                removedExtractionMappingIds.push(tempprompt.extractionMappingId);
                            }
                        }
                    }
                    if(pmtEle.summaryPromptId){
                        let summaryprompt = this.promptsMap.get(pmtEle.summaryPromptId);
                        if(summaryprompt){
                            removedConnectionIds.push(summaryprompt.connectionId);
                            removedExtractionMappingIds.push(summaryprompt.extractionMappingId);
                        }
                    }
                }
            }
            removedConnectionIds.push(promptData.connectionId);
            if(promptData.includeFiles && promptData.aIModelFileProcessing && promptData.aIModelFileProcessing.length > 0){
                    removedConnectionIds.push(promptData.aIModelFileProcessing);
            }
            removedExtractionMappingIds.push(promptData.extractionMappingId);
        }
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : {
                data:selectedPrompt,
                connectionIds:connectionIds, 
                removedConnectionIds:removedConnectionIds, 
                extractionMappingIds:extractionMappingIds, 
                removedExtractionMappingIds:removedExtractionMappingIds
                }
        }}));
    }

    handlePromptRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempMapping = JSON.parse(JSON.stringify(this.prompts));
        tempMapping.splice(mIndex, 1);
        this.prompts = JSON.parse(JSON.stringify(tempMapping));
        this.dispatchEvent(new CustomEvent('remove' , {detail : {
            value : this.prompts
        }}));
    }

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            alert(error.body.message);
        }else{
            alert(error.toString());
        }
    }

    handleInputChange(event){

    }
}