/** Bulk escalation subscriber. Invalid events and failed routes do not abandon other groups. */
public with sharing class AEIR_EscalationRequestedEventHandler {
    public class EventReferenceException extends Exception {}

    public static void handle(List<Escalation_Requested__e> events) {
        if (events == null || events.isEmpty()) return;
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('EscalationRequested');
        Map<String, List<Id>> logIdsByRoute = new Map<String, List<Id>>();
        Map<String, List<Id>> sessionIdsByRoute = new Map<String, List<Id>>();
        Map<String, Map<Id, Set<String>>> correlationsByRoute = new Map<String, Map<Id, Set<String>>>();
        for (Escalation_Requested__e evt : events) {
            try {
                if (evt == null) throw new EventReferenceException('An escalation event is required.');
                String routeKey = String.isBlank(evt.Route_Key__c) ? '' : evt.Route_Key__c.trim();
                Boolean hasError = !String.isBlank(evt.Error_Log_Id__c);
                Boolean hasSession = !String.isBlank(evt.Session_Id__c);
                if (hasError == hasSession) throw new EventReferenceException('An escalation event must identify exactly one error or session.');
                Id reference = validReference(hasError ? evt.Error_Log_Id__c : evt.Session_Id__c,
                    hasError ? Error_Log__c.SObjectType : Diagnostic_Session__c.SObjectType);
                add(hasError ? logIdsByRoute : sessionIdsByRoute, correlationsByRoute,
                    routeKey, reference, evt.Correlation_Id__c);
            } catch (Exception malformed) {
                telemetry.record(evt == null ? null : evt.Correlation_Id__c, malformed);
            }
        }
        for (String routeKey : logIdsByRoute.keySet()) {
            try { AEIR_EscalationService.createForErrors(logIdsByRoute.get(routeKey), blankToNull(routeKey), true); }
            catch (Exception groupFailure) { recordAll(telemetry, logIdsByRoute.get(routeKey), correlationsByRoute.get(routeKey), groupFailure); }
        }
        for (String routeKey : sessionIdsByRoute.keySet()) {
            try { AEIR_EscalationService.createForSessions(sessionIdsByRoute.get(routeKey), blankToNull(routeKey), true); }
            catch (Exception groupFailure) { recordAll(telemetry, sessionIdsByRoute.get(routeKey), correlationsByRoute.get(routeKey), groupFailure); }
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
    private static void add(Map<String, List<Id>> target, Map<String, Map<Id, Set<String>>> correlations,
        String key, Id value, String correlation) {
        if (!target.containsKey(key)) target.put(key, new List<Id>());
        if (!correlations.containsKey(key)) correlations.put(key, new Map<Id, Set<String>>());
        if (!correlations.get(key).containsKey(value)) {
            correlations.get(key).put(value, new Set<String>());
            target.get(key).add(value);
        }
        correlations.get(key).get(value).add(correlation);
    }
    private static void recordAll(AEIR_SubscriberTelemetry telemetry, List<Id> ids,
        Map<Id, Set<String>> correlations, Exception failure) {
        for (Id reference : ids) for (String correlation : correlations.get(reference)) telemetry.record(correlation, failure);
    }
    private static String blankToNull(String value) { return String.isBlank(value) ? null : value; }
}
