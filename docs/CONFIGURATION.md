# Aegis Flow Configuration Guide

## Escalation routing

Update `Escalation_Route__mdt` records:

- `DEFAULT_DEV_EMAIL`: recipient for developer-only errors.
- `DEFAULT_ADMIN_EMAIL`: recipient for permission, FLS, and configuration issues.

For MVP, email is enabled in Apex. Case, Jira, Slack, Teams, GitHub Issue, and Webhook routes are represented in the data model and routing metadata. Implement external channel clients with Named Credentials before enabling those channels.

## Agentforce connection

Create an Agentforce agent with these topics:

1. Diagnose Error
2. Assist User on Current Screen
3. Request Missing Data
4. Prepare Developer Escalation
5. Explain Business Rule
6. Retry Eligible Process

Expose these Apex invocable actions to the agent:

- `AEIR Invoke Diagnosis`
- `AEIR Execute Remediation`
- `AEIR Create Developer Escalation`
- `AEIR Capture Flow Fault` where Flow-based invocation is preferred

Use the prompt contract in `docs/AGENTFORCE_PROMPT_CONTRACT.md`.

## Flow fault integration

For each production Flow:

1. Connect fault paths to an Assignment element that populates error variables.
2. Call Apex Action `AEIR Capture Flow Fault`.
3. Optionally call `AEIR Invoke Diagnosis`.
4. Show a friendly error screen containing the correlation id, not the raw stack trace.

## Help Me utility

Add `Aegis Flow Diagnostic Assistant` and `Aegis Flow Headless Monitor` as Utility Bar items in target Lightning apps.

The **Aegis Flow Admin** app ships a utility bar (`Aegis_Flow_Admin_UtilityBar`) with the headless monitor already on it.

Utility items are **per application**, so every other app your pilot users work in — Sales, Service, or custom — needs its own utility bar or those users receive no proactive alerts. Add via Setup > App Manager > edit the app > Utility Items, then retrieve the generated FlexiPage into source so it is reproducible (tracked as AF-26).

## Safe remediation

Add `Remediation_Action_Setting__mdt` records for every object/field/action that the agent may update. Do not allow generic object/field updates. The orchestrator blocks actions unless the object and field match the metadata whitelist and the user confirms.
