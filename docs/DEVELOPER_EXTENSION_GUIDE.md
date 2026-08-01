# Developer Extension Guide

## Capturing Apex errors

```apex
try {
    // customer business logic
} catch (Exception ex) {
    AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
    input.sourceType = 'Apex Class';
    input.sourceName = 'CustomerService';
    input.objectApiName = 'Account';
    input.recordId = accountId;
    input.actionName = 'Customer action name';
    input.originalMessage = ex.getMessage();
    input.stackTrace = ex.getStackTraceString();
    input.contextJson = JSON.serialize(contextMap);
    AEIR_ErrorCaptureService.capture(input);
    throw ex;
}
```

## Adding a remediation action

1. Create `Remediation_Action_Setting__mdt` record.
2. Set `Action_Key__c`, `Object__c`, `Field__c`, `Requires_Confirmation__c`, and `Active__c`.
3. Call `AEIR_RemediationOrchestrator.execute` or expose the invocable action to Agentforce.

## Adding a retry handler

```apex
public with sharing class MyRetryHandler implements AEIR_RetryHandler {
    public AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request) {
        AEIR_RetryOrchestrationService.RetryResult result = new AEIR_RetryOrchestrationService.RetryResult();
        // idempotent retry logic
        result.success = true;
        result.message = 'Retried safely.';
        return result;
    }
}
```

Then create `Retry_Handler__mdt` with `Apex_Class__c = MyRetryHandler`.
