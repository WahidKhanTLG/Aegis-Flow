/**
 * Diagnostic_Session_Requested__e subscriber.
 *
 * The platform delivers up to 200 events per batch and this created sessions one at a time,
 * at one query plus one insert each, so the SOQL limit was reached at 100 events. Inputs are
 * now built for the whole batch and created in one call.
 */
public with sharing class AEIR_DiagnosticSessionRequestHandler {

    public static void handle(List<Diagnostic_Session_Requested__e> events) {
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('DiagnosticSessionRequested');

        List<AEIR_DiagnosticSessionService.SessionInput> inputs =
            new List<AEIR_DiagnosticSessionService.SessionInput>();
        List<String> correlationIds = new List<String>();

        for (Diagnostic_Session_Requested__e evt : events) {
            try {
                // An event that already carries a session id was raised by a session that
                // exists; creating another would duplicate the user's report.
                if (!String.isBlank(evt.Session_Id__c)) continue;
                AEIR_DiagnosticSessionService.SessionInput input =
                    new AEIR_DiagnosticSessionService.SessionInput();
                input.correlationId = evt.Correlation_Id__c;
                input.userId = evt.User_Id__c;
                input.pageReferenceJson = evt.Page_Reference_JSON__c;
                input.userDescription = evt.User_Description__c;
                input.detectedIssueType = 'Report Issue';
                input.createdFrom = 'Platform Event';
                Map<String, Object> ctx = parse(evt.Page_Reference_JSON__c);
                input.contextRecordId = stringValue(ctx.get('recordId'));
                input.objectApiName = stringValue(ctx.get('objectApiName'));
                input.pageUrl = stringValue(ctx.get('pageUrl'));
                input.browserContextJson = evt.Page_Reference_JSON__c;
                inputs.add(input);
                correlationIds.add(evt.Correlation_Id__c);
            } catch (Exception malformed) {
                telemetry.record(evt.Correlation_Id__c, malformed);
            }
        }

        if (!inputs.isEmpty()) {
            try {
                AEIR_DiagnosticSessionService.createSessions(inputs);
            } catch (Exception batchFailure) {
                // Every event in the batch lost its session, so report each one rather than
                // logging a single entry that hides how many users were affected.
                for (String correlationId : correlationIds) {
                    telemetry.record(correlationId, batchFailure);
                }
            }
        }

        telemetry.flush();
    }

    private static Map<String, Object> parse(String payload) {
        if (String.isBlank(payload)) return new Map<String, Object>();
        try { return (Map<String, Object>) JSON.deserializeUntyped(payload); }
        catch (Exception ex) { return new Map<String, Object>(); }
    }

    private static String stringValue(Object value) { return value == null ? null : String.valueOf(value); }
}