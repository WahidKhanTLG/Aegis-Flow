/**
 * Flow-invocable field remediation.
 *
 * Per-record by design, for the same reason as AEIR_ExecuteRemediationAction: the orchestrator
 * enforces the whitelist, CRUD/FLS and the confirmation flag for one field on one record, and
 * writes an individually approved audit row. The batch is capped so a large call is refused
 * outright instead of dying half-applied on a governor limit.
 */
public with sharing class AEIR_UpdateMissingFieldAction {

    /** See AEIR_ExecuteRemediationAction.MAX_BATCH; kept in step with it deliberately. */
    @TestVisible
    private static final Integer MAX_BATCH = 40;

    public class Request {
        @InvocableVariable public String correlationId;
        @InvocableVariable(required=true) public String actionKey;
        @InvocableVariable(required=true) public String objectApiName;
        @InvocableVariable(required=true) public String recordId;
        @InvocableVariable(required=true) public String fieldApiName;
        @InvocableVariable public String newValue;
        @InvocableVariable public Boolean confirmed;
        @InvocableVariable public Id errorLogId;
        @InvocableVariable public Id diagnosticSessionId;
    }
    public class Response {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String correlationId;
        @InvocableVariable public Id remediationActionId;
        @InvocableVariable public String status;
        @InvocableVariable public String userMessage;
        @InvocableVariable public String technicalMessage;
        @InvocableVariable public Boolean retryRecommended;
        @InvocableVariable public Boolean escalationRecommended;
    }
    @InvocableMethod(label='Aegis Flow: Update Missing Field' description='Executes a configured field remediation after whitelist, confirmation, CRUD/FLS, and sharing checks.')
    public static List<Response> run(List<Request> requests) {
        List<Response> output = new List<Response>();
        if (requests == null || requests.isEmpty()) return output;

        if (requests.size() > MAX_BATCH) {
            // Refuse the whole batch: a partial application that dies on a limit leaves the
            // caller unable to tell which customer records were changed.
            for (Integer i = 0; i < requests.size(); i++) {
                Response refused = new Response();
                refused.success = false;
                refused.status = 'Refused';
                refused.userMessage = 'This fix was not applied. Too many records were submitted at once.';
                refused.technicalMessage = 'Aegis Flow applies governed remediations one record at a time so '
                    + 'each is individually approved and audited. This batch had ' + requests.size()
                    + ' records; the limit is ' + MAX_BATCH + '. Split the batch and retry.';
                refused.escalationRecommended = false;
                refused.retryRecommended = false;
                output.add(refused);
            }
            return output;
        }

        for (Request request : requests) {
            AEIR_RemediationOrchestrator.RemediationRequest remediationRequest = new AEIR_RemediationOrchestrator.RemediationRequest();
            remediationRequest.correlationId = request.correlationId;
            remediationRequest.actionKey = request.actionKey;
            remediationRequest.objectApiName = request.objectApiName;
            remediationRequest.recordId = request.recordId;
            remediationRequest.fieldApiName = request.fieldApiName;
            remediationRequest.newValue = request.newValue;
            remediationRequest.confirmed = request.confirmed;
            remediationRequest.errorLogId = request.errorLogId;
            remediationRequest.diagnosticSessionId = request.diagnosticSessionId;
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(remediationRequest);
            Response response = new Response();
            response.success = result.success;
            response.correlationId = result.correlationId;
            response.remediationActionId = result.remediationActionId;
            response.status = result.status;
            response.userMessage = result.userMessage;
            response.technicalMessage = result.technicalMessage;
            response.retryRecommended = result.retryRecommended;
            response.escalationRecommended = result.escalationRecommended;
            output.add(response);
        }
        return output;
    }
}