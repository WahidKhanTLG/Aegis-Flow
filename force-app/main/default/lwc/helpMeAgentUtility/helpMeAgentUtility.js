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

    handleIssueType(event) { this.issueType = event.detail.value; }
    handleDescription(event) { this.description = event.detail.value; }

    buildContext() {
        const state = this.currentPageReference && this.currentPageReference.state ? this.currentPageReference.state : {};
        return {
            correlationId: this.correlationId,
            pageUrl: window.location.href,
            pageReference: this.currentPageReference,
            objectApiName: state.objectApiName || state.objectApiName__c || null,
            recordId: state.recordId || state.recordId__c || (this.currentPageReference && this.currentPageReference.attributes ? this.currentPageReference.attributes.recordId : null),
            userAgent: navigator.userAgent,
            language: navigator.language,
            screen: { width: window.screen.width, height: window.screen.height, viewportWidth: window.innerWidth, viewportHeight: window.innerHeight },
            timestamp: new Date().toISOString()
        };
    }

    startDiagnosis() {
        this.runAsync(
            createSession({ contextJson: JSON.stringify(this.buildContext()), userDescription: this.description, detectedIssueType: this.issueType }),
            res => { this.sessionId = res.sessionId; this.correlationId = res.correlationId; this.message = res.message; }
        );
    }
    askAgent() {
        this.runAsync(
            diagnoseSession({ sessionId: this.sessionId }),
            res => { this.agentSummary = res.summary; this.recommendedAction = res.recommendedAction; this.message = 'Analysis completed using the configured diagnostic gateway.'; }
        );
    }
    sendReport() {
        this.runAsync(
            escalateSession({ sessionId: this.sessionId, userDescription: this.description }),
            res => { this.message = `Governed report created: ${res.subject}`; }
        );
    }
    runAsync(promise, successHandler) {
        this.error = null;
        this.isLoading = true;
        promise.then(successHandler).catch(e => { this.error = this.normalizeError(e); }).finally(() => { this.isLoading = false; });
    }
    reset() {
        this.sessionId = null; this.correlationId = null; this.message = null; this.agentSummary = null;
        this.recommendedAction = null; this.error = null; this.description = ''; this.issueType = 'Unknown';
    }
    normalizeError(e) { return e && e.body && e.body.message ? e.body.message : 'The diagnostic request could not be completed.'; }
}