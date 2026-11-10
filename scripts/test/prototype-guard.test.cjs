const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const test = require('node:test');

// Exercise the exact dependency resolved by Jest's configuration loader.
const jestRequire = createRequire(require.resolve('jest-config'));
const merge = jestRequire('deepmerge');
const maliciousObject = () => JSON.parse('{"__proto__":{"aegisPrototypeProbe":true}}');

function assertSafe(operation) {
    const result = operation();
    assert.equal(Object.getPrototypeOf(result), Object.prototype);
    assert.equal(result.aegisPrototypeProbe, undefined);
    assert.equal(Object.hasOwn(result, '__proto__'), false);
    assert.equal(Object.hasOwn(Object.prototype, 'aegisPrototypeProbe'), false);
    assert.equal(({}).aegisPrototypeProbe, undefined);
}

test('patched merger discards a malicious source with a null-prototype target', () => {
    assertSafe(() => merge(Object.create(null), maliciousObject()));
});

test('patched merger discards a target own __proto__ key before reading it', () => {
    assertSafe(() => merge(maliciousObject(), {}));
});

test('patched merger blocks nested prototype poisoning over a null placeholder', () => {
    assertSafe(() => merge({ session: null }, { session: maliciousObject() }).session);
});

test('patched merger preserves ordinary nested merging, array merging, and input isolation', () => {
    const target = { nested: { first: 1 }, values: [1] };
    const source = { nested: { second: 2 }, values: [2] };
    const result = merge(target, source);
    assert.deepEqual(result, { nested: { first: 1, second: 2 }, values: [1, 2] });
    assert.deepEqual(target, { nested: { first: 1 }, values: [1] });
    assert.deepEqual(source, { nested: { second: 2 }, values: [2] });
    assert.notEqual(result.nested, target.nested);
    assert.notEqual(result.nested, source.nested);
    assert.notEqual(result.values, target.values);
    assert.notEqual(result.values, source.values);
    assert.equal(Object.getPrototypeOf(result), Object.prototype);
    assert.equal(Object.getPrototypeOf(result.nested), Object.prototype);
});


test('the actual Jest merger is the explicit security fork and works without the Node guard', () => {
    const { execFileSync } = require('node:child_process');
    const manifest = jestRequire('deepmerge/package.json');
    assert.equal(manifest.name, '@aegis-flow/safe-deepmerge');
    const env = { ...process.env }; delete env.NODE_OPTIONS;
    const script = `const assert = require('node:assert/strict'); const merge = require(process.argv[1]);
const bad = () => JSON.parse('{"__proto__":{"aegisPrototypeProbe":true}}');
for (const result of [merge(Object.create(null), bad()), merge(bad(), {}), merge({session:null},{session:bad()}).session]) {
assert.equal(Object.getPrototypeOf(result), Object.prototype); assert.equal(result.aegisPrototypeProbe, undefined);
assert.equal(Object.hasOwn(result,'__proto__'), false); }
assert.equal(({}).aegisPrototypeProbe, undefined);`;
    execFileSync(process.execPath, ['-e', script, jestRequire.resolve('deepmerge')], { env, stdio: 'pipe' });
});
