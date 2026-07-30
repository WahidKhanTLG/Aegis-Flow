public with sharing class AEIR_QueueableFinalizer implements System.Finalizer {
    private String correlationId;
    private String sourceName;
    private String objectApiName;
    private String recordId;
    private String contextJson;
    public AEIR_QueueableFinalizer(String correlationId, String sourceName, String objectApiName, String recordId, String contextJson) {
        this.correlationId = correlationId;
        this.sourceName = sourceName;
        this.objectApiName = objectApiName;
        this.recordId = recordId;
        this.contextJson = contextJson;
    }
    public void execute(System.FinalizerContext context) {
        if (String.valueOf(context.getResult()) == 'SUCCESS') return;
        Exception exceptionValue = context.getException();
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = correlationId;
        input.sourceType = 'Queueable';
        input.sourceName = sourceName;
        input.objectApiName = objectApiName;
        input.recordId = recordId;
        input.originalMessage = exceptionValue == null ? 'Queueable failed with result: ' + String.valueOf(context.getResult()) : exceptionValue.getMessage();
        input.stackTrace = exceptionValue == null ? null : exceptionValue.getStackTraceString();
        input.contextJson = contextJson;
        input.severity = 'High';
        AEIR_ErrorCaptureService.capture(input);
    }
}