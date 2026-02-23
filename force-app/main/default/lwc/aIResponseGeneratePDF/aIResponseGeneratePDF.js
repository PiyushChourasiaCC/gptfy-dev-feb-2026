import { LightningElement, track } from 'lwc';

export default class AIResponseGeneratePDF extends LightningElement {
    @track responseData;
    connectedCallback(){
        this.responseData = sessionStorage.getItem('responseData');
    }
    reviewAndDownload(){
        alert("To ensure all colors and formatting appear correctly, please check your print settings and enable options for printing background colors, images, or graphics before printing.");
        window.print();
    }
}