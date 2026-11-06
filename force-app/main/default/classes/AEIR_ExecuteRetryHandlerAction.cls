public with sharing class AEIR_ExecuteRetryHandlerAction {
    @InvocableMethod(label='Aegis Flow: Execute Retry Handler' description='Runs authorized registered handlers. Supports at most 20 synchronous requests per transaction; split larger batches.')
    public static List<AEIR_RetryOrchestrationService.RetryResult> run(List<AEIR_RetryOrchestrationService.RetryRequest> requests) {
        return AEIR_RetryOrchestrationService.requestRetries(requests);
    }
}
