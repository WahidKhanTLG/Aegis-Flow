/**
 * Flow-invocable diagnosis.
 *
 * Flow passes the whole batch in one call, so this diagnosed each error log separately at
 * roughly six operations each. Error logs are now diagnosed in one bulk call and matched back
 * to requests by id.
 */
global with sharing class AEIR_InvokeDiagnosisAction {

    global class Request {
        global Request() {}
        @InvocableVariable global Id errorLogId;
        @InvocableVariable global Id diagnosticSessionId;
    }

    global class Response {
        global Response() {}
        @InvocableVariable global Id diagnosisId;
        @InvocableVariable global String summary;
        @InvocableVariable global String fixability;
        @InvocableVariable global Boolean escalationRequired;
        @InvocableVariable global String recommendedAction;
        @InvocableVariable global String safeRemediationActionKey;
    }

    @InvocableMethod(category='Aegis Flow' label='AEIR Invoke Diagnosis'
        description='Runs deterministic/agentic diagnosis for an Error Log or Diagnostic Session.')
    global static List<Response> invokeDiagnosis(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) return out;

        List<Id> errorLogIds = new List<Id>();
        List<Id> sessionIds = new List<Id>();
        for (Request req : requests) {
            if (req.errorLogId != null) errorLogIds.add(req.errorLogId);
            else if (req.diagnosticSessionId != null) sessionIds.add(req.diagnosticSessionId);
        }
        Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> byLog =
            AEIR_AgentforceGatewayService.diagnoseErrors(errorLogIds);
        Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> bySession =
            AEIR_AgentforceGatewayService.diagnoseSessions(sessionIds);

        for (Request req : requests) {
            AEIR_AgentforceGatewayService.DiagnosisResult d = req.errorLogId != null
                ? byLog.get(req.errorLogId)
                : bySession.get(req.diagnosticSessionId);
            Response r = new Response();
            if (d != null) {
                r.diagnosisId = d.diagnosisId;
                r.summary = d.summary;
                r.fixability = d.fixability;
                r.escalationRequired = d.escalationRequired;
                r.recommendedAction = d.recommendedAction;
                r.safeRemediationActionKey = d.safeRemediationActionKey;
            } else {
                // The record was deleted or is not visible. Returning a blank row would read
                // as a clean diagnosis that found nothing wrong.
                r.summary = 'No diagnosis produced: the referenced record could not be read.';
                r.fixability = 'UNKNOWN';
                r.escalationRequired = true;
            }
            out.add(r);
        }
        return out;
    }
}
