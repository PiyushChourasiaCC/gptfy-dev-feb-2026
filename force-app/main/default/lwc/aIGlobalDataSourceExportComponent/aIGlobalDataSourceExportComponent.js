import { LightningElement, api, track } from 'lwc';
export default class AIGlobalDataSourceExportComponent extends LightningElement {

    @track showSpinner = false;
    @api parentdatasource;
    @api isImport = false;
    @track datasource;
    @track allDataSourceSelected = false;
    @track parentSelectedDatasource;

    get hasRecords(){
        return (this.datasource && this.datasource.length>0);
    }

    @api get selectedDatasource(){
        return this.parentSelectedDatasource;
    }

    set selectedDatasource(value){
        this.setAttribute('selectedDatasource', value);
        this.parentSelectedDatasource = value;
        this.handleSelectDatasource(value);
    }

    connectedCallback(){
        if(this.parentdatasource){
            this.datasource = JSON.parse(JSON.stringify(Object.values(this.parentdatasource)));
        }
        if(this.parentSelectedDatasource){
            this.handleSelectDatasource(this.parentSelectedDatasource);
        }
    }

    handleSelectDatasource(promptDatasource){
        this.allDataSourceSelected = false;
        if(this.datasource && this.datasource.length > 0){
            var datasourceIds = [];
            for(let elem of promptDatasource){
                datasourceIds.push(elem.salesforceId);
            }
            for(var i = 0; i < this.datasource.length; i++){
                let isSelected = false;
                if(datasourceIds.includes(this.datasource[i].salesforceId)){
                    isSelected = true;
                }
                this.datasource[i] = {...this.datasource[i], "selected": isSelected };
            }
            var selecteddatasource = this.datasource.filter(prompt => prompt.selected);
            if(selecteddatasource && selecteddatasource.length == this.datasource.length){
                this.allDataSourceSelected = true;
            }
        }
    }

    handleAllPromptSelect(event){
        this.allDataSourceSelected = event.target.checked;
        for(var i = 0; i < this.datasource.length; i++){
            this.datasource[i]['selected'] = event.target.checked;
        }
        var selecteddatasource = this.datasource.filter(prompt => prompt.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : selecteddatasource
        }}));
    }

    handlePromptSelect(event){
        var mIndex = event.target.dataset.mid;
        //alert(mIndex);
        this.datasource[mIndex]['selected'] = event.target.checked;

        this.allDataSourceSelected = false;
        var selecteddatasource = [];
        for(var pmt of this.datasource){
            if(pmt.selected){
                selecteddatasource.push(pmt);
            }
        }
        if(selecteddatasource && selecteddatasource.length == this.datasource.length){
            this.allDataSourceSelected = true;
        }
        var selecteddatasource = this.datasource.filter(prompt => prompt.selected);
        this.dispatchEvent(new CustomEvent('select' , {detail : {
            value : selecteddatasource
        }}));
    }

    handleRemove(event){
        var mIndex = event.target.dataset.mid;
        var tempData = JSON.parse(JSON.stringify(this.datasource));
        tempData.splice(mIndex, 1);
        this.datasource = JSON.parse(JSON.stringify(tempData));
        this.dispatchEvent(new CustomEvent('remove' , {detail : {
            value : this.datasource
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