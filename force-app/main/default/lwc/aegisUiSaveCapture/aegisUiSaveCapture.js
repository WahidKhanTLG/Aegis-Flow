import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import reportUiSaveError from '@salesforce/apex/AEIR_UiSaveErrorController.reportUiSaveError';

export default class AegisUiSaveCapture extends LightningElement {
    @api recordId;
    @api objectApiName;
    isSubmitting = false;

    handleSubmit() {
        this.isSubmitting = true;
    }

    handleSuccess() {
        this.isSubmitting = false;
        this.toast('Saved', 'The record was saved successfully.', 'success');
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleCancel() {
        this.isSubmitting = false;
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    /**
     * lightning-record-form already renders the validation/save error for the user.
     * We additionally report it to Aegis so the failure is preserved, correlated,
     * and surfaced through the normal notification pipeline.
     */
    handleError(event) {
        this.isSubmitting = false;
        const detail = event.detail || {};
        const output = detail.output || {};
        const fieldErrors = output.fieldErrors || {};
        const recordErrors = Array.isArray(output.errors) ? output.errors : [];
        const messages = [];
        const addError = (error, fieldName) => {
            if (!error) return;
            const code = error.errorCode || error.statusCode || '';
            const message = typeof error === 'string' ? error : error.message || '';
            if (code || message) messages.push([fieldName, code, message].filter(Boolean).join(': '));
        };
        recordErrors.forEach(error => addError(error));
        Object.entries(fieldErrors).forEach(([fieldName, errors]) => {
            (Array.isArray(errors) ? errors : [errors]).forEach(error => addError(error, fieldName));
        });
        addError({ errorCode: detail.errorCode, message: detail.message });
        if (typeof detail.detail === 'string') addError(detail.detail);
        const message = [...new Set(messages)].join('\n') || 'Save failed';
        // Preserve the complete structured output, including record-level duplicate and
        // validation details. The flattened message also carries server error codes so
        // deterministic classification does not depend on a generic form summary.
        const evidence = {
            message: detail.message || null,
            detail: detail.detail || null,
            errorCode: detail.errorCode || null,
            output
        };
        const pageUrl = window.location.href;

        reportUiSaveError({
            correlationId: null,
            objectApiName: this.objectApiName,
            recordId: this.recordId,
            recordName: null,
            userAction: 'Record save via Aegis UI Save Capture',
            errorMessage: message,
            fieldErrorsJson: JSON.stringify(evidence),
            pageUrl: pageUrl
        })
            .then(result => {
                if (result.success) {
                    this.toast(
                        'Issue captured',
                        `Aegis logged this save issue. Reference: ${result.correlationId}`,
                        'warning'
                    );
                }
            })
            .catch(captureError => {
                // Never hide the original validation message from the user.
                // Aegis capture failure is operational noise; log it silently.
                console.warn('Aegis Flow: UI save capture failed', captureError);
            });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
