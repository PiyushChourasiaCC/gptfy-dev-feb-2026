import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getAllSalesforceObjects from '@salesforce/apex/AIPromptFactoryController.getAllSalesforceObjects';
import getObjectRecords from '@salesforce/apex/AIPromptFactoryController.getObjectRecords';
import getChatAIModels from '@salesforce/apex/AIPromptFactoryController.getChatAIModels';
import discoverSchema from '@salesforce/apex/AIPromptFactoryController.discoverSchema';
import generatePromptWithConnection from '@salesforce/apex/AIPromptFactoryController.generatePromptWithConnection';
import deployPrompt from '@salesforce/apex/AIPromptFactoryController.deployPrompt';
import refinePrompt from '@salesforce/apex/AIPromptFactoryController.refinePrompt';
import getNamespace from '@salesforce/apex/AIPromptFactoryController.getNamespace';
import initiateGPT from '@salesforce/apex/ChatGPTUtills.initiateGPT';
import AI_PROMPT_OBJECT from '@salesforce/schema/AI_Prompt__c';

export default class AIPromptFactory extends NavigationMixin(LightningElement) {
    // Track properties
    @track objectOptions = [];
    @track recordOptions = [];
    @track aiModelOptions = [];
    @track selectedTargetObject = '';
    @track businessContext = '';
    @track selectedSampleRecord = '';
    @track selectedSampleRecordName = '';
    @track selectedAIModel = '';
    @track generatedPrompt = '';
    @track htmlOutput = '';
    @track isProcessing = false;
    @track isRunning = false;
    @track activeTab = 'promptText';
    @track recordSearchTerm = '';
    @track isDropdownOpen = false;
    @track isLoadingRecords = false;
    @track selectedTargetObjectIcon = 'standard:record';
    @track schemaInfo = null;
    @track isDiscoveringSchema = false;
    @track testRecordId = '';
    @track promptName = '';
    @track deployedPromptId = null;
    @track showRefineInput = false;
    @track refinementInput = '';
    @track showPromptOverride = false;
    @track namespace = '';
    @track navigationTabName = '';
    @track isModalOpen = false;
    @track copyTooltip = 'Copy to clipboard';
    @track messages = [];
    @track hasStartedGeneration = false;

    searchTimeout;
    messageCounter = 0;
    
    // Object API name for navigation
    aiPromptObjectApiName = AI_PROMPT_OBJECT.objectApiName;

    // Wire methods
    @wire(getAllSalesforceObjects)
    wiredObjects({ error, data }) {
        if (data) {
            this.objectOptions = data.map(obj => ({
                label: obj.label,
                value: obj.value
            }));
        } else if (error) {
            this.showToast('Error', 'Error fetching Salesforce objects: ' + error.body.message, 'error');
        }
    }

    @wire(getChatAIModels)
    wiredAIModels({ error, data }) {
        if (data) {
            this.aiModelOptions = data.map(model => ({
                label: model.label,
                value: model.value
            }));
        } else if (error) {
            this.showToast('Error', 'Error fetching AI Models: ' + error.body.message, 'error');
        }
    }

    // Computed properties
    get showSampleRecordField() {
        return this.selectedTargetObject !== '';
    }

    get isGenerateDisabled() {
        return !this.selectedTargetObject || !this.businessContext.trim() || !this.selectedAIModel || this.isProcessing;
    }

    get showOutput() {
        return this.generatedPrompt !== '';
    }

    get isPromptTabActive() {
        return this.activeTab === 'promptText';
    }

    get isOutputTabActive() {
        return this.activeTab === 'output';
    }

    get promptTabClass() {
        return this.activeTab === 'promptText' ? 'tab-button tab-active' : 'tab-button';
    }

    get outputTabClass() {
        return this.activeTab === 'output' ? 'tab-button tab-active' : 'tab-button';
    }

    get comboboxClass() {
        return this.isDropdownOpen ? 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open' : 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click';
    }

    get showDropdown() {
        return this.isDropdownOpen && !this.selectedSampleRecordName;
    }

    get hasRecords() {
        return this.recordOptions && this.recordOptions.length > 0;
    }

    get formattedCharCount() {
        if (!this.generatedPrompt) return '0';
        const count = this.generatedPrompt.length;
        if (count >= 1000) {
            return (count / 1000).toFixed(1) + 'K';
        }
        return String(count);
    }

    get hasHtmlOutput() {
        return this.htmlOutput && this.htmlOutput.length > 0;
    }

    get isRunDisabled() {
        return !this.testRecordId || !this.generatedPrompt || this.isRunning || this.isProcessing;
    }

    get isDeployDisabled() {
        return !this.generatedPrompt || this.isProcessing || this.isRunning;
    }

    get isRefineApplyDisabled() {
        return !this.refinementInput.trim() || this.isProcessing;
    }

    get defaultPromptName() {
        // Auto-generate prompt name: "Account 360 — Mar 4, 6:31 PM"
        const now = new Date();
        const dateStr = now.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        const timeStr = now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        const objectName = this.selectedTargetObject || 'AI';
        return `${objectName} 360 — ${dateStr}, ${timeStr}`;
    }

    get modalTitle() {
        return this.activeTab === 'promptText' ? 'Prompt Text' : 'Output';
    }

    // Event handlers
    handleTargetObjectChange(event) {
        this.selectedTargetObject = event.detail.value;
        
        // Update icon based on selected object
        this.selectedTargetObjectIcon = this.getObjectIcon(this.selectedTargetObject);
        
        // Reset sample record fields
        this.selectedSampleRecord = '';
        this.selectedSampleRecordName = '';
        this.recordOptions = [];
        this.recordSearchTerm = '';
        this.isDropdownOpen = false;
    }

    handleBusinessContextChange(event) {
        this.businessContext = event.target.value;
    }

    handleAIModelChange(event) {
        this.selectedAIModel = event.detail.value;
    }

    handleRecordSearch(event) {
        this.recordSearchTerm = event.target.value;
        
        // Clear existing timeout
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }
        
        // Debounce search
        this.searchTimeout = setTimeout(() => {
            this.loadRecords();
        }, 300);
    }

    handleSearchFocus() {
        if (this.recordOptions.length > 0) {
            this.isDropdownOpen = true;
        } else if (this.selectedTargetObject) {
            this.loadRecords();
        }
    }

    handleSearchIconClick() {
        if (this.selectedTargetObject) {
            this.loadRecords();
        }
    }

    handleRecordSelect(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const recordName = event.currentTarget.dataset.recordName;
        
        this.selectedSampleRecord = recordId;
        this.selectedSampleRecordName = recordName;
        this.isDropdownOpen = false;
        this.recordSearchTerm = '';
    }

    handleClearSelection() {
        this.selectedSampleRecord = '';
        this.selectedSampleRecordName = '';
        this.recordSearchTerm = '';
        this.recordOptions = [];
        this.isDropdownOpen = false;
    }

    handlePromptTab() {
        this.activeTab = 'promptText';
    }

    handleOutputTab() {
        this.activeTab = 'output';
    }

    handleGeneratePrompt() {
        if (this.isGenerateDisabled) return;

        this.hasStartedGeneration = true;
        this.isProcessing = true;
        this.activeTab = 'promptText';
        this.showRefineInput = false;
        
        // Add system message
        this.addMessage('system', 'Starting session and generating golden prompt...');

        // Step 1: Discover Schema
        this.isDiscoveringSchema = true;
        discoverSchema({ objectName: this.selectedTargetObject })
            .then(schemaResult => {
                this.schemaInfo = schemaResult;
                this.isDiscoveringSchema = false;
                
                // Step 2: Generate Prompt with Connection
                const request = {
                    targetObject: this.selectedTargetObject,
                    businessContext: this.businessContext,
                    sampleRecordId: this.selectedSampleRecord,
                    aiModelId: this.selectedAIModel
                };
                
                return generatePromptWithConnection({ request: request });
            })
            .then(result => {
                this.generatedPrompt = result;
                this.htmlOutput = '';
                // Pre-fill test record ID if sample record was provided
                if (this.selectedSampleRecord && !this.testRecordId) {
                    this.testRecordId = this.selectedSampleRecord;
                }
                
                // Add success message
                const charCount = result.length;
                const sizeLabel = charCount >= 1000 
                    ? (charCount / 1000).toFixed(1) + 'K' 
                    : charCount;
                this.addMessage('assistant', `Golden prompt generated successfully!\n${sizeLabel} characters. Review the prompt in the preview panel, then run against a record or refine.`);
                
                this.showToast('Success', 'Golden prompt generated successfully!', 'success');
            })
            .catch(error => {
                const errorMessage = error.body?.message || error.message || 'Unknown error';
                this.addMessage('system', 'Generation failed: ' + errorMessage);
                this.showToast('Error', 'Error: ' + errorMessage, 'error');
            })
            .finally(() => {
                this.isProcessing = false;
                this.isDiscoveringSchema = false;
            });
    }

    handleTestRecordIdChange(event) {
        this.testRecordId = event.target.value;
    }

    handlePromptNameChange(event) {
        this.promptName = event.target.value;
    }

    handleRefinementChange(event) {
        this.refinementInput = event.target.value;
    }

    handleRun() {
        if (this.isRunDisabled) return;

        this.isRunning = true;
        this.activeTab = 'output';
        
        // Add user message
        this.addMessage('user', `Run prompt against record: ${this.testRecordId}`);

        // First deploy/update the prompt, then execute it
        const finalPromptName = this.promptName || this.defaultPromptName;

        const deployRequest = {
            goldenPromptText: this.generatedPrompt,
            promptName: finalPromptName,
            targetObject: this.selectedTargetObject,
            aiModelId: this.selectedAIModel || '',
            existingPromptId: this.deployedPromptId || '',
            schemaInfo: this.schemaInfo,
            businessContext: this.businessContext || '',
            priorityChildObjects: []
        };

        deployPrompt({ request: deployRequest })
            .then(deployResult => {
                console.log('Deploy result:', deployResult);
                this.deployedPromptId = deployResult.promptId;
                this.promptName = deployResult.promptName;
                
                // Validate we have all required data before executing
                if (!deployResult.promptId) {
                    throw new Error('Prompt ID not returned from deployment');
                }
                if (!this.testRecordId) {
                    throw new Error('Record ID is required to run the prompt');
                }
                if (!this.selectedAIModel) {
                    throw new Error('AI Model is required to run the prompt');
                }
                
                console.log('Executing prompt with:', {
                    promptId: deployResult.promptId,
                    recordId: this.testRecordId
                });
                
                // Add system message
                this.addMessage('system', 'Executing prompt...');
                
                // Now execute the prompt using initiateGPT (same as testing console)
                return initiateGPT({
                    recordId: this.testRecordId,
                    promptId: deployResult.promptId,
                    userInput: '',
                    mapOfFiles: null,
                    isGptfyConsole: true
                });
            })
            .then(result => {
                console.log('Prompt execution result:', result);
                
                // Check if result has an error
                if (result && result.Status__c === 'Errored' && result.Message__c) {
                    throw new Error(result.Message__c);
                }
                
                // Extract the HTML output from the response
                // The response structure matches AI_Response__c
                const htmlResult = result.AI_Processed_Data_PII_Added__c || result.AI_Processed_Data_No_PII__c || '';
                
                if (!htmlResult) {
                    throw new Error('No output generated from prompt execution');
                }
                
                this.htmlOutput = htmlResult;
                
                // Render HTML in iframe
                this.renderHtmlOutput();
                
                const outputSize = htmlResult.length >= 1000
                    ? (htmlResult.length / 1000).toFixed(1) + 'K'
                    : htmlResult.length;
                
                // Add success message
                this.addMessage('assistant', `Output rendered (${outputSize} chars). You can refine the prompt and re-run, or deploy.`);
                
                this.showToast('Success', `Output rendered (${outputSize} chars)`, 'success');
            })
            .catch(error => {
                const errorMessage = error.body?.message || error.message || 'Unknown error';
                this.addMessage('system', 'Run failed: ' + errorMessage);
                this.showToast('Error', 'Run failed: ' + errorMessage, 'error');
            })
            .finally(() => {
                this.isRunning = false;
            });
    }

    handleStartRefine() {
        this.showRefineInput = true;
        this.refinementInput = '';
    }

    handleCancelRefine() {
        this.showRefineInput = false;
        this.refinementInput = '';
    }

    handleApplyRefinement() {
        if (this.isRefineApplyDisabled) return;

        this.isProcessing = true;
        this.showRefineInput = false;
        
        // Add user message
        this.addMessage('user', this.refinementInput);
        this.addMessage('system', 'Refining golden prompt...');

        refinePrompt({
            currentPrompt: this.generatedPrompt,
            refinementInstruction: this.refinementInput,
            aiModelId: this.selectedAIModel
        })
            .then(result => {
                this.generatedPrompt = result.goldenPrompt;
                this.htmlOutput = '';
                this.activeTab = 'promptText';
                
                const sizeLabel = result.charCount >= 1000
                    ? (result.charCount / 1000).toFixed(1) + 'K'
                    : result.charCount;
                
                // Add success message
                this.addMessage('assistant', `Prompt refined.\n${sizeLabel} characters. Review and deploy, or refine again.`);
                
                this.showToast('Success', `Prompt refined (${sizeLabel} characters)`, 'success');
            })
            .catch(error => {
                const errorMessage = error.body?.message || error.message || 'Unknown error';
                this.addMessage('system', 'Refinement failed: ' + errorMessage);
                this.showToast('Error', 'Refinement failed: ' + errorMessage, 'error');
            })
            .finally(() => {
                this.isProcessing = false;
                this.refinementInput = '';
            });
    }

    handleDeploy() {
        if (this.isDeployDisabled) return;

        // If prompt is already deployed, just navigate to it
        if (this.deployedPromptId) {
            this.addMessage('system', `Navigating to existing prompt: ${this.promptName}`);
            this.showToast('Success', 'Navigating to prompt record', 'success');
            this.navigateToPromptRecord(this.deployedPromptId);
            return;
        }

        const finalPromptName = this.promptName || this.defaultPromptName;

        this.isProcessing = true;
        
        // Add user message
        this.addMessage('user', `Deploy as: ${finalPromptName}`);

        const deployRequest = {
            goldenPromptText: this.generatedPrompt,
            promptName: finalPromptName,
            targetObject: this.selectedTargetObject,
            aiModelId: this.selectedAIModel || '',
            existingPromptId: this.deployedPromptId || '',
            schemaInfo: this.schemaInfo,
            businessContext: this.businessContext || '',
            priorityChildObjects: []
        };

        deployPrompt({ request: deployRequest })
            .then(result => {
                this.deployedPromptId = result.promptId;
                this.promptName = result.promptName;

                const action = result.status === 'updated' ? 'updated' : 'deployed';
                
                // Add success message
                this.addMessage('assistant', `Prompt ${action} successfully!\nName: ${result.promptName}\nPrompt ID: ${result.promptId}`);
                
                this.showToast('Deployed', `Golden prompt ${action} as ${result.promptName}`, 'success');
                
                // Navigate to the newly created/updated prompt record
                this.navigateToPromptRecord(result.promptId);
            })
            .catch(error => {
                const errorMessage = error.body?.message || error.message || 'Unknown error';
                this.addMessage('system', 'Deployment failed: ' + errorMessage);
                this.showToast('Error', 'Deployment failed: ' + errorMessage, 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    renderHtmlOutput() {
        // Wait for DOM to update
        setTimeout(() => {
            const outputFrame = this.template.querySelector('.output-frame');
            if (outputFrame && this.htmlOutput) {
                outputFrame.innerHTML = this.htmlOutput;
            }
            
            // Also render in modal if open
            const modalFrame = this.template.querySelector('.modal-output-frame');
            if (modalFrame && this.htmlOutput) {
                modalFrame.innerHTML = this.htmlOutput;
            }
        }, 100);
    }

    renderedCallback() {
        // Re-render HTML output when switching to output tab or opening modal
        if (this.activeTab === 'output' && this.htmlOutput) {
            this.renderHtmlOutput();
        }
        if (this.isModalOpen && this.htmlOutput) {
            this.renderHtmlOutput();
        }
    }

    // Helper: add message to thread
    addMessage(type, content) {
        this.messageCounter++;
        const now = new Date();
        const timeLabel = now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        
        let icon, senderLabel, cssClass;
        
        switch(type) {
            case 'system':
                icon = 'utility:info';
                senderLabel = 'SYSTEM';
                cssClass = 'message-bubble message-system';
                break;
            case 'user':
                icon = 'utility:user';
                senderLabel = 'USER';
                cssClass = 'message-bubble message-user';
                break;
            case 'assistant':
                icon = 'utility:magic_wand';
                senderLabel = 'PROMPT FACTORY';
                cssClass = 'message-bubble message-assistant';
                break;
            default:
                icon = 'utility:info';
                senderLabel = 'INFO';
                cssClass = 'message-bubble';
        }
        
        const msg = {
            id: 'msg-' + this.messageCounter,
            type,
            icon,
            senderLabel,
            content,
            timeLabel,
            cssClass,
            timestamp: Date.now()
        };
        
        // Create new array to trigger reactivity
        this.messages = [...this.messages, msg];
    }

    // Helper methods
    loadRecords() {
        if (!this.selectedTargetObject) return;

        this.isLoadingRecords = true;
        
        getObjectRecords({
            objectApiName: this.selectedTargetObject,
            searchTerm: this.recordSearchTerm
        })
            .then(result => {
                this.recordOptions = result.map(record => ({
                    label: record.label,
                    value: record.value
                }));
                this.isDropdownOpen = this.recordOptions.length > 0;
            })
            .catch(error => {
                this.showToast('Error', 'Error loading records: ' + error.body.message, 'error');
                this.recordOptions = [];
                this.isDropdownOpen = false;
            })
            .finally(() => {
                this.isLoadingRecords = false;
            });
    }

    getObjectIcon(objectName) {
        const iconMap = {
            'Account': 'standard:account',
            'Contact': 'standard:contact',
            'Lead': 'standard:lead',
            'Opportunity': 'standard:opportunity',
            'Case': 'standard:case',
            'Task': 'standard:task',
            'Event': 'standard:event',
            'Campaign': 'standard:campaign',
            'Quote': 'standard:quote',
            'Order': 'standard:orders',
            'Product2': 'standard:product',
            'Contract': 'standard:contract',
            'Asset': 'standard:asset',
            'User': 'standard:user'
        };

        return iconMap[objectName] || 'standard:record';
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Copy to clipboard
    handleCopy() {
        const textToCopy = this.activeTab === 'promptText' ? this.generatedPrompt : this.htmlOutput;
        
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(textToCopy)
                .then(() => {
                    this.copyTooltip = 'Copied!';
                    setTimeout(() => {
                        this.copyTooltip = 'Copy to clipboard';
                    }, 2000);
                    this.showToast('Success', 'Copied to clipboard', 'success');
                })
                .catch(err => {
                    console.error('Copy failed:', err);
                    this.showToast('Error', 'Failed to copy to clipboard', 'error');
                });
        } else {
            this.showToast('Error', 'Clipboard API not supported', 'error');
        }
    }

    // Expand to full view
    handleExpand() {
        this.isModalOpen = true;
    }

    // Close modal
    handleModalClose() {
        this.isModalOpen = false;
    }

    // Prevent modal close when clicking inside modal content
    handleModalContentClick(event) {
        event.stopPropagation();
    }

    // Lifecycle hook - fetch namespace on component load
    connectedCallback() {
        this.fetchNamespace();
    }

    // Fetch namespace for navigation
    async fetchNamespace() {
        try {
            const result = await getNamespace();
            this.namespace = result || '';
        } catch (error) {
            console.error('Error fetching namespace:', error);
            this.namespace = '';
        }
    }

    // Navigation Methods
    handleBack() {
        try {
            if (this.navigationTabName) {
                // Navigate to specified tab with namespace prefix
                const tabUrl = '/lightning/n/' + this.namespace + this.navigationTabName;
                window.location.href = tabUrl;
            } else {
                // Navigate to AI_Prompt__c list view
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: this.aiPromptObjectApiName,
                        actionName: 'list'
                    }
                });
            }
        } catch (error) {
            console.error('Error in handleBack:', error);
            this.showToast('Error', 'Failed to navigate back: ' + error.message, 'error');
        }
    }

    navigateToPromptRecord(promptId) {
        try {
            // Navigate to the prompt record page
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: promptId,
                    objectApiName: this.aiPromptObjectApiName,
                    actionName: 'view'
                }
            });
        } catch (error) {
            console.error('Navigation error:', error);
            this.showToast('Error', 'Failed to navigate to prompt: ' + error.message, 'error');
        }
    }

    handleBuildYourOwn() {
        this.showPromptOverride = true;
    }

    handlePromptOverrideCancel() {
        this.showPromptOverride = false;
    }
}
