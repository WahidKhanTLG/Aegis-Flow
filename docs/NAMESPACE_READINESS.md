# Namespace and managed-source contract

Updated November 10, 2026. This replaces the July 27 namespace assumptions.
Local packaging development is implemented. Actual namespace registration, Dev Hub readiness,
namespaced compilation and subscriber installation still need environment evidence.

## Environment and source

Keep the existing development org out of namespace registration and commercial packaging.
The team selects a separate company-controlled namespace org and durable Dev Hub, preferably
its Partner Business Org. Verify actual IDs, ownership, capabilities, permissions, capacity
and Namespace Registry linkage. Old aliases and the historical reserved-org note are not evidence.

Managed 2GP is source driven; the Dev Hub owns packages and is not the source deployment target.
The development project deliberately retains an empty namespace. No namespace was reserved.
[Salesforce org responsibilities](https://developer.salesforce.com/docs/platform/pkg2-dev/guide/sfdx-dev-dev2gp-before-know-orgs.html).

## Implemented behavior

- MCP uses explicit validated `AEGIS_PACKAGE_NAMESPACE`. Empty/unset preserves unmanaged
  development. A selected namespace inserts its segment before the REST mapping. Invalid
  values fail before credential/network access. HTTP errors never select an alternative route.
- Record forms, pickers, dashboard columns and diagnosis reads use schema-derived API names.
  Same-named subscriber fields cannot replace the intended packaged display fields.
- Custom alert channels come from Apex describe. Empty/rejected/mismatched lookup marks live
  streaming unavailable and retains saved-notice refresh. No bare custom-event fallback remains.
  Event payload fields use the package prefix; the standard Flow error event stays unprefixed.
- Nine subscriber action classes, invocable methods, wrapper types, variables and wrapper
  constructors are global. Existing permission, confirmation, bulk and data checks are preserved.
  Internal service methods remain public. This does not enable Agentforce or a business operation.
- The retry interface and existing request/result DTOs are global for registered subscriber
  implementations. Builtins resolve through type tokens; other registered classes resolve
  package-local, local subscriber, then explicitly qualified namespace/class. All existing
  registration, permission, attempt, savepoint and business idempotency requirements remain.

Subscriber actions require these global contracts. Freeze their names and field signatures
before a first managed release; do not make all services global.
[Salesforce managed agent requirements](https://developer.salesforce.com/docs/platform/apex-dev/references/apex-dev/apex-manpkgs-agent.html),
[invocable visibility](https://developer.salesforce.com/docs/platform/apex-dev/references/apex-dev/apex-classes-annotation-invocablemethod.html).

## Metadata-as-data ownership

| Value | Contract |
| --- | --- |
| Package object/field references in code | Typed schema/static references or describe-derived full names |
| Dynamic business object/field configuration | Exact fully qualified describe names and allowlists; standard Account/Description remain standard |
| Subscriber/third-party fields, classes and credentials | Explicit administrator-reviewed identity and owner; no inferred Aegis prefix |
| Retention objects | Stable logical keys Error_Log__c and Diagnostic_Session__c select typed queries |
| Action, handler and CMDT developer keys | Stable logical identifiers; never rename to prepend a namespace |
| Retry classes | Builtin type tokens; explicit registered implementations; qualify third-party classes as namespace.ClassName |
| Customer Flow and required permission | Exact reviewed subscriber configuration; no default customer recovery is enabled |

Apex resolves same-package names within its namespace. Literal dynamic SOQL is not automatically
broken; metadata text is not automatically rewritten. Do not blanket-prefix raw strings.
The namespaced Apex tests must still run in the actual managed environment.
[Salesforce namespace resolution](https://developer.salesforce.com/docs/platform/apex-dev/references/apex-dev/apex-classes-namespace-prefix.html).

## Package inputs and checks

The initial boundary is one managed core with dormant optional adapters. The historical
four-package split is not part of this baseline. `packaging/managed-source-files.json`
classifies every metadata/test/editor path. Managed source excludes development failure flows,
standard-app overrides/utility pages, the customer Contact layout, sample tax schema/access
and sample retry registration. Staging removes the corresponding sample field permission
from Product Admin only in its generated copy. Development source stays intact.

`npm run check:packaging` rejects missing/unclassified/symlinked metadata, action visibility
regressions, raw LDS object/field bindings, guessed alert fallback and subscriber-user bindings.
`npm run test:packaging` checks staging isolation and refusal behavior. See
[packaging handoff](PACKAGING_DEVELOPMENT_HANDOFF.md).
