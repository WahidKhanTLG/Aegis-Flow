import { createElement } from 'lwc';
import AegisUiSaveCapture from 'c/aegisUiSaveCapture';
import reportUiSaveError from '@salesforce/apex/AEIR_UiSaveErrorController.reportUiSaveError';
import { CloseActionScreenEvent } from 'lightning/actions';

jest.mock(
    '@salesforce/apex/AEIR_UiSaveErrorController.reportUiSaveError',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise(resolve => setTimeout(resolve, 0));
}

describe('c-aegis-ui-save-capture', () => {
    let element;

    beforeEach(() => {
        reportUiSaveError.mockResolvedValue({ success: true, correlationId: 'UI-SAVE-123' });
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    async function mount() {
        element = createElement('c-aegis-ui-save-capture', { is: AegisUiSaveCapture });
        element.recordId = '006000000000001';
        element.objectApiName = 'Opportunity';
        document.body.appendChild(element);
        await flushPromises();
    }

    it('renders a record form with the provided record context', async () => {
        await mount();
        const form = element.shadowRoot.querySelector('lightning-record-form');
        expect(form).not.toBeNull();
        expect(form.recordId).toBe('006000000000001');
        expect(form.objectApiName).toBe('Opportunity');
        expect(form.layoutType).toBe('Full');
        expect(form.mode).toBe('edit');
    });

    it('reports validation errors to Aegis while preserving the standard UI error', async () => {
        await mount();
        const form = element.shadowRoot.querySelector('lightning-record-form');
        form.dispatchEvent(
            new CustomEvent('error', {
                detail: {
                    message: 'FIELD_CUSTOM_VALIDATION_EXCEPTION: Tax Code is required.',
                    output: {
                        fieldErrors: {
                            Amount: [{ message: 'Amount must be positive' }]
                        }
                    }
                }
            })
        );
        await flushPromises();

        expect(reportUiSaveError).toHaveBeenCalledTimes(1);
        const args = reportUiSaveError.mock.calls[0][0];
        expect(args.objectApiName).toBe('Opportunity');
        expect(args.recordId).toBe('006000000000001');
        expect(args.errorMessage).toContain('Tax Code is required');
        expect(args.fieldErrorsJson).toContain('Amount must be positive');
    });

    it.each([
        ['Opportunity', '006000000000001', 'FIELD_CUSTOM_VALIDATION_EXCEPTION', 'Close date must be after the approval date'],
        ['Case', '500000000000001', 'DUPLICATES_DETECTED', 'A matching service case already exists'],
        ['Example_Work_Item__c', 'a01000000000001', 'INSUFFICIENT_ACCESS_OR_READONLY', 'This work item cannot be updated']
    ])('preserves record-level error codes and details for %s', async (objectApiName, recordId, errorCode, message) => {
        await mount();
        element.objectApiName = objectApiName;
        element.recordId = recordId;
        const recordError = { errorCode, message, duplicateRecordError: { matchResults: [{ entityType: objectApiName }] } };
        const detail = {
            message: 'An error occurred while trying to update the record. Please try again.',
            detail: 'Additional server detail',
            output: { errors: [recordError], fieldErrors: {} }
        };
        element.shadowRoot.querySelector('lightning-record-form').dispatchEvent(new CustomEvent('error', { detail }));
        await flushPromises();
        const args = reportUiSaveError.mock.calls[0][0];
        expect(args.objectApiName).toBe(objectApiName);
        expect(args.recordId).toBe(recordId);
        expect(args.errorMessage).toContain(errorCode);
        expect(args.errorMessage).toContain(message);
        expect(args.errorMessage).toContain('Additional server detail');
        expect(JSON.parse(args.fieldErrorsJson).output.errors).toEqual([recordError]);
    });

    it('includes every field validation code in the classification message and preserves evidence', async () => {
        await mount();
        const fieldErrors = {
            Amount: [
                { errorCode: 'FIELD_CUSTOM_VALIDATION_EXCEPTION', message: 'Amount must be positive' },
                { errorCode: 'NUMBER_OUTSIDE_VALID_RANGE', message: 'Amount exceeds the allowed range' }
            ],
            StageName: [{ errorCode: 'INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST', message: 'Select an active stage' }]
        };
        element.shadowRoot.querySelector('lightning-record-form').dispatchEvent(new CustomEvent('error', {
            detail: { message: 'Save failed', output: { errors: [], fieldErrors } }
        }));
        await flushPromises();
        const args = reportUiSaveError.mock.calls[0][0];
        expect(args.errorMessage).toContain('Amount: FIELD_CUSTOM_VALIDATION_EXCEPTION: Amount must be positive');
        expect(args.errorMessage).toContain('NUMBER_OUTSIDE_VALID_RANGE');
        expect(args.errorMessage).toContain('StageName: INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST');
        expect(JSON.parse(args.fieldErrorsJson).output.fieldErrors).toEqual(fieldErrors);
    });

    it('captures API/network error codes without field output', async () => {
        await mount();
        element.shadowRoot.querySelector('lightning-record-form').dispatchEvent(new CustomEvent('error', {
            detail: { errorCode: 'INVALID_SESSION_ID', message: 'Session expired', detail: { status: 401 } }
        }));
        await flushPromises();
        const args = reportUiSaveError.mock.calls[0][0];
        expect(args.errorMessage).toBe('INVALID_SESSION_ID: Session expired');
        expect(JSON.parse(args.fieldErrorsJson).detail).toEqual({ status: 401 });
    });

    it('closes the action panel after a successful save', async () => {
        await mount();
        const form = element.shadowRoot.querySelector('lightning-record-form');
        const closeHandler = jest.fn();
        element.addEventListener(CloseActionScreenEvent.CLOSE_ACTION_SCREEN, closeHandler);
        form.dispatchEvent(new CustomEvent('success'));
        await flushPromises();
        expect(closeHandler).toHaveBeenCalled();
    });

    it('closes the action panel on cancel without capturing an error or saving', async () => {
        await mount();
        const closeHandler = jest.fn();
        element.addEventListener(CloseActionScreenEvent.CLOSE_ACTION_SCREEN, closeHandler);
        element.shadowRoot.querySelector('lightning-record-form').dispatchEvent(new CustomEvent('cancel'));
        await flushPromises();
        expect(closeHandler).toHaveBeenCalledTimes(1);
        expect(reportUiSaveError).not.toHaveBeenCalled();
    });
});
