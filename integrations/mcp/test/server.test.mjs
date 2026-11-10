import test from 'node:test';
import assert from 'node:assert/strict';
import { Readable, Writable } from 'node:stream';
import { createHandler, createSalesforceClient, serve, validateInstance, validatePackageNamespace } from '../server.mjs';

const initialize = async handler => {
    const result = await handler({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25' } });
    assert.equal(result.result.protocolVersion, '2025-11-25');
    await handler({ jsonrpc: '2.0', method: 'notifications/initialized' });
};
const call = (name, args = {}) => ({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name, arguments: args } });

test('read-only handshake exposes five diagnostic tools and two local knowledge tools', async () => {
    const handler = createHandler({ callApi: async () => ({}), allowWrites: false });
    assert.equal((await handler(call('get_capabilities'))).error.code, -32002);
    assert.equal((await handler({ jsonrpc: '2.0', id: 0, method: 'server/discover' })).error.code, -32601);
    await initialize(handler);
    const result = await handler({ jsonrpc: '2.0', id: 3, method: 'tools/list' });
    assert.equal(result.result.tools.length, 7);
    assert.deepEqual(result.result.tools.filter(tool => ['search_knowledge', 'get_knowledge'].includes(tool.name)).map(tool => tool.name),
        ['search_knowledge', 'get_knowledge']);
    assert(result.result.tools.every(tool => tool.annotations.readOnlyHint));
    assert.equal((await handler(call('create_escalation', { correlationId: 'ref', confirmed: true }))).error.code, -32602);
});

test('unknown protocol is counter-offered a supported legacy revision', async () => {
    const handler = createHandler();
    const result = await handler({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: 'unknown' } });
    assert.equal(result.result.protocolVersion, '2025-11-25');
    assert.equal(await handler({ jsonrpc: '2.0', method: 'notifications/initialized' }), null);
});

test('writes require server opt-in and explicit confirmation', async () => {
    const calls = [];
    const handler = createHandler({ allowWrites: true, callApi: async (...args) => { calls.push(args); return { success: true }; } });
    await initialize(handler);
    assert.equal((await handler(call('create_escalation', { correlationId: 'ref' }))).result.isError, true);
    assert.equal((await handler(call('create_escalation', { correlationId: 'ref', confirmed: false }))).result.isError, true);
    assert.equal(calls.length, 0);
    const result = await handler(call('create_escalation', { correlationId: 'ref', confirmed: true }));
    assert.equal(result.result.isError, undefined);
    assert.deepEqual(calls[0], ['POST', 'escalate', { correlationId: 'ref', confirmed: true }]);
});

test('argument contracts reject injections, excessive limits, malformed IDs and unknown properties', async () => {
    const calls = [];
    const handler = createHandler({ callApi: async (...args) => { calls.push(args); return {}; } });
    await initialize(handler);
    for (const args of [{ limit: 101 }, { limit: '25' }, { recordId: 'bad' }, { endpoint: 'https://attacker.invalid' }, { scope: 'all' }]) {
        assert.equal((await handler(call('find_recent_errors', args))).result.isError, true);
    }
    assert.equal(calls.length, 0);
    const result = await handler(call('find_recent_errors', { objectApiName: "Case' OR User__c != null", limit: 10 }));
    assert.equal(result.result.isError, undefined, 'Filter data stays a value; server SOQL binds enforce the query boundary.');
    assert.equal(calls[0][1], 'errors');
});

test('connection rejects non-Salesforce hosts, credentials in URLs and redirects', async () => {
    for (const url of ['http://example.my.salesforce.com', 'https://attacker.invalid', 'https://example.my.salesforce.com@attacker.invalid', 'https://example.my.salesforce.com/path', 'https://example.my.salesforce.com/?token=x']) {
        assert.throws(() => validateInstance(url));
    }
    assert.equal(validateInstance('https://example.my.salesforce.com'), 'https://example.my.salesforce.com');
    let captured;
    const client = createSalesforceClient({ env: { AEGIS_INSTANCE_URL: 'https://example.my.salesforce.com', AEGIS_ACCESS_TOKEN: 'SYNTHETIC_TOKEN' },
        fetchImpl: async (url, options) => { captured = { url, options }; return { ok: true, text: async () => '{"items":[]}' }; } });
    await client('GET', 'errors', { objectApiName: "Case' OR Id!=null", limit: 10 });
    assert.equal(captured.options.redirect, 'error');
    assert.equal(captured.url.searchParams.get('objectApiName'), "Case' OR Id!=null");
    assert.equal(captured.url.origin, 'https://example.my.salesforce.com');
    assert.equal(captured.options.headers.Authorization, 'Bearer SYNTHETIC_TOKEN');
});

test('CLI authorization stays off command arguments and MCP responses', async () => {
    let invocations = 0;
    const bearerHeaders = [];
    const client = createSalesforceClient({ env: { AEGIS_TARGET_ORG: 'customer-development' },
        execImpl: async (binary, args, options) => {
            invocations++;
            assert.equal(binary, 'sf');
            assert.equal(options.env.SF_DISABLE_LOG_FILE, 'true');
            assert(!JSON.stringify(args).includes('SYNTHETIC_SECRET'));
            if (args[1] === 'display') {
                assert.deepEqual(args, ['org', 'display', '--target-org', 'customer-development', '--json']);
                return { stdout: JSON.stringify({ status: 0, result: {
                    instanceUrl: 'https://example.my.salesforce.com', accessToken: 'REDACTED: use org auth show-access-token'
                } }) };
            }
            assert.deepEqual(args, ['org', 'auth', 'show-access-token', '--target-org', 'customer-development', '--json']);
            return { stdout: JSON.stringify({ status: 0, result: { accessToken: 'SYNTHETIC_SECRET' } }) };
        }, fetchImpl: async (url, options) => { bearerHeaders.push(options.headers.Authorization); return { ok: true, text: async () => '{"items":[]}' }; } });
    const handler = createHandler({ callApi: client });
    await initialize(handler);
    for (let i = 0; i < 2; i++) {
        const result = await handler(call('find_recent_errors'));
        assert(!JSON.stringify(result).includes('SYNTHETIC_SECRET'));
    }
    assert.equal(invocations, 2, 'Read routing and refreshed credentials once, then use the short-lived memory cache.');
    assert.deepEqual(bearerHeaders, ['Bearer SYNTHETIC_SECRET', 'Bearer SYNTHETIC_SECRET']);
});

test('HTTP and CLI errors never forward raw service credentials or response bodies', async () => {
    for (const status of [401, 403, 404, 429, 503]) {
        const client = createSalesforceClient({ env: { AEGIS_INSTANCE_URL: 'https://example.my.salesforce.com', AEGIS_ACCESS_TOKEN: 'SYNTHETIC_SECRET' },
            fetchImpl: async () => ({ ok: false, status, text: async () => 'SECRET_RESPONSE' }) });
        const handler = createHandler({ callApi: client });
        await initialize(handler);
        const result = await handler(call('get_capabilities'));
        assert.equal(result.result.isError, true);
        assert(JSON.stringify(result).includes(`HTTP ${status}`));
        assert(!JSON.stringify(result).includes('SECRET'));
    }
    const denied = createSalesforceClient({ env: { AEGIS_TARGET_ORG: 'customer' }, execImpl: async () => { throw new Error('TOKEN_SHOULD_NOT_LEAK'); } });
    await assert.rejects(denied('GET', 'errors', {}), error => !error.message.includes('TOKEN_SHOULD_NOT_LEAK'));
});

test('CLI GET refreshes once after 401 without exposing either token', async () => {
    let metadataReads = 0, tokenReads = 0, requests = 0;
    const client = createSalesforceClient({ env: { AEGIS_TARGET_ORG: 'customer-development' },
        execImpl: async (binary, args) => {
            assert.equal(binary, 'sf');
            if (args[1] === 'display') {
                metadataReads++;
                return { stdout: JSON.stringify({ status: 0, result: { instanceUrl: 'https://example.my.salesforce.com', accessToken: 'REDACTED' } }) };
            }
            tokenReads++;
            return { stdout: JSON.stringify({ status: 0, result: { accessToken: `SYNTHETIC_SECRET_${tokenReads}` } }) };
        }, fetchImpl: async (url, options) => {
            requests++;
            assert.equal(options.method, 'GET');
            assert.equal(url.searchParams.get('limit'), '3');
            assert.equal(options.headers.Authorization, `Bearer SYNTHETIC_SECRET_${requests}`);
            return requests === 1 ? { ok: false, status: 401, text: async () => 'PRIVATE_UNAUTHORIZED_RESPONSE' }
                : { ok: true, text: async () => '{"items":[]}' };
        } });
    const handler = createHandler({ callApi: client }); await initialize(handler);
    const result = await handler(call('find_recent_errors', { limit: 3 }));
    assert.equal(result.result.isError, undefined);
    assert.equal(requests, 2); assert.equal(metadataReads, 2); assert.equal(tokenReads, 2);
    assert(!JSON.stringify(result).includes('SECRET'));
    assert(!JSON.stringify(result).includes('PRIVATE'));
});

test('CLI GET auth refresh is bounded and never retries other failures', async () => {
    for (const status of [401, 403, 429, 503]) {
        let tokenReads = 0, requests = 0;
        const client = createSalesforceClient({ env: { AEGIS_TARGET_ORG: 'customer-development' },
            execImpl: async (binary, args) => ({ stdout: JSON.stringify({ status: 0, result: args[1] === 'display'
                ? { instanceUrl: 'https://example.my.salesforce.com', accessToken: 'REDACTED' }
                : { accessToken: `SYNTHETIC_SECRET_${++tokenReads}` } }) }),
            fetchImpl: async () => { requests++; return { ok: false, status, text: async () => 'PRIVATE_RESPONSE' }; } });
        await assert.rejects(client('GET', 'errors', {}), error => error.message.includes(`HTTP ${status}`) && !error.message.includes('PRIVATE'));
        assert.equal(requests, status === 401 ? 2 : 1);
        assert.equal(tokenReads, requests);
    }
});

test('CLI mutations and explicit environment tokens are never automatically replayed after 401', async () => {
    let cliRequests = 0, tokenReads = 0;
    const client = createSalesforceClient({ env: { AEGIS_TARGET_ORG: 'customer-development' },
        execImpl: async (binary, args) => ({ stdout: JSON.stringify({ status: 0, result: args[1] === 'display'
            ? { instanceUrl: 'https://example.my.salesforce.com' } : { accessToken: `SYNTHETIC_SECRET_${++tokenReads}` } }) }),
        fetchImpl: async () => { cliRequests++; return { ok: false, status: 401 }; } });
    await assert.rejects(client('POST', 'escalate', { correlationId: 'confirmed-request', confirmed: true }), /HTTP 401/);
    assert.equal(cliRequests, 1); assert.equal(tokenReads, 1);
    let explicitRequests = 0;
    const explicit = createSalesforceClient({ env: { AEGIS_INSTANCE_URL: 'https://example.my.salesforce.com', AEGIS_ACCESS_TOKEN: 'SYNTHETIC_SECRET' },
        execImpl: async () => { assert.fail('Explicit token mode must never fall back to CLI identity.'); },
        fetchImpl: async () => { explicitRequests++; return { ok: false, status: 401 }; } });
    await assert.rejects(explicit('GET', 'errors', {}), /HTTP 401/);
    assert.equal(explicitRequests, 1);
});

test('unsupported explicit token command and redacted token output fail closed before API access', async () => {
    for (const token of [undefined, 'REDACTED', '[redacted]', 'header\ninjection', 'hidden']) {
        let requests = 0;
        const client = createSalesforceClient({ env: { AEGIS_TARGET_ORG: 'customer-development' },
            execImpl: async (binary, args) => {
                if (args[1] === 'display') return { stdout: JSON.stringify({ status: 0, result: {
                    instanceUrl: 'https://example.my.salesforce.com', accessToken: 'DISPLAY_VALUE_MUST_NEVER_BE_USED'
                } }) };
                if (token === undefined) throw new Error('Unsupported command; SYNTHETIC_PRIVATE_STDERR');
                return { stdout: JSON.stringify({ status: 0, result: { accessToken: token } }) };
            }, fetchImpl: async () => { requests++; assert.fail('No invalid or display token may be sent as Bearer.'); } });
        await assert.rejects(client('GET', 'errors', {}), error => !error.message.includes('SYNTHETIC_PRIVATE'));
        assert.equal(requests, 0);
    }
});

test('confirmed tool metadata is removed from the API payload and mutations are not retried', async () => {
    let attempts = 0;
    const client = createSalesforceClient({ env: { AEGIS_INSTANCE_URL: 'https://example.my.salesforce.com', AEGIS_ACCESS_TOKEN: 'SYNTHETIC_TOKEN' },
        fetchImpl: async (url, options) => {
            attempts++;
            assert.deepEqual(JSON.parse(options.body), { correlationId: 'ref' });
            throw new Error('network details');
        } });
    await assert.rejects(client('POST', 'escalate', { correlationId: 'ref', confirmed: true }), /No automatic mutation retry/);
    assert.equal(attempts, 1);
});

test('malformed/oversized API responses are reported without their raw contents', async () => {
    for (const response of ['<html>private</html>', 'x'.repeat(1_000_001)]) {
        const client = createSalesforceClient({ env: { AEGIS_INSTANCE_URL: 'https://example.my.salesforce.com', AEGIS_ACCESS_TOKEN: 'SYNTHETIC_TOKEN' },
            fetchImpl: async () => ({ ok: true, text: async () => response }) });
        await assert.rejects(client('GET', 'errors', {}), error => !error.message.includes('private') && error.message.length < 200);
    }
});

test('stdio emits only JSON-RPC and recovers from malformed requests', async () => {
    let output = '';
    const sink = new Writable({ write(chunk, encoding, done) { output += chunk; done(); } });
    const input = Readable.from(['not-json\n', JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' }) + '\n']);
    await serve({ input, output: sink, handler: createHandler() });
    const messages = output.trim().split('\n').map(line => JSON.parse(line));
    assert.equal(messages[0].error.code, -32700);
    assert.equal(messages[1].id, 1);
    assert.deepEqual(messages[1].result, {});
});


test('prototype property names cannot bypass the strict tool schema', async () => {
    let called = false;
    const handler = createHandler({ callApi: async () => { called = true; return {}; } });
    await initialize(handler);
    for (const key of ['constructor', 'toString', '__proto__']) {
        const args = JSON.parse(`{ "${key}": "untrusted" }`);
        assert.equal((await handler(call('find_recent_errors', args))).result.isError, true);
    }
    assert.equal(called, false);
});

test('response-stream and unexpected adapter errors cannot leak private failure text', async () => {
    const client = createSalesforceClient({ env: { AEGIS_INSTANCE_URL: 'https://example.my.salesforce.com', AEGIS_ACCESS_TOKEN: 'SYNTHETIC_TOKEN' },
        fetchImpl: async () => ({ ok: true, text: async () => { throw new Error('SYNTHETIC_PRIVATE_READ_ERROR'); } }) });
    for (const callApi of [client, async () => { throw new Error('SYNTHETIC_PRIVATE_ADAPTER_ERROR'); }]) {
        const handler = createHandler({ callApi });
        await initialize(handler);
        const result = await handler(call('get_capabilities'));
        assert.equal(result.result.isError, true);
        assert(!JSON.stringify(result).includes('SYNTHETIC_PRIVATE'));
    }
});


test('managed and unmanaged API routes preserve origin, query values and mutation semantics', async () => {
    for (const namespace of ['', 'aegisflow', 'my_np']) {
        const calls = [];
        const client = createSalesforceClient({
            env: { AEGIS_INSTANCE_URL: 'https://example.my.salesforce.com', AEGIS_ACCESS_TOKEN: 'SYNTHETIC_TOKEN', AEGIS_PACKAGE_NAMESPACE: namespace },
            fetchImpl: async (url, options) => { calls.push({ url, options }); return { ok: true, text: async () => '{}' }; }
        });
        await client('GET', 'errors', { limit: 3, objectApiName: 'Account' });
        await client('POST', 'help', { description: 'Confirmed help', confirmed: true });
        const prefix = `/services/apexrest/${namespace ? namespace + '/' : ''}aegis-flow/v1/operations/`;
        assert.equal(calls[0].url.pathname, prefix + 'errors');
        assert.equal(calls[0].url.searchParams.get('limit'), '3');
        assert.equal(calls[0].url.origin, 'https://example.my.salesforce.com');
        assert.equal(calls[1].url.pathname, prefix + 'help');
        assert.deepEqual(JSON.parse(calls[1].options.body), { description: 'Confirmed help' });
        assert(calls.every(call => call.options.redirect === 'error'));
    }
});

test('invalid namespace configuration fails before credentials or network access', () => {
    for (const namespace of ['a/b', '../x', ' x', 'x ', 'x__y', '1start', 'abcdefghijklmnop', null, {}, 'x%2fy']) {
        assert.throws(() => createSalesforceClient({ env: { AEGIS_PACKAGE_NAMESPACE: namespace },
            execImpl: () => assert.fail('No credential lookup'), fetchImpl: () => assert.fail('No network call') }), /namespace/i);
    }
    assert.equal(validatePackageNamespace(), '');
    assert.equal(validatePackageNamespace('a'), 'a');
    assert.equal(validatePackageNamespace('abcdefghijklmno'), 'abcdefghijklmno');
});

test('a managed-route error never falls back to an unmanaged URL or replays a mutation', async () => {
    for (const status of [401, 404, 503]) {
        const paths = [];
        const client = createSalesforceClient({
            env: { AEGIS_INSTANCE_URL: 'https://example.my.salesforce.com', AEGIS_ACCESS_TOKEN: 'SYNTHETIC_TOKEN', AEGIS_PACKAGE_NAMESPACE: 'aegisflow' },
            fetchImpl: async url => { paths.push(url.pathname); return { ok: false, status }; }
        });
        await assert.rejects(client('POST', 'escalate', { correlationId: 'confirmed-request', confirmed: true }), new RegExp(`HTTP ${status}`));
        assert.deepEqual(paths, ['/services/apexrest/aegisflow/aegis-flow/v1/operations/escalate']);
    }
});
