public with sharing class AEIR_BatchApexErrorEventHandler {
    public static void handle(List<BatchApexErrorEvent> events) {
        if (events == null || events.isEmpty()) return;
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('BatchApexError');
        List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        for (BatchApexErrorEvent evt : events) {
            if (evt == null) {
                telemetry.record(null, new BatchCaptureException('A Batch failure event is required.'));
                continue;
            }
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = correlationFor(evt);
            input.sourceType = 'Batch';
            input.userId = evt.CreatedById == null ? null : String.valueOf(evt.CreatedById);
            input.sourceName = String.valueOf(evt.AsyncApexJobId);
            input.originalMessage = evt.ExceptionType + ': ' + evt.Message;
            input.stackTrace = evt.StackTrace;
            input.contextJson = JSON.serialize(new Map<String,Object>{
                'AsyncApexJobId' => evt.AsyncApexJobId,
                'JobScope' => AEIR_SecuritySanitizerService.safeTruncate(evt.JobScope, 20000),
                'Phase' => evt.Phase, 'EventUuid' => evt.EventUuid,
                'DoesExceedJobScopeMaxLength' => evt.DoesExceedJobScopeMaxLength,
                'scopeTruncatedByAegis' => evt.JobScope != null && evt.JobScope.length() > 20000 });
            input.severity = 'High';
            inputs.add(input);
        }
        telemetry.flush();
        AEIR_ErrorCapturedEventHandler.captureInputs(inputs, 'BatchApexError');
    }
    @TestVisible
    private static String correlationFor(BatchApexErrorEvent event) {
        String identity = String.isBlank(event.EventUuid) ? JSON.serialize(new List<Object>{
            event.AsyncApexJobId, event.Phase, event.JobScope, event.ExceptionType,
            event.Message, event.StackTrace, event.CreatedDate, event.ReplayId }) : event.EventUuid;
        return 'BATCH-' + String.valueOf(event.AsyncApexJobId) + '-' + EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(identity))).substring(0, 40);
    }
    private class BatchCaptureException extends Exception {}
}
