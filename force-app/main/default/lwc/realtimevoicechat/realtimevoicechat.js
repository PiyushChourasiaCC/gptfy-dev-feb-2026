import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import audioworkletprocessor from '@salesforce/resourceUrl/audioworkletprocessor';
import gptfylogo from '@salesforce/resourceUrl/gptfylogo';
//import getAccountsByName from '@salesforce/apex/OpenAIServiceTestVoice.getAccountsByName';

export default class Realtimevoicechat extends LightningElement {
    @track messages = [];
    @track isRecording = false;
    @track isResponding = false;
    @track buttonLabel = 'Start Recording';

    gptfylogo = gptfylogo
    websocket;
    audioContext;
    audioStream;
    buffer = new Uint8Array();
    playbackQueue = []; // Queue for audio playback to prevent overlaps

    // Azure OpenAI configuration
    deployment = 'gpt-4o-mini-realtime-preview';
    endpoint = 'neel-m74zh4ra-swedencentral.cognitiveservices.azure.com';
    apiKey = 'lRM3ZDfA8sPy3U2Wr1KfJ669HKBqKPmhbuxrvDTqmdi5M5BcDqUuJQQJ99BBACfhMk5XJ3w3AAAAACOGZYpH'; // Provide your API key here
    apiVersion = '2024-10-01-preview';

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
            await this.initializeWebSocket();
            await this.initializeAudioRecording();
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
            const wsUrl = `wss://${this.endpoint}/openai/realtime?api-version=${this.apiVersion}&deployment=${this.deployment}&api-key=${this.apiKey}`;
            this.websocket = new WebSocket(wsUrl);

            this.websocket.onopen = () => {
                console.log('WebSocket connection established');
                this.websocket.send(
                    JSON.stringify({
                        type: 'session.update',
                        session: {
                            voice: 'alloy',
                            instructions: "User Native language is english. Please respond to the user in english language.",
                            input_audio_format: 'pcm16',
                            input_audio_transcription: { model: 'whisper-1' },
                            turn_detection: {
                                type: 'server_vad',
                                threshold: 0.5,
                                prefix_padding_ms: 300,
                                silence_duration_ms: 200,
                            },
                            tools: [
                                {
                                    type: 'function',
                                    name: 'getAccountDetails',
                                    description: 'Get Account Details with related records details from Salesforce',
                                    parameters: {
                                        type: 'object',
                                        properties: {
                                            name: { type: 'string', description: 'Account Name of Record' },
                                        },
                                    },
                                },
                                {
                                    type: 'function',
                                    name: 'executePromptWithRecord',
                                    description: 'Execute Prompt using Account Record Id',
                                    parameters: {
                                        type: 'object',
                                        properties: {
                                            recordId: { type: 'string', description: 'Account Id of Record' },
                                        },
                                    },
                                }
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

                        // const inputData = event.inputBuffer.getChannelData(0);
                        // this.combineArray(inputData);
    
                        // if (this.buffer.length >= 2400 * 2) {
                        //     const pcm16Data = this.float32ToPCM16(this.buffer);
                        //     const base64Audio = btoa(String.fromCharCode(...new Uint8Array(pcm16Data.buffer)));
                        //     this.websocket.send(
                        //         JSON.stringify({ type: 'input_audio_buffer.append', audio: base64Audio })
                        //     );
                        //     this.buffer = new Uint8Array(); // Clear buffer after sending
                        // }
                    }
        };

        // Connect microphone to the worklet
        const source = this.audioContext.createMediaStreamSource(this.audioStream);
        source.connect(audioWorkletNode);

        this.showToast('Success', 'Microphone access granted', 'success');







            // const source = this.audioContext.createMediaStreamSource(this.audioStream);
            // const processor = this.audioContext.createScriptProcessor(4096, 1, 1);

            // processor.onaudioprocess = (e) => {
            //     if (this.isRecording && this.websocket?.readyState === WebSocket.OPEN) {
            //         const inputData = e.inputBuffer.getChannelData(0);
            //         this.combineArray(inputData);

            //         if (this.buffer.length >= 2400 * 2) {
            //             const pcm16Data = this.float32ToPCM16(this.buffer);
            //             const base64Audio = btoa(String.fromCharCode(...new Uint8Array(pcm16Data.buffer)));
            //             this.websocket.send(
            //                 JSON.stringify({ type: 'input_audio_buffer.append', audio: base64Audio })
            //             );
            //             this.buffer = new Uint8Array(); // Clear buffer after sending
            //         }
            //     }
            // };

            // source.connect(processor);
            // processor.connect(this.audioContext.destination);

           // this.showToast('Success', 'Microphone access granted', 'success');
        } catch (error) {
            this.showToast('Error', `Microphone access failed: ${error.message}`, 'error');
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
                    this.enqueueAudioPlayback(message.delta);
                    break;
    
                case 'response.done':
                    this.isResponding = false;
                    //this.addMessage('System', '<< Response Completed >>');
                    break;
    
                case 'input_audio_buffer.speech_started':
                    //this.addMessage('System', '<< Speech Started >>');
                    break;

                case 'response.function_call_arguments.done':
                    console.log('Function Call Arguments:', message.arguments);
                    console.log('Function Call name:', message.name);
                    if(message.name === 'getAccountDetails'){
                        let args = JSON.parse(message.arguments);
                        this.addMessage('GPTfy', `Fetching Account Details for ${args.name}...`);
                        this.fetchAccountDetails(args.name).then((acc)=> {
                            this.websocket.send(JSON.stringify({ 
                                type: 'conversation.item.create',
                                item: {
                                    type: 'function_call_output',
                                    call_id: message.call_id, 
                                    output: JSON.stringify(acc) 
                                }}));
    
                            this.websocket.send(JSON.stringify({
                                    type: "response.create",
                                    response: {
                                        modalities: ["text", "audio"],
                                        instructions: `Respond to the user Record Name and Description in html format with bullets. Here is details Account Name is ${acc.Name} and Description is ${acc.Description}. Be concise, formated design and friendly.`,
                                    }
                                }));
                        });
                    }else if(message.name === 'executePromptWithRecord'){
                        //let args = JSON.parse(message.arguments);
                        this.addMessage('GPTfy', `Executing Prompt ...`);
                        this.executePrompt().then((response)=> {
                            this.websocket.send(JSON.stringify({ 
                                type: 'conversation.item.create',
                                item: {
                                    type: 'function_call_output',
                                    call_id: message.call_id, 
                                    output: response 
                                }}));

                                this.addMessage('GPTfy', response);
    
                            // this.websocket.send(JSON.stringify({
                            //         type: "response.create",
                            //         response: {
                            //             modalities: ["text", "audio"],
                            //             instructions: `Respond to the html response ${response}.`,
                            //         }
                            //     }));
                        });
                    }
                    break;
    
                default:
                    console.log('Unhandled message type:', message.type);
                    break;
            }
        }
    }

    async executePrompt() {
        let getOpportunityRows = await this.generateOpportunitiesTable();
        let getCaseRows = await this.generateCasesTable();
        return `
            ${getOpportunityRows}
            ${getCaseRows}
        `;
    }
    
    async generateOpportunitiesTable() {
        let opportunities = await this.getOpportunityRows();
        return `
            <table border="1">
                <caption style="font-size: 1.0rem; font-weight: bold; padding: 0.5rem; color: #5C5C5C; text-align: left;">
                    Opportunities
                </caption>
                <tr>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Opportunity</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Summary</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Objection</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Next Best Action</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Close date</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Amount</th>
                </tr>
                ${opportunities}
            </table>
        `;
    }
    
    async generateCasesTable() {
        let cases = await this.getCaseRows();
        return `
            <table border="1">
                <caption style="font-size: 1.0rem; font-weight: bold; padding: 0.5rem; color: #5C5C5C; text-align: left;">
                    Cases
                </caption>
                <tr>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Case</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Summary</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Customer Intent</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Sentiment</th>
                    <th style="background-color: #e1ebf7; color: #16325c; padding: 0.5rem; text-align: left;">Days Open</th>
                </tr>
                ${cases}
            </table>
        `;
    }
    
    getOpportunityRows() {
        return `
            <tr>
                <td><a href="/006J7000003d2pZIAQ" target="_blank">Integration of Platts Price Assessments</a></td>
                <td>Gaslume Europe division wants to integrate Platts price assessments to make informed decisions regarding their trading and investment strategies.</td>
                <td>N/A</td>
                <td>N/A</td>
                <td>28-Jun-24</td>
                <td>1500000.00</td>
            </tr>
            <tr>
                <td><a href="/006J7000003d2pbIAA" target="_blank">Supplier Risk Assessment for Global partners</a></td>
                <td>Gaslume wants to use the Supplier Risk Indicator™ to assess and manage their supplier risks better.</td>
                <td>N/A</td>
                <td>N/A</td>
                <td>31-Jan-24</td>
                <td>317985.00</td>
            </tr>
            <tr>
                <td><a href="/006J7000003d2paIAA" target="_blank">Solar/ESG - Custom Market Analysis Deal</a></td>
                <td>Gaslume's global commodities trading team wants in-depth analysis to guide their trading decisions to align with their corporate sustainability and ESG goals.</td>
                <td>N/A</td>
                <td>N/A</td>
                <td>29-Feb-24</td>
                <td>500000.00</td>
            </tr>
        `;
    }
    
    getCaseRows() {
        return `
            <tr>
                <td><a href="/500J7000007shLPIAY" target="_blank">Discrepancy in Platts Price Assessments</a></td>
                <td>I've noticed discrepancies between the Platts price assessments and the actual market prices.</td>
                <td>N/A</td>
                <td>N/A</td>
                <td>1 day</td>
            </tr>
            <tr>
                <td><a href="/500J7000007shLQIAY" target="_blank">Request for Custom Market Analysis</a></td>
                <td>Our company is looking for a custom report on the biofuel market in Southeast Asia.</td>
                <td>N/A</td>
                <td>N/A</td>
                <td>1 day</td>
            </tr>
            <tr>
                <td><a href="/500J7000007shLRIAY" target="_blank">Integration Issues with Workflow Solutions</a></td>
                <td>We're facing technical glitches with the integration of workflow solutions into our systems.</td>
                <td>N/A</td>
                <td>N/A</td>
                <td>1 day</td>
            </tr>
            <tr>
                <td><a href="/500J7000007shLSIAY" target="_blank">Data Analytics API Access</a></td>
                <td>We're interested in accessing data analytics on metal commodities through an API.</td>
                <td>N/A</td>
                <td>N/A</td>
                <td>Closed</td>
            </tr>
            <tr>
                <td><a href="/500J7000007shLTIAY" target="_blank">Registration for CERAWeek Conference</a></td>
                <td>I'm trying to register for the CERAWeek conference, but the registration page is down.</td>
                <td>N/A</td>
                <td>N/A</td>
                <td>1 day</td>
            </tr>
        `;
    }
    
    

   // executePrompt(){
   //     
        // initiateGPT({
        //             "recordId" : "001J700000CpUqBIAV", 
        //             "promptId" : "a058d00000FUapFAAT", 
        //             "userInput" : null, 
        //             "mapOfFiles" : null,
        //             "isGptfyConsole" : false
        //         })
        //         .then(result => {
        //             if(result && result[RESP_STATUS_FIELD.fieldApiName] && result[RESP_STATUS_FIELD.fieldApiName] == 'Errored' && result[RESP_MESSAGE_FIELD.fieldApiName] && result[RESP_MESSAGE_FIELD.fieldApiName] != null){
        //                 var msg = result[RESP_MESSAGE_FIELD.fieldApiName];
        //                 this.showToast('error', 'Error', msg, 'dismissable');
        //                 this.showSpinner = false; 
        //             }else{
        //                 this.getGptResponses();
        //             } 
        //         })
        //         .catch(error => {
        //             console.error('Error in executePrompt:', error);
        //             //this.handleError(error);
        //         });
   // }

    async fetchAccountDetails(accountName) {  

        // return { 
        //     "Object Name" : "Account",
        //     "Description" : "Established in 2000, GasLume Energy is a pioneer in gas exploration and production, with 23 years in the market and annual revenues of $5.8 billion.",
        //     "Id" : "001J700000CpUqBIAV",
        //     "Name" : "GasLume Energy"
        // }


return {
  "Cases" : [ {
    "Origin" : "Email",
    "CreatedBy.SystemModstamp" : "2024-11-07 17:45:11",
    "AccountId" : "001J700000CpUqBIAV",
    "Subject" : "Discrepancy in Platts Price Assessments",
    "Description" : "I've been using your Platts price assessments for crude oil, but I've noticed some discrepancies between the prices listed on your platform and the actual market prices. Can you explain the methodology behind these assessments and how often they are updated?",
    "CreatedDate" : "2025-01-04 00:00:08",
    "IsClosed" : "false",
    "CaseNumber" : "00001179",
    "Id" : "500J7000007shLPIAY",
    "Status" : "New"
  }, {
    "Origin" : "Phone",
    "CreatedBy.SystemModstamp" : "2024-11-07 17:45:11",
    "AccountId" : "001J700000CpUqBIAV",
    "Subject" : "Request for Custom Market Analysis",
    "Description" : "Our company is looking to expand into the biofuel market in Southeast Asia. We would like a custom report detailing the supply and demand trends, potential challenges, and growth forecasts for the next five years. Can your research team assist with this?",
    "CreatedDate" : "2025-01-04 00:00:08",
    "IsClosed" : "false",
    "CaseNumber" : "00001180",
    "Id" : "500J7000007shLQIAY",
    "Status" : "Escalated"
  }, {
    "Origin" : "Web",
    "CreatedBy.SystemModstamp" : "2024-11-07 17:45:11",
    "AccountId" : "001J700000CpUqBIAV",
    "Subject" : "Integration Issues with Workflow Solutions",
    "Description" : "We recently integrated your workflow solutions into our internal systems. However, we're facing some technical glitches, especially with data synchronization. Can we get technical support to resolve these issues?",
    "CreatedDate" : "2025-01-04 00:00:08",
    "IsClosed" : "false",
    "CaseNumber" : "00001181",
    "Id" : "500J7000007shLRIAY",
    "Status" : "On Hold"
  }, {
    "Origin" : "Email",
    "CreatedBy.SystemModstamp" : "2024-11-07 17:45:11",
    "AccountId" : "001J700000CpUqBIAV",
    "Subject" : "Data Analytics API Access",
    "Description" : "We're interested in accessing your data analytics on metal commodities through an API for our internal dashboard. Do you offer such services, and if so, what are the associated costs and access limitations?",
    "CreatedDate" : "2025-01-04 00:00:08",
    "ClosedDate" : "2025-01-04 00:00:08",
    "IsClosed" : "true",
    "CaseNumber" : "00001182",
    "Id" : "500J7000007shLSIAY",
    "Status" : "Closed"
  }, {
    "Origin" : "Phone",
    "CreatedBy.SystemModstamp" : "2024-11-07 17:45:11",
    "AccountId" : "001J700000CpUqBIAV",
    "Subject" : "Registration for CERAWeek Conference",
    "Description" : "I'm trying to register for the upcoming CERAWeek conference, but the registration page seems to be down. Can you provide an alternative method for registration or check if there's an issue with the website?",
    "CreatedDate" : "2025-01-04 00:00:08",
    "IsClosed" : "false",
    "CaseNumber" : "00001183",
    "Id" : "500J7000007shLTIAY",
    "Status" : "New"
  } ],
  "Contacts" : [ {
    "Id" : "003J700000CyV78IAF",
    "AccountId" : "001J700000CpUqBIAV",
    "Email" : "cherlyn.smalman@gaslumeenergy.com.invalid",
    "LastName" : "Smalman",
    "FirstName" : "Cherlyn",
    "Description" : "Oversees the analysis of commodity markets, leveraging data and technology to forecast trends and inform business strategies.",
    "Title" : "Data Analytics Specialist"
  }, {
    "Id" : "003J700000CyV7oIAF",
    "AccountId" : "001J700000CpUqBIAV",
    "Email" : "jacinda.towey@gaslumeenergy.com.invalid",
    "LastName" : "Towey",
    "FirstName" : "Jacinda",
    "Description" : "Responsible for sourcing metals for manufacturing processes. Relies on market insights to negotiate contracts and ensure a steady supply.",
    "Title" : "Supply Chain Director"
  }, {
    "Id" : "003J700000CyV8GIAV",
    "AccountId" : "001J700000CpUqBIAV",
    "Email" : "faydra.rassell@gaslumeenergy.com.invalid",
    "LastName" : "Rassell",
    "FirstName" : "Faydra",
    "Description" : "Oversees the analysis of commodity markets, leveraging data and technology to forecast trends and inform business strategies.",
    "Title" : "Technology Integration Lead"
  }, {
    "Id" : "003J700000CyV93IAF",
    "AccountId" : "001J700000CpUqBIAV",
    "Email" : "katalin.mendonca@gaslumeenergy.com.invalid",
    "LastName" : "Mendonca",
    "FirstName" : "Katalin",
    "Description" : "Advises on agricultural commodity markets, leveraging data-driven insights to guide procurement and sales strategies.",
    "Title" : "Commodity Research Lead"
  }, {
    "Id" : "003J700000CyV8OIAV",
    "AccountId" : "001J700000CpUqBIAV",
    "Email" : "aurel.itzkovwich@gaslumeenergy.com.invalid",
    "LastName" : "Itzkovwich",
    "FirstName" : "Aurel",
    "Description" : "Responsible for sourcing and purchasing commodities and services. Relies on data-driven insights to make informed decisions and is keen on adopting technology to streamline procurement processes.",
    "Title" : "Sustainability Officer"
  }, {
    "Id" : "003J700000CyV8iIAF",
    "AccountId" : "001J700000CpUqBIAV",
    "Email" : "norah.ervine@gaslumeenergy.com.invalid",
    "LastName" : "Ervine",
    "FirstName" : "Norah",
    "Description" : "Leads research initiatives related to commodities, leveraging technology to gather and analyze data, and provide actionable insights.",
    "Title" : "Data Analytics Specialist"
  }, {
    "Id" : "003J700000CyV91IAF",
    "AccountId" : "001J700000CpUqBIAV",
    "Email" : "bond.raymen@gaslumeenergy.com.invalid",
    "LastName" : "Raymen",
    "FirstName" : "Bond",
    "Description" : "Oversees the analysis of commodity markets, leveraging data and technology to forecast trends and inform business strategies.",
    "Title" : "Supply Chain Director"
  }, {
    "Id" : "003J700000CyV8HIAV",
    "AccountId" : "001J700000CpUqBIAV",
    "Email" : "eduino.kowalik@gaslumeenergy.com.invalid",
    "LastName" : "Kowalik",
    "FirstName" : "Eduino",
    "Description" : "Responsible for sourcing and purchasing commodities and services. Relies on data-driven insights to make informed decisions and is keen on adopting technology to streamline procurement processes.",
    "Title" : "Energy Market Analyst"
  } ],
  "Emails" : [ {
    "Subject" : "Re: Re: Re: Initial Consultation Request",
    "Status" : "2",
    "FromName" : "Jack Ryan",
    "FromAddress" : "demosg@outlook.com",
    "ToAddress" : "norah.ervine@gaslumeenergy.com.invalid",
    "TextBody" : "Norah, We are set for 10am EST tomorrow. Please find the dial-in details below. I've put together an agenda that will cover all the topics you outlined. Our platform has best-in-class data and analytics across global oil and gas markets, from upstream production to end-user demand trends. I'll also make sure to demonstrate our geospatial risk analysis capabilities, shale forecasts, and solar energy projections. Really looking forward to showing you how New Oil/Data can provide Gaslume with unparalleled market insights to drive your trading strategies. Speak soon! Regards, Jack Ryan, Account Executive, New Oil/Data Inc., 555-987-6543, Agenda: 1) Oil and gas pricing data - Granular assessments for ME/Africa - Supply/demand forecasts 2) Geopolitical risk analytics 3) US/Latin American shale oil analysis 4) Solar trends in US/China, Dial-In: +1-555-123-9876, Access Code: 890345",
    "RelatedToId" : "001J700000CpUqBIAV",
    "MessageDate" : "2023-09-19 14:30:15"
  }, {
    "Subject" : "Re: Demo and Pricing Follow-up",
    "Status" : "2",
    "FromName" : "Norah Ervine",
    "FromAddress" : "norah.ervine@gaslumeenergy.com.invalid",
    "ToAddress" : "demosg@outlook.com",
    "TextBody" : "Hi Jack, Thank you for the very informative demo yesterday. I'm impressed with the breadth and depth of your oil and gas pricing data, especially for the middle east and africa. The risk analysis features are also very valuable for our trading strategy. Before we move forward, I wanted to follow up on the subscription pricing options you outlined. Can you send over the multi-year packages? I'd like to explore whether there's additional cost savings for a 3-5 year commitment. Thanks again, Norah",
    "RelatedToId" : "001J700000CpUqBIAV",
    "MessageDate" : "2023-09-20 09:00:00"
  }, {
    "Subject" : "Re: Re: Demo and Pricing Follow-up",
    "Status" : "2",
    "FromName" : "Jack Ryan",
    "FromAddress" : "demosg@outlook.com",
    "ToAddress" : "norah.ervine@gaslumeenergy.com.invalid",
    "TextBody" : "Hi Norah, I'm glad you found the demo valuable and that you're interested in a multi-year deal. Please find attached our 3-5 year pricing packages for the MidEast/Africa Plus plan you're interested in. As you'll see, we offer tiered discounts for longer subscriptions, up to 20% off for 5 year commitments. This allows us to lock-in the partnership and ensures you get the lowest rate. Let me know if you need any additional details as you evaluate options. I'm confident New Oil/Data will become an indispensable tool for Gaslume's success. Looking forward to your thoughts, Jack",
    "RelatedToId" : "001J700000CpUqBIAV",
    "MessageDate" : "2023-09-21 12:30:45"
  }, {
    "Subject" : "Re: Re: Initial Consultation Request",
    "Status" : "2",
    "FromName" : "Norah Ervine",
    "FromAddress" : "norah.ervine@gaslumeenergy.com.invalid",
    "ToAddress" : "demosg@outlook.com",
    "TextBody" : "Dear Jack, 10am EST tomorrow works perfectly. I'm looking forward to learning more about your data offerings during the call. As discussed, I'm particularly interested in: - Granular pricing data for Middle East and African oil - Detailed supply/demand analysis - Geopolitical risk insights that could impact pricing - Emerging shale oil dynamics in US/Latin America - Solar growth trends in US/China Please send along an agenda and dial-in details when you have a moment. Thanks again for your quick response. Regards, Norah Ervine, Lead Data Analytics Specialist, Gaslume Energy, 555-123-4567",
    "RelatedToId" : "001J700000CpUqBIAV",
    "MessageDate" : "2023-09-19 13:15:45"
  }, {
    "Subject" : "Re: Re: Re: Re: Demo and Pricing Follow-up",
    "Status" : "2",
    "FromName" : "Jack Ryan",
    "FromAddress" : "demosg@outlook.com",
    "ToAddress" : "norah.ervine@gaslumeenergy.com.invalid",
    "TextBody" : "Hi Norah, Great to hear you're nearing final approval. Setting up access is simple. Once we have a signed agreement in place, I'll just need a list of email addresses for your team members that need access. We then set them up with individual logins to our online portal where they can access the data, tools, and downloads. Most of our platform interactions are self-serve through the portal, but we also provide support via email and phone as needed. Let me know if you need any help navigating the platform once your team is set up. Looking forward to getting started! Best, Jack",
    "RelatedToId" : "001J700000CpUqBIAV",
    "MessageDate" : "2023-09-24 08:15:30"
  }, {
    "Subject" : "Initial Consultation Request",
    "Status" : "1",
    "FromName" : "Norah Ervine",
    "FromAddress" : "norah.ervine@gaslumeenergy.com.invalid",
    "ToAddress" : "demosg@outlook.com",
    "TextBody" : "Dear Jack, I'm Norah Ervine, Lead Data Analytics Specialist at Gaslume Energy. I came across your company New Oil/Data and was very impressed with your energy data offerings. I wanted to schedule a call to discuss potentially getting access to your oil and gas pricing data, as well as any geopolitical risk insights you may have, especially for the Middle East and Africa. Please let me know if you have any availability this week. Best regards, Norah Ervine, Lead Data Analytics Specialist, Gaslume Energy, 555-123-4567",
    "RelatedToId" : "001J700000CpUqBIAV",
    "MessageDate" : "2023-09-17 08:30:15"
  }, {
    "Subject" : "Re: Initial Consultation Request",
    "Status" : "2",
    "FromName" : "Jack Ryan",
    "FromAddress" : "demosg@outlook.com",
    "ToAddress" : "norah.ervine@gaslumeenergy.com.invalid",
    "TextBody" : "Dear Norah, Thank you for reaching out and for your interest in New Oil/Data. As the leading provider of energy data and analytics, I'm confident we can provide Gaslume everything needed to maximize your trading and risk management strategies. I have availability tomorrow at 10am EST for a call. We can discuss your data needs in more depth, as well as provide a demo of our platform's capabilities covering oil and gas fundamentals, geopolitical risk analysis, and emerging trends like US shale and global solar. Please let me know if this time works for you. I look forward to speaking! Best, Jack Ryan, Account Executive, New Oil/Data Inc., 555-987-6543",
    "RelatedToId" : "001J700000CpUqBIAV",
    "MessageDate" : "2023-09-18 10:45:30"
  }, {
    "Subject" : "Re: Re: Re: Demo and Pricing Follow-up",
    "Status" : "2",
    "FromName" : "Norah Ervine",
    "FromAddress" : "norah.ervine@gaslumeenergy.com.invalid",
    "ToAddress" : "demosg@outlook.com",
    "TextBody" : "Jack, Thank you for sending over the multi-year pricing options. The discounts look very compelling. I'm going to get final approval from my manager and should have the green light shortly. One final question - can you outline the technical process for establishing access to the platform across my team? Please let me know any technical requirements on our end. Thanks, Norah",
    "RelatedToId" : "001J700000CpUqBIAV",
    "MessageDate" : "2023-09-23 15:45:15"
  } ],
  "Opportunities" : [ {
    "StageName" : "Value Proposition",
    "Owner.Name" : "Saurabh Gupta",
    "Name" : "Integration of Platts Price Assessments",
    "AccountId" : "001J700000CpUqBIAV",
    "CloseDate" : "2024-06-28 00:00:00",
    "Amount" : "1500000.00",
    "Description" : "Gaslume Europe division is looking to integrate Platts price assessments into their internal systems to better understand the value of commodity markets. They believe that by having access to over 15,000 industry-respected price assessments, they can make more informed decisions regarding their trading and investment strategies.\r\n\r\nQuestions/Issues:\r\n\r\nHow frequently are the Platts price assessments updated?\r\nCan the assessments be integrated seamlessly into ABC Energy Corp.'s existing systems?\r\nAre there any volume discounts available for large-scale integrations?",
    "Id" : "006J7000003d2pZIAQ",
    "IsClosed" : "false"
  }, {
    "StageName" : "Qualification",
    "Owner.Name" : "Saurabh Gupta",
    "Name" : "Supplier Risk Assessment for Global partners",
    "AccountId" : "001J700000CpUqBIAV",
    "CloseDate" : "2024-01-31 00:00:00",
    "Amount" : "317985.00",
    "Description" : "Gaslume is keen on using the Supplier Risk Indicator™ to assess and manage their supplier risks better. With suppliers spread across various continents, they want a comprehensive tool that can provide insights into potential risks. They have the following questions about the product:\r\nHow does the Supplier Risk Indicator™ gather and update data on suppliers?\r\nCan the tool integrate with their existing ERP system?\r\nHow does the tool handle sudden geopolitical changes that might affect supplier stability?\r\nIs there a feature to set up alerts for specific risk thresholds?",
    "Id" : "006J7000003d2pbIAA",
    "IsClosed" : "false"
  }, {
    "StageName" : "Needs Analysis",
    "Owner.Name" : "Saurabh Gupta",
    "Name" : "Solar/ESG - Custom Market Analysis Deal",
    "AccountId" : "001J700000CpUqBIAV",
    "CloseDate" : "2024-02-29 00:00:00",
    "Amount" : "500000.00",
    "Description" : "Gaslume's global commodities trading team is keen on diving deep into ESG and Carbon Credits for specific market supply and demand trends. They are interested in S&P's independent commodity market news and in-depth analysis to guide their trading decisions to align with their corporate sustainability and ESG goals.",
    "Id" : "006J7000003d2paIAA",
    "IsClosed" : "false"
  } ],
  "Object Name" : "Account",
  "Industry" : "Energy",
  "Description" : "Established in 2000, GasLume Energy is a pioneer in gas exploration and production, with 23 years in the market and annual revenues of $5.8 billion.",
  "Id" : "001J700000CpUqBIAV",
  "Name" : "GasLume Energy"
}

        // let result = await getAccountsByName({ accountName: accountName })
        // if(result){
        //     return result;
        // } else {
        //     return 'Record not found'
        // }         
        // return { 
        //     "accountDetails": {
        //         "name": accountName,
        //         "accountNumber": "1234567890",
        //         "accountType": "Savings",
        //         "accountOwner": "John Doe",
        //         "address": "ABC, 123",
        //         "city": "ABC City",
        //         "state": "ABC State",
        //         "postalCode": "ABC1234",
        //         "country": "ABC Country"
        //     }
        // }
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
        this.messages = [...this.messages, { id: Date.now(), role, text, messageClass, gptfy }];
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
}