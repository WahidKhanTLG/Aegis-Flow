# Aegis Flow Deployment and Testing Guide

This guide describes the exact steps to deploy and test the Agentic Error Intelligence and Recovery package in a Salesforce sandbox or production org.

## 1. Prerequisites

- Salesforce org with Lightning Experience enabled.
- System Administrator or deployment user with Metadata API deployment permissions.
- Salesforce CLI installed locally.
- A sandbox is strongly recommended for first deployment.
- Agentforce is required only for the final conversational agent layer. The core product works without Agentforce by using deterministic diagnosis and escalation logic.
- Email deliverability must be enabled if you want escalation emails to send during tests.

## 2. Unzip and inspect

```bash
unzip Agentic_Error_Intelligence_Recovery_Product_REVIEWED.zip
cd aeir_product
python3 scripts/local_audit.py
```

Expected result:

```text
Result: PASS
```

## 3. Update required configuration before deployment

Open this file before deploying:

```text
force-app/main/default/customMetadata/Escalation_Route.DEFAULT_DEV_EMAIL.md-meta.xml
```

Replace:

```text
devteam@example.com
```

with your real development team email address.

Optionally update:

```text
force-app/main/default/customMetadata/Escalation_Route.DEFAULT_ADMIN_EMAIL.md-meta.xml
```

Replace:

```text
admin@example.com
```

with the Salesforce admin/support team email address.

## 4. Authenticate target org

```bash
sf org login web --alias aeir-target --set-default
```

For a sandbox:

```bash
sf org login web --instance-url https://test.salesforce.com --alias aeir-target --set-default
```

## 5. Validate in a sandbox

Use dry-run deployment first:

```bash
sf project deploy start --source-dir force-app --target-org aeir-target --dry-run --test-level RunLocalTests --wait 60
```

Or use the included helper script:

```bash
./scripts/validate_sandbox.sh aeir-target
```

## 6. Deploy

```bash
sf project deploy start --source-dir force-app --target-org aeir-target --test-level RunLocalTests --wait 60
```

Or:

```bash
./scripts/deploy.sh aeir-target
```

## 7. Run Apex tests after deployment

```bash
sf apex run test --class-names AEIR_CoreTest --target-org aeir-target --code-coverage --result-format human --wait 60
```

## 8. Run smoke test

```bash
sf apex run --file scripts/smoke_test.apex --target-org aeir-target
```

Expected debug output includes:

```text
AEIR SMOKE TEST PASS
```

The smoke test creates:

- one Account
- one Error Log
- one AI Diagnosis
- one Diagnostic Session
- one Remediation Action
- one Developer Escalation

## 9. Assign permission sets

Assign these permission sets based on role:

| Permission Set | Assign To | Purpose |
|---|---|---|
| AEIR_Product_Admin | Implementation owner, admin | Full AEIR setup/admin access |
| AEIR_End_User | Pilot users | Help Me utility, diagnostic session creation, client error reporting |
| AEIR_Support_Analyst | Support/admin triage team | Triage logs, sessions, and escalations |
| AEIR_Developer_Viewer | Developers | Read-only access to diagnostic packages |
| AEIR_Integration_User | Integration/automation user | Platform event publishing and service invocation |
| AEIR_Sample_Account_Remediation | Test/pilot users only | Allows sample Account Description and Tax Code remediation |

CLI assignment example:

```bash
sf org assign permset --name AEIR_Product_Admin --target-org aeir-target
sf org assign permset --name AEIR_End_User --target-org aeir-target
sf org assign permset --name AEIR_Sample_Account_Remediation --target-org aeir-target
```

## 10. Add the Help Me utility to Lightning apps

1. Go to Setup.
2. Open App Manager.
3. Find the target Lightning app, such as Sales or Service Console.
4. Click Edit.
5. Open Utility Items.
6. Click Add Utility Item.
7. Select `AEIR Help Me Agent Utility`.
8. Set label to `Help Me` or `AI Help`.
9. Save and assign the app to pilot users.

Test by opening an Account record and clicking the Help Me utility in the footer.

## 11. Configure Agentforce actions

The package exposes these invocable Apex actions for Agentforce Builder:

| Agentforce Action | Apex Class / Method | Purpose |
|---|---|---|
| AEIR Invoke Diagnosis | `AEIR_InvokeDiagnosisAction.invokeDiagnosis` | Diagnose error log or diagnostic session |
| AEIR Execute Remediation | `AEIR_ExecuteRemediationAction.executeRemediation` | Execute approved whitelisted remediation |
| AEIR Create Developer Escalation | `AEIR_CreateEscalationAction.createEscalation` | Create/send escalation package |
| AEIR Capture Flow Fault | `AEIR_CaptureFlowFaultAction.captureFlowFault` | Capture Flow fault context |

Recommended Agentforce topics:

- Diagnose Salesforce Error
- Help User on Current Screen
- Request Missing Data
- Execute Safe Remediation
- Escalate to Development Team
- Explain Validation or Permission Issue

Important: The actual Agentforce agent, topics, instructions, and action assignment are org-specific and must be created in the target org after deployment.

## 12. Wire Flow fault paths

For each important Flow:

1. Add a fault connector from the risky element.
2. Populate variables for error message, record id, object API name, user action, and page URL when available.
3. Add Apex Action: `AEIR Capture Flow Fault`.
4. Pass the Flow API name, failed element, object name, record id, and error message.
5. Optionally add Apex Action: `AEIR Invoke Diagnosis`.
6. Show the user a friendly screen with the correlation id.

## 13. Test core scenarios

### Scenario A: Manual Help Me fallback

1. Open an Account record.
2. Click Help Me in the utility bar.
3. Select Report Issue.
4. Enter: `I received an error while trying to save this account.`
5. Click Start Diagnosis.
6. Click Ask Agent.
7. Click Send Report.
8. Verify records were created in Diagnostic Sessions and Developer Escalations.

### Scenario B: Flow fault capture

Create a test Flow that intentionally faults, wire the fault path to `AEIR Capture Flow Fault`, then run it. Verify an Error Log is created with Source Type = Flow.

### Scenario C: Apex capture

Run anonymous Apex:

```apex
AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
input.sourceType = 'Apex Class';
input.sourceName = 'Manual Apex Test';
input.originalMessage = 'System.NullPointerException: Attempt to de-reference a null object';
AEIR_ErrorCaptureService.CaptureResult result = AEIR_ErrorCaptureService.capture(input);
System.debug(result.errorLogId);
```

Verify the Error Log is categorized as Null Pointer and can be escalated.

### Scenario D: Safe remediation

1. Assign `AEIR_Sample_Account_Remediation` to the testing user.
2. Create an Account.
3. Run `scripts/smoke_test.apex`.
4. Verify the Account Description was updated and a Remediation Action record was created.

### Scenario E: Developer escalation email

1. Confirm `Escalation_Route.DEFAULT_DEV_EMAIL` points to a real mailbox.
2. Run Help Me and click Send Report, or run the smoke test with email disabled and then manually invoke escalation with email enabled.
3. Verify a Developer Escalation record was created and email status is Sent.

### Scenario F: Retry handler

Run anonymous Apex:

```apex
AEIR_RetryOrchestrationService.RetryRequest req = new AEIR_RetryOrchestrationService.RetryRequest();
req.handlerKey = 'ORDER_TAX_RECALCULATION';
req.attemptNumber = 1;
AEIR_RetryOrchestrationService.RetryResult res = AEIR_RetryOrchestrationService.requestRetry(req);
System.debug(res.message);
```

The included handler is a sample; replace it with customer-specific idempotent retry logic.

## 14. Schedule retention

```bash
sf apex run --file scripts/schedule_retention.apex --target-org aeir-target
```

This schedules `AEIR_RetentionScheduler` at 2:00 AM org time.

## 15. Production deployment sequence

1. Deploy and test in sandbox.
2. Update escalation recipients.
3. Validate production deployment:

```bash
sf project deploy validate --source-dir force-app --target-org prod --test-level RunLocalTests --wait 60
```

4. If validation succeeds, quick deploy the returned job id:

```bash
sf project deploy quick --job-id <VALIDATED_JOB_ID> --target-org prod --wait 60
```

5. Assign permission sets.
6. Add Help Me to target Lightning apps.
7. Configure Agentforce actions.
8. Wire Flow fault paths.
9. Run smoke test in production only if approved, because it creates test data.

## 16. Known implementation boundaries

- The package does not deploy a fully configured Agentforce agent because agent topics, trusted actions, channels, and licensing are org-specific.
- Debug log body retrieval is represented by `AEIR_LogCollectorService`, but full Tooling API log retrieval must be configured with a Named Credential in the customer org.
- Standard Lightning pages do not expose every unsaved field change to a managed LWC. The Help Me utility captures page context and user-provided details; exact changed values are reliable only in custom LWCs/forms or server-side automation contexts.
- Browser button-click automation is intentionally not included. The package uses Apex/Flow remediation actions instead.
- External channels such as Jira, Slack, Teams, GitHub, and Webhook are represented in the routing model; production connectors should be added with Named Credentials and customer-specific security approval.
