# Scenario Coverage Matrix

| Scenario | Package Support | Key Components |
|---|---|---|
| Flow failed during data update | Supported through invocable action | `AEIR_CaptureFlowFaultAction`, `Error_Log__c` |
| Apex DML exception | Supported through service wrapper | `AEIR_ErrorCaptureService`, `AEIR_ErrorNormalizationService` |
| Batch Apex failure | Supported when batch implements `Database.RaisesPlatformEvents` | `AEIR_BatchApexErrorEventTrigger` |
| Queueable failure | Supported through included finalizer example | `AEIR_QueueableFinalizerExample` |
| LWC component error | Supported | `errorBoundaryWrapper`, `AEIR_ClientErrorController` |
| Standard page save issue | Manual context capture supported; unsaved deltas are limited | `helpMeAgentUtility`, `Diagnostic_Session__c` |
| Custom LWC form save error | Supported when the custom form passes changed fields JSON | `AEIR_ErrorCaptureService` |
| Integration/API failure | Supported through Apex logging contract | `AEIR_ErrorCaptureService`, platform events |
| User confused/no error | Supported | `helpMeAgentUtility`, `AEIR_AgentforceGatewayService` |
| Agentforce did not trigger | Supported fallback | `Diagnostic_Session__c`, `AEIR_EscalationService` |
| Missing field safe update | Supported if whitelisted | `AEIR_RemediationOrchestrator`, `Remediation_Action_Setting__mdt` |
| Retryable process | Supported through interface pattern | `AEIR_RetryOrchestrationService`, `Retry_Handler__mdt` |
| Sensitive payload | Supported | `AEIR_SecuritySanitizerService`, `Sensitive_Field__mdt` |
