# Approved synchronous Flow recovery

`AEIR_ApprovedFlowRetryHandler` is a reusable extension for an administrator-reviewed,
idempotent recovery process. It ships with **no enabled business Flow registration**.
The org inventory contains no approved customer recovery Flow; Salesforce-provided
managed Flows and the existing QA order-failure Flows are not automatically registered.
No tax calculation, order rule or customer process is inferred.

Configure one unique active `Retry_Handler__mdt` record with the normal handler key,
attempt limit/backoff/idempotency policy and these exact values:

| Field | Required value |
| --- | --- |
| `Apex_Class__c` | `AEIR_ApprovedFlowRetryHandler` |
| `Flow_API_Name__c` | Exact API name of the reviewed synchronous autolaunched Flow |
| `Target_Object__c` | Exact standard/custom object API name |
| `Required_Permission__c` | Exact custom permission for that recovery process |

The caller needs both `AEIR_Execute_Retry` and the registered custom permission, native
retry-state/audit CRUD/FLS, readable/editable target-object access, a user-mode-visible
target and record-level edit access. The extension does not confer those permissions.
Call `AEIR_RetryOrchestrationService`; its existing savepoints, unique audits, attempt
limits and backoff protect the business changes and failed outcomes. Calling the handler
directly does not supply the orchestrator's audit/rollback contract.

The caller cannot select a Flow or add variables through `payloadJson`; any nonblank
payload is rejected. Inputs are constructed by the server:

| Flow variable | Type | Meaning |
| --- | --- | --- |
| `varTargetRecordId` | Text, input | Authorized target record ID |
| `varCorrelationId` | Text, input | Validated diagnostic correlation |
| `varAttemptNumber` | Number, input | Positive configured retry attempt |
| `varRecoveryKey` | Text, input | SHA-256 of normalized handler, canonical target ID and correlation; stable across attempts |
| `varRecoverySucceeded` | Boolean, output | Must be the Boolean `true` after verification |
| `varRecoveredRecordId` | Text, output | Must identify exactly the authorized target |
| `varResultMessage` | Text, optional output | Sanitized, bounded result summary |

Missing/false/malformed success or a different target fails the attempt. The orchestrator
rolls back writes made by the Flow and keeps a failed audit. The Flow itself must verify
its business postcondition and use `varRecoveryKey` or an equivalent durable business
key to avoid repeated effects across explicit attempts. A service duplicate audit alone
does not establish business idempotency across different attempts.

Flows invoked from Apex can inherit privileged execution context. Approving the Flow is
therefore approval of its exact business writes, including field access and any related
records. Review every active-version change. Do not register screens, pauses/waits,
async paths, callouts, immediate platform events, emails or irreversible side effects.
External delivery belongs in the separate durable connector/outbox transaction.
See [Salesforce Flow security guidance](https://developer.salesforce.com/docs/platform/secure-coding/guide/secure-coding-considerations-flow-design.html)
and the [Flow interview API reference](https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/salesforce_apex_reference_guide.pdf).

The legacy orchestration limit remains 20 requests per transaction. The extension adds
two ordinary access queries per executed target; custom-metadata configuration reads
are not ordinary SOQL-query consumption. The reviewed Flow's queries/DML, other customer
automation and existing transaction usage must fit the remaining governor budget.
Chunk earlier for expensive recovery processes.

Required business inputs before enabling a registration are the process owner, exact
Flow/active version, target object, approved writes and related records, recovery custom
permission, durable idempotency/postcondition, expected volume and denied/failure cases.
No business registration can be enabled responsibly without those decisions.

The separate [QA fixture](../qa/approved-flow-retry/README.md) demonstrates a real owned,
marker-constrained synthetic write. `scripts/acceptance/cross_business_rollback.apex`
stages synchronous diagnostic acceptance for Sales, Service, custom objects and integration
evidence with rollback cleanup. Root coordinates execution; source creation and mocked
unit tests do not establish live Flow or external-service acceptance.
