import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import AEGIS_LOGO from '@salesforce/resourceUrl/AegisFlowLogo';
import createSession from '@salesforce/apex/AEIR_HelpMeController.createSession';
import diagnoseSession from '@salesforce/apex/AEIR_HelpMeController.diagnoseSession';
import escalateSession from '@salesforce/apex/AEIR_HelpMeController.escalateSession';

export default class HelpMeAgentUtility extends LightningElement {
    @wire(CurrentPageReference) currentPageReference;
    logoUrl = AEGIS_LOGO;
    sessionId;
    correlationId;
    message;
    agentSummary;
    recommendedAction;
    error;
    isLoading = false;
    description = '';
    issueType = 'Unknown';
    requestVersion = 0;
    reportSubmitted = false;
    confirmed = false;

    get issueTypeOptions() {
        return [
            { label: 'Save error', value: 'Save Error' },
            { label: 'Process failed', value: 'Process Failed' },
            { label: 'Navigation help', value: 'Navigation Help' },
            { label: 'Data question', value: 'Data Question' },
            { label: 'Report an issue', value: 'Report Issue' },
            { label: 'Not sure', value: 'Unknown' }
        ];
    }
    get isStartDisabled() { return this.isLoading || !this.description || !this.description.trim(); }
    get diagnosisStepClass() { return this.agentSummary ? 'progress-item complete' : 'progress-item active'; }
    get resolutionStepClass() { return this.agentSummary ? 'progress-item active' : 'progress-item'; }
    get diagnoseButtonLabel() { return this.agentSummary ? 'Refresh diagnosis' : 'Analyze captured context'; }
    get isReportDisabled() { return this.isLoading || !this.sessionId || !this.confirmed || this.reportSubmitted; }
    get confirmationDisabled() { return this.isLoading || this.reportSubmitted; }
    disconnectedCallback() { this.requestVersion++; }

    handleIssueType(event) { this.issueType = event.detail.value; }
    handleDescription(event) { if (this.isLoading) return; this.description = event.detail.value || ''; this.confirmed = false; }
    handleConfirmation(event) { if (!this.confirmationDisabled) this.confirmed = event.target.checked === true; }

    buildContext() {
        const state = this.currentPageReference && this.currentPageReference.state ? this.currentPageReference.state : {};
        const attributes = this.currentPageReference && this.currentPageReference.attributes ? this.currentPageReference.attributes : {};
        return {
            correlationId: this.correlationId,
            pageUrl: window.location.href,
            pageReference: this.currentPageReference,
            objectApiName: attributes.objectApiName || state.objectApiName || state.objectApiName__c || state.c__objectApiName || null,
            recordId: attributes.recordId || state.recordId || state.recordId__c || state.c__recordId || null,
            userAgent: navigator.userAgent,
            language: navigator.language,
            screen: { width: window.screen.width, height: window.screen.height, viewportWidth: window.innerWidth, viewportHeight: window.innerHeight },
            timestamp: new Date().toISOString()
        };
    }

    startDiagnosis() {
        if (this.isStartDisabled) return;
        this.runAsync(
            createSession({ contextJson: JSON.stringify(this.buildContext()), userDescription: this.description, detectedIssueType: this.issueType }),
            res => { this.sessionId = res.sessionId; this.correlationId = res.correlationId; this.message = res.message; }
        );
    }
    askAgent() {
        if (this.isLoading || !this.sessionId) return;
        this.runAsync(
            diagnoseSession({ sessionId: this.sessionId }),
            res => { this.agentSummary = res.summary; this.recommendedAction = res.recommendedAction; this.message = 'The initial diagnosis is ready.'; }
        );
    }
    sendReport() {
        if (this.isReportDisabled || !this.sessionId) return;
        this.confirmed = false;
        this.runAsync(
            escalateSession({ sessionId: this.sessionId, userDescription: this.description }),
            res => {
                if (!res || !res.escalationId) {
                    this.error = 'The governed report was not created. Review the outcome before trying again.';
                    return;
                }
                this.reportSubmitted = true;
                this.message = `Governed report created: ${res.subject}. Delivery status: ${res.status || 'New'}.`;
            }
        );
    }
    runAsync(promise, successHandler) {
        this.error = null;
        this.isLoading = true;
        const version = ++this.requestVersion;
        promise.then(value => { if (version === this.requestVersion) successHandler(value); })
            .catch(e => { if (version === this.requestVersion) this.error = this.normalizeError(e); })
            .finally(() => { if (version === this.requestVersion) this.isLoading = false; });
    }
    reset() {
        if (this.isLoading) return;
        this.requestVersion++;
        this.reportSubmitted = false;
        this.confirmed = false;
        this.sessionId = null; this.correlationId = null; this.message = null; this.agentSummary = null;
        this.recommendedAction = null; this.error = null; this.description = ''; this.issueType = 'Unknown';
    }
    normalizeError(e) { return e && e.body && e.body.message ? e.body.message : 'The diagnostic request could not be completed.'; }
}
