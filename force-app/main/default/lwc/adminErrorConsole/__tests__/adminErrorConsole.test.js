import { createElement } from 'lwc';
import AdminErrorConsole from 'c/adminErrorConsole';
import getRecentErrors from '@salesforce/apex/AEIR_AdminConsoleController.getRecentErrors';
import getMetrics from '@salesforce/apex/AEIR_AdminConsoleController.getMetrics';
jest.mock('@salesforce/apex/AEIR_AdminConsoleController.getRecentErrors',()=>{ const {createApexTestWireAdapter}=require('@salesforce/wire-service-jest-util'); return {default:createApexTestWireAdapter(jest.fn())}; },{virtual:true});
jest.mock('@salesforce/apex/AEIR_AdminConsoleController.getMetrics',()=>{ const {createApexTestWireAdapter}=require('@salesforce/wire-service-jest-util'); return {default:createApexTestWireAdapter(jest.fn())}; },{virtual:true});
const errorsAdapter=getRecentErrors;
const metricsAdapter=getMetrics;
const flush=async()=>{for(let i=0;i<4;i++) await Promise.resolve();};
describe('command center data states',()=>{
    let element;
    beforeEach(()=>{element=createElement('c-admin-error-console',{is:AdminErrorConsole});document.body.appendChild(element);});
    afterEach(()=>{while(document.body.firstChild) document.body.firstChild.remove();});
    it('does not claim monitoring health or empty success while loading',()=>{
        expect(element.shadowRoot.textContent).not.toContain('Monitoring active');
        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();
        expect(element.shadowRoot.textContent).not.toContain('No diagnostic incidents found');
    });
    it('distinguishes access errors from a true empty result',async()=>{
        errorsAdapter.error();metricsAdapter.emit({newErrorsToday:0});await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('could not be loaded');
        expect(element.shadowRoot.textContent).not.toContain('No diagnostic incidents found');
        errorsAdapter.emit([]);await flush();
        expect(element.shadowRoot.textContent).toContain('No diagnostic incidents found');
    });
});
