import { LightningElement, track } from 'lwc';

import readFileData from '@salesforce/apex/AICardConfigurationExportController.readFileData';
import saveCards from '@salesforce/apex/AICardConfigurationExportController.saveCards';

export default class AICardConfigurationImportComponent extends LightningElement {

    @track showSpinner = false;

    @track cards;
    @track fileName;
    @track data;

    handleFileInputChange(event){
        this.cards = undefined;
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
            if(result && !result.hasError && result.data && result.data.cardConfigs && result.data.cardConfigs.length > 0){
                this.data = JSON.parse(JSON.stringify(result.data));
                this.cards = JSON.parse(JSON.stringify(result.data.cardConfigs));
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
        this.cards = undefined;
        this.fileName = undefined;
    }

    handleMasterRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempMapping = JSON.parse(JSON.stringify(this.cards));
        tempMapping.splice(mIndex, 1);
        this.cards = JSON.parse(JSON.stringify(tempMapping));
    }

    handleUpload(){
        if(this.cards && this.cards.length > 0){
            this.insertMappings();
        }else{
            alert('No Cards to Insert.');
        }
    }

    async insertMappings(){
        this.showSpinner = true;
        await saveCards({
            cards : this.cards,
            isPostInstall : false
        })
        .then(result => {        
            alert('Cards Imported.');
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