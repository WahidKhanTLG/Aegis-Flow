global with sharing class AEIR_ExecuteRetryHandlerAction {
    @InvocableMethod(category='Aegis Flow' label='Aegis Flow: Execute Retry Handler' description='Runs authorized registered handlers. Supports at most 20 synchronous requests per transaction; split larger batches.')
    global static List<AEIR_RetryOrchestrationService.RetryResult> run(List<AEIR_RetryOrchestrationService.RetryRequest> requests) {
        return AEIR_RetryOrchestrationService.requestRetries(requests);
    }
}
