import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex methods
import getSmartMatches from '@salesforce/apex/AIExchangeEmailController.getSmartMatches';
import searchContactAndLead from '@salesforce/apex/AIExchangeEmailController.searchContactAndLead';
import getAccountsForContacts from '@salesforce/apex/AIExchangeEmailController.getAccountsForContacts';
import getOpportunitiesForAccount from '@salesforce/apex/AIExchangeEmailController.getOpportunitiesForAccount';
import associateEmailsFromModal from '@salesforce/apex/AIExchangeEmailController.associateEmailsFromModal';
import associateCalendarFromModal from '@salesforce/apex/AICalendarSyncController.associateCalendarFromModal';
import associateTasksFromModal from '@salesforce/apex/AITaskSyncController.associateTasksFromModal';

export default class AiAutoRecordMatchingModal extends LightningElement {
    // Public API properties
    @api sourceType = 'EMAIL'; // 'EMAIL', 'CALENDAR', or 'TASK'
    @api providerType; // e.g., 'MICROSOFT_EMAIL', 'GMAIL_EMAIL', 'MICROSOFT_TASKS', 'GOOGLE_TASKS', 'MICROSOFT_CALENDAR', 'GOOGLE_CALENDAR'
    @api connectedAccountEmail = ''; // Connected provider account email to exclude from matching
    
    // Private properties
    _items = [];
    _initialized = false;
    
    // Tracked properties
    @track modalItems = []; // Processed items with smart matches and selections
    @track isLoading = false;
    @track isProcessing = false;
    
    // Search state
    modalSearchDebounce;
    
    /**
     * Getter/Setter for items to trigger initialization when items are set
     */
    @api
    get items() {
        return this._items;
    }
    
    set items(value) {
        this._items = value;
        // Initialize modal when items are set
        if (value && value.length > 0 && !this._initialized) {
            this._initialized = true;
            // Use setTimeout to ensure the component is fully rendered
            setTimeout(() => {
                this.initializeModal();
            }, 0);
        }
    }
    
    /**
     * Initialize modal with items and fetch smart matches
     */
    async initializeModal() {
        if (!this._items || this._items.length === 0) {
            return;
        }
        
        this.isLoading = true;
        
        try {
            // Prepare modal items with smart matches
            const modalItemsPromises = this._items.map(async (item) => {
                let allMatches = [];
                
                // 1. Get matches for organizer/sender/assignedTo
                const itemEmail = this.getItemEmail(item);
                const itemName = this.getItemName(item);
                
                // For tasks, only match if we have a valid email
                // Note: Task sync does NOT exclude connected account email
                if (this.sourceType === 'TASK') {
                    if (itemEmail) {
                        try {
                            const taskMatches = await getSmartMatches({
                                senderEmail: itemEmail,
                                senderName: itemName,
                                subject: this.getItemSubject(item),
                                connectedAccountEmail: null // Tasks don't exclude connected account
                            });
                            allMatches = allMatches.concat(taskMatches);
                        } catch (error) {
                            console.error('Error getting task matches:', error);
                            // Continue processing even if this fails
                        }
                    }
                } else {
                    // For emails and calendar events
                    // Only call getSmartMatches if we have an email
                    // Exclude connected account email from matching for EMAIL and CALENDAR
                    if (itemEmail) {
                        try {
                            const organizerMatches = await getSmartMatches({
                                senderEmail: itemEmail,
                                senderName: itemName,
                                subject: this.getItemSubject(item),
                                connectedAccountEmail: this.connectedAccountEmail || null
                            });
                            allMatches = allMatches.concat(organizerMatches);
                        } catch (error) {
                            console.error('Error getting organizer matches:', error);
                            // Continue processing even if this fails
                        }
                    }
                    
                    // 2. For emails, also get matches for all TO/CC recipients
                    if (this.sourceType === 'EMAIL') {
                        const recipientMatchPromises = [];
                        
                        // Match against TO recipients (exclude connected account email)
                        if (item.toRecipients && item.toRecipients.length > 0) {
                            item.toRecipients.forEach(recipient => {
                                const email = recipient.emailAddress?.address || '';
                                const name = recipient.emailAddress?.name || '';
                                if (email) {
                                    recipientMatchPromises.push(
                                        getSmartMatches({
                                            senderEmail: email,
                                            senderName: name,
                                            subject: this.getItemSubject(item),
                                            connectedAccountEmail: this.connectedAccountEmail || null
                                        }).catch(error => {
                                            console.error('Error getting recipient matches:', error);
                                            return []; // Return empty array on error
                                        })
                                    );
                                }
                            });
                        }
                        
                        // Match against CC recipients (exclude connected account email)
                        if (item.ccRecipients && item.ccRecipients.length > 0) {
                            item.ccRecipients.forEach(recipient => {
                                const email = recipient.emailAddress?.address || '';
                                const name = recipient.emailAddress?.name || '';
                                if (email) {
                                    recipientMatchPromises.push(
                                        getSmartMatches({
                                            senderEmail: email,
                                            senderName: name,
                                            subject: this.getItemSubject(item),
                                            connectedAccountEmail: this.connectedAccountEmail || null
                                        }).catch(error => {
                                            console.error('Error getting CC recipient matches:', error);
                                            return []; // Return empty array on error
                                        })
                                    );
                                }
                            });
                        }
                        
                        if (recipientMatchPromises.length > 0) {
                            try {
                                const recipientMatchResults = await Promise.all(recipientMatchPromises);
                                // Flatten and merge all recipient matches
                                recipientMatchResults.forEach(matches => {
                                    allMatches = allMatches.concat(matches);
                                });
                            } catch (error) {
                                console.error('Error processing recipient matches:', error);
                                // Continue processing even if this fails
                            }
                        }
                    }
                    
                    // 3. For calendar events, also get matches for all attendees (exclude connected account email)
                    if (this.sourceType === 'CALENDAR' && item.attendees && item.attendees.length > 0) {
                        const attendeeMatchPromises = [];
                        
                        item.attendees.forEach(attendee => {
                            const email = attendee.email || '';
                            const name = attendee.name || '';
                            // Only call getSmartMatches if email is not empty
                            if (email) {
                                attendeeMatchPromises.push(
                                    getSmartMatches({
                                        senderEmail: email,
                                        senderName: name,
                                        subject: this.getItemSubject(item),
                                        connectedAccountEmail: this.connectedAccountEmail || null
                                    }).catch(error => {
                                        console.error('Error getting attendee matches:', error);
                                        return []; // Return empty array on error
                                    })
                                );
                            }
                        });
                        
                        if (attendeeMatchPromises.length > 0) {
                            try {
                                const attendeeMatchResults = await Promise.all(attendeeMatchPromises);
                                // Flatten and merge all attendee matches
                                attendeeMatchResults.forEach(matches => {
                                    allMatches = allMatches.concat(matches);
                                });
                            } catch (error) {
                                console.error('Error processing attendee matches:', error);
                                // Continue processing even if this fails
                            }
                        }
                    }
                }
                
                // Remove duplicates based on recordId
                // IMPORTANT: Preserve shouldPreSelect=true if ANY duplicate has it
                const uniqueMatches = [];
                const matchesById = new Map();
                
                allMatches.forEach(match => {
                    if (!matchesById.has(match.recordId)) {
                        // Create a plain object copy to avoid proxy issues
                        matchesById.set(match.recordId, {
                            recordId: match.recordId,
                            recordName: match.recordName,
                            objectType: match.objectType,
                            email: match.email,
                            details: match.details,
                            iconName: match.iconName,
                            confidence: match.confidence,
                            shouldPreSelect: match.shouldPreSelect || false
                        });
                    } else {
                        // If duplicate found, merge shouldPreSelect flag (OR logic)
                        const existing = matchesById.get(match.recordId);
                        if (match.shouldPreSelect === true) {
                            // Create a new object with updated shouldPreSelect
                            matchesById.set(match.recordId, {
                                ...existing,
                                shouldPreSelect: true
                            });
                        }
                    }
                });
                
                // Convert map to array
                matchesById.forEach(match => uniqueMatches.push(match));
                
                // Separate matches by type
                const contacts = uniqueMatches.filter(m => m.objectType === 'Contact');
                const leads = uniqueMatches.filter(m => m.objectType === 'Lead');
                const accounts = uniqueMatches.filter(m => m.objectType === 'Account');
                
                // Pre-populate pills ONLY from matches marked with shouldPreSelect=true (precedence-based)
                // This implements the HYBRID approach: show all matches, but pre-select only precedence matches
                const selectedContactIds = contacts
                    .filter(c => c.shouldPreSelect === true)
                    .map(c => c.recordId);
                const selectedLeadIds = leads
                    .filter(l => l.shouldPreSelect === true)
                    .map(l => l.recordId);
                const selectedAccountIds = accounts
                    .filter(a => a.shouldPreSelect === true)
                    .map(a => a.recordId);
                const selectedContactPills = contacts
                    .filter(c => c.shouldPreSelect === true)
                    .map(c => ({
                        recordId: c.recordId,
                        recordName: c.recordName,
                        objectType: 'Contact'
                    }));
                const selectedLeadPills = leads
                    .filter(l => l.shouldPreSelect === true)
                    .map(l => ({
                        recordId: l.recordId,
                        recordName: l.recordName,
                        objectType: 'Lead'
                    }));
                const selectedAccountPills = accounts
                    .filter(a => a.shouldPreSelect === true)
                    .map(a => ({
                        recordId: a.recordId,
                        recordName: a.recordName,
                        objectType: 'Account'
                    }));
                
                return {
                    item: item,
                    smartMatchContacts: contacts,
                    smartMatchLeads: leads,
                    smartMatchAccounts: accounts,
                    selectedContactIds: selectedContactIds,
                    selectedLeadIds: selectedLeadIds,
                    selectedAccountIds: selectedAccountIds,
                    selectedContactPills: selectedContactPills,
                    selectedLeadPills: selectedLeadPills,
                    selectedAccountPills: selectedAccountPills,
                    selectedAccountId: null,
                    selectedAccountName: null,
                    selectedOpportunityId: null,
                    selectedOpportunityName: null,
                    accountOptions: [],
                    opportunityOptions: [],
                    searchResults: [],
                    showAccountDropdown: false,
                    showOpportunityDropdown: false
                };
            });
            
            this.modalItems = await Promise.all(modalItemsPromises);
            
            // Pre-fetch account options for items with smart match contacts/leads OR domain-matched accounts
            for (let modalItem of this.modalItems) {
                if (modalItem.selectedContactIds.length > 0 || 
                    (modalItem.smartMatchAccounts && modalItem.smartMatchAccounts.length > 0)) {
                    await this.updateAccountOptionsForItem(modalItem);
                }
            }
            
            // For Calendar events: After initialization, clear leads if Account/Opportunity is selected
            // Salesforce restriction: Cannot link Leads to Events with Account/Opportunity WhatId
            if (this.sourceType === 'CALENDAR') {
                for (let modalItem of this.modalItems) {
                    if (modalItem.selectedAccountId || modalItem.selectedOpportunityId) {
                        modalItem.selectedLeadIds = [];
                        modalItem.selectedLeadPills = [];
                    }
                }
            }
            
        } catch (error) {
            console.error('Error initializing modal:', error);
            this.showToast('Error', 'Failed to load smart matches', 'error');
            this.handleClose();
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * Get email address from item based on source type
     */
    getItemEmail(item) {
        if (this.sourceType === 'EMAIL') {
            return item.fromAddress || item.from?.emailAddress?.address;
        } else if (this.sourceType === 'CALENDAR') {
            return item.organizerEmail || item.organizer?.emailAddress?.address;
        } else if (this.sourceType === 'TASK') {
            return item.assignedToEmail || '';
        }
        return '';
    }
    
    /**
     * Get name from item based on source type
     */
    getItemName(item) {
        if (this.sourceType === 'EMAIL') {
            return item.fromName || item.from?.emailAddress?.name;
        } else if (this.sourceType === 'CALENDAR') {
            return item.organizerName || item.organizer?.emailAddress?.name;
        } else if (this.sourceType === 'TASK') {
            return item.assignedToName || '';
        }
        return '';
    }
    
    /**
     * Get subject from item based on source type
     */
    getItemSubject(item) {
        return item.subject || '(No Subject)';
    }
    
    /**
     * Handle close button click
     */
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
    
    /**
     * Prevent modal content clicks from closing modal
     */
    handleModalContentClick(event) {
        event.stopPropagation();
    }
    
    /**
     * Handle delete row button click
     */
    handleDeleteRow(event) {
        const itemIndex = parseInt(event.currentTarget.dataset.itemIndex, 10);
        this.modalItems = this.modalItems.filter((_, index) => index !== itemIndex);
        
        // If no items left, close modal
        if (this.modalItems.length === 0) {
            this.handleClose();
        }
    }
    
    /**
     * Close all custom dropdowns when clicking anywhere in modal body
     */
    handleModalBodyClick() {
        let hasOpenDropdown = false;
        this.modalItems.forEach(item => {
            if (item.showAccountDropdown || item.showOpportunityDropdown) {
                hasOpenDropdown = true;
                item.showAccountDropdown = false;
                item.showOpportunityDropdown = false;
            }
        });
        
        if (hasOpenDropdown) {
            this.modalItems = [...this.modalItems];
        }
    }
    
    /**
     * Prevent dropdown container clicks from closing dropdown
     */
    handleDropdownClick(event) {
        event.stopPropagation();
    }
    
    /**
     * Handle search input
     */
    handleSearch(event) {
        const itemIndex = parseInt(event.target.dataset.itemIndex, 10);
        const searchTerm = event.target.value;
        
        clearTimeout(this.modalSearchDebounce);
        
        if (!searchTerm || searchTerm.length < 2) {
            if (this.modalItems[itemIndex]) {
                this.modalItems[itemIndex].searchResults = [];
                this.modalItems = [...this.modalItems];
            }
            return;
        }
        
        this.modalSearchDebounce = setTimeout(async () => {
            try {
                const results = await searchContactAndLead({ searchTerm });
                const modalItem = this.modalItems[itemIndex];
                
                const processedResults = results.map(r => {
                    let isSelected = false;
                    if (r.objectType === 'Contact') {
                        isSelected = modalItem.selectedContactIds.includes(r.recordId);
                    } else if (r.objectType === 'Lead') {
                        isSelected = modalItem.selectedLeadIds.includes(r.recordId);
                    } else if (r.objectType === 'Account') {
                        isSelected = modalItem.selectedAccountIds.includes(r.recordId);
                    }
                    
                    return {
                        ...r,
                        isContact: r.objectType === 'Contact',
                        isLead: r.objectType === 'Lead',
                        isAccount: r.objectType === 'Account',
                        isSelected: isSelected,
                        resultItemClass: isSelected ? 'modal-search-result-item selected' : 'modal-search-result-item'
                    };
                });
                
                modalItem.searchResults = processedResults;
                this.modalItems = [...this.modalItems];
            } catch (error) {
                console.error('Error searching Contact/Lead:', error);
            }
        }, 300);
    }
    
    /**
     * Handle search focus - show all suggestions
     */
    handleSearchFocus(event) {
        const itemIndex = parseInt(event.target.dataset.itemIndex, 10);
        const modalItem = this.modalItems[itemIndex];
        
        // Only show Contacts and Leads in the search results
        // Accounts are shown in the Account dropdown, not in Contact/Lead search
        const allSuggestions = [
            ...modalItem.smartMatchContacts,
            ...modalItem.smartMatchLeads
        ];
        
        modalItem.searchResults = allSuggestions.map(s => {
            let isSelected = false;
            if (s.objectType === 'Contact') {
                isSelected = modalItem.selectedContactIds.includes(s.recordId);
            } else if (s.objectType === 'Lead') {
                isSelected = modalItem.selectedLeadIds.includes(s.recordId);
            } else if (s.objectType === 'Account') {
                isSelected = modalItem.selectedAccountIds.includes(s.recordId);
            }
            
            return {
                ...s,
                isContact: s.objectType === 'Contact',
                isLead: s.objectType === 'Lead',
                isAccount: s.objectType === 'Account',
                isSelected: isSelected,
                resultItemClass: isSelected ? 'modal-search-result-item selected' : 'modal-search-result-item'
            };
        });
        
        this.modalItems = [...this.modalItems];
    }
    
    /**
     * Handle search result selection
     */
    async handleSearchResultClick(event) {
        const itemIndex = parseInt(event.currentTarget.dataset.itemIndex, 10);
        const recordId = event.currentTarget.dataset.recordId;
        const recordName = event.currentTarget.dataset.recordName;
        const objectType = event.currentTarget.dataset.objectType;
        const isSelected = event.currentTarget.dataset.isSelected === 'true';
        
        if (isSelected) {
            return;
        }
        
        const modalItem = this.modalItems[itemIndex];
        
        if (objectType === 'Contact') {
            modalItem.selectedContactIds.push(recordId);
            modalItem.selectedContactPills.push({ recordId, recordName, objectType });
        } else if (objectType === 'Lead') {
            modalItem.selectedLeadIds.push(recordId);
            modalItem.selectedLeadPills.push({ recordId, recordName, objectType });
        } else if (objectType === 'Account') {
            modalItem.selectedAccountIds.push(recordId);
            modalItem.selectedAccountPills.push({ recordId, recordName, objectType });
        }
        
        // Clear search
        const searchInput = this.template.querySelector(`[data-item-index="${itemIndex}"].modal-search-input`);
        if (searchInput) {
            searchInput.value = '';
        }
        modalItem.searchResults = [];
        
        // Update account options
        await this.updateAccountOptionsForItem(modalItem);
        
        this.modalItems = [...this.modalItems];
    }
    
    /**
     * Handle search blur
     */
    handleSearchBlur(event) {
        const itemIndex = parseInt(event.target.dataset.itemIndex, 10);
        
        setTimeout(() => {
            if (this.modalItems[itemIndex]) {
                this.modalItems[itemIndex].searchResults = [];
                this.modalItems = [...this.modalItems];
            }
        }, 200);
    }
    
    /**
     * Remove pill
     */
    async handleRemovePill(event) {
        const itemIndex = parseInt(event.currentTarget.dataset.itemIndex, 10);
        const recordId = event.currentTarget.dataset.recordId;
        const objectType = event.currentTarget.dataset.objectType;
        
        const modalItem = this.modalItems[itemIndex];
        
        if (objectType === 'Contact') {
            modalItem.selectedContactIds = modalItem.selectedContactIds.filter(id => id !== recordId);
            modalItem.selectedContactPills = modalItem.selectedContactPills.filter(p => p.recordId !== recordId);
        } else if (objectType === 'Lead') {
            modalItem.selectedLeadIds = modalItem.selectedLeadIds.filter(id => id !== recordId);
            modalItem.selectedLeadPills = modalItem.selectedLeadPills.filter(p => p.recordId !== recordId);
        } else if (objectType === 'Account') {
            modalItem.selectedAccountIds = modalItem.selectedAccountIds.filter(id => id !== recordId);
            modalItem.selectedAccountPills = modalItem.selectedAccountPills.filter(p => p.recordId !== recordId);
        }
        
        await this.updateAccountOptionsForItem(modalItem);
        
        this.modalItems = [...this.modalItems];
    }
    
    /**
     * Update account options based on selected contacts
     */
    async updateAccountOptionsForItem(modalItem) {
        const previouslySelectedAccountId = modalItem.selectedAccountId;
        
        if (modalItem.selectedContactIds.length > 0) {
            try {
                const accountOptionsFromContacts = await getAccountsForContacts({ contactIds: modalItem.selectedContactIds });
                
                // Create a new array to avoid proxy issues
                let allAccountOptions = [...accountOptionsFromContacts];
                
                // Store the original options for selection logic
                const originalAccountOptions = [...accountOptionsFromContacts];
                
                // Add domain-matched Accounts from smartMatchAccounts (independent feature)
                if (modalItem.smartMatchAccounts && modalItem.smartMatchAccounts.length > 0) {
                    modalItem.smartMatchAccounts.forEach(smartAccount => {
                        // Only add if not already in the list (avoid duplicates)
                        const exists = allAccountOptions.some(opt => opt.value === smartAccount.recordId);
                        if (!exists) {
                            allAccountOptions = [...allAccountOptions, {
                                value: smartAccount.recordId,
                                label: smartAccount.recordName + ' (Domain Match)',
                                isDomainMatch: true
                            }];
                        }
                    });
                }
                
                // Add "None" option at the beginning if there are any accounts
                if (allAccountOptions.length > 0) {
                    modalItem.accountOptions = [
                        { value: 'none', label: '-- None --', isNone: true },
                        ...allAccountOptions
                    ];
                } else {
                    modalItem.accountOptions = [];
                }
                
                // Check if previously selected Account is still available
                if (previouslySelectedAccountId) {
                    // Check in accounts from contacts
                    const accountFromContact = originalAccountOptions.find(opt => opt.value === previouslySelectedAccountId);
                    
                    // Check in domain-matched accounts
                    const accountFromDomain = modalItem.smartMatchAccounts?.find(acc => acc.recordId === previouslySelectedAccountId);
                    
                    if (accountFromContact || accountFromDomain) {
                        // Account is still available, keep it selected
                        modalItem.selectedAccountId = previouslySelectedAccountId;
                        modalItem.selectedAccountName = accountFromContact ? accountFromContact.label : (accountFromDomain.recordName + ' (Domain Match)');
                        return;
                    } else {
                        // Previously selected Account is no longer available (Contact was removed)
                        // Reset Account and Opportunity to "-- None --"
                        modalItem.selectedAccountId = null;
                        modalItem.selectedAccountName = null;
                        modalItem.selectedOpportunityId = null;
                        modalItem.selectedOpportunityName = null;
                        modalItem.opportunityOptions = [];
                        // Don't return here, continue with normal selection logic
                    }
                }
                
                if (modalItem.smartMatchAccount) {
                    const smartAccountInList = originalAccountOptions.find(opt => opt.value === modalItem.smartMatchAccount.recordId);
                    if (smartAccountInList) {
                        modalItem.selectedAccountId = modalItem.smartMatchAccount.recordId;
                        modalItem.selectedAccountName = smartAccountInList.label;
                    } else if (originalAccountOptions.length > 0) {
                        modalItem.selectedAccountId = originalAccountOptions[0].value;
                        modalItem.selectedAccountName = originalAccountOptions[0].label;
                    } else {
                        modalItem.selectedAccountId = null;
                        modalItem.selectedAccountName = null;
                    }
                } else if (originalAccountOptions.length > 0) {
                    modalItem.selectedAccountId = originalAccountOptions[0].value;
                    modalItem.selectedAccountName = originalAccountOptions[0].label;
                } else {
                    modalItem.selectedAccountId = null;
                    modalItem.selectedAccountName = null;
                }
                
                if (modalItem.selectedAccountId !== previouslySelectedAccountId) {
                    if (modalItem.selectedAccountId) {
                        await this.updateOpportunityOptionsForItem(modalItem);
                    } else {
                        modalItem.opportunityOptions = [];
                        modalItem.selectedOpportunityId = null;
                        modalItem.selectedOpportunityName = null;
                    }
                }
                
            } catch (error) {
                console.error('Error fetching accounts:', error);
            }
        } else {
            // No selected contacts, but check for domain-matched Accounts
            if (modalItem.smartMatchAccounts && modalItem.smartMatchAccounts.length > 0) {
                // Add domain-matched Accounts
                const domainMatchedAccounts = modalItem.smartMatchAccounts.map(smartAccount => ({
                    value: smartAccount.recordId,
                    label: smartAccount.recordName + ' (Domain Match)',
                    isDomainMatch: true
                }));
                
                modalItem.accountOptions = [
                    { value: 'none', label: '-- None --', isNone: true },
                    ...domainMatchedAccounts
                ];
                
                // Check if previously selected Account was a domain match and still available
                if (previouslySelectedAccountId) {
                    const stillAvailable = domainMatchedAccounts.find(opt => opt.value === previouslySelectedAccountId);
                    if (!stillAvailable) {
                        // Previously selected Account is no longer available, reset
                        modalItem.selectedAccountId = null;
                        modalItem.selectedAccountName = null;
                        modalItem.selectedOpportunityId = null;
                        modalItem.selectedOpportunityName = null;
                        modalItem.opportunityOptions = [];
                    }
                }
            } else if (modalItem.smartMatchAccount) {
                // Legacy: single account from smart match
                modalItem.accountOptions = [{
                    value: modalItem.smartMatchAccount.recordId,
                    label: modalItem.smartMatchAccount.recordName
                }];
                if (previouslySelectedAccountId !== modalItem.smartMatchAccount.recordId) {
                    modalItem.selectedAccountId = modalItem.smartMatchAccount.recordId;
                    modalItem.selectedAccountName = modalItem.smartMatchAccount.recordName;
                    await this.updateOpportunityOptionsForItem(modalItem);
                }
            } else {
                // No accounts available at all
                modalItem.accountOptions = [];
                if (previouslySelectedAccountId !== null) {
                    modalItem.selectedAccountId = null;
                    modalItem.selectedAccountName = null;
                    modalItem.opportunityOptions = [];
                    modalItem.selectedOpportunityId = null;
                    modalItem.selectedOpportunityName = null;
                }
            }
        }
    }
    
    /**
     * Toggle account dropdown
     */
    handleAccountDropdownToggle(event) {
        event.stopPropagation();
        const itemIndex = parseInt(event.currentTarget.dataset.itemIndex, 10);
        const modalItem = this.modalItems[itemIndex];
        
        this.modalItems.forEach((item, idx) => {
            if (idx !== itemIndex) {
                item.showAccountDropdown = false;
                item.showOpportunityDropdown = false;
            }
        });
        
        modalItem.showAccountDropdown = !modalItem.showAccountDropdown;
        modalItem.showOpportunityDropdown = false;
        this.modalItems = [...this.modalItems];
    }
    
    /**
     * Handle account option selection
     */
    async handleAccountOptionClick(event) {
        event.stopPropagation();
        const itemIndex = parseInt(event.currentTarget.dataset.itemIndex, 10);
        const selectedAccountId = event.currentTarget.dataset.accountId;
        const selectedAccountName = event.currentTarget.dataset.accountName;
        
        const modalItem = this.modalItems[itemIndex];
        const previousAccountId = modalItem.selectedAccountId;
        
        // Handle "None" option - set to null
        if (selectedAccountId === 'none' || selectedAccountId === 'null' || selectedAccountId === null) {
            modalItem.selectedAccountId = null;
            modalItem.selectedAccountName = null;
            modalItem.showAccountDropdown = false;
            
            // Clear opportunities when account is deselected
            modalItem.opportunityOptions = [];
            modalItem.selectedOpportunityId = null;
            modalItem.selectedOpportunityName = null;
        } else {
            modalItem.selectedAccountId = selectedAccountId;
            modalItem.selectedAccountName = selectedAccountName;
            modalItem.showAccountDropdown = false;
            
            // For Calendar events: Clear lead selections when Account is selected
            // Salesforce restriction: Cannot link Leads to Events with Account/Opportunity WhatId
            if (this.sourceType === 'CALENDAR' && selectedAccountId) {
                modalItem.selectedLeadIds = [];
                modalItem.selectedLeadPills = [];
            }
            
            if (selectedAccountId !== previousAccountId) {
                await this.updateOpportunityOptionsForItem(modalItem);
            }
        }
        
        this.modalItems = [...this.modalItems];
    }
    
    /**
     * Update opportunity options based on selected account
     */
    async updateOpportunityOptionsForItem(modalItem) {
        const previouslySelectedOpportunityId = modalItem.selectedOpportunityId;
        
        if (modalItem.selectedAccountId) {
            try {
                const oppOptions = await getOpportunitiesForAccount({ accountId: modalItem.selectedAccountId });
                
                // Store the original options for selection logic
                const originalOppOptions = [...oppOptions];
                
                // Add "None" option at the beginning if there are any opportunities
                if (oppOptions.length > 0) {
                    modalItem.opportunityOptions = [
                        { value: 'none', label: '-- None --', isNone: true },
                        ...oppOptions
                    ];
                } else {
                    modalItem.opportunityOptions = oppOptions;
                }
                
                if (previouslySelectedOpportunityId) {
                    const currentOppStillAvailable = originalOppOptions.find(opt => opt.value === previouslySelectedOpportunityId);
                    if (currentOppStillAvailable) {
                        modalItem.selectedOpportunityName = currentOppStillAvailable.label;
                        return;
                    }
                }
                
                if (originalOppOptions.length > 0) {
                    modalItem.selectedOpportunityId = originalOppOptions[0].value;
                    modalItem.selectedOpportunityName = originalOppOptions[0].label;
                } else {
                    modalItem.selectedOpportunityId = null;
                    modalItem.selectedOpportunityName = null;
                }
            } catch (error) {
                console.error('Error fetching opportunities:', error);
            }
        } else {
            modalItem.opportunityOptions = [];
            modalItem.selectedOpportunityId = null;
            modalItem.selectedOpportunityName = null;
        }
    }
    
    /**
     * Toggle opportunity dropdown
     */
    handleOpportunityDropdownToggle(event) {
        event.stopPropagation();
        const itemIndex = parseInt(event.currentTarget.dataset.itemIndex, 10);
        const modalItem = this.modalItems[itemIndex];
        
        this.modalItems.forEach((item, idx) => {
            if (idx !== itemIndex) {
                item.showAccountDropdown = false;
                item.showOpportunityDropdown = false;
            }
        });
        
        modalItem.showOpportunityDropdown = !modalItem.showOpportunityDropdown;
        modalItem.showAccountDropdown = false;
        this.modalItems = [...this.modalItems];
    }
    
    /**
     * Handle opportunity option selection
     */
    handleOpportunityOptionClick(event) {
        event.stopPropagation();
        const itemIndex = parseInt(event.currentTarget.dataset.itemIndex, 10);
        const selectedOpportunityId = event.currentTarget.dataset.opportunityId;
        const selectedOpportunityName = event.currentTarget.dataset.opportunityName;
        
        const modalItem = this.modalItems[itemIndex];
        
        // Handle "None" option - set to null
        if (selectedOpportunityId === 'none' || selectedOpportunityId === 'null' || selectedOpportunityId === null) {
            modalItem.selectedOpportunityId = null;
            modalItem.selectedOpportunityName = null;
            modalItem.showOpportunityDropdown = false;
        } else {
            modalItem.selectedOpportunityId = selectedOpportunityId;
            modalItem.selectedOpportunityName = selectedOpportunityName;
            modalItem.showOpportunityDropdown = false;
            
            // For Calendar events: Clear lead selections when Opportunity is selected
            // Salesforce restriction: Cannot link Leads to Events with Account/Opportunity WhatId
            if (this.sourceType === 'CALENDAR' && selectedOpportunityId) {
                modalItem.selectedLeadIds = [];
                modalItem.selectedLeadPills = [];
            }
        }
        
        this.modalItems = [...this.modalItems];
    }
    
    /**
     * Check if Associate button should be disabled
     * Disabled if no items have at least one Contact, Lead, or Account selected
     */
    get isAssociateDisabled() {
        if (this.isProcessing) {
            return true;
        }
        
        // Check if at least one item has a Contact, Lead, or Account selected
        const hasValidSelection = this.modalItems.some(modalItem => {
            const hasContact = modalItem.selectedContactIds && modalItem.selectedContactIds.length > 0;
            const hasLead = modalItem.selectedLeadIds && modalItem.selectedLeadIds.length > 0;
            const hasAccount = modalItem.selectedAccountIds && modalItem.selectedAccountIds.length > 0;
            // Also check for single Account selection (including domain-matched Accounts)
            const hasSingleAccount = modalItem.selectedAccountId && modalItem.selectedAccountId !== 'none';
            return hasContact || hasLead || hasAccount || hasSingleAccount;
        });
        
        return !hasValidSelection;
    }
    
    /**
     * Handle Associate button click
     */
    async handleAssociate(event) {
        event.stopPropagation();
        this.isProcessing = true;
        
        try {
            // Build selections payload based on source type
            // For tasks, use messageId (compositeId with listId::taskId)
            // For emails and calendar, use id
            // ONLY include items that have at least one Contact, Lead, or Account selected
            const selections = this.modalItems
                .filter(modalItem => {
                    const hasContact = modalItem.selectedContactIds && modalItem.selectedContactIds.length > 0;
                    const hasLead = modalItem.selectedLeadIds && modalItem.selectedLeadIds.length > 0;
                    const hasAccount = modalItem.selectedAccountIds && modalItem.selectedAccountIds.length > 0;
                    // Also check for single Account selection (including domain-matched Accounts)
                    const hasSingleAccount = modalItem.selectedAccountId && modalItem.selectedAccountId !== 'none';
                    return hasContact || hasLead || hasAccount || hasSingleAccount;
                })
                .map(modalItem => ({
                    messageId: modalItem.item.messageId || modalItem.item.id,
                    contactIds: modalItem.selectedContactIds,
                    leadIds: modalItem.selectedLeadIds,
                    accountIds: modalItem.selectedAccountIds,
                    accountId: modalItem.selectedAccountId,
                    opportunityId: modalItem.selectedOpportunityId
                }));
            
            let result;
            
            // Call appropriate Apex method based on source type
            if (this.sourceType === 'EMAIL') {
                result = await associateEmailsFromModal({
                    selections: selections,
                    providerType: this.providerType
                });
            } else if (this.sourceType === 'CALENDAR') {
                result = await associateCalendarFromModal({
                    selections: selections,
                    providerType: this.providerType
                });
            } else if (this.sourceType === 'TASK') {
                result = await associateTasksFromModal({
                    selections: selections,
                    providerType: this.providerType
                });
            }
            
            if (result && result.success) {
                const successCount = result.successCount || 0;
                const excludedCount = result.excludedCount || 0;
                const duplicateCount = result.duplicateCount || 0;
                
                // Dispatch success event with result (parent will show toast and close modal)
                // Note: Parent component shows the toast, so we don't show it here to avoid duplicates
                this.dispatchEvent(new CustomEvent('success', {
                    detail: {
                        count: successCount,
                        excludedCount: excludedCount,
                        duplicateCount: duplicateCount,
                        sourceType: this.sourceType
                    },
                    bubbles: true,
                    composed: true
                }));
                
                // Don't close modal here - let parent handle it to avoid timing issues
                // The parent's handleModalSuccess already sets showQuickMatchModal = false
            } else {
                // Check if this is a "all duplicates" scenario
                const duplicateCount = result && result.duplicateCount ? result.duplicateCount : 0;
                const successCount = result && result.successCount ? result.successCount : 0;
                
                if (successCount === 0 && duplicateCount > 0) {
                    // All items were duplicates - treat as info, not error
                    this.showToast('Info', `All selected ${this.sourceTypeLabel}(s) have already been imported`, 'info');
                    this.handleClose();
                } else {
                    // Real error
                    const errorMsg = result && result.errors && result.errors.length > 0 
                        ? result.errors.join(', ') 
                        : 'Association failed';
                    throw new Error(errorMsg);
                }
            }
            
        } catch (error) {
            console.error('Error associating items:', error);
            
            // Extract error message, ensuring it's always a string
            // This handles cases where error.body.message might be an object
            let errorMessage = 'Failed to associate items';
            if (error.body && error.body.message) {
                errorMessage = typeof error.body.message === 'string' 
                    ? error.body.message 
                    : JSON.stringify(error.body.message);
            } else if (error.message) {
                errorMessage = typeof error.message === 'string' 
                    ? error.message 
                    : JSON.stringify(error.message);
            }
            
            // Check if this is a duplicate key error - show user-friendly message
            if (errorMessage.toLowerCase().includes('duplicate value found') || 
                errorMessage.toLowerCase().includes('workspace_sync_id__c')) {
                errorMessage = 'This event has already been imported by another user in your org.';
            }
            
            // Dispatch error event so parent can handle it (parent will show toast and close modal)
            this.dispatchEvent(new CustomEvent('error', {
                detail: {
                    message: errorMessage
                },
                bubbles: true,
                composed: true
            }));
        } finally {
            this.isProcessing = false;
        }
    }
    
    /**
     * Show toast notification
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
    
    // Computed properties
    
    get modalTitle() {
        return `Quick Match - ${this.modalItems.length} ${this.sourceTypeLabel}(s)`;
    }
    
    get sourceTypeLabel() {
        if (this.sourceType === 'EMAIL') return 'Email';
        if (this.sourceType === 'CALENDAR') return 'Event';
        if (this.sourceType === 'TASK') return 'Task';
        return 'Item';
    }
    
    get hasItems() {
        return this.modalItems && this.modalItems.length > 0;
    }
}