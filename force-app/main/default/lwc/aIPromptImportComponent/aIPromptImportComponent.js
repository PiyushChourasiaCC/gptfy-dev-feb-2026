import { LightningElement, track } from 'lwc';

import readFileData from '@salesforce/apex/AIPromptImportController.readFileData';
import saveMappings from '@salesforce/apex/AIPromptImportController.saveMappings';

export default class AIPromptImportComponent extends LightningElement {

    @track showSpinner = false;

    @track prompts;
    @track fileName;
    @track data;

    handleFileInputChange(event){
        this.prompts = undefined;
        this.fileName = undefined;
        if(event.target.files.length > 0){
            var file = event.target.files[0];
            this.fileName = file.name;
            var fileReader = new FileReader();
            var txt = fileReader.readAsText(file);
            fileReader.onloadend = (() => {
                var fileData = fileReader.result;
                this.readUploadedFile(fileData);
            });
        }
    }

    async readUploadedFile(fileData){
        this.showSpinner = true;
        await readFileData({
            fileData : fileData
        })
        .then(result => {       
            if(result && !result.hasError && result.data && result.data.prompts && result.data.prompts.length > 0){
                this.data = JSON.parse(JSON.stringify(result.data));
                this.prompts = JSON.parse(JSON.stringify(result.data.prompts));
            }else if(result && result.hasError){
                alert(result.message);
                this.fileName = undefined;
            }
            this.showSpinner = false;
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleReset(){
        this.prompts = undefined;
        this.fileName = undefined;
    }

    handleMasterRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempMapping = JSON.parse(JSON.stringify(this.prompts));
        tempMapping.splice(mIndex, 1);
        this.prompts = JSON.parse(JSON.stringify(tempMapping));
    }

    handleUpload(){
        if(this.prompts && this.prompts.length > 0){
            this.insertMappings();
        }else{
            alert('No Prompts to Insert.');
        }
    }

    async insertMappings(){
        this.showSpinner = true;

        var mappings = [];
        var mappingIds = [];
        var connections = [];
        var connectionIds = [];

        var filters = [];

        for(var pmt of this.prompts){
            if(!mappingIds.includes(pmt.extractionMappingId)){
                mappingIds.push(pmt.extractionMappingId);
                mappings.push(this.data.dataExtractionMappings[pmt.extractionMappingId]);
            }
        }

        for(var pmt of this.prompts){
            if(!connectionIds.includes(pmt.connectionId)){
                connectionIds.push(pmt.connectionId);
                connections.push(this.data.connections[pmt.connectionId]);
            }
        }
        
        if(this.data.securityFilters.hasOwnProperty('Regex')){
            for(let i = 0; i < this.data.securityFilters.Regex.length; i++){
                filters.push(this.data.securityFilters.Regex[i]);
            }
        }
        if(this.data.securityFilters.hasOwnProperty('Blocklist')){
            for(let i = 0; i < this.data.securityFilters.Blocklist.length; i++){
                filters.push(this.data.securityFilters.Blocklist[i]);
            }
        }

        await saveMappings({
            prompts : this.prompts,
            connections : connections,
            mappings : mappings,
            filters : filters,
            dataSources : this.data.dataSources,
            isPostInstall : false
        })
        .then(result => {        
            alert('Prompts Imported.');
            this.handleNavigateToListView();
        })
        .catch(error => {
            this.handleError(error);
        });
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