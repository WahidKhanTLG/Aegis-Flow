import { createElement } from 'lwc';
import AegisHeadlessMonitor from 'c/aegisHeadlessMonitor';
import { __emit, __emitOn, __reset, subscribe, unsubscribe } from 'lightning/empApi';
import getOpenAlerts from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getOpenAlerts';
import getAlertBehavior from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertBehavior';
import captureFlowError from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.captureFlowError';
import getAlertDetails from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';
import { getUtilityBarAPI, openUtilityBar } from 'lightning/platformUtilityBarApi';
import USER_ID from '@salesforce/user/Id';

jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getOpenAlerts',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.dismissAlert',
    () => ({ default: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.startHelpFromAlert',
    () => ({ default: jest.fn(() => Promise.resolve({ message: 'ok' })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.escalateAlert',
    () => ({ default: jest.fn(() => Promise.resolve({ subject: 'ok' })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.captureFlowError',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertBehavior',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/user/Id', () => ({ default: '005000000000001AAA' }), { virtual: true });

function alertPayload(overrides = {}) {
    return {
        Correlation_Id__c: 'CID-1',
        Target_User_Id__c: USER_ID,
        Error_Log_Id__c: 'a01000000000001',
        Notification_Type__c: 'Detected',
        Severity__c: 'High',
        Headline__c: 'I have identified the issue.',
        Short_Message__c: 'A required value is missing.',
        Action_Available__c: 'VIEW',
        Expires_At__c: new Date(Date.now() + 3600000).toISOString(),
        ...overrides
    };
}

describe('c-aegis-headless-monitor', () => {
    let element;

    beforeEach(() => {
        __reset();
        getOpenAlerts.mockResolvedValue([]);
        getAlertBehavior.mockResolvedValue({ autoOpenUtility: false, autoOpenMinimumSeverity: 'High' });
        captureFlowError.mockResolvedValue('FLOWINT-test-guid');
        getAlertDetails.mockResolvedValue({});
        getUtilityBarAPI.mockClear();
        openUtilityBar.mockClear();
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    function buttonLabels(el) {
        return Array.from(el.shadowRoot.querySelectorAll('lightning-button')).map((b) => b.label);
    }

    async function clickButton(el, label) {
        const button = Array.from(el.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === label);
        if (!button) throw new Error(`No button labelled "${label}". Present: ${buttonLabels(el).join(', ')}`);
        button.dispatchEvent(new CustomEvent('click'));
        // getAlertDetails resolves, then .finally, then re-render.
        for (let i = 0; i < 4; i++) await Promise.resolve();
    }

    function mount() {
        element = createElement('c-aegis-headless-monitor', { is: AegisHeadlessMonitor });
        document.body.appendChild(element);
        return Promise.resolve();
    }

    it('is dormant on load: subscribes once and renders no alert', async () => {
        await mount();
        const channels = subscribe.mock.calls.map((c) => c[0]);
        expect(channels).toContain('/event/Aegis_User_Alert__e');
        expect(channels).toContain('/event/FlowExecutionErrorEvent');
        expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
    });

    it('shows an alert addressed to the current user', async () => {
        await mount();
        __emit(alertPayload());
        await Promise.resolve();
        expect(element.shadowRoot.textContent).toContain('I have identified the issue.');
    });

    it('ignores an alert addressed to a different user', async () => {
        await mount();
        __emit(alertPayload({ Target_User_Id__c: '005000000000999AAA', Correlation_Id__c: 'OTHER' }));
        await Promise.resolve();
        expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
    });

    it('ignores an expired alert', async () => {
        await mount();
        __emit(alertPayload({
            Correlation_Id__c: 'EXPIRED',
            Expires_At__c: new Date(Date.now() - 3600000).toISOString()
        }));
        await Promise.resolve();
        expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
    });

    it('suppresses a duplicate correlation id', async () => {
        await mount();
        __emit(alertPayload());
        await Promise.resolve();
        __emit(alertPayload());
        await Promise.resolve();
        const matches = element.shadowRoot.textContent.match(/I have identified the issue\./g) || [];
        expect(matches.length).toBe(1);
    });

    it('upgrades Detected to Diagnosed in place rather than stacking a second card', async () => {
        await mount();
        __emit(alertPayload());
        await Promise.resolve();
        __emit(alertPayload({
            Notification_Type__c: 'Diagnosed',
            Headline__c: 'I found the issue, but it requires technical assistance.',
            Action_Available__c: 'ESCALATE'
        }));
        await Promise.resolve();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('requires technical assistance');
        expect(text).not.toContain('I have identified the issue.');
    });

    it('loads missed alerts on init for the mobile fallback path', async () => {
        getOpenAlerts.mockResolvedValue([
            {
                correlationId: 'MISSED-1',
                headline: 'Missed while offline',
                shortMessage: 'Recovered from durable storage',
                severity: 'Medium',
                actionAvailable: 'VIEW'
            }
        ]);
        await mount();
        await Promise.resolve();
        await Promise.resolve();
        expect(getOpenAlerts).toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Missed while offline');
    });

    it('does not auto-open the panel when policy disables it', async () => {
        await mount();
        await Promise.resolve();
        __emit(alertPayload({ Severity__c: 'Critical' }));
        await Promise.resolve();
        expect(getUtilityBarAPI).not.toHaveBeenCalled();
    });

    it('auto-opens for a high severity alert when policy allows it', async () => {
        getAlertBehavior.mockResolvedValue({ autoOpenUtility: true, autoOpenMinimumSeverity: 'High' });
        await mount();
        await Promise.resolve();
        await Promise.resolve();
        __emit(alertPayload({ Severity__c: 'Critical', Correlation_Id__c: 'CRIT-1' }));
        await Promise.resolve();
        expect(getUtilityBarAPI).toHaveBeenCalled();
    });

    it('does not interrupt for an alert below the severity threshold', async () => {
        getAlertBehavior.mockResolvedValue({ autoOpenUtility: true, autoOpenMinimumSeverity: 'High' });
        await mount();
        await Promise.resolve();
        await Promise.resolve();
        __emit(alertPayload({ Severity__c: 'Medium', Correlation_Id__c: 'MED-1' }));
        await Promise.resolve();
        expect(getUtilityBarAPI).not.toHaveBeenCalled();
    });

    it('captures a real-time Flow failure with no fault path', async () => {
        await mount();
        await Promise.resolve();
        __emitOn('/event/FlowExecutionErrorEvent', {
            FlowApiName: 'Aegis_Test_Order_On_Closed_Won',
            ElementApiName: 'Create_Order_Without_Account',
            ErrorMessage: 'REQUIRED_FIELD_MISSING: Select an account.',
            ContextRecordId: '006000000000001',
            UserId: '005000000000001AAA',
            InterviewGuid: 'guid-1'
        });
        await Promise.resolve();
        await Promise.resolve();
        expect(captureFlowError).toHaveBeenCalled();
        const sent = JSON.parse(captureFlowError.mock.calls[0][0].payloadJson);
        expect(sent.ContextRecordId).toBe('006000000000001');
        expect(sent.ElementApiName).toBe('Create_Order_Without_Account');
    });

    it('ignores a Flow failure belonging to another user', async () => {
        await mount();
        await Promise.resolve();
        __emitOn('/event/FlowExecutionErrorEvent', {
            FlowApiName: 'Someone_Elses_Flow',
            ErrorMessage: 'not mine',
            UserId: '005999999999999AAA',
            InterviewGuid: 'guid-2'
        });
        await Promise.resolve();
        expect(captureFlowError).not.toHaveBeenCalled();
    });


    /*
     * Regression: the retention purge deletes an Error_Log__c and, because the lookup is
     * deleteConstraint = SetNull, leaves the User_Notification__c pointing at nothing.
     * getAlertDetails then returns a detail whose errorLog is null. The template used to
     * render {detail.errorLog.Severity__c} directly, which threw
     * "Cannot read properties of undefined (reading 'Severity__c')" and killed the panel.
     */
    it('renders the detail panel when the Error Log has been purged', async () => {
        getAlertDetails.mockResolvedValue({
            alert: {
                correlationId: 'CID-1',
                severity: 'High',
                shortMessage: 'A required value is missing.'
            },
            errorLog: null,
            diagnosis: null,
            contexts: [],
            canEscalate: false
        });
        await mount();
        __emit(alertPayload());
        await Promise.resolve();

        await clickButton(element, 'View details');

        const text = element.shadowRoot.textContent;
        expect(text).toContain('no longer available');
        expect(text).toContain('CID-1');
        // Escalation needs an Error Log to build a package, so it must not be offered.
        expect(buttonLabels(element)).not.toContain('Escalate');
        expect(buttonLabels(element)).toContain('Dismiss');
    });

    it('renders the full detail panel when the Error Log is present', async () => {
        getAlertDetails.mockResolvedValue({
            alert: { correlationId: 'CID-1', severity: 'High' },
            errorLog: {
                Severity__c: 'Critical',
                Source_Type__c: 'Flow',
                Correlation_Id__c: 'FLOWINT-abc',
                Normalized_Message__c: 'A referenced value was empty.'
            },
            diagnosis: { Root_Cause__c: 'Missing AccountId', Recommended_Action__c: 'Map the field' },
            contexts: [],
            canEscalate: true
        });
        await mount();
        __emit(alertPayload());
        await Promise.resolve();

        await clickButton(element, 'View details');

        const text = element.shadowRoot.textContent;
        expect(text).toContain('Critical');
        expect(text).toContain('A referenced value was empty.');
        expect(text).toContain('Missing AccountId');
        expect(buttonLabels(element)).toContain('Escalate');
    });

    it('does not throw when the details call resolves with nothing at all', async () => {
        getAlertDetails.mockResolvedValue(undefined);
        await mount();
        __emit(alertPayload());
        await Promise.resolve();
        await clickButton(element, 'View details');
        expect(element.shadowRoot.textContent).toBeDefined();
    });

    it('unsubscribes when removed from the DOM', async () => {
        await mount();
        await Promise.resolve();
        document.body.removeChild(element);
        expect(unsubscribe).toHaveBeenCalled();
    });
});
