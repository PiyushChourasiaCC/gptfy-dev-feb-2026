import { LightningElement, api, track } from 'lwc';
export default class AIGlobalCatalogCardExportComponent extends LightningElement {

    @track showSpinner = false;
    @api parentcatalogcard;
    @track catalogcard;
    @api isImport = false;
    @track allCatalogCardSelected = false;
    _selectedCatalogCard = [];

    get hasRecords(){
        return (this.catalogcard && this.catalogcard.length>0);
    }

    connectedCallback(){
        if(this.parentcatalogcard && !this.isImport){
            this.catalogcard = JSON.parse(JSON.stringify(Object.values(this.parentcatalogcard)));
        }else if(this.parentcatalogcard){
            this.catalogcard = JSON.parse(JSON.stringify(this.parentcatalogcard));
        }
    }

    @api 
    get selectedCatalogCard(){
        return this._selectedCatalogCard;
    }

    set selectedCatalogCard(value){
        this._selectedCatalogCard = value || [];
        this.updateCatalogCardSelections();
    }

    updateCatalogCardSelections(){
        if(this.catalogcard && this.catalogcard.length > 0){
            const selectedIds = this._selectedCatalogCard.map(card => card.salesforceId);
            for(let i = 0; i < this.catalogcard.length; i++){
                this.catalogcard[i].selected = selectedIds.includes(this.catalogcard[i].salesforceId);
            }
            // Update allCatalogCardSelected flag
            const selectedCount = this.catalogcard.filter(card => card.selected).length;
            this.allCatalogCardSelected = (selectedCount === this.catalogcard.length && this.catalogcard.length > 0);
        }
    }

    handleAllPromptSelect(event){
        this.allCatalogCardSelected = event.target.checked;
        for(var i = 0; i < this.catalogcard.length; i++){
            this.catalogcard[i]['selected'] = event.target.checked;
        }
        var selectedcatalogcard = this.catalogcard.filter(element => element.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : selectedcatalogcard
        }}));
    }

    handlePromptSelect(event){
        var mIndex = event.target.dataset.mid;
        //alert(mIndex);
        this.catalogcard[mIndex]['selected'] = event.target.checked;

        this.allCatalogCardSelected = false;
        var selectedConnections = [];
        for(var pmt of this.catalogcard){
            if(pmt.selected){
                selectedConnections.push(pmt);
            }
        }
        if(selectedConnections && selectedConnections.length == this.catalogcard.length){
            this.allCatalogCardSelected = true;
        }
        var selectedcatalogcard = this.catalogcard.filter(element => element.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : selectedcatalogcard
        }}));
    }

    handleRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempData = JSON.parse(JSON.stringify(this.catalogcard));
        tempData.splice(mIndex, 1);
        this.catalogcard = JSON.parse(JSON.stringify(tempData));
        this.dispatchEvent(new CustomEvent('remove' , {detail : {
            value : this.catalogcard
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