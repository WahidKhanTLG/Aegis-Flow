import { LightningElement, api } from 'lwc';
export default class AegisRemediationConfirmation extends LightningElement {
    @api recordId;
    @api correlationId;
}