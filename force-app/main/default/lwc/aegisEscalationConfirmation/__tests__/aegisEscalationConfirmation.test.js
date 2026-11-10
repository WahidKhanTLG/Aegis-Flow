import { createElement } from 'lwc';
import AegisEscalationConfirmation from 'c/aegisEscalationConfirmation';
import getAlertDetails from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';
import escalateAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.escalateAlert';

jest.mock('@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_AegisHeadlessMonitorController.escalateAlert', () => ({ default: jest.fn() }), { virtual: true });
const flush = async () => { for (let i = 0; i < 6; i++) await Promise.resolve(); };

describe('c-aegis-escalation-confirmation', () => {
    afterEach(() => { document.body.replaceChildren(); jest.resetAllMocks(); });
    function mount() {
        const element = createElement('c-aegis-escalation-confirmation', { is: AegisEscalationConfirmation });
        element.correlationId = 'ESC-REF';
        document.body.appendChild(element);
        return element;
    }
    it('sends only after the user explicitly confirms retained authorized evidence', async () => {
        getAlertDetails.mockResolvedValue({ canEscalate: true, errorLog: { severity: 'High', normalizedMessage: 'Approved evidence summary' } });
        escalateAlert.mockResolvedValue({ escalationId: 'a03000000000001', subject: 'Diagnostic escalation', status: 'Pending', channel: 'Webhook' });
        const element = mount();
        await flush();
        expect(escalateAlert).not.toHaveBeenCalled();
        const sendButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(item => item.label === 'Confirm and send escalation');
        expect(sendButton.disabled).toBe(true);
        const checkbox = [...element.shadowRoot.querySelectorAll('lightning-input')].find(input => input.type === 'checkbox');
        checkbox.checked = true;
        checkbox.dispatchEvent(new CustomEvent('change'));
        await flush();
        sendButton.click();
        await flush();
        expect(escalateAlert).toHaveBeenCalledTimes(1);
        expect(escalateAlert).toHaveBeenCalledWith({ correlationId: 'ESC-REF' });
        expect(element.shadowRoot.textContent).toContain('Delivery status: Pending');
        expect(element.shadowRoot.textContent).toContain('Channel: Webhook');
        expect(sendButton.disabled).toBe(true);
    });
    it('does not offer escalation when retained evidence is absent', async () => {
        getAlertDetails.mockResolvedValue({ canEscalate: false, errorLog: null });
        const element = mount();
        await flush();
        expect([...element.shadowRoot.querySelectorAll('lightning-input')].find(input => input.type === 'checkbox')).toBeUndefined();
        expect(escalateAlert).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('accessible retained evidence');
    });
    it('reports an authorization failure without sending or exposing a summary', async () => {
        getAlertDetails.mockRejectedValue({ body: { message: 'Not authorized to view this diagnostic' } });
        const element = mount();
        await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Not authorized');
        expect(escalateAlert).not.toHaveBeenCalled();
    });
    it('requires a new confirmation after the user types a different reference', async () => {
        getAlertDetails.mockResolvedValue({ canEscalate: true, errorLog: { normalizedMessage: 'Authorized diagnostic' } });
        const element = mount();
        await flush();
        const inputs = [...element.shadowRoot.querySelectorAll('lightning-input')];
        const checkbox = inputs.find(input => input.type === 'checkbox');
        checkbox.checked = true;
        checkbox.dispatchEvent(new CustomEvent('change'));
        await flush();
        inputs.find(input => input.type !== 'checkbox').dispatchEvent(new CustomEvent('change', { detail: { value: '  ESC-NEW  ' } }));
        await flush();
        expect(getAlertDetails).toHaveBeenLastCalledWith({ correlationId: 'ESC-NEW' });
        const send = [...element.shadowRoot.querySelectorAll('lightning-button')].find(item => item.label === 'Confirm and send escalation');
        expect(send.disabled).toBe(true);
        expect(escalateAlert).not.toHaveBeenCalled();
    });
});
