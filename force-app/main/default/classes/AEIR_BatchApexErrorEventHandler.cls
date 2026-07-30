public with sharing class AEIR_BatchApexErrorEventHandler {
    public static void handle(List<BatchApexErrorEvent> events) {
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('BatchApexError');
        List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        for (BatchApexErrorEvent evt : events) {
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = 'BATCH-' + String.valueOf(evt.AsyncApexJobId);
            input.sourceType = 'Batch';
            input.sourceName = String.valueOf(evt.AsyncApexJobId);
            input.originalMessage = evt.ExceptionType + ': ' + evt.Message;
            input.stackTrace = evt.StackTrace;
            input.contextJson = JSON.serialize(new Map<String,Object>{ 'AsyncApexJobId' => evt.AsyncApexJobId, 'JobScope' => evt.JobScope, 'Phase' => evt.Phase, 'DoesExceedJobScopeMaxLength' => evt.DoesExceedJobScopeMaxLength });
            input.severity = 'High';
            inputs.add(input);
        }
        if (!inputs.isEmpty()) {
            // One bulk capture: an event batch can carry many failed chunks.
            try {
                AEIR_ErrorCaptureService.captureFromEvents(inputs);
            } catch (Exception subscriberFailure) {
                telemetry.record(inputs[0].correlationId, subscriberFailure);
            }
        }
        telemetry.flush();
    }
}