import { LightningElement, api } from 'lwc';
import AEGIS_LOGO from '@salesforce/resourceUrl/AegisFlowLogo';
import ESCALATION_OBJECT from '@salesforce/schema/Developer_Escalation__c';
import SUBJECTFIELD from '@salesforce/schema/Developer_Escalation__c.Subject__c';
import STATUSFIELD from '@salesforce/schema/Developer_Escalation__c.Status__c';
import SEVERITYFIELD from '@salesforce/schema/Developer_Escalation__c.Severity__c';
import CHANNELFIELD from '@salesforce/schema/Developer_Escalation__c.Channel__c';
import RECIPIENTFIELD from '@salesforce/schema/Developer_Escalation__c.Recipient__c';
import PACKAGEFIELD from '@salesforce/schema/Developer_Escalation__c.Diagnostic_Package_JSON__c';
export default class DeveloperEscalationViewer extends LightningElement {
    @api recordId;
    logoUrl = AEGIS_LOGO;
    escalationObject = ESCALATION_OBJECT.objectApiName;
    subjectField = SUBJECTFIELD.fieldApiName;
    statusField = STATUSFIELD.fieldApiName;
    severityField = SEVERITYFIELD.fieldApiName;
    channelField = CHANNELFIELD.fieldApiName;
    recipientField = RECIPIENTFIELD.fieldApiName;
    packageField = PACKAGEFIELD.fieldApiName;
}
