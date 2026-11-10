# CI and static checks

The repository's local validation is also the GitHub Actions validation path. The workflow
checks pull requests and pushes to `main` on Ubuntu 24.04 with Node 22 and Node 24, using
Python 3.12. It contains no Salesforce login, deployment, publication, or customer operation.

The workflow file is [ci.yml](../.github/workflows/ci.yml). It takes effect after a separately
authorized commit and push. A locally validated workflow is not evidence of a hosted run.
Branch-protection requirements must be selected after the first hosted checks exist; no
repository settings are changed by adding this file.

## Run locally

```bash
npm ci --ignore-scripts --no-audit --no-fund
npm ci --prefix tools/lint --ignore-scripts --no-audit --no-fund
npm run verify
npm run audit:deps
npm audit --prefix tools/lint --json
```

The dependency audit needs public npm registry connectivity. The other checks use local
source and installed tools. No Salesforce identity, AI provider key, or customer data is
needed. `npm test` remains the separate, explicitly targeted Salesforce test command and
is not invoked by this CI workflow.

| Command | What it checks | Boundary |
| --- | --- | --- |
| `npm run audit:local` | Metadata/XML, bundle and manifest completeness, private evidence objects, event commit contracts, bounded subscribers, internal event permission denial, unique request key, protected fields, permission section ordering | Static source checks; no org validation |
| `npm run test:apex:syntax` | Grammar and inline-query syntax in all product Apex classes/triggers | Does not compile against Salesforce APIs or execute Apex |
| `npm run test:lwc:syntax` | Every bundle's JavaScript, HTML, and CSS through the pinned LWC compiler, using its metadata API version and LWS transforms | Local compiler syntax/transforms; no rendered Salesforce or server-side contract validation |
| `npm run test:source:syntax` | Project JSON, Python AST, shell syntax, and standalone Node syntax | Parses source without executing application/operational scripts |
| `npm run check:release-prep` | Prepared acceptance-case contracts, finite fixture caps, source references and unexecuted evidence-template consistency | Local preparation only; it performs no org operation and does not count a prepared case as a passing acceptance test |
| `npm run test:parity` | Eight snapshot-comparison regressions: inactive field/default permission representations plus preservation of true/unknown grants, duplicates, attributes, field settings and formula policies | Local comparator only; no org or authority inference |
| `npm run lint` | JavaScript correctness, Salesforce LWC decorator/wire/import rules, dangerous dynamic code, unsafe DOM patterns, public API reassignment, and Apex invocation shape | Selected source-correctness rules; no blanket security certification |
| `npm run test:deps` | Advisory-range guard, dependency API compatibility, actual LWC wire-rule enforcement, and deepmerge prototype-guard regressions | Twelve compatibility/security checks, including the owned merger patch without runtime prototype protection |
| `npm run test:unit -- -- --runInBand` | Existing LWC Jest suites plus typed-reference interaction regressions | Browser/component mocks; real browser/mobile acceptance remains separate |
| `npm run test:mcp` | MCP protocol, scoping, corpus bounds, credential handling, and confirmed-write boundaries | Offline protocol/adapters; no customer org connection |
| `npm run audit:deps` | All-severity registry advisory report, with failure at high or critical severity | Advisory counts change; low/moderate findings remain visible and need review |

## Lint configuration

[eslint.config.cjs](../eslint.config.cjs) uses the preserved Salesforce LWC base rules through
the qualified local port in `tools/lint`, plus the
ESLint recommended correctness rules and selected Lightning/LWC rules. It covers product
LWC JavaScript, Jest tests/mocks, the MCP server/tests, validation scripts, and root tooling
configuration. Generated output, vendor code, temporary QA projects, and local auth caches
are excluded from JavaScript lint scope.

Production-only wire/decorator checks are scoped away from Jest's function-based wire
mocks. Tests still receive normal JavaScript checks and the correct Jest/browser/Node
globals. Callback argument signatures and unused catch bindings are allowed; unused local
variables and undefined names remain errors. Lint exits on warnings as well as errors.

Two intentional design choices are explicit:

- The application uses bounded refresh/reconnect timers. This initial correctness policy
  does not adopt the broader recommended rule that forbids all asynchronous operations.
- The knowledge corpus validator intentionally rejects control characters. Its existing
  control-character regular expression has one documented line-level lint exception;
  that validation behavior is unchanged.

Reference-input handlers update the components' existing private state through a shared
internal path. Public `correlationId` setters still normalize values, refresh/reset the
same state, and preserve stale-response guards. The remediation component's public `result`
API remains available through a getter/setter while internal execution updates private state.
No Apex method, event contract, component metadata, template, or styling changed for this setup.

## Reproducibility and workflow permissions

- npm versions are exact and the lockfile is committed only when explicitly authorized.
- The LWC compiler is a direct pinned development dependency, using the same version as
  the existing Jest toolchain.
- ESLint 10.14.0 / Babel 8 live in a separate locked lint installation. Compiler/Jest retain
  Babel 7. Salesforce rule ports are locally qualified; upstream ESLint 10 support is not claimed.
- Both dependency trees use strict peer installation and both locks are cached/installed in CI.
- Checkout, Node setup, and Python setup use full official commit SHAs. Checkout does not
  persist credentials; workflow token permissions are limited to `contents: read`.
- Dependency installation disables package lifecycle scripts. The workflow has no org,
  provider, publishing, or deployment secrets and does not install the Salesforce CLI.
- Local dependency, LWC, coverage, and MCP test entry points explicitly start Node with
  `--disable-proto=throw`. The CI verification step also sets that option through
  `NODE_OPTIONS` so child Node processes inherit it. This environment setting is scoped to
  verification; it does not change checkout/setup actions or the external Salesforce CLI.
  Directly invoking the raw vendor binary or `node --test` bypasses the local entry points.
- Workflow syntax is checked with actionlint 1.7.12. Its Linux archive is fetched from the
  official release and checked against a literal SHA-256 before extracting the named binary.
  Automatic shellcheck/pyflakes integration is disabled; shell/Python syntax is checked by
  the source syntax command above.
- Concurrent runs for the same branch/ref cancel older runs; matrix failures do not cancel
  the other Node version. Each job has a 15-minute timeout.

## Current acceptance limits

The reviewed source is merged to main through [PR #2](https://github.com/WahidKhanTLG/Aegis-Flow/pull/2).
[Actual hosted run 42811497088](https://github.com/WahidKhanTLG/Aegis-Flow/actions/runs/42811497088)
failed before either Node 22/24 job executed any step: GitHub reports the account is locked
because of billing. Full current-source local verification passes on Node 22.23.4 and
24.22.2. No check or workflow permission was relaxed. The account owner must resolve billing,
then rerun the hosted matrix; REL-20 remains open and no hosted/Linux pass is claimed.

The November 10 local packaging update closes the remaining project findings through the
explicit owned deepmerge security fork and isolated maintained lint runtime. Both all-severity
locked audits are clean. No thresholds were lowered or advisories ignored. The global CLI is
separate and unchanged. See [dependency review](DEPENDENCY_SECURITY_REVIEW.md) for fork ownership,
source-backed archives, compatibility evidence and maintenance requirements.

`npm run check:packaging` checks exact managed-source membership, global subscriber action
contracts, unsafe namespace bindings and staging transformations. `npm run test:packaging`
exercises refusal, traversal/symlink, isolation and source-preservation behavior. Neither
command creates a package, accesses a Salesforce org or proves namespaced compilation.

Current unmanaged Apex compilation and regression pass the separately authorized
571-component / 311-test check-only review. Actual namespaced build/install, rendered
browser/mobile, live load/concurrency, provider delivery and customer pilot acceptance
remain in the [product tracker](PRODUCT_PLAN_AND_TRACKER.md). Local LWC syntax checks
and Jest do not replace those environment tests.

## Primary tool references

- [Salesforce LWC lint configuration](https://github.com/salesforce/eslint-config-lwc)
- [ESLint flat configuration](https://eslint.org/docs/latest/use/configure/configuration-files)
- [GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- [Official actionlint release](https://github.com/rhysd/actionlint/releases/tag/v1.7.12)
- [Minimatch advisory](https://github.com/advisories/GHSA-g3hv-75wg-m249)

The E47 development deployment passes 311/311 Apex tests and a focused 9/9 lifecycle
follow-up; the final 717-file scoped comparison passes. Both supported local Node versions
pass the complete verify chain including eight new parity regressions. The hosted billing
block remains separate. See [deployment verification](DEVELOPMENT_DEPLOYMENT_VERIFICATION.md).
