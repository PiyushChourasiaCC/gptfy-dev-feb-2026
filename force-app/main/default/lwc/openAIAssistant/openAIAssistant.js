import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createAssistant from '@salesforce/apex/OpenAIAssistantController.createAssistant';
import sendMessage from '@salesforce/apex/OpenAIAssistantController.sendMessage';
import getRelatedFiles from '@salesforce/apex/OpenAIAssistantController.getRelatedFiles';
import uploadFileToAzure from '@salesforce/apex/OpenAIAssistantController.uploadFileToAzure';

export default class OpenAIAssistant extends LightningElement {
    @api recordId;
    @track messages = [];
    @track inputMessage = '';
    @track isprocessing = false;
    @track isuploading = false;
    @track assistantId = 'asst_BA3MJNDHaGytxVnLXGbdnLYI'; // Updated assistant ID with vector store access
    @track threadId;
    @track uploadedFiles = [];
    @track relatedFiles = [];
    @track showFileModal = false;
    @track selectedFiles = new Set();
    
    columns = [
        { label: 'Title', fieldName: 'title', type: 'text' },
        { label: 'Type', fieldName: 'fileType', type: 'text' },
        { 
            label: 'Size', 
            fieldName: 'size', 
            type: 'text',
            typeAttributes: {
                formatStyle: 'decimal'
            },
            cellAttributes: { alignment: 'right' }
        }
    ];
    
    acceptedFormats = ['.txt', '.pdf', '.doc', '.docx', '.csv', '.json'];

    get isButtonDisabled() {
        return this.isprocessing || this.isuploading;
    }

    get hasSelectedFiles() {
        return this.selectedFiles.size > 0;
    }

    connectedCallback() {
        this.initializeAssistant();
        if (this.recordId) {
            this.loadRelatedFiles();
        }
    }

    async loadRelatedFiles() {
        try {
            const files = await getRelatedFiles({ recordId: this.recordId });
            this.relatedFiles = files.map(file => ({
                ...file,
                size: this.formatFileSize(parseInt(file.size, 10))
            }));
        } catch (error) {
            this.showToast('Error', 'Failed to load related files', 'error');
            console.error('Error loading related files:', error);
        }
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    handleShowFileModal() {
        this.showFileModal = true;
    }

    handleCloseFileModal() {
        this.showFileModal = false;
        this.selectedFiles = new Set();
    }

    handleFileSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedFiles = new Set(selectedRows.map(row => row.id));
    }

    handleSelectedFilesUpload() {
        if (this.selectedFiles.size === 0) return;
        
        this.isuploading = true;
        const fileIds = Array.from(this.selectedFiles);
        console.log('Uploading files:', fileIds);
        
        Promise.all(fileIds.map(fileId => {
            // Call the Apex method for each file
            return uploadFileToAzure({
                threadId: this.threadId,
                contentDocumentId: fileId
            })
            .then(result => {
                console.log('File upload result:', result);
                // Add safe check for preview before calling substring
                const previewText = result.preview ? result.preview.substring(0, 100) + '...' : 'No preview available';
                console.log('File preview received:', previewText);
                
                // Add file message to chat
                this.addMessage('system', `File uploaded: ${result.fileName}
Type: ${result.fileType}
Size: ${result.fileSize} bytes

The file has been added to the vector store and is now searchable. You can ask questions about its content.

Preview:
${result.preview || 'No preview available'}`);
                
                // Add to tracked files
                const file = this.relatedFiles.find(f => f.id === fileId);
                if (file) {
                    this.uploadedFiles.push({
                        id: file.id,
                        name: file.title,
                        type: result.fileType,
                        size: result.fileSize,
                        preview: result.preview
                    });
                }
                
                return result;
            });
        }))
        .then(() => {
            this.showToast('Success', 'Files uploaded successfully. You can now send your message.', 'success');
            this.showFileModal = false;
            this.selectedFiles = new Set();
        })
        .catch(error => {
            this.showToast('Error', 'Failed to upload files: ' + this.reduceErrorMessage(error), 'error');
            console.error('Error uploading files:', error);
        })
        .finally(() => {
            this.isuploading = false;
        });
    }

    async initializeAssistant() {
        try {
            // We already have the hardcoded assistant ID, just need to create a thread
            const result = await createAssistant();
            this.threadId = result.threadId;
            
            // Add a welcome message
            this.addMessage('assistant', 'Hello! I\'m your AI assistant with file search capabilities. I can help you analyze documents, search through uploaded files, and answer questions. Please upload a file or ask me a question.');
        } catch (error) {
            this.showToast('Error', 'Failed to initialize assistant: ' + this.getErrorMessage(error), 'error');
            console.error('Error initializing assistant:', error);
        }
    }

    handleInputChange(event) {
        this.inputMessage = event.target.value;
    }

    async handleSendMessage() {
        if (!this.inputMessage.trim()) return;
        
        const userMessage = this.inputMessage.trim();
        this.addMessage('user', userMessage);
        this.inputMessage = '';
        this.isprocessing = true;
        
        try {
            // Add a system message to indicate processing
            this.addMessage('system', 'Processing your request...');
            
            // Send the message to the backend
            const result = await sendMessage({
                threadId: this.threadId,
                assistantId: this.assistantId, // Using hardcoded assistant ID
                message: userMessage
            });
            
            // Remove the processing message
            this.messages = this.messages.filter(msg => msg.content !== 'Processing your request...');
            
            // Add file search results if available
            if (result.fileSearchResults) {
                this.addMessage('assistant', result.fileSearchResults);
            }
            
            // Add the assistant's response
            if (result.response) {
                this.addMessage('assistant', result.response);
            } else {
                this.addMessage('system', 'No response received from the assistant.');
            }
        } catch (error) {
            // Remove the processing message
            this.messages = this.messages.filter(msg => msg.content !== 'Processing your request...');
            
            // Add error message
            this.addMessage('system', 'Error: ' + this.getErrorMessage(error));
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isprocessing = false;
        }
    }

    addMessage(role, content) {
        // Ensure content is a string before calling substring
        const contentStr = content || '';
        console.log(`Adding ${role} message to chat:`, contentStr.length > 100 ? contentStr.substring(0, 100) + '...' : contentStr);
        this.messages = [...this.messages, {
            id: Date.now(),
            role: role,
            content: content,
            messageClass: role === 'user' ? 'user-message' : 
                         (role === 'system' ? 'system-message' : 'assistant-message'),
            timestamp: new Date().toLocaleTimeString()
        }];

        // Scroll to bottom
        this.scrollToBottom();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }

    generateUniqueId() {
        return 'msg_' + Date.now() + '_' + Math.floor(Math.random() * 1000);
    }

    reduceErrorMessage(error) {
        return error.body?.message || error.message || JSON.stringify(error);
    }

    scrollToBottom() {
        setTimeout(() => {
            const container = this.template.querySelector('.chat-container');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 0);
    }

    getErrorMessage(error) {
        return error.body?.message || error.message || JSON.stringify(error);
    }
}