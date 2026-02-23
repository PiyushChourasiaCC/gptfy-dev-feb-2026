import { LightningElement, track } from 'lwc';

import getMappings from '@salesforce/apex/AIPromptExportController.getMappings';

export default class AIPromptExportComponent extends LightningElement {

    @track showSpinner = false;
    @track exportedOn;
    @track orgId;
    @track exportedBy;

    @track prompts;
    @track mappings;
    @track connections;
    @track filters;
    @track dataSources;

    connectedCallback(){
        this.getExportData();
    }

    async getExportData(){
        this.showSpinner = true;
        this.prompts = undefined;
        this.mappings = undefined;
        this.connections = undefined;
        this.exportedOn = undefined;
        this.orgId = undefined;
        this.exportedBy = undefined;
        this.filters = undefined;
        this.dataSources = undefined;
        await getMappings()
        .then(result => {      
            if(result && result.prompts && result.prompts.length > 0){
                this.prompts = JSON.parse(JSON.stringify(result.prompts));  
                this.mappings = JSON.parse(JSON.stringify(result.dataExtractionMappings));  
                this.connections = JSON.parse(JSON.stringify(result.connections));
                if(result.securityFilters){
                    this.filters = JSON.parse(JSON.stringify(result.securityFilters));
                }
                if(result.dataSources && result.dataSources.length > 0){
                    this.dataSources = JSON.parse(JSON.stringify(result.dataSources));
                }
                this.exportedBy = result.exportedBy;
                this.exportedOn = result.exportedOn;
                this.orgId = result.orgId;
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleReset(){
        this.getExportData();
    }

    handleAllPromptSelect(event){
        this.allPromptSelected = event.target.checked;
        for(var i = 0; i < this.prompts.length; i++){
            this.prompts[i]['selected'] = event.target.checked;
        }
    }

    @track allPromptSelected = false;
    handlePromptSelect(event){
        var mIndex = event.target.dataset.mid;
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
    }

    /*
    handlePromptRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempMapping = JSON.parse(JSON.stringify(this.prompts));
        tempMapping.splice(mIndex, 1);
        this.prompts = JSON.parse(JSON.stringify(tempMapping));
    }
    */

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            alert(error.body.message);
        }else{
            alert(error.toString());
        }
    }

    downloadExportFile(){

        var promptsToBeExported = [];
        if(this.prompts && this.prompts.length > 0){
            for(var pmt of this.prompts){
                if(pmt.selected){
                    promptsToBeExported.push(pmt);
                }
            }
        }

        if(promptsToBeExported && promptsToBeExported.length > 0){

            var mappings = {};
            var mappingIds = [];
            var connections = {};
            var connectionIds = [];
            var dataSourceIds = [];

            for(var pmt of promptsToBeExported){
                if(!mappingIds.includes(pmt.extractionMappingId)){
                    mappingIds.push(pmt.extractionMappingId);
                    mappings[pmt.extractionMappingId] = this.mappings[pmt.extractionMappingId];

                    if(mappings[pmt.extractionMappingId] && mappings[pmt.extractionMappingId]['dataSourceId'] && !dataSourceIds.includes(mappings[pmt.extractionMappingId]['dataSourceId'])){
                        dataSourceIds.push(mappings[pmt.extractionMappingId]['dataSourceId']);
                    }
                }

                if(!connectionIds.includes(pmt.connectionId)){
                    connectionIds.push(pmt.connectionId);
                    connections[pmt.connectionId] = this.connections[pmt.connectionId];
                }
            }

            var dataSources = [];
            if(dataSourceIds && dataSourceIds.length > 0 && this.dataSources && this.dataSources.length > 0){
                for(var ds of this.dataSources){
                    if(dataSourceIds.includes(ds.salesforceId)){
                        dataSources.push(ds);
                    }
                }
            }

            var obj = {
                "exportedBy" : this.exportedBy,
                "exportedOn" : this.exportedOn,
                "orgId" : this.orgId,
                "prompts" : promptsToBeExported,
                "connections" : connections,
                "dataExtractionMappings" : mappings,
                "securityFilters" : this.filters,
                "dataSources" : dataSources
            };
            var fileName = "Prompts - "+this.exportedOn+".json";
            const blob = new Blob([JSON.stringify(obj)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = fileName || 'download';
            a.click();
            a.remove();
        }else{
            alert('No Prompts to Export.');
        }
    }

    handleNavigateToListView(){
        this.dispatchEvent(new CustomEvent(
            'closechild', 
            {
                detail: true,
                bubbles: true,
                composed: true,
            }
        ));
    }
}