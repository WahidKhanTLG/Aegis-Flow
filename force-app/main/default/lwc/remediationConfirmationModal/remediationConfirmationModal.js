import { LightningElement, api } from 'lwc';
export default class RemediationConfirmationModal extends LightningElement {
    @api message = 'Confirm the proposed data change before continuing.';
    hasFocused = false;
    renderedCallback() {
        if (this.hasFocused) return;
        const cancelButton = this.template.querySelector('.cancel');
        if (cancelButton) {
            cancelButton.focus();
            this.hasFocused = true;
        }
    }
    handleKeydown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            event.stopPropagation();
            this.cancel();
            return;
        }
        if (event.key !== 'Tab') return;
        const first = this.template.querySelector('.cancel');
        const last = this.template.querySelector('.confirm');
        if (event.shiftKey && event.target === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && event.target === last) {
            event.preventDefault();
            first.focus();
        }
    }
    confirm() { this.dispatchEvent(new CustomEvent('confirm')); }
    cancel() { this.dispatchEvent(new CustomEvent('cancel')); }
}
