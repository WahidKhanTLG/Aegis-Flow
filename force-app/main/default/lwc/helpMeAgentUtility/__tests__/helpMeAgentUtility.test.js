import { createElement } from 'lwc';
import HelpMeAgentUtility from 'c/helpMeAgentUtility';
import { CurrentPageReference } from 'lightning/navigation';
import createSession from '@salesforce/apex/AEIR_HelpMeController.createSession';
import diagnoseSession from '@salesforce/apex/AEIR_HelpMeController.diagnoseSession';
import escalateSession from '@salesforce/apex/AEIR_HelpMeController.escalateSession';

jest.mock('@salesforce/apex/AEIR_HelpMeController.createSession', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_HelpMeController.diagnoseSession', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_HelpMeController.escalateSession', () => ({ default: jest.fn() }), { virtual: true });
const flush = async () => { for (let i = 0; i < 6; i++) await Promise.resolve(); };
async function mount(objectApiName = 'Case') {
    const element = createElement('c-help-me-agent-utility', { is: HelpMeAgentUtility });
    document.body.appendChild(element);
    CurrentPageReference.emit({ type: 'standard__recordPage', attributes: { objectApiName, recordId: '500000000000001' }, state: {} });
    element.shadowRoot.querySelector('lightning-textarea').dispatchEvent(new CustomEvent('change', { detail: { value: 'The record could not be saved' } }));
    await flush();
    return element;
}
afterEach(() => { document.body.replaceChildren(); jest.resetAllMocks(); });
it.each(['Case', 'Opportunity', 'Customer_Process__c'])('preserves %s record-page attributes and prevents duplicate submissions', async objectApiName => {
    let complete;
    createSession.mockImplementation(() => new Promise(resolve => { complete = resolve; }));
    const element = await mount(objectApiName);
    element.shadowRoot.querySelector('button.primary-action').click();
    element.shadowRoot.querySelector('button.primary-action').click();
    expect(createSession).toHaveBeenCalledTimes(1);
    const context = JSON.parse(createSession.mock.calls[0][0].contextJson);
    expect(context.objectApiName).toBe(objectApiName);
    expect(context.recordId).toBe('500000000000001');
    complete({ sessionId: 'SESSION-1', correlationId: 'REF-1' });
    await flush();
    expect(element.shadowRoot.textContent).toContain('REF-1');
});
it('sends one explicitly requested escalation and displays its actual delivery status', async () => {
    createSession.mockResolvedValue({ sessionId: 'SESSION-1', correlationId: 'REF-1' });
    escalateSession.mockResolvedValue({ escalationId: 'ESC-1', subject: 'Service issue', status: 'Pending' });
    const element = await mount();
    element.shadowRoot.querySelector('button.primary-action').click();
    await flush();
    element.shadowRoot.querySelector('button.secondary-action').click();
    element.shadowRoot.querySelector('button.secondary-action').click();
    await flush();
    expect(escalateSession).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.textContent).toContain('Delivery status: Pending');
    expect(element.shadowRoot.querySelector('button.secondary-action').disabled).toBe(true);
});
it('keeps server failures actionable without inventing a session or diagnosis', async () => {
    createSession.mockRejectedValue({ body: { message: 'Diagnostic session access denied' } });
    const element = await mount();
    element.shadowRoot.querySelector('button.primary-action').click();
    await flush();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Diagnostic session access denied');
    expect(diagnoseSession).not.toHaveBeenCalled();
});
