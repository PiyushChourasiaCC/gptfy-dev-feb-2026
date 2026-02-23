import { LightningElement, api, track } from 'lwc';

export default class AIGlobalConnectionExportComponent extends LightningElement {

    @track showSpinner = false;
    @api parentconnections;
    @track parentSelectedConnections;
    @track connections;
    @api isImport = false;
    @track allConnectionsSelected = false;

    get hasRecords(){
        return (this.connections && this.connections.length>0);
    }

    connectedCallback(){
        if(this.parentconnections && !this.isImport){
            this.connections = JSON.parse(JSON.stringify(Object.values(this.parentconnections)));
        }else if(this.parentconnections){
            this.connections = JSON.parse(JSON.stringify(this.parentconnections));
        }
        if(this.parentSelectedConnections){
            this.handleSelectConnections(this.parentSelectedConnections);
        }
    }

    @api get selectedConnections(){
        return this.parentSelectedConnections;
    }

    set selectedConnections(value){
        this.setAttribute('selectedConnections', value);
        this.parentSelectedConnections = value;
        this.handleSelectConnections(value);
    }

    handleSelectConnections(promptConnections){
        this.allConnectionsSelected = false;
        if(this.connections && this.connections.length > 0){
            var connectionIds = [];
            for(let pconn of promptConnections){
                connectionIds.push(pconn.salesforceId);
            }
            for(var i = 0; i < this.connections.length; i++){
                let isSelected = false;
                if(connectionIds.includes(this.connections[i].salesforceId)){
                    isSelected = true;
                }
                this.connections[i]['selected'] = isSelected;
            }
            var selectedconnections = this.connections.filter(prompt => prompt.selected);
            if(selectedconnections && selectedconnections.length == this.connections.length){
                this.allConnectionsSelected = true;
            }
        }
    }

    handleAllPromptSelect(event){
        this.allConnectionsSelected = event.target.checked;
        for(var i = 0; i < this.connections.length; i++){
            this.connections[i]['selected'] = event.target.checked;
        }
        var selectedConnections = this.connections.filter(prompt => prompt.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : selectedConnections
        }}));
    }

    handlePromptSelect(event){
        var mIndex = event.target.dataset.mid;
        //alert(mIndex);
        this.connections[mIndex]['selected'] = event.target.checked;

        this.allConnectionsSelected = false;
        var selectedConnections = [];
        for(var pmt of this.connections){
            if(pmt.selected){
                selectedConnections.push(pmt);
            }
        }
        if(selectedConnections && selectedConnections.length == this.connections.length){
            this.allConnectionsSelected = true;
        }
        var selectedConnections = this.connections.filter(prompt => prompt.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : selectedConnections
        }}));
    }

    handleRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempData = JSON.parse(JSON.stringify(this.connections));
        tempData.splice(mIndex, 1);
        this.connections = JSON.parse(JSON.stringify(tempData));
        this.dispatchEvent(new CustomEvent('remove' , {detail : {
            value : this.connections
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