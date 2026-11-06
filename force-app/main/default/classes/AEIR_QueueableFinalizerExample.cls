/**
 * Safe attachment example: the default Queueable performs no customer work and
 * succeeds. The failure branch runs only when real Queueable work fails.
 */
public with sharing class AEIR_QueueableFinalizerExample implements Queueable, Finalizer {
    private String correlationId;
    public AEIR_QueueableFinalizerExample(String correlationId) { this.correlationId = String.isBlank(correlationId) ? AEIR_CorrelationIdService.nextId() : correlationId; }
    public void execute(QueueableContext context) {
        System.attachFinalizer(this);
        // Place customer async work here.
    }
    public void execute(FinalizerContext context) {
        if (context.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            Exception ex = context.getException();
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = correlationId;
            input.sourceType = 'Queueable';
            input.sourceName = String.valueOf(context.getAsyncApexJobId());
            input.originalMessage = ex == null ? 'Queueable failed with unknown exception.' : ex.getMessage();
            input.stackTrace = ex == null ? null : ex.getStackTraceString();
            input.contextJson = JSON.serialize(new Map<String,Object>{ 'asyncApexJobId' => context.getAsyncApexJobId(), 'requestId' => context.getRequestId(), 'result' => String.valueOf(context.getResult()) });
            input.severity = 'High';
            try { AEIR_ErrorCaptureService.capture(input); }
            catch (Exception captureFailure) {
                // Do not conceal a finalizer failure or echo potentially sensitive
                // source exception text into an unrestricted debug log.
                System.debug(LoggingLevel.WARN, 'Aegis Flow: Queueable finalizer could not persist diagnostic evidence.');
            }
        }
    }
}
