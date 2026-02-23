import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import audioworkletprocessor from '@salesforce/resourceUrl/audioworkletprocessor';
import playbackworklet from '@salesforce/resourceUrl/playbackworklet';
import gptfylogo from '@salesforce/resourceUrl/gptfylogo';
import getObjectByName from '@salesforce/apex/OpenAIServiceTestVoice.getObjectByName';
import getPromptByName from '@salesforce/apex/OpenAIServiceTestVoice.getPromptByName';
import createRealtimeSession from '@salesforce/apex/OpenAIServiceTestVoice.createRealtimeSession';
import RESP_MESSAGE_FIELD from '@salesforce/schema/AI_Response__c.Message__c';
import RESP_STATUS_FIELD from '@salesforce/schema/AI_Response__c.Status__c';
import RESP_DATA_ORIGINAL_FIELD from '@salesforce/schema/AI_Response__c.Data_Original__c';
import RESP_Processed_Data_PII_Added_FIELD from '@salesforce/schema/AI_Response__c.AI_Processed_Data_PII_Added__c';
import initiateGPT from '@salesforce/apex/ChatGPTUtills.initiateGPT';

export default class Realtimevoicechatdev extends LightningElement {
    @track messages = [];
    @track isRecording = false;
    @track isResponding = false;
    @track buttonLabel = 'Start Recording';
    @track userInput = '';

    gptfylogo = gptfylogo
    websocket;
    audioContext;
    audioStream;
    buffer = new Uint8Array();
    playbackQueue = []; // Queue for audio playback to prevent overlaps
    playbackNode = null;

    // Azure OpenAI Realtime API configuration
    // Reference: https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/realtime-audio-webrtc
    deploymentName = 'gpt-realtime';
    azureResource = 'neel-m74zh4ra-swedencentral'; // Your Azure resource name
    ephemeralToken = null; // Ephemeral token fetched from server
    tokenExpiresAt = null; // Token expiration timestamp

    // Toggle Recording
    async toggleRecording() {
        if (this.isRecording) {
            this.stopRecording();
        } else {
            await this.startRecording();
        }
    }

    // Start Recording
    async startRecording() {
        try {
            // First, fetch ephemeral token from server
            await this.fetchEphemeralToken();
            
            if (!this.ephemeralToken) {
                throw new Error('Failed to obtain ephemeral token');
            }
            
            await this.initializeWebSocket();
            await this.initializeAudioRecording();
            this.isRecording = true;
            this.buttonLabel = 'Stop Recording';
        } catch (error) {
            this.showToast('Error', `Error starting recording: ${error.message}`, 'error');
        }
    }

    // Fetch ephemeral token from Apex (server-side)
    // Calls POST /openai/v1/realtime/client_secrets on Azure OpenAI
    // Reference: https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/realtime-audio-webrtc
    async fetchEphemeralToken() {
        try {
            const secretResponse = await createRealtimeSession({ 
                deploymentName: this.deploymentName,
                instructions: 'User Native language is english. Please respond to the user in english language.',
                voice: 'alloy'
            });
            
            if (secretResponse && secretResponse.value) {
                this.ephemeralToken = secretResponse.value;
                this.tokenExpiresAt = secretResponse.expiresAt;
                console.log('Ephemeral token obtained successfully');
                if (this.tokenExpiresAt) {
                    console.log('Token expires at:', new Date(this.tokenExpiresAt * 1000));
                }
            } else {
                throw new Error('Invalid client secret response from server');
            }
        } catch (error) {
            console.error('Error fetching ephemeral token:', error);
            this.showToast('Error', `Failed to get client secret: ${error.body?.message || error.message}`, 'error');
            throw error;
        }
    }

    // Stop Recording
    stopRecording() {
        this.isRecording = false;
        this.buttonLabel = 'Start Recording';

        if (this.websocket?.readyState === WebSocket.OPEN) {
            this.websocket.send(JSON.stringify({ type: 'input_audio_buffer.commit' }));
            this.websocket.close();
        }
    }

    // WebSocket Initialization for Azure OpenAI Realtime API
    // Reference: https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/realtime-audio-webrtc
    async initializeWebSocket() {
        try {
            // Azure OpenAI WebSocket URL format:
            // wss://{resource}.openai.azure.com/openai/realtime?api-version=2024-10-01-preview&deployment={deployment}
            //const wsUrl = `wss://${this.azureResource}.cognitiveservices.azure.com/openai/realtime?deployment=${this.deploymentName}&api-key=${this.ephemeralToken}`;
            const wsUrl = 'wss://neel-m74zh4ra-swedencentral.cognitiveservices.azure.com/openai/realtime?api-version=2024-10-01-preview&deployment=gpt-realtime&api-key=lRM3ZDfA8sPy3U2Wr1KfJ669HKBqKPmhbuxrvDTqmdi5M5BcDqUuJQQJ99BBACfhMk5XJ3w3AAAAACOGZYpH'
            console.log('Connecting to WebSocket:', wsUrl);
            
            // For Azure OpenAI, use the ephemeral token in the subprotocol
            this.websocket = new WebSocket(wsUrl);

            this.websocket.onopen = () => {
                console.log('WebSocket connection established');
                // Session is already configured via the client_secrets endpoint
                // Send session.update only if you need to modify the session
                this.websocket.send(
                    JSON.stringify({
                        type: 'session.update',
                        session: {
                            instructions: 'User Native language is english. Please respond to the user in english language.',
                            voice: 'alloy',
                            input_audio_format: 'pcm16',
                            output_audio_format: 'pcm16',
                            input_audio_transcription: { 
                                model: 'whisper-1' 
                            },
                            turn_detection: {
                                type: 'server_vad',
                                threshold: 0.5,
                                prefix_padding_ms: 300,
                                silence_duration_ms: 500
                            }
                        }
                    })
                );
                this.showToast('Success', 'Connected to Azure OpenAI Realtime', 'success');
            };

            this.websocket.onmessage = this.handleWebSocketMessage.bind(this);
            this.websocket.onerror = this.handleWebSocketError.bind(this);
            this.websocket.onclose = this.handleWebSocketClose.bind(this);
        } catch (error) {
            console.error('Error initializing WebSocket:', error);
            this.showToast('WebSocket Error', `Failed to initialize WebSocket: ${error.message}`, 'error');
        }
    }

    // Audio Recording Initialization
    async initializeAudioRecording() {
        try {
            this.audioStream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    echoCancellation: true,
                    noiseSuppression: true,
                    sampleRate: 24000,
                    channelCount: 1,
                },
            });

            const AudioContext = window.AudioContext || window.webkitAudioContext;
            this.audioContext = new AudioContext({ sampleRate: 24000 });

            await this.audioContext.audioWorklet.addModule(audioworkletprocessor);
            await this.audioContext.audioWorklet.addModule(playbackworklet);
            this.playbackNode = new AudioWorkletNode(this.audioContext, "playback-worklet");
            this.playbackNode.port.onmessage = (event) => {
                 console.log('player message');
                 console.log(event.data);

                // if (event.data === "playback-ended") {
                //   this.isCurrentlyPlaying = false;
                // }
              };
            this.playbackNode.connect(this.audioContext.destination);
            

           // Create the Audio Worklet Node
        const audioWorkletNode = new AudioWorkletNode(this.audioContext, 'audio-worklet-processor');

        // Listen for PCM data from the Audio Worklet
        audioWorkletNode.port.onmessage = (event) => {
            if (this.isRecording && this.websocket?.readyState === WebSocket.OPEN) {

                const uint8Array = new Uint8Array(event.data.buffer);
                this.combineArray(uint8Array);
                if (this.buffer.length >= 4800) {
                    const toSend = new Uint8Array(this.buffer.slice(0, 4800));
                    this.buffer = new Uint8Array(this.buffer.slice(4800));
                    const regularArray = String.fromCharCode(...toSend);
                    const base64 = btoa(regularArray);
                    this.websocket.send(JSON.stringify({
                        type: "input_audio_buffer.append",
                        audio: base64,
                    }));
                }   
            }
        };

        // Connect microphone to the worklet
        const source = this.audioContext.createMediaStreamSource(this.audioStream);
        source.connect(audioWorkletNode);

        this.showToast('Success', 'Microphone access granted', 'success');

        } catch (error) {
            this.showToast('Error', `Microphone access failed: ${error.message}`, 'error');
        }
    }

    play(buffer) {
        if (this.playbackNode) {
          this.playbackNode.port.postMessage(buffer);
        }
    }
    
    clear() {
        if (this.playbackNode) {
          this.playbackNode.port.postMessage(null);
        }
    }

    handleWebSocketMessage(event) {
        if (typeof event.data === 'string') {
            const message = JSON.parse(event.data);
            console.log('message', message);
            switch (message.type) {
                case 'session.created':
                    //this.addMessage('System', '<< Session Started >>');
                    break;
    
                case 'session.update':
                    console.log('Session updated:', message.session);
                    //this.addMessage('System', '<< Session Updated >>');
                    break;
    
                case 'session.updated': // NEW CASE FOR session.updated
                    console.log('Session updated:', message);
                    //this.addMessage('System', '<< Session Updated >>');
                    break;
                case 'conversation.item.input_audio_transcription.completed':
                        if(message.transcript && message.transcript.length > 0 ){
                            this.addMessage('Me', message.transcript);
                        }
                        break;
                case 'response.audio_transcript.delta':
                    if(message.delta){
                        this.appendToLatestMessage('GPTfy', message.delta);
                    }
                    break;
    
                case 'response.audio.delta':
                    //this.enqueueAudioPlayback(message.delta);
                    const binary = atob(message.delta);
                    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
                    const pcmData = new Int16Array(bytes.buffer);
                    this.play(pcmData);
                    break;
    
                case 'response.done':
                    this.isResponding = false;
                    //this.addMessage('System', '<< Response Completed >>');
                    break;
    
                case 'input_audio_buffer.speech_started':
                    //this.addMessage('System', '<< Speech Started >>');
                    this.clear();
                    break;

                case 'response.function_call_arguments.done':
                    console.log('Function Call Arguments:', message.arguments);
                    console.log('Function Call name:', message.name);
                    this.functionCalling(message)
                    break;
    
                default:
                    console.log('Unhandled message type:', message.type);
                    break;
            }
        }
    }

    functionCalling = (message) => {
        try {
            if (message.name === 'getObjectDetails') {
                let args = JSON.parse(message.arguments);
                this.addMessage('GPTfy', `Fetching ${args.objectType} Details for ${args.recordName}...`);
                if (args.objectType && args.recordName) {
                    this.fetchObjectDetails(args.objectType, args.recordName)
                        .then((acc) => {
                            this.websocket.send(JSON.stringify({ 
                                type: 'conversation.item.create',
                                item: {
                                    type: 'function_call_output',
                                    call_id: message.call_id, 
                                    output: JSON.stringify(acc) 
                                }
                            }));
        
                            this.websocket.send(JSON.stringify({
                                type: "response.create",
                                response: {
                                    modalities: ["text", "audio"],
                                    instructions: `Respond to the user Record Name and Description. Here is details Account Name is ${acc.Name}. Be concise, formated design and friendly.`,
                                }
                            }));
                        })
                        .catch((error) => {
                            this.showToast('Error', `Failed to fetch object details: ${error.message}`, 'error');
                        });
                }
                
            } else if (message.name === 'getPromptDetails') {
                let args = JSON.parse(message.arguments);
                if (args.promptName) {
                    this.addMessage('GPTfy', `Fetching Prompt ${args.promptName}...`);
                    getPromptByName({ promptName: args.promptName })
                        .then((prompt) => {
                            if (prompt) {
                                let res = JSON.stringify(prompt);
                                this.websocket.send(JSON.stringify({ 
                                    type: 'conversation.item.create',
                                    item: {
                                        type: 'function_call_output',
                                        call_id: message.call_id, 
                                        output: res
                                    }
                                }));
                                this.websocket.send(JSON.stringify({
                                    type: "response.create",
                                    response: {
                                        modalities: ["text", "audio"],
                                        instructions: `Respond to the user Prompt Name`,
                                    }
                                }));
                            }
                        })
                        .catch((error) => {
                            this.showToast('Error', `Failed to fetch prompt details: ${error.message}`, 'error');
                        });
                }
                
            } else if (message.name === 'executePromptWithRecord') {
                let args = JSON.parse(message.arguments);
                this.addMessage('GPTfy', `Executing Prompt ...`);
                if (args.recordId && args.promptId) {
                    this.executePrompt(args.recordId, args.promptId)
                        .then((response) => {
                            if (response) {
                                let res = JSON.parse(JSON.stringify(response));
                                this.websocket.send(JSON.stringify({ 
                                    type: 'conversation.item.create',
                                    item: {
                                        type: 'function_call_output',
                                        call_id: message.call_id, 
                                        output: res[RESP_DATA_ORIGINAL_FIELD.fieldApiName]
                                    }
                                }));
            
                                this.addMessage('GPTfy', res[RESP_Processed_Data_PII_Added_FIELD.fieldApiName]);
                            }
                        })
                        .catch((error) => {
                            this.showToast('Error', `Failed to execute prompt: ${error.message}`, 'error');
                        });
                }
            }
        } catch (error) {
            console.error('Error in functionCalling:', error);
            this.showToast('Error', `Function call failed: ${error.message}`, 'error');
        }
    }


   async executePrompt(recordId,promptId) {
       
        let result = await initiateGPT({
                    "recordId" : recordId, 
                    "promptId" : promptId, 
                    "userInput" : null, 
                    "mapOfFiles" : null,
                    "isGptfyConsole" : false
                })
        if(result && result[RESP_STATUS_FIELD.fieldApiName] && result[RESP_STATUS_FIELD.fieldApiName] == 'Errored' && result[RESP_MESSAGE_FIELD.fieldApiName] && result[RESP_MESSAGE_FIELD.fieldApiName] != null){
                    var msg = result[RESP_MESSAGE_FIELD.fieldApiName];
                    console.log(msg)
                    return;
        }else{
                    return result;
        }         
   }

    async fetchObjectDetails(objectName, name) {  
        let result = await getObjectByName({ objectName: objectName, name: name })
        if(result){
            return result;
        } else {
            return 'Record not found'
        }         
    }
    

    // WebSocket Error Handler
    handleWebSocketError(error) {
        console.error('WebSocket Error:', error);
        this.showToast('WebSocket Error', error.message, 'error');
    }

    // WebSocket Close Handler
    handleWebSocketClose() {
        this.isRecording = false;
        this.isResponding = false;
        this.buttonLabel = 'Start Recording';
    }

    // Stop AI Response
    stopResponse() {
        if (this.websocket?.readyState === WebSocket.OPEN) {
            this.websocket.send(JSON.stringify({ type: 'response.cancel' }));
            this.clear();
        }
        this.isResponding = false;
    }

    // Audio Playback Queue
    enqueueAudioPlayback(delta) {
        this.playbackQueue.push(delta);
        if (this.playbackQueue.length === 1) {
            this.processAudioQueue();
        }
    }
    
    async processAudioQueue() {
        if (this.playbackQueue.length === 0) return;
    
        const delta = this.playbackQueue[0];
        await this.playAudioMessage(delta);
        this.playbackQueue.shift();
        this.processAudioQueue(); // Process next audio in queue
    }
    

    // Play Audio Message
    async playAudioMessage(delta) {
        try {
            const binary = atob(delta);
            const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
            const pcmData = new Int16Array(bytes.buffer);

            if (!this.audioContext) {
                this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            }

            const audioBuffer = this.audioContext.createBuffer(1, pcmData.length, 24000);
            const channelData = audioBuffer.getChannelData(0);

            for (let i = 0; i < pcmData.length; i++) {
                channelData[i] = pcmData[i] / 32768; // Normalize Int16 to Float32
            }

            const source = this.audioContext.createBufferSource();
            source.buffer = audioBuffer;
            source.connect(this.audioContext.destination);
            source.start(0);

            return new Promise((resolve) => {
                source.onended = resolve; // Resolve when playback ends
            });
        } catch (error) {
            console.error('Error playing audio message:', error);
        }
    }


    resetChatAndAudio() {
        try {
            // Clear chat messages
            this.messages = [];
    
            // Stop audio stream if active
            if (this.audioStream) {
                this.audioStream.getTracks().forEach((track) => track.stop());
                this.audioStream = null;
            }
    
            // Close WebSocket if open
            if (this.websocket && this.websocket.readyState === WebSocket.OPEN) {
                this.websocket.close();
                this.websocket = null;
            }
    
            // Reset audio context
            if (this.audioContext) {
                this.audioContext.close();
                this.audioContext = null;
            }
    
            // Clear playback queue
            this.playbackQueue = [];
    
            // Reset recording and responding states
            this.isRecording = false;
            this.isResponding = false;
            this.buttonLabel = 'Start Recording';
    
            this.showToast('Success', 'Chat and audio have been reset.', 'success');
        } catch (error) {
            this.showToast('Error', `Error resetting chat and audio: ${error.message}`, 'error');
        }
    }
    


    combineArray(newData) {
        const newBuffer = new Uint8Array(this.buffer.length + newData.length);
        newBuffer.set(this.buffer);
        newBuffer.set(newData, this.buffer.length);
        this.buffer = newBuffer;
    }


    float32ToPCM16(float32Array) {
        const pcm16Array = new Int16Array(float32Array.length);
        for (let i = 0; i < float32Array.length; i++) {
            const s = Math.max(-1, Math.min(1, float32Array[i]));
            pcm16Array[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
        }
        return pcm16Array;
    }

    addMessage(role, text) {
        const messageClass = role === 'GPTfy' ? 'ai' : 'user';
        let gptfy = role === 'GPTfy' ? true : false;
        this.messages = [...this.messages, { id: Date.now(), role, text, messageClass, gptfy,isUserInputMessage: false }];
        this.scrollToBottom();
    }

    appendToLatestMessage(role, delta) {
        const lastMessage = this.messages[this.messages.length - 1];
        if (lastMessage && lastMessage.role === role) {
            lastMessage.text += delta;
            this.messages = [...this.messages];
        } else {
            this.addMessage(role, delta);
        }
    }

    scrollToBottom() {
        requestAnimationFrame(() => {
            const container = this.template.querySelector('.chat-messages');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
            })
        );
    }

    // Clean up resources when component is disconnected
    disconnectedCallback() {
        if (this.websocket) {
            this.websocket.close();
        }
        if (this.audioStream) {
            this.audioStream.getTracks().forEach((track) => track.stop());
        }
        if (this.audioContext) {
            this.audioContext.close();
            this.audioContext = null;
        }
    }

    handleInputChange = (event) => {
        this.userInput = event.target.value;
    }

    userInputChangeHandler = (event) => {
        this.userInput = event.target.value;
        // Send message on Enter key press
        if (event.keyCode === 13 && this.userInput) { 
            this.sendMessageToAI(this.userInput);
            this.userInput = '';
        }
    }

    handleSendClick = () => {
        if (this.userInput && this.userInput.length > 0) {
            this.sendMessageToAI(this.userInput);
            this.userInput = '';
        }
    }

    sendMessageToAI = (value) => {
        if (this.websocket?.readyState !== WebSocket.OPEN) {
            this.showToast('Error', 'WebSocket is not connected. Please start recording first.', 'error');
            return;
        }
        
        // Send user message as conversation item
        this.websocket.send(JSON.stringify({
            type: 'conversation.item.create',
            item: {
                type: 'message',
                role: 'user',
                content: [{ type: 'input_text', text: value }]
            }
        }));
        
        // Request response
        this.websocket.send(JSON.stringify({
            type: "response.create",
            response: {
                modalities: ["text", "audio"]
            }
        }));
        
        this.addMessage('Me', value);
        this.isResponding = true;
    }
}