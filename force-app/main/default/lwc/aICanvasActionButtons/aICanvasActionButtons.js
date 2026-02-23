import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { NavigationMixin } from 'lightning/navigation';

export default class AICanvasActionButtons extends NavigationMixin(LightningElement) {
    @api recordId;
    @api settings;
    @api bodyContent;
    @api emailActionName
    @api userSignature;
    @api namespace = '';

    handleEmail() {
        var emailBody = this.bodyContent;
        if(this.userSignature && this.userSignature != null && this.userSignature != ''){
            var userSign = this.userSignature;
            userSign = userSign.replace(/\n/g, '<br>');
            emailBody += '<br><br>'+userSign;
        }

        if(this.emailActionName){
            var pageRef = {
                type: "standard__quickAction",
                attributes: {
                    apiName: this.emailActionName
                },
                state: {
                    recordId: this.recordId,
                    defaultFieldValues:
                    encodeDefaultFieldValues({
                        HtmlBody : emailBody
                    })
                }
            };
            this[NavigationMixin.Navigate](pageRef);
        }
    }
    
    handleCopy(){
        let result = this.bodyContent;
        if(this.isJSONString(result)){
            result = this.convertNestedJSONToReadableFormatInText(JSON.parse(result));
        }
        let regexHtmlTags = /<([A-Za-z][A-Za-z0-9]*)\b[^>]*>(.*?)<\/\1>/

        const listener = function(ev) {
            ev.preventDefault();
            if(regexHtmlTags.test(result)){
                ev.clipboardData.setData('text/html', result);
            }else{
                ev.clipboardData.setData('text/plain', result);
            }
        };
        document.addEventListener('copy', listener);
        document.execCommand('copy');
        document.removeEventListener('copy', listener);
        this.showToast('Success', 'Content Copied!', 'success');
    }
    
    handleRefresh(){
        this.dispatchEvent(new CustomEvent('refresh'));
    }
    handleZoomOut(){
        this.dispatchEvent(new CustomEvent('zoomout'));
    }
    isJSONString(str){
        try {
          JSON.parse(str);
        } catch (e) {
          return false;
        }
        return true;
    }

    convertNestedJSONToReadableFormat(jsonObj, indent = 0) {
        let result = '';
        for(let property in jsonObj){
            if(jsonObj.hasOwnProperty(property)){
                if(typeof jsonObj[property] === 'object'){
                    var resp = this.convertNestedJSONToReadableFormat(jsonObj[property], indent + 1);
                    if(resp && resp != null && resp != ''){
                        result += resp;
                    }
                }else{
                    result += '<b style="color:gray">'+property+':</b> ';
                    result += jsonObj[property]+'<br>';
                }
            }
        }
        return result;
    }
    
    convertNestedJSONToReadableFormatInText(jsonObj, indent = 0) {
        let result = '';
        for(let property in jsonObj){
            if(jsonObj.hasOwnProperty(property)){
                if(typeof jsonObj[property] === 'object'){
                    var resp = this.convertNestedJSONToReadableFormat(jsonObj[property], indent + 1);
                    if(resp && resp != null && resp != ''){
                        result += resp;
                    }
                }else{
                    result += ''+property+': ';
                    result += jsonObj[property]+'\n';
                }
            }
        }
        return result;
    }
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
    handlePreviewAndDownload(){
        sessionStorage.setItem('responseData',  this.bodyContent);
        let url = '/' + (!this.namespace ? 'c' : this.namespace.replaceAll('__','')) + '/AIResponseViewer.app';
        window.open(url, '_blank');
    }
}