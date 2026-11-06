import { LightningElement, api } from 'lwc';
import executeRemediation from '@salesforce/apex/AEIR_RemediationController.executeRemediation';

export default class AegisRemediationConfirmation extends LightningElement {
    @api recordId;
    @api correlationId;
    @api pending = false;
    @api result;
    @api externallyManaged = false;
    _proposal;
    showReview = false;
    confirmationSent = false;
    isExecuting = false;
    error;
    requestVersion = 0;

    /**
     * Standalone execution uses the existing server-governed orchestrator. Hosts can
     * opt into externallyManaged, handle `confirm`, and return the actual result.
     */
    @api
    get proposal() { return this._proposal; }
    set proposal(value) {
        this._proposal = value ? { ...value } : null;
        this.requestVersion += 1;
        this.showReview = false;
        this.confirmationSent = false;
        this.isExecuting = false;
        this.error = null;
        this.result = null;
    }
    disconnectedCallback() { this.requestVersion += 1; }
    get hasProposal() {
        const proposal = this._proposal;
        return !!(proposal && proposal.actionKey && proposal.objectApiName && proposal.fieldApiName
            && (proposal.recordId || this.recordId) && Object.prototype.hasOwnProperty.call(proposal, 'newValue'));
    }
    get actionKey() { return this._proposal ? this._proposal.actionKey : ''; }
    get targetRecordId() { return this._proposal ? this._proposal.recordId || this.recordId : this.recordId; }
    get targetField() { return this._proposal ? this._proposal.objectApiName + '.' + this._proposal.fieldApiName : ''; }
    get beforeValue() { return this._proposal && this._proposal.beforeValue != null ? String(this._proposal.beforeValue) : 'Not provided'; }
    get afterValue() { return this._proposal && this._proposal.newValue != null ? String(this._proposal.newValue) : '(clear value)'; }
    get risk() { return this._proposal && this._proposal.risk ? this._proposal.risk : 'Writes to the selected record. Server authorization and registered-action checks are required.'; }
    get busy() { return this.pending || this.isExecuting; }
    get reviewDisabled() { return !this.hasProposal || this.busy || this.confirmationSent || !!this.result; }
    get confirmationMessage() { return 'Approve ' + this.actionKey + ' for ' + this.targetField + ' on record ' + this.targetRecordId + '. Execution requires server authorization and a matching registered action.'; }
    get resultMessage() { return this.result ? this.result.userMessage || this.result.status || 'The server returned a result.' : ''; }
    get resultFailed() { return !!(this.result && this.result.success === false); }
    get awaitingResult() { return this.confirmationSent && !this.result; }
    review() { if (!this.reviewDisabled) this.showReview = true; }
    confirm(event) {
        event.stopPropagation();
        if (!this.showReview || this.reviewDisabled) return;
        this.showReview = false;
        this.confirmationSent = true;
        const proposal = this._proposal;
        const request = {
            actionKey: proposal.actionKey,
            objectApiName: proposal.objectApiName,
            fieldApiName: proposal.fieldApiName,
            recordId: this.targetRecordId,
            newValue: proposal.newValue,
            correlationId: proposal.correlationId || this.correlationId || null,
            errorLogId: proposal.errorLogId || null,
            diagnosticSessionId: proposal.diagnosticSessionId || null,
            confirmed: true
        };
        if (this.externallyManaged) {
            this.dispatchEvent(new CustomEvent('confirm', { detail: request }));
        } else {
            const version = ++this.requestVersion;
            this.isExecuting = true;
            this.dispatchEvent(new CustomEvent('executionstatechange', { detail: { pending: true } }));
            this.error = null;
            executeRemediation({ requestJson: JSON.stringify(request) })
                .then(result => {
                    if (version !== this.requestVersion) return;
                    if (!result || typeof result.success !== 'boolean') throw new Error('The server did not return an execution result. Refresh the diagnostic before requesting another correction.');
                    this.result = result;
                    this.dispatchEvent(new CustomEvent('completed', { detail: { correlationId: result.correlationId, remediationActionId: result.remediationActionId, success: result.success, status: result.status } }));
                })
                .catch(error => {
                    if (version === this.requestVersion) this.error = error && error.body && error.body.message ? error.body.message : error && error.message ? error.message : 'The execution result could not be retrieved. Refresh the diagnostic before requesting another correction.';
                })
                .finally(() => {
                    if (version === this.requestVersion) {
                        this.isExecuting = false;
                        this.dispatchEvent(new CustomEvent('executionstatechange', { detail: { pending: false } }));
                        this.restoreReviewFocus();
                    }
                });
        }
        this.restoreReviewFocus();
    }
    cancel(event) {
        if (event) event.stopPropagation();
        this.showReview = false;
        this.dispatchEvent(new CustomEvent('cancel'));
        this.restoreReviewFocus();
    }
    handleKeydown(event) {
        if (event.key === 'Escape' && this.showReview) {
            event.preventDefault();
            this.cancel();
        }
    }
    restoreReviewFocus() {
        Promise.resolve().then(() => {
            const status = this.template.querySelector('[data-result-status]');
            if (status) { status.focus(); return; }
            const button = this.template.querySelector('lightning-button[data-review]');
            if (button && !button.disabled) button.focus();
        });
    }
}
