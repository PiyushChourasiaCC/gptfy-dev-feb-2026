/**
 * @description AI Agent Intent Manager — full-page LWC for AI_Agent_Intent__c record page.
 *   Displays intent details (edit/read mode) and child actions datatable with add/edit/delete.
 * @author  Sagar Alwani
 * @jira    V2-7338
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';

import getIntentWithActions from '@salesforce/apex/AIAgentIntentController.getIntentWithActions';
import upsertIntent from '@salesforce/apex/AIAgentIntentController.upsertIntent';
import deleteAction from '@salesforce/apex/AIAgentIntentController.deleteAction';
import deleteIntent from '@salesforce/apex/AIAgentIntentController.deleteIntent';

const ACTION_COLUMNS = [
    {
        label: 'Action Type',
        fieldName: 'actionType',
        type: 'text',
        initialWidth: 160,
        cellAttributes: { class: 'slds-text-title_caps' }
    },
    {
        label: 'Description',
        fieldName: 'description',
        type: 'text'
    },
    {
        label: 'Sequence',
        fieldName: 'sequence',
        type: 'number',
        initialWidth: 100,
        cellAttributes: { alignment: 'center' }
    },
    {
        label: 'Active',
        fieldName: 'isActiveLabel',
        type: 'text',
        initialWidth: 90,
        cellAttributes: { alignment: 'center' }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

export default class AIAgentIntentManager extends NavigationMixin(LightningElement) {
    @api recordId; // AI_Agent_Intent__c record Id

    // State
    @track isLoading = true;
    @track isSaving = false;
    @track isEditMode = false;

    // Intent data
    @track intent = {};
    @track originalIntent = {};

    // Actions data
    @track actions = [];
    actionColumns = ACTION_COLUMNS;

    // Picklist metadata (passed to child action form)
    @track actionTypeOptions = [];
    @track apexReturnTypeOptions = [];
    @track languageOptions = [];

    // Action modal state
    @track showActionModal = false;
    @track currentAction = {};

    // ─── Lifecycle ─────────────────────────────────────────────

    connectedCallback() {
        this.loadData();
    }

    // ─── Data loading ──────────────────────────────────────────

    async loadData() {
        this.isLoading = true;
        try {
            const result = await getIntentWithActions({ intentId: this.recordId });

            this.intent = { ...result.intent };
            this.originalIntent = { ...result.intent };

            // Enrich actions with display label for active column
            this.actions = (result.actions || []).map(a => ({
                ...a,
                isActiveLabel: a.isActive ? 'Yes' : 'No'
            }));

            this.actionTypeOptions = result.actionTypeOptions || [];
            this.apexReturnTypeOptions = result.apexReturnTypeOptions || [];
            this.languageOptions = result.languageOptions || [];
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Computed properties ───────────────────────────────────

    get intentName() {
        return this.intent?.name || 'Intent';
    }

    get activeStatusClass() {
        return this.intent?.isActive
            ? 'status-badge status-active'
            : 'status-badge status-draft';
    }

    get activeStatusLabel() {
        return this.intent?.isActive ? 'Active' : 'Inactive';
    }

    get actionCount() {
        return this.actions ? this.actions.length : 0;
    }

    get hasActions() {
        return this.actions && this.actions.length > 0;
    }

    // ─── Intent edit handlers ──────────────────────────────────

    handleEdit() {
        this.isEditMode = true;
    }

    handleCancel() {
        this.intent = { ...this.originalIntent };
        this.isEditMode = false;
    }

    handleNameChange(event) {
        this.intent = { ...this.intent, name: event.target.value };
    }

    handleDescriptionChange(event) {
        this.intent = { ...this.intent, description: event.target.value };
    }

    handleSequenceChange(event) {
        const val = event.target.value;
        this.intent = { ...this.intent, sequence: val ? parseInt(val, 10) : null };
    }

    handleActiveChange(event) {
        this.intent = { ...this.intent, isActive: event.target.checked };
    }

    async handleSave() {
        // Validate
        if (!this.intent.name || this.intent.name.trim() === '') {
            this.showToast('Error', 'Intent Name is required', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const result = await upsertIntent({ intentJson: JSON.stringify(this.intent) });
            this.intent = { ...this.intent, id: result.id };
            this.originalIntent = { ...this.intent };
            this.isEditMode = false;
            this.showToast('Success', 'Intent saved successfully', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ─── Navigate back to parent agent ─────────────────────────

    handleBackToAgent() {
        if (this.intent?.agentId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.intent.agentId,
                    objectApiName: 'AI_Agent__c',
                    actionName: 'view'
                }
            });
        }
    }

    // ─── Delete intent ─────────────────────────────────────────

    async handleDeleteIntent() {
        const confirmed = await LightningConfirm.open({
            message: 'Are you sure you want to delete this intent? All associated actions will also be deleted. This action cannot be undone.',
            variant: 'headerless',
            label: 'Delete Confirmation'
        });
        if (!confirmed) return;

        this.isSaving = true;
        try {
            const agentId = this.intent?.agentId;
            await deleteIntent({ intentId: this.recordId });
            this.showToast('Success', 'Intent deleted successfully', 'success');
            if (agentId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: agentId,
                        objectApiName: 'AI_Agent__c',
                        actionName: 'view'
                    }
                });
            }
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ─── Actions datatable handlers ────────────────────────────

    handleAddAction() {
        this.currentAction = {};
        this.showActionModal = true;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        switch (actionName) {
            case 'edit':
                // Use the full action object from this.actions (not the datatable row)
                // because lightning-datatable strips nested arrays like fieldMappings
                const fullAction = this.actions.find(a => a.id === row.id);
                this.currentAction = fullAction
                    ? JSON.parse(JSON.stringify(fullAction))
                    : { ...row };
                this.showActionModal = true;
                break;
            case 'delete':
                this.handleDeleteAction(row.id);
                break;
            default:
                break;
        }
    }

    async handleDeleteAction(actionId) {
        this.isLoading = true;
        try {
            await deleteAction({ actionId: actionId });
            this.showToast('Success', 'Action deleted successfully', 'success');
            await this.loadData();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
            this.isLoading = false;
        }
    }

    // ─── Action modal callbacks ────────────────────────────────

    handleActionModalClose() {
        this.showActionModal = false;
        this.currentAction = {};
    }

    async handleActionSaved() {
        this.showActionModal = false;
        this.currentAction = {};
        this.showToast('Success', 'Action saved successfully', 'success');
        await this.loadData();
    }

    // ─── Utilities ─────────────────────────────────────────────

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        } else if (error?.message) {
            return error.message;
        }
        return 'An unknown error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}