/**
 * Agent_Diagnosis_Requested__e subscriber.
 *
 * The platform delivers up to 200 events per batch and this diagnosed them one at a time, at
 * roughly six operations each. An error storm - the condition that generates these events in
 * the first place - exhausted limits around thirty logs, and the whole batch was retried and
 * then discarded. Error logs are now diagnosed in one bulk call.
 *
 * Sessions are batched the same way. They usually arrive singly from a "get help" click, but
 * "usually" is an assumption about user behaviour, not a bound the platform enforces.
 */
public with sharing class AEIR_AgentDiagnosisRequestedEventHandler {

    public static void handle(List<Agent_Diagnosis_Requested__e> events) {
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('AgentDiagnosisRequested');

        List<Id> errorLogIds = new List<Id>();
        Map<String, String> correlationById = new Map<String, String>();
        List<Id> sessionIds = new List<Id>();

        for (Agent_Diagnosis_Requested__e evt : events) {
            try {
                if (!String.isBlank(evt.Error_Log_Id__c)) {
                    errorLogIds.add((Id) evt.Error_Log_Id__c);
                    correlationById.put(evt.Error_Log_Id__c, evt.Correlation_Id__c);
                } else if (!String.isBlank(evt.Session_Id__c)) {
                    sessionIds.add((Id) evt.Session_Id__c);
                    correlationById.put(evt.Session_Id__c, evt.Correlation_Id__c);
                }
            } catch (Exception malformed) {
                telemetry.record(evt.Correlation_Id__c, malformed);
            }
        }

        if (!errorLogIds.isEmpty()) {
            try {
                AEIR_AgentforceGatewayService.diagnoseErrors(errorLogIds);
            } catch (Exception batchFailure) {
                // Report every log in the batch: a failure here costs all of them their
                // diagnosis, and recording it once would understate the impact.
                for (Id logId : errorLogIds) {
                    telemetry.record(correlationById.get(String.valueOf(logId)), batchFailure);
                }
            }
        }

        if (!sessionIds.isEmpty()) {
            try {
                AEIR_AgentforceGatewayService.diagnoseSessions(sessionIds);
            } catch (Exception batchFailure) {
                for (Id sessionId : sessionIds) {
                    telemetry.record(correlationById.get(String.valueOf(sessionId)), batchFailure);
                }
            }
        }

        telemetry.flush();
    }
}