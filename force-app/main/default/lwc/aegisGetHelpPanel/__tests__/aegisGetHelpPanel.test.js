import { createElement } from 'lwc';
import AegisGetHelpPanel from 'c/aegisGetHelpPanel';
import createSession from '@salesforce/apex/AEIR_HelpMeController.createSession';
import diagnoseSession from '@salesforce/apex/AEIR_HelpMeController.diagnoseSession';
import escalateSession from '@salesforce/apex/AEIR_HelpMeController.escalateSession';

jest.mock('@salesforce/apex/AEIR_HelpMeController.createSession', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_HelpMeController.diagnoseSession', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_HelpMeController.escalateSession', () => ({ default: jest.fn() }), { virtual: true });
const flush = async () => { for (let i = 0; i < 6; i++) await Promise.resolve(); };
const button = (element, label) => [...element.shadowRoot.querySelectorAll('lightning-button')].find(item => item.label === label);

describe('c-aegis-get-help-panel', () => {
    afterEach(() => { document.body.replaceChildren(); jest.resetAllMocks(); });
    async function mount() {
        const element = createElement('c-aegis-get-help-panel', { is: AegisGetHelpPanel });
        element.recordId = '500000000000001';
        element.objectApiName = 'Case';
        document.body.appendChild(element);
        element.shadowRoot.querySelector('lightning-textarea').dispatchEvent(new CustomEvent('change', { detail: { value: 'Case save failed' } }));
        await flush();
        return element;
    }
    it('creates and diagnoses a real session, then requires explicit confirmation before sending', async () => {
        createSession.mockResolvedValue({ sessionId: 'SESSION-1', correlationId: 'HELP-1', message: 'Context captured' });
        diagnoseSession.mockResolvedValue({ summary: 'Required contact is missing', recommendedAction: 'Select a contact' });
        escalateSession.mockResolvedValue({ escalationId: 'ESC-1', subject: 'Help request', status: 'Sent' });
        const element = await mount();
        button(element, 'Create diagnostic session').click();
        await flush();
        const context = JSON.parse(createSession.mock.calls[0][0].contextJson);
        expect(context.recordId).toBe('500000000000001');
        expect(context.objectApiName).toBe('Case');
        button(element, 'Analyze captured context').click();
        await flush();
        expect(diagnoseSession).toHaveBeenCalledWith({ sessionId: 'SESSION-1' });
        expect(element.shadowRoot.textContent).toContain('Select a contact');
        expect(button(element, 'Send governed report').disabled).toBe(true);
        expect(escalateSession).not.toHaveBeenCalled();
        const confirmation = [...element.shadowRoot.querySelectorAll('lightning-input')].find(input => input.type === 'checkbox');
        confirmation.checked = true;
        confirmation.dispatchEvent(new CustomEvent('change'));
        await flush();
        button(element, 'Send governed report').click();
        await flush();
        expect(escalateSession).toHaveBeenCalledWith({ sessionId: 'SESSION-1', userDescription: 'Case save failed' });
        expect(element.shadowRoot.textContent).toContain('Delivery status: Sent');
    });
    it('prevents duplicate submissions while creation is pending and ignores a result after record context changes', async () => {
        let finish;
        createSession.mockImplementation(() => new Promise(resolve => { finish = resolve; }));
        const element = await mount();
        button(element, 'Create diagnostic session').click();
        button(element, 'Create diagnostic session').click();
        expect(createSession).toHaveBeenCalledTimes(1);
        element.recordId = '500000000000002';
        finish({ sessionId: 'OLD-SESSION', correlationId: 'OLD-REF' });
        await flush();
        expect(element.shadowRoot.textContent).not.toContain('OLD-REF');
    });
    it('shows server errors without claiming a session exists', async () => {
        createSession.mockRejectedValue({ body: { message: 'Session access denied' } });
        const element = await mount();
        button(element, 'Create diagnostic session').click();
        await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe('Session access denied');
        expect(button(element, 'Analyze captured context')).toBeUndefined();
    });
    it('invalidates the old help session when a related reference is typed', async () => {
        createSession.mockResolvedValueOnce({ sessionId: 'OLD-SESSION', correlationId: 'OLD-HELP' });
        const element = await mount();
        button(element, 'Create diagnostic session').click();
        await flush();
        expect(button(element, 'Analyze captured context')).toBeDefined();
        element.shadowRoot.querySelector('lightning-input').dispatchEvent(new CustomEvent('change', { detail: { value: '  RELATED-NEW  ' } }));
        await flush();
        expect(button(element, 'Analyze captured context')).toBeUndefined();
        createSession.mockResolvedValueOnce({ sessionId: 'NEW-SESSION', correlationId: 'NEW-HELP' });
        button(element, 'Create diagnostic session').click();
        await flush();
        expect(JSON.parse(createSession.mock.calls[1][0].contextJson).correlationId).toBe('RELATED-NEW');
        expect(diagnoseSession).not.toHaveBeenCalled();
        expect(escalateSession).not.toHaveBeenCalled();
    });
    it('requires fresh confirmation after a failed report and prevents resending after success', async () => {
        createSession.mockResolvedValue({ sessionId: 'SESSION-1', correlationId: 'HELP-1' });
        escalateSession.mockRejectedValueOnce({ body: { message: 'Delivery unavailable' } });
        const element = await mount();
        button(element, 'Create diagnostic session').click();
        await flush();
        const confirmation = [...element.shadowRoot.querySelectorAll('lightning-input')].find(input => input.type === 'checkbox');
        confirmation.checked = true;
        confirmation.dispatchEvent(new CustomEvent('change'));
        await flush();
        button(element, 'Send governed report').click();
        await flush();
        expect(button(element, 'Send governed report').disabled).toBe(true);
        expect(confirmation.checked).toBe(false);
        escalateSession.mockResolvedValueOnce({ escalationId: 'ESC-1', subject: 'Help request', status: 'Pending' });
        confirmation.checked = true;
        confirmation.dispatchEvent(new CustomEvent('change'));
        await flush();
        button(element, 'Send governed report').click();
        await flush();
        confirmation.checked = true;
        confirmation.dispatchEvent(new CustomEvent('change'));
        await flush();
        button(element, 'Send governed report').click();
        expect(escalateSession).toHaveBeenCalledTimes(2);
        expect(confirmation.disabled).toBe(true);
        button(element, 'Start a new session').click();
        await flush();
        expect(button(element, 'Send governed report')).toBeUndefined();
    });

});
