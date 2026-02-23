import { LightningElement, api, track } from 'lwc';
export default class AIGlobalSecurityLayerExportComponent extends LightningElement {

    @track showSpinner = false;
    @api parentsecuritylayers;
    @api isImport = false;
    @track securitylayers;
    @track allSecurityLayersSelected = false;
    @track parentSelectedSecuritylayers;

    get hasRecords(){
        return (this.securitylayers && this.securitylayers.length>0);
    }

    connectedCallback(){
        if(this.parentsecuritylayers && !this.isImport){
            var tempSecurityLayers = [];
            Object.values(this.parentsecuritylayers).forEach(function(elementArr) {
                tempSecurityLayers = tempSecurityLayers.concat(elementArr)
            });
            this.securitylayers = tempSecurityLayers;
        }else if(this.parentsecuritylayers){
            this.securitylayers = JSON.parse(JSON.stringify(this.parentsecuritylayers));
        }
        if(this.parentSelectedSecuritylayers){
            this.handleSelectSecurityLayers(this.parentSelectedSecuritylayers);
        }
    }

    @api get selectedSecurityLayers(){
        return this.parentSelectedSecurityLayers;
    }

    set selectedSecurityLayers(value){
        this.setAttribute('selectedSecurityLayers', value);
        this.parentSelectedSecurityLayers = value;
        setTimeout(() => {
            this.handleSelectSecurityLayers(value);
        }, 1000);
    }

    handleSelectSecurityLayers(promptSecurityLayers){
        this.allSecurityLayersSelected = false;
        if(this.securitylayers &&  this.securitylayers.length > 0){
            var filterIds = [];
            for(let elem of promptSecurityLayers){
                filterIds.push(elem.salesforceId);
            }
            for(var i = 0; i < this.securitylayers.length; i++){
                let isSelected = false;
                if(filterIds.includes(this.securitylayers[i].salesforceId)){
                    isSelected = true;
                }
                this.securitylayers[i] = {...this.securitylayers[i], "selected": isSelected };
            }
            var selectedsecuritylayers = this.securitylayers.filter(element => element.selected);
            if(selectedsecuritylayers && selectedsecuritylayers.length == this.securitylayers.length){
                this.allSecurityLayersSelected = true;
            }
        }
    }

    handleAllPromptSelect(event){
        this.allSecurityLayersSelected = event.target.checked;
        for(var i = 0; i < this.securitylayers.length; i++){
            this.securitylayers[i] = {...this.securitylayers[i], "selected": event.target.checked };
        }
        var selectedsecuritylayers = this.securitylayers.filter(element => element.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : selectedsecuritylayers
        }}));
    }

    handlePromptSelect(event){
        var mIndex = event.target.dataset.mid;
        let val = event.target.checked;
        this.securitylayers[mIndex] = {...this.securitylayers[mIndex], "selected": val };
        this.allSecurityLayersSelected = false;
        var selectedsecuritylayers = [];
        for(var pmt of this.securitylayers){
            if(pmt.selected){
                selectedsecuritylayers.push(pmt);
            }
        }
        if(selectedsecuritylayers && selectedsecuritylayers.length == this.securitylayers.length){
            this.allSecurityLayersSelected = true;
        }
       var selectedsecuritylayers = this.securitylayers.filter(element => element.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : selectedsecuritylayers
        }}));
    }

    handleRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempData = JSON.parse(JSON.stringify(this.securitylayers));
        tempData.splice(mIndex, 1);
        this.securitylayers = JSON.parse(JSON.stringify(tempData));
        this.dispatchEvent(new CustomEvent('remove' , {detail : {
            value : this.securitylayers
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