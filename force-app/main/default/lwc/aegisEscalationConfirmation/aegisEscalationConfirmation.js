import { LightningElement, api } from 'lwc';
import getAlertDetails from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getAlertDetails';
import escalateAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.escalateAlert';

export default class AegisEscalationConfirmation extends LightningElement {
    @api recordId;
    _correlationId = '';
    detail;
    result;
    confirmed = false;
    isLoading = false;
    error;
    requestVersion = 0;

    @api
    get correlationId() { return this._correlationId; }
    set correlationId(value) {
        this._correlationId = value ? String(value).trim() : '';
        if (this.isConnected) this.refresh();
    }
    connectedCallback() { this.refresh(); }
    disconnectedCallback() { this.requestVersion += 1; }
    get canEscalate() { return !!(this.detail && this.detail.canEscalate && this.detail.errorLog); }
    get summary() { return this.detail && this.detail.errorLog ? this.detail.errorLog.normalizedMessage : ''; }
    get severity() { return this.detail && this.detail.errorLog ? this.detail.errorLog.severity : ''; }
    get sendDisabled() { return this.isLoading || !this.canEscalate || !this.confirmed || !!this.result; }
    get deliveryStatus() { return this.result ? this.result.status || 'Pending' : ''; }
    get deliveryChannel() { return this.result ? this.result.channel || 'Configured route' : ''; }
    get resultReference() { return this.result ? this.result.subject || this.result.escalationId : ''; }
    handleReference(event) { this.correlationId = event.detail.value; }
    handleConfirmation(event) { this.confirmed = event.target.checked; }

    @api
    refresh() {
        const version = ++this.requestVersion;
        this.detail = null;
        this.result = null;
        this.error = null;
        this.confirmed = false;
        this.isLoading = !!this._correlationId;
        if (!this._correlationId) return Promise.resolve();
        return getAlertDetails({ correlationId: this._correlationId })
            .then(detail => { if (version === this.requestVersion) this.detail = detail; })
            .catch(error => {
                if (version === this.requestVersion) this.error = error && error.body && error.body.message ? error.body.message : 'This diagnostic is unavailable or you do not have access. Check the reference and try again.';
            })
            .finally(() => { if (version === this.requestVersion) this.isLoading = false; });
    }
    send() {
        if (this.sendDisabled) return;
        const version = ++this.requestVersion;
        const correlationId = this._correlationId;
        this.isLoading = true;
        this.error = null;
        escalateAlert({ correlationId })
            .then(result => {
                if (version !== this.requestVersion) return;
                if (!result || !result.escalationId) throw new Error('The escalation was not created. Try again.');
                this.result = result;
                this.confirmed = false;
                this.dispatchEvent(new CustomEvent('escalated', { detail: { correlationId, escalationId: result.escalationId, status: result.status } }));
            })
            .catch(error => {
                if (version === this.requestVersion) this.error = error && error.body && error.body.message ? error.body.message : error && error.message ? error.message : 'The escalation could not be created. Try again.';
            })
            .finally(() => { if (version === this.requestVersion) this.isLoading = false; });
    }
}
