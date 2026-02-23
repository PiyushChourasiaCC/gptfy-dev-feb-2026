import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import checkConnectionStatus from '@salesforce/apex/AIWorkspaceAuthController.checkConnectionStatus';
import getAuthorizationUrl from '@salesforce/apex/AIWorkspaceAuthController.getAuthorizationUrl';
import disconnectAccount from '@salesforce/apex/AIWorkspaceAuthController.disconnectAccount';
import getOutlookUserProfile from '@salesforce/apex/AIWorkspaceAuthController.getOutlookUserProfile';
import getGmailUserProfile from '@salesforce/apex/AIWorkspaceAuthController.getGmailUserProfile';
import refreshOutlookAndGetProfile from '@salesforce/apex/AIWorkspaceAuthController.refreshOutlookAndGetProfile';
import refreshGmailAndGetProfile from '@salesforce/apex/AIWorkspaceAuthController.refreshGmailAndGetProfile';
import getAutoSyncStatus from '@salesforce/apex/AIWorkspaceAuthController.getAutoSyncStatus';
import setAutoSyncStatus from '@salesforce/apex/AIWorkspaceAuthController.setAutoSyncStatus';
import getProviderSettings from '@salesforce/apex/AISyncSettingsService.getProviderSettings';

export default class AiWorkspaceAuthenticator extends LightningElement {
    selectedProvider = 'Outlook';
    
    // Outlook state
    outlookConnected = false;
    isLoadingOutlook = true;
    outlookEmail = '';
    outlookDisplayName = '';
    outlookJobTitle = '';
    outlookProfileError = '';
    showOutlookProfile = false;
    
    // Gmail state
    gmailConnected = false;
    isLoadingGmail = true;
    gmailEmail = '';
    gmailDisplayName = '';
    gmailProfileError = '';
    showGmailProfile = false;
    
    // Auto Sync state
    autoSyncEnabled = true;
    showAutoSyncToggle = false;
    
    // Provider settings from org configuration
    @track providerSettings = {
        outlookEnabled: false,
        gmailEnabled: false,
        bothEnabled: false,
        neitherEnabled: true,
        singleProvider: null
    };
    
    // Initial loading state to prevent flicker
    @track isInitializing = true;
    
    /**
     * Component lifecycle hook - called when component is inserted into DOM
     */
    connectedCallback() {
        this.loadProviderSettings();
    }
    
    /**
     * Computed property: Show content only after initialization is complete
     */
    get showContent() {
        return !this.isInitializing;
    }
    
    /**
     * Load provider settings from org configuration
     */
    loadProviderSettings() {
        getProviderSettings()
            .then(settings => {
                this.providerSettings = settings;
                
                // Create promises array for parallel loading
                const loadingPromises = [];
                
                // Only check connections for enabled providers
                if (settings.outlookEnabled) {
                    loadingPromises.push(this.checkOutlookConnectionAsync());
                } else {
                    this.isLoadingOutlook = false;
                }
                
                if (settings.gmailEnabled) {
                    loadingPromises.push(this.checkGmailConnectionAsync());
                } else {
                    this.isLoadingGmail = false;
                }
                
                // Load auto sync status
                loadingPromises.push(this.loadAutoSyncStatusAsync());
                
                // Wait for all loading to complete before showing content
                return Promise.allSettled(loadingPromises);
            })
            .then(() => {
                // All data loaded, show content
                this.isInitializing = false;
            })
            .catch(error => {
                console.error('Error loading provider settings:', error);
                // Even on error, show content to prevent infinite loading
                this.isInitializing = false;
                // Fallback: check both connections if settings fail to load
                this.checkOutlookConnection();
                this.checkGmailConnection();
                this.loadAutoSyncStatus();
            });
    }
    
    /**
     * Computed property: Show "Not Configured" message when no providers are enabled
     */
    get showNoProviderMessage() {
        return this.providerSettings.neitherEnabled;
    }
    
    /**
     * Computed property: Show Outlook card
     */
    get showOutlookCard() {
        return this.providerSettings.outlookEnabled;
    }
    
    /**
     * Computed property: Show Gmail card
     */
    get showGmailCard() {
        return this.providerSettings.gmailEnabled;
    }
    
    /**
     * Computed property: CSS class for Outlook content (hidden when loading)
     */
    get outlookContentClass() {
        return this.isLoadingOutlook ? 'content-hidden' : 'content-visible';
    }
    
    /**
     * Computed property: CSS class for Gmail content (hidden when loading)
     */
    get gmailContentClass() {
        return this.isLoadingGmail ? 'content-hidden' : 'content-visible';
    }
    
    /**
     * Load Auto Sync status
     */
    loadAutoSyncStatus() {
        getAutoSyncStatus()
            .then(status => {
                this.showAutoSyncToggle = status.hasAnyConnection;
                this.autoSyncEnabled = status.isEnabled;
            })
            .catch(error => {
                console.error('Error loading auto sync status:', error);
            });
    }
    
    /**
     * Load Auto Sync status (async version for Promise.allSettled)
     */
    loadAutoSyncStatusAsync() {
        return getAutoSyncStatus()
            .then(status => {
                this.showAutoSyncToggle = status.hasAnyConnection;
                this.autoSyncEnabled = status.isEnabled;
            })
            .catch(error => {
                console.error('Error loading auto sync status:', error);
            });
    }
    
    /**
     * Handle Auto Sync toggle change
     */
    handleAutoSyncToggle(event) {
        const newValue = event.target.checked;
        
        setAutoSyncStatus({ enabled: newValue })
            .then(status => {
                if (status.errorMessage) {
                    this.showToast('Error', status.errorMessage, 'error');
                    // Revert the toggle
                    this.autoSyncEnabled = !newValue;
                } else {
                    this.autoSyncEnabled = status.isEnabled;
                    
                    // Build provider-specific message
                    let providerMessage = '';
                    if (this.providerSettings.bothEnabled) {
                        providerMessage = 'for Outlook and Gmail';
                    } else if (this.providerSettings.outlookEnabled) {
                        providerMessage = 'for Outlook';
                    } else if (this.providerSettings.gmailEnabled) {
                        providerMessage = 'for Gmail';
                    } else {
                        providerMessage = 'for all connected accounts';
                    }
                    
                    this.showToast(
                        'Success', 
                        `Auto Sync ${status.isEnabled ? 'enabled' : 'disabled'} ${providerMessage}.`, 
                        'success'
                    );
                }
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
                // Revert the toggle
                this.autoSyncEnabled = !newValue;
            });
    }
    
    /**
     * Handle tab selection
     */
    handleProviderSelect(event) {
        this.selectedProvider = event.target.value;
    }
    
    /**
     * Check Outlook connection status
     */
    checkOutlookConnection() {
        this.isLoadingOutlook = true;
        
        checkConnectionStatus({ provider: 'Outlook' })
            .then(data => {
                this.isLoadingOutlook = false;
                this.outlookConnected = data.isConnected;
                
                if (this.outlookConnected) {
                    this.fetchOutlookProfile();
                }
            })
            .catch(error => {
                this.isLoadingOutlook = false;
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }
    
    /**
     * Check Outlook connection status (async version for Promise.allSettled)
     * Proactively refreshes token on page load to prevent disconnection issues
     */
    checkOutlookConnectionAsync() {
        this.isLoadingOutlook = true;
        
        return checkConnectionStatus({ provider: 'Outlook' })
            .then(data => {
                this.outlookConnected = data.isConnected;
                
                if (this.outlookConnected) {
                    // Proactively refresh token on page load to ensure it's fresh
                    return refreshOutlookAndGetProfile()
                        .then(refreshResult => {
                            if (refreshResult.isSuccess) {
                                // Token refreshed successfully, fetch profile
                                return this.fetchOutlookProfileAsync();
                            } else {
                                // Refresh failed, try fetching profile anyway (might still work)
                                return this.fetchOutlookProfileAsync();
                            }
                        })
                        .catch(refreshError => {
                            console.error('Error refreshing Outlook token:', refreshError);
                            // Even if refresh fails, try to fetch profile
                            return this.fetchOutlookProfileAsync();
                        })
                        .finally(() => {
                            this.isLoadingOutlook = false;
                        });
                } else {
                    this.isLoadingOutlook = false;
                }
            })
            .catch(error => {
                this.isLoadingOutlook = false;
                console.error('Error checking Outlook connection:', error);
            });
    }
    
    /**
     * Check Gmail connection status
     */
    checkGmailConnection() {
        this.isLoadingGmail = true;
        
        checkConnectionStatus({ provider: 'Gmail' })
            .then(data => {
                this.isLoadingGmail = false;
                this.gmailConnected = data.isConnected;
                
                if (this.gmailConnected) {
                    this.fetchGmailProfile();
                }
            })
            .catch(error => {
                this.isLoadingGmail = false;
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }
    
    /**
     * Check Gmail connection status (async version for Promise.allSettled)
     * Proactively refreshes token on page load to prevent disconnection issues
     */
    checkGmailConnectionAsync() {
        this.isLoadingGmail = true;
        
        return checkConnectionStatus({ provider: 'Gmail' })
            .then(data => {
                this.gmailConnected = data.isConnected;
                
                if (this.gmailConnected) {
                    // Proactively refresh token on page load to ensure it's fresh
                    return refreshGmailAndGetProfile()
                        .then(refreshResult => {
                            if (refreshResult.isSuccess) {
                                // Token refreshed successfully, fetch profile
                                return this.fetchGmailProfileAsync();
                            } else {
                                // Refresh failed, try fetching profile anyway (might still work)
                                return this.fetchGmailProfileAsync();
                            }
                        })
                        .catch(refreshError => {
                            console.error('Error refreshing Gmail token:', refreshError);
                            // Even if refresh fails, try to fetch profile
                            return this.fetchGmailProfileAsync();
                        })
                        .finally(() => {
                            this.isLoadingGmail = false;
                        });
                } else {
                    this.isLoadingGmail = false;
                }
            })
            .catch(error => {
                this.isLoadingGmail = false;
                console.error('Error checking Gmail connection:', error);
            });
    }
    
    /**
     * Fetch Outlook user profile
     */
    fetchOutlookProfile() {
        getOutlookUserProfile()
            .then(profile => {
                if (profile.isSuccess) {
                    this.outlookEmail = profile.email || '';
                    this.outlookDisplayName = profile.displayName || '';
                    this.outlookJobTitle = profile.jobTitle || '';
                    this.showOutlookProfile = true;
                    this.outlookProfileError = '';
                } else {
                    // If token expired, try to auto-refresh
                    if (profile.isTokenExpired) {
                        this.autoRefreshOutlookToken();
                    } else {
                        this.outlookProfileError = profile.errorMessage;
                        this.showOutlookProfile = false;
                    }
                }
            })
            .catch(error => {
                this.showOutlookProfile = false;
                this.outlookProfileError = this.getErrorMessage(error);
            });
    }
    
    /**
     * Fetch Outlook user profile (async version for Promise.allSettled)
     */
    fetchOutlookProfileAsync() {
        return getOutlookUserProfile()
            .then(profile => {
                if (profile.isSuccess) {
                    this.outlookEmail = profile.email || '';
                    this.outlookDisplayName = profile.displayName || '';
                    this.outlookJobTitle = profile.jobTitle || '';
                    this.showOutlookProfile = true;
                    this.outlookProfileError = '';
                } else {
                    // If token expired, don't show error during initial load
                    if (!profile.isTokenExpired) {
                        this.outlookProfileError = profile.errorMessage;
                        this.showOutlookProfile = false;
                    }
                }
            })
            .catch(error => {
                this.showOutlookProfile = false;
                console.error('Error fetching Outlook profile:', error);
            });
    }
    
    /**
     * Auto-refresh Outlook token and fetch profile again
     */
    autoRefreshOutlookToken() {
        this.outlookProfileError = 'Refreshing connection...';
        
        refreshOutlookAndGetProfile()
            .then(result => {
                if (result.isSuccess) {
                    // Token refreshed, now fetch profile again
                    this.fetchOutlookProfileAfterRefresh();
                } else {
                    this.outlookProfileError = result.errorMessage;
                    this.showOutlookProfile = false;
                    this.showToast('Warning', 'Your Outlook session has expired. Please reconnect.', 'warning');
                }
            })
            .catch(error => {
                this.outlookProfileError = this.getErrorMessage(error);
                this.showOutlookProfile = false;
                this.showToast('Warning', 'Failed to refresh connection. Please reconnect.', 'warning');
            });
    }
    
    /**
     * Fetch Outlook profile after token refresh
     */
    fetchOutlookProfileAfterRefresh() {
        getOutlookUserProfile()
            .then(profile => {
                if (profile.isSuccess) {
                    this.outlookEmail = profile.email || '';
                    this.outlookDisplayName = profile.displayName || '';
                    this.outlookJobTitle = profile.jobTitle || '';
                    this.showOutlookProfile = true;
                    this.outlookProfileError = '';
                } else {
                    this.outlookProfileError = profile.errorMessage;
                    this.showOutlookProfile = false;
                }
            })
            .catch(error => {
                this.showOutlookProfile = false;
                this.outlookProfileError = this.getErrorMessage(error);
            });
    }
    
    /**
     * Fetch Gmail user profile
     */
    fetchGmailProfile() {
        getGmailUserProfile()
            .then(profile => {
                if (profile.isSuccess) {
                    this.gmailEmail = profile.email || '';
                    this.gmailDisplayName = profile.displayName || '';
                    this.showGmailProfile = true;
                    this.gmailProfileError = '';
                } else {
                    // If token expired, try to auto-refresh
                    if (profile.isTokenExpired) {
                        this.autoRefreshGmailToken();
                    } else {
                        this.gmailProfileError = profile.errorMessage;
                        this.showGmailProfile = false;
                    }
                }
            })
            .catch(error => {
                this.showGmailProfile = false;
                this.gmailProfileError = this.getErrorMessage(error);
            });
    }
    
    /**
     * Fetch Gmail user profile (async version for Promise.allSettled)
     */
    fetchGmailProfileAsync() {
        return getGmailUserProfile()
            .then(profile => {
                if (profile.isSuccess) {
                    this.gmailEmail = profile.email || '';
                    this.gmailDisplayName = profile.displayName || '';
                    this.showGmailProfile = true;
                    this.gmailProfileError = '';
                } else {
                    // If token expired, don't show error during initial load
                    if (!profile.isTokenExpired) {
                        this.gmailProfileError = profile.errorMessage;
                        this.showGmailProfile = false;
                    }
                }
            })
            .catch(error => {
                this.showGmailProfile = false;
                console.error('Error fetching Gmail profile:', error);
            });
    }
    
    /**
     * Auto-refresh Gmail token and fetch profile again
     */
    autoRefreshGmailToken() {
        this.gmailProfileError = 'Refreshing connection...';
        
        refreshGmailAndGetProfile()
            .then(result => {
                if (result.isSuccess) {
                    // Token refreshed, now fetch profile again
                    this.fetchGmailProfileAfterRefresh();
                } else {
                    this.gmailProfileError = result.errorMessage;
                    this.showGmailProfile = false;
                    this.showToast('Warning', 'Your Gmail session has expired. Please reconnect.', 'warning');
                }
            })
            .catch(error => {
                this.gmailProfileError = this.getErrorMessage(error);
                this.showGmailProfile = false;
                this.showToast('Warning', 'Failed to refresh connection. Please reconnect.', 'warning');
            });
    }
    
    /**
     * Fetch Gmail profile after token refresh
     */
    fetchGmailProfileAfterRefresh() {
        getGmailUserProfile()
            .then(profile => {
                if (profile.isSuccess) {
                    this.gmailEmail = profile.email || '';
                    this.gmailDisplayName = profile.displayName || '';
                    this.showGmailProfile = true;
                    this.gmailProfileError = '';
                } else {
                    this.gmailProfileError = profile.errorMessage;
                    this.showGmailProfile = false;
                }
            })
            .catch(error => {
                this.showGmailProfile = false;
                this.gmailProfileError = this.getErrorMessage(error);
            });
    }
    
    /**
     * Handle Outlook Connect button
     */
    handleOutlookConnect() {
        this.navigateToOAuth('Outlook');
    }
    
    /**
     * Handle Outlook Reconnect button
     */
    handleOutlookReconnect() {
        this.navigateToOAuth('Outlook');
    }
    
    /**
     * Handle Outlook Disconnect button
     */
    handleOutlookDisconnect() {
        this.isLoadingOutlook = true;
        
        disconnectAccount({ provider: 'Outlook' })
            .then(result => {
                if (result.isSuccess) {
                    // Update all state atomically before showing UI
                    this.outlookConnected = false;
                    this.outlookEmail = '';
                    this.outlookDisplayName = '';
                    this.outlookJobTitle = '';
                    this.showOutlookProfile = false;
                    this.outlookProfileError = '';
                    this.isLoadingOutlook = false;
                    this.showToast('Success', result.message, 'success');
                    // Refresh auto sync toggle visibility
                    this.loadAutoSyncStatus();
                } else {
                    this.isLoadingOutlook = false;
                    this.showToast('Error', result.message, 'error');
                }
            })
            .catch(error => {
                this.isLoadingOutlook = false;
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }
    
    /**
     * Handle Gmail Connect button
     */
    handleGmailConnect() {
        this.navigateToOAuth('Gmail');
    }
    
    /**
     * Handle Gmail Reconnect button
     */
    handleGmailReconnect() {
        this.navigateToOAuth('Gmail');
    }
    
    /**
     * Handle Gmail Disconnect button
     */
    handleGmailDisconnect() {
        this.isLoadingGmail = true;
        
        disconnectAccount({ provider: 'Gmail' })
            .then(result => {
                if (result.isSuccess) {
                    // Update all state atomically before showing UI
                    this.gmailConnected = false;
                    this.gmailEmail = '';
                    this.gmailDisplayName = '';
                    this.showGmailProfile = false;
                    this.gmailProfileError = '';
                    this.isLoadingGmail = false;
                    this.showToast('Success', result.message, 'success');
                    // Refresh auto sync toggle visibility
                    this.loadAutoSyncStatus();
                } else {
                    this.isLoadingGmail = false;
                    this.showToast('Error', result.message, 'error');
                }
            })
            .catch(error => {
                this.isLoadingGmail = false;
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }
    
    /**
     * Navigate to OAuth VF page
     */
    navigateToOAuth(provider) {
        if (provider === 'Outlook') {
            this.isLoadingOutlook = true;
        } else if (provider === 'Gmail') {
            this.isLoadingGmail = true;
        }
        
        getAuthorizationUrl({ provider: provider })
            .then(url => {
                // Navigate to the VF page
                window.location.href = url;
            })
            .catch(error => {
                if (provider === 'Outlook') {
                    this.isLoadingOutlook = false;
                } else if (provider === 'Gmail') {
                    this.isLoadingGmail = false;
                }
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }
    
    /**
     * Extract error message from error object
     */
    getErrorMessage(error) {
        if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        } else if (typeof error === 'string') {
            return error;
        }
        return 'An unknown error occurred';
    }
    
    /**
     * Show toast notification
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