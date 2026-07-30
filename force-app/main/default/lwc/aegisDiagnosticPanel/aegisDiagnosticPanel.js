import { LightningElement, api } from 'lwc';
export default class AegisDiagnosticPanel extends LightningElement {
    @api recordId;
    @api correlationId;
}