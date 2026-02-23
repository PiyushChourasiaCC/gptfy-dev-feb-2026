import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import audioworkletprocessor from '@salesforce/resourceUrl/audioworkletprocessor';
import playbackworklet from '@salesforce/resourceUrl/playbackworklet';
import gptfylogo from '@salesforce/resourceUrl/gptfylogo';
// import getObjectByName from '@salesforce/apex/AIRealTimeVoiceController.getObjectByName';
// import getPromptByName from '@salesforce/apex/AIRealTimeVoiceController.getPromptByName';
import getInitDetails from '@salesforce/apex/AIRealTimeVoiceController.getInitDetails';
import findRecordsUsingSearchKey from '@salesforce/apex/AIRealTimeVoiceController.findRecordsUsingSearchKey';
import RESP_MESSAGE_FIELD from '@salesforce/schema/AI_Response__c.Message__c';
import RESP_STATUS_FIELD from '@salesforce/schema/AI_Response__c.Status__c';
import RESP_DATA_ORIGINAL_FIELD from '@salesforce/schema/AI_Response__c.Data_Original__c';
import RESP_Processed_Data_PII_Added_FIELD from '@salesforce/schema/AI_Response__c.AI_Processed_Data_PII_Added__c';
import initiateGPT from '@salesforce/apex/ChatGPTUtills.initiateGPT';

export default class AIRealTimeVoiceComponent extends LightningElement {
    @track messages = [];
    @track isRecording = false;
    @track isResponding = false;
    @track buttonLabel = 'Start Recording';
    @track userInput = '';
    columns = [];
    dataTable = [
        { Id: 'sdfgsdf555', 'Account Name': 'Acc test name', 'Industry': 'Technology' },
        { Id: 'ghjk98765', 'Account Name': 'Another Account', 'Industry': 'Finance' }
    ]

    gptfylogo = gptfylogo
    websocket;
    audioContext;
    audioStream;
    buffer = new Uint8Array();
    playbackQueue = []; // Queue for audio playback to prevent overlaps
    isChatInputTextEnabled = true;
    playbackNode = null;
    objectTypes = []
    promptNames = [];

    
    


    // Azure OpenAI configuration
   // deployment = 'gpt-4o-realtime-preview';
    endpoint = ''
    // apiKey = '9FzRxq2nMHNzlduqmGEozrwJ5o9Ittb57A0SGOPTzwVvS7Otjb6NJQQJ99ALACHYHv6XJ3w3AAAAACOGIjot'; // Provide your API key here
    // apiVersion = '2024-10-01-preview';

    get showChat(){
        return this.endpoint && this.endpoint.length > 0;
    }


    connectedCallback(){
        getInitDetails().then((result) => {
            let res = JSON.parse(JSON.stringify(result))
            console.log(res)
            this.endpoint = res.endpoint;
            this.promptNames = res.promptNames
            this.objectTypes = res.objectTypes
            this.initializeWebSocket();
            if (this.dataTable.length > 0) {
                let keys = Object.keys(this.dataTable[0]);
                this.columns = keys.map(key => {
                    return {
                        label: key,
                        fieldName: key,
                        type: key === 'Id' ? 'text' : 'text' // Adjust type if needed
                    };
                });
                // Add "Select" button column
                this.columns.push({
                    label: 'Action',
                    type: 'button',
                    initialWidth: 120,
                    typeAttributes: {
                        label: 'Select',
                        name: 'select',
                        variant: 'brand'
                    }
                });
            }
        })

    }

    handleRowAction(event) {
        const row = event.detail.row;
        alert(`Selected Row: ${JSON.stringify(row)}`); // You can replace this with any logic
    }

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
           // await this.initializeWebSocket();
           // await this.initializeAudioRecording();
           // await this.initializeAudioPlayer();
            this.isRecording = true;
            this.buttonLabel = 'Stop Recording';
        } catch (error) {
            this.showToast('Error', `Error starting recording: ${error.message}`, 'error');
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

    // WebSocket Initialization
    async initializeWebSocket() {
        try {
            this.websocket = new WebSocket(this.endpoint);

            this.websocket.onopen = () => {
                console.log('WebSocket connection established');
                this.websocket.send(
                    JSON.stringify({
                        type: 'session.update',
                        session: {
                            voice: 'alloy',
                            input_audio_format: 'pcm16',
                            input_audio_transcription: { model: 'whisper-1' },
                            turn_detection: {
                                type: 'server_vad',
                                threshold: 0.5,
                                prefix_padding_ms: 300,
                                silence_duration_ms: 200,
                            },
                            tools: [
                                // {
                                //     type: 'function',
                                //     name: 'getObjectDetails',
                                //     description: 'Gets a record from Salesforce using record name and object type',
                                //     parameters: {
                                //         type: 'object',
                                //         properties: {
                                //             recordName: { type: 'string', description: 'The record name for which data to be fetched' },
                                //             objectType: { type: 'string', enum: this.objectTypes, description: 'The Object Type for which object to be fetch from Salesforce.' },
                                //         },
                                //         required: ["recordName","objectType"]
                                //     },
                                // },
                                {
                                    type: 'function',
                                    "name": "fetchObjectRecordUsingPrompt",
                                    "description": "Get object record details from salesforce using name filter. Its will be return Account, Contact, Opportunity, Lead, Case, Task, Event, Custom Object etc.",
                                    parameters: {
                                        type: 'object',
                                        properties: {
                                            recordName: { type: 'string', description: 'The recordName is name field of record' },
                                            promptName: { type: 'string', enum: this.promptNames, description: 'Use default value of prompt Name.' },
                                        },
                                        required: ["recordName","promptName"]
                                    },
                                }
                                // ,
                                // {
                                //     type: 'function',
                                //     name: "getPromptRecord",
                                //     description: "Get Prompt Record Details from Salesforce. Its will be return Prompt Object.",
                                //     parameters: {
                                //         type: 'object',
                                //         properties: {
                                //             promptName : { type: 'string',enum: this.promptNames, description: 'The prompt Name for Prompt record fetched from Salesforce' },
                                //         },
                                //     },
                                // },
                                
                                // {
                                //     type: 'function',
                                //     "name": "exceutePromptOnRecord",
                                //     "description": "Execute a prompt on an object record using its Record ID and associated Prompt ID. Prompt ID is fetched using the retrievePromptRecordId function.",
                                //     parameters: {
                                //         type: 'object',
                                //         properties: {
                                //             recordId: { type: 'string', description: 'The record Id of Object Record' },
                                //             promptId: { type: 'string', description: 'Prompt Id of Prompt Record' },
                                //         },
                                //     },
                                // }
                            ]
                        },
                    })
                );
            };

            this.websocket.onmessage = this.handleWebSocketMessage.bind(this);
            this.websocket.onerror = this.handleWebSocketError.bind(this);
            this.websocket.onclose = this.handleWebSocketClose.bind(this);
        } catch (error) {
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
            // if (this.isRecording && this.websocket?.readyState === WebSocket.OPEN) {

            //     const uint8Array = new Uint8Array(event.data.buffer);
            //     this.combineArray(uint8Array);
            //     if (this.buffer.length >= 4800) {
            //         const toSend = new Uint8Array(this.buffer.slice(0, 4800));
            //         this.buffer = new Uint8Array(this.buffer.slice(4800));
            //         const regularArray = String.fromCharCode(...toSend);
            //         const base64 = btoa(regularArray);
            //         this.websocket.send(JSON.stringify({
            //             type: "input_audio_buffer.append",
            //             audio: base64,
            //         }));
            //     }   
            // }
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
                case 'response.text.delta':
                    if(message.delta){
                        this.appendToLatestMessage('GPTfy', message.delta);
                    }
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
                    // play audio
                    // const binary = atob(message.delta);
                    // const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
                    // const pcmData = new Int16Array(bytes.buffer);
                    // this.play(pcmData);
                    break;
    
                case 'response.done':
                    this.isResponding = false;
                    //this.addMessage('System', '<< Response Completed >>');
                    break;
                case 'response.text.done':
                    //console.log('response.text.done:', message);
                    // if(message.text){
                    //     this.addMessage('GPTfy', message.text);
                    // }
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
                    console.log('Unhandled message type:', message);
                    break;
            }
        }
    }

    functionCalling = (message) => {
        // if(message.name === 'getObjectDetails'){
        //     let args = JSON.parse(message.arguments);
        //     this.addMessage('GPTfy', `Fetching Account Details for ${args.recordName}...`);
        //     if(args.objectType && args.recordName){
        //         this.fetchObjectDetails(args.objectType,args.recordName).then((acc)=> {
        //             this.websocket.send(JSON.stringify({ 
        //                 type: 'conversation.item.create',
        //                 item: {
        //                     type: 'function_call_output',
        //                     call_id: message.call_id, 
        //                     output: JSON.stringify(acc) 
        //                 }}));
    
        //             this.websocket.send(JSON.stringify({
        //                     type: "response.create",
        //                     response: {
        //                         modalities: ["text"],
        //                         instructions: `Respond to the user Record Name and Description. Here is details Account Name is ${acc.Name}. Be concise, formated design and friendly.`,
        //                     }
        //                 }));
        //         });
        //     }
            
        // }else 
        // if(message.name === 'getPromptRecord'){
        //     let args = JSON.parse(message.arguments);
        //     if(args.promptName){
        //         this.addMessage('GPTfy', `Fetching Prompt ${args.promptName}...`);
        //         getPromptByName({ promptName: args.promptName }).then((prompt)=> {
        //             if(prompt){
        //                 let res = JSON.stringify(prompt)
        //                 this.websocket.send(JSON.stringify({ 
        //                     type: 'conversation.item.create',
        //                     item: {
        //                         type: 'function_call_output',
        //                         call_id: message.call_id, 
        //                         output: res
        //                     }}));
        //                 this.websocket.send(JSON.stringify({
        //                         type: "response.create",
        //                         response: {
        //                             modalities: ["text"],
        //                             instructions: `Respond to the user Prompt Name. Call function exceutePromptOnRecord`,
        //                         }
        //                     }));
        //             }
        //         })
        //     }
        // }else 
        if(message.name === 'fetchObjectRecordUsingPrompt'){
            let args = JSON.parse(message.arguments);
            this.addMessage('GPTfy', `Fetching ...`);
            if(args.recordName && args.promptName){
                findRecordsUsingSearchKey({ promptName: args.promptName,searchKey: args.recordName }).then((response)=> {
                    if(response){
                        let res = JSON.parse(JSON.stringify(response))
                        if(res.length > 10){
                            res = res.slice(0,10)
                         }
                        this.websocket.send(JSON.stringify({ 
                            type: 'conversation.item.create',
                            item: {
                                type: 'function_call_output',
                                call_id: message.call_id, 
                                output: res
                            }}));
                        let arr = []
                        res.map((item) => {
                            arr.push({label: item['Account Name'], value: item.Id})
                        })
                        this.accountOptions = arr;
                        let lastIndex = this.messages[this.messages.length - 1]
                        lastIndex.optionsVisible = true
                        this.messages = [...this.messages];
                    }else{
                        this.websocket.send(JSON.stringify({ 
                            type: 'conversation.item.create',
                            item: {
                                type: 'function_call_output',
                                call_id: message.call_id, 
                                output: 'Record not found'
                            }}));
                        this.addMessage('GPTfy', `Record not found`);
                    }
                })
            }
        }
        // else if(message.name === 'runPromptOnObjectRecord'){
        //     let args = JSON.parse(message.arguments);
        //     this.addMessage('GPTfy', `Executing Prompt ...`);
        //     if(args.recordId && args.promptId){
        //         this.executePrompt(args.recordId,args.promptId).then((response)=> {
                
        //             if(response){
        //                 let res = JSON.parse(JSON.stringify(response))
        //                 this.websocket.send(JSON.stringify({ 
        //                     type: 'conversation.item.create',
        //                     item: {
        //                         type: 'function_call_output',
        //                         call_id: message.call_id, 
        //                         output: res[RESP_DATA_ORIGINAL_FIELD.fieldApiName]
        //                     }}));
        
        //                     this.addMessage('GPTfy', res[RESP_Processed_Data_PII_Added_FIELD.fieldApiName]);
        //             }
        //         });
        //     }
            
        // }
        // else if(message.name === 'userInputRecordNameFunction'){
        //     let msg = this.messages
        //     msg[msg.length - 1].isUserInputMessage = true
        //     this.messages = msg;
        // }
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
    

    appendToLatestMessage(role, delta) {
        const lastMessage = this.messages[this.messages.length - 1];
        if (lastMessage && lastMessage.role === role) {
            lastMessage.text += delta;
            this.messages = [...this.messages];
        } else {
            this.addMessage(role, delta);
        }
    }
    
    
    

    // WebSocket Error Handler
    handleWebSocketError(error) {
        this.showToast('WebSocket Error', error.message, 'error');
    }

    // WebSocket Close Handler
    handleWebSocketClose() {
        this.isRecording = false;
        this.isResponding = false;
        this.buttonLabel = 'Start Recording';
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
        this.messages = [...this.messages, { id: Date.now(), role, text, messageClass, gptfy,isUserInputMessage: false,optionsVisible: false }];
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

    userInputChangeHandler = (event) => {
        console.log(event.keyCode);
        console.log(event.target.value)
        this.userInput = event.target.value;
        if(event.keyCode === 13 && event.target.value){ 
            this.sendMessageToAI(event.target.value)
            this.userInput = '';
        }
    }

    handleSendClick = (event) => {
        let chatInputText = this.template.querySelector('.chat-input').value;
        if(chatInputText && chatInputText.length > 0){
            this.sendMessageToAI(chatInputText)
        }
    }

    sendMessageToAI = (value)=> {
        this.websocket.send(JSON.stringify({
            type: "response.create",
            response: {
               // modalities: ["text", "audio"],
                modalities: ["text"],
                instructions: value ,
            }
        }));
        this.addMessage('user', value);
        
    }

    handleOptionClick = (event) => {
        const selectedId = event.target.dataset.id;
        console.log('Selected Account ID:', selectedId);
    }
}