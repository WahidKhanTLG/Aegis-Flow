/**
 * Escalation_Requested__e subscriber.
 *
 * The platform delivers up to 200 events per batch, so this ran createForError() 200 times
 * in a loop. Each call cost several DML, which meant an incident storm - the exact condition
 * that raises escalations in the first place - blew the DML limit and the whole batch was
 * retried, then discarded. Events are now grouped by route key and each group escalated in
 * one bulk call.
 */
public with sharing class AEIR_EscalationRequestedEventHandler {

    public static void handle(List<Escalation_Requested__e> events) {
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('EscalationRequested');

        // Route key varies per event and the bulk API resolves one route per call, so the
        // batch is partitioned by route. A blank key means "let the router decide" and is a
        // group of its own.
        Map<String, List<Id>> logIdsByRoute = new Map<String, List<Id>>();
        Map<String, List<Id>> sessionIdsByRoute = new Map<String, List<Id>>();
        Map<String, String> correlationById = new Map<String, String>();

        for (Escalation_Requested__e evt : events) {
            String routeKey = String.isBlank(evt.Route_Key__c) ? '' : evt.Route_Key__c;
            try {
                if (!String.isBlank(evt.Error_Log_Id__c)) {
                    add(logIdsByRoute, routeKey, (Id) evt.Error_Log_Id__c);
                    correlationById.put(evt.Error_Log_Id__c, evt.Correlation_Id__c);
                } else if (!String.isBlank(evt.Session_Id__c)) {
                    add(sessionIdsByRoute, routeKey, (Id) evt.Session_Id__c);
                    correlationById.put(evt.Session_Id__c, evt.Correlation_Id__c);
                }
            } catch (Exception malformed) {
                // A malformed id must not cost the other 199 events their escalation.
                telemetry.record(evt.Correlation_Id__c, malformed);
            }
        }

        for (String routeKey : logIdsByRoute.keySet()) {
            List<Id> logIds = logIdsByRoute.get(routeKey);
            try {
                AEIR_EscalationService.createForErrors(logIds, blankToNull(routeKey), true);
            } catch (Exception groupFailure) {
                // Report every event in the group. A route-level failure such as a
                // deactivated Escalation_Route__mdt affects all of them, and recording it
                // once would understate the blast radius in the telemetry.
                recordAll(telemetry, logIds, correlationById, groupFailure);
            }
        }

        for (String routeKey : sessionIdsByRoute.keySet()) {
            List<Id> sessionIds = sessionIdsByRoute.get(routeKey);
            try {
                AEIR_EscalationService.createForSessions(sessionIds, blankToNull(routeKey), true);
            } catch (Exception groupFailure) {
                recordAll(telemetry, sessionIds, correlationById, groupFailure);
            }
        }

        telemetry.flush();
    }

    private static void add(Map<String, List<Id>> target, String key, Id value) {
        if (!target.containsKey(key)) target.put(key, new List<Id>());
        target.get(key).add(value);
    }

    private static void recordAll(AEIR_SubscriberTelemetry telemetry, List<Id> ids,
                                  Map<String, String> correlationById, Exception failure) {
        for (Id recordId : ids) {
            telemetry.record(correlationById.get(String.valueOf(recordId)), failure);
        }
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value;
    }
}