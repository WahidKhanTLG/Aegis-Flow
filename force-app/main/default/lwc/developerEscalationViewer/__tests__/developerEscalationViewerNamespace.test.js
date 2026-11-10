import { createElement } from 'lwc';
import Viewer from 'c/developerEscalationViewer';
jest.mock('@salesforce/schema/Developer_Escalation__c', () => ({ default: { objectApiName: 'packaged__Developer_Escalation__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Developer_Escalation__c.Subject__c', () => ({ default: { fieldApiName: 'packaged__Subject__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Developer_Escalation__c.Status__c', () => ({ default: { fieldApiName: 'packaged__Status__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Developer_Escalation__c.Severity__c', () => ({ default: { fieldApiName: 'packaged__Severity__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Developer_Escalation__c.Channel__c', () => ({ default: { fieldApiName: 'packaged__Channel__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Developer_Escalation__c.Recipient__c', () => ({ default: { fieldApiName: 'packaged__Recipient__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Developer_Escalation__c.Diagnostic_Package_JSON__c', () => ({ default: { fieldApiName: 'packaged__Diagnostic_Package_JSON__c' } }), { virtual: true });
afterEach(() => { document.body.replaceChildren(); });
it('binds the packaged escalation object and all evidence fields through schema', async () => {
    const el = createElement('c-developer-escalation-viewer', { is: Viewer }); el.recordId = 'a01000000000001AAA'; document.body.appendChild(el);
    await Promise.resolve();
    expect(el.shadowRoot.querySelector('lightning-record-view-form').objectApiName).toBe('packaged__Developer_Escalation__c');
    expect([...el.shadowRoot.querySelectorAll('lightning-output-field')].map(field => field.fieldName)).toEqual([
        'packaged__Subject__c', 'packaged__Status__c', 'packaged__Severity__c', 'packaged__Channel__c', 'packaged__Recipient__c', 'packaged__Diagnostic_Package_JSON__c'
    ]);
});
