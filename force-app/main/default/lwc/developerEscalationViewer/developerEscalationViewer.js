import { LightningElement, api } from 'lwc';
import AEGIS_LOGO from '@salesforce/resourceUrl/AegisFlowLogo';
export default class DeveloperEscalationViewer extends LightningElement {
    @api recordId;
    logoUrl = AEGIS_LOGO;
}