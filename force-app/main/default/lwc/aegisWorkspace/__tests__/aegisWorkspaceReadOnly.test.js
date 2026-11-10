import { createElement } from 'lwc';
import AegisWorkspace from 'c/aegisWorkspace';
import { CurrentPageReference } from 'lightning/navigation';
import getAvailableActions from '@salesforce/apex/AEIR_RemediationController.getAvailableActions';
import prepareProposal from '@salesforce/apex/AEIR_RemediationController.prepareProposal';

jest.mock('@salesforce/customPermission/AEIR_Execute_Remediation', () => ({ default: undefined }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_RemediationController.getAvailableActions', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_RemediationController.prepareProposal', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_LogCollectorService.collectForError', () => ({ default: jest.fn() }), { virtual: true });
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

beforeEach(() => { getAvailableActions.mockRejectedValue({ body: { message: 'Correction access denied' } }); });
afterEach(() => { document.body.replaceChildren(); jest.clearAllMocks(); });
it('keeps diagnostic/help surfaces available without requesting the protected correction controller', async () => {
    const element = createElement('c-aegis-workspace', { is: AegisWorkspace });
    document.body.appendChild(element);
    await flush();
    expect(getAvailableActions).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('c-aegis-get-help-panel')).not.toBeNull();
    expect(element.shadowRoot.querySelector('c-aegis-diagnostic-panel')).not.toBeNull();
    expect([...element.shadowRoot.querySelectorAll('lightning-tab')].map(tab => tab.label)).not.toContain('Prepare a correction');
    expect(element.shadowRoot.querySelector('c-aegis-remediation-confirmation')).toBeNull();
    expect(prepareProposal).not.toHaveBeenCalled();
});
it('loads a readable record context without enabling correction controls for a read-only role', async () => {
    const element = createElement('c-aegis-workspace', { is: AegisWorkspace });
    document.body.appendChild(element);
    CurrentPageReference.emit({ attributes: { recordId: '003000000000001AAA', objectApiName: 'Contact' } });
    await flush();
    expect(element.shadowRoot.querySelector('c-aegis-get-help-panel').recordId).toBe('003000000000001AAA');
    expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
    expect(getAvailableActions).not.toHaveBeenCalled();
    expect(prepareProposal).not.toHaveBeenCalled();
});
