# Aegis Flow Implementation Coverage Report

This file maps the technical solution blueprint scenarios to the deployable Salesforce DX package contents.

## Package Status

| Area | Status | Package assets |
|---|---|---|
| Core data model | Implemented | `Error_Log__c`, `Error_Context__c`, `AI_Diagnosis__c`, `Diagnostic_Session__c`, `Remediation_Action__c`, `Developer_Escalation__c`, `Error_Attachment__c`, `Error_Feedback__c`, `Retry_Attempt__c`, `Delivery_Audit__c` |
| Platform events | Implemented | `Error_Captured__e`, `Diagnostic_Session_Requested__e`, `Agent_Diagnosis_Requested__e`, `Aegis_User_Alert__e`, `Escalation_Requested__e` |
| Rule/config layer | Implemented | `Error_Rule__mdt`, `Escalation_Route__mdt`, `Remediation_Action_Setting__mdt`, `Retry_Handler__mdt`, `Sensitive_Field__mdt`, `Context_Field_Setting__mdt`, `Surface_Config__mdt`, `Retention_Policy__mdt` |
| Automatic error capture | Implemented scaffold | `AEIR_ErrorCaptureService`, `AEIR_CaptureFlowFaultAction`, `AEIR_ClientErrorController`, event triggers |
| Flow fault handling | Implemented extension point | Invocable action `AEIR Capture Flow Fault`; customer Flow fault paths must call it |
| Apex exception handling | Implemented utility | `AEIR_ErrorCaptureService.capture()` and `captureFromJson()` |
| Batch Apex failures | Implemented | `AEIR_BatchApexErrorEventTrigger`, `AEIR_BatchApexErrorEventHandler` |
| Queueable failures | Implemented pattern | `AEIR_QueueableFinalizer` provides reusable finalizer capture; `AEIR_QueueableFinalizerExample` demonstrates `System.attachFinalizer()` |
| LWC client errors | Implemented | `errorBoundaryWrapper` plus `AEIR_ClientErrorController` |
| Inbound/API diagnostic capture | Implemented | Authenticated REST endpoint `AEIR_InboundDiagnosticRestService` at `/services/apexrest/aegis-flow/v1/diagnostics/*` |
| Failed async-job monitoring | Implemented | `AEIR_AsyncJobMonitorScheduler` plus `Error_Log__c.Async_Job_Id__c` duplicate suppression |
| Manual Help Me | Implemented | `helpMeAgentUtility`, `AEIR_HelpMeController`, `AEIR_DiagnosticSessionService` |
| Agentforce integration | Implemented as action contract | Approved invocable Apex actions for context retrieval, recent-error search, record snapshots, diagnosis, governed remediation, retry, and escalation. Actual agent/topics are org-specific. |
| Deterministic diagnosis | Implemented | `AEIR_ErrorNormalizationService`, default `Error_Rule__mdt` records |
| Agent diagnosis storage | Implemented | `AEIR_AgentforceGatewayService`, `AI_Diagnosis__c` |
| Safe remediation | Implemented | `AEIR_RemediationOrchestrator`, metadata whitelist, CRUD/FLS checks, audit object |
| Sample tax-code remediation | Implemented | `Account.Tax_Code__c`, `Remediation_Action_Setting.UPDATE_ACCOUNT_TAX_CODE` |
| Retry orchestration | Implemented pattern | `AEIR_RetryOrchestrationService`, `AEIR_RetryHandler`, `AEIR_SampleTaxRetryHandler`, `Retry_Attempt__c`, `Retry_Handler.ORDER_TAX_RECALCULATION` |
| Developer escalation | Implemented | `AEIR_EscalationService`, `Developer_Escalation__c`, `Delivery_Audit__c`, `Escalation_Requested__e`, default email route |
| Admin console | Implemented | `adminErrorConsole`, `AEIR_AdminConsoleController`, custom tabs/app |
| Developer escalation viewer | Implemented | `developerEscalationViewer` |
| Sensitive data masking | Implemented | `AEIR_SecuritySanitizerService`, `Sensitive_Field__mdt` |
| Retention | Implemented | `AEIR_RetentionScheduler`, `Retention_Policy__mdt` |
| Permissions | Implemented | End-user, support, developer viewer, product admin, integration-user permission sets |

## Scenario Coverage

| Scenario | Coverage in package | Notes |
|---|---|---|
| Required Account tax field causes Order tax process failure | Covered | Default tax code field/remediation action included. Replace handler with org-specific tax retry logic. |
| Validation rule blocks user save | Covered | Error rule classifies `FIELD_CUSTOM_VALIDATION_EXCEPTION`; user/admin guidance generated. |
| Flow Update Records element fails | Covered | Flow fault path calls `AEIR Capture Flow Fault`. |
| Apex DML exception | Covered | Apex callers use `AEIR_ErrorCaptureService.capture()`. |
| Apex NullPointerException | Covered | Rule classifies null pointer as developer-only and escalates. |
| Batch Apex unhandled exception | Covered | `BatchApexErrorEvent` trigger creates AEIR error logs. Batch classes must implement `Database.RaisesPlatformEvents`. |
| Queueable unhandled exception | Covered | Finalizer pattern logs failure context. Production queueables should attach the finalizer. |
| LWC component error | Covered | Wrap custom components in `errorBoundaryWrapper`. |
| Standard Lightning page user confusion | Covered | Help Me Utility captures page context and creates diagnostic session. |
| Agentforce auto-trigger failure | Covered | Manual Help Me path can start diagnostic/escalation manually. |
| Generic error where logs are unavailable | Covered | Diagnostic session + user description + context snapshot + escalation package. |
| Sensitive values in payload | Covered | Regex masking and custom metadata-driven sensitive field masking. |
| Safe fix cannot be executed | Covered | Remediation audit row records failure and recommends escalation. |
| Retry required | Covered | Retry handler interface and sample handler. Only idempotent customer-specific retry logic should be enabled. |
| Development team notification | Covered | Developer escalation package object and optional email sending. |

## Deployment Validation Performed in This Build

- SFDX project generated with source-format metadata.
- Metadata XML well-formedness checked locally.
- File inventory checked.
- README, configuration guide, extension guide, Agentforce prompt/action contract, scenario coverage, and smoke Apex script included.

## Validation Not Performed Here

A live Salesforce deployment and Apex test execution were not run in this environment because no authenticated Salesforce org and no Salesforce CLI runtime are available in the execution container. After unzipping, validate in your org with:

```bash
sf org login web --set-default --alias aeir-target
sf project deploy validate --source-dir force-app --target-org aeir-target --test-level RunLocalTests --wait 30
sf project deploy start --source-dir force-app --target-org aeir-target --test-level RunLocalTests --wait 30
```

## Org-Specific Setup Required After Deployment

1. Replace `devteam@example.com` in `Escalation_Route.DEFAULT_DEV_EMAIL`.
2. Add `helpMeAgentUtility` to selected Lightning App Utility Bars.
3. Connect important Flow fault paths to `AEIR Capture Flow Fault`.
4. Register the package's invocable Apex actions as Agentforce custom actions.
5. Replace sample retry/remediation mappings with customer-specific idempotent logic where needed.
6. Configure debug-log collection through a Named Credential if the org wants Tooling API log-body retrieval.
