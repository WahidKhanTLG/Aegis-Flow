import { LightningElement, api } from 'lwc';
import reportClientError from '@salesforce/apex/AEIR_ClientErrorController.reportClientError';

export default class ErrorBoundaryWrapper extends LightningElement {
    @api correlationId;
    @api componentName = 'Unknown LWC';
    errorCallback(error, stack) {
        reportClientError({
            correlationId: this.correlationId,
            componentName: this.componentName,
            message: error && error.message ? error.message : 'Unknown client error',
            stackTrace: stack,
            pageUrl: window.location.href,
            userAgent: navigator.userAgent
        });
    }
}