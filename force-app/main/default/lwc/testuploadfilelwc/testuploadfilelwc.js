import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
//import callOpenAI from '@salesforce/apex/OpenAIServiceTestVoice.callOpenAI';
import { loadScript } from 'lightning/platformResourceLoader';
import rtlib from '@salesforce/resourceUrl/rtlib';

export default class Testuploadfilelwc extends LightningElement {
    @track messages = [];
    @track isRecording = false;
    @track isSpeakerOn = true;
    @track visualizerBars = Array(20).fill(0);
    
    recognition = null;
    audioContext = null;
    mediaStream = null;
    audioAnalyser = null;
    speechSynthesis = window.speechSynthesis;
    
    get microphoneIcon() {
        return this.isRecording ? 'utility:stop' : 'utility:voice';
    }
    
    get speakerIcon() {
        return this.isSpeakerOn ? 'utility:volume_high' : 'utility:volume_off';
    }
    
    get micButtonClass() {
        return `mic-button ${this.isRecording ? 'recording' : ''}`;
    }
    
    connectedCallback() {
        //this.initializeSpeechRecognition();
       // this.initializeAudioContext();

       Promise.all([
        loadScript(this, `${rtlib}/index.js`), // Main script
         loadScript(this, `${rtlib}/models.js`), // Utility script
         loadScript(this, `${rtlib}/client.js`), // Helper script
        // loadScript(this, `${rtlib}/model-utils.js`), // Helper script
        // loadScript(this, `${rtlib}/util/auth.js`), // Helper script
        // loadScript(this, `${rtlib}/util/connection-settings-browser.js`), // Helper script
        // loadScript(this, `${rtlib}/util/connection-settings.js`), // Helper script
        // loadScript(this, `${rtlib}/util/crypto.js`), // Helper script
        // loadScript(this, `${rtlib}/util/interfaces.js`), // Helper script
        // loadScript(this, `${rtlib}/util/message_queue.js`), // Helper script
        // loadScript(this, `${rtlib}/util/websocket-client.js`), // Helper script
        // loadScript(this, `${rtlib}/util/websocket-browser.js`), // Helper script
        // loadScript(this, `${rtlib}/util/websocket.js`), // Helper script
    ])
        .then(() => {
          console.log('Library loaded successfully');
          
        })
        .catch(error => {
          console.error('Error loading library', error);
        });
    }
    
    disconnectedCallback() {
        // this.stopRecording();
        // if (this.mediaStream) {
        //     this.mediaStream.getTracks().forEach(track => track.stop());
        // }
    }
    
    initializeSpeechRecognition() {
        if ('webkitSpeechRecognition' in window) {
            this.recognition = new webkitSpeechRecognition();
            this.recognition.continuous = false;
            this.recognition.interimResults = true;
            
            this.recognition.onresult = (event) => {
                const transcript = event.results[0][0].transcript;
                if (event.results[0].isFinal) {
                    this.handleVoiceInput(transcript);
                }
            };
            
            this.recognition.onerror = (event) => {
                console.error('Speech recognition error:', event.error);
                this.showToast('Error', 'Speech recognition failed', 'error');
                this.stopRecording();
            };
        }
    }
    
    async initializeAudioContext() {
        try {
            // Check if the browser supports required APIs
            if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
                throw new Error('Browser does not support media devices');
            }

            // Initialize audio context with fallback
            this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            
            // Request microphone access
            try {
                this.mediaStream = await navigator.mediaDevices.getUserMedia({ 
                    audio: true,
                    video: false
                });
            } catch (mediaError) {
                if (mediaError.name === 'NotAllowedError') {
                    throw new Error('Microphone permission denied');
                } else {
                    throw new Error(`Microphone access error: ${mediaError.message}`);
                }
            }

            const source = this.audioContext.createMediaStreamSource(this.mediaStream);
            this.audioAnalyser = this.audioContext.createAnalyser();
            source.connect(this.audioAnalyser);
            
            this.audioAnalyser.fftSize = 64;
            const bufferLength = this.audioAnalyser.frequencyBinCount;
            const dataArray = new Uint8Array(bufferLength);
            
            const updateVisualizer = () => {
                if (this.isRecording) {
                    this.audioAnalyser.getByteFrequencyData(dataArray);
                    this.visualizerBars = Array.from(dataArray).map(value => 
                        `height: ${value/2}px`
                    );
                    requestAnimationFrame(updateVisualizer);
                }
            };
            
            updateVisualizer();
        } catch (error) {
            console.error('Audio initialization error:', error);
            this.showToast('Error', 'Microphone access denied', 'error');
        }
    }
    
    toggleRecording() {
        if (this.isRecording) {
            this.stopRecording();
        } else {
            this.startRecording();
        }
    }
    
    startRecording() {
        if (this.recognition) {
            this.isRecording = true;
            this.recognition.start();
        }
    }
    
    stopRecording() {
        if (this.recognition) {
            this.isRecording = false;
            this.recognition.stop();
        }
    }
    
    toggleSpeaker() {
        this.isSpeakerOn = !this.isSpeakerOn;
        if (this.speechSynthesis.speaking) {
            this.speechSynthesis.cancel();
        }
    }
    
    async handleVoiceInput(transcript) {
        this.addMessage(transcript, 'user');
        
        try {
            const response = await callOpenAI({ message: transcript });
            this.addMessage(response, 'assistant');
            
            if (this.isSpeakerOn) {
                this.speakResponse(response);
            }
        } catch (error) {
            console.error('OpenAI API error:', error);
            this.showToast('Error', 'Failed to process your request', 'error');
        }
    }
    
    addMessage(content, sender) {
        this.messages.push({
            id: Date.now(),
            content,
            messageClass: `message ${sender}-message`
        });
    }
    
    speakResponse(text) {
        const utterance = new SpeechSynthesisUtterance(text);
        utterance.rate = 1.0;
        utterance.pitch = 1.0;
        this.speechSynthesis.speak(utterance);
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}