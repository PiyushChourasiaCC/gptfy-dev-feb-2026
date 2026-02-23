import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getSettings from '@salesforce/apex/AIWorkspaceSyncSettingsController.getSettings';
import updateField from '@salesforce/apex/AIWorkspaceSyncSettingsController.updateField';
import validateRequiredFields from '@salesforce/apex/AIWorkspaceSyncSettingsController.validateRequiredFields';

// Mask pattern constant - must match the Apex constant
const MASKED_VALUE = '****************';

export default class AiWorkspaceSyncSettings extends LightningElement {
    @track showSpinner = false;
    @track settings = {};

    // Digest frequency options for combobox
    digestFrequencyOptions = [
        { label: 'Daily', value: 'Daily' },
        { label: 'Weekly', value: 'Weekly' },
        { label: 'Monthly', value: 'Monthly' }
    ];

    // Placeholder getters for secure fields
    get microsoftClientIdPlaceholder() {
        return this.settings.hasMicrosoftClientId ? MASKED_VALUE : 'Enter Client Id';
    }

    get microsoftClientSecretPlaceholder() {
        return this.settings.hasMicrosoftClientSecret ? MASKED_VALUE : 'Enter Client Secret';
    }

    get googleClientIdPlaceholder() {
        return this.settings.hasGoogleClientId ? MASKED_VALUE : 'Enter Client Id';
    }

    get googleClientSecretPlaceholder() {
        return this.settings.hasGoogleClientSecret ? MASKED_VALUE : 'Enter Client Secret';
    }

    get syncPrecedencePlaceholder() {
        return '{"1": ["Lead", "Contact", "User"]}';
    }

    connectedCallback() {
        this.loadSettings();
    }

    async loadSettings() {
        this.showSpinner = true;
        try {
            const result = await getSettings();
            this.settings = { ...result };
        } catch (error) {
            this.handleError(error);
        } finally {
            this.showSpinner = false;
        }
    }

    // Handle toggle/checkbox changes - save immediately
    async handleToggleChange(event) {
        const fieldName = event.target.name;
        const value = event.target.checked;
        
        // Update local state immediately for responsiveness
        this.settings = { ...this.settings, [fieldName]: value };
        
        await this.saveField(fieldName, value);
        
        // If provider enablement changed, validate required fields
        if (fieldName === 'wsOutlookEnabled' || fieldName === 'wsGmailEnabled') {
            await this.validateProviderFields();
        }
    }

    // Handle text/url field blur - save on blur
    async handleFieldBlur(event) {
        const fieldName = event.target.name;
        const value = event.target.value;
        
        // Only save if value changed
        if (this.settings[fieldName] !== value) {
            this.settings = { ...this.settings, [fieldName]: value };
            await this.saveField(fieldName, value);
        }
    }

    // Handle number field blur - convert to number and save
    async handleNumberFieldBlur(event) {
        const fieldName = event.target.name;
        const rawValue = event.target.value;
        const value = rawValue ? parseFloat(rawValue) : null;
        
        // Only save if value changed
        if (this.settings[fieldName] !== value) {
            this.settings = { ...this.settings, [fieldName]: value };
            await this.saveField(fieldName, value);
        }
    }

    // Handle secure field blur (Client ID, Client Secret) - special masking logic
    async handleSecureFieldBlur(event) {
        const fieldName = event.target.name;
        const value = event.target.value;
        
        // Skip if value is the masked value (user didn't change it)
        if (value === MASKED_VALUE || value === '') {
            return;
        }
        
        // Save the actual value
        await this.saveField(fieldName, value);
        
        // Reload settings to get the masked display value
        await this.loadSettings();
    }

    // Handle combobox changes
    async handleComboboxChange(event) {
        const fieldName = event.target.name;
        const value = event.detail.value;
        
        this.settings = { ...this.settings, [fieldName]: value };
        await this.saveField(fieldName, value);
    }

    // Save a single field
    async saveField(fieldName, value) {
        try {
            await updateField({ fieldName, value });
            this.showToast('success', 'Success', 'Setting saved successfully');
        } catch (error) {
            this.handleError(error);
            // Reload settings to revert to saved state
            await this.loadSettings();
        }
    }

    // Validate provider required fields
    async validateProviderFields() {
        try {
            const missingFields = await validateRequiredFields({
                wsOutlookEnabled: this.settings.wsOutlookEnabled,
                wsGmailEnabled: this.settings.wsGmailEnabled
            });
            
            if (missingFields && missingFields.length > 0) {
                this.showToast(
                    'warning', 
                    'Required Fields Missing', 
                    'Please configure: ' + missingFields.join(', ')
                );
            }
        } catch (error) {
            console.error('Error validating fields:', error);
        }
    }

    showToast(variant, title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }

    handleError(error) {
        this.showSpinner = false;
        let message = 'An unexpected error occurred';
        if (error?.body?.message) {
            message = error.body.message;
        } else if (error?.message) {
            message = error.message;
        } else if (typeof error === 'string') {
            message = error;
        }
        this.showToast('error', 'Error', message);
        console.error('Error:', error);
    }
}