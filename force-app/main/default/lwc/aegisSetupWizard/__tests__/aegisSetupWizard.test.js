import { createElement } from 'lwc';
import AegisSetupWizard from 'c/aegisSetupWizard';
import getConfig from '@salesforce/apex/AEIR_OrgSetupService.getConfig';
import runHealthCheck from '@salesforce/apex/AEIR_SetupHealthCheckService.run';
import runCaptureProbe from '@salesforce/apex/AEIR_SetupHealthCheckService.runWithProbe';

jest.mock('@salesforce/apex/AEIR_OrgSetupService.getConfig', () => { const {createApexTestWireAdapter}=require('@salesforce/wire-service-jest-util'); return {default:createApexTestWireAdapter(jest.fn())}; }, {virtual:true});
jest.mock('@salesforce/apex/AEIR_OrgSetupService.saveConfig', () => ({default:jest.fn()}), {virtual:true});
jest.mock('@salesforce/apex/AEIR_SetupHealthCheckService.run', () => ({default:jest.fn()}), {virtual:true});
jest.mock('@salesforce/apex/AEIR_SetupHealthCheckService.runWithProbe', () => ({default:jest.fn()}), {virtual:true});
jest.mock('@salesforce/apex/AEIR_FlowCoverageService.scan', () => ({default:jest.fn()}), {virtual:true});
const configAdapter=getConfig;
const flush=async()=>{for(let i=0;i<6;i++) await Promise.resolve();};
const report={overallStatus:'PASS',passCount:10,warningCount:0,failCount:0,checks:[]};
const button=(element,label)=>[...element.shadowRoot.querySelectorAll('lightning-button')].find(item=>item.label===label);

describe('setup health consent and honest scope',()=>{
    let element;
    beforeEach(async()=>{
        runHealthCheck.mockResolvedValue(report); runCaptureProbe.mockResolvedValue(report);
        element=createElement('c-aegis-setup-wizard',{is:AegisSetupWizard});document.body.appendChild(element);
        configAdapter.emit({onboardingComplete:true,developerTeamEmail:'developer@customer.test'});await flush();
    });
    afterEach(()=>{while(document.body.firstChild) document.body.firstChild.remove();jest.clearAllMocks();});
    it('uses the read-only health endpoint for the normal check',async()=>{
        button(element,'Run read-only health check').click(); await flush();
        expect(runHealthCheck).toHaveBeenCalledTimes(1);expect(runCaptureProbe).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('does not send a report');
    });
    it('requires explicit probe consent and consumes that consent once',async()=>{
        expect(button(element,'Run capture probe').disabled).toBe(true);
        const consent=[...element.shadowRoot.querySelectorAll('lightning-input')].find(item=>item.type==='checkbox');
        consent.checked=true;consent.dispatchEvent(new CustomEvent('change')); await flush();
        button(element,'Run capture probe').click();await flush();
        expect(runCaptureProbe).toHaveBeenCalledTimes(1);expect(runHealthCheck).not.toHaveBeenCalled();
        expect(button(element,'Run capture probe').disabled).toBe(true);
        expect(element.shadowRoot.textContent).toContain('follow-up notifications and diagnosis requests suppressed');
    });
    it('exposes an actionable error instead of a healthy report when access fails',async()=>{
        runHealthCheck.mockRejectedValue({body:{message:'Configuration access denied'}});
        button(element,'Run read-only health check').click();await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Configuration access denied');
    });
    it('withholds editable onboarding until the saved configuration arrives',async()=>{
        const pending=createElement('c-aegis-setup-wizard',{is:AegisSetupWizard});document.body.appendChild(pending);await flush();
        expect(pending.shadowRoot.querySelector('lightning-spinner').alternativeText).toBe('Loading saved setup');
        expect(pending.shadowRoot.querySelector('lightning-input')).toBeNull();
        expect(button(pending,'Next')).toBeUndefined();
        configAdapter.emit({onboardingComplete:true});await flush();
        expect(pending.shadowRoot.querySelector('lightning-spinner')).toBeNull();
        expect(button(pending,'Run read-only health check')).toBeDefined();
    });
    it('keeps a failed config read from presenting a blank setup that could overwrite existing settings',async()=>{
        configAdapter.error({message:'Configuration unavailable'});await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-input')).toBeNull();
        expect(button(element,'Next')).toBeUndefined();
        expect(button(element,'Save setup')).toBeUndefined();
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });
});
