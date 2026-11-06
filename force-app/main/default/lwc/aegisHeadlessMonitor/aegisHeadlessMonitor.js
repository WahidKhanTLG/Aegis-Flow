import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import USER_ID from '@salesforce/user/Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { EnclosingUtilityId, getInfo, open, updatePanel, updateUtility } from 'lightning/platformUtilityBarApi';
import getOpenAlerts from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getOpenAlerts';
import resolveAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.resolveAlert';
import getAlertDetails from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';
import dismissAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.dismissAlert';
import startHelpFromAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.startHelpFromAlert';
import escalateAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.escalateAlert';
import getAlertBehavior from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertBehavior';
import getAlertChannel from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertChannel';
import getFlowErrorChannel from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getFlowErrorChannel';
import getSurfaceSettings from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getSurfaceSettings';
import captureFlowError from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.captureFlowError';
import reportScreenIssue from '@salesforce/apex/AEIR_UiSaveErrorController.reportScreenIssue';

const DEFAULT_ALERT_CHANNEL = '/event/Aegis_User_Alert__e';
// Optional live Flow source; availability depends on the org and current user.
const DEFAULT_FLOW_ERROR_CHANNEL = '/event/FlowExecutionErrorEvent';
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
    behavior = { autoOpenUtility: false, autoOpenMinimumSeverity: 'High' };
    hasUnreadAlerts = false;
    showCaptureForm = false;
    captureDescription = '';
    captureSubmitting = false;
    isConnectedToAlerts = false;
    resolutionSequence = 0;
    pendingResolutions = new Map();
    dismissedCorrelations = new Set();
    ineligibleCorrelations = new Set();
    monitoringState = 'loading';
    alertChannel = DEFAULT_ALERT_CHANNEL;
    flowErrorChannel = DEFAULT_FLOW_ERROR_CHANNEL;
    alertConnectionState = 'connecting';
    alertStreamWarning = false;
    transportWarning = false;
    flowWarning;
    isRefreshingAlerts = false;
    savedAlertsState = 'loading';
    actionErrorOrigin;

    @wire(EnclosingUtilityId)
    wiredUtilityId(utilityId) {
        this.utilityId = utilityId;
        if (utilityId) this.syncUtilitySignal();
    }

    connectedCallback() {
        this.isConnectedToAlerts = true;
        // Resolve policy before any event subscription or durable-notice request.
        // A rejected/missing policy fails closed; manual assistance remains available.
        getSurfaceSettings().then(settings => {
            if (!this.isConnectedToAlerts) return;
            this.monitoringState = settings && settings.utilityEnabled === true ? 'enabled' : 'disabled';
            if (!this.monitoringEnabled) return;
            this.loadBehavior();
            this.registerStreamingErrorListener();
            this.subscribeToAlerts();
            this.subscribeToFlowErrors();
            this.loadMissedAlerts();
        }).catch(error => {
            if (!this.isConnectedToAlerts) return;
            this.monitoringState = 'error';
            this.setActionError('Monitoring settings could not be loaded', error);
        });
    }
    disconnectedCallback() {
        this.isConnectedToAlerts = false;
        this.pendingResolutions.clear();
        if (this.subscription) unsubscribe(this.subscription, () => {});
        if (this.flowErrorSubscription) unsubscribe(this.flowErrorSubscription, () => {});
    }
    get hasAlerts() { return this.alerts.length > 0 && this.activeAlert; }
    get monitoringEnabled() { return this.monitoringState === 'enabled'; }
    get monitoringMessage() {
        if (this.monitoringState === 'loading') return 'Checking automatic monitoring settings…';
        if (this.monitoringState === 'disabled') return 'Automatic utility monitoring is disabled by your administrator. Manual assistance remains available.';
        if (this.monitoringState === 'error') return 'Automatic monitoring could not start. Check your access or reload this app. Manual assistance remains available.';
        if (this.alertConnectionState === 'unavailable' || this.alertStreamWarning || this.transportWarning) {
            return 'Automatic monitoring is enabled by your administrator. Live alert delivery is not confirmed.';
        }
        if (this.alertConnectionState === 'connecting') return 'Automatic monitoring is enabled by your administrator. Connecting to live alert updates…';
        return 'Live alert subscription established. Only authorized active notices are displayed.';
    }
    get connectionWarning() {
        if (this.alertConnectionState === 'unavailable') {
            return 'Live alert updates are unavailable. Select Refresh alerts to check saved notices, or reload this app to reconnect.';
        }
        if (this.alertStreamWarning) return 'The live alert connection reported a problem. Select Refresh alerts to check saved notices, or reload this app to reconnect.';
        return this.transportWarning
            ? 'The live connection reported a problem. Select Refresh alerts to check saved notices, or reload this app to reconnect.'
            : '';
    }
    get optionalFlowWarning() {
        if (this.flowWarning === 'capture') return 'A live Flow error could not be captured. Refresh alerts to check saved notices; report a screen issue if you still need help.';
        return this.flowWarning === 'subscription'
            ? 'Live Flow error capture is unavailable. Refresh alerts checks saved notices; reload this app to try the Flow connection again.'
            : '';
    }
    get savedAlertsMessage() {
        if (this.isRefreshingAlerts) return 'Loading saved alerts…';
        return this.savedAlertsState === 'loaded' ? 'Saved alerts refreshed.' : '';
    }
    get emptyAlertsMessage() {
        if (this.monitoringEnabled && this.isRefreshingAlerts) return 'Checking saved alerts…';
        if (this.monitoringEnabled && this.savedAlertsState === 'error') return 'No alerts are currently displayed. Select Refresh alerts to check again.';
        return 'No active alerts. Get Help remains available when a user needs diagnostic assistance.';
    }
    get captureSubmitDisabled() { return this.captureSubmitting || !this.captureDescription || !this.captureDescription.trim(); }
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
            if (!this.isConnectedToAlerts || !this.monitoringEnabled) return;
            // EMP errors are global to the browser. Ignore only an unambiguously
            // unrelated structured event channel, never an unknown transport error.
            const channels = [...new Set([
                error && error.subscription, error && error.channel,
                error && error.data && error.data.subscription,
                error && error.data && error.data.channel
            ].filter(channel => typeof channel === 'string' && /^\/(event|data|topic|u)\//.test(channel)))];
            const channel = channels.length === 1 ? channels[0] : null;
            if (channel === this.flowErrorChannel) this.flowWarning = 'subscription';
            else if (channel === this.alertChannel) this.alertStreamWarning = true;
            else if (!channel) this.transportWarning = true;
        });
    }
    subscribeToAlerts() {
        getAlertChannel()
            .catch(() => DEFAULT_ALERT_CHANNEL)
            .then(channel => {
                this.alertChannel = channel || DEFAULT_ALERT_CHANNEL;
                return subscribe(this.alertChannel, -1, message => this.handleStreamingMessage(message));
            })
            .then(response => {
                if (this.isConnectedToAlerts) {
                    this.subscription = response;
                    this.alertConnectionState = 'subscribed';
                }
                else unsubscribe(response, () => {});
            })
            .catch(() => {
                if (this.isConnectedToAlerts) this.alertConnectionState = 'unavailable';
            });
    }
    /**
     * Real-time Flow failures. Salesforce publishes FlowExecutionErrorEvent the moment an
     * element errors, so a user watching their own save is told immediately rather than
     * waiting for the scheduled reconciler. Requires access to the event; if the
     * subscription fails, show a separate status and retain saved-notice refresh.
     */
    subscribeToFlowErrors() {
        getFlowErrorChannel()
            .catch(() => DEFAULT_FLOW_ERROR_CHANNEL)
            .then(channel => {
                this.flowErrorChannel = channel || DEFAULT_FLOW_ERROR_CHANNEL;
                return subscribe(this.flowErrorChannel, -1, message => this.handleFlowError(message));
            })
            .then(response => {
                if (this.isConnectedToAlerts) this.flowErrorSubscription = response;
                else unsubscribe(response, () => {});
            })
            .catch(() => {
                if (this.isConnectedToAlerts) this.flowWarning = 'subscription';
            });
    }

    handleFlowError(message) {
        if (!this.isConnectedToAlerts || !this.monitoringEnabled) return;
        const payload = message && message.data ? message.data.payload : null;
        if (!payload) return;
        // Only the user whose work actually failed should be interrupted.
        const affected = payload.UserId || payload.InterviewStartedById;
        if (affected && USER_ID && !USER_ID.startsWith(String(affected).substring(0, 15))) return;

        captureFlowError({ payloadJson: JSON.stringify(payload) })
            .then(correlationId => this.resolveStreamingAlert(correlationId))
            .catch(() => {
                if (this.isConnectedToAlerts) this.flowWarning = 'capture';
            });
    }

    loadMissedAlerts() {
        if (!this.isConnectedToAlerts || !this.monitoringEnabled || this.isRefreshingAlerts) return Promise.resolve();
        this.isRefreshingAlerts = true;
        const alertsAtRequest = new Map(this.alerts.map(alert => [alert.correlationId, alert]));
        return getOpenAlerts().then(result => {
            if (!this.isConnectedToAlerts || !this.monitoringEnabled) return;
            // A stream response may have arrived while the initial request was pending.
            // Preserve that newer state and do not resurrect a locally dismissed notice.
            const loaded = Array.isArray(result) ? result.filter(alert => this.isUsableAlert(alert) && !this.ineligibleCorrelations.has(alert.correlationId)) : [];
            const loadedById = new Map(loaded.map(alert => [alert.correlationId, alert]));
            const currentIds = new Set(this.alerts.map(alert => alert.correlationId));
            // Refresh can deliver a saved diagnosis upgrade when streaming is down.
            // Preserve any DTO replaced by a newer stream response during this read.
            const current = this.alerts.map(alert => alertsAtRequest.get(alert.correlationId) === alert && loadedById.has(alert.correlationId)
                ? loadedById.get(alert.correlationId) : alert);
            this.alerts = [...current, ...loaded.filter(alert => !currentIds.has(alert.correlationId))].slice(0, 20);
            this.activeAlert = this.alerts.length ? this.alerts[0] : null;
            this.hasUnreadAlerts = this.alerts.length > 0;
            this.savedAlertsState = 'loaded';
            this.clearActionError('Saved alerts could not be loaded');
            this.syncUtilitySignal();
        }).catch(error => {
            if (!this.isConnectedToAlerts) return;
            this.savedAlertsState = 'error';
            this.setActionError('Saved alerts could not be loaded', error);
        }).finally(() => {
            this.isRefreshingAlerts = false;
        });
    }
    refreshAlerts() { return this.loadMissedAlerts(); }
    handleStreamingMessage(message) {
        if (!this.isConnectedToAlerts || !this.monitoringEnabled) return;
        const payload = message && message.data ? message.data.payload : null;
        if (!payload || payload.Target_User_Id__c !== USER_ID || !payload.Correlation_Id__c) return;
        // This callback belongs to the actual Aegis subscription. A later valid
        // wake-up demonstrates that channel recovered, not that every stream did.
        // Keep unknown transport, optional Flow and action failures independent.
        this.alertStreamWarning = false;
        this.resolveStreamingAlert(payload.Correlation_Id__c);
    }
    resolveStreamingAlert(correlationId) {
        if (!this.isConnectedToAlerts || !this.monitoringEnabled || !correlationId || this.dismissedCorrelations.has(correlationId)) return Promise.resolve();
        const sequence = ++this.resolutionSequence;
        this.pendingResolutions.set(correlationId, sequence);
        return resolveAlert({ correlationId })
            .then(alert => {
                if (!this.isConnectedToAlerts || this.pendingResolutions.get(correlationId) !== sequence) return;
                if (!this.isUsableAlert(alert) || alert.correlationId !== correlationId) {
                    // A late initial list must not resurrect a notice that the server
                    // just rejected. A later valid resolution can clear this tombstone.
                    this.ineligibleCorrelations.add(correlationId);
                    if (this.ineligibleCorrelations.size > 100) this.ineligibleCorrelations.delete(this.ineligibleCorrelations.values().next().value);
                    this.removeAlert(correlationId);
                    return;
                }
                this.ineligibleCorrelations.delete(correlationId);
                this.showCanonicalAlert(alert);
            })
            .catch(() => {
                // A transport failure or unresolvable hint must never display event text.
                // Durable alerts remain available on the next successful refresh.
            })
            .finally(() => {
                if (this.pendingResolutions.get(correlationId) === sequence) this.pendingResolutions.delete(correlationId);
            });
    }
    isUsableAlert(alert) {
        return !!(alert && alert.correlationId && !this.dismissedCorrelations.has(alert.correlationId)
            && (alert.status === 'New' || alert.status === 'Viewed')
            && alert.expiresAt && !this.isExpired(alert.expiresAt));
    }
    showCanonicalAlert(alert) {
        // A later event for the same correlation id is a status upgrade (Detected -> Diagnosed),
        // not a duplicate. Replace in place so the spinner resolves instead of stacking a card.
        const existing = this.alerts.find(item => item.correlationId === alert.correlationId);
        const isUpgrade = !!existing;
        if (existing && ['headline', 'shortMessage', 'severity', 'notificationType', 'actionAvailable']
            .every(field => existing[field] === alert[field])) return;
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
    isExpired(value) { return !value || !Number.isFinite(new Date(value).getTime()) || new Date(value).getTime() <= Date.now(); }
    removeAlert(correlationId) {
        this.alerts = this.alerts.filter(item => item.correlationId !== correlationId);
        if (this.activeAlert && this.activeAlert.correlationId === correlationId) {
            this.activeAlert = this.alerts.length ? this.alerts[0] : null;
            this.detail = null;
            this.showDetails = false;
        }
        this.hasUnreadAlerts = this.alerts.length > 0;
        this.syncUtilitySignal();
    }
    openDetails() {
        if (!this.activeAlert) return;
        this.showDetails = true;
        this.hasUnreadAlerts = false;
        this.syncUtilitySignal();
        this.isLoading = true;
        this.clearActionError('Alert details could not be loaded');
        getAlertDetails({ correlationId: this.activeAlert.correlationId })
            .then(result => { this.detail = result; })
            .catch(error => { this.setActionError('Alert details could not be loaded', error); })
            .finally(() => { this.isLoading = false; });
    }
    closeDetails() { this.showDetails = false; }
    dismissActive() {
        if (!this.activeAlert) return;
        const cid = this.activeAlert.correlationId;
        dismissAlert({ correlationId: cid }).then(() => {
            this.clearActionError('Alert could not be dismissed');
            this.dismissedCorrelations.add(cid);
            this.pendingResolutions.delete(cid);
            this.removeAlert(cid);
        }).catch(error => { this.setActionError('Alert could not be dismissed', error); });
    }
    startHelp() {
        if (!this.activeAlert) return;
        startHelpFromAlert({ correlationId: this.activeAlert.correlationId, contextJson: JSON.stringify(this.buildClientContext()), userDescription: 'User requested help from a proactive Aegis Flow notification.' })
            .then(result => {
                this.clearActionError('Diagnostic session could not be started');
                this.toast('Diagnostic session created', result.message, 'success');
            })
            .catch(error => { this.setActionError('Diagnostic session could not be started', error); });
    }
    startManualHelp() {
        this.toast('Aegis Flow Get Help', 'Open the Aegis Flow Diagnostic Assistant utility to create a manual diagnostic session.', 'info');
    }
    openCaptureForm() { this.showCaptureForm = true; }
    closeCaptureForm() { this.showCaptureForm = false; this.captureDescription = ''; }
    handleCaptureDescription(event) { this.captureDescription = event && event.detail ? event.detail.value : ''; }
    submitScreenCapture() {
        if (this.captureSubmitting || !this.captureDescription || !this.captureDescription.trim()) return;
        this.captureSubmitting = true;
        const context = this.buildClientContext();
        reportScreenIssue({
            description: this.captureDescription.trim(),
            pageUrl: context.pageUrl,
            recordId: context.recordId,
            objectApiName: context.objectApiName,
            userAgent: context.userAgent
        })
            .then(result => {
                if (result.success) {
                    this.clearActionError('Screen issue could not be captured');
                    this.toast('Issue captured', `Aegis recorded this screen issue. Reference: ${result.correlationId}`, 'success');
                } else {
                    this.toast('Capture failed', result.message || 'Aegis could not record the issue.', 'error');
                }
                this.closeCaptureForm();
            })
            .catch(error => {
                this.setActionError('Screen issue could not be captured', error);
            })
            .finally(() => {
                this.captureSubmitting = false;
            });
    }
    escalate() {
        if (!this.activeAlert) return;
        escalateAlert({ correlationId: this.activeAlert.correlationId })
            .then(result => {
                this.clearActionError('Escalation could not be created');
                this.toast('Escalation created', result.subject, 'success');
            })
            .catch(error => { this.setActionError('Escalation could not be created', error); });
    }
    buildClientContext() {
        const pageReference = this.currentPageReference || {};
        const attributes = pageReference.attributes || {};
        const state = pageReference.state || {};
        return {
            pageUrl: window.location.href,
            pageReference: this.currentPageReference,
            recordId: attributes.recordId || state.recordId || state.c__recordId || state.recordId__c || null,
            objectApiName: attributes.objectApiName || state.objectApiName || state.c__objectApiName || state.objectApiName__c || null,
            userAgent: navigator.userAgent,
            timestamp: new Date().toISOString()
        };
    }
    toast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
    toastVariant(severity) { return severity === 'Critical' || severity === 'High' ? 'warning' : 'info'; }
    setActionError(origin, error) {
        this.actionErrorOrigin = origin;
        this.error = `${origin}. ${this.normalizeError(error)}`;
    }
    clearActionError(origin) {
        if (this.actionErrorOrigin !== origin) return;
        this.actionErrorOrigin = null;
        this.error = null;
    }
    normalizeError(error) { return error && error.body && error.body.message ? error.body.message : 'Try again or contact your administrator.'; }

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
