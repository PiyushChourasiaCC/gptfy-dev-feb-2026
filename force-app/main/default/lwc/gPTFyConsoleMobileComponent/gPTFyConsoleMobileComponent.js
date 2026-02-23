import { LightningElement, api, track } from 'lwc';

export default class GPTFyConsoleMobileComponent extends LightningElement {
    @api recordId;

    @track mobileView = false;
    connectedCallback(){
        if(window.innerWidth < 480){
            this.mobileView = true;
        }
    }
}