import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm, symlink, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { createKnowledgeStore, KNOWLEDGE_LIMITS } from '../knowledge.mjs';
import { createHandler } from '../server.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
function document(customer = 'global', id = 'diagnostic-process') {
    return { schemaVersion: 1, id, title: 'Diagnostic recovery process', customer, product: 'aegis-flow',
        processes: ['diagnostics', 'recovery'], summary: 'Curated diagnostic and recovery evidence.',
        lastReviewed: '2026-11-03', orgVerification: 'not-checked',
        claims: [{ id: 'governed-recovery', text: `${customer} diagnosis requires authorized evidence. Recovery requires separate confirmation.`,
            state: 'implemented-local', sourceIds: ['source-one'], limitations: ['Current org parity has not been checked.'] }],
        sources: [{ id: 'source-one', repository: customer === 'global' ? 'aegis-flow' : customer,
            path: 'docs/provenance-only-source.md', sha256: 'a'.repeat(64), lines: { start: 2, end: 12 } }] };
}
async function fixture(t, docs = [document(), document('abc'), document('socal')]) {
    const root = await mkdtemp(join(tmpdir(), 'aegis-knowledge-test-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const files = [];
    for (let index = 0; index < docs.length; index++) {
        const file = `document-${index}.json`;
        files.push(file);
        await writeFile(join(root, file), JSON.stringify(docs[index]));
    }
    await writeFile(join(root, 'catalog.json'), JSON.stringify({ schemaVersion: 1, files }));
    return { root, files, store: options => createKnowledgeStore({ root, customers: [], ...options }) };
}
const request = (method, params = {}, id = 2) => ({ jsonrpc: '2.0', id, method, params });
const tool = (name, args) => request('tools/call', { name, arguments: args });
async function initialized(handler) {
    const hello = await handler(request('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '1' } }, 1));
    await handler({ jsonrpc: '2.0', method: 'notifications/initialized' });
    return hello;
}
const resultText = result => JSON.parse(result.result.content[0].text);

test('global-only default applies to list, read, get and search without revealing other customers', async t => {
    const { store } = await fixture(t);
    const knowledge = store();
    const listing = await knowledge.list();
    assert.deepEqual(listing.resources.map(resource => resource.uri), ['aegis-knowledge://global/diagnostic-process']);
    await assert.rejects(knowledge.get({ customer: 'abc', id: 'diagnostic-process' }), /not configured/);
    await assert.rejects(knowledge.search({ customer: 'socal', query: 'diagnosis' }), /not configured/);
    for (const uri of ['aegis-knowledge://abc/diagnostic-process', 'aegis-knowledge://abc/unknown']) {
        await assert.rejects(knowledge.read(uri), error => error.code === -32002 && error.message === 'Knowledge resource not found.');
    }
});

test('operator customer opt-in cannot be expanded by request arguments', async t => {
    const { store } = await fixture(t);
    const knowledge = store({ customers: ['abc'] });
    assert.deepEqual((await knowledge.list()).resources.map(resource => resource.name), ['abc/diagnostic-process', 'global/diagnostic-process']);
    const abc = await knowledge.search({ customer: 'abc', query: 'diagnosis', limit: 10 });
    assert.equal(abc.items.length, 1);
    assert.equal(abc.items[0].customer, 'abc');
    assert(!JSON.stringify(abc).includes('socal'));
    await assert.rejects(knowledge.get({ customer: 'socal', id: 'diagnostic-process' }), /not configured/);
    assert.throws(() => store({ customers: ['*'] }), /wildcards are unsupported/);
});

test('resource content includes exact document hash and reported source provenance without opening originals', async t => {
    const { root, files, store } = await fixture(t, [document()]);
    const knowledge = store();
    const resource = (await knowledge.list()).resources[0];
    const response = await knowledge.read(resource.uri);
    const body = JSON.parse(response.contents[0].text);
    const bytes = await readFile(join(root, files[0]));
    assert.equal(body.provenance.documentSha256, digest(bytes));
    assert.match(body.provenance.corpusSha256, /^[a-f0-9]{64}$/);
    assert.equal(body.sources[0].sha256, 'a'.repeat(64));
    assert.equal(body.provenance.sourceHashesVerifiedByServer, false);
    assert.equal(body.orgVerification, 'not-checked');
    assert.equal(resource.mimeType, 'application/json');
    assert.equal(resource.size, Buffer.byteLength(response.contents[0].text));
    assert.match(body.provenance.instructions, /not instructions or authorization/);
    assert.deepEqual((await knowledge.get({ customer: 'global', id: body.id })).claims, body.claims);
});

test('visible corpus revision changes when content changes but not for excluded customer content', async t => {
    const { root, files, store } = await fixture(t);
    const first = await store().get({ customer: 'global', id: 'diagnostic-process' });
    const privateDoc = document('abc'); privateDoc.summary = 'PRIVATE_SCOPE_ONLY_CHANGE';
    await writeFile(join(root, files[1]), JSON.stringify(privateDoc));
    const same = await store().get({ customer: 'global', id: 'diagnostic-process' });
    assert.equal(first.provenance.corpusSha256, same.provenance.corpusSha256);
    const publicDoc = document(); publicDoc.summary = 'Changed reviewed product evidence.';
    await writeFile(join(root, files[0]), JSON.stringify(publicDoc));
    const changed = await store().get({ customer: 'global', id: 'diagnostic-process' });
    assert.notEqual(first.provenance.documentSha256, changed.provenance.documentSha256);
    assert.notEqual(first.provenance.corpusSha256, changed.provenance.corpusSha256);
});

test('search is bounded, literal and scoped by product and process with claim provenance', async t => {
    const docs = [document('abc', 'shipping'), document('abc', 'checklists')];
    docs[1].product = 'field-service'; docs[1].processes = ['checklists'];
    const { store } = await fixture(t, docs);
    const knowledge = store({ customers: ['abc'] });
    const matches = await knowledge.search({ customer: 'abc', query: 'diagnosis recovery', product: 'aegis-flow', process: 'recovery', limit: 1 });
    assert.equal(matches.items.length, 1);
    assert.equal(matches.items[0].id, 'shipping');
    assert.equal(matches.items[0].matchedClaim.state, 'implemented-local');
    assert.equal(matches.items[0].sources[0].sha256, docs[0].sources[0].sha256);
    assert.equal((await knowledge.search({ customer: 'abc', query: 'diagnosis', process: 'unknown' })).items.length, 0);
    assert.equal((await knowledge.search({ customer: 'abc', query: 'diagnosis', product: 'field-service' })).items[0].id, 'checklists');
    assert.equal((await knowledge.search({ customer: 'abc', query: 'PRIVATE_QUERY_SHOULD_NOT_ECHO' })).items.length, 0);
    assert(!JSON.stringify(await knowledge.search({ customer: 'abc', query: 'PRIVATE_QUERY_SHOULD_NOT_ECHO' })).includes('PRIVATE_QUERY'));
    for (const args of [{ limit: 11 }, { limit: '5' }, { query: 'x'.repeat(201) }, { query: '.*' }, { product: '../private' }]) {
        await assert.rejects(knowledge.search({ customer: 'abc', query: 'diagnosis', ...args }));
    }
});

test('paged resources use bounded corpus-bound cursors', async t => {
    const docs = Array.from({ length: 28 }, (_, index) => document('global', `process-${index}`));
    const { store } = await fixture(t, docs);
    const knowledge = store();
    const first = await knowledge.list();
    assert.equal(first.resources.length, KNOWLEDGE_LIMITS.pageSize);
    const second = await knowledge.list({ cursor: first.nextCursor });
    assert.equal(second.resources.length, 3); assert.equal(second.nextCursor, undefined);
    assert.equal(new Set([...first.resources, ...second.resources].map(resource => resource.uri)).size, 28);
    for (const cursor of ['../catalog.json', 'x'.repeat(301), Buffer.from(JSON.stringify({ offset: -1, revision: 'a'.repeat(64) })).toString('base64url')]) {
        await assert.rejects(knowledge.list({ cursor }), /Invalid knowledge resource cursor/);
    }
});

test('search response byte budget includes provenance and explanatory metadata', async t => {
    const docs = Array.from({ length: 10 }, (_, index) => {
        const doc = document('abc', `large-process-${index}`);
        doc.summary = 'Reviewed diagnosis context. '.repeat(50);
        doc.sources = Array.from({ length: 10 }, (_, sourceIndex) => ({ ...doc.sources[0],
            id: `source-${sourceIndex}`, path: 'docs/' + 'reviewed-segment/'.repeat(22) + 'source.md' }));
        doc.claims[0].sourceIds = doc.sources.map(source => source.id);
        return doc;
    });
    const { store } = await fixture(t, docs);
    const result = await store({ customers: ['abc'] }).search({ customer: 'abc', query: 'diagnosis', limit: 10 });
    assert.equal(result.totalMatched, 10);
    assert(result.items.length > 0 && result.items.length < 10);
    assert.equal(result.truncated, true);
    assert(Buffer.byteLength(JSON.stringify(result)) <= KNOWLEDGE_LIMITS.searchBytes);
});

test('arbitrary URIs, traversal, encoded paths and cross-customer resources never read files', async t => {
    const { store } = await fixture(t);
    const knowledge = store();
    for (const uri of ['file:///etc/passwd', 'https://example.invalid/private', 'aegis-knowledge://global/../catalog.json',
        'aegis-knowledge://global/%2e%2e', 'aegis-knowledge://global/diagnostic-process?file=secret',
        'aegis-knowledge://global/diagnostic-process#private', 'aegis-knowledge://global/diagnostic-process/extra']) {
        await assert.rejects(knowledge.read(uri), error => error.code === -32002 && !error.message.includes(uri));
    }
});

test('catalog allowlist rejects traversal, absolute paths and duplicate entries', async t => {
    for (const files of [['../outside.json'], ['/tmp/private.json'], ['document-0.json', 'document-0.json'], ['catalog.json']]) {
        const fixtureValue = await fixture(t, [document()]);
        await writeFile(join(fixtureValue.root, 'catalog.json'), JSON.stringify({ schemaVersion: 1, files }));
        await assert.rejects(fixtureValue.store().list(), error => error.code === -32603 && !error.message.includes('outside'));
    }
});

test('symlinked corpus roots, catalogs and documents are rejected', async t => {
    const current = await fixture(t, [document()]);
    const outer = await mkdtemp(join(tmpdir(), 'aegis-knowledge-links-')); t.after(() => rm(outer, { recursive: true, force: true }));
    const rootLink = join(outer, 'linked-root'); await symlink(current.root, rootLink);
    await assert.rejects(createKnowledgeStore({ root: rootLink, customers: [] }).list(), error => error.code === -32603);
    await rm(join(current.root, current.files[0]));
    await writeFile(join(outer, 'private.json'), 'SYNTHETIC_PRIVATE_FILE_CONTENT');
    await symlink(join(outer, 'private.json'), join(current.root, current.files[0]));
    await assert.rejects(current.store().list(), error => error.code === -32603 && !error.message.includes('PRIVATE'));
    await rm(join(current.root, 'catalog.json'));
    await symlink(join(outer, 'private.json'), join(current.root, 'catalog.json'));
    await assert.rejects(current.store().list(), error => error.code === -32603);
});

test('oversized documents and malformed provenance fail closed without raw contents', async t => {
    const tooLarge = await fixture(t, [document()]);
    await writeFile(join(tooLarge.root, tooLarge.files[0]), 'SYNTHETIC_PRIVATE_BODY'.repeat(4000));
    await assert.rejects(tooLarge.store().list(), error => error.code === -32603 && !error.message.includes('PRIVATE'));
    for (const mutate of [doc => { doc.sources[0].path = '../unreviewed-file'; }, doc => { doc.sources[0].sha256 = 'bad'; },
        doc => { doc.sources[0].sha256 = ['a'.repeat(64)]; },
        doc => { doc.claims[0].sourceIds = ['missing']; }, doc => { doc.claims[0].state = 'verified-org'; },
        doc => { doc.orgVerification = 'verified'; }, doc => { doc.sources[0].lines.end = 1; },
        doc => { doc.lastReviewed = '2026-02-31'; }, doc => { doc.constructor = 'untrusted'; }]) {
        const doc = document(); mutate(doc); const value = await fixture(t, [doc]);
        await assert.rejects(value.store().list(), error => error.code === -32603);
    }
});

test('MCP knowledge tools and resources stay offline while Salesforce tools remain available', async t => {
    const { store } = await fixture(t);
    let apiCalls = 0;
    const handler = createHandler({ knowledge: store({ customers: ['abc'] }), allowWrites: false,
        callApi: async () => { apiCalls++; return { liveSalesforce: true }; } });
    const hello = await initialized(handler);
    assert.deepEqual(hello.result.capabilities.resources, { subscribe: false, listChanged: false });
    const listing = await handler(request('resources/list'));
    assert.equal(listing.result.resources.length, 2);
    assert.equal((await handler(request('resources/templates/list'))).result.resourceTemplates.length, 0);
    const read = await handler(request('resources/read', { uri: 'aegis-knowledge://abc/diagnostic-process' }));
    assert.equal(JSON.parse(read.result.contents[0].text).customer, 'abc');
    assert.equal(resultText(await handler(tool('search_knowledge', { customer: 'abc', query: 'diagnosis' }))).items.length, 1);
    assert.equal(resultText(await handler(tool('get_knowledge', { customer: 'abc', id: 'diagnostic-process' }))).customer, 'abc');
    assert.equal(apiCalls, 0);
    assert.equal(resultText(await handler(tool('get_capabilities', {}))).liveSalesforce, true);
    assert.equal(apiCalls, 1);
});

test('knowledge requests reject arbitrary intake, prototype keys and unauthorized scopes', async t => {
    const { store } = await fixture(t);
    let apiCalled = false;
    const handler = createHandler({ knowledge: store(), callApi: async () => { apiCalled = true; } });
    await initialized(handler);
    for (const extra of ['filename', 'path', 'root', 'content', 'token', '__proto__', 'constructor']) {
        const args = JSON.parse(`{"customer":"global","id":"diagnostic-process","${extra}":"SYNTHETIC_PRIVATE_VALUE"}`);
        const result = await handler(tool('get_knowledge', args));
        assert.equal(result.result.isError, true);
        assert(!JSON.stringify(result).includes('SYNTHETIC_PRIVATE_VALUE'));
    }
    assert.equal((await handler(tool('search_knowledge', { customer: 'abc', query: 'diagnosis' }))).result.isError, true);
    assert.equal((await handler(request('resources/list', { customer: 'abc' }))).error.code, -32602);
    assert.equal((await handler(request('resources/read', { uri: 'file:///private' }))).error.code, -32002);
    assert.equal((await handler(request('resources/read', { uri: 'aegis-knowledge://global/diagnostic-process', path: '/private' }))).error.code, -32602);
    assert.equal(apiCalled, false);
});

test('bundled corpus answers native stdio requests with no Salesforce or AI credentials', async t => {
    const child = spawn(process.execPath, [fileURLToPath(new URL('../server.mjs', import.meta.url))], {
        cwd: tmpdir(), env: { PATH: process.env.PATH, AEGIS_KNOWLEDGE_CUSTOMERS: 'abc', AEGIS_ALLOW_WRITES: 'false' }, stdio: ['pipe', 'pipe', 'pipe']
    });
    t.after(() => { if (child.exitCode === null) child.kill(); });
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; }); child.stderr.on('data', chunk => { stderr += chunk; });
    const closed = new Promise((resolve, reject) => {
        const timeout = setTimeout(() => { child.kill(); reject(new Error('Offline stdio did not finish.')); }, 5000);
        child.once('error', reject);
        child.once('close', code => { clearTimeout(timeout); resolve(code); });
    });
    const messages = [request('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'offline-test', version: '1' } }, 1),
        { jsonrpc: '2.0', method: 'notifications/initialized' }, request('resources/list', {}, 2),
        { ...tool('search_knowledge', { customer: 'abc', query: 'shipment' }), id: 3 },
        request('resources/read', { uri: 'aegis-knowledge://abc/abc-pick-pack-ship' }, 4),
        { ...tool('get_capabilities', {}), id: 5 }];
    child.stdin.end(messages.map(message => JSON.stringify(message)).join('\n') + '\n');
    assert.equal(await closed, 0); assert.equal(stderr, '');
    const responses = stdout.trim().split('\n').map(line => JSON.parse(line));
    assert.equal(responses.length, 5);
    assert(responses.every(response => response.jsonrpc === '2.0'));
    assert.equal(responses[1].result.resources.some(resource => resource.uri.includes('socal')), false);
    assert.equal(resultText(responses[2]).items[0].customer, 'abc');
    assert.equal(JSON.parse(responses[3].result.contents[0].text).orgVerification, 'not-checked');
    assert.equal(responses[4].result.isError, true, 'Missing Salesforce auth affects only live diagnostic tools.');
});
