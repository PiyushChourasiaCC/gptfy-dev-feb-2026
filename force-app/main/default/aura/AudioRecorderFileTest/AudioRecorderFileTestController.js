({
    //mediaRecorder,
	handleClick : function (cmp, event, helper) {
        navigator.mediaDevices.getUserMedia({ audio: true, video: false })
            .then(stream => {
                  this.mediaRecorder = new MediaRecorder(stream);
                  this.mediaRecorder.ondataavailable = (event) => {
                        this.audioChunks.push(event.data);
                    };
                    this.mediaRecorder.onstop = () => {
                        let audioBlob = new Blob(this.audioChunks, { type: 'audio/mp3' });
        				console.log(audioBlob);
                        this.mediaRecorder = null;
                    };
                    this.mediaRecorder.start();
    				cmp.set("v.mediaRecorder", this.mediaRecorder);
            })
    },
    handleStop : function (cmp, event, helper) {
        console.log(cmp.get("v.mediaRecorder"))
        cmp.get("v.mediaRecorder").stop();
        //this.mediaRecorder.stop();
    }
})