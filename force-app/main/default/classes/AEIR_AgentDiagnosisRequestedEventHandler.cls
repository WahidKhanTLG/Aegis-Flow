/** Bulk, failure-isolated subscriber for error and manual-session diagnosis requests. */
public with sharing class AEIR_AgentDiagnosisRequestedEventHandler {
    public class EventReferenceException extends Exception {}

    public static void handle(List<Agent_Diagnosis_Requested__e> events) {
        if (events == null || events.isEmpty()) return;
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('AgentDiagnosisRequested');
        List<Id> errorLogIds = new List<Id>();
        List<Id> sessionIds = new List<Id>();
        Map<Id, Set<String>> correlations = new Map<Id, Set<String>>();
        for (Agent_Diagnosis_Requested__e evt : events) {
            try {
                if (evt == null) throw new EventReferenceException('A diagnosis event is required.');
                Boolean hasError = !String.isBlank(evt.Error_Log_Id__c);
                Boolean hasSession = !String.isBlank(evt.Session_Id__c);
                if (hasError == hasSession) throw new EventReferenceException('A diagnosis event must identify exactly one error or session.');
                Id reference = validReference(hasError ? evt.Error_Log_Id__c : evt.Session_Id__c,
                    hasError ? Error_Log__c.SObjectType : Diagnostic_Session__c.SObjectType);
                if (!correlations.containsKey(reference)) {
                    correlations.put(reference, new Set<String>());
                    if (hasError) errorLogIds.add(reference);
                    else sessionIds.add(reference);
                }
                correlations.get(reference).add(evt.Correlation_Id__c);
            } catch (Exception malformed) {
                telemetry.record(evt == null ? null : evt.Correlation_Id__c, malformed);
            }
        }
        if (!errorLogIds.isEmpty()) {
            try {
                Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> results = AEIR_AgentforceGatewayService.diagnoseErrors(errorLogIds);
                recordUnavailable(telemetry, errorLogIds, correlations, results);
            }
            catch (Exception batchFailure) { recordAll(telemetry, errorLogIds, correlations, batchFailure); }
        }
        if (!sessionIds.isEmpty()) {
            try {
                Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> results = AEIR_AgentforceGatewayService.diagnoseSessions(sessionIds);
                recordUnavailable(telemetry, sessionIds, correlations, results);
            }
            catch (Exception batchFailure) { recordAll(telemetry, sessionIds, correlations, batchFailure); }
        }
        telemetry.flush();
    }

    private static Id validReference(String value, Schema.SObjectType expectedType) {
        Id reference;
        try { reference = (Id)value; }
        catch (Exception invalidId) { throw new EventReferenceException('The event contains an invalid Salesforce record Id.'); }
        if (reference.getSObjectType() != expectedType) throw new EventReferenceException('The event record Id belongs to the wrong object.');
        return reference;
    }
    private static void recordUnavailable(AEIR_SubscriberTelemetry telemetry, List<Id> references,
        Map<Id, Set<String>> correlations, Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> results) {
        List<Id> missing = new List<Id>();
        for (Id reference : references) if (!results.containsKey(reference)) missing.add(reference);
        recordAll(telemetry, missing, correlations, new EventReferenceException('The requested diagnostic record is not available to this subscriber.'));
    }
    private static void recordAll(AEIR_SubscriberTelemetry telemetry, List<Id> references,
        Map<Id, Set<String>> correlations, Exception failure) {
        for (Id reference : references) for (String correlation : correlations.get(reference)) telemetry.record(correlation, failure);
    }
}
