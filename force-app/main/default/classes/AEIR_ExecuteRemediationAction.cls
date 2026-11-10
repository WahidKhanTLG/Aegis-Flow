/**
 * Flow-invocable governed remediation.
 *
 * This one stays per-record on purpose, unlike the other invocable actions in the product.
 * AEIR_RemediationOrchestrator.execute() enforces the whitelist, the CRUD/FLS check and the
 * confirmation flag for one specific field on one specific record, and writes an individually
 * approved Remediation_Action__c audit row. Batching those writes would mean a single
 * approval covering a set, which is precisely the governance the spec requires it not do.
 *
 * The real exposure is therefore a limits failure part-way through a large batch: some
 * records changed, some did not, and the caller cannot tell which. So the batch size is
 * capped and anything above the cap is refused up front with an explicit message rather than
 * being half-applied.
 */
global with sharing class AEIR_ExecuteRemediationAction {

    /** Successful work uses four statements; audit-failure rollback can use six.
     * Twenty inputs leave headroom for the caller, and the service rechecks capacity. */
    @TestVisible
    private static final Integer MAX_BATCH = 20;

    global class Request {
        global Request() {}
        @InvocableVariable global String correlationId;
        @InvocableVariable global String actionKey;
        @InvocableVariable global String objectApiName;
        @InvocableVariable global String recordId;
        @InvocableVariable global String fieldApiName;
        @InvocableVariable global String newValue;
        @InvocableVariable global Boolean confirmed;
        @InvocableVariable global Id errorLogId;
        @InvocableVariable global Id diagnosticSessionId;
    }

    global class Response {
        global Response() {}
        @InvocableVariable global Boolean success;
        @InvocableVariable global Id remediationActionId;
        @InvocableVariable global String userMessage;
        @InvocableVariable global String technicalMessage;
    }

    @InvocableMethod(category='Aegis Flow' label='AEIR Execute Remediation'
        description='Executes a whitelisted remediation action after confirmation.')
    global static List<Response> executeRemediation(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) return out;

        if (requests.size() > MAX_BATCH) {
            // Refuse the whole batch. Remediation writes to customer records, so a partial
            // application that dies on a governor limit is worse than doing nothing.
            for (Integer i = 0; i < requests.size(); i++) {
                Response r = new Response();
                r.success = false;
                r.userMessage = 'This fix was not applied. Too many records were submitted at once.';
                r.technicalMessage = 'Aegis Flow applies governed remediations one record at a time so each '
                    + 'is individually approved and audited. This batch had ' + requests.size()
                    + ' records; the limit is ' + MAX_BATCH + '. Split the batch and retry.';
                out.add(r);
            }
            return out;
        }

        for (Request req : requests) {
            Response r = new Response();
            try {
                AEIR_RemediationOrchestrator.RemediationRequest rr =
                    new AEIR_RemediationOrchestrator.RemediationRequest();
                rr.correlationId = req.correlationId;
                rr.actionKey = req.actionKey;
                rr.objectApiName = req.objectApiName;
                rr.recordId = req.recordId;
                rr.fieldApiName = req.fieldApiName;
                rr.newValue = req.newValue;
                rr.confirmed = req.confirmed;
                rr.errorLogId = req.errorLogId;
                rr.diagnosticSessionId = req.diagnosticSessionId;
                AEIR_RemediationOrchestrator.RemediationResult er = AEIR_RemediationOrchestrator.execute(rr);
                r.success = er.success;
                r.remediationActionId = er.remediationActionId;
                r.userMessage = er.userMessage;
                r.technicalMessage = er.technicalMessage;
            } catch (Exception remediationFailure) {
                // One record's failure must not abandon the rest of the batch unreported.
                r.success = false;
                r.userMessage = 'This fix could not be applied.';
                r.technicalMessage = AEIR_SecuritySanitizerService.mask(remediationFailure.getMessage());
            }
            out.add(r);
        }
        return out;
    }
}
