import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import AEGIS_LOGO from '@salesforce/resourceUrl/AegisFlowLogo';
import getRecentErrors from '@salesforce/apex/AEIR_AdminConsoleController.getRecentErrors';
import getMetrics from '@salesforce/apex/AEIR_AdminConsoleController.getMetrics';

export default class AdminErrorConsole extends LightningElement {
    errors = [];
    metrics;
    wiredErrorsResult;
    wiredMetricsResult;
    logoUrl = AEGIS_LOGO;
    errorsLoading = true;
    metricsLoading = true;
    errorsError;
    metricsError;
    columns = [
        { label: 'Reference', fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' }, initialWidth: 130 },
        { label: 'Severity', fieldName: 'Severity__c', initialWidth: 105 },
        { label: 'Category', fieldName: 'Error_Category__c' },
        { label: 'Source', fieldName: 'Source_Type__c', initialWidth: 120 },
        { label: 'Status', fieldName: 'Status__c', initialWidth: 135 },
        { label: 'Captured', fieldName: 'CreatedDate', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }, initialWidth: 180 }
    ];

    get hasErrors() { return this.errors && this.errors.length > 0; }
    get isLoading() { return this.errorsLoading || this.metricsLoading; }
    get error() { return this.errorsError || this.metricsError; }
    get showEmpty() { return !this.isLoading && !this.errorsError && !this.hasErrors; }

    @wire(getRecentErrors, { status: null, severity: null, limitSize: 50 })
    wiredErrors(result) {
        this.wiredErrorsResult = result;
        if (result.data) {
            this.errors = result.data.map(row => ({ ...row, recordUrl: `/${row.Id}` }));
            this.errorsError = null;
        } else if (result.error) {
            this.errorsError = 'Diagnostic records could not be loaded. Check your access and refresh.';
        }
        if (result.data || result.error) this.errorsLoading = false;
    }

    @wire(getMetrics)
    wiredMetrics(result) {
        this.wiredMetricsResult = result;
        if (result.data) { this.metrics = result.data; this.metricsError = null; }
        else if (result.error) this.metricsError = 'Diagnostic metrics could not be loaded. Check your access and refresh.';
        if (result.data || result.error) this.metricsLoading = false;
    }

    handleRefresh() {
        return Promise.all([refreshApex(this.wiredErrorsResult), refreshApex(this.wiredMetricsResult)]);
    }
}
