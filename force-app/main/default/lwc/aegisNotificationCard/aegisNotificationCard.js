import { LightningElement, api } from 'lwc';
import resolveAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.resolveAlert';
import dismissAlert from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.dismissAlert';

export default class AegisNotificationCard extends LightningElement {
    @api recordId;
    _correlationId = '';
    alert;
    error;
    isLoading = false;
    showDetails = false;
    message;
    requestVersion = 0;

    @api
    get correlationId() { return this._correlationId; }
    set correlationId(value) {
        this._correlationId = value ? String(value).trim() : '';
        this.showDetails = false;
        if (this.isConnected) this.refresh();
    }
    connectedCallback() { this.refresh(); }
    disconnectedCallback() { this.requestVersion += 1; }
    get headline() { return this.alert ? this.alert.headline : ''; }
    get summary() { return this.alert ? this.alert.shortMessage : ''; }
    get severity() { return this.alert ? this.alert.severity : ''; }
    get isEmpty() { return !this.alert && !this.isLoading && !this.error; }
    handleReference(event) { this.correlationId = event.detail.value; }
    openDetails() { this.showDetails = true; }

    @api
    refresh() {
        const version = ++this.requestVersion;
        this.alert = null;
        this.error = null;
        this.message = null;
        this.showDetails = false;
        this.isLoading = !!this._correlationId;
        if (!this._correlationId) return Promise.resolve();
        return resolveAlert({ correlationId: this._correlationId })
            .then(alert => {
                if (version !== this.requestVersion) return;
                const expiresAt = alert && alert.expiresAt ? new Date(alert.expiresAt).getTime() : NaN;
                if (alert && alert.correlationId === this._correlationId && ['New', 'Viewed'].includes(alert.status) && expiresAt > Date.now()) this.alert = alert;
            })
            .catch(error => {
                if (version === this.requestVersion) this.error = error && error.body && error.body.message ? error.body.message : 'The notification could not be loaded. Try refreshing.';
            })
            .finally(() => { if (version === this.requestVersion) this.isLoading = false; });
    }

    dismiss() {
        if (!this.alert || this.isLoading) return;
        const correlationId = this.alert.correlationId;
        const version = ++this.requestVersion;
        this.isLoading = true;
        this.error = null;
        dismissAlert({ correlationId })
            .then(() => {
                if (version !== this.requestVersion) return;
                this.alert = null;
                this.showDetails = false;
                this.message = 'Notification dismissed.';
                this.dispatchEvent(new CustomEvent('dismiss', { detail: { correlationId } }));
            })
            .catch(error => {
                if (version === this.requestVersion) this.error = error && error.body && error.body.message ? error.body.message : 'The notification could not be dismissed. Try again.';
            })
            .finally(() => { if (version === this.requestVersion) this.isLoading = false; });
    }
}
