({
	handleReceiveMessage : function(component, event, helper) {
        var pubsubutil = component.find('util');
        var callback = $A.getCallback(function (data) {
             //const pageRef = component.get("v.pageReference");
             navigator.mediaDevices.getUserMedia({ audio: true, video: false })
            .then(stream => {
                  const mediaRecorder = new MediaRecorder(stream);
                	console.log(mediaRecorder);
                  pubsubutil.fireEvent('mediadeviceEvent', mediaRecorder);
            }).catch(error => {
                console.log('error');
            })
         });
         pubsubutil.registerListener('startRecording', callback);
	}
})