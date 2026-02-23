import { LightningElement, track } from "lwc";
import validateLicenseKey from "@salesforce/apex/AILicenseManagerController.validateLicenseKey";
import getLicenses from "@salesforce/apex/AILicenseManagerController.getLicenses";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from '@salesforce/apex';

export default class AILicenseManagerComponent extends LightningElement {
	columns = [
		{ label: 'License Id', fieldName: 'uniqueId', hideDefaultActions: true },
		{ label: 'Type', fieldName: 'licenseType', hideDefaultActions: true},
		{ label: 'Start Date', fieldName: 'startDate', type: 'date', hideDefaultActions: true },
		{ label: 'End Date', fieldName: 'endDate', type: 'date', hideDefaultActions: true },
		{ label: 'Status', fieldName: 'status', hideDefaultActions: true },
		{ label: 'Usage Limit', fieldName: 'usageLimit', type: 'Integer', hideDefaultActions: true }
	];
	@track licenses = [];

	validateActivationKey(){
		var actKey = this.template.querySelector('.actKey').value;
		if(actKey && actKey != null && actKey.trim()!=''){
			this.validateKey(actKey);
		}else{
			this.showToast("Error!","Please Enter a valid Licence Key","error","dismissable");
		}
	}

	validateKey(actKey){
		let reqMap = {
			"licenseKey": actKey
		};
		validateLicenseKey({dataMap : reqMap})
		.then(result => {
			if(result && result.length > 0){
				this.showToast("Error!", result, "error", "dismissable");
			}else{
				this.showToast("Success!",'License Key successfully Applied.',"success","dismissable");
				this.template.querySelector('.actKey').value = '';
				var i = 0;
				var temp = this;
				var myVar = setInterval(function () {
					i++;
					if(i < 3){
						temp.doInit();
					}else{
						clearInterval(myVar);
					}
				}, 1500);
			}
		})
		.catch(error => {
			this.handleError(error);
		})
	}

	connectedCallback() {
		this.doInit();
	}

	doInit() {
		getLicenses()
		.then(result => {
			this.licenses = result;
			return refreshApex(result);
		})
		.catch(error => {
			this.handleError(error);
		});
	}

	showToast(title, message, variant, mode) {
		const evt = new ShowToastEvent({
			title: title,
			message: message,
			variant: variant,
			mode: mode
		});
		this.dispatchEvent(evt);
	}

	handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error', error.body.message);
        }else{
            this.showToast('error', 'Error', error.toString());
        }
    }

}