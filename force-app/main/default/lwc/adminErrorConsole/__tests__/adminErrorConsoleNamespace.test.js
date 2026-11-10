import { createElement } from 'lwc';
import Console from 'c/adminErrorConsole';
import errors from '@salesforce/apex/AEIR_AdminConsoleController.getRecentErrors';
import metrics from '@salesforce/apex/AEIR_AdminConsoleController.getMetrics';
jest.mock('@salesforce/apex/AEIR_AdminConsoleController.getRecentErrors', () => ({ default: require('@salesforce/sfdx-lwc-jest').createApexTestWireAdapter(jest.fn()) }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_AdminConsoleController.getMetrics', () => ({ default: require('@salesforce/sfdx-lwc-jest').createApexTestWireAdapter(jest.fn()) }), { virtual: true });
jest.mock('@salesforce/schema/Error_Log__c.Severity__c', () => ({ default: { fieldApiName: 'packaged__Severity__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Error_Log__c.Error_Category__c', () => ({ default: { fieldApiName: 'packaged__Error_Category__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Error_Log__c.Source_Type__c', () => ({ default: { fieldApiName: 'packaged__Source_Type__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Error_Log__c.Status__c', () => ({ default: { fieldApiName: 'packaged__Status__c' } }), { virtual: true });
afterEach(() => { document.body.replaceChildren(); });
it('uses packaged datatable keys even when same-named subscriber fields exist', async () => {
    const el = createElement('c-admin-error-console', { is: Console }); document.body.appendChild(el);
    errors.emit([{ Id: 'a01000000000001AAA', Name: 'REF', packaged__Severity__c: 'High', Severity__c: 'Wrong subscriber value',
        packaged__Error_Category__c: 'Validation', packaged__Source_Type__c: 'Flow', packaged__Status__c: 'New' }]);
    metrics.emit({}); await Promise.resolve(); await Promise.resolve();
    const table = el.shadowRoot.querySelector('lightning-datatable');
    expect(table.columns.slice(1, 5).map(column => column.fieldName)).toEqual([
        'packaged__Severity__c', 'packaged__Error_Category__c', 'packaged__Source_Type__c', 'packaged__Status__c'
    ]);
    expect(table.data[0][table.columns[1].fieldName]).toBe('High');
    expect(table.data[0].recordUrl).toBe('/a01000000000001AAA');
});
