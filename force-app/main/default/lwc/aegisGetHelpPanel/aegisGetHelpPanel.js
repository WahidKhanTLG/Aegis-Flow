import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import createSession from '@salesforce/apex/AEIR_HelpMeController.createSession';
import diagnoseSession from '@salesforce/apex/AEIR_HelpMeController.diagnoseSession';
import escalateSession from '@salesforce/apex/AEIR_HelpMeController.escalateSession';

export default class AegisGetHelpPanel extends LightningElement {
    @wire(CurrentPageReference) pageReference;
    @api objectApiName;
    _recordId;
    _correlationId = '';
    sessionId;
    sessionReference;
    description = '';
    summary;
    recommendation;
    message;
    error;
    confirmed = false;
    isLoading = false;
    requestVersion = 0;

    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        if (value !== this._recordId) this.resetSession();
        this._recordId = value;
    }
    @api
    get correlationId() { return this._correlationId; }
    set correlationId(value) {
        const reference = value ? String(value).trim() : '';
        if (reference !== this._correlationId) this.resetSession();
        this._correlationId = reference;
    }
    disconnectedCallback() { this.requestVersion += 1; }
    get startDisabled() { return this.isLoading || !this.description.trim(); }
    get sendDisabled() { return this.isLoading || !this.sessionId || !this.confirmed; }
    get sessionActionsDisabled() { return this.isLoading || !this.sessionId; }
    handleDescription(event) { this.description = event.detail.value || ''; this.confirmed = false; }
    handleReference(event) { this.correlationId = event.detail.value; }
    handleConfirmation(event) { this.confirmed = event.target.checked; }

    buildContext() {
        const page = this.pageReference || {};
        const attributes = page.attributes || {};
        const state = page.state || {};
        return {
            correlationId: this._correlationId || null,
            recordId: this._recordId || attributes.recordId || state.recordId || state.c__recordId || null,
            objectApiName: this.objectApiName || attributes.objectApiName || state.objectApiName || state.c__objectApiName || null,
            pageUrl: window.location.href,
            pageReference: this.pageReference,
            userAgent: navigator.userAgent
        };
    }
    start() {
        if (this.startDisabled) return;
        this.runRequest(() => createSession({
            contextJson: JSON.stringify(this.buildContext()), userDescription: this.description.trim(), detectedIssueType: 'Report Issue'
        }), response => {
            if (!response || !response.sessionId) throw new Error('The session was not created. Try again.');
            this.sessionId = response.sessionId;
            this.sessionReference = response.correlationId;
            this.message = response.message || 'Diagnostic session created.';
            this.confirmed = false;
        });
    }
    diagnose() {
        if (this.sessionActionsDisabled) return;
        this.runRequest(() => diagnoseSession({ sessionId: this.sessionId }), response => {
            this.summary = response && response.summary;
            this.recommendation = response && response.recommendedAction;
            this.message = 'Diagnostic analysis completed.';
        });
    }
    send() {
        if (this.sendDisabled) return;
        this.runRequest(() => escalateSession({ sessionId: this.sessionId, userDescription: this.description.trim() }), response => {
            if (!response || !response.escalationId) throw new Error('The escalation could not be created. Try again.');
            this.message = 'Governed report created: ' + (response.subject || response.escalationId) + '. Delivery status: ' + (response.status || 'Pending') + '.';
            this.confirmed = false;
            this.dispatchEvent(new CustomEvent('escalated', { detail: { sessionId: this.sessionId, correlationId: this.sessionReference } }));
        });
    }
    runRequest(operation, onSuccess) {
        const version = ++this.requestVersion;
        this.isLoading = true;
        this.error = null;
        return operation()
            .then(result => { if (version === this.requestVersion) onSuccess(result); })
            .catch(error => {
                if (version === this.requestVersion) this.error = error && error.body && error.body.message ? error.body.message : error && error.message ? error.message : 'This operation could not be completed. Try again.';
            })
            .finally(() => { if (version === this.requestVersion) this.isLoading = false; });
    }
    resetSession() {
        this.requestVersion += 1;
        this.sessionId = null;
        this.sessionReference = null;
        this.summary = null;
        this.recommendation = null;
        this.message = null;
        this.error = null;
        this.confirmed = false;
        this.isLoading = false;
    }
}
