import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getConfig from '@salesforce/apex/AEIR_OrgSetupService.getConfig';
import saveConfig from '@salesforce/apex/AEIR_OrgSetupService.saveConfig';
import runHealthCheck from '@salesforce/apex/AEIR_SetupHealthCheckService.runWithProbe';
import scanFlows from '@salesforce/apex/AEIR_FlowCoverageService.scan';

export default class AegisSetupWizard extends LightningElement {
    @track config = {
        companyName: '',
        developerTeamEmail: '',
        adminTeamEmail: '',
        fallbackToSystemAdmins: true,
        shareDiagnosticsWithVendor: false,
        vendorSupportEmail: ''
    };
    @track report;
    @track coverage;
    isScanning = false;
    step = 1;
    isSaving = false;
    isChecking = false;
    error;
    wiredConfig;

    @wire(getConfig)
    loadConfig(result) {
        this.wiredConfig = result;
        if (result.data) {
            this.config = { ...this.config, ...result.data };
            if (result.data.onboardingComplete) this.step = 3;
        } else if (result.error) {
            this.error = this.readError(result.error);
        }
    }

    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }
    get hasReport() { return !!this.report; }
    get hasCoverage() { return !!this.coverage; }
    get coverageVariant() {
        if (!this.coverage) return 'base';
        return this.coverage.uncapturedFailures > 0 ? 'warning' : 'success';
    }
    get riskyFlows() {
        if (!this.coverage) return [];
        // Only Flows that have actually failed are worth an admin's attention.
        return this.coverage.flows.map((f) => ({
            ...f,
            key: f.label,
            counts: `${f.failuresObserved} failed, ${f.failuresCaptured} captured`
        }));
    }
    get vendorEmailDisabled() { return !this.config.shareDiagnosticsWithVendor; }
    get routingSummary() {
        if (this.config.developerTeamEmail) return `Findings go to ${this.config.developerTeamEmail}`;
        if (this.config.fallbackToSystemAdmins) return 'No team named yet, so findings go to your System Administrators.';
        return 'No recipient configured. Findings will not be delivered.';
    }
    get overallVariant() {
        if (!this.report) return 'base';
        if (this.report.overallStatus === 'FAIL') return 'error';
        return this.report.overallStatus === 'WARNING' ? 'warning' : 'success';
    }
    get decoratedChecks() {
        if (!this.report) return [];
        return this.report.checks.map((c) => ({
            ...c,
            key: c.name,
            badgeClass:
                c.status === 'PASS'
                    ? 'slds-badge slds-theme_success'
                    : c.status === 'WARNING'
                    ? 'slds-badge slds-theme_warning'
                    : 'slds-badge slds-theme_error'
        }));
    }

    handleChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.config = { ...this.config, [field]: value };
    }

    next() { this.step = 2; }
    back() { this.step = this.step === 3 ? 2 : 1; }

    save() {
        this.isSaving = true;
        this.error = undefined;
        saveConfig({ configJson: JSON.stringify(this.config) })
            .then((saved) => {
                this.config = { ...this.config, ...saved };
                this.step = 3;
                this.toast('Setup saved', 'Aegis Flow will route findings to the teams you named.', 'success');
                return refreshApex(this.wiredConfig);
            })
            .catch((e) => {
                this.error = this.readError(e);
                this.toast('Could not save setup', this.error, 'error');
            })
            .finally(() => { this.isSaving = false; });
    }

    check() {
        this.isChecking = true;
        this.error = undefined;
        runHealthCheck()
            .then((r) => { this.report = r; })
            .catch((e) => { this.error = this.readError(e); })
            .finally(() => { this.isChecking = false; });
    }

    scan() {
        this.isScanning = true;
        scanFlows()
            .then((c) => { this.coverage = c; })
            .catch((e) => { this.error = this.readError(e); })
            .finally(() => { this.isScanning = false; });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    readError(e) {
        return e && e.body && e.body.message ? e.body.message : 'Aegis Flow could not complete this operation.';
    }
}