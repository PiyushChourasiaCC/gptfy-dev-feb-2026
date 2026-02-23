import LightningDatatable from 'lightning/datatable';
import picklistColumn from './picklistColumn.html';
import pickliststatic from './pickliststatic.html'
import customNavigation from './customNavigation.html'

export default class AICustomDatatable extends LightningDatatable {
    static customTypes = {
        picklistColumn: {
            template: pickliststatic,
            editTemplate: picklistColumn,
            standardCellLayout: true,
            typeAttributes: ['label', 'placeholder', 'options', 'value', 'context', 'variant','name', 'contextName', 'fieldName']
        },
        navigation: {
            template: customNavigation,
            typeAttributes: ['label','rowid', 'value', 'context'],
        }
    };
}