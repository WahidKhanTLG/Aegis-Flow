# Dependency security and tooling qualification

Updated November 10, 2026. Earlier November 9 findings remain historical evidence.
The current root and isolated lint lockfiles each return zero all-severity npm audit findings.
No ignore list, lowered threshold, forced peer install or production risk exception was used.
This review covers development dependencies, not the global CLI or running Salesforce org.

| ID | Issue | Closed local disposition |
| --- | --- | --- |
| DEPS-01 | Minimatch amplification | Reviewed override to 11.0.5 in both trees; matcher and wire-boundary tests pass |
| DEPS-02 | Deepmerge prototype poisoning | Source-backed owned security fork replaces the actual Jest dependency and rejects __proto__ on both operand paths |
| DEPS-03 | ESLint 9 end of support | Isolated ESLint 10.14.0 / Babel 8 lint stack with locally qualified Salesforce rule ports; compiler/Jest keep Babel 7 |

## Explicit security fork

No fixed upstream deepmerge release was available. `tools/vendor/safe-deepmerge` identifies
itself as **@aegis-flow/safe-deepmerge**, derived from deepmerge 4.3.1. Its API-compatible
version remains 4.3.1 for consumer range compatibility. Its MIT license, upstream entry hash,
patch and fork identity are retained. This is not a published upstream fixed release.

The root file dependency and `$deepmerge` override make Jest load the packed owned fork.
The two code changes discard __proto__ before copying target keys or merging source keys.
No prototype setter is read or written for that key. Three original attacks, ordinary merges,
input isolation, actual loader identity and an unguarded child process are permanently tested.
A 400-case benign differential check against the original bundled implementation found identical
results across scalar/object/array/date/regexp inputs and four merge-option combinations.

The zero audit result for the owned fork is supported by code review and security tests; it
is not a security certification. Upstream's advisory still applies to unpatched upstream code.
Node's prototype guard stays as defense in depth; correctness no longer depends on it.
The receiving tooling owner maintains this explicit fork until a qualified upstream replacement.

## Maintained lint runtime and local rule port

`tools/lint` has a separate package/lockfile with ESLint 10.14.0, Babel 8.1.0 and parser 8.0.7.
The compiler/Jest tree uses Babel 7.29.13. Clean installations enforce strict peers and disable
lifecycle scripts. No --force or --legacy-peer-deps is used.

Salesforce's published LWC/Lightning plugins still declare ESLint 9 peers. The local ports
retain their rule implementation unchanged, adapt peer metadata for the qualified ESLint 10 /
Babel 8 combination, and remove unused vendor development scripts/dependencies. This is
**local compatibility qualification**, not Salesforce's upstream endorsement of ESLint 10.

The Salesforce base rules, adapter definitions and license are retained under tools/lint.
Unused shareable-config/import/Jest lint dependencies were removed; their unactivated rule sets
were not part of this project's configuration. Browser globals remain pinned to the same
15.14.0 data. All previous 77 rules remain; the current configuration has 80. Existing severities
remain, and globalThis shadow checking is stricter. Expanded default option reporting is
recorded in qualification evidence. Positive/negative wire, API reassignment, unsafe DOM and
Apex invocation checks pass. Matcher tests now exercise the actual maintained consumers;
no application regression assertion was removed to make the migration pass.

Source-backed deterministic vendor archives and licenses are included. Changes to vendor
source require rebuilding those archives, recording fingerprints and repeating qualification.

## Reproduce

```bash
npm ci --ignore-scripts --no-audit --no-fund
npm ci --prefix tools/lint --ignore-scripts --no-audit --no-fund
npm run verify
npm audit --json
npm audit --prefix tools/lint --json
```

Qualified runtimes are Node 22.23.4 and 24.22.2. The lint stack requires Node 22.18+ or 24.11+.
The full run passes 124 LWC, 33 MCP, 12 dependency/security and eight packaging tests, plus
metadata/manifest checks, 105 Apex grammar inputs, 14 LWC bundles / 39 compiler inputs, source
syntax and lint. Hosted CI, actual Apex/namespaced compilation and installation remain separate.

## References

- [Deepmerge advisory](https://github.com/advisories/GHSA-gcqx-w48m-w2h4)
- [Minimatch advisory](https://github.com/advisories/GHSA-g3hv-75wg-m249)
- [ESLint support](https://eslint.org/version-support/)
- [Salesforce lint plugins](https://github.com/salesforce/eslint-plugin-lwc)
- [Salesforce lint configuration](https://github.com/salesforce/eslint-config-lwc)
- [npm overrides](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/#overrides)
