import { createElement } from 'lwc';
import AegisWorkspace from 'c/aegisWorkspace';
import getAvailableActions from '@salesforce/apex/AEIR_RemediationController.getAvailableActions';
import prepareProposal from '@salesforce/apex/AEIR_RemediationController.prepareProposal';
import executeRemediation from '@salesforce/apex/AEIR_RemediationController.executeRemediation';
import collectForError from '@salesforce/apex/AEIR_LogCollectorService.collectForError';
import { CurrentPageReference } from 'lightning/navigation';
jest.mock('@salesforce/customPermission/AEIR_Execute_Remediation',()=>({default:true}),{virtual:true});
jest.mock('@salesforce/apex/AEIR_RemediationController.getAvailableActions',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/AEIR_RemediationController.prepareProposal',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/AEIR_RemediationController.executeRemediation',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/AEIR_LogCollectorService.collectForError',()=>({default:jest.fn()}),{virtual:true});
const flush=async()=>{for(let i=0;i<8;i++) await Promise.resolve();};
const button=(element,label)=>[...element.shadowRoot.querySelectorAll('lightning-button')].find(item=>item.label===label);
const input=(element,label)=>[...element.shadowRoot.querySelectorAll('lightning-input')].find(item=>item.label===label);
const setInput=async(element,label,value)=>{input(element,label).dispatchEvent(new CustomEvent('change',{detail:{value}}));await flush();};

describe('functional diagnostic workspace',()=>{
    let element;
    beforeEach(async()=>{
        getAvailableActions.mockResolvedValue([{actionKey:'REGISTERED',label:'Registered correction',objectApiName:'Account',fieldApiName:'Description'}]);
        element=createElement('c-aegis-workspace',{is:AegisWorkspace});document.body.appendChild(element);await flush();
    });
    afterEach(()=>{while(document.body.firstChild) document.body.firstChild.remove();jest.clearAllMocks();});
    it('loads supplied current-record context and mounts the actual save capture surface',async()=>{
        CurrentPageReference.emit({attributes:{recordId:'003000000000001AAA',objectApiName:'Contact'}});await flush();
        const capture=element.shadowRoot.querySelector('c-aegis-ui-save-capture');
        expect(capture.recordId).toBe('003000000000001AAA');expect(capture.objectApiName).toBe('Contact');
        expect(element.shadowRoot.querySelector('c-aegis-get-help-panel').recordId).toBe(capture.recordId);
    });
    it('rejects malformed context without mounting a save form',async()=>{
        await setInput(element,'Salesforce record Id','bad');await setInput(element,'Object API name','Account');
        button(element,'Load record context').click();await flush();
        expect(element.shadowRoot.querySelector('c-aegis-ui-save-capture')).toBeNull();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('15- or 18-character');
    });
    it('prepares actual evidence and delegates confirmation, without optimistic execution',async()=>{
        const proposal={actionKey:'REGISTERED',objectApiName:'Account',fieldApiName:'Description',recordId:'001000000000001AAA',beforeValue:'Before',newValue:'After'};
        prepareProposal.mockResolvedValue(proposal);
        element.shadowRoot.querySelector('lightning-combobox').dispatchEvent(new CustomEvent('change',{detail:{value:'REGISTERED'}}));
        await setInput(element,'Correction target record Id',proposal.recordId);
        element.shadowRoot.querySelector('lightning-textarea').dispatchEvent(new CustomEvent('change',{detail:{value:'After'}}));await flush();
        button(element,'Prepare correction for review').click();await flush();
        expect(prepareProposal).toHaveBeenCalledWith({actionKey:'REGISTERED',recordId:proposal.recordId,newValue:'After',correlationId:null});
        expect(element.shadowRoot.querySelector('c-aegis-remediation-confirmation').proposal).toEqual(proposal);
        expect(executeRemediation).not.toHaveBeenCalled();
        const confirmation=element.shadowRoot.querySelector('c-aegis-remediation-confirmation');
        confirmation.dispatchEvent(new CustomEvent('executionstatechange',{detail:{pending:true}}));await flush();
        expect(button(element,'Load record context').disabled).toBe(true);
        expect(input(element,'Correction target record Id').disabled).toBe(true);
        confirmation.dispatchEvent(new CustomEvent('executionstatechange',{detail:{pending:false}}));await flush();
        expect(button(element,'Load record context').disabled).toBe(false);
        await setInput(element,'Correction target record Id','001000000000002AAA');
        expect(element.shadowRoot.querySelector('c-aegis-remediation-confirmation')).toBeNull();
    });
    it('does not resurrect a stale proposal after the target changes',async()=>{
        let resolveProposal;prepareProposal.mockImplementation(()=>new Promise(resolve=>{resolveProposal=resolve;}));
        element.shadowRoot.querySelector('lightning-combobox').dispatchEvent(new CustomEvent('change',{detail:{value:'REGISTERED'}}));
        await setInput(element,'Correction target record Id','001000000000001AAA');
        element.shadowRoot.querySelector('lightning-textarea').dispatchEvent(new CustomEvent('change',{detail:{value:'After'}}));await flush();
        button(element,'Prepare correction for review').click();await flush();
        await setInput(element,'Correction target record Id','001000000000002AAA');resolveProposal({actionKey:'REGISTERED'});await flush();
        expect(element.shadowRoot.querySelector('c-aegis-remediation-confirmation')).toBeNull();
    });
    it('shows escaped ephemeral log text and clears it on a new selection',async()=>{
        collectForError.mockResolvedValue({bodyRetrieved:true,debugLogBody:'<script>safe text</script>',truncated:true,message:'Sanitized body retrieved'});
        const picker=[...element.shadowRoot.querySelectorAll('lightning-record-picker')].find(item=>item.objectApiName==='Error_Log__c');
        picker.dispatchEvent(new CustomEvent('change',{detail:{recordId:'a01000000000001AAA'}}));await flush();
        button(element,'Retrieve authorized log evidence').click();await flush();
        expect(collectForError).toHaveBeenCalledWith({errorLogId:'a01000000000001AAA'});
        expect(element.shadowRoot.querySelector('pre').textContent).toBe('<script>safe text</script>');
        expect(element.shadowRoot.querySelector('pre').querySelector('script')).toBeNull();
        picker.dispatchEvent(new CustomEvent('change',{detail:{recordId:'a01000000000002AAA'}}));await flush();
        expect(element.shadowRoot.querySelector('pre')).toBeNull();
    });
    it('ignores late log evidence after clearing or changing selection',async()=>{
        let resolveLog;collectForError.mockImplementation(()=>new Promise(resolve=>{resolveLog=resolve;}));
        const picker=[...element.shadowRoot.querySelectorAll('lightning-record-picker')].find(item=>item.objectApiName==='Error_Log__c');
        picker.dispatchEvent(new CustomEvent('change',{detail:{recordId:'a01000000000001AAA'}}));await flush();
        button(element,'Retrieve authorized log evidence').click();await flush();
        button(element,'Clear debug-log evidence').click();await flush();
        resolveLog({bodyRetrieved:true,debugLogBody:'stale evidence'});await flush();
        expect(element.shadowRoot.querySelector('pre')).toBeNull();
        expect(element.shadowRoot.textContent).not.toContain('stale evidence');
    });
    it('does not imply a linked reference contains a retrieved body',async()=>{
        collectForError.mockResolvedValue({bodyRetrieved:false,debugLogBody:null,message:'Body collection disabled',debugLogLink:'/setup/logs'});
        const picker=[...element.shadowRoot.querySelectorAll('lightning-record-picker')].find(item=>item.objectApiName==='Error_Log__c');
        picker.dispatchEvent(new CustomEvent('change',{detail:{recordId:'a01000000000001AAA'}}));await flush();
        button(element,'Retrieve authorized log evidence').click();await flush();
        expect(element.shadowRoot.querySelector('pre')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Body collection disabled');
        button(element,'Clear record context').click();await flush();
        expect(button(element,'Retrieve authorized log evidence').disabled).toBe(true);
    });

});
