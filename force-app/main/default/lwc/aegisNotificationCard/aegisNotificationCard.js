import { LightningElement, api } from 'lwc';
export default class AegisNotificationCard extends LightningElement {
    @api recordId;
    @api correlationId;
}