/**
 * @description AI Advance Agent Builder Lightning Web Component
 *              Enables users to create AI agents using natural language descriptions
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @jira V2-7442
 */
import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import gptfyLogo from '@salesforce/resourceUrl/gptfylogo';
import getAgenticPrompts from '@salesforce/apex/AIAdvanceAgentBuilderController.getAgenticPrompts';
import generateAgentDetails from '@salesforce/apex/AIAdvanceAgentBuilderController.generateAgentDetails';
import createAgent from '@salesforce/apex/AIAdvanceAgentBuilderController.createAgent';
import getActiveAgents from '@salesforce/apex/AIAdvanceAgentBuilderController.getActiveAgents';
import getNamespace from '@salesforce/apex/AIAdvanceAgentBuilderController.getNamespace';

// Import Custom Labels
import helpdeskDescription from '@salesforce/label/c.AI_Agent_Builder_Pill_Helpdesk_Description';
import salesDescription from '@salesforce/label/c.AI_Agent_Builder_Pill_Sales_Description';
import supportDescription from '@salesforce/label/c.AI_Agent_Builder_Pill_Support_Description';

// Import Object Schema
import AI_AGENT_OBJECT from '@salesforce/schema/AI_Agent__c';

export default class AIAdvanceAgentBuilder extends NavigationMixin(LightningElement) {
    // ==================== CONSTANTS ====================
    static TYPING_SPEED_MS = 50;
    static PLACEHOLDER_DELAY_MS = 10000;
    
    // ==================== TRACKED PROPERTIES ====================
    @track userInput = '';
    @track isProcessing = false;
    @track isLoadingAgents = true;
    @track existingAgents = [];
    @track availablePrompts = [];
    @track currentPlaceholder = '';
    @track namespace = '';
    
    // ==================== PROPERTIES ====================
    placeholderTexts = [
        'Create an agent to help with customer support and answer common questions...',
        'Build an agent that analyzes sales data and provides insights for better decision making...',
        'Design an agent to automate invoice processing and expense approvals...'
    ];
    
    currentPlaceholderIndex = 0;
    placeholderInterval;
    typingTimeout;
    currentCharIndex = 0;
    isUserTyping = false;
    
    // Getter for GPTfy logo
    get gptfyLogoUrl() {
        return gptfyLogo;
    }
    
    pillSuggestions = [
        {
            label: 'Helpdesk',
            key: 'helpdesk',
            description: helpdeskDescription
        },
        {
            label: 'Sales Agent',
            key: 'sales',
            description: salesDescription
        },
        {
            label: 'Support Agent',
            key: 'support',
            description: supportDescription
        }
    ];
    
    // ==================== LIFECYCLE HOOKS ====================
    
    /**
     * Lifecycle hook called when component is inserted into DOM
     * @jira V2-7442
     */
    connectedCallback() {
        this.loadExistingAgents();
        this.fetchNamespace();
        this.startTypingPlaceholder();
    }
    
    /**
     * Lifecycle hook called when component is removed from DOM
     * Cleans up intervals and timeouts
     */
    disconnectedCallback() {
        if (this.placeholderInterval) {
            clearInterval(this.placeholderInterval);
        }
        if (this.typingTimeout) {
            clearTimeout(this.typingTimeout);
        }
    }
    
    /**
     * Fetches the namespace from Apex
     * Used for namespaced navigation
     * @jira V2-7442
     */
    async fetchNamespace() {
        try {
            this.namespace = await getNamespace();
        } catch (error) {
            console.error('Error fetching namespace:', error);
            this.namespace = '';
        }
    }
    
    // ==================== PLACEHOLDER ANIMATION ====================
    
    /**
     * Starts the typing animation for placeholder text
     */
    startTypingPlaceholder() {
        if (this.typingTimeout) {
            clearTimeout(this.typingTimeout);
        }
        
        this.currentCharIndex = 0;
        this.currentPlaceholder = '';
        this.typeNextCharacter();
    }
    
    /**
     * Types the next character in the placeholder animation
     */
    typeNextCharacter() {
        const fullText = this.placeholderTexts[this.currentPlaceholderIndex];
        
        if (this.currentCharIndex < fullText.length) {
            this.currentPlaceholder = fullText.substring(0, this.currentCharIndex + 1);
            this.currentCharIndex++;
            
            this.typingTimeout = setTimeout(() => {
                this.typeNextCharacter();
            }, AIAdvanceAgentBuilder.TYPING_SPEED_MS);
        } else {
            this.typingTimeout = setTimeout(() => {
                this.currentPlaceholderIndex = (this.currentPlaceholderIndex + 1) % this.placeholderTexts.length;
                this.startTypingPlaceholder();
            }, AIAdvanceAgentBuilder.PLACEHOLDER_DELAY_MS);
        }
    }
    
    /**
     * Stops the typing effect animation
     */
    stopTypingEffect() {
        if (this.typingTimeout) {
            clearTimeout(this.typingTimeout);
            this.typingTimeout = null;
        }
    }
    
    // ==================== EVENT HANDLERS ====================
    
    /**
     * Handles input change in the textarea
     * @param {Event} event - Input event
     */
    handleInputChange(event) {
        this.userInput = event.target.value;
        this.isUserTyping = true;
        
        if (this.userInput && this.userInput.length > 0) {
            this.stopTypingEffect();
            this.currentPlaceholder = '';
        } else if (!this.userInput || this.userInput.length === 0) {
            this.isUserTyping = false;
            this.startTypingPlaceholder();
        }
    }
    
    /**
     * Handles pill button click
     * @param {Event} event - Click event
     */
    handlePillClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const pillLabel = event.currentTarget.dataset.label;
        const selectedPill = this.pillSuggestions.find(pill => pill.label === pillLabel);
        
        if (selectedPill && selectedPill.description) {
            this.stopTypingEffect();
            this.currentPlaceholder = '';
            this.isUserTyping = true;
            this.userInput = selectedPill.description;
            
            setTimeout(() => {
                const textarea = this.template.querySelector('.search-input');
                if (textarea) {
                    textarea.value = selectedPill.description;
                    textarea.focus();
                }
            }, 50);
        }
    }
    
    /**
     * Handles Enter key press in textarea
     * @param {Event} event - Keydown event
     */
    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSubmit();
        }
    }
    
    /**
     * Handles submit button click
     * Creates agent using AI-generated details (parsed server-side)
     * @jira V2-7442
     */
    async handleSubmit() {
        if (!this.userInput || this.userInput.trim() === '') {
            this.showToast('Warning', 'Please describe your agent', 'warning');
            return;
        }
        if (this.userInput.trim().length < 10) {
            this.showToast('Warning', 'Please describe your agent in more detail (at least 10 characters)', 'warning');
            return;
        }
        
        this.isProcessing = true;
        
        try {
            // Load available prompts if not already loaded
            if (this.availablePrompts.length === 0) {
                this.availablePrompts = await getAgenticPrompts();
            }
            
            // Prepare prompts data for AI
            const promptsJson = JSON.stringify(
                this.availablePrompts.map(p => ({ id: p.Id, name: p.Name }))
            );
            
            // Call AI to generate agent details - parsing is done server-side
            const agentDetails = await generateAgentDetails({ 
                userInput: this.userInput,
                promptsJson: promptsJson
            });
            
            // Check if parsing was successful
            if (!agentDetails || !agentDetails.success) {
                const errorMsg = agentDetails?.errorMessage || 'Failed to generate agent details';
                throw new Error(errorMsg);
            }
            
            // Create the agent using the parsed wrapper data
            const agentId = await createAgent({
                agentName: agentDetails.name,
                description: agentDetails.description,
                systemPrompt: agentDetails.systemPrompt,
                welcomeMessage: agentDetails.welcomeMessage,
                skillIds: agentDetails.selectedSkillIds || []
            });
            
            this.showToast('Success', 'Agent created successfully!', 'success');
            
            // Navigate to the agent record page (will use aIAgentCreationOverride as the override)
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: agentId,
                    objectApiName: AI_AGENT_OBJECT.objectApiName,
                    actionName: 'view'
                }
            });
            
        } catch (error) {
            console.error('Error creating agent:', error);
            this.showToast('Error', 
                'Failed to create agent: ' + (error.body?.message || error.message), 
                'error'
            );
        } finally {
            this.isProcessing = false;
        }
    }
    
    /**
     * Handles agent card click
     * Navigates to agent record page
     * @param {Event} event - Click event
     */
    handleAgentClick(event) {
        // Use currentTarget to get the element with the event listener (the article element)
        // This ensures we get the correct element even when clicking on child elements
        const agentId = event.currentTarget.dataset.agentId;
        
        if (!agentId) {
            console.error('Agent ID not found');
            return;
        }
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: agentId,
                objectApiName: AI_AGENT_OBJECT.objectApiName,
                actionName: 'view'
            },
            state: {
                c__recordId: agentId
            }
        });
    }
    
    // ==================== DATA LOADING ====================
    
    /**
     * Loads existing agents from the database
     * @jira V2-7442
     */
    async loadExistingAgents() {
        this.isLoadingAgents = true;
        try {
            const data = await getActiveAgents();
            // The description is now created server-side in the AgentListWrapper
            this.existingAgents = data.map(agent => {
                return {
                    ...agent,
                    iconName: this.getAgentIcon(agent.status),
                    isActive: agent.status === 'Active',
                    isDraft: agent.status !== 'Active'
                };
            });
        } catch (error) {
            this.showToast('Error', 'Failed to load agents', 'error');
        } finally {
            this.isLoadingAgents = false;
        }
    }
    
    // ==================== HELPER METHODS ====================
    
    /**
     * Gets icon name based on agent status
     * @param {String} status - Agent status
     * @return {String} Icon name
     */
    getAgentIcon(status) {
        const icons = {
            'Active': 'standard:bot',
            'Draft': 'standard:drafts'
        };
        return icons[status] || 'standard:bot';
    }
    
    /**
     * Shows toast notification
     * @param {String} title - Toast title
     * @param {String} message - Toast message
     * @param {String} variant - Toast variant (success, error, warning, info)
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