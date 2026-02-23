import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getLicensesForCheck from "@salesforce/apex/AILicenseManagerController.getLicensesForCheck";
import getSchedulingInformation from '@salesforce/apex/AISchedulerOverrideController.getSchedulingInformation';
import saveSchedulingInformation from '@salesforce/apex/AISchedulerOverrideController.saveSchedulingInformation';

import LICENSES_PRO_PLAN from '@salesforce/label/c.LICENSES_PRO_PLAN';
import LICENSES_ENTERPRISE_PLAN from '@salesforce/label/c.LICENSES_ENTERPRISE_PLAN';

export default class AISchedulerOverrideComponent extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    @track showSpinner = true;

    @track scheduleOptions = [
        {"label" : "Hourly", "value" : "Hourly"},
        {"label" : "Daily", "value" : "Daily"},
        {"label" : "Weekly", "value" : "Weekly"},
        {"label" : "Monthly", "value" : "Monthly"},
        {"label" : "Custom", "value" : "Custom"},
    ];

    @track weekdaysOptions = [
        {"label" : "Sunday", "value" : "Sunday"},
        {"label" : "Monday", "value" : "Monday"},
        {"label" : "Tuesday", "value" : "Tuesday"},
        {"label" : "Wednesday", "value" : "Wednesday"},
        {"label" : "Thursday", "value" : "Thursday"},
        {"label" : "Friday", "value" : "Friday"},
        {"label" : "Saturday", "value" : "Saturday"}
    ];

    @track monthDaysOptions = [
        {"label" : "1", "value" : "1"}, {"label" : "2", "value" : "2"}, {"label" : "3", "value" : "3"}, {"label" : "4", "value" : "4"}, {"label" : "5", "value" : "5"},
        {"label" : "6", "value" : "6"}, {"label" : "7", "value" : "7"}, {"label" : "8", "value" : "8"}, {"label" : "9", "value" : "9"}, {"label" : "10", "value" : "10"},
        {"label" : "11", "value" : "11"}, {"label" : "12", "value" : "12"}, {"label" : "13", "value" : "13"}, {"label" : "14", "value" : "14"}, {"label" : "15", "value" : "15"},
        {"label" : "16", "value" : "16"}, {"label" : "17", "value" : "17"}, {"label" : "18", "value" : "18"}, {"label" : "19", "value" : "19"}, {"label" : "20", "value" : "20"},
        {"label" : "21", "value" : "21"}, {"label" : "22", "value" : "22"}, {"label" : "23", "value" : "23"}, {"label" : "24", "value" : "24"}, {"label" : "25", "value" : "25"},
        {"label" : "26", "value" : "26"}, {"label" : "27", "value" : "27"}, {"label" : "28", "value" : "28"}, {"label" : "29", "value" : "29"}, {"label" : "30", "value" : "30"},
        {"label" : "31", "value" : "31"}
    ];

    @track hoursOptions = [
        {"label" : "0", "value" : "0"}, {"label" : "1", "value" : "1"}, {"label" : "2", "value" : "2"}, {"label" : "3", "value" : "3"}, {"label" : "4", "value" : "4"}, {"label" : "5", "value" : "5"},
        {"label" : "6", "value" : "6"}, {"label" : "7", "value" : "7"}, {"label" : "8", "value" : "8"}, {"label" : "9", "value" : "9"}, {"label" : "10", "value" : "10"},
        {"label" : "11", "value" : "11"}, {"label" : "12", "value" : "12"}, {"label" : "13", "value" : "13"}, {"label" : "14", "value" : "14"}, {"label" : "15", "value" : "15"},
        {"label" : "16", "value" : "16"}, {"label" : "17", "value" : "17"}, {"label" : "18", "value" : "18"}, {"label" : "19", "value" : "19"}, {"label" : "20", "value" : "20"},
        {"label" : "21", "value" : "21"}, {"label" : "22", "value" : "22"}, {"label" : "23", "value" : "23"}
    ];

    @track schedulerName = '';
    @track selectedScheduleOption = 'Daily';
    @track showWeekdaysOptions = false;
    @track showMonthsDaysOptions = false;
    @track showHoursOptions = false;
    @track showCustom = false;

    @track scheduleTime;
    @track cronExp;
    @track selectedSchedules = [];
    @track retryCount = 0;
    @track isDialogVisibile = false;

    connectedCallback(){
        getLicensesForCheck()
        .then(result => {
            var isLicensePresent = false
            if(result){
                if(result.licenseBypass){
                    isLicensePresent = true;
                }else{
                    if(result.licenses && result.licenses.length > 0){
                        result.licenses.forEach((item)=> {
                            if(item.status === 'Active'){
                                let licenseType = item.licenseType.toLowerCase()
                                if(licenseType === LICENSES_ENTERPRISE_PLAN.toLowerCase() || licenseType === LICENSES_PRO_PLAN.toLowerCase()){
                                    isLicensePresent = true;
                                }
                            }
                        })
                    }
                }
            }
            if(!isLicensePresent){
                this.showToast('warning', 'Alert.', 'This Feature is available in Paid Version.');
                this.navigateToListView()
            }else{
                this.isDialogVisibile = true;
                this.doInit();
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    doInit(){
        this.schedulerName = '';
        this.selectedScheduleOption = 'Daily';
        this.selectedSchedules = [];
        this.scheduleTime = undefined;
        this.cronExp = '';
        this.showWeekdaysOptions = false;
        this.showMonthsDaysOptions = false;
        this.showHoursOptions = false;
        this.showCustom = false;
        this.retryCount = 0;
        getSchedulingInformation({
            recordId : this.recordId
        })
        .then(result => {
            this.showSpinner = false;
            this.schedulerName = result.schedulerName;
            if(result.time){
                this.scheduleTime = result.time;
            }if(result.cronExp){
                this.cronExp = result.cronExp;
            }if(result.selectedScheduleOption){
                this.selectedScheduleOption = result.selectedScheduleOption;
            }if(result.scheduleDetail && result.scheduleDetail.length > 0){
                this.selectedSchedules = result.scheduleDetail;
            }if(result.retryCount && result.retryCount > 0){
                this.retryCount = result.retryCount;
            }

            if(this.selectedScheduleOption == 'Weekly'){
                this.showWeekdaysOptions = true;
            }else if(this.selectedScheduleOption == 'Monthly'){
                this.showMonthsDaysOptions = true;
            }else if(this.selectedScheduleOption == 'Hourly'){
                this.showHoursOptions = true;
            }else if(this.selectedScheduleOption == 'Custom'){
                this.showCustom = true;
            }
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleNameChange(event){
        this.schedulerName = event.target.value;
    }

    handleTimeChange(event){
        this.scheduleTime = event.target.value;
    }

    handleDaysOptionsChange(event){
        this.selectedSchedules = JSON.parse(JSON.stringify(event.target.value));
    }

    handleCronExpChange(event){
        this.cronExp = event.target.value;
    }

    handleRetryCountChange(event){
        this.retryCount = event.target.value;
    }

    handleSave(){
        if(!this.schedulerName || this.schedulerName == null || this.schedulerName == ''){
            this.showToast('error', 'Alert.', 'Scheduler Name is required.');
        }else if(!this.selectedScheduleOption || this.selectedScheduleOption == null || this.selectedScheduleOption == ''){
            this.showToast('error', 'Alert.', 'Scheduling Frequency is required.');
        }else if((this.selectedScheduleOption == 'Weekly' || this.selectedScheduleOption == 'Monthly' || this.selectedScheduleOption == 'Daily') && (!this.scheduleTime || this.scheduleTime == null || this.scheduleTime == '')){
            this.showToast('error', 'Alert.', 'Schedule Time is required.');
        }else if((this.selectedScheduleOption == 'Weekly' || this.selectedScheduleOption == 'Monthly') && (!this.selectedSchedules || this.selectedSchedules.length == 0)){
            this.showToast('error', 'Alert.', 'Weekdays/Days is required.');
        }else if((this.selectedScheduleOption == 'Hourly') && (!this.selectedSchedules || this.selectedSchedules.length == 0)){
            this.showToast('error', 'Alert.', 'Hours is required.');
        }else if((this.selectedScheduleOption == 'Custom') && (!this.cronExp || this.cronExp == null || this.cronExp == '')){
            this.showToast('error', 'Alert.', 'Cron Expression is required.');
        }else{
            this.updateSchedule();
        }
    }

    updateSchedule(){
        this.showSpinner = true;
        saveSchedulingInformation({
            recordId : this.recordId,
            schedulerName : this.schedulerName,
            schedularType : this.selectedScheduleOption,
            schedularTime : this.scheduleTime,
            schedulerDetail : this.selectedSchedules,
            cronExp : this.cronExp,
            retryCount : (this.retryCount != null && this.retryCount > 0 ? this.retryCount : 0)
        })
        .then(result => {
            this.showToast('success', 'Success!', 'Record saved successfully.');
            this.handleCancel();
        })
        .catch(error => {
            this.handleError(error);
        });
    }

    handleScheduleOptionChange(event){
        this.selectedSchedules = [];
        this.showWeekdaysOptions = false;
        this.showMonthsDaysOptions = false;
        this.showHoursOptions = false;
        this.showCustom = false;
        this.selectedScheduleOption = 'Daily';
        this.cronExp = '';
        this.scheduleTime = undefined;
        if(event.target.value){
            this.selectedScheduleOption = event.target.value;
        }
        if(this.selectedScheduleOption == 'Weekly'){
            this.showWeekdaysOptions = true;
        }else if(this.selectedScheduleOption == 'Monthly'){
            this.showMonthsDaysOptions = true;
        }else if(this.selectedScheduleOption == 'Hourly'){
            this.showHoursOptions = true;
        }else if(this.selectedScheduleOption == 'Custom'){
            this.showCustom = true;
        }
    }

    handleError(error){
        this.showSpinner = false;
        console.log(JSON.stringify(error));
        if(error && error.body && error.body.message){
            this.showToast('error', 'Error.', error.body.message);
        }else{
            this.showToast('error', 'Error.', error.toString());
        }
        this.closeQuickAction();
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant : variant,
            message: message,
        });
        this.dispatchEvent(event);
    }

    handleCancel(){
        if(this.recordId){
            this.naviagteToRecordPage();
        }else{
            this.navigateToListView();
        }
    }

    naviagteToRecordPage(){
        const value = this.recordId;
        const selectedEvent = new CustomEvent("cancel", {
             detail: { value }
        });
        this.dispatchEvent(selectedEvent);
    }

    navigateToListView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: this.objectApiName,
                actionName: 'list'
            }
        });
    }
}