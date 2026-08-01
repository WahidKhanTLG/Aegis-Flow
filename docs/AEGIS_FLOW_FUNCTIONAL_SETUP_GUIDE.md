# Aegis Flow Functional Setup Guide

**Audience:** Salesforce admins, implementation leads, support managers, and customer success teams
**Last updated:** 2026-08-01

## 1. What Aegis Flow Does

Aegis Flow helps Salesforce users and admins understand why an automation or custom process failed. When a supported failure happens, Aegis records the issue, groups it with similar issues, creates a user-safe explanation, and can notify the affected user through the Lightning utility bar.

The product is designed for:

- Users who need a clear next step instead of a confusing platform error.
- Admins who need to know which automation failed.
- Developers who need sanitized technical evidence.
- Support teams who need escalation packages without manually gathering logs.

## 2. What Users See

When Aegis has active alerts, the utility item is highlighted in the Lightning footer:

![Aegis Flow highlighted utility alerts](images/aegis-utility-highlighted-alerts.png)

When auto-open is enabled and the alert meets the policy threshold, the utility can open automatically:

![Aegis Flow auto-open alert panel](images/aegis-utility-auto-open-alert.png)

Users and admins can open the details panel to see the diagnosis and escalation options:

![Aegis Flow diagnostic details](images/aegis-utility-alert-details.png)

## 3. Setup Checklist

Before testing with business users:

- Deploy the Aegis Flow metadata to the target Salesforce org.
- Assign the correct permission sets.
- Open the `Aegis Flow Setup` tab and save routing details.
- Add `Aegis Flow Alerts` to every Lightning app utility bar where users work.
- Add `Get Help` to the same utility bars when users should be able to start a manual diagnostic session.
- Run the Aegis setup health check.
- Test one automation failure scenario before pilot rollout.

## 4. Permission Sets

| Permission set | Assign to | Purpose |
| --- | --- | --- |
| `AEIR_Product_Admin` | Implementation owner or Salesforce admin | Configure Aegis Flow and review all diagnostic records. |
| `AEIR_End_User` | Pilot and production users | Use the utility bar alerts and manual Get Help flow. |
| `AEIR_Support_Analyst` | Support/admin triage team | Review logs, sessions, incidents, and escalations. |
| `AEIR_Developer_Viewer` | Developers or technical support | Read sanitized diagnostic packages. |
| `AEIR_Integration_User` | Integration user only | Publish or create diagnostics through the API/integration path. |
| `AEIR_Sample_Account_Remediation` | Test users only | Enables the sample remediation scenario. Do not assign broadly. |

## 5. Configure Aegis Flow Setup

Open the `Aegis Flow Setup` tab in Salesforce.

Use this page to:

- Save the company or org-level routing details.
- Enter the admin/support team email address.
- Enter the developer escalation email address.
- Decide whether sanitized summaries can be shared with the Aegis Flow support address.
- Run the health check.
- Scan Flows for missing failure coverage.

The setup tab is backed by the `Aegis_Flow_Setup` custom tab and the `aegisSetupWizard` component.

## 6. Add Aegis Flow To A Lightning Utility Bar

Repeat these steps for every Lightning app where users should see proactive Aegis alerts.

1. Go to Salesforce Setup.
2. Open `App Manager`.
3. Find the target Lightning app, such as Sales, Service, Sales Console, or a customer app.
4. Click `Edit`.
5. Open `Utility Items`.
6. Click `Add Utility Item`.
7. Choose the custom Lightning component `Aegis Flow Headless Monitor`.
8. Configure it with these values:

| Property | Recommended value |
| --- | --- |
| Label | `Aegis Flow Alerts` |
| Icon | `screen` |
| Width | `340` |
| Height | `480` |
| Start automatically | Enabled |
| Scrollable | Enabled |

Then add the manual help utility:

1. Click `Add Utility Item`.
2. Choose `helpMeAgentUtility`.
3. Configure it with these values:

| Property | Recommended value |
| --- | --- |
| Label | `Get Help` |
| Icon | `question` |
| Width | `380` |
| Height | `520` |
| Start automatically | Disabled |
| Scrollable | Enabled |

Save and activate the app. Users may need to refresh the browser before the new utility items appear.

## 7. Notification Policy Defaults

The current default policy is `Notification_Policy.DEFAULT`.

| Setting | Current value | What it means |
| --- | --- | --- |
| Active | `true` | The policy is enabled. |
| Notify affected user | `true` | The user involved in the failure can receive the alert. |
| Notify admin | `true` | Admin/support recipients can also be notified. |
| Auto open utility | `true` | The utility may open automatically when an eligible alert is created. |
| Minimum severity | `Medium` | Low-severity items are not auto-opened by the default policy. |
| Critical mode | `Notify Both` | Critical issues can notify both user and admin paths. |
| Cooldown | `15 minutes` | Reduces repeated alerts for the same user/incident. |
| Max alerts per hour | `3` | Prevents alert spam. |
| Minimum confidence | `60` | Filters out low-confidence diagnosis results. |

## 8. Scenarios Covered

### Flow Fails Because A Validation Rule Blocks The Transaction

This is the key scenario tested in the utility bar. Example: a Flow runs on an Order, Opportunity, Lead, or Contact path and tries to save data, but a validation rule blocks the save. Aegis can capture this when the failure happens through supported automation paths.

Expected user experience:

- The utility bar highlights as `Aegis Flow Alerts`.
- If policy allows, it opens automatically.
- The user sees a clear message such as: "A validation rule blocked the action. Review the rule message and update the record accordingly."
- The details panel shows severity, source type, diagnosis, and escalation controls.

### Flow With A Fault Path

Best practice for important customer Flows is to connect the Flow fault path to the Aegis capture action.

Expected result:

- Aegis logs the error in seconds.
- Record context is preserved.
- The transaction can still roll back safely because the capture path uses a platform event.

### Flow Without A Fault Path

Aegis also has a monitor for failed Flow interviews.

Expected result:

- Aegis can detect the failed Flow after the scheduled monitor runs.
- This is useful for background coverage.
- Record context may be missing because Salesforce does not expose it in the same way as an explicit fault path.

### Browser-Based Real-Time Flow Alert

When a Lightning app has the Aegis utility bar open or loaded, Aegis can listen for Salesforce Flow failure events in the browser.

Expected result:

- The user sees the alert quickly.
- This is browser-dependent. If no user has the Aegis utility loaded, the scheduled/publish-based paths are still needed for durable monitoring.

### Apex Exception

Developers can wrap important Apex operations with the Aegis guard/capture pattern.

Expected result:

- Aegis records the failure.
- The error can be grouped into an incident.
- The user/admin notification policy can route alerts.

### Batch Apex Failure

Batch classes that opt in to Salesforce batch error events can be captured.

Expected result:

- Aegis records failed batch chunks.
- Support and developer teams can review the technical failure.

### Failed Async Job

Aegis includes a scheduled monitor for failed async jobs.

Expected result:

- Failed jobs are found by the monitor.
- A diagnostic record is created.
- Record context may not be available.

### Custom LWC Error

Custom LWCs can use the Aegis error boundary wrapper.

Expected result:

- Client-side errors are captured.
- Page and component context can be included.
- This is the best option for custom user-facing forms.

### Integration Or API Failure

An authenticated integration can submit diagnostic information to Aegis.

Expected result:

- Aegis creates a diagnostic record from the integration payload.
- The caller should use a scoped integration user, not a broad admin account.

### User Needs Help But There Is No Error

Users can open the `Get Help` utility.

Expected result:

- A diagnostic session is created.
- The user can describe what they were trying to do.
- Support receives structured context instead of a vague help request.

## 9. Scenarios Not Captured Automatically

Some Salesforce errors happen before Aegis can receive a platform automation failure.

| Scenario | Expected behavior |
| --- | --- |
| User directly edits a record and a validation rule blocks Save | Not automatically captured. This is a standard platform save failure. |
| User directly hits a duplicate rule | Not automatically captured unless handled by a custom form or automation wrapper. |
| Lead Convert fails because of a validation rule | Not automatically captured by the current package. |
| Page layout or field-level security prevents an edit | Not automatically captured as an Aegis automation failure. |

For these scenarios, use the `Get Help` utility, a custom LWC form with the Aegis wrapper, or an automation/Apex path that explicitly calls Aegis.

## 10. Where To Verify Results

After running a test, check these areas:

- The Lightning utility bar label and alert panel.
- `Error Logs`.
- `User Notifications`.
- `Incidents`.
- `AI Diagnoses`.
- `Diagnostic Sessions`.
- `Developer Escalations`.
- `Delivery Audits`.
- `Aegis Flow Setup` health check.

## 11. Troubleshooting

| Issue | What to check |
| --- | --- |
| Utility does not appear | Confirm the component was added to the correct Lightning app utility bar and the user refreshed the app. |
| Utility appears but does not auto-open | Confirm `Auto_Open_Utility__c` is enabled, the alert severity meets the policy threshold, and the alert is not inside the cooldown window. |
| No alert appears for a Flow failure | Confirm the Flow has a fault path to Aegis, or keep the Aegis utility loaded for browser-based Flow event capture, or wait for the scheduled monitor. |
| Direct validation rule error is not captured | This is expected for direct record saves. Use manual Get Help or a custom instrumented form if capture is required. |
| Details are missing record id | This can happen for scheduled/polling paths where Salesforce does not expose the record id. Use a Flow fault path for reliable record context. |
| Too many alerts | Adjust cooldown, max alerts per hour, severity threshold, or grouping policy. |
| Users cannot see records | Review the assigned Aegis permission set and standard Salesforce object permissions. |

## 12. Current Versus Future

Current release focus:

- Salesforce-native error logging.
- Flow, Apex, batch, async, LWC, REST, and manual help capture paths.
- Utility bar notifications and auto-open behavior.
- Incident grouping.
- Deterministic diagnosis.
- Sanitized developer escalation.
- Retention and security controls.

Future headless focus:

- A formal headless diagnostic API.
- MCP tools for support and developer copilots.
- Real Agentforce action execution.
- Optional external operations channels.
- Managed package namespace readiness.

## 13. Customer Acceptance Checklist

Use this before pilot sign-off:

- `Aegis Flow Alerts` appears in the target Lightning app utility bar.
- `Get Help` appears where manual diagnostics are required.
- A test Flow failure creates an Aegis error log.
- A Flow fault path test preserves record context.
- The utility highlights or opens for an eligible alert.
- Details show a clear user-safe diagnosis.
- Escalation creates a sanitized package.
- Admin/support users can find the record in Aegis list views.
- Direct validation-rule saves are understood as out of automatic capture scope.
- The customer knows how to route future high-value Flows through the Aegis capture action.
