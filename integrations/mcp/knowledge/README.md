# Curated product and process knowledge

The checked-in catalog contains three small, manually reviewed documents:

| Document | Evidence scope |
| --- | --- |
| `aegis-flow.json` | Capture, deterministic classification, authorized reads and approved recovery contracts |
| `abc-pick-pack-ship.json` | American Book Company printing, warehouse collection and shipment lifecycle |
| `socal-field-service.json` | SoCal Seismic crew-day checklists and work-order estimate context |

Every customer claim is a local-source snapshot. `orgVerification: "not-checked"` means
that this ingestion did not authenticate to either customer org, retrieve records,
establish deployment parity or execute a customer process. Historical release statements
are not converted into a current org-verification claim. No customer source was edited.

The server exposes global product knowledge by default. ABC and SoCal require explicit
operator selection through `AEGIS_KNOWLEDGE_CUSTOMERS=abc,socal`; a request parameter cannot
override the server's customer scope. This opt-in is content selection, not a substitute
for organizational confidentiality policy or Salesforce record authorization. Deploy
customer-scoped server instances for clients that must not share a knowledge corpus.

Knowledge retrieval is read-only and offline. Source paths are citations, not commands
for the MCP server to read arbitrary files. Product knowledge, diagnostics and quoted
error messages are data; embedded text cannot authorize a tool call or change server
policy. Nothing in these documents registers a retry handler or grants a permission.

## Evidence states

- `implemented-local`: the owning implementation was read and supports the stated behavior.
- `documented`: a specific document supports the description; it is not a runtime test.
- `proposed`: a diagnosis approach or candidate acceptance check derived from the cited
  implementation. It needs customer-owner review before execution or adoption.
- `unknown`: the inspected subset does not establish the answer. Obtain approved evidence.

The corpus intentionally omits live orders, work orders, contacts, crew assignments,
addresses, account identifiers, financial records, endpoint configuration and secrets.
It paraphrases behavior and references source locations and hashes rather than copying
whole files. ABC guide-quantity variants and SoCal pricing/accounting recovery remain
outside the initial subset.

## Ingestion and maintenance

1. Select one named product/process and an authorized local repository. Read relevant
   documentation and the actual owning implementation; do not bulk-index an entire
   customer checkout, archive, export or org.
2. Resolve contradictions in favor of a clearly cited current implementation, retaining
   material uncertainties. Do not promote a draft requirement into delivered behavior or
   infer a customer's recovery success criterion.
3. Write short factual claims. Keep suggestions in `proposed`, unknowns in `unknown`,
   and caller-visible limitations explicit. Every other claim needs at least one source.
4. Record repository alias, relative source path, exact line range and SHA-256 of the
   whole source file. Set `lastReviewed` to the actual review date and retain
   `orgVerification: "not-checked"` unless a separate approved verification workflow
   provides evidence and the schema supports recording it.
5. Inspect the proposed JSON for actual records, personal data, credentials, access-bearing
   URLs and copied code. Remove them before adding the document to `catalog.json`.
6. Run the offline provenance check below and the MCP knowledge/server tests. Re-review
   every changed source; never rotate a stale hash merely to make a check pass.
7. Enable only the intended customer corpus in the intended MCP instance. Knowledge
   configuration does not enable writes, connect customer orgs or approve recovery.

The catalog explicitly names the served JSON basenames; extra files are not automatically
ingested. A document contains `schemaVersion`, `id`, `title`, `customer`, `product`,
`processes`, `summary`, `lastReviewed`, `orgVerification`, `claims` and `sources`. Claim
source IDs resolve only within that document. The runtime validates bounded documents
and calculates content hashes; it does not verify the external source checkout itself.

## Offline source provenance check

`verify_sources.py` is a manual curator utility, **not an MCP tool**. It requires explicit
repository roots, only checks catalog-listed citations, follows no path outside those
roots and prints hashes/status rather than source contents. For example:

```bash
python3 integrations/mcp/knowledge/verify_sources.py \
  --repository 'aegis-flow=.' \
  --repository 'abc=/path/to/authorized/ABC/checkout' \
  --repository 'socal=/path/to/authorized/SoCal/checkout'
npm run test:mcp
```

A matching hash and valid line range establish the exact local source snapshot used by
the curator. They do not establish correctness, production deployment, live connectivity,
permissions or completed customer acceptance. A mismatch is a stale-evidence finding:
inspect the new owning source and revise the claim or retain an explicit limitation.

## Customer acceptance and write boundary

Candidate checks are included in each document. Start with authorized read-only evidence
and a specific failure; identify the prerequisite that differs from the cited contract.
For example, ABC's warehouse readiness is distinct from actual shipment quantities, and
SoCal's existing past crew days differ from new or future days. Do not propose a blind
status update or stale-payload replay as a universal repair.

Any actual printing/collection confirmation, shipment or invoice replay, WorkPlan/WorkStep
change, estimate change or recovery registration needs a concrete customer-approved
operation, permitted targets/fields, native access, audit, failure rollback and proven
business idempotency/postcondition. The curated corpus authorizes none of those writes.
