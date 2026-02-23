/**
 * @description Lightning Web Component for AI Agent Creation Override
 * Provides comprehensive interface for managing AI Agent configurations
 * @author Plumcloud Labs
 * @jira V2-7442
 */
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';

// Import Apex methods
import getAgentData from '@salesforce/apex/AIAgentCreationOverrideController.getAgentData';
import getAgenticAIModels from '@salesforce/apex/AIAgentCreationOverrideController.getAgenticAIModels';
import getKnowledgeBases from '@salesforce/apex/AIAgentCreationOverrideController.getKnowledgeBases';
import getAvailablePrompts from '@salesforce/apex/AIAgentCreationOverrideController.getAvailablePrompts';
import getProfileOptions from '@salesforce/apex/AIAgentCreationOverrideController.getProfileOptions';
import getPermissionSetOptions from '@salesforce/apex/AIAgentCreationOverrideController.getPermissionSetOptions';
import saveAgent from '@salesforce/apex/AIAgentCreationOverrideController.saveAgent';
import updateAgentName from '@salesforce/apex/AIAgentCreationOverrideController.updateAgentName';
import deleteAgent from '@salesforce/apex/AIAgentCreationOverrideController.deleteAgent';
import getNamespace from '@salesforce/apex/AIAgentCreationOverrideController.getNamespace';

// Import Schema for AI_Agent__c object
import AI_AGENT_OBJECT from '@salesforce/schema/AI_Agent__c';
import NAME_FIELD from '@salesforce/schema/AI_Agent__c.Name';

 // Import static resources for channel logos
 import assistantLogo from '@salesforce/resourceUrl/assistant_logo';
 import whatsappLogo from '@salesforce/resourceUrl/whatsapp_logo';
 import msteamsLogo from '@salesforce/resourceUrl/msteams_logo';
 import mscopilotLogo from '@salesforce/resourceUrl/mscopilot_logo';
 import slackLogo from '@salesforce/resourceUrl/slack_logo';

const FIELDS = [NAME_FIELD];

// Constants for timing and delays
const FOCUS_DELAY_MS = 0;
const NAVIGATION_DELAY_MS = 500;

export default class AIAgentCreationOverride extends NavigationMixin(LightningElement) {
        @api recordId;
        
        @track isEditMode = false;
        @track isLoading = true;
        @track isSaving = false;
        @track isEditingName = false;
        @track editedAgentName = '';
        
        // Store current page reference
        currentPageReference;
        
        // Flag to track if edit mode was explicitly set by URL parameter
        isEditModeSetByURL = false;
        
        // Agent data (using wrapper structure from Apex)
        @track agentData = {};
        @track originalAgentData = {}; // For cancel functionality
        
        // Current selections
        @track selectedSkills = [];
        @track selectedKnowledgeBases = [];
        @track selectedProfiles = [];
        @track selectedPermissionSets = [];
        @track selectedChannels = [];
        @track currentSkills = []; // Store skill details for display
        
        // Original selections for cancel
        originalSelectedSkills = [];
        originalSelectedKnowledgeBases = [];
        originalSelectedProfiles = [];
        originalSelectedPermissionSets = [];
        originalSelectedChannels = [];
        
        // Options for dropdowns and dual listboxes
        @track aiModelOptions = [];
        @track skillOptions = [];
        @track knowledgeBaseOptions = [];
        @track profileOptions = [];
        @track permissionSetOptions = [];
        
        // Advanced settings collapsible state
        @track isAdvancedSettingsExpanded = false;
        
        // Store wired results for refreshApex
        wiredAgentResult;
        wiredAgentDataResult;
        
        // Wire to get agent name for display
        @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
        agent;
        
        // Wire to get current page reference for URL parameters
        @wire(CurrentPageReference)
        setCurrentPageReference(pageRef) {
            this.currentPageReference = pageRef;
            
            // Check if parameters are present in URL state
            if (pageRef && pageRef.state) {
                const editParam = pageRef.state.edit || pageRef.state.c__edit;
                // Set isEditMode to true if edit parameter is 'true' or '1'
                if (editParam === 'true' || editParam === '1') {
                    this.isEditMode = true;
                    this.isEditModeSetByURL = true;
                }
            }
        }
        
        connectedCallback() {
            // Also check URL query parameters for edit mode
            // This handles cases where navigation uses window.location.href
            const urlParams = new URLSearchParams(window.location.search);
            const editParam = urlParams.get('edit');
            if (editParam === 'true' || editParam === '1') {
                this.isEditMode = true;
                this.isEditModeSetByURL = true;
            }
            
            // Load all data
            this.loadAllData();
        }
        
        /**
         * Error callback for uncaught JavaScript errors
         * Provides graceful degradation and user feedback
         */
        errorCallback(error, stack) {
            this.showToast('Error', 'An unexpected error occurred. Please refresh the page.', 'error');
        }
        
        get agentName() {
            return this.agentData?.name || '';
        }
        
        
        get showSaveButton() {
            return this.isEditMode;
        }
        
        get showCancelButton() {
            return this.isEditMode;
        }
        
        get showDeleteButton() {
            return !this.isLoading && !this.isSaving;
        }
        
        get showSaveAndActivateButton() {
            return this.isEditMode && this.agentData.status !== 'Active';
        }
        
        get showDeactivateButton() {
            return !this.isEditMode && this.agentData.status === 'Active';
        }
        
        // Computed property for selected skills display in read mode
        get selectedSkillsDisplay() {
            if (!this.selectedSkills || this.selectedSkills.length === 0) {
                return 'No skills selected';
            }
            
            return this.selectedSkills.map(skillId => {
                const option = this.skillOptions.find(opt => opt.value === skillId);
                return option ? option.label : skillId;
            }).join(', ');
        }
        
        // Computed property for selected knowledge bases display in read mode
        get selectedKnowledgeBasesDisplay() {
            if (!this.selectedKnowledgeBases || this.selectedKnowledgeBases.length === 0) {
                return 'No knowledge bases selected';
            }
            
            return this.selectedKnowledgeBases.map(kbId => {
                const option = this.knowledgeBaseOptions.find(opt => opt.value === kbId);
                return option ? option.label : kbId;
            }).join(', ');
        }
        
        // Channel options with logos, checked state, and card class
        get channelOptions() {
            const options = [
                { label: 'Assistant', value: 'Assistant', logoUrl: assistantLogo },
                { label: 'Whatsapp', value: 'Whatsapp', logoUrl: whatsappLogo },
                { label: 'MS Teams', value: 'MS Teams', logoUrl: msteamsLogo },
                { label: 'MS Copilot', value: 'MS Copilot', logoUrl: mscopilotLogo },
                { label: 'Slack', value: 'Slack', logoUrl: slackLogo }
            ];
            
            // Add checked state and card class based on selectedChannels
            return options.map(option => {
                const isChecked = this.selectedChannels && this.selectedChannels.includes(option.value);
                return {
                    ...option,
                    checked: isChecked,
                    cardClass: isChecked ? 'channel-option channel-option-selected' : 'channel-option'
                };
            });
        }
        
        // Computed property for selected channels display in read mode
        get selectedChannelsDisplay() {
            if (!this.selectedChannels || this.selectedChannels.length === 0) {
                return 'No channels selected';
            }
            
            return this.selectedChannels.join(', ');
        }
        
        // Computed property for AI Model display name
        get aiModelDisplayName() {
            if (!this.agentData.aiModel) {
                return 'No model selected';
            }
            
            const option = this.aiModelOptions.find(opt => opt.value === this.agentData.aiModel);
            return option ? option.label : this.agentData.aiModel;
        }
        
        get advancedSettingsToggleIcon() {
            return this.isAdvancedSettingsExpanded ? 'utility:chevrondown' : 'utility:chevronright';
        }
        
        // Show TTL Message field only when TTL minutes has a value
        get showTTLMessage() {
            return this.agentData.ttl && this.agentData.ttl > 0;
        }
        
        
        async loadAllData() {
            this.isLoading = true;
            
            try {
                // Load options (cacheable)
                await Promise.all([
                    this.loadAIModelOptions(),
                    this.loadSkillOptions(),
                    this.loadKnowledgeBaseOptions(),
                    this.loadProfileOptions(),
                    this.loadPermissionSetOptions()
                ]);
                
                // Load agent data
                await this.loadAgentData();
                
            } catch (error) {
                this.showToast('Error', 'Failed to load data: ' + this.getErrorMessage(error), 'error');
            } finally {
                this.isLoading = false;
            }
        }
        
        async loadAgentData() {
            try {
                const data = await getAgentData({ agentId: this.recordId });
                
                // Store agent data from wrapper
                this.agentData = { ...data.agent };
                this.originalAgentData = { ...data.agent };
                
                // Set selected values from the wrapper level (not nested in agent)
                this.currentSkills = data.currentSkills || [];
                this.selectedSkills = (data.currentSkills || []).map(skill => skill.promptId);
                this.originalSelectedSkills = [...this.selectedSkills];
                
                this.selectedKnowledgeBases = data.selectedKnowledgeBases || [];
                this.originalSelectedKnowledgeBases = [...this.selectedKnowledgeBases];
                
                this.selectedProfiles = data.selectedProfiles || [];
                this.originalSelectedProfiles = [...this.selectedProfiles];
                
                this.selectedPermissionSets = data.selectedPermissionSets || [];
                this.originalSelectedPermissionSets = [...this.selectedPermissionSets];
                
                this.selectedChannels = data.selectedChannels || [];
                this.originalSelectedChannels = [...this.selectedChannels];
                
                // Set edit mode based on status (only if not already set by URL parameter)
                // If Status is not 'Active', open in edit mode; otherwise read-only
                if (!this.isEditModeSetByURL) {
                    this.isEditMode = this.agentData.status !== 'Active';
                }
                
            } catch (error) {
                throw error;
            }
        }
        
        async loadAIModelOptions() {
            try {
                this.aiModelOptions = await getAgenticAIModels();
            } catch (error) {
                throw error;
            }
        }
        
        async loadSkillOptions() {
            try {
                this.skillOptions = await getAvailablePrompts();
            } catch (error) {
                throw error;
            }
        }
        
        async loadKnowledgeBaseOptions() {
            try {
                this.knowledgeBaseOptions = await getKnowledgeBases();
            } catch (error) {
                throw error;
            }
        }
        
        async loadProfileOptions() {
            try {
                this.profileOptions = await getProfileOptions();
            } catch (error) {
                throw error;
            }
        }
        
        async loadPermissionSetOptions() {
            try {
                this.permissionSetOptions = await getPermissionSetOptions();
            } catch (error) {
                throw error;
            }
        }
        
        // Event Handlers
        
        handleEdit() {
            this.isEditMode = true;
        }
        
        async handleSave() {
            await this.saveAgentInternal(false);
        }
        
        async handleSaveAndActivate() {
            await this.saveAgentInternal(true);
        }
        
        /**
         * Internal save method to reduce code duplication
         * @param {Boolean} activateAfterSave - Whether to set status to Active
         */
        async saveAgentInternal(activateAfterSave = false) {
            // Validate required fields
            if (!this.agentData.name) {
                this.showToast('Error', 'Agent Name is required', 'error');
                return;
            }
            
            if (!this.agentData.aiModel) {
                this.showToast('Error', 'AI Model is required', 'error');
                return;
            }
            
            // Validate TTL Message if TTL minutes is set
            if (this.agentData.ttl && this.agentData.ttl > 0) {
                if (!this.agentData.ttlMessage || this.agentData.ttlMessage.trim() === '') {
                    this.showToast('Error', 'TTL Message is required when TTL (minutes) is set', 'error');
                    return;
                }
            }
            
            this.isSaving = true;
            
            try {
                // Clean up agentData to ensure all values are properly set
                const cleanAgentData = {
                    id: this.agentData.id || null,
                    name: this.agentData.name || '',
                    description: this.agentData.description || '',
                    systemPrompt: this.agentData.systemPrompt || '',
                    welcomeMessage: this.agentData.welcomeMessage || '',
                    status: activateAfterSave ? 'Active' : (this.agentData.status || 'Draft'),
                    aiModel: this.agentData.aiModel || null,
                    useThreadId: this.agentData.useThreadId || false,
                    ttlMessage: this.agentData.ttlMessage || '',
                    ttl: this.agentData.ttl || null
                };
                
                await saveAgent({
                    agentData: JSON.stringify(cleanAgentData),
                    selectedSkillIds: this.selectedSkills || [],
                    selectedKnowledgeBaseIds: this.selectedKnowledgeBases || [],
                    selectedProfiles: this.selectedProfiles || [],
                    selectedPermissionSets: this.selectedPermissionSets || [],
                    selectedChannels: this.selectedChannels || []
                });
                
                // Update original data after successful save
                this.originalAgentData = { ...this.agentData };
                this.originalSelectedSkills = [...this.selectedSkills];
                this.originalSelectedKnowledgeBases = [...this.selectedKnowledgeBases];
                this.originalSelectedProfiles = [...this.selectedProfiles];
                this.originalSelectedPermissionSets = [...this.selectedPermissionSets];
                this.originalSelectedChannels = [...this.selectedChannels];
                
                // Switch mode based on activation status
                if (activateAfterSave) {
                    this.isEditMode = false;
                    this.showToast('Success', 'Agent activated successfully', 'success');
                } else {
                    this.showToast('Success', 'Agent saved successfully', 'success');
                }
                
                // Refresh the wired data to get latest values
                await this.refreshData();
                
                // Refresh the chat container with updated agent data
                await this.refreshChatContainer();
                
            } catch (error) {
                const errorMessage = this.getErrorMessage(error);
                this.showToast('Error', 'Failed to ' + (activateAfterSave ? 'activate' : 'save') + ' agent: ' + errorMessage, 'error');
            } finally {
                this.isSaving = false;
            }
        }
        
        async handleCancel() {
            this.isLoading = true;
            
            try {
                // Refresh data from server to discard changes
                await this.refreshData();
                
                this.showToast('Info', 'Changes discarded', 'info');
            } catch (error) {
                this.showToast('Error', 'Failed to refresh data: ' + this.getErrorMessage(error), 'error');
            } finally {
                this.isLoading = false;
            }
        }
        
        async handleDelete() {
            // Show confirmation dialog using Lightning Confirm
            const confirmed = await this.showConfirmDialog();
            
            if (!confirmed) {
                return;
            }
            
            this.isSaving = true;
            
            try {
                // Call Apex to delete the agent
                await deleteAgent({ agentId: this.recordId });
                
                // Show success message
                this.showToast('Success', 'Agent deleted successfully', 'success');
                
                // Get namespace and navigate to Agents custom tab
                const namespace = await getNamespace();
                const agentsTabApiName = namespace ? `${namespace}Agents` : 'Agents';
                
                // Use window.top.location.href to force a complete page refresh
                const baseUrl = window.location.origin;
                const tabUrl = `/lightning/n/${agentsTabApiName}`;
                
                // Force a complete page reload to the Agents tab
                window.top.location.href = baseUrl + tabUrl;
                
            } catch (error) {
                this.showToast('Error', 'Failed to delete agent: ' + this.getErrorMessage(error), 'error');
                this.isSaving = false;
            }
        }
        
        /**
         * Shows confirmation dialog using Lightning Confirm
         * SECURITY FIX: Replaced native confirm() with Lightning modal
         * @returns {Promise<Boolean>} - User's confirmation choice
         */
        async showConfirmDialog() {
            const result = await LightningConfirm.open({
                message: 'Are you sure you want to delete this agent? This action cannot be undone.',
                variant: 'headerless',
                label: 'Delete Confirmation',
            });
            return result;
        }
        
        async handleDeactivate() {
            this.isSaving = true;
            this.isLoading = true;
            
            try {
                // Set status to Draft
                this.agentData.status = 'Draft';
                
                await saveAgent({
                    agentData: JSON.stringify(this.agentData),
                    selectedSkillIds: this.selectedSkills,
                    selectedKnowledgeBaseIds: this.selectedKnowledgeBases,
                    selectedProfiles: this.selectedProfiles,
                    selectedPermissionSets: this.selectedPermissionSets,
                    selectedChannels: this.selectedChannels
                });
                
                // Update original data after successful save
                this.originalAgentData = { ...this.agentData };
                
                // Switch to edit mode after deactivation
                this.isEditMode = true;
                this.showToast('Success', 'Agent deactivated and moved to edit mode', 'success');
                
                // Refresh the wired data to get latest values
                await this.refreshData();
                
                // Refresh the chat container with updated agent data
                await this.refreshChatContainer();
                
            } catch (error) {
                this.showToast('Error', 'Failed to deactivate agent: ' + this.getErrorMessage(error), 'error');
            } finally {
                this.isSaving = false;
                this.isLoading = false;
            }
        }
        
        async refreshData() {
            // Reload all data
            await this.loadAllData();
        }
        
        async refreshChatContainer() {
            try {
                // Get reference to chat container and refresh it
                const chatContainer = this.refs.chatContainer;
                if (chatContainer) {
                    await chatContainer.refreshAgent();
                }
            } catch (error) {
                // Silently fail - chat container refresh is not critical
            }
        }
        
        // Field change handlers
        
        handleNameChange(event) {
            this.agentData.name = event.target.value;
        }
        
        handleDescriptionChange(event) {
            this.agentData.description = event.target.value;
        }
        
        handleSystemPromptChange(event) {
            this.agentData.systemPrompt = event.target.value;
        }
        
        handleAIModelChange(event) {
            this.agentData.aiModel = event.detail.value;
        }
        
        handleSkillChange(event) {
            this.selectedSkills = event.detail.value;
        }
        
        handleKnowledgeBaseChange(event) {
            this.selectedKnowledgeBases = event.detail.value;
        }
        
        handleChannelClick(event) {
            const channelValue = event.currentTarget.dataset.channel;
            
            if (!channelValue) return;
            
            // Toggle the channel selection
            const isCurrentlySelected = this.selectedChannels.includes(channelValue);
            
            if (isCurrentlySelected) {
                // Remove channel from selection
                this.selectedChannels = this.selectedChannels.filter(channel => channel !== channelValue);
            } else {
                // Add channel to selection
                this.selectedChannels = [...this.selectedChannels, channelValue];
            }
        }
        
        handleProfileChange(event) {
            this.selectedProfiles = event.detail.value;
        }
        
        handlePermissionSetChange(event) {
            this.selectedPermissionSets = event.detail.value;
        }
        
        // Advanced settings handlers
        
        handleWelcomeMessageChange(event) {
            this.agentData.welcomeMessage = event.target.value;
        }
        
        handleUseThreadIdChange(event) {
            this.agentData.useThreadId = event.target.checked;
        }
        
        handleTTLMessageChange(event) {
            this.agentData.ttlMessage = event.target.value;
        }
        
        handleTTLChange(event) {
            const newValue = event.target.value;
            this.agentData.ttl = newValue;
            
            // Clear TTL Message if TTL is empty or 0
            if (!newValue || newValue <= 0) {
                this.agentData.ttlMessage = '';
            }
            
            // Force re-render to show/hide TTL Message field
            this.agentData = { ...this.agentData };
        }
        
        // Advanced settings toggle handler
        handleAdvancedSettingsToggle() {
            this.isAdvancedSettingsExpanded = !this.isAdvancedSettingsExpanded;
        }
        
        // Agent name inline editing handlers
        
        handleEditName() {
            this.isEditingName = true;
            this.editedAgentName = this.agentName;
            
            // Focus on the input field after rendering
            // Use requestAnimationFrame for better timing with LWC rendering
            requestAnimationFrame(() => {
                const input = this.template.querySelector('lightning-input.agent-name-input');
                if (input) {
                    input.focus();
                }
            });
        }
        
        handleInlineNameChange(event) {
            this.editedAgentName = event.target.value;
            // Update agentData.name so it's ready for save
            this.agentData.name = event.target.value;
        }
        
        handleNameBlur() {
            // Check if name has changed and is valid
            if (!this.editedAgentName.trim()) {
                // Empty name, revert to original
                this.agentData.name = this.originalAgentData.name;
                this.editedAgentName = '';
                this.isEditingName = false;
                return;
            }
            
            // Just exit editing mode without saving
            // The name will be saved when user clicks Save or Save & Publish button
            this.isEditingName = false;
            this.editedAgentName = '';
        }
        
        // Utility methods
        
        /**
         * Extracts user-friendly error message from various error formats
         * @param {Object} error - Error object from Apex or JavaScript
         * @returns {String} - Formatted error message
         */
        getErrorMessage(error) {
            if (error?.body?.message) {
                return error.body.message;
            } else if (error?.message) {
                return error.message;
            } else if (typeof error === 'string') {
                return error;
            } else {
                return 'An unknown error occurred';
            }
        }
        
        showToast(title, message, variant) {
            const event = new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            });
            this.dispatchEvent(event);
        }
    }