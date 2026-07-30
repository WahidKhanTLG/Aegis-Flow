public with sharing class AEIR_SampleTaxRetryHandler implements AEIR_RetryHandler {
    public AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request) {
        AEIR_RetryOrchestrationService.RetryResult res = new AEIR_RetryOrchestrationService.RetryResult();
        res.success = true;
        res.message = 'Sample retry handler executed. Replace this class with customer-specific idempotent tax recalculation logic.';
        res.externalReference = request == null ? null : String.valueOf(request.targetRecordId);
        return res;
    }
}