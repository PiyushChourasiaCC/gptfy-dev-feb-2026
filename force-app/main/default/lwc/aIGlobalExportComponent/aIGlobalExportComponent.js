import { LightningElement, api, track } from 'lwc';
import getInitData from '@salesforce/apex/AIGlobalExportImportController.getInitData';

export default class AIGlobalExportComponent extends LightningElement {

    @track showSpinner = true;
    @track exportedOn;
    @track orgId;
    @track exportedBy;

    @api prompts;
    @api mappings;
    @api connections;
    @api filters;
    @api apiSources = [];
    @api cardConfigs;

    selectedprompts = [];
    selectedmappings = [];
    selectedconnections = [];
    selectedfilters = [];
    selectedapiSources = [];
    selectedcardConfigs = [];

    connectedCallback(){
       this.getData();
    }

    async getData(){
        this.showSpinner = true;
        this.prompts = undefined;
        this.mappings = undefined;
        this.connections = undefined;
        this.exportedOn = undefined;
        this.orgId = undefined;
        this.exportedBy = undefined;
        this.filters = undefined;
        this.dataSources = undefined;
        this.cardConfigs = undefined;
        await getInitData()
        .then(result => {      
            if(result && result.prompts && result.prompts.length > 0){
                this.prompts = JSON.parse(JSON.stringify(result.prompts)); 
                this.promptsMap = this.getMappedPromptsById(); 
                this.mappings = JSON.parse(JSON.stringify(result.dataExtractionMappings));  
                this.connections = JSON.parse(JSON.stringify(result.connections));
                if(result.securityFilters){
                    this.filters = JSON.parse(JSON.stringify(result.securityFilters));
                }
                if(result.dataSources && result.dataSources.length > 0){
                    this.apiSources = JSON.parse(JSON.stringify(result.dataSources));
                }
                this.cardConfigs = JSON.parse(JSON.stringify(result.cardConfigs));
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
    getMappedPromptsById(){
        let promptsMap = new Map();
        if(this.prompts){
            for(var pmt of this.prompts){
                promptsMap.set(pmt.salesforceId, pmt);
            }
            return promptsMap;
        }
        return [];
    }
    handleSelectPrompt(event){
        var eventData = event.detail.value;
        this.selectedprompts = eventData.data;
        this.handleSelectDependentConnections(eventData);
        this.handleSelectDependentMappingDataSourceAndFilters(eventData);
        this.handleSelectDependentCardCatalogs(eventData);
        console.log('eventData', eventData);
    }

    handleSelectDependentConnections(eventData){
        var tempSelectedconnections = [];
        if(this.connections && eventData.connectionIds && eventData.connectionIds.length > 0){
            let tempConnections = JSON.parse(JSON.stringify(Object.values(this.connections)));
            for(let tempconn of tempConnections){
                if(eventData.connectionIds.includes(tempconn.salesforceId)){
                    tempSelectedconnections.push(tempconn);
                }
            }
        }
        if(this.selectedconnections && this.selectedconnections.length > 0){
            for(var tempConn of this.selectedconnections){
                if(eventData.removedConnectionIds && eventData.removedConnectionIds.length > 0 && !eventData.removedConnectionIds.includes(tempConn.salesforceId)){
                    tempSelectedconnections.push(tempConn);
                }else if(eventData.connectionIds && eventData.connectionIds.length > 0 && !eventData.connectionIds.includes(tempConn.salesforceId)){
                    tempSelectedconnections.push(tempConn);
                }
            }
        }
        this.selectedconnections = tempSelectedconnections;
    }

    handleSelectDependentCardCatalogs(eventData){
        var tempSelectedCardCatalogs = [];
        var selectedPurposes = [];
        var selectedPrompts = eventData.data;

        if(this.cardConfigs){
            let tempCardConfigs = JSON.parse(JSON.stringify(Object.values(this.cardConfigs)));

            for(var prompt of selectedPrompts){
                if(prompt.purpose && prompt.purpose.length > 0){
                    for(var purpose of prompt.purpose.split(';')){
                            for(let tempCardConfig of tempCardConfigs){
                                if(tempCardConfig.configName === purpose){
                                    tempSelectedCardCatalogs.push(tempCardConfig);
                                    selectedPurposes.push(purpose);
                                }
                            }
                    }
                }
        }
    }
    console.log('selectedPurposes', selectedPurposes);
    console.log('tempSelectedCardCatalogs', tempSelectedCardCatalogs);
    console.log('this.selectedcardConfigs', this.selectedcardConfigs);
    console.log('selectedPrompts', selectedPrompts);

        // Preserve previously selected catalog cards that aren't being removed
        if(this.selectedcardConfigs && this.selectedcardConfigs.length > 0){
            for(let existingCard of this.selectedcardConfigs){
                if(!selectedPurposes.includes(existingCard.configName)){
                    tempSelectedCardCatalogs.push(existingCard);
                }
            }
        }

        this.selectedcardConfigs = tempSelectedCardCatalogs;

        // Update the cardConfigs to reflect selection state visually
        if(this.cardConfigs){
            let allCardConfigs = Object.values(this.cardConfigs);
            for(let card of allCardConfigs){
                card.selected = tempSelectedCardCatalogs.some(selected => selected.salesforceId === card.salesforceId);
            }
        }
    }

    handleSelectDependentMappingDataSourceAndFilters(eventData){
        var tempSelectedmappings = [];
        var dataSourceIds = [];
        var removedDataSourceIds = [];
        var filterIds = [];
        var removeFilterIds = [];

        if(this.mappings && eventData.extractionMappingIds && eventData.extractionMappingIds.length > 0){
            let tempMappings = JSON.parse(JSON.stringify(Object.values(this.mappings)));
            for(let tempmapp of tempMappings){
                if(eventData.extractionMappingIds.includes(tempmapp.salesforceId)){
                    tempSelectedmappings.push(tempmapp);
                    if(tempmapp.dataSourceId && !dataSourceIds.includes(tempmapp.dataSourceId)){
                        dataSourceIds.push(tempmapp.dataSourceId);
                    }
                    if(tempmapp.apexSecurityLayerId && !filterIds.includes(tempmapp.apexSecurityLayerId)){
                        filterIds.push(tempmapp.apexSecurityLayerId);
                    }
                }
                if(eventData.removedExtractionMappingIds && eventData.removedExtractionMappingIds.includes(tempmapp.salesforceId)){
                    if(tempmapp.dataSourceId && !removedDataSourceIds.includes(tempmapp.dataSourceId)){
                        removedDataSourceIds.push(tempmapp.dataSourceId);
                    }
                    if(tempmapp.apexSecurityLayerId && !removeFilterIds.includes(tempmapp.apexSecurityLayerId)){
                        removeFilterIds.push(tempmapp.apexSecurityLayerId);
                    }
                }
            }
        }
        if(this.selectedmappings && this.selectedmappings.length > 0){
           for(var tempmapp of this.selectedmappings){
                if(eventData.removedExtractionMappingIds && eventData.removedExtractionMappingIds.length > 0 && !eventData.removedExtractionMappingIds.includes(tempmapp.salesforceId)){
                    tempSelectedmappings.push(tempmapp);
                    if(tempmapp.dataSourceId && !dataSourceIds.includes(tempmapp.dataSourceId)){
                        dataSourceIds.push(tempmapp.dataSourceId);
                    }
                    if(tempmapp.apexSecurityLayerId && !filterIds.includes(tempmapp.apexSecurityLayerId)){
                        filterIds.push(tempmapp.apexSecurityLayerId);
                    }
                }else if(eventData.extractionMappingIds && eventData.extractionMappingIds.length > 0 && !eventData.extractionMappingIds.includes(tempmapp.salesforceId)){
                    tempSelectedmappings.push(tempmapp);
                    if(tempmapp.dataSourceId && !dataSourceIds.includes(tempmapp.dataSourceId)){
                        dataSourceIds.push(tempmapp.dataSourceId);
                    }
                    if(tempmapp.apexSecurityLayerId && !filterIds.includes(tempmapp.apexSecurityLayerId)){
                        filterIds.push(tempmapp.apexSecurityLayerId);
                    }
                }
                if(eventData.removedExtractionMappingIds && eventData.removedExtractionMappingIds.includes(tempmapp.salesforceId)){
                    if(tempmapp.dataSourceId && !removedDataSourceIds.includes(tempmapp.dataSourceId)){
                        removedDataSourceIds.push(tempmapp.dataSourceId);
                    }
                    if(tempmapp.apexSecurityLayerId && !removeFilterIds.includes(tempmapp.apexSecurityLayerId)){
                        removeFilterIds.push(tempmapp.apexSecurityLayerId);
                    }
                }
            }
        }
        var tempApiDataSources = [];
        if(dataSourceIds && dataSourceIds.length > 0){
            let tempApiSources = JSON.parse(JSON.stringify(Object.values(this.apiSources)));
            for(let tempsource of tempApiSources){
                if(dataSourceIds.includes(tempsource.salesforceId) && !removedDataSourceIds.includes(tempsource.salesforceId)){
                    tempApiDataSources.push(tempsource);
                }
            }
        }
        if(this.selectedapiSources && this.selectedapiSources.length > 0){
            for(let tempsource of this.selectedapiSources){
                if(!dataSourceIds.includes(tempsource.salesforceId) && !removedDataSourceIds.includes(tempsource.salesforceId)){
                    tempApiDataSources.push(tempsource);
                }
            }
        }
        var tempFilters = [];
        if(filterIds && filterIds.length > 0){
            var tempfiltersdata = [];
            Object.values(this.filters).forEach(function(elementArr) {
                tempfiltersdata = tempfiltersdata.concat(elementArr)
            });
            for(let tempfilter of tempfiltersdata){
                if(filterIds.includes(tempfilter.salesforceId) && !removeFilterIds.includes(tempfilter.salesforceId)){
                    tempFilters.push(tempfilter);
                }
            }
        }
        if(this.selectedfilters && this.selectedfilters.length > 0){
            for(let tempfilter of this.selectedfilters){
                if(!filterIds.includes(tempfilter.salesforceId) && !removeFilterIds.includes(tempfilter.salesforceId)){
                    tempFilters.push(tempfilter);
                }
            }
        }
        this.selectedmappings = tempSelectedmappings;
        this.selectedapiSources = tempApiDataSources;
        this.selectedfilters = tempFilters;
    }

    handleSelectConnections(event){
        this.selectedconnections = event.detail.value;
    }

    handleSelectMappings(event){
        this.selectedmappings = event.detail.value;
    }

    handleSelectFilters(event){
        this.selectedfilters = event.detail.value;
    }

    handleSelectApiSources(event){
        this.selectedapiSources = event.detail.value;
    }

    handleSelectCardConfigs(event){
        this.selectedcardConfigs = event.detail.value;
    }

    downloadExportFile(event){
        var obj = {
            "exportedBy" : this.exportedBy,
            "exportedOn" : this.exportedOn,
            "orgId" : this.orgId,
            "prompts" : this.selectedprompts,
            "connections" : this.selectedconnections,
            "dataExtractionMappings" : this.selectedmappings,
            "securityFilters" : this.selectedfilters,
            "dataSources" : this.selectedapiSources,
            "catalogCards" : this.selectedcardConfigs
        };
        var fileName = "Global Export - "+this.exportedOn+".json";
        const blob = new Blob([JSON.stringify(obj)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = fileName || 'download';
        a.click();
        a.remove();
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
    get disableDownlaod(){
        return (this.selectedprompts.length === 0 && this.selectedmappings.length === 0 && this.selectedfilters.length === 0 && 
                this.selectedapiSources.length === 0 && this.selectedcardConfigs.length === 0 && this.selectedconnections.length === 0);
    }
    handleReset(){
        this.selectedprompts = [];
        this.selectedmappings = [];
        this.selectedconnections = [];
        this.selectedfilters = [];
        this.selectedapiSources = [];
        this.selectedcardConfigs = [];
        this.getData();
    }
}