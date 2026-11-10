# Aegis Flow product plan and execution tracker

Updated November 10, 2026. Product `1.2.0-reconciled`, Metadata API 67.0.
This portable team tracker keeps implemented features, current release work, optional
integrations, commercial work and future ideas separate. Dated evidence references (E01–E44)
refer to retained private engineering records; the current public verification summary is
[source publication review](SOURCE_PUBLICATION_REVIEW.md).

| Inventory | Current state |
| --- | --- |
| Current product features | 55 implemented entries across ten areas |
| Release tasks | 25 total; nine Done, nine Prepared, six Pending, one Awaiting billing resolution (16 open) |
| Local packaging-development tasks | All seven complete; actual namespace/build/install work remains |
| Optional integrations | Seven awaiting approved setup and live acceptance |
| Commercial work | COM-01 prepared for team environment binding; six other decision-dependent items |
| Future ideas | 20 Proposed; excluded from the current release commitment |
| Latest Apex proof | PUB-APEX-01 passed 311/311 tests; original shared-org ACC-07-01 remains Failed |
| Live connector proof | Four read operations pass; writes disabled; no ordinary-user/browser acceptance inferred |
| Git publication | [PR #2](https://github.com/WahidKhanTLG/Aegis-Flow/pull/2) merged at `0089f56e21d4efa25048ea9a7411d148b2e13eb5`; post-merge full Node 24 checks and live read-only MCP checks pass |
| Development org | Unchanged by publication: 38 scoped file differences and the new test class/metadata absent; deployment remains separate |

Implemented means code exists, Prepared means available local work is complete while actual
environment acceptance is open, and Done means the task's recorded scope has passed. Do not
combine these different inventories into one completion percentage. No new customer business
operation, provider delivery, package creation or commercial clearance is implied.

## Current implemented features


All 55 entries below have **Implemented** status. Evidence references identify the owning contracts and development results. A feature can be implemented while its live customer setup or final release acceptance remains pending.

### 4.1 Error capture — 9 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| CAP-01 | Direct Apex capture and rollback-resilient publication through reusable services/guard | Instrument supported Apex paths; publication acceptance is not persistence confirmation | Source and dated development evidence |
| CAP-02 | Flow fault invocable and packaged fault subflow | Wire the customer's fault path; choose rollback-safe mode where required | Source and dated development evidence |
| CAP-03 | Custom record-save capture and LWC error boundary | Covers the instrumented/custom surface; does not wrap every native Salesforce form | Source and dated development evidence |
| CAP-04 | Batch failure adapter with separate failure-event identities | Batch opt-in and real multi-scope failure acceptance remain environment-specific | Source and dated development evidence |
| CAP-05 | Queueable finalizer capture pattern | Attach it to the relevant jobs; not automatic instrumentation of every Queueable | Source and dated development evidence |
| CAP-06 | Scheduled failed-async-job monitoring | Persistent bounded pages exist; verify a real backlog beyond 100 jobs | Source and dated development evidence |
| CAP-07 | Failed Flow interview monitoring | Persistent bounded pages exist; verify a real backlog beyond 200 interviews | Source and dated development evidence |
| CAP-08 | Authenticated inbound diagnostic REST capture | Caller must supply valid authorized context and integrate error reporting | Source and dated development evidence |
| CAP-09 | Correlations, normalized capture, replay deduplication, rejection telemetry, and final publish callback | Verify transient/restart/final-failure handling under controlled live load | Source and dated development evidence |

### 4.2 Evidence protection and retention — 7 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| EVD-01 | Error/context records and business-record snapshots | Customer field allowlists and actual record permissions determine available context | Source and dated development evidence |
| EVD-02 | Structured JSON/text masking of sensitive values | Maintain customer masking rules; verify storage and outbound boundaries with representative values | Source and dated development evidence |
| EVD-03 | Private diagnostic sharing and authorized record/context reads | Retest each customer role; elevated admin access is a separate authority | Source and dated development evidence |
| EVD-04 | Diagnostic attachment references and escalation evidence manifest | References existing Salesforce Files; file permission/retention acceptance is separate from uploading files | Source and dated development evidence |
| EVD-05 | Bounded payloads, valid JSON, Unicode-safe truncation, and explicit omitted context | Evidence limits intentionally prevent unlimited collection | Source and dated development evidence |
| EVD-06 | Protected diagnosis/resolution timestamps and lifecycle-derived durations | Unknown legacy timing remains unknown; no fabricated history/backfill | Source and dated development evidence |
| EVD-07 | Configurable retention and scheduled purge services | Confirm the customer's retention values, ownership, and cleanup behavior | Source and dated development evidence |

### 4.3 Diagnosis and guidance — 5 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| DIA-01 | Deterministic diagnosis with 24 shipped error-rule records | Rules cover known patterns; they do not guarantee the cause of every error | Source and dated development evidence |
| DIA-02 | Automatic diagnosis requests and persisted diagnosis results | Development automatic diagnosis was enabled; customer activation is explicit | Source and dated development evidence |
| DIA-03 | Metadata-driven classification, severity, and SLA policy foundations | Review tenant policy mappings before using them as operational commitments | Source and dated development evidence |
| DIA-04 | Fallback guidance and evidence-preserving handling of unknown/provider failures | Preserve uncertainty and escalate when an approved correction is unavailable | Source and dated development evidence |
| DIA-05 | Invocable context, snapshot, recent-error, diagnosis, escalation, and governed action contracts | Configure interactive write actions separately from a read-only enrichment agent | Source and dated development evidence |

### 4.4 User experience — 7 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| UX-01 | Utility-bar monitor with minimal live alert hints | Requires supported hosting and access; optional native Flow streaming was unavailable in earlier acceptance | Source and dated development evidence |
| UX-02 | Durable saved alerts, authorized resolution, reload/refresh, and persistent dismissal | Recheck the latest end-to-end journey across sessions and supported browsers | Source and dated development evidence |
| UX-03 | Diagnostic detail and guidance panels with loading/empty/error states | Latest rendered browser, accessibility, and mobile checks remain pending | Source and dated development evidence |
| UX-04 | Manual Help Me sessions without a technical exception | Description/context are validated; ordinary requests remain bound to the current user | Source and dated development evidence |
| UX-05 | Remediation confirmation UI | Visibility does not grant permission to execute an unregistered correction | Source and dated development evidence |
| UX-06 | Escalation confirmation and developer evidence viewer | Test the selected route, permissions, and actual delivery destination | Source and dated development evidence |
| UX-07 | Helpfulness/outcome/comments feedback linked to diagnostics | Feedback collection exists; automated learning from it is a proposed enhancement | Source and dated development evidence |

### 4.5 Governed remediation — 3 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| REM-01 | Exact registered object/field/action whitelist and strict value validation | Sample Account actions are not approved customer recovery rules | Source and dated development evidence |
| REM-02 | Feature/role permission, confirmation, CRUD/FLS, and record access gates | Validate the customer's actual role and action combination | Source and dated development evidence |
| REM-03 | Atomic target change and remediation audit, with rollback on audit failure | Acceptance must show both successful execution and refusal/rollback paths | Source and dated development evidence |

### 4.6 Retry and approved process recovery — 4 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| RTY-01 | Registered synchronous handlers and exact approved-Flow recovery contract | No enabled customer business retry is shipped; the sample tax handler fails closed | Source and dated development evidence |
| RTY-02 | Bounded batches, retry attempts, backoff, and permission-controlled audits | Synchronous retry accepts at most 20 inputs and requires operation-specific access | Source and dated development evidence |
| RTY-03 | Duplicate-attempt protection and idempotency obligations | Every business handler must also prove its own durable business idempotency | Source and dated development evidence |
| RTY-04 | Rollback when a synchronous handler fails after mutation | Irreversible external business effects require a separately designed async delivery flow | Source and dated development evidence |

### 4.7 Escalation and delivery — 5 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| ESC-01 | Sanitized diagnostic package and configurable support/developer routes | Confirm actual recipients and appropriate evidence access | Source and dated development evidence |
| ESC-02 | Email escalation channel | Latest hardening did not send email; accept delivery to an approved test destination | Source and dated development evidence |
| ESC-03 | Case escalation channel | Latest hardening verified an unsent draft; accept actual Case creation and required fields | Source and dated development evidence |
| ESC-04 | Delivery audits/outbox and explicit pending/failed/uncertain outcomes | Reconcile uncertain outcomes before any deliberate resend | Source and dated development evidence |
| ESC-05 | Durable source/route keys, locking, delivery claims, and replay protection | Cross-transaction replay passed; true concurrent contention still needs live acceptance | Source and dated development evidence |

### 4.8 Headless REST operations — 3 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| API-01 | Scoped capabilities, errors, incidents, context, and notification reads | Enforce bounded filters/cursors and actual diagnostic access | Source and dated development evidence |
| API-02 | Explicit help, dismiss, and escalate operations | Mutations retain canonical ownership and operation-specific authorization | Source and dated development evidence |
| API-03 | Separate headless permission, diagnostic roles, and controlled visible scope | Headless permission alone grants no diagnostic CRUD/FLS or sharing bypass | Source and dated development evidence |

### 4.9 MCP and product/process knowledge — 5 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| MCP-01 | Dependency-free local Node stdio server, protocol lifecycle, and resources | Register it in the chosen client; shared remote hosting is not implemented by this server | Source and dated development evidence |
| MCP-02 | Five Salesforce read tools plus two offline knowledge tools | Salesforce reads need an authorized identity; offline knowledge needs no provider key | Source and dated development evidence |
| MCP-03 | Three curated knowledge documents with claims, citations, and snapshot hashes | Knowledge is a reviewed local-source snapshot, not customer-org verification | Source and dated development evidence |
| MCP-04 | Explicit customer opt-in, bounded corpus, and filesystem/request isolation | Use separate configurations for customers; corpus selection is not tenant authentication | Source and dated development evidence |
| MCP-05 | Three optional writes with server opt-in and per-call confirmation | Disabled by default; registering knowledge does not authorize business recovery | Source and dated development evidence |

### 4.10 Administration, monitoring, and operations — 7 entries

| ID | Feature | Boundary / next acceptance | Evidence |
| --- | --- | --- | --- |
| OPS-01 | Incident grouping with complete long-key hashing | Validate representative grouping/time buckets; old keys are not silently migrated | Source and dated development evidence |
| OPS-02 | Command center and lifecycle-based aggregate metrics | Verify denominators, permissions, and known/unknown/reopened durations | Source and dated development evidence |
| OPS-03 | Flow coverage estimates matched to observed interview identities | This measures observed coverage, not guaranteed interception of all failures | Source and dated development evidence |
| OPS-04 | Setup/onboarding wizard and ten configuration health checks | Development passed 10/10; repeat against the intended tenant | Source and dated development evidence |
| OPS-05 | Seven permission sets, feature flags, and configuration metadata | Assign least-privilege roles and treat sample remediation permissions separately | Source and dated development evidence |
| OPS-06 | Five event subscribers with 200-event configuration and six recorded schedules | Runtime principal and capacity must be accepted for each tenant | Source and dated development evidence |
| OPS-07 | Aegis Operations workspace and Lightning app/utility placement | Existing Case Solutions remain preserved; current rendered placement needs final acceptance | Source and dated development evidence |

### November 7 hardening closure

These eight fixes strengthen the features above; they are not eight additional product features.

| ID | Finding addressed | Recorded result | Remaining acceptance |
| --- | --- | --- | --- |
| FIX-01 | Internal session-event access and forged user attribution | End User event access removed; publisher-bound requests and six real-role permission checks passed | Recheck actual pilot entitlements |
| FIX-02 | Lost/rejected asynchronous capture and misleading publish acknowledgement | Per-item failure telemetry, bounded retry, publication-result checks, and final-failure callback added | Live transient/final-failure/restart exercise |
| FIX-03 | Multiple failed Batch scopes collapsing into one error | Event-specific correlation and replay deduplication added/tested | Representative live Batch failures |
| FIX-04 | Monitor backlogs repeatedly stuck on the first page | Persistent keyset cursors and end-of-sweep handling added/tested | Real backlogs above both page sizes |
| FIX-05 | Duplicate escalation from replay | Unique request keys, source locks, and durable delivery claim; draft replay passed | True concurrent requests and real delivery |
| FIX-06 | Historical captures hiding new uncaptured Flow interviews | Exact observed-interview matching added/tested | Live coverage reconciliation |
| FIX-07 | Long grouping keys losing distinguishing fields | Complete inputs hashed; runtime object distinction passed | Representative customer grouping |
| FIX-08 | Duration reporting using modification time | Protected lifecycle timestamps and formulas; null/known/reopened cases passed | Final dashboard/rendered acceptance |

The current project dependency review is **Done (REL-21/E43)**. Both the root and isolated
lint dependency trees report zero findings at every severity. The earlier six moderate
minimatch and 12 low deepmerge-chain entries are resolved by the tested override, owned
source-backed deepmerge security replacement and maintained isolated lint runtime with
qualified Salesforce rule ports. Historical E20/E22 findings remain in their dated evidence;
they are not current open findings. The isolated CLI candidate separately reports zero
findings across 844 instances and is qualified only for its recorded restricted scope.
The global installation is unchanged and remains unqualified. These are separate graphs;
no upstream-support claim, advisory suppression or production risk exception is made.


## Release execution backlog


This backlog covers the existing product, not all optional or proposed features. Suggested owners identify the responsible role; no individual assignment or schedule has been confirmed.

### Workstream 1 — Plan, source review, and Git handoff

| ID | Task | Status | Completion condition / evidence | Owner / dependency |
| --- | --- | --- | --- | --- |
| REL-01 | Establish this master feature/release tracker | Done | Current, optional, commercial, and proposed scope separated; stable IDs, task counts, and evidence recorded | Engineering; this file |
| REL-02 | Freeze and verify the local planning baseline | Done | 106 deployment fingerprints match; source census, HEAD, and dirty-tree inventory captured in E06 | Engineering |
| REL-03 | Review the complete uncommitted diff and define the release file allowlist | Done | All 74 files reviewed/classified: 63 proposed Git inclusions, 11 local-only snapshots/QA exclusions. No new blocking regression identified; local manifest conversion includes ten new fields/trigger and excludes QA fixtures. HEAD/index/source hashes unchanged; E16/E17. Existing acceptance gates remain open. | Engineering; REL-02 |
| REL-04 | Commit the exact reviewed source | Done | 214 reviewed paths committed and pushed on release/aegis-flow-reviewed-2026-11-10; 12 local-only exclusions preserved. Main merged through REL-05; hosted acceptance remains blocked by billing. | Engineering |
| REL-05 | Publish the reviewed commit through the chosen Git review path | Done | PR #2 merged at 0089f56e21d4efa25048ea9a7411d148b2e13eb5; local main fast-forwarded, same 747 metadata/test files as successful check-only validation, post-merge full verify and live MCP reads pass. Hosted CI remains blocked before execution by owner billing; no hosted pass claimed. | Engineering |

### Workstream 2 — Final regression and user acceptance

| ID | Task | Status | Completion condition / evidence | Owner / dependency |
| --- | --- | --- | --- | --- |
| REL-06 | Rerun local validation for the current baseline | Done | Initial November 9 baseline: metadata/syntax, 105 LWC and 30 MCP tests, whitespace and unchanged-source checks pass; E06. REL-20 expands the gates and passes 109 LWC / 30 MCP tests; E18. REL-21 reruns the full actual-checkout suite on Node 22/24 with six dependency regressions; E20. The prototype safeguard raises dependency checks to ten and passes the full suite on both runtimes; E22. Latest E25 actual-checkout verification passes on maintained Node 22.23.4/24.22.2 with the 17-case preparation gate; no org acceptance is inferred. | Engineering |
| REL-07 | Validate the current complete Aegis Apex release baseline in nonproduction | Done | PUB-APEX-01: check-only 571 components, 311/311 tests across all 38 executable product test classes, zero component/test errors or coverage warnings; 93.14% returned weighted Aegis coverage. Historical shared-org ACC-07-01 remains Failed; its unrelated product failures are not waived. | Engineering; unmanaged product scope |
| REL-08 | Recheck rendered admin, support, developer-viewer, and end-user journeys | Prepared | E40 completes the Aegis-only local role/journey review and confirmed fixes across 14 paths, including six component regressions. Node 22/24 full verify passes: 115 LWC / 30 MCP / 10 dependency tests; offline conversion 389 files. Read-only direct-role inventory finds no ordinary End User candidates; User B remains unverified. ACC-08-01–04 all Not run; actual actor/build/fixture authority and rendered/cross-user/recovery outcomes remain. | QA + engineering; REL-07 |
| REL-09 | Accept supported mobile/responsive and accessibility behavior | Prepared | ACC-09-01/02 define keyboard/focus/announcement/zoom and selected mobile/responsive acceptance with platform exclusions. Surface/device/owner decisions and actual browser/assistive-technology execution remain; E25. | QA/product owner; REL-08 |
| REL-10 | Prove real Email and Case delivery after the hardening | Prepared | ACC-10-01/02 define one intended Email/Case, destination-side proof, masking, audit and replay checks with finite side-effect caps. No delivery executed; approved recipient/sender/Case owner and actual delivery evidence remain; E25. | QA + tenant admin; explicit test destination/action scope |

### Workstream 3 — Reliability, security, and operational evidence

| ID | Task | Status | Completion condition / evidence | Owner / dependency |
| --- | --- | --- | --- | --- |
| REL-11 | Drain representative Flow/async backlogs across multiple pages | Prepared | ACC-11-01/02 prepare 201 Flow / 101 failed-job recipes, at most one late arrival/completion, three sweeps, cursor/cost/reconciliation evidence and cleanup. Target-specific real fixture/capacity approval and live drainage remain; E25. | Engineering; controlled nonproduction capacity |
| REL-12 | Exercise genuine concurrent escalation requests | Prepared | ACC-12-01 defines two callers/two simultaneous requests/one replay/one intended delivery and timing/claim/reconciliation evidence. No concurrent requests were sent; real client/route binding and contention acceptance remain; E25. | Engineering; REL-10 and bounded test plan |
| REL-13 | Exercise capture rejection, transient retry, final publish failure, and recovery | Prepared | ACC-13-01/02 prepare rejection/transient/final-publication and Batch-scope replay cases, existing test seams, attribution/telemetry evidence and bounded cleanup. Controlled target fixture review and runtime execution remain; E25. | Engineering; isolated failure fixtures |
| REL-14 | Verify privacy and reporting across the full lifecycle | Prepared | ACC-14-01/02 prepare own/foreign/sensitive evidence, masking, affected-user omission, protected/null/reopened timing, grouping and exact coverage checks. Actual selected role/lifecycle/outbound observations remain; E25. | Security/QA + engineering; REL-08/REL-11 |

### Workstream 4 — One defined customer pilot

| ID | Task | Status | Completion condition / evidence | Owner / dependency |
| --- | --- | --- | --- | --- |
| REL-15 | Select the first customer, process, and nonproduction environment | Pending | Customer owner, exact operation, capture point, affected roles, data bounds, expected volume, and success criteria named | Product/customer owner; DEC-01 |
| REL-16 | Configure approved diagnostic policy and access | Pending | Context fields, masking, routes, recipients, retention, roles, and instrumentation reviewed for the selected process | Tenant admin + engineering; REL-15 |
| REL-17 | Implement/register only the selected recovery operation, if required | Pending | Exact targets/writes, access checks, confirmation, business idempotency, postcondition, rollback, and audit proven; diagnostics-only pilot can explicitly mark recovery excluded | Customer process owner + engineering; DEC-02 |
| REL-18 | Run pilot acceptance and capture customer sign-off | Pending | Representative successful/failed/denied/repeated operations satisfy section 8; cleanup and unresolved limitations recorded | QA + customer owner; REL-16/REL-17 |
| REL-19 | Register the MCP server in the selected client with the intended customer scope | Pending | Client connects using the documented absolute entry point; corpus isolation/read tools pass; optional writes remain separately selected | Engineering/client owner; DEC-04; explicit pinned launcher/credential-scope review if CLI-backed authentication is selected; E33 excludes bare sf launch |

### Workstream 5 — Release tooling, operations, and launch

| ID | Task | Status | Completion condition / evidence | Owner / dependency |
| --- | --- | --- | --- | --- |
| REL-20 | Add repeatable CI and appropriate lint/static checks | Awaiting billing resolution | Actual GitHub run 42811497088 failed before either Node 22/24 job executed any step: account locked due to billing. Current local full Node 22/24 checks pass. Workflow checks remain intact; no hosted pass or Linux acceptance is claimed. Resolve owner billing and rerun before closing. | Repository owner + engineering |
| REL-21 | Review and resolve or disposition the remaining project dependency findings | Done | E43 closes the six moderate and 12 low entries plus ESLint lifecycle gap through the explicit owned deepmerge patch and isolated ESLint 10/Babel 8 with qualified Salesforce rule ports. Two clean strict-peer trees; both all-severity audits zero; 12 security/compatibility tests and full actual-checkout Node 22/24 gates pass. No audit ignore, threshold reduction, upstream-support claim or production exception. | Engineering; source-backed vendor maintenance is documented |
| REL-22 | Review the separately installed Salesforce CLI used for release | Done | Global CLI 2.156.8 inventory/advisory review preserved (E23); it remains unchanged/unqualified. E26/E29/E31 preserve candidate preparation/remediation. E33 completes local release-use qualification of the exact hardened 2.157.8 nonproduction scope: zero findings, all vendor/API/limit decisions closed, guarded native command/plugin checks pass. Technical eligibility is scoped; production/current authority false. | Engineering; local CLI follow-up complete; target/profile/owner/action binding and actual acceptance remain separate |
| REL-23 | Finalize operating roles, support handoff, and user guidance | Prepared | Operating/support handoff, actual access/role matrix, user quick start and training/acknowledgement guidance delivered; E25. Named owners, agreed operational response/retention, review and actual training/customer acceptance remain. | Product/support + engineering |
| REL-24 | Rehearse recovery and rollback for the agreed release model | Prepared | Recovery runbook, source snapshot and 849-file local hash/mode restoration rehearsal passed; E25/E28. ACC-24-01 Not run: fresh target baseline, authorized metadata/configuration/business-data rehearsal, timing and owner review remain. | Release owner + engineering; stable baseline |
| REL-25 | Complete release exit review and choose a launch date | Pending | Required gates pass; accepted limits and selected scope recorded; exact release artifact and rollout owner identified | Product/release owner; DEC-05 |


## Optional integrations


These seven capabilities are separate from the 55 core entries. Their implementation does not establish a configured provider, licensed agent, working tenant credential, or accepted destination.

| ID | Capability | Current state | Required to finish | Initial deterministic pilot? |
| --- | --- | --- | --- | --- |
| OPT-01 | Live Agentforce enrichment | Awaiting setup; client, async enrichment, mocks, strict response validation, and fallback preservation exist | Dedicated read-only agent/principal, licensing, approved OAuth/Named Credential, scoped instructions, and live success/failure acceptance | Optional |
| OPT-02 | Slack escalation | Awaiting setup; adapter/outbox code exists | Approved tenant/route/credential and actual delivery, masking, failure, and duplicate tests | Optional |
| OPT-03 | Microsoft Teams escalation | Awaiting setup; adapter/outbox code exists | Approved tenant/route/credential and actual delivery acceptance | Optional |
| OPT-04 | Jira escalation | Awaiting setup; adapter/outbox code exists | Approved project/issue mapping, credential, scopes, and issue/replay acceptance | Optional |
| OPT-05 | GitHub escalation | Awaiting setup; adapter/outbox code exists | Approved repository/issue destination, credential/scopes, and issue/replay acceptance | Optional |
| OPT-06 | Generic webhook escalation | Awaiting setup; bounded delivery code exists | Approved endpoint/authentication/payload contract and actual delivery/failure acceptance | Optional |
| OPT-07 | Same-org Tooling debug-log body collection | Awaiting setup; bounded, authorized, masked retrieval code exists | Approved same-org Named Credential, sensitive-context authority, stored log reference, and live limit/denial tests | Optional |

OPT-07 does not automatically enable trace flags or persist raw debug-log bodies in Files. Optional connector setup does not authorize arbitrary business transactions. E07/E08 define the current contracts; provider configuration must be checked when selected.


## Commercial and distribution work


The COM-01 local readiness review and team handoff are now selected and complete (E42).
Managed packaging setup/build remains excluded from this assistant's execution scope, and
the user explicitly excludes the existing development org from package creation. This
commercial plan remains separate from a development/customer pilot and the 25 release tasks.

| ID | Work item | Origin / state | Completion condition when resumed |
| --- | --- | --- | --- |
| COM-01 | Namespace and namespace-org/Dev Hub selection | **Prepared** — local implementation and handoff complete (E43); permanent namespace and actual owning-org verification remain with team | Team selects namespace and separate company-owned environments, verifies settings/permissions/linkage and completes actual namespaced build/install acceptance in COM-02/COM-03 |
| COM-02 | 2GP package build and distribution pipeline | Documented deferred packaging work | Reproducible package versions, dependencies, promotion/distribution rules, and release evidence |
| COM-03 | Clean-org installation and onboarding acceptance | Existing readiness gap, held with packaging | Install into a clean supported org; verify metadata, permissions, initial configuration, and supported app placement |
| COM-04 | Upgrade, migration, and uninstall/data-retention behavior | Existing commercial readiness gap; exact policy unscoped | Upgrade from supported versions without unapproved data loss; document migration and uninstall behavior |
| COM-05 | Commercial licensing, editions, and entitlements | Distribution decision needed; not an approved implementation requirement | Choose the commercial model and implement only the required entitlement behavior |
| COM-06 | AppExchange listing, demo, and submission materials | Historical open go-to-market item, AF-22 | Target buyer/scope, listing assets, support route, and submission package reviewed |
| COM-07 | Security-review evidence and privacy/data-handling documents | Historical AF-22 readiness work; no certification claimed | Assemble the evidence and documents required for the selected distribution path and complete its review |

COM-03 is managed-package installation acceptance. REL-24 is recovery rehearsal for the current release model. These are different tasks and should not be counted twice.


## Pilot acceptance contract


| ID | Scenario | Pass condition |
| --- | --- | --- |
| PILOT-01 | Supported foreground failure | Failure captured with useful sanitized context, correct user attribution, and a durable authorized alert |
| PILOT-02 | Background failure with no browser open | Evidence persists; the intended user later retrieves the correct durable notice |
| PILOT-03 | Manual help for an uncaptured/native failure | User can describe the issue, receive bounded guidance, and escalate without pretending automatic interception occurred |
| PILOT-04 | Unknown or uncertain diagnosis | Uncertainty stays explicit; useful evidence and escalation remain available; no unregistered write is attempted |
| PILOT-05 | Approved correction/retry, if selected | Confirmation, exact operation, real business postcondition, audit, and idempotency pass; otherwise mark recovery explicitly excluded |
| PILOT-06 | Denied or failed recovery | Missing permissions, missing confirmation, invalid targets, duplicate requests, and mutation failure are denied or rolled back with useful audit |
| PILOT-07 | Repeated failure and escalation | Intended incident grouping and one delivery per request key; concurrent/replayed requests do not duplicate business effects |
| PILOT-08 | Privacy, load, and cleanup | Foreign evidence denied, sensitive values masked, agreed volume stays within budgets, temporary artifacts cleaned up, and known limits signed off |

For each executed case record: source commit/snapshot, environment, role, fixture/process, expected result, actual result, sanitized evidence link, business postcondition, cleanup, and reviewer. A test is not Done until the actual result and cleanup are recorded.


## Proposed enhancements


These ideas were added during this planning pass. They are **Proposed**, have not been estimated, and are not confirmed missing requirements. Discovery must first check for reusable behavior in the existing product and customer tooling.

| ID | Proposed enhancement | User/business value | Earliest sensible point / dependency |
| --- | --- | --- | --- |
| IDEA-01 | Capture-coverage assessment and instrumentation assistant | Show which approved Flows/Apex/integrations have capture coverage and suggest reviewed wiring changes | After pilot; build on OPS-03; no promise to intercept unsupported platform saves |
| IDEA-02 | Rule configuration and test workbench | Let admins test representative errors, severity, masking, and proposed guidance before activation | After baseline acceptance; reuse existing rule metadata |
| IDEA-03 | Known-issue/runbook authoring and versioning | Connect recurring diagnostics to reviewed explanations and resolution steps | After pilot; retain source provenance and explicit uncertainty |
| IDEA-04 | Collaborative incident workbench | Assignment, investigation notes, ownership, and review history around grouped incidents | After support workflow validation; reuse Incident rather than duplicate it |
| IDEA-05 | Post-incident review package | Assemble a reviewed timeline, evidence, actions, and unresolved cause questions | After lifecycle/metrics acceptance; avoid invented root-cause claims |
| IDEA-06 | Advanced analytics and saved operational views | Trend comparisons, affected-process views, recurrence, and measured recovery outcomes | After sufficient reliable data; explicit denominators and permissions |
| IDEA-07 | SLA breach reminders and governed escalation policies | Help support teams prioritize aging unresolved issues | After SLA ownership and actual routes are accepted |
| IDEA-08 | Subscriber/rejection health and replay console | Expose failed processing, retry budgets, and recovery actions to authorized operators | After live failure acceptance; bounded replay and retained audit |
| IDEA-09 | Uncertain-delivery reconciliation console | Help operators reconcile attempted deliveries before explicitly requesting a resend | After live delivery acceptance; preserve ESC-05 claim semantics |
| IDEA-10 | Deployment/configuration change correlation | Give investigators relevant recent change context near a failure | Later; reviewed metadata access and evidence scope required |
| IDEA-11 | Audited redacted diagnostic download/export | Share an approved evidence bundle outside a live escalation workflow | After evidence/export permission and retention requirements are defined |
| IDEA-12 | Guided evidence submission | Let users deliberately attach approved screenshots/files with clear context | After file-access and sanitization requirements; no automatic capture of sensitive screens |
| IDEA-13 | Knowledge curation/review interface with staleness checks | Maintain process knowledge, source reviews, versions, and customer scoping more easily | After current MCP client acceptance; reuse the existing strict corpus schema |
| IDEA-14 | Reusable customer process packs | Versioned capture/rule/runbook templates for repeatedly accepted business processes | After at least one genuine customer acceptance; no enabled generic repair defaults |
| IDEA-15 | Diagnosis evaluation and feedback quality framework | Measure recommendation usefulness, unsupported claims, fallback quality, and unsafe-action refusals | Before expanding AI reliance; grounded test cases and actual outcomes |
| IDEA-16 | Predictive/recurrent-failure intelligence | Explore whether reliable patterns can identify emerging operational problems | Later research; requires sufficient quality data and measured value |
| IDEA-17 | Localization and user-language preferences | Improve guidance, dates, and messages for multilingual teams | After supported languages and content ownership are chosen |
| IDEA-18 | Expanded supported mobile experience | Improve the approved mobile journeys and fallback behavior | After REL-09 establishes current support; separate native app only if justified |
| IDEA-19 | Continuous operational health and configuration drift reporting | Track disabled listeners, stale rules, schedules, and connection readiness over time | After baseline operational owners/thresholds are known; reuse health services |
| IDEA-20 | Hosted MCP gateway / broader support-console distribution | Evaluate remote client access where local stdio is insufficient | Separate architecture decision; real tenant identity/isolation, hosting, and operating model first |

Promote an idea only by recording its problem, acceptance criteria, chosen scope, dependencies, and priority. Give selected work an execution task ID. Keep rejected/held ideas visible with the reason instead of treating every idea as committed development.
