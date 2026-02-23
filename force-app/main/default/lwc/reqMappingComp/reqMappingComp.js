import { LightningElement, track, api, wire } from 'lwc';
import AI_REQ_MAP_OBJ from '@salesforce/schema/Request_Mapping__c';
import AI_MODAL_FIELD from '@salesforce/schema/Request_Mapping__c.AI_Model__c';
import DESCRIPTION_FIELD from '@salesforce/schema/Request_Mapping__c.Description__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import findRecords from "@salesforce/apex/reqMappingController.getRecords";
import createRequestMapping from "@salesforce/apex/reqMappingController.createRequestMapping";
export default class ReqMappingComp extends LightningElement {
    showSpinner = false;
    

    @api iconName = 'standard:bill_of_materials';
    @api selectedValue;
    @api lookupLabel;
    @api selectedRecordId;
    @api name;

    @track openModal = true;
    @track value = 'Prompt';
    @track roleVal = '';

    @track searchKey = "";
    @track recordsList;
    @track message;

    @track isNewRecord = false;

    @track selectedRecordList = [];

    @track reqMapObj = AI_REQ_MAP_OBJ;
    @track aiModalField = AI_MODAL_FIELD;
    @track descField = DESCRIPTION_FIELD;
    

    rowId = 2;
    @track rows = [{
        'id': 0, 'dataSource': '', 'userRole': '', 'sequence': '1', 'annotation': '', dataSourceOption: [
            { label: '--None--', value: '' },
            { label: 'Prompt', value: 'Prompt' },
            { label: 'Data Context', value: 'Data Context' },
            { label: 'Files', value: 'Files' },
            /*{ label: 'Grounding', value: 'Grounding' },
            { label: 'GPTfy Console Input Field', value: 'GPTfy Console Input Field' },*/
        ]
    }];

    get roleOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'System', value: 'System' },
            { label: 'Agent', value: 'Agent' },
            { label: 'User', value: 'User' },
        ];
    }

    @track dataSource = '';
    @track userRole = '';
    @track sequence = '';
    @track annotation = '';

    @track selectedDataSource = [];

    /**=============================================*/
    @track promptInput = '';
    @track dataContextInput = '';
    @track fileInput = '';
    @track groundingInput = '';
    @track gptConsoleInput = '';

    @track systemRequestInput = '';
    @track agentRequestInput = '';
    /**=============================================*/

    handlePromptInputChange(event) {
        this.promptInput = event.detail.value;
    }

    handleDataContextInputChange(event) {
        this.dataContextInput = event.detail.value;
    }

    handleFileInputChange(event) {
        this.fileInput = event.detail.value;
    }

    handleGroundingInputChange(event) {
        this.groundingInput = event.detail.value;
    }

    handleConsoleInputChange(event) {
        this.gptConsoleInput = event.detail.value;
    }

    handleChange(event) {
        this.rows[event.target.name].dataSource = event.detail.value;
        this.rows[event.target.name].annotation = '[' + event.detail.value.toUpperCase() + ']';
    }

    handleRoleChange(event) {
        if (this.openModal) {
            this.rows[event.target.name].userRole = event.detail.value;
        }
    }

    handleSequenceChange(event) {
        if (this.openModal) {
            this.rows[event.target.name].sequence = parseInt(event.detail.value);
        }
    }

    handleAnnotationChange(event) {
        if (this.openModal) {
            this.rows[event.target.name].annotation = event.detail.value;
        }
    }

    handleAddRow() {
        if (this.rows.length < 5) {
            let rown = this.rowId++;
            const newRow = {
                id: rown - 1,
                dataSource: '',
                userRole: '',
                sequence: rown,
                annotation: '',
                dataSourceOption: [
                    { label: '--None--', value: '' },
                    { label: 'Prompt', value: 'Prompt' },
                    { label: 'Data Context', value: 'Data Context' },
                    { label: 'Files', value: 'Files' },
                    { label: 'Grounding', value: 'Grounding' },
                    { label: 'GPTfy Console Input Field', value: 'GPTfy Console Input Field' },
                ]
            };
            this.rows = [...this.rows, newRow];
        }
    }


    handleRemoveRow(event) {
        if (this.rows.length > 1) {
            const rowId = event.target.name;
            let index = this.selectedDataSource.indexOf(this.rows[rowId].dataSource);
            if (index > -1) {
                this.selectedDataSource.splice(index, 1);
            }
            // Remove the row with the specified ID
            this.rows = this.rows.filter(row => row.id !== rowId);
            this.rows = this.rows.map((row, index) => ({ ...row, id: index + 1 }));
        }
    }

    generateRequest(event) {
        try {
            const groupedAndSortedData = this.rows.reduce((acc, item) => {
                const { userRole, sequence } = item;
                if (!acc[userRole]) {
                    acc[userRole] = [];
                }
                acc[userRole].push(item);
                acc[userRole].sort((a, b) => a.sequence - b.sequence); // Sort by sequence
                return acc;
            }, {});
            let extractInputData = this.extractInputData(groupedAndSortedData);
            this.systemRequestInput = extractInputData['systemRequestInput'];
            this.agentRequestInput = extractInputData['agentRequestInput'];
        } catch (e) {
            console.log(e);
        }
    }

    extractInputData(groupedAndSortedData) {
        // Initialize the variables to store the result
        let systemRequestInput = '';
        let agentRequestInput = '';

        // Define mapping for dataSource to input variable
        const dataSourceToInputMapping = {
            'Prompt': this.promptInput,
            'Data Context': this.dataContextInput, // You didn't provide the corresponding variable for Data Context, replace with the actual variable
            'Files': this.fileInput,
            'Grounding': this.groundingInput,
            'GPTfy Console Input Field': this.gptConsoleInput
        };

        // Extract data for System group
        if (groupedAndSortedData.System) {
            groupedAndSortedData.System.forEach(item => {
                const { dataSource, annotation } = item;
                const inputVariable = dataSourceToInputMapping[dataSource];
                systemRequestInput += `${annotation}\n${inputVariable}\n\n`;
            });
        }

        // Extract data for Agent group
        if (groupedAndSortedData.Agent) {
            groupedAndSortedData.Agent.forEach(item => {
                const { dataSource, annotation } = item;
                const inputVariable = dataSourceToInputMapping[dataSource];
                agentRequestInput += `${annotation}\n${inputVariable}\n\n`;
            });
        }

        // Extract data for Agent group
        if (groupedAndSortedData.User) {
            groupedAndSortedData.User.forEach(item => {
                const { dataSource, annotation } = item;
                const inputVariable = dataSourceToInputMapping[dataSource];
                agentRequestInput += `${annotation}\n${inputVariable}\n\n`;
            });
        }

        return { systemRequestInput, agentRequestInput };
    }

    handleSave(event) {
        let isValid = true;
        let obj = {}
        let mFields = [];
        const inputFields = this.template.querySelectorAll('.field-input');
        if (inputFields) {
            inputFields.forEach(element => {
                if (element.required && !element.value) {
                    element.reportValidity();
                    isValid = false;
                } else {
                    obj[element.name] = element.value;
                    if (element.name != 'label' && element.name != 'name') {
                        mFields.push(element.name);
                    }
                }
            });
        }
        if (!isValid) {
            this.showToast('error', 'Error', 'Please fill required fields and try again.');
        } else if (isValid) {
            this.showSpinner = true;
            let hasReqMapping = false;
            let reqMapping = {};
            let reqLineMapping = [];
            reqMapping['reqName'] = this.template.querySelector('.name-input').value;
            reqMapping['AI_Model__c'] = this.template.querySelector('.modal-input').value;
            reqMapping['Description__c'] = this.template.querySelector('.desc-input').value;
            for (let i = 0; i < this.rows.length; i++) {
                let tempMap = {}
                tempMap['dataSource'] = this.rows[i].dataSource;
                tempMap['userRole'] = this.rows[i].userRole;
                tempMap['sequence'] = this.rows[i].sequence;
                tempMap['annotation'] = this.rows[i].annotation;

                reqLineMapping.push(tempMap);
            }
            createRequestMapping({ 'mapReqParams': reqMapping, 'mapReqLineParams': reqLineMapping })
                .then((result) => {
                    this.selectedRecordList = {Id:result[0].Request_Mapping__c, name:this.template.querySelector('.name-input').value};
                    this.onSeletedRecordUpdate();
                    this.createNewRecord();
                    this.showSpinner = false;
                })
                .catch((error) => {
                    this.showSpinner = false;
                    console.log('error key : ' + JSON.stringify(error));
                    this.showToast('error', 'Error', error.body.message);
                });
        }
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant: variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    removeRecordOnLookup(event) {
        this.searchKey = "";
        this.selectedValue = null;
        this.recordsList = null;
        //this.onSeletedRecordUpdate();
    }

    onLeave(event) {
        setTimeout(() => {
            this.searchKey = "";
            this.recordsList = null;
        }, 300);
    }

    handleKeyChange(event) {
        const searchKey = event.target.value;
        this.searchKey = searchKey;
        this.getLookupResult();
    }

    onRecordSelection(event) {
        this.selectedRecordId = event.target.dataset.key;
        this.selectedValue = event.target.dataset.name;
        this.recordsList.forEach(element => {
            if (element.Id == event.target.dataset.key) {
                this.selectedRecordList = {Id:this.selectedRecordId, name:this.selectedValue};
            }
        });
        this.searchKey = "";
        this.onSeletedRecordUpdate();
    }

    createNewRecord() {
        this.isNewRecord = !this.isNewRecord;
    }

    onSeletedRecordUpdate() {
        const passEventr = new CustomEvent('select', {
            detail: { record: this.selectedRecordList, sectionName: this.name }
        });
        this.dispatchEvent(passEventr);
    }

    getLookupResult() {
        findRecords({searchTerm: this.searchKey })
            .then((result) => {
                if (result.length === 0) {
                    this.recordsList = [];
                    this.message = "No Records Found";
                } else {
                    this.recordsList = result;
                    this.message = "";
                }
                this.error = undefined;
            })
            .catch((error) => {
                console.log('error key : ' + JSON.stringify(error));
                this.error = error;
                this.recordsList = undefined;
            });
    }
}