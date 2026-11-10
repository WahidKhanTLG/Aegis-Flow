import ERROR_LOG_OBJECT from '@salesforce/schema/Error_Log__c';
import ROOT_CAUSE_FIELD from '@salesforce/schema/AI_Diagnosis__c.Root_Cause__c';
import RECOMMENDED_ACTION_FIELD from '@salesforce/schema/AI_Diagnosis__c.Recommended_Action__c';
import { createElement } from 'lwc';
import AegisHeadlessMonitor from 'c/aegisHeadlessMonitor';
import { __emit, __emitOn, __reset, subscribe, unsubscribe, onError } from 'lightning/empApi';
import getOpenAlerts from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getOpenAlerts';
import resolveAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.resolveAlert';
import dismissAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.dismissAlert';
import { CurrentPageReference } from 'lightning/navigation';
import getAlertBehavior from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertBehavior';
import getAlertChannel from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertChannel';
import getFlowErrorChannel from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getFlowErrorChannel';
import getSurfaceSettings from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getSurfaceSettings';
import captureFlowError from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.captureFlowError';
import reportScreenIssue from '@salesforce/apex/AEIR_UiSaveErrorController.reportScreenIssue';
import getAlertDetails from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';
import startHelpFromAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.startHelpFromAlert';
import {
    EnclosingUtilityId,
    getInfo,
    open,
    updateUtility,
    updatePanel
} from 'lightning/platformUtilityBarApi';
import USER_ID from '@salesforce/user/Id';

jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getSurfaceSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.resolveAlert',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
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
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertChannel',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getFlowErrorChannel',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AEIR_UiSaveErrorController.reportScreenIssue',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/schema/Error_Log__c', () => ({ default: { objectApiName: 'Error_Log__c' } }), { virtual: true });
jest.mock('@salesforce/schema/AI_Diagnosis__c.Root_Cause__c', () => ({ default: { fieldApiName: 'Root_Cause__c' } }), { virtual: true });
jest.mock('@salesforce/schema/AI_Diagnosis__c.Recommended_Action__c', () => ({ default: { fieldApiName: 'Recommended_Action__c' } }), { virtual: true });
jest.mock('@salesforce/user/Id', () => ({ default: '005000000000001AAA' }), { virtual: true });

function alertPayload(overrides = {}) {
    return {
        Correlation_Id__c: 'CID-1',
        Target_User_Id__c: USER_ID,
        ...overrides
    };
}

function canonicalAlert(overrides = {}) {
    return {
        correlationId: 'CID-1',
        errorLogId: 'a01000000000001',
        notificationType: 'Detected',
        severity: 'High',
        headline: 'I have identified the issue.',
        shortMessage: 'A required value is missing.',
        actionAvailable: 'VIEW',
        status: 'New',
        expiresAt: new Date(Date.now() + 3600000).toISOString(),
        ...overrides
    };
}

describe('c-aegis-headless-monitor', () => {
    let element;

    beforeEach(() => {
        __reset();
        ERROR_LOG_OBJECT.objectApiName = 'Error_Log__c';
        ROOT_CAUSE_FIELD.fieldApiName = 'Root_Cause__c';
        RECOMMENDED_ACTION_FIELD.fieldApiName = 'Recommended_Action__c';
        getSurfaceSettings.mockResolvedValue({ utilityEnabled: true });
        getOpenAlerts.mockResolvedValue([]);
        resolveAlert.mockReset().mockImplementation(({ correlationId }) => Promise.resolve(canonicalAlert({ correlationId })));
        getAlertBehavior.mockResolvedValue({ autoOpenUtility: false, autoOpenMinimumSeverity: 'High' });
        getAlertChannel.mockResolvedValue('/event/Aegis_User_Alert__e');
        getFlowErrorChannel.mockResolvedValue('/event/FlowExecutionErrorEvent');
        reportScreenIssue.mockResolvedValue({ success: true, correlationId: 'UI-SCREEN-123' });
        captureFlowError.mockResolvedValue('FLOWINT-test-guid');
        getAlertDetails.mockResolvedValue({});
        getInfo.mockResolvedValue({ utilityVisible: false });
        getInfo.mockClear();
        open.mockClear();
        updateUtility.mockClear();
        updatePanel.mockClear();
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

    async function flushUtilityUpdates() {
        for (let i = 0; i < 8; i++) await Promise.resolve();
    }

    async function mount() {
        element = createElement('c-aegis-headless-monitor', { is: AegisHeadlessMonitor });
        document.body.appendChild(element);
        EnclosingUtilityId.emit('utility-aegis-alerts');
        await flushUtilityUpdates();
    }

    it('is dormant on load: subscribes once and renders no alert', async () => {
        await mount();
        const channels = subscribe.mock.calls.map((c) => c[0]);
        expect(channels).toContain('/event/Aegis_User_Alert__e');
        expect(channels).toContain('/event/FlowExecutionErrorEvent');
        expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
    });

    it('keeps an action failure when an unknown EMP transport problem arrives', async () => {
        getAlertDetails.mockRejectedValueOnce({ body: { message: 'Your access to this notice could not be verified.' } });
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        await clickButton(element, 'View details');

        onError.mock.calls[0][0]({ channel: '/meta/handshake', error: 'RAW EMP ERROR MUST NOT DISPLAY' });
        await flushUtilityUpdates();

        const actionError = element.shadowRoot.querySelector('[role="alert"]');
        expect(actionError.textContent).toContain('Alert details could not be loaded. Your access');
        expect(element.shadowRoot.textContent).toContain('The live connection reported a problem');
        expect(element.shadowRoot.textContent).toContain('Live alert delivery is not confirmed');
        expect(element.shadowRoot.textContent).not.toContain('RAW EMP ERROR');
        expect(element.shadowRoot.querySelectorAll('[role="alert"]')).toHaveLength(1);
        __emit(alertPayload());
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('The live connection reported a problem');
    });

    it('refreshes saved notices after core stream failure with only one request in flight', async () => {
        subscribe.mockRejectedValueOnce({ body: { message: 'RAW SUBSCRIPTION FAILURE' } });
        await mount();
        expect(element.shadowRoot.textContent).toContain('Live alert updates are unavailable');
        expect(element.shadowRoot.querySelector('.error')).toBeNull();

        let finishRefresh;
        getOpenAlerts.mockImplementationOnce(() => new Promise(resolve => { finishRefresh = resolve; }));
        await clickButton(element, 'Refresh alerts');
        await clickButton(element, 'Refresh alerts');
        expect(getOpenAlerts).toHaveBeenCalledTimes(2); // startup plus one explicit refresh
        const refresh = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(button => button.label === 'Refresh alerts');
        expect(refresh.disabled).toBe(true);
        expect(element.shadowRoot.textContent).toContain('Loading saved alerts');

        finishRefresh([canonicalAlert()]);
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('I have identified the issue.');
        expect(element.shadowRoot.textContent).toContain('Saved alerts refreshed.');
        expect(element.shadowRoot.textContent).toContain('Live alert updates are unavailable');
        expect(element.shadowRoot.textContent).not.toContain('RAW SUBSCRIPTION FAILURE');
        expect(refresh.disabled).toBe(false);
        expect(subscribe).toHaveBeenCalledTimes(2); // refresh never reconnects or starts polling
    });

    it('reports optional Flow subscription failure without marking core actions failed', async () => {
        // Alert channel succeeds first; the second subscription is the optional Flow source.
        const normalSubscription = subscribe.getMockImplementation();
        subscribe.mockImplementationOnce(normalSubscription).mockRejectedValueOnce({ body: { message: 'RAW FLOW FAILURE' } });
        await mount();

        expect(element.shadowRoot.textContent).toContain('Live Flow error capture is unavailable');
        expect(element.shadowRoot.textContent).toContain('Live alert subscription established');
        expect(element.shadowRoot.textContent).not.toContain('Live alert updates are unavailable');
        expect(element.shadowRoot.textContent).not.toContain('RAW FLOW FAILURE');
        expect(element.shadowRoot.querySelector('.error')).toBeNull();
        await clickButton(element, 'Refresh alerts');
        expect(getOpenAlerts).toHaveBeenCalledTimes(2);
    });

    it('distinguishes a Flow capture failure from an alert action failure', async () => {
        captureFlowError.mockRejectedValueOnce(new Error('RAW CAPTURE FAILURE'));
        await mount();
        __emitOn('/event/FlowExecutionErrorEvent', { UserId: USER_ID, InterviewGuid: 'capture-failure' });
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('A live Flow error could not be captured');
        expect(element.shadowRoot.textContent).not.toContain('RAW CAPTURE FAILURE');
        expect(element.shadowRoot.querySelector('.error')).toBeNull();
    });

    it.each([null, '', '/event/Other__e'])('does not guess a custom alert channel when lookup returns %s', async channel => {
        getAlertChannel.mockResolvedValueOnce(channel);
        await mount();
        expect(subscribe.mock.calls.map(call => call[0])).toEqual(['/event/FlowExecutionErrorEvent']);
        expect(element.shadowRoot.textContent).toContain('Live alert updates are unavailable');
        expect(getOpenAlerts).toHaveBeenCalled();
    });

    it('retains saved alerts when custom-channel lookup rejects', async () => {
        getAlertChannel.mockRejectedValueOnce(new Error('PRIVATE CHANNEL FAILURE'));
        await mount();
        expect(subscribe.mock.calls.map(call => call[0])).toEqual(['/event/FlowExecutionErrorEvent']);
        expect(element.shadowRoot.textContent).toContain('Live alert updates are unavailable');
        expect(element.shadowRoot.textContent).not.toContain('PRIVATE CHANNEL FAILURE');
        expect(getOpenAlerts).toHaveBeenCalled();
    });

    it('reads namespaced event fields and diagnoses while rejecting an unqualified or foreign wake-up', async () => {
        ERROR_LOG_OBJECT.objectApiName = 'example__Error_Log__c';
        ROOT_CAUSE_FIELD.fieldApiName = 'example__Root_Cause__c';
        RECOMMENDED_ACTION_FIELD.fieldApiName = 'example__Recommended_Action__c';
        getAlertChannel.mockResolvedValueOnce('/event/example__Aegis_User_Alert__e');
        getAlertDetails.mockResolvedValue({ errorLog: { severity: 'High', normalizedMessage: 'Packaged evidence' },
            diagnosis: { example__Root_Cause__c: 'Packaged cause', example__Recommended_Action__c: 'Packaged action' } });
        await mount();
        __emitOn('/event/example__Aegis_User_Alert__e', alertPayload());
        __emitOn('/event/example__Aegis_User_Alert__e', { example__Target_User_Id__c: '005000000000002AAA', example__Correlation_Id__c: 'FOREIGN' });
        await flushUtilityUpdates();
        expect(resolveAlert).not.toHaveBeenCalled();
        __emitOn('/event/example__Aegis_User_Alert__e', { example__Target_User_Id__c: USER_ID, example__Correlation_Id__c: 'PACKAGED' });
        await flushUtilityUpdates();
        expect(resolveAlert).toHaveBeenCalledWith({ correlationId: 'PACKAGED' });
        await clickButton(element, 'View details');
        expect(element.shadowRoot.textContent).toContain('Packaged cause');
        expect(element.shadowRoot.textContent).toContain('Packaged action');
    });

    it('ignores clearly unrelated structured channels but retains unknown transport warnings', async () => {
        ERROR_LOG_OBJECT.objectApiName = 'example__Error_Log__c';
        getAlertChannel.mockResolvedValueOnce('/event/example__Aegis_User_Alert__e');
        await mount();
        const emitError = onError.mock.calls[0][0];
        emitError({ channel: '/meta/subscribe', subscription: '/event/Unrelated__e', error: 'RAW UNRELATED' });
        await flushUtilityUpdates();
        expect(element.shadowRoot.querySelector('.connection-warning')).toBeNull();

        emitError({ channel: '/meta/subscribe', subscription: '/event/example__Aegis_User_Alert__e' });
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('The live alert connection reported a problem');
        expect(element.shadowRoot.querySelector('.error')).toBeNull();
        expect(element.shadowRoot.textContent).not.toContain('RAW UNRELATED');
    });

    it('clears only the dedicated alert-channel warning when a later own wake-up arrives', async () => {
        getAlertDetails.mockRejectedValueOnce({ body: { message: 'Details are temporarily unavailable.' } });
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        await clickButton(element, 'View details');
        const emitError = onError.mock.calls[0][0];
        emitError({ subscription: '/event/Aegis_User_Alert__e' });
        emitError({ subscription: '/event/FlowExecutionErrorEvent' });
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('The live alert connection reported a problem');

        await clickButton(element, 'Refresh alerts');
        expect(element.shadowRoot.textContent).toContain('The live alert connection reported a problem');
        __emit(alertPayload());
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).not.toContain('The live alert connection reported a problem');
        expect(element.shadowRoot.textContent).toContain('Live alert subscription established');
        expect(element.shadowRoot.textContent).toContain('Live Flow error capture is unavailable');
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Alert details could not be loaded');
    });

    it('does not discard a metadata-channel error whose subscription is unknown', async () => {
        await mount();
        onError.mock.calls[0][0]({ channel: '/meta/subscribe', error: 'RAW UNKNOWN' });
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('The live connection reported a problem');
        expect(element.shadowRoot.textContent).not.toContain('RAW UNKNOWN');
    });

    it('keeps an observed transport warning after a late subscription success', async () => {
        let finishSubscription;
        subscribe.mockImplementationOnce(() => new Promise(resolve => { finishSubscription = resolve; }));
        await mount();
        onError.mock.calls[0][0]({ channel: '/meta/connect', error: 'RAW TRANSPORT' });
        finishSubscription({ id: 'late-alert-subscription', channel: '/event/Aegis_User_Alert__e' });
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('Live alert delivery is not confirmed');
        expect(element.shadowRoot.textContent).toContain('The live connection reported a problem');
        expect(element.shadowRoot.textContent).not.toContain('Live alert subscription established');
    });

    it('labels a failed saved-alert read and clears only that action failure after refresh', async () => {
        getOpenAlerts.mockRejectedValueOnce({ body: { message: 'Saved notice access is unavailable.' } });
        await mount();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent)
            .toBe('Saved alerts could not be loaded. Saved notice access is unavailable.');
        expect(element.shadowRoot.textContent).toContain('No alerts are currently displayed');
        onError.mock.calls[0][0]({ channel: '/meta/connect' });
        await flushUtilityUpdates();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Saved alerts could not be loaded');

        await clickButton(element, 'Refresh alerts');
        await flushUtilityUpdates();
        expect(element.shadowRoot.querySelector('.error')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('The live connection reported a problem');
    });

    it('retains a newer streamed notice and dismissed tombstones during explicit refresh', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        let finishRefresh;
        getOpenAlerts.mockImplementationOnce(() => new Promise(resolve => { finishRefresh = resolve; }));
        await clickButton(element, 'Refresh alerts');
        await clickButton(element, 'Dismiss');
        __emit(alertPayload({ Correlation_Id__c: 'CID-NEW' }));
        await flushUtilityUpdates();
        finishRefresh([canonicalAlert({ headline: 'Stale dismissed notice' })]);
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).not.toContain('Stale dismissed notice');
        await clickButton(element, 'View details');
        expect(getAlertDetails).toHaveBeenLastCalledWith({ correlationId: 'CID-NEW' });
    });

    it('uses a saved diagnosis upgrade for an already displayed correlation when streaming is unavailable', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        onError.mock.calls[0][0]({ subscription: '/event/Aegis_User_Alert__e' });
        getOpenAlerts.mockResolvedValueOnce([canonicalAlert({ notificationType: 'Diagnosed', headline: 'Saved diagnosis is now ready' })]);
        await clickButton(element, 'Refresh alerts');
        await flushUtilityUpdates();

        expect(element.shadowRoot.textContent).toContain('Saved diagnosis is now ready');
        expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
        expect(element.shadowRoot.textContent).toContain('The live alert connection reported a problem');
        expect(element.shadowRoot.querySelectorAll('.alert-strip')).toHaveLength(1);
    });

    it('preserves a newer same-correlation stream upgrade over a late saved refresh response', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        let finishRefresh;
        getOpenAlerts.mockImplementationOnce(() => new Promise(resolve => { finishRefresh = resolve; }));
        await clickButton(element, 'Refresh alerts');
        resolveAlert.mockResolvedValueOnce(canonicalAlert({ notificationType: 'Diagnosed', headline: 'New streamed diagnosis' }));
        __emit(alertPayload());
        await flushUtilityUpdates();
        finishRefresh([canonicalAlert({ headline: 'Stale saved diagnosis' })]);
        await flushUtilityUpdates();

        expect(element.shadowRoot.textContent).toContain('New streamed diagnosis');
        expect(element.shadowRoot.textContent).not.toContain('Stale saved diagnosis');
    });

    it('labels failed dismissal and help without exposing unknown technical errors', async () => {
        getAlertDetails.mockResolvedValueOnce({ errorLog: { correlationId: 'CID-1' }, canEscalate: true });
        dismissAlert.mockRejectedValueOnce(new Error('PRIVATE TECHNICAL DETAILS'));
        startHelpFromAlert.mockRejectedValueOnce(new Error('PRIVATE TECHNICAL DETAILS'));
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        await clickButton(element, 'Dismiss');
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Alert could not be dismissed. Try again');
        await clickButton(element, 'View details');
        await clickButton(element, 'Get Help');
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Diagnostic session could not be started. Try again');
        expect(element.shadowRoot.textContent).not.toContain('PRIVATE TECHNICAL DETAILS');
    });

    it('waits for Surface Config before subscriptions or startup notice reads', async () => {
        let resolveSettings;
        getSurfaceSettings.mockImplementation(() => new Promise(resolve => { resolveSettings = resolve; }));
        await mount();
        expect(subscribe).not.toHaveBeenCalled();
        expect(getOpenAlerts).not.toHaveBeenCalled();
        resolveSettings({ utilityEnabled: true });
        await flushUtilityUpdates();
        expect(subscribe).toHaveBeenCalledTimes(2);
        expect(getOpenAlerts).toHaveBeenCalledTimes(1);
    });

    it('honors disabled monitoring without removing manual assistance', async () => {
        getSurfaceSettings.mockResolvedValue({ utilityEnabled: false });
        await mount();
        expect(subscribe).not.toHaveBeenCalled();
        expect(getOpenAlerts).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('disabled by your administrator');
        expect(buttonLabels(element)).toContain('Capture Screen Issue');
    });

    it('fails closed when monitoring policy cannot be read', async () => {
        getSurfaceSettings.mockRejectedValue({ body: { message: 'Surface settings unavailable' } });
        await mount();
        expect(subscribe).not.toHaveBeenCalled();
        expect(getOpenAlerts).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Automatic monitoring could not start');
    });

    it('does not start monitoring after disconnecting while settings are pending', async () => {
        let resolveSettings;
        getSurfaceSettings.mockImplementation(() => new Promise(resolve => { resolveSettings = resolve; }));
        await mount();
        element.remove();
        resolveSettings({ utilityEnabled: true });
        await flushUtilityUpdates();
        expect(subscribe).not.toHaveBeenCalled();
        expect(getOpenAlerts).not.toHaveBeenCalled();
    });

    it('shows an alert addressed to the current user', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('I have identified the issue.');
        expect(updateUtility).toHaveBeenLastCalledWith('utility-aegis-alerts', {
            highlighted: true,
            icon: 'warning',
            iconVariant: 'error',
            label: 'Aegis Flow Alerts (1)'
        });
        expect(updatePanel).toHaveBeenLastCalledWith('utility-aegis-alerts', {
            icon: 'warning',
            label: 'Aegis Flow Alerts (1)'
        });
    });

    it('ignores an alert addressed to a different user', async () => {
        await mount();
        __emit(alertPayload({ Target_User_Id__c: '005000000000999AAA', Correlation_Id__c: 'OTHER' }));
        await flushUtilityUpdates();
        expect(resolveAlert).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
    });

    it('ignores an expired alert', async () => {
        resolveAlert.mockResolvedValue(canonicalAlert({ correlationId: 'EXPIRED', expiresAt: new Date(Date.now() - 3600000).toISOString() }));
        await mount();
        __emit(alertPayload({
            Correlation_Id__c: 'EXPIRED',
            Expires_At__c: new Date(Date.now() - 3600000).toISOString()
        }));
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
    });

    it('suppresses a duplicate correlation id', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        __emit(alertPayload());
        await flushUtilityUpdates();
        const matches = element.shadowRoot.textContent.match(/I have identified the issue\./g) || [];
        expect(matches.length).toBe(1);
    });

    it('upgrades Detected to Diagnosed in place rather than stacking a second card', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        resolveAlert.mockResolvedValue(canonicalAlert({
            notificationType: 'Diagnosed',
            headline: 'I found the issue, but it requires technical assistance.',
            actionAvailable: 'ESCALATE'
        }));
        __emit(alertPayload());
        await flushUtilityUpdates();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('requires technical assistance');
        expect(text).not.toContain('I have identified the issue.');
    });

    it('loads missed alerts on init for the mobile fallback path', async () => {
        getOpenAlerts.mockResolvedValue([
            canonicalAlert({
                correlationId: 'MISSED-1',
                headline: 'Missed while offline',
                shortMessage: 'Recovered from durable storage',
                severity: 'Medium',
                actionAvailable: 'VIEW'
            })
        ]);
        await mount();
        await flushUtilityUpdates();
        expect(getOpenAlerts).toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Missed while offline');
        expect(updateUtility).toHaveBeenLastCalledWith('utility-aegis-alerts', expect.objectContaining({ highlighted: true }));
    });

    it('does not auto-open the panel when policy disables it', async () => {
        await mount();
        await Promise.resolve();
        __emit(alertPayload({ Severity__c: 'Critical' }));
        await flushUtilityUpdates();
        expect(open).not.toHaveBeenCalled();
        expect(updateUtility).toHaveBeenLastCalledWith('utility-aegis-alerts', expect.objectContaining({ highlighted: true }));
    });

    it('auto-opens for a high severity alert when policy allows it', async () => {
        getAlertBehavior.mockResolvedValue({ autoOpenUtility: true, autoOpenMinimumSeverity: 'High' });
        resolveAlert.mockResolvedValue(canonicalAlert({ severity: 'Critical', correlationId: 'CRIT-1' }));
        await mount();
        await Promise.resolve();
        await Promise.resolve();
        __emit(alertPayload({ Severity__c: 'Critical', Correlation_Id__c: 'CRIT-1' }));
        await flushUtilityUpdates();
        expect(getInfo).toHaveBeenCalledWith('utility-aegis-alerts');
        expect(open).toHaveBeenCalledWith('utility-aegis-alerts');
    });

    it('does not interrupt for an alert below the severity threshold', async () => {
        getAlertBehavior.mockResolvedValue({ autoOpenUtility: true, autoOpenMinimumSeverity: 'High' });
        resolveAlert.mockResolvedValue(canonicalAlert({ severity: 'Medium', correlationId: 'MED-1' }));
        await mount();
        await Promise.resolve();
        await Promise.resolve();
        __emit(alertPayload({ Severity__c: 'Medium', Correlation_Id__c: 'MED-1' }));
        await flushUtilityUpdates();
        expect(open).not.toHaveBeenCalled();
        expect(updateUtility).toHaveBeenLastCalledWith('utility-aegis-alerts', expect.objectContaining({ highlighted: true }));
    });

    it('clears the utility highlight once the active alert is viewed', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        expect(updateUtility).toHaveBeenLastCalledWith('utility-aegis-alerts', expect.objectContaining({ highlighted: true }));

        await clickButton(element, 'View details');
        await flushUtilityUpdates();

        expect(updateUtility).toHaveBeenLastCalledWith('utility-aegis-alerts', expect.objectContaining({
            highlighted: false,
            label: 'Aegis Flow Alerts (1)'
        }));
    });

    it('resets the utility signal when the last alert is dismissed', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        await clickButton(element, 'Dismiss');
        await flushUtilityUpdates();

        expect(updateUtility).toHaveBeenLastCalledWith('utility-aegis-alerts', {
            highlighted: false,
            icon: 'screen',
            iconVariant: null,
            label: 'Aegis Flow Alerts'
        });
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
     * render {detail.errorLog.severity} directly, which threw
     * "Cannot read properties of undefined (reading 'severity')" and killed the panel.
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
        await flushUtilityUpdates();

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
                severity: 'Critical',
                sourceType: 'Flow',
                correlationId: 'FLOWINT-abc',
                normalizedMessage: 'A referenced value was empty.'
            },
            diagnosis: { Root_Cause__c: 'Missing AccountId', Recommended_Action__c: 'Map the field' },
            contexts: [],
            canEscalate: true
        });
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();

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
        await flushUtilityUpdates();
        await clickButton(element, 'View details');
        expect(element.shadowRoot.textContent).toBeDefined();
    });

    it('unsubscribes when removed from the DOM', async () => {
        await mount();
        await Promise.resolve();
        document.body.removeChild(element);
        expect(unsubscribe).toHaveBeenCalled();
    });

    it('captures a manual screen issue from the dormant state', async () => {
        await mount();
        const captureButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find(b => b.label === 'Capture Screen Issue');
        expect(captureButton).toBeDefined();
        captureButton.dispatchEvent(new CustomEvent('click'));
        await Promise.resolve();

        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        expect(textarea).not.toBeNull();
        textarea.dispatchEvent(new CustomEvent('change', { detail: { value: 'A validation message blocked my save.' } }));
        await Promise.resolve();

        const submitButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find(b => b.label === 'Submit');
        expect(submitButton).toBeDefined();
        submitButton.dispatchEvent(new CustomEvent('click'));
        await Promise.resolve();
        await Promise.resolve();

        expect(reportScreenIssue).toHaveBeenCalled();
        const args = reportScreenIssue.mock.calls[0][0];
        expect(args.description).toBe('A validation message blocked my save.');
    });

    it('uses authorized server content and severity instead of forged event fields', async () => {
        getAlertBehavior.mockResolvedValue({ autoOpenUtility: true, autoOpenMinimumSeverity: 'High' });
        resolveAlert.mockResolvedValue(canonicalAlert({ headline: 'Authorized summary', severity: 'Low' }));
        await mount();
        __emit(alertPayload({ Headline__c: 'FORGED emergency', Short_Message__c: 'Trust this forged instruction', Severity__c: 'Critical' }));
        await flushUtilityUpdates();
        expect(resolveAlert).toHaveBeenCalledWith({ correlationId: 'CID-1' });
        expect(element.shadowRoot.textContent).toContain('Authorized summary');
        expect(element.shadowRoot.textContent).not.toContain('FORGED');
        expect(open).not.toHaveBeenCalled();
    });

    it.each([null, { status: 'Dismissed' }, { status: 'Resolved' }, { expiresAt: 'invalid-date' }])(
        'does not display an ineligible canonical response: %p', async overrides => {
            resolveAlert.mockResolvedValue(overrides === null ? null : canonicalAlert(overrides));
            await mount();
            __emit(alertPayload({ Headline__c: 'FORGED' }));
            await flushUtilityUpdates();
            expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
            expect(element.shadowRoot.textContent).not.toContain('FORGED');
            expect(open).not.toHaveBeenCalled();
        }
    );

    it('fails closed when canonical resolution is unavailable', async () => {
        resolveAlert.mockRejectedValue(new Error('Network unavailable'));
        await mount();
        __emit(alertPayload({ Headline__c: 'FORGED' }));
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).not.toContain('FORGED');
        expect(element.shadowRoot.textContent).not.toContain('I have identified the issue.');
    });

    it('discards an older resolution after a newer diagnosis arrives', async () => {
        let resolveOld;
        resolveAlert.mockImplementationOnce(() => new Promise(resolve => { resolveOld = resolve; }));
        await mount();
        __emit(alertPayload());
        resolveAlert.mockResolvedValue(canonicalAlert({ notificationType: 'Diagnosed', headline: 'Latest diagnosis' }));
        __emit(alertPayload());
        await flushUtilityUpdates();
        resolveOld(canonicalAlert({ headline: 'Stale detected alert' }));
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('Latest diagnosis');
        expect(element.shadowRoot.textContent).not.toContain('Stale detected alert');
    });

    it('does not resurrect an alert when a lookup resolves after dismissal', async () => {
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        let resolvePending;
        resolveAlert.mockImplementationOnce(() => new Promise(resolve => { resolvePending = resolve; }));
        __emit(alertPayload());
        await clickButton(element, 'Dismiss');
        resolvePending(canonicalAlert({ headline: 'Stale pending diagnosis' }));
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).not.toContain('Stale pending diagnosis');
        expect(element.shadowRoot.querySelector('.alert-strip')).toBeNull();
    });

    it('retains an alert when server dismissal fails', async () => {
        dismissAlert.mockRejectedValueOnce({ body: { message: 'Please retry dismissal' } });
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        await clickButton(element, 'Dismiss');
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('I have identified the issue.');
    });

    it('ignores a pending response after the component is removed', async () => {
        let resolvePending;
        resolveAlert.mockImplementationOnce(() => new Promise(resolve => { resolvePending = resolve; }));
        await mount();
        __emit(alertPayload());
        document.body.removeChild(element);
        updateUtility.mockClear();
        resolvePending(canonicalAlert());
        await flushUtilityUpdates();
        expect(updateUtility).not.toHaveBeenCalled();
    });

    it('does not resurrect a rejected notice from a late initial list response', async () => {
        let finishInitial;
        getOpenAlerts.mockImplementationOnce(() => new Promise(resolve => { finishInitial = resolve; }));
        resolveAlert.mockResolvedValue(null);
        await mount();
        __emit(alertPayload());
        await flushUtilityUpdates();
        finishInitial([canonicalAlert()]);
        await flushUtilityUpdates();
        expect(element.shadowRoot.querySelector('.alert-strip')).toBeNull();
        // A later valid server resolution can represent a newly eligible notice.
        resolveAlert.mockResolvedValue(canonicalAlert());
        __emit(alertPayload());
        await flushUtilityUpdates();
        expect(element.shadowRoot.textContent).toContain('I have identified the issue.');
    });

    it('resolves a captured Flow error without displaying raw event text', async () => {
        resolveAlert.mockResolvedValue(null);
        await mount();
        __emitOn('/event/FlowExecutionErrorEvent', {
            UserId: USER_ID, InterviewGuid: 'policy-suppressed', ErrorMessage: 'RAW EVENT MUST NOT DISPLAY'
        });
        await flushUtilityUpdates();
        expect(resolveAlert).toHaveBeenCalledWith({ correlationId: 'FLOWINT-test-guid' });
        expect(element.shadowRoot.textContent).not.toContain('RAW EVENT MUST NOT DISPLAY');
        expect(element.shadowRoot.querySelector('.alert-strip')).toBeNull();
    });

    it.each([
        ['Sales record', { attributes: { recordId: '006000000000001', objectApiName: 'Opportunity' } }, '006000000000001', 'Opportunity'],
        ['Service record', { attributes: { recordId: '500000000000001', objectApiName: 'Case' } }, '500000000000001', 'Case'],
        ['Custom object', { attributes: { recordId: 'a01000000000001', objectApiName: 'Example_Work_Item__c' } }, 'a01000000000001', 'Example_Work_Item__c'],
        ['Namespaced page state', { state: { c__recordId: '500000000000002', c__objectApiName: 'Case' } }, '500000000000002', 'Case'],
        ['App page', { attributes: { apiName: 'AEIR_Admin' } }, null, null]
    ])('captures context from %s', async (label, pageReference, recordId, objectApiName) => {
        await mount();
        CurrentPageReference.emit(pageReference);
        await flushUtilityUpdates();
        await clickButton(element, 'Capture Screen Issue');
        element.shadowRoot.querySelector('lightning-textarea').dispatchEvent(new CustomEvent('change', { detail: { value: 'Context test' } }));
        await flushUtilityUpdates();
        await clickButton(element, 'Submit');
        expect(reportScreenIssue).toHaveBeenCalledWith(expect.objectContaining({ recordId, objectApiName }));
    });
});
