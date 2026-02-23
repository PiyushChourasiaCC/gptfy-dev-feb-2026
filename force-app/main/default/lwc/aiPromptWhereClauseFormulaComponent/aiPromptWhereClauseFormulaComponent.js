import { api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getObjectFields from '@salesforce/apex/AIPromptController.getObjectFields'
import getPickListValues from '@salesforce/apex/AIPromptController.getPickListValues'
import getRecordTypeOptions from '@salesforce/apex/AIPromptController.getRecordTypeOptions'
import LightningModal from 'lightning/modal';

export default class AiPromptWhereClauseFormulaComponent extends LightningModal {

    @track equalTOvalue;
    @track condition = ['Any condition ', 'And Condition ']
    @track fieldOptions;
    @track fieldTabIndex = 1;
    @api objectApiName
    @track selectedField;
    @track customLogicText;
    @track orderByField;
    @track orderByFieldOptions;
    @track orderByDirection;
    @track orderByDirectionOptions = [{ label: 'Ascending Order', value : 'ASC'},
                                      { label : 'Descending Order', value: 'DESC'}]
    @track recordLimit;


    @track conditionOptions = [{ label: 'All Conditions Are Met', value: 'All Conditions Are Met' },
    { label: 'Any Condition Is Met', value: 'Any Condition Is Met' },
    { label: 'Custom Logic Is Met', value: 'Custom Logic Is Met' }]
    @track selectedCondition = 'All Conditions Are Met'
    @track operatorOptions = [
    { label: 'Contains', value: 'like' },
    { label: 'Equal', value: '=' },
    { label: 'Does Not Equal', value: '!=' },
    { label: 'Greater Than', value: '>' },
    { label: 'Greater Than Equal', value: '>=' },
    { label: 'Less Than', value: '<' },
    { label: 'Less Than Equal', value: '<=' }]
    @track selectedOperator = ''
    @track conditionsArray = [{
        key: 1, field: '', operator: '', value: '',
        selectedMultipicklistValues: [], type: '', conditionValue: '', conditionType: '',
        isPicklistField: false, isMultiPicklistField: false, isTextField: true, fieldValueOptions: [],
        operatorOptions: [], isDateField: false,isTimeField:false, dateType: 'date', isAddButtonVisible: true
    }]
    @track isCustomLogicSelected;
    conditionPosition = 0;
    connectedCallback() {
        this.getFields()
    }

    handleCancel = () => {
        this.close();
    }

    getFields = () => {
        // console.log('------- object name ------------')
        // console.log(this.objectApiName)
        getObjectFields({ objectName: this.objectApiName })
            .then((res) => {
                if(res){
                    let fields = res.fields;
                    fields.sort((a, b) => {
                        let fa = a.label.toLowerCase(), fb = b.label.toLowerCase();
                    
                        if (fa < fb) {
                            return -1;
                        }
                        if (fa > fb) {
                            return 1;
                        }
                        return 0;
                    });
                    this.fieldOptions = fields;
                    let orderByFields = res.orderByFields;
                    orderByFields.sort((a, b) => {
                        let fa = a.label.toLowerCase(), fb = b.label.toLowerCase();
                    
                        if (fa < fb) {
                            return -1;
                        }
                        if (fa > fb) {
                            return 1;
                        }
                        return 0;
                    });
                    this.orderByFieldOptions = orderByFields;
                }
                
            }).catch((e) => {
                // console.log('error : ' + e.message)
                // console.log(e)
            })
    }

    setPicklistValues = (fieldName, index) => {
        getPickListValues({ objName: this.objectApiName, fieldName: fieldName })
            .then((res) => {
                // console.log('picklist values ');
                // console.log(res)
                let arr = JSON.parse(JSON.stringify(res));
                // arr.unshift({label: '-- None --',value : ''})
                let arrField = JSON.parse(JSON.stringify(this.conditionsArray));
                arrField[index].fieldValueOptions = arr;
                this.conditionsArray = arrField;
            }).catch((e) => {
             //   console.log('error : ' + e)
            })
    }


    handleConditionChange = (e) => {
       // console.log(e.target.value)
        this.selectedCondition = e.target.value;
        let arr = JSON.parse(JSON.stringify(this.conditionsArray));
        let conditionvalue = this.getConditionValue();

        arr.forEach((i) => {
            if (this.selectedCondition === 'Custom Logic Is Met') {
                i.conditionValue = i.key;
            } else {
                if (i.key === 1) {
                    i.conditionValue = ''
                 //   console.log('condition value: ' + conditionvalue)
                } else {
                    i.conditionValue = conditionvalue;
                }
            }
            i.conditionType = this.selectedCondition
        })
        this.conditionsArray = arr;
        if (this.selectedCondition === 'Custom Logic Is Met') {
            this.isCustomLogicSelected = true;
            this.updateCustomLogic(this.conditionPosition + 1)
        } else {
            this.isCustomLogicSelected = false;
        }
      //  console.log('condition ceriteria change ')
       // console.log(arr)

    }

    updateCustomLogic = (pos) => {
        let logicText = '1';
        for (let i = 2; i <= pos; i++) {
            logicText = logicText + ' AND ' + i;
        }
        this.customLogicText = logicText
    }



    handleFieldChange = (e) => {
    //    console.log(e.target.value)
        let index = e.target.dataset.index;
        let arr = JSON.parse(JSON.stringify(this.conditionsArray))
        arr[index].field = e.target.value;
        let type = this.getFieldTypeByFieldName(e.target.value)
        arr[index].type = type;
        arr[index].value = ''
        arr[index].operatorOptions = this.getFieldTypeOperatorOptions(type, e.target.value)
        if (e.target.value === 'RecordTypeId') {
            arr[index].fieldValueOptions = this.getRecordTypeNameOptions(index)
            arr[index].isMultiPicklistField = false;
            arr[index].isPicklistField = true;
            arr[index].isTextField = false;
            arr[index].isDateField = false;
            arr[index].isDateTimeField = false;
            arr[index].isTimeField = false;
        } else if (type === 'PICKLIST' || type === 'MULTIPICKLIST') {
            this.setPicklistValues(e.target.value, index)
            arr[index].isMultiPicklistField = true;
            arr[index].isPicklistField = true;
            arr[index].isTextField = false;
            arr[index].isDateField = false;
            arr[index].isDateTimeField = false;
            arr[index].isTimeField = false;
        } else if (type === 'BOOLEAN') {
            arr[index].fieldValueOptions = [{ label: 'FALSE', value: 'FALSE' }, { label: 'TRUE', value: 'TRUE' }]
            arr[index].isMultiPicklistField = false;
            arr[index].isPicklistField = true;
            arr[index].isTextField = false;
            arr[index].isDateField = false;
            arr[index].isDateTimeField = false;
            arr[index].isTimeField = false;
            arr[index].value = 'FALSE'
        } else if (type === 'DATE') {
            arr[index].isMultiPicklistField = false;
            arr[index].isPicklistField = false;
            arr[index].isTextField = false;
            arr[index].isDateField = true;
            arr[index].isTimeField = false;
            arr[index].isDateTimeField = false;
        } else if (type === 'DATETIME') {
            arr[index].isMultiPicklistField = false;
            arr[index].isPicklistField = false;
            arr[index].isTextField = false;
            arr[index].isDateField = false;
            arr[index].isDateTimeField = true;
            arr[index].isTimeField = false;
        }else if (type === 'TIME') {
            arr[index].isMultiPicklistField = false;
            arr[index].isPicklistField = false;
            arr[index].isTextField = false;
            arr[index].isDateField = false;
            arr[index].isDateTimeField = false;
            arr[index].isTimeField = true;
        } else {
            arr[index].isMultiPicklistField = false;
            arr[index].isPicklistField = false;
            arr[index].isTextField = true;
            arr[index].isDateField = false;
            arr[index].isDateTimeField = false;
            arr[index].isTimeField = false;
        }
        this.conditionsArray = arr;

    }

    getRecordTypeNameOptions = (index) => {
        getRecordTypeOptions({ objName: this.objectApiName })
            .then((res) => {
                let arrField = JSON.parse(JSON.stringify(this.conditionsArray));
                arrField[index].fieldValueOptions = res;
                this.conditionsArray = arrField;
                return res;
            }).catch((e) => {
                return [];
            })
    }

    getFieldTypeByFieldName = (fieldName) => {
        let arr = JSON.parse(JSON.stringify(this.fieldOptions))
        let obj = arr.find((item) => item.value === fieldName);
       // console.log(obj)
        return obj.type;
    }

    handleOperatorChange = (e) => {
       // console.log(e.target.value)
        let index = e.target.dataset.index;
        let arr = JSON.parse(JSON.stringify(this.conditionsArray))
        arr[index].operator = e.target.value;
        this.conditionsArray = arr;
    }

    handleValueChange = (e) => {
      // console.log(e.target.dataset)
        let arr = JSON.parse(JSON.stringify(this.conditionsArray))
        let index = e.target.dataset.index;
        let v = e.detail.value;
        arr[index].value = e.detail.value;
        if (arr[index].isMultiPicklistField) {
            let selectedMultiPicklist = arr[index].selectedMultipicklistValues;
            let selectedMultiPicklistSize = selectedMultiPicklist.length
            let selectedObj = this.getSeletedMultiPicklistByValue(e.detail.value, arr[index].fieldValueOptions)
            if (selectedMultiPicklistSize === 0) {
                selectedMultiPicklist.push({ key: 1, label: selectedObj.label, value: selectedObj.value, })
            } else {
                let res = selectedMultiPicklist.find((item) => item.value === v)
                if (res === undefined) {
                    let lastObj = selectedMultiPicklist[selectedMultiPicklistSize - 1]
                    selectedMultiPicklist.push({ key: lastObj.key + 1, label: selectedObj.label, value: selectedObj.value, })
                }
            }
        } else {
            arr[index].selectedMultipicklistValues = [];
        }

        this.conditionsArray = arr;
    }

    getSeletedMultiPicklistByValue = (value, arr) => {
        return arr.find((item) => item.value === value)
    }

    handleChangeCustomLogic = (e) => {
       // console.log(e.target)
        this.customLogicText = e.target.value;
    }

    handleRemoveMultiPicklist = (e) => {
       // console.log('called picklist')
        let index = e.target.dataset.index;
        let arr = JSON.parse(JSON.stringify(this.conditionsArray))
        let arrMultiPicklist = arr[index].selectedMultipicklistValues
        arrMultiPicklist.splice(arrMultiPicklist.indexOf(e.target.name, 1))
        arr[index].selectedMultipicklistValues = arrMultiPicklist;
        this.conditionsArray = arr;
    }

    handleAddConditionChange = (e) => {
        let index = e.target.dataset.index;
        let arr = JSON.parse(JSON.stringify(this.conditionsArray))
        if (this.isValidCondition(index, arr)) {
            // let arrlength = this.conditionsArray.length-1;
            // if(arrlength === index)
            arr[index].isAddButtonVisible = false;
            let key = arr[index].key + 1;
            let conditionValue = this.getConditionValue(key);
            arr.push({
                key: key, field: '', operator: '', value: '', type: '',
                conditionValue: conditionValue, conditionType: this.selectedCondition,
                isPicklistField: false, isMultiPicklistField: false, isTextField: true, fieldValueOptions: [],
                selectedMultipicklistValues: [], isDateField: false,isTimeField: false,
                operatorOptions: this.getFieldTypeOperatorOptions(''), isAddButtonVisible: true
            });
            this.conditionsArray = arr;
            this.conditionPosition++;
            this.customLogicText = this.customLogicText + ' AND ' + key
         //   console.log('push  : ' + arr)
        }

    }

    handleOrderByFieldChange = (e)=> {
         this.orderByField = e.target.value;
    }

    handleOrderByDirectionChange = (e)=> {
        this.orderByDirection = e.target.value;
   }

   handleRecordLimitChange = (e)=> {
         this.recordLimit = e.target.value;
    }

    getFieldTypeOperatorOptions = (type) => {
        if (type === 'PICKLIST') {
            return [
                { label: 'Contains', value: 'IN' },
                { label: 'Not Contains', value: 'NOT IN' }]
        }else if ( type === 'MULTIPICKLIST') {
            return [
                { label: 'Includes', value: 'includes' },
                { label: 'Excludes', value: 'excludes' }]
        }else if (type === 'BOOLEAN' || type === 'REFERENCE' || type === 'ID') {
            return [
                { label: 'Equal', value: '=' },
                { label: 'Does Not Equal', value: '!=' }]
        } else if (type === 'INTEGER' || type === 'DOUBLE' || type === 'DATE' || type === 'DATETIME' 
                        || type === 'TIME' || type === 'CURRENCY' || type === 'PERCENT') {
            return [
            { label: 'Equal', value: '=' },
            { label: 'Does Not Equal', value: '!=' },
            { label: 'Greater Than', value: '>' },
            { label: 'Greater Than Equal', value: '>=' },
            { label: 'Less Than', value: '<' },
            { label: 'Less Than Equal', value: '<=' }]
        }
        return [
        { label: 'Contains', value: 'like' },
        { label: 'Equal', value: '=' },
        { label: 'Does Not Equal', value: '!=' }]
    }



    getConditionValue = (key) => {
        if (this.selectedCondition === 'All Conditions Are Met') {
            return 'AND'
        } else if (this.selectedCondition === 'Any Condition Is Met') {
            return 'OR'
        } else if (this.selectedCondition === 'Custom Logic Is Met') {
            return key;
        }
        return ''
    }

    isValidCondition = (pos, arr) => {
        if ((arr[pos].field !== undefined && arr[pos].field !== '') && (arr[pos].operator === undefined || arr[pos].operator === '')) {
                 this.showToast('error', 'Error', 'Invalid Operator. Please Select Operator')
                 return false;
        }
        return true;
    }

    showToast(variant, title, message) {
        const event = new ShowToastEvent({
            title: title,
            variant: variant,
            message: message,
        });
        this.dispatchEvent(event);
    }


    handleDeleteButton = (e) => {
        let index = e.target.dataset.index;
        let arr = JSON.parse(JSON.stringify(this.conditionsArray))
        if (arr.length > 1) {
            arr.splice(index, 1);
            arr = this.recalculateKeyNumber(arr);
            this.conditionsArray = arr;
            this.conditionPosition--;
        }

    }

    recalculateKeyNumber = (arr) => {
        let i = 1;
        let len = arr.length;
        arr.forEach((item) => {
            item.key = i;
            item.conditionValue = this.getConditionValue(i);
            if (i === len) {
                item.isAddButtonVisible = true;
            } else {
                item.isAddButtonVisible = false;
            }
            i++;
        })
        return arr;
    }

    validationOrderByANDLimit = ()=> {
        if(this.orderByField && this.orderByField !== '' && (this.orderByDirection === undefined || this.orderByDirection === '')){
            this.showToast('error', 'Error', 'Invalid OrderBy Option. Please Select Option')
            return false;
        }
        if(this.recordLimit && this.recordLimit !== '' && this.recordLimit <= 0){
                this.showToast('error', 'Error', 'Invalid Record Limit. Please Enter a Valid Number')
                return false;
        }
        return true;
    }

    appendOrderByANDLimit = (q)=> {
          if(this.orderByField && this.orderByField !== '' && this.orderByDirection !== undefined && this.orderByDirection !== ''){
              q = q + ' ORDER BY ' + this.orderByField + ' ' + this.orderByDirection
          }
          if(this.recordLimit && this.recordLimit !== '' && this.recordLimit > 0){
              q = q + ' LIMIT ' + this.recordLimit
          }
          return q;
    }

    handleMergeChange = (e) => {
        let arr = JSON.parse(JSON.stringify(this.conditionsArray))
        let isValid = true;
        for (let i = 0; i < arr.length; i++) {
            if (!this.isValidCondition(i, arr)) {
                isValid = false;
                break;
            }
        }

        if(!this.validationOrderByANDLimit()){
            isValid = false;
        }

        if (isValid) {
            try {
                if (this.selectedCondition !== 'Custom Logic Is Met') {
                    let condition = this.getConditionValue()
                    let customlogic = ''
                    customlogic = this.getQueryRow(arr[0])
                    
                    for (let i = 1; i < arr.length; i++) {
                        customlogic += ' ' + condition + ' ' + this.getQueryRow(arr[i])
                    }
                    if(customlogic !== ''){
                        customlogic = '( '+customlogic+' )';
                    }
                    customlogic = this.appendOrderByANDLimit(customlogic)
                    this.close(customlogic);
                } else {

                        let s = this.customLogicText
                        let str = ''
                        for (let a of s.split(/[ ]+/)) {
                            //console.log(a)
    
                            if (/[0-9]/.test(a)) {
                                let numStr = ''
                                let isFirst = false;
                                let firstStr = ''
                                let arrrr = a.split('');
                                for (let x of arrrr) {
                                    if (/[0-9]/.test(x)) {
                                        numStr += x;
                                        if (arrrr[0] === x) {
                                            isFirst = true;
                                        }
                                    } else {
                                        if (isFirst) {
                                            firstStr += x;
                                        } else {
                                            str += x;
                                        }
                                    }
                                }
                                let n;
                                if (numStr !== '') {
                                    n = Number.parseInt(numStr, 36);
                                } else {
                                    n = Number.parseInt(a, 36);
                                }
    
                                n--;
                                if (isFirst) {
                                    if (str === '') {
                                        str += this.getQueryRow(arr[n]) + ' ' + firstStr
                                    } else {
                                        str += ' ' + this.getQueryRow(arr[n]) + ' ' + firstStr
                                    }
                                } else {
                                    if (str === '') {
                                        str += this.getQueryRow(arr[n]) + ' '
                                    } else {
                                        str += ' ' + this.getQueryRow(arr[n]) + ' '
                                    }
                                }
    
    
                            } else {
                                str += a
                            }
                        }
                        str = str.trim();
                        if(str !== ''){
                            str = '( '+str+' )';
                        }
                        str = this.appendOrderByANDLimit(str)
                        this.close(str);

                }

            } catch (e) {
                this.showToast('error', 'Error', 'Invalid Custom Logic. Please Check')
            }
        }


    }


    getQueryRow = (obj) => {
        if(obj.field === undefined || obj.field === ''){
            return '';
        }
        if (obj.operator === 'IN' || obj.operator === 'NOT IN' || obj.operator === 'includes' || obj.operator === 'excludes') {
            try {
                let selectedValues = obj.selectedMultipicklistValues;
                if(selectedValues.length === 0){
                    if(obj.operator === 'NOT IN' || obj.operator === 'excludes'){
                        obj.operator = '!='
                    }else if(obj.operator === 'IN' || obj.operator === 'includes'){
                        obj.operator = '='
                    }
                    return obj.field + ' ' + obj.operator + ' NULL'
                }
                let str = obj.field + ' ' + obj.operator + ' (\'' + selectedValues[0].value + '\''
                for (let a = 1; a < selectedValues.length; a++) {
                    str += ',\'' + selectedValues[a].value + '\'';
                }
                str += ')'
                return str;
            } catch (e) {
                return obj.field + ' = \'\''
            }

        } if (obj.operator === 'like') {
            let str = obj.field + ' ' + obj.operator + ' \'%' + obj.value + '%\''
            return str;
        }
        if (obj.field === 'RecordTypeId') {
            let str = 'RecordType.DeveloperName ' + obj.operator + ' \'' + obj.value + '\''
            return str;
        }
        if (obj.type === 'BOOLEAN') {
            let str = obj.field + ' ' + obj.operator  + ' ' + obj.value
            return str;
        }
        if (obj.type === 'TIME') {
            obj.value = (obj.value === '' || obj.value === undefined)? 'NULL' : obj.value+'Z'
            let str = obj.field + ' ' + obj.operator  + ' ' + obj.value
            return str;
        }
        if ( obj.type === 'DATE' || obj.type === 'DATETIME' || obj.type === 'INTEGER' || obj.type === 'DOUBLE'
                        || obj.type === 'CURRENCY' || obj.type === 'PERCENT') {
            obj.value = (obj.value === '' || obj.value === undefined)? 'NULL' : obj.value
            let str = obj.field + ' ' + obj.operator  + ' ' + obj.value;
            return str;
        }
        obj.value = (obj.value === '' || obj.value === undefined)? 'NULL' : ' \'' + obj.value + '\''
        return obj.field + ' ' + obj.operator + ' ' +obj.value

    }


}