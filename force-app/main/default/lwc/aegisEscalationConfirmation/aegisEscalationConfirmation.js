import { LightningElement, api } from 'lwc';
export default class AegisEscalationConfirmation extends LightningElement {
    @api recordId;
    @api correlationId;
}