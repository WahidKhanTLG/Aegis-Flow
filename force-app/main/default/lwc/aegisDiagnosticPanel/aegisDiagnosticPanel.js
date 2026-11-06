import { LightningElement, api } from 'lwc';
import getAlertDetails from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';

export default class AegisDiagnosticPanel extends LightningElement {
    @api recordId;
    _correlationId = '';
    detail;
    error;
    isLoading = false;
    requestVersion = 0;

    @api
    get correlationId() { return this._correlationId; }
    set correlationId(value) {
        this._correlationId = value ? String(value).trim() : '';
        if (this.isConnected) this.refresh();
    }
    connectedCallback() { this.refresh(); }
    disconnectedCallback() { this.requestVersion += 1; }
    get hasReference() { return !!this._correlationId; }
    get errorLog() { return this.detail && this.detail.errorLog; }
    get hasEvidence() { return !!this.errorLog; }
    get severity() { return this.errorLog ? this.errorLog.severity : this.detail && this.detail.alert ? this.detail.alert.severity : ''; }
    get status() { return this.errorLog ? this.errorLog.status : ''; }
    get summary() { return this.errorLog ? this.errorLog.normalizedMessage : this.detail && this.detail.alert ? this.detail.alert.shortMessage : ''; }
    get source() { return this.errorLog ? this.errorLog.sourceName || this.errorLog.sourceType : ''; }
    get diagnosis() { return this.detail && this.detail.diagnosis; }
    get rootCause() { return this.diagnosis ? this.diagnosis.Root_Cause__c : ''; }
    get recommendedAction() { return this.diagnosis ? this.diagnosis.Recommended_Action__c : ''; }
    handleReference(event) { this.correlationId = event.detail.value; }

    @api
    refresh() {
        const version = ++this.requestVersion;
        this.detail = null;
        this.error = null;
        this.isLoading = this.hasReference;
        if (!this.hasReference) return Promise.resolve();
        return getAlertDetails({ correlationId: this._correlationId })
            .then(detail => { if (version === this.requestVersion) this.detail = detail; })
            .catch(error => {
                if (version === this.requestVersion) this.error = error && error.body && error.body.message ? error.body.message : 'This diagnostic is unavailable or you do not have access. Check the reference and try again.';
            })
            .finally(() => { if (version === this.requestVersion) this.isLoading = false; });
    }
}
