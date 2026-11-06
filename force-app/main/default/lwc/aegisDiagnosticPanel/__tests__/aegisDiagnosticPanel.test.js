import { createElement } from 'lwc';
import AegisDiagnosticPanel from 'c/aegisDiagnosticPanel';
import getAlertDetails from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';

jest.mock('@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails', () => ({ default: jest.fn() }), { virtual: true });
const flush = async () => { for (let i = 0; i < 6; i++) await Promise.resolve(); };

describe('c-aegis-diagnostic-panel', () => {
    afterEach(() => { document.body.replaceChildren(); jest.resetAllMocks(); });
    function mount(reference) {
        const element = createElement('c-aegis-diagnostic-panel', { is: AegisDiagnosticPanel });
        element.correlationId = reference;
        document.body.appendChild(element);
        return element;
    }
    it('renders authorized summary and diagnosis without exposing raw evidence', async () => {
        getAlertDetails.mockResolvedValue({ errorLog: { severity: 'High', status: 'Diagnosed', normalizedMessage: 'Approved summary', sourceName: 'Order process' }, diagnosis: { Root_Cause__c: 'Missing account', Recommended_Action__c: 'Choose an account' } });
        const element = mount('DIAG-1');
        await flush();
        expect(getAlertDetails).toHaveBeenCalledWith({ correlationId: 'DIAG-1' });
        expect(element.shadowRoot.textContent).toContain('Approved summary');
        expect(element.shadowRoot.textContent).toContain('Choose an account');
    });
    it('provides an empty state without querying for an absent reference', async () => {
        const element = mount('');
        await flush();
        expect(getAlertDetails).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Enter a diagnostic reference');
    });
    it('reports denied access and discards a stale response after the reference changes', async () => {
        let finishOld;
        getAlertDetails.mockImplementationOnce(() => new Promise(resolve => { finishOld = resolve; }));
        const element = mount('OLD');
        getAlertDetails.mockRejectedValueOnce({ body: { message: 'Not authorized' } });
        element.correlationId = 'NEW';
        await flush();
        finishOld({ errorLog: { normalizedMessage: 'STALE PRIVATE SUMMARY' } });
        await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe('Not authorized');
        expect(element.shadowRoot.textContent).not.toContain('STALE PRIVATE SUMMARY');
    });
    it('keeps a purged-evidence notification readable', async () => {
        getAlertDetails.mockResolvedValue({ alert: { severity: 'Medium', shortMessage: 'Retained summary' }, errorLog: null });
        const element = mount('PURGED');
        await flush();
        expect(element.shadowRoot.textContent).toContain('Retained summary');
        expect(element.shadowRoot.textContent).toContain('no longer available');
    });
});
