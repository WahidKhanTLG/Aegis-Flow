const { createRequire } = require('node:module');
const path = require('node:path');
const lintRequire = createRequire(path.join(__dirname, 'tools/lint/package.json'));
const js = lintRequire('@eslint/js');
const lwcBase = require('./tools/lint/lwc-base.cjs');
const lightning = lintRequire('@salesforce/eslint-plugin-lightning');
const globals = require('globals');

const lwcFiles = ['force-app/main/default/lwc/**/*.js'];

module.exports = [
    {
        ignores: ['node_modules/**', 'coverage/**', 'output/**', 'qa/**', 'tools/vendor/**', '.sf/**', '.sfdx/**']
    },
    {
        files: ['**/*.{js,cjs,mjs}'],
        rules: {
            ...js.configs.recommended.rules,
            'no-eval': 'error',
            'no-implied-eval': 'error',
            'no-new-func': 'error',
            // Callback signatures and intentionally unused catch bindings are contracts.
            'no-unused-vars': ['error', { args: 'none', caughtErrors: 'none' }]
        },
        languageOptions: { ecmaVersion: 2022 }
    },
    // Jest wire mocks are functions, so platform wire/decorator rules are production-only.
    ...lwcBase.map(config => ({ ...config, files: lwcFiles, ignores: ['**/__tests__/**'] })),
    {
        files: lwcFiles,
        ignores: ['**/__tests__/**'],
        plugins: { '@salesforce/lightning': lightning },
        rules: {
            '@lwc/lwc/no-api-reassignments': 'error',
            '@lwc/lwc/no-attributes-during-construction': 'error',
            '@lwc/lwc/no-document-query': 'error',
            '@lwc/lwc/no-inner-html': 'error',
            '@salesforce/lightning/valid-apex-method-invocation': 'error'
        }
    },
    {
        files: ['integrations/**/*.mjs', 'scripts/**/*.cjs', 'tools/lint/**/*.cjs', '*.cjs', 'jest.config.js'],
        languageOptions: { globals: globals.node }
    },
    {
        files: ['**/*.cjs', 'jest.config.js'],
        languageOptions: { sourceType: 'commonjs' }
    },
    {
        files: ['**/__tests__/**/*.js', 'force-app/test/**/*.js'],
        languageOptions: { globals: { ...globals.browser, ...globals.node, ...globals.jest } }
    }
];
