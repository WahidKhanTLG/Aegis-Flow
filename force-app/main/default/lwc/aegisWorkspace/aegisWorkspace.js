import ERROR_LOG_OBJECT from '@salesforce/schema/Error_Log__c';
import ESCALATION_OBJECT from '@salesforce/schema/Developer_Escalation__c';
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getAvailableActions from '@salesforce/apex/AEIR_RemediationController.getAvailableActions';
import prepareProposal from '@salesforce/apex/AEIR_RemediationController.prepareProposal';
import collectForError from '@salesforce/apex/AEIR_LogCollectorService.collectForError';
import hasRemediationPermission from '@salesforce/customPermission/AEIR_Execute_Remediation';

/** Hosts the reusable surfaces; all record reads and writes remain server-authorized. */
export default class AegisWorkspace extends LightningElement {
    errorLogObject = ERROR_LOG_OBJECT.objectApiName;
    escalationObject = ESCALATION_OBJECT.objectApiName;
    @api recordId;
    @api objectApiName;
    correlationId = '';
    referenceInput = '';
    recordInput = '';
    objectInput = '';
    activeRecordId;
    activeObjectApiName;
    actions = [];
    selectedAction = '';
    correctionRecordId = '';
    proposedValue = '';
    clearValue = false;
    proposal;
    isPreparing = false;
    actionError;
    contextError;
    escalationRecordId;
    requestVersion = 0;
    workspaceVersion = 0;
    selectedErrorId;
    collectorResult;
    collectorError;
    isCollecting = false;
    collectorVersion = 0;
    isExecuting = false;

    @wire(CurrentPageReference)
    readPageContext(page) {
        const attributes = (page && page.attributes) || {};
        const state = (page && page.state) || {};
        const recordId = this.recordId || attributes.recordId || state.c__recordId;
        const objectApiName = this.objectApiName || attributes.objectApiName || state.c__objectApiName;
        if (recordId && objectApiName && !this.activeRecordId) {
            this.recordInput = recordId;
            this.objectInput = objectApiName;
            this.loadContext();
        }
    }
    connectedCallback() {
        if (!this.canPrepareCorrections) return;
        getAvailableActions().then(actions => { if (this.isConnected) this.actions = Array.isArray(actions) ? actions : []; })
            .catch(error => { if (this.isConnected) this.actionError = this.readError(error, 'Registered corrections are unavailable for your access.'); });
    }
    disconnectedCallback() { this.requestVersion += 1; this.clearLogBody(); }
    get canPrepareCorrections() { return hasRemediationPermission === true; }
    get actionOptions() { return this.actions.map(action => ({ label: action.label, value: action.actionKey })); }
    get hasActions() { return this.actions.length > 0; }
    get hasContext() { return !!(this.activeRecordId && this.activeObjectApiName); }
    get workspaceContexts() { return [{ key: this.workspaceVersion }]; }
    get contextLabel() { return this.hasContext ? this.activeObjectApiName + ' · ' + this.activeRecordId : 'No record context selected'; }
    get prepareDisabled() { return !this.canPrepareCorrections || this.isExecuting || this.isPreparing || !this.selectedAction || !this.correctionRecordId || (!this.clearValue && !this.proposedValue); }
    get correctionInputsDisabled() { return this.isExecuting || this.isPreparing; }
    get proposedValueDisabled() { return this.isExecuting || this.clearValue; }
    get collectDisabled() { return !this.selectedErrorId || this.isCollecting; }
    get hasLogBody() { return !!(this.collectorResult && this.collectorResult.bodyRetrieved && this.collectorResult.debugLogBody); }
    get debugLogBody() { return this.hasLogBody ? this.collectorResult.debugLogBody : ''; }
    get logTruncated() { return !!(this.hasLogBody && this.collectorResult.truncated); }
    handleReference(event) { this.referenceInput = event.detail.value; }
    applyReference() { if (this.isExecuting) return; this.correlationId = (this.referenceInput || '').trim(); this.invalidateProposal(); this.resetLogSelection(); this.workspaceVersion += 1; }
    handleRecord(event) { this.recordInput = event.detail.value; }
    handleObject(event) { this.objectInput = event.detail.value; }
    loadContext() {
        if (this.isExecuting) return;
        const recordId = (this.recordInput || '').trim();
        const objectApiName = (this.objectInput || '').trim();
        if (!/^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(recordId) || !/^[A-Za-z][A-Za-z0-9_]{0,99}$/.test(objectApiName)) {
            this.contextError = 'Enter a 15- or 18-character Salesforce record Id and its object API name.';
            return;
        }
        this.contextError = null;
        this.activeRecordId = recordId;
        this.activeObjectApiName = objectApiName;
        this.correctionRecordId = recordId;
        this.invalidateProposal();
        this.resetLogSelection();
        this.workspaceVersion += 1;
    }
    clearContext() {
        if (this.isExecuting) return;
        this.activeRecordId = null;
        this.activeObjectApiName = null;
        this.recordInput = '';
        this.objectInput = '';
        this.correctionRecordId = '';
        this.contextError = null;
        this.invalidateProposal();
        this.resetLogSelection();
        this.workspaceVersion += 1;
    }
    handleAction(event) { this.selectedAction = event.detail.value; this.invalidateProposal(); }
    handleCorrectionRecord(event) { this.correctionRecordId = event.detail.value; this.invalidateProposal(); }
    handleProposedValue(event) { this.proposedValue = event.detail.value; this.invalidateProposal(); }
    handleClearValue(event) { this.clearValue = event.target.checked; this.invalidateProposal(); }
    invalidateProposal() { this.requestVersion += 1; this.proposal = null; this.isPreparing = false; }
    prepare() {
        if (this.prepareDisabled) return;
        const version = ++this.requestVersion;
        this.isPreparing = true;
        this.actionError = null;
        this.proposal = null;
        prepareProposal({ actionKey: this.selectedAction, recordId: this.correctionRecordId.trim(),
            newValue: this.clearValue ? null : this.proposedValue, correlationId: this.correlationId || null })
            .then(proposal => { if (version === this.requestVersion) this.proposal = proposal; })
            .catch(error => { if (version === this.requestVersion) this.actionError = this.readError(error, 'The proposal could not be prepared. Check the action, record and your access.'); })
            .finally(() => { if (version === this.requestVersion) this.isPreparing = false; });
    }
    selectEscalation(event) { this.escalationRecordId = event.detail.recordId; }
    handleExecutionState(event) { this.isExecuting = event.detail.pending === true; }
    resetLogSelection() { this.selectedErrorId = null; this.clearLogBody(); }
    selectError(event) { this.selectedErrorId = event.detail.recordId; this.clearLogBody(); }
    clearLogBody() { this.collectorVersion += 1; this.collectorResult = null; this.collectorError = null; this.isCollecting = false; }
    collectLog() {
        if (this.collectDisabled) return;
        const version = ++this.collectorVersion;
        this.collectorResult = null;
        this.collectorError = null;
        this.isCollecting = true;
        collectForError({ errorLogId: this.selectedErrorId })
            .then(result => { if (version === this.collectorVersion) this.collectorResult = result; })
            .catch(error => { if (version === this.collectorVersion) this.collectorError = this.readError(error, 'The authorized debug-log evidence could not be retrieved.'); })
            .finally(() => { if (version === this.collectorVersion) this.isCollecting = false; });
    }
    readError(error, fallback) { return error && error.body && error.body.message ? error.body.message : fallback; }
}
