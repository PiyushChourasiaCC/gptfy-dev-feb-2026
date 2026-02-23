import { LightningElement, track } from 'lwc';

import getMappings from '@salesforce/apex/AICardConfigurationExportController.getMappings';

export default class AICardConfigurationExportComponent extends LightningElement {

    @track showSpinner = false;
    @track exportedOn;
    @track orgId;
    @track exportedBy;

    @track cards;

    connectedCallback(){
        this.getExportData();
    }

    async getExportData(){
        this.showSpinner = true;
        this.cards = undefined;
        this.exportedOn = undefined;
        this.orgId = undefined;
        this.exportedBy = undefined;
        await getMappings()
        .then(result => {      
            if(result && result.cardConfigs && result.cardConfigs.length > 0){
                this.cards = JSON.parse(JSON.stringify(result.cardConfigs));  
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

    handlePromptRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempMapping = JSON.parse(JSON.stringify(this.cards));
        tempMapping.splice(mIndex, 1);
        this.cards = JSON.parse(JSON.stringify(tempMapping));
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

    downloadExportFile(){
        if(this.cards && this.cards.length > 0){
            var obj = {
                "exportedBy" : this.exportedBy,
                "exportedOn" : this.exportedOn,
                "orgId" : this.orgId,
                "cardConfigs" : this.cards
            };
            var fileName = "Cards - "+this.exportedOn+".json";
            const blob = new Blob([JSON.stringify(obj)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = fileName || 'download';
            a.click();
            a.remove();
        }else{
            alert('No Cards to Export.');
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