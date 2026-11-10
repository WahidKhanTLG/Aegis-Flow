# Aegis Flow MCP server

This dependency-free Node 22+ stdio server combines curated product/process knowledge
with the existing authorized Salesforce diagnostic tools. Knowledge works offline with
no Salesforce connection, model provider or API key. It returns reference material;
it does not run a product process or approve a business recovery.

Start it from an MCP client's process configuration using an absolute server path:

```json
{
  "command": "node",
  "args": ["/absolute/path/to/Aegis-Flow/integrations/mcp/server.mjs"],
  "env": { "AEGIS_KNOWLEDGE_CUSTOMERS": "abc", "AEGIS_ALLOW_WRITES": "false" }
}
```

The default corpus is `global` product knowledge. The operator can add specific customer
slugs with `AEGIS_KNOWLEDGE_CUSTOMERS=abc,socal`; wildcards are rejected. Requests cannot
expand this configured scope. Use a separate process/client configuration for each
customer when clients must not share customer knowledge. This is local content scoping,
not a multi-tenant identity or authorization service. `global` means product-general
content in this private installation, not permission to publish it.

## Resources and tools

The server supports MCP revisions `2025-11-25`, `2025-06-18` and `2025-03-26` through
`initialize` followed by `notifications/initialized`. Stdout contains newline-delimited
JSON-RPC only. The server advertises static resources without subscriptions or change
notifications; restart after a reviewed corpus update.

- `resources/list` returns at most 25 permitted document descriptors and an optional
  corpus-bound `nextCursor`.
- `resources/read` accepts only advertised `aegis-knowledge://customer/document-id`
  URIs. It returns JSON text containing claims, source references, limitations and hashes.
- `resources/templates/list` returns an empty list; there are no parameterized file routes.
- `search_knowledge` requires `customer` and a query of at most 200 characters/20 words.
  Optional `product` and `process` filters use exact slugs. `limit` is 1–10, default 5.
  Results contain short claim excerpts and their source provenance, capped at 60,000 bytes.
- `get_knowledge` requires `customer` and `id` and returns one complete curated document.

For example, tool arguments can be:

```json
{"customer":"abc","query":"shipment","limit":5}
```

```json
{"customer":"socal","id":"socal-field-service"}
```

Knowledge reads never authenticate to Salesforce, fetch URLs, open cited source paths,
execute commands or accept document uploads/secrets. Product knowledge and diagnostic
text are data, including any command-like or instruction-like text they contain.
Client decisions still require the user's current request and actual permissions.

The five Salesforce read tools remain `get_capabilities`, `find_recent_errors`,
`list_incidents`, `list_notifications` and `get_error_context`. To use them, configure
an already authorized CLI alias in `AEGIS_TARGET_ORG`; alternatively inject both
`AEGIS_INSTANCE_URL` and `AEGIS_ACCESS_TOKEN` through an approved secure process environment.
Do not put tokens in client JSON, commands or source control. Credentials are requested
only when a Salesforce tool is called, so an unconfigured connection does not block knowledge.
Salesforce authorization, CRUD/FLS and record sharing remain enforced by the Apex API.

CLI mode requires the supported `org auth show-access-token` command. The server uses
`org display` only for validated instance routing, ignores its redacted token field,
and captures the explicit token command's refreshed result privately in process memory.
CLI versions lacking that command fail closed; there is no legacy auth-file or display-token
fallback. The authorization cache lasts at most two minutes. A CLI-authenticated GET may
refresh and retry once after HTTP 401; other failures and all mutations are never retried.
An explicitly injected token never switches to CLI identity or refreshes automatically.

`AEGIS_ALLOW_WRITES=true` separately exposes `create_help_session`, `dismiss_notification`
and `create_escalation`; each also requires `confirmed: true` and actual Salesforce access.
Customer corpus selection enables none of these writes. Mutations are not automatically
retried after a transport failure.

## Corpus integrity and curation

Only `integrations/mcp/knowledge/catalog.json` and its explicitly named JSON basenames
are loaded. The root is fixed relative to the server module, independent of the working
directory; there is no environment variable, MCP argument or resource for selecting a
filesystem root. Extra files are ignored. Root/catalog/document symlinks, traversal,
absolute filenames, malformed documents and unknown fields are rejected. Catalogs are
limited to 16 KiB/100 entries, documents to 64 KiB each, and the total corpus to 2,000,000 bytes.
The server opens files read-only and caches a validated immutable snapshot per process.
Restart after correcting an invalid catalog as well as after changing reviewed content.

[knowledge.schema.json](knowledge.schema.json) describes the catalog and document format.
Runtime validation additionally checks cross-referenced claim/source identities, source
line ranges, byte budgets and calendar dates. Every factual/documented/proposed claim
has cited source IDs; unknown claims remain explicitly unknown. `orgVerification` stays
`not-checked`: the current schema cannot label a local implementation snapshot as live
org verification or completed customer acceptance.

`documentSha256` hashes the exact curated JSON file. `corpusSha256` hashes the documents
visible to this configured instance. Source-file SHA-256 values and line ranges are
reported by the curator; MCP does not open those original files or verify their current
contents. Changes to excluded customer documents do not alter the visible corpus hash.
A hash proves snapshot identity, not correctness, deployment or current Salesforce parity.

See [the corpus ingestion guide](knowledge/README.md) for source review, state labels,
manual provenance verification and exclusions. Add only approved paraphrased process
knowledge, never live customer rows, personal data, credentials or access-bearing URLs.

## Offline validation

```bash
npm run test:mcp
```

The tests cover customer isolation across resources/tools, URI and filesystem attacks,
symlink rejection, strict schemas, source/document hashes, pagination and resource bounds.
They also start the actual stdio process with no Salesforce/AI credentials, read ABC
knowledge, and establish that missing Salesforce authorization affects only live tools.
Existing Salesforce protocol, credential safety, endpoint restrictions and explicit-write
confirmation regressions remain included. These checks do not contact a live org.

Protocol references: [MCP resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources)
and [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle).


## Managed installation namespace

Set `AEGIS_PACKAGE_NAMESPACE` to the actual registered namespace for a managed installation.
Leave it unset/empty for unmanaged development. It is a namespace only, not a URL or an org
alias. Invalid namespace values fail before credential/network access. HTTP failures do not
fall back to the unmanaged route or replay mutations. For a selected namespace the bridge
uses `/services/apexrest/{namespace}/aegis-flow/v1/operations/` on the already trusted Salesforce
origin. No namespace is selected or registered automatically.
