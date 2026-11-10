# External Salesforce CLI review — November 9, 2026

REL-22 completes the inventory and advisory review of the separately installed release
tool. It does not approve that tool for credentialed release use or change its installation.

## Installed baseline

| Item | Observed value |
| --- | --- |
| Distribution | npm global `@salesforce/cli` |
| CLI | 2.156.8, published October 26, 2026 |
| Runtime | Node 24.13.0; installed CLI requires Node >=22 |
| Executables | `sf` and `sfdx` resolve to the same sf v2 entry point; the latter is an alias |
| Core plugins relevant to release | Deploy/retrieve 4.2.18; Apex 4.4.4; org 7.0.2; auth 6.0.0 |
| Libraries relevant to org operations | Salesforce core 9.4.4; source-deploy-retrieve 13.10.0 |
| Inventory scope | 848 package instances under the installed CLI, including the root package |
| Stable npm channel at review | `latest` = 2.157.8, published November 3, 2026 |
| Other channels at review | `latest-rc` = 2.158.7; `nightly` = 2.159.4; neither selected |

The current Node version satisfies the CLI's declared engine range. This check does not
establish that every dependency or runtime security patch is current. Additional user,
linked, or just-in-time plugins are outside the scanned core distribution and must be
inventoried if selected for a later release operation.

## Advisory results and applicability

Public npm bulk-advisory results were matched against exact installed versions using
semver. The result is **16 distinct advisory matches across eight package names: seven
high and nine moderate**, with no critical matches in this scan. These are root-advisory
matches, not npm's propagated package counts and not demonstrated exploitation.

| Installed dependency | Relevant path / use | Review result |
| --- | --- | --- |
| `marked` 2.1.3 | `marked-terminal` dependency; the separate plugin-info copy is newer | Two high regex denial-of-service matches |
| `basic-ftp` 5.3.1 | `get-uri` transport dependency | One high FTP listing parser complexity match |
| `protobufjs` 7.5.6 | `o11y` telemetry dependency | One high and three moderate parsing/expansion matches |
| `undici` 6.29.0 | Bundled npm/node-gyp subtree; separate top-level HTTP client is not this affected instance | Three high and two moderate transport/parser matches |
| `@opentelemetry/core` 1.30.1 | Application Insights / tracing dependencies | One moderate baggage-allocation match |
| `ip-address` 10.7.2 | Bundled npm's socks dependency | One moderate parser-complexity match |
| `minimatch` 9.0.9 / 10.2.5 / 10.2.6 | Source-deploy-retrieve, oclif/glob, and bundled npm paths | One moderate glob-amplification advisory across three instances |
| `glob` 11.1.0 / 13.0.6 | Agent plugin and bundled npm paths | One moderate cancellation-bypass advisory across two instances |

Dependency paths were checked with `npm explain`. FTP, telemetry, plugin installation,
and specific parsing inputs have different reachability requirements; this review does
not claim they execute during every deployment. Telemetry being disabled for review does
not patch its libraries. The standalone HTTP client used by org tooling must not be
confused with the affected nested npm copy.

No source overrides were applied to the global CLI, and the product's minimatch override
does not reach it. Its 16 historical matches were separate from the product's then-recorded 12 low deepmerge entries.
The November 10 project security fork/lint port clears those product entries; it does not modify or qualify the global CLI.
The product CI does not install this CLI or provide org credentials.

## CLI-01 — local release-use review complete

The exact hardened CLI **2.157.8** candidate is locally qualified for the restricted
nonproduction validation/Apex-test workflow in the [decision record](../release-preparation/cli-release-use-review.json).
All 13 caller-range overrides, the prior protobuf exact pin, API changes and retained
limits have explicit closed local dispositions. No local tool-review item remains open.
The [qualification](../release-preparation/cli-qualification.json) now records technical
eligibility **true within that scope**, production eligibility **false**, and all current
execution authorities **false**. It does not authorize an org operation or deployment.

### Exact identity and supporting evidence

The artifact remains unchanged from E31: 844 package instances and 34,154 file/link/mode
entries, canonical SHA-256 `3f8998228b699c3ac48bdf9e279c0fdd0c380611ae8bfea1b0e1a06e59a2fdf5`.
The [two-layer construction manifest](../release-preparation/cli-remediation-manifest.json)
retains the original official archive, five high-remediation payloads, embedded protobuf
wrapper and six moderate-remediation payloads. Its construction layers and replay result
are unchanged; its technical eligibility now points to this scoped local decision.

Maintained macOS arm64 Node **22.23.4 and 24.22.2** binary hashes, the exact `bin/run.js`
hash, all 29 bundled plugin/command-manifest identities and the exact source manifest hash
are bound in the decision. Fresh physical-tree advisory matching still reports **zero
findings**. Prior E31 evidence remains 72 security/control results, 42 compatibility tests,
22 offline CLI/npm checks, two identical 389-file conversions and complete archive replay.

The local review adds **14 contract tests** and **eight guarded entry-point/version/help
checks** across both runtimes. Actual Config loads use only the 29 sealed bundled plugins,
with user/development/JIT discovery disabled; five real command classes load without any
`run()` method invocation. Outbound network attempts are zero. Inline yoga-layout WASM
data-URI loading is local and is recorded separately from network requests. Targeted
checks also cover actual TUF delegation boundaries, release-age exclusion semantics,
package-json readme discovery and telemetry-disable behavior.

### Override and API decisions

- Oclif's minimatch override is accepted for selected command dispatch/plugin matching.
  Real loader selection and sealed command loading pass; arbitrary plugins remain excluded.
- SDR's minimatch override is accepted for the exact reviewed manifest and recorded
  source resolution/conversion behavior. Alternate selectors and the known metadata-only
  exclusion path are excluded. The full 389-file conversion remains identical.
- The agent-plugin glob override and installed npm subtree are accepted as retained
  supporting dependencies. Agentforce, package/plugin installation, updates, trust changes
  and general npm execution are excluded from this release-use scope. Actual helper and
  cancellation tests support the retained dependency APIs.
- The protobuf exact pin and private embedded-bundle adaptation are accepted for the
  tested serializer paths with telemetry disabled. Real reporter imports use client,
  collectors and simple_collector; the pre-existing orchestrator/uploader paths are excluded.
- Removed minimatch `makeRe`/AST/prototype interfaces, changed Matcher/set representation,
  bounded optimization, partial/dot/globstar behavior and numeric-range semantics are
  acknowledged. Selected callers use tested matching APIs; no shim or general old-API
  compatibility claim is made. Glob bundled/raw and path-scurry 3 behavior are covered.

The decision is local engineering compatibility acceptance under explicit constraints,
not Salesforce vendor endorsement, a known-vulnerability waiver or compliance certification.
Parent declarations stay unchanged. The standard npm wrapper-ci peer-lock failure is
closed for this workflow by selecting the demonstrated archive/overlay replay construction;
it is not claimed repaired. Other OS/runtimes and arbitrary/native/additional plugins are
not qualified. Refresh advisories and re-review any identity, command or scope change.

### Qualified command and invocation scope

Use an explicitly bound absolute Node binary plus candidate `bin/run.js`, with their
recorded hashes, controlled empty plugin state and `NODE_ENV=production`. Unset injection
and implicit-target variables; disable telemetry, updates and forced version refresh as
specified in the decision. The current shared global CLI **2.156.8 remains unqualified**.

| Command | Qualified mode and constraints |
| --- | --- |
| `project convert source` | Offline; exact manifest hash, API 67.0 and a controlled new output directory |
| `project deploy start` | Later explicitly authorized nonproduction check-only use; mandatory `--dry-run`, exact manifest, API 67.0, explicit verified target, `RunLocalTests`, bounded wait and JSON |
| `project deploy report` | Later authorized status read for the exact owned dry-run job and target; no most-recent fallback |
| `apex run test` | Later authorized nonproduction tests for the selected source/acceptance window; explicit target/API/test level/wait/evidence |
| `apex get test` | Later authorized status read for the exact owned test run and target |

Salesforce [documents `project deploy start --dry-run --test-level RunLocalTests` for
sandbox validation](https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_project_deploy_validate.html).
The prepared acceptance recipe now uses that path. Production-oriented `project deploy
validate`, actual/quick deployment, destructive changes, anonymous Apex, business writes,
credential-output commands, Agentforce/provider actions and package/plugin changes are
outside this local decision. No such operation was executed by this review.

The current MCP adapter and existing npm/shell wrappers invoke bare `sf`. They do not
automatically select this candidate. CLI-backed MCP binding remains selected-client work
under REL-19; it is excluded here. No integration or wrapper implementation was changed.

### Execution-readiness boundary

CLI-01's local technical gate is complete. The target-profile example can reference this
qualified tool but remains an **unbound example**: no target/run/owners, no selected cases,
no action or delivery authority, and no fabricated acceptance results. It still must fail
`--require-ready`. Source/profile structural checks are not a runtime authorization engine.

Next bind and independently verify the nonproduction target, owners, exact release source,
cases/actions/budgets and evidence storage; obtain explicit authority and perform the
prepared acceptance. All 17 actual cases remain Not run. Production and deployment need
separate selection/review/authority. No local vendor/API review is being deferred to that
phase, and no target/runtime/customer acceptance is claimed by completing this local gate.

## Command and credential boundaries

Installed command manifests contain `project deploy start`, `project deploy validate`,
`apex run test`, `org display`, and `org auth show-access-token`. Their presence and flag
names were inspected without executing an org operation.

Salesforce's credential-redaction change applies from CLI 2.136 onward. The MCP adapter
already uses `org display` for metadata and the dedicated `org auth show-access-token`
command internally for an explicitly configured alias. Its offline tests cover token
handling and redaction; this review does not establish live authorization or authentication.
Do not use credential-output commands as an inventory or smoke test, or save auth state
in review artifacts. No tokens, auth URLs, org identities, or private config were collected.

Historical smoke attempts on the original shared CLI remain **not verified**. They failed because
the default CLI logger could not write the protected user state directory. A bounded
retry that routed logging to stderr timed out at 40 seconds on the version command; it
was terminated before any later retry commands. Version evidence comes from executable
resolution and the installed package manifest, not a successful CLI run. The new isolated candidate has the separate successful maintained-runtime results above;
they do not retrospectively verify the shared installation.

## Primary references

- [Salesforce CLI releases](https://github.com/salesforcecli/cli/releases)
- [CLI 2.157.8 release](https://github.com/salesforcecli/cli/releases/tag/2.157.8)
- [Official update methods and auto-update controls](https://developer.salesforce.com/docs/platform/sfdx-setup/guide/sfdx-setup-update-cli.html)
- [Credential-output security change](https://help.salesforce.com/s/articleView?id=005385006&language=en_US&type=1)
- [High TLS-option advisory in the nested npm HTTP library](https://github.com/advisories/GHSA-2m5v-pch6-74hx)
- [High FTP-parser advisory](https://github.com/advisories/GHSA-c475-qrg2-pj4r)

The dated local evidence contains all 16 advisory identifiers, vulnerable ranges, exact
installed instances, dependency paths, registry channel metadata, and preservation hashes.
Recheck it for drift before a later release; advisory/version data changes over time.
