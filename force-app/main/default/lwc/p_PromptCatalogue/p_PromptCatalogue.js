/**
 * @description Redesigned Prompt Catalogue Component with metrics and enhanced UX
 * @author      Salesforce Development Team
 * @date        2025-11-09
 */
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { deleteRecord } from 'lightning/uiRecordApi';
import getCardConfiguration from '@salesforce/apex/AddCardController.getCardConfiguration';
import updatePromptData from '@salesforce/apex/CatalogController.updatePromptData';
import getPurposeOptions from '@salesforce/apex/CatalogController.getPurposeOptions';
import PMT_OBJECT from '@salesforce/schema/AI_Prompt__c';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import AiPromptWhereClauseFormulaComponent from 'c/aiPromptWhereClauseFormulaComponent';

export default class P_PromptCatalogue extends NavigationMixin(LightningElement) {
    
    // ================== LEGACY PROPERTIES (Not Used) ==================
    // These properties are maintained for backward compatibility with existing page layouts
    @api showHeader;
    @api headerTitle;
    @api showSearchBar;
    @api cardsPerRow;
    
    // ================== STATE MANAGEMENT ==================
    
    @track cards = [];
    @track metrics = {
        totalPrompts: 0,
        activePrompts: 0,
        hoursSaved: 0,
        costSaved: 0,
        costSavedFormatted: '0k',
        roi: 0
    };
    
    @track searchTerm = '';
    @track selectedStage = '';
    @track isGridView = true;
    @track isLoading = false;
    @track error = undefined;
    @track showEditModal = false;
    @track editRecordId = null;
    @track editCardName = '';
    @track isCreateMode = false;
    @track isShowNewPromptComp = false;
    
    // Table view properties
    @track currentView = 'purpose'; // 'purpose', 'configuration', or 'deployment'
    @track selectedPurpose = '';
    @track prompts = [];
    @track isLoadingPrompts = false;
    @track selectedPrompts = [];
    @track selectedPromptIds = [];
    
    // Deployment properties
    @track selectedMappings = [];
    @track profileOptions = [];
    @track recTypeOptions = {};
    @track extractOptions = {};
    @track promptData = {};
    @track isLoadingDeployment = false;
    @track helpText_VisibilityCondition;
    
    // Table columns configuration (matching the UI design)
    columns = [
        { label: 'Prompt Name', fieldName: 'promptName', type: 'text', sortable: true, wrapText: true },
        { label: 'Primary Object', fieldName: 'primaryObject', type: 'text', sortable: true },
        { label: 'Connection', fieldName: 'connection', type: 'text', sortable: true },
        { label: 'Description', fieldName: 'description', type: 'text', sortable: true, wrapText: true },
        { label: 'Status', fieldName: 'status', type: 'text', sortable: true }
    ];
    
    // Modal fields configuration
    modalFields = [
        'Name',
        'Description__c',
        'Feature__c',
        'Icon_Source__c',
        'Icon_Details__c',
        'Sequence__c',
        'Enabled__c'
    ];
    
    // Category color mapping
    categoryColors = {
        'Sales Acceleration': 'catalog-card-sales',
        'Support & Retention': 'catalog-card-support',
        'Service Optimization': 'catalog-card-service',
        'Revenue Operations': 'catalog-card-revenue',
        'Relationship Management': 'catalog-card-relationship'
    };
    
    // ================== LIFECYCLE HOOKS ==================
    
    /**
     * @description Called when component is inserted into DOM
     */
    connectedCallback() {
        this.loadCards();
        this.fetchPurposeOptions();
    }
    
    /**
     * @description Wire service to fetch metrics (NO LONGER USED - costSaved now comes from getPromptCards)
     * Kept for potential future use with other metrics
     */
    // @wire(getCatalogueMetrics)
    // wiredMetrics(result) {
    //     if (result.data) {
    //         // Use moneySaved from metrics response (calculated from AI_Usage_Tracking__c)
    //         const moneySaved = result.data.moneySaved || result.data.costSaved || 0;
    //         this.metrics = {
    //             ...result.data,
    //             costSaved: moneySaved,
    //             costSavedFormatted: this.formatCost(moneySaved)
    //         };
    //     } else if (result.error) {
    //         console.error('Error fetching metrics:', result.error);
    //     }
    // }
    
    /**
     * @description Wire to get AI_Prompt__c object info for help text
     */
    @wire(getObjectInfo, { objectApiName: PMT_OBJECT })
    wiredPromptObjectInfo({ error, data }) {
        if (error) {
            console.error('Error fetching object info:', error);
        } else if (data) {
            if (data.fields && data.fields['Visibility_Condition__c'] && data.fields['Visibility_Condition__c'].inlineHelpText) {
                this.helpText_VisibilityCondition = data.fields['Visibility_Condition__c'].inlineHelpText;
            }
        }
    }
    
    // ================== GETTERS ==================
    
    /**
     * @description Get grid class based on view mode
     */
    get cardGridClass() {
        return this.isGridView ? 'card-grid' : 'card-grid card-grid-list';
    }
    
    // Grid/List button variants removed - always showing grid view
    // /**
    //  * @description Get grid button variant
    //  */
    // get gridViewClass() {
    //     return this.isGridView ? 'brand' : 'neutral';
    // }
    
    // /**
    //  * @description Get list button variant
    //  */
    // get listViewClass() {
    //     return !this.isGridView ? 'brand' : 'neutral';
    // }
    
    /**
     * @description Check if cards are available
     */
    get hasCards() {
        return this.cards && this.cards.length > 0;
    }
    
    /**
     * @description Check if no data available
     */
    get hasNoData() {
        return !this.isLoading && !this.hasCards && !this.error;
    }
    
    /**
     * @description Check if errors exist
     */
    get hasErrors() {
        return this.error !== undefined;
    }
    
    /**
     * @description Get error message
     */
    get errorMessage() {
        return this.error || 'An unexpected error occurred';
    }
    
    /**
     * @description Get modal title based on mode
     */
    get modalTitle() {
        if (this.isCreateMode) {
            return 'Create Prompt Catalogue';
        }
        return `Edit ${this.editCardName}`;
    }
    
    /**
     * @description Check if in edit mode (Name field should be disabled)
     */
    get isEditMode() {
        return !this.isCreateMode && this.editRecordId !== null;
    }
    
    /**
     * @description Check if showing purpose view (cards)
     */
    get isPurposeView() {
        return this.currentView === 'purpose';
    }
    
    /**
     * @description Check if showing configuration view (table)
     */
    get isConfigurationView() {
        return this.currentView === 'configuration';
    }
    
    /**
     * @description Check if showing deployment view
     */
    get isDeploymentView() {
        return this.currentView === 'deployment';
    }
    
    /**
     * @description Check if any prompts are selected
     */
    get hasSelectedPrompts() {
        return this.selectedPrompts && this.selectedPrompts.length > 0;
    }
    
    /**
     * @description Get selected prompts formatted for deployment component
     */
    get selectedPromptsForDeployment() {
        return this.selectedPrompts;
    }
    
    /**
     * @description Get progress bar classes for Purpose
     */
    get purposeStepClass() {
        return this.currentView === 'purpose' ? 'progress-step progress-complete' : 'progress-step progress-complete';
    }
    
    /**
     * @description Get progress bar classes for Configuration
     */
    get configurationStepClass() {
        if (this.currentView === 'configuration') {
            return 'progress-step progress-current';
        } else if (this.currentView === 'deployment') {
            return 'progress-step progress-complete';
        }
        return 'progress-step';
    }
    
    /**
     * @description Get progress line class
     */
    get progressLineClass() {
        return (this.currentView === 'configuration' || this.currentView === 'deployment') 
            ? 'progress-line progress-line-active' 
            : 'progress-line';
    }
    
    /**
     * @description Get stage filter options
     */
    get stageOptions() {
        return [
            { label: 'All Stages', value: '' },
            { label: 'Purpose', value: 'purpose' },
            { label: 'Configuration', value: 'configuration' },
            { label: 'Deployment', value: 'deployment' }
        ];
    }
    
    /**
     * @description Get purpose filter options from available cards
     */
    get purposeOptions() {
        const options = [{ label: 'All Purposes', value: '' }];
        if (this.cards && this.cards.length > 0) {
            this.cards.forEach(card => {
                options.push({
                    label: card.Name,
                    value: card.Name
                });
            });
        }
        return options;
    }
    
    /**
     * @description Get total prompts count for metrics card
     */
    get totalPromptsCount() {
        return this.metrics.totalPrompts || 0;
    }
    
    /**
     * @description Get active prompts count for metrics card
     */
    get activePromptsCount() {
        return this.metrics.activePrompts || 0;
    }
    
    /**
     * @description Get total hours saved for metrics card
     */
    get totalHoursSaved() {
        return this.metrics.totalHoursSaved || 0;
    }
    
    /**
     * @description Get total cost saved for metrics card (formatted for display)
     */
    get totalCostSaved() {
        return this.formatMoneySavedForDisplay(this.metrics.costSaved || 0);
    }
    
    /**
     * @description Get ROI percentage for metrics card
     */
    get roiPercentage() {
        return `ROI ${this.metrics.roi || 0}%`;
    }
    
    // ================== HELPER METHODS ==================
    
    /**
     * @description Get card CSS class based on category
     */
    getCardClass(card) {
        const cardName = card.name || card.Name || card.MasterLabel || '';
        const category = this.getCategoryFromName(cardName);
        const colorClass = this.categoryColors[category] || 'catalog-card';
        return `catalog-card ${colorClass}`;
    }
    
    /**
     * @description Extract category from card name
     */
    getCategoryFromName(name) {
        if (name.toLowerCase().includes('sales') || name.toLowerCase().includes('boost')) {
            return 'Sales Acceleration';
        }
        if (name.toLowerCase().includes('customer') || name.toLowerCase().includes('support')) {
            return 'Support & Retention';
        }
        if (name.toLowerCase().includes('service')) {
            return 'Service Optimization';
        }
        if (name.toLowerCase().includes('renewal') || name.toLowerCase().includes('revenue')) {
            return 'Revenue Operations';
        }
        if (name.toLowerCase().includes('stakeholder') || name.toLowerCase().includes('relationship')) {
            return 'Relationship Management';
        }
        return 'General';
    }
    
    /**
     * @description Format cost for display
     */
    formatCost(cost) {
        if (cost >= 1000) {
            return Math.round(cost / 1000) + 'k';
        }
        return cost.toString();
    }
    
    /**
     * @description Format currency with k for thousands
     */
    formatCurrency(value) {
        if (!value) return '0';
        if (value >= 1000) {
            return (value / 1000).toFixed(value % 1000 === 0 ? 0 : 1) + 'k';
        }
        return Math.round(value).toString();
    }
    
    /**
     * @description Format value as dollar with decimals and thousand separators
     * @param {Number} value - The value to format
     * @returns {String} Formatted dollar string (e.g., $15,234.50)
     */
    formatDollar(value) {
        if (!value || value === 0) return '$0.00';
        
        // Convert to number and format with 2 decimal places
        const numValue = Number(value);
        
        // Use Intl.NumberFormat for proper currency formatting with comma separators
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(numValue);
    }
    
    /**
     * @description Format money saved for metric card display (abbreviated format for visual appeal)
     * @param {Number} value - The value to format
     * @returns {String} Formatted string (e.g., $123, $1.2K, $45.6K, $1.2M)
     */
    formatMoneySavedForDisplay(value) {
        if (!value || value === 0) return '$0';
        
        const numValue = Number(value);
        
        // For values >= 1 million, show as $X.XM
        if (numValue >= 1000000) {
            const millions = numValue / 1000000;
            return '$' + (millions % 1 === 0 ? millions.toFixed(0) : millions.toFixed(1)) + 'M';
        }
        
        // For values >= 1000, show as $X.XK
        if (numValue >= 1000) {
            const thousands = numValue / 1000;
            return '$' + (thousands % 1 === 0 ? thousands.toFixed(0) : thousands.toFixed(1)) + 'K';
        }
        
        // For values < 1000, show as rounded dollar amount
        return '$' + Math.round(numValue);
    }
    
    /**
     * @description Get random prompt count for demo
     */
    getRandomPromptCount() {
        return Math.floor(Math.random() * 10) + 8 + '/' + (Math.floor(Math.random() * 10) + 15);
    }
    
    /**
     * @description Get random time saved for demo
     */
    getRandomTimeSaved() {
        return Math.floor(Math.random() * 10) + 4;
    }
    
    /**
     * @description Get random cost saved for demo
     */
    getRandomCostSaved() {
        const amounts = ['2k', '407', '350'];
        return amounts[Math.floor(Math.random() * amounts.length)];
    }
    
    // ================== DATA LOADING METHODS ==================
    
    /**
     * @description Load cards imperatively from AddCardController
     */
    async loadCards() {
        this.isLoading = true;
        try {
            const result = await getCardConfiguration({ feature: 'CTLOG' });
            
            // Extract data from AddCardController.getCardConfiguration response
            const cardsData = result || [];
            
            // Calculate overall metrics
            let totalPromptsSum = 0;
            let activePromptsSum = 0;
            let totalHoursSaved = 0;
            let totalMoneySaved = 0;
            
            this.cards = cardsData.map(dataWrap => {
                const mdt = dataWrap.mdtRecord;
                const matrics1 = dataWrap.matrics1 || '0/0 Prompts Deployed';
                const matrics2 = dataWrap.matrics2 || '0 Hours / 0 Saved';
                
                // Parse matrics1: "1/5 Prompts Deployed" -> activePrompts=1, totalPrompts=5
                const promptMatch = matrics1.match(/(\d+)\/(\d+)\s+Prompts/);
                const activePrompts = promptMatch ? parseInt(promptMatch[1], 10) : 0;
                const totalPrompts = promptMatch ? parseInt(promptMatch[2], 10) : 0;
                
                // Parse matrics2: "2 Hours / $100 Saved" or "2k Hours / $5k Saved"
                const metricsMatch = matrics2.match(/([\d.]+k?)\s+Hours\s+\/\s+\$([\d.]+k?)\s+Saved/);
                let timeSaved = '0';
                let costSaved = '0';
                
                if (metricsMatch) {
                    timeSaved = metricsMatch[1];
                    costSaved = '$' + metricsMatch[2];
                    
                    // Calculate numeric values for totals
                    const timeValue = timeSaved.includes('k') ? parseFloat(timeSaved) * 1000 : parseFloat(timeSaved);
                    const costValue = metricsMatch[2].includes('k') ? parseFloat(metricsMatch[2]) * 1000 : parseFloat(metricsMatch[2]);
                    
                    totalHoursSaved += timeValue || 0;
                    totalMoneySaved += costValue || 0;
                }
                
                // Accumulate totals
                totalPromptsSum += totalPrompts;
                activePromptsSum += activePrompts;
                
                // Debug logging
                console.log('=== CARD DATA DEBUG ===');
                console.log('Raw dataWrap from Apex:', JSON.stringify(dataWrap));
                console.log('mdt.Id:', mdt.Id);
                console.log('mdt.MasterLabel:', mdt.MasterLabel);
                console.log('mdt.Description:', mdt.Description);
                
                const mappedCard = {
                    Id: mdt.Id,
                    Name: mdt.MasterLabel || '[NO NAME FROM APEX]',
                    description: mdt.Description || '',
                    iconDetails: mdt.Icon_Details,
                    iconSource: mdt.Icon_Source,
                    hasStaticResource: mdt.Icon_Source === 'Static Resource',
                    sequence: mdt.Sequence,
                    enabled: mdt.Enabled,
                    feature: mdt.Card_Type,
                    totalPrompts: totalPrompts,
                    activePrompts: activePrompts,
                    timeSaved: timeSaved,
                    costSaved: costSaved,
                    costSavedFormatted: costSaved,
                    cardClass: this.getCardClass(mdt)
                };
                
                console.log('Mapped card for UI:', JSON.stringify(mappedCard));
                console.log('mappedCard.Name:', mappedCard.Name);
                console.log('mappedCard.description:', mappedCard.description);
                console.log('mappedCard.iconSource:', mappedCard.iconSource);
                console.log('mappedCard.iconDetails:', mappedCard.iconDetails);
                console.log('mappedCard.hasStaticResource:', mappedCard.hasStaticResource);
                console.log('======================');
                
                return mappedCard;
            });
            
            console.log('Final cards array:', this.cards);
            console.log('Total cards count:', this.cards.length);
            console.log('Total money saved:', totalMoneySaved);
            console.log('Total hours saved:', totalHoursSaved);
            
            // Update overall metrics
            const calculatedRoi = totalMoneySaved > 0 ? Math.min(75, Math.round((totalMoneySaved / 10))) : 0;
            
            this.metrics = {
                totalPrompts: totalPromptsSum,
                activePrompts: activePromptsSum,
                hoursSaved: totalHoursSaved,
                costSaved: totalMoneySaved,
                costSavedFormatted: this.formatDollar(totalMoneySaved),
                roi: calculatedRoi
            };
            
            this.error = undefined;
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * @description Fetch purpose options and prompt data from CatalogController
     */
    async fetchPurposeOptions() {
        try {
            const result = await getPurposeOptions();
            
            if (result && result.profileOptions && result.profileOptions.length > 0) {
                this.profileOptions = JSON.parse(JSON.stringify(result.profileOptions));
            }
            if (result && result.recTypeOptions) {
                this.recTypeOptions = JSON.parse(JSON.stringify(result.recTypeOptions));
            }
            if (result && result.extractOptions) {
                this.extractOptions = JSON.parse(JSON.stringify(result.extractOptions));
            }
            if (result && result.promptData) {
                this.promptData = JSON.parse(JSON.stringify(result.promptData));
            }
        } catch (error) {
            this.handleError(error);
        }
    }
    
    /**
     * @description Handle AI automation step - load prompts from promptData
     */
    handleAiAutomationStep() {
        this.prompts = [];
        if (this.promptData && this.promptData.hasOwnProperty(this.selectedPurpose)) {
            // Map the prompt data to the format expected by the datatable
            const purposePrompts = JSON.parse(JSON.stringify(this.promptData[this.selectedPurpose]));
            this.prompts = purposePrompts.map(prompt => ({
                id: prompt.pmtId,
                promptName: prompt.name,
                primaryObject: prompt.objectName,
                connection: prompt.aiConnectionName,
                description: prompt.description,
                status: prompt.status,
                pmtId: prompt.pmtId,
                pmtUrl: prompt.pmtUrl,
                aiConnection: prompt.aiConnection,
                aiConnectionName: prompt.aiConnectionName,
                name: prompt.name,
                objectName: prompt.objectName,
                profileNames: prompt.profileNames || [],
                recordTypes: prompt.recordTypes || [],
                visibilityCondition: prompt.visibilityCondition || '',
                pickListOptions: prompt.pickListOptions
            }));
        }
    }
    
    // ================== EVENT HANDLERS ==================
    
    // Grid/List toggle handlers removed - always showing grid view
    // /**
    //  * @description Handle grid view toggle
    //  */
    // handleGridView() {
    //     this.isGridView = true;
    // }
    
    // /**
    //  * @description Handle list view toggle
    //  */
    // handleListView() {
    //     this.isGridView = false;
    // }
    
    /**
     * @description Handle edit card action - opens modal
     */
    handleEditCard(event) {
        event.stopPropagation();
        const cardId = event.currentTarget.dataset.id;
        this.editRecordId = cardId;
        this.isCreateMode = false;
        
        // Find the card to get its name
        const card = this.cards.find(c => c.Id === cardId);
        this.editCardName = card ? card.Name : '';
        
        this.showEditModal = true;
    }
    
    /**
     * @description Handle card click - switch to configuration view and load prompts
     */
    handleCardClick(event) {
        // Only navigate if not clicking on the edit button
        if (!event.target.closest('.edit-button')) {
            const cardId = event.currentTarget.dataset.id;
            const card = this.cards.find(c => c.Id === cardId);
            
            if (card) {
                this.selectedPurpose = card.Name;
                this.handleAiAutomationStep();
                
                if (this.prompts && this.prompts.length > 0) {
                    this.currentView = 'configuration';
                } else {
                    this.selectedPurpose = '';
                    this.showToast(
                        'No Prompts Found', 
                        `No Prompts exists for the selected Purpose: "${card.Name}".`, 
                        'error'
                    );
                }
            }
        }
    }
    
    /**
     * @description Handle purpose step click - go back to cards view
     */
    handlePurposeClick() {
        this.currentView = 'purpose';
        this.selectedPurpose = '';
        this.prompts = [];
        this.selectedPrompts = [];
        this.selectedPromptIds = [];
    }
    
    /**
     * @description Handle configuration step click - go to configuration view
     */
    handleConfigurationClick() {
        if (this.currentView === 'deployment' && this.selectedPurpose) {
            this.currentView = 'configuration';
        }
    }
    
    /**
     * @description Handle row selection in datatable
     */
    handleRowSelection(event) {
        this.selectedPrompts = event.detail.selectedRows;
        this.selectedPromptIds = this.selectedPrompts.map(row => row.id);
    }
    
    /**
     * @description Handle Previous button in configuration view
     */
    handleConfigurationPrevious() {
        this.currentView = 'purpose';
        this.selectedPurpose = '';
        this.selectedPrompts = [];
        this.selectedPromptIds = [];
    }
    
    /**
     * @description Handle Next button in configuration view - navigate to deployment
     */
    async handleConfigurationNext() {
        if (this.selectedPrompts && this.selectedPrompts.length > 0) {
            await this.loadDeploymentData();
            this.currentView = 'deployment';
        } else {
            this.showToast('Error', 'Please select at least one prompt.', 'error');
        }
    }
    
    /**
     * @description Handle Previous button from deployment view
     */
    handleDeploymentPrevious() {
        this.currentView = 'configuration';
    }
    
    /**
     * @description Handle Finish button from deployment view
     */
    async handleDeploymentFinish() {
        try {
            // Validate that at least one profile is selected for each prompt
            const missingProfiles = this.selectedMappings.filter(map => 
                !map.profileNames || map.profileNames.length === 0
            );
            
            if (missingProfiles.length > 0) {
                this.showToast('Error', 'Please select at least one profile for each prompt.', 'error');
                return;
            }
            
            this.isLoadingDeployment = true;
            
            // Save deployment configuration
            await updatePromptData({ data: this.selectedMappings });
            
            this.isLoadingDeployment = false;
            this.showToast('Success', 'Prompts enabled successfully!', 'success');
            
            // Navigate back to purpose view and reset state
            this.currentView = 'purpose';
            this.selectedPurpose = '';
            this.prompts = [];
            this.selectedPrompts = [];
            this.selectedPromptIds = [];
            this.selectedMappings = [];
            
            // Refresh cards
            await this.loadCards();
            
        } catch (error) {
            this.isLoadingDeployment = false;
            console.error('Error in deployment finish:', error);
            
            let errorMessage = 'Failed to enable prompts';
            if (error && error.body && error.body.message) {
                errorMessage = error.body.message;
            } else if (typeof error === 'string') {
                errorMessage = error;
            } else if (error && error.message) {
                errorMessage = error.message;
            }
            
            this.showToast('Error', errorMessage, 'error');
        }
    }
    
    /**
     * @description Load deployment data (profiles, record types) and initialize mappings
     */
    async loadDeploymentData() {
        this.isLoadingDeployment = true;
        
        try {
            // Profile options and record type options are already loaded in connectedCallback
            // Just initialize selected mappings from selected prompts
            this.initializeSelectedMappings();
            
        } catch (error) {
            console.error('Error loading deployment data:', error);
            this.showToast('Error', 'Failed to load deployment options', 'error');
        } finally {
            this.isLoadingDeployment = false;
        }
    }
    
    /**
     * @description Initialize selected mappings with record type options
     */
    initializeSelectedMappings() {
        if (this.selectedPrompts && this.selectedPrompts.length > 0) {
            this.selectedMappings = JSON.parse(JSON.stringify(this.selectedPrompts));
            console.log('selectedMappings', JSON.parse(JSON.stringify(this.selectedPrompts)));
            // Add record type options for each mapping based on object
            for (let rec of this.selectedMappings) {
                const oName = rec['primaryObject'] || rec['objectName'];
                if (this.recTypeOptions && this.recTypeOptions.hasOwnProperty(oName)) {
                    rec['recordTypeOptions'] = this.recTypeOptions[oName];
                }
                
                // Add pmtId if not present (use id field)
                if (!rec['pmtId'] && rec['id']) {
                    rec['pmtId'] = rec['id'];
                }
                
                // Add pmtUrl if not present (construct from id)
                if (!rec['pmtUrl'] && rec['id']) {
                    rec['pmtUrl'] = '/' + rec['id'];
                }
                
                // Initialize arrays if not present (keep existing values from Apex)
                if (!rec['profileNames'] || !Array.isArray(rec['profileNames'])) {
                    rec['profileNames'] = [];
                }
                if (!rec['recordTypes'] || !Array.isArray(rec['recordTypes'])) {
                    rec['recordTypes'] = [];
                }
                if (rec['visibilityCondition'] === undefined || rec['visibilityCondition'] === null) {
                    rec['visibilityCondition'] = '';
                }
            }
        }
    }
    
    /**
     * @description Handle profile selection change in deployment
     * @param {Event} event - Change event from dual listbox
     */
    handleDeploymentProfileChange(event) {
        const index = event.target.dataset.id;
        this.selectedMappings[index].profileNames = event.target.value;
    }
    
    /**
     * @description Handle record type selection change in deployment
     * @param {Event} event - Change event from dual listbox
     */
    handleDeploymentRecordTypeChange(event) {
        const index = event.target.dataset.id;
        this.selectedMappings[index].recordTypes = event.target.value;
    }
    
    /**
     * @description Handle visibility condition text change in deployment
     * @param {Event} event - Change event from textarea
     */
    handleDeploymentVisibilityConditionChange(event) {
        const index = event.target.dataset.index;
        this.selectedMappings[index].visibilityCondition = event.target.value;
    }
    
    /**
     * @description Open visibility condition modal for formula builder
     * @param {Event} event - Click event from button
     */
    async handleOpenDeploymentVisibilityCondition(event) {
        const index = event.target.dataset.index;
        const objectName = event.target.dataset.objectname;
        
        try {
            const result = await AiPromptWhereClauseFormulaComponent.open({
                size: 'medium',
                description: 'Visibility Condition',
                objectApiName: objectName
            });
            
            if (result) {
                this.selectedMappings[index].visibilityCondition = result;
            }
        } catch (error) {
            console.error('Error opening visibility condition modal:', error);
        }
    }
    
    /**
     * @description Handle purpose filter change
     */
    handlePurposeFilter(event) {
        this.selectedPurpose = event.detail.value;
        if (this.selectedPurpose) {
            this.handleAiAutomationStep();
        } else {
            // If "All Purposes" is selected, clear the prompts
            this.prompts = [];
        }
    }
    
    // Note: fetchPrompts() method removed - now using handleAiAutomationStep() 
    // which loads prompts from this.promptData populated by fetchPurposeOptions()
    
    /**
     * @description Close the edit modal
     */
    handleCloseModal() {
        this.showEditModal = false;
        this.editRecordId = null;
        this.editCardName = '';
        this.isCreateMode = false;
    }
    
    /**
     * @description Handle save button click - submit the form
     */
    handleSaveClick(event) {
        event.preventDefault();
        // Find the lightning-record-edit-form and submit it
        const form = this.template.querySelector('lightning-record-edit-form');
        if (form) {
            form.submit();
        }
    }
    
    /**
     * @description Handle form successful save - refresh data and close modal
     */
    handleFormSuccess(event) {
        const successMessage = this.isCreateMode 
            ? 'Prompt Catalogue created successfully' 
            : 'Prompt Catalogue updated successfully';
        
        this.showToast('Success', successMessage, 'success');
        this.showEditModal = false;
        this.editRecordId = null;
        this.editCardName = '';
        this.isCreateMode = false;
        
        // Refresh the card data to reflect changes in real-time
        return this.loadCards();
    }
    
    /**
     * @description Handle save error
     */
    handleSaveError(event) {
        this.showToast('Error', 'Error updating Prompt Catalogue: ' + event.detail.message, 'error');
    }
    
    /**
     * @description Handle delete button click - deletes the catalogue
     */
    handleDelete() {
        // Confirm deletion
        const confirmDelete = confirm(`Are you sure you want to delete "${this.editCardName}"? This action cannot be undone.`);
        
        if (!confirmDelete) {
            return;
        }
        
        // Delete the record
        deleteRecord(this.editRecordId)
            .then(() => {
                this.showToast('Success', `"${this.editCardName}" has been deleted successfully`, 'success');
                
                // Close modal
                this.showEditModal = false;
                this.editRecordId = null;
                this.editCardName = '';
                this.isCreateMode = false;
                
                // Refresh the card data to remove the deleted card from UI
                return this.loadCards();
            })
            .catch(error => {
                this.showToast(
                    'Error', 
                    'Error deleting Prompt Catalogue: ' + (error.body?.message || error.message || 'Unknown error'), 
                    'error'
                );
            });
    }
    
    /**
     * @description Handle new prompt button - opens aIPromptOverride component
     */
    handleNewPrompt() {
        this.isShowNewPromptComp = true;
    }
    
    /**
     * @description Handle close event from aIPromptOverride component
     */
    async handleHideNewPrompt() {
        this.isShowNewPromptComp = false;
        
        // Refresh the prompt data and cards
        await this.fetchPurposeOptions();
        await this.loadCards();
        
        // Refresh the prompts if user is in configuration view
        if (this.currentView === 'configuration' && this.selectedPurpose) {
            this.handleAiAutomationStep();
        }
    }
    
    /**
     * @description Handle create new catalog - opens modal for creating new catalogue
     */
    handleCreateNew() {
        this.editRecordId = null;
        this.editCardName = '';
        this.isCreateMode = true;
        this.showEditModal = true;
    }
    
    /**
     * @description Handle refresh action
     */
    handleRefresh() {
        window.location.reload();
    }
    
    // ================== NAVIGATION METHODS ==================
    
    /**
     * @description Navigate to record page
     */
    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }
    
    /**
     * @description Navigate to external URL
     */
    navigateToUrl(url) {
        if (url) {
            window.open(url, '_blank');
        }
    }
    
    // ================== ERROR HANDLING ==================
    
    /**
     * @description Handle errors
     */
    handleError(error) {
        let message = 'An unexpected error occurred';
        
        if (error && error.body) {
            if (Array.isArray(error.body)) {
                message = error.body.map(e => e.message).join(', ');
            } else if (typeof error.body.message === 'string') {
                message = error.body.message;
            }
        } else if (typeof error === 'string') {
            message = error;
        }
        
        this.error = message;
        this.showToast('Error', message, 'error');
    }
    
    /**
     * @description Show toast notification
     */
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}