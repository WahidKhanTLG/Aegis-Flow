import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import USER_ID from '@salesforce/user/Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { EnclosingUtilityId, getInfo, open, updatePanel, updateUtility } from 'lightning/platformUtilityBarApi';
import getOpenAlerts from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getOpenAlerts';
import getAlertDetails from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';
import dismissAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.dismissAlert';
import startHelpFromAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.startHelpFromAlert';
import escalateAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.escalateAlert';
import getAlertBehavior from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertBehavior';
import captureFlowError from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.captureFlowError';

const CHANNEL = '/event/Aegis_User_Alert__e';
// Fires the instant a Flow element fails, with no fault path and no polling delay.
const FLOW_ERROR_CHANNEL = '/event/FlowExecutionErrorEvent';
const MAX_CACHE = 50;
const UTILITY_IDLE_LABEL = 'Aegis Flow Alerts';
const UTILITY_IDLE_ICON = 'screen';
const UTILITY_ALERT_ICON = 'warning';

export default class AegisHeadlessMonitor extends LightningElement {
    @wire(CurrentPageReference) currentPageReference;
    utilityId;
    subscription;
    flowErrorSubscription;
    alerts = [];
    activeAlert;
    detail;
    showDetails = false;
    isLoading = false;
    error;
    seen = [];
    behavior = { autoOpenUtility: false, autoOpenMinimumSeverity: 'High' };
    hasUnreadAlerts = false;

    @wire(EnclosingUtilityId)
    wiredUtilityId(utilityId) {
        this.utilityId = utilityId;
        if (utilityId) this.syncUtilitySignal();
    }

    connectedCallback() {
        this.loadBehavior();
        this.registerStreamingErrorListener();
        this.subscribeToAlerts();
        this.subscribeToFlowErrors();
        this.loadMissedAlerts();
    }
    disconnectedCallback() {
        if (this.subscription) unsubscribe(this.subscription, () => {});
        if (this.flowErrorSubscription) unsubscribe(this.flowErrorSubscription, () => {});
    }
    get hasAlerts() { return this.alerts.length > 0 && this.activeAlert; }
    get detailTitle() { return this.activeAlert ? this.activeAlert.headline : 'Aegis Flow diagnostic'; }
    get hasDiagnosis() { return !!(this.detail && this.detail.diagnosis); }

    /*
     * Flattened, null-safe accessors for everything the panel renders.
     *
     * LWC templates do not optional-chain. `{detail.errorLog.severity}` compiles to a
     * plain member access, so the instant `errorLog` is null the component throws
     * "Cannot read properties of undefined (reading 'severity')" and the whole panel
     * fails to render.
     *
     * `errorLog` is legitimately null: `User_Notification__c.Error_Log__c` is a lookup with
     * deleteConstraint = SetNull, so the retention purge removes the Error Log and leaves the
     * notification pointing at nothing. The alert is still real and the user must still be
     * able to read and dismiss it.
     */
    get errorLog() { return (this.detail && this.detail.errorLog) || null; }
    get hasErrorLog() { return !!this.errorLog; }
    /** A live alert whose evidence has been purged - render the fallback, not a crash. */
    get isEvidencePurged() { return !!(this.detail && !this.detail.errorLog); }

    get errorSeverity() { return this.errorLog ? this.errorLog.severity : ''; }
    get errorSource() { return this.errorLog ? this.errorLog.sourceType : ''; }
    get errorReference() { return this.errorLog ? this.errorLog.correlationId : ''; }
    get errorMessage() { return this.errorLog ? this.errorLog.normalizedMessage : ''; }

    get diagnosisRootCause() { return this.hasDiagnosis ? this.detail.diagnosis.Root_Cause__c : ''; }
    get diagnosisRecommendedAction() { return this.hasDiagnosis ? this.detail.diagnosis.Recommended_Action__c : ''; }

    /** Falls back to the alert itself when the Error Log is gone. */
    get alertSeverity() {
        if (this.detail && this.detail.alert && this.detail.alert.severity) return this.detail.alert.severity;
        return this.activeAlert && this.activeAlert.severity ? this.activeAlert.severity : 'Medium';
    }
    get alertReference() {
        if (this.detail && this.detail.alert && this.detail.alert.correlationId) return this.detail.alert.correlationId;
        return this.activeAlert ? this.activeAlert.correlationId : '';
    }
    get alertMessage() {
        if (this.detail && this.detail.alert && this.detail.alert.shortMessage) return this.detail.alert.shortMessage;
        return this.activeAlert && this.activeAlert.shortMessage
            ? this.activeAlert.shortMessage
            : 'Aegis Flow recorded this issue.';
    }

    /**
     * Escalating needs an Error Log to build the diagnostic package. Apex already rejects the
     * attempt; hiding the buttons stops the user hitting an error they cannot act on.
     */
    get canEscalate() { return !!(this.detail && this.detail.canEscalate && this.errorLog); }
    get severityClass() {
        const severity = this.activeAlert && this.activeAlert.severity ? this.activeAlert.severity.toLowerCase() : 'medium';
        return `severity-dot ${severity}`;
    }
    loadBehavior() {
        getAlertBehavior()
            .then(b => { if (b) this.behavior = b; })
            .catch(() => { /* conservative default: never auto-open */ });
    }

    /**
     * Opening the panel interrupts whatever the user is doing, so it is gated on policy
     * and severity. Anything below the threshold stays a passive toast.
     */
    autoOpenIfWarranted(alert) {
        if (!this.behavior || this.behavior.autoOpenUtility !== true) return;
        const rank = { Low: 1, Medium: 2, High: 3, Critical: 4 };
        const threshold = rank[this.behavior.autoOpenMinimumSeverity] || 3;
        if ((rank[alert.severity] || 2) < threshold) return;
        if (!this.utilityId) return;
        getInfo(this.utilityId)
            .then(info => {
                if (info && info.utilityVisible === true) return true;
                return open(this.utilityId);
            })
            .catch(() => { /* not hosted in a utility bar; the toast already fired */ });
    }

    registerStreamingErrorListener() {
        onError(error => {
            this.error = this.normalizeError(error);
        });
    }
    subscribeToAlerts() {
        subscribe(CHANNEL, -1, message => this.handleStreamingMessage(message)).then(response => {
            this.subscription = response;
        }).catch(error => {
            this.error = this.normalizeError(error);
        });
    }
    /**
     * Real-time Flow failures. Salesforce publishes FlowExecutionErrorEvent the moment an
     * element errors, so a user watching their own save is told immediately rather than
     * waiting for the scheduled reconciler. Requires access to the event; if the
     * subscription is refused we simply fall back to the poll.
     */
    subscribeToFlowErrors() {
        subscribe(FLOW_ERROR_CHANNEL, -1, message => this.handleFlowError(message))
            .then(response => { this.flowErrorSubscription = response; })
            .catch(() => {
                // No access to the event stream. The scheduled monitor still covers it.
            });
    }

    handleFlowError(message) {
        const payload = message && message.data ? message.data.payload : null;
        if (!payload) return;
        // Only the user whose work actually failed should be interrupted.
        const affected = payload.UserId || payload.InterviewStartedById;
        if (affected && USER_ID && !USER_ID.startsWith(String(affected).substring(0, 15))) return;

        captureFlowError({ payloadJson: JSON.stringify(payload) })
            .then(correlationId => {
                if (!correlationId || this.isDuplicate(correlationId)) return;
                const alert = {
                    correlationId,
                    headline: 'I have identified the issue.',
                    shortMessage: payload.ErrorMessage || 'A background process failed.',
                    severity: 'High',
                    notificationType: 'Detected',
                    actionAvailable: 'VIEW',
                    errorLogId: null
                };
                this.alerts = [alert, ...this.alerts].slice(0, 20);
                this.activeAlert = alert;
                this.hasUnreadAlerts = true;
                this.syncUtilitySignal();
                this.dispatchEvent(new ShowToastEvent({
                    title: alert.headline,
                    message: `${payload.FlowApiName || 'A process'} failed at ${payload.ElementApiName || 'an element'}.`,
                    variant: 'warning',
                    mode: 'sticky'
                }));
                this.autoOpenIfWarranted(alert);
            })
            .catch(() => { /* capture failed; the scheduled monitor is the backstop */ });
    }

    loadMissedAlerts() {
        getOpenAlerts().then(result => {
            this.alerts = Array.isArray(result) ? result : [];
            this.activeAlert = this.alerts.length ? this.alerts[0] : null;
            this.hasUnreadAlerts = this.alerts.length > 0;
            this.syncUtilitySignal();
        }).catch(error => {
            this.error = this.normalizeError(error);
        });
    }
    handleStreamingMessage(message) {
        const payload = message && message.data ? message.data.payload : null;
        if (!payload || payload.Target_User_Id__c !== USER_ID) return;
        if (this.isExpired(payload.Expires_At__c)) return;
        // A later event for the same correlation id is a status upgrade (Detected -> Diagnosed),
        // not a duplicate. Replace in place so the spinner resolves instead of stacking a card.
        const isUpgrade = this.alerts.some(item => item.correlationId === payload.Correlation_Id__c);
        if (!isUpgrade && this.isDuplicate(payload.Correlation_Id__c)) return;
        const alert = {
            correlationId: payload.Correlation_Id__c,
            errorLogId: payload.Error_Log_Id__c,
            headline: payload.Headline__c || 'I have identified the issue.',
            shortMessage: payload.Short_Message__c,
            severity: payload.Severity__c || 'Medium',
            notificationType: payload.Notification_Type__c || 'Detected',
            actionAvailable: payload.Action_Available__c || 'VIEW',
            expiresAt: payload.Expires_At__c
        };
        this.alerts = isUpgrade
            ? this.alerts.map(item => (item.correlationId === alert.correlationId ? alert : item))
            : [alert, ...this.alerts].slice(0, 20);
        this.activeAlert = alert;
        this.hasUnreadAlerts = true;
        this.syncUtilitySignal();
        if (isUpgrade && this.showDetails) this.openDetails();
        this.dispatchEvent(new ShowToastEvent({ title: alert.headline, message: alert.shortMessage, variant: this.toastVariant(alert.severity), mode: 'dismissable' }));
        this.autoOpenIfWarranted(alert);
    }
    isExpired(value) { return value ? new Date(value).getTime() < Date.now() : false; }
    isDuplicate(correlationId) {
        if (!correlationId) return true;
        if (this.seen.includes(correlationId)) return true;
        this.seen = [correlationId, ...this.seen].slice(0, MAX_CACHE);
        return false;
    }
    openDetails() {
        if (!this.activeAlert) return;
        this.showDetails = true;
        this.hasUnreadAlerts = false;
        this.syncUtilitySignal();
        this.isLoading = true;
        this.error = null;
        getAlertDetails({ correlationId: this.activeAlert.correlationId })
            .then(result => { this.detail = result; })
            .catch(error => { this.error = this.normalizeError(error); })
            .finally(() => { this.isLoading = false; });
    }
    closeDetails() { this.showDetails = false; }
    dismissActive() {
        if (!this.activeAlert) return;
        const cid = this.activeAlert.correlationId;
        dismissAlert({ correlationId: cid }).finally(() => {
            this.alerts = this.alerts.filter(item => item.correlationId !== cid);
            this.activeAlert = this.alerts.length ? this.alerts[0] : null;
            this.hasUnreadAlerts = this.alerts.length > 0;
            this.syncUtilitySignal();
            if (!this.activeAlert) this.showDetails = false;
        });
    }
    startHelp() {
        if (!this.activeAlert) return;
        startHelpFromAlert({ correlationId: this.activeAlert.correlationId, contextJson: JSON.stringify(this.buildClientContext()), userDescription: 'User requested help from a proactive Aegis Flow notification.' })
            .then(result => { this.toast('Diagnostic session created', result.message, 'success'); })
            .catch(error => { this.error = this.normalizeError(error); });
    }
    startManualHelp() {
        this.toast('Aegis Flow Get Help', 'Open the Aegis Flow Diagnostic Assistant utility to create a manual diagnostic session.', 'info');
    }
    escalate() {
        if (!this.activeAlert) return;
        escalateAlert({ correlationId: this.activeAlert.correlationId })
            .then(result => { this.toast('Escalation created', result.subject, 'success'); })
            .catch(error => { this.error = this.normalizeError(error); });
    }
    buildClientContext() {
        return { pageUrl: window.location.href, pageReference: this.currentPageReference, userAgent: navigator.userAgent, timestamp: new Date().toISOString() };
    }
    toast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
    toastVariant(severity) { return severity === 'Critical' || severity === 'High' ? 'warning' : 'info'; }
    normalizeError(error) { return error && error.body && error.body.message ? error.body.message : 'Aegis Flow could not complete this operation.'; }

    /**
     * The platform utility APIs only work when this component is hosted inside a utility
     * bar. Record/home placements still render, so every runtime signal is best effort.
     */
    syncUtilitySignal() {
        if (!this.utilityId) return;
        const count = this.alerts.length;
        const highlighted = this.hasUnreadAlerts && count > 0;
        const label = count > 0 ? `${UTILITY_IDLE_LABEL} (${Math.min(count, 99)})` : UTILITY_IDLE_LABEL;
        const icon = highlighted ? UTILITY_ALERT_ICON : UTILITY_IDLE_ICON;

        updateUtility(this.utilityId, {
            highlighted,
            icon,
            iconVariant: highlighted ? 'error' : null,
            label
        }).catch(() => {});
        updatePanel(this.utilityId, { icon, label }).catch(() => {});
    }
}
