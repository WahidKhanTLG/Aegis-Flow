const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const path = require('node:path');
const test = require('node:test');
const lintRequire = createRequire(path.resolve(__dirname, '../../tools/lint/package.json'));
const { ESLint } = lintRequire('eslint');

const root = path.resolve(__dirname, '../..');
const consumerModule = name => createRequire(lintRequire.resolve(`${name}/package.json`));

test('affected tool consumers resolve outside the published minimatch advisory range', () => {
    for (const consumer of ['@lwc/eslint-plugin-lwc', 'eslint']) {
        const { version } = consumerModule(consumer)('minimatch/package.json');
        const parts = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
        assert(parts, `${consumer}: review non-stable minimatch version ${version}`);
        const [, major, minor, patch] = parts.map(Number);
        const outsideAffectedRange = major < 7 || major > 11 ||
            (major === 11 && (minor > 0 || patch >= 1));
        assert(outsideAffectedRange,
            `${consumer}: minimatch ${version} is affected by GHSA-g3hv-75wg-m249`);
    }
});

test('maintained ESLint matcher preserves basename and directory boundaries', () => {
    const { Minimatch } = consumerModule('eslint')('minimatch');
    assert.equal(new Minimatch('*.js').match('record.js'), true);
    assert.equal(new Minimatch('*.js').match('source/record.js'), false);
});

test('LWC wire glob matching preserves namespace and adapter boundaries', () => {
    const { Minimatch } = consumerModule('@lwc/eslint-plugin-lwc')('minimatch');
    const cases = [
        ['lightning/**', 'lightning/uiRecordApi', true],
        ['lightning/**', 'unapproved/uiRecordApi', false],
        ['@salesforce/**', '@salesforce/apex/Example.read', true],
        ['@salesforce/**', '@salesforce-unapproved/apex/Example.read', false],
        ['commerce/*Api', 'commerce/cartApi', true],
        ['commerce/*Api', 'commerce/cartApi/internal', false],
        ['*Adapter', 'CartAdapter', true],
        ['*Adapter', 'createCart', false],
        ['experience/*Api', 'experience/siteApi', true],
        ['get*', 'getSite', true],
        ['get*', 'setSite', false]
    ];
    for (const [pattern, value, expected] of cases) {
        assert.equal(new Minimatch(pattern).match(value), expected, `${pattern}: ${value}`);
    }
});

test('current LWC lint globs preserve dot-file options and path boundaries', () => {
    const { minimatch } = consumerModule('@lwc/eslint-plugin-lwc')('minimatch');
    const cases = [
        ['.config.ts', '*.ts', true],
        ['source/.config.ts', 'source/*.ts', true],
        ['source/file.ts', '*.ts', false],
        ['source/deep/file.ts', 'source/*.ts', false],
        ['source/file.tsx', 'source/*.{ts,tsx}', true],
        ['source/file.js', 'source/*.{ts,tsx}', false]
    ];
    for (const [value, pattern, expected] of cases) {
        assert.equal(minimatch(value, pattern, { dot: true }), expected, `${pattern}: ${value}`);
    }
});

async function lintComponent(imports, body) {
    const eslint = new ESLint({ cwd: root, overrideConfigFile: path.join(root, 'eslint.config.cjs') });
    const code = `import { LightningElement, wire } from 'lwc';
${imports}
export default class DependencyProbe extends LightningElement { ${body} }`;
    const [result] = await eslint.lintText(code, {
        filePath: path.join(root, 'force-app/main/default/lwc/dependencyProbe/dependencyProbe.js')
    });
    return result.messages;
}

test('actual LWC lint rules accept configured Lightning and Apex wire adapters', async () => {
    const lightning = await lintComponent(
        "import { getRecord } from 'lightning/uiRecordApi';", '@wire(getRecord) record;');
    assert.deepEqual(lightning, []);
    const apex = await lintComponent(
        "import read from '@salesforce/apex/Example.read';", '@wire(read) record;');
    assert.deepEqual(apex, []);
});

test('actual LWC lint rules still reject unapproved adapters and imperative wire calls', async () => {
    const unknown = await lintComponent(
        "import unknownAdapter from 'unapproved/adapter';", '@wire(unknownAdapter) record;');
    assert(unknown.some(message => message.ruleId === '@lwc/lwc/no-unknown-wire-adapters'));
    const imperative = await lintComponent(
        "import { getRecord } from 'lightning/uiRecordApi';", '@wire(getRecord) record; read() { return getRecord(); }');
    assert(imperative.some(message => message.ruleId === '@lwc/lwc/no-unexpected-wire-adapter-usages'));
});


test('ported Salesforce safety rules retain API, DOM and Apex invocation rejection', async () => {
    for (const [imports, body, rule] of [
        ["import { api } from 'lwc';", '@api value; mutate() { this.value = 1; }', '@lwc/lwc/no-api-reassignments'],
        ['', 'renderedCallback() { this.template.innerHTML = "unsafe"; }', '@lwc/lwc/no-inner-html'],
        ["import save from '@salesforce/apex/Example.save';", 'invoke() { return save("positional"); }', '@salesforce/lightning/valid-apex-method-invocation']
    ]) {
        const messages = await lintComponent(imports, body);
        assert(messages.some(message => message.ruleId === rule), JSON.stringify(messages));
    }
});
