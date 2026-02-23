import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class AICustomDatatableNavigation extends NavigationMixin(LightningElement) {
    @api recordId;
    @api label;
    @api value;
    
    isEdit = false;

     navigateToRecordViewPage = () => {
        window.open('/'+this.recordId, '_blank');
    }

    handleEdit(){
        this.isEdit = true;
    }

    handleCloseInput(event){
        this.isEdit = false;
    }

    handleChange(event){
        this.value = event.detail.value;
        this.dispatchEvent(new CustomEvent('navigationchanged', {
            composed: true,
            bubbles: true,
            cancelable: true,
            detail: {
                data: { pmtId: this.recordId, name: this.value }
            }
        }));

    }

    renderedCallback(){
        let fieldToFocus = this.template.querySelector(".navfield");
        if(fieldToFocus){
            fieldToFocus.focus();
        }
    }

}