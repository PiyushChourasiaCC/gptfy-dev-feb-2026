import { LightningElement, track } from 'lwc';

export default class RealTimeAudioChat extends LightningElement {
    @track isListening = false;
    @track conversationContext = [];
    @track transcribedText = '';
    
    audioContext;
    mediaStreamSource;
    processor;
    stream;
    audioBuffer = [];
    silenceThreshold = 0.01;
    silenceTime = 0;
    lastAudioTime = Date.now();

    // Azure OpenAI Configuration
    AZURE_ENDPOINT = 'saura-m51w47qu-eastus2.cognitiveservices.azure.com';
    API_KEY = '9FzRxq2nMHNzlduqmGEozrwJ5o9Ittb57A0SGOPTzwVvS7Otjb6NJQQJ99ALACHYHv6XJ3w3AAAAACOGIjot';
    DEPLOYMENT_NAME = 'gpt-4o-realtime-preview';
    API_VERSION = '2024-02-15-preview';

    get buttonLabel() {
        return this.isListening ? 'Stop Listening' : 'Start Listening';
    }

    async toggleListening() {
        if (this.isListening) {
            await this.stopListening();
        } else {
            await this.startListening();
        }
    }

    async startListening() {
        try {
            this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            this.audioContext = new AudioContext();
            this.mediaStreamSource = this.audioContext.createMediaStreamSource(this.stream);
            
            this.processor = this.audioContext.createScriptProcessor(4096, 1, 1);
            this.mediaStreamSource.connect(this.processor);
            this.processor.connect(this.audioContext.destination);

            this.processor.onaudioprocess = async (e) => {
                const audioData = e.inputBuffer.getChannelData(0);
                await this.processAudioChunk(audioData);
            };

            this.isListening = true;
        } catch (error) {
            console.error('Error starting audio:', error);
            this.showToast('Error', 'Failed to start audio recording', 'error');
        }
    }

    async stopListening() {
        try {
            if (this.processor) {
                this.processor.disconnect();
                this.processor = null;
            }
            if (this.mediaStreamSource) {
                this.mediaStreamSource.disconnect();
                this.mediaStreamSource = null;
            }
            if (this.audioContext) {
                await this.audioContext.close();
                this.audioContext = null;
            }
            if (this.stream) {
                this.stream.getTracks().forEach(track => track.stop());
                this.stream = null;
            }
            
            this.isListening = false;
        } catch (error) {
            console.error('Error stopping audio:', error);
        }
    }

    async processAudioChunk(audioData) {
        const isCurrentlySilent = this.isSilent(audioData);
        const currentTime = Date.now();
        
        if (isCurrentlySilent) {
            this.silenceTime += currentTime - this.lastAudioTime;
            
            if (this.silenceTime > 1000 && this.audioBuffer.length > 0) {
                const audioBlob = this.createAudioBlob(this.audioBuffer);
                this.audioBuffer = [];
                await this.handleSpeechToText(audioBlob);
                this.silenceTime = 0;
            }
        } else {
            this.silenceTime = 0;
            this.audioBuffer.push(new Float32Array(audioData));
        }
        
        this.lastAudioTime = currentTime;
    }

    async handleSpeechToText(audioBlob) {
        try {
            const formData = new FormData();
            formData.append('file', audioBlob, 'audio.wav');
            formData.append('model', 'whisper-1');

            const response = await fetch(`${this.AZURE_ENDPOINT}/openai/audio/transcriptions?api-version=${this.API_VERSION}`, {
                method: 'POST',
                headers: {
                    'api-key': this.API_KEY
                },
                body: formData
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const data = await response.json();
            if (data.text) {
                this.transcribedText = data.text;
                await this.getChatCompletion(data.text);
            }
        } catch (error) {
            console.error('Speech to text error:', error);
        }
    }

    async getChatCompletion(userInput) {
        try {
            // Add user message to context
            this.conversationContext.push({
                role: 'user',
                content: userInput
            });

            const response = await fetch(`${this.AZURE_ENDPOINT}/openai/deployments/${this.DEPLOYMENT_NAME}/chat/completions?api-version=${this.API_VERSION}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'api-key': this.API_KEY
                },
                body: JSON.stringify({
                    messages: this.conversationContext,
                    max_tokens: 150,
                    temperature: 0.7,
                    stream: true
                })
            });

            // Handle streaming response
            const reader = response.body.getReader();
            let assistantResponse = '';

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                // Process the streaming chunks
                const chunk = new TextDecoder().decode(value);
                const lines = chunk.split('\n');
                
                for (const line of lines) {
                    if (line.startsWith('data: ')) {
                        const jsonString = line.slice(6);
                        if (jsonString === '[DONE]') continue;
                        
                        try {
                            const jsonResponse = JSON.parse(jsonString);
                            if (jsonResponse.choices[0].delta.content) {
                                assistantResponse += jsonResponse.choices[0].delta.content;
                                // Update UI with partial response
                                this.updateAssistantResponse(assistantResponse);
                            }
                        } catch (e) {
                            console.error('Error parsing JSON:', e);
                        }
                    }
                }
            }

            // Add final assistant response to context
            this.conversationContext.push({
                role: 'assistant',
                content: assistantResponse
            });

            // Convert response to speech
            await this.textToSpeech(assistantResponse);

        } catch (error) {
            console.error('Chat completion error:', error);
        }
    }

    async textToSpeech(text) {
        try {
            const response = await fetch(`${this.AZURE_ENDPOINT}/openai/audio/speech?api-version=${this.API_VERSION}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'api-key': this.API_KEY
                },
                body: JSON.stringify({
                    input: text,
                    voice: 'alloy',
                    model: 'tts-1'
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const audioBlob = await response.blob();
            const audioUrl = URL.createObjectURL(audioBlob);
            const audio = new Audio(audioUrl);
            await audio.play();

        } catch (error) {
            console.error('Text to speech error:', error);
        }
    }

    // Helper methods
    isSilent(audioData) {
        const sum = audioData.reduce((acc, val) => acc + Math.abs(val), 0);
        const average = sum / audioData.length;
        return average < this.silenceThreshold;
    }

    createAudioBlob(audioBuffer) {
        const combinedBuffer = new Float32Array(
            audioBuffer.reduce((acc, curr) => acc + curr.length, 0)
        );
        
        let offset = 0;
        audioBuffer.forEach(buffer => {
            combinedBuffer.set(buffer, offset);
            offset += buffer.length;
        });

        return new Blob([this.createWAV(combinedBuffer)], { type: 'audio/wav' });
    }

    createWAV(audioData) {
        const numChannels = 1;
        const sampleRate = this.audioContext.sampleRate;
        const bytesPerSample = 2;
        const blockAlign = numChannels * bytesPerSample;
        const byteRate = sampleRate * blockAlign;
        const dataSize = audioData.length * bytesPerSample;
        const buffer = new ArrayBuffer(44 + dataSize);
        const view = new DataView(buffer);
    
        // WAV Header (44 bytes)
        // "RIFF" chunk descriptor
        this.writeString(view, 0, 'RIFF');                     // ChunkID
        view.setUint32(4, 36 + dataSize, true);               // ChunkSize
        this.writeString(view, 8, 'WAVE');                     // Format
    
        // "fmt " sub-chunk
        this.writeString(view, 12, 'fmt ');                    // Subchunk1ID
        view.setUint32(16, 16, true);                         // Subchunk1Size (16 for PCM)
        view.setUint16(20, 1, true);                          // AudioFormat (1 for PCM)
        view.setUint16(22, numChannels, true);                // NumChannels
        view.setUint32(24, sampleRate, true);                 // SampleRate
        view.setUint32(28, byteRate, true);                   // ByteRate
        view.setUint16(32, blockAlign, true);                 // BlockAlign
        view.setUint16(34, bytesPerSample * 8, true);         // BitsPerSample
    
        // "data" sub-chunk
        this.writeString(view, 36, 'data');                   // Subchunk2ID
        view.setUint32(40, dataSize, true);                   // Subchunk2Size
    
        // Write audio data
        const length = audioData.length;
        let index = 44;
        for (let i = 0; i < length; i++) {
            // Convert Float32 audio data to 16-bit PCM
            view.setInt16(index, audioData[i] * 0x7FFF, true);
            index += 2;
        }
    
        return buffer;
    }
    
    writeString(view, offset, string) {
        for (let i = 0; i < string.length; i++) {
            view.setUint8(offset + i, string.charCodeAt(i));
        }
    }

    updateAssistantResponse(text) {
        const responseDiv = this.template.querySelector('.assistant-response');
        if (responseDiv) {
            responseDiv.textContent = text;
        }
    }

    clearContext() {
        this.conversationContext = [];
        this.transcribedText = '';
        if (this.isListening) {
            this.stopListening();
        }
    }

    disconnectedCallback() {
        if (this.isListening) {
            this.stopListening();
        }
    }
}