/**
 * @description AI Agent Intent Action Form — modal component for add/edit of AI_Intent_Action__c.
 *   Renders different field sets based on Action_Type__c.
 * @author  Sagar Alwani
 * @jira    V2-7338
 */
import { LightningElement, api, track } from 'lwc';

import upsertAction from '@salesforce/apex/AIAgentIntentController.upsertAction';
import getObjectOptions from '@salesforce/apex/AIAgentIntentController.getObjectOptions';
import getFieldOptions from '@salesforce/apex/AIAgentIntentController.getFieldOptions';
import getFlows from '@salesforce/apex/AIAgentIntentController.getFlows';

export default class AIAgentIntentActionForm extends LightningElement {
    @api intentId;
    @api actionData = {};
    @api actionTypeOptions = [];
    @api apexReturnTypeOptions = [];
    @api languageOptions = [];

    @track action = {};
    @track isSaving = false;

    // Schema pickers
    @track objectOptions = [];
    @track fieldOptions = [];
    @track objectOptionsLoaded = false;
    @track flowOptions = [];
    @track flowOptionsLoaded = false;
    @track flowSearchTerm = '';
    @track showFlowDropdown = false;

    // ─── Lifecycle ─────────────────────────────────────────────

    _handleDocumentClick;

    connectedCallback() {
        // Deep clone incoming data
        this.action = this.actionData && this.actionData.id
            ? JSON.parse(JSON.stringify(this.actionData))
            : { isActive: false, language: 'en', fieldMappings: [] };

        // Ensure fieldMappings is always an array
        if (!this.action.fieldMappings) {
            this.action.fieldMappings = [];
        }

        // If action type needs object options, pre-load them
        if (this.needsObjectPicker) {
            this.loadObjectOptions();
        }

        // If editing an existing action with an objectName, pre-load field options
        if (this.action.objectName && (this.isUpdateFieldAction || this.isCreateRecordAction)) {
            this.loadFieldOptions(this.action.objectName);
        }

        // If action type is Flow, pre-load flow options
        if (this.isFlowAction) {
            this.loadFlows();
            // Set search term to the selected flow label if editing
            if (this.action.flowApiName) {
                this.flowSearchTerm = this.action.flowApiName;
            }
        }

        // Close flow dropdown on outside click
        this._handleDocumentClick = (evt) => {
            const combobox = this.template.querySelector('.slds-combobox_container');
            if (combobox && !combobox.contains(evt.target)) {
                this.showFlowDropdown = false;
            }
        };
        document.addEventListener('click', this._handleDocumentClick);
    }

    disconnectedCallback() {
        if (this._handleDocumentClick) {
            document.removeEventListener('click', this._handleDocumentClick);
        }
    }

    // ─── Computed: action type checks ──────────────────────────

    get isEditing() {
        return !!this.action.id;
    }

    get modalTitle() {
        return this.isEditing ? 'Edit Action' : 'Add Action';
    }

    get isCannedResponseAction() {
        return this.action.actionType === 'Canned Response';
    }

    get isUpdateFieldAction() {
        return this.action.actionType === 'Update Field';
    }

    get isCreateRecordAction() {
        return this.action.actionType === 'Create Record';
    }

    get isApexAction() {
        return this.action.actionType === 'Apex';
    }

    get isFlowAction() {
        return this.action.actionType === 'Flow';
    }

    get needsObjectPicker() {
        return this.isUpdateFieldAction || this.isCreateRecordAction;
    }

    get hasActionType() {
        return !!this.action.actionType;
    }

    get showTypeSpecificFields() {
        return this.hasActionType;
    }

    // ─── Filtered action type options (exclude Invoke Agent) ───

    get filteredActionTypeOptions() {
        // The controller already filters out Invoke Agent,
        // but belt-and-suspenders here too
        return (this.actionTypeOptions || []).filter(
            opt => opt.value !== 'Invoke Agent'
        );
    }

    // ─── Field change handlers ─────────────────────────────────

    handleTypeChange(event) {
        const newType = event.detail.value;
        // Reset type-specific fields when switching type
        this.action = {
            ...this.action,
            actionType: newType,
            objectName: null,
            fieldApiName: null,
            cannedResponse: null,
            language: newType === 'Canned Response' ? 'en' : this.action.language,
            apexClassName: null,
            apexReturnType: null,
            flowApiName: null,
            fieldMappings: []
        };

        this.fieldOptions = [];
        this.flowSearchTerm = '';
        this.showFlowDropdown = false;

        if (this.needsObjectPicker && !this.objectOptionsLoaded) {
            this.loadObjectOptions();
        }

        if (newType === 'Flow' && !this.flowOptionsLoaded) {
            this.loadFlows();
        }
    }

    handleDescriptionChange(event) {
        this.action = { ...this.action, description: event.target.value };
    }

    handleSequenceChange(event) {
        const val = event.target.value;
        this.action = { ...this.action, sequence: val ? parseInt(val, 10) : null };
    }

    handleActiveChange(event) {
        this.action = { ...this.action, isActive: event.target.checked };
    }

    // Canned Response
    handleLanguageChange(event) {
        this.action = { ...this.action, language: event.detail.value };
    }

    handleCannedResponseChange(event) {
        this.action = { ...this.action, cannedResponse: event.target.value };
    }

    // Update Field / Create Record
    handleObjectNameChange(event) {
        const objName = event.detail.value;
        this.action = { ...this.action, objectName: objName, fieldApiName: null };
        this.fieldOptions = [];
        if (objName) {
            this.loadFieldOptions(objName);
        }
        // Reset field mappings when object changes for Create Record
        if (this.isCreateRecordAction) {
            this.action = { ...this.action, fieldMappings: [] };
        }
    }

    handleFieldApiNameChange(event) {
        this.action = { ...this.action, fieldApiName: event.detail.value };
    }

    // ─── Field Mapping handlers (Create Record) ───────────────

    get mappingTypeOptions() {
        return [
            { label: 'Hardcoded', value: 'Hardcoded' },
            { label: 'AI Extracted', value: 'AI Extracted' }
        ];
    }

    get hasFieldMappings() {
        return this.action.fieldMappings && this.action.fieldMappings.length > 0;
    }

    get fieldMappingsWithIndex() {
        return (this.action.fieldMappings || []).map((m, idx) => ({
            ...m,
            _index: idx,
            _key: m.id || `new-${idx}`,
            _isHardcoded: m.type === 'Hardcoded'
        }));
    }

    handleAddFieldMapping() {
        const mappings = [...(this.action.fieldMappings || [])];
        mappings.push({
            id: null,
            fieldApiName: null,
            type: 'AI Extracted',
            value: '',
            sequence: mappings.length + 1
        });
        this.action = { ...this.action, fieldMappings: mappings };
    }

    handleRemoveFieldMapping(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const mappings = [...(this.action.fieldMappings || [])];
        mappings.splice(idx, 1);
        this.action = { ...this.action, fieldMappings: mappings };
    }

    handleMappingFieldChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const mappings = [...(this.action.fieldMappings || [])];
        mappings[idx] = { ...mappings[idx], fieldApiName: event.detail.value };
        this.action = { ...this.action, fieldMappings: mappings };
    }

    handleMappingTypeChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const mappings = [...(this.action.fieldMappings || [])];
        mappings[idx] = { ...mappings[idx], type: event.detail.value, value: '' };
        this.action = { ...this.action, fieldMappings: mappings };
    }

    handleMappingValueChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const mappings = [...(this.action.fieldMappings || [])];
        mappings[idx] = { ...mappings[idx], value: event.target.value };
        this.action = { ...this.action, fieldMappings: mappings };
    }

    // Apex
    handleApexClassChange(event) {
        this.action = { ...this.action, apexClassName: event.target.value };
    }

    handleApexReturnTypeChange(event) {
        this.action = { ...this.action, apexReturnType: event.detail.value };
    }

    // Flow — searchable picker
    handleFlowSearch(event) {
        this.flowSearchTerm = event.target.value;
        this.showFlowDropdown = true;
        // If user clears search, clear selection
        if (!this.flowSearchTerm) {
            this.action = { ...this.action, flowApiName: null };
        }
    }

    handleFlowInputFocus() {
        this.showFlowDropdown = true;
    }

    handleFlowSelect(event) {
        const value = event.currentTarget.dataset.value;
        const selected = this.flowOptions.find(opt => opt.value === value);
        if (selected) {
            this.action = { ...this.action, flowApiName: selected.value };
            this.flowSearchTerm = selected.label;
        }
        this.showFlowDropdown = false;
    }

    handleFlowDropdownClose() {
        // Delay to allow click events on dropdown items to fire first
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showFlowDropdown = false;
        }, 200);
    }

    get filteredFlowOptions() {
        const term = (this.flowSearchTerm || '').toLowerCase();
        return this.flowOptions
            .filter(opt => !term || opt.label.toLowerCase().includes(term) || opt.value.toLowerCase().includes(term))
            .map(opt => ({
                ...opt,
                itemClass: 'slds-media slds-listbox__option slds-listbox__option_plain slds-media_small' +
                    (opt.value === this.action.flowApiName ? ' slds-is-selected' : '')
            }));
    }

    get hasFilteredFlowOptions() {
        return this.filteredFlowOptions.length > 0;
    }

    get flowComboboxClass() {
        return 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click' +
            (this.showFlowDropdown ? ' slds-is-open' : '');
    }

    // ─── Schema loading ────────────────────────────────────────

    async loadObjectOptions() {
        try {
            const result = await getObjectOptions();
            this.objectOptions = (result || []).map(opt => ({
                label: opt.label,
                value: opt.value
            }));
            this.objectOptionsLoaded = true;
        } catch (error) {
            console.error('Error loading objects', error);
        }
    }

    async loadFieldOptions(objectName) {
        try {
            const result = await getFieldOptions({ objectName: objectName });
            this.fieldOptions = (result || []).map(opt => ({
                label: opt.label + ' (' + opt.value + ')',
                value: opt.value
            }));
        } catch (error) {
            console.error('Error loading fields', error);
            this.fieldOptions = [];
        }
    }

    async loadFlows() {
        try {
            const result = await getFlows();
            this.flowOptions = (result || []).map(opt => ({
                label: opt.label,
                value: opt.value
            }));
            this.flowOptionsLoaded = true;
            // If editing, set the search term to the selected flow's label
            if (this.action.flowApiName) {
                const match = this.flowOptions.find(o => o.value === this.action.flowApiName);
                if (match) {
                    this.flowSearchTerm = match.label;
                }
            }
        } catch (error) {
            console.error('Error loading flows', error);
            this.flowOptions = [];
        }
    }

    // ─── Save & Close ──────────────────────────────────────────

    async handleSave() {
        if (!this.validate()) {
            return;
        }

        this.isSaving = true;
        try {
            await upsertAction({
                actionJson: JSON.stringify(this.action),
                intentId: this.intentId
            });
            this.dispatchEvent(new CustomEvent('save'));
        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Save failed';
            // Use an alert here since we're in a modal and toasts may not show
            console.error('Error saving action', msg);
            // Bubble error up — parent handles toast
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ─── Validation ────────────────────────────────────────────

    validate() {
        if (!this.action.actionType) {
            this.setError('Action Type is required.');
            return false;
        }

        switch (this.action.actionType) {
            case 'Canned Response':
                if (!this.action.cannedResponse || this.action.cannedResponse.trim() === '') {
                    this.setError('Canned Response text is required.');
                    return false;
                }
                break;
            case 'Update Field':
                if (!this.action.objectName) {
                    this.setError('Object Name is required for Update Field.');
                    return false;
                }
                if (!this.action.fieldApiName) {
                    this.setError('Field API Name is required for Update Field.');
                    return false;
                }
                break;
            case 'Create Record':
                if (!this.action.objectName) {
                    this.setError('Object Name is required for Create Record.');
                    return false;
                }
                if (!this.action.fieldMappings || this.action.fieldMappings.length === 0) {
                    this.setError('At least one field mapping is required for Create Record.');
                    return false;
                }
                // Validate each mapping row
                for (const mapping of this.action.fieldMappings) {
                    if (!mapping.fieldApiName) {
                        this.setError('Each field mapping must have a Field selected.');
                        return false;
                    }
                    if (!mapping.type) {
                        this.setError('Each field mapping must have a Type selected.');
                        return false;
                    }
                    if (mapping.type === 'Hardcoded' && (!mapping.value || mapping.value.trim() === '')) {
                        this.setError('Hardcoded mappings require a Value (field: ' + mapping.fieldApiName + ').');
                        return false;
                    }
                }
                break;
            case 'Apex':
                if (!this.action.apexClassName || this.action.apexClassName.trim() === '') {
                    this.setError('Apex Class Name is required.');
                    return false;
                }
                break;
            case 'Flow':
                if (!this.action.flowApiName || this.action.flowApiName.trim() === '') {
                    this.setError('Flow API Name is required.');
                    return false;
                }
                break;
            default:
                break;
        }

        this.clearError();
        return true;
    }

    @track validationError = '';

    get hasValidationError() {
        return !!this.validationError;
    }

    setError(msg) {
        this.validationError = msg;
    }

    clearError() {
        this.validationError = '';
    }
}