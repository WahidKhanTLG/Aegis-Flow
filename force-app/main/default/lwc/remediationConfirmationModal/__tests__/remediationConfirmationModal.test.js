import { createElement } from 'lwc';
import RemediationConfirmationModal from 'c/remediationConfirmationModal';

describe('c-remediation-confirmation-modal keyboard behavior', () => {
    afterEach(() => document.body.replaceChildren());
    function mount() {
        const element = createElement('c-remediation-confirmation-modal', { is: RemediationConfirmationModal });
        document.body.appendChild(element);
        return element;
    }
    it('focuses cancel on opening and contains forward/backward keyboard focus', () => {
        const element = mount();
        const cancel = element.shadowRoot.querySelector('.cancel');
        const confirm = element.shadowRoot.querySelector('.confirm');
        expect(element.shadowRoot.activeElement).toBe(cancel);
        const reverse = new KeyboardEvent('keydown', { key: 'Tab', shiftKey: true, bubbles: true, cancelable: true });
        cancel.dispatchEvent(reverse);
        expect(reverse.defaultPrevented).toBe(true);
        expect(element.shadowRoot.activeElement).toBe(confirm);
        const forward = new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true });
        confirm.dispatchEvent(forward);
        expect(forward.defaultPrevented).toBe(true);
        expect(element.shadowRoot.activeElement).toBe(cancel);
    });
    it('cancels with Escape while preserving the confirm/cancel event API', () => {
        const element = mount();
        const canceled = jest.fn();
        const confirmed = jest.fn();
        element.addEventListener('cancel', canceled);
        element.addEventListener('confirm', confirmed);
        element.shadowRoot.querySelector('.cancel').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
        expect(canceled).toHaveBeenCalledTimes(1);
        expect(confirmed).not.toHaveBeenCalled();
        element.shadowRoot.querySelector('.confirm').click();
        expect(confirmed).toHaveBeenCalledTimes(1);
    });
});
