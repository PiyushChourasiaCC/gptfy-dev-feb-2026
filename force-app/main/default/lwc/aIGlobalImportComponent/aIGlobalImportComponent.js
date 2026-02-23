import { LightningElement, track } from 'lwc';
import readFileData from '@salesforce/apex/AIGlobalExportImportController.readFileData';
import saveMappings from '@salesforce/apex/AIGlobalExportImportController.saveMappings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AIGlobalImportComponent extends LightningElement {

    @track showSpinner = false;
    mappings;
    @track prompts;
    @track fileName;
    @track data;
    @track dataFound = false;

    get uploadBtnDisabled(){
        let isDisabled = true;
        if(this.data && (this.data.prompts.length > 0 
                    || this.data.connections.length > 0 
                    || this.data.dataSources.length > 0 
                    || this.data.securityFilters.length > 0 
                    || this.data.catalogCards.length > 0)){
            isDisabled = false;
        }
        return isDisabled;
    }

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
            if(result && !result.hasError && result.data){
                this.dataFound = true;
                this.data = JSON.parse(JSON.stringify(result.data));
            }else if(result && result.hasError){
                alert(result.message);
                this.fileName = undefined;
                this.dataFound = false;
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
        this.dataFound = false;
        this.data = undefined;
        this.showSpinner = false;
    }

    handleRemovePrompt(event){
        this.data.prompts = event.detail.value;
    }

    handleRemoveConnections(event){
        this.data.connections = event.detail.value;
    }

    handleRemoveApiSources(event){
        this.data.dataSources = event.detail.value;
    }

    handleRemoveFilters(event){
        this.data.securityFilters = event.detail.value;
    }

    handleRemoveCardConfigs(event){
        this.data.catalogCards = event.detail.value;
    }

    async handleUpload(event){
        console.log('---handleUpload---'+JSON.stringify(this.data));
        this.showSpinner = true;
        await saveMappings({
            prompts : this.data.prompts,
            connections : this.data.connections,
            mappings : this.data.dataExtractionMappings,
            filters : this.data.securityFilters,
            dataSources : this.data.dataSources,
            catalogCards : this.data.catalogCards,
            isPostInstall : false
        })
        .then(result => {        
            this.showToast('success', 'Success', 'Import completed successfully.');
            this.handleReset();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            //alert(error.body.message);
            this.showToast('error', 'Error', error.body.message);
        }else{
            //alert(error.toString());
            this.showToast('error', 'Error', error.toString());
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

}