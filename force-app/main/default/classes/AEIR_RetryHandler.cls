public interface AEIR_RetryHandler {
    AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request);
}