public with sharing class AEIR_ErrorCapturedEventHandler {
    public static void handle(List<Error_Captured__e> events) {
        if (events == null || events.isEmpty()) return;
        List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('ErrorCaptured');
        for (Error_Captured__e evt : events) {
            if (evt == null) {
                telemetry.record(null, new CaptureProcessingException('A capture event is required.'));
                continue;
            }
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = evt.Correlation_Id__c;
            input.sourceType = evt.Source_Type__c;
            input.sourceName = evt.Source_Name__c;
            input.originalMessage = evt.Error_Message__c;
            input.recordId = evt.Record_Id__c;
            input.objectApiName = evt.Object_API_Name__c;
            input.contextJson = evt.Context_JSON__c;
            input.severity = evt.Severity__c;
            input.userId = evt.User_Id__c;
            input.stackTrace = evt.Stack_Trace__c;
            input.actionName = evt.Action_Name__c;
            input.pageUrl = evt.Page_URL__c;
            inputs.add(input);
        }
        telemetry.flush();
        captureInputs(inputs, 'ErrorCaptured');
    }
    /** Shared by trusted capture adapters; every rejected input gets telemetry. */
    public static List<AEIR_ErrorCaptureService.CaptureResult> captureInputs(
        List<AEIR_ErrorCaptureService.ErrorInput> inputs, String subscriber) {
        if (inputs == null || inputs.isEmpty()) return new List<AEIR_ErrorCaptureService.CaptureResult>();
        List<AEIR_ErrorCaptureService.CaptureResult> results = AEIR_ErrorCaptureService.captureFromEvents(inputs);
        Boolean nativeEventDelivery = Trigger.isExecuting && Trigger.new != null && !Trigger.new.isEmpty()
            && (Trigger.new[0] instanceof Error_Captured__e || Trigger.new[0] instanceof BatchApexErrorEvent);
        EventBus.TriggerContext context = nativeEventDelivery ? EventBus.TriggerContext.currentContext() : null;
        recordResults(inputs, results, subscriber, context == null ? null : context.retries);
        return results;
    }

    @TestVisible
    private static void recordResults(List<AEIR_ErrorCaptureService.ErrorInput> inputs,
        List<AEIR_ErrorCaptureService.CaptureResult> results, String subscriber, Integer retries) {
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry(subscriber);
        for (Integer i = 0; i < inputs.size(); i++) {
            AEIR_ErrorCaptureService.CaptureResult result = results != null && i < results.size() ? results[i] : null;
            if (result != null && result.success == true) continue;
            // Throwing rolls back this delivery and retries all messages. Stable capture
            // correlations prevent replay from duplicating already committed evidence.
            if (result != null && result.retryable == true && retries != null && retries < 9) {
                throw new EventBus.RetryableException('Aegis capture encountered a temporary persistence failure.');
            }
            telemetry.record(inputs[i] == null ? null : inputs[i].correlationId,
                new CaptureProcessingException(result == null ? 'The capture returned no result.' : result.message));
        }
        telemetry.flush();
    }
    public class CaptureProcessingException extends Exception {}
}
