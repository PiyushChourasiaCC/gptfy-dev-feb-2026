/**
 * @description AI-powered Prompt Builder Lightning Web Component
 *              Enables users to create AI prompts using natural language descriptions.
 *              The component provides an intuitive interface with example suggestions,
 *              animated placeholders, and real-time AI-powered prompt generation.
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @jira V2-7442
 */
import { LightningElement, track, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Import Apex methods
import generatePromptDetails from '@salesforce/apex/AIAdvancePromptBuilderController.generatePromptDetails';
import createPromptWithMapping from '@salesforce/apex/AIAdvancePromptBuilderController.createPromptWithMapping';
import getExistingPrompts from '@salesforce/apex/AIAdvancePromptBuilderController.getExistingPrompts';
import getNamespace from '@salesforce/apex/AIAdvancePromptBuilderController.getNamespace';

// Import Static Resource
import GPTFY_LOGO from '@salesforce/resourceUrl/gptfylogo';

// Import Custom Labels for Example Prompts
import LABEL_ACCOUNT_ANALYSIS from '@salesforce/label/c.AI_Example_Prompt_Account_Analysis';
import LABEL_CASE_INSIGHTS from '@salesforce/label/c.AI_Example_Prompt_Case_Insights';
import LABEL_OPPORTUNITY_RECOMMENDATIONS from '@salesforce/label/c.AI_Example_Prompt_Opportunity_Recommendations';
import LABEL_CONTACT_SUMMARY from '@salesforce/label/c.AI_Example_Prompt_Contact_Summary';

// Import Custom Labels for UI Text
import LABEL_PLACEHOLDER_1 from '@salesforce/label/c.AI_Prompt_Builder_Placeholder_1';
import LABEL_PLACEHOLDER_2 from '@salesforce/label/c.AI_Prompt_Builder_Placeholder_2';
import LABEL_PLACEHOLDER_3 from '@salesforce/label/c.AI_Prompt_Builder_Placeholder_3';
import LABEL_PLACEHOLDER_4 from '@salesforce/label/c.AI_Prompt_Builder_Placeholder_4';
import LABEL_PILL_ACCOUNT from '@salesforce/label/c.AI_Prompt_Builder_Pill_Account';
import LABEL_PILL_CASE from '@salesforce/label/c.AI_Prompt_Builder_Pill_Case';
import LABEL_PILL_OPPORTUNITY from '@salesforce/label/c.AI_Prompt_Builder_Pill_Opportunity';
import LABEL_PILL_CONTACT from '@salesforce/label/c.AI_Prompt_Builder_Pill_Contact';
import LABEL_ERROR_EMPTY_INPUT from '@salesforce/label/c.AI_Prompt_Builder_Error_Empty_Input';
import LABEL_ERROR_PARSE_FAILED from '@salesforce/label/c.AI_Prompt_Builder_Error_Parse_Failed';
import LABEL_SUCCESS_CREATED from '@salesforce/label/c.AI_Prompt_Builder_Success_Created';
import LABEL_ERROR_CREATE_FAILED from '@salesforce/label/c.AI_Prompt_Builder_Error_Create_Failed';

// Import Schema for Object API Names
import AI_PROMPT_OBJECT from '@salesforce/schema/AI_Prompt__c';

export default class AIAdvancePromptBuilder extends NavigationMixin(LightningElement) {
    // ==================== CONSTANTS ====================
    static TYPING_SPEED_MS = 30;
    static PLACEHOLDER_DELAY_MS = 3000;
    
    // ==================== API PROPERTIES ====================
    /**
     * Navigation tab name for back button navigation
     * If provided: Navigate to the specified tab
     * If not provided: Navigate to AI_Prompt__c list view
     */
    @api navigationTabName;
    
    // ==================== TRACKED PROPERTIES ====================
    @track userInput = '';
    @track isProcessing = false;
    @track namespace = '';
    @track currentPlaceholder = '';
    @track showPromptOverride = false;
    
    // ==================== PROPERTIES ====================
    gptfyLogoUrl = GPTFY_LOGO;
    @track aiPromptObjectApiName = AI_PROMPT_OBJECT.objectApiName;
    
    // Placeholder texts from custom labels
    placeholderTexts = [
        LABEL_PLACEHOLDER_1,
        LABEL_PLACEHOLDER_2,
        LABEL_PLACEHOLDER_3,
        LABEL_PLACEHOLDER_4
    ];
    
    // Pill suggestions from custom labels
    pillSuggestions = [
        { label: LABEL_PILL_ACCOUNT, key: 'account' },
        { label: LABEL_PILL_CASE, key: 'case' },
        { label: LABEL_PILL_OPPORTUNITY, key: 'opportunity' },
        { label: LABEL_PILL_CONTACT, key: 'contact' }
    ];
    
    // Animation state
    currentPlaceholderIndex = 0;
    placeholderInterval;
    typingTimeout;
    currentCharIndex = 0;
    isUserTyping = false;
    hasRendered = false;
    
    // ==================== LIFECYCLE HOOKS ====================
    
    /**
     * Lifecycle hook called when component is inserted into DOM
     * Initializes component state and starts placeholder animation
     */
    connectedCallback() {
        this.resetComponentState();
        this.startPlaceholderAnimation();
        this.fetchNamespace();
    }
    
    /**
     * Fetches the namespace from Apex
     * Used for namespaced tab navigation
     * @jira V2-7442
     */
    async fetchNamespace() {
        try {
            this.namespace = await getNamespace();
        } catch (error) {
            console.error('Error fetching namespace:', error);
            // Default to empty string if error occurs
            this.namespace = '';
        }
    }
    
    /**
     * Lifecycle hook called after component renders
     * Ensures component state is reset on first render to handle caching
     */
    renderedCallback() {
        // Force reset on first render to handle cached component state
        if (!this.hasRendered) {
            this.hasRendered = true;
            this.resetComponentState();
        }
    }
    
    /**
     * Lifecycle hook called when component is removed from DOM
     * Cleans up timers and resets state
     */
    disconnectedCallback() {
        this.stopPlaceholderAnimation();
        this.hasRendered = false;
    }
    
    /**
     * Resets all component state to initial values
     * Used for initialization and cleanup
     */
    resetComponentState() {
        this.isProcessing = false;
        this.showPromptOverride = false;
        this.userInput = '';
        this.isUserTyping = false;
    }
    
    // ==================== PLACEHOLDER ANIMATION ====================
    
    /**
     * Starts the animated placeholder text effect
     * Initializes the typing animation for placeholder text
     */
    startPlaceholderAnimation() {
        this.currentPlaceholder = '';
        this.typePlaceholder();
    }
    
    /**
     * Types out placeholder text character by character
     * Creates a typewriter effect for better UX
     */
    typePlaceholder() {
        if (this.isUserTyping) {
            this.scheduleNextPlaceholder();
            return;
        }
        
        const currentText = this.placeholderTexts[this.currentPlaceholderIndex];
        
        if (this.currentCharIndex < currentText.length) {
            this.currentPlaceholder = currentText.substring(0, this.currentCharIndex + 1);
            this.currentCharIndex++;
            
            this.typingTimeout = setTimeout(() => {
                this.typePlaceholder();
            }, AIAdvancePromptBuilder.TYPING_SPEED_MS);
        } else {
            this.scheduleNextPlaceholder();
        }
    }
    
    /**
     * Schedules the next placeholder text to be displayed
     * Rotates through available placeholder texts
     */
    scheduleNextPlaceholder() {
        this.typingTimeout = setTimeout(() => {
            if (!this.isUserTyping) {
                this.currentPlaceholderIndex = (this.currentPlaceholderIndex + 1) % this.placeholderTexts.length;
                this.currentCharIndex = 0;
                this.currentPlaceholder = '';
                this.typePlaceholder();
            } else {
                this.scheduleNextPlaceholder();
            }
        }, AIAdvancePromptBuilder.PLACEHOLDER_DELAY_MS);
    }
    
    /**
     * Stops all placeholder animation timers
     * Cleans up resources to prevent memory leaks
     */
    stopPlaceholderAnimation() {
        if (this.typingTimeout) {
            clearTimeout(this.typingTimeout);
        }
        if (this.placeholderInterval) {
            clearInterval(this.placeholderInterval);
        }
    }
    
    // ==================== EVENT HANDLERS ====================
    // @jira V2-7442
    
    /**
     * Handles user input changes in the textarea
     * Updates component state based on user typing
     * @param {Event} event - Input change event
     */
    handleInputChange(event) {
        this.userInput = event.target.value;
        this.isUserTyping = this.userInput.length > 0;
    }
    
    /**
     * Handles keyboard shortcuts for form submission
     * Allows Ctrl+Enter or Cmd+Enter to submit
     * @param {KeyboardEvent} event - Keyboard event
     */
    handleKeyDown(event) {
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
            event.preventDefault();
            this.handleSubmit();
        }
    }
    
    /**
     * Handles pill button clicks to populate textarea with example prompts
     * Maps pill labels to their corresponding custom label values
     * @param {Event} event - Click event from pill button
     */
    handlePillClick(event) {
        const label = event.currentTarget.dataset.label;
        
        // Map labels to custom label imports
        const prompts = {
            [LABEL_PILL_ACCOUNT]: LABEL_ACCOUNT_ANALYSIS,
            [LABEL_PILL_CASE]: LABEL_CASE_INSIGHTS,
            [LABEL_PILL_OPPORTUNITY]: LABEL_OPPORTUNITY_RECOMMENDATIONS,
            [LABEL_PILL_CONTACT]: LABEL_CONTACT_SUMMARY
        };
        
        const selectedPrompt = prompts[label] || '';
        
        this.userInput = selectedPrompt;
        this.isUserTyping = true;
        
        const textarea = this.template.querySelector('.search-input');
        if (textarea) {
            textarea.value = selectedPrompt;
            textarea.focus();
            textarea.scrollTop = 0;
        }
    }
    
    /**
     * Main submission handler - orchestrates AI prompt generation and creation
     * Validates input, calls AI service, parses response, creates prompt record
     * @jira V2-7442
     */
    async handleSubmit() {
        // Validate user input
        if (!this.userInput || this.userInput.trim() === '') {
            this.showToast('Warning', LABEL_ERROR_EMPTY_INPUT, 'warning');
            return;
        }
        
        this.isProcessing = true;
        
        try {
            // Fetch existing prompts for context
            const existingPrompts = await getExistingPrompts();
            const existingPromptsJson = JSON.stringify(existingPrompts);
            
            // Generate prompt details using AI
            const aiResponse = await generatePromptDetails({ 
                userInput: this.userInput,
                existingPromptsJson: existingPromptsJson
            });
            
            // Parse AI response
            const parsedResponse = this.parseAIResponse(aiResponse);
            
            if (!parsedResponse) {
                let responsePreview = '';
                try {
                    responsePreview = typeof aiResponse === 'string' 
                        ? aiResponse.substring(0, 500) 
                        : JSON.stringify(aiResponse).substring(0, 500);
                } catch (e) {
                    responsePreview = String(aiResponse).substring(0, 500);
                }
                throw new Error(LABEL_ERROR_PARSE_FAILED + ' Response preview: ' + responsePreview);
            }
            
            // Create prompt record with mapping
            const promptId = await createPromptWithMapping({
                promptName: parsedResponse.name,
                targetObject: parsedResponse.targetObject,
                description: parsedResponse.description,
                promptCommand: parsedResponse.promptCommand,
                dataContextMapping: JSON.stringify(parsedResponse.dataContextMapping)
            });
            
            // Show success message and navigate
            this.showToast('Success', LABEL_SUCCESS_CREATED, 'success');
            this.navigateToPromptRecord(promptId);
            
        } catch (error) {
            let errorMessage = LABEL_ERROR_CREATE_FAILED + ' ';
            if (error.body?.message) {
                errorMessage += error.body.message;
            } else if (error.message) {
                errorMessage += error.message;
            } else {
                errorMessage += 'Unknown error occurred';
            }
            
            this.showToast('Error', errorMessage, 'error');
        } finally {
            // Reset component state
            this.isUserTyping = false;
            const textarea = this.template.querySelector('.search-input');
            if (textarea) {
                textarea.value = '';
                textarea.focus();
                textarea.scrollTop = 0;
            }
            this.startPlaceholderAnimation();
            this.isProcessing = false;
        }   
    }
    
    /**
     * Handles back button click to navigate away from prompt builder
     * Navigation behavior depends on navigationTabName value:
     * - If navigationTabName has a value: Navigate to the specified tab
     * - If navigationTabName is empty/null: Navigate to AI_Prompt__c list view
     * @jira V2-7442
     */
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
    
    /**
     * Handles "Build Your Own" button click
     * Shows the manual prompt override component
     */
    handleBuildYourOwn() {
        this.showPromptOverride = true;
    }
    
    /**
     * Handles cancel action from prompt override component
     * Returns to the main prompt builder view
     */
    handlePromptOverrideCancel() {
        this.showPromptOverride = false;
    }
    
    // ==================== HELPER METHODS ====================
    // @jira V2-7442
    
    /**
     * Parses AI service response into structured prompt details
     * Handles multiple response formats from different AI providers
     * @param {Object|String} response - Raw AI service response
     * @returns {Object|null} Parsed prompt details or null if parsing fails
     */
    parseAIResponse(response) {
        try {
            let content = null;
            
            if (typeof response === 'string') {
                content = response;
            } else if (typeof response === 'object' && response !== null) {
                if (response.data && response.data.value && response.data.value.choices) {
                    const choices = response.data.value.choices;
                    if (choices.length > 0 && choices[0].message) {
                        content = choices[0].message.content;
                    }
                } else if (response.choices && response.choices.length > 0) {
                    content = response.choices[0].message?.content || response.choices[0].text;
                } else if (response.output) {
                    content = response.output;
                } else if (response.content) {
                    content = response.content;
                } else if (response.text) {
                    content = response.text;
                } else {
                    content = JSON.stringify(response);
                }
            }
            
            if (!content || content.trim() === '') {
                return null;
            }
            
            content = content.trim();
            
            if (content.startsWith('```json')) {
                content = content.substring(7);
            } else if (content.startsWith('```')) {
                content = content.substring(3);
            }
            
            if (content.endsWith('```')) {
                content = content.substring(0, content.length - 3);
            }
            
            content = content.trim();
            
            const promptDetails = JSON.parse(content);
            
            if (!promptDetails.name || !promptDetails.targetObject || !promptDetails.promptCommand) {
                return null;
            }
            
            return promptDetails;
            
        } catch (error) {
            return null;
        }
    }
    
    /**
     * Navigates to the newly created prompt record page
     * Uses Lightning Navigation for seamless user experience
     * @param {String} promptId - Salesforce record ID of the created prompt
     */
    navigateToPromptRecord(promptId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: promptId,
                objectApiName: this.aiPromptObjectApiName,
                actionName: 'view'
            }
        });
    }
    
    /**
     * Displays a toast notification to the user
     * @param {String} title - Toast title
     * @param {String} message - Toast message content
     * @param {String} variant - Toast variant (success, error, warning, info)
     */
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: variant === 'error' ? 'sticky' : 'dismissable'
        });
        this.dispatchEvent(event);
    }
}