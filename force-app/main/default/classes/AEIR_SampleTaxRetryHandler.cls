/** Extension example only. It must never report tax recalculation that did not occur. */
public with sharing class AEIR_SampleTaxRetryHandler implements AEIR_RetryHandler {
    public AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request) {
        AEIR_RetryOrchestrationService.RetryResult result = new AEIR_RetryOrchestrationService.RetryResult();
        result.success = false;
        result.status = 'Failed';
        result.message = 'No customer tax recalculation is configured. Register an authorized, idempotent business retry handler before enabling this action.';
        return result;
    }
}
