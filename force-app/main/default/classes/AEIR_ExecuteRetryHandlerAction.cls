public with sharing class AEIR_ExecuteRetryHandlerAction {
    @InvocableMethod(label='Aegis Flow: Execute Retry Handler' description='Runs only an active retry handler registered in Retry_Handler__mdt.')
    public static List<AEIR_RetryOrchestrationService.RetryResult> run(List<AEIR_RetryOrchestrationService.RetryRequest> requests) {
        List<AEIR_RetryOrchestrationService.RetryResult> output = new List<AEIR_RetryOrchestrationService.RetryResult>();
        for (AEIR_RetryOrchestrationService.RetryRequest request : requests) output.add(AEIR_RetryOrchestrationService.requestRetry(request));
        return output;
    }
}