import { LightningElement, api } from 'lwc';
export default class RemediationConfirmationModal extends LightningElement {
    @api message = 'Confirm the proposed data change before continuing.';
    confirm() { this.dispatchEvent(new CustomEvent('confirm')); }
    cancel() { this.dispatchEvent(new CustomEvent('cancel')); }
}