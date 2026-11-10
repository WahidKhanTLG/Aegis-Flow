import { createElement } from 'lwc';
import Workspace from 'c/aegisWorkspace';
import actions from '@salesforce/apex/AEIR_RemediationController.getAvailableActions';
jest.mock('@salesforce/apex/AEIR_RemediationController.getAvailableActions', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/customPermission/AEIR_Execute_Remediation', () => ({ default: true }), { virtual: true });
jest.mock('@salesforce/schema/Error_Log__c', () => ({ default: { objectApiName: 'packaged__Error_Log__c' } }), { virtual: true });
jest.mock('@salesforce/schema/Developer_Escalation__c', () => ({ default: { objectApiName: 'packaged__Developer_Escalation__c' } }), { virtual: true });
afterEach(() => { document.body.replaceChildren(); jest.clearAllMocks(); });
it('searches the packaged escalation and error objects in the workspace pickers', async () => {
    const el = createElement('c-aegis-workspace', { is: Workspace }); document.body.appendChild(el);
    for (let i = 0; i < 8; i++) await Promise.resolve();
    expect(actions).toHaveBeenCalledTimes(1);
    expect([...el.shadowRoot.querySelectorAll('lightning-record-picker')].map(picker => picker.objectApiName)).toEqual([
        'packaged__Developer_Escalation__c', 'packaged__Error_Log__c'
    ]);
});
