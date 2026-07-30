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
public with sharing class AEIR_ExecuteRemediationAction {

    /**
     * execute() costs roughly three operations per record (a describe-guarded query, the
     * update, and the audit insert). 40 leaves comfortable headroom under the 150 DML limit
     * for whatever else the calling Flow is doing.
     */
    @TestVisible
    private static final Integer MAX_BATCH = 40;

    public class Request {
        @InvocableVariable public String correlationId;
        @InvocableVariable public String actionKey;
        @InvocableVariable public String objectApiName;
        @InvocableVariable public String recordId;
        @InvocableVariable public String fieldApiName;
        @InvocableVariable public String newValue;
        @InvocableVariable public Boolean confirmed;
        @InvocableVariable public Id errorLogId;
        @InvocableVariable public Id diagnosticSessionId;
    }

    public class Response {
        @InvocableVariable public Boolean success;
        @InvocableVariable public Id remediationActionId;
        @InvocableVariable public String userMessage;
        @InvocableVariable public String technicalMessage;
    }

    @InvocableMethod(label='AEIR Execute Remediation'
        description='Executes a whitelisted remediation action after confirmation.')
    public static List<Response> executeRemediation(List<Request> requests) {
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