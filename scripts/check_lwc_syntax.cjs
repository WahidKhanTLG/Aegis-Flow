const fs = require('node:fs');
const path = require('node:path');
const { transformSync, version } = require('@lwc/compiler');

const root = path.resolve(__dirname, '..');
const bundlesRoot = path.join(root, 'force-app/main/default/lwc');
const errors = [];
const warnings = [];
let bundles = 0;
let filesParsed = 0;

for (const entry of fs.readdirSync(bundlesRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const directory = path.join(bundlesRoot, entry.name);
    const metadata = path.join(directory, `${entry.name}.js-meta.xml`);
    if (!fs.existsSync(metadata)) {
        errors.push({ file: path.relative(root, directory), message: 'LWC bundle metadata is missing.' });
        continue;
    }
    const apiMatch = fs.readFileSync(metadata, 'utf8').match(/<apiVersion>([\d.]+)<\/apiVersion>/);
    if (!apiMatch) {
        errors.push({ file: path.relative(root, metadata), message: 'LWC API version is missing.' });
        continue;
    }
    bundles++;
    for (const name of fs.readdirSync(directory).sort()) {
        if (!/\.(js|html|css)$/.test(name)) continue;
        const file = path.join(directory, name);
        const relative = path.relative(root, file);
        filesParsed++;
        try {
            const result = transformSync(fs.readFileSync(file, 'utf8'), relative, {
                name: entry.name,
                namespace: 'c',
                apiVersion: Number(apiMatch[1]),
                enableLightningWebSecurityTransforms: true
            });
            for (const warning of result.warnings || []) {
                warnings.push({ file: relative, code: warning.code, message: warning.message });
            }
        } catch (error) {
            errors.push({ file: relative, message: error.message });
        }
    }
}

if (bundles === 0 || filesParsed === 0) {
    errors.push({ message: 'No LWC source was checked.' });
}
process.stdout.write(JSON.stringify({ compiler: version, bundles, filesParsed, warnings, errors }, null, 2) + '\n');
process.exitCode = errors.length ? 1 : 0;
