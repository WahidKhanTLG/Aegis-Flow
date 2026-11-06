import { createElement } from 'lwc';
import AegisNotificationCard from 'c/aegisNotificationCard';
import resolveAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.resolveAlert';
import dismissAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.dismissAlert';

jest.mock('@salesforce/apex/AEIR_AegisHeadlessMonitorController.resolveAlert', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_AegisHeadlessMonitorController.dismissAlert', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
const flush = async () => { for (let i = 0; i < 6; i++) await Promise.resolve(); };
const notice = () => ({ correlationId: 'NOTICE-1', status: 'New', expiresAt: new Date(Date.now() + 60000).toISOString(), headline: 'Canonical server alert', shortMessage: 'User-safe detail', severity: 'High' });

describe('c-aegis-notification-card', () => {
    afterEach(() => { document.body.replaceChildren(); jest.resetAllMocks(); });
    function mount() {
        const element = createElement('c-aegis-notification-card', { is: AegisNotificationCard });
        element.correlationId = 'NOTICE-1';
        document.body.appendChild(element);
        return element;
    }
    it('resolves canonical content and dismisses through the server boundary', async () => {
        resolveAlert.mockResolvedValue(notice());
        dismissAlert.mockResolvedValue();
        const element = mount();
        const onDismiss = jest.fn();
        element.addEventListener('dismiss', onDismiss);
        await flush();
        expect(element.shadowRoot.textContent).toContain('Canonical server alert');
        element.shadowRoot.querySelectorAll('lightning-button')[2].click();
        await flush();
        expect(dismissAlert).toHaveBeenCalledWith({ correlationId: 'NOTICE-1' });
        expect(onDismiss).toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Notification dismissed');
    });
    it.each([null, { ...notice(), status: 'Dismissed' }, { ...notice(), correlationId: 'SOMEONE-ELSE' }, { ...notice(), expiresAt: new Date(0).toISOString() }])('does not render an ineligible response %p', async response => {
        resolveAlert.mockResolvedValue(response);
        const element = mount();
        await flush();
        expect(element.shadowRoot.textContent).not.toContain('Canonical server alert');
        expect(element.shadowRoot.textContent).toContain('No active notification');
    });
    it('provides an actionable error if canonical resolution fails', async () => {
        resolveAlert.mockRejectedValue(new Error('offline'));
        const element = mount();
        await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
        expect(element.shadowRoot.textContent).toContain('Try refreshing');
    });
});
