import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getCardConfiguration from '@salesforce/apex/AddCardController.getCardConfiguration';

export default class GptfyCardDetailComponent extends LightningElement {
    @api metadata;
    @api cardType;

    catalog = false;

    @track showSpinner = false;

    connectedCallback() {

        if (this.cardType == 'CTLOG') {
            this.catalog = true;
        } else {
            this.catalog = false;
        }
        this.doInit();
    }

    @api doInit() {
        this.showSpinner = true;
        getCardConfiguration({
            'feature': this.cardType
        }).then(result => {
            var options = JSON.parse(JSON.stringify(result));
            var i = 1;
            for (var opt of options) {
                opt['hasStaticResource'] = opt.mdtRecord.Icon_Source == 'Static Resource' ? true : false;
                i++;
            }
            this.metadata = JSON.parse(JSON.stringify(options));
            this.showSpinner = false;
        }).catch(error => {
            this.showSpinner = false;
            this.handleError(error);
        });
    }

    handleNavigate(event) {
        console.log('============================= handleNavigate : ');
        if (this.catalog) {
            const customEvent = new CustomEvent('navigate', {
                detail: { recid: event.target.dataset.name }
            });
            this.dispatchEvent(customEvent);
        }else{
            console.log('============================= event.target.dataset.id : '+event.target.dataset.id);
            console.log('============================= event.target.dataset.index : '+event.target.dataset.index);
            const customEvent = new CustomEvent('edit', {
                detail: { name: event.target.dataset.id, rec: this.metadata[event.target.dataset.index] }
            });
            this.dispatchEvent(customEvent);
        }
    }

    handleCreateYourOwn() {
        const selectedEvent = new CustomEvent("createown");
        this.dispatchEvent(selectedEvent);
    }

    handleEditCard(event) {
        event.stopPropagation();
        const customEvent = new CustomEvent('edit', {
            detail: { name: event.target.name }
        });
        this.dispatchEvent(customEvent);
    }

    handleError(error) {
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if (error && error.body && error.body.message) {
            this.showToast('error', 'Error', error.body.message);
        } else {
            this.showToast('error', 'Error', error.toString());
        }
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant: variant,
            message: message,
        });
        this.dispatchEvent(event);
    }
}