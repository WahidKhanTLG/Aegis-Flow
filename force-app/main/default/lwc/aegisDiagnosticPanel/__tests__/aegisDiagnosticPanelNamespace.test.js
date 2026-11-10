import { createElement } from 'lwc';
import Panel from 'c/aegisDiagnosticPanel';
import details from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';
jest.mock('@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/schema/AI_Diagnosis__c.Root_Cause__c', () => ({ default: { fieldApiName: 'packaged__Root_Cause__c' } }), { virtual: true });
jest.mock('@salesforce/schema/AI_Diagnosis__c.Recommended_Action__c', () => ({ default: { fieldApiName: 'packaged__Recommended_Action__c' } }), { virtual: true });
afterEach(() => { document.body.replaceChildren(); jest.clearAllMocks(); });
it('renders packaged diagnosis fields rather than same-named subscriber keys', async () => {
    details.mockResolvedValue({ errorLog: { normalizedMessage: 'Evidence' }, diagnosis: {
        packaged__Root_Cause__c: 'Correct cause', packaged__Recommended_Action__c: 'Correct action',
        Root_Cause__c: 'Wrong subscriber value', Recommended_Action__c: 'Wrong action'
    } });
    const el = createElement('c-aegis-diagnostic-panel', { is: Panel }); el.correlationId = 'REF'; document.body.appendChild(el);
    for (let i = 0; i < 8; i++) await Promise.resolve();
    expect(el.shadowRoot.textContent).toContain('Correct cause');
    expect(el.shadowRoot.textContent).toContain('Correct action');
    expect(el.shadowRoot.textContent).not.toContain('Wrong subscriber value');
});
