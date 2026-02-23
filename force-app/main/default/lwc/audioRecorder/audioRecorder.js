import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { createRecord } from 'lightning/uiRecordApi';
import createContentDocumentLink from '@salesforce/apex/AudioRecorderController.createContentDocumentLink';
import isUserAuthorized from '@salesforce/apex/AudioRecorderController.isUserAuthorized';
import getConfigurationDetails from '@salesforce/apex/AIVoiceConfigurationController.getConfigurationDetails';
import gptfylogo from '@salesforce/resourceUrl/gptfylogo';
import { fireEvent, registerListener } from 'c/aIPubSubUtil';
import { CurrentPageReference } from 'lightning/navigation';
const { userAgent } = navigator;

export default class AudioRecorder extends LightningElement {
    @api recordId;
    mediaRecorder;
    audioChunks = [];
    isRecording = false;
    visibleResumebtn = false;
    audioUrl;
    isliveRecording = false;
    isAudioReady = false;
    isSubmitProgress = false;
    @track showSpinner = false;
    @track timeVal = '0:00';
    timeIntervalInstance;
    totalMilliseconds = 0;
    timeLimit = 30000;
    gptfylogo = gptfylogo;
    visibleLWC = false;

    @wire(CurrentPageReference) pageRef;

    get isVisiblePauseBtn(){
        return this.isRecording && !this.visibleResumebtn && !this.isAudioReady
    }

    get isVisibleResumeBtn(){
        return this.isRecording && this.visibleResumebtn && !this.isAudioReady
    }

    get isVisibleStopBtn(){
        return this.isRecording && !this.isAudioReady
    }

    connectedCallback(){

        isUserAuthorized().then((result)=> {
            if(result){
                this.visibleLWC = true;
                registerListener("mediadeviceEvent", this.startRecordingHandler, this);

                getConfigurationDetails()
                        .then(result => {
                            if(result){
                                let voiceConfig = JSON.parse(JSON.stringify(result));
                                if(voiceConfig && voiceConfig.duration && voiceConfig.duration != 0){
                                    let minutes = voiceConfig.duration;
                                    let seconds = minutes * 60;
                                    let totalmillisecondstemp = seconds * 1000;
                                    this.timeLimit = totalmillisecondstemp;
                                }
                                
                            }
                        })
                        .catch(error => {
                            this.handleError(error);
                        });
            }else{
                this.visibleLWC = false;
            }
        })
       
    }

    get isIOS() {
        return userAgent.match(/iPhone|iPad|iPod/i) != null;
    }

    get isAndroid() {
        return userAgent.match(/Android/i) != null;
    }

    get isWindows() {
        return userAgent.match(/Windows/i) != null;
    }
    
    get isMac() {
        return userAgent.match(/Mac/i) != null && !this.isIOS && !this.isChrome;
    }

    get isChrome() {
        return userAgent.match(/Chrome/i) != null;
    }
    

     startTimer (){

        var parentThis = this;

        this.timeIntervalInstance = setInterval(async function() {
            if(parentThis.totalMilliseconds >= parentThis.timeLimit){
                await parentThis.stopRecording();
                clearInterval(this.timeIntervalInstance);
            }else 
            {
                var minutes = Math.floor(parentThis.totalMilliseconds / (1000 * 60));

                    var seconds = Math.floor(parentThis.totalMilliseconds % (1000 * 60) / 1000);

                    parentThis.timeVal = minutes + ":"+ (seconds < 10 ? "0" : "") + seconds; 

                    parentThis.totalMilliseconds += 500; 
            }
        
        }, 500);

    }

    stopTimer() {
        clearInterval(this.timeIntervalInstance);
    }

    resetTimer() {
        this.timeVal = '0:00';
        this.totalMilliseconds = 0;
        clearInterval(this.timeIntervalInstance);
    }

    startRecordingHandler(mediaData){
        this.mediaRecorder = mediaData;
        this.mediaRecorder.ondataavailable = (event) => {
            this.audioChunks.push(event.data);
        };
        this.mediaRecorder.onstop = () => {
            this.audioBlob = new Blob(this.audioChunks, { type: 'audio/mp3' });
            this.audioUrl = URL.createObjectURL(this.audioBlob);
            this.isAudioReady = true;
            this.mediaRecorder = null;
        };
        this.mediaRecorder.start();
        this.isRecording = true;
        this.visibleResumebtn = false;
        this.isliveRecording = true;
        this.isAudioReady = false;
        this.startTimer();
    }

    startRecording() {
        if(navigator && navigator.mediaDevices){
            navigator.mediaDevices.getUserMedia({ audio: true, video: false })
            .then(stream => {
                this.mediaRecorder = new MediaRecorder(stream);
                this.mediaRecorder.ondataavailable = (event) => {
                    this.audioChunks.push(event.data);
                };
                this.mediaRecorder.onstop = () => {
                    this.audioBlob = new Blob(this.audioChunks, { type: 'audio/mp3' });
                    this.audioUrl = URL.createObjectURL(this.audioBlob);
                    this.isAudioReady = true;
                    this.mediaRecorder = null;
                };
                this.mediaRecorder.start();
                this.isRecording = true;
                this.visibleResumebtn = false;
                this.isliveRecording = true;
                this.isAudioReady = false;
                this.startTimer()
            })
            .catch(error => {
                this.handleError(error);
            });
        }else{
            fireEvent(this.pageRef ,'startRecording', {});
        }
    }

    stopRecording() {
       // this.stopTimer();
        if (this.mediaRecorder && this.isRecording) {
            this.mediaRecorder.stop();
            this.isliveRecording = false;
            this.isAudioReady = false;
           // this.isRecording = false
        }
    }

    handleSubmit () {
        if(this.isAudioReady && this.audioUrl && this.audioChunks && this.audioChunks.length > 0) {
            this.isSubmitProgress = true;
            this.saveAudioFile(this.audioBlob);
        }else{
            this.handleError('No file found to submit.');
        }
        this.resetTimer();
    }

    pauseRecording() {
        
        if (this.mediaRecorder && this.isRecording) {
            if (this.mediaRecorder.state === "recording") {
                this.stopTimer();
                this.mediaRecorder.pause();
                this.visibleResumebtn = true;
                this.isliveRecording = false;
              } else if (this.mediaRecorder.state === "paused") {
                this.startTimer();
                this.mediaRecorder.resume();
                this.visibleResumebtn = false;
                this.isliveRecording = true;
              }
        }
        
    }

    clearRecording() {
        this.mediaRecorder = null;
            this.isRecording = false;
            this.visibleResumebtn = false;
            this.isliveRecording = false;
            this.isAudioReady = false;
            this.audioChunks = []
            this.audioUrl = null
            this.resetTimer();
    }

    saveAudioFile(audioBlob) {
        const reader = new FileReader();
        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            this.createContentVersion(base64);
        };
        reader.readAsDataURL(audioBlob);
    }

    createContentVersion(base64) {
        const fields = {
            Title: `Audio Recording ${new Date().toISOString()}`,
            PathOnClient: 'audio_recording.mp3',
            VersionData: base64,
            IsMajorVersion : false
        };
        createRecord({ apiName: 'ContentVersion', fields })
        .then(result => {
            this.linkContentDocumentToRecord(result.id);
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    linkContentDocumentToRecord(contentVersionId) {
        createContentDocumentLink({
            "cdId" : contentVersionId,
            "recordId" : this.recordId,
            "isIOS": (this.isIOS || this.isMac)
        })
        .then(result => {
            this.showSpinner = false;
            this.showToast('success', 'Success', 'Heard you! GPTfy is turning it into digital gold. Notification on its way!');
            this.isSubmitProgress = false;
            this.isRecording = false;
            this.visibleResumebtn = false;
            this.isliveRecording = false;
            this.isAudioReady = false;
            this.audioUrl = null;
            this.audioChunks = []
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    get recordButtonLabel() {
        return 'Voice';
    }

    get recordButtonIcon() {
        return this.isRecording ? 'utility:stop' : 'utility:play';
    }
    
    handleRecordClick() {
      //  if (this.isRecording) {
       //     this.showSpinner = true;
       //     this.stopRecording();
       // } else {
            this.startRecording();
       // }
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    handleError(error){
        this.showSpinner = false;
        this.isSubmitProgress = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
             if(error.body.message && (error.body.message.includes('You do not have access to the Apex class') || error.body.message.includes('AudioRecorderController') || error.body.message.includes('AIVoiceConfigurationController'))){
                //do-nothing
            }else{
                this.showToast('error', 'Error.', error.body.message);
            }
        }else if(error && error.body && error.body.error && error.body.error.includes('Received exception event aura:systemError from server')){
            this.showToast('error', 'Error.', error.body.error);
        }else{
            this.showToast('error', 'Error.', error.toString());
        }
    }

  
}