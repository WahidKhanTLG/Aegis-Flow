import { createElement } from 'lwc';
import AegisRemediationConfirmation from 'c/aegisRemediationConfirmation';
import executeRemediation from '@salesforce/apex/AEIR_RemediationController.executeRemediation';

jest.mock('@salesforce/apex/AEIR_RemediationController.executeRemediation', () => ({ default: jest.fn() }), { virtual: true });

const flush = async () => { for (let i = 0; i < 6; i++) await Promise.resolve(); };
const proposal = () => ({ actionKey: 'UPDATE_ACCOUNT_DESCRIPTION', objectApiName: 'Account', fieldApiName: 'Description', recordId: '001000000000001', beforeValue: 'Old description', newValue: 'Approved description', risk: 'Updates one field' });

describe('c-aegis-remediation-confirmation', () => {
    afterEach(() => { document.body.replaceChildren(); jest.resetAllMocks(); });
    function mount(value, externallyManaged = false) {
        const element = createElement('c-aegis-remediation-confirmation', { is: AegisRemediationConfirmation });
        element.proposal = value;
        element.correlationId = 'REMEDIATE-1';
        element.externallyManaged = externallyManaged;
        document.body.appendChild(element);
        return element;
    }
    it('shows the exact proposal and emits a server-request contract only after explicit confirmation', async () => {
        const element = mount(proposal(), true);
        const confirmed = jest.fn();
        element.addEventListener('confirm', confirmed);
        expect(element.shadowRoot.textContent).toContain('Old description');
        expect(element.shadowRoot.textContent).toContain('Approved description');
        expect(confirmed).not.toHaveBeenCalled();
        element.shadowRoot.querySelector('lightning-button').click();
        await flush();
        const dialog = element.shadowRoot.querySelector('c-remediation-confirmation-modal');
        expect(dialog).not.toBeNull();
        dialog.dispatchEvent(new CustomEvent('confirm'));
        await flush();
        expect(confirmed).toHaveBeenCalledTimes(1);
        expect(executeRemediation).not.toHaveBeenCalled();
        expect(confirmed.mock.calls[0][0].detail).toEqual({ actionKey: 'UPDATE_ACCOUNT_DESCRIPTION', objectApiName: 'Account', fieldApiName: 'Description', recordId: '001000000000001', newValue: 'Approved description', correlationId: 'REMEDIATE-1', errorLogId: null, diagnosticSessionId: null, confirmed: true });
        expect(element.shadowRoot.textContent).toContain('Awaiting its execution result');
        expect(element.shadowRoot.textContent).not.toContain('change completed');
        element.result = { success: false, status: 'Rejected', userMessage: 'Server authorization denied the action' };
        await flush();
        expect(element.shadowRoot.textContent).toContain('Server authorization denied');
        expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
    });
    it('does not approve an incomplete proposal or execute any action on cancellation', async () => {
        const element = mount({ actionKey: 'MISSING-TARGET' });
        const confirmed = jest.fn();
        element.addEventListener('confirm', confirmed);
        expect(element.shadowRoot.querySelector('lightning-button')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('No remediation proposal');
        element.proposal = proposal();
        await flush();
        element.shadowRoot.querySelector('lightning-button').click();
        await flush();
        element.shadowRoot.querySelector('c-remediation-confirmation-modal').dispatchEvent(new CustomEvent('cancel'));
        await flush();
        expect(confirmed).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('c-remediation-confirmation-modal')).toBeNull();
    });
    it('accepts an explicit clear-value proposal without inventing a successful result', async () => {
        const element = mount({ ...proposal(), newValue: null });
        expect(element.shadowRoot.textContent).toContain('(clear value)');
        expect(element.shadowRoot.querySelector('lightning-button').disabled).toBe(false);
        expect(element.shadowRoot.querySelector('[role="status"]')).toBeNull();
    });

    it('executes standalone corrections only after explicit confirmation and displays the actual server result', async () => {
        let finish;
        executeRemediation.mockImplementation(() => new Promise(resolve => { finish = resolve; }));
        const element = mount(proposal());
        const completed = jest.fn();
        const pendingStates=[];
        element.addEventListener('executionstatechange',event=>pendingStates.push(event.detail.pending));
        element.addEventListener('completed', completed);
        expect(executeRemediation).not.toHaveBeenCalled();
        element.shadowRoot.querySelector('lightning-button').click();
        await flush();
        element.shadowRoot.querySelector('c-remediation-confirmation-modal').dispatchEvent(new CustomEvent('confirm'));
        await flush();
        expect(executeRemediation).toHaveBeenCalledTimes(1);
        expect(pendingStates).toEqual([true]);
        const request = JSON.parse(executeRemediation.mock.calls[0][0].requestJson);
        expect(request).toEqual(expect.objectContaining({ actionKey: 'UPDATE_ACCOUNT_DESCRIPTION', fieldApiName: 'Description', confirmed: true, newValue: 'Approved description' }));
        expect(element.shadowRoot.textContent).toContain('Awaiting its execution result');
        expect(element.shadowRoot.textContent).not.toContain('Correction executed');
        finish({ success: true, status: 'Executed', userMessage: 'Correction executed', correlationId: 'REMEDIATE-1', remediationActionId: 'AUDIT-1' });
        await flush();
        expect(element.shadowRoot.textContent).toContain('Correction executed');
        expect(completed.mock.calls[0][0].detail.success).toBe(true);
        expect(pendingStates).toEqual([true,false]);
    });

    it('shows server denial without treating it as a successful correction', async () => {
        executeRemediation.mockResolvedValue({ success: false, status: 'Denied', userMessage: 'You are not authorized to run this correction.' });
        const element = mount(proposal());
        element.shadowRoot.querySelector('lightning-button').click();
        await flush();
        element.shadowRoot.querySelector('c-remediation-confirmation-modal').dispatchEvent(new CustomEvent('confirm'));
        await flush();
        expect(element.shadowRoot.textContent).toContain('not authorized');
        expect(element.shadowRoot.textContent).toContain('was not completed');
        expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
    });

    it('does not automatically repeat a correction when its response is lost', async () => {
        executeRemediation.mockRejectedValue({ body: { message: 'Execution response unavailable. Check the audit before retrying.' } });
        const element = mount(proposal());
        element.shadowRoot.querySelector('lightning-button').click();
        await flush();
        element.shadowRoot.querySelector('c-remediation-confirmation-modal').dispatchEvent(new CustomEvent('confirm'));
        await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Check the audit');
        expect(element.shadowRoot.querySelector('lightning-button').disabled).toBe(true);
        expect(executeRemediation).toHaveBeenCalledTimes(1);
    });
});
